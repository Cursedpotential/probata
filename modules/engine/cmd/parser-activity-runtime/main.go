// Command parser-activity-runtime exposes the platform's atomic parser
// Activities to n8n Activity bodies while keeping source bytes and raw records
// out of HTTP responses and Temporal history.
package main

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/Cursedpotential/probata/engine/activities"
	sbvadapter "github.com/Cursedpotential/probata/engine/adapters/sbv"
	"github.com/Cursedpotential/probata/engine/parser"
	platformpostgres "github.com/Cursedpotential/probata/engine/postgres"
	"github.com/Cursedpotential/probata/engine/runtimeapi"
	"github.com/jackc/pgx/v5/pgxpool"
)

const (
	defaultAddress      = ":8090"
	defaultReadTimeout  = 30 * time.Second
	defaultWriteTimeout = 31 * time.Minute
	defaultIdleTimeout  = 60 * time.Second
	dependencyTimeout   = 3 * time.Second
	gracefulStopTimeout = 20 * time.Second
)

func main() {
	if err := run(); err != nil {
		slog.Error("parser Activity runtime stopped", "error", err)
		os.Exit(1)
	}
}

func run() error {
	databaseURL := firstEnvironment("PLATFORM_DATABASE_URL", "DATABASE_URL")
	if databaseURL == "" {
		return errors.New("PLATFORM_DATABASE_URL or DATABASE_URL is required")
	}
	token := strings.TrimSpace(os.Getenv("PARSER_ACTIVITY_TOKEN"))
	if token == "" {
		return errors.New("PARSER_ACTIVITY_TOKEN is required")
	}
	bundleDirectory := strings.TrimSpace(os.Getenv("PARSER_BUNDLE_DIR"))
	if bundleDirectory == "" {
		return errors.New("PARSER_BUNDLE_DIR is required")
	}
	artifactDirectory := strings.TrimSpace(os.Getenv("PARSER_ARTIFACT_DIR"))
	if artifactDirectory == "" {
		return errors.New("PARSER_ARTIFACT_DIR is required")
	}
	address := strings.TrimSpace(os.Getenv("PARSER_ACTIVITY_ADDR"))
	if address == "" {
		address = defaultAddress
	}

	startup, cancelStartup := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancelStartup()
	pool, err := pgxpool.New(startup, databaseURL)
	if err != nil {
		return errors.New("configure platform database pool: invalid configuration")
	}
	defer pool.Close()
	if err := pool.Ping(startup); err != nil {
		return errors.New("connect to platform database: unavailable")
	}
	if err := probeRuntimeSchema(startup, pool); err != nil {
		return err
	}

	objectOpener, err := runtimeapi.NewRetainedObjectOpener(pool)
	if err != nil {
		return err
	}
	bundleFactory, err := runtimeapi.NewFilesystemBundleFactory(pool, bundleDirectory)
	if err != nil {
		return err
	}
	parserStore, err := platformpostgres.NewParserStore(pool, bundleFactory)
	if err != nil {
		return err
	}
	artifactSink, err := sbvadapter.NewFilesystemArtifactSink(artifactDirectory, parserStore)
	if err != nil {
		return fmt.Errorf("configure governed SBV artifact sink: %w", err)
	}
	defer func() {
		if err := artifactSink.Close(); err != nil {
			slog.Error("release governed SBV artifact runtime lock", "error", err)
		}
	}()
	adapters, err := sbvadapter.NewAllWithArtifactSink(objectOpener, artifactSink)
	if err != nil {
		return fmt.Errorf("register SBV parser adapters: %w", err)
	}
	registry, err := parser.NewRegistry(adapters...)
	if err != nil {
		return fmt.Errorf("build parser capability registry: %w", err)
	}
	handlerAuthorization, err := platformpostgres.NewHandlerSelectionStore(pool, objectOpener)
	if err != nil {
		return fmt.Errorf("configure handler execution authorization: %w", err)
	}
	parserActivities := activities.ParserActivities{Registry: registry, Store: parserStore, Authorization: handlerAuthorization}
	handler, err := runtimeapi.NewParserActivityHandler(parserActivities, token)
	if err != nil {
		return err
	}
	capabilities := make([]parser.Capability, 0, len(adapters))
	for _, adapter := range adapters {
		capabilities = append(capabilities, adapter.Capability())
	}
	router, err := runtimeapi.NewRouter(handler, capabilities, func(parent context.Context) error {
		ctx, cancel := context.WithTimeout(parent, dependencyTimeout)
		defer cancel()
		return probeRuntimeSchema(ctx, pool)
	})
	if err != nil {
		return err
	}

	server := &http.Server{
		Addr: address, Handler: router,
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       defaultReadTimeout, WriteTimeout: defaultWriteTimeout,
		IdleTimeout: defaultIdleTimeout,
	}
	shutdownContext, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	serveErrors := make(chan error, 1)
	go func() {
		slog.Info("parser Activity runtime listening", "address", address, "parser_count", len(capabilities))
		serveErrors <- server.ListenAndServe()
	}()
	select {
	case err := <-serveErrors:
		if errors.Is(err, http.ErrServerClosed) {
			return nil
		}
		return err
	case <-shutdownContext.Done():
		stopContext, cancel := context.WithTimeout(context.Background(), gracefulStopTimeout)
		defer cancel()
		return server.Shutdown(stopContext)
	}
}

func probeRuntimeSchema(ctx context.Context, pool *pgxpool.Pool) error {
	const requiredRelationCount = 11
	var found int
	if err := pool.QueryRow(ctx, `
		SELECT count(*)
		FROM (VALUES
		    (to_regclass('context.retained_object')),
		    (to_regclass('context.source_version')),
		    (to_regclass('context.source_version_object')),
		    (to_regclass('context.activity_execution')),
		    (to_regclass('context.activity_receipt')),
		    (to_regclass('context.handler_selection_validation')),
		    (to_regclass('context.handler_recommendation')),
		    (to_regclass('context.handler_selection_decision')),
		    (to_regclass('context.handler_detected_format')),
		    (to_regclass('context.handler_content_signature')),
		    (to_regclass('context.handler_compatibility'))
		) AS required(relation)
		WHERE relation IS NOT NULL`).Scan(&found); err != nil {
		return errors.New("verify parser runtime database schema: unavailable")
	}
	if found != requiredRelationCount {
		return fmt.Errorf("verify parser runtime database schema: found %d of %d required relations", found, requiredRelationCount)
	}
	return nil
}

func firstEnvironment(names ...string) string {
	for _, name := range names {
		if value := strings.TrimSpace(os.Getenv(name)); value != "" {
			return value
		}
	}
	return ""
}
