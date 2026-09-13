package temporal

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/Cursedpotential/probata/engine/proffer"
	"github.com/Cursedpotential/probata/engine/stagegraph"
)

func testConfig(t *testing.T, baseURL string) Config {
	t.Helper()
	path := filepath.Join(t.TempDir(), "n8n-auth-value")
	if err := os.WriteFile(path, []byte("Bearer test-token\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	return Config{
		N8NBaseURL:         baseURL,
		N8NAuthHeader:      "Authorization",
		N8NAuthValueFile:   path,
		SelectHTTPTimeout:  2 * time.Second,
		ExecuteHTTPTimeout: 2 * time.Second,
	}
}

func testFileConfig(t *testing.T, baseURL, value string) (Config, string) {
	t.Helper()
	path := filepath.Join(t.TempDir(), "n8n-auth-value")
	if err := os.WriteFile(path, []byte(value), 0o600); err != nil {
		t.Fatal(err)
	}
	cfg := testConfig(t, baseURL)
	cfg.N8NAuthValueFile = path
	return cfg, path
}

func selectRequest() proffer.StageRequest {
	return proffer.StageRequest{
		RequestID:        "req-1",
		SourceVersionRef: "srcv-1",
		DeclaredFormat:   "whatsapp_export_json",
		Refs: map[string]proffer.Ref{
			"filesystem_metadata": "fs-ref",
			"container_manifest":  "container-ref",
			"metadata_manifest":   "metadata-ref",
		},
	}
}

func executeRequest() proffer.StageRequest {
	return proffer.StageRequest{
		RequestID:        "req-1",
		SourceVersionRef: "srcv-1",
		DeclaredFormat:   "whatsapp_export_json",
		Refs: map[string]proffer.Ref{
			"parser_selection": "selection-ref",
			"original":         "original-ref",
			"parser_options":   "parser-options-ref",
		},
	}
}

func TestCallStageSelectParserSuccess(t *testing.T) {
	var gotPath, gotAuth, gotRequestID, gotIdempotency string
	var gotBody map[string]any
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotPath = r.URL.Path
		gotAuth = r.Header.Get("Authorization")
		gotRequestID = r.Header.Get("X-Request-ID")
		gotIdempotency = r.Header.Get("Idempotency-Key")
		_ = json.NewDecoder(r.Body).Decode(&gotBody)
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]string{
			"stage": "select_parser_activity", "status": "success",
			"ref": "selection-ref", "receipt_ref": "selection-receipt",
		})
	}))
	defer server.Close()

	client, err := NewN8NClient(testConfig(t, server.URL))
	if err != nil {
		t.Fatalf("NewN8NClient() error = %v", err)
	}

	result, err := client.CallStage(t.Context(), stagegraph.SelectParser, selectRequest())
	if err != nil {
		t.Fatalf("CallStage() error = %v, want nil", err)
	}
	if result.Stage != stagegraph.SelectParser || result.Status != proffer.StatusSuccess ||
		result.Ref != "selection-ref" || result.ReceiptRef != "selection-receipt" {
		t.Errorf("CallStage() result = %+v, unexpected", result)
	}
	if gotPath != "/proffer/select-parser-activity" {
		t.Errorf("request path = %q, want select webhook path", gotPath)
	}
	if gotAuth != "Bearer test-token" {
		t.Errorf("Authorization header = %q, want configured auth value", gotAuth)
	}
	if gotRequestID != "req-1" || gotIdempotency != "req-1" {
		t.Errorf("X-Request-ID/Idempotency-Key = %q/%q, want req-1/req-1", gotRequestID, gotIdempotency)
	}
	if gotBody["request_id"] != "req-1" || gotBody["source_version_ref"] != "srcv-1" || gotBody["declared_format"] != "whatsapp_export_json" {
		t.Errorf("request body = %+v, missing expected top-level fields", gotBody)
	}
	refs, ok := gotBody["refs"].(map[string]any)
	if !ok || len(refs) != 3 {
		t.Errorf("request body refs = %+v, want exactly 3 named refs", gotBody["refs"])
	}
}

func TestCallStageRereadsRotatedAuthValueFile(t *testing.T) {
	var gotAuth []string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotAuth = append(gotAuth, r.Header.Get("Authorization"))
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]string{
			"stage": "select_parser_activity", "status": "success",
			"ref": "selection-ref", "receipt_ref": "selection-receipt",
		})
	}))
	defer server.Close()

	cfg, path := testFileConfig(t, server.URL, "Bearer first-token\r\n")
	client, err := NewN8NClient(cfg)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := client.CallStage(t.Context(), stagegraph.SelectParser, selectRequest()); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte("Bearer rotated-token\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := client.CallStage(t.Context(), stagegraph.SelectParser, selectRequest()); err != nil {
		t.Fatal(err)
	}
	if len(gotAuth) != 2 || gotAuth[0] != "Bearer first-token" || gotAuth[1] != "Bearer rotated-token" {
		t.Fatalf("Authorization headers = %q, want original then rotated value", gotAuth)
	}
}

func TestCallStageFailsClosedWhenAuthValueFileIsMissing(t *testing.T) {
	called := false
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		called = true
	}))
	defer server.Close()
	cfg := testConfig(t, server.URL)
	cfg.N8NAuthValueFile = filepath.Join(t.TempDir(), "missing")
	client, err := NewN8NClient(cfg)
	if err != nil {
		t.Fatal(err)
	}
	_, err = client.CallStage(t.Context(), stagegraph.SelectParser, selectRequest())
	if err == nil || !strings.Contains(err.Error(), "unavailable or invalid") {
		t.Fatalf("CallStage() error = %v, want generic auth-file error", err)
	}
	if called {
		t.Fatal("n8n webhook was called without a readable auth value")
	}
}

func TestCallStageRejectsMalformedAuthValueWithoutLeakingIt(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		t.Fatal("n8n webhook should not be called with malformed auth")
	}))
	defer server.Close()
	const secret = "Bearer secret-value"
	cfg, path := testFileConfig(t, server.URL, secret+"\nembedded")
	client, err := NewN8NClient(cfg)
	if err != nil {
		t.Fatal(err)
	}
	_, err = client.CallStage(t.Context(), stagegraph.SelectParser, selectRequest())
	if err == nil || !strings.Contains(err.Error(), "unavailable or invalid") {
		t.Fatalf("CallStage() error = %v, want malformed auth rejection", err)
	}
	if strings.Contains(err.Error(), secret) || strings.Contains(err.Error(), path) {
		t.Fatalf("CallStage() error leaked auth material or its path: %q", err)
	}
}

func TestReadN8NAuthValueRejectsInvalidFiles(t *testing.T) {
	for name, value := range map[string][]byte{
		"empty":        {},
		"invalid utf8": {0xff},
		"oversized":    bytes.Repeat([]byte("x"), maxN8NAuthValueBytes+3),
	} {
		t.Run(name, func(t *testing.T) {
			path := filepath.Join(t.TempDir(), "auth")
			if err := os.WriteFile(path, value, 0o600); err != nil {
				t.Fatal(err)
			}
			if _, err := ReadRuntimeSecretFile(path, maxN8NAuthValueBytes); err == nil {
				t.Fatal("ReadRuntimeSecretFile() error = nil, want invalid-file rejection")
			}
		})
	}
	if _, err := ReadRuntimeSecretFile(t.TempDir(), maxN8NAuthValueBytes); err == nil {
		t.Fatal("ReadRuntimeSecretFile() accepted a directory")
	}
	target := filepath.Join(t.TempDir(), "target")
	if err := os.WriteFile(target, []byte("Bearer target"), 0o600); err != nil {
		t.Fatal(err)
	}
	link := filepath.Join(t.TempDir(), "link")
	if err := os.Symlink(target, link); err != nil {
		t.Skipf("symlink creation unavailable: %v", err)
	}
	if _, err := ReadRuntimeSecretFile(link, maxN8NAuthValueBytes); err == nil {
		t.Fatal("ReadRuntimeSecretFile() accepted a symlink")
	}
}

func TestCallStageExecuteParserSuccess(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/proffer/execute-parser-activity" {
			t.Errorf("request path = %q, want execute webhook path", r.URL.Path)
		}
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]string{
			"stage": "execute_parser_activity", "status": "success",
			"ref": "execute-ref", "receipt_ref": "execute-receipt",
		})
	}))
	defer server.Close()

	client, err := NewN8NClient(testConfig(t, server.URL))
	if err != nil {
		t.Fatalf("NewN8NClient() error = %v", err)
	}
	result, err := client.CallStage(t.Context(), stagegraph.ExecuteParser, executeRequest())
	if err != nil {
		t.Fatalf("CallStage() error = %v, want nil", err)
	}
	if result.Ref != "execute-ref" || result.ReceiptRef != "execute-receipt" {
		t.Errorf("CallStage() result = %+v, unexpected", result)
	}
}

func TestCallStageRejectsMissingRequiredRefs(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		t.Fatal("n8n webhook should never be called when client-side validation fails")
	}))
	defer server.Close()

	client, err := NewN8NClient(testConfig(t, server.URL))
	if err != nil {
		t.Fatalf("NewN8NClient() error = %v", err)
	}
	req := selectRequest()
	delete(req.Refs, "container_manifest")

	if _, err := client.CallStage(t.Context(), stagegraph.SelectParser, req); err == nil {
		t.Fatal("CallStage() error = nil, want error for missing required ref")
	}
}

func TestOutboundRequestAllowsOnlyBoundedHandlerDecisionRefs(t *testing.T) {
	route := stageRoutes(Config{})[stagegraph.SelectParser]
	req := selectRequest()
	if err := validateOutboundRequest(route, req); err != nil {
		t.Fatalf("validateOutboundRequest() rejected legacy refs: %v", err)
	}
	for _, name := range handlerDecisionRefNames() {
		req.Refs[name] = proffer.Ref(name + "-ref")
	}
	if err := validateOutboundRequest(route, req); err != nil {
		t.Fatalf("validateOutboundRequest() rejected durable handler refs: %v", err)
	}
	req.Refs["browser_handler_hint"] = "untrusted"
	if err := validateOutboundRequest(route, req); err == nil || !strings.Contains(err.Error(), "unsupported") {
		t.Fatalf("validateOutboundRequest() error = %v, want unsupported extra ref", err)
	}
}

func TestOutboundRequestRequiresHandlerDecisionRefsAllOrNone(t *testing.T) {
	route := stageRoutes(Config{})[stagegraph.ExecuteParser]
	for _, omitted := range handlerDecisionRefNames() {
		req := executeRequest()
		for _, name := range handlerDecisionRefNames() {
			if name != omitted {
				req.Refs[name] = proffer.Ref(name + "-ref")
			}
		}
		if err := validateOutboundRequest(route, req); err == nil || !strings.Contains(err.Error(), "all handler decision refs") {
			t.Fatalf("validateOutboundRequest() with %q omitted error = %v, want all-or-none rejection", omitted, err)
		}
	}
}

func TestCallStageFailsClosedOnNon2xx(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusUnprocessableEntity)
		_ = json.NewEncoder(w).Encode(map[string]string{"error": "select parser for format \"bogus\": no capability"})
	}))
	defer server.Close()

	client, err := NewN8NClient(testConfig(t, server.URL))
	if err != nil {
		t.Fatalf("NewN8NClient() error = %v", err)
	}
	_, err = client.CallStage(t.Context(), stagegraph.SelectParser, selectRequest())
	if err == nil {
		t.Fatal("CallStage() error = nil, want error on non-2xx response")
	}
	if !strings.Contains(err.Error(), "no capability") {
		t.Errorf("CallStage() error = %q, want it to surface the n8n error body", err.Error())
	}
}

func TestCallStageFailsClosedOnMismatchedStage(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]string{
			"stage": "execute_parser_activity", "status": "success",
			"ref": "x", "receipt_ref": "r",
		})
	}))
	defer server.Close()

	client, err := NewN8NClient(testConfig(t, server.URL))
	if err != nil {
		t.Fatalf("NewN8NClient() error = %v", err)
	}
	if _, err := client.CallStage(t.Context(), stagegraph.SelectParser, selectRequest()); err == nil {
		t.Fatal("CallStage() error = nil, want error when returned stage doesn't match invoked stage")
	}
}

func TestCallStageFailsClosedOnEmptyRefs(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]string{
			"stage": "select_parser_activity", "status": "success",
			"ref": "", "receipt_ref": "",
		})
	}))
	defer server.Close()

	client, err := NewN8NClient(testConfig(t, server.URL))
	if err != nil {
		t.Fatalf("NewN8NClient() error = %v", err)
	}
	if _, err := client.CallStage(t.Context(), stagegraph.SelectParser, selectRequest()); err == nil {
		t.Fatal("CallStage() error = nil, want error on empty ref/receipt_ref")
	}
}

func TestCallStageFailsClosedOnUnroutableStage(t *testing.T) {
	client, err := NewN8NClient(testConfig(t, "https://n8n.example.invalid"))
	if err != nil {
		t.Fatalf("NewN8NClient() error = %v", err)
	}
	if _, err := client.CallStage(t.Context(), stagegraph.FingerprintSource, selectRequest()); err == nil {
		t.Fatal("CallStage() error = nil, want error for a stage this client has no route for")
	}
}

func TestNewN8NClientRequiresBaseURLAndAuth(t *testing.T) {
	if _, err := NewN8NClient(Config{N8NAuthHeader: "Authorization", N8NAuthValueFile: filepath.Join(t.TempDir(), "auth")}); err == nil {
		t.Error("NewN8NClient() error = nil, want error for missing base URL")
	}
	if _, err := NewN8NClient(Config{N8NBaseURL: "https://n8n.example.com"}); err == nil {
		t.Error("NewN8NClient() error = nil, want error for missing auth header/value")
	}
}
