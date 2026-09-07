-- 0005_workflow_run_ledger.sql — C0 run ledger (docs/PROJECT_CANON.md / operator
-- console): today the evidence workflows (server/evidence/workflows.py) are
-- black boxes — telemetry only exists as the final in-memory step_log. This
-- migration makes every run_chat_transcript()/run_sms_xml() call a first-class
-- DB object, with per-stage rows written AS STAGES EXECUTE (not just at the
-- end), so a REST API can start/watch a run in flight.
--
-- analysis.workflow_run       : one row per workflow run.
-- analysis.workflow_run_stage : one row per Step in that run — seeded 'pending'
--   before the run starts, flipped 'running' -> 'success'/'failed'/'skipped'
--   by server/evidence/run_ledger.py as server/evidence/workflows.py executes.
--
-- Byline: Claude Code · Sonnet (agent) · 2026-07-20
--
-- Idempotent: safe to re-run against an existing DB (IF NOT EXISTS throughout).
-- NEVER edit this file once applied to a live DB — add a new numbered migration.

CREATE TABLE IF NOT EXISTS analysis.workflow_run (
  run_id      UUID PRIMARY KEY DEFAULT uuidv7(),   -- PG18 native; timestamp-ordered
  workflow    TEXT NOT NULL,                        -- e.g. 'chat-transcript' | 'sms-xml'
  mode        TEXT NOT NULL DEFAULT 'auto'
    CHECK (mode IN ('auto','supervised')),          -- supervised gates land in C2
  source_name TEXT,                                 -- original uploaded filename
  source_path TEXT,                                 -- where the runner read the artifact from
  sha256      TEXT,                                 -- filled once custody computes it
  artifact_id TEXT,                                 -- evidence.evidence_hash.id (text, cross-schema-loose)
  domain      TEXT,                                 -- knowledge domain tag
  status      TEXT NOT NULL DEFAULT 'running'
    CHECK (status IN ('running','paused','completed','failed')),
  summary     JSONB,                                -- the runner's existing summary dict, at completion
  error       TEXT,                                 -- set on an unhandled exception
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS analysis.workflow_run_stage (
  stage_id    BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  run_id      UUID NOT NULL REFERENCES analysis.workflow_run(run_id) ON DELETE CASCADE,
  seq         INT NOT NULL,                         -- 1-based order within the run (custody=1, ...)
  name        TEXT NOT NULL,                        -- 'custody' | 'parse' | 'store' | 'knowledge'
  status      TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','running','success','failed','skipped')),
  content     TEXT,                                 -- the step's human-readable status line
  output      JSONB,                                -- typed per-stage detail (see run_ledger.py)
  started_at  TIMESTAMPTZ,
  finished_at TIMESTAMPTZ,
  UNIQUE (run_id, seq)
);

-- ---------------------------------------------------------------------------
-- Indexes
-- ---------------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_workflow_run_status
  ON analysis.workflow_run(status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_workflow_run_stage_run
  ON analysis.workflow_run_stage(run_id);
