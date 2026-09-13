// Byline: Codex · GPT-5.6 · 2026-08-29 (opaque Proffer preview HTTP contract tests)
package runtimeapi

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/require"

	"github.com/Cursedpotential/probata/engine/proffer"
	"github.com/Cursedpotential/probata/engine/runtimeapi/previewmodel"
	"github.com/Cursedpotential/probata/engine/stagegraph"
)

type previewWorkflowStub struct {
	started        proffer.WorkflowInput
	decision       proffer.PreviewDecision
	repair         proffer.RepairDecision
	handler        proffer.HandlerSelectionDecision
	state          proffer.PreviewState
	operation      proffer.OperationState
	operations     map[string]proffer.OperationState
	operationErr   error
	operationCalls int
	order          *[]string
}

func (s *previewWorkflowStub) Start(_ context.Context, in proffer.WorkflowInput) (string, string, error) {
	s.started = in
	return "workflow-1", "run-1", nil
}
func (s *previewWorkflowStub) Decide(_ context.Context, _ string, decision proffer.PreviewDecision) error {
	s.decision = decision
	return nil
}
func (s *previewWorkflowStub) DecideRepair(_ context.Context, _ string, decision proffer.RepairDecision) error {
	s.repair = decision
	if s.order != nil {
		*s.order = append(*s.order, "signal")
	}
	return nil
}
func (s *previewWorkflowStub) DecideHandler(_ context.Context, _ string, decision proffer.HandlerSelectionDecision) error {
	s.handler = decision
	if s.order != nil {
		*s.order = append(*s.order, "signal")
	}
	return nil
}
func (s *previewWorkflowStub) Preview(context.Context, string) (proffer.PreviewState, error) {
	return s.state, nil
}
func (s *previewWorkflowStub) Operation(_ context.Context, workflowID string) (proffer.OperationState, error) {
	s.operationCalls++
	if s.operationErr != nil {
		return proffer.OperationState{}, s.operationErr
	}
	if state, ok := s.operations[workflowID]; ok {
		return state, nil
	}
	if s.operation.Lifecycle != "" {
		return s.operation, nil
	}
	lifecycle := proffer.OperationRunning
	wait := proffer.OperationWait("")
	switch s.state.Phase {
	case proffer.PhaseAwaitingRepairDecision:
		lifecycle, wait = proffer.OperationAwaitingRepairDecision, proffer.OperationWaitRepairDecision
	case proffer.PhaseAwaitingDecision, proffer.PhaseRejected:
		lifecycle, wait = proffer.OperationAwaitingPreviewDecision, proffer.OperationWaitPreviewDecision
	}
	return proffer.OperationState{Lifecycle: lifecycle, Wait: wait, ActiveStages: []proffer.ActivityName{}}, nil
}

type countingEntropy struct{ next byte }

type failOncePreviewStore struct {
	*MemoryPreviewStore
	failed bool
}

func (s *failOncePreviewStore) Create(ctx context.Context, binding PreviewBinding) (PreviewBinding, error) {
	if !s.failed {
		s.failed = true
		return PreviewBinding{}, errors.New("transient binding failure")
	}
	return s.MemoryPreviewStore.Create(ctx, binding)
}

type repairWriterStub struct {
	got   proffer.RepairDecisionSpec
	order *[]string
}

type handlerDecisionWriterStub struct {
	source, recommendation, actor, compatibility proffer.Ref
	idempotency                                  string
	order                                        *[]string
}

func (s *handlerDecisionWriterStub) PersistHandlerSelectionDecision(_ context.Context, source, recommendation, actor, compatibility proffer.Ref, idempotency string) (proffer.Ref, error) {
	s.source, s.recommendation, s.actor, s.compatibility, s.idempotency = source, recommendation, actor, compatibility, idempotency
	if s.order != nil {
		*s.order = append(*s.order, "persist")
	}
	return "77777777-7777-7777-7777-777777777777", nil
}

type sourceContextValidatorStub struct{ err error }

func (s sourceContextValidatorStub) ValidateSourceContext(context.Context, string, string, string, string, string) error {
	return s.err
}

func (s *repairWriterStub) PersistRepairDecision(_ context.Context, spec proffer.RepairDecisionSpec) (proffer.Ref, error) {
	s.got = spec
	if s.order != nil {
		*s.order = append(*s.order, "persist")
	}
	return "66666666-6666-6666-6666-666666666666", nil
}

func (r *countingEntropy) Read(dest []byte) (int, error) {
	for index := range dest {
		dest[index] = r.next
		r.next++
	}
	return len(dest), nil
}

func previewTestHandler(t *testing.T) (*PreviewHTTPHandler, *MemoryPreviewStore, *previewWorkflowStub) {
	t.Helper()
	store := NewMemoryPreviewStore(&countingEntropy{next: 1})
	workflow := &previewWorkflowStub{state: proffer.PreviewState{
		Phase: proffer.PhaseAwaitingDecision, SelectRef: "selection-1", ParserOptionsRef: "options-1",
		Checkpoints: []proffer.PreviewCheckpoint{
			{Checkpoint: "raw_source_verification", Status: proffer.CheckpointRunning},
			{Checkpoint: "parser_selection", Status: proffer.CheckpointCompleted, ReceiptRef: "receipt-selection"},
		},
	}}
	handler, err := NewPreviewHTTPHandler(workflow, store, store, store, bytes.Repeat([]byte("k"), 32), serviceTokenPath(t), sourceContextValidatorStub{})
	require.NoError(t, err)
	return handler, store, workflow
}

func serviceTokenPath(t *testing.T) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "proffer-service-token")
	require.NoError(t, os.WriteFile(path, []byte(strings.Repeat("s", 32)), 0600))
	return path
}

func servePreview(handler http.Handler, method, target string, body []byte) *httptest.ResponseRecorder {
	req := httptest.NewRequest(method, target, bytes.NewReader(body))
	req.RemoteAddr = "100.64.1.9:3456"
	req.Header.Set("X-authentik-uid", "authentik-user-1")
	req.Header.Set("X-authentik-username", "operator")
	req.Header.Set("Authorization", "Bearer "+strings.Repeat("s", 32))
	recorder := httptest.NewRecorder()
	handler.ServeHTTP(recorder, req)
	return recorder
}

func startPreview(t *testing.T, handler *PreviewHTTPHandler) string {
	t.Helper()
	body := []byte(`{"request_id":"request-1","matter_id":"11111111-1111-1111-1111-111111111111","court_case_id":"22222222-2222-2222-2222-222222222222","source_ref":"upload://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","declared_format":"sms_xml","parser_options_ref":"options-1"}`)
	recorder := servePreview(handler.Routes(), http.MethodPost, "/reference-import/start", body)
	require.Equal(t, http.StatusCreated, recorder.Code, recorder.Body.String())
	var response struct {
		PreviewHandle string `json:"preview_handle"`
	}
	require.NoError(t, json.NewDecoder(recorder.Body).Decode(&response))
	require.Len(t, response.PreviewHandle, 32)
	return response.PreviewHandle
}

func putValidProjection(t *testing.T, store *MemoryPreviewStore, handle string) {
	t.Helper()
	snapshot := PreviewSnapshot{PreviewHandle: handle, Phase: "awaiting_decision", PreviewDigest: strings.Repeat("a", 64)}
	snapshot.Correlation.RequestID = "request-1"
	snapshot.Correlation.SourceVersionID = uuid.MustParse("33333333-3333-3333-3333-333333333333")
	snapshot.Correlation.RawGenerationID = uuid.MustParse("44444444-4444-4444-4444-444444444444")
	snapshot.Correlation.NormalizedGenerationID = uuid.MustParse("55555555-5555-5555-5555-555555555555")
	snapshot.Parser = &PreviewParser{ParserID: "sbv", ParserVersion: "1.2.3", ConfigDigest: strings.Repeat("b", 64)}
	for i, kind := range receiptTypes {
		digest := sha256.Sum256([]byte(kind))
		snapshot.Receipts = append(snapshot.Receipts, PreviewReceipt{ReceiptType: kind, ReceiptRef: "receipt-" + kind, Status: "completed", Digest: fmtDigest(digest), RecordedAt: time.Unix(int64(i+1), 0).UTC()})
	}
	participant := PreviewParticipant{ParticipantID: "p-1", DisplayName: "Person One"}
	sender := "p-1"
	messages := []PreviewMessage{
		{MessageID: "m-2", Ordinal: 2, SenderParticipantID: &sender, Body: "second", ParticipantIDs: []string{"p-1"}, Attachments: []PreviewAttachment{{AttachmentID: "a-1", SourceLocatorRef: "attachment-locator"}}, SourceLocatorRef: "locator-2"},
		{MessageID: "m-1", Ordinal: 1, SenderParticipantID: &sender, Body: "first", ParticipantIDs: []string{"p-1"}, SourceLocatorRef: "locator-1"},
	}
	event := PreviewEvent{EventID: 1, EventType: "messages_available", OccurredAt: time.Unix(10, 0).UTC(), PreviewHandle: handle, Phase: "awaiting_decision"}
	require.NoError(t, store.PutProjection(handle, snapshot, []PreviewParticipant{participant}, messages, []PreviewEvent{event}))
}

func TestPreviewContentReturnsExactGenericRecordsAndScopedChunkCursor(t *testing.T) {
	handler, store, _ := previewTestHandler(t)
	handle := startPreview(t, handler)
	putValidProjection(t, store, handle)
	content := PreviewContentPage{
		Package:        previewmodel.Package{SourceVersionRef: "33333333-3333-3333-3333-333333333333", DeclaredFormat: "document", Status: "retained"},
		Attempt:        previewmodel.Attempt{ProjectionRef: "55555555-5555-5555-5555-555555555555", SourceVersionRef: "33333333-3333-3333-3333-333333333333", RawGenerationRef: "44444444-4444-4444-4444-444444444444", NormalizedGenerationRef: "55555555-5555-5555-5555-555555555555"},
		AttemptsReason: "complete attempt history is not exposed",
		Records: []previewmodel.Record{
			{RecordID: "record-1", Ordinal: 0, RecordType: "document", Payload: json.RawMessage(`{"title":"Exact"}`), SourceLocatorRef: "context.normalized_record_identity/record-1"},
			{RecordID: "record-2", Ordinal: 1, RecordType: "other", Payload: json.RawMessage(`{"value":2}`), SourceLocatorRef: "context.normalized_record_identity/record-2"},
		},
		Chunks: []previewmodel.ContentChunk{
			{ChunkRef: "chunk-1", Index: 0, Content: "alpha", SHA256: strings.Repeat("a", 64), DerivationMode: "verbatim_span", LocatorRef: "locator-1", ByteStart: 0, ByteEnd: 5},
			{ChunkRef: "chunk-2", Index: 1, Content: " beta", SHA256: strings.Repeat("b", 64), DerivationMode: "verbatim_span", LocatorRef: "locator-2", ByteStart: 5, ByteEnd: 10},
		},
	}
	require.NoError(t, store.PutContent(handle, content))

	response := servePreview(handler.Routes(), http.MethodGet, "/reference-import/previews/"+handle+"/content?limit=1", nil)
	require.Equal(t, http.StatusOK, response.Code, response.Body.String())
	var page struct {
		PreviewHandle    string                      `json:"preview_handle"`
		Records          []previewmodel.Record       `json:"records"`
		Chunks           []previewmodel.ContentChunk `json:"chunks"`
		NextRecordCursor string                      `json:"next_record_cursor"`
		NextChunkCursor  string                      `json:"next_chunk_cursor"`
	}
	require.NoError(t, json.NewDecoder(response.Body).Decode(&page))
	require.Equal(t, handle, page.PreviewHandle)
	require.Equal(t, json.RawMessage(`{"title":"Exact"}`), page.Records[0].Payload)
	require.Equal(t, "alpha", page.Chunks[0].Content)
	require.NotEmpty(t, page.NextRecordCursor)
	require.NotEmpty(t, page.NextChunkCursor)

	crossed := servePreview(handler.Routes(), http.MethodGet, "/reference-import/previews/"+handle+"/content?limit=1&chunk_cursor="+page.NextRecordCursor, nil)
	require.Equal(t, http.StatusUnprocessableEntity, crossed.Code, crossed.Body.String())
	second := servePreview(handler.Routes(), http.MethodGet, "/reference-import/previews/"+handle+"/content?limit=1&record_cursor="+page.NextRecordCursor+"&chunk_cursor="+page.NextChunkCursor, nil)
	require.Equal(t, http.StatusOK, second.Code, second.Body.String())
	require.Contains(t, second.Body.String(), `"record_id":"record-2"`)
	require.Contains(t, second.Body.String(), `"chunk_ref":"chunk-2"`)
}

func TestMemoryPreviewDecisionsAppendImmutableCompleteSuccessors(t *testing.T) {
	store := NewMemoryPreviewStore(&countingEntropy{next: 1})
	binding, err := store.Create(t.Context(), PreviewBinding{
		RequestID: "request-1", WorkflowID: "workflow-1", RunID: "run-1", ParserOptionsRef: "options-1",
	})
	require.NoError(t, err)
	putValidProjection(t, store, binding.Handle)

	store.mu.RLock()
	original := store.entries[binding.Handle].projections[0]
	store.mu.RUnlock()

	require.NoError(t, store.RecordDecision(t.Context(), binding.Handle, false, "needs repair", "actor-1", "selection-1", "options-1"))
	require.NoError(t, store.RecordDecision(t.Context(), binding.Handle, true, "repaired", "actor-1", "selection-2", "options-2"))
	// An exact retry is idempotent and must not allocate another successor or event.
	require.NoError(t, store.RecordDecision(t.Context(), binding.Handle, true, "repaired", "actor-1", "selection-2", "options-2"))

	store.mu.RLock()
	entry := store.entries[binding.Handle]
	require.Len(t, entry.projections, 3, "initial seq 0 plus decision successors seq 1 and 2")
	require.Len(t, entry.events, 4, "initial, projection, reject, approve")
	initial, rejected, approved := entry.projections[0], entry.projections[1], entry.projections[2]
	store.mu.RUnlock()

	require.Equal(t, "awaiting_decision", initial.snapshot.Phase)
	require.Empty(t, initial.snapshot.Reason)
	require.Equal(t, original, initial, "the prior immutable projection changed")
	require.Equal(t, "rejected", rejected.snapshot.Phase)
	require.Equal(t, "needs repair", rejected.snapshot.Reason)
	require.Equal(t, "approved", approved.snapshot.Phase)
	require.Equal(t, "repaired", approved.snapshot.Reason)
	for _, successor := range []memoryPreviewProjection{rejected, approved} {
		require.Equal(t, initial.snapshot.Correlation, successor.snapshot.Correlation)
		require.Equal(t, initial.snapshot.Parser, successor.snapshot.Parser)
		require.Equal(t, initial.snapshot.PreviewDigest, successor.snapshot.PreviewDigest)
		require.Equal(t, initial.snapshot.Receipts, successor.snapshot.Receipts)
		require.Equal(t, initial.participants, successor.participants)
		require.Equal(t, initial.messages, successor.messages)
	}

	current, err := store.Snapshot(t.Context(), binding.Handle)
	require.NoError(t, err)
	require.Equal(t, "approved", current.Phase)
	page, err := store.Page(t.Context(), binding.Handle, 0, 10)
	require.NoError(t, err)
	require.Equal(t, initial.participants, page.Participants)
	require.Equal(t, initial.messages, page.Messages)
	currentBinding, err := store.Binding(t.Context(), binding.Handle)
	require.NoError(t, err)
	require.Equal(t, proffer.Ref("selection-2"), currentBinding.SelectionRef)
	require.Equal(t, proffer.Ref("options-2"), currentBinding.ParserOptionsRef)
}

func fmtDigest(value [sha256.Size]byte) string {
	const alphabet = "0123456789abcdef"
	output := make([]byte, sha256.Size*2)
	for i, b := range value {
		output[i*2], output[i*2+1] = alphabet[b>>4], alphabet[b&15]
	}
	return string(output)
}

func TestPreviewSurfaceCorrelatesPagesDecisionsAndReplay(t *testing.T) {
	handler, store, workflow := previewTestHandler(t)
	handle := startPreview(t, handler)

	notReady := servePreview(handler.Routes(), http.MethodGet, "/reference-import/previews/"+handle, nil)
	require.Equal(t, http.StatusOK, notReady.Code)
	require.Contains(t, notReady.Body.String(), `"checkpoint":"raw_source_verification","status":"running"`)
	require.Contains(t, notReady.Body.String(), `"checkpoint":"parser_selection","status":"completed","receipt_ref":"receipt-selection"`)
	putValidProjection(t, store, handle)

	snapshot := servePreview(handler.Routes(), http.MethodGet, "/reference-import/previews/"+handle, nil)
	require.Equal(t, http.StatusOK, snapshot.Code)
	require.Contains(t, snapshot.Body.String(), `"preview_handle":"`+handle+`"`)

	page1 := servePreview(handler.Routes(), http.MethodGet, "/reference-import/previews/"+handle+"/messages?limit=1", nil)
	require.Equal(t, http.StatusOK, page1.Code)
	var page struct {
		Messages   []PreviewMessage `json:"messages"`
		NextCursor string           `json:"next_cursor"`
	}
	require.NoError(t, json.NewDecoder(page1.Body).Decode(&page))
	require.Equal(t, "m-1", page.Messages[0].MessageID)
	require.NotEmpty(t, page.NextCursor)

	otherBinding, err := store.Create(t.Context(), PreviewBinding{RequestID: "request-2", WorkflowID: "workflow-2", RunID: "run-2", ParserOptionsRef: "options-1"})
	require.NoError(t, err)
	other := otherBinding.Handle
	crossHandle := servePreview(handler.Routes(), http.MethodGet, "/reference-import/previews/"+other+"/messages?cursor="+page.NextCursor, nil)
	require.Equal(t, http.StatusUnprocessableEntity, crossHandle.Code)

	decisionBody := []byte(`{"approved":true,"reason":""}`)
	decision := servePreview(handler.Routes(), http.MethodPost, "/reference-import/previews/"+handle+"/decision", decisionBody)
	require.Equal(t, http.StatusOK, decision.Code, decision.Body.String())
	require.Equal(t, "authentik-user-1", workflow.decision.Decider)
	current := servePreview(handler.Routes(), http.MethodGet, "/reference-import/previews/"+handle, nil)
	require.Contains(t, current.Body.String(), `"phase":"approved"`)

	req := httptest.NewRequest(http.MethodGet, "/reference-import/previews/"+handle+"/events", nil)
	req.RemoteAddr = "100.64.1.9:3456"
	req.Header.Set("Last-Event-ID", "0")
	req.Header.Set("Authorization", "Bearer "+strings.Repeat("s", 32))
	events := httptest.NewRecorder()
	handler.Routes().ServeHTTP(events, req)
	require.Equal(t, http.StatusOK, events.Code)
	require.Contains(t, events.Header().Get("Content-Type"), "text/event-stream")
	require.Contains(t, events.Body.String(), "id: 1")
	require.Contains(t, events.Body.String(), "id: 2")
}

func TestOperationSurfaceListsFiltersPagesAndOpensByOpaqueHandle(t *testing.T) {
	handler, store, workflow := previewTestHandler(t)
	base := time.Date(2026, 9, 12, 12, 0, 0, 0, time.UTC)
	create := func(requestID, workflowID string, createdAt time.Time) PreviewBinding {
		binding, err := store.Create(t.Context(), PreviewBinding{
			RequestID: requestID, SourceRef: proffer.Ref("upload://" + strings.Repeat(requestID[len(requestID)-1:], 64)),
			WorkflowID: workflowID, RunID: "internal-" + workflowID, ParserOptionsRef: "options-1", CreatedAt: createdAt,
		})
		require.NoError(t, err)
		return binding
	}
	oldest := create("request-1", "workflow-1", base)
	waiting := create("request-2", "workflow-2", base.Add(time.Minute))
	newest := create("request-3", "workflow-3", base.Add(2*time.Minute))
	workflow.operations = map[string]proffer.OperationState{
		"workflow-1": {Lifecycle: proffer.OperationCompleted, Terminal: true, ActiveStages: []proffer.ActivityName{}, CompletedStageCount: 26},
		"workflow-2": {Lifecycle: proffer.OperationAwaitingRepairDecision, Wait: proffer.OperationWaitRepairDecision, ActiveStages: []proffer.ActivityName{}, CompletedStageCount: 3},
		"workflow-3": {
			Lifecycle: proffer.OperationRunning, CurrentStage: stagegraph.ExecuteParser,
			ActiveStages: []proffer.ActivityName{stagegraph.ExecuteParser}, CompletedStageCount: 8,
			SourceVersionRef: "33333333-3333-3333-3333-333333333333",
			Stages:           []proffer.OperationStage{{Stage: stagegraph.RegisterSource, Status: proffer.StatusSuccess, Ref: "source-ref", ReceiptRef: "source-receipt"}},
		},
	}

	first := servePreview(handler.Routes(), http.MethodGet, "/reference-import/operations?limit=2", nil)
	require.Equal(t, http.StatusOK, first.Code, first.Body.String())
	var page OperationListResponse
	require.NoError(t, json.NewDecoder(first.Body).Decode(&page))
	require.Len(t, page.Items, 2)
	require.Equal(t, newest.Handle, page.Items[0].PreviewHandle)
	require.Equal(t, waiting.Handle, page.Items[1].PreviewHandle)
	require.NotNil(t, page.NextCursor)
	require.NotContains(t, first.Body.String(), "workflow_id")
	require.NotContains(t, first.Body.String(), "run_id")

	second := servePreview(handler.Routes(), http.MethodGet, "/reference-import/operations?limit=2&cursor="+*page.NextCursor, nil)
	require.Equal(t, http.StatusOK, second.Code, second.Body.String())
	page = OperationListResponse{}
	require.NoError(t, json.NewDecoder(second.Body).Decode(&page))
	require.Len(t, page.Items, 1)
	require.Equal(t, oldest.Handle, page.Items[0].PreviewHandle)
	require.Nil(t, page.NextCursor)

	filtered := servePreview(handler.Routes(), http.MethodGet, "/reference-import/operations?status=awaiting_repair_decision", nil)
	require.Equal(t, http.StatusOK, filtered.Code, filtered.Body.String())
	page = OperationListResponse{}
	require.NoError(t, json.NewDecoder(filtered.Body).Decode(&page))
	require.Len(t, page.Items, 1)
	require.Equal(t, waiting.Handle, page.Items[0].PreviewHandle)
	require.Equal(t, proffer.OperationWaitRepairDecision, page.Items[0].Wait)

	workflow.operationCalls = 0
	detailResponse := servePreview(handler.Routes(), http.MethodGet, "/reference-import/operations/"+newest.Handle, nil)
	require.Equal(t, http.StatusOK, detailResponse.Code, detailResponse.Body.String())
	var detail OperationDetail
	require.NoError(t, json.NewDecoder(detailResponse.Body).Decode(&detail))
	require.Equal(t, newest.Handle, detail.PreviewHandle)
	require.Equal(t, proffer.OperationRunning, detail.Lifecycle)
	require.Equal(t, stagegraph.ExecuteParser, detail.CurrentStage)
	require.Equal(t, "proffer", detail.Service)
	require.Len(t, detail.Stages, 1)
	require.Equal(t, string(stagegraph.RegisterSource), detail.Stages[0].Stage)
	require.Equal(t, 1, workflow.operationCalls, "detail must use one authoritative Temporal query")
}

func TestOperationCursorAndFilterFailClosed(t *testing.T) {
	handler, _, _ := previewTestHandler(t)
	badFilter := servePreview(handler.Routes(), http.MethodGet, "/reference-import/operations?status=spinning", nil)
	require.Equal(t, http.StatusUnprocessableEntity, badFilter.Code)
	badCursor := servePreview(handler.Routes(), http.MethodGet, "/reference-import/operations?cursor=not-signed", nil)
	require.Equal(t, http.StatusUnprocessableEntity, badCursor.Code)
}

func TestPreviewSnapshotCarriesLiveOperationWithoutErasingDecisionPhase(t *testing.T) {
	handler, store, workflow := previewTestHandler(t)
	handle := startPreview(t, handler)
	putValidProjection(t, store, handle)
	workflow.operation = proffer.OperationState{
		Lifecycle: proffer.OperationCompleted, Terminal: true, ActiveStages: []proffer.ActivityName{}, CompletedStageCount: 26,
	}
	response := servePreview(handler.Routes(), http.MethodGet, "/reference-import/previews/"+handle, nil)
	require.Equal(t, http.StatusOK, response.Code, response.Body.String())
	var snapshot PreviewSnapshot
	require.NoError(t, json.NewDecoder(response.Body).Decode(&snapshot))
	require.Equal(t, "awaiting_decision", snapshot.Phase, "phase remains the immutable preview decision projection")
	require.Equal(t, proffer.OperationCompleted, snapshot.Lifecycle)
	require.True(t, snapshot.Terminal)
	require.Equal(t, 26, snapshot.CompletedStageCount)
}

func TestPreviewSnapshotNeverGuessesTerminalStateFromPostgresProjection(t *testing.T) {
	handler, store, workflow := previewTestHandler(t)
	handle := startPreview(t, handler)
	putValidProjection(t, store, handle)
	require.NoError(t, store.RecordDecision(t.Context(), handle, true, "approved", "actor-1", "selection-1", "options-1"))
	workflow.operationErr = errors.New("temporal query unavailable")

	response := servePreview(handler.Routes(), http.MethodGet, "/reference-import/previews/"+handle, nil)
	require.Equal(t, http.StatusOK, response.Code, response.Body.String())
	var snapshot PreviewSnapshot
	require.NoError(t, json.NewDecoder(response.Body).Decode(&snapshot))
	require.Equal(t, "approved", snapshot.Phase)
	require.Equal(t, proffer.OperationUnavailable, snapshot.Lifecycle)
	require.False(t, snapshot.Terminal, "an approved PG projection is not proof that the workflow terminated")
}

func TestPreviewSurfaceFailsClosedOnAuthUnknownHandleAndEventGap(t *testing.T) {
	handler, _, _ := previewTestHandler(t)
	unauthorized := httptest.NewRecorder()
	handler.Routes().ServeHTTP(unauthorized, httptest.NewRequest(http.MethodGet, "/reference-import/previews/unknown", nil))
	require.Equal(t, http.StatusUnauthorized, unauthorized.Code)

	unknown := servePreview(handler.Routes(), http.MethodGet, "/reference-import/previews/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", nil)
	require.Equal(t, http.StatusNotFound, unknown.Code)

	handle := startPreview(t, handler)
	req := httptest.NewRequest(http.MethodGet, "/reference-import/previews/"+handle+"/events", nil)
	req.RemoteAddr = "100.64.1.9:3456"
	req.Header.Set("Last-Event-ID", "99")
	req.Header.Set("Authorization", "Bearer "+strings.Repeat("s", 32))
	recorder := httptest.NewRecorder()
	handler.Routes().ServeHTTP(recorder, req)
	require.Equal(t, http.StatusConflict, recorder.Code)
}

func TestRepairDecisionIsPersistedByProfferBeforeTemporalSignal(t *testing.T) {
	store := NewMemoryPreviewStore(&countingEntropy{next: 1})
	order := []string{}
	workflow := &previewWorkflowStub{order: &order, state: proffer.PreviewState{
		Phase:               proffer.PhaseAwaitingRepairDecision,
		SourceVersionRef:    "33333333-3333-3333-3333-333333333333",
		RepairAssessmentRef: "44444444-4444-4444-4444-444444444444",
	}}
	writer := &repairWriterStub{order: &order}
	handler, err := NewPreviewHTTPHandler(workflow, store, writer, store, bytes.Repeat([]byte("k"), 32), serviceTokenPath(t))
	require.NoError(t, err)
	handle := startPreview(t, handler)
	req := httptest.NewRequest(http.MethodPost, "/reference-import/previews/"+handle+"/repair-decision", strings.NewReader(`{"approved":true,"apply_repair":false,"tool_payload":{}}`))
	req.RemoteAddr = "100.64.1.9:3456"
	req.Header.Set("X-authentik-uid", "authentik-subject-1")
	req.Header.Set("X-authentik-username", "operator")
	req.Header.Set("Idempotency-Key", "repair-choice-1")
	req.Header.Set("Authorization", "Bearer "+strings.Repeat("s", 32))
	recorder := httptest.NewRecorder()
	handler.Routes().ServeHTTP(recorder, req)
	require.Equal(t, http.StatusOK, recorder.Code, recorder.Body.String())
	require.Equal(t, []string{"persist", "signal"}, order)
	require.Equal(t, proffer.Ref("authentik-subject-1"), writer.got.ActorRef)
	require.Equal(t, proffer.Ref("66666666-6666-6666-6666-666666666666"), workflow.repair.DecisionRef)
}

func TestHandlerSelectionIsCorrelatedPersistedBeforeReferenceOnlySignal(t *testing.T) {
	store := NewMemoryPreviewStore(&countingEntropy{next: 1})
	order := []string{}
	compatibilityRef := proffer.Ref("55555555-5555-5555-5555-555555555555")
	workflow := &previewWorkflowStub{order: &order, state: proffer.PreviewState{
		Phase:                    proffer.PhaseAwaitingHandlerSelection,
		SourceVersionRef:         "33333333-3333-3333-3333-333333333333",
		HandlerRecommendationRef: "44444444-4444-4444-4444-444444444444",
		RecommendedHandler: &proffer.HandlerCandidate{
			HandlerID: "duckdb_structured_elt", HandlerVersion: "1.0.0", ExecutionPath: proffer.HandlerPathDuckDB,
			CompatibilityRef: compatibilityRef, Reason: "content signature match",
		},
	}}
	writer := &handlerDecisionWriterStub{order: &order}
	handler, err := NewPreviewHTTPHandler(workflow, store, store, writer, bytes.Repeat([]byte("k"), 32), serviceTokenPath(t))
	require.NoError(t, err)
	handle := startPreview(t, handler)
	visible := servePreview(handler.Routes(), http.MethodGet, "/reference-import/previews/"+handle, nil)
	require.Equal(t, http.StatusOK, visible.Code, visible.Body.String())
	require.Contains(t, visible.Body.String(), `"handler_recommendation_ref":"44444444-4444-4444-4444-444444444444"`)
	require.Contains(t, visible.Body.String(), `"compatibility_ref":"55555555-5555-5555-5555-555555555555"`)
	req := httptest.NewRequest(http.MethodPost, "/reference-import/previews/"+handle+"/handler-selection", strings.NewReader(`{"compatibility_ref":"55555555-5555-5555-5555-555555555555"}`))
	req.RemoteAddr = "100.64.1.9:3456"
	req.Header.Set("X-authentik-uid", "authentik-subject-1")
	req.Header.Set("X-authentik-username", "operator")
	req.Header.Set("Idempotency-Key", "handler-choice-1")
	req.Header.Set("Authorization", "Bearer "+strings.Repeat("s", 32))
	recorder := httptest.NewRecorder()
	handler.Routes().ServeHTTP(recorder, req)
	require.Equal(t, http.StatusOK, recorder.Code, recorder.Body.String())
	require.Equal(t, []string{"persist", "signal"}, order)
	require.Equal(t, proffer.Ref("authentik-subject-1"), writer.actor)
	require.Equal(t, compatibilityRef, writer.compatibility)
	require.Equal(t, "proffer:"+handle+":handler-choice-1", writer.idempotency)
	require.Equal(t, proffer.Ref("77777777-7777-7777-7777-777777777777"), workflow.handler.DecisionRef)

	badRequest := httptest.NewRequest(http.MethodPost, "/reference-import/previews/"+handle+"/handler-selection", strings.NewReader(`{"compatibility_ref":"66666666-6666-6666-6666-666666666666"}`))
	badRequest.RemoteAddr = "100.64.1.9:3456"
	badRequest.Header.Set("X-authentik-uid", "authentik-subject-1")
	badRequest.Header.Set("X-authentik-username", "operator")
	badRequest.Header.Set("Idempotency-Key", "handler-choice-2")
	badRequest.Header.Set("Authorization", "Bearer "+strings.Repeat("s", 32))
	bad := httptest.NewRecorder()
	handler.Routes().ServeHTTP(bad, badRequest)
	require.Equal(t, http.StatusConflict, bad.Code, bad.Body.String())
	require.Equal(t, []string{"persist", "signal"}, order, "mismatched candidate must not persist or signal")
}

func TestStartRetryReconcilesSameWorkflowAfterBindingFailure(t *testing.T) {
	base := NewMemoryPreviewStore(&countingEntropy{next: 1})
	store := &failOncePreviewStore{MemoryPreviewStore: base}
	workflow := &previewWorkflowStub{}
	handler, err := NewPreviewHTTPHandler(workflow, store, store, store, bytes.Repeat([]byte("k"), 32), serviceTokenPath(t))
	require.NoError(t, err)
	body := []byte(`{"request_id":"request-1","matter_id":"11111111-1111-1111-1111-111111111111","court_case_id":"22222222-2222-2222-2222-222222222222","source_ref":"upload://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","declared_format":"sms_xml","parser_options_ref":"options-1"}`)
	require.Equal(t, http.StatusServiceUnavailable, servePreview(handler.Routes(), http.MethodPost, "/reference-import/start", body).Code)
	retry := servePreview(handler.Routes(), http.MethodPost, "/reference-import/start", body)
	require.Equal(t, http.StatusCreated, retry.Code, retry.Body.String())
	var response map[string]string
	require.NoError(t, json.NewDecoder(retry.Body).Decode(&response))
	require.NotEmpty(t, response["preview_handle"])
	again := servePreview(handler.Routes(), http.MethodPost, "/reference-import/start", body)
	require.Equal(t, http.StatusCreated, again.Code)
	require.Contains(t, again.Body.String(), response["preview_handle"])
}

func TestStartPassesOnlyTheDurableSourceContextReferenceIntoTemporal(t *testing.T) {
	handler, _, workflow := previewTestHandler(t)
	body := []byte(`{"request_id":"request-with-context","matter_id":"11111111-1111-1111-1111-111111111111","court_case_id":"22222222-2222-2222-2222-222222222222","source_ref":"upload://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","declared_format":"sms_xml","parser_options_ref":"options-1","source_context_ref":"33333333-3333-3333-3333-333333333333"}`)
	recorder := servePreview(handler.Routes(), http.MethodPost, "/reference-import/start", body)
	require.Equal(t, http.StatusCreated, recorder.Code, recorder.Body.String())
	require.Equal(t, proffer.Ref("33333333-3333-3333-3333-333333333333"), workflow.started.SourceContextRef)
}

func TestStartRejectsSourceContextThatDoesNotOwnTheExactIntakeScope(t *testing.T) {
	store := NewMemoryPreviewStore(&countingEntropy{next: 1})
	workflow := &previewWorkflowStub{}
	handler, err := NewPreviewHTTPHandler(workflow, store, store, store, bytes.Repeat([]byte("k"), 32), serviceTokenPath(t), sourceContextValidatorStub{err: errors.New("scope mismatch")})
	require.NoError(t, err)
	body := []byte(`{"request_id":"request-with-context","matter_id":"11111111-1111-1111-1111-111111111111","court_case_id":"22222222-2222-2222-2222-222222222222","source_ref":"upload://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","declared_format":"sms_xml","parser_options_ref":"options-1","source_context_ref":"33333333-3333-3333-3333-333333333333"}`)
	recorder := servePreview(handler.Routes(), http.MethodPost, "/reference-import/start", body)
	require.Equal(t, http.StatusUnprocessableEntity, recorder.Code, recorder.Body.String())
	require.Empty(t, workflow.started.RequestID)
}

func TestIntegratedRejectedPreviewCanApproveWithoutLegacyRepairRefs(t *testing.T) {
	handler, store, workflow := previewTestHandler(t)
	handle := startPreview(t, handler)
	putValidProjection(t, store, handle)
	workflow.state = proffer.PreviewState{Phase: proffer.PhaseRejected, PreviewHandle: proffer.Ref(handle), SelectRef: "selection-1", ParserOptionsRef: "options-1"}
	response := servePreview(handler.Routes(), http.MethodPost, "/reference-import/previews/"+handle+"/decision", []byte(`{"approved":true}`))
	require.Equal(t, http.StatusOK, response.Code, response.Body.String())
	require.Empty(t, workflow.decision.RepairedSelectionRef)
}

func TestServiceTokenRotationIsReloadedPerRequest(t *testing.T) {
	store := NewMemoryPreviewStore(&countingEntropy{next: 1})
	path := serviceTokenPath(t)
	handler, err := NewPreviewHTTPHandler(&previewWorkflowStub{}, store, store, store, bytes.Repeat([]byte("k"), 32), path)
	require.NoError(t, err)
	require.NoError(t, os.WriteFile(path, []byte(strings.Repeat("r", 32)), 0600))
	oldToken := servePreview(handler.Routes(), http.MethodGet, "/reference-import/previews/unknown", nil)
	require.Equal(t, http.StatusUnauthorized, oldToken.Code)
	req := httptest.NewRequest(http.MethodGet, "/reference-import/previews/unknown", nil)
	req.RemoteAddr = "100.64.1.9:3456"
	req.Header.Set("Authorization", "Bearer "+strings.Repeat("r", 32))
	recorder := httptest.NewRecorder()
	handler.Routes().ServeHTTP(recorder, req)
	require.Equal(t, http.StatusNotFound, recorder.Code)
}

func TestLoadServiceTokenMatchesBFFFileAndTokenPolicy(t *testing.T) {
	fullAlphabet := strings.Repeat("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~+/", 2) + "=="
	tests := []struct {
		name    string
		content []byte
		want    string
	}{
		{name: "minimum", content: []byte(strings.Repeat("a", 32)), want: strings.Repeat("a", 32)},
		{name: "maximum", content: []byte(strings.Repeat("Z", 4096)), want: strings.Repeat("Z", 4096)},
		{name: "maximum with CRLF", content: []byte(strings.Repeat("x", 4096) + "\r\n"), want: strings.Repeat("x", 4096)},
		{name: "full alphabet and trailing padding", content: []byte(fullAlphabet), want: fullAlphabet},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			path := filepath.Join(t.TempDir(), "token")
			require.NoError(t, os.WriteFile(path, test.content, 0600))
			got, err := loadServiceToken(path)
			require.NoError(t, err)
			require.Equal(t, test.want, string(got))
		})
	}
}

func TestLoadServiceTokenRejectsInvalidFilesAndBytes(t *testing.T) {
	invalid := []struct {
		name    string
		content []byte
	}{
		{name: "raw too short", content: []byte(strings.Repeat("a", 31))},
		{name: "trimmed too short", content: []byte(strings.Repeat("a", 31) + "\r\n")},
		{name: "raw too long", content: []byte(strings.Repeat("a", 4099))},
		{name: "token too long", content: []byte(strings.Repeat("a", 4097))},
		{name: "invalid UTF8", content: append([]byte(strings.Repeat("a", 31)), 0xff)},
		{name: "NUL", content: append([]byte(strings.Repeat("a", 31)), 0)},
		{name: "space", content: []byte(strings.Repeat("a", 31) + " ")},
		{name: "padding in middle", content: []byte(strings.Repeat("a", 31) + "=a")},
		{name: "only padding", content: []byte(strings.Repeat("=", 32))},
		{name: "newline in middle", content: []byte(strings.Repeat("a", 31) + "\n" + "a")},
	}
	for _, test := range invalid {
		t.Run(test.name, func(t *testing.T) {
			path := filepath.Join(t.TempDir(), "token")
			require.NoError(t, os.WriteFile(path, test.content, 0600))
			_, err := loadServiceToken(path)
			require.Error(t, err)
		})
	}

	_, err := loadServiceToken("relative-token")
	require.Error(t, err)
	_, err = loadServiceToken(t.TempDir())
	require.Error(t, err)

	target := filepath.Join(t.TempDir(), "target")
	require.NoError(t, os.WriteFile(target, []byte(strings.Repeat("a", 32)), 0600))
	link := filepath.Join(filepath.Dir(target), "link")
	if err := os.Symlink(target, link); err == nil {
		_, err = loadServiceToken(link)
		require.Error(t, err)
	}
}
