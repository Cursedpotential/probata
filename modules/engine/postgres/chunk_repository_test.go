package postgres

import (
	"testing"

	"github.com/Cursedpotential/probata/engine/activities"
	"github.com/Cursedpotential/probata/engine/chunk"
	"github.com/Cursedpotential/probata/engine/proffer"
)

func testChunkDocumentSpec() activities.ChunkDocumentSpec {
	return activities.ChunkDocumentSpec{
		RequestID: "request-1", Attempt: 1, PackageRef: "package-1", ExtractionAttemptRef: "attempt-1",
		SourceVersionRef: "source-1", SourceRepresentationRef: "representation-1",
		NormalizedGenerationRef: "normalized-1", NormalizedVerificationRef: "verification-1",
		Signature: chunk.SignatureResearchReport, DerivationMode: activities.DerivationModeVerbatimSpan,
		PolicyID: "context.default", PolicyVersion: "1.0.0",
	}
}

func TestChunkGenerationReceiptRoundTripsImmutableAttemptProvenance(t *testing.T) {
	spec := testChunkDocumentSpec()
	encoded := chunkGenerationResultJSON("generation-1", spec)
	decoded, err := decodeChunkGenerationResult(encoded)
	if err != nil {
		t.Fatal(err)
	}
	if decoded.RefID != "generation-1" || decoded.PackageRef != string(spec.PackageRef) ||
		decoded.AttemptRef != string(spec.ExtractionAttemptRef) || decoded.SourceRepresentationRef != string(spec.SourceRepresentationRef) ||
		decoded.NormalizedGenerationRef != string(spec.NormalizedGenerationRef) || decoded.NormalizedVerificationRef != string(spec.NormalizedVerificationRef) {
		t.Fatalf("chunk receipt lost provenance: %+v", decoded)
	}
}

func TestChunkDocumentIdempotencyChangesWithDomainAttempt(t *testing.T) {
	first := testChunkDocumentSpec()
	second := first
	second.ExtractionAttemptRef = proffer.Ref("attempt-2")
	if chunkDocumentKey(first) == chunkDocumentKey(second) {
		t.Fatal("distinct immutable extraction attempts shared a chunk idempotency key")
	}
}
