// Package activities: this file owns chunk_document_activity only. Under the
// D-158 non-messaging context route it chunks the retained source
// representation selected for one immutable extraction attempt. It runs only
// after the workflow has verified extraction/normalization and never parses,
// normalizes, reconciles, publishes, or creates evidence/custody state.
package activities

import (
	"context"
	"errors"
	"fmt"
	"strings"

	"github.com/Cursedpotential/probata/engine/chunk"
	"github.com/Cursedpotential/probata/engine/proffer"
	"github.com/Cursedpotential/probata/engine/stagegraph"
)

// Content-chunk derivation modes, matching working.content_chunk's
// derivation_mode CHECK constraint exactly. Only DerivationModeVerbatimSpan
// is implemented: engine/chunk's registered document-markdown chunker always
// emits Chunk.Text as an exact Source[ByteStart:ByteEnd] slice (proven by
// chunk.Result.Validate), never a composed or unverified derivation. A
// caller requesting either of the other two modes fails closed rather than
// silently being downgraded to verbatim_span.
const (
	DerivationModeVerbatimSpan      = "verbatim_span"
	DerivationModeComposed          = "composed"
	DerivationModeUnverifiedDerived = "unverified_derived"
)

// ChunkDocumentSpec is the compact, already-resolved input to
// chunk_document_activity, built from proffer.StageRequest by
// chunkDocumentSpecFrom. SourceRepresentationRef names the retained
// original/member/derived object used for this exact extraction attempt.
// Signature selects the chunk.Registry variant.
type ChunkDocumentSpec struct {
	RequestID                 string
	Attempt                   int32
	PackageRef                proffer.Ref
	ExtractionAttemptRef      proffer.Ref
	SourceVersionRef          proffer.Ref
	SourceRepresentationRef   proffer.Ref
	NormalizedGenerationRef   proffer.Ref
	NormalizedVerificationRef proffer.Ref
	Signature                 chunk.Signature
	DerivationMode            string
	PolicyID                  string
	PolicyVersion             string
}

func (s ChunkDocumentSpec) validate() error {
	if strings.TrimSpace(s.RequestID) == "" || s.PackageRef == "" || s.ExtractionAttemptRef == "" ||
		s.SourceVersionRef == "" || s.SourceRepresentationRef == "" || s.NormalizedGenerationRef == "" || s.NormalizedVerificationRef == "" {
		return fmt.Errorf("%s requires request, package, extraction-attempt, source, representation, normalized-generation, and verification references", stagegraph.ChunkDocument)
	}
	if s.Attempt < 1 {
		return fmt.Errorf("%s attempt must be positive", stagegraph.ChunkDocument)
	}
	if err := s.Signature.Validate(); err != nil {
		return fmt.Errorf("%s: %w", stagegraph.ChunkDocument, err)
	}
	if s.DerivationMode != DerivationModeVerbatimSpan {
		return fmt.Errorf("%s: unsupported derivation mode %q, only %q is implemented", stagegraph.ChunkDocument, s.DerivationMode, DerivationModeVerbatimSpan)
	}
	if strings.TrimSpace(s.PolicyID) == "" || strings.TrimSpace(s.PolicyVersion) == "" {
		return fmt.Errorf("%s requires policy id and version", stagegraph.ChunkDocument)
	}
	return nil
}

// ChunkGenerationOutcome is the durable result of one chunk_document_activity
// attempt — literally the {generation ref, chunk_count, reassembly verified}
// tuple this Activity is specified to return. It is the return value of
// ChunkRepository.PersistChunkGeneration (a plain Go call, not a Temporal
// wire type); ChunkActivities.ChunkDocument flattens it into the canon
// proffer.StageResult (Ref + ReceiptRef) that every other Activity in this
// codebase returns, so a future gated workflow branch can invoke it through
// the existing r.exec helper unchanged. ChunkCount and ReassemblyVerified
// remain fully durable and independently queryable via that Ref:
// working.content_chunk_generation.chunk_count and
// working.content_chunk_reassembly_receipt.verification_result.
type ChunkGenerationOutcome struct {
	GenerationRef      proffer.Ref
	ReceiptRef         proffer.Ref
	ChunkCount         int64
	ReassemblyVerified bool
}

// ChunkRepository is the PostgreSQL storage boundary for
// chunk_document_activity. ResolveSourceRepresentation reads the exact bytes to chunk;
// PersistChunkGeneration is the only write. Implementations must make
// PersistChunkGeneration retry-safe using context.activity_execution and
// context.activity_receipt, exactly like every other repository in this
// package: a repeated idempotency coordinate returns the existing durable
// outcome rather than writing a second time.
type ChunkRepository interface {
	ResolveSourceRepresentation(context.Context, ChunkDocumentSpec) ([]byte, error)
	PersistChunkGeneration(context.Context, ChunkDocumentSpec, chunk.Result) (ChunkGenerationOutcome, error)
}

// ChunkActivities implements chunk_document_activity. Registry is the
// injected chunk-stage coordinator (engine/chunk.Registry) — computation —
// kept explicit and separate from Repository — storage — exactly like
// NormalizedPipelineActivities separates its Normalizer from its Store.
type ChunkActivities struct {
	Registry   *chunk.Registry
	Repository ChunkRepository
	Attempt    Attempt
}

func (a ChunkActivities) validate() error {
	if a.Registry == nil {
		return errors.New("chunk activities: registry is required")
	}
	if a.Repository == nil {
		return errors.New("chunk activities: repository is required")
	}
	return nil
}

func (a ChunkActivities) attempt(ctx context.Context) int32 {
	if a.Attempt == nil {
		return 1
	}
	attempt := a.Attempt(ctx)
	if attempt < 1 {
		return 1
	}
	return attempt
}

// ChunkDocument resolves the retained source object named by
// req.Refs["source_representation"], chunks it in-memory via the
// injected chunk.Registry (which independently validates completeness —
// contiguous, gap-free, non-overlapping, source/reassembly hashes equal —
// before ever returning a Result, per engine/chunk.Registry.Execute), then
// persists exactly one chunk generation. It never parses or normalizes.
func (a ChunkActivities) ChunkDocument(ctx context.Context, req proffer.StageRequest) (proffer.StageResult, error) {
	if err := a.validate(); err != nil {
		return proffer.StageResult{}, err
	}
	if err := ctx.Err(); err != nil {
		return proffer.StageResult{}, err
	}
	spec, err := chunkDocumentSpecFrom(req, a.attempt(ctx))
	if err != nil {
		return proffer.StageResult{}, err
	}
	if err := spec.validate(); err != nil {
		return proffer.StageResult{}, err
	}

	source, err := a.Repository.ResolveSourceRepresentation(ctx, spec)
	if err != nil {
		return proffer.StageResult{}, fmt.Errorf("%s: resolve source representation: %w", stagegraph.ChunkDocument, err)
	}
	if err := ctx.Err(); err != nil {
		return proffer.StageResult{}, err
	}

	result, err := a.Registry.Execute(ctx, source, spec.Signature)
	if err != nil {
		return proffer.StageResult{}, fmt.Errorf("%s: chunk: %w", stagegraph.ChunkDocument, err)
	}

	outcome, err := a.Repository.PersistChunkGeneration(ctx, spec, result)
	if err != nil {
		return proffer.StageResult{}, fmt.Errorf("%s: persist: %w", stagegraph.ChunkDocument, err)
	}
	if outcome.GenerationRef == "" || outcome.ReceiptRef == "" {
		return proffer.StageResult{}, fmt.Errorf("%s: persisted chunk generation lacks result or activity receipt reference", stagegraph.ChunkDocument)
	}
	if !outcome.ReassemblyVerified {
		return proffer.StageResult{}, fmt.Errorf("%s: chunk generation persisted without a verified reassembly receipt", stagegraph.ChunkDocument)
	}

	return proffer.StageResult{
		Stage: stagegraph.ChunkDocument, Status: proffer.StatusSuccess,
		Ref: outcome.GenerationRef, ReceiptRef: outcome.ReceiptRef,
	}, nil
}

// chunkDocumentSpecFrom reads chunk_document_activity's parameters out of
// proffer.StageRequest.Refs, following the same reference-passing convention as
// every neighboring Activity (requiredRawRef, defined in raw_pipeline.go).
// chunk_signature/chunk_derivation_mode/chunk_policy_id/chunk_policy_version
// are short controlled-vocabulary identifiers, not payloads — the same class
// of value StageRequest.DeclaredFormat already carries directly rather than
// by reference — so packing them into the Refs map (Ref is a bare string
// type) adds no file bodies or record content to Temporal history.
func chunkDocumentSpecFrom(req proffer.StageRequest, attempt int32) (ChunkDocumentSpec, error) {
	if strings.TrimSpace(req.RequestID) == "" || req.SourceVersionRef == "" {
		return ChunkDocumentSpec{}, fmt.Errorf("%s requires request and source version references", stagegraph.ChunkDocument)
	}
	packageRef, err := requiredRawRef(req, stagegraph.ChunkDocument, "package")
	if err != nil {
		return ChunkDocumentSpec{}, err
	}
	extractionAttemptRef, err := requiredRawRef(req, stagegraph.ChunkDocument, "extraction_attempt")
	if err != nil {
		return ChunkDocumentSpec{}, err
	}
	sourceRepresentationRef, err := requiredRawRef(req, stagegraph.ChunkDocument, "source_representation")
	if err != nil {
		return ChunkDocumentSpec{}, err
	}
	normalizedGenerationRef, err := requiredRawRef(req, stagegraph.ChunkDocument, "normalized_generation")
	if err != nil {
		return ChunkDocumentSpec{}, err
	}
	normalizedVerificationRef, err := requiredRawRef(req, stagegraph.ChunkDocument, "normalized_verification")
	if err != nil {
		return ChunkDocumentSpec{}, err
	}
	signatureRef, err := requiredRawRef(req, stagegraph.ChunkDocument, "chunk_signature")
	if err != nil {
		return ChunkDocumentSpec{}, err
	}
	derivationRef, err := requiredRawRef(req, stagegraph.ChunkDocument, "chunk_derivation_mode")
	if err != nil {
		return ChunkDocumentSpec{}, err
	}
	policyIDRef, err := requiredRawRef(req, stagegraph.ChunkDocument, "chunk_policy_id")
	if err != nil {
		return ChunkDocumentSpec{}, err
	}
	policyVersionRef, err := requiredRawRef(req, stagegraph.ChunkDocument, "chunk_policy_version")
	if err != nil {
		return ChunkDocumentSpec{}, err
	}
	return ChunkDocumentSpec{
		RequestID: req.RequestID, Attempt: attempt, PackageRef: packageRef, ExtractionAttemptRef: extractionAttemptRef,
		SourceVersionRef: req.SourceVersionRef, SourceRepresentationRef: sourceRepresentationRef,
		NormalizedGenerationRef: normalizedGenerationRef, NormalizedVerificationRef: normalizedVerificationRef,
		Signature: chunk.Signature(signatureRef), DerivationMode: string(derivationRef),
		PolicyID: string(policyIDRef), PolicyVersion: string(policyVersionRef),
	}, nil
}
