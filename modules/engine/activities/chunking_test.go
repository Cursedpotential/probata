package activities

import (
	"testing"

	"github.com/Cursedpotential/probata/engine/chunk"
	"github.com/Cursedpotential/probata/engine/proffer"
)

func validContextChunkRequest() proffer.StageRequest {
	return proffer.StageRequest{
		RequestID: "request-1", SourceVersionRef: "source-version-1", DeclaredFormat: "pdf",
		Refs: map[string]proffer.Ref{
			"package": "package-1", "extraction_attempt": "attempt-1",
			"source_representation": "representation-1", "normalized_generation": "normalized-1",
			"normalized_verification": "verification-1", "chunk_signature": "research_report",
			"chunk_derivation_mode": DerivationModeVerbatimSpan, "chunk_policy_id": "context.default",
			"chunk_policy_version": "1.0.0",
		},
	}
}

func TestChunkDocumentSpecBindsPackageAttemptAndVerifiedRepresentation(t *testing.T) {
	spec, err := chunkDocumentSpecFrom(validContextChunkRequest(), 2)
	if err != nil {
		t.Fatal(err)
	}
	if err := spec.validate(); err != nil {
		t.Fatal(err)
	}
	if spec.PackageRef != "package-1" || spec.ExtractionAttemptRef != "attempt-1" ||
		spec.SourceVersionRef != "source-version-1" || spec.SourceRepresentationRef != "representation-1" ||
		spec.NormalizedGenerationRef != "normalized-1" || spec.NormalizedVerificationRef != "verification-1" ||
		spec.Signature != chunk.SignatureResearchReport || spec.Attempt != 2 {
		t.Fatalf("chunk spec lost immutable provenance: %+v", spec)
	}
}

func TestChunkDocumentSpecFailsClosedWhenAttemptProvenanceIsMissing(t *testing.T) {
	for _, key := range []string{"package", "extraction_attempt", "source_representation", "normalized_generation", "normalized_verification"} {
		t.Run(key, func(t *testing.T) {
			request := validContextChunkRequest()
			delete(request.Refs, key)
			if _, err := chunkDocumentSpecFrom(request, 1); err == nil {
				t.Fatalf("missing %s reference was accepted", key)
			}
		})
	}
}
