-- 0027_walk_ledger.sql — ADR-0045 §B DERIVED pass materialization lands (W1.3).
--
-- Byline: Claude Code . glm-5.2:cloud . 2026-08-14
-- Byline amendment: Codex GPT-5 . 2026-08-18
-- Byline amendment: Codex GPT-5 . 2026-08-18 (legacy-view forward upgrade)
-- Supersession: this HELD/unapplied draft now separates resumable healthy
-- checkpoints from sealed failure snapshots and hashes every visibility-bearing
-- base input (routes, acquisitions, and realization links), not only source rows.
--
-- ✅ APPLIED TO PROD — verified live 2026-08-23 against 100.91.190.107:5432 db=ai by direct
--    introspection (Claude Code · Opus 5). walk_run, walk_step, walk_step_retrieval and
--    walk_checkpoint all confirmed PRESENT.
-- ~~⚠ HELD FOR OWNER — COMMITTED + ROLLBACK-VALIDATED, NOT APPLIED TO PROD.~~  (historical)
-- Apply only through the reviewed 0026-0030 release sequence.
--
-- WHAT THIS IS
-- ============
-- Wave 1.3 — the checkpoint-derivation ledger. ADR-0045 §B (signed D-042)
-- sanctions version-pinned DERIVED pass materializations and FORBIDS parallel
-- authored as-lived/hindsight stores: there is ONE authored store
-- (working.normalized_record + working.realization_event), and the derivation
-- engine (server/evidence/derivation.py, W1.3) is its SOLE writer of the pass
-- corpora. This migration creates the ledger tables those corpora + checkpoints
-- live in, plus two diagnostic views (contamination + delta).
--
-- This is a DERIVED store, never authored by hand. The refresher is the only
-- writer (enforced app-side by pg_advisory_lock F13 here, DB-side by W1.4
-- grants). Re-derivation at the same base_version MUST reproduce the identical
-- hash chain (proven by the W1.3 validation script before any agent binds).
--
-- RECONCILED FROM sql/drafts/walk_ledger.postgres-draft.HOLD.sql (SUPERSEDED)
-- ========================================================================
-- The draft was design input, NOT a lift-as-is. It was reconciled against the
-- ADR-0045 §B refresher contract. Four corrections (the draft predates the
-- working/analysis schema split and ADR-0045 §B's signing):
--   1. schema analysis.* -> working.* — ADR-0045 §B names working.walk_ledger.
--   2. FK -> working.normalized_record (the draft referenced analysis.normalized_record,
--      the pre-split location; canonical evidence is working.normalized_record).
--   3. contamination view: working.visible_from(record_id) > horizon_at (NOT the
--      draft's nr.knowledge_time > s.horizon_at — knowledge_time is SUPERSEDED,
--      ADR-0045 §A / 0008:247; the horizon clock is visible_from).
--   4. §B chain-hash + version-pin columns the draft had NONE of: walk_run gains
--      base_version + parameters + genesis_hash + final_corpus_hash; walk_step
--      gains corpus_hash + prev_hash. The draft's step rows were unhashed — they
--      could not prove reproducibility. The §B contract requires every checkpoint
--      to record base_version, parameters, corpus_hash, prev_hash and to
--      hash-attest to ops.audit_ledger.
--
-- SCOPE BOUNDARY — what this migration does NOT do
-- =================================================
-- * It does NOT repoint working.horizon_visible / working.vw_spine_horizon at
--   visible_from. That is the F1-resolution repoint, a SEPARATE migration
--   (0028, drafted + rollback-validated in W1.3, held for owner — it is the
--   live-behavior flip and depends on the F4 bundled-doc degenerate ruling).
--   This migration is purely additive (new tables + new views; no DROP/REPLACE).
-- * It does NOT create the refresher engine — that is server/evidence/derivation.py
--   (W1.3 code). The tables are empty until the engine writes them.
-- * It does NOT grant roles — W1.4 (default-deny, refresher = sole writer).
-- * It does NOT bind agents — W1.5 (only after W1.3 + W1.4 land).
--
-- SAFETY
-- ======
-- Pure additive: three CREATE TABLE IF NOT EXISTS, two CREATE OR REPLACE VIEW
-- (new names — no existing object of these names), indexes, COMMENTs. NO DROP,
-- NO REPLACE of any EXISTING object. Never edits the evidence spine. Idempotent.
-- Applied to the LIVE schema (the authority). Validated inside a rollback
-- transaction on live before it is applied for real. Never edit after apply — add 0028.

BEGIN;

-- ---------------------------------------------------------------------------
-- working.walk_run — one horizon walk (an agent running a pass over a case).
-- ---------------------------------------------------------------------------
-- A "pass" is a knowledge horizon bound to an agent (canon §1) — NOT a table.
-- A walk_run is the DERIVED record of one agent executing one pass: the
-- version-pinned base it was derived against, the schedule, and the final hash.
-- horizon_policy:
--   ignorant  — walks forward, horizon advances each step (the gaslightable agent)
--   hindsight — sees the whole case at once (horizon_at IS NULL = no cutoff)
--   custom    — a caller-supplied ceiling (horizon_ceiling)
-- base_version: the pinned DB content-version the walk was derived against. The
-- refresher pins a base_version at the start; re-deriving at the SAME base_version
-- MUST reproduce the identical hash chain (§B). Moving the base forward produces
-- a NEW run, never mutates an old one (append-only).
CREATE TABLE IF NOT EXISTS working.walk_run (
    id              UUID PRIMARY KEY DEFAULT uuidv7(),

    case_id         TEXT NOT NULL DEFAULT 'primary'
                    CHECK (length(case_id) > 0),

    agent_id        TEXT NOT NULL,
    bound_lane      TEXT,                       -- the pass/lane binding (W1.5)

    horizon_policy  TEXT NOT NULL
                    CHECK (horizon_policy IN ('ignorant', 'hindsight', 'custom')),
    horizon_ceiling TIMESTAMPTZ,                 -- custom policy only; NULL = no ceiling

    -- Provenance of the walk itself (for reproducibility + court export).
    model_id        TEXT,
    prompt_version  TEXT,

    -- §B version-pinning. base_version is the content-hash of the authored store
    -- at derivation time; genesis_hash = sha256(base_version || canonical
    -- parameters) is the prev_hash of step 1. The refresher computes these; the
    -- DB only stores them. final_corpus_hash is stamped when the run completes.
    base_version    TEXT NOT NULL,
    parameters      JSONB NOT NULL DEFAULT '{}' CHECK (jsonb_typeof(parameters) = 'object'),
    genesis_hash    TEXT NOT NULL,
    final_corpus_hash TEXT,

    status          TEXT NOT NULL DEFAULT 'running'
                    CHECK (status IN ('running', 'completed', 'failed',
                                      'invalidated')),
    invalidated_reason TEXT,

    started_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    finished_at     TIMESTAMPTZ,
    notes           TEXT,

    CHECK (horizon_policy <> 'custom' OR horizon_ceiling IS NOT NULL)
);

CREATE INDEX IF NOT EXISTS idx_walk_run_case_status
    ON working.walk_run (case_id, status);
CREATE INDEX IF NOT EXISTS idx_walk_run_base_version
    ON working.walk_run (base_version);

COMMENT ON TABLE working.walk_run IS
  'ADR-0045 §B DERIVED pass materialization: one agent executing one pass over '
  'a case at a pinned base_version. A pass is a knowledge horizon bound to an '
  'agent (canon §1), not a table. DERIVED — never hand-authored; the refresher '
  '(server/evidence/derivation.py) is the SOLE writer (pg_advisory_lock F13 + '
  'W1.4 grants). Re-derivation at the same base_version MUST reproduce the '
  'identical hash chain. Append-only: a new base_version is a NEW run.';

COMMENT ON COLUMN working.walk_run.base_version IS
  'The content-version of the authored store (normalized_record + '
  'realization_event) this walk was derived against. genesis_hash = '
  'sha256(base_version || canonical parameters). Re-deriving at this same '
  'base_version reproduces the identical corpus_hash chain (§B reproducibility).';

-- ---------------------------------------------------------------------------
-- working.walk_step — one checkpoint in the walk (the chain-hashed unit).
-- ---------------------------------------------------------------------------
-- As-lived (ignorant) walks advance the horizon one step at a time; each step
-- appends the newly-visible slice and chain-hashes it. These step records ARE
-- working.walk_ledger (ADR-0045 §B): prev_hash chains to the prior step's
-- corpus_hash (step 1's prev_hash = run.genesis_hash). corpus_hash is the hash
-- of the canonical visible slice at this step. Hindsight walks are a single
-- step (horizon_at NULL = no cutoff).
--
-- record_id is the FOCAL record of the step (the event the agent is reacting
-- to), if any — NOT the whole visible slice (the slice is hashed into
-- corpus_hash, not stored row-by-row, to keep the ledger compact + reproducible).
CREATE TABLE IF NOT EXISTS working.walk_step (
    id              UUID PRIMARY KEY DEFAULT uuidv7(),

    walk_run_id     UUID NOT NULL
                    REFERENCES working.walk_run(id) ON DELETE CASCADE,

    step_no         INT NOT NULL,

    -- The knowledge horizon for this step. NULL = hindsight (no cutoff — the
    -- whole case is visible). For an ignorant walk this ADVANCES each step;
    -- that advance is the point (canon §1 — the agent lives events as discovered).
    horizon_at      TIMESTAMPTZ,

    -- The focal record the agent is reacting to at this step, if any.
    record_id       UUID REFERENCES working.normalized_record(id) ON DELETE RESTRICT,

    -- The agent's output + state at this step (analysis layer writes these).
    conclusion      TEXT,
    belief          JSONB CHECK (belief IS NULL OR jsonb_typeof(belief) = 'object'),
    confidence      REAL CHECK (confidence IS NULL OR (confidence >= 0 AND confidence <= 1)),
    stance          TEXT,

    -- §B chain-hash. corpus_hash = sha256(canonical visible slice at this step);
    -- prev_hash = the prior step's corpus_hash (step 1 = run.genesis_hash).
    -- The refresher computes these; re-derivation at the same base_version
    -- reproduces them exactly. These are the reproducibility attestation.
    corpus_hash    TEXT NOT NULL,
    prev_hash      TEXT NOT NULL,

    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),

    UNIQUE (walk_run_id, step_no)
);

CREATE INDEX IF NOT EXISTS idx_walk_step_run_step
    ON working.walk_step (walk_run_id, step_no);
CREATE INDEX IF NOT EXISTS idx_walk_step_record
    ON working.walk_step (record_id) WHERE record_id IS NOT NULL;

COMMENT ON TABLE working.walk_step IS
  'ADR-0045 §B: one checkpoint in a walk_run. As-lived walks append the '
  'newly-visible slice per step and chain-hash it (prev_hash -> prior corpus_hash; '
  'step 1 prev_hash = run.genesis_hash). corpus_hash attests to the visible slice; '
  'the chain proves the walk was not tampered with. Re-derivation at the same '
  'base_version reproduces the identical chain. DERIVED — refresher is sole writer.';

COMMENT ON COLUMN working.walk_step.corpus_hash IS
  'sha256 of the canonical visible slice at this step (the records visible in '
  'the horizon window, deterministically serialized). The chain link: this step''s '
  'corpus_hash is the next step''s prev_hash. Reproducibility attestation.';

-- ---------------------------------------------------------------------------
-- working.walk_step_retrieval — what the agent retrieved at each step.
-- ---------------------------------------------------------------------------
-- Provenance for the delta + contamination views: which records were retrieved
-- from which store, at what rank/score, and whether the agent actually used
-- them. was_used=false is a retrieved-but-discarded record (a contamination
-- signal if its visible_from > step horizon_at).
CREATE TABLE IF NOT EXISTS working.walk_step_retrieval (
    id              UUID PRIMARY KEY DEFAULT uuidv7(),

    walk_step_id    UUID NOT NULL
                    REFERENCES working.walk_step(id) ON DELETE CASCADE,

    record_id       UUID NOT NULL
                    REFERENCES working.normalized_record(id) ON DELETE RESTRICT,

    store           TEXT NOT NULL
                    CHECK (store IN ('postgres', 'weaviate', 'graphiti',
                                     'neo4j', 'other')),
    rank            INT,
    score           REAL,
    was_used        BOOLEAN NOT NULL DEFAULT false,

    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

    UNIQUE (walk_step_id, record_id, store)
);

CREATE INDEX IF NOT EXISTS idx_walk_step_retrieval_record
    ON working.walk_step_retrieval (record_id);

COMMENT ON TABLE working.walk_step_retrieval IS
  'What a walk_step retrieved: record, store, rank, score, and whether the agent '
  'used it. Feeds vw_walk_contamination (retrieved a record whose visible_from > '
  'the step horizon) and the delta provenance. DERIVED — refresher is sole writer.';

-- ---------------------------------------------------------------------------
-- working.vw_walk_contamination — the silent-leak detector (ADR-0045 §A).
-- ---------------------------------------------------------------------------
-- A row here means a record was retrieved/used at a step whose visible_from is
-- AFTER the step's horizon_at — i.e. the ignorant agent saw a fact it should not
-- have known yet. This is the contamination that silently corrupts the delta.
-- Uses working.visible_from(record_id) (the §A clock), NOT the superseded
-- knowledge_time (correction #3 from the draft).
CREATE OR REPLACE VIEW working.vw_walk_contamination AS
SELECT s.walk_run_id,
       s.step_no,
       s.horizon_at,
       ret.record_id,
       ret.store,
       ret.was_used,
       working.visible_from(ret.record_id) AS visible_from
  FROM working.walk_step s
  JOIN working.walk_step_retrieval ret
    ON ret.walk_step_id = s.id
 WHERE s.horizon_at IS NOT NULL
   AND working.visible_from(ret.record_id) > s.horizon_at;

COMMENT ON VIEW working.vw_walk_contamination IS
  'ADR-0045 §A contamination detector: a record retrieved at a step whose '
  'visible_from(record_id) > the step horizon_at was knowable only later — the '
  'ignorant agent saw a future fact. Non-empty here = the delta is silently '
  'corrupted. Uses visible_from (the §A clock), NOT the superseded knowledge_time.';

-- ---------------------------------------------------------------------------
-- 2026-08-18 held-draft amendment: resumability and complete version inputs.
-- ---------------------------------------------------------------------------
ALTER TABLE working.walk_run
  DROP CONSTRAINT IF EXISTS walk_run_status_check;
ALTER TABLE working.walk_run
  ADD CONSTRAINT walk_run_status_check
  CHECK (status IN ('running','paused','completed','sealed','failed','invalidated'));
ALTER TABLE working.walk_run
  ADD COLUMN IF NOT EXISTS rewalk_of_id UUID REFERENCES working.walk_run(id) ON DELETE RESTRICT,
  ADD COLUMN IF NOT EXISTS resume_from_checkpoint_id UUID,
  ADD COLUMN IF NOT EXISTS sealed_at TIMESTAMPTZ;

CREATE TABLE IF NOT EXISTS working.walk_checkpoint (
  id UUID PRIMARY KEY DEFAULT uuidv7(),
  walk_run_id UUID NOT NULL REFERENCES working.walk_run(id) ON DELETE CASCADE,
  checkpoint_no INTEGER NOT NULL CHECK (checkpoint_no>=0),
  checkpoint_kind TEXT NOT NULL CHECK (checkpoint_kind IN ('healthy','failure_seal')),
  last_completed_step_no INTEGER NOT NULL CHECK (last_completed_step_no>=0),
  cursor JSONB NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(cursor)='object'),
  belief_state JSONB NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(belief_state)='object'),
  base_version TEXT NOT NULL CHECK (length(base_version)>0),
  horizon_hash TEXT NOT NULL CHECK (length(horizon_hash)=64),
  chain_hash TEXT NOT NULL CHECK (length(chain_hash)=64),
  is_resumable BOOLEAN NOT NULL,
  failure JSONB CHECK (failure IS NULL OR jsonb_typeof(failure)='object'),
  captured_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(id, walk_run_id),
  UNIQUE(walk_run_id, checkpoint_no),
  CHECK ((checkpoint_kind='healthy' AND is_resumable AND failure IS NULL)
      OR (checkpoint_kind='failure_seal' AND NOT is_resumable AND failure IS NOT NULL))
);
CREATE INDEX IF NOT EXISTS walk_checkpoint_run_latest_idx
  ON working.walk_checkpoint(walk_run_id, checkpoint_no DESC);

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='walk_run_resume_checkpoint_fk'
                  AND conrelid='working.walk_run'::regclass) THEN
    ALTER TABLE working.walk_run ADD CONSTRAINT walk_run_resume_checkpoint_fk
      FOREIGN KEY(resume_from_checkpoint_id, id)
      REFERENCES working.walk_checkpoint(id, walk_run_id)
      ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED;
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS working.walk_step_realization_retrieval (
  id UUID PRIMARY KEY DEFAULT uuidv7(),
  walk_step_id UUID NOT NULL REFERENCES working.walk_step(id) ON DELETE CASCADE,
  realization_event_id UUID NOT NULL REFERENCES working.realization_event(id) ON DELETE RESTRICT,
  store TEXT NOT NULL CHECK (store IN ('postgres','weaviate','graphiti','neo4j','other')),
  rank INTEGER,
  score REAL,
  was_used BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(walk_step_id, realization_event_id, store)
);
CREATE INDEX IF NOT EXISTS walk_step_realization_retrieval_event_idx
  ON working.walk_step_realization_retrieval(realization_event_id);

-- Canonical rows for deterministic base_version hashing.  Consumers serialize
-- these in (input_kind,input_key) order. Proposed decisions are included because
-- approval transitions alter visibility and therefore must move the base version.
CREATE OR REPLACE VIEW working.vw_walk_base_version_input AS
SELECT nr.case_id, 'normalized_record'::TEXT AS input_kind, nr.id::TEXT AS input_key,
       jsonb_build_object('content_sha256',encode(COALESCE(nr.source_content_sha256,
         digest(convert_to(nr.content,'UTF8'),'sha256')),'hex'),
         'occurred_at',nr.occurred_at,'disclosure_tier',nr.disclosure_tier) AS input_payload
  FROM working.normalized_record nr
UNION ALL
SELECT nr.case_id, 'message_projection_route', r.normalized_record_id::TEXT,
       jsonb_build_object('projection_kind',r.projection_kind,'decision_state',r.decision_state,
                          'approved_at',r.approved_at,'deriver_version',r.deriver_version)
  FROM working.message_projection_route r
  JOIN working.normalized_record nr ON nr.id=r.normalized_record_id
UNION ALL
SELECT tc.case_id, 'third_party_acquisition', ca.id::TEXT,
       jsonb_build_object('conversation_id',ca.conversation_id,'acquisition_id',ca.acquisition_id,
                          'approval_state',ca.approval_state,'acquired_at',a.acquired_at)
  FROM working.third_party_conversation_acquisition ca
  JOIN working.third_party_conversation tc ON tc.id=ca.conversation_id
  JOIN evidence.acquisition a ON a.id=ca.acquisition_id
UNION ALL
SELECT re.case_id, 'realization_event', re.id::TEXT,
       jsonb_build_object('kind',re.kind,'realized_at',re.realized_at,
                          'approval_state',re.approval_state,'trigger_record_id',re.trigger_record_id)
  FROM working.realization_event re
UNION ALL
SELECT rer.case_id, 'realization_event_record',
       rer.realization_event_id::TEXT || ':' || rer.normalized_record_id::TEXT,
       jsonb_build_object('realization_event_id',rer.realization_event_id,
                          'normalized_record_id',rer.normalized_record_id)
  FROM working.realization_event_record rer;

-- NULL availability is a fail-closed contamination, not an invisible success.
CREATE OR REPLACE VIEW working.vw_walk_contamination AS
SELECT s.walk_run_id, s.step_no, s.horizon_at, ret.record_id, ret.store, ret.was_used,
       working.source_available_from(ret.record_id) AS visible_from
  FROM working.walk_step s
  JOIN working.walk_step_retrieval ret ON ret.walk_step_id=s.id
 WHERE working.source_available_from(ret.record_id) IS NULL
    OR (s.horizon_at IS NOT NULL
        AND working.source_available_from(ret.record_id)>s.horizon_at)
UNION ALL
SELECT s.walk_run_id, s.step_no, s.horizon_at, NULL::UUID, ret.store, ret.was_used,
       re.realized_at
  FROM working.walk_step s
  JOIN working.walk_step_realization_retrieval ret ON ret.walk_step_id=s.id
  JOIN working.realization_event re ON re.id=ret.realization_event_id
 WHERE re.approval_state<>'approved'
    OR (s.horizon_at IS NOT NULL AND re.realized_at>s.horizon_at);

CREATE OR REPLACE VIEW working.vw_walk_delta AS
SELECT s.walk_run_id, s.step_no, s.horizon_at, s.record_id AS focal_record_id,
       s.conclusion AS believed_then, nr.content AS actual, nr.occurred_at,
       working.source_available_from(s.record_id) AS actual_known_from,
       CASE WHEN rz.first_realized_at IS NOT NULL AND nr.occurred_at IS NOT NULL
            THEN rz.first_realized_at-nr.occurred_at END AS realization_lag,
       rz.first_realized_at
  FROM working.walk_step s
  JOIN working.normalized_record nr ON nr.id=s.record_id
  LEFT JOIN LATERAL (
    SELECT min(re.realized_at) AS first_realized_at
      FROM working.realization_event_record rer
      JOIN working.realization_event re ON re.id=rer.realization_event_id
     WHERE rer.normalized_record_id=s.record_id AND re.approval_state='approved'
  ) rz ON true
 WHERE s.record_id IS NOT NULL;

COMMENT ON TABLE working.walk_checkpoint IS
  'Healthy checkpoints are resumable. Failure seals are immutable diagnostic snapshots and never resume; create rewalk_of_id for a clean rewalk.';
COMMENT ON VIEW working.vw_walk_base_version_input IS
  'Deterministically ordered inputs for a walk base-version hash, including visibility-bearing projection, acquisition, and realization decisions.';

COMMIT;
