-- 0002_schema.sql — dual-schema boundary + HITL audit tables (handoff §6/§8.1)
--
-- evidence  : raw/source data — agents read-only (enforced at the connection,
--             not the prompt: readonly_engine + default_transaction_read_only).
-- analysis  : derived artifacts — writes only after recorded approval.
-- public    : HITL audit tables (agent_run, approval_request) + Agno-managed
--             tables (knowledge vectors/contents, learning stores — Agno creates those).
--
-- NO learned_knowledge table — the native LearningMachine owns that (ADR-0004).

CREATE SCHEMA IF NOT EXISTS evidence;
CREATE SCHEMA IF NOT EXISTS analysis;

-- ---------------------------------------------------------------------------
-- HITL audit trail
--
-- LEGACY (2026-06-12): agent_run + approval_request are SUPERSEDED by the
-- native agno approvals store (agno 2.6.13 creates/owns agno_approvals;
-- @approval tools persist rows there and /approvals serves them). Kept only
-- so existing rows/provenance survive; no code writes here anymore.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS agent_run (
  id UUID PRIMARY KEY DEFAULT uuidv7(),   -- PG18 native; timestamp-ordered
  agent_name TEXT NOT NULL,
  run_type TEXT NOT NULL CHECK (run_type IN ('platform','builder')),
  status TEXT NOT NULL CHECK (status IN
    ('queued','running','awaiting_approval','completed','failed','cancelled')),
  user_prompt TEXT NOT NULL,
  summarized_plan TEXT,
  approval_required BOOLEAN NOT NULL DEFAULT TRUE,
  started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  completed_at TIMESTAMPTZ,
  error_message TEXT
);

CREATE TABLE IF NOT EXISTS approval_request (
  id UUID PRIMARY KEY DEFAULT uuidv7(),
  agent_run_id UUID REFERENCES agent_run(id) ON DELETE CASCADE,
  -- Agno run id needed to resume a paused run via continue_run(run_id=...)
  run_id UUID,
  -- which paused tool execution this approval refers to (native requires_confirmation)
  paused_tool TEXT,
  requested_action TEXT NOT NULL,
  requested_by_agent TEXT NOT NULL,
  risk_level TEXT NOT NULL CHECK (risk_level IN ('low','medium','high','critical')),
  approval_status TEXT NOT NULL DEFAULT 'pending' CHECK (approval_status IN
    ('pending','approved','rejected','expired')),
  requested_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  decided_at TIMESTAMPTZ,
  decided_by TEXT,
  decision_notes TEXT
);

-- ---------------------------------------------------------------------------
-- Evidence schema — custody/integrity hashes live with the evidence
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS evidence.evidence_hash (
  id UUID PRIMARY KEY DEFAULT uuidv7(),
  source_ref TEXT NOT NULL,                 -- what was hashed (path/object key/record id)
  algo TEXT NOT NULL DEFAULT 'sha256',
  digest BYTEA NOT NULL,                    -- RAW bytes, not hex text (32B for sha256)
  hashed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (algo <> 'sha256' OR octet_length(digest) = 32)
);

-- ---------------------------------------------------------------------------
-- ChatMiner output (Phase 10 fills this; table exists from day one)
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS transcript_insight (
  id UUID PRIMARY KEY DEFAULT uuidv7(),
  source_file TEXT NOT NULL,
  platform TEXT,
  insight_type TEXT NOT NULL,
  content TEXT NOT NULL,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  mined_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ---------------------------------------------------------------------------
-- Indexes
-- ---------------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_agent_run_status
  ON agent_run(status, started_at DESC);
CREATE INDEX IF NOT EXISTS idx_approval_request_status
  ON approval_request(approval_status, requested_at DESC);
CREATE INDEX IF NOT EXISTS idx_evidence_hash_digest
  ON evidence.evidence_hash(digest);
CREATE INDEX IF NOT EXISTS idx_transcript_insight_type
  ON transcript_insight(insight_type, mined_at DESC);
