package profferworker

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func setWorkerEnvironment(t *testing.T) {
	t.Helper()
	root := t.TempDir()
	authValueFile := filepath.Join(root, "n8n-auth-value")
	if err := os.WriteFile(authValueFile, []byte("Bearer secret-value\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	databaseURLFile := filepath.Join(root, "platform-database-url")
	if err := os.WriteFile(databaseURLFile, []byte("postgresql://runtime:secret@postgres/platform\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	gatewayTokenFile := filepath.Join(root, "tool-gateway-service-token")
	if err := os.WriteFile(gatewayTokenFile, []byte("gateway-token-value\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	values := map[string]string{
		"TEMPORAL_HOST_PORT":              "temporal:7233",
		"TEMPORAL_NAMESPACE":              "default",
		"TEMPORAL_TASK_QUEUE":             "proffer-v1",
		"PLATFORM_DATABASE_URL_FILE":      databaseURLFile,
		"SOURCE_OBJECT_DIR":               filepath.Join(root, "source"),
		"PARSER_BUNDLE_DIR":               filepath.Join(root, "parser"),
		"NORMALIZED_BUNDLE_DIR":           filepath.Join(root, "normalized"),
		"INVENTORY_MANIFEST_DIR":          filepath.Join(root, "inventory"),
		"PLATFORM_TOOLS_BASE_URL":         "https://platform-tools.example.test",
		"TOOL_GATEWAY_SERVICE_TOKEN_FILE": gatewayTokenFile,
		"N8N_PROFFER_BASE_URL":            "https://n8n.example.test/webhook/",
		"N8N_PROFFER_AUTH_HEADER":         "Authorization",
		"N8N_PROFFER_AUTH_VALUE_FILE":     authValueFile,
		"N8N_FLOW_BINDINGS_FILE":          "",
		"SELECT_PARSER_HTTP_TIMEOUT":      "",
		"EXECUTE_PARSER_HTTP_TIMEOUT":     "",
	}
	for name, value := range values {
		t.Setenv(name, value)
	}
}

func TestLoadConfigAcceptsAnOptionalAbsoluteFlowBindingsFile(t *testing.T) {
	setWorkerEnvironment(t)
	path := filepath.Join(t.TempDir(), "n8n-flow-bindings.json")
	t.Setenv("N8N_FLOW_BINDINGS_FILE", path)
	cfg, err := LoadConfig()
	if err != nil {
		t.Fatalf("LoadConfig() error = %v", err)
	}
	if cfg.N8NFlowBindingsFile != path {
		t.Fatalf("N8NFlowBindingsFile = %q, want %q", cfg.N8NFlowBindingsFile, path)
	}
}

func TestLoadConfigRejectsRelativeFlowBindingsFile(t *testing.T) {
	setWorkerEnvironment(t)
	t.Setenv("N8N_FLOW_BINDINGS_FILE", "config/n8n-flow-bindings.json")
	_, err := LoadConfig()
	if err == nil || !strings.Contains(err.Error(), "N8N_FLOW_BINDINGS_FILE must be an absolute path") {
		t.Fatalf("LoadConfig() error = %v, want absolute flow bindings path rejection", err)
	}
}

func TestLoadConfigBuildsDedicatedWorkerContract(t *testing.T) {
	setWorkerEnvironment(t)
	cfg, err := LoadConfig()
	if err != nil {
		t.Fatalf("LoadConfig() error = %v", err)
	}
	if cfg.TemporalTaskQueue != "proffer-v1" {
		t.Fatalf("task queue = %q", cfg.TemporalTaskQueue)
	}
	if strings.HasSuffix(cfg.N8NBaseURL, "/") {
		t.Fatalf("n8n base URL retained trailing slash: %q", cfg.N8NBaseURL)
	}
	if cfg.DatabaseURL != "postgresql://runtime:secret@postgres/platform" {
		t.Fatal("database URL was not loaded from its runtime file")
	}
	if err := validateSharedPaths(cfg); err != nil {
		t.Fatalf("validateSharedPaths() error = %v", err)
	}
}

func TestLoadConfigRejectsMissingDatabaseURLFileWithoutLeakingPath(t *testing.T) {
	setWorkerEnvironment(t)
	path := filepath.Join(t.TempDir(), "missing-secret")
	t.Setenv("PLATFORM_DATABASE_URL_FILE", path)
	_, err := LoadConfig()
	if err == nil || !strings.Contains(err.Error(), "PLATFORM_DATABASE_URL_FILE is unavailable or invalid") {
		t.Fatalf("LoadConfig() error = %v, want generic database secret error", err)
	}
	if strings.Contains(err.Error(), path) {
		t.Fatalf("LoadConfig() error leaked database secret path: %q", err)
	}
}

// D-132: the tool gateway is the only sanctioned path to a platform tool and
// requires a bearer service token. A worker that starts without it would poll
// the queue and 401 on every repair Activity, so the failure belongs at
// startup, not at call time.
func TestLoadConfigFailsClosedWithoutTheToolGatewayServiceToken(t *testing.T) {
	setWorkerEnvironment(t)
	path := filepath.Join(t.TempDir(), "missing-gateway-token")
	t.Setenv("TOOL_GATEWAY_SERVICE_TOKEN_FILE", path)
	_, err := LoadConfig()
	if err == nil || !strings.Contains(err.Error(), "TOOL_GATEWAY_SERVICE_TOKEN_FILE is unavailable or empty") {
		t.Fatalf("LoadConfig() error = %v, want fail-closed gateway token error", err)
	}
	if strings.Contains(err.Error(), path) {
		t.Fatalf("LoadConfig() error leaked the gateway secret path: %q", err)
	}
}

func TestLoadConfigRejectsLegacyEvidenceQueue(t *testing.T) {
	setWorkerEnvironment(t)
	t.Setenv("TEMPORAL_TASK_QUEUE", legacyEvidenceTaskQueue)
	_, err := LoadConfig()
	if err == nil || !strings.Contains(err.Error(), legacyEvidenceTaskQueue) {
		t.Fatalf("LoadConfig() error = %v, want legacy queue rejection", err)
	}
}

func TestLoadConfigNeverEchoesSecrets(t *testing.T) {
	setWorkerEnvironment(t)
	t.Setenv("TEMPORAL_HOST_PORT", "")
	_, err := LoadConfig()
	if err == nil {
		t.Fatal("LoadConfig() error = nil")
	}
	for _, secret := range []string{"secret-value", "gateway-token-value", "postgresql://runtime:secret@postgres/platform"} {
		if strings.Contains(err.Error(), secret) {
			t.Fatalf("configuration error exposed a secret: %q", err)
		}
	}
}

func TestValidateSharedPathsRejectsRelativeAndNestedRoots(t *testing.T) {
	setWorkerEnvironment(t)
	cfg, err := LoadConfig()
	if err != nil {
		t.Fatal(err)
	}
	cfg.ParserBundleDir = "relative/parser"
	if err := validateSharedPaths(cfg); err == nil {
		t.Fatal("relative path accepted")
	}

	setWorkerEnvironment(t)
	cfg, err = LoadConfig()
	if err != nil {
		t.Fatal(err)
	}
	cfg.ParserBundleDir = filepath.Join(cfg.SourceObjectDir, "parser")
	if err := validateSharedPaths(cfg); err == nil {
		t.Fatal("nested shared path accepted")
	}
}
