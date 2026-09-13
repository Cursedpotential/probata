package postgres

// This file implements the PostgreSQL boundary for the four raw-generation
// Activities. persist_raw_generation_activity is the only one that writes raw
// records; reconcile_record_accounting_activity, reconcile_byte_coverage_activity,
// and verify_raw_coverage_against_source_activity verify only, recomputing
// their proofs independently rather than trusting an earlier receipt's claim.

import (
	"bytes"
	"context"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"sort"
	"strings"
	"time"

	"github.com/Cursedpotential/probata/engine/activities"
	"github.com/Cursedpotential/probata/engine/parser"
	"github.com/Cursedpotential/probata/engine/proffer"
	"github.com/Cursedpotential/probata/engine/stagegraph"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/lowcarbdev/sbv/pkg/custodyhash"
)

// rawBundleContractVersion pins the read side of the JSONL bundle contract
// written by the parser Activity runtime's filesystem bundle writer
// (engine/runtimeapi/bundle_store.go). That writer's line shape is
// unexported, so the shape is reproduced here as the minimal shared contract
// rather than adding a cross-package dependency out of this file's scope.
const rawBundleContractVersion = "platform-raw-extraction-jsonl-v1"

// RawPipelineRepository implements activities.RawPipelineRepository.
type RawPipelineRepository struct {
	db    DB
	open  ObjectOpener
	clock func() time.Time
}

// NewRawPipelineRepository constructs a repository. open may be nil when
// every retained object the raw pipeline touches is inline; a non-inline
// bundle or locator object then fails closed rather than reading through an
// ungoverned path.
func NewRawPipelineRepository(db DB, open ObjectOpener) (*RawPipelineRepository, error) {
	if db == nil {
		return nil, errors.New("postgres raw pipeline repository: database is required")
	}
	return &RawPipelineRepository{db: db, open: open, clock: func() time.Time { return time.Now().UTC() }}, nil
}

func (r *RawPipelineRepository) now() time.Time { return r.clock().UTC() }

// bundleLine mirrors runtimeapi's private bundleLine encoding exactly (kind,
// contract, header, record, accounting) so the JSONL stream it wrote decodes
// correctly here.
type bundleLine struct {
	Kind       string                    `json:"kind"`
	Contract   string                    `json:"contract"`
	Header     *parser.BundleHeader      `json:"header,omitempty"`
	Record     *parser.RawRecordEnvelope `json:"record,omitempty"`
	Accounting *parser.BundleAccounting  `json:"accounting,omitempty"`
}

func (r *RawPipelineRepository) OpenRawBundle(ctx context.Context, ref proffer.Ref) (activities.RawBundleReader, error) {
	if err := requireRef(ref, "raw bundle"); err != nil {
		return nil, err
	}
	objectID, err := parseUUIDRef(ref, "raw bundle")
	if err != nil {
		return nil, err
	}
	var storageClass, objectURI string
	var inline []byte
	if err := r.db.QueryRow(ctx, `
		SELECT storage_class, object_uri, inline_bytes
		FROM context.retained_object
		WHERE id = $1::uuid`, objectID).Scan(&storageClass, &objectURI, &inline); err != nil {
		return nil, fmt.Errorf("resolve raw bundle object %q: %w", ref, err)
	}
	var reader io.ReadCloser
	if storageClass == "inline" {
		reader = io.NopCloser(bytes.NewReader(inline))
	} else {
		if r.open == nil {
			return nil, fmt.Errorf("non-inline raw bundle %q requires an ObjectOpener", objectURI)
		}
		reader, err = r.open(ctx, objectURI)
		if err != nil {
			return nil, fmt.Errorf("open raw bundle object: %w", err)
		}
	}
	return &rawBundleReader{closer: reader, dec: json.NewDecoder(reader)}, nil
}

type rawBundleReader struct {
	closer      io.Closer
	dec         *json.Decoder
	header      parser.BundleHeader
	haveHeader  bool
	trailer     parser.BundleAccounting
	haveTrailer bool
}

func (r *rawBundleReader) Header(ctx context.Context) (parser.BundleHeader, error) {
	if r.haveHeader {
		return r.header, nil
	}
	if err := ctx.Err(); err != nil {
		return parser.BundleHeader{}, err
	}
	var line bundleLine
	if err := r.dec.Decode(&line); err != nil {
		return parser.BundleHeader{}, fmt.Errorf("decode raw bundle header line: %w", err)
	}
	if line.Kind != "header" || line.Contract != rawBundleContractVersion || line.Header == nil {
		return parser.BundleHeader{}, errors.New("raw bundle does not begin with a valid header line")
	}
	r.header, r.haveHeader = *line.Header, true
	return r.header, nil
}

func (r *rawBundleReader) Next(ctx context.Context) (parser.RawRecordEnvelope, error) {
	if !r.haveHeader {
		return parser.RawRecordEnvelope{}, errors.New("raw bundle header must be read before records")
	}
	if r.haveTrailer {
		return parser.RawRecordEnvelope{}, io.EOF
	}
	if err := ctx.Err(); err != nil {
		return parser.RawRecordEnvelope{}, err
	}
	var line bundleLine
	if err := r.dec.Decode(&line); err != nil {
		if errors.Is(err, io.EOF) {
			return parser.RawRecordEnvelope{}, errors.New("raw bundle ended before its accounting trailer")
		}
		return parser.RawRecordEnvelope{}, fmt.Errorf("decode raw bundle line: %w", err)
	}
	if line.Contract != rawBundleContractVersion {
		return parser.RawRecordEnvelope{}, fmt.Errorf("raw bundle line has unsupported contract %q", line.Contract)
	}
	switch line.Kind {
	case "record":
		if line.Record == nil {
			return parser.RawRecordEnvelope{}, errors.New("raw bundle record line is empty")
		}
		return *line.Record, nil
	case "accounting":
		if line.Accounting == nil {
			return parser.RawRecordEnvelope{}, errors.New("raw bundle accounting line is empty")
		}
		r.trailer, r.haveTrailer = *line.Accounting, true
		return parser.RawRecordEnvelope{}, io.EOF
	default:
		return parser.RawRecordEnvelope{}, fmt.Errorf("raw bundle line has unsupported kind %q", line.Kind)
	}
}

func (r *rawBundleReader) Trailer(ctx context.Context) (parser.BundleAccounting, error) {
	if err := ctx.Err(); err != nil {
		return parser.BundleAccounting{}, err
	}
	if !r.haveTrailer {
		return parser.BundleAccounting{}, errors.New("raw bundle trailer has not been read")
	}
	return r.trailer, nil
}

func (r *rawBundleReader) Close() error { return r.closer.Close() }

var _ activities.RawBundleReader = (*rawBundleReader)(nil)

// rawRefResult is the compact {"ref_kind","ref_id"} shape every raw-pipeline
// activity_receipt.result_ref carries, matching the convention already used
// by the parser and source-lifecycle stores in this package.
type rawRefResult struct {
	RefKind string `json:"ref_kind"`
	RefID   string `json:"ref_id"`
}

// rawGenerationResult is persist_raw_generation_activity's durable receipt
// payload: the raw generation identity plus the accounting counts it
// persisted, so later reconciliation can compare against exactly what was
// declared without re-reading the (by then possibly gone) source bundle.
type rawGenerationResult struct {
	RefKind     string `json:"ref_kind"`
	RefID       string `json:"ref_id"`
	Emitted     uint64 `json:"emitted"`
	Rejected    uint64 `json:"rejected"`
	Malformed   uint64 `json:"malformed"`
	Unknown     uint64 `json:"unknown"`
	Unparsed    uint64 `json:"unparsed"`
	Attachments uint64 `json:"attachments"`
	Total       uint64 `json:"total"`
}

func (r rawGenerationResult) BundleAccounting() parser.BundleAccounting {
	return parser.BundleAccounting{
		Emitted: r.Emitted, Rejected: r.Rejected, Malformed: r.Malformed,
		Unknown: r.Unknown, Unparsed: r.Unparsed, Attachments: r.Attachments,
	}
}

func decodeRawGenerationResult(raw []byte) (rawGenerationResult, error) {
	var result rawGenerationResult
	if err := json.Unmarshal(raw, &result); err != nil {
		return rawGenerationResult{}, fmt.Errorf("decode raw generation result: %w", err)
	}
	if result.RefKind != "raw_generation" || strings.TrimSpace(result.RefID) == "" {
		return rawGenerationResult{}, errors.New("raw generation result is incomplete or mutable")
	}
	return result, nil
}

func (r *RawPipelineRepository) BeginRawGeneration(ctx context.Context, spec activities.RawGenerationSpec) (activities.RawGenerationWriter, error) {
	if err := validateRawGenerationSpec(spec); err != nil {
		return nil, err
	}
	sourceID, err := uuid.Parse(string(spec.SourceVersionRef))
	if err != nil {
		return nil, fmt.Errorf("source version reference %q: %w", spec.SourceVersionRef, err)
	}
	bundleID, err := parseUUIDRef(spec.BundleRef, "raw bundle")
	if err != nil {
		return nil, err
	}
	format := parser.FormatID(spec.DeclaredFormat)
	if err := format.Validate(); err != nil {
		return nil, fmt.Errorf("raw generation format: %w", err)
	}

	tx, err := r.db.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return nil, fmt.Errorf("begin raw generation transaction: %w", err)
	}
	rollback := true
	defer func() {
		if rollback {
			cleanupCtx, cancel := boundedCleanup(ctx)
			defer cancel()
			_ = tx.Rollback(cleanupCtx)
		}
	}()

	var workflowID, status string
	if err := tx.QueryRow(ctx, `SELECT workflow_id, status FROM context.source_version WHERE id = $1::uuid`, sourceID).Scan(&workflowID, &status); err != nil {
		return nil, fmt.Errorf("read raw generation source version: %w", err)
	}
	if workflowID != spec.RequestID || status != "retained" {
		return nil, errors.New("persist raw generation requires a retained source version owned by this request")
	}

	executionID, err := parserEnsureExecution(ctx, tx, sourceID, spec.RequestID, string(stagegraph.PersistRawGeneration), rawGenerationKey(spec))
	if err != nil {
		return nil, err
	}

	var priorReceiptID uuid.UUID
	var priorResult []byte
	err = tx.QueryRow(ctx, `
		SELECT id, result_ref FROM context.activity_receipt
		WHERE activity_execution_id = $1::uuid AND status = 'success'
		ORDER BY attempt DESC LIMIT 1`, executionID).Scan(&priorReceiptID, &priorResult)
	if err == nil {
		summary, decodeErr := decodeRawGenerationResult(priorResult)
		if decodeErr != nil {
			return nil, decodeErr
		}
		return &rawGenerationReplayWriter{
			resultRef: proffer.Ref(summary.RefID), receiptRef: proffer.Ref(priorReceiptID.String()),
			expected: summary.BundleAccounting(),
		}, nil
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return nil, fmt.Errorf("inspect prior raw generation receipts: %w", err)
	}

	if _, err := tx.Exec(ctx, `SELECT context.register_raw_format_subtype($1)`, string(format)); err != nil {
		return nil, fmt.Errorf("register raw format subtype %q: %w", format, err)
	}

	var rawGenerationID uuid.UUID
	if err := tx.QueryRow(ctx, `
		INSERT INTO context.raw_generation
		    (source_version_id, generation_ordinal, format_id, parser_id, parser_version,
		     extraction_bundle_object_id)
		SELECT $1::uuid, COALESCE(MAX(generation_ordinal), 0) + 1, $2, $3, $4, $5::uuid
		FROM context.raw_generation WHERE source_version_id = $1::uuid
		RETURNING id`, sourceID, string(format), spec.ParserID, spec.ParserVersion, bundleID).Scan(&rawGenerationID); err != nil {
		return nil, fmt.Errorf("create raw generation: %w", err)
	}

	rollback = false
	return &rawGenerationWriter{
		tx: tx, executionID: executionID, sourceID: sourceID, rawGenerationID: rawGenerationID,
		formatID: string(format), attempt: spec.Attempt, startedAt: r.now(), clock: r.clock,
	}, nil
}

// rawGenerationWriter owns one open transaction for the full Append→Commit
// lifecycle. Unlike hash membership, an already-finalized parser bundle is
// immutable and content-addressed, so a retry that finds no prior successful
// receipt can simply re-run from scratch inside a fresh transaction: nothing
// commits until Commit, so a crash mid-stream leaves no partial raw_generation
// or raw_record_identity rows behind to reconcile.
type rawGenerationWriter struct {
	tx                    pgx.Tx
	executionID, sourceID uuid.UUID
	rawGenerationID       uuid.UUID
	formatID              string
	attempt               int32
	startedAt             time.Time
	clock                 func() time.Time
	count                 uint64
	tally                 parser.BundleAccounting
	closed                bool
}

func (w *rawGenerationWriter) Append(ctx context.Context, record parser.RawRecordEnvelope) error {
	if w.closed {
		return errors.New("raw generation writer is closed")
	}
	if err := ctx.Err(); err != nil {
		return err
	}
	if record.RecordOrdinal != w.count {
		return fmt.Errorf("raw record ordinal %d, want contiguous ordinal %d", record.RecordOrdinal, w.count)
	}
	locatorObjectID, byteOffset, byteLength, storedBytes, err := resolveRawLocator(ctx, w.tx, w.sourceID, record)
	if err != nil {
		return err
	}
	for _, attachment := range record.Attachments {
		objectID, err := resolveLocatorObject(ctx, w.tx, w.sourceID, attachment.Locator.ObjectRef)
		if err != nil {
			return fmt.Errorf("resolve attachment %d governed locator: %w", attachment.AttachmentOrdinal, err)
		}
		var objectLength int64
		if err := w.tx.QueryRow(ctx, `SELECT byte_length FROM context.retained_object WHERE id = $1::uuid`, objectID).Scan(&objectLength); err != nil {
			return fmt.Errorf("resolve attachment %d object length: %w", attachment.AttachmentOrdinal, err)
		}
		if _, _, err := checkedLocatorRange(attachment.Locator.ByteRange, objectLength); err != nil {
			return fmt.Errorf("validate attachment %d locator range: %w", attachment.AttachmentOrdinal, err)
		}
	}
	construction := rawHashConstruction(record.RecordStatus)
	recordMetadata, err := attachmentsMetadataJSON(record.Attachments)
	if err != nil {
		return err
	}
	var statusReason *string
	if record.StatusReason != "" {
		statusReason = &record.StatusReason
	}

	var rawRecordID uuid.UUID
	if err := w.tx.QueryRow(ctx, `
		INSERT INTO context.raw_record_identity
		    (raw_generation_id, source_version_id, format_id, record_ordinal, record_status,
		     raw_hash_construction, status_reason, locator_object_id, byte_offset, byte_length,
		     stored_bytes, native_metadata)
		VALUES ($1::uuid, $2::uuid, $3, $4, $5, $6, $7, $8::uuid, $9, $10, $11, $12::jsonb)
		RETURNING id`,
		w.rawGenerationID, w.sourceID, w.formatID, record.RecordOrdinal, string(record.RecordStatus),
		construction, statusReason, locatorObjectID, byteOffset, byteLength, storedBytes, recordMetadata,
	).Scan(&rawRecordID); err != nil {
		return fmt.Errorf("persist raw record %d: %w", record.RecordOrdinal, err)
	}

	nativeFields := record.NativeFields
	if len(nativeFields) == 0 {
		nativeFields = json.RawMessage(`{}`)
	}
	subtypeMetadata := record.NativeMetadata
	if len(subtypeMetadata) == 0 {
		subtypeMetadata = json.RawMessage(`{}`)
	}
	subtypeTable := "context.raw_" + w.formatID
	if _, err := w.tx.Exec(ctx, fmt.Sprintf(`
		INSERT INTO %s (raw_record_id, native_fields, native_metadata)
		VALUES ($1::uuid, $2::jsonb, $3::jsonb)`, subtypeTable),
		rawRecordID, []byte(nativeFields), []byte(subtypeMetadata)); err != nil {
		return fmt.Errorf("persist raw record %d subtype fields: %w", record.RecordOrdinal, err)
	}

	w.count++
	tallyAccounting(&w.tally, record)
	return nil
}

func (w *rawGenerationWriter) Commit(ctx context.Context, accounting parser.BundleAccounting) (proffer.Ref, proffer.Ref, error) {
	if w.closed {
		return "", "", errors.New("raw generation writer is closed")
	}
	if err := ctx.Err(); err != nil {
		return "", "", err
	}
	if w.count == 0 {
		return "", "", errors.New("raw generation refuses to seal an empty bundle")
	}
	if accounting != w.tally {
		return "", "", fmt.Errorf("raw generation accounting %+v does not match staged counts %+v", accounting, w.tally)
	}
	var durableCount int64
	if err := w.tx.QueryRow(ctx, `SELECT count(*) FROM context.raw_record_identity WHERE raw_generation_id = $1::uuid`, w.rawGenerationID).Scan(&durableCount); err != nil {
		return "", "", fmt.Errorf("count durable raw records: %w", err)
	}
	if uint64(durableCount) != w.count {
		return "", "", fmt.Errorf("durable raw record count %d disagrees with writer count %d", durableCount, w.count)
	}

	result := rawGenerationResult{
		RefKind: "raw_generation", RefID: w.rawGenerationID.String(),
		Emitted: accounting.Emitted, Rejected: accounting.Rejected, Malformed: accounting.Malformed,
		Unknown: accounting.Unknown, Unparsed: accounting.Unparsed, Attachments: accounting.Attachments,
		Total: w.count,
	}
	resultJSON, err := json.Marshal(result)
	if err != nil {
		return "", "", fmt.Errorf("encode raw generation result: %w", err)
	}
	receiptID := uuid.New()
	completedAt := w.clock().UTC()
	if _, err := w.tx.Exec(ctx, `
		INSERT INTO context.activity_receipt
		    (id, activity_execution_id, attempt, status, started_at, completed_at, result_ref)
		VALUES ($1::uuid, $2::uuid, $3, 'success', $4, $5, $6::jsonb)`,
		receiptID, w.executionID, w.attempt, w.startedAt, completedAt, resultJSON); err != nil {
		return "", "", fmt.Errorf("write raw generation receipt: %w", err)
	}
	if err := w.tx.Commit(ctx); err != nil {
		return "", "", fmt.Errorf("commit raw generation: %w", err)
	}
	w.closed = true
	return proffer.Ref(w.rawGenerationID.String()), proffer.Ref(receiptID.String()), nil
}

func (w *rawGenerationWriter) Abort(ctx context.Context) error {
	if w.closed {
		return nil
	}
	w.closed = true
	cleanupCtx, cancel := boundedCleanup(ctx)
	defer cancel()
	return w.tx.Rollback(cleanupCtx)
}

// rawGenerationReplayWriter serves a retry that already has a durable,
// successful persist_raw_generation_activity receipt. It re-consumes the
// caller's stream (contiguity only, no DB writes) and verifies the caller's
// final accounting matches the prior receipt exactly before returning the
// same references.
type rawGenerationReplayWriter struct {
	resultRef, receiptRef proffer.Ref
	expected              parser.BundleAccounting
	count                 uint64
	closed                bool
}

func (w *rawGenerationReplayWriter) Append(ctx context.Context, record parser.RawRecordEnvelope) error {
	if w.closed {
		return errors.New("raw generation writer is closed")
	}
	if err := ctx.Err(); err != nil {
		return err
	}
	if record.RecordOrdinal != w.count {
		return fmt.Errorf("raw record ordinal %d, want contiguous ordinal %d", record.RecordOrdinal, w.count)
	}
	w.count++
	return nil
}

func (w *rawGenerationReplayWriter) Commit(ctx context.Context, accounting parser.BundleAccounting) (proffer.Ref, proffer.Ref, error) {
	if w.closed {
		return "", "", errors.New("raw generation writer is closed")
	}
	if err := ctx.Err(); err != nil {
		return "", "", err
	}
	w.closed = true
	if accounting != w.expected {
		return "", "", fmt.Errorf("retry raw generation accounting %+v does not match prior durable receipt %+v", accounting, w.expected)
	}
	return w.resultRef, w.receiptRef, nil
}

func (w *rawGenerationReplayWriter) Abort(context.Context) error { return nil }

var _ activities.RawGenerationWriter = (*rawGenerationWriter)(nil)
var _ activities.RawGenerationWriter = (*rawGenerationReplayWriter)(nil)

func tallyAccounting(tally *parser.BundleAccounting, record parser.RawRecordEnvelope) {
	tally.Attachments += uint64(len(record.Attachments))
	switch record.RecordStatus {
	case parser.StatusParsed:
		tally.Emitted++
	case parser.StatusRejected:
		tally.Rejected++
	case parser.StatusMalformed:
		tally.Malformed++
	case parser.StatusUnknown:
		tally.Unknown++
	case parser.StatusUnparsed:
		tally.Unparsed++
	case parser.StatusEnvelope:
	}
}

// rawHashConstruction assigns the exact context fingerprint construction.
// The persist stage, not the parser, owns this decision. Envelope and
// unparsed values are byte spans; every other status is a logical raw record.
func rawHashConstruction(status parser.RecordStatus) string {
	switch status {
	case parser.StatusEnvelope, parser.StatusUnparsed:
		return activities.CanonContextRawSpanFingerprint
	default:
		return activities.CanonContextRawRecordFingerprint
	}
}

// attachmentsMetadataJSON records raw-record attachments as provenance inside
// raw_record_identity.native_metadata. Attachments are not persisted as their
// own raw_record_identity rows in this contract: they typically locate
// container-extracted or otherwise-derived objects rather than a span of the
// record's own source bytes, so folding them into a raw row's byte-range
// contract would misrepresent that row's custody span.
func attachmentsMetadataJSON(attachmentRefs []parser.AttachmentRef) ([]byte, error) {
	if len(attachmentRefs) == 0 {
		return []byte(`{}`), nil
	}
	attachments := make([]map[string]any, 0, len(attachmentRefs))
	for _, attachment := range attachmentRefs {
		locator := map[string]any{
			"type":          string(attachment.Locator.Type),
			"storage_class": attachment.Locator.ObjectRef.StorageClass,
			"object_uri":    attachment.Locator.ObjectRef.URI,
		}
		if attachment.Locator.ByteRange != nil {
			locator["byte_offset"] = attachment.Locator.ByteRange.Offset
			locator["byte_length"] = attachment.Locator.ByteRange.Length
		}
		entry := map[string]any{
			"attachment_ordinal": attachment.AttachmentOrdinal,
			"locator":            locator,
		}
		if len(attachment.NativeMetadata) > 0 {
			var meta any
			if err := json.Unmarshal(attachment.NativeMetadata, &meta); err != nil {
				return nil, fmt.Errorf("decode attachment %d native metadata: %w", attachment.AttachmentOrdinal, err)
			}
			entry["native_metadata"] = meta
		}
		attachments = append(attachments, entry)
	}
	encoded, err := json.Marshal(map[string]any{"attachments": attachments})
	if err != nil {
		return nil, fmt.Errorf("encode attachment metadata: %w", err)
	}
	return encoded, nil
}

// resolveRawLocator maps one raw record's stored bytes or exact locator into
// the raw_record_identity storage contract. A locator resolves only to an
// object already bound to this source version via source_version_object — a
// bundle that references any other object is a hard persistence error, not a
// later reconciliation concern.
func resolveRawLocator(ctx context.Context, tx pgx.Tx, sourceID uuid.UUID, record parser.RawRecordEnvelope) (pgtype.UUID, *int64, *int64, []byte, error) {
	if record.StoredBytes != nil {
		stored := record.StoredBytes.Bytes
		if stored == nil {
			stored = []byte{}
		}
		return pgtype.UUID{}, nil, nil, stored, nil
	}
	if record.Locator == nil {
		return pgtype.UUID{}, nil, nil, nil, errors.New("raw record has neither a locator nor stored bytes")
	}
	objectID, err := resolveLocatorObject(ctx, tx, sourceID, record.Locator.ObjectRef)
	if err != nil {
		return pgtype.UUID{}, nil, nil, nil, err
	}
	var objectLength int64
	if err := tx.QueryRow(ctx, `SELECT byte_length FROM context.retained_object WHERE id = $1::uuid`, objectID).Scan(&objectLength); err != nil {
		return pgtype.UUID{}, nil, nil, nil, fmt.Errorf("resolve locator object byte length: %w", err)
	}
	offset, length, err := checkedLocatorRange(record.Locator.ByteRange, objectLength)
	if err != nil {
		return pgtype.UUID{}, nil, nil, nil, err
	}
	return pgtype.UUID{Bytes: [16]byte(objectID), Valid: true}, &offset, &length, nil, nil
}

func checkedLocatorRange(bounds *parser.ByteRange, objectLength int64) (int64, int64, error) {
	if objectLength < 0 {
		return 0, 0, errors.New("retained object has a negative byte length")
	}
	if bounds == nil {
		return 0, objectLength, nil
	}
	const maxInt64AsUint64 = uint64(1<<63 - 1)
	if bounds.Offset > maxInt64AsUint64 || bounds.Length > maxInt64AsUint64 {
		return 0, 0, errors.New("raw locator byte range exceeds PostgreSQL BIGINT coordinates")
	}
	offset, length := int64(bounds.Offset), int64(bounds.Length)
	if offset > objectLength || length > objectLength-offset {
		return 0, 0, fmt.Errorf(
			"raw locator byte range [%d,%d) exceeds retained object length %d", offset, offset+length, objectLength,
		)
	}
	return offset, length, nil
}

func resolveLocatorObject(ctx context.Context, tx pgx.Tx, sourceID uuid.UUID, objectRef parser.ObjectRef) (uuid.UUID, error) {
	var objectID uuid.UUID
	if err := tx.QueryRow(ctx, `
		SELECT object.id
		FROM context.retained_object object
		JOIN context.source_version_object member ON member.object_id = object.id
		WHERE member.source_version_id = $1::uuid
		  AND object.storage_class = $2
		  AND object.object_uri = $3`, sourceID, objectRef.StorageClass, objectRef.URI).Scan(&objectID); err != nil {
		return uuid.Nil, fmt.Errorf("resolve raw locator object %q: %w", objectRef.URI, err)
	}
	if objectRef.ContentHash != "" {
		var contentHash string
		if err := tx.QueryRow(ctx, `SELECT encode(content_sha256, 'hex') FROM context.retained_object WHERE id = $1::uuid`, objectID).Scan(&contentHash); err != nil {
			return uuid.Nil, fmt.Errorf("verify raw locator content hash: %w", err)
		}
		if contentHash != objectRef.ContentHash {
			return uuid.Nil, errors.New("raw locator content hash does not match the retained object")
		}
	}
	return objectID, nil
}

func validateRawGenerationSpec(spec activities.RawGenerationSpec) error {
	if strings.TrimSpace(spec.RequestID) == "" || spec.SourceVersionRef == "" || spec.BundleRef == "" {
		return errors.New("raw generation requires request, source version, and bundle references")
	}
	if strings.TrimSpace(spec.DeclaredFormat) == "" || strings.TrimSpace(spec.ParserID) == "" || strings.TrimSpace(spec.ParserVersion) == "" {
		return errors.New("raw generation requires declared format and parser identity")
	}
	if spec.Attempt < 1 {
		return errors.New("raw generation attempt must be positive")
	}
	return nil
}

func rawGenerationKey(spec activities.RawGenerationSpec) string {
	return fmt.Sprintf("raw-generation:%s:%s:%s", spec.RequestID, spec.SourceVersionRef, spec.BundleRef)
}

// discrepancy mirrors contracts/import/v1/schemas/reconciliation-receipt.schema.json's
// discrepancies[] item: every non-empty entry must carry an explanation.
type discrepancy struct {
	Field       string `json:"field"`
	Expected    any    `json:"expected,omitempty"`
	Observed    any    `json:"observed,omitempty"`
	Explanation string `json:"explanation"`
}

func encodeJSON(value any) ([]byte, error) {
	encoded, err := json.Marshal(value)
	if err != nil {
		return nil, fmt.Errorf("encode json: %w", err)
	}
	return encoded, nil
}

func resolveRawGenerationFromChain(ctx context.Context, tx pgx.Tx, ref proffer.Ref) (rawGenerationID, sourceVersionID uuid.UUID, err error) {
	receiptID, err := parseUUIDRef(ref, "raw generation chain")
	if err != nil {
		return uuid.Nil, uuid.Nil, err
	}
	var kind string
	if err := tx.QueryRow(ctx, `
		SELECT raw_generation_id, hash_kind,
		       (SELECT source_version_id FROM context.raw_generation WHERE id = hash_receipt.raw_generation_id)
		FROM context.hash_receipt hash_receipt
		WHERE hash_receipt.id = $1::uuid`, receiptID).Scan(&rawGenerationID, &kind, &sourceVersionID); err != nil {
		return uuid.Nil, uuid.Nil, fmt.Errorf("resolve raw generation chain %q: %w", ref, err)
	}
	if kind != "context_raw_generation_fingerprint" {
		return uuid.Nil, uuid.Nil, fmt.Errorf("raw generation chain reference %q is not a context_raw_generation_fingerprint receipt", ref)
	}
	return rawGenerationID, sourceVersionID, nil
}

func verifySourceOwnership(ctx context.Context, tx pgx.Tx, sourceID uuid.UUID, requestID, sourceVersionRef string) error {
	if sourceID.String() != sourceVersionRef {
		return errors.New("raw generation chain reference belongs to a different source version")
	}
	var workflowID, status string
	if err := tx.QueryRow(ctx, `SELECT workflow_id, status FROM context.source_version WHERE id = $1::uuid`, sourceID).Scan(&workflowID, &status); err != nil {
		return fmt.Errorf("read source version: %w", err)
	}
	if workflowID != requestID || status != "retained" {
		return errors.New("reconciliation requires a retained source version owned by this request")
	}
	return nil
}

func reconcileKey(stage stagegraph.StageID, spec activities.RawGenerationChainSpec) string {
	return fmt.Sprintf("%s:%s:%s", stage, spec.RequestID, spec.RawGenerationChainRef)
}

func verifyKey(spec activities.RawSourceVerificationSpec) string {
	return fmt.Sprintf("%s:%s:%s:%s:%s:%s", stagegraph.VerifyRawCoverageAgainstSource,
		spec.RequestID, spec.AccountingRef, spec.CoverageRef, spec.ContextSourceFingerprintRef, spec.RawGenerationChainRef)
}

func validateChainSpec(spec activities.RawGenerationChainSpec) error {
	if strings.TrimSpace(spec.RequestID) == "" || spec.SourceVersionRef == "" || spec.RawGenerationChainRef == "" {
		return errors.New("raw generation chain reconciliation requires request, source version, and chain references")
	}
	if spec.Attempt < 1 {
		return errors.New("raw generation chain reconciliation attempt must be positive")
	}
	return nil
}

func validateVerificationSpec(spec activities.RawSourceVerificationSpec) error {
	if strings.TrimSpace(spec.RequestID) == "" || spec.SourceVersionRef == "" {
		return errors.New("raw source verification requires request and source version references")
	}
	if spec.AccountingRef == "" || spec.CoverageRef == "" || spec.ContextSourceFingerprintRef == "" || spec.RawGenerationChainRef == "" {
		return errors.New("raw source verification requires accounting, coverage, context source fingerprint, and chain references")
	}
	if spec.Attempt < 1 {
		return errors.New("raw source verification attempt must be positive")
	}
	return nil
}

// priorReconciliationOutcome recovers a retry's already-durable outcome. The
// activity_receipt itself is always status='success' for these Activities —
// the business finding lives only in reconciliation_receipt.status — so a
// retry never re-derives its proof, it only replays the durable verdict.
func priorReconciliationOutcome(ctx context.Context, tx pgx.Tx, executionID uuid.UUID, noun string) (activities.ReconciliationOutcome, bool, error) {
	var receiptID uuid.UUID
	var resultJSON []byte
	err := tx.QueryRow(ctx, `
		SELECT id, result_ref FROM context.activity_receipt
		WHERE activity_execution_id = $1::uuid AND status = 'success'
		ORDER BY attempt DESC LIMIT 1`, executionID).Scan(&receiptID, &resultJSON)
	if errors.Is(err, pgx.ErrNoRows) {
		return activities.ReconciliationOutcome{}, false, nil
	}
	if err != nil {
		return activities.ReconciliationOutcome{}, false, fmt.Errorf("inspect prior %s receipt: %w", noun, err)
	}
	var ref rawRefResult
	if err := json.Unmarshal(resultJSON, &ref); err != nil || ref.RefKind != "reconciliation_receipt" || strings.TrimSpace(ref.RefID) == "" {
		return activities.ReconciliationOutcome{}, false, fmt.Errorf("prior %s activity receipt has an unexpected result reference", noun)
	}
	var status string
	var discrepancyCount int
	if err := tx.QueryRow(ctx, `
		SELECT status, jsonb_array_length(discrepancies) FROM context.reconciliation_receipt WHERE id = $1::uuid`, ref.RefID).Scan(&status, &discrepancyCount); err != nil {
		return activities.ReconciliationOutcome{}, false, fmt.Errorf("read prior %s reconciliation receipt: %w", noun, err)
	}
	outcome := activities.ReconciliationOutcome{ReceiptRef: proffer.Ref(receiptID.String())}
	switch status {
	case "success":
		outcome.Status = proffer.StatusSuccess
		outcome.Ref = proffer.Ref(ref.RefID)
	case "not_applicable":
		outcome.Status = proffer.StatusNotApplicable
		outcome.Reason = fmt.Sprintf("%s previously determined not applicable", noun)
	case "failed":
		outcome.Status = proffer.StatusFailed
		outcome.Reason = fmt.Sprintf("%s previously found %d discrepancy(ies)", noun, discrepancyCount)
	default:
		return activities.ReconciliationOutcome{}, false, fmt.Errorf("prior %s reconciliation receipt has unsupported status %q", noun, status)
	}
	return outcome, true, nil
}

// writeReconciliation writes the paired activity_receipt (always status
// 'success') and context.reconciliation_receipt (the business status/finding)
// in the trigger-required order: the activity_receipt's result_ref must name
// the reconciliation_receipt id before that row exists, so the id is minted
// first.
func (r *RawPipelineRepository) writeReconciliation(
	ctx context.Context, tx pgx.Tx, executionID uuid.UUID, attempt int32,
	kind, subjectRawGenerationID string, expected, observed []byte, discrepancies []discrepancy, status, reason string,
) (activities.ReconciliationOutcome, error) {
	discrepanciesJSON := []byte(`[]`)
	if len(discrepancies) > 0 {
		encoded, err := encodeJSON(discrepancies)
		if err != nil {
			return activities.ReconciliationOutcome{}, err
		}
		discrepanciesJSON = encoded
	}

	reconciliationID := uuid.New()
	receiptID := uuid.New()
	completedAt := r.now()
	resultJSON, err := encodeJSON(rawRefResult{RefKind: "reconciliation_receipt", RefID: reconciliationID.String()})
	if err != nil {
		return activities.ReconciliationOutcome{}, err
	}

	if _, err := tx.Exec(ctx, `
		INSERT INTO context.activity_receipt
		    (id, activity_execution_id, attempt, status, started_at, completed_at, result_ref)
		VALUES ($1::uuid, $2::uuid, $3, 'success', $4, $4, $5::jsonb)`,
		receiptID, executionID, attempt, completedAt, resultJSON); err != nil {
		return activities.ReconciliationOutcome{}, fmt.Errorf("write %s activity receipt: %w", kind, err)
	}
	if _, err := tx.Exec(ctx, `
		INSERT INTO context.reconciliation_receipt
		    (id, activity_receipt_id, reconciliation_kind, raw_generation_id, status, expected, observed, discrepancies, verified_at)
		VALUES ($1::uuid, $2::uuid, $3, $4::uuid, $5, $6::jsonb, $7::jsonb, $8::jsonb, $9)`,
		reconciliationID, receiptID, kind, subjectRawGenerationID, status, expected, observed, discrepanciesJSON, completedAt); err != nil {
		return activities.ReconciliationOutcome{}, fmt.Errorf("write %s reconciliation receipt: %w", kind, err)
	}

	outcome := activities.ReconciliationOutcome{ReceiptRef: proffer.Ref(receiptID.String())}
	switch status {
	case "success":
		outcome.Status = proffer.StatusSuccess
		outcome.Ref = proffer.Ref(reconciliationID.String())
	case "not_applicable":
		outcome.Status = proffer.StatusNotApplicable
		outcome.Reason = reason
	default:
		outcome.Status = proffer.StatusFailed
		outcome.Reason = reason
	}
	return outcome, nil
}

func loadPersistedAccounting(ctx context.Context, tx pgx.Tx, sourceID, rawGenerationID uuid.UUID) (rawGenerationResult, error) {
	var resultJSON []byte
	err := tx.QueryRow(ctx, `
		SELECT receipt.result_ref
		FROM context.activity_receipt receipt
		JOIN context.activity_execution execution ON execution.id = receipt.activity_execution_id
		WHERE execution.source_version_id = $1::uuid
		  AND execution.activity_name = $2
		  AND receipt.status = 'success'
		  AND receipt.result_ref->>'ref_kind' = 'raw_generation'
		  AND receipt.result_ref->>'ref_id' = $3::text
		ORDER BY receipt.attempt DESC LIMIT 1`,
		sourceID, string(stagegraph.PersistRawGeneration), rawGenerationID.String()).Scan(&resultJSON)
	if err != nil {
		return rawGenerationResult{}, fmt.Errorf("load persisted raw generation accounting: %w", err)
	}
	return decodeRawGenerationResult(resultJSON)
}

type observedRawCounts struct {
	Emitted, Rejected, Malformed, Unknown, Unparsed, Envelope, Total, Attachments uint64
	MinOrdinal, MaxOrdinal, DistinctOrdinals                                      int64
}

func (c observedRawCounts) contiguous() bool {
	return c.Total > 0 && c.MinOrdinal == 0 && c.MaxOrdinal == int64(c.Total)-1 && c.DistinctOrdinals == int64(c.Total)
}

func observedAccounting(ctx context.Context, tx pgx.Tx, rawGenerationID uuid.UUID) (observedRawCounts, error) {
	rows, err := tx.Query(ctx, `
		SELECT record_status, count(*)
		FROM context.raw_record_identity
		WHERE raw_generation_id = $1::uuid
		GROUP BY record_status`, rawGenerationID)
	if err != nil {
		return observedRawCounts{}, fmt.Errorf("count raw records by status: %w", err)
	}
	var counts observedRawCounts
	for rows.Next() {
		var status string
		var count int64
		if err := rows.Scan(&status, &count); err != nil {
			rows.Close()
			return observedRawCounts{}, err
		}
		switch parser.RecordStatus(status) {
		case parser.StatusParsed:
			counts.Emitted = uint64(count)
		case parser.StatusRejected:
			counts.Rejected = uint64(count)
		case parser.StatusMalformed:
			counts.Malformed = uint64(count)
		case parser.StatusUnknown:
			counts.Unknown = uint64(count)
		case parser.StatusUnparsed:
			counts.Unparsed = uint64(count)
		case parser.StatusEnvelope:
			counts.Envelope = uint64(count)
		}
		counts.Total += uint64(count)
	}
	if err := rows.Err(); err != nil {
		rows.Close()
		return observedRawCounts{}, err
	}
	rows.Close()

	if err := tx.QueryRow(ctx, `
		SELECT COALESCE(SUM(jsonb_array_length(COALESCE(native_metadata->'attachments', '[]'::jsonb))), 0)
		FROM context.raw_record_identity WHERE raw_generation_id = $1::uuid`, rawGenerationID).Scan(&counts.Attachments); err != nil {
		return observedRawCounts{}, fmt.Errorf("sum raw record attachments: %w", err)
	}
	if err := tx.QueryRow(ctx, `
		SELECT COALESCE(MIN(record_ordinal), -1), COALESCE(MAX(record_ordinal), -1), COUNT(DISTINCT record_ordinal)
		FROM context.raw_record_identity WHERE raw_generation_id = $1::uuid`, rawGenerationID).Scan(
		&counts.MinOrdinal, &counts.MaxOrdinal, &counts.DistinctOrdinals); err != nil {
		return observedRawCounts{}, fmt.Errorf("inspect raw record ordinals: %w", err)
	}
	return counts, nil
}

func compareAccounting(expected rawGenerationResult, observed observedRawCounts) []discrepancy {
	var out []discrepancy
	check := func(field string, want, got uint64) {
		if want != got {
			out = append(out, discrepancy{
				Field: field, Expected: want, Observed: got,
				Explanation: fmt.Sprintf("%s count diverged between the persisted receipt and durable raw records", field),
			})
		}
	}
	check("emitted", expected.Emitted, observed.Emitted)
	check("rejected", expected.Rejected, observed.Rejected)
	check("malformed", expected.Malformed, observed.Malformed)
	check("unknown", expected.Unknown, observed.Unknown)
	check("unparsed", expected.Unparsed, observed.Unparsed)
	check("attachments", expected.Attachments, observed.Attachments)
	check("total", expected.Total, observed.Total)
	if !observed.contiguous() {
		out = append(out, discrepancy{
			Field:       "record_ordinal",
			Explanation: "raw record ordinals are not a contiguous zero-based sequence",
		})
	}
	return out
}

func (r *RawPipelineRepository) ReconcileRecordAccounting(ctx context.Context, spec activities.RawGenerationChainSpec) (activities.ReconciliationOutcome, error) {
	if err := validateChainSpec(spec); err != nil {
		return activities.ReconciliationOutcome{}, err
	}
	tx, err := r.db.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return activities.ReconciliationOutcome{}, fmt.Errorf("begin record accounting transaction: %w", err)
	}
	rollback := true
	defer func() {
		if rollback {
			cleanupCtx, cancel := boundedCleanup(ctx)
			defer cancel()
			_ = tx.Rollback(cleanupCtx)
		}
	}()

	rawGenerationID, sourceID, err := resolveRawGenerationFromChain(ctx, tx, spec.RawGenerationChainRef)
	if err != nil {
		return activities.ReconciliationOutcome{}, err
	}
	if err := verifySourceOwnership(ctx, tx, sourceID, spec.RequestID, string(spec.SourceVersionRef)); err != nil {
		return activities.ReconciliationOutcome{}, err
	}
	executionID, err := parserEnsureExecution(ctx, tx, sourceID, spec.RequestID, string(stagegraph.ReconcileRecordAccounting), reconcileKey(stagegraph.ReconcileRecordAccounting, spec))
	if err != nil {
		return activities.ReconciliationOutcome{}, err
	}
	if outcome, found, err := priorReconciliationOutcome(ctx, tx, executionID, "record accounting"); err != nil {
		return activities.ReconciliationOutcome{}, err
	} else if found {
		return outcome, nil
	}

	expected, err := loadPersistedAccounting(ctx, tx, sourceID, rawGenerationID)
	if err != nil {
		return activities.ReconciliationOutcome{}, err
	}
	observed, err := observedAccounting(ctx, tx, rawGenerationID)
	if err != nil {
		return activities.ReconciliationOutcome{}, err
	}
	discrepancies := compareAccounting(expected, observed)

	expectedJSON, err := encodeJSON(map[string]any{
		"emitted": expected.Emitted, "rejected": expected.Rejected, "malformed": expected.Malformed,
		"unknown": expected.Unknown, "unparsed": expected.Unparsed, "attachments": expected.Attachments,
		"total": expected.Total,
	})
	if err != nil {
		return activities.ReconciliationOutcome{}, err
	}
	observedJSON, err := encodeJSON(map[string]any{
		"emitted": observed.Emitted, "rejected": observed.Rejected, "malformed": observed.Malformed,
		"unknown": observed.Unknown, "unparsed": observed.Unparsed, "attachments": observed.Attachments,
		"total": observed.Total, "envelope": observed.Envelope, "contiguous": observed.contiguous(),
	})
	if err != nil {
		return activities.ReconciliationOutcome{}, err
	}

	status, reason := "success", ""
	if len(discrepancies) > 0 {
		status = "failed"
		reason = fmt.Sprintf("record accounting found %d discrepancy(ies)", len(discrepancies))
	}

	outcome, err := r.writeReconciliation(ctx, tx, executionID, spec.Attempt, "record_accounting", rawGenerationID.String(),
		expectedJSON, observedJSON, discrepancies, status, reason)
	if err != nil {
		return activities.ReconciliationOutcome{}, err
	}
	if err := tx.Commit(ctx); err != nil {
		return activities.ReconciliationOutcome{}, fmt.Errorf("commit record accounting: %w", err)
	}
	rollback = false
	return outcome, nil
}

func loadOriginalObject(ctx context.Context, tx pgx.Tx, sourceID uuid.UUID) (uuid.UUID, int64, error) {
	var objectID uuid.UUID
	var byteLength int64
	if err := tx.QueryRow(ctx, `
		SELECT object.id, object.byte_length
		FROM context.source_version version
		JOIN context.retained_object object ON object.id = version.original_object_id
		WHERE version.id = $1::uuid`, sourceID).Scan(&objectID, &byteLength); err != nil {
		return uuid.Nil, 0, fmt.Errorf("resolve original retained object: %w", err)
	}
	return objectID, byteLength, nil
}

type byteRange struct{ Offset, Length int64 }

func loadLocatorRanges(ctx context.Context, tx pgx.Tx, rawGenerationID, originalObjectID uuid.UUID) ([]byteRange, error) {
	rows, err := tx.Query(ctx, `
		SELECT byte_offset, byte_length
		FROM context.raw_record_identity
		WHERE raw_generation_id = $1::uuid AND locator_object_id = $2::uuid
		ORDER BY byte_offset`, rawGenerationID, originalObjectID)
	if err != nil {
		return nil, fmt.Errorf("load raw record byte ranges: %w", err)
	}
	defer rows.Close()
	var ranges []byteRange
	for rows.Next() {
		var offset, length int64
		if err := rows.Scan(&offset, &length); err != nil {
			return nil, err
		}
		ranges = append(ranges, byteRange{Offset: offset, Length: length})
	}
	return ranges, rows.Err()
}

type gapRange struct {
	Offset int64 `json:"offset"`
	Length int64 `json:"length"`
}

// mergeAndGapRanges merges overlapping/adjacent byte ranges, then walks the
// merged set to compute total covered bytes and the exact uncovered gaps
// within [0, totalLength) — "explain every gap" per the boundary doc.
func mergeAndGapRanges(ranges []byteRange, totalLength int64) (covered int64, gaps []gapRange) {
	sorted := append([]byteRange(nil), ranges...)
	sort.Slice(sorted, func(i, j int) bool { return sorted[i].Offset < sorted[j].Offset })
	var merged []byteRange
	for _, item := range sorted {
		if item.Length <= 0 {
			continue
		}
		start, end := item.Offset, item.Offset+item.Length
		if len(merged) > 0 && start <= merged[len(merged)-1].Offset+merged[len(merged)-1].Length {
			last := &merged[len(merged)-1]
			if end > last.Offset+last.Length {
				last.Length = end - last.Offset
			}
			continue
		}
		merged = append(merged, byteRange{Offset: start, Length: end - start})
	}
	var cursor int64
	for _, m := range merged {
		if m.Offset > cursor {
			gaps = append(gaps, gapRange{Offset: cursor, Length: m.Offset - cursor})
		}
		covered += m.Length
		cursor = m.Offset + m.Length
	}
	if cursor < totalLength {
		gaps = append(gaps, gapRange{Offset: cursor, Length: totalLength - cursor})
	}
	return covered, gaps
}

func (r *RawPipelineRepository) ReconcileByteCoverage(ctx context.Context, spec activities.RawGenerationChainSpec) (activities.ReconciliationOutcome, error) {
	if err := validateChainSpec(spec); err != nil {
		return activities.ReconciliationOutcome{}, err
	}
	tx, err := r.db.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return activities.ReconciliationOutcome{}, fmt.Errorf("begin byte coverage transaction: %w", err)
	}
	rollback := true
	defer func() {
		if rollback {
			cleanupCtx, cancel := boundedCleanup(ctx)
			defer cancel()
			_ = tx.Rollback(cleanupCtx)
		}
	}()

	rawGenerationID, sourceID, err := resolveRawGenerationFromChain(ctx, tx, spec.RawGenerationChainRef)
	if err != nil {
		return activities.ReconciliationOutcome{}, err
	}
	if err := verifySourceOwnership(ctx, tx, sourceID, spec.RequestID, string(spec.SourceVersionRef)); err != nil {
		return activities.ReconciliationOutcome{}, err
	}
	executionID, err := parserEnsureExecution(ctx, tx, sourceID, spec.RequestID, string(stagegraph.ReconcileByteCoverage), reconcileKey(stagegraph.ReconcileByteCoverage, spec))
	if err != nil {
		return activities.ReconciliationOutcome{}, err
	}
	if outcome, found, err := priorReconciliationOutcome(ctx, tx, executionID, "byte coverage"); err != nil {
		return activities.ReconciliationOutcome{}, err
	} else if found {
		return outcome, nil
	}

	originalObjectID, sourceByteLength, err := loadOriginalObject(ctx, tx, sourceID)
	if err != nil {
		return activities.ReconciliationOutcome{}, err
	}
	ranges, err := loadLocatorRanges(ctx, tx, rawGenerationID, originalObjectID)
	if err != nil {
		return activities.ReconciliationOutcome{}, err
	}

	var expected, observed []byte
	var discrepancies []discrepancy
	var status, reason string
	if len(ranges) == 0 {
		expected, err = encodeJSON(map[string]any{"source_byte_length": sourceByteLength})
		if err != nil {
			return activities.ReconciliationOutcome{}, err
		}
		observed, err = encodeJSON(map[string]any{"locator_based_records": 0})
		if err != nil {
			return activities.ReconciliationOutcome{}, err
		}
		status = "not_applicable"
		reason = "no locator-based raw records reference the original retained object; byte coverage is not derivable"
	} else {
		covered, gaps := mergeAndGapRanges(ranges, sourceByteLength)
		expected, err = encodeJSON(map[string]any{"source_byte_length": sourceByteLength})
		if err != nil {
			return activities.ReconciliationOutcome{}, err
		}
		observed, err = encodeJSON(map[string]any{"covered_bytes": covered, "gaps": gaps})
		if err != nil {
			return activities.ReconciliationOutcome{}, err
		}
		status = "success"
		if covered != sourceByteLength || len(gaps) > 0 {
			status = "failed"
			reason = fmt.Sprintf("byte coverage left %d gap(s) totaling %d uncovered byte(s)", len(gaps), sourceByteLength-covered)
			discrepancies = []discrepancy{{
				Field: "byte_coverage", Expected: sourceByteLength, Observed: covered, Explanation: reason,
			}}
		}
	}

	outcome, err := r.writeReconciliation(ctx, tx, executionID, spec.Attempt, "byte_coverage", rawGenerationID.String(),
		expected, observed, discrepancies, status, reason)
	if err != nil {
		return activities.ReconciliationOutcome{}, err
	}
	if err := tx.Commit(ctx); err != nil {
		return activities.ReconciliationOutcome{}, fmt.Errorf("commit byte coverage: %w", err)
	}
	rollback = false
	return outcome, nil
}

func loadReconciliationStatus(ctx context.Context, tx pgx.Tx, ref proffer.Ref, wantKind string, rawGenerationID uuid.UUID) (string, error) {
	reconciliationID, err := parseUUIDRef(ref, wantKind)
	if err != nil {
		return "", err
	}
	var status, kind string
	var subjectRawGenerationID uuid.UUID
	if err := tx.QueryRow(ctx, `
		SELECT status, reconciliation_kind, raw_generation_id
		FROM context.reconciliation_receipt WHERE id = $1::uuid`, reconciliationID).Scan(&status, &kind, &subjectRawGenerationID); err != nil {
		return "", fmt.Errorf("resolve %s reconciliation receipt: %w", wantKind, err)
	}
	if kind != wantKind {
		return "", fmt.Errorf("reconciliation reference %q is not a %s receipt", ref, wantKind)
	}
	if subjectRawGenerationID != rawGenerationID {
		return "", fmt.Errorf("%s reconciliation receipt belongs to a different raw generation", wantKind)
	}
	return status, nil
}

func loadHashReceiptDigest(ctx context.Context, tx pgx.Tx, ref proffer.Ref, wantKind string) (digestHex, construction string, sourceVersionID uuid.UUID, err error) {
	receiptID, err := parseUUIDRef(ref, wantKind)
	if err != nil {
		return "", "", uuid.Nil, err
	}
	var digest []byte
	var kind string
	var sourceVersion, rawGeneration pgtype.UUID
	if err := tx.QueryRow(ctx, `
		SELECT digest, construction, hash_kind, source_version_id, raw_generation_id
		FROM context.hash_receipt WHERE id = $1::uuid`, receiptID).Scan(&digest, &construction, &kind, &sourceVersion, &rawGeneration); err != nil {
		return "", "", uuid.Nil, fmt.Errorf("resolve %s hash receipt: %w", wantKind, err)
	}
	if kind != wantKind {
		return "", "", uuid.Nil, fmt.Errorf("hash reference %q is not a %s receipt", ref, wantKind)
	}
	switch {
	case sourceVersion.Valid:
		return hex.EncodeToString(digest), construction, uuid.UUID(sourceVersion.Bytes), nil
	case rawGeneration.Valid:
		var resolvedSourceID uuid.UUID
		if err := tx.QueryRow(ctx, `SELECT source_version_id FROM context.raw_generation WHERE id = $1::uuid`, uuid.UUID(rawGeneration.Bytes)).Scan(&resolvedSourceID); err != nil {
			return "", "", uuid.Nil, fmt.Errorf("resolve raw generation source version: %w", err)
		}
		return hex.EncodeToString(digest), construction, resolvedSourceID, nil
	default:
		return "", "", uuid.Nil, fmt.Errorf("%s hash receipt lacks a resolvable source version", wantKind)
	}
}

// recomputeRawGenerationFromBytes reopens every retained raw member and hashes
// the bytes again. It never reads context.hash_receipt.digest, so verification
// cannot pass by merely refolding the fingerprint Activity's stored claims.
func recomputeRawGenerationFromBytes(ctx context.Context, tx pgx.Tx, rawGenerationID uuid.UUID, open ObjectOpener) (string, error) {
	rows, err := tx.Query(ctx, `
		SELECT raw.id::text, raw.record_ordinal, raw.raw_hash_construction,
		       raw.stored_bytes, COALESCE(object.storage_class, ''),
		       COALESCE(object.object_uri, ''),
		       CASE WHEN object.storage_class = 'inline'
		            AND raw.byte_offset >= 0 AND raw.byte_length >= 0
		            AND raw.byte_offset + raw.byte_length <= octet_length(object.inline_bytes)
		            THEN substring(object.inline_bytes FROM raw.byte_offset + 1 FOR raw.byte_length)
		       END,
		       COALESCE(raw.byte_offset, 0), COALESCE(raw.byte_length, 0)
		FROM context.raw_record_identity raw
		LEFT JOIN context.retained_object object ON object.id = raw.locator_object_id
		WHERE raw.raw_generation_id = $1::uuid
		ORDER BY raw.record_ordinal`, rawGenerationID)
	if err != nil {
		return "", fmt.Errorf("open ordered retained raw members: %w", err)
	}
	stream := &byteRows{rows: rows, open: open, raw: true}
	return recomputeRawGenerationFingerprint(ctx, stream)
}

// recomputeRawGenerationFingerprint is the byte-reading core used by the
// PostgreSQL verifier. Keeping it stream-oriented makes the retained-byte
// behavior executable in isolation without replacing PostgreSQL's schema
// contract with a SQL-string mock.
func recomputeRawGenerationFingerprint(ctx context.Context, stream activities.ByteMemberStream) (string, error) {
	if stream == nil {
		return "", errors.New("retained raw member stream is required")
	}
	defer stream.Close()
	chain := custodyhash.NewChain("")
	var count int64
	for {
		member, nextErr := stream.Next(ctx)
		if errors.Is(nextErr, io.EOF) {
			break
		}
		if nextErr != nil {
			return "", fmt.Errorf("read retained raw member %d: %w", count, nextErr)
		}
		if member.Ordinal != count {
			_ = member.Reader.Close()
			return "", fmt.Errorf("retained raw member ordinal %d, want %d", member.Ordinal, count)
		}
		if member.Canon != activities.CanonContextRawRecordFingerprint && member.Canon != activities.CanonContextRawSpanFingerprint {
			_ = member.Reader.Close()
			return "", fmt.Errorf("raw member has unsupported construction %q", member.Canon)
		}
		digest, hashErr := custodyhash.HashReaderH1(member.Reader)
		closeErr := member.Reader.Close()
		if hashErr != nil {
			return "", fmt.Errorf("hash retained raw member %q: %w", member.SubjectRef, hashErr)
		}
		if closeErr != nil {
			return "", fmt.Errorf("close retained raw member %q: %w", member.SubjectRef, closeErr)
		}
		chain.Add(digest)
		count++
	}
	if count == 0 {
		return "", errors.New("raw generation has no retained raw members to verify")
	}
	return chain.Value(), nil
}

func recomputeSourceFingerprint(reader io.ReadCloser) (string, error) {
	if reader == nil {
		return "", errors.New("retained source reader is required")
	}
	digest, hashErr := custodyhash.HashReaderH1(reader)
	closeErr := reader.Close()
	if hashErr != nil {
		return "", fmt.Errorf("hash retained original bytes: %w", hashErr)
	}
	if closeErr != nil {
		return "", fmt.Errorf("close retained original bytes: %w", closeErr)
	}
	return digest, nil
}

func recomputeSourceFromBytes(ctx context.Context, tx pgx.Tx, sourceVersionID uuid.UUID, open ObjectOpener) (string, error) {
	var storageClass, objectURI string
	var inline []byte
	if err := tx.QueryRow(ctx, `
		SELECT object.storage_class, object.object_uri, object.inline_bytes
		FROM context.source_version source
		JOIN context.retained_object object ON object.id = source.original_object_id
		WHERE source.id = $1::uuid`, sourceVersionID).Scan(&storageClass, &objectURI, &inline); err != nil {
		return "", fmt.Errorf("resolve retained original bytes: %w", err)
	}
	var reader io.ReadCloser
	if storageClass == "inline" {
		reader = io.NopCloser(bytes.NewReader(inline))
	} else {
		if open == nil {
			return "", fmt.Errorf("non-inline retained original %q requires an ObjectOpener", objectURI)
		}
		var err error
		reader, err = open(ctx, objectURI)
		if err != nil {
			return "", fmt.Errorf("open retained original %q: %w", objectURI, err)
		}
	}
	return recomputeSourceFingerprint(reader)
}

func (r *RawPipelineRepository) VerifyRawCoverageAgainstSource(ctx context.Context, spec activities.RawSourceVerificationSpec) (activities.ReconciliationOutcome, error) {
	if err := validateVerificationSpec(spec); err != nil {
		return activities.ReconciliationOutcome{}, err
	}
	tx, err := r.db.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return activities.ReconciliationOutcome{}, fmt.Errorf("begin raw source verification transaction: %w", err)
	}
	rollback := true
	defer func() {
		if rollback {
			cleanupCtx, cancel := boundedCleanup(ctx)
			defer cancel()
			_ = tx.Rollback(cleanupCtx)
		}
	}()

	rawGenerationID, sourceID, err := resolveRawGenerationFromChain(ctx, tx, spec.RawGenerationChainRef)
	if err != nil {
		return activities.ReconciliationOutcome{}, err
	}
	if err := verifySourceOwnership(ctx, tx, sourceID, spec.RequestID, string(spec.SourceVersionRef)); err != nil {
		return activities.ReconciliationOutcome{}, err
	}
	executionID, err := parserEnsureExecution(ctx, tx, sourceID, spec.RequestID, string(stagegraph.VerifyRawCoverageAgainstSource), verifyKey(spec))
	if err != nil {
		return activities.ReconciliationOutcome{}, err
	}
	if outcome, found, err := priorReconciliationOutcome(ctx, tx, executionID, "raw/source verification"); err != nil {
		return activities.ReconciliationOutcome{}, err
	} else if found {
		if outcome.Status == proffer.StatusSuccess {
			if err := sealRawGeneration(ctx, tx, rawGenerationID, r.now()); err != nil {
				return activities.ReconciliationOutcome{}, err
			}
			if err := tx.Commit(ctx); err != nil {
				return activities.ReconciliationOutcome{}, fmt.Errorf("commit replayed raw source verification seal: %w", err)
			}
			rollback = false
		}
		return outcome, nil
	}

	accountingStatus, err := loadReconciliationStatus(ctx, tx, spec.AccountingRef, "record_accounting", rawGenerationID)
	if err != nil {
		return activities.ReconciliationOutcome{}, err
	}
	coverageStatus, err := loadReconciliationStatus(ctx, tx, spec.CoverageRef, "byte_coverage", rawGenerationID)
	if err != nil {
		return activities.ReconciliationOutcome{}, err
	}
	storedGenerationFingerprint, _, chainSourceID, err := loadHashReceiptDigest(ctx, tx, spec.RawGenerationChainRef, "context_raw_generation_fingerprint")
	if err != nil {
		return activities.ReconciliationOutcome{}, err
	}
	if chainSourceID != sourceID {
		return activities.ReconciliationOutcome{}, errors.New("raw generation chain reference belongs to a different source version")
	}
	sourceFingerprint, _, fingerprintSourceID, err := loadHashReceiptDigest(ctx, tx, spec.ContextSourceFingerprintRef, "context_source_fingerprint")
	if err != nil {
		return activities.ReconciliationOutcome{}, err
	}
	if fingerprintSourceID != sourceID {
		return activities.ReconciliationOutcome{}, errors.New("context source fingerprint reference belongs to a different source version")
	}
	recomputedGenerationFingerprint, err := recomputeRawGenerationFromBytes(ctx, tx, rawGenerationID, r.open)
	if err != nil {
		return activities.ReconciliationOutcome{}, err
	}
	recomputedSourceFingerprint, err := recomputeSourceFromBytes(ctx, tx, sourceID, r.open)
	if err != nil {
		return activities.ReconciliationOutcome{}, err
	}

	expected := map[string]any{
		"context_raw_generation_fingerprint": storedGenerationFingerprint, "verification_mode": "retained_bytes_recomputation",
		"context_source_fingerprint": sourceFingerprint, "accounting_status": accountingStatus, "coverage_status": coverageStatus,
	}
	observed := map[string]any{
		"context_raw_generation_fingerprint": recomputedGenerationFingerprint, "verification_mode": "retained_bytes_recomputation",
		"context_source_fingerprint": recomputedSourceFingerprint, "accounting_status": accountingStatus, "coverage_status": coverageStatus,
	}
	contextCoverage := false
	if coverageStatus == "not_applicable" && accountingStatus == "success" &&
		storedGenerationFingerprint == recomputedGenerationFingerprint && sourceFingerprint == recomputedSourceFingerprint {
		proof, proofErr := loadDuckDBContextCoverageProof(ctx, tx, rawGenerationID, sourceID, spec.RequestID)
		if proofErr != nil {
			return activities.ReconciliationOutcome{}, proofErr
		}
		if proof != nil {
			contextCoverage = true
			for key, value := range proof {
				observed[key] = value
				expected[key] = value
			}
		}
	}

	var discrepancies []discrepancy
	if recomputedGenerationFingerprint != storedGenerationFingerprint {
		discrepancies = append(discrepancies, discrepancy{
			Field: "context_raw_generation_fingerprint", Expected: storedGenerationFingerprint, Observed: recomputedGenerationFingerprint,
			Explanation: "independently recomputed raw-generation context fingerprint does not match the stored digest",
		})
	}
	if recomputedSourceFingerprint != sourceFingerprint {
		discrepancies = append(discrepancies, discrepancy{
			Field: "context_source_fingerprint", Expected: sourceFingerprint, Observed: recomputedSourceFingerprint,
			Explanation: "independently recomputed retained original bytes do not match the stored context source fingerprint",
		})
	}
	if accountingStatus != "success" {
		discrepancies = append(discrepancies, discrepancy{
			Field: "accounting_status", Expected: "success", Observed: accountingStatus,
			Explanation: "record accounting reconciliation did not succeed",
		})
	}
	if coverageStatus != "success" && !contextCoverage {
		discrepancies = append(discrepancies, discrepancy{
			Field: "coverage_status", Expected: "success", Observed: coverageStatus,
			Explanation: "byte coverage reconciliation did not prove complete source coverage",
		})
	}
	status, reason := "success", ""
	if len(discrepancies) > 0 {
		status = "failed"
		reason = fmt.Sprintf("raw/source verification found %d discrepancy(ies)", len(discrepancies))
	}

	expectedJSON, err := encodeJSON(expected)
	if err != nil {
		return activities.ReconciliationOutcome{}, err
	}
	observedJSON, err := encodeJSON(observed)
	if err != nil {
		return activities.ReconciliationOutcome{}, err
	}

	outcome, err := r.writeReconciliation(ctx, tx, executionID, spec.Attempt, "raw_source_verification", rawGenerationID.String(),
		expectedJSON, observedJSON, discrepancies, status, reason)
	if err != nil {
		return activities.ReconciliationOutcome{}, err
	}
	if outcome.Status == proffer.StatusSuccess {
		if err := sealRawGeneration(ctx, tx, rawGenerationID, r.now()); err != nil {
			return activities.ReconciliationOutcome{}, err
		}
	}
	if err := tx.Commit(ctx); err != nil {
		return activities.ReconciliationOutcome{}, fmt.Errorf("commit raw source verification: %w", err)
	}
	rollback = false
	return outcome, nil
}

// D-149: DuckDB read_xml does not expose source offsets. Context verification
// may instead prove source SHA, exact inserted row fingerprints and accounting.
// This is not a byte-coverage or promotion assertion. Durable source-bound
// handler validation and every row's pinned template are checked independently.
func loadDuckDBContextCoverageProof(ctx context.Context, tx pgx.Tx, generationID, sourceID uuid.UUID, requestID string) (map[string]any, error) {
	var declared, detected, validationID string
	err := tx.QueryRow(ctx, `SELECT generation.format_id, format.format_id, validation.id::text
		FROM context.raw_generation generation
		JOIN context.source_version source ON source.id=generation.source_version_id
		JOIN context.handler_selection_validation validation ON validation.source_version_id=source.id
		JOIN context.activity_receipt receipt ON receipt.id=validation.activity_receipt_id AND receipt.status='success'
		JOIN context.activity_execution execution ON execution.id=receipt.activity_execution_id
		JOIN context.handler_selection_decision decision ON decision.id=validation.decision_id
		JOIN context.handler_recommendation recommendation ON recommendation.id=validation.recommendation_id
		JOIN context.handler_detected_format format ON format.id=recommendation.detected_format_id
		JOIN context.handler_content_signature signature ON signature.id=recommendation.content_signature_id
		JOIN context.handler_compatibility compatibility ON compatibility.id=validation.compatibility_id
		WHERE generation.id=$1 AND generation.source_version_id=$2 AND source.workflow_id=$3
		  AND generation.parser_id=$4 AND generation.parser_version=$5 AND generation.extraction_bundle_object_id IS NOT NULL
		  AND validation.created_at<=generation.created_at
		  AND execution.source_version_id=$2 AND execution.workflow_id=$3
		  AND decision.source_version_id=$2 AND decision.recommendation_id=recommendation.id AND decision.compatibility_id=compatibility.id
		  AND recommendation.source_version_id=$2 AND recommendation.original_object_id=source.original_object_id
		  AND format.source_version_id=$2 AND signature.source_version_id=$2 AND signature.original_object_id=source.original_object_id
		  AND compatibility.detected_format_id=format.id AND compatibility.handler_id=generation.parser_id
		  AND compatibility.handler_version=generation.parser_version AND compatibility.execution_path='duckdb'
		ORDER BY validation.created_at DESC LIMIT 1`, generationID, sourceID, requestID,
		activities.StructuredELTParserID, activities.StructuredELTParserVersion).Scan(&declared, &detected, &validationID)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("resolve source-bound DuckDB context verification: %w", err)
	}
	format, err := activities.StructuredELTFormatForDeclaredFormat(detected)
	if err != nil {
		return nil, nil
	}
	template, err := activities.StructuredELTTemplateForFormat(format)
	if err != nil {
		return nil, nil
	}
	if err = parser.FormatID(declared).Validate(); err != nil {
		return nil, err
	}
	table := pgx.Identifier{"context", "raw_" + declared}.Sanitize()
	var valid bool
	err = tx.QueryRow(ctx, fmt.Sprintf(`SELECT count(*)>0 AND bool_and(raw.stored_bytes IS NOT NULL
		AND raw.locator_object_id IS NULL AND raw.record_status='parsed'
		AND COALESCE(subtype.native_metadata->>'duckdb_template','')=$2)
		FROM context.raw_record_identity raw LEFT JOIN %s subtype ON subtype.raw_record_id=raw.id
		WHERE raw.raw_generation_id=$1`, table), generationID, template).Scan(&valid)
	if err != nil {
		return nil, fmt.Errorf("verify every DuckDB raw-row template: %w", err)
	}
	if !valid {
		return nil, nil
	}
	return map[string]any{"coverage_mode": "duckdb_context_rows_without_source_offsets",
		"byte_coverage_proven": false, "coverage_reason": "DuckDB extraction supplies no source offsets; source fingerprint, inserted-row fingerprints and record accounting were independently verified; promotion reparses original bytes",
		"handler_validation_ref": validationID, "duckdb_template": template, "handler_id": activities.StructuredELTParserID,
		"handler_version": activities.StructuredELTParserVersion}, nil
}

// sealRawGeneration performs the sole legitimate raw-generation lifecycle
// transition. SQL 0036's transition trigger independently requires complete
// subtype rows, context fingerprints, and successful accounting, byte-coverage,
// and raw/source verification receipts. Keeping the final receipt and seal in
// one transaction prevents a generation from being observed as verified but
// still mutable.
func sealRawGeneration(ctx context.Context, tx pgx.Tx, rawGenerationID uuid.UUID, sealedAt time.Time) error {
	tag, err := tx.Exec(ctx, `
		UPDATE context.raw_generation
		SET status = 'sealed', sealed_at = $2, sealed_by = $3
		WHERE id = $1::uuid AND status = 'open'`,
		rawGenerationID, sealedAt.UTC(), string(stagegraph.VerifyRawCoverageAgainstSource))
	if err != nil {
		return fmt.Errorf("seal verified raw generation: %w", err)
	}
	if tag.RowsAffected() == 1 {
		return nil
	}
	var status string
	if err := tx.QueryRow(ctx, `SELECT status FROM context.raw_generation WHERE id = $1::uuid`, rawGenerationID).Scan(&status); err != nil {
		return fmt.Errorf("resolve raw generation seal state: %w", err)
	}
	if status != "sealed" {
		return fmt.Errorf("raw generation %s has non-sealable status %q", rawGenerationID, status)
	}
	return nil
}

var _ activities.RawPipelineRepository = (*RawPipelineRepository)(nil)
