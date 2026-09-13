package proffer

import "time"

// PreviewDecisionSignalName is the Signal ProfferWorkflow listens on
// between select_parser_activity and execute_parser_activity: a human
// operator's approve/reject decision on the persisted parser selection.
// This is a real Temporal Signal, not an Activity-level trick, precisely so
// the hold survives a worker restart or a replica change — Temporal replays
// this workflow's own durable history, not any single worker's in-memory
// state.
const PreviewDecisionSignalName = "preview_decision"

const RepairDecisionSignalName = "repair_decision"

// PreviewQueryName is the Query a caller uses to read the current hold state
// (see PreviewState) while ProfferWorkflow is waiting on
// PreviewDecisionSignalName. Queries, like Signals, are served from the
// workflow's own history/state and work against any worker, and even after
// the workflow has closed (within retention).
const PreviewQueryName = "preview"

// previewDecisionTimeout bounds how long the hold waits for
// PreviewDecisionSignalName before failing the run closed. This is a real
// Temporal Timer (workflow.NewTimer), backed by the Temporal server itself —
// not bounded by any Activity's StartToCloseTimeout — so it is independent
// of engine/proffer/options.go's per-stage Activity timeouts.
const previewDecisionTimeout = 24 * time.Hour

// PreviewPhase is the human-readable lifecycle position of the preview
// hold, as reported by PreviewState.
type PreviewPhase string

const (
	PhaseStarting                 PreviewPhase = "starting"
	PhaseAwaitingHandlerSelection PreviewPhase = "awaiting_handler_selection"
	PhaseHandlerSelected          PreviewPhase = "handler_selected"
	PhaseAwaitingDecision         PreviewPhase = "awaiting_decision"
	PhaseAwaitingRepairDecision   PreviewPhase = "awaiting_repair_decision"
	PhaseRepairApproved           PreviewPhase = "repair_approved"
	PhaseApproved                 PreviewPhase = "approved"
	PhaseRejected                 PreviewPhase = "rejected"
	PhaseTimedOut                 PreviewPhase = "timed_out"
)

// PreviewDecision is the human operator's approve/reject input, sent as
// PreviewDecisionSignalName's payload.
type PreviewDecision struct {
	Approved                 bool   `json:"approved"`
	Reason                   string `json:"reason,omitempty"`
	Decider                  string `json:"decider"`
	RepairedSelectionRef     Ref    `json:"repaired_selection_ref,omitempty"`
	RepairedParserOptionsRef Ref    `json:"repaired_parser_options_ref,omitempty"`
}

// RepairDecision contains only the durable decision registry. The HTTP
// surface persists the authenticated actor-bound decision before signaling.
type RepairDecision struct {
	DecisionRef Ref `json:"decision_ref"`
}

type RepairDecisionSpec struct {
	SourceVersionRef Ref            `json:"source_version_ref"`
	AssessmentRef    Ref            `json:"assessment_ref"`
	ActorRef         Ref            `json:"actor_ref"`
	Approved         bool           `json:"approved"`
	ApplyRepair      bool           `json:"apply_repair"`
	ToolID           string         `json:"tool_id,omitempty"`
	ToolPayload      map[string]any `json:"tool_payload,omitempty"`
	IdempotencyKey   string         `json:"idempotency_key"`
}

// PreviewState is PreviewQueryName's response: what select_parser_activity
// produced (SelectRef) and where the hold currently stands.
type PreviewState struct {
	Phase                    PreviewPhase          `json:"phase"`
	PreviewHandle            Ref                   `json:"preview_handle,omitempty"`
	SourceVersionRef         Ref                   `json:"source_version_ref,omitempty"`
	RepairAssessmentRef      Ref                   `json:"repair_assessment_ref,omitempty"`
	SelectRef                Ref                   `json:"select_ref"`
	ParserOptionsRef         Ref                   `json:"parser_options_ref,omitempty"`
	Reason                   string                `json:"reason,omitempty"`
	RepairAssessment         *RepairAssessmentView `json:"repair_assessment,omitempty"`
	Checkpoints              []PreviewCheckpoint   `json:"checkpoints,omitempty"`
	HandlerRecommendationRef Ref                   `json:"handler_recommendation_ref,omitempty"`
	HandlerDecisionRef       Ref                   `json:"handler_decision_ref,omitempty"`
	DetectedFormat           string                `json:"detected_format,omitempty"`
	DetectedFormatRef        Ref                   `json:"detected_format_ref,omitempty"`
	SignatureRef             Ref                   `json:"signature_ref,omitempty"`
	RecommendedHandler       *HandlerCandidate     `json:"recommended_handler,omitempty"`
	AlternativeHandlers      []HandlerCandidate    `json:"alternative_handlers,omitempty"`
}

// PreviewCheckpointStatus is the live, context-only progress of one of the
// six import checkpoints shown before the full normalized preview is ready.
// These statuses are operational intake state, not evidence custody or a
// promotion decision.
type PreviewCheckpointStatus string

const (
	CheckpointPending   PreviewCheckpointStatus = "pending"
	CheckpointRunning   PreviewCheckpointStatus = "running"
	CheckpointCompleted PreviewCheckpointStatus = "completed"
	CheckpointFailed    PreviewCheckpointStatus = "failed"
)

// PreviewCheckpoint is intentionally compact enough to live in Temporal
// workflow state. The full preview remains gated until PublishPreview; this
// only reports stage status and the durable receipt once one exists.
type PreviewCheckpoint struct {
	Checkpoint string                  `json:"checkpoint"`
	Status     PreviewCheckpointStatus `json:"status"`
	ReceiptRef Ref                     `json:"receipt_ref,omitempty"`
	Reason     string                  `json:"reason,omitempty"`
}

func newPreviewCheckpoints(enabled bool) []PreviewCheckpoint {
	if !enabled {
		return nil
	}
	return []PreviewCheckpoint{
		{Checkpoint: "raw_source_verification", Status: CheckpointPending},
		{Checkpoint: "parser_selection", Status: CheckpointPending},
		{Checkpoint: "parser_execution", Status: CheckpointPending},
		{Checkpoint: "normalization", Status: CheckpointPending},
		{Checkpoint: "storage", Status: CheckpointPending},
		{Checkpoint: "completeness", Status: CheckpointPending},
	}
}

func (s *PreviewState) setCheckpoint(checkpoint string, status PreviewCheckpointStatus, receipt Ref, reason string) {
	for index := range s.Checkpoints {
		if s.Checkpoints[index].Checkpoint != checkpoint {
			continue
		}
		s.Checkpoints[index].Status = status
		s.Checkpoints[index].ReceiptRef = receipt
		s.Checkpoints[index].Reason = reason
		return
	}
}

// RepairAssessmentView is the reference-only human-gate projection. Detailed
// detector output remains in PostgreSQL and never enters Temporal history.
type RepairAssessmentView struct {
	AssessmentRef    Ref  `json:"assessment_ref"`
	SourceVersionRef Ref  `json:"source_version_ref"`
	ReviewRequired   bool `json:"review_required"`
}
