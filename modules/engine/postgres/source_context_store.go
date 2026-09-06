// Byline: Codex · GPT-5.6-Sol · 2026-08-30 (append-only Proffer source context)
package postgres

import (
	"context"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	"github.com/Cursedpotential/probata/engine/sourcecontext"
)

type SourceContextStore struct {
	db    DB
	clock func() time.Time
}

func NewSourceContextStore(db DB) (*SourceContextStore, error) {
	if db == nil {
		return nil, errors.New("source context store requires a database")
	}
	return &SourceContextStore{db: db, clock: func() time.Time { return time.Now().UTC() }}, nil
}

func (s *SourceContextStore) PersistSourceContext(ctx context.Context, spec sourcecontext.Spec) (sourcecontext.Receipt, error) {
	observed, err := json.Marshal(spec.ObservedSource)
	if err != nil {
		return sourcecontext.Receipt{}, err
	}
	assertions, err := json.Marshal(spec.Assertions)
	if err != nil {
		return sourcecontext.Receipt{}, err
	}
	id, err := uuid.NewV7()
	if err != nil {
		return sourcecontext.Receipt{}, err
	}
	recordedAt := s.clock()
	receiptRef := "proffer-source-context://" + id.String()
	tx, err := s.db.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return sourcecontext.Receipt{}, err
	}
	rollback := func() { cleanup, cancel := boundedCleanup(ctx); defer cancel(); _ = tx.Rollback(cleanup) }
	revision := 1
	var supersedes any
	var previousAssertions any
	if spec.SupersedesRef != "" {
		var priorAssertions []byte
		err = tx.QueryRow(ctx, `
			SELECT revision, assertions
			FROM context.proffer_source_context_revision
			WHERE source_context_ref=$1::uuid AND request_id=$2
			  AND matter_id=$3::uuid AND court_case_id=$4::uuid
			  AND source_ref=$5 AND observed_source=$6::jsonb
			FOR UPDATE`, spec.SupersedesRef, spec.RequestID, spec.MatterID,
			spec.CourtCaseID, spec.SourceRef, observed).Scan(&revision, &priorAssertions)
		if errors.Is(err, pgx.ErrNoRows) {
			rollback()
			return sourcecontext.Receipt{}, errors.New("superseded source context does not own the same request and immutable source")
		}
		if err != nil {
			rollback()
			return sourcecontext.Receipt{}, fmt.Errorf("resolve superseded source context: %w", err)
		}
		revision++
		supersedes = spec.SupersedesRef
		previousAssertions = priorAssertions
	}
	result, err := tx.Exec(ctx, `
		INSERT INTO context.proffer_source_context_revision
		    (source_context_ref, request_id, revision, supersedes_ref, matter_id, court_case_id,
		     source_ref, observed_source, previous_assertions, assertions, change_reason,
		     actor_subject_uid, actor_username, idempotency_key, content_digest,
		     receipt_ref, recorded_at)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17)
		ON CONFLICT (idempotency_key) DO NOTHING`, id, spec.RequestID, revision, supersedes,
		spec.MatterID, spec.CourtCaseID, spec.SourceRef, observed, previousAssertions, assertions, spec.ChangeReason,
		spec.ActorSubjectUID, spec.ActorUsername, spec.IdempotencyKey,
		spec.ContentDigest[:], receiptRef, recordedAt)
	if err != nil {
		rollback()
		return sourcecontext.Receipt{}, fmt.Errorf("persist source context: %w", err)
	}
	if result.RowsAffected() == 1 {
		if err := tx.Commit(ctx); err != nil {
			rollback()
			return sourcecontext.Receipt{}, err
		}
		return sourcecontext.Receipt{SourceContextRef: id.String(), ReceiptRef: receiptRef,
			ContentDigest: hex.EncodeToString(spec.ContentDigest[:]), Revision: revision, RecordedAt: recordedAt}, nil
	}
	var existing sourcecontext.Receipt
	var digest []byte
	err = tx.QueryRow(ctx, `
		SELECT source_context_ref::text, receipt_ref, content_digest, revision, recorded_at
		FROM context.proffer_source_context_revision WHERE idempotency_key=$1`, spec.IdempotencyKey).Scan(
		&existing.SourceContextRef, &existing.ReceiptRef, &digest, &existing.Revision, &existing.RecordedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		rollback()
		return sourcecontext.Receipt{}, errors.New("source context idempotency conflict could not be resolved")
	}
	if err != nil {
		rollback()
		return sourcecontext.Receipt{}, err
	}
	rollback()
	existing.ContentDigest = hex.EncodeToString(digest)
	if existing.ContentDigest != hex.EncodeToString(spec.ContentDigest[:]) {
		return sourcecontext.Receipt{}, errors.New("idempotency key is already bound to different source context")
	}
	return existing, nil
}

func (s *SourceContextStore) ValidateSourceContext(
	ctx context.Context, ref, requestID, matterID, courtCaseID, sourceRef string,
) error {
	var valid bool
	err := s.db.QueryRow(ctx, `
		SELECT EXISTS (
			SELECT 1 FROM context.proffer_source_context_revision
			WHERE source_context_ref=$1::uuid AND request_id=$2
			  AND matter_id=$3::uuid AND court_case_id=$4::uuid AND source_ref=$5
		)`, ref, requestID, matterID, courtCaseID, sourceRef).Scan(&valid)
	if err != nil {
		return fmt.Errorf("validate source context: %w", err)
	}
	if !valid {
		return errors.New("source context does not own the requested intake scope")
	}
	return nil
}

var _ sourcecontext.Writer = (*SourceContextStore)(nil)
var _ sourcecontext.Validator = (*SourceContextStore)(nil)
