-- 0033_chunk_classification_drafts.sql
--
-- Byline: Claude Code · Fable 5 · 2026-08-24
--
-- Landing table for the n8n/Temporal classification pipeline (D-068, builder guide).
-- DRAFTS BY DESIGN (owner ruling 2026-08-24): every row is a versioned draft — the
-- classifier_version records exactly which prompt/config/model produced it; re-runs
-- INSERT new rows under a new version, never overwrite. Low confidence routes here as
-- review_state='unreviewed' — NEVER as a "flag" (anti-over-flagging rule). Nothing in
-- this table touches evidence status; promotion stays behind its own gate.

BEGIN;

CREATE TABLE IF NOT EXISTS analysis.chunk_classification (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    run_key             text        NOT NULL,               -- idempotency key of the pipeline run
    batch_index         int         NOT NULL,
    classifier_version  text        NOT NULL,               -- prompt/config/model version stamp
    conversation_key    text,
    seq                 bigint,
    record_ref          text,                               -- source record id (chat/message/chunk id)
    occurred_at         timestamptz,                        -- temporal mandate: the record's own clock
    message_text        text        NOT NULL,
    labels              text[]      NOT NULL DEFAULT '{}',
    sentiment           text,
    severity            int         CHECK (severity IS NULL OR (severity >= 0 AND severity <= 10)),
    summary             text,
    judge_verdict       text,                               -- pass / needs_review / (top-tier verdicts later)
    judge_confidence    real        CHECK (judge_confidence IS NULL OR (judge_confidence >= 0 AND judge_confidence <= 1)),
    judge_model         text,
    classify_model      text,
    review_state        text        NOT NULL DEFAULT 'unreviewed',
    created_at          timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_chunkclass_runkey  ON analysis.chunk_classification (run_key, batch_index);
CREATE INDEX IF NOT EXISTS idx_chunkclass_version ON analysis.chunk_classification (classifier_version);
CREATE INDEX IF NOT EXISTS idx_chunkclass_conv    ON analysis.chunk_classification (conversation_key, seq);

COMMENT ON TABLE analysis.chunk_classification IS
    'DRAFT classification output of the n8n/Temporal pipeline (D-068). Versioned drafts only — '
    'classifier_version stamps provenance; re-runs add rows under new versions; low confidence '
    'lands as review_state=unreviewed (never a flag). No evidence-status effect.';

GRANT SELECT, INSERT, UPDATE ON analysis.chunk_classification TO agno_app;

COMMIT;
