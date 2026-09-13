// Byline: Codex · GPT-5.6 · 2026-08-29 (opaque Proffer preview HTTP surface)
package runtimeapi

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
	"unicode/utf8"

	"github.com/google/uuid"

	"github.com/Cursedpotential/probata/engine/proffer"
	"github.com/Cursedpotential/probata/engine/runtimeapi/previewmodel"
	"github.com/Cursedpotential/probata/engine/sourcecontext"
)

const (
	maxPreviewRequestBytes int64 = 16 << 10
	maxPreviewPage               = 250
	maxOperationPage             = 100
	maxOperationScan             = 1000
	maxReasonBytes               = 4000
)

var (
	ErrPreviewNotFound = previewmodel.ErrNotFound
	ErrPreviewNotReady = previewmodel.ErrNotReady
	ErrPreviewEventGap = previewmodel.ErrEventGap
)

// PreviewWorkflow is the compact Temporal boundary used by the preview HTTP
// surface. It never transports source or normalized bytes.
type PreviewWorkflow interface {
	Start(context.Context, proffer.WorkflowInput) (workflowID, runID string, err error)
	Decide(context.Context, string, proffer.PreviewDecision) error
	DecideRepair(context.Context, string, proffer.RepairDecision) error
	DecideHandler(context.Context, string, proffer.HandlerSelectionDecision) error
	Preview(context.Context, string) (proffer.PreviewState, error)
	Operation(context.Context, string) (proffer.OperationState, error)
}

type RepairDecisionWriter interface {
	PersistRepairDecision(context.Context, proffer.RepairDecisionSpec) (proffer.Ref, error)
}

type HandlerSelectionDecisionWriter interface {
	PersistHandlerSelectionDecision(context.Context, proffer.Ref, proffer.Ref, proffer.Ref, proffer.Ref, string) (proffer.Ref, error)
}

type PreviewBinding = previewmodel.Binding
type PreviewReceipt = previewmodel.Receipt
type PreviewParser = previewmodel.Parser
type PreviewSnapshot = previewmodel.Snapshot
type PreviewParticipant = previewmodel.Participant
type PreviewAttachment = previewmodel.Attachment
type PreviewMessage = previewmodel.Message
type PreviewEvent = previewmodel.Event
type PreviewPage = previewmodel.Page
type PreviewStore = previewmodel.Store

type memoryPreview struct {
	binding     PreviewBinding
	projections []memoryPreviewProjection
	decisions   map[[sha256.Size]byte]struct{}
	events      []PreviewEvent
}

type memoryPreviewProjection struct {
	snapshot     PreviewSnapshot
	participants []PreviewParticipant
	messages     []PreviewMessage
}

type MemoryPreviewStore struct {
	mu      sync.RWMutex
	entries map[string]*memoryPreview
	entropy io.Reader
}

func NewMemoryPreviewStore(entropy io.Reader) *MemoryPreviewStore {
	if entropy == nil {
		entropy = rand.Reader
	}
	return &MemoryPreviewStore{entries: make(map[string]*memoryPreview), entropy: entropy}
}

func (s *MemoryPreviewStore) PersistRepairDecision(_ context.Context, spec proffer.RepairDecisionSpec) (proffer.Ref, error) {
	if spec.SourceVersionRef == "" || spec.AssessmentRef == "" || spec.ActorRef == "" || spec.IdempotencyKey == "" {
		return "", errors.New("memory repair decision is incomplete")
	}
	id := uuid.NewSHA1(uuid.NameSpaceOID, []byte(spec.IdempotencyKey))
	return proffer.Ref(id.String()), nil
}

func (s *MemoryPreviewStore) PersistHandlerSelectionDecision(_ context.Context, sourceRef, recommendationRef, actorRef, compatibilityRef proffer.Ref, idempotencyKey string) (proffer.Ref, error) {
	if sourceRef == "" || recommendationRef == "" || actorRef == "" || compatibilityRef == "" || strings.TrimSpace(idempotencyKey) == "" {
		return "", errors.New("memory handler selection decision is incomplete")
	}
	id := uuid.NewSHA1(uuid.NameSpaceOID, []byte(idempotencyKey))
	return proffer.Ref(id.String()), nil
}

func (s *MemoryPreviewStore) Create(_ context.Context, binding PreviewBinding) (PreviewBinding, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for _, entry := range s.entries {
		if entry.binding.RequestID == binding.RequestID {
			if entry.binding.WorkflowID == binding.WorkflowID && entry.binding.RunID == binding.RunID {
				return entry.binding, nil
			}
			return PreviewBinding{}, errors.New("preview request is already bound to another workflow execution")
		}
	}
	for attempts := 0; attempts < 4; attempts++ {
		raw := make([]byte, 24)
		if _, err := io.ReadFull(s.entropy, raw); err != nil {
			return PreviewBinding{}, fmt.Errorf("generate preview handle: %w", err)
		}
		binding.Handle = base64.RawURLEncoding.EncodeToString(raw)
		if binding.CreatedAt.IsZero() {
			binding.CreatedAt = time.Now().UTC()
		}
		if _, exists := s.entries[binding.Handle]; exists {
			continue
		}
		s.entries[binding.Handle] = &memoryPreview{binding: binding, decisions: make(map[[sha256.Size]byte]struct{}), events: []PreviewEvent{{
			EventID: 0, EventType: "phase_changed", OccurredAt: time.Unix(0, 0).UTC(),
			PreviewHandle: binding.Handle, Phase: "starting",
		}}}
		return binding, nil
	}
	return PreviewBinding{}, errors.New("generate unique preview handle")
}

func (s *MemoryPreviewStore) ListBindings(_ context.Context, cursor *previewmodel.BindingCursor, limit int) (previewmodel.BindingPage, error) {
	if limit < 1 {
		return previewmodel.BindingPage{}, errors.New("preview binding page limit must be positive")
	}
	s.mu.RLock()
	defer s.mu.RUnlock()
	bindings := make([]PreviewBinding, 0, len(s.entries))
	for _, entry := range s.entries {
		binding := entry.binding
		if cursor != nil && !binding.CreatedAt.Before(cursor.CreatedAt) && !(binding.CreatedAt.Equal(cursor.CreatedAt) && binding.Handle < cursor.Handle) {
			continue
		}
		bindings = append(bindings, binding)
	}
	sort.Slice(bindings, func(i, j int) bool {
		if bindings[i].CreatedAt.Equal(bindings[j].CreatedAt) {
			return bindings[i].Handle > bindings[j].Handle
		}
		return bindings[i].CreatedAt.After(bindings[j].CreatedAt)
	})
	page := previewmodel.BindingPage{Bindings: bindings}
	if len(page.Bindings) > limit {
		page.Bindings = page.Bindings[:limit]
		page.HasMore = true
	}
	return page, nil
}

func (*MemoryPreviewStore) OperationStages(context.Context, string) ([]previewmodel.OperationStage, error) {
	return []previewmodel.OperationStage{}, nil
}

func (s *MemoryPreviewStore) Binding(_ context.Context, handle string) (PreviewBinding, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	entry := s.entries[handle]
	if entry == nil {
		return PreviewBinding{}, ErrPreviewNotFound
	}
	return entry.binding, nil
}

func (s *MemoryPreviewStore) Snapshot(_ context.Context, handle string) (PreviewSnapshot, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	entry := s.entries[handle]
	if entry == nil {
		return PreviewSnapshot{}, ErrPreviewNotFound
	}
	if len(entry.projections) == 0 {
		return PreviewSnapshot{}, ErrPreviewNotReady
	}
	return clonePreviewSnapshot(entry.projections[len(entry.projections)-1].snapshot), nil
}

func (s *MemoryPreviewStore) Page(_ context.Context, handle string, offset, limit int) (PreviewPage, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	entry := s.entries[handle]
	if entry == nil {
		return PreviewPage{}, ErrPreviewNotFound
	}
	if len(entry.projections) == 0 {
		return PreviewPage{}, ErrPreviewNotReady
	}
	projection := entry.projections[len(entry.projections)-1]
	if offset < 0 || offset > len(projection.messages) {
		return PreviewPage{}, ErrPreviewEventGap
	}
	end := offset + limit
	if end > len(projection.messages) {
		end = len(projection.messages)
	}
	page := PreviewPage{
		Participants: clonePreviewParticipants(projection.participants),
		Messages:     clonePreviewMessages(projection.messages[offset:end]),
	}
	if end < len(projection.messages) {
		page.NextOffset = &end
	}
	return page, nil
}

func (s *MemoryPreviewStore) EventsAfter(_ context.Context, handle string, after int64) ([]PreviewEvent, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	entry := s.entries[handle]
	if entry == nil {
		return nil, ErrPreviewNotFound
	}
	latest := entry.events[len(entry.events)-1].EventID
	if after > latest {
		return nil, ErrPreviewEventGap
	}
	first := entry.events[0].EventID
	if after >= 0 && after+1 < first {
		return nil, ErrPreviewEventGap
	}
	result := make([]PreviewEvent, 0, len(entry.events))
	for _, event := range entry.events {
		if event.EventID > after {
			result = append(result, event)
		}
	}
	return result, nil
}

func (s *MemoryPreviewStore) RecordDecision(_ context.Context, handle string, approved bool, reason, actor string, selection, options proffer.Ref) error {
	if strings.TrimSpace(actor) == "" || strings.TrimSpace(string(selection)) == "" || strings.TrimSpace(string(options)) == "" {
		return errors.New("memory preview decision requires actor, selection, and options refs")
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	entry := s.entries[handle]
	if entry == nil {
		return ErrPreviewNotFound
	}
	if len(entry.projections) == 0 {
		return ErrPreviewNotReady
	}
	key := memoryDecisionKey(handle, approved, reason, actor, selection, options)
	if _, exists := entry.decisions[key]; exists {
		return nil
	}
	entry.binding.SelectionRef = selection
	entry.binding.ParserOptionsRef = options
	status := "rejected"
	if approved {
		status = "approved"
	}
	current := entry.projections[len(entry.projections)-1]
	successor := memoryPreviewProjection{
		snapshot:     clonePreviewSnapshot(current.snapshot),
		participants: clonePreviewParticipants(current.participants),
		messages:     clonePreviewMessages(current.messages),
	}
	successor.snapshot.Phase, successor.snapshot.Reason = status, strings.TrimSpace(reason)
	entry.projections = append(entry.projections, successor)
	entry.decisions[key] = struct{}{}
	entry.events = append(entry.events, PreviewEvent{
		EventID: int64(len(entry.events)), EventType: "decision_recorded", OccurredAt: time.Now().UTC(),
		PreviewHandle: handle, Phase: status, Detail: strings.TrimSpace(actor + ": " + reason),
	})
	return nil
}

// PutProjection is intentionally test/importer-only scaffolding. A durable
// PostgreSQL store will populate these same projections from receipt refs.
func (s *MemoryPreviewStore) PutProjection(handle string, snapshot PreviewSnapshot, participants []PreviewParticipant, messages []PreviewMessage, events []PreviewEvent) error {
	if err := previewmodel.Validate(handle, snapshot, participants, messages); err != nil {
		return err
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	entry := s.entries[handle]
	if entry == nil {
		return ErrPreviewNotFound
	}
	if snapshot.Correlation.RequestID != entry.binding.RequestID {
		return errors.New("preview projection request correlation does not match its server binding")
	}
	sort.SliceStable(messages, func(i, j int) bool { return messages[i].Ordinal < messages[j].Ordinal })
	if len(entry.projections) > 0 {
		current := entry.projections[len(entry.projections)-1].snapshot
		if current.Correlation.NormalizedGenerationID == snapshot.Correlation.NormalizedGenerationID {
			if current.PreviewDigest == snapshot.PreviewDigest {
				return nil
			}
			return errors.New("preview projection retry changed digest for the same normalized generation")
		}
	}
	for _, event := range events {
		if event.PreviewHandle != handle || event.EventID != int64(len(entry.events)) {
			return errors.New("preview events must be contiguous and handle-bound")
		}
	}
	entry.binding.SourceVersionID = snapshot.Correlation.SourceVersionID
	entry.binding.RawGenerationID = snapshot.Correlation.RawGenerationID
	entry.binding.NormalizedGenerationID = snapshot.Correlation.NormalizedGenerationID
	entry.projections = append(entry.projections, memoryPreviewProjection{
		snapshot:     clonePreviewSnapshot(snapshot),
		participants: clonePreviewParticipants(participants),
		messages:     clonePreviewMessages(messages),
	})
	for _, event := range events {
		entry.events = append(entry.events, event)
	}
	return nil
}

func memoryDecisionKey(handle string, approved bool, reason, actor string, selection, options proffer.Ref) [sha256.Size]byte {
	return sha256.Sum256([]byte(fmt.Sprintf("%s\x00%t\x00%s\x00%s\x00%s\x00%s", handle, approved, reason, actor, selection, options)))
}

func clonePreviewSnapshot(snapshot PreviewSnapshot) PreviewSnapshot {
	clone := snapshot
	clone.Receipts = append([]PreviewReceipt(nil), snapshot.Receipts...)
	clone.ActiveStages = append([]proffer.ActivityName(nil), snapshot.ActiveStages...)
	if snapshot.Parser != nil {
		parser := *snapshot.Parser
		clone.Parser = &parser
	}
	return clone
}

func clonePreviewParticipants(participants []PreviewParticipant) []PreviewParticipant {
	clone := append([]PreviewParticipant(nil), participants...)
	for index := range clone {
		if clone[index].CanonicalAddress != nil {
			value := *clone[index].CanonicalAddress
			clone[index].CanonicalAddress = &value
		}
	}
	return clone
}

func clonePreviewMessages(messages []PreviewMessage) []PreviewMessage {
	clone := append([]PreviewMessage(nil), messages...)
	for index := range clone {
		clone[index].ParticipantIDs = append([]string(nil), messages[index].ParticipantIDs...)
		clone[index].Attachments = append([]PreviewAttachment(nil), messages[index].Attachments...)
		for attachmentIndex := range clone[index].Attachments {
			attachment := &clone[index].Attachments[attachmentIndex]
			original := messages[index].Attachments[attachmentIndex]
			if original.Filename != nil {
				value := *original.Filename
				attachment.Filename = &value
			}
			if original.MediaType != nil {
				value := *original.MediaType
				attachment.MediaType = &value
			}
			if original.ByteLength != nil {
				value := *original.ByteLength
				attachment.ByteLength = &value
			}
			if original.SHA256 != nil {
				value := *original.SHA256
				attachment.SHA256 = &value
			}
		}
		if messages[index].SentAt != nil {
			value := *messages[index].SentAt
			clone[index].SentAt = &value
		}
		if messages[index].SenderParticipantID != nil {
			value := *messages[index].SenderParticipantID
			clone[index].SenderParticipantID = &value
		}
	}
	return clone
}

var receiptTypes = previewmodel.ReceiptTypes

// ValidatePreviewProjection is the shared fail-closed gate used by durable
// projection writers before any snapshot/message rows become visible.
func ValidatePreviewProjection(handle string, snapshot PreviewSnapshot, participants []PreviewParticipant, messages []PreviewMessage) error {
	return previewmodel.Validate(handle, snapshot, participants, messages)
}

type PreviewHTTPHandler struct {
	workflow         PreviewWorkflow
	store            PreviewStore
	repairs          RepairDecisionWriter
	handlerDecisions HandlerSelectionDecisionWriter
	cursorKey        []byte
	serviceTokenPath string
	sourceContext    sourcecontext.Validator
}

// OperationSummary is the browser-safe identity and lifecycle of one Proffer
// execution. Temporal workflow/run IDs stay behind the service boundary; the
// opaque preview handle is the only external operation key.
type OperationSummary struct {
	PreviewHandle       string                     `json:"preview_handle"`
	RequestID           string                     `json:"request_id"`
	SourceRef           proffer.Ref                `json:"source_ref"`
	Service             string                     `json:"service"`
	CreatedAt           time.Time                  `json:"created_at"`
	Lifecycle           proffer.OperationLifecycle `json:"lifecycle"`
	CurrentStage        proffer.ActivityName       `json:"current_stage,omitempty"`
	ActiveStages        []proffer.ActivityName     `json:"active_stages"`
	Wait                proffer.OperationWait      `json:"wait,omitempty"`
	Terminal            bool                       `json:"terminal"`
	Reason              string                     `json:"reason,omitempty"`
	SourceVersionRef    proffer.Ref                `json:"source_version_ref,omitempty"`
	CompletedStageCount int                        `json:"completed_stage_count"`
}

type OperationDetail struct {
	OperationSummary
	Stages []previewmodel.OperationStage `json:"stages"`
}

type OperationListResponse struct {
	Items      []OperationSummary `json:"items"`
	NextCursor *string            `json:"next_cursor,omitempty"`
}

func NewPreviewHTTPHandler(workflow PreviewWorkflow, store PreviewStore, repairs RepairDecisionWriter, handlerDecisions HandlerSelectionDecisionWriter, cursorKey []byte, serviceTokenPath string, validators ...sourcecontext.Validator) (*PreviewHTTPHandler, error) {
	if workflow == nil || store == nil || repairs == nil || handlerDecisions == nil {
		return nil, errors.New("proffer preview handler requires workflow, preview store, repair decision writer, and handler decision writer")
	}
	if len(cursorKey) < 32 {
		return nil, errors.New("proffer preview cursor key must be at least 32 bytes")
	}
	if _, err := loadServiceToken(serviceTokenPath); err != nil {
		return nil, err
	}
	if len(validators) > 1 {
		return nil, errors.New("proffer preview handler accepts at most one source context validator")
	}
	var validator sourcecontext.Validator
	if len(validators) == 1 {
		validator = validators[0]
	}
	return &PreviewHTTPHandler{workflow: workflow, store: store, repairs: repairs, handlerDecisions: handlerDecisions, cursorKey: append([]byte(nil), cursorKey...), serviceTokenPath: serviceTokenPath, sourceContext: validator}, nil
}

func (h *PreviewHTTPHandler) Routes() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("POST /reference-import/start", h.auth(h.start))
	mux.HandleFunc("GET /reference-import/operations", h.auth(h.operations))
	mux.HandleFunc("GET /reference-import/operations/{preview_handle}", h.auth(h.operation))
	mux.HandleFunc("GET /reference-import/previews/{preview_handle}", h.auth(h.snapshot))
	mux.HandleFunc("GET /reference-import/previews/{preview_handle}/messages", h.auth(h.messages))
	mux.HandleFunc("GET /reference-import/previews/{preview_handle}/events", h.auth(h.events))
	mux.HandleFunc("POST /reference-import/previews/{preview_handle}/decision", h.auth(h.decide))
	mux.HandleFunc("POST /reference-import/previews/{preview_handle}/repair-decision", h.auth(h.decideRepair))
	mux.HandleFunc("POST /reference-import/previews/{preview_handle}/handler-selection", h.auth(h.decideHandler))
	return mux
}

func (h *PreviewHTTPHandler) auth(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		host, _, err := net.SplitHostPort(strings.TrimSpace(r.RemoteAddr))
		ip := net.ParseIP(host).To4()
		serviceToken, tokenErr := loadServiceToken(h.serviceTokenPath)
		auth := strings.TrimSpace(r.Header.Get("Authorization"))
		provided := strings.TrimSpace(strings.TrimPrefix(auth, "Bearer "))
		trusted := tokenErr == nil && strings.HasPrefix(auth, "Bearer ") && hmac.Equal([]byte(provided), serviceToken)
		if err != nil || ip == nil || ip[0] != 100 || ip[1] < 64 || ip[1] > 127 || !trusted {
			previewError(w, http.StatusUnauthorized, errors.New("proffer preview tailnet authorization required"))
			return
		}
		w.Header().Set("Cache-Control", "no-store")
		w.Header().Set("X-Content-Type-Options", "nosniff")
		next(w, r)
	}
}

var serviceTokenPattern = regexp.MustCompile(`^[A-Za-z0-9._~+/\-]+={0,}$`)
var previewHandlePattern = regexp.MustCompile(`^[A-Za-z0-9_-]{32,128}$`)

func loadServiceToken(path string) ([]byte, error) {
	if path == "" || path != strings.TrimSpace(path) || !filepath.IsAbs(path) {
		return nil, errors.New("proffer preview service token path must be absolute")
	}
	info, err := os.Lstat(path)
	if err != nil {
		return nil, fmt.Errorf("read proffer preview service token: %w", err)
	}
	if !info.Mode().IsRegular() || info.Mode()&os.ModeSymlink != 0 || info.Size() < 32 || info.Size() > 4098 {
		return nil, errors.New("proffer preview service token must be a safe regular file of 32-4098 bytes")
	}
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()
	openedInfo, err := file.Stat()
	if err != nil || !openedInfo.Mode().IsRegular() || !os.SameFile(info, openedInfo) {
		return nil, errors.New("proffer preview service token changed or is not a regular file")
	}
	raw, err := io.ReadAll(io.LimitReader(file, 4099))
	if err != nil {
		return nil, err
	}
	if len(raw) < 32 || len(raw) > 4098 {
		return nil, errors.New("proffer preview service token raw length is invalid")
	}
	raw = bytes.TrimRight(raw, "\r\n")
	if len(raw) < 32 || len(raw) > 4096 || !utf8.Valid(raw) || bytes.IndexByte(raw, 0) >= 0 || !serviceTokenPattern.Match(raw) {
		return nil, errors.New("proffer preview service token is invalid")
	}
	return raw, nil
}

type previewStartRequest struct {
	RequestID, MatterID, CourtCaseID, SourceRef, DeclaredFormat, ParserOptionsRef, SourceContextRef string
}

func (r *previewStartRequest) UnmarshalJSON(data []byte) error {
	type wire struct {
		RequestID        string `json:"request_id"`
		MatterID         string `json:"matter_id"`
		CourtCaseID      string `json:"court_case_id"`
		SourceRef        string `json:"source_ref"`
		DeclaredFormat   string `json:"declared_format"`
		ParserOptionsRef string `json:"parser_options_ref"`
		SourceContextRef string `json:"source_context_ref"`
	}
	var value wire
	if err := json.Unmarshal(data, &value); err != nil {
		return err
	}
	*r = previewStartRequest{value.RequestID, value.MatterID, value.CourtCaseID, value.SourceRef, value.DeclaredFormat, value.ParserOptionsRef, value.SourceContextRef}
	return nil
}

func (h *PreviewHTTPHandler) start(w http.ResponseWriter, r *http.Request) {
	var req previewStartRequest
	if err := decodePreviewJSON(w, r, &req); err != nil {
		previewError(w, 400, err)
		return
	}
	if strings.TrimSpace(req.RequestID) == "" || strings.TrimSpace(req.SourceRef) == "" || strings.TrimSpace(req.DeclaredFormat) == "" || strings.TrimSpace(req.ParserOptionsRef) == "" {
		previewError(w, 400, errors.New("start request is incomplete"))
		return
	}
	if _, err := uuid.Parse(req.MatterID); err != nil {
		previewError(w, 400, errors.New("matter_id must be a UUID"))
		return
	}
	if _, err := uuid.Parse(req.CourtCaseID); err != nil {
		previewError(w, 400, errors.New("court_case_id must be a UUID"))
		return
	}
	if _, _, err := validateAuthorizedSourceRef(req.SourceRef); err != nil {
		previewError(w, http.StatusUnprocessableEntity, err)
		return
	}
	if req.SourceContextRef != "" {
		if _, err := uuid.Parse(req.SourceContextRef); err != nil {
			previewError(w, http.StatusUnprocessableEntity, errors.New("source_context_ref must be a UUID"))
			return
		}
		if h.sourceContext == nil {
			previewError(w, http.StatusServiceUnavailable, errors.New("source context validation is unavailable"))
			return
		}
		if err := h.sourceContext.ValidateSourceContext(r.Context(), req.SourceContextRef, req.RequestID, req.MatterID, req.CourtCaseID, req.SourceRef); err != nil {
			previewError(w, http.StatusUnprocessableEntity, err)
			return
		}
	}
	in := proffer.WorkflowInput{RequestID: req.RequestID, MatterID: req.MatterID, CourtCaseID: req.CourtCaseID, SourceRef: proffer.Ref(req.SourceRef), DeclaredFormat: req.DeclaredFormat, ParserOptionsRef: proffer.Ref(req.ParserOptionsRef), SourceContextRef: proffer.Ref(req.SourceContextRef)}
	workflowID, runID, err := h.workflow.Start(r.Context(), in)
	if err != nil {
		previewError(w, 422, err)
		return
	}
	binding, err := h.store.Create(r.Context(), PreviewBinding{RequestID: req.RequestID, SourceRef: in.SourceRef, WorkflowID: workflowID, RunID: runID, ParserOptionsRef: in.ParserOptionsRef})
	if err != nil {
		previewError(w, 503, err)
		return
	}
	previewJSON(w, 201, map[string]string{"preview_handle": binding.Handle})
}

func (h *PreviewHTTPHandler) snapshot(w http.ResponseWriter, r *http.Request) {
	handle := r.PathValue("preview_handle")
	binding, bindErr := h.store.Binding(r.Context(), handle)
	if bindErr != nil {
		h.storeError(w, bindErr)
		return
	}
	operation := h.readOperation(r.Context(), binding)
	snapshot, err := h.store.Snapshot(r.Context(), handle)
	if err != nil {
		if errors.Is(err, ErrPreviewNotReady) {
			state, queryErr := h.workflow.Preview(r.Context(), binding.WorkflowID)
			var assessment *proffer.RepairAssessmentView
			phase := string(operation.Lifecycle)
			if queryErr == nil {
				assessment = state.RepairAssessment
				phase = string(state.Phase)
			}
			previewJSON(w, http.StatusOK, struct {
				PreviewHandle            string                        `json:"preview_handle"`
				Phase                    string                        `json:"phase"`
				RepairAssessment         *proffer.RepairAssessmentView `json:"repair_assessment,omitempty"`
				Checkpoints              []proffer.PreviewCheckpoint   `json:"checkpoints,omitempty"`
				HandlerRecommendationRef proffer.Ref                   `json:"handler_recommendation_ref,omitempty"`
				DetectedFormat           string                        `json:"detected_format,omitempty"`
				DetectedFormatRef        proffer.Ref                   `json:"detected_format_ref,omitempty"`
				SignatureRef             proffer.Ref                   `json:"signature_ref,omitempty"`
				RecommendedHandler       *proffer.HandlerCandidate     `json:"recommended_handler,omitempty"`
				AlternativeHandlers      []proffer.HandlerCandidate    `json:"alternative_handlers,omitempty"`
				Lifecycle                proffer.OperationLifecycle    `json:"lifecycle"`
				CurrentStage             proffer.ActivityName          `json:"current_stage,omitempty"`
				ActiveStages             []proffer.ActivityName        `json:"active_stages"`
				Wait                     proffer.OperationWait         `json:"wait,omitempty"`
				Terminal                 bool                          `json:"terminal"`
				CompletedStages          int                           `json:"completed_stage_count"`
			}{handle, phase, assessment, state.Checkpoints, state.HandlerRecommendationRef,
				state.DetectedFormat, state.DetectedFormatRef, state.SignatureRef, state.RecommendedHandler, state.AlternativeHandlers,
				operation.Lifecycle,
				operation.CurrentStage, operation.ActiveStages, operation.Wait,
				operation.Terminal, operation.CompletedStageCount})
			return
		}
		h.storeError(w, err)
		return
	}
	applyOperationToSnapshot(&snapshot, operation)
	previewJSON(w, 200, snapshot)
}

func (h *PreviewHTTPHandler) operations(w http.ResponseWriter, r *http.Request) {
	limit := 50
	if raw := r.URL.Query().Get("limit"); raw != "" {
		value, err := strconv.Atoi(raw)
		if err != nil || value < 1 || value > maxOperationPage {
			previewError(w, http.StatusUnprocessableEntity, errors.New("limit must be between 1 and 100"))
			return
		}
		limit = value
	}
	status := proffer.OperationLifecycle(strings.TrimSpace(r.URL.Query().Get("status")))
	if status != "" && !validOperationLifecycle(status) {
		previewError(w, http.StatusUnprocessableEntity, errors.New("status is not a recognized operation lifecycle"))
		return
	}
	var cursor *previewmodel.BindingCursor
	if raw := r.URL.Query().Get("cursor"); raw != "" {
		decoded, err := h.decodeOperationCursor(raw)
		if err != nil {
			previewError(w, http.StatusUnprocessableEntity, err)
			return
		}
		cursor = &decoded
	}
	response := OperationListResponse{Items: []OperationSummary{}}
	var lastScanned *previewmodel.BindingCursor
	hasMore := false
	for scanned := 0; len(response.Items) < limit && scanned < maxOperationScan; {
		batchLimit := maxOperationPage
		page, err := h.store.ListBindings(r.Context(), cursor, batchLimit)
		if err != nil {
			previewError(w, http.StatusServiceUnavailable, err)
			return
		}
		if len(page.Bindings) == 0 {
			hasMore = false
			break
		}
		for index, binding := range page.Bindings {
			scanned++
			coordinate := previewmodel.BindingCursor{CreatedAt: binding.CreatedAt, Handle: binding.Handle}
			lastScanned = &coordinate
			operation := h.readOperation(r.Context(), binding)
			if status == "" || operation.Lifecycle == status {
				response.Items = append(response.Items, operation)
			}
			if len(response.Items) == limit || scanned == maxOperationScan {
				hasMore = index < len(page.Bindings)-1 || page.HasMore
				break
			}
		}
		if len(response.Items) == limit || scanned == maxOperationScan {
			break
		}
		if !page.HasMore {
			hasMore = false
			break
		}
		last := page.Bindings[len(page.Bindings)-1]
		cursor = &previewmodel.BindingCursor{CreatedAt: last.CreatedAt, Handle: last.Handle}
		hasMore = true
	}
	if hasMore && lastScanned != nil {
		encoded := h.encodeOperationCursor(*lastScanned)
		response.NextCursor = &encoded
	}
	previewJSON(w, http.StatusOK, response)
}

func (h *PreviewHTTPHandler) operation(w http.ResponseWriter, r *http.Request) {
	handle := r.PathValue("preview_handle")
	binding, err := h.store.Binding(r.Context(), handle)
	if err != nil {
		h.storeError(w, err)
		return
	}
	summary, queriedStages := h.readOperationState(r.Context(), binding)
	stages, err := h.store.OperationStages(r.Context(), handle)
	if err != nil {
		previewError(w, http.StatusServiceUnavailable, err)
		return
	}
	stages = mergeOperationStages(stages, queriedStages)
	previewJSON(w, http.StatusOK, OperationDetail{OperationSummary: summary, Stages: stages})
}

func (h *PreviewHTTPHandler) readOperation(ctx context.Context, binding PreviewBinding) OperationSummary {
	summary, _ := h.readOperationState(ctx, binding)
	return summary
}

func (h *PreviewHTTPHandler) readOperationState(ctx context.Context, binding PreviewBinding) (OperationSummary, []proffer.OperationStage) {
	state, err := h.workflow.Operation(ctx, binding.WorkflowID)
	if err != nil || !validOperationLifecycle(state.Lifecycle) {
		state = proffer.OperationState{
			Lifecycle:        proffer.OperationUnavailable,
			ActiveStages:     []proffer.ActivityName{},
			SourceVersionRef: proffer.Ref(binding.SourceVersionID.String()),
			Reason:           "durable workflow state is currently unavailable",
		}
		if binding.SourceVersionID == uuid.Nil {
			state.SourceVersionRef = ""
		}
	}
	if state.ActiveStages == nil {
		state.ActiveStages = []proffer.ActivityName{}
	}
	return OperationSummary{
		PreviewHandle: binding.Handle, RequestID: binding.RequestID, SourceRef: binding.SourceRef,
		Service: "proffer", CreatedAt: binding.CreatedAt, Lifecycle: state.Lifecycle,
		CurrentStage: state.CurrentStage, ActiveStages: state.ActiveStages, Wait: state.Wait,
		Terminal: state.Terminal, Reason: state.Reason, SourceVersionRef: state.SourceVersionRef,
		CompletedStageCount: state.CompletedStageCount,
	}, state.Stages
}

func applyOperationToSnapshot(snapshot *PreviewSnapshot, operation OperationSummary) {
	snapshot.Lifecycle = operation.Lifecycle
	snapshot.CurrentStage = operation.CurrentStage
	snapshot.ActiveStages = operation.ActiveStages
	snapshot.Wait = operation.Wait
	snapshot.Terminal = operation.Terminal
	snapshot.CompletedStageCount = operation.CompletedStageCount
}

func mergeOperationStages(durable []previewmodel.OperationStage, queried []proffer.OperationStage) []previewmodel.OperationStage {
	seen := make(map[string]bool, len(durable))
	for _, stage := range durable {
		seen[stage.Stage+"\x00"+stage.ReceiptRef] = true
	}
	for _, stage := range queried {
		key := string(stage.Stage) + "\x00" + string(stage.ReceiptRef)
		if seen[key] {
			continue
		}
		durable = append(durable, previewmodel.OperationStage{
			Stage: string(stage.Stage), Status: string(stage.Status), Ref: string(stage.Ref),
			ReceiptRef: string(stage.ReceiptRef), Reason: stage.Reason,
		})
	}
	if durable == nil {
		return []previewmodel.OperationStage{}
	}
	return durable
}

func validOperationLifecycle(value proffer.OperationLifecycle) bool {
	switch value {
	case proffer.OperationRunning, proffer.OperationAwaitingRepairDecision,
		proffer.OperationAwaitingPreviewDecision, proffer.OperationCompleted,
		proffer.OperationFailed, proffer.OperationUnavailable:
		return true
	default:
		return false
	}
}

func (h *PreviewHTTPHandler) encodeOperationCursor(cursor previewmodel.BindingCursor) string {
	payload := cursor.CreatedAt.UTC().Format(time.RFC3339Nano) + "\n" + cursor.Handle
	mac := hmac.New(sha256.New, h.cursorKey)
	_, _ = mac.Write([]byte("operations\n" + payload))
	return base64.RawURLEncoding.EncodeToString([]byte(payload + "\n" + hex.EncodeToString(mac.Sum(nil))))
}

func (h *PreviewHTTPHandler) decodeOperationCursor(cursor string) (previewmodel.BindingCursor, error) {
	decoded, err := base64.RawURLEncoding.DecodeString(cursor)
	if err != nil || len(decoded) > 1024 {
		return previewmodel.BindingCursor{}, errors.New("operation cursor is malformed")
	}
	parts := strings.Split(string(decoded), "\n")
	if len(parts) != 3 || !previewHandlePattern.MatchString(parts[1]) {
		return previewmodel.BindingCursor{}, errors.New("operation cursor is malformed")
	}
	payload := parts[0] + "\n" + parts[1]
	mac := hmac.New(sha256.New, h.cursorKey)
	_, _ = mac.Write([]byte("operations\n" + payload))
	actual, err := hex.DecodeString(parts[2])
	if err != nil || !hmac.Equal(actual, mac.Sum(nil)) {
		return previewmodel.BindingCursor{}, errors.New("operation cursor signature is invalid")
	}
	createdAt, err := time.Parse(time.RFC3339Nano, parts[0])
	if err != nil {
		return previewmodel.BindingCursor{}, errors.New("operation cursor time is invalid")
	}
	return previewmodel.BindingCursor{CreatedAt: createdAt, Handle: parts[1]}, nil
}

func (h *PreviewHTTPHandler) messages(w http.ResponseWriter, r *http.Request) {
	handle := r.PathValue("preview_handle")
	limit := 100
	if raw := r.URL.Query().Get("limit"); raw != "" {
		value, err := strconv.Atoi(raw)
		if err != nil || value < 1 || value > maxPreviewPage {
			previewError(w, 422, errors.New("limit must be between 1 and 250"))
			return
		}
		limit = value
	}
	offset := 0
	if raw := r.URL.Query().Get("cursor"); raw != "" {
		value, err := h.decodeCursor(handle, raw)
		if err != nil {
			previewError(w, 422, err)
			return
		}
		offset = value
	}
	page, err := h.store.Page(r.Context(), handle, offset, limit)
	if err != nil {
		h.storeError(w, err)
		return
	}
	var next *string
	if page.NextOffset != nil {
		encoded := h.encodeCursor(handle, *page.NextOffset)
		next = &encoded
	}
	previewJSON(w, 200, struct {
		PreviewHandle string               `json:"preview_handle"`
		Participants  []PreviewParticipant `json:"participants"`
		Messages      []PreviewMessage     `json:"messages"`
		NextCursor    *string              `json:"next_cursor,omitempty"`
	}{handle, page.Participants, page.Messages, next})
}

type previewDecisionRequest struct {
	Approved bool   `json:"approved"`
	Reason   string `json:"reason"`
}

func (h *PreviewHTTPHandler) decide(w http.ResponseWriter, r *http.Request) {
	handle := r.PathValue("preview_handle")
	var req previewDecisionRequest
	if err := decodePreviewJSON(w, r, &req); err != nil {
		previewError(w, 400, err)
		return
	}
	actor, _, err := authenticatedActor(r)
	if err != nil {
		previewError(w, http.StatusUnauthorized, err)
		return
	}
	if len(req.Reason) > maxReasonBytes || (!req.Approved && strings.TrimSpace(req.Reason) == "") {
		previewError(w, 422, errors.New("rejection requires a bounded reason"))
		return
	}
	binding, err := h.store.Binding(r.Context(), handle)
	if err != nil {
		h.storeError(w, err)
		return
	}
	if _, err := h.store.Snapshot(r.Context(), handle); err != nil {
		h.storeError(w, err)
		return
	}
	state, err := h.workflow.Preview(r.Context(), binding.WorkflowID)
	if err != nil {
		previewError(w, 422, err)
		return
	}
	if state.Phase != proffer.PhaseAwaitingDecision && state.Phase != proffer.PhaseRejected {
		previewError(w, 409, errors.New("workflow is not awaiting a preview decision"))
		return
	}
	selection, options := state.SelectRef, state.ParserOptionsRef
	decision := proffer.PreviewDecision{Approved: req.Approved, Reason: req.Reason, Decider: actor}
	if state.Phase == proffer.PhaseRejected && req.Approved && state.PreviewHandle == "" {
		if selection == binding.SelectionRef && options == binding.ParserOptionsRef {
			previewError(w, http.StatusConflict, errors.New("approval after rejection requires changed repair selection or options refs"))
			return
		}
		decision.RepairedSelectionRef = selection
		decision.RepairedParserOptionsRef = options
	}
	if err := h.store.RecordDecision(r.Context(), handle, req.Approved, req.Reason, actor, selection, options); err != nil {
		previewError(w, 503, err)
		return
	}
	if err := h.workflow.Decide(r.Context(), binding.WorkflowID, decision); err != nil {
		previewError(w, 422, err)
		return
	}
	status := "rejected"
	if req.Approved {
		status = "approved"
	}
	previewJSON(w, 200, map[string]string{"preview_handle": handle, "status": status})
}

type repairDecisionRequest struct {
	Approved    bool           `json:"approved"`
	ApplyRepair bool           `json:"apply_repair"`
	ToolID      string         `json:"tool_id"`
	ToolPayload map[string]any `json:"tool_payload"`
}

func (h *PreviewHTTPHandler) decideRepair(w http.ResponseWriter, r *http.Request) {
	handle := r.PathValue("preview_handle")
	var req repairDecisionRequest
	if err := decodePreviewJSON(w, r, &req); err != nil {
		previewError(w, http.StatusBadRequest, err)
		return
	}
	actor, _, err := authenticatedActor(r)
	if err != nil {
		previewError(w, http.StatusUnauthorized, err)
		return
	}
	idempotencyKey := strings.TrimSpace(r.Header.Get("Idempotency-Key"))
	if idempotencyKey == "" || len(idempotencyKey) > 256 {
		previewError(w, http.StatusBadRequest, errors.New("bounded Idempotency-Key is required"))
		return
	}
	binding, err := h.store.Binding(r.Context(), handle)
	if err != nil {
		h.storeError(w, err)
		return
	}
	state, err := h.workflow.Preview(r.Context(), binding.WorkflowID)
	if err != nil {
		previewError(w, http.StatusUnprocessableEntity, err)
		return
	}
	if state.Phase != proffer.PhaseAwaitingRepairDecision || state.SourceVersionRef == "" || state.RepairAssessmentRef == "" {
		previewError(w, http.StatusConflict, errors.New("workflow is not awaiting an identified repair decision"))
		return
	}
	decisionRef, err := h.repairs.PersistRepairDecision(r.Context(), proffer.RepairDecisionSpec{
		SourceVersionRef: state.SourceVersionRef, AssessmentRef: state.RepairAssessmentRef,
		ActorRef: proffer.Ref(actor), Approved: req.Approved, ApplyRepair: req.ApplyRepair,
		ToolID: strings.TrimSpace(req.ToolID), ToolPayload: nonNilPayload(req.ToolPayload),
		IdempotencyKey: "proffer:" + handle + ":" + idempotencyKey,
	})
	if err != nil {
		previewError(w, http.StatusUnprocessableEntity, err)
		return
	}
	if err := h.workflow.DecideRepair(r.Context(), binding.WorkflowID, proffer.RepairDecision{DecisionRef: decisionRef}); err != nil {
		previewError(w, http.StatusServiceUnavailable, err)
		return
	}
	previewJSON(w, http.StatusOK, map[string]string{"preview_handle": handle, "decision_ref": string(decisionRef), "status": "signaled"})
}

type handlerSelectionRequest struct {
	CompatibilityRef proffer.Ref `json:"compatibility_ref"`
}

func (h *PreviewHTTPHandler) decideHandler(w http.ResponseWriter, r *http.Request) {
	handle := r.PathValue("preview_handle")
	var req handlerSelectionRequest
	if err := decodePreviewJSON(w, r, &req); err != nil {
		previewError(w, http.StatusBadRequest, err)
		return
	}
	actor, _, err := authenticatedActor(r)
	if err != nil {
		previewError(w, http.StatusUnauthorized, err)
		return
	}
	if _, err := uuid.Parse(string(req.CompatibilityRef)); err != nil {
		previewError(w, http.StatusUnprocessableEntity, errors.New("compatibility_ref must be a UUID"))
		return
	}
	idempotencyKey := strings.TrimSpace(r.Header.Get("Idempotency-Key"))
	if idempotencyKey == "" || len(idempotencyKey) > 256 {
		previewError(w, http.StatusBadRequest, errors.New("bounded Idempotency-Key is required"))
		return
	}
	binding, err := h.store.Binding(r.Context(), handle)
	if err != nil {
		h.storeError(w, err)
		return
	}
	state, err := h.workflow.Preview(r.Context(), binding.WorkflowID)
	if err != nil {
		previewError(w, http.StatusUnprocessableEntity, err)
		return
	}
	if state.Phase != proffer.PhaseAwaitingHandlerSelection || state.SourceVersionRef == "" || state.HandlerRecommendationRef == "" || state.RecommendedHandler == nil {
		previewError(w, http.StatusConflict, errors.New("workflow is not awaiting an identified handler selection"))
		return
	}
	candidates := append([]proffer.HandlerCandidate{*state.RecommendedHandler}, state.AlternativeHandlers...)
	matched := false
	for _, candidate := range candidates {
		if candidate.CompatibilityRef == req.CompatibilityRef {
			matched = true
			break
		}
	}
	if !matched {
		previewError(w, http.StatusConflict, errors.New("compatibility_ref is not in the preview recommendation"))
		return
	}
	decisionRef, err := h.handlerDecisions.PersistHandlerSelectionDecision(
		r.Context(), state.SourceVersionRef, state.HandlerRecommendationRef, proffer.Ref(actor), req.CompatibilityRef,
		"proffer:"+handle+":"+idempotencyKey,
	)
	if err != nil {
		previewError(w, http.StatusUnprocessableEntity, err)
		return
	}
	if err := h.workflow.DecideHandler(r.Context(), binding.WorkflowID, proffer.HandlerSelectionDecision{DecisionRef: decisionRef}); err != nil {
		previewError(w, http.StatusServiceUnavailable, err)
		return
	}
	previewJSON(w, http.StatusOK, map[string]string{"preview_handle": handle, "decision_ref": string(decisionRef), "status": "signaled"})
}

func authenticatedActor(r *http.Request) (subjectUID, username string, err error) {
	subjectUID = strings.TrimSpace(r.Header.Get("X-authentik-uid"))
	username = strings.TrimSpace(r.Header.Get("X-authentik-username"))
	if subjectUID == "" || username == "" || len(subjectUID) > 512 || len(username) > 512 || strings.ContainsAny(subjectUID+username, "\x00\r\n") {
		return "", "", errors.New("Authentik actor headers are required")
	}
	return subjectUID, username, nil
}

func (h *PreviewHTTPHandler) events(w http.ResponseWriter, r *http.Request) {
	handle := r.PathValue("preview_handle")
	after := int64(-1)
	if raw := r.Header.Get("Last-Event-ID"); raw != "" {
		value, err := strconv.ParseInt(raw, 10, 64)
		if err != nil || value < 0 {
			previewError(w, 422, errors.New("Last-Event-ID must be a non-negative integer"))
			return
		}
		after = value
	}
	events, err := h.store.EventsAfter(r.Context(), handle, after)
	if err != nil {
		h.storeError(w, err)
		return
	}
	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-store")
	for _, event := range events {
		payload, _ := json.Marshal(event)
		_, _ = fmt.Fprintf(w, "id: %d\nevent: proffer.preview\ndata: %s\n\n", event.EventID, payload)
	}
}

func (h *PreviewHTTPHandler) encodeCursor(handle string, offset int) string {
	payload := fmt.Sprintf("%s:%d", handle, offset)
	mac := hmac.New(sha256.New, h.cursorKey)
	_, _ = mac.Write([]byte(payload))
	return base64.RawURLEncoding.EncodeToString([]byte(payload + ":" + hex.EncodeToString(mac.Sum(nil))))
}

func (h *PreviewHTTPHandler) decodeCursor(handle, cursor string) (int, error) {
	decoded, err := base64.RawURLEncoding.DecodeString(cursor)
	if err != nil || len(decoded) > 512 {
		return 0, errors.New("cursor is malformed")
	}
	parts := strings.Split(string(decoded), ":")
	if len(parts) != 3 || parts[0] != handle {
		return 0, errors.New("cursor does not belong to this preview")
	}
	payload := parts[0] + ":" + parts[1]
	mac := hmac.New(sha256.New, h.cursorKey)
	_, _ = mac.Write([]byte(payload))
	actual, err := hex.DecodeString(parts[2])
	if err != nil || !hmac.Equal(actual, mac.Sum(nil)) {
		return 0, errors.New("cursor signature is invalid")
	}
	offset, err := strconv.Atoi(parts[1])
	if err != nil || offset < 0 {
		return 0, errors.New("cursor offset is invalid")
	}
	return offset, nil
}

func (h *PreviewHTTPHandler) storeError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, ErrPreviewNotFound):
		previewError(w, 404, err)
	case errors.Is(err, ErrPreviewNotReady):
		previewError(w, 409, err)
	case errors.Is(err, ErrPreviewEventGap):
		previewError(w, 409, err)
	default:
		previewError(w, 503, err)
	}
}

func decodePreviewJSON(w http.ResponseWriter, r *http.Request, dest any) error {
	decoder := json.NewDecoder(http.MaxBytesReader(w, r.Body, maxPreviewRequestBytes))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(dest); err != nil {
		return err
	}
	var trailing any
	if err := decoder.Decode(&trailing); !errors.Is(err, io.EOF) {
		if err == nil {
			return errors.New("request must contain exactly one JSON object")
		}
		return err
	}
	return nil
}

// nonNilPayload guarantees a use-original decision persists `{}` rather than
// `null`: encoding/json renders a nil map as null, which violates
// context.repair_decision_check (live 2026-09-05, first decision on
// rehearsal-20260905-r2e-1788612588 returned 422 until tool_payload was sent
// explicitly as {}).
func nonNilPayload(payload map[string]any) map[string]any {
	if payload == nil {
		return map[string]any{}
	}
	return payload
}

func previewJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}
func previewError(w http.ResponseWriter, status int, err error) {
	previewJSON(w, status, map[string]string{"detail": err.Error()})
}
