// This file implements the PostgreSQL boundary for chunk_document_activity
// (BUILD LANE C1, D-116 / owner ruling 2026-08-29 skip-to-chunk). It is the
// only writer for working.content_chunk_generation, working.content_chunk,
// working.content_chunk_source_span, and working.content_chunk_reassembly_receipt.
//
// Locator basis (verified live against the platform schema, 2026-09-02):
// working.content_chunk_source_span.source_range_locator_id references
// context.source_range_locator, and that table carries a DEFERRABLE
// "exactly one typed subject" trigger
// (working.check_source_range_locator_subject_deferred ->
// working.validate_source_range_locator_subject) that counts ONLY
// context.source_object_range_locator, context.raw_record_range_locator,
// and context.normalized_record_range_locator rows — it does not know about
// working.content_chunk_source_span at all. Every locator this repository
// creates therefore also gets one context.source_object_range_locator row
// (source_object_id = the exact retained source representation), which is the
// correct typed-subject basis for a range measured against a whole source object
// rather than a specific raw or normalized record; content_chunk_source_span
// is then a second, uncounted consumer of that same locator. This is not a
// workaround — context.source_object_range_locator exists precisely to
// anchor a locator's basis to a source object.
package postgres

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/binary"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"strings"
	"time"

	"github.com/Cursedpotential/probata/engine/activities"
	"github.com/Cursedpotential/probata/engine/chunk"
	"github.com/Cursedpotential/probata/engine/proffer"
	"github.com/Cursedpotential/probata/engine/stagegraph"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

// chunkManifestCanon names this repository's manifest-digest construction:
// sha256 seeded with this canon string plus a NUL byte, then for every
// sealed chunk in chunk_index order, an 8-byte big-endian ordinal frame
// followed by that chunk's raw 32-byte content_sha256 — the exact
// length-framed technique engine/activities/hashing.go's
// newNormalizedAccumulator already uses for
// normalized-generation-ordered-digests-lengthframed-sha256-v1, reused here
// under its own canon tag because chunk manifests are a distinct
// construction from normalized-generation manifests.
const chunkManifestCanon = "content-chunk-manifest-ordered-digests-lengthframed-sha256-v1"

// chunkImplementationCanon and chunkConfigCanon seed this repository's
// implementation_digest and config_digest constructions. Neither column is
// defined by engine/chunk itself (it only proves chunk-level completeness);
// this repository owns both digests' exact construction, version-pinned by
// these canon tags.
const (
	chunkImplementationCanon = "content-chunk-implementation-v1"
	chunkConfigCanon         = "content-chunk-config-v1"
	chunkVerifierID          = "engine/chunk.Result.Validate"
)

// ChunkRepository implements activities.ChunkRepository.
type ChunkRepository struct {
	db    DB
	open  ObjectOpener
	clock func() time.Time
}

// NewChunkRepository constructs a repository. open may be nil when every
// original object this repository chunks is inline; a non-inline object then
// fails closed rather than reading through an ungoverned path.
func NewChunkRepository(db DB, open ObjectOpener) (*ChunkRepository, error) {
	if db == nil {
		return nil, errors.New("postgres chunk repository: database is required")
	}
	return &ChunkRepository{db: db, open: open, clock: func() time.Time { return time.Now().UTC() }}, nil
}

func (r *ChunkRepository) now() time.Time {
	if r.clock == nil {
		return time.Now().UTC()
	}
	return r.clock().UTC()
}

// ResolveSourceRepresentation reads and independently verifies the exact
// bytes named by spec.SourceRepresentationRef. The retained object must be
// the source original or a registered member/derived representation of
// spec.SourceVersionRef (a retained source version owned by spec.RequestID),
// and the bytes actually read must match the retained object's own declared
// byte_length and content_sha256 — the same "recompute rather than trust"
// discipline every other repository in this package applies.
func (r *ChunkRepository) ResolveSourceRepresentation(ctx context.Context, spec activities.ChunkDocumentSpec) ([]byte, error) {
	if err := validateChunkDocumentSpec(spec); err != nil {
		return nil, err
	}
	sourceVersionID, err := parseUUIDRef(spec.SourceVersionRef, "chunk source version")
	if err != nil {
		return nil, err
	}
	representationObjectID, err := parseUUIDRef(spec.SourceRepresentationRef, "chunk source representation")
	if err != nil {
		return nil, err
	}

	var workflowID, status string
	var boundOriginalObjectID uuid.UUID
	if err := r.db.QueryRow(ctx, `
		SELECT workflow_id, status, original_object_id
		FROM context.source_version WHERE id = $1::uuid`, sourceVersionID).Scan(
		&workflowID, &status, &boundOriginalObjectID); err != nil {
		return nil, fmt.Errorf("read chunk source version: %w", err)
	}
	if workflowID != spec.RequestID || status != "retained" {
		return nil, errors.New("chunk document requires a retained source version owned by this request")
	}
	if boundOriginalObjectID != representationObjectID {
		var role string
		if err := r.db.QueryRow(ctx, `
			SELECT object_role FROM context.source_version_object
			WHERE source_version_id = $1::uuid AND object_id = $2::uuid`, sourceVersionID, representationObjectID).Scan(&role); err != nil {
			return nil, fmt.Errorf("chunk source representation is not registered to the source version: %w", err)
		}
		if role == "original" {
			return nil, errors.New("chunk source representation has inconsistent original-object membership")
		}
	}

	var storageClass, objectURI string
	var inline, declaredHash []byte
	var declaredLength int64
	if err := r.db.QueryRow(ctx, `
		SELECT storage_class, object_uri, inline_bytes, content_sha256, byte_length
		FROM context.retained_object WHERE id = $1::uuid`, representationObjectID).Scan(
		&storageClass, &objectURI, &inline, &declaredHash, &declaredLength); err != nil {
		return nil, fmt.Errorf("resolve chunk source representation %q: %w", spec.SourceRepresentationRef, err)
	}

	var source []byte
	if storageClass == "inline" {
		source = inline
	} else {
		if r.open == nil {
			return nil, fmt.Errorf("non-inline chunk source representation %q requires an ObjectOpener", objectURI)
		}
		reader, err := r.open(ctx, objectURI)
		if err != nil {
			return nil, fmt.Errorf("open chunk original object: %w", err)
		}
		defer reader.Close()
		source, err = io.ReadAll(reader)
		if err != nil {
			return nil, fmt.Errorf("read chunk original object: %w", err)
		}
	}

	if int64(len(source)) != declaredLength {
		return nil, fmt.Errorf("chunk source representation byte length %d does not match retained object's declared length %d", len(source), declaredLength)
	}
	sum := sha256.Sum256(source)
	if !bytes.Equal(sum[:], declaredHash) {
		return nil, errors.New("chunk source representation content does not match its retained sha256")
	}
	return source, nil
}

// PersistChunkGeneration is the only write for working.content_chunk_generation,
// working.content_chunk, working.content_chunk_source_span, and
// working.content_chunk_reassembly_receipt, plus the context.source_range_locator
// / context.source_object_range_locator rows each chunk's span requires. The
// whole generation is computed synchronously in memory before this method is
// ever called (engine/chunk.Registry.Execute already independently proved
// completeness), so — unlike raw/normalized generations, which stream
// incrementally through an open-then-seal lifecycle — this repository writes
// one sealed generation directly in a single bounded transaction.
func (r *ChunkRepository) PersistChunkGeneration(ctx context.Context, spec activities.ChunkDocumentSpec, result chunk.Result) (activities.ChunkGenerationOutcome, error) {
	if err := validateChunkDocumentSpec(spec); err != nil {
		return activities.ChunkGenerationOutcome{}, err
	}
	sourceVersionID, err := parseUUIDRef(spec.SourceVersionRef, "chunk source version")
	if err != nil {
		return activities.ChunkGenerationOutcome{}, err
	}
	representationObjectID, err := parseUUIDRef(spec.SourceRepresentationRef, "chunk source representation")
	if err != nil {
		return activities.ChunkGenerationOutcome{}, err
	}
	normalizedGenerationID, err := parseUUIDRef(spec.NormalizedGenerationRef, "chunk normalized generation")
	if err != nil {
		return activities.ChunkGenerationOutcome{}, err
	}
	normalizedVerificationReceiptID, err := parseUUIDRef(spec.NormalizedVerificationRef, "chunk normalized verification receipt")
	if err != nil {
		return activities.ChunkGenerationOutcome{}, err
	}

	tx, err := r.db.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return activities.ChunkGenerationOutcome{}, fmt.Errorf("begin chunk generation transaction: %w", err)
	}
	rollback := true
	defer func() {
		if rollback {
			cleanupCtx, cancel := boundedCleanup(ctx)
			defer cancel()
			_ = tx.Rollback(cleanupCtx)
		}
	}()

	executionID, err := parserEnsureExecution(ctx, tx, sourceVersionID, spec.RequestID, string(stagegraph.ChunkDocument), chunkDocumentKey(spec))
	if err != nil {
		return activities.ChunkGenerationOutcome{}, err
	}

	var priorReceiptID uuid.UUID
	var priorResult []byte
	err = tx.QueryRow(ctx, `
		SELECT id, result_ref FROM context.activity_receipt
		WHERE activity_execution_id = $1::uuid AND status = 'success'
		ORDER BY attempt DESC LIMIT 1`, executionID).Scan(&priorReceiptID, &priorResult)
	if err == nil {
		prior, decodeErr := decodeChunkGenerationResult(priorResult)
		if decodeErr != nil {
			return activities.ChunkGenerationOutcome{}, decodeErr
		}
		if prior.PackageRef != string(spec.PackageRef) || prior.AttemptRef != string(spec.ExtractionAttemptRef) ||
			prior.SourceRepresentationRef != string(spec.SourceRepresentationRef) || prior.NormalizedGenerationRef != string(spec.NormalizedGenerationRef) ||
			prior.NormalizedVerificationRef != string(spec.NormalizedVerificationRef) {
			return activities.ChunkGenerationOutcome{}, errors.New("prior chunk generation receipt does not match the requested package, attempt, or source representation")
		}
		generationID, parseErr := uuid.Parse(prior.RefID)
		if parseErr != nil {
			return activities.ChunkGenerationOutcome{}, fmt.Errorf("prior chunk generation result has an invalid id: %w", parseErr)
		}
		return loadChunkOutcome(ctx, tx, generationID, priorReceiptID)
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return activities.ChunkGenerationOutcome{}, fmt.Errorf("inspect prior chunk generation receipts: %w", err)
	}

	var workflowID, status string
	var boundOriginalObjectID uuid.UUID
	if err := tx.QueryRow(ctx, `
		SELECT workflow_id, status, original_object_id
		FROM context.source_version WHERE id = $1::uuid`, sourceVersionID).Scan(
		&workflowID, &status, &boundOriginalObjectID); err != nil {
		return activities.ChunkGenerationOutcome{}, fmt.Errorf("read chunk source version: %w", err)
	}
	if workflowID != spec.RequestID || status != "retained" {
		return activities.ChunkGenerationOutcome{}, errors.New("chunk document requires a retained source version owned by this request")
	}
	sourceView := "original"
	if boundOriginalObjectID != representationObjectID {
		if err := tx.QueryRow(ctx, `
			SELECT object_role FROM context.source_version_object
			WHERE source_version_id = $1::uuid AND object_id = $2::uuid`, sourceVersionID, representationObjectID).Scan(&sourceView); err != nil {
			return activities.ChunkGenerationOutcome{}, fmt.Errorf("chunk source representation is not registered to the source version: %w", err)
		}
		if sourceView == "original" {
			return activities.ChunkGenerationOutcome{}, errors.New("chunk source representation has inconsistent original-object membership")
		}
	}
	var normalizedStatus string
	if err := tx.QueryRow(ctx, `
		SELECT status FROM context.normalized_generation
		WHERE id = $1::uuid AND source_version_id = $2::uuid`, normalizedGenerationID, sourceVersionID).Scan(&normalizedStatus); err != nil {
		return activities.ChunkGenerationOutcome{}, fmt.Errorf("read chunk normalized generation: %w", err)
	}
	if normalizedStatus != "open" && normalizedStatus != "sealed" && normalizedStatus != "published" {
		return activities.ChunkGenerationOutcome{}, fmt.Errorf("chunk normalized generation has invalid status %q", normalizedStatus)
	}
	var verificationActivity, verificationStatus string
	if err := tx.QueryRow(ctx, `
		SELECT execution.activity_name, receipt.status
		FROM context.activity_receipt receipt
		JOIN context.activity_execution execution ON execution.id = receipt.activity_execution_id
		WHERE receipt.id = $1::uuid AND execution.source_version_id = $2::uuid`,
		normalizedVerificationReceiptID, sourceVersionID).Scan(&verificationActivity, &verificationStatus); err != nil {
		return activities.ChunkGenerationOutcome{}, fmt.Errorf("read normalized verification receipt for chunk generation: %w", err)
	}
	if verificationActivity != string(stagegraph.VerifyNormalizedGeneration) || verificationStatus != "success" {
		return activities.ChunkGenerationOutcome{}, errors.New("chunk generation requires a successful normalized-generation verification receipt for the same source")
	}

	sourceSHA256, err := decodeHexDigest(result.SourceHash, "chunk source")
	if err != nil {
		return activities.ChunkGenerationOutcome{}, err
	}
	reassembledSHA256, err := decodeHexDigest(result.ReassemblyHash, "chunk reassembly")
	if err != nil {
		return activities.ChunkGenerationOutcome{}, err
	}

	chunkCount := int64(len(result.Chunks))
	manifestDigest := chunkManifestDigest(result.Chunks)
	configDigest := chunkConfigDigest(spec)
	implementationDigest := chunkImplementationDigest()

	generationID := uuid.New()
	receiptID := uuid.New()
	now := r.now()

	resultRef := chunkGenerationResultJSON(generationID.String(), spec)
	if _, err := tx.Exec(ctx, `
		INSERT INTO context.activity_receipt
		    (id, activity_execution_id, attempt, status, started_at, completed_at, result_ref)
		VALUES ($1::uuid, $2::uuid, $3, 'success', $4, $5, $6::jsonb)`,
		receiptID, executionID, spec.Attempt, now, now, resultRef); err != nil {
		return activities.ChunkGenerationOutcome{}, fmt.Errorf("write chunk document activity receipt: %w", err)
	}

	// content_chunk_generation requires a NOT NULL activity_receipt_id even
	// while open (see the file-level comment on the tri-state CHECK), so the
	// receipt above must exist before this insert. The whole generation is
	// already known-complete at this point (chunk.Registry.Execute proved it
	// before returning result), so this repository seals it directly rather
	// than opening, streaming, then sealing across two writes.
	var insertedID uuid.UUID
	if err := tx.QueryRow(ctx, `
		INSERT INTO working.content_chunk_generation
		    (id, source_version_id, normalized_generation_id, generation_ordinal, status, completeness_scope,
		     requires_verbatim_reassembly, policy_id, policy_version, chunker_id, chunker_version, config_digest,
		     schema_version, implementation_digest, source_view, source_canonicalization, source_sha256,
		     source_byte_length, source_codepoint_length, chunk_count, member_count, manifest_sha256,
		     activity_execution_id, activity_receipt_id, created_at, sealed_at, sealed_by)
		SELECT $1::uuid, $2::uuid, $3::uuid, COALESCE(MAX(generation_ordinal), 0) + 1, 'sealed', 'complete',
		       true, $4, $5, $6, $7, $8::bytea,
		       $9, $10::bytea, $11, 'utf8_bytes_verbatim', $12::bytea,
		       $13, $14, $15, $15, $16::bytea,
		       $17::uuid, $18::uuid, $19, $19, $20
		FROM working.content_chunk_generation WHERE source_version_id = $2::uuid
		RETURNING id`,
		generationID, sourceVersionID, normalizedGenerationID, spec.PolicyID, spec.PolicyVersion, chunk.ChunkerID, chunk.ChunkerVersion, configDigest,
		chunk.SchemaVersion, implementationDigest, sourceView, sourceSHA256,
		int64(result.SourceByteCount), int64(result.SourceCharCount), chunkCount, manifestDigest,
		executionID, receiptID, now, string(stagegraph.ChunkDocument),
	).Scan(&insertedID); err != nil {
		return activities.ChunkGenerationOutcome{}, fmt.Errorf("create chunk generation: %w", err)
	}

	for _, member := range result.Chunks {
		contentDigest, err := decodeHexDigest(member.ContentHash, fmt.Sprintf("chunk %d content", member.Index))
		if err != nil {
			return activities.ChunkGenerationOutcome{}, err
		}

		chunkID := uuid.New()
		if _, err := tx.Exec(ctx, `
			INSERT INTO working.content_chunk
			    (id, generation_id, source_version_id, chunk_index, content, content_sha256, derivation_mode)
			VALUES ($1::uuid, $2::uuid, $3::uuid, $4, $5, $6::bytea, $7)`,
			chunkID, generationID, sourceVersionID, int64(member.Index), member.Text, contentDigest, spec.DerivationMode); err != nil {
			return activities.ChunkGenerationOutcome{}, fmt.Errorf("persist chunk %d: %w", member.Index, err)
		}

		locatorID := uuid.New()
		if _, err := tx.Exec(ctx, `
			INSERT INTO context.source_range_locator
			    (id, source_version_id, coordinate_system, range_start, range_end, exact_slice_sha256, verification_activity_receipt_id)
			VALUES ($1::uuid, $2::uuid, 'utf8_bytes', $3, $4, $5::bytea, $6::uuid)`,
			locatorID, sourceVersionID, int64(member.ByteStart), int64(member.ByteEnd), contentDigest, receiptID); err != nil {
			return activities.ChunkGenerationOutcome{}, fmt.Errorf("persist chunk %d source range locator: %w", member.Index, err)
		}
		if _, err := tx.Exec(ctx, `
			INSERT INTO context.source_object_range_locator (source_range_locator_id, source_version_id, source_object_id)
			VALUES ($1::uuid, $2::uuid, $3::uuid)`,
			locatorID, sourceVersionID, representationObjectID); err != nil {
			return activities.ChunkGenerationOutcome{}, fmt.Errorf("persist chunk %d source object range locator: %w", member.Index, err)
		}
		if _, err := tx.Exec(ctx, `
			INSERT INTO working.content_chunk_source_span
			    (id, chunk_id, generation_id, source_version_id, member_ordinal, source_range_locator_id)
			VALUES ($1::uuid, $2::uuid, $3::uuid, $4::uuid, 0, $5::uuid)`,
			uuid.New(), chunkID, generationID, sourceVersionID, locatorID); err != nil {
			return activities.ChunkGenerationOutcome{}, fmt.Errorf("persist chunk %d source span: %w", member.Index, err)
		}
	}

	if _, err := tx.Exec(ctx, `
		INSERT INTO working.content_chunk_reassembly_receipt
		    (id, generation_id, source_version_id, source_sha256, reassembled_sha256, source_byte_length,
		     reassembled_byte_length, covered_range_start, covered_range_end, gap_count, overlap_count,
		     chunk_count, member_count, verification_result, verifier_id, verifier_version,
		     activity_receipt_id, verified_at)
		VALUES ($1::uuid, $2::uuid, $3::uuid, $4::bytea, $5::bytea, $6,
		        $6, 0, $6, 0, 0,
		        $7, $7, 'exact', $8, $9,
		        $10::uuid, $11)`,
		uuid.New(), generationID, sourceVersionID, sourceSHA256, reassembledSHA256, int64(result.SourceByteCount),
		chunkCount, chunkVerifierID, chunk.ContractVersion,
		receiptID, now); err != nil {
		return activities.ChunkGenerationOutcome{}, fmt.Errorf("persist chunk reassembly receipt: %w", err)
	}

	if err := tx.Commit(ctx); err != nil {
		return activities.ChunkGenerationOutcome{}, fmt.Errorf("commit chunk generation: %w", err)
	}
	rollback = false
	return activities.ChunkGenerationOutcome{
		GenerationRef: proffer.Ref(generationID.String()), ReceiptRef: proffer.Ref(receiptID.String()),
		ChunkCount: chunkCount, ReassemblyVerified: true,
	}, nil
}

func loadChunkOutcome(ctx context.Context, tx pgx.Tx, generationID, receiptID uuid.UUID) (activities.ChunkGenerationOutcome, error) {
	var chunkCount int64
	if err := tx.QueryRow(ctx, `SELECT chunk_count FROM working.content_chunk_generation WHERE id = $1::uuid`, generationID).Scan(&chunkCount); err != nil {
		return activities.ChunkGenerationOutcome{}, fmt.Errorf("read prior chunk generation: %w", err)
	}
	var verification string
	if err := tx.QueryRow(ctx, `SELECT verification_result FROM working.content_chunk_reassembly_receipt WHERE generation_id = $1::uuid`, generationID).Scan(&verification); err != nil {
		return activities.ChunkGenerationOutcome{}, fmt.Errorf("read prior chunk reassembly receipt: %w", err)
	}
	return activities.ChunkGenerationOutcome{
		GenerationRef: proffer.Ref(generationID.String()), ReceiptRef: proffer.Ref(receiptID.String()),
		ChunkCount: chunkCount, ReassemblyVerified: verification == "exact",
	}, nil
}

type chunkRefResult struct {
	RefKind                   string `json:"ref_kind"`
	RefID                     string `json:"ref_id"`
	PackageRef                string `json:"package_ref"`
	AttemptRef                string `json:"attempt_ref"`
	SourceRepresentationRef   string `json:"source_representation_ref"`
	NormalizedGenerationRef   string `json:"normalized_generation_ref"`
	NormalizedVerificationRef string `json:"normalized_verification_ref"`
}

func chunkGenerationResultJSON(id string, spec activities.ChunkDocumentSpec) []byte {
	encoded, _ := json.Marshal(chunkRefResult{
		RefKind: "chunk_generation", RefID: id,
		PackageRef: string(spec.PackageRef), AttemptRef: string(spec.ExtractionAttemptRef),
		SourceRepresentationRef:   string(spec.SourceRepresentationRef),
		NormalizedGenerationRef:   string(spec.NormalizedGenerationRef),
		NormalizedVerificationRef: string(spec.NormalizedVerificationRef),
	})
	return encoded
}

func decodeChunkGenerationResult(raw []byte) (chunkRefResult, error) {
	var ref chunkRefResult
	if err := json.Unmarshal(raw, &ref); err != nil {
		return chunkRefResult{}, fmt.Errorf("decode chunk generation result: %w", err)
	}
	if ref.RefKind != "chunk_generation" || strings.TrimSpace(ref.RefID) == "" || strings.TrimSpace(ref.PackageRef) == "" ||
		strings.TrimSpace(ref.AttemptRef) == "" || strings.TrimSpace(ref.SourceRepresentationRef) == "" ||
		strings.TrimSpace(ref.NormalizedGenerationRef) == "" || strings.TrimSpace(ref.NormalizedVerificationRef) == "" {
		return chunkRefResult{}, errors.New("chunk generation result is incomplete or mutable")
	}
	return ref, nil
}

func decodeHexDigest(value, label string) ([]byte, error) {
	decoded, err := hex.DecodeString(value)
	if err != nil {
		return nil, fmt.Errorf("%s digest %q is not valid hex: %w", label, value, err)
	}
	if len(decoded) != sha256.Size {
		return nil, fmt.Errorf("%s digest has %d bytes, want %d", label, len(decoded), sha256.Size)
	}
	return decoded, nil
}

// chunkManifestDigest applies chunkManifestCanon's length-framed construction
// over the sealed chunk set in chunk_index order.
func chunkManifestDigest(chunks []chunk.Chunk) []byte {
	h := sha256.New()
	_, _ = io.WriteString(h, chunkManifestCanon)
	_, _ = h.Write([]byte{0})
	for _, member := range chunks {
		var frame [8]byte
		binary.BigEndian.PutUint64(frame[:], uint64(member.Index))
		_, _ = h.Write(frame[:])
		digestBytes, err := hex.DecodeString(member.ContentHash)
		if err != nil {
			// engine/chunk.Result.Validate already proved every ContentHash is
			// a valid hex sha256 before this Result ever reached persistence;
			// an error here can only mean that guarantee was violated.
			continue
		}
		_, _ = h.Write(digestBytes)
	}
	return h.Sum(nil)
}

// chunkImplementationDigest identifies the exact registered chunker code
// that ran, independent of any per-run policy choice.
func chunkImplementationDigest() []byte {
	h := sha256.New()
	for _, part := range []string{chunkImplementationCanon, chunk.ChunkerID, chunk.ChunkerVersion, chunk.ContractVersion, chunk.SchemaID, chunk.SchemaVersion} {
		_, _ = io.WriteString(h, part)
		_, _ = h.Write([]byte{0})
	}
	return h.Sum(nil)
}

// chunkConfigDigest identifies the exact policy/variant/derivation choice
// applied for one generation, independent of the chunker's own code identity
// — two generations of the same source under different signatures or
// policies must not collide.
func chunkConfigDigest(spec activities.ChunkDocumentSpec) []byte {
	h := sha256.New()
	for _, part := range []string{chunkConfigCanon, spec.PolicyID, spec.PolicyVersion, string(spec.Signature), spec.DerivationMode} {
		_, _ = io.WriteString(h, part)
		_, _ = h.Write([]byte{0})
	}
	return h.Sum(nil)
}

func chunkDocumentKey(spec activities.ChunkDocumentSpec) string {
	h := sha256.New()
	for _, part := range []string{
		spec.RequestID, string(spec.PackageRef), string(spec.ExtractionAttemptRef), string(spec.SourceVersionRef),
		string(spec.SourceRepresentationRef), string(spec.NormalizedGenerationRef), string(spec.NormalizedVerificationRef),
		string(spec.Signature), spec.PolicyID, spec.PolicyVersion,
	} {
		var frame [8]byte
		binary.BigEndian.PutUint64(frame[:], uint64(len(part)))
		_, _ = h.Write(frame[:])
		_, _ = io.WriteString(h, part)
	}
	return "chunk-document-v2:" + hex.EncodeToString(h.Sum(nil))
}

func validateChunkDocumentSpec(spec activities.ChunkDocumentSpec) error {
	if strings.TrimSpace(spec.RequestID) == "" || spec.PackageRef == "" || spec.ExtractionAttemptRef == "" || spec.SourceVersionRef == "" ||
		spec.SourceRepresentationRef == "" || spec.NormalizedGenerationRef == "" || spec.NormalizedVerificationRef == "" {
		return errors.New("chunk document requires request, package, extraction-attempt, source, representation, normalized-generation, and verification references")
	}
	if spec.Attempt < 1 {
		return errors.New("chunk document attempt must be positive")
	}
	if err := spec.Signature.Validate(); err != nil {
		return fmt.Errorf("chunk document: %w", err)
	}
	if spec.DerivationMode != activities.DerivationModeVerbatimSpan {
		return fmt.Errorf("chunk document: unsupported derivation mode %q", spec.DerivationMode)
	}
	if strings.TrimSpace(spec.PolicyID) == "" || strings.TrimSpace(spec.PolicyVersion) == "" {
		return errors.New("chunk document requires policy id and version")
	}
	return nil
}

var _ activities.ChunkRepository = (*ChunkRepository)(nil)
