// tool-gateway is the locator-addressed front end for the Python tool-runtime
// registry (D-132).
//
// It gets its OWN Tailscale identity via tsnet, so callers address the gateway
// by a stable tailnet name and which physical host it — or tool-runtime —
// happens to run on stops mattering. That is the durable fix for the defect
// found live on 2026-09-02: the Proffer worker (ovh-files) handed tool-runtime
// (then named platform-tools, on ovh-app) a worker-local filesystem path, and
// the runtime 404'd with the
// path as the response body because the file was not there.
//
// Source bytes cross hosts through the object store, never a shared disk
// (owner, 2026-09-02: "you can object store but use b2 / mount an object if you
// need to"). Only the short-lived materialized copy is local.
//
// Byline: Claude Code · Opus 5 · 2026-09-02.
package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"strings"
	"syscall"
	"time"

	"tailscale.com/tsnet"

	"github.com/Cursedpotential/probata/engine/acquisition"
	platformpostgres "github.com/Cursedpotential/probata/engine/postgres"
	"github.com/Cursedpotential/probata/engine/runtimeapi"
	"github.com/Cursedpotential/probata/engine/toolgateway"
)

func main() {
	if err := run(); err != nil {
		slog.Error("tool gateway failed to start", "error", err.Error())
		os.Exit(1)
	}
}

func env(name string) string { return strings.TrimSpace(os.Getenv(name)) }

func requireEnv(name string) (string, error) {
	if v := env(name); v != "" {
		return v, nil
	}
	return "", fmt.Errorf("%s is required", name)
}

func requireToolRuntimeURL() (string, error) {
	if value := env("TOOL_RUNTIME_BASE_URL"); value != "" {
		return value, nil
	}
	if value := env("PLATFORM_TOOLS_BASE_URL"); value != "" {
		slog.Warn("PLATFORM_TOOLS_BASE_URL is deprecated; use TOOL_RUNTIME_BASE_URL")
		return value, nil
	}
	return "", errors.New("TOOL_RUNTIME_BASE_URL is required")
}

// readSecretFile reads a mounted secret. The VALUE is never logged — only
// whether it was present and its length, per the platform's secret-handling
// rule.
func readSecretFile(path string) (string, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return "", fmt.Errorf("read secret file: %w", err)
	}
	return strings.TrimRight(string(raw), "\r\n"), nil
}

func run() error {
	runtimeBaseURL, err := requireToolRuntimeURL()
	if err != nil {
		return err
	}
	materializeDir, err := requireEnv("TOOL_GATEWAY_MATERIALIZE_DIR")
	if err != nil {
		return err
	}
	if !filepath.IsAbs(materializeDir) {
		return errors.New("TOOL_GATEWAY_MATERIALIZE_DIR must be an absolute path shared with tool-runtime")
	}

	runner, err := runtimeapi.NewToolRuntimeClient(runtimeBaseURL)
	if err != nil {
		return err
	}

	resolver, schemes, err := buildResolver()
	if err != nil {
		return err
	}

	handler := &toolgateway.HTTPHandler{
		Gateway: &toolgateway.Gateway{
			Runner:         runner,
			Resolve:        resolver,
			MaterializeDir: materializeDir,
		},
		Index: toolIndexFunc(runtimeBaseURL),
	}
	if path := env("TOOL_GATEWAY_SERVICE_TOKEN_FILE"); path != "" {
		token, err := readSecretFile(path)
		if err != nil {
			return err
		}
		if len(token) < 32 {
			return errors.New("tool gateway service token is too short to be credible")
		}
		handler.ServiceToken = token
		slog.Info("tool gateway service token loaded", "token_length", len(token))
	}

	listener, describe, cleanup, err := buildListener()
	if err != nil {
		return err
	}
	defer cleanup()
	// tsnet listeners (service or node) hand requests over loopback with the
	// tailnet peer in X-Forwarded-For; only then is that header trusted.
	handler.TrustForwardedFromLoopback = env("TOOL_GATEWAY_TS_AUTHKEY_FILE") != ""

	server := &http.Server{
		Handler:           handler.Routes(),
		ReadHeaderTimeout: 15 * time.Second,
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	go func() {
		<-ctx.Done()
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
		defer cancel()
		_ = server.Shutdown(shutdownCtx)
	}()

	slog.Info("tool gateway listening",
		"address", describe,
		"tool_runtime", runtimeBaseURL,
		"materialize_dir", materializeDir,
		"resolver_schemes", strings.Join(schemes, ","))

	if err := server.Serve(listener); err != nil && !errors.Is(err, http.ErrServerClosed) {
		return err
	}
	return nil
}

// buildResolver assembles the scheme router from whatever credentials are
// mounted. An unregistered scheme fails closed rather than silently falling
// back to some default provider.
func buildResolver() (platformpostgres.ImmutableAcquisitionResolver, []string, error) {
	sealRoot, err := requireEnv("TOOL_GATEWAY_SEAL_DIR")
	if err != nil {
		return nil, nil, fmt.Errorf("%w (the directory this gateway seals fetched objects into)", err)
	}
	resolvers := map[string]platformpostgres.ImmutableAcquisitionResolver{}
	var schemes []string

	// Local sealed objects, when the gateway shares a host with an object store.
	if dir := env("SOURCE_OBJECT_DIR"); dir != "" {
		fsResolver, err := runtimeapi.NewFilesystemImmutableAcquisitionResolver(dir)
		if err != nil {
			return nil, nil, err
		}
		uploadResolver, err := acquisition.NewUploadIngressResolver(dir)
		if err != nil {
			return nil, nil, err
		}
		resolvers["file"] = fsResolver
		resolvers["upload"] = uploadResolver
		schemes = append(schemes, "file", "upload")
	}

	// Cross-host source bytes travel via object storage.
	if path := env("CASEBIBLE_R2_CONFIG_PATH"); path != "" {
		cfg, err := acquisition.LoadObjectStorageConfigFile(path)
		if err != nil {
			return nil, nil, fmt.Errorf("r2: %w", err)
		}
		r2, err := acquisition.NewCloudflareR2AcquisitionResolver(sealRoot, cfg)
		if err != nil {
			return nil, nil, err
		}
		resolvers["r2"] = r2
		schemes = append(schemes, "r2")
	}
	if path := env("B2_CONFIG_PATH"); path != "" {
		cfg, err := acquisition.LoadObjectStorageConfigFile(path)
		if err != nil {
			return nil, nil, fmt.Errorf("b2: %w", err)
		}
		b2, err := acquisition.NewBackblazeB2AcquisitionResolver(sealRoot, cfg)
		if err != nil {
			return nil, nil, err
		}
		resolvers["b2"] = b2
		schemes = append(schemes, "b2")
	}

	if len(resolvers) == 0 {
		return nil, nil, errors.New("tool gateway: no acquisition resolvers configured — set SOURCE_OBJECT_DIR and/or CASEBIBLE_R2_CONFIG_PATH / B2_CONFIG_PATH")
	}
	router, err := acquisition.NewSchemeRouter(resolvers)
	if err != nil {
		return nil, nil, err
	}
	return router, schemes, nil
}

// buildListener gives the gateway its own Tailscale identity.
//
// PREFERRED: a Tailscale SERVICE (TOOL_GATEWAY_TS_SERVICE, e.g. "svc:tool-gateway").
// This matches the pattern already in use on this tailnet — the Workbench is
// advertised as svc:workbench — and yields a stable HTTPS FQDN owned by the
// service rather than by whichever host it happens to run on. Tailscale requires
// a TAG-BASED identity to advertise a service, so TOOL_GATEWAY_TS_TAGS must name
// at least one tag (the tailnet's existing nodes use tag:docker).
//
// Falling back, in order: a plain tsnet node listener, then TOOL_GATEWAY_BIND_IP
// for hosts not yet joined via tsnet. The HTTP layer enforces tailnet-only peers
// in every mode, so no fallback widens exposure.
func buildListener() (net.Listener, string, func(), error) {
	port := env("TOOL_GATEWAY_PORT")
	if port == "" {
		port = "8099"
	}

	keyPath := env("TOOL_GATEWAY_TS_AUTHKEY_FILE")
	if keyPath == "" {
		bindIP, err := requireEnv("TOOL_GATEWAY_BIND_IP")
		if err != nil {
			return nil, "", func() {}, fmt.Errorf("%w (or set TOOL_GATEWAY_TS_AUTHKEY_FILE for a tsnet identity)", err)
		}
		addr := net.JoinHostPort(bindIP, port)
		listener, err := net.Listen("tcp", addr)
		if err != nil {
			return nil, "", func() {}, err
		}
		return listener, addr, func() {}, nil
	}

	authKey, err := readSecretFile(keyPath)
	if err != nil {
		return nil, "", func() {}, err
	}
	if authKey == "" {
		return nil, "", func() {}, errors.New("TOOL_GATEWAY_TS_AUTHKEY_FILE is empty")
	}
	stateDir, err := requireEnv("TOOL_GATEWAY_TS_STATE_DIR")
	if err != nil {
		return nil, "", func() {}, err
	}
	if err := os.MkdirAll(stateDir, 0o700); err != nil {
		return nil, "", func() {}, fmt.Errorf("create tsnet state dir: %w", err)
	}
	hostname := env("TOOL_GATEWAY_TS_HOSTNAME")
	if hostname == "" {
		hostname = "tool-gateway"
	}

	srv := &tsnet.Server{
		Hostname: hostname,
		AuthKey:  authKey,
		Dir:      stateDir,
		Logf:     func(string, ...any) {},
	}
	if tags := env("TOOL_GATEWAY_TS_TAGS"); tags != "" {
		for _, tag := range strings.Split(tags, ",") {
			if trimmed := strings.TrimSpace(tag); trimmed != "" {
				srv.AdvertiseTags = append(srv.AdvertiseTags, trimmed)
			}
		}
	}

	// Start explicitly so a registration failure surfaces as a startup failure
	// rather than as a confusing listen failure. Without an auth key tsnet would
	// print an authentication URL here instead.
	if err := srv.Start(); err != nil {
		_ = srv.Close()
		return nil, "", func() {}, fmt.Errorf("tsnet start: %w", err)
	}

	if service := env("TOOL_GATEWAY_TS_SERVICE"); service != "" {
		if len(srv.AdvertiseTags) == 0 {
			_ = srv.Close()
			return nil, "", func() {}, errors.New("TOOL_GATEWAY_TS_SERVICE requires TOOL_GATEWAY_TS_TAGS: Tailscale Services need a tag-based identity")
		}
		listener, err := srv.ListenService(service, tsnet.ServiceModeHTTP{HTTPS: true, Port: 443})
		if err != nil {
			_ = srv.Close()
			return nil, "", func() {}, fmt.Errorf("tsnet listen service %q: %w", service, err)
		}
		return listener, "https://" + listener.FQDN + " (" + service + ")", func() { _ = srv.Close() }, nil
	}

	listener, err := srv.Listen("tcp", ":"+port)
	if err != nil {
		_ = srv.Close()
		return nil, "", func() {}, fmt.Errorf("tsnet listen: %w", err)
	}
	return listener, "tsnet:" + hostname + ":" + port, func() { _ = srv.Close() }, nil
}

// toolIndexFunc proxies the tool-runtime registry so callers discover tools
// on the same surface they invoke them on.
func toolIndexFunc(baseURL string) func() (json.RawMessage, error) {
	client := &http.Client{Timeout: 30 * time.Second}
	endpoint := strings.TrimRight(baseURL, "/") + "/tools"
	return func() (json.RawMessage, error) {
		resp, err := client.Get(endpoint)
		if err != nil {
			return nil, fmt.Errorf("tool gateway: list tools: %w", err)
		}
		defer resp.Body.Close()
		body, err := io.ReadAll(io.LimitReader(resp.Body, 4<<20))
		if err != nil {
			return nil, fmt.Errorf("tool gateway: read tool index: %w", err)
		}
		if resp.StatusCode != http.StatusOK {
			return nil, fmt.Errorf("tool gateway: tool-runtime index returned %d", resp.StatusCode)
		}
		return json.RawMessage(body), nil
	}
}
