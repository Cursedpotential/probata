-- 0025_durable_run_reports.sql — structured run outcomes + append-only review actions.
--
-- A workflow report must answer what ran, what did not run, why, and what
-- the operator did about it. Langfuse/OTel traces are correlated debugging
-- telemetry; these Postgres rows remain the durable platform authority.
--
-- Byline: Codex · GPT-5 · 2026-08-13
--
-- Idempotent. NEVER edit an applied migration; add the next numbered file.

BEGIN;

ALTER TABLE ops.workflow_run_stage
  ADD COLUMN IF NOT EXISTS outcome_reason_code TEXT,
  ADD COLUMN IF NOT EXISTS outcome_reason_detail TEXT;

UPDATE ops.workflow_run_stage
SET outcome_reason_code = CASE status
  WHEN 'success' THEN 'completed'
  WHEN 'failed' THEN 'legacy_failure'
  WHEN 'skipped' THEN 'legacy_skip'
  ELSE NULL
END
WHERE outcome_reason_code IS NULL;

ALTER TABLE ops.workflow_run_stage
  DROP CONSTRAINT IF EXISTS workflow_run_stage_terminal_reason;
ALTER TABLE ops.workflow_run_stage
  ADD CONSTRAINT workflow_run_stage_terminal_reason CHECK (
    (status IN ('pending', 'running') AND outcome_reason_code IS NULL)
    OR
    (status IN ('success', 'failed', 'skipped') AND outcome_reason_code IS NOT NULL)
  );

ALTER TABLE ops.workflow_run
  ADD COLUMN IF NOT EXISTS trace_id TEXT,
  ADD COLUMN IF NOT EXISTS report_schema_version TEXT NOT NULL DEFAULT '1.0';

CREATE INDEX IF NOT EXISTS idx_workflow_run_trace_id
  ON ops.workflow_run(trace_id)
  WHERE trace_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS ops.workflow_run_review_action (
  action_id    UUID PRIMARY KEY DEFAULT uuidv7(),
  run_id       UUID NOT NULL REFERENCES ops.workflow_run(run_id),
  stage_seq    INT,
  action_type  TEXT NOT NULL
    CHECK (action_type IN ('acknowledge', 'approve', 'override', 'continue', 'abort', 'retry')),
  actor        TEXT NOT NULL DEFAULT 'owner',
  reason       TEXT NOT NULL CHECK (length(btrim(reason)) > 0),
  replacement JSONB,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE ops.workflow_run_review_action IS
  'Append-only operator decisions attached to a durable workflow report. '
  'Original stage outcomes are never rewritten; corrections and overrides are new actions.';

DROP TRIGGER IF EXISTS workflow_run_review_action_append_only
  ON ops.workflow_run_review_action;
CREATE TRIGGER workflow_run_review_action_append_only
  BEFORE UPDATE OR DELETE ON ops.workflow_run_review_action
  FOR EACH ROW EXECUTE FUNCTION working.forbid_mutation();

CREATE INDEX IF NOT EXISTS idx_workflow_run_review_action_run
  ON ops.workflow_run_review_action(run_id, created_at, action_id);

COMMIT;
