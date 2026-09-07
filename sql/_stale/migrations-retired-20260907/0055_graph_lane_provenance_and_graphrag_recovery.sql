-- 0055_graph_lane_provenance_and_graphrag_recovery.sql
--
-- Byline: Claude · Opus 5 · 2026-08-30, from an owner directive ("cheap now,
-- expensive later means FIX IT NOW").
--
-- Three things land here. All additive. NOTHING in this migration is immutable
-- and no append-only / forbid / assert guard is created. Per repeated owner
-- ruling (see DECISION_LOG D-108): immutability applies ONLY to promoted
-- evidence, behind a development feature flag, and no evidence has been
-- promoted. Every table below is mutable, alterable, droppable.
--
-- PART 1 · Recovered analysis.graphrag_* comparison schema.
--   Reconstructed from server/analysis/graphrag_repository.cpython-313.pyc
--   (compiled 2026-08-27 16:11) after the .py sources were lost. The exact
--   column lists come from the INSERT/SELECT statements embedded in that
--   bytecode; see docs/recovered/GRAPHRAG-RECOVERED-FROM-BYTECODE.txt.
--   Implements D-093: one sealed PostgreSQL-authorized eligibility manifest
--   feeding two lanes that return lane-labelled envelopes with no fusion.
--
-- PART 2 · The graph-lane discriminator. D-093 requires Semantica and SAT to
--   be independently readable and diffable. Without a lane column their
--   candidate rows are indistinguishable in PG and the A/B is void.
--
-- PART 3 · PG source coordinates on projected graph nodes/edges, plus the
--   source_generation staleness guard. Per
--   docs/design/DUAL-GRAPH-IDENTITY-AND-WRITEBACK-2026-08-29.md §1/§2: a node
--   that cannot be traced to a PG row cannot be diffed, rebuilt, or audited,
--   and a disagreement computed across different generations is staleness,
--   not divergence. Both are cheap while every table is empty and
--   unrecoverable once an extractor has run.

-- ===========================================================================
-- PART 2 (first — the enum is referenced below)
-- ===========================================================================

-- NOTE ON SPELLING: the Neo4j *database* is `sat-temporal` (a dash; Neo4j
-- rejects underscores in database names, which is why D-093's `sat_temporal`
-- spelling could never be created — see D-106). The PostgreSQL *enum label*
-- is `sat_temporal` (underscore), matching the lane ids already baked into
-- graphrag_contracts.pyc and the NEO4J_DB_SAT_TEMPORAL env contract. The two
-- differ deliberately; map at the driver boundary, never rename one to match.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace
                 WHERE t.typname = 'graph_lane' AND n.nspname = 'analysis') THEN
    CREATE TYPE analysis.graph_lane AS ENUM ('semantica', 'sat_temporal');
  END IF;
END $$;

-- ===========================================================================
-- PART 1 · Recovered graphrag comparison schema
-- ===========================================================================

CREATE TABLE IF NOT EXISTS analysis.graphrag_comparison_run (
  id                          UUID PRIMARY KEY DEFAULT uuidv7(),
  query_reference             TEXT NOT NULL,
  correlation_id              TEXT,
  requested_mode              TEXT NOT NULL,
  case_compatibility_reference TEXT,
  horizon_at                  TIMESTAMPTZ NOT NULL,
  created_by                  TEXT NOT NULL,
  created_at                  TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE analysis.graphrag_comparison_run IS
  'D-093 side-by-side evaluation run. horizon_at pins the pre-ranking horizon boundary both lanes share.';

CREATE TABLE IF NOT EXISTS analysis.graphrag_eligibility_manifest (
  id                              UUID PRIMARY KEY DEFAULT uuidv7(),
  run_id                          UUID NOT NULL REFERENCES analysis.graphrag_comparison_run(id) ON DELETE CASCADE,
  schema_version                  INTEGER NOT NULL DEFAULT 1,
  pg_generation_reference         TEXT NOT NULL,
  source_availability_policy_version TEXT NOT NULL,
  disclosure_policy_version       TEXT NOT NULL,
  authorization_policy_version    TEXT NOT NULL,
  issuer                          TEXT NOT NULL,
  status                          TEXT NOT NULL DEFAULT 'open'
                                    CHECK (status IN ('open','sealed')),
  membership_digest               BYTEA,
  member_count                    INTEGER,
  sealed_at                       TIMESTAMPTZ,
  created_at                      TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE analysis.graphrag_eligibility_manifest IS
  'The single PostgreSQL-authorized eligibility set both lanes receive. Sealing computes membership_digest; both lanes cite the same digest or the comparison is invalid.';

CREATE TABLE IF NOT EXISTS analysis.graphrag_eligibility_manifest_member (
  manifest_id              UUID NOT NULL REFERENCES analysis.graphrag_eligibility_manifest(id) ON DELETE CASCADE,
  ordinal                  BIGINT NOT NULL CHECK (ordinal >= 0),
  source_version_id        UUID NOT NULL,
  normalized_record_id     UUID NOT NULL,
  text_unit_id             UUID,
  source_sha256            BYTEA CHECK (source_sha256 IS NULL OR octet_length(source_sha256) = 32),
  normalized_record_digest BYTEA CHECK (normalized_record_digest IS NULL OR octet_length(normalized_record_digest) = 32),
  source_available_from    TIMESTAMPTZ,
  disclosure_tier          TEXT,
  authority_class          TEXT,
  projection_version       TEXT,
  source_provenance_ref    JSONB,
  PRIMARY KEY (manifest_id, ordinal)
);
CREATE INDEX IF NOT EXISTS graphrag_manifest_member_source_version_idx
  ON analysis.graphrag_eligibility_manifest_member (source_version_id);
CREATE INDEX IF NOT EXISTS graphrag_manifest_member_normalized_record_idx
  ON analysis.graphrag_eligibility_manifest_member (normalized_record_id);

CREATE TABLE IF NOT EXISTS analysis.graphrag_lane_result (
  id                 UUID PRIMARY KEY DEFAULT uuidv7(),
  run_id             UUID NOT NULL REFERENCES analysis.graphrag_comparison_run(id) ON DELETE CASCADE,
  lane_id            analysis.graph_lane NOT NULL,
  manifest_id        UUID NOT NULL REFERENCES analysis.graphrag_eligibility_manifest(id) ON DELETE CASCADE,
  manifest_digest    BYTEA NOT NULL,
  projection_version TEXT,
  status             TEXT NOT NULL,
  trace_ref          JSONB,
  warning_refs       JSONB,
  error_ref          JSONB,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (run_id, lane_id)
);

CREATE TABLE IF NOT EXISTS analysis.graphrag_lane_candidate (
  id                       UUID PRIMARY KEY DEFAULT uuidv7(),
  lane_result_id           UUID NOT NULL REFERENCES analysis.graphrag_lane_result(id) ON DELETE CASCADE,
  ordinal                  BIGINT NOT NULL CHECK (ordinal >= 0),
  source_version_id        UUID NOT NULL,
  normalized_record_id     UUID NOT NULL,
  text_unit_id             UUID,
  source_sha256            BYTEA CHECK (source_sha256 IS NULL OR octet_length(source_sha256) = 32),
  normalized_record_digest BYTEA CHECK (normalized_record_digest IS NULL OR octet_length(normalized_record_digest) = 32),
  source_available_from    TIMESTAMPTZ,
  disclosure_tier          TEXT,
  authority_class          TEXT,
  projection_version       TEXT,
  candidate_type           TEXT NOT NULL,
  candidate_ref            JSONB,
  trace_ref                JSONB,
  created_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (lane_result_id, ordinal)
);
COMMENT ON TABLE analysis.graphrag_lane_candidate IS
  'Per-lane candidates carrying the PG source coordinate (source_version_id, normalized_record_id, text_unit_id) so two lanes can be diffed on provenance without first resolving entity identity.';

CREATE TABLE IF NOT EXISTS analysis.graphrag_lane_receipt (
  id              UUID PRIMARY KEY DEFAULT uuidv7(),
  run_id          UUID NOT NULL REFERENCES analysis.graphrag_comparison_run(id) ON DELETE CASCADE,
  lane_id         analysis.graph_lane NOT NULL,
  stage_id        TEXT NOT NULL,
  stage_version   TEXT NOT NULL,
  manifest_id     UUID NOT NULL REFERENCES analysis.graphrag_eligibility_manifest(id) ON DELETE CASCADE,
  manifest_digest BYTEA NOT NULL,
  status          TEXT NOT NULL,
  lane_result_id  UUID REFERENCES analysis.graphrag_lane_result(id) ON DELETE SET NULL,
  outcome_ref     JSONB,
  error_ref       JSONB,
  completed_at    TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (run_id, lane_id, stage_id, stage_version, manifest_digest)
);

CREATE TABLE IF NOT EXISTS analysis.graphrag_comparison_join (
  id                      UUID PRIMARY KEY DEFAULT uuidv7(),
  run_id                  UUID NOT NULL REFERENCES analysis.graphrag_comparison_run(id) ON DELETE CASCADE,
  stage_id                TEXT NOT NULL,
  stage_version           TEXT NOT NULL,
  manifest_id             UUID NOT NULL REFERENCES analysis.graphrag_eligibility_manifest(id) ON DELETE CASCADE,
  manifest_digest         BYTEA NOT NULL,
  semantica_receipt_id    UUID REFERENCES analysis.graphrag_lane_receipt(id) ON DELETE SET NULL,
  sat_temporal_receipt_id UUID REFERENCES analysis.graphrag_lane_receipt(id) ON DELETE SET NULL,
  created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (run_id, stage_id, stage_version, manifest_id, manifest_digest)
);
COMMENT ON TABLE analysis.graphrag_comparison_join IS
  'Joins the two lane receipts for one stage. Both lanes must cite the same manifest_digest; no automatic fusion of results (D-093).';

-- Seal an exact membership set and return its canonical digest.
CREATE OR REPLACE FUNCTION analysis.seal_graphrag_manifest(p_manifest_id UUID)
RETURNS TABLE (manifest_id UUID, membership_digest BYTEA, member_count INTEGER, sealed_at TIMESTAMPTZ)
LANGUAGE plpgsql AS $$
DECLARE
  v_digest BYTEA;
  v_count  INTEGER;
  v_now    TIMESTAMPTZ := now();
BEGIN
  SELECT count(*)::INTEGER,
         digest(coalesce(string_agg(
           m.ordinal::TEXT || ':' || m.source_version_id::TEXT || ':' ||
           m.normalized_record_id::TEXT || ':' || coalesce(m.text_unit_id::TEXT,''),
           '|' ORDER BY m.ordinal), ''), 'sha256')
    INTO v_count, v_digest
    FROM analysis.graphrag_eligibility_manifest_member m
   WHERE m.manifest_id = p_manifest_id;

  UPDATE analysis.graphrag_eligibility_manifest
     SET status = 'sealed', membership_digest = v_digest,
         member_count = v_count, sealed_at = v_now
   WHERE id = p_manifest_id;

  RETURN QUERY SELECT p_manifest_id, v_digest, v_count, v_now;
END $$;

CREATE OR REPLACE FUNCTION analysis.record_graphrag_comparison_join(
  p_run_id UUID, p_stage_id TEXT, p_stage_version TEXT, p_manifest_id UUID,
  p_manifest_digest BYTEA, p_semantica_receipt_id UUID, p_sat_temporal_receipt_id UUID)
RETURNS UUID
LANGUAGE plpgsql AS $$
DECLARE v_id UUID;
BEGIN
  INSERT INTO analysis.graphrag_comparison_join (
    run_id, stage_id, stage_version, manifest_id, manifest_digest,
    semantica_receipt_id, sat_temporal_receipt_id)
  VALUES (p_run_id, p_stage_id, p_stage_version, p_manifest_id, p_manifest_digest,
          p_semantica_receipt_id, p_sat_temporal_receipt_id)
  ON CONFLICT (run_id, stage_id, stage_version, manifest_id, manifest_digest) DO UPDATE
    SET semantica_receipt_id    = COALESCE(EXCLUDED.semantica_receipt_id,    analysis.graphrag_comparison_join.semantica_receipt_id),
        sat_temporal_receipt_id = COALESCE(EXCLUDED.sat_temporal_receipt_id, analysis.graphrag_comparison_join.sat_temporal_receipt_id)
  RETURNING id INTO v_id;
  RETURN v_id;
END $$;

-- ===========================================================================
-- PART 2 (continued) · Lane discriminator on the shared candidate tables
-- ===========================================================================
-- Without these, a Semantica reading and a SAT reading of the same chunk land
-- in the same rows and become indistinguishable. Nullable: existing pipelines
-- that are not lane-aware keep working and write NULL.

ALTER TABLE working.candidate_entity   ADD COLUMN IF NOT EXISTS graph_lane analysis.graph_lane;
ALTER TABLE working.candidate_fact     ADD COLUMN IF NOT EXISTS graph_lane analysis.graph_lane;
ALTER TABLE working.candidate_event    ADD COLUMN IF NOT EXISTS graph_lane analysis.graph_lane;
ALTER TABLE working.extraction_run     ADD COLUMN IF NOT EXISTS graph_lane analysis.graph_lane;
ALTER TABLE working.claim_candidate    ADD COLUMN IF NOT EXISTS graph_lane analysis.graph_lane;
ALTER TABLE working.claim_temporal_edge ADD COLUMN IF NOT EXISTS graph_lane analysis.graph_lane;

CREATE INDEX IF NOT EXISTS candidate_entity_graph_lane_idx ON working.candidate_entity (graph_lane);
CREATE INDEX IF NOT EXISTS candidate_fact_graph_lane_idx   ON working.candidate_fact (graph_lane);
CREATE INDEX IF NOT EXISTS candidate_event_graph_lane_idx  ON working.candidate_event (graph_lane);
CREATE INDEX IF NOT EXISTS extraction_run_graph_lane_idx   ON working.extraction_run (graph_lane);

-- ===========================================================================
-- PART 3 · Graph node/edge registry with PG source coordinates
-- ===========================================================================
-- The load-bearing item. Every node and edge in either graph is anchored to
-- the PG row it came from, so the two graphs can be diffed at a shared source
-- coordinate WITHOUT first deciding whether Semantica's "A" and SAT's "A-prime"
-- are the same entity. Identity resolution becomes an OUTPUT of the diff
-- rather than a prerequisite for it — which is why the alias table can be
-- deferred safely.

CREATE TABLE IF NOT EXISTS analysis.graph_node_projection (
  id                   UUID PRIMARY KEY DEFAULT uuidv7(),
  graph_lane           analysis.graph_lane NOT NULL,
  graph_database       TEXT NOT NULL,          -- 'evidence' | 'sat-temporal' (Neo4j spelling, dash)
  graph_node_id        TEXT NOT NULL,          -- Neo4j element id
  node_labels          TEXT[] NOT NULL DEFAULT '{}',

  -- PG source coordinate. Unrecoverable if not written at projection time.
  source_version_id    UUID,
  normalized_record_id UUID,
  content_chunk_id     UUID,
  chat_message_id      UUID,
  span_start           INTEGER,
  span_end             INTEGER,
  source_provenance_ref JSONB,

  -- Version stamping (design doc §2, all seven fields).
  extractor_name       TEXT NOT NULL,
  extractor_version    TEXT NOT NULL,
  model_id             TEXT,
  prompt_version       TEXT,
  run_id               UUID,
  source_generation    BIGINT,                 -- the staleness guard
  projected_at         TIMESTAMPTZ NOT NULL DEFAULT now(),

  created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (graph_lane, graph_database, graph_node_id)
);
CREATE INDEX IF NOT EXISTS graph_node_projection_source_version_idx
  ON analysis.graph_node_projection (source_version_id);
CREATE INDEX IF NOT EXISTS graph_node_projection_chunk_idx
  ON analysis.graph_node_projection (content_chunk_id);
CREATE INDEX IF NOT EXISTS graph_node_projection_generation_idx
  ON analysis.graph_node_projection (source_generation);
COMMENT ON COLUMN analysis.graph_node_projection.source_generation IS
  'The projection generation this node was computed against. A disagreement between two lanes at the SAME generation is genuine divergence worth adjudicating; across DIFFERENT generations it is staleness and requires a re-run, not a decision. Telling them apart after the fact is impossible, which is why this is written at projection time.';

CREATE TABLE IF NOT EXISTS analysis.graph_edge_projection (
  id                UUID PRIMARY KEY DEFAULT uuidv7(),
  graph_lane        analysis.graph_lane NOT NULL,
  graph_database    TEXT NOT NULL,
  graph_edge_id     TEXT NOT NULL,
  edge_type         TEXT NOT NULL,
  from_node_id      TEXT NOT NULL,
  to_node_id        TEXT NOT NULL,

  source_version_id    UUID,
  normalized_record_id UUID,
  content_chunk_id     UUID,
  span_start           INTEGER,
  span_end             INTEGER,
  source_provenance_ref JSONB,

  extractor_name    TEXT NOT NULL,
  extractor_version TEXT NOT NULL,
  model_id          TEXT,
  prompt_version    TEXT,
  run_id            UUID,
  source_generation BIGINT,
  projected_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (graph_lane, graph_database, graph_edge_id)
);
CREATE INDEX IF NOT EXISTS graph_edge_projection_source_version_idx
  ON analysis.graph_edge_projection (source_version_id);
CREATE INDEX IF NOT EXISTS graph_edge_projection_generation_idx
  ON analysis.graph_edge_projection (source_generation);

-- Complete the version stamping on the tables that already had part of it.
ALTER TABLE working.claim_candidate ADD COLUMN IF NOT EXISTS prompt_version    TEXT;
ALTER TABLE working.claim_candidate ADD COLUMN IF NOT EXISTS source_generation BIGINT;
ALTER TABLE working.claim_candidate ADD COLUMN IF NOT EXISTS projected_at      TIMESTAMPTZ;
ALTER TABLE working.extraction_run  ADD COLUMN IF NOT EXISTS prompt_version    TEXT;
ALTER TABLE working.extraction_run  ADD COLUMN IF NOT EXISTS source_generation BIGINT;

-- ===========================================================================
-- PART 4 · Repair the projection sink vocabulary
-- ===========================================================================
-- working.chat_chunk_projection.sink was CHECK (sink IN ('weaviate','graphiti')).
-- 'graphiti' is retired (D-095) and neither graph lane can be expressed, so a
-- graph projection cannot be recorded at all today.

ALTER TABLE working.chat_chunk_projection DROP CONSTRAINT IF EXISTS chat_chunk_projection_sink_check;
ALTER TABLE working.chat_chunk_projection ADD  CONSTRAINT chat_chunk_projection_sink_check
  CHECK (sink IN ('weaviate', 'graphiti', 'semantica', 'sat_temporal', 'surrealdb', 'opensearch'));
COMMENT ON CONSTRAINT chat_chunk_projection_sink_check ON working.chat_chunk_projection IS
  '''graphiti'' retained only so historical rows remain valid; it is retired per D-095 and must not be written.';

-- ===========================================================================
-- PART 5 · A REAL migration ledger
-- ===========================================================================
-- public.schema_version is NOT a migration ledger and never was. Its status
-- vocabulary is ('active','superseded','deprecated') and its columns are
-- applies_to / ddl_uri / supersedes: it is a DOMAIN table describing versions
-- of data contracts. It merely looks like a ledger.
--
-- That resemblance has now cost real time twice. On 2026-08-29 a `CREATE
-- DATABASE platform TEMPLATE ai` inherited schema_version from the source
-- database, the rows looked like migration state, and the actual applied-
-- migration state was unrecoverable — roughly seven hours went into
-- reconstructing it by hand. Nothing prevented a repeat, so:

CREATE TABLE IF NOT EXISTS ops.migration_ledger (
  migration_id   TEXT PRIMARY KEY,        -- '0001' .. '0055', or 'baseline'
  filename       TEXT NOT NULL,
  ddl_sha256     BYTEA NOT NULL CHECK (octet_length(ddl_sha256) = 32),
  applied_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  applied_by     TEXT NOT NULL,
  statements_ok  INTEGER,
  guards_skipped INTEGER,
  notes          TEXT
);
COMMENT ON TABLE ops.migration_ledger IS
  'THE migration ledger. public.schema_version is NOT one — it is a data-contract version table whose status vocabulary is active/superseded/deprecated. Do not confuse them; that confusion has already destroyed migration state once (2026-08-29).';
COMMENT ON COLUMN ops.migration_ledger.ddl_sha256 IS
  'SHA-256 of the migration file as applied. A mismatch against the file on disk means the file changed after it was applied.';
COMMENT ON COLUMN ops.migration_ledger.guards_skipped IS
  'Count of immutability/append-only guard statements deliberately NOT applied. Non-zero across this rebuild by owner ruling: guards belong to promoted evidence only, behind a dev flag, and nothing has been promoted.';
