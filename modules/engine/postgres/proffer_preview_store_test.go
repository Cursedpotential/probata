// Byline: Codex · GPT-5.6 · 2026-08-29 (durable Proffer preview store tests)
package postgres

import (
	"context"
	"errors"
	"fmt"
	"os"
	"strings"
	"testing"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/Cursedpotential/probata/engine/proffer"
	"github.com/Cursedpotential/probata/engine/runtimeapi/previewmodel"
)

type nestedPreviewTestDB struct{ tx pgx.Tx }

func (db nestedPreviewTestDB) BeginTx(ctx context.Context, _ pgx.TxOptions) (pgx.Tx, error) {
	return db.tx.Begin(ctx)
}
func (db nestedPreviewTestDB) Query(ctx context.Context, sql string, args ...any) (pgx.Rows, error) {
	return db.tx.Query(ctx, sql, args...)
}
func (db nestedPreviewTestDB) QueryRow(ctx context.Context, sql string, args ...any) pgx.Row {
	return db.tx.QueryRow(ctx, sql, args...)
}

func TestNewProfferPreviewStoreRequiresDatabase(t *testing.T) {
	if _, err := NewProfferPreviewStore(nil, nil); err == nil {
		t.Fatal("nil database accepted")
	}
	if _, err := NewProfferPreviewStore(testDB{}, strings.NewReader(strings.Repeat("x", 64))); err != nil {
		t.Fatalf("valid preview store rejected: %v", err)
	}
}

func TestPreviewDecisionKeyIsDeterministicAndCoordinateBound(t *testing.T) {
	base := decisionKey("handle", true, "reason", "actor", proffer.Ref("selection"), proffer.Ref("options"))
	if base != decisionKey("handle", true, "reason", "actor", proffer.Ref("selection"), proffer.Ref("options")) {
		t.Fatal("decision key is not deterministic")
	}
	variants := [][6]string{
		{"other", "true", "reason", "actor", "selection", "options"},
		{"handle", "false", "reason", "actor", "selection", "options"},
		{"handle", "true", "other", "actor", "selection", "options"},
		{"handle", "true", "reason", "other", "selection", "options"},
		{"handle", "true", "reason", "actor", "other", "options"},
		{"handle", "true", "reason", "actor", "selection", "other"},
	}
	for _, variant := range variants {
		approved := variant[1] == "true"
		if base == decisionKey(variant[0], approved, variant[2], variant[3], proffer.Ref(variant[4]), proffer.Ref(variant[5])) {
			t.Fatalf("decision key ignored coordinate %+v", variant)
		}
	}
}

func TestPreviewStoreAgainstSnapshotSchemaRollbackOnly(t *testing.T) {
	// The database IS sql/bootstrap/schema_snapshot_<date>.sql (owner rulings D-142 §3, D-152; migrations retired
	// 2026-09-07). This test assumes the preview projection store already exists in the target database and
	// exercises the store inside a rollback-only transaction; it applies no DDL.
	dsn := strings.TrimSpace(os.Getenv("PLATFORM_PREVIEW_STORE_TEST_DSN"))
	if dsn == "" {
		t.Skip("PLATFORM_PREVIEW_STORE_TEST_DSN is not configured")
	}
	ctx := context.Background()
	pool, err := pgxpool.New(ctx, dsn)
	if err != nil {
		t.Fatal(err)
	}
	defer pool.Close()
	var major string
	if err := pool.QueryRow(ctx, `SELECT current_setting('server_version_num')::int / 10000`).Scan(&major); err != nil {
		t.Fatal(err)
	}
	if major != "18" {
		t.Fatalf("snapshot schema requires PostgreSQL 18, got %s", major)
	}
	tx, err := pool.Begin(ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer func() {
		if rollbackErr := tx.Rollback(context.Background()); rollbackErr != nil && !errors.Is(rollbackErr, context.Canceled) {
			// pgx reports ErrTxClosed after a test failure that closed the tx.
		}
	}()
	var relation string
	if err := tx.QueryRow(ctx, `SELECT to_regclass('context.proffer_preview_binding')::text`).Scan(&relation); err != nil {
		t.Fatal(err)
	}
	if relation != "context.proffer_preview_binding" && relation != "proffer_preview_binding" {
		t.Fatalf("snapshot schema lacks context.proffer_preview_binding (got %q); rebuild from sql/bootstrap", relation)
	}
	store, err := NewProfferPreviewStore(nestedPreviewTestDB{tx: tx}, strings.NewReader(strings.Repeat("abcdefghijklmnopqrstuvwx", 8)))
	if err != nil {
		t.Fatal(err)
	}
	binding, err := store.Create(ctx, previewmodel.Binding{
		RequestID: "request-preview", SourceRef: "upload://source", WorkflowID: "workflow-preview",
		RunID: "run-preview", ParserOptionsRef: "options-preview",
	})
	if err != nil {
		t.Fatal(err)
	}
	duplicate, err := store.Create(ctx, previewmodel.Binding{
		RequestID: "request-preview", SourceRef: "upload://source", WorkflowID: "workflow-preview",
		RunID: "run-preview", ParserOptionsRef: "options-preview",
	})
	if err != nil || duplicate.Handle != binding.Handle {
		t.Fatalf("idempotent binding = %+v, %v; want handle %s", duplicate, err, binding.Handle)
	}
	page, err := store.ListBindings(ctx, nil, 100)
	if err != nil {
		t.Fatal(err)
	}
	foundBinding := false
	for _, listed := range page.Bindings {
		if listed.Handle == binding.Handle {
			foundBinding = true
			if listed.CreatedAt.IsZero() {
				t.Fatal("listed binding omitted its durable created_at coordinate")
			}
		}
	}
	if !foundBinding {
		t.Fatalf("operation binding %s was absent from the newest page", binding.Handle)
	}
	stages, err := store.OperationStages(ctx, binding.Handle)
	if err != nil || len(stages) != 0 {
		t.Fatalf("unregistered operation stages = %+v, %v; want an empty durable projection", stages, err)
	}
	if _, err := store.Snapshot(ctx, binding.Handle); !errors.Is(err, previewmodel.ErrNotReady) {
		t.Fatalf("unpublished snapshot error = %v", err)
	}
	var sourceID, rawID, normalizedID string
	err = tx.QueryRow(ctx, `SELECT source_version_id::text, raw_generation_id::text, id::text
		FROM context.normalized_generation ORDER BY created_at LIMIT 1`).Scan(&sourceID, &rawID, &normalizedID)
	if errors.Is(err, pgx.ErrNoRows) {
		if err := store.RecordDecision(ctx, binding.Handle, false, "repair required", "actor-1", "selection-1", "options-1"); !errors.Is(err, previewmodel.ErrNotReady) {
			t.Fatalf("decision without projection error = %v, want ErrNotReady", err)
		}
		var decisions int
		if err := tx.QueryRow(ctx, `SELECT count(*) FROM context.proffer_preview_decision WHERE preview_handle=$1`, binding.Handle).Scan(&decisions); err != nil || decisions != 0 {
			t.Fatalf("rolled-back premature decisions = %d, %v", decisions, err)
		}
	} else if err != nil {
		t.Fatal(err)
	} else {
		if _, err := tx.Exec(ctx, `INSERT INTO context.proffer_preview_snapshot
			(preview_handle,snapshot_seq,phase,source_version_id,raw_generation_id,normalized_generation_id,
			 parser_id,parser_version,parser_config_digest,preview_digest)
			VALUES ($1,0,'awaiting_decision',$2,$3,$4,'sbv','1.2.3',decode(repeat('b',64),'hex'),decode(repeat('a',64),'hex'))`,
			binding.Handle, sourceID, rawID, normalizedID); err != nil {
			t.Fatal(err)
		}
		if _, err := tx.Exec(ctx, `INSERT INTO context.proffer_preview_receipt
			(preview_handle,snapshot_seq,receipt_type,receipt_ref,status,recorded_at)
			SELECT $1,0,receipt_type,'receipt-'||receipt_type,'completed',now()
			FROM unnest(ARRAY['custody','parser_selection','parser_execution','normalization','storage','completeness']) receipt_type`, binding.Handle); err != nil {
			t.Fatal(err)
		}
		if _, err := tx.Exec(ctx, `INSERT INTO context.proffer_preview_participant
			(preview_handle,snapshot_seq,participant_id,display_name,canonical_address)
			VALUES ($1,0,'p-1','Person One','person@example.test')`, binding.Handle); err != nil {
			t.Fatal(err)
		}
		if _, err := tx.Exec(ctx, `INSERT INTO context.proffer_preview_message
			(preview_handle,snapshot_seq,message_id,ordinal,sender_participant_id,body,participant_ids,source_locator_ref)
			VALUES ($1,0,'m-1',0,'p-1','body',ARRAY['p-1'],'locator-1')`, binding.Handle); err != nil {
			t.Fatal(err)
		}
		if _, err := tx.Exec(ctx, `INSERT INTO context.proffer_preview_attachment
			(preview_handle,snapshot_seq,message_id,attachment_id,filename,source_locator_ref)
			VALUES ($1,0,'m-1','a-1','file.txt','attachment-locator')`, binding.Handle); err != nil {
			t.Fatal(err)
		}

		if err := store.RecordDecision(ctx, binding.Handle, false, "repair required", "actor-1", "selection-1", "options-1"); err != nil {
			t.Fatal(err)
		}
		if err := store.RecordDecision(ctx, binding.Handle, false, "repair required", "actor-1", "selection-1", "options-1"); err != nil {
			t.Fatal(err)
		}
		if err := store.RecordDecision(ctx, binding.Handle, true, "repair accepted", "actor-1", "selection-2", "options-2"); err != nil {
			t.Fatal(err)
		}

		rows, err := tx.Query(ctx, `SELECT snapshot_seq, phase, reason FROM context.proffer_preview_snapshot
			WHERE preview_handle=$1 ORDER BY snapshot_seq`, binding.Handle)
		if err != nil {
			t.Fatal(err)
		}
		defer rows.Close()
		var snapshots []struct {
			seq    int64
			phase  string
			reason string
		}
		for rows.Next() {
			var snapshot struct {
				seq    int64
				phase  string
				reason string
			}
			if err := rows.Scan(&snapshot.seq, &snapshot.phase, &snapshot.reason); err != nil {
				t.Fatal(err)
			}
			snapshots = append(snapshots, snapshot)
		}
		if err := rows.Err(); err != nil {
			t.Fatal(err)
		}
		if len(snapshots) != 3 || snapshots[0].seq != 0 || snapshots[0].phase != "awaiting_decision" || snapshots[0].reason != "" || snapshots[1].seq != 1 || snapshots[1].phase != "rejected" || snapshots[2].seq != 2 || snapshots[2].phase != "approved" {
			t.Fatalf("append-only decision snapshots = %+v", snapshots)
		}
		for _, table := range []string{"proffer_preview_receipt", "proffer_preview_participant", "proffer_preview_message", "proffer_preview_attachment"} {
			var initial, rejected, approved int
			query := fmt.Sprintf(`SELECT count(*) FILTER (WHERE snapshot_seq=0), count(*) FILTER (WHERE snapshot_seq=1), count(*) FILTER (WHERE snapshot_seq=2) FROM context.%s WHERE preview_handle=$1`, table)
			if err := tx.QueryRow(ctx, query, binding.Handle).Scan(&initial, &rejected, &approved); err != nil {
				t.Fatal(err)
			}
			if initial == 0 || rejected != initial || approved != initial {
				t.Fatalf("%s child copies = initial %d rejected %d approved %d", table, initial, rejected, approved)
			}
		}
	}
	events, err := store.EventsAfter(ctx, binding.Handle, -1)
	if err != nil {
		t.Fatal(err)
	}
	wantEvents := 1
	if normalizedID != "" {
		wantEvents = 3
	}
	if len(events) != wantEvents || events[0].EventID != 0 || events[len(events)-1].EventID != int64(wantEvents-1) {
		t.Fatalf("idempotent event replay = %+v", events)
	}
}

func TestRecordDecisionContainsNoSnapshotMutation(t *testing.T) {
	body, err := os.ReadFile("proffer_preview_store.go")
	if err != nil {
		t.Fatal(err)
	}
	source := string(body)
	if strings.Contains(source, "UPDATE context.proffer_preview_snapshot") {
		t.Fatal("RecordDecision contains a forbidden snapshot UPDATE")
	}
	for _, table := range []string{
		"INSERT INTO context.proffer_preview_snapshot",
		"INSERT INTO context.proffer_preview_receipt",
		"INSERT INTO context.proffer_preview_participant",
		"INSERT INTO context.proffer_preview_message",
		"INSERT INTO context.proffer_preview_attachment",
	} {
		if !strings.Contains(source, table) {
			t.Fatalf("append-only decision path is missing %q", table)
		}
	}
}
