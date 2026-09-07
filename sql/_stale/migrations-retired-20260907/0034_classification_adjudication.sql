-- 0034_classification_adjudication.sql
--
-- Byline: Claude Code · Sonnet 5 · 2026-08-26
--
-- GAP-031 follow-through: durable item-level HITL adjudication fields on the EXISTING
-- analysis.chunk_classification drafts table (sql/0033) — no new ledger table, per owner
-- instruction to reuse existing classification batch/item identity and tables. Extends the
-- table so the n8n persist-results webhook
-- (docs/research/integration-audit-2026-08-24/composed/wf-persist-results.json) can durably
-- record who decided, what they decided, why, and where the decision came from, for every
-- item that passed the Temporal ClassificationBatchPipeline review gate
-- (server/temporal/classification_workflow.py — NOT modified by this packet).
--
-- Idempotency / fail-closed design (mirrors the workflow's own
-- ItemAdjudication/_apply_item_decision contract):
--   * The pre-existing table has no natural key (only the surrogate `id` PK), so a retried
--     persist activity call for the same batch could previously double-insert. This adds the
--     natural row key the composed n8n body's own sticky note already assumed (it was
--     originally spelled record_id/chunk_id, which were never real columns on this table —
--     record_ref is this table's actual item-identity column; see the n8n body's Normalize
--     node, updated in the same change, for the chunk_id > record_id > record_ref precedence
--     that mirrors ClassificationBatchPipeline._item_key exactly).
--   * decision_id is the reviewer-minted idempotency key for ONE item's decision. A partial
--     unique index on decision_id (rows that carry one) means: a byte-identical retry of the
--     same persist call is a no-op via ON CONFLICT on the general row key below (the retried
--     row is identical, including decision_id, so it simply doesn't insert twice); a
--     decision_id reused across two DIFFERENT items (a case the workflow's in-memory gate does
--     NOT catch, since it only checks conflicts per item_key, not decision_id uniqueness across
--     items) raises a unique-violation error on THIS index instead of silently landing a second,
--     conflicting row. wf-persist-results.json batches every row of one persist call inside a
--     single transaction (queryBatching=transaction), so that error rolls back the WHOLE batch
--     rather than partially applying it — fail closed, not fail partial.
--   * Untouched (still-pending) and rejected items are never sent to this webhook at all — that
--     exclusion is enforced entirely in the Temporal workflow's _resolve_gate(); nothing here
--     re-derives it, and there is deliberately no column for "rejected"/"pending" state.

BEGIN;

ALTER TABLE analysis.chunk_classification
    ADD COLUMN IF NOT EXISTS decision_id    text,
    ADD COLUMN IF NOT EXISTS actor          text,
    ADD COLUMN IF NOT EXISTS decision       text,
    ADD COLUMN IF NOT EXISTS reason         text,
    ADD COLUMN IF NOT EXISTS source         text,
    ADD COLUMN IF NOT EXISTS adjudicated_at timestamptz;

-- Only approve/correct can ever reach this table (reject/pending are excluded upstream by the
-- workflow's _resolve_gate() — this CHECK is defense-in-depth against a future/other writer).
ALTER TABLE analysis.chunk_classification
    ADD CONSTRAINT chunkclass_decision_valid
        CHECK (decision IS NULL OR decision IN ('approve', 'correct'));

-- All six adjudication fields travel together or not at all — a row is either a
-- straight-through draft (all NULL) or a fully-provenanced adjudicated row.
ALTER TABLE analysis.chunk_classification
    ADD CONSTRAINT chunkclass_adjudication_fields_complete
        CHECK (
            (decision_id IS NULL AND actor IS NULL AND decision IS NULL
                AND reason IS NULL AND source IS NULL AND adjudicated_at IS NULL)
            OR
            (decision_id IS NOT NULL AND actor IS NOT NULL AND decision IS NOT NULL
                AND reason IS NOT NULL AND source IS NOT NULL AND adjudicated_at IS NOT NULL)
        );

-- General row idempotency: retrying the same persist call for the same batch/item/classifier
-- version is a no-op. This is the ON CONFLICT target in wf-persist-results.json.
CREATE UNIQUE INDEX IF NOT EXISTS uq_chunkclass_batch_item
    ON analysis.chunk_classification (run_key, batch_index, record_ref, classifier_version);

-- Decision-level idempotency / fail-closed conflict detection: a decision_id may appear on at
-- most one row ever, regardless of which item it is attached to.
CREATE UNIQUE INDEX IF NOT EXISTS uq_chunkclass_decision_id
    ON analysis.chunk_classification (decision_id)
    WHERE decision_id IS NOT NULL;

COMMENT ON COLUMN analysis.chunk_classification.decision_id IS
    'GAP-031: reviewer-minted idempotency key for this item''s adjudication decision. NULL for drafts never routed through the HITL review gate.';
COMMENT ON COLUMN analysis.chunk_classification.actor IS
    'GAP-031: reviewer identity that made this adjudication decision.';
COMMENT ON COLUMN analysis.chunk_classification.decision IS
    'GAP-031: normalized decision — approve or correct only (reject/pending items never reach this table).';
COMMENT ON COLUMN analysis.chunk_classification.reason IS
    'GAP-031: reviewer-supplied rationale for the decision. Required whenever decision_id is set.';
COMMENT ON COLUMN analysis.chunk_classification.source IS
    'GAP-031: origin surface of the decision (e.g. workbench-ui, temporal-cli).';
COMMENT ON COLUMN analysis.chunk_classification.adjudicated_at IS
    'GAP-031: when the persist activity recorded the decision (n8n now()), not when the reviewer made it in the gate — the workflow''s ItemDecisionRecord carries no timestamp today (out of this packet''s file ownership; see GAP-031-IMPLEMENTATION-STATUS.md follow-through section).';

GRANT SELECT, INSERT, UPDATE ON analysis.chunk_classification TO agno_app;

COMMIT;
