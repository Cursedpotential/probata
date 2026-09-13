// Package profferworker composes the production Temporal worker for the single
// ProfferWorkflow. It is the only Go process allowed to poll the
// dedicated Proffer task queue, and it registers every canonical stage body.
//
// Package profferworker (formerly uiwworker / Proffer worker; renamed D-140, 2026-09-05).
package profferworker

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	platformtemporal "github.com/Cursedpotential/probata/engine/temporal"
)

const legacyEvidenceTaskQueue = "evidence-pipeline"

// Config contains only production worker settings. Secrets are held in
// memory and are never included in validation errors or log fields.
type Config struct {
	TemporalHostPort  string
	TemporalNamespace string
	TemporalTaskQueue string
	DatabaseURLFile   string
	DatabaseURL       string

	SourceObjectDir      string
	ParserBundleDir      string
	NormalizedBundleDir  string
	InventoryManifestDir string

	// PlatformToolsBaseURL addresses the TOOL GATEWAY, not platform-tools
	// directly (D-132): the gateway is the only sanctioned path from an
	// Activity to a tool, because it takes locators instead of host paths.
	// The name is retained so the deployed Coolify env key does not churn.
	PlatformToolsBaseURL string
	// ToolGatewayServiceTokenFile is a mounted secret file. The gateway
	// requires `Authorization: Bearer`, so a missing or empty file is a
	// startup failure, never a silent unauthenticated mode.
	ToolGatewayServiceTokenFile string
	ToolGatewayServiceToken     string

	N8NBaseURL          string
	N8NAuthHeader       string
	N8NAuthValueFile    string
	N8NFlowBindingsFile string
	SelectHTTPTimeout   time.Duration
	ExecuteHTTPTimeout  time.Duration
}

// LoadConfig reads the fail-closed worker environment contract. The worker
// intentionally uses TEMPORAL_TASK_QUEUE too, so the separately deployed HTTP
// starter can target the same queue without a second naming convention.
func LoadConfig() (Config, error) {
	var problems []string
	require := func(name string) string {
		value := strings.TrimSpace(os.Getenv(name))
		if value == "" {
			problems = append(problems, name+" is required")
		}
		return value
	}

	cfg := Config{
		TemporalHostPort:     require("TEMPORAL_HOST_PORT"),
		TemporalNamespace:    require("TEMPORAL_NAMESPACE"),
		TemporalTaskQueue:    require("TEMPORAL_TASK_QUEUE"),
		SourceObjectDir:      require("SOURCE_OBJECT_DIR"),
		ParserBundleDir:      require("PARSER_BUNDLE_DIR"),
		NormalizedBundleDir:  require("NORMALIZED_BUNDLE_DIR"),
		InventoryManifestDir: require("INVENTORY_MANIFEST_DIR"),
		PlatformToolsBaseURL: strings.TrimRight(require("PLATFORM_TOOLS_BASE_URL"), "/"),
		N8NBaseURL:           strings.TrimRight(require("N8N_PROFFER_BASE_URL"), "/"),
		N8NAuthHeader:        require("N8N_PROFFER_AUTH_HEADER"),
		N8NAuthValueFile:     firstEnvironment("N8N_PROFFER_AUTH_VALUE_FILE"),
		N8NFlowBindingsFile:  firstEnvironment("N8N_FLOW_BINDINGS_FILE"),
		SelectHTTPTimeout:    35 * time.Second,
		ExecuteHTTPTimeout:   31 * time.Minute,
	}
	cfg.DatabaseURLFile = firstEnvironment("PLATFORM_DATABASE_URL_FILE")
	if cfg.DatabaseURLFile == "" {
		cfg.DatabaseURLFile = "/run/secrets/platform-database-url"
	}
	if !absoluteRuntimePath(cfg.DatabaseURLFile) {
		problems = append(problems, "PLATFORM_DATABASE_URL_FILE must be an absolute path")
	} else if value, err := platformtemporal.ReadRuntimeSecretFile(cfg.DatabaseURLFile, 16<<10); err != nil {
		problems = append(problems, "PLATFORM_DATABASE_URL_FILE is unavailable or invalid")
	} else {
		cfg.DatabaseURL = value
	}
	cfg.ToolGatewayServiceTokenFile = firstEnvironment("TOOL_GATEWAY_SERVICE_TOKEN_FILE")
	if cfg.ToolGatewayServiceTokenFile == "" {
		cfg.ToolGatewayServiceTokenFile = "/run/secrets/tool-gateway-service-token"
	}
	if !absoluteRuntimePath(cfg.ToolGatewayServiceTokenFile) {
		problems = append(problems, "TOOL_GATEWAY_SERVICE_TOKEN_FILE must be an absolute path")
	} else if value, err := platformtemporal.ReadRuntimeSecretFile(cfg.ToolGatewayServiceTokenFile, 16<<10); err != nil || strings.TrimSpace(value) == "" {
		// Fail closed. The gateway is the only sanctioned path to a platform
		// tool (D-132) and answers 401 without this bearer token, so a worker
		// that starts without it would poll the queue only to fail every
		// repair Activity at call time.
		problems = append(problems, "TOOL_GATEWAY_SERVICE_TOKEN_FILE is unavailable or empty")
	} else {
		cfg.ToolGatewayServiceToken = value
	}
	if cfg.N8NAuthValueFile == "" {
		cfg.N8NAuthValueFile = "/run/secrets/n8n-proffer-auth"
	}
	if !absoluteRuntimePath(cfg.N8NAuthValueFile) {
		problems = append(problems, "N8N_PROFFER_AUTH_VALUE_FILE must be an absolute path")
	}
	if cfg.N8NFlowBindingsFile != "" && !absoluteRuntimePath(cfg.N8NFlowBindingsFile) {
		problems = append(problems, "N8N_FLOW_BINDINGS_FILE must be an absolute path when configured")
	}
	if cfg.TemporalTaskQueue == legacyEvidenceTaskQueue {
		problems = append(problems, "TEMPORAL_TASK_QUEUE must be dedicated to universal import and cannot be evidence-pipeline")
	}
	if timeout, err := optionalDuration("SELECT_PARSER_HTTP_TIMEOUT", cfg.SelectHTTPTimeout); err != nil {
		problems = append(problems, err.Error())
	} else {
		cfg.SelectHTTPTimeout = timeout
	}
	if timeout, err := optionalDuration("EXECUTE_PARSER_HTTP_TIMEOUT", cfg.ExecuteHTTPTimeout); err != nil {
		problems = append(problems, err.Error())
	} else {
		cfg.ExecuteHTTPTimeout = timeout
	}
	if len(problems) > 0 {
		return Config{}, fmt.Errorf("proffer worker: invalid configuration: %s", strings.Join(problems, "; "))
	}
	return cfg, nil
}

func absoluteRuntimePath(path string) bool {
	return filepath.IsAbs(path) || strings.HasPrefix(path, "/")
}

func firstEnvironment(names ...string) string {
	for _, name := range names {
		if value := strings.TrimSpace(os.Getenv(name)); value != "" {
			return value
		}
	}
	return ""
}

func optionalDuration(name string, fallback time.Duration) (time.Duration, error) {
	raw := strings.TrimSpace(os.Getenv(name))
	if raw == "" {
		return fallback, nil
	}
	value, err := time.ParseDuration(raw)
	if err != nil {
		return 0, fmt.Errorf("%s must be a valid Go duration: %w", name, err)
	}
	if value <= 0 {
		return 0, errors.New(name + " must be a positive duration")
	}
	return value, nil
}

func (c Config) temporalConfig() platformtemporal.Config {
	return platformtemporal.Config{
		TemporalHostPort:   c.TemporalHostPort,
		TemporalNamespace:  c.TemporalNamespace,
		TemporalTaskQueue:  c.TemporalTaskQueue,
		N8NBaseURL:         c.N8NBaseURL,
		N8NAuthHeader:      c.N8NAuthHeader,
		N8NAuthValueFile:   c.N8NAuthValueFile,
		SelectHTTPTimeout:  c.SelectHTTPTimeout,
		ExecuteHTTPTimeout: c.ExecuteHTTPTimeout,
	}
}

// validateSharedPaths requires four explicit, non-overlapping absolute roots.
// Coolify mounts these exact paths into both the parser runtime and this
// worker; relative or nested roots would make stored file:// references
// ambiguous across services and are rejected before Temporal polling begins.
func validateSharedPaths(c Config) error {
	paths := map[string]string{
		"SOURCE_OBJECT_DIR":      c.SourceObjectDir,
		"PARSER_BUNDLE_DIR":      c.ParserBundleDir,
		"NORMALIZED_BUNDLE_DIR":  c.NormalizedBundleDir,
		"INVENTORY_MANIFEST_DIR": c.InventoryManifestDir,
	}
	clean := make(map[string]string, len(paths))
	for name, path := range paths {
		if !filepath.IsAbs(path) {
			return fmt.Errorf("proffer worker: %s must be an absolute shared path", name)
		}
		clean[name] = filepath.Clean(path)
	}
	for leftName, left := range clean {
		for rightName, right := range clean {
			if leftName >= rightName {
				continue
			}
			if sameOrNestedPath(left, right) || sameOrNestedPath(right, left) {
				return fmt.Errorf("proffer worker: shared paths %s and %s must be separate non-nested roots", leftName, rightName)
			}
		}
	}
	return nil
}

func sameOrNestedPath(parent, candidate string) bool {
	relative, err := filepath.Rel(parent, candidate)
	if err != nil {
		return false
	}
	return relative == "." || (relative != ".." && !strings.HasPrefix(relative, ".."+string(filepath.Separator)))
}
