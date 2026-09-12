package profferworker

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"strings"

	"go.temporal.io/sdk/activity"
	"go.temporal.io/sdk/client"
	"go.temporal.io/sdk/worker"

	"github.com/Cursedpotential/probata/engine/acquisition"
	"github.com/Cursedpotential/probata/engine/activities"
	"github.com/Cursedpotential/probata/engine/normalize"
	platformpostgres "github.com/Cursedpotential/probata/engine/postgres"
	"github.com/Cursedpotential/probata/engine/proffer"
	"github.com/Cursedpotential/probata/engine/runtimeapi"
	"github.com/Cursedpotential/probata/engine/stagegraph"
	platformtemporal "github.com/Cursedpotential/probata/engine/temporal"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Registrations contains the bounded Activity groups that collectively
// implement all 26 Proffer stages. Filesystem and embedded observation bodies are
// separate values so extractor provenance cannot cross activity boundaries.
type Registrations struct {
	Lifecycle             activities.SourceLifecycleActivities
	FilesystemObservation activities.SourceObservationActivities
	InventoryObservation  activities.SourceObservationActivities
	EmbeddedObservation   activities.SourceObservationActivities
	N8N                   platformtemporal.N8NActivities
	Hash                  activities.HashActivities
	StructuredELT         activities.StructuredELTActivities
	HandlerSelection      HandlerSelectionActivities
	Raw                   activities.RawPipelineActivities
	Normalized            activities.NormalizedPipelineActivities
	Repair                activities.RepairActivities
	Preview               activities.PreviewProjectionActivity
}

// HandlerSelectionActivities is the production integration seam for the
// content-backed recommendation and actor-bound decision-validation stores.
// Their implementations belong with runtime persistence, not workflow
// orchestration. Both must be supplied together before new-version workflows
// are enabled in a deployed worker.
type HandlerSelectionActivities struct {
	Recommend func(context.Context, proffer.StageRequest) (proffer.HandlerRecommendationResult, error)
	Validate  func(context.Context, proffer.StageRequest) (proffer.HandlerSelectionValidationResult, error)
}

// RegisterAll installs the one workflow plus every exact stagegraph name on
// one worker. A partial worker must never poll this task queue.
func RegisterAll(registrar interface {
	activities.ActivityRegistrar
	RegisterWorkflow(interface{})
}, registrations Registrations) {
	registrar.RegisterWorkflow(proffer.ProfferWorkflow)
	activities.RegisterSourceLifecycleActivities(registrar, registrations.Lifecycle)
	activities.RegisterFilesystemMetadataActivity(registrar, registrations.FilesystemObservation)
	activities.RegisterHashActivities(registrar, registrations.Hash)
	activities.RegisterInventoryContainerActivity(registrar, registrations.InventoryObservation)
	activities.RegisterEmbeddedMetadataActivity(registrar, registrations.EmbeddedObservation)
	registrar.RegisterActivityWithOptions(registrations.N8N.SelectParser, activity.RegisterOptions{Name: string(stagegraph.SelectParser)})
	registrar.RegisterActivityWithOptions(registrations.N8N.ExecuteParser, activity.RegisterOptions{Name: string(stagegraph.ExecuteParser)})
	activities.RegisterStructuredELTActivities(registrar, registrations.StructuredELT)
	if registrations.HandlerSelection.Recommend != nil || registrations.HandlerSelection.Validate != nil {
		if registrations.HandlerSelection.Recommend == nil || registrations.HandlerSelection.Validate == nil {
			panic("proffer worker: handler recommendation and validation activities must be registered together")
		}
		registrar.RegisterActivityWithOptions(registrations.HandlerSelection.Recommend, activity.RegisterOptions{Name: proffer.RecommendHandlerActivityName})
		registrar.RegisterActivityWithOptions(registrations.HandlerSelection.Validate, activity.RegisterOptions{Name: proffer.ValidateHandlerSelectionActivityName})
	}
	activities.RegisterRawPipelineActivities(registrar, registrations.Raw)
	activities.RegisterNormalizedPipelineActivities(registrar, registrations.Normalized)
	activities.RegisterRepairActivities(registrar, registrations.Repair)
	activities.RegisterPreviewProjectionActivity(registrar, registrations.Preview)
}

// Run constructs concrete production adapters, verifies PostgreSQL and shared
// storage before polling, and serves the dedicated Proffer queue until shutdown.
func Run(ctx context.Context, cfg Config) error {
	if stringsTrim(cfg.TemporalTaskQueue) == "" {
		return errors.New("proffer worker: TEMPORAL_TASK_QUEUE is required")
	}
	if cfg.TemporalTaskQueue == legacyEvidenceTaskQueue {
		return errors.New("proffer worker: refusing legacy evidence-pipeline task queue")
	}
	if err := validateSharedPaths(cfg); err != nil {
		return err
	}
	if err := prepareSharedPaths(cfg); err != nil {
		return err
	}

	pool, err := pgxpool.New(ctx, cfg.DatabaseURL)
	if err != nil {
		return errors.New("proffer worker: configure platform database pool: invalid configuration")
	}
	defer pool.Close()
	if err := pool.Ping(ctx); err != nil {
		return errors.New("proffer worker: connect to platform database: unavailable")
	}
	if err := platformpostgres.ProbeProfferSchema(ctx, pool); err != nil {
		return err
	}

	registrations, err := buildRegistrations(pool, cfg)
	if err != nil {
		return err
	}
	temporalClient, err := client.Dial(client.Options{HostPort: cfg.TemporalHostPort, Namespace: cfg.TemporalNamespace})
	if err != nil {
		return fmt.Errorf("proffer worker: connect to Temporal: %w", err)
	}
	defer temporalClient.Close()

	temporalWorker := worker.New(temporalClient, cfg.TemporalTaskQueue, worker.Options{})
	RegisterAll(temporalWorker, registrations)
	if err := temporalWorker.Start(); err != nil {
		return fmt.Errorf("proffer worker: start Temporal worker: %w", err)
	}
	slog.Info("universal import worker started", "task_queue", cfg.TemporalTaskQueue, "namespace", cfg.TemporalNamespace, "activity_count", len(stagegraph.Stages))
	<-ctx.Done()
	temporalWorker.Stop()
	return nil
}

func buildRegistrations(pool *pgxpool.Pool, cfg Config) (Registrations, error) {
	openObject, err := runtimeapi.NewRetainedObjectOpener(pool)
	if err != nil {
		return Registrations{}, err
	}
	// The API boundary (runtimeapi/source_ref.go) admits only upload:// and
	// r2:// source refs, so a worker wired with the file:// resolver alone can
	// never resolve anything a caller is allowed to send: every run died in
	// retain_original_activity with "acquisition reference must be a file://
	// URI" (live rehearsal 2026-09-02, docs/reviews/2026-09-02-proffer-rehearsal-
	// acquisition-seam.md). acquisition.NewSchemeRouter is the seam that closes
	// this, and its own doc comment names exactly this wiring.
	//
	// file:// stays registered for internal callers that mint sealed refs
	// (acquisition/seal.go returns file:// URIs); it is not reachable from the
	// HTTP boundary.
	//
	// ~~r2:// is deliberately NOT registered yet: the Go worker has no R2
	// credential plumbing~~ CORRECTED 2026-09-05 (live rehearsal
	// req-rehearsal-20260905-r2-1788608263 died in retain_original_activity with
	// `no acquisition resolver registered for scheme "r2"`): the worker compose
	// has mounted /run/secrets/casebible-r2.json and set CASEBIBLE_R2_CONFIG_PATH
	// since 2026-08-29, and the API boundary admits r2:// refs, so r2:// is now
	// registered exactly as the tool gateway does it (cmd/tool-gateway/main.go
	// buildResolver), sealing into the same SOURCE_OBJECT_DIR. Cross-host source
	// bytes travel via object storage (D-132). Absent the config path, r2://
	// stays unregistered and fails closed as before.
	filesystemResolver, err := runtimeapi.NewFilesystemImmutableAcquisitionResolver(cfg.SourceObjectDir)
	if err != nil {
		return Registrations{}, err
	}
	uploadResolver, err := acquisition.NewUploadIngressResolver(cfg.SourceObjectDir)
	if err != nil {
		return Registrations{}, err
	}
	resolvers := map[string]platformpostgres.ImmutableAcquisitionResolver{
		"file":   filesystemResolver,
		"upload": uploadResolver,
	}
	if path := strings.TrimSpace(os.Getenv("CASEBIBLE_R2_CONFIG_PATH")); path != "" {
		r2cfg, err := acquisition.LoadObjectStorageConfigFile(path)
		if err != nil {
			return Registrations{}, fmt.Errorf("r2 acquisition config: %w", err)
		}
		r2Resolver, err := acquisition.NewCloudflareR2AcquisitionResolver(cfg.SourceObjectDir, r2cfg)
		if err != nil {
			return Registrations{}, err
		}
		resolvers["r2"] = r2Resolver
	}
	acquisitionResolver, err := acquisition.NewSchemeRouter(resolvers)
	if err != nil {
		return Registrations{}, err
	}
	lifecycleRepo, err := platformpostgres.NewSourceLifecycleRepository(pool, acquisitionResolver)
	if err != nil {
		return Registrations{}, err
	}
	manifestFactory, err := runtimeapi.NewFilesystemInventoryManifestFactory(cfg.InventoryManifestDir)
	if err != nil {
		return Registrations{}, err
	}
	observationRepo, err := platformpostgres.NewSourceObservationRepository(pool, manifestFactory)
	if err != nil {
		return Registrations{}, err
	}
	filesystemExtractor, err := runtimeapi.NewFilesystemMetadataExtractor(pool)
	if err != nil {
		return Registrations{}, err
	}
	embeddedExtractor, err := runtimeapi.NewEmbeddedMetadataExtractor(pool)
	if err != nil {
		return Registrations{}, err
	}
	hashRepo, err := platformpostgres.NewRepository(pool, openObject)
	if err != nil {
		return Registrations{}, err
	}
	structuredELTRepo, err := platformpostgres.NewStructuredELTRepository(pool)
	if err != nil {
		return Registrations{}, err
	}
	handlerSelectionStore, err := platformpostgres.NewHandlerSelectionStore(pool, openObject)
	if err != nil {
		return Registrations{}, err
	}
	parserBundleFactory, err := runtimeapi.NewFilesystemBundleFactory(pool, cfg.ParserBundleDir)
	if err != nil {
		return Registrations{}, err
	}
	parserStore, err := platformpostgres.NewParserStore(pool, parserBundleFactory)
	if err != nil {
		return Registrations{}, err
	}
	rawRepo, err := platformpostgres.NewRawPipelineRepository(pool, openObject)
	if err != nil {
		return Registrations{}, err
	}
	normalizedWriter, err := runtimeapi.NewFilesystemNormalizedBundleFactory(pool, cfg.NormalizedBundleDir)
	if err != nil {
		return Registrations{}, err
	}
	normalizedReader, err := runtimeapi.NewFilesystemNormalizedBundleReaderFactory(pool, openObject)
	if err != nil {
		return Registrations{}, err
	}
	normalizedRepo, err := platformpostgres.NewNormalizedPipelineRepository(pool, normalizedWriter, normalizedReader)
	if err != nil {
		return Registrations{}, err
	}
	repairStore, err := platformpostgres.NewRepairActivityStore(pool, []string{cfg.SourceObjectDir, cfg.ParserBundleDir, cfg.NormalizedBundleDir})
	if err != nil {
		return Registrations{}, err
	}
	// D-132: Activities reach tools ONLY through the gateway, addressing the
	// source by locator and authenticating with the mounted service token.
	toolsClient, err := runtimeapi.NewToolGatewayClient(cfg.PlatformToolsBaseURL, cfg.ToolGatewayServiceToken)
	if err != nil {
		return Registrations{}, err
	}
	previewStore, err := platformpostgres.NewProfferPreviewStore(pool, nil)
	if err != nil {
		return Registrations{}, err
	}
	n8nClient, err := platformtemporal.NewN8NClient(cfg.temporalConfig())
	if err != nil {
		return Registrations{}, err
	}
	return Registrations{
		Lifecycle:             activities.NewSourceLifecycleActivities(lifecycleRepo),
		FilesystemObservation: activities.NewSourceObservationActivities(filesystemExtractor, nil, observationRepo),
		InventoryObservation:  activities.NewSourceObservationActivities(nil, runtimeapi.NewNonContainerMemberEnumerator(), observationRepo),
		EmbeddedObservation:   activities.NewSourceObservationActivities(embeddedExtractor, nil, observationRepo),
		N8N:                   platformtemporal.N8NActivities{Client: n8nClient},
		Hash:                  activities.NewHashActivities(hashRepo),
		StructuredELT:         activities.NewStructuredELTActivities(structuredELTRepo, parserStore),
		HandlerSelection: HandlerSelectionActivities{
			Recommend: func(ctx context.Context, req proffer.StageRequest) (proffer.HandlerRecommendationResult, error) {
				attempt := activity.GetInfo(ctx).Attempt
				if attempt < 1 {
					attempt = 1
				}
				return handlerSelectionStore.RecommendHandler(ctx, req, attempt)
			},
			Validate: func(ctx context.Context, req proffer.StageRequest) (proffer.HandlerSelectionValidationResult, error) {
				attempt := activity.GetInfo(ctx).Attempt
				if attempt < 1 {
					attempt = 1
				}
				return handlerSelectionStore.ValidateHandlerSelection(ctx, req, attempt)
			},
		},
		Raw:        activities.NewRawPipelineActivities(rawRepo),
		Normalized: activities.NewNormalizedPipelineActivities(normalizedRepo, normalize.GenericMessageNormalizer{}),
		Repair:     activities.NewRepairActivities(toolsClient, repairStore),
		Preview:    activities.PreviewProjectionActivity{Store: previewStore},
	}, nil
}

func prepareSharedPaths(cfg Config) error {
	for name, path := range map[string]string{
		"SOURCE_OBJECT_DIR":      cfg.SourceObjectDir,
		"PARSER_BUNDLE_DIR":      cfg.ParserBundleDir,
		"NORMALIZED_BUNDLE_DIR":  cfg.NormalizedBundleDir,
		"INVENTORY_MANIFEST_DIR": cfg.InventoryManifestDir,
	} {
		if err := os.MkdirAll(path, 0o750); err != nil {
			return fmt.Errorf("proffer worker: create %s: %w", name, err)
		}
		info, err := os.Lstat(path)
		if err != nil {
			return fmt.Errorf("proffer worker: inspect %s: %w", name, err)
		}
		if !info.IsDir() || info.Mode()&os.ModeSymlink != 0 {
			return fmt.Errorf("proffer worker: %s must be a real directory", name)
		}
		resolved, err := filepath.EvalSymlinks(path)
		if err != nil || filepath.Clean(resolved) != filepath.Clean(path) {
			return fmt.Errorf("proffer worker: %s must not traverse a symlink or junction", name)
		}
	}
	return nil
}

func stringsTrim(value string) string {
	return strings.TrimSpace(value)
}
