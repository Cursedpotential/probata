package proffer

import (
	"errors"
	"fmt"
	"strings"
)

// HandlerSelectionDecisionSignalName carries only the durable, actor-bound
// decision reference. The authenticated HTTP surface persists the operator's
// choice before it signals Temporal; handler identity and reasons are loaded
// and checked by ValidateHandlerSelectionActivityName.
const HandlerSelectionDecisionSignalName = "handler_selection_decision"

const (
	RecommendHandlerActivityName         = "recommend_handler_activity"
	ValidateHandlerSelectionActivityName = "validate_handler_selection_activity"
)

// HandlerExecutionPath identifies the one paired select/execute
// implementation that may run after validation. It is bounded control data,
// never inferred from a filename or supplied directly by the browser.
type HandlerExecutionPath string

const (
	HandlerPathDecoder HandlerExecutionPath = "decoder"
	HandlerPathDuckDB  HandlerExecutionPath = "duckdb"
)

const maxCompatibleAlternatives = 3

// HandlerCandidate is a registered implementation proven compatible with the
// detected content signature. CompatibilityRef points to the durable registry
// determination; Reason is concise operator-facing rationale.
type HandlerCandidate struct {
	HandlerID        string               `json:"handler_id"`
	HandlerVersion   string               `json:"handler_version"`
	ExecutionPath    HandlerExecutionPath `json:"execution_path"`
	CompatibilityRef Ref                  `json:"compatibility_ref"`
	Reason           string               `json:"reason"`
}

// HandlerRecommendationResult is the compact output of content inspection.
// Declared filename/extension metadata may inform diagnostics, but may not
// populate these fields by itself. DetectedFormatRef and SignatureRef make the
// content-backed determination durable and independently reviewable.
type HandlerRecommendationResult struct {
	RecommendationRef Ref                `json:"recommendation_ref"`
	ReceiptRef        Ref                `json:"receipt_ref"`
	DetectedFormat    string             `json:"detected_format"`
	DetectedFormatRef Ref                `json:"detected_format_ref"`
	SignatureRef      Ref                `json:"signature_ref"`
	Recommended       HandlerCandidate   `json:"recommended"`
	Alternatives      []HandlerCandidate `json:"alternatives,omitempty"`
}

// HandlerSelectionDecision is the reference-only Temporal Signal payload.
// The referenced record must identify the authenticated actor, recommendation
// revision, and chosen candidate. None of those assertions are trusted from a
// browser payload or duplicated into Temporal history.
type HandlerSelectionDecision struct {
	DecisionRef Ref `json:"decision_ref"`
}

// HandlerSelectionValidationResult is returned only after the validation
// Activity has loaded the durable decision, verified its actor binding, and
// proved the chosen handler is still a member of the recommendation's bounded
// compatible set. SelectionRef is deliberately absent: the chosen path's own
// Select implementation persists the canonical parser selection next.
type HandlerSelectionValidationResult struct {
	DecisionRef       Ref              `json:"decision_ref"`
	ActorRef          Ref              `json:"actor_ref"`
	ValidationReceipt Ref              `json:"validation_receipt_ref"`
	RecommendationRef Ref              `json:"recommendation_ref"`
	DetectedFormat    string           `json:"detected_format"`
	DetectedFormatRef Ref              `json:"detected_format_ref"`
	SignatureRef      Ref              `json:"signature_ref"`
	Chosen            HandlerCandidate `json:"chosen"`
}

func validateHandlerRecommendation(result HandlerRecommendationResult) error {
	if result.RecommendationRef == "" || result.ReceiptRef == "" || result.DetectedFormatRef == "" || result.SignatureRef == "" {
		return errors.New("handler recommendation lacks a durable recommendation, receipt, detected-format, or signature reference")
	}
	if strings.TrimSpace(result.DetectedFormat) == "" {
		return errors.New("handler recommendation lacks a detected format")
	}
	if len(result.Alternatives) > maxCompatibleAlternatives {
		return fmt.Errorf("handler recommendation has %d alternatives; maximum is %d", len(result.Alternatives), maxCompatibleAlternatives)
	}
	seen := make(map[string]struct{}, 1+len(result.Alternatives))
	for index, candidate := range append([]HandlerCandidate{result.Recommended}, result.Alternatives...) {
		if err := validateHandlerCandidate(candidate); err != nil {
			return fmt.Errorf("handler recommendation candidate %d: %w", index, err)
		}
		key := handlerCandidateKey(candidate)
		if _, duplicate := seen[key]; duplicate {
			return fmt.Errorf("handler recommendation repeats candidate %q", key)
		}
		seen[key] = struct{}{}
	}
	return nil
}

func validateHandlerCandidate(candidate HandlerCandidate) error {
	if strings.TrimSpace(candidate.HandlerID) == "" || strings.TrimSpace(candidate.HandlerVersion) == "" {
		return errors.New("handler id and version are required")
	}
	if candidate.ExecutionPath != HandlerPathDecoder && candidate.ExecutionPath != HandlerPathDuckDB {
		return fmt.Errorf("unsupported execution path %q", candidate.ExecutionPath)
	}
	if candidate.CompatibilityRef == "" || strings.TrimSpace(candidate.Reason) == "" {
		return errors.New("compatibility reference and reason are required")
	}
	return nil
}

func validateHandlerSelection(recommendation HandlerRecommendationResult, decisionRef Ref, result HandlerSelectionValidationResult) error {
	if decisionRef == "" || result.DecisionRef != decisionRef {
		return errors.New("handler selection validation does not match the signaled decision reference")
	}
	if result.ActorRef == "" || result.ValidationReceipt == "" {
		return errors.New("handler selection validation lacks actor or receipt reference")
	}
	if result.RecommendationRef != recommendation.RecommendationRef || result.DetectedFormat != recommendation.DetectedFormat ||
		result.DetectedFormatRef != recommendation.DetectedFormatRef || result.SignatureRef != recommendation.SignatureRef {
		return errors.New("handler selection validation does not match the durable content recommendation")
	}
	if err := validateHandlerCandidate(result.Chosen); err != nil {
		return fmt.Errorf("validated chosen handler: %w", err)
	}
	for _, candidate := range append([]HandlerCandidate{recommendation.Recommended}, recommendation.Alternatives...) {
		if handlerCandidatesEqual(candidate, result.Chosen) {
			return nil
		}
	}
	return errors.New("chosen handler is not in the bounded compatible recommendation set")
}

func handlerCandidateKey(candidate HandlerCandidate) string {
	return strings.Join([]string{candidate.HandlerID, candidate.HandlerVersion, string(candidate.ExecutionPath)}, "\x00")
}

func handlerCandidatesEqual(left, right HandlerCandidate) bool {
	return left.HandlerID == right.HandlerID && left.HandlerVersion == right.HandlerVersion &&
		left.ExecutionPath == right.ExecutionPath && left.CompatibilityRef == right.CompatibilityRef
}
