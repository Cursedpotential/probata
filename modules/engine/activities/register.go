package activities

import (
	"context"

	"go.temporal.io/sdk/activity"

	"github.com/Cursedpotential/probata/engine/normalize"
	"github.com/Cursedpotential/probata/engine/parser"
	"github.com/Cursedpotential/probata/engine/stagegraph"
)

// ActivityRegistrar is the narrow Temporal worker registration seam used by
// RegisterHashActivities. worker.Worker satisfies it directly.
type ActivityRegistrar interface {
	RegisterActivityWithOptions(interface{}, activity.RegisterOptions)
}

// NewHashActivities binds production Temporal heartbeats to the hash bodies.
// Storage remains an injected PostgreSQL-backed HashRepository.
func NewHashActivities(repository HashRepository) HashActivities {
	return HashActivities{
		Repository: repository,
		Heartbeat: func(ctx context.Context, progress Progress) {
			activity.RecordHeartbeat(ctx, progress)
		},
		Attempt: func(ctx context.Context) int32 {
			return activity.GetInfo(ctx).Attempt
		},
	}
}

// NewParserActivities binds the persisted parser-selection/execution bodies
// to Temporal attempt numbers. Registry and Store remain explicit runtime
// dependencies so the UI and workflow history never become parser state.
func NewParserActivities(registry *parser.Registry, store ParserActivityStore, authorization HandlerExecutionAuthorizationStore) ParserActivities {
	return ParserActivities{
		Registry:      registry,
		Store:         store,
		Authorization: authorization,
		Attempt: func(ctx context.Context) int32 {
			return activity.GetInfo(ctx).Attempt
		},
	}
}

// NewSourceLifecycleActivities binds identity/retention persistence to the
// current Temporal attempt while keeping source bytes outside workflow state.
func NewSourceLifecycleActivities(store SourceLifecycleStore) SourceLifecycleActivities {
	return SourceLifecycleActivities{
		Store: store,
		Attempt: func(ctx context.Context) int32 {
			return activity.GetInfo(ctx).Attempt
		},
	}
}

// NewSourceObservationActivities binds metadata/inventory tools and durable
// persistence while keeping all source bytes and metadata payloads outside
// workflow history.
func NewSourceObservationActivities(
	extractor SourceMetadataExtractor,
	enumerator MemberEnumerator,
	repository SourceObservationRepository,
) SourceObservationActivities {
	return SourceObservationActivities{
		Extractor:  extractor,
		Enumerator: enumerator,
		Repository: repository,
		Attempt: func(ctx context.Context) int32 {
			return activity.GetInfo(ctx).Attempt
		},
		Heartbeat: func(ctx context.Context, progress Progress) {
			activity.RecordHeartbeat(ctx, progress)
		},
	}
}

// RegisterHashActivities registers each atomic body under the exact StageID
// invoked by ProfferWorkflow. Registering methods individually avoids
// Go method names silently becoming a second naming scheme.
// Context integrity fingerprints (R02) are registered under their new names.
// Custody hashes (R04) are registered separately when R04 is implemented.
func RegisterHashActivities(registrar ActivityRegistrar, activities HashActivities) {
	registrar.RegisterActivityWithOptions(activities.FingerprintSource, activity.RegisterOptions{Name: string(stagegraph.FingerprintSource)})
	registrar.RegisterActivityWithOptions(activities.FingerprintRawRecords, activity.RegisterOptions{Name: string(stagegraph.FingerprintRawRecords)})
	registrar.RegisterActivityWithOptions(activities.FingerprintRawGeneration, activity.RegisterOptions{Name: string(stagegraph.FingerprintRawGeneration)})
	// Replay aliases for workflows started before the context-fingerprint
	// vocabulary correction. Do not use these names for new schedules.
	registrar.RegisterActivityWithOptions(activities.LegacyHashSource, activity.RegisterOptions{Name: legacyHashSourceActivity})
	registrar.RegisterActivityWithOptions(activities.LegacyHashRawRecords, activity.RegisterOptions{Name: legacyHashRawRecordsActivity})
	registrar.RegisterActivityWithOptions(activities.LegacyHashRawGeneration, activity.RegisterOptions{Name: legacyHashRawGenerationActivity})
	registrar.RegisterActivityWithOptions(activities.HashNormalizedRecords, activity.RegisterOptions{Name: string(stagegraph.HashNormalizedRecords)})
	registrar.RegisterActivityWithOptions(activities.HashNormalizedGeneration, activity.RegisterOptions{Name: string(stagegraph.HashNormalizedGeneration)})
}

const (
	legacyHashSourceActivity        = "hash_source_activity"
	legacyHashRawRecordsActivity    = "hash_raw_records_activity"
	legacyHashRawGenerationActivity = "hash_raw_generation_activity"
)

// RegisterParserActivities preserves the stage graph as the only Activity
// naming authority and prevents Go method names from drifting into history.
func RegisterParserActivities(registrar ActivityRegistrar, activities ParserActivities) {
	registrar.RegisterActivityWithOptions(activities.SelectParser, activity.RegisterOptions{Name: string(stagegraph.SelectParser)})
	registrar.RegisterActivityWithOptions(activities.ExecuteParser, activity.RegisterOptions{Name: string(stagegraph.ExecuteParser)})
}

// RegisterSourceLifecycleActivities registers the two intake lifecycle
// boundaries under their exact stage graph identities.
func RegisterSourceLifecycleActivities(registrar ActivityRegistrar, activities SourceLifecycleActivities) {
	registrar.RegisterActivityWithOptions(activities.RegisterSource, activity.RegisterOptions{Name: string(stagegraph.RegisterSource)})
	registrar.RegisterActivityWithOptions(activities.RetainOriginal, activity.RegisterOptions{Name: string(stagegraph.RetainOriginal)})
}

func NewRepairActivities(client RepairToolClient, store RepairActivityStore) RepairActivities {
	return RepairActivities{Client: client, Store: store, Attempt: func(ctx context.Context) int32 {
		return activity.GetInfo(ctx).Attempt
	}}
}

func RegisterRepairActivities(registrar ActivityRegistrar, activities RepairActivities) {
	registrar.RegisterActivityWithOptions(activities.AssessSourceRepair, activity.RegisterOptions{Name: string(stagegraph.AssessSourceRepair)})
	registrar.RegisterActivityWithOptions(activities.ResolveSourceRepair, activity.RegisterOptions{Name: string(stagegraph.ResolveSourceRepair)})
}

func RegisterPreviewProjectionActivity(registrar ActivityRegistrar, projection PreviewProjectionActivity) {
	registrar.RegisterActivityWithOptions(projection.Publish, activity.RegisterOptions{Name: string(stagegraph.PublishPreview)})
}

// RegisterSourceObservationActivities registers the three observation-only
// boundaries; none of them parses or hashes source records.
func RegisterSourceObservationActivities(registrar ActivityRegistrar, activities SourceObservationActivities) {
	RegisterFilesystemMetadataActivity(registrar, activities)
	RegisterInventoryContainerActivity(registrar, activities)
	RegisterEmbeddedMetadataActivity(registrar, activities)
}

// RegisterFilesystemMetadataActivity registers only the filesystem metadata
// boundary. Production uses this split helper because filesystem and embedded
// metadata are intentionally backed by distinct extractor instances.
func RegisterFilesystemMetadataActivity(registrar ActivityRegistrar, activities SourceObservationActivities) {
	registrar.RegisterActivityWithOptions(activities.CaptureFilesystemMetadata, activity.RegisterOptions{Name: string(stagegraph.CaptureFilesystemMetadata)})
}

// RegisterInventoryContainerActivity registers only the structural inventory
// boundary so its enumerator cannot accidentally become a metadata extractor.
func RegisterInventoryContainerActivity(registrar ActivityRegistrar, activities SourceObservationActivities) {
	registrar.RegisterActivityWithOptions(activities.InventoryContainer, activity.RegisterOptions{Name: string(stagegraph.InventoryContainer)})
}

// RegisterEmbeddedMetadataActivity registers only the embedded metadata
// boundary, preserving its independent extractor/tool provenance.
func RegisterEmbeddedMetadataActivity(registrar ActivityRegistrar, activities SourceObservationActivities) {
	registrar.RegisterActivityWithOptions(activities.ExtractEmbeddedMetadata, activity.RegisterOptions{Name: string(stagegraph.ExtractEmbeddedMetadata)})
}

// NewRawPipelineActivities binds durable raw-generation persistence and
// reconciliation bodies to the current Temporal attempt.
func NewRawPipelineActivities(repository RawPipelineRepository) RawPipelineActivities {
	return RawPipelineActivities{
		Repository: repository,
		Heartbeat: func(ctx context.Context, progress Progress) {
			activity.RecordHeartbeat(ctx, progress)
		},
		Attempt: func(ctx context.Context) int32 {
			return activity.GetInfo(ctx).Attempt
		},
	}
}

// RegisterRawPipelineActivities registers the four raw-generation Activities
// under their exact stage graph identities.
func RegisterRawPipelineActivities(registrar ActivityRegistrar, activities RawPipelineActivities) {
	registrar.RegisterActivityWithOptions(activities.PersistRawGeneration, activity.RegisterOptions{Name: string(stagegraph.PersistRawGeneration)})
	registrar.RegisterActivityWithOptions(activities.ReconcileRecordAccounting, activity.RegisterOptions{Name: string(stagegraph.ReconcileRecordAccounting)})
	registrar.RegisterActivityWithOptions(activities.ReconcileByteCoverage, activity.RegisterOptions{Name: string(stagegraph.ReconcileByteCoverage)})
	registrar.RegisterActivityWithOptions(activities.VerifyRawCoverageAgainstSource, activity.RegisterOptions{Name: string(stagegraph.VerifyRawCoverageAgainstSource)})
}

// NewNormalizedPipelineActivities binds the transform, lineage, verification,
// sealing, and publication bodies to the current Temporal attempt. The
// normalizer remains an explicit dependency so parser and normalization
// responsibilities cannot collapse into one Activity.
func NewNormalizedPipelineActivities(
	store NormalizedPipelineStore,
	normalizer normalize.Adapter,
) NormalizedPipelineActivities {
	return NormalizedPipelineActivities{
		Store:      store,
		Normalizer: normalizer,
		Attempt: func(ctx context.Context) int32 {
			return activity.GetInfo(ctx).Attempt
		},
	}
}

// RegisterNormalizedPipelineActivities registers every normalized-side body
// under the exact stage graph identity used by ProfferWorkflow.
func RegisterNormalizedPipelineActivities(registrar ActivityRegistrar, activities NormalizedPipelineActivities) {
	registrar.RegisterActivityWithOptions(activities.NormalizeGeneration, activity.RegisterOptions{Name: string(stagegraph.NormalizeGeneration)})
	registrar.RegisterActivityWithOptions(activities.PersistNormalizedGeneration, activity.RegisterOptions{Name: string(stagegraph.PersistNormalizedGeneration)})
	registrar.RegisterActivityWithOptions(activities.PersistLineage, activity.RegisterOptions{Name: string(stagegraph.PersistLineage)})
	registrar.RegisterActivityWithOptions(activities.ValidateRawLineage, activity.RegisterOptions{Name: string(stagegraph.ValidateRawLineage)})
	registrar.RegisterActivityWithOptions(activities.VerifyNormalizedGeneration, activity.RegisterOptions{Name: string(stagegraph.VerifyNormalizedGeneration)})
	registrar.RegisterActivityWithOptions(activities.SealGeneration, activity.RegisterOptions{Name: string(stagegraph.SealGeneration)})
	registrar.RegisterActivityWithOptions(activities.PublishGeneration, activity.RegisterOptions{Name: string(stagegraph.PublishGeneration)})
}

// NewStructuredELTActivities binds the pg_duckdb row stream and the canonical
// parser bundle/receipt store to the current Temporal attempt. DuckDB replaces
// only ExecuteParser; PersistRawGeneration and all downstream gates are shared.
func NewStructuredELTActivities(rows StructuredELTRowRepository, store ParserActivityStore, authorization HandlerExecutionAuthorizationStore) StructuredELTActivities {
	return StructuredELTActivities{
		Rows:          rows,
		Store:         store,
		Authorization: authorization,
		Attempt: func(ctx context.Context) int32 {
			return activity.GetInfo(ctx).Attempt
		},
	}
}

// RegisterStructuredELTActivities registers the paired select/execute DuckDB
// implementation under distinct Temporal names. Proffer routes both names
// together for exact eligible formats, avoiding decoder registration
// collisions and false parser attribution.
func RegisterStructuredELTActivities(registrar ActivityRegistrar, activities StructuredELTActivities) {
	registrar.RegisterActivityWithOptions(activities.SelectStructuredELT, activity.RegisterOptions{Name: SelectStructuredELTActivityName})
	registrar.RegisterActivityWithOptions(activities.ExecuteStructuredELT, activity.RegisterOptions{Name: ExecuteStructuredELTActivityName})
}
