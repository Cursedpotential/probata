-- 0006_run_gates_and_custody_tier.sql — C2 operator-console additive migration
-- on top of sql/0005_workflow_run_ledger.sql (NEVER edit that file once
-- applied to a live DB — this is the new numbered migration instead).
--
--   1. Supervised-mode gates: gate_state on analysis.workflow_run, flipped by
--      the workflow's per-stage wrapper (server/evidence/workflows.py's
--      _wrap_step_for_run_control) and by the run-control endpoints
--      (server/api/run_routes.py POST .../continue|abort) — 'waiting' while
--      paused at a gate awaiting an operator decision, 'released'/'abort' as
--      the two decisions an operator can make, NULL when no gate is open.
--   2. Retry lineage: parent_run_id links a retried run back to the run it
--      was retried from (server/api/run_routes.py's POST /v1/runs/{id}/retry).
--   3. Two-tier custody (docs/planning/operator-console-requirements.md
--      addendum 2): custody_tier records whether a run's custody step took
--      the FULL evidence-schema path (sha256 + blob + H1, and — for verticals
--      that generate them — the H2/H3 chain rows; 'full' is the historical/
--      only behavior before this migration) or the LIGHT tier (sha256 + blob
--      write + dedupe check ONLY, no evidence-schema chain rows) — for
--      knowledge-lane pours where the material is the owner's story, not
--      evidence. Defaults to 'full' so every pre-existing run keeps its
--      original (only possible) meaning unchanged.
--
-- Byline: Claude Code · Sonnet (agent) · 2026-07-20
--
-- Idempotent: safe to re-run against an existing DB (IF NOT EXISTS guards
-- throughout). NEVER edit this file (or 0005) once applied to a live DB —
-- add a new numbered migration.

ALTER TABLE analysis.workflow_run
  ADD COLUMN IF NOT EXISTS gate_state text
    CHECK (gate_state IN ('waiting','released','abort') OR gate_state IS NULL),
  ADD COLUMN IF NOT EXISTS parent_run_id uuid REFERENCES analysis.workflow_run(run_id),
  ADD COLUMN IF NOT EXISTS custody_tier text NOT NULL DEFAULT 'full'
    CHECK (custody_tier IN ('full','light'));

-- ---------------------------------------------------------------------------
-- Indexes
-- ---------------------------------------------------------------------------

-- Retry lineage lookups ("show me every retry of run X") + cheap filtering
-- of root runs (parent_run_id IS NULL) without a full scan.
CREATE INDEX IF NOT EXISTS idx_workflow_run_parent
  ON analysis.workflow_run(parent_run_id)
  WHERE parent_run_id IS NOT NULL;

-- The supervised-gate poll loop (server/evidence/run_ledger.py's read_gate)
-- runs every ~2s per paused run; a partial index on the non-NULL gate states
-- keeps that lookup (and the operator console's "runs awaiting a decision"
-- view) index-only.
CREATE INDEX IF NOT EXISTS idx_workflow_run_gate_state
  ON analysis.workflow_run(gate_state)
  WHERE gate_state IS NOT NULL;
