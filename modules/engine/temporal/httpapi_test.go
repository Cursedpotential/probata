// Byline: Claude Code · Sonnet 5 · 2026-09-02 (BUILD LANE N2, D-125/D-127):
// added PLATFORM_DEV_AUTH_BYPASS coverage for withAuth -- all four states
// (flag unset/set x tailnet/non-tailnet peer) below.
package temporal

import (
	"bytes"
	"context"
	"encoding/json"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/Cursedpotential/probata/engine/proffer"
)

// fakeStarter is a hand-rolled WorkflowStarter for HTTP-layer tests, so they
// never need a real Temporal connection.
type fakeStarter struct {
	startIn       proffer.WorkflowInput
	startErr      error
	decideID      string
	decideArg     proffer.PreviewDecision
	decideErr     error
	previewID     string
	previewResult proffer.PreviewState
	previewErr    error
}

func (f *fakeStarter) Start(_ context.Context, in proffer.WorkflowInput) (string, string, error) {
	f.startIn = in
	if f.startErr != nil {
		return "", "", f.startErr
	}
	return "wf-" + in.RequestID, "run-1", nil
}

func (f *fakeStarter) Decide(_ context.Context, workflowID string, decision proffer.PreviewDecision) error {
	f.decideID = workflowID
	f.decideArg = decision
	return f.decideErr
}
func (f *fakeStarter) DecideRepair(context.Context, string, proffer.RepairDecision) error { return nil }

func (f *fakeStarter) Preview(_ context.Context, workflowID string) (proffer.PreviewState, error) {
	f.previewID = workflowID
	if f.previewErr != nil {
		return proffer.PreviewState{}, f.previewErr
	}
	return f.previewResult, nil
}
func (f *fakeStarter) Operation(context.Context, string) (proffer.OperationState, error) {
	return proffer.OperationState{Lifecycle: proffer.OperationRunning, ActiveStages: []proffer.ActivityName{}}, nil
}

func newTestHandler(t *testing.T, starter *fakeStarter) http.Handler {
	t.Helper()
	handler, err := NewStarterHTTPHandler(starter)
	if err != nil {
		t.Fatalf("NewStarterHTTPHandler() error = %v", err)
	}
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Query().Get("test_peer") == "tailnet" {
			r.RemoteAddr = "100.64.1.2:1234"
		}
		handler.Routes().ServeHTTP(w, r)
	})
}

// buildStarterHandler constructs the routes directly (no test_peer query
// rewriting), so the caller's real httptest.NewServer client address --
// always loopback, never tailnet-ranged -- is what withAuth evaluates.
func buildStarterHandler(t *testing.T, starter *fakeStarter) http.Handler {
	t.Helper()
	handler, err := NewStarterHTTPHandler(starter)
	if err != nil {
		t.Fatalf("NewStarterHTTPHandler() error = %v", err)
	}
	return handler.Routes()
}

// captureSlogWarnings redirects slog's default logger to an in-memory
// buffer for the duration of the test, mirroring
// engine/postgres/proffer_schema_probe_test.go's TestProbeProfferSchemaDevBypassLogsLoudWarning.
// Call it AFTER any handler construction whose own startup log should not
// be captured, so per-request assertions aren't polluted by the one-time
// construction-time warning.
func captureSlogWarnings(t *testing.T) *bytes.Buffer {
	t.Helper()
	var buf bytes.Buffer
	previous := slog.Default()
	slog.SetDefault(slog.New(slog.NewTextHandler(&buf, nil)))
	t.Cleanup(func() { slog.SetDefault(previous) })
	return &buf
}

func validStartBody() []byte {
	body, _ := json.Marshal(startRequest{
		RequestID:        "req-1",
		MatterID:         "11111111-1111-1111-1111-111111111111",
		CourtCaseID:      "22222222-2222-2222-2222-222222222222",
		SourceRef:        "acquisition-ref",
		DeclaredFormat:   "whatsapp_export_json",
		ParserOptionsRef: "parser-options-ref",
	})
	return body
}

func TestStartHandlerSuccess(t *testing.T) {
	starter := &fakeStarter{}
	server := httptest.NewServer(newTestHandler(t, starter))
	defer server.Close()

	req, _ := http.NewRequest(http.MethodPost, server.URL+"/reference-import/start?test_peer=tailnet", bytes.NewReader(validStartBody()))
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("POST /reference-import/start: %v", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusCreated {
		t.Fatalf("status = %d, want 201", resp.StatusCode)
	}
	var out startResponse
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if out.WorkflowID != "wf-req-1" || out.RunID != "run-1" {
		t.Errorf("response = %+v, unexpected", out)
	}
	if starter.startIn.RequestID != "req-1" || starter.startIn.SourceRef != "acquisition-ref" || starter.startIn.ParserOptionsRef != "parser-options-ref" {
		t.Errorf("starter.Start received %+v, unexpected", starter.startIn)
	}
}

func TestStartHandlerRejectsMissingAuth(t *testing.T) {
	starter := &fakeStarter{}
	server := httptest.NewServer(newTestHandler(t, starter))
	defer server.Close()

	resp, err := http.Post(server.URL+"/reference-import/start", "application/json", bytes.NewReader(validStartBody()))
	if err != nil {
		t.Fatalf("POST /reference-import/start: %v", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusUnauthorized {
		t.Fatalf("status = %d, want 401", resp.StatusCode)
	}
}

func TestStartHandlerRejectsMissingFields(t *testing.T) {
	starter := &fakeStarter{}
	server := httptest.NewServer(newTestHandler(t, starter))
	defer server.Close()

	body, _ := json.Marshal(startRequest{RequestID: "req-1", SourceRef: "acquisition-ref", MatterID: "11111111-1111-1111-1111-111111111111", CourtCaseID: "22222222-2222-2222-2222-222222222222"})
	req, _ := http.NewRequest(http.MethodPost, server.URL+"/reference-import/start?test_peer=tailnet", bytes.NewReader(body))
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("POST /reference-import/start: %v", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400 for a missing declared_format/parser_options_ref", resp.StatusCode)
	}
}

func TestDecisionHandlerSuccess(t *testing.T) {
	starter := &fakeStarter{}
	server := httptest.NewServer(newTestHandler(t, starter))
	defer server.Close()

	body, _ := json.Marshal(decisionRequest{Approved: true, Decider: "operator-1"})
	req, _ := http.NewRequest(http.MethodPost, server.URL+"/reference-import/wf-req-1/decision?test_peer=tailnet", bytes.NewReader(body))
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("POST decision: %v", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("status = %d, want 200", resp.StatusCode)
	}
	if starter.decideID != "wf-req-1" || !starter.decideArg.Approved || starter.decideArg.Decider != "operator-1" {
		t.Errorf("starter.Decide received id=%q arg=%+v, unexpected", starter.decideID, starter.decideArg)
	}
}

func TestDecisionHandlerRejectsRejectionWithoutReason(t *testing.T) {
	starter := &fakeStarter{}
	server := httptest.NewServer(newTestHandler(t, starter))
	defer server.Close()

	body, _ := json.Marshal(decisionRequest{Approved: false, Decider: "operator-1"})
	req, _ := http.NewRequest(http.MethodPost, server.URL+"/reference-import/wf-req-1/decision?test_peer=tailnet", bytes.NewReader(body))
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("POST decision: %v", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400 when a rejection has no reason", resp.StatusCode)
	}
}

func TestPreviewHandlerSuccess(t *testing.T) {
	starter := &fakeStarter{previewResult: proffer.PreviewState{Phase: proffer.PhaseAwaitingDecision, SelectRef: "selection-ref"}}
	server := httptest.NewServer(newTestHandler(t, starter))
	defer server.Close()

	req, _ := http.NewRequest(http.MethodGet, server.URL+"/reference-import/wf-req-1/preview?test_peer=tailnet", nil)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("GET preview: %v", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("status = %d, want 200", resp.StatusCode)
	}
	var state previewResponse
	if err := json.NewDecoder(resp.Body).Decode(&state); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if state.Phase != string(proffer.PhaseAwaitingDecision) || state.SelectRef != "selection-ref" {
		t.Errorf("preview state = %+v, unexpected", state)
	}
	if starter.previewID != "wf-req-1" {
		t.Errorf("starter.Preview received id=%q, want wf-req-1", starter.previewID)
	}
}

func TestHealthzIsUnauthenticated(t *testing.T) {
	server := httptest.NewServer(newTestHandler(t, &fakeStarter{}))
	defer server.Close()

	resp, err := http.Get(server.URL + "/healthz")
	if err != nil {
		t.Fatalf("GET /healthz: %v", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("status = %d, want 200", resp.StatusCode)
	}
}

func TestNewStarterHTTPHandlerRequiresStarter(t *testing.T) {
	if _, err := NewStarterHTTPHandler(nil); err == nil {
		t.Error("NewStarterHTTPHandler() error = nil, want error for nil starter")
	}
}

// --- PLATFORM_DEV_AUTH_BYPASS (D-125/D-127) -- all four withAuth states ---

// TestWithAuthFlagUnsetRejectsNonTailnetPeer: flag unset + non-tailnet peer
// => 401. This is today's unchanged strict default (D-127 Rule 0: the
// flag's default state IS production behavior).
func TestWithAuthFlagUnsetRejectsNonTailnetPeer(t *testing.T) {
	t.Setenv("PLATFORM_DEV_AUTH_BYPASS", "")
	starter := &fakeStarter{}
	server := httptest.NewServer(buildStarterHandler(t, starter))
	defer server.Close()

	resp, err := http.Post(server.URL+"/reference-import/start", "application/json", bytes.NewReader(validStartBody()))
	if err != nil {
		t.Fatalf("POST /reference-import/start: %v", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusUnauthorized {
		t.Fatalf("status = %d, want 401 when the flag is unset and the peer is not tailnet-ranged", resp.StatusCode)
	}
}

// TestWithAuthFlagUnsetAllowsTailnetPeer: flag unset + tailnet peer =>
// allowed. The strict path must work on its own, flag or no flag.
func TestWithAuthFlagUnsetAllowsTailnetPeer(t *testing.T) {
	t.Setenv("PLATFORM_DEV_AUTH_BYPASS", "")
	starter := &fakeStarter{}
	server := httptest.NewServer(newTestHandler(t, starter))
	defer server.Close()

	req, _ := http.NewRequest(http.MethodPost, server.URL+"/reference-import/start?test_peer=tailnet", bytes.NewReader(validStartBody()))
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("POST /reference-import/start: %v", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusCreated {
		t.Fatalf("status = %d, want 201 when the flag is unset and the peer is tailnet-ranged", resp.StatusCode)
	}
}

// TestWithAuthFlagSetAllowsNonTailnetPeerAndLogsWarning: flag set +
// non-tailnet peer => allowed, AND a per-request WARN line names the flag,
// the rejected RemoteAddr, and the route (D-127 Rule 5: never suppress a
// relaxed check into silence).
func TestWithAuthFlagSetAllowsNonTailnetPeerAndLogsWarning(t *testing.T) {
	t.Setenv("PLATFORM_DEV_AUTH_BYPASS", "1")
	starter := &fakeStarter{}
	// Construct before capturing logs so the one-time startup warning
	// (also emitted because the flag is set) doesn't pollute this
	// per-request assertion -- it has its own test below.
	handler := buildStarterHandler(t, starter)
	server := httptest.NewServer(handler)
	defer server.Close()

	buf := captureSlogWarnings(t)
	resp, err := http.Post(server.URL+"/reference-import/start", "application/json", bytes.NewReader(validStartBody()))
	if err != nil {
		t.Fatalf("POST /reference-import/start: %v", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusCreated {
		t.Fatalf("status = %d, want 201 -- PLATFORM_DEV_AUTH_BYPASS=1 must admit a non-tailnet peer", resp.StatusCode)
	}
	if starter.startIn.RequestID != "req-1" {
		t.Errorf("starter.Start did not receive the admitted request, got %+v", starter.startIn)
	}
	logged := buf.String()
	if !strings.Contains(logged, "PLATFORM_DEV_AUTH_BYPASS") {
		t.Fatalf("dev-bypass admission must log a warning naming the flag, got: %s", logged)
	}
	if !strings.Contains(strings.ToUpper(logged), "WARN") {
		t.Fatalf("dev-bypass admission warning must be logged at WARN level, got: %s", logged)
	}
	if !strings.Contains(logged, "/reference-import/start") {
		t.Fatalf("dev-bypass admission warning must name the route, got: %s", logged)
	}
	if !strings.Contains(logged, "remote_addr") {
		t.Fatalf("dev-bypass admission warning must name the rejected RemoteAddr, got: %s", logged)
	}
}

// TestWithAuthFlagSetAllowsTailnetPeerWithoutWarning: flag set + tailnet
// peer => allowed with NO per-request warning -- the strict check already
// passed, so there is nothing for the flag to have relaxed.
func TestWithAuthFlagSetAllowsTailnetPeerWithoutWarning(t *testing.T) {
	t.Setenv("PLATFORM_DEV_AUTH_BYPASS", "1")
	starter := &fakeStarter{}
	// Construct before capturing logs (see note above).
	handler := newTestHandler(t, starter)
	server := httptest.NewServer(handler)
	defer server.Close()

	buf := captureSlogWarnings(t)
	req, _ := http.NewRequest(http.MethodPost, server.URL+"/reference-import/start?test_peer=tailnet", bytes.NewReader(validStartBody()))
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("POST /reference-import/start: %v", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusCreated {
		t.Fatalf("status = %d, want 201 for a tailnet-ranged peer regardless of flag state", resp.StatusCode)
	}
	if logged := buf.String(); strings.Contains(logged, "PLATFORM_DEV_AUTH_BYPASS") {
		t.Fatalf("a tailnet-ranged peer must never trigger the dev-bypass per-request warning, got: %s", logged)
	}
}

// TestNewStarterHTTPHandlerLogsBypassWarningAtStartup: D-125/D-127 Rule 3
// requires a one-time startup warning naming the flag, matching the wording
// style of engine/postgres.ProbeProfferSchema's equivalent startup log.
func TestNewStarterHTTPHandlerLogsBypassWarningAtStartup(t *testing.T) {
	t.Setenv("PLATFORM_DEV_AUTH_BYPASS", "1")
	buf := captureSlogWarnings(t)

	if _, err := NewStarterHTTPHandler(&fakeStarter{}); err != nil {
		t.Fatalf("NewStarterHTTPHandler() error = %v", err)
	}
	logged := buf.String()
	if !strings.Contains(logged, "PLATFORM_DEV_AUTH_BYPASS") {
		t.Fatalf("starter construction must log a startup warning naming the flag when it is set, got: %s", logged)
	}
	if !strings.Contains(strings.ToUpper(logged), "WARN") {
		t.Fatalf("startup dev-bypass warning must be logged at WARN level, got: %s", logged)
	}
}

// TestNewStarterHTTPHandlerNoStartupWarningWhenBypassUnset: the flag-off
// default must stay quiet at startup -- no flag, no warning.
func TestNewStarterHTTPHandlerNoStartupWarningWhenBypassUnset(t *testing.T) {
	t.Setenv("PLATFORM_DEV_AUTH_BYPASS", "")
	buf := captureSlogWarnings(t)

	if _, err := NewStarterHTTPHandler(&fakeStarter{}); err != nil {
		t.Fatalf("NewStarterHTTPHandler() error = %v", err)
	}
	if logged := buf.String(); strings.Contains(logged, "PLATFORM_DEV_AUTH_BYPASS") {
		t.Fatalf("starter construction must not log the dev-bypass warning when the flag is unset, got: %s", logged)
	}
}
