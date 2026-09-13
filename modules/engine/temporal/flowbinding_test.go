// Byline: Claude Code · Opus 5 · 2026-09-03.
package temporal

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/Cursedpotential/probata/engine/proffer"
)

func TestFlowBindingRejectsUnsafeDeclarations(t *testing.T) {
	cases := map[string]FlowBinding{
		"empty name":        {Name: "", WebhookPath: "a/b"},
		"padded name":       {Name: " x ", WebhookPath: "a/b"},
		"name with slash":   {Name: "a/b", WebhookPath: "a/b"},
		"missing path":      {Name: "x", WebhookPath: ""},
		"absolute path":     {Name: "x", WebhookPath: "/a/b"},
		"full URL":          {Name: "x", WebhookPath: "http://evil/a"},
		"traversal":         {Name: "x", WebhookPath: "a/../../etc/passwd"},
		"query string":      {Name: "x", WebhookPath: "a/b?c=1"},
		"backslash":         {Name: "x", WebhookPath: `a\b`},
		"duplicate ref key": {Name: "x", WebhookPath: "a/b", RequireRefs: []string{"o", "o"}},
		"padded input key":  {Name: "x", WebhookPath: "a/b", RequireInputs: []string{" f"}},
		"negative timeout":  {Name: "x", WebhookPath: "a/b", TimeoutSeconds: -1},
	}
	for label, binding := range cases {
		if _, err := NewFlowRegistry([]FlowBinding{binding}); err == nil {
			t.Fatalf("%s: expected the binding to be refused", label)
		}
	}
}

func TestFlowRegistryRefusesDuplicateNames(t *testing.T) {
	_, err := NewFlowRegistry([]FlowBinding{
		{Name: "chunk_preview", WebhookPath: "a/one"},
		{Name: "chunk_preview", WebhookPath: "a/two"},
	})
	if err == nil || !strings.Contains(err.Error(), "declared more than once") {
		t.Fatalf("expected duplicate names to fail at startup, got %v", err)
	}
}

func TestFlowBindingTimeoutDefaultsAndCeiling(t *testing.T) {
	if got := (FlowBinding{}).Timeout(); got != defaultFlowTimeout {
		t.Fatalf("default timeout = %v, want %v", got, defaultFlowTimeout)
	}
	if got := (FlowBinding{TimeoutSeconds: 30}).Timeout(); got != 30*time.Second {
		t.Fatalf("declared timeout = %v, want 30s", got)
	}
	if got := (FlowBinding{TimeoutSeconds: 999999}).Timeout(); got != maxFlowTimeout {
		t.Fatalf("timeout ceiling = %v, want %v", got, maxFlowTimeout)
	}
}

// A missing binding file is a legitimate configuration: the built-in parser
// stages must keep working with no extra flows declared.
func TestLoadFlowBindingsMissingFileIsEmptyNotAnError(t *testing.T) {
	registry, err := LoadFlowBindings(filepath.Join(t.TempDir(), "absent.json"))
	if err != nil {
		t.Fatalf("missing binding file should not error: %v", err)
	}
	if len(registry.Names()) != 0 {
		t.Fatalf("expected an empty registry, got %v", registry.Names())
	}
}

func TestLoadFlowBindingsReadsDeclarations(t *testing.T) {
	path := filepath.Join(t.TempDir(), "bindings.json")
	doc := `{"bindings":[
      {"name":"chunk_preview","webhook_path":"proffer/chunk-preview","require_refs":["original"],
       "require_inputs":["chunk_profile"],"description":"Chunk and preview","timeout_seconds":120},
      {"name":"ocr_page","webhook_path":"tools/ocr-page"}
    ]}`
	if err := os.WriteFile(path, []byte(doc), 0o600); err != nil {
		t.Fatal(err)
	}
	registry, err := LoadFlowBindings(path)
	if err != nil {
		t.Fatalf("LoadFlowBindings: %v", err)
	}
	if got := registry.Names(); len(got) != 2 || got[0] != "chunk_preview" || got[1] != "ocr_page" {
		t.Fatalf("names = %v, want sorted [chunk_preview ocr_page]", got)
	}
	if got := registry.Count(); got != 2 {
		t.Fatalf("count = %d, want 2", got)
	}
	binding, err := registry.Lookup("chunk_preview")
	if err != nil {
		t.Fatalf("Lookup: %v", err)
	}
	if binding.Timeout() != 120*time.Second || binding.Description != "Chunk and preview" {
		t.Fatalf("binding not read faithfully: %+v", binding)
	}
	if _, err := registry.Lookup("nope"); err == nil {
		t.Fatal("expected an undeclared flow to be refused")
	}
}

func TestLoadFlowBindingsRejectsUnknownFields(t *testing.T) {
	path := filepath.Join(t.TempDir(), "bindings.json")
	if err := os.WriteFile(path, []byte(`{"bindings":[{"name":"x","webhook_path":"a/b","surprise":1}]}`), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := LoadFlowBindings(path); err == nil {
		t.Fatal("expected an unknown field to be refused")
	}
}

func TestLoadFlowBindingsRequiresOneCompleteBindingsDocument(t *testing.T) {
	for label, doc := range map[string]string{
		"missing bindings": `{}`,
		"null document":    `null`,
		"null bindings":    `{"bindings":null}`,
		"trailing value":   `{"bindings":[]} {"bindings":[]}`,
		"trailing junk":    `{"bindings":[]} nope`,
	} {
		t.Run(label, func(t *testing.T) {
			path := filepath.Join(t.TempDir(), "bindings.json")
			if err := os.WriteFile(path, []byte(doc), 0o600); err != nil {
				t.Fatal(err)
			}
			if _, err := LoadFlowBindings(path); err == nil {
				t.Fatalf("LoadFlowBindings() accepted %s", doc)
			}
		})
	}
}

func newFlowTestRegistry(t *testing.T) *FlowRegistry {
	t.Helper()
	registry, err := NewFlowRegistry([]FlowBinding{{
		Name:          "chunk_preview",
		WebhookPath:   "proffer/chunk-preview",
		RequireRefs:   []string{"original"},
		RequireInputs: []string{"chunk_profile"},
	}})
	if err != nil {
		t.Fatalf("NewFlowRegistry: %v", err)
	}
	return registry
}

func TestRunFlowEnforcesTheDeclaredContractBeforeAnyHTTPCall(t *testing.T) {
	activities := FlowActivities{Client: &N8NClient{}, Registry: newFlowTestRegistry(t)}
	base := FlowRequest{
		Flow:      "chunk_preview",
		RequestID: "req-1",
		Refs:      map[string]proffer.Ref{"original": "upload://abc"},
		Inputs:    map[string]any{"chunk_profile": "chronology"},
	}

	missingFlow := base
	missingFlow.Flow = "undeclared"
	if _, err := activities.RunFlow(context.Background(), missingFlow); err == nil {
		t.Fatal("expected an undeclared flow to be refused")
	}

	noRequestID := base
	noRequestID.RequestID = ""
	if _, err := activities.RunFlow(context.Background(), noRequestID); err == nil ||
		!strings.Contains(err.Error(), "idempotency") {
		t.Fatalf("expected a missing request_id to be refused for idempotency, got %v", err)
	}

	missingRef := base
	missingRef.Refs = map[string]proffer.Ref{}
	if _, err := activities.RunFlow(context.Background(), missingRef); err == nil ||
		!strings.Contains(err.Error(), `requires ref "original"`) {
		t.Fatalf("expected the declared ref to be required, got %v", err)
	}

	missingInput := base
	missingInput.Inputs = map[string]any{}
	if _, err := activities.RunFlow(context.Background(), missingInput); err == nil ||
		!strings.Contains(err.Error(), `requires input "chunk_profile"`) {
		t.Fatalf("expected the declared input to be required, got %v", err)
	}

	tooMany := base
	tooMany.Inputs = map[string]any{"chunk_profile": "chronology"}
	for i := 0; i < maxFlowInputs; i++ {
		tooMany.Inputs[string(rune('a'+i%26))+string(rune('0'+i/26))] = i
	}
	if _, err := activities.RunFlow(context.Background(), tooMany); err == nil ||
		!strings.Contains(err.Error(), "inputs are knobs, not content") {
		t.Fatalf("expected an oversized input map to be refused, got %v", err)
	}
}

func TestCallFlowRoundTripsTheWireContract(t *testing.T) {
	var gotPath, gotIdempotency string
	var gotBody flowRequestWire
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotPath = r.URL.Path
		gotIdempotency = r.Header.Get("Idempotency-Key")
		_ = json.NewDecoder(r.Body).Decode(&gotBody)
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"flow":"chunk_preview","status":"success","ref":"chunks://gen-1","receipt_ref":"receipt://r1","outputs":{"chunk_count":42}}`))
	}))
	defer server.Close()

	client, err := NewN8NClient(testConfig(t, server.URL))
	if err != nil {
		t.Fatalf("NewN8NClient: %v", err)
	}
	activities := FlowActivities{Client: client, Registry: newFlowTestRegistry(t)}

	result, err := activities.RunFlow(context.Background(), FlowRequest{
		Flow:             "chunk_preview",
		RequestID:        "req-42",
		SourceVersionRef: "sv-1",
		DeclaredFormat:   "smsbackuprestore_xml",
		Refs:             map[string]proffer.Ref{"original": "upload://abc"},
		Inputs:           map[string]any{"chunk_profile": "chronology"},
	})
	if err != nil {
		t.Fatalf("RunFlow: %v", err)
	}
	if !strings.HasSuffix(gotPath, "/proffer/chunk-preview") {
		t.Fatalf("called %q, want the declared webhook path", gotPath)
	}
	if gotIdempotency != "req-42" {
		t.Fatalf("Idempotency-Key = %q, want req-42 (Activities get retried)", gotIdempotency)
	}
	if gotBody.Flow != "chunk_preview" || gotBody.Refs["original"] != "upload://abc" ||
		gotBody.Inputs["chunk_profile"] != "chronology" {
		t.Fatalf("outbound wire body lost data: %+v", gotBody)
	}
	if result.Status != proffer.StatusSuccess || result.Ref != "chunks://gen-1" {
		t.Fatalf("result = %+v", result)
	}
	if count, _ := result.Outputs["chunk_count"].(float64); count != 42 {
		t.Fatalf("outputs lost: %+v", result.Outputs)
	}
}

func TestCallFlowRejectsAResultNamingADifferentFlow(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte(`{"flow":"something_else","status":"success","ref":"x://1","receipt_ref":"","outputs":null}`))
	}))
	defer server.Close()
	client, err := NewN8NClient(testConfig(t, server.URL))
	if err != nil {
		t.Fatal(err)
	}
	activities := FlowActivities{Client: client, Registry: newFlowTestRegistry(t)}
	_, err = activities.RunFlow(context.Background(), FlowRequest{
		Flow: "chunk_preview", RequestID: "r", Refs: map[string]proffer.Ref{"original": "upload://a"},
		Inputs: map[string]any{"chunk_profile": "c"},
	})
	if err == nil || !strings.Contains(err.Error(), "the result names") {
		t.Fatalf("expected a mismatched flow name to be refused, got %v", err)
	}
}

func TestCallFlowRejectsSuccessWithNothingUsable(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte(`{"flow":"chunk_preview","status":"success","ref":"","receipt_ref":"","outputs":null}`))
	}))
	defer server.Close()
	client, err := NewN8NClient(testConfig(t, server.URL))
	if err != nil {
		t.Fatal(err)
	}
	activities := FlowActivities{Client: client, Registry: newFlowTestRegistry(t)}
	_, err = activities.RunFlow(context.Background(), FlowRequest{
		Flow: "chunk_preview", RequestID: "r", Refs: map[string]proffer.Ref{"original": "upload://a"},
		Inputs: map[string]any{"chunk_profile": "c"},
	})
	if err == nil || !strings.Contains(err.Error(), "neither a ref nor outputs") {
		t.Fatalf("expected empty success to be refused, got %v", err)
	}
}

func TestCallFlowSurfacesNon200(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusBadGateway)
		_, _ = w.Write([]byte(`{"error":"flow is not active"}`))
	}))
	defer server.Close()
	client, err := NewN8NClient(testConfig(t, server.URL))
	if err != nil {
		t.Fatal(err)
	}
	activities := FlowActivities{Client: client, Registry: newFlowTestRegistry(t)}
	_, err = activities.RunFlow(context.Background(), FlowRequest{
		Flow: "chunk_preview", RequestID: "r", Refs: map[string]proffer.Ref{"original": "upload://a"},
		Inputs: map[string]any{"chunk_profile": "c"},
	})
	if err == nil || !strings.Contains(err.Error(), "flow is not active") {
		t.Fatalf("expected the upstream error to surface, got %v", err)
	}
}
