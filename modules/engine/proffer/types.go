// Package proffer implements ProfferWorkflow, the single Temporal
// workflow every source — every format, client, and entrypoint — runs
// through, per
// docs/reviews/2026-08-25-schema-audit/SBV-GO-TEMPORAL-RUNTIME-BOUNDARY.html
// (Lane C). It orchestrates the exact stage graph locked in
// engine/stagegraph and does not implement any Activity body: Activities are
// invoked by their canon name and are registered by whichever worker lands
// in a later lane, per the boundary document's lane table (Lane C depends on
// Lane A contracts and Lane B PostgreSQL interfaces; it does not provide
// them).
//
// Package proffer (formerly uiw / Universal Import Workflow; renamed D-140, 2026-09-05).
package proffer

import (
	"fmt"
	"strings"

	"github.com/Cursedpotential/probata/engine/stagegraph"
)

// ActivityName is the Temporal-registered name for one Activity in
// ProfferWorkflow. It is always identical to the canon StageID from
// engine/stagegraph, so the orchestration graph in workflow.go and the
// Temporal task-dispatch table can never drift apart.
type ActivityName = stagegraph.StageID

// Ref is a compact opaque pointer into external storage — a PostgreSQL row
// id, an immutable-object-storage key, or a receipt id. A Ref is never a
// payload. Per the boundary document's acceptance gate 6 ("Temporal history
// contains compact references only"), nothing in this package may carry a
// file, a raw record, a normalized record, or a metadata payload — those
// stay in PostgreSQL/immutable storage and Activities resolve them by
// following the Refs handed across the workflow boundary.
type Ref string

// PreviewPublicationRequest is the compact reference-only payload used by
// publish_preview_activity. Workflow and run identifiers stay in the durable
// preview binding created by the starter and are never exposed as the browser
// handle.
type PreviewPublicationRequest struct {
	RequestID               string         `json:"request_id"`
	PackageRef              Ref            `json:"package_ref,omitempty"`
	AttemptRef              Ref            `json:"attempt_ref,omitempty"`
	SourceVersionRef        Ref            `json:"source_version_ref"`
	SourceRepresentationRef Ref            `json:"source_representation_ref,omitempty"`
	RawGenerationRef        Ref            `json:"raw_generation_ref"`
	NormalizedGenerationRef Ref            `json:"normalized_generation_ref"`
	ChunkGenerationRef      Ref            `json:"chunk_generation_ref,omitempty"`
	ChunkReceiptRef         Ref            `json:"chunk_receipt_ref,omitempty"`
	ParserSelectionRef      Ref            `json:"parser_selection_ref"`
	ParserOptionsRef        Ref            `json:"parser_options_ref"`
	ReceiptRefs             map[string]Ref `json:"receipt_refs"`
}

// ContextChunkingInput opts a non-messaging package into the D-158 context
// chunk path. It contains only opaque references and short, version-pinned
// controlled-vocabulary identifiers. Source bytes, extracted records, chunk
// text, and parser/template bodies never enter Temporal history.
//
// Messaging imports leave the corresponding WorkflowInput fields empty and
// preserve the existing normalized-message preview path. A caller must not
// use this as a generic "chunk every import" flag: message chunking has its
// own ordered-record contract.
type ContextChunkingInput struct {
	PackageRef    Ref
	AttemptRef    Ref
	ContextKind   string
	Signature     string
	PolicyID      string
	PolicyVersion string
}

func (in ContextChunkingInput) validate() error {
	if in.PackageRef == "" || in.AttemptRef == "" {
		return fmt.Errorf("non-messaging context chunking requires package and extraction-attempt references")
	}
	if in.ContextKind != "non_messaging" {
		return fmt.Errorf("context chunking requires context kind %q", "non_messaging")
	}
	for name, value := range map[string]string{
		"signature":      in.Signature,
		"policy id":      in.PolicyID,
		"policy version": in.PolicyVersion,
	} {
		trimmed := strings.TrimSpace(value)
		if trimmed == "" {
			return fmt.Errorf("non-messaging context chunking requires %s", name)
		}
		if len(trimmed) > 256 {
			return fmt.Errorf("non-messaging context chunking %s exceeds 256 bytes", name)
		}
	}
	return nil
}

// Status is the recorded business outcome of one stage. success and
// not_applicable are both valid terminal states that let the workflow
// proceed to the stage's dependents; failed halts every descendant and the
// seal/publish stages, per the boundary document's per-Activity contract.
type Status string

const (
	StatusSuccess       Status = "success"
	StatusNotApplicable Status = "not_applicable"
	StatusFailed        Status = "failed"
)

// WorkflowInput starts ProfferWorkflow. It names the not-yet-
// retained acquisition object and the client idempotency coordinate;
// register_source_activity (stage 1) turns SourceRef into the durable
// source/version reference every later stage keys off.
type WorkflowInput struct {
	// RequestID is the client-supplied idempotency key. Callers are expected
	// to use it as the Temporal workflow ID so a duplicate submission joins
	// the existing run rather than starting a second one. It is also carried
	// on every StageRequest (see StageRequest.RequestID) so an Activity can
	// key its own idempotency/dedup checks off the same coordinate the
	// workflow itself uses.
	RequestID   string
	MatterID    string
	CourtCaseID string
	// SourceRef points at the not-yet-retained acquisition object (upload,
	// watcher-discovered file, or other external pointer). It is never the
	// bytes themselves.
	SourceRef Ref
	// DeclaredFormat is the short format tag from the boundary document's
	// ParserInput contract (section 3), e.g. "whatsapp_export_json". It is
	// an identifier, never file content.
	DeclaredFormat string
	// ParserOptionsRef is the ParserInput.parser_options_ref: a reference to
	// parser configuration, not the configuration payload itself.
	ParserOptionsRef Ref
	// SourceContextRef points to the append-only, actor-bound operator
	// assertion receipt. Metadata values never enter Temporal history.
	SourceContextRef Ref
	// The context-chunk fields enable the D-158 non-messaging context path.
	// Empty fields preserve the established messaging path. The flat wire
	// shape deliberately uses only Refs and bounded strings.
	PackageRef                Ref
	AttemptRef                Ref
	ContextKind               string
	ContextChunkSignature     string
	ContextChunkPolicyID      string
	ContextChunkPolicyVersion string
}

func (in WorkflowInput) contextChunkingInput() *ContextChunkingInput {
	if in.PackageRef == "" && in.AttemptRef == "" && strings.TrimSpace(in.ContextKind) == "" &&
		strings.TrimSpace(in.ContextChunkSignature) == "" && strings.TrimSpace(in.ContextChunkPolicyID) == "" &&
		strings.TrimSpace(in.ContextChunkPolicyVersion) == "" {
		return nil
	}
	return &ContextChunkingInput{
		PackageRef: in.PackageRef, AttemptRef: in.AttemptRef, ContextKind: strings.TrimSpace(in.ContextKind),
		Signature: strings.TrimSpace(in.ContextChunkSignature), PolicyID: strings.TrimSpace(in.ContextChunkPolicyID),
		PolicyVersion: strings.TrimSpace(in.ContextChunkPolicyVersion),
	}
}

// StageRequest is the single compact wire type sent to every Activity: the
// running source/version reference, the declared-format tag, and whichever
// named upstream references that stage's contract declares as inputs.
// Activities resolve anything else they need (file bytes, records,
// metadata) from PostgreSQL/immutable storage by following these
// references — never from the workflow payload.
type StageRequest struct {
	// RequestID is WorkflowInput.RequestID, propagated to every Activity
	// invocation (not just register_source_activity) so any Activity can
	// key its own idempotency/dedup checks off the same client-supplied
	// coordinate the workflow uses as its Temporal workflow ID.
	RequestID        string
	MatterID         string
	CourtCaseID      string
	SourceVersionRef Ref
	DeclaredFormat   string
	// Refs is a small, named set of upstream references this stage
	// consumes, e.g. {"original": ..., "raw_generation": ...}. Keys are
	// stable, documented names, not row content.
	Refs map[string]Ref
}

// StageResult is the single compact wire type every Activity returns. Every
// terminal Status (success, not_applicable, or a business-reported failed)
// must carry a durable ReceiptRef; see validateStageResult in workflow.go for
// the exact per-Status contract this type's fields are held to.
type StageResult struct {
	Stage ActivityName
	// Status is the business outcome; see the Status constants.
	Status Status
	// Ref is this stage's compact usable result registry. Required (must be
	// non-empty) when Status is StatusSuccess. Always empty for
	// StatusFailed — a business failure has nothing usable to hand
	// downstream, only a receipt of the outcome. For StatusNotApplicable,
	// Ref is usually empty but MAY carry a durable reference when one
	// genuinely exists (e.g. reconcile_byte_coverage_activity recording a
	// "no byte coverage to reconcile" marker). When present it propagates to
	// dependent stages exactly like a success Ref. When absent, settle uses
	// the required ReceiptRef as the compact downstream dependency Ref while
	// preserving this StageResult exactly as returned. Thus a later stage can
	// cite the durable N/A determination instead of receiving an empty string
	// indistinguishable from "nothing recorded at all."
	Ref Ref
	// ReceiptRef is this stage's durable receipt reference — proof the
	// stage's outcome was recorded, independent of Ref. Required (must be
	// non-empty) for every terminal Status: StatusSuccess,
	// StatusNotApplicable, and a business-reported StatusFailed all
	// certify something happened and must be provable after the fact. It is
	// never populated when Get returns a Temporal execution error, because
	// the Activity may have crashed before producing any receipt at all.
	ReceiptRef Ref
	// Reason is required (must be non-empty) when Status is not
	// StatusSuccess: a short, operator-facing explanation. It is never a
	// payload.
	Reason string
}

// WorkflowResult is the terminal, compact summary of one workflow
// execution.
type WorkflowResult struct {
	SourceVersionRef Ref
	// PublicationRef is publish_generation_activity's receipt. Empty unless
	// Status is StatusSuccess.
	PublicationRef Ref
	Status         Status
	// Stages is the ordered receipt of every stage that actually ran, in
	// the order its result was recorded. A failed run's Stages ends at the
	// first failure; no descendant or seal/publish receipt follows it.
	Stages []StageResult
}
