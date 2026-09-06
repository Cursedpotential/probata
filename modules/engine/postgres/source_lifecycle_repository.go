package postgres

// This file is the PostgreSQL boundary for the two source-lifecycle
// Activities.  Registration establishes identity; retention attaches one
// immutable original object.  Neither operation parses, normalizes, hashes,
// or writes evidence data.

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/Cursedpotential/probata/engine/activities"
	"github.com/Cursedpotential/probata/engine/proffer"
	"github.com/Cursedpotential/probata/engine/stagegraph"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
)

const lifecycleCleanupTimeout = 5 * time.Second

// ImmutableAcquisition is the already-resolved immutable object metadata for
// an acquisition registry. ContentSHA256 is supplied by the acquisition
// boundary; this lifecycle Activity intentionally never computes it. Inline
// bytes are permitted only for storage_class=inline and are copied into the
// retained-object row.
type ImmutableAcquisition struct {
	StorageClass  string
	ObjectURI     string
	ContentSHA256 []byte
	ByteLength    int64
	InlineBytes   []byte
}

// ImmutableAcquisitionResolver resolves an acquisition pointer outside the
// database transaction. Implementations must attest that the returned object
// is immutable and that ContentSHA256/ByteLength describe exactly that object.
// The pointer and any bytes remain Activity-local; they are never sent through
// Temporal history.
type ImmutableAcquisitionResolver func(context.Context, proffer.Ref) (ImmutableAcquisition, error)

// SourceLifecycleRepository implements activities.SourceLifecycleStore.
type SourceLifecycleRepository struct {
	db      DB
	resolve ImmutableAcquisitionResolver
	clock   func() time.Time
}

func NewSourceLifecycleRepository(db DB, resolve ImmutableAcquisitionResolver) (*SourceLifecycleRepository, error) {
	if db == nil {
		return nil, errors.New("postgres source lifecycle repository: database is required")
	}
	if resolve == nil {
		return nil, errors.New("postgres source lifecycle repository: immutable acquisition resolver is required")
	}
	return &SourceLifecycleRepository{db: db, resolve: resolve, clock: func() time.Time { return time.Now().UTC() }}, nil
}

func (r *SourceLifecycleRepository) RegisterSource(ctx context.Context, spec activities.SourceRegistrationSpec) (proffer.Ref, proffer.Ref, error) {
	if err := validateRegistrationSpec(spec); err != nil {
		return "", "", err
	}
	tx, err := r.db.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return "", "", fmt.Errorf("begin source registration transaction: %w", err)
	}
	rollback := true
	defer func() {
		if rollback {
			cleanupCtx, cancel := lifecycleCleanup(ctx)
			defer cancel()
			_ = tx.Rollback(cleanupCtx)
		}
	}()
	if spec.SourceContextRef != "" {
		var valid bool
		if err := tx.QueryRow(ctx, `
			SELECT EXISTS (
				SELECT 1 FROM context.proffer_source_context_revision
				WHERE source_context_ref=$1::uuid AND request_id=$2
				  AND matter_id=$3::uuid AND court_case_id=$4::uuid AND source_ref=$5
			)`, spec.SourceContextRef, spec.RequestID, spec.MatterID, spec.CourtCaseID, spec.AcquisitionRef).Scan(&valid); err != nil {
			return "", "", fmt.Errorf("validate registration source context: %w", err)
		}
		if !valid {
			return "", "", errors.New("registration source context does not own the requested intake scope")
		}
	}
	var sourceContextValue any
	if spec.SourceContextRef != "" {
		sourceContextValue = string(spec.SourceContextRef)
	}

	var sourceID uuid.UUID
	if err := tx.QueryRow(ctx, `
		INSERT INTO context.source (source_key, provenance_class)
		VALUES ($1, 'unknown')
		ON CONFLICT (source_key) DO NOTHING
		RETURNING id`, string(spec.AcquisitionRef)).Scan(&sourceID); err != nil {
		if !errors.Is(err, pgx.ErrNoRows) {
			return "", "", fmt.Errorf("register source identity: %w", err)
		}
		if err := tx.QueryRow(ctx, `SELECT id FROM context.source WHERE source_key = $1 FOR UPDATE`, string(spec.AcquisitionRef)).Scan(&sourceID); err != nil {
			return "", "", fmt.Errorf("recover source identity: %w", err)
		}
	}

	var sourceVersionID uuid.UUID
	err = tx.QueryRow(ctx, `
		INSERT INTO context.source_version
			(source_id, version_ordinal, workflow_id, submission_idempotency_key,
			 declared_format, acquired_at, matter_id, court_case_id, source_context_ref)
		SELECT $1, COALESCE(MAX(version_ordinal), 0) + 1, $2, $2, $3, $4, $5::uuid, $6::uuid, $7::uuid
		FROM context.source_version
		WHERE source_id = $1
		ON CONFLICT DO NOTHING
		RETURNING id`, sourceID, spec.RequestID, spec.DeclaredFormat, r.now(), spec.MatterID, spec.CourtCaseID, sourceContextValue).Scan(&sourceVersionID)
	if errors.Is(err, pgx.ErrNoRows) {
		err = tx.QueryRow(ctx, `
			SELECT version.id
			FROM context.source_version version
			JOIN context.source source ON source.id = version.source_id
			WHERE version.workflow_id = $1
			FOR UPDATE`, spec.RequestID).Scan(&sourceVersionID)
	}
	if err != nil {
		return "", "", fmt.Errorf("create or recover source version: %w", err)
	}
	var actualSourceKey, actualFormat, actualWorkflow, actualMatterID, actualCourtCaseID string
	var actualSourceContext pgtype.UUID
	if err := tx.QueryRow(ctx, `
		SELECT source.source_key, version.declared_format, version.workflow_id,
		       version.matter_id::text, version.court_case_id::text, version.source_context_ref
		FROM context.source_version version
		JOIN context.source source ON source.id = version.source_id
		WHERE version.id = $1::uuid`, sourceVersionID).Scan(&actualSourceKey, &actualFormat, &actualWorkflow, &actualMatterID, &actualCourtCaseID, &actualSourceContext); err != nil {
		return "", "", fmt.Errorf("verify source version ownership: %w", err)
	}
	if actualWorkflow != spec.RequestID || actualSourceKey != string(spec.AcquisitionRef) || actualFormat != spec.DeclaredFormat || actualMatterID != spec.MatterID || actualCourtCaseID != spec.CourtCaseID || uuidOrEmpty(actualSourceContext) != string(spec.SourceContextRef) {
		return "", "", errors.New("registration idempotency key is already owned by a different source or format")
	}

	executionID, err := lifecycleEnsureExecution(ctx, tx, sourceVersionID, spec.RequestID, string(stagegraph.RegisterSource), registrationKey(spec), nil)
	if err != nil {
		return "", "", err
	}
	if result, receipt, found, err := successfulReceipt(ctx, tx, executionID, "source_version", sourceVersionID.String()); err != nil {
		return "", "", err
	} else if found {
		if err := tx.Commit(ctx); err != nil {
			return "", "", fmt.Errorf("commit recovered registration: %w", err)
		}
		rollback = false
		return result, receipt, nil
	}
	receiptID, err := insertSuccessReceipt(ctx, tx, executionID, spec.Attempt, "source_version", sourceVersionID.String(), r.now())
	if err != nil {
		return "", "", err
	}
	if err := tx.Commit(ctx); err != nil {
		return "", "", fmt.Errorf("commit source registration: %w", err)
	}
	rollback = false
	return proffer.Ref(sourceVersionID.String()), proffer.Ref(receiptID.String()), nil
}

func (r *SourceLifecycleRepository) RetainOriginal(ctx context.Context, spec activities.OriginalRetentionSpec) (proffer.Ref, proffer.Ref, error) {
	if err := validateRetentionSpec(spec); err != nil {
		return "", "", err
	}
	// Resolve before opening the SQL transaction. The resolver may copy or
	// inspect an external object, but no database transaction is held while it
	// does so.
	object, err := r.resolve(ctx, spec.AcquisitionRef)
	if err != nil {
		return "", "", fmt.Errorf("resolve immutable acquisition: %w", err)
	}
	if err := object.validate(); err != nil {
		return "", "", err
	}
	versionID, err := uuid.Parse(string(spec.SourceVersionRef))
	if err != nil {
		return "", "", fmt.Errorf("source version reference is not a UUID: %w", err)
	}
	tx, err := r.db.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return "", "", fmt.Errorf("begin original retention transaction: %w", err)
	}
	rollback := true
	defer func() {
		if rollback {
			cleanupCtx, cancel := lifecycleCleanup(ctx)
			defer cancel()
			_ = tx.Rollback(cleanupCtx)
		}
	}()

	var workflowID, sourceKey, status string
	var existingObject pgtype.UUID
	if err := tx.QueryRow(ctx, `
		SELECT version.workflow_id, source.source_key, version.status, version.original_object_id
		FROM context.source_version version
		JOIN context.source source ON source.id = version.source_id
		WHERE version.id = $1::uuid
		FOR UPDATE`, versionID).Scan(&workflowID, &sourceKey, &status, &existingObject); err != nil {
		return "", "", fmt.Errorf("resolve source version ownership: %w", err)
	}
	if workflowID != spec.RequestID || sourceKey != string(spec.AcquisitionRef) {
		return "", "", errors.New("retention request does not own the source version and acquisition")
	}
	executionID, err := lifecycleEnsureExecution(ctx, tx, versionID, spec.RequestID, string(stagegraph.RetainOriginal), retentionKey(spec), nil)
	if err != nil {
		return "", "", err
	}
	if result, receipt, found, err := successfulReceipt(ctx, tx, executionID, "retained_object", uuidOrEmpty(existingObject)); err != nil {
		return "", "", err
	} else if found {
		if status != "retained" || !existingObject.Valid {
			return "", "", errors.New("successful retention receipt does not match retained source state")
		}
		if err := tx.Commit(ctx); err != nil {
			return "", "", fmt.Errorf("commit recovered retention: %w", err)
		}
		rollback = false
		return result, receipt, nil
	}
	if status != "registered" || existingObject.Valid {
		return "", "", errors.New("source version is not awaiting original retention")
	}
	objectID, err := insertOrReuseRetainedObject(ctx, tx, object)
	if err != nil {
		return "", "", err
	}
	if _, err := tx.Exec(ctx, `
		INSERT INTO context.source_version_object
			(source_version_id, object_id, object_role, member_locator)
		VALUES ($1::uuid, $2::uuid, 'original', '{}'::jsonb)
		ON CONFLICT (source_version_id, object_id) DO NOTHING`, versionID, objectID); err != nil {
		return "", "", fmt.Errorf("bind original object membership: %w", err)
	}
	resultJSON, err := resultReference("retained_object", objectID.String())
	if err != nil {
		return "", "", err
	}
	receiptID := uuid.New()
	completed := r.now()
	if _, err := tx.Exec(ctx, `
		INSERT INTO context.activity_receipt
			(id, activity_execution_id, attempt, status, started_at, completed_at, result_ref)
		VALUES ($1::uuid, $2::uuid, $3, 'success', $4, $5, $6::jsonb)`, receiptID, executionID, spec.Attempt, completed, completed, resultJSON); err != nil {
		return "", "", fmt.Errorf("record original retention receipt: %w", err)
	}
	if _, err := tx.Exec(ctx, `
		UPDATE context.source_version
		SET status = 'retained', original_object_id = $2::uuid
		WHERE id = $1::uuid AND status = 'registered'`, versionID, objectID); err != nil {
		return "", "", fmt.Errorf("advance source version to retained: %w", err)
	}
	if err := tx.Commit(ctx); err != nil {
		return "", "", fmt.Errorf("commit original retention: %w", err)
	}
	rollback = false
	return proffer.Ref(objectID.String()), proffer.Ref(receiptID.String()), nil
}

func (o ImmutableAcquisition) validate() error {
	if o.StorageClass != "immutable_object_store" && o.StorageClass != "filesystem" && o.StorageClass != "inline" {
		return fmt.Errorf("unsupported retained object storage class %q", o.StorageClass)
	}
	if strings.TrimSpace(o.ObjectURI) == "" {
		return errors.New("immutable acquisition requires an object URI")
	}
	if len(o.ContentSHA256) != 32 {
		return errors.New("immutable acquisition requires a 32-byte SHA-256 supplied by the acquisition boundary")
	}
	if o.ByteLength < 0 {
		return errors.New("immutable acquisition byte length cannot be negative")
	}
	if o.StorageClass == "inline" {
		if int64(len(o.InlineBytes)) != o.ByteLength {
			return errors.New("inline acquisition bytes do not match declared byte length")
		}
	} else if o.InlineBytes != nil {
		return errors.New("non-inline immutable acquisition cannot include inline bytes")
	}
	return nil
}

func insertOrReuseRetainedObject(ctx context.Context, tx pgx.Tx, object ImmutableAcquisition) (uuid.UUID, error) {
	var id uuid.UUID
	err := tx.QueryRow(ctx, `
		INSERT INTO context.retained_object
			(storage_class, object_uri, content_sha256, byte_length, inline_bytes)
		VALUES ($1, $2, $3, $4, $5)
		ON CONFLICT (content_sha256, byte_length) DO NOTHING
		RETURNING id`, object.StorageClass, object.ObjectURI, object.ContentSHA256, object.ByteLength, object.InlineBytes).Scan(&id)
	if err == nil {
		return id, nil
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return uuid.Nil, fmt.Errorf("insert retained object: %w", err)
	}
	var storedDigest []byte
	var storedLength int64
	if err := tx.QueryRow(ctx, `
		SELECT id, content_sha256, byte_length
		FROM context.retained_object
		WHERE (content_sha256, byte_length) = ($1, $2)
		   OR (storage_class, object_uri) = ($3, $4)
		ORDER BY id
		LIMIT 1`, object.ContentSHA256, object.ByteLength, object.StorageClass, object.ObjectURI).Scan(&id, &storedDigest, &storedLength); err != nil {
		return uuid.Nil, fmt.Errorf("recover retained object: %w", err)
	}
	if storedLength != object.ByteLength || !bytes.Equal(storedDigest, object.ContentSHA256) {
		return uuid.Nil, errors.New("immutable object URI is already bound to different content")
	}
	return id, nil
}

func lifecycleEnsureExecution(ctx context.Context, tx pgx.Tx, sourceVersionID uuid.UUID, workflowID, activityName, key string, requestDigest []byte) (uuid.UUID, error) {
	expectedWorkflow := workflowID
	var id uuid.UUID
	err := tx.QueryRow(ctx, `
		INSERT INTO context.activity_execution
			(source_version_id, workflow_id, activity_name, idempotency_key, request_digest)
		VALUES ($1::uuid, $2, $3, $4, $5)
		ON CONFLICT (source_version_id, activity_name, idempotency_key) DO NOTHING
		RETURNING id`, sourceVersionID, workflowID, activityName, key, requestDigest).Scan(&id)
	if errors.Is(err, pgx.ErrNoRows) {
		err = tx.QueryRow(ctx, `
			SELECT id, workflow_id
			FROM context.activity_execution
			WHERE source_version_id = $1::uuid AND activity_name = $2 AND idempotency_key = $3
			FOR UPDATE`, sourceVersionID, activityName, key).Scan(&id, &workflowID)
	}
	if err != nil {
		return uuid.Nil, fmt.Errorf("create or recover activity execution: %w", err)
	}
	if workflowID != "" {
		// The INSERT path already supplied workflowID. On recovery, Scan wrote
		// the stored value into the same variable; a mismatch means this
		// idempotency coordinate is being reused across workflows.
		var storedWorkflow string
		if err := tx.QueryRow(ctx, `SELECT workflow_id FROM context.activity_execution WHERE id = $1::uuid`, id).Scan(&storedWorkflow); err != nil {
			return uuid.Nil, fmt.Errorf("verify activity execution ownership: %w", err)
		}
		if storedWorkflow != expectedWorkflow {
			return uuid.Nil, errors.New("activity execution belongs to a different workflow")
		}
	}
	return id, nil
}

func successfulReceipt(ctx context.Context, tx pgx.Tx, executionID uuid.UUID, refKind, refID string) (proffer.Ref, proffer.Ref, bool, error) {
	var receiptID uuid.UUID
	var resultJSON []byte
	err := tx.QueryRow(ctx, `
		SELECT id, result_ref
		FROM context.activity_receipt
		WHERE activity_execution_id = $1::uuid AND status = 'success'
		ORDER BY attempt DESC LIMIT 1`, executionID).Scan(&receiptID, &resultJSON)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", "", false, nil
	}
	if err != nil {
		return "", "", false, fmt.Errorf("read successful activity receipt: %w", err)
	}
	var result struct {
		RefKind string `json:"ref_kind"`
		RefID   string `json:"ref_id"`
	}
	if err := json.Unmarshal(resultJSON, &result); err != nil || result.RefKind != refKind || result.RefID != refID {
		return "", "", false, errors.New("existing successful activity receipt has an unexpected result reference")
	}
	return proffer.Ref(result.RefID), proffer.Ref(receiptID.String()), true, nil
}

func insertSuccessReceipt(ctx context.Context, tx pgx.Tx, executionID uuid.UUID, attempt int32, kind, id string, now time.Time) (uuid.UUID, error) {
	resultJSON, err := resultReference(kind, id)
	if err != nil {
		return uuid.Nil, err
	}
	receiptID := uuid.New()
	if _, err := tx.Exec(ctx, `
		INSERT INTO context.activity_receipt
			(id, activity_execution_id, attempt, status, started_at, completed_at, result_ref)
		VALUES ($1::uuid, $2::uuid, $3, 'success', $4, $5, $6::jsonb)`, receiptID, executionID, attempt, now, now, resultJSON); err != nil {
		return uuid.Nil, fmt.Errorf("record activity receipt: %w", err)
	}
	return receiptID, nil
}

func resultReference(kind, id string) ([]byte, error) {
	return json.Marshal(struct {
		RefKind string `json:"ref_kind"`
		RefID   string `json:"ref_id"`
	}{kind, id})
}

func validateRegistrationSpec(spec activities.SourceRegistrationSpec) error {
	if strings.TrimSpace(spec.RequestID) == "" || strings.TrimSpace(string(spec.AcquisitionRef)) == "" || strings.TrimSpace(spec.DeclaredFormat) == "" {
		return errors.New("source registration requires request, acquisition, and declared format")
	}
	if spec.Attempt < 1 {
		return errors.New("source registration attempt must be positive")
	}
	if _, err := uuid.Parse(strings.TrimSpace(spec.MatterID)); err != nil {
		return errors.New("source registration requires a valid matter_id UUID")
	}
	if _, err := uuid.Parse(strings.TrimSpace(spec.CourtCaseID)); err != nil {
		return errors.New("source registration requires a valid court_case_id UUID")
	}
	return nil
}
func validateRetentionSpec(spec activities.OriginalRetentionSpec) error {
	if strings.TrimSpace(spec.RequestID) == "" || strings.TrimSpace(string(spec.SourceVersionRef)) == "" || strings.TrimSpace(string(spec.AcquisitionRef)) == "" {
		return errors.New("original retention requires request, source version, and acquisition")
	}
	if spec.Attempt < 1 {
		return errors.New("original retention attempt must be positive")
	}
	return nil
}
func registrationKey(spec activities.SourceRegistrationSpec) string {
	return fmt.Sprintf("source-lifecycle:register:%s:%s:%s:%s", spec.RequestID, spec.AcquisitionRef, spec.DeclaredFormat, spec.SourceContextRef)
}
func retentionKey(spec activities.OriginalRetentionSpec) string {
	return fmt.Sprintf("source-lifecycle:retain:%s:%s:%s", spec.RequestID, spec.SourceVersionRef, spec.AcquisitionRef)
}
func (r *SourceLifecycleRepository) now() time.Time { return r.clock().UTC() }
func uuidOrEmpty(id pgtype.UUID) string {
	if !id.Valid {
		return ""
	}
	parsed, err := uuid.FromBytes(id.Bytes[:])
	if err != nil {
		return ""
	}
	return parsed.String()
}
func lifecycleCleanup(ctx context.Context) (context.Context, context.CancelFunc) {
	return context.WithTimeout(context.WithoutCancel(ctx), lifecycleCleanupTimeout)
}

var _ activities.SourceLifecycleStore = (*SourceLifecycleRepository)(nil)
