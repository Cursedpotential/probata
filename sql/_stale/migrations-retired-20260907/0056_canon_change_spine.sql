-- 0056_canon_change_spine.sql
--
-- Byline: Claude · Opus 5 · 2026-08-31, owner-ruled ("This seems logical" —
-- spine over per-domain, after systems/archetype/KT analysis).
--
-- THE UNIVERSAL CHANGE-PROPOSAL SPINE. Owner requirement, verbatim across the
-- 2026-08-30/31 design session:
--
--   "anywhere where a change is made to something that has to come back to PG
--    and be approved in order to make it canonical and then it has to
--    re-trigger any downstream derived works to be recalculated"
--
-- One mechanism for every surface: AI extractors (entity/event/classification
-- suggestions), the Workbench/UIW (form edits), graph reconciliation
-- (Semantica vs SAT contradictions resolved in PG then reprojected), agents,
-- and direct human correction — including corrected metadata and promotion.
--
-- The existing typed candidate tables (working.candidate_*, claim_candidate,
-- timeline.event_candidate, ...) are NOT replaced: they propose NEW things.
-- The spine governs CHANGES TO CANON and the adoption step for everything.
--
-- Three requirements from the design analysis are structural here:
--   1. RISK TIERS AS DATA. The review valve is one human. Proposal classes map
--      to auto_adopt / batch_review / explicit_review in a data table, so the
--      valve is retunable without a migration. (Limits-to-Growth guard.)
--   2. CANON BOUNDARY. The spine governs only tables registered in
--      canon.canonical_table. Unregistered = out of scope by definition.
--   3. THE RECOMPUTE LEG SHIPS WITH THE SPINE. canon.recompute_queue is the
--      change-detection hook; adoption enqueues it in the same transaction.
--      (The 0024 CDC outbox died of consumer-lessness; this one is pollable
--      by design and the one-lane test wires its first consumer.)
--
-- Staleness guard (0055's source_generation doing double duty, design doc §3):
-- every proposal records the generation it was reasoned against; adoption of a
-- superseded-generation proposal REQUEUES instead of applying.
--
-- NOTHING HERE IS IMMUTABLE. No guard triggers, per D-110. Correction history
-- is preserved by RECORDING (prior values snapshotted on apply), not by
-- forbidding writes.

CREATE SCHEMA IF NOT EXISTS canon AUTHORIZATION platform_admin;

-- ---------------------------------------------------------------------------
-- 1 · Risk tiers — data, not enum, so the valve is retunable live
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS canon.change_tier (
  tier          TEXT PRIMARY KEY,
  description   TEXT NOT NULL,
  auto_applies  BOOLEAN NOT NULL DEFAULT FALSE,
  sort_order    INTEGER NOT NULL DEFAULT 0
);
INSERT INTO canon.change_tier (tier, description, auto_applies, sort_order) VALUES
  ('auto_adopt',      'Applied immediately, logged, reversible. For mechanical low-risk classes (e.g. whitespace/format normalization).', TRUE,  1),
  ('batch_review',    'Queued for bulk human approval. The default for AI-suggested corrections.',                                        FALSE, 2),
  ('explicit_review', 'One-by-one human ruling. Promotions, evidence-adjacent changes, merges.',                                          FALSE, 3)
ON CONFLICT (tier) DO NOTHING;

-- ---------------------------------------------------------------------------
-- 2 · Canon boundary — which tables the spine governs
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS canon.canonical_table (
  id                 UUID PRIMARY KEY DEFAULT uuidv7(),
  table_schema       TEXT NOT NULL,
  table_name         TEXT NOT NULL,
  default_tier       TEXT NOT NULL REFERENCES canon.change_tier(tier) DEFAULT 'batch_review',
  current_generation BIGINT NOT NULL DEFAULT 0,   -- bumped on every applied change; the staleness anchor
  recompute_targets  TEXT[] NOT NULL DEFAULT '{}', -- e.g. {semantica,sat_temporal,vectors,timeline}
  registered_by      TEXT NOT NULL,
  registered_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  notes              TEXT,
  UNIQUE (table_schema, table_name)
);
COMMENT ON TABLE canon.canonical_table IS
  'The canon boundary. The spine accepts proposals only against rows of tables registered here. Registration is an owner act. current_generation is the per-table staleness anchor: proposals record it at filing, adoption checks it.';

-- ---------------------------------------------------------------------------
-- 3 · The spine — one proposal shape for every surface
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS canon.change_proposal (
  id                 UUID PRIMARY KEY DEFAULT uuidv7(),
  canonical_table_id UUID NOT NULL REFERENCES canon.canonical_table(id),
  target_pk          JSONB NOT NULL,        -- {"id": "..."} or composite
  proposal_kind      TEXT NOT NULL CHECK (proposal_kind IN
                       ('correct',          -- change field values on an existing canonical row
                        'adopt_candidate',  -- adopt a row from a typed candidate table into canon
                        'promote',          -- promotion (e.g. context -> evidence)
                        'merge',            -- two canonical rows are one thing
                        'retire',           -- canonical row should no longer be canon
                        'create')),         -- new canonical row proposed directly
  patch              JSONB NOT NULL,        -- {"column": new_value, ...}; for merge/retire: parameters
  rationale          TEXT,

  -- provenance: which surface proposed this, with enough to trace back
  origin_surface     TEXT NOT NULL CHECK (origin_surface IN
                       ('extractor','workbench','graph_reconciliation','agent','human')),
  origin_ref         JSONB NOT NULL DEFAULT '{}'::jsonb,  -- {graph_lane, run_id, candidate_table, candidate_id, ...}
  proposed_by        TEXT NOT NULL,

  -- staleness guard (design doc §3; the same field as 0055 §2 doing double duty)
  source_generation  BIGINT NOT NULL,

  tier               TEXT NOT NULL REFERENCES canon.change_tier(tier),
  status             TEXT NOT NULL DEFAULT 'proposed' CHECK (status IN
                       ('proposed','approved','rejected','stale_requeued','applied','failed')),
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS change_proposal_open_idx
  ON canon.change_proposal (status, tier) WHERE status = 'proposed';
CREATE INDEX IF NOT EXISTS change_proposal_table_idx
  ON canon.change_proposal (canonical_table_id, created_at);
COMMENT ON TABLE canon.change_proposal IS
  'The universal write path to canon. Nothing authors canonical rows directly: extractors, the Workbench, graph reconciliation, agents and humans all file here. Rejected proposals are retained and marked, never deleted.';

-- ---------------------------------------------------------------------------
-- 4 · Decisions — the human ruling (or the auto_adopt record)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS canon.change_decision (
  id           UUID PRIMARY KEY DEFAULT uuidv7(),
  proposal_id  UUID NOT NULL REFERENCES canon.change_proposal(id),
  decided_by   TEXT NOT NULL,               -- 'owner' | 'auto:<tier>' — auto adoptions are decisions too, attributed
  decision     TEXT NOT NULL CHECK (decision IN ('approve','reject','requeue')),
  batch_id     UUID,                        -- set when ruled as part of a bulk batch_review pass
  note         TEXT,
  decided_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS change_decision_proposal_idx ON canon.change_decision (proposal_id);

-- ---------------------------------------------------------------------------
-- 5 · Application receipts — original values preserved by RECORDING
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS canon.change_application (
  id                  UUID PRIMARY KEY DEFAULT uuidv7(),
  proposal_id         UUID NOT NULL UNIQUE REFERENCES canon.change_proposal(id),
  decision_id         UUID NOT NULL REFERENCES canon.change_decision(id),
  prior_values        JSONB NOT NULL,       -- snapshot of every patched column BEFORE the change
  applied_patch       JSONB NOT NULL,
  generation_before   BIGINT NOT NULL,
  generation_after    BIGINT NOT NULL,
  applied_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  error               TEXT                  -- populated when status went to 'failed'
);
COMMENT ON TABLE canon.change_application IS
  'The receipt. prior_values preserves what canon said before the change, so no correction ever silently destroys the original reading — history by recording, not by immutability guards (D-110).';

-- ---------------------------------------------------------------------------
-- 6 · The recompute leg — change detection's hook, shipped WITH the spine
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS canon.recompute_queue (
  id                 UUID PRIMARY KEY DEFAULT uuidv7(),
  application_id     UUID NOT NULL REFERENCES canon.change_application(id),
  canonical_table_id UUID NOT NULL REFERENCES canon.canonical_table(id),
  target_pk          JSONB NOT NULL,
  recompute_target   TEXT NOT NULL,         -- 'semantica' | 'sat_temporal' | 'vectors' | 'timeline' | ...
  status             TEXT NOT NULL DEFAULT 'pending' CHECK (status IN
                       ('pending','claimed','done','failed','skipped')),
  claimed_by         TEXT,
  claimed_at         TIMESTAMPTZ,
  finished_at        TIMESTAMPTZ,
  error              TEXT,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS recompute_queue_pending_idx
  ON canon.recompute_queue (recompute_target, created_at) WHERE status = 'pending';
COMMENT ON TABLE canon.recompute_queue IS
  'One row per (applied change x downstream target). Consumers poll their target, mark claimed/done. This is the leg that forces derived work to recalculate after re-canonicalization. It ships with the spine so it cannot become another consumer-less outbox.';

-- ---------------------------------------------------------------------------
-- 7 · apply function — staleness-checked, snapshotting, enqueueing
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION canon.apply_proposal(p_proposal_id UUID, p_decision_id UUID)
RETURNS UUID
LANGUAGE plpgsql AS $fn$
DECLARE
  v_p        canon.change_proposal%ROWTYPE;
  v_ct       canon.canonical_table%ROWTYPE;
  v_prior    JSONB := '{}'::jsonb;
  v_app_id   UUID;
  v_col      TEXT;
  v_pk_col   TEXT;
  v_pk_val   TEXT;
  v_set_sql  TEXT := '';
  v_tgt      TEXT;
BEGIN
  SELECT * INTO v_p  FROM canon.change_proposal  WHERE id = p_proposal_id FOR UPDATE;
  IF v_p.id IS NULL THEN RAISE EXCEPTION 'proposal % not found', p_proposal_id; END IF;
  IF v_p.status NOT IN ('proposed','approved') THEN
    RAISE EXCEPTION 'proposal % is %, not applicable', p_proposal_id, v_p.status;
  END IF;
  SELECT * INTO v_ct FROM canon.canonical_table  WHERE id = v_p.canonical_table_id FOR UPDATE;

  -- STALENESS GUARD: reasoned against a superseded generation -> requeue, never apply
  IF v_p.source_generation <> v_ct.current_generation THEN
    UPDATE canon.change_proposal SET status = 'stale_requeued' WHERE id = p_proposal_id;
    RETURN NULL;
  END IF;

  -- Only 'correct' patches are applied generically here; other kinds record the
  -- ruling + receipt and are executed by their kind-specific worker off the queue.
  IF v_p.proposal_kind = 'correct' THEN
    SELECT key, value #>> '{}' INTO v_pk_col, v_pk_val
      FROM jsonb_each(v_p.target_pk) LIMIT 1;
    -- snapshot prior values of exactly the patched columns
    EXECUTE format('SELECT to_jsonb(t) FROM %I.%I t WHERE %I = $1::uuid',
                   v_ct.table_schema, v_ct.table_name, v_pk_col)
      INTO v_prior USING v_pk_val;
    IF v_prior IS NULL THEN RAISE EXCEPTION 'target row not found for proposal %', p_proposal_id; END IF;
    SELECT jsonb_object_agg(k, v_prior -> k) INTO v_prior
      FROM jsonb_object_keys(v_p.patch) k;
    -- build and run the update
    SELECT string_agg(format('%I = ($1::jsonb ->> %L)::%s', key,
             key,
             (SELECT format_type(a.atttypid, a.atttypmod)
                FROM pg_attribute a
               WHERE a.attrelid = format('%I.%I', v_ct.table_schema, v_ct.table_name)::regclass
                 AND a.attname = key AND a.attnum > 0)), ', ')
      INTO v_set_sql
      FROM jsonb_each(v_p.patch);
    EXECUTE format('UPDATE %I.%I SET %s WHERE %I = $2::uuid',
                   v_ct.table_schema, v_ct.table_name, v_set_sql, v_pk_col)
      USING v_p.patch, v_pk_val;
  END IF;

  UPDATE canon.canonical_table
     SET current_generation = current_generation + 1
   WHERE id = v_ct.id;

  INSERT INTO canon.change_application
      (proposal_id, decision_id, prior_values, applied_patch, generation_before, generation_after)
  VALUES (p_proposal_id, p_decision_id, coalesce(v_prior,'{}'::jsonb), v_p.patch,
          v_ct.current_generation, v_ct.current_generation + 1)
  RETURNING id INTO v_app_id;

  FOREACH v_tgt IN ARRAY v_ct.recompute_targets LOOP
    INSERT INTO canon.recompute_queue
        (application_id, canonical_table_id, target_pk, recompute_target)
    VALUES (v_app_id, v_ct.id, v_p.target_pk, v_tgt);
  END LOOP;

  UPDATE canon.change_proposal SET status = 'applied' WHERE id = p_proposal_id;
  RETURN v_app_id;
END $fn$;
COMMENT ON FUNCTION canon.apply_proposal(UUID, UUID) IS
  'Adoption: staleness-checked against canonical_table.current_generation, snapshots prior values, applies the patch (correct-kind generically; other kinds via their workers), bumps the generation, enqueues recompute rows — one transaction.';

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------
GRANT USAGE ON SCHEMA canon TO platform_api, platform_worker, platform_reader;
GRANT SELECT ON ALL TABLES IN SCHEMA canon TO platform_reader;
GRANT SELECT, INSERT ON canon.change_proposal TO platform_api, platform_worker;
GRANT SELECT ON canon.canonical_table, canon.change_tier TO platform_api, platform_worker;
GRANT SELECT, INSERT ON canon.change_decision TO platform_api;
GRANT SELECT, UPDATE ON canon.recompute_queue TO platform_worker;
GRANT SELECT ON canon.change_application TO platform_api, platform_worker;
