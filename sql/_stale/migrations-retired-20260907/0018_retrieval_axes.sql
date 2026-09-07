-- 0018_retrieval_axes.sql — the metadata axes every retrievable unit must carry.
--
-- Byline: Claude Code . Fable 5 . 2026-08-02
--
-- SPEC: docs/HANDOFF-2026-08-02-semantica-platform-review.md, "Independent
-- metadata axes". Codex listed nine; five already existed on the spine
-- (occurred_at + ts_precision, disclosure_tier, source/custody ids,
-- extraction/review status). This migration adds the four that did not, plus
-- the shared horizon predicate, and puts them on the spine AND the 0016
-- candidate family — the rows that actually get retrieved and promoted.
--
--   case_id          tenant/case boundary. Text, not uuid: it is a routing
--                    key, appears in every predicate, and must stay readable
--                    in a court-facing export. Default 'primary' so existing
--                    single-case rows are valid without inventing an id.
--   domain           legal / behavioral / platform_design / evidence /
--                    context. TEXT + CHECK, never an enum: vocabularies
--                    evolve and ALTER TYPE rewrites everything (0016 rule).
--   topic_tags       zero or more, GIN-indexed. Tags are a FACET, never a
--                    reason to create another table or collection.
--   knowledge_actor  WHOSE knowledge `knowledge_time` represents. Without it
--                    the horizon is ambiguous the moment a second party's
--                    discovery timeline matters — "when was it knowable" has
--                    no meaning until you say knowable BY WHOM.
--   ontology_version the reference/ontology revision in force when the row
--                    was derived, so an old extraction stays reproducible
--                    after the taxonomy moves.
--
-- CANON (AGENTS.md WHY THIS EXISTS): these axes are METADATA on one store.
-- Do NOT encode them by multiplying databases or collections. A pass is a
-- retrieval filter bound to an agent.
--
-- Idempotent. Percent-free. Never edit after apply — add 0019.

BEGIN;

-- ---------------------------------------------------------------------------
-- The axes, applied uniformly.
-- ---------------------------------------------------------------------------
DO $axes$
DECLARE
    t text;
BEGIN
    FOREACH t IN ARRAY ARRAY[
        'normalized_record', 'candidate_entity', 'candidate_fact', 'candidate_event'
    ] LOOP
        EXECUTE 'ALTER TABLE working.' || quote_ident(t) ||
                ' ADD COLUMN IF NOT EXISTS case_id text NOT NULL DEFAULT ''primary''';
        EXECUTE 'ALTER TABLE working.' || quote_ident(t) ||
                ' ADD COLUMN IF NOT EXISTS domain text NOT NULL DEFAULT ''evidence''';
        EXECUTE 'ALTER TABLE working.' || quote_ident(t) ||
                ' ADD COLUMN IF NOT EXISTS topic_tags text[] NOT NULL DEFAULT ''{}''';
        EXECUTE 'ALTER TABLE working.' || quote_ident(t) ||
                ' ADD COLUMN IF NOT EXISTS knowledge_actor text NOT NULL DEFAULT ''owner''';
        EXECUTE 'ALTER TABLE working.' || quote_ident(t) ||
                ' ADD COLUMN IF NOT EXISTS ontology_version text';
        -- candidate_* rows carry no knowledge_time of their own (they inherit
        -- the source record's); the spine already has it, so this is a no-op
        -- there. Must precede the horizon index below.
        EXECUTE 'ALTER TABLE working.' || quote_ident(t) ||
                ' ADD COLUMN IF NOT EXISTS knowledge_time timestamptz';

        EXECUTE 'ALTER TABLE working.' || quote_ident(t) ||
                ' DROP CONSTRAINT IF EXISTS ' || quote_ident(t || '_domain_ck');
        EXECUTE 'ALTER TABLE working.' || quote_ident(t) ||
                ' ADD CONSTRAINT ' || quote_ident(t || '_domain_ck') ||
                ' CHECK (domain IN (''evidence'', ''legal'', ''behavioral'',' ||
                ' ''platform_design'', ''context''))';

        EXECUTE 'ALTER TABLE working.' || quote_ident(t) ||
                ' DROP CONSTRAINT IF EXISTS ' || quote_ident(t || '_case_id_ck');
        EXECUTE 'ALTER TABLE working.' || quote_ident(t) ||
                ' ADD CONSTRAINT ' || quote_ident(t || '_case_id_ck') ||
                ' CHECK (length(case_id) > 0)';

        -- The horizon access path: every filtered read starts (case, knowable-when).
        EXECUTE 'CREATE INDEX IF NOT EXISTS ' || quote_ident(t || '_horizon_idx') ||
                ' ON working.' || quote_ident(t) || ' (case_id, knowledge_time)';
        EXECUTE 'CREATE INDEX IF NOT EXISTS ' || quote_ident(t || '_domain_idx') ||
                ' ON working.' || quote_ident(t) || ' (case_id, domain)';
        EXECUTE 'CREATE INDEX IF NOT EXISTS ' || quote_ident(t || '_topics_gin') ||
                ' ON working.' || quote_ident(t) || ' USING GIN (topic_tags)';
    END LOOP;
END
$axes$;

-- ---------------------------------------------------------------------------
-- THE SHARED HORIZON PREDICATE — one definition, every Postgres reader.
-- ---------------------------------------------------------------------------
-- Codex C-01 + canon: the horizon must be a PRE-filter, and Postgres, Weaviate
-- and Neo4j must share one policy. This is the Postgres half; the application
-- compiles the same rule into Weaviate DICT filters (FilterExpr silently
-- no-ops on Weaviate — AGENTS.md landmine) and Neo4j predicates.
--
--   hindsight agent : sees everything in its case
--   ignorant agent  : sees only what was knowable to ITS actor at or before
--                     its horizon, and never a row tagged hindsight
--
-- IMMUTABLE + STRICT-free so the planner can inline it into an index scan.
CREATE OR REPLACE FUNCTION working.horizon_visible(
    row_case_id       text,
    row_knowledge_time timestamptz,
    row_disclosure    text,
    row_actor         text,
    p_case_id         text,
    p_horizon         timestamptz,   -- NULL => hindsight (no cutoff)
    p_actor           text DEFAULT 'owner'
) RETURNS boolean
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS
$fn$
    SELECT row_case_id = p_case_id
       AND (
            p_horizon IS NULL                       -- hindsight: no cutoff
            OR (row_knowledge_time IS NOT NULL
                AND row_knowledge_time <= p_horizon
                AND row_actor = p_actor
                AND row_disclosure <> 'hindsight')  -- never leaks backwards
       );
$fn$;

COMMENT ON FUNCTION working.horizon_visible IS
  'THE horizon pre-filter for Postgres readers. p_horizon NULL = hindsight '
  'agent (whole case); otherwise the ignorant agent sees only rows knowable '
  'to p_actor at or before p_horizon, excluding hindsight-tagged rows. Every '
  'Postgres query that feeds an agent MUST apply this — filtering after '
  'top-k silently shrinks k and leaks future facts.';

-- Convenience view for the common spine read. Parameters come from
-- set_config so a session can pin its horizon once.
CREATE OR REPLACE VIEW working.vw_spine_horizon AS
SELECT r.*
  FROM working.normalized_record r
 WHERE working.horizon_visible(
           r.case_id, r.knowledge_time, r.disclosure_tier, r.knowledge_actor,
           current_setting('app.case_id', true),
           nullif(current_setting('app.horizon', true), '')::timestamptz,
           coalesce(nullif(current_setting('app.actor', true), ''), 'owner'));

COMMENT ON VIEW working.vw_spine_horizon IS
  'Spine filtered by the session horizon: SET app.case_id / app.horizon / '
  'app.actor first. app.horizon unset or empty = hindsight.';

COMMIT;
