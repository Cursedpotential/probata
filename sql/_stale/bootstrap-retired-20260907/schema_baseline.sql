-- sql/bootstrap/schema_baseline.sql — REPRODUCIBLE BOOTSTRAP (Codex C-02).
-- Captured 2026-08-10 01:13 from the live database by scripts/capture_bootstrap_ddl.py.
-- Apply to an EMPTY database to reproduce the full live schema. The numbered
-- sql/NNNN chain remains the historical record; regenerate this file after
-- applying any new numbered migration. Structure only — never data.

--
-- PostgreSQL database dump
--

\restrict AN3heiIngjiXbRkuyiNRBKjHgTp2eDWijtBhXcYsjwTwEcne1dwY187Y39S0N2e

-- Dumped from database version 18.1 (Debian 18.1-1.pgdg12+2)
-- Dumped by pg_dump version 18.4

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: ai; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA ai;


--
-- Name: analysis; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA analysis;


--
-- Name: SCHEMA analysis; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA analysis IS 'Conclusions only: findings, assertions, scores, review decisions, ground-truth labels and the litigation work product built on them. Derived data lives in working; taxonomy lives in reference; run ledgers live in ops.';


--
-- Name: pg_duckdb; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pg_duckdb WITH SCHEMA public;


--
-- Name: EXTENSION pg_duckdb; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pg_duckdb IS 'DuckDB Embedded in Postgres';


--
-- Name: evidence; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA evidence;


--
-- Name: ops; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA ops;


--
-- Name: SCHEMA ops; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA ops IS 'Operational plumbing - run ledgers, stage records, tool-call logs. Safe to prune under a retention policy, which is exactly why it must not sit beside evidence or findings.';


--
-- Name: reference; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA reference;


--
-- Name: SCHEMA reference; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA reference IS 'Hand-curated taxonomy and configuration. Not derived from evidence and not a conclusion about the case. Re-seeded from source lexicons, never re-derived.';


--
-- Name: working; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA working;


--
-- Name: SCHEMA working; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA working IS 'Derived working set (0014: spine, projections, links, resolved entities — rebuilt by re-deriving from evidence.raw_* without touching originals) plus the extraction gate (0016: machine-extracted CANDIDATES awaiting human review). Never court-facing; if it disagrees with evidence, evidence wins. Promotion of candidates requires an approved review_decision.';


--
-- Name: btree_gin; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS btree_gin WITH SCHEMA public;


--
-- Name: EXTENSION btree_gin; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION btree_gin IS 'support for indexing common datatypes in GIN';


--
-- Name: btree_gist; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS btree_gist WITH SCHEMA public;


--
-- Name: EXTENSION btree_gist; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION btree_gist IS 'support for indexing common datatypes in GiST';


--
-- Name: citext; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS citext WITH SCHEMA ai;


--
-- Name: EXTENSION citext; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION citext IS 'data type for case-insensitive character strings';


--
-- Name: fuzzystrmatch; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS fuzzystrmatch WITH SCHEMA ai;


--
-- Name: EXTENSION fuzzystrmatch; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION fuzzystrmatch IS 'determine similarities and distance between strings';


--
-- Name: hstore; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS hstore WITH SCHEMA ai;


--
-- Name: EXTENSION hstore; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION hstore IS 'data type for storing sets of (key, value) pairs';


--
-- Name: ltree; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS ltree WITH SCHEMA ai;


--
-- Name: EXTENSION ltree; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION ltree IS 'data type for hierarchical tree-like structures';


--
-- Name: pg_stat_statements; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pg_stat_statements WITH SCHEMA public;


--
-- Name: EXTENSION pg_stat_statements; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pg_stat_statements IS 'track planning and execution statistics of all SQL statements executed';


--
-- Name: pg_trgm; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA public;


--
-- Name: EXTENSION pg_trgm; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pg_trgm IS 'text similarity measurement and index searching based on trigrams';


--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: postgis; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA public;


--
-- Name: EXTENSION postgis; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION postgis IS 'PostGIS geometry and geography spatial types and functions';


--
-- Name: unaccent; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS unaccent WITH SCHEMA public;


--
-- Name: EXTENSION unaccent; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION unaccent IS 'text search dictionary that removes accents';


--
-- Name: vector; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS vector WITH SCHEMA public;


--
-- Name: EXTENSION vector; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION vector IS 'vector data type and ivfflat and hnsw access methods';


--
-- Name: anchor_kind; Type: TYPE; Schema: ai; Owner: -
--

CREATE TYPE ai.anchor_kind AS ENUM (
    'docketed_event',
    'recurring_holiday',
    'life_event',
    'derived'
);


--
-- Name: assertion_source; Type: TYPE; Schema: ai; Owner: -
--

CREATE TYPE ai.assertion_source AS ENUM (
    'gps',
    'claimed_text',
    'exif',
    'ip_geo',
    'cell_tower',
    'wifi',
    'witness',
    'geocode',
    'manual'
);


--
-- Name: assertion_type; Type: TYPE; Schema: ai; Owner: -
--

CREATE TYPE ai.assertion_type AS ENUM (
    'raw_evidence',
    'extracted_fact',
    'inferred_fact',
    'analytical_finding',
    'legal_conclusion'
);


--
-- Name: canonical_id; Type: DOMAIN; Schema: ai; Owner: -
--

CREATE DOMAIN ai.canonical_id AS uuid;


--
-- Name: category_polarity; Type: TYPE; Schema: ai; Owner: -
--

CREATE TYPE ai.category_polarity AS ENUM (
    'negative',
    'positive',
    'neutral',
    'linguistic_marker'
);


--
-- Name: conduct_party; Type: TYPE; Schema: ai; Owner: -
--

CREATE TYPE ai.conduct_party AS ENUM (
    'user',
    'partner',
    'child',
    'mutual',
    'third_party',
    'institution',
    'unknown'
);


--
-- Name: confidence; Type: DOMAIN; Schema: ai; Owner: -
--

CREATE DOMAIN ai.confidence AS numeric(4,3)
	CONSTRAINT confidence_check CHECK (((VALUE IS NULL) OR ((VALUE >= (0)::numeric) AND (VALUE <= (1)::numeric))));


--
-- Name: cycle_phase; Type: TYPE; Schema: ai; Owner: -
--

CREATE TYPE ai.cycle_phase AS ENUM (
    'calm',
    'tension_building',
    'conflict',
    'repair',
    'reconciliation',
    'love_bombing',
    'withdrawal',
    'escalation',
    'de_escalation',
    'unknown'
);


--
-- Name: detection_method; Type: TYPE; Schema: ai; Owner: -
--

CREATE TYPE ai.detection_method AS ENUM (
    'literal',
    'regex',
    'priority_screener',
    'semantic_similarity',
    'model',
    'human',
    'imported'
);


--
-- Name: disclosure_horizon; Type: TYPE; Schema: ai; Owner: -
--

CREATE TYPE ai.disclosure_horizon AS ENUM (
    'contemporaneous',
    'hindsight',
    'discovered'
);


--
-- Name: entity_type; Type: TYPE; Schema: ai; Owner: -
--

CREATE TYPE ai.entity_type AS ENUM (
    'person',
    'org',
    'project',
    'tech',
    'location',
    'concept',
    'phone',
    'email',
    'handle',
    'device',
    'account',
    'vehicle',
    'address',
    'court',
    'attorney',
    'school',
    'doctor',
    'institution',
    'platform',
    'ai_system'
);


--
-- Name: event_type; Type: TYPE; Schema: ai; Owner: -
--

CREATE TYPE ai.event_type AS ENUM (
    'milestone',
    'decision',
    'meeting',
    'incident',
    'change',
    'memory',
    'upcoming',
    'presence',
    'communication',
    'observation'
);


--
-- Name: evidence_tier; Type: TYPE; Schema: ai; Owner: -
--

CREATE TYPE ai.evidence_tier AS ENUM (
    'raw',
    'extracted',
    'inferred',
    'analytical',
    'legal_conclusion'
);


--
-- Name: geo_point; Type: DOMAIN; Schema: ai; Owner: -
--

CREATE DOMAIN ai.geo_point AS public.geography(Point,4326);


--
-- Name: geocode_provider; Type: TYPE; Schema: ai; Owner: -
--

CREATE TYPE ai.geocode_provider AS ENUM (
    'google',
    'radar',
    'nominatim',
    'osm',
    'manual'
);


--
-- Name: match_method; Type: TYPE; Schema: ai; Owner: -
--

CREATE TYPE ai.match_method AS ENUM (
    'exact',
    'resolved',
    'manual'
);


--
-- Name: mcl_factor; Type: TYPE; Schema: ai; Owner: -
--

CREATE TYPE ai.mcl_factor AS ENUM (
    'a',
    'b',
    'c',
    'd',
    'e',
    'f',
    'g',
    'h',
    'i',
    'j',
    'k',
    'l'
);


--
-- Name: pattern_match_type; Type: TYPE; Schema: ai; Owner: -
--

CREATE TYPE ai.pattern_match_type AS ENUM (
    'literal',
    'regex'
);


--
-- Name: precision_class; Type: TYPE; Schema: ai; Owner: -
--

CREATE TYPE ai.precision_class AS ENUM (
    'exact',
    'approximate',
    'inferred',
    'uncertain'
);


--
-- Name: review_state; Type: TYPE; Schema: ai; Owner: -
--

CREATE TYPE ai.review_state AS ENUM (
    'unreviewed',
    'in_review',
    'approved',
    'rejected',
    'needs_more_evidence'
);


--
-- Name: sensitivity_tier; Type: TYPE; Schema: ai; Owner: -
--

CREATE TYPE ai.sensitivity_tier AS ENUM (
    'public',
    'restricted',
    'sealed'
);


--
-- Name: source_system; Type: TYPE; Schema: ai; Owner: -
--

CREATE TYPE ai.source_system AS ENUM (
    'postgres',
    'neo4j',
    'milvus',
    'surrealdb'
);


--
-- Name: source_ref; Type: TYPE; Schema: ai; Owner: -
--

CREATE TYPE ai.source_ref AS (
	system ai.source_system,
	native_id text,
	locator text
);


--
-- Name: strength_class; Type: TYPE; Schema: ai; Owner: -
--

CREATE TYPE ai.strength_class AS ENUM (
    'none',
    'weak',
    'moderate',
    'strong',
    'conclusive'
);


--
-- Name: temporal_class; Type: TYPE; Schema: ai; Owner: -
--

CREATE TYPE ai.temporal_class AS ENUM (
    'historical',
    'current',
    'future'
);


--
-- Name: temporal_relation; Type: TYPE; Schema: ai; Owner: -
--

CREATE TYPE ai.temporal_relation AS ENUM (
    'preceded',
    'meets',
    'overlaps',
    'during',
    'same_day',
    'equals',
    'caused_hypothesis'
);


--
-- Name: acquisition_authority; Type: TYPE; Schema: evidence; Owner: -
--

CREATE TYPE evidence.acquisition_authority AS ENUM (
    'device_owner',
    'parent_guardian',
    'account_holder',
    'consent_given',
    'court_order',
    'unclear'
);


--
-- Name: acquisition_method; Type: TYPE; Schema: evidence; Owner: -
--

CREATE TYPE evidence.acquisition_method AS ENUM (
    'own_device',
    'household_device',
    'voluntary_third_party',
    'legal_process',
    'public_source',
    'unknown'
);


--
-- Name: record_medium; Type: TYPE; Schema: evidence; Owner: -
--

CREATE TYPE evidence.record_medium AS ENUM (
    'export',
    'screenshot',
    'screen_capture',
    'forwarded',
    'transcript',
    'unknown'
);


--
-- Name: log_task_status(); Type: FUNCTION; Schema: analysis; Owner: -
--

CREATE FUNCTION analysis.log_task_status() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ BEGIN
    IF NEW.status IS DISTINCT FROM OLD.status THEN
      IF NEW.status = 'archived' AND COALESCE(NEW.archive_reason,'') = '' THEN
        RAISE EXCEPTION 'archived status requires archive_reason (no silent discard)';
      END IF;
      INSERT INTO analysis.task_event(task_id, from_status, to_status, actor, actor_kind, reason, ts)
      VALUES (NEW.id, OLD.status, NEW.status, COALESCE(current_setting('app.actor', true),'system'),
              COALESCE(current_setting('app.actor_kind', true),'system'), NEW.archive_reason, now());
    END IF; RETURN NEW; END $$;


--
-- Name: snapshot_task(); Type: FUNCTION; Schema: analysis; Owner: -
--

CREATE FUNCTION analysis.snapshot_task() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ BEGIN
    INSERT INTO analysis.task_revision(task_id, snapshot, changed_by, change_note, ts)
    VALUES (OLD.id, to_jsonb(OLD), COALESCE(current_setting('app.actor', true),'unknown'),
            'auto-snapshot before UPDATE', now());
    RETURN NEW; END $$;


--
-- Name: chain_custody_event(); Type: FUNCTION; Schema: evidence; Owner: -
--

CREATE FUNCTION evidence.chain_custody_event() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    PERFORM pg_advisory_xact_lock(hashtextextended(NEW.source_id::text, 0));
    SELECT ce.event_digest INTO NEW.prev_event_digest
      FROM evidence.custody_event ce
     WHERE ce.source_id = NEW.source_id ORDER BY ce.seq DESC LIMIT 1;
    NEW.event_digest := digest(convert_to(
        coalesce(NEW.source_id::text,'') || '|' || coalesce(NEW.file_node_id::text,'') || '|' ||
        coalesce(NEW.evidence_hash_id::text,'') || '|' || NEW.event_type || '|' || NEW.actor || '|' ||
        to_char(NEW.occurred_at,'YYYY-MM-DD"T"HH24:MI:SS.US TZH:TZM') || '|' ||
        coalesce(NEW.detail::text,'{}') || '|' || coalesce(encode(NEW.prev_event_digest,'hex'),''),
      'UTF8'), 'sha256');
    RETURN NEW;
END $$;


--
-- Name: forbid_mutation(); Type: FUNCTION; Schema: evidence; Owner: -
--

CREATE FUNCTION evidence.forbid_mutation() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  RAISE EXCEPTION 'evidence.% is immutable (originals/append-only): % blocked (never-delete -> _stale)',
    TG_TABLE_NAME, TG_OP;
END $$;


--
-- Name: raw_no_mutate(); Type: FUNCTION; Schema: evidence; Owner: -
--

CREATE FUNCTION evidence.raw_no_mutate() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  -- INERT UNTIL LIVE (owner, 2026-08-01: "append only only starts once we are
  -- actually live"). During build-out the schema and parsers churn, and a hard
  -- immutability rule would force a DB rebuild for every iteration. The trigger is
  -- installed now so going live is a one-line switch rather than a migration:
  --
  --   ALTER DATABASE <db> SET app.evidence_live = 'on';
  --
  -- Until then raw behaves like an ordinary table.
  IF current_setting('app.evidence_live', true) IS DISTINCT FROM 'on' THEN
    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
  END IF;

  -- One exception: marking a row superseded. That is the ONLY legal mutation, and it
  -- adds a forward pointer rather than changing anything the row asserts. Everything
  -- the row claimed about the source stays exactly as written.
  IF TG_OP = 'UPDATE'
     AND OLD.superseded_by IS NULL
     AND NEW.superseded_by IS NOT NULL
     AND NEW.raw            IS NOT DISTINCT FROM OLD.raw
     AND NEW.raw_text       IS NOT DISTINCT FROM OLD.raw_text
     AND NEW.content_hash   IS NOT DISTINCT FROM OLD.content_hash
     AND NEW.source_id      IS NOT DISTINCT FROM OLD.source_id
     AND NEW.device_id      IS NOT DISTINCT FROM OLD.device_id
     AND NEW.medium         IS NOT DISTINCT FROM OLD.medium
     AND NEW.record_index   IS NOT DISTINCT FROM OLD.record_index
  THEN
    RETURN NEW;
  END IF;

  RAISE EXCEPTION USING MESSAGE =
    'evidence.' || TG_TABLE_NAME ||
    ' is append-only: raw source records are never updated or deleted '
    '(the only permitted change is setting superseded_by on a live row)';
END;
$$;


--
-- Name: source_immutable_core(); Type: FUNCTION; Schema: evidence; Owner: -
--

CREATE FUNCTION evidence.source_immutable_core() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION 'evidence.source is write-once: DELETE blocked (never-delete -> _stale)';
    END IF;
    IF  NEW.sha256 IS DISTINCT FROM OLD.sha256
     OR NEW.md5_prefilter IS DISTINCT FROM OLD.md5_prefilter
     OR NEW.byte_size IS DISTINCT FROM OLD.byte_size
     OR NEW.mime_type IS DISTINCT FROM OLD.mime_type
     OR NEW.original_filename IS DISTINCT FROM OLD.original_filename
     OR NEW.source_type IS DISTINCT FROM OLD.source_type
     OR NEW.custodian IS DISTINCT FROM OLD.custodian
     OR NEW.acquisition_source IS DISTINCT FROM OLD.acquisition_source
     OR NEW.r2_bucket IS DISTINCT FROM OLD.r2_bucket
     OR NEW.r2_key IS DISTINCT FROM OLD.r2_key
     OR NEW.provenance_tier IS DISTINCT FROM OLD.provenance_tier
     OR NEW.hash_canon_version IS DISTINCT FROM OLD.hash_canon_version
     OR NEW.supersedes_source_id IS DISTINCT FROM OLD.supersedes_source_id
     OR NEW.original_metadata IS DISTINCT FROM OLD.original_metadata
     OR NEW.ingested_at IS DISTINCT FROM OLD.ingested_at THEN
        RAISE EXCEPTION 'evidence.source core/identity columns immutable (only lifecycle status may change)';
    END IF;
    RETURN NEW;
END $$;


--
-- Name: change_log_chain(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.change_log_chain() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE prev bytea;
BEGIN
  SELECT row_hash INTO prev FROM public.change_log ORDER BY seq DESC LIMIT 1;
  NEW.prev_change_hash := prev;
  NEW.row_hash := digest(
      coalesce(NEW.table_name,'') || '|' || coalesce(NEW.record_id::text,'') || '|' ||
      coalesce(NEW.field_name,'') || '|' || NEW.action || '|' ||
      coalesce(NEW.previous_value,'') || '|' || coalesce(NEW.new_value,'') || '|' ||
      NEW.actor || '|' || NEW.change_origin || '|' || coalesce(encode(prev,'hex'),''), 'sha256');
  RETURN NEW;
END $$;


--
-- Name: forbid_mutation(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.forbid_mutation() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  RAISE EXCEPTION 'public.% is append-only: % blocked', TG_TABLE_NAME, TG_OP;
END $$;


--
-- Name: derived_write_guard(); Type: FUNCTION; Schema: working; Owner: -
--

CREATE FUNCTION working.derived_write_guard() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF current_setting('app.enforce_derived_guard', true) IS DISTINCT FROM 'on' THEN
    RETURN NEW;                      -- guard not armed
  END IF;
  IF current_setting('app.deriving', true) = 'on' THEN
    RETURN NEW;                      -- the deriver is allowed
  END IF;
  RAISE EXCEPTION USING MESSAGE =
    'analysis.' || TG_TABLE_NAME
    || ' is a DERIVED table: write it only from the derivation pass '
    || '(SET LOCAL app.deriving = ''on''). Raw is the single insert target.';
END;
$$;


--
-- Name: entity_candidate_no_mutate(); Type: FUNCTION; Schema: working; Owner: -
--

CREATE FUNCTION working.entity_candidate_no_mutate() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF NEW.entity_text  IS DISTINCT FROM OLD.entity_text
     OR NEW.record_id IS DISTINCT FROM OLD.record_id
     OR NEW.extractor IS DISTINCT FROM OLD.extractor
     OR NEW.span_start IS DISTINCT FROM OLD.span_start
     OR NEW.span_end   IS DISTINCT FROM OLD.span_end THEN
    RAISE EXCEPTION
      'analysis.entity_candidate is append-only: insert a new row instead of editing the claim';
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: extraction_candidate_no_mutate(); Type: FUNCTION; Schema: working; Owner: -
--

CREATE FUNCTION working.extraction_candidate_no_mutate() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF NEW.entity_text  IS DISTINCT FROM OLD.entity_text
     OR NEW.record_id IS DISTINCT FROM OLD.record_id
     OR NEW.extractor IS DISTINCT FROM OLD.extractor
     OR NEW.candidate_kind IS DISTINCT FROM OLD.candidate_kind
     OR NEW.span_start IS DISTINCT FROM OLD.span_start
     OR NEW.span_end   IS DISTINCT FROM OLD.span_end THEN
    RAISE EXCEPTION USING MESSAGE =
      'analysis.extraction_candidate is append-only: insert a new row instead of '
      'editing the claim (review columns and consumed_by are the mutable surface)';
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: forbid_mutation(); Type: FUNCTION; Schema: working; Owner: -
--

CREATE FUNCTION working.forbid_mutation() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    RAISE EXCEPTION '% is append-only: % blocked (corrections are new rows)',
        TG_TABLE_NAME, TG_OP;
END
$$;


--
-- Name: horizon_visible(text, timestamp with time zone, text, text, text, timestamp with time zone, text); Type: FUNCTION; Schema: working; Owner: -
--

CREATE FUNCTION working.horizon_visible(row_case_id text, row_knowledge_time timestamp with time zone, row_disclosure text, row_actor text, p_case_id text, p_horizon timestamp with time zone, p_actor text DEFAULT 'owner'::text) RETURNS boolean
    LANGUAGE sql IMMUTABLE PARALLEL SAFE
    AS $$
    SELECT row_case_id = p_case_id
       AND (
            p_horizon IS NULL                       -- hindsight: no cutoff
            OR (row_knowledge_time IS NOT NULL
                AND row_knowledge_time <= p_horizon
                AND row_actor = p_actor
                AND row_disclosure <> 'hindsight')  -- never leaks backwards
       );
$$;


--
-- Name: FUNCTION horizon_visible(row_case_id text, row_knowledge_time timestamp with time zone, row_disclosure text, row_actor text, p_case_id text, p_horizon timestamp with time zone, p_actor text); Type: COMMENT; Schema: working; Owner: -
--

COMMENT ON FUNCTION working.horizon_visible(row_case_id text, row_knowledge_time timestamp with time zone, row_disclosure text, row_actor text, p_case_id text, p_horizon timestamp with time zone, p_actor text) IS 'THE horizon pre-filter for Postgres readers. p_horizon NULL = hindsight agent (whole case); otherwise the ignorant agent sees only rows knowable to p_actor at or before p_horizon, excluding hindsight-tagged rows. Every Postgres query that feeds an agent MUST apply this — filtering after top-k silently shrinks k and leaks future facts.';


--
-- Name: promotion_revoke_only(); Type: FUNCTION; Schema: working; Owner: -
--

CREATE FUNCTION working.promotion_revoke_only() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION 'working.promotion is append-only: DELETE blocked (revoke instead)';
    END IF;
    -- The ONLY legal update: first-time revocation. Everything else identical.
    IF OLD.revoked_at IS NOT NULL THEN
        RAISE EXCEPTION 'working.promotion: row already revoked; further updates blocked';
    END IF;
    IF NEW.revoked_at IS NULL THEN
        RAISE EXCEPTION 'working.promotion: UPDATE must set revoked_at (revocation is the only legal update)';
    END IF;
    IF to_jsonb(NEW) - 'revoked_at' - 'revoked_reason'
       IS DISTINCT FROM to_jsonb(OLD) - 'revoked_at' - 'revoked_reason' THEN
        RAISE EXCEPTION 'working.promotion: only revoked_at/revoked_reason may change on revocation';
    END IF;
    RETURN NEW;
END
$$;


--
-- Name: reject_mutation(); Type: FUNCTION; Schema: working; Owner: -
--

CREATE FUNCTION working.reject_mutation() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ BEGIN
    RAISE EXCEPTION 'append-only table %.% — % not allowed', TG_TABLE_SCHEMA, TG_TABLE_NAME, TG_OP; END $$;


--
-- Name: simple_s3_secret; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_1; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_1 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_1; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_1 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_10; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_10 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_10; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_10 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_11; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_11 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_11; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_11 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_12; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_12 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_12; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_12 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_13; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_13 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_13; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_13 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_14; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_14 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_14; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_14 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_15; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_15 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_15; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_15 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_16; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_16 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_16; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_16 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_17; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_17 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_17; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_17 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_18; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_18 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_18; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_18 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_19; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_19 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_19; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_19 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_2; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_2 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_2; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_2 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_20; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_20 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_20; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_20 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_21; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_21 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_21; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_21 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_22; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_22 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_22; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_22 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_23; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_23 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_23; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_23 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_24; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_24 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_24; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_24 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_25; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_25 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_25; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_25 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_26; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_26 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_26; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_26 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_27; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_27 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_27; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_27 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_28; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_28 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_28; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_28 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_29; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_29 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_29; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_29 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_3; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_3 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_3; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_3 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_30; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_30 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_30; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_30 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_31; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_31 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_31; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_31 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_32; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_32 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_32; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_32 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_33; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_33 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_33; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_33 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_34; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_34 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_34; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_34 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_35; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_35 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_35; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_35 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_36; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_36 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_36; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_36 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_37; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_37 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_37; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_37 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_38; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_38 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_38; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_38 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_39; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_39 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_39; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_39 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_4; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_4 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_4; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_4 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_40; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_40 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_40; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_40 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_41; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_41 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_41; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_41 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_42; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_42 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_42; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_42 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_43; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_43 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_43; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_43 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_44; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_44 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_44; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_44 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_45; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_45 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_45; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_45 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_46; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_46 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_46; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_46 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_47; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_47 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_47; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_47 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_48; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_48 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_48; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_48 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_49; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_49 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_49; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_49 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_5; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_5 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_5; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_5 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_50; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_50 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_50; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_50 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_51; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_51 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_51; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_51 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_52; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_52 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_52; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_52 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_53; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_53 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_53; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_53 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_54; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_54 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_54; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_54 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_55; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_55 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_55; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_55 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_56; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_56 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_56; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_56 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_57; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_57 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_57; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_57 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_58; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_58 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_58; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_58 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_59; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_59 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_59; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_59 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_6; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_6 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_6; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_6 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_60; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_60 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_60; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_60 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_61; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_61 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_61; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_61 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_62; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_62 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_62; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_62 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_63; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_63 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_63; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_63 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_64; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_64 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_64; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_64 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_65; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_65 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_65; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_65 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_66; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_66 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_66; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_66 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_67; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_67 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_67; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_67 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_68; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_68 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_68; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_68 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_69; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_69 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_69; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_69 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_7; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_7 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_7; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_7 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_70; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_70 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_70; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_70 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_71; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_71 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_71; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_71 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_72; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_72 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_72; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_72 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_73; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_73 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_73; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_73 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_74; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_74 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_74; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_74 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_75; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_75 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_75; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_75 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_76; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_76 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_76; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_76 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_77; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_77 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_77; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_77 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_78; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_78 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_78; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_78 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_79; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_79 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_79; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_79 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_8; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_8 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_8; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_8 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_80; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_80 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_80; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_80 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_81; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_81 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_81; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_81 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_82; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_82 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_82; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_82 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_83; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_83 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_83; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_83 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_84; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_84 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_84; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_84 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_85; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_85 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_85; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_85 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_86; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_86 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_86; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_86 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_87; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_87 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_87; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_87 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_88; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_88 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_88; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_88 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_89; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_89 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_89; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_89 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_9; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_9 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_9; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_9 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_90; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_90 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_90; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_90 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_91; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_91 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_91; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_91 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


--
-- Name: simple_s3_secret_92; Type: SERVER; Schema: -; Owner: -
--

CREATE SERVER simple_s3_secret_92 TYPE 'S3' FOREIGN DATA WRAPPER duckdb OPTIONS (
    endpoint '1a7406c497493a52128bb282f499e7b8.r2.cloudflarestorage.com',
    region 'auto'
);


--
-- Name: USER MAPPING ai SERVER simple_s3_secret_92; Type: USER MAPPING; Schema: -; Owner: -
--

CREATE USER MAPPING FOR ai SERVER simple_s3_secret_92 OPTIONS (
    key_id '9e9eb4a1f55d967f83c42dc041e37313',
    secret 'f64180b5668fedd0db791c2d2688154a5613b66c2ff1ac12fe7b27a6896e0878'
);


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: agno_approvals; Type: TABLE; Schema: ai; Owner: -
--

CREATE TABLE ai.agno_approvals (
    id character varying NOT NULL,
    run_id character varying NOT NULL,
    session_id character varying NOT NULL,
    status character varying NOT NULL,
    source_type character varying NOT NULL,
    approval_type character varying,
    pause_type character varying NOT NULL,
    tool_name character varying,
    tool_args jsonb,
    expires_at bigint,
    agent_id character varying,
    team_id character varying,
    workflow_id character varying,
    user_id character varying,
    schedule_id character varying,
    schedule_run_id character varying,
    source_name character varying,
    requirements jsonb,
    context jsonb,
    resolution_data jsonb,
    resolved_by character varying,
    resolved_at bigint,
    created_at bigint NOT NULL,
    updated_at bigint,
    run_status character varying
);


--
-- Name: agno_component_configs; Type: TABLE; Schema: ai; Owner: -
--

CREATE TABLE ai.agno_component_configs (
    component_id character varying NOT NULL,
    version integer NOT NULL,
    label character varying,
    stage character varying NOT NULL,
    config jsonb NOT NULL,
    notes text,
    created_at bigint NOT NULL,
    updated_at bigint,
    deleted_at bigint
);


--
-- Name: agno_component_links; Type: TABLE; Schema: ai; Owner: -
--

CREATE TABLE ai.agno_component_links (
    parent_component_id character varying NOT NULL,
    parent_version integer NOT NULL,
    link_kind character varying NOT NULL,
    link_key character varying NOT NULL,
    child_component_id character varying NOT NULL,
    child_version integer,
    "position" integer NOT NULL,
    meta jsonb,
    created_at bigint,
    updated_at bigint
);


--
-- Name: agno_components; Type: TABLE; Schema: ai; Owner: -
--

CREATE TABLE ai.agno_components (
    component_id character varying NOT NULL,
    component_type character varying NOT NULL,
    name character varying,
    description text,
    current_version integer,
    metadata jsonb,
    created_at bigint NOT NULL,
    updated_at bigint,
    deleted_at bigint
);


--
-- Name: agno_eval_runs; Type: TABLE; Schema: ai; Owner: -
--

CREATE TABLE ai.agno_eval_runs (
    run_id character varying NOT NULL,
    eval_type character varying NOT NULL,
    eval_data jsonb NOT NULL,
    eval_input jsonb NOT NULL,
    name character varying,
    agent_id character varying,
    team_id character varying,
    workflow_id character varying,
    model_id character varying,
    model_provider character varying,
    evaluated_component_name character varying,
    created_at bigint NOT NULL,
    updated_at bigint
);


--
-- Name: agno_knowledge; Type: TABLE; Schema: ai; Owner: -
--

CREATE TABLE ai.agno_knowledge (
    id character varying NOT NULL,
    name character varying NOT NULL,
    description text NOT NULL,
    metadata jsonb,
    type character varying,
    size bigint,
    linked_to character varying,
    access_count bigint,
    status character varying,
    status_message text,
    created_at bigint,
    updated_at bigint,
    external_id character varying
);


--
-- Name: agno_learnings; Type: TABLE; Schema: ai; Owner: -
--

CREATE TABLE ai.agno_learnings (
    learning_id character varying NOT NULL,
    learning_type character varying NOT NULL,
    namespace character varying,
    user_id character varying,
    agent_id character varying,
    team_id character varying,
    workflow_id character varying,
    session_id character varying,
    entity_id character varying,
    entity_type character varying,
    content jsonb NOT NULL,
    metadata jsonb,
    created_at bigint NOT NULL,
    updated_at bigint
);


--
-- Name: agno_memories; Type: TABLE; Schema: ai; Owner: -
--

CREATE TABLE ai.agno_memories (
    memory_id character varying NOT NULL,
    memory jsonb NOT NULL,
    feedback text,
    input text,
    agent_id character varying,
    team_id character varying,
    user_id character varying,
    topics jsonb,
    created_at bigint NOT NULL,
    updated_at bigint
);


--
-- Name: agno_metrics; Type: TABLE; Schema: ai; Owner: -
--

CREATE TABLE ai.agno_metrics (
    id character varying NOT NULL,
    agent_runs_count bigint NOT NULL,
    team_runs_count bigint NOT NULL,
    workflow_runs_count bigint NOT NULL,
    agent_sessions_count bigint NOT NULL,
    team_sessions_count bigint NOT NULL,
    workflow_sessions_count bigint NOT NULL,
    users_count bigint NOT NULL,
    token_metrics jsonb NOT NULL,
    model_metrics jsonb NOT NULL,
    date date NOT NULL,
    aggregation_period character varying NOT NULL,
    created_at bigint NOT NULL,
    updated_at bigint,
    completed boolean NOT NULL
);


--
-- Name: agno_schedule_runs; Type: TABLE; Schema: ai; Owner: -
--

CREATE TABLE ai.agno_schedule_runs (
    id character varying NOT NULL,
    schedule_id character varying NOT NULL,
    attempt bigint NOT NULL,
    triggered_at bigint,
    completed_at bigint,
    status character varying NOT NULL,
    status_code bigint,
    run_id character varying,
    session_id character varying,
    error text,
    input jsonb,
    output jsonb,
    requirements jsonb,
    created_at bigint NOT NULL
);


--
-- Name: agno_schedules; Type: TABLE; Schema: ai; Owner: -
--

CREATE TABLE ai.agno_schedules (
    id character varying NOT NULL,
    name character varying NOT NULL,
    description text,
    method character varying NOT NULL,
    endpoint character varying NOT NULL,
    payload jsonb,
    cron_expr character varying NOT NULL,
    timezone character varying NOT NULL,
    timeout_seconds bigint NOT NULL,
    max_retries bigint NOT NULL,
    retry_delay_seconds bigint NOT NULL,
    enabled boolean NOT NULL,
    next_run_at bigint,
    locked_by character varying,
    locked_at bigint,
    created_at bigint NOT NULL,
    updated_at bigint
);


--
-- Name: agno_schema_versions; Type: TABLE; Schema: ai; Owner: -
--

CREATE TABLE ai.agno_schema_versions (
    table_name character varying NOT NULL,
    version character varying NOT NULL,
    created_at character varying NOT NULL,
    updated_at character varying
);


--
-- Name: agno_service_accounts; Type: TABLE; Schema: ai; Owner: -
--

CREATE TABLE ai.agno_service_accounts (
    id character varying NOT NULL,
    name character varying NOT NULL,
    user_id character varying,
    token_hash character varying NOT NULL,
    token_prefix character varying NOT NULL,
    scopes jsonb NOT NULL,
    created_at bigint NOT NULL,
    expires_at bigint,
    last_used_at bigint,
    revoked_at bigint,
    created_by character varying
);


--
-- Name: agno_sessions; Type: TABLE; Schema: ai; Owner: -
--

CREATE TABLE ai.agno_sessions (
    session_id character varying NOT NULL,
    session_type character varying NOT NULL,
    agent_id character varying,
    team_id character varying,
    workflow_id character varying,
    user_id character varying,
    session_data jsonb,
    agent_data jsonb,
    team_data jsonb,
    workflow_data jsonb,
    metadata jsonb,
    runs jsonb,
    summary jsonb,
    created_at bigint NOT NULL,
    updated_at bigint
);


--
-- Name: agno_spans; Type: TABLE; Schema: ai; Owner: -
--

CREATE TABLE ai.agno_spans (
    span_id character varying NOT NULL,
    trace_id character varying NOT NULL,
    parent_span_id character varying,
    name character varying NOT NULL,
    span_kind character varying NOT NULL,
    status_code character varying NOT NULL,
    status_message text,
    start_time character varying NOT NULL,
    end_time character varying NOT NULL,
    duration_ms bigint NOT NULL,
    attributes jsonb,
    created_at character varying NOT NULL
);


--
-- Name: agno_traces; Type: TABLE; Schema: ai; Owner: -
--

CREATE TABLE ai.agno_traces (
    trace_id character varying NOT NULL,
    name character varying NOT NULL,
    status character varying NOT NULL,
    start_time character varying NOT NULL,
    end_time character varying NOT NULL,
    duration_ms bigint NOT NULL,
    run_id character varying,
    session_id character varying,
    user_id character varying,
    agent_id character varying,
    team_id character varying,
    workflow_id character varying,
    created_at character varying NOT NULL
);


--
-- Name: api_keys; Type: TABLE; Schema: ai; Owner: -
--

CREATE TABLE ai.api_keys (
    id bigint NOT NULL,
    key text NOT NULL,
    name text,
    scopes text[] DEFAULT ARRAY['mcp'::text] NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    expires_at timestamp with time zone,
    revoked boolean DEFAULT false NOT NULL,
    last_used_at timestamp with time zone
);


--
-- Name: api_keys_id_seq; Type: SEQUENCE; Schema: ai; Owner: -
--

CREATE SEQUENCE ai.api_keys_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: api_keys_id_seq; Type: SEQUENCE OWNED BY; Schema: ai; Owner: -
--

ALTER SEQUENCE ai.api_keys_id_seq OWNED BY ai.api_keys.id;


--
-- Name: casebible_evidence_contents; Type: TABLE; Schema: ai; Owner: -
--

CREATE TABLE ai.casebible_evidence_contents (
    id character varying NOT NULL,
    name character varying NOT NULL,
    description text NOT NULL,
    metadata jsonb,
    type character varying,
    size bigint,
    linked_to character varying,
    access_count bigint,
    status character varying,
    status_message text,
    created_at bigint,
    updated_at bigint,
    external_id character varying
);


--
-- Name: casebible_evidence_test_contents; Type: TABLE; Schema: ai; Owner: -
--

CREATE TABLE ai.casebible_evidence_test_contents (
    id character varying NOT NULL,
    name character varying NOT NULL,
    description text NOT NULL,
    metadata jsonb,
    type character varying,
    size bigint,
    linked_to character varying,
    access_count bigint,
    status character varying,
    status_message text,
    created_at bigint,
    updated_at bigint,
    external_id character varying
);


--
-- Name: casebible_ingest_test2_contents; Type: TABLE; Schema: ai; Owner: -
--

CREATE TABLE ai.casebible_ingest_test2_contents (
    id character varying NOT NULL,
    name character varying NOT NULL,
    description text NOT NULL,
    metadata jsonb,
    type character varying,
    size bigint,
    linked_to character varying,
    access_count bigint,
    status character varying,
    status_message text,
    created_at bigint,
    updated_at bigint,
    external_id character varying
);


--
-- Name: casebible_ingest_test_contents; Type: TABLE; Schema: ai; Owner: -
--

CREATE TABLE ai.casebible_ingest_test_contents (
    id character varying NOT NULL,
    name character varying NOT NULL,
    description text NOT NULL,
    metadata jsonb,
    type character varying,
    size bigint,
    linked_to character varying,
    access_count bigint,
    status character varying,
    status_message text,
    created_at bigint,
    updated_at bigint,
    external_id character varying
);


--
-- Name: platform_context_contents; Type: TABLE; Schema: ai; Owner: -
--

CREATE TABLE ai.platform_context_contents (
    id character varying NOT NULL,
    name character varying NOT NULL,
    description text NOT NULL,
    metadata jsonb,
    type character varying,
    size bigint,
    linked_to character varying,
    access_count bigint,
    status character varying,
    status_message text,
    created_at bigint,
    updated_at bigint,
    external_id character varying
);


--
-- Name: platform_knowledge_contents; Type: TABLE; Schema: ai; Owner: -
--

CREATE TABLE ai.platform_knowledge_contents (
    id character varying NOT NULL,
    name character varying NOT NULL,
    description text NOT NULL,
    metadata jsonb,
    type character varying,
    size bigint,
    linked_to character varying,
    access_count bigint,
    status character varying,
    status_message text,
    created_at bigint,
    updated_at bigint,
    external_id character varying
);


--
-- Name: completion_evidence; Type: TABLE; Schema: analysis; Owner: -
--

CREATE TABLE analysis.completion_evidence (
    id uuid DEFAULT uuidv7() NOT NULL,
    task_id uuid NOT NULL,
    source_id uuid,
    evidence_item_id uuid,
    evidence_hash_id uuid,
    sha256 bytea,
    outcome text NOT NULL,
    outcome_note text,
    recorded_by text NOT NULL,
    recorded_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT completion_evidence_outcome_check CHECK ((outcome = ANY (ARRAY['satisfied'::text, 'unmet'::text, 'overcome'::text, 'partial'::text]))),
    CONSTRAINT completion_sha_len CHECK (((sha256 IS NULL) OR (octet_length(sha256) = 32)))
);


--
-- Name: corroboration_flag; Type: TABLE; Schema: analysis; Owner: -
--

CREATE TABLE analysis.corroboration_flag (
    flag_id uuid DEFAULT uuidv7() NOT NULL,
    target_kind text NOT NULL,
    target_id text NOT NULL,
    claim text NOT NULL,
    claim_date_start date,
    claim_date_end date,
    evidence_wanted text[],
    status text DEFAULT 'open'::text NOT NULL,
    linked_artifacts jsonb DEFAULT '[]'::jsonb NOT NULL,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT corroboration_flag_status_check CHECK ((status = ANY (ARRAY['open'::text, 'partial'::text, 'corroborated'::text, 'unobtainable'::text]))),
    CONSTRAINT corroboration_flag_target_kind_check CHECK ((target_kind = ANY (ARRAY['record'::text, 'knowledge'::text, 'run'::text])))
);


--
-- Name: discovery_request; Type: TABLE; Schema: analysis; Owner: -
--

CREATE TABLE analysis.discovery_request (
    id uuid DEFAULT uuidv7() NOT NULL,
    task_id uuid NOT NULL,
    instrument_type text NOT NULL,
    target_person_id uuid,
    target_custodian text,
    draft_text text NOT NULL,
    scope_note text,
    status text DEFAULT 'draft'::text NOT NULL,
    hitl_status text DEFAULT 'pending'::text NOT NULL,
    prompt_version text,
    created_by text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT discovery_request_hitl_status_check CHECK ((hitl_status = ANY (ARRAY['pending'::text, 'approved'::text, 'declined'::text]))),
    CONSTRAINT discovery_request_instrument_type_check CHECK ((instrument_type = ANY (ARRAY['subpoena'::text, 'subpoena_duces_tecum'::text, 'rfa'::text, 'rfp'::text, 'rog'::text, 'witness_question'::text, 'deposition_topic'::text, 'self_collection'::text, 'records_request'::text, 'preservation_letter'::text]))),
    CONSTRAINT discovery_request_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'approved'::text, 'served'::text, 'responded'::text, 'withdrawn'::text])))
);


--
-- Name: discovery_request_revision; Type: TABLE; Schema: analysis; Owner: -
--

CREATE TABLE analysis.discovery_request_revision (
    revision_id uuid DEFAULT uuidv7() NOT NULL,
    request_id uuid NOT NULL,
    snapshot jsonb NOT NULL,
    changed_by text NOT NULL,
    ts timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: evidence_item; Type: TABLE; Schema: analysis; Owner: -
--

CREATE TABLE analysis.evidence_item (
    id uuid DEFAULT uuidv7() NOT NULL,
    case_id uuid NOT NULL,
    source_id uuid,
    file_node_id uuid,
    normalized_record_id uuid,
    evidence_hash_id uuid,
    exhibit_number text,
    title text NOT NULL,
    description text,
    quote text,
    context text,
    evidence_type text DEFAULT 'communication'::text NOT NULL,
    evidence_date timestamp with time zone,
    evidence_date_end timestamp with time zone,
    date_precision ai.precision_class DEFAULT 'exact'::ai.precision_class NOT NULL,
    assertion_type ai.assertion_type DEFAULT 'extracted_fact'::ai.assertion_type NOT NULL,
    confidence ai.confidence,
    confidence_tier text DEFAULT 'low'::text NOT NULL,
    relevance_score ai.confidence,
    is_hypothesis boolean DEFAULT false NOT NULL,
    is_exhibit boolean DEFAULT false NOT NULL,
    is_authenticated boolean DEFAULT false NOT NULL,
    authentication_method text,
    chain_of_custody text,
    sensitivity_tier ai.sensitivity_tier DEFAULT 'restricted'::ai.sensitivity_tier NOT NULL,
    privacy_sensitivity text DEFAULT 'none'::text NOT NULL,
    redaction_status text DEFAULT 'none'::text NOT NULL,
    review_status ai.review_state DEFAULT 'unreviewed'::ai.review_state NOT NULL,
    reviewed_by text,
    reviewed_at timestamp with time zone,
    hitl_required boolean DEFAULT true NOT NULL,
    safe_for_legal_use boolean DEFAULT false NOT NULL,
    supersedes_item_id uuid,
    source_run_id uuid,
    prompt_version text,
    ontology_version text,
    schema_version text,
    created_by text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    CONSTRAINT evidence_item_authentication_method_check CHECK (((authentication_method IS NULL) OR (authentication_method = ANY (ARRAY['witness_with_knowledge'::text, 'distinctive_characteristics'::text, 'process_or_system'::text, 'public_record'::text, 'hash_chain_of_custody'::text, 'self_authenticating'::text, 'stipulation'::text])))),
    CONSTRAINT evidence_item_conf_tier_ck CHECK (((confidence_tier <> 'high'::text) OR (confidence IS NULL) OR ((confidence)::numeric >= 0.60))),
    CONSTRAINT evidence_item_confidence_tier_check CHECK ((confidence_tier = ANY (ARRAY['high'::text, 'medium'::text, 'low'::text]))),
    CONSTRAINT evidence_item_evidence_type_check CHECK ((evidence_type = ANY (ARRAY['communication'::text, 'document'::text, 'photo'::text, 'record'::text, 'media'::text, 'screenshot'::text, 'transcript'::text, 'metadata'::text, 'other'::text]))),
    CONSTRAINT evidence_item_privacy_sensitivity_check CHECK ((privacy_sensitivity = ANY (ARRAY['none'::text, 'pii'::text, 'minor'::text, 'sensitive_pii'::text]))),
    CONSTRAINT evidence_item_redaction_status_check CHECK ((redaction_status = ANY (ARRAY['none'::text, 'required'::text, 'applied'::text]))),
    CONSTRAINT evidence_item_safe_ck CHECK (((safe_for_legal_use = false) OR ((review_status = 'approved'::ai.review_state) AND (is_authenticated = true) AND (is_hypothesis = false) AND (redaction_status <> 'required'::text))))
);


--
-- Name: evidence_task; Type: TABLE; Schema: analysis; Owner: -
--

CREATE TABLE analysis.evidence_task (
    id uuid DEFAULT uuidv7() NOT NULL,
    task_key text NOT NULL,
    case_id uuid NOT NULL,
    finding_id uuid,
    trigger_kind text DEFAULT 'manual'::text NOT NULL,
    evidence_needed text NOT NULL,
    evidence_need_kind text DEFAULT 'corroboration'::text NOT NULL,
    likely_source_id uuid,
    likely_source_note text,
    priority text DEFAULT 'P3_low'::text NOT NULL,
    priority_score numeric,
    priority_inputs jsonb,
    priority_override text,
    priority_override_reason text,
    risk text DEFAULT 'none'::text NOT NULL,
    risk_kind text[] DEFAULT '{}'::text[] NOT NULL,
    risk_note text,
    due_date date,
    due_basis text,
    status text DEFAULT 'draft'::text NOT NULL,
    human_action text,
    human_action_kind text DEFAULT 'none_yet'::text NOT NULL,
    assertion_type ai.assertion_type DEFAULT 'analytical_finding'::ai.assertion_type NOT NULL,
    confidence ai.confidence,
    confidence_tier text DEFAULT 'low'::text NOT NULL,
    confidence_note text,
    is_hypothesis boolean DEFAULT false NOT NULL,
    label_sensitivity text DEFAULT 'routine'::text NOT NULL,
    hitl_required boolean DEFAULT false NOT NULL,
    hitl_status text DEFAULT 'pending'::text NOT NULL,
    source_run_id uuid,
    prompt_version text,
    ontology_version text,
    schema_version text,
    review_status ai.review_state DEFAULT 'unreviewed'::ai.review_state NOT NULL,
    created_by text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    archive_reason text,
    CONSTRAINT evidence_task_confidence_tier_check CHECK ((confidence_tier = ANY (ARRAY['high'::text, 'medium'::text, 'low'::text]))),
    CONSTRAINT evidence_task_evidence_need_kind_check CHECK ((evidence_need_kind = ANY (ARRAY['corroboration'::text, 'original_source'::text, 'authentication'::text, 'metadata'::text, 'completeness'::text, 'chain_of_custody'::text, 'rebuttal'::text, 'foundation'::text, 'impeachment'::text]))),
    CONSTRAINT evidence_task_hitl_status_check CHECK ((hitl_status = ANY (ARRAY['pending'::text, 'approved'::text, 'declined'::text]))),
    CONSTRAINT evidence_task_human_action_kind_check CHECK ((human_action_kind = ANY (ARRAY['review_label'::text, 'approve_instrument'::text, 'serve_subpoena'::text, 'collect_self'::text, 'request_from_counsel'::text, 'interview_witness'::text, 'authenticate'::text, 'redact'::text, 'decide_relevance'::text, 'file_motion'::text, 'none_yet'::text]))),
    CONSTRAINT evidence_task_label_sensitivity_check CHECK ((label_sensitivity = ANY (ARRAY['routine'::text, 'sensitive'::text, 'high'::text]))),
    CONSTRAINT evidence_task_priority_check CHECK ((priority = ANY (ARRAY['P0_critical'::text, 'P1_high'::text, 'P2_medium'::text, 'P3_low'::text, 'P4_backlog'::text]))),
    CONSTRAINT evidence_task_priority_override_check CHECK (((priority_override IS NULL) OR (priority_override = ANY (ARRAY['P0_critical'::text, 'P1_high'::text, 'P2_medium'::text, 'P3_low'::text, 'P4_backlog'::text])))),
    CONSTRAINT evidence_task_risk_check CHECK ((risk = ANY (ARRAY['none'::text, 'low'::text, 'medium'::text, 'high'::text]))),
    CONSTRAINT evidence_task_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'proposed'::text, 'needs_human_review'::text, 'approved'::text, 'in_progress'::text, 'awaiting_response'::text, 'blocked'::text, 'obtained'::text, 'verified'::text, 'closed_satisfied'::text, 'closed_unmet'::text, 'closed_overcome'::text, 'superseded'::text, 'archived'::text]))),
    CONSTRAINT evidence_task_trigger_kind_check CHECK ((trigger_kind = ANY (ARRAY['contradiction'::text, 'anomaly'::text, 'gap'::text, 'behavioral_pattern'::text, 'custody_factor_concern'::text, 'safety_concern'::text, 'communication_barrier'::text, 'established_custodial_environment'::text, 'selective_framing'::text, 'timeline_hole'::text, 'attribution_uncertainty'::text, 'manual'::text])))
);


--
-- Name: export; Type: TABLE; Schema: analysis; Owner: -
--

CREATE TABLE analysis.export (
    export_id uuid DEFAULT uuidv7() NOT NULL,
    export_run uuid,
    package_uri text NOT NULL,
    manifest_sha256 bytea NOT NULL,
    signature bytea,
    included_artifacts uuid[] NOT NULL,
    tier ai.sensitivity_tier NOT NULL,
    purpose text,
    requested_by text NOT NULL,
    approved_by text NOT NULL,
    blocked_by_open_questions uuid[] DEFAULT '{}'::uuid[] NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: export_item; Type: TABLE; Schema: analysis; Owner: -
--

CREATE TABLE analysis.export_item (
    package_id uuid NOT NULL,
    evidence_item_id uuid NOT NULL,
    ordinal integer,
    included_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: export_package; Type: TABLE; Schema: analysis; Owner: -
--

CREATE TABLE analysis.export_package (
    id uuid DEFAULT uuidv7() NOT NULL,
    case_id uuid NOT NULL,
    package_name text NOT NULL,
    purpose text,
    status text DEFAULT 'draft'::text NOT NULL,
    approved_by text,
    approved_at timestamp with time zone,
    exported_at timestamp with time zone,
    manifest jsonb DEFAULT '{}'::jsonb NOT NULL,
    signature bytea,
    created_by text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT export_package_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'approved'::text, 'exported'::text, 'withdrawn'::text])))
);


--
-- Name: factor_citation; Type: TABLE; Schema: analysis; Owner: -
--

CREATE TABLE analysis.factor_citation (
    id uuid DEFAULT uuidv7() NOT NULL,
    evidence_item_id uuid NOT NULL,
    factor ai.mcl_factor NOT NULL,
    legal_issue_id uuid,
    supports_factor boolean NOT NULL,
    strength text DEFAULT 'moderate'::text NOT NULL,
    supporting_text text,
    relevance_explanation text,
    assertion_type ai.assertion_type DEFAULT 'analytical_finding'::ai.assertion_type NOT NULL,
    confidence ai.confidence,
    is_hypothesis boolean DEFAULT false NOT NULL,
    review_status ai.review_state DEFAULT 'unreviewed'::ai.review_state NOT NULL,
    safe_for_legal_use boolean DEFAULT false NOT NULL,
    supersedes_citation_id uuid,
    created_by text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT factcite_legal_gate CHECK (((safe_for_legal_use = false) OR ((review_status = 'approved'::ai.review_state) AND (is_hypothesis = false)))),
    CONSTRAINT factor_citation_strength_check CHECK ((strength = ANY (ARRAY['weak'::text, 'moderate'::text, 'strong'::text, 'decisive'::text])))
);


--
-- Name: finding; Type: TABLE; Schema: analysis; Owner: -
--

CREATE TABLE analysis.finding (
    id uuid DEFAULT uuidv7() NOT NULL,
    case_id uuid,
    finding_type text NOT NULL,
    title text NOT NULL,
    statement text,
    subject_refs uuid[] DEFAULT '{}'::uuid[] NOT NULL,
    conduct_party ai.conduct_party,
    mcl_factors ai.mcl_factor[] DEFAULT '{}'::ai.mcl_factor[] NOT NULL,
    assertion_type ai.assertion_type DEFAULT 'analytical_finding'::ai.assertion_type NOT NULL,
    data_tier ai.evidence_tier DEFAULT 'analytical'::ai.evidence_tier NOT NULL,
    confidence ai.confidence,
    evidence_strength ai.strength_class,
    is_hypothesis boolean DEFAULT true NOT NULL,
    requires_human_review boolean DEFAULT true NOT NULL,
    review_status ai.review_state DEFAULT 'unreviewed'::ai.review_state NOT NULL,
    safe_for_legal_use boolean DEFAULT false NOT NULL,
    bias_caution boolean DEFAULT true NOT NULL,
    authored_perspective text,
    provenance_id uuid,
    created_by text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    pattern_type text,
    span_message_ids uuid[],
    span_message_count integer,
    span_start timestamp with time zone,
    span_end timestamp with time zone,
    severity_progression text,
    escalation_index numeric,
    contradicts_finding_id uuid,
    CONSTRAINT finding_legal_gate CHECK (((safe_for_legal_use = false) OR ((review_status = 'approved'::ai.review_state) AND (is_hypothesis = false)))),
    CONSTRAINT finding_pattern_type_check CHECK (((pattern_type IS NULL) OR (pattern_type = ANY (ARRAY['escalation'::text, 'cycle'::text, 'triggered_response'::text, 'time_based'::text, 'single'::text])))),
    CONSTRAINT finding_severity_progression_check CHECK (((severity_progression IS NULL) OR (severity_progression = ANY (ARRAY['escalating'::text, 'stable'::text, 'de_escalating'::text]))))
);


--
-- Name: COLUMN finding.escalation_index; Type: COMMENT; Schema: analysis; Owner: -
--

COMMENT ON COLUMN analysis.finding.escalation_index IS 'app.py metric: (mean severity 2nd-half − 1st-half)/1st-half ×100 over time-sorted span.';


--
-- Name: COLUMN finding.contradicts_finding_id; Type: COMMENT; Schema: analysis; Owner: -
--

COMMENT ON COLUMN analysis.finding.contradicts_finding_id IS 'Self-reference: this finding contradicts another (0003 patternMatches.contradictsWith).';


--
-- Name: finding_version; Type: TABLE; Schema: analysis; Owner: -
--

CREATE TABLE analysis.finding_version (
    version_id uuid DEFAULT uuidv7() NOT NULL,
    finding_id uuid NOT NULL,
    snapshot jsonb NOT NULL,
    changed_by text NOT NULL,
    change_note text,
    ts timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: human_label; Type: TABLE; Schema: analysis; Owner: -
--

CREATE TABLE analysis.human_label (
    message_id uuid,
    conversation_key text NOT NULL,
    seq bigint NOT NULL,
    occurred_at timestamp with time zone,
    who text,
    message_text text NOT NULL,
    ai_flagged text,
    ai_flag_count integer DEFAULT 0 NOT NULL,
    labels text[] DEFAULT '{}'::text[] NOT NULL,
    is_clean boolean,
    severity integer,
    notes text,
    labeled_by text,
    labeled_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    relink_status text DEFAULT 'unlinked'::text NOT NULL,
    CONSTRAINT human_label_relink_status_check CHECK ((relink_status = ANY (ARRAY['unlinked'::text, 'linked'::text, 'ambiguous'::text]))),
    CONSTRAINT human_label_severity_check CHECK (((severity IS NULL) OR ((severity >= 0) AND (severity <= 10))))
);


--
-- Name: TABLE human_label; Type: COMMENT; Schema: analysis; Owner: -
--

COMMENT ON TABLE analysis.human_label IS 'Manual classification workspace (NocoDB front-end). labels[] = owner multi-label ground truth. is_clean=true means reviewed-and-nothing (NOT the same as labels={} untagged). Feeds refinement + training.';


--
-- Name: human_label_gold; Type: TABLE; Schema: analysis; Owner: -
--

CREATE TABLE analysis.human_label_gold (
    legacy_message_id uuid,
    conversation_key text NOT NULL,
    seq bigint NOT NULL,
    occurred_at timestamp with time zone,
    who text,
    message_text text,
    ai_flagged text,
    ai_flag_count integer,
    labels text[],
    is_clean boolean,
    severity integer,
    notes text,
    labeled_by text,
    labeled_at timestamp with time zone,
    created_at timestamp with time zone,
    relink_status text,
    archived_at timestamp with time zone DEFAULT now()
);


--
-- Name: TABLE human_label_gold; Type: COMMENT; Schema: analysis; Owner: -
--

COMMENT ON TABLE analysis.human_label_gold IS 'Dependency-free archive of the owner-authored ground-truth labels. NO foreign keys by design: on 2026-08-01 human_label.message_id was found to be BOTH the primary key AND an ON DELETE CASCADE FK to analysis.message, so a routine clear of the message tables would have deleted all 1918 rows outright. This table cannot be reached by any cascade. legacy_message_id is a plain UUID column, deliberately not a reference.';


--
-- Name: legal_timeline_event; Type: TABLE; Schema: analysis; Owner: -
--

CREATE TABLE analysis.legal_timeline_event (
    id uuid DEFAULT uuidv7() NOT NULL,
    case_id uuid NOT NULL,
    event_date timestamp with time zone NOT NULL,
    event_date_end timestamp with time zone,
    date_precision ai.precision_class DEFAULT 'exact'::ai.precision_class NOT NULL,
    title text NOT NULL,
    description text,
    event_type text DEFAULT 'communication'::text NOT NULL,
    evidence_item_ids uuid[] DEFAULT '{}'::uuid[] NOT NULL,
    normalized_record_ids uuid[] DEFAULT '{}'::uuid[] NOT NULL,
    mcl_factors ai.mcl_factor[] DEFAULT '{}'::ai.mcl_factor[] NOT NULL,
    participants text[] DEFAULT '{}'::text[] NOT NULL,
    assertion_type ai.assertion_type DEFAULT 'analytical_finding'::ai.assertion_type NOT NULL,
    confidence ai.confidence,
    is_verified boolean DEFAULT false NOT NULL,
    is_disputed boolean DEFAULT false NOT NULL,
    review_status ai.review_state DEFAULT 'unreviewed'::ai.review_state NOT NULL,
    safe_for_legal_use boolean DEFAULT false NOT NULL,
    created_by text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    CONSTRAINT legal_timeline_event_event_type_check CHECK ((event_type = ANY (ARRAY['communication'::text, 'incident'::text, 'filing'::text, 'hearing'::text, 'order'::text, 'exchange'::text, 'visit'::text, 'other'::text]))),
    CONSTRAINT legaltl_legal_gate CHECK (((safe_for_legal_use = false) OR (review_status = 'approved'::ai.review_state)))
);


--
-- Name: location_assertion; Type: TABLE; Schema: analysis; Owner: -
--

CREATE TABLE analysis.location_assertion (
    id uuid DEFAULT uuidv7() NOT NULL,
    subject_type text NOT NULL,
    subject_id uuid NOT NULL,
    location_id uuid,
    geog ai.geo_point,
    asserted_at_ts timestamp with time zone,
    ts_precision ai.precision_class DEFAULT 'inferred'::ai.precision_class NOT NULL,
    spatial_confidence ai.confidence,
    assertion_source ai.assertion_source NOT NULL,
    evidence_strength ai.strength_class,
    requires_human_review boolean DEFAULT false NOT NULL,
    review_status ai.review_state DEFAULT 'unreviewed'::ai.review_state NOT NULL,
    safe_for_legal_use boolean DEFAULT false NOT NULL,
    data_tier ai.evidence_tier DEFAULT 'inferred'::ai.evidence_tier NOT NULL,
    provenance_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT locassert_legal_gate CHECK (((safe_for_legal_use = false) OR (review_status = 'approved'::ai.review_state))),
    CONSTRAINT location_assertion_data_tier_check CHECK ((data_tier = ANY (ARRAY['inferred'::ai.evidence_tier, 'analytical'::ai.evidence_tier]))),
    CONSTRAINT location_assertion_subject_type_check CHECK ((subject_type = ANY (ARRAY['event'::text, 'message'::text, 'person'::text, 'device'::text, 'media'::text])))
);


--
-- Name: location_contradiction; Type: TABLE; Schema: analysis; Owner: -
--

CREATE TABLE analysis.location_contradiction (
    id uuid DEFAULT uuidv7() NOT NULL,
    claimed_assertion_id uuid NOT NULL,
    observed_assertion_id uuid NOT NULL,
    distance_m numeric(12,2),
    disagreement_flag boolean DEFAULT false NOT NULL,
    tie_break_reason text,
    analysis_confidence ai.confidence,
    requires_human_review boolean DEFAULT true NOT NULL,
    review_status ai.review_state DEFAULT 'unreviewed'::ai.review_state NOT NULL,
    safe_for_legal_use boolean DEFAULT false NOT NULL,
    data_tier ai.evidence_tier DEFAULT 'analytical'::ai.evidence_tier NOT NULL,
    provenance_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT chk_loc_contra_distinct CHECK ((claimed_assertion_id <> observed_assertion_id)),
    CONSTRAINT location_contradiction_data_tier_check CHECK ((data_tier = 'analytical'::ai.evidence_tier)),
    CONSTRAINT loccontra_legal_gate CHECK (((safe_for_legal_use = false) OR (review_status = 'approved'::ai.review_state)))
);


--
-- Name: pattern_finding; Type: TABLE; Schema: analysis; Owner: -
--

CREATE TABLE analysis.pattern_finding (
    id uuid DEFAULT uuidv7() NOT NULL,
    subject_type text NOT NULL,
    subject_id uuid NOT NULL,
    category_id ai.citext NOT NULL,
    pattern_id uuid,
    pattern_set_id uuid,
    subcategory text,
    detection_method ai.detection_method NOT NULL,
    rule_name text,
    matched_text text,
    matched_pattern text,
    start_char integer,
    end_char integer,
    context_before text,
    context_after text,
    author_party ai.conduct_party,
    author_entity_id uuid,
    bias_caution boolean DEFAULT true NOT NULL,
    authored_perspective text,
    confidence ai.confidence,
    severity smallint,
    score smallint,
    evidence_strength ai.strength_class,
    is_verified boolean DEFAULT false NOT NULL,
    verified_by text,
    verified_at timestamp with time zone,
    verification_notes text,
    requires_human_review boolean DEFAULT true NOT NULL,
    review_status ai.review_state DEFAULT 'unreviewed'::ai.review_state NOT NULL,
    safe_for_legal_use boolean DEFAULT false NOT NULL,
    finding_id uuid,
    data_tier ai.evidence_tier DEFAULT 'inferred'::ai.evidence_tier NOT NULL,
    provenance_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT pattern_finding_attribution_gate CHECK (((safe_for_legal_use = false) OR (author_party IS NOT NULL))),
    CONSTRAINT pattern_finding_legal_gate CHECK (((safe_for_legal_use = false) OR (review_status = 'approved'::ai.review_state))),
    CONSTRAINT pattern_finding_score_chk CHECK (((score IS NULL) OR ((score >= 1) AND (score <= 10)))),
    CONSTRAINT pattern_finding_sev_chk CHECK (((severity IS NULL) OR ((severity >= 0) AND (severity <= 10)))),
    CONSTRAINT pattern_finding_subj_chk CHECK ((subject_type = ANY (ARRAY['message'::text, 'ocr_text'::text, 'transcript'::text, 'event'::text]))),
    CONSTRAINT pattern_finding_tier_chk CHECK ((data_tier = ANY (ARRAY['inferred'::ai.evidence_tier, 'analytical'::ai.evidence_tier])))
);


--
-- Name: redaction; Type: TABLE; Schema: analysis; Owner: -
--

CREATE TABLE analysis.redaction (
    redaction_id uuid DEFAULT uuidv7() NOT NULL,
    redaction_run uuid,
    source_artifact uuid NOT NULL,
    redacted_artifact uuid NOT NULL,
    policy_version text NOT NULL,
    redaction_map jsonb NOT NULL,
    reversible boolean DEFAULT true NOT NULL,
    authorized_by text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: relational_classification; Type: TABLE; Schema: analysis; Owner: -
--

CREATE TABLE analysis.relational_classification (
    id uuid DEFAULT uuidv7() NOT NULL,
    subject_type text NOT NULL,
    subject_id uuid NOT NULL,
    event_category text,
    surface_sentiment text,
    emotional_tone text,
    relational_function text,
    cycle_phase ai.cycle_phase,
    cycle_transition_type text,
    love_bombing_indicator boolean,
    repair_attempt_indicator boolean,
    cooperation_indicator boolean,
    neutral_context_indicator boolean,
    precedes_concerning_event boolean,
    follows_concerning_event boolean,
    temporal_proximity_to_conflict_s bigint,
    changes_nearby_interpretation boolean,
    corroborated boolean,
    conduct_party ai.conduct_party,
    pattern_relevance text,
    mcl_factor_hint ai.mcl_factor,
    classified_by text,
    confidence ai.confidence,
    detector_provenance_id uuid,
    requires_human_review boolean DEFAULT true NOT NULL,
    review_status ai.review_state DEFAULT 'unreviewed'::ai.review_state NOT NULL,
    safe_for_legal_use boolean DEFAULT false NOT NULL,
    data_tier ai.evidence_tier DEFAULT 'analytical'::ai.evidence_tier NOT NULL,
    provenance_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT relational_classification_classified_by_check CHECK ((classified_by = ANY (ARRAY['rule'::text, 'model'::text, 'human'::text]))),
    CONSTRAINT relational_classification_subject_type_check CHECK ((subject_type = ANY (ARRAY['message'::text, 'event'::text, 'call'::text]))),
    CONSTRAINT relcls_legal_gate CHECK (((safe_for_legal_use = false) OR (review_status = 'approved'::ai.review_state)))
);


--
-- Name: resolution_evidence; Type: TABLE; Schema: analysis; Owner: -
--

CREATE TABLE analysis.resolution_evidence (
    id uuid DEFAULT uuidv7() NOT NULL,
    resolution_id uuid NOT NULL,
    polarity text NOT NULL,
    method text,
    evidence_ref_type text,
    evidence_ref_id uuid,
    weight ai.confidence,
    note text,
    provenance ai.source_ref[] DEFAULT '{}'::ai.source_ref[] NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT resolution_evidence_polarity_check CHECK ((polarity = ANY (ARRAY['supports'::text, 'contradicts'::text])))
);


--
-- Name: review_decision; Type: TABLE; Schema: analysis; Owner: -
--

CREATE TABLE analysis.review_decision (
    decision_id uuid DEFAULT uuidv7() NOT NULL,
    task_id uuid,
    target_kind text NOT NULL,
    target_id uuid NOT NULL,
    reviewer text NOT NULL,
    decision text NOT NULL,
    set_confidence ai.confidence,
    set_evidence_strength ai.strength_class,
    sensitive_label_decision jsonb,
    court_readiness text DEFAULT 'not_reviewed'::text NOT NULL,
    tier_approved ai.sensitivity_tier,
    requires_corroboration boolean DEFAULT false NOT NULL,
    score_snapshot uuid[] DEFAULT '{}'::uuid[] NOT NULL,
    prompt_version_id uuid,
    ontology_version_id uuid,
    schema_version_id uuid,
    rationale text NOT NULL,
    decided_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT review_decision_court_readiness_check CHECK ((court_readiness = ANY (ARRAY['not_reviewed'::text, 'draft'::text, 'needs_corroboration'::text, 'review_passed'::text, 'court_ready'::text, 'excluded'::text, 'strategically_sensitive'::text]))),
    CONSTRAINT review_decision_decision_check CHECK ((decision = ANY (ARRAY['approved'::text, 'rejected'::text, 'needs_changes'::text, 'needs_context'::text, 'escalated'::text, 'hold'::text])))
);


--
-- Name: review_task; Type: TABLE; Schema: analysis; Owner: -
--

CREATE TABLE analysis.review_task (
    task_id uuid DEFAULT uuidv7() NOT NULL,
    trigger_code text NOT NULL,
    target_kind text NOT NULL,
    target_id uuid NOT NULL,
    score_ids uuid[] DEFAULT '{}'::uuid[] NOT NULL,
    blocks text NOT NULL,
    reviewer_role text,
    state text DEFAULT 'pending'::text NOT NULL,
    created_by text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT review_task_state_check CHECK ((state = ANY (ARRAY['pending'::text, 'in_review'::text, 'resolved'::text])))
);


--
-- Name: score; Type: TABLE; Schema: analysis; Owner: -
--

CREATE TABLE analysis.score (
    score_id uuid DEFAULT uuidv7() NOT NULL,
    target_kind text NOT NULL,
    target_id uuid NOT NULL,
    score_type text NOT NULL,
    value ai.confidence NOT NULL,
    band text NOT NULL,
    method text NOT NULL,
    method_detail jsonb DEFAULT '{}'::jsonb NOT NULL,
    rationale text NOT NULL,
    evidence_refs uuid[] DEFAULT '{}'::uuid[] NOT NULL,
    assertion_type ai.assertion_type NOT NULL,
    config_version text,
    scoring_run_id uuid NOT NULL,
    recheck_after timestamp with time zone,
    stale boolean DEFAULT false NOT NULL,
    valid_from timestamp with time zone DEFAULT now() NOT NULL,
    valid_to timestamp with time zone,
    superseded_by uuid,
    created_by text NOT NULL,
    CONSTRAINT score_band_check CHECK ((band = ANY (ARRAY['very_low'::text, 'low'::text, 'medium'::text, 'high'::text, 'very_high'::text]))),
    CONSTRAINT score_method_check CHECK ((method = ANY (ARRAY['rule'::text, 'model'::text, 'human'::text, 'hybrid'::text]))),
    CONSTRAINT score_score_type_check CHECK ((score_type = ANY (ARRAY['extraction'::text, 'temporal'::text, 'identity'::text, 'location'::text, 'evidence_strength'::text, 'legal_relevance'::text, 'abuse_pattern'::text, 'corroboration'::text, 'contradiction'::text, 'court_readiness'::text])))
);


--
-- Name: task_dependency; Type: TABLE; Schema: analysis; Owner: -
--

CREATE TABLE analysis.task_dependency (
    task_id uuid NOT NULL,
    depends_on uuid NOT NULL,
    dep_kind text NOT NULL,
    CONSTRAINT task_dependency_check CHECK ((task_id <> depends_on)),
    CONSTRAINT task_dependency_dep_kind_check CHECK ((dep_kind = ANY (ARRAY['blocks'::text, 'prereq_of'::text, 'corroborates'::text, 'duplicate_of'::text])))
);


--
-- Name: task_event; Type: TABLE; Schema: analysis; Owner: -
--

CREATE TABLE analysis.task_event (
    event_id uuid DEFAULT uuidv7() NOT NULL,
    task_id uuid NOT NULL,
    from_status text,
    to_status text NOT NULL,
    actor text NOT NULL,
    actor_kind text NOT NULL,
    reason text,
    ts timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT task_event_actor_kind_check CHECK ((actor_kind = ANY (ARRAY['system'::text, 'agent'::text, 'human'::text])))
);


--
-- Name: task_legal_link; Type: TABLE; Schema: analysis; Owner: -
--

CREATE TABLE analysis.task_legal_link (
    task_id uuid NOT NULL,
    legal_issue_id uuid NOT NULL,
    factor ai.mcl_factor NOT NULL,
    element_note text
);


--
-- Name: task_person; Type: TABLE; Schema: analysis; Owner: -
--

CREATE TABLE analysis.task_person (
    task_id uuid NOT NULL,
    person_id uuid NOT NULL,
    role text NOT NULL,
    CONSTRAINT task_person_role_check CHECK ((role = ANY (ARRAY['subject'::text, 'custodian'::text, 'witness'::text, 'child'::text, 'third_party'::text, 'self'::text])))
);


--
-- Name: task_revision; Type: TABLE; Schema: analysis; Owner: -
--

CREATE TABLE analysis.task_revision (
    revision_id uuid DEFAULT uuidv7() NOT NULL,
    task_id uuid NOT NULL,
    snapshot jsonb NOT NULL,
    changed_by text NOT NULL,
    change_note text,
    ts timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: time_assertion; Type: TABLE; Schema: analysis; Owner: -
--

CREATE TABLE analysis.time_assertion (
    assertion_id uuid DEFAULT uuidv7() NOT NULL,
    event_id uuid NOT NULL,
    valid_earliest timestamp with time zone NOT NULL,
    valid_latest timestamp with time zone NOT NULL,
    valid_point timestamp with time zone,
    valid_range tstzrange GENERATED ALWAYS AS (tstzrange(valid_earliest, valid_latest, '[]'::text)) STORED,
    ts_raw text,
    ts_utc timestamp with time zone,
    tz_offset_minutes integer,
    tz_source text,
    certainty ai.precision_class NOT NULL,
    assertion_type ai.assertion_type DEFAULT 'extracted_fact'::ai.assertion_type NOT NULL,
    confidence ai.confidence,
    disclosure_horizon ai.disclosure_horizon DEFAULT 'contemporaneous'::ai.disclosure_horizon NOT NULL,
    is_conflicted boolean DEFAULT false NOT NULL,
    requires_human_review boolean DEFAULT false NOT NULL,
    discovered_at timestamp with time zone,
    discovery_source uuid,
    ingested_at timestamp with time zone DEFAULT now() NOT NULL,
    ingest_run_id uuid,
    sys_period tstzrange DEFAULT tstzrange(now(), NULL::timestamp with time zone) NOT NULL,
    superseded_by uuid,
    derived_from uuid[] DEFAULT '{}'::uuid[] NOT NULL,
    anchor_refs uuid[] DEFAULT '{}'::uuid[] NOT NULL,
    reasoning text,
    prompt_version text,
    ontology_version text,
    schema_version text,
    author text NOT NULL,
    CONSTRAINT time_assertion_tz_source_check CHECK (((tz_source IS NULL) OR (tz_source = ANY (ARRAY['exif_offset'::text, 'export_header'::text, 'assumed_local'::text, 'device_setting'::text, 'unknown'::text])))),
    CONSTRAINT valid_ordering CHECK ((valid_earliest <= valid_latest))
);


--
-- Name: timeline_event; Type: TABLE; Schema: analysis; Owner: -
--

CREATE TABLE analysis.timeline_event (
    event_id uuid DEFAULT uuidv7() NOT NULL,
    canonical_event_id ai.canonical_id,
    event_key ai.citext,
    serial_id bigint,
    title text NOT NULL,
    description text,
    event_type ai.event_type NOT NULL,
    temporal_class ai.temporal_class DEFAULT 'historical'::ai.temporal_class NOT NULL,
    valid_earliest timestamp with time zone,
    valid_latest timestamp with time zone,
    valid_point timestamp with time zone,
    valid_range tstzrange GENERATED ALWAYS AS (tstzrange(valid_earliest, valid_latest, '[]'::text)) STORED,
    current_certainty ai.precision_class,
    current_confidence ai.confidence,
    disclosure_horizon ai.disclosure_horizon DEFAULT 'contemporaneous'::ai.disclosure_horizon NOT NULL,
    assertion_type ai.assertion_type DEFAULT 'analytical_finding'::ai.assertion_type NOT NULL,
    location_id uuid,
    primary_geo ai.geo_point,
    is_conflicted boolean DEFAULT false NOT NULL,
    requires_human_review boolean DEFAULT false NOT NULL,
    safe_for_legal_use boolean DEFAULT false NOT NULL,
    reviewed_by text,
    reviewed_at timestamp with time zone,
    conduct_party ai.conduct_party,
    mcl_relevance ai.mcl_factor[] DEFAULT '{}'::ai.mcl_factor[] NOT NULL,
    source_artifact_id uuid,
    primary_record_id uuid,
    ingest_run_id uuid,
    derived_from uuid[] DEFAULT '{}'::uuid[] NOT NULL,
    prompt_version text,
    ontology_version text,
    schema_version text,
    attrs jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: vw_court_export; Type: VIEW; Schema: analysis; Owner: -
--

CREATE VIEW analysis.vw_court_export AS
 SELECT id,
    case_id,
    exhibit_number,
    title,
    description,
    quote,
    context,
    evidence_type,
    evidence_date,
    date_precision,
    assertion_type,
    confidence,
    confidence_tier,
    is_authenticated,
    authentication_method,
    chain_of_custody,
    sensitivity_tier,
    redaction_status,
    source_id,
    file_node_id,
    evidence_hash_id,
    reviewed_by,
    reviewed_at
   FROM analysis.evidence_item ei
  WHERE ((safe_for_legal_use = true) AND (review_status = 'approved'::ai.review_state) AND (confidence_tier = ANY (ARRAY['high'::text, 'medium'::text])) AND (is_hypothesis = false) AND (is_authenticated = true) AND (redaction_status <> 'required'::text) AND (sensitivity_tier <> 'sealed'::ai.sensitivity_tier));


--
-- Name: vw_human_label_long; Type: VIEW; Schema: analysis; Owner: -
--

CREATE VIEW analysis.vw_human_label_long AS
 SELECT h.message_id,
    h.conversation_key,
    h.seq,
    h.occurred_at,
    h.who,
    h.message_text,
    label.label,
    h.severity,
    h.labeled_by,
    h.labeled_at
   FROM (analysis.human_label h
     CROSS JOIN LATERAL unnest(
        CASE
            WHEN (cardinality(h.labels) > 0) THEN h.labels
            WHEN h.is_clean THEN ARRAY['__CLEAN__'::text]
            ELSE ARRAY[]::text[]
        END) label(label));


--
-- Name: VIEW vw_human_label_long; Type: COMMENT; Schema: analysis; Owner: -
--

COMMENT ON VIEW analysis.vw_human_label_long IS 'One row per (message,label). __CLEAN__ = explicitly-reviewed-nothing. Untagged messages absent. Join vs analysis.pattern_finding for precision/recall per category.';


--
-- Name: vw_labeling_progress; Type: VIEW; Schema: analysis; Owner: -
--

CREATE VIEW analysis.vw_labeling_progress AS
 SELECT count(*) AS total_messages,
    count(*) FILTER (WHERE ((cardinality(labels) > 0) OR is_clean)) AS labeled,
    count(*) FILTER (WHERE (cardinality(labels) > 0)) AS labeled_with_behavior,
    count(*) FILTER (WHERE is_clean) AS marked_clean,
    count(*) FILTER (WHERE ((cardinality(labels) = 0) AND (is_clean IS NOT TRUE))) AS remaining,
    round(((100.0 * (count(*) FILTER (WHERE ((cardinality(labels) > 0) OR is_clean)))::numeric) / (NULLIF(count(*), 0))::numeric), 1) AS pct_done
   FROM analysis.human_label;


--
-- Name: message; Type: TABLE; Schema: working; Owner: -
--

CREATE TABLE working.message (
    id uuid NOT NULL,
    conversation_id uuid NOT NULL,
    ts_utc timestamp with time zone,
    platform text NOT NULL,
    external_id text,
    serial_number bigint NOT NULL,
    prev_message_id uuid,
    next_message_id uuid,
    time_since_prev_s integer,
    sender_raw text,
    sender_e164 text,
    sender_entity_id uuid,
    recipient_raw text,
    recipient_e164 text,
    direction text,
    message_type text DEFAULT 'text'::text NOT NULL,
    delivery_status text,
    status_code integer,
    is_blocked boolean DEFAULT false NOT NULL,
    raw_ts text,
    tz text,
    ts_earliest timestamp with time zone,
    ts_latest timestamp with time zone,
    temporal_confidence ai.confidence,
    relative_time_refs jsonb DEFAULT '[]'::jsonb NOT NULL,
    word_count integer,
    char_count integer,
    content_sha256 bytea,
    language text,
    surface_sentiment_hint text,
    inferred_intent_hint text,
    topic_hint text,
    domain_type_hint text,
    relevance_hint text,
    custody_relevance_hint text,
    evidence_strength_hint ai.strength_class,
    extraction_confidence ai.confidence,
    is_private boolean DEFAULT false NOT NULL,
    is_redacted boolean DEFAULT false NOT NULL,
    has_attachments boolean DEFAULT false NOT NULL,
    attachment_count integer DEFAULT 0 NOT NULL,
    has_behaviors boolean DEFAULT false NOT NULL,
    behavior_count integer DEFAULT 0 NOT NULL,
    max_behavior_severity text,
    screenshot_attachment_id uuid,
    body_embedding_ref text,
    platform_attrs jsonb DEFAULT '{}'::jsonb NOT NULL,
    raw_data jsonb,
    is_read boolean,
    hint_provenance jsonb,
    derived_from_record_id uuid,
    derived_from_raw_table text,
    derived_from_raw_id uuid,
    deriver_version text,
    derived_at timestamp with time zone,
    CONSTRAINT message_content_sha256_check CHECK (((content_sha256 IS NULL) OR (octet_length(content_sha256) = 32))),
    CONSTRAINT message_direction_check CHECK ((direction = ANY (ARRAY['inbound'::text, 'outbound'::text, 'unknown'::text])))
);


--
-- Name: COLUMN message.is_read; Type: COMMENT; Schema: working; Owner: -
--

COMMENT ON COLUMN working.message.is_read IS 'SMS/MMS read flag (SBV read=1/0; iMessage is_read). NULL = unknown/not-applicable.';


--
-- Name: COLUMN message.hint_provenance; Type: COMMENT; Schema: working; Owner: -
--

COMMENT ON COLUMN working.message.hint_provenance IS 'Provenance for the *_hint columns: {field: {model, at, method, reasoning}}. A model-assigned hint that cannot say why/when/what-model is not court-usable; this records it. NULL until any hint is set by an analysis pass.';


--
-- Name: vw_message_behavior; Type: VIEW; Schema: analysis; Owner: -
--

CREATE VIEW analysis.vw_message_behavior AS
 SELECT m.id AS message_id,
    m.conversation_id,
    m.ts_utc,
    m.direction,
    m.has_behaviors,
    m.behavior_count,
    m.max_behavior_severity,
    count(pf.*) AS finding_count,
    count(pf.*) FILTER (WHERE (pf.review_status = 'approved'::ai.review_state)) AS confirmed_count,
    bool_or((pf.category_id OPERATOR(ai.=) 'threats'::ai.citext)) AS flag_threat_hypothesis,
    bool_or(((pf.category_id OPERATOR(ai.=) 'threats'::ai.citext) AND (pf.review_status = 'approved'::ai.review_state))) AS flag_threat_confirmed,
    bool_or((pf.category_id OPERATOR(ai.=) 'gaslighting'::ai.citext)) AS flag_gaslighting_hypothesis,
    bool_or((pf.category_id OPERATOR(ai.=) 'minimizing'::ai.citext)) AS flag_minimizing_hypothesis,
    bool_or((pf.category_id OPERATOR(ai.=) 'blame_shifting'::ai.citext)) AS flag_blame_hypothesis,
    array_agg(DISTINCT pf.category_id) FILTER (WHERE (pf.category_id IS NOT NULL)) AS categories
   FROM (working.message m
     LEFT JOIN analysis.pattern_finding pf ON (((pf.subject_id = m.id) AND (pf.subject_type = 'message'::text))))
  GROUP BY m.id, m.conversation_id, m.ts_utc, m.direction, m.has_behaviors, m.behavior_count, m.max_behavior_severity;


--
-- Name: VIEW vw_message_behavior; Type: COMMENT; Schema: analysis; Owner: -
--

COMMENT ON VIEW analysis.vw_message_behavior IS 'One-click behavior filters for UI. *_hypothesis = a finding exists (unreviewed OK); *_confirmed = human-approved only. Replaces the old containsThreat/Blame booleans WITHOUT bypassing the court-safety review gate.';


--
-- Name: vw_open_tasks; Type: VIEW; Schema: analysis; Owner: -
--

CREATE VIEW analysis.vw_open_tasks AS
 SELECT id,
    task_key,
    case_id,
    status,
    priority,
    priority_score,
    due_date,
    due_basis,
    human_action,
    human_action_kind,
    label_sensitivity,
    hitl_required,
    hitl_status,
    confidence_tier,
    is_hypothesis,
    ( SELECT count(*) AS count
           FROM analysis.task_dependency d
          WHERE ((d.depends_on = t.id) AND (d.dep_kind = ANY (ARRAY['blocks'::text, 'prereq_of'::text])))) AS blocks_n,
    ( SELECT e.to_status
           FROM analysis.task_event e
          WHERE (e.task_id = t.id)
          ORDER BY e.ts DESC
         LIMIT 1) AS last_event
   FROM analysis.evidence_task t
  WHERE (status <> ALL (ARRAY['closed_satisfied'::text, 'closed_unmet'::text, 'closed_overcome'::text, 'superseded'::text, 'archived'::text]))
  ORDER BY priority, priority_score DESC NULLS LAST, due_date;


--
-- Name: acquisition; Type: TABLE; Schema: evidence; Owner: -
--

CREATE TABLE evidence.acquisition (
    id uuid DEFAULT uuidv7() NOT NULL,
    method evidence.acquisition_method DEFAULT 'unknown'::evidence.acquisition_method NOT NULL,
    authority evidence.acquisition_authority DEFAULT 'unclear'::evidence.acquisition_authority NOT NULL,
    source_device text,
    device_custodian text,
    custody_transferred_at timestamp with time zone,
    acquired_at timestamp with time zone,
    export_created_at timestamp with time zone,
    notes text,
    producible boolean DEFAULT false NOT NULL,
    supersedes_id uuid,
    asserted_by text DEFAULT 'human'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    device_id uuid,
    CONSTRAINT acquisition_human_only CHECK ((asserted_by = 'human'::text))
);


--
-- Name: TABLE acquisition; Type: COMMENT; Schema: evidence; Owner: -
--

COMMENT ON TABLE evidence.acquisition IS 'One row per acquisition event (device/export). HITL-authored, append-only, non-producible by default. Referenced by evidence.source; never duplicated per message.';


--
-- Name: artifact_metadata; Type: TABLE; Schema: evidence; Owner: -
--

CREATE TABLE evidence.artifact_metadata (
    id uuid DEFAULT uuidv7() NOT NULL,
    source_id uuid NOT NULL,
    acquisition_id uuid,
    fs_original_path text,
    fs_filename text,
    fs_size_bytes bigint,
    fs_mtime timestamp with time zone,
    fs_ctime timestamp with time zone,
    fs_birthtime timestamp with time zone,
    fs_observed_at timestamp with time zone DEFAULT now() NOT NULL,
    embedded jsonb DEFAULT '{}'::jsonb NOT NULL,
    embedded_export_at timestamp with time zone,
    export_set_id text,
    export_kind text,
    record_count_claimed integer,
    filename_export_at timestamp with time zone,
    resolved_export_at timestamp with time zone,
    resolved_source text,
    layer_disagreement jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT artifact_metadata_resolved_source_check CHECK ((resolved_source = ANY (ARRAY['embedded'::text, 'filename'::text, 'filesystem'::text, 'manual'::text])))
);


--
-- Name: TABLE artifact_metadata; Type: COMMENT; Schema: evidence; Owner: -
--

COMMENT ON TABLE evidence.artifact_metadata IS 'Wide, cold, one row per artifact. Records filesystem / embedded / derived metadata layers separately and never collapses them. Precedence for export time: embedded > filename > filesystem. Filesystem times are observations — they do not survive copying or cloud sync.';


--
-- Name: COLUMN artifact_metadata.record_count_claimed; Type: COMMENT; Schema: evidence; Owner: -
--

COMMENT ON COLUMN evidence.artifact_metadata.record_count_claimed IS 'The exporter''s own record count. Diffing it against rows actually parsed detects truncated/interrupted exports — sbv currently reads this only to drive a progress bar and never compares it.';


--
-- Name: custody_event; Type: TABLE; Schema: evidence; Owner: -
--

CREATE TABLE evidence.custody_event (
    seq bigint NOT NULL,
    id uuid DEFAULT uuidv7() NOT NULL,
    source_id uuid NOT NULL,
    file_node_id uuid,
    evidence_hash_id uuid,
    event_type text NOT NULL,
    actor text NOT NULL,
    occurred_at timestamp with time zone DEFAULT now() NOT NULL,
    occurred_certainty ai.precision_class DEFAULT 'exact'::ai.precision_class NOT NULL,
    detail jsonb DEFAULT '{}'::jsonb NOT NULL,
    prev_event_digest bytea,
    event_digest bytea NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT custody_event_event_type_check CHECK ((event_type = ANY (ARRAY['collected'::text, 'sealed'::text, 'in_processing'::text, 'verified'::text, 'disputed'::text, 'released'::text, 're_hashed'::text, 'integrity_violation'::text, 'superseded'::text, 'accessed'::text])))
);


--
-- Name: custody_event_seq_seq; Type: SEQUENCE; Schema: evidence; Owner: -
--

ALTER TABLE evidence.custody_event ALTER COLUMN seq ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME evidence.custody_event_seq_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: evidence_hash; Type: TABLE; Schema: evidence; Owner: -
--

CREATE TABLE evidence.evidence_hash (
    id uuid DEFAULT uuidv7() NOT NULL,
    source_ref text NOT NULL,
    algo text DEFAULT 'sha256'::text NOT NULL,
    digest bytea NOT NULL,
    hashed_at timestamp with time zone DEFAULT now() NOT NULL,
    blob_key text,
    meta jsonb DEFAULT '{}'::jsonb NOT NULL,
    level text DEFAULT 'H1'::text NOT NULL,
    source_id uuid,
    file_node_id uuid,
    md5_prefilter bytea,
    record_locator jsonb,
    member_hash_ids uuid[],
    canon_version text DEFAULT 'h1-rawbytes-v1'::text NOT NULL,
    computed_by text,
    CONSTRAINT evidence_hash_check CHECK (((algo <> 'sha256'::text) OR (octet_length(digest) = 32))),
    CONSTRAINT evidence_hash_level_check CHECK ((level = ANY (ARRAY['H1'::text, 'H2'::text, 'H3'::text])))
);


--
-- Name: file_node; Type: TABLE; Schema: evidence; Owner: -
--

CREATE TABLE evidence.file_node (
    id uuid DEFAULT uuidv7() NOT NULL,
    source_id uuid NOT NULL,
    parent_node_id uuid,
    node_kind text NOT NULL,
    node_path ai.ltree,
    ordinal integer,
    sha256 bytea,
    byte_span_start bigint,
    byte_span_end bigint,
    locator jsonb DEFAULT '{}'::jsonb NOT NULL,
    mime_type text,
    extraction_confidence ai.confidence,
    attrs jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT file_node_node_kind_check CHECK ((node_kind = ANY (ARRAY['file'::text, 'archive_member'::text, 'page'::text, 'frame'::text, 'region'::text, 'screenshot'::text, 'ocr_block'::text, 'attachment'::text, 'message_unit'::text, 'event_unit'::text]))),
    CONSTRAINT file_node_sha_len CHECK (((sha256 IS NULL) OR (octet_length(sha256) = 32)))
);


--
-- Name: gps_point; Type: TABLE; Schema: evidence; Owner: -
--

CREATE TABLE evidence.gps_point (
    id uuid DEFAULT uuidv7() NOT NULL,
    source_id uuid NOT NULL,
    file_node_id uuid,
    device_id uuid,
    geog ai.geo_point NOT NULL,
    captured_at timestamp with time zone,
    captured_raw text,
    ts_precision ai.precision_class DEFAULT 'exact'::ai.precision_class NOT NULL,
    accuracy_m numeric(8,2),
    point_sequence bigint,
    ingest_run_id uuid,
    raw_data jsonb DEFAULT '{}'::jsonb NOT NULL,
    data_tier ai.evidence_tier DEFAULT 'raw'::ai.evidence_tier NOT NULL,
    ingested_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT gps_point_data_tier_check CHECK ((data_tier = 'raw'::ai.evidence_tier))
);


--
-- Name: ingest_run; Type: TABLE; Schema: evidence; Owner: -
--

CREATE TABLE evidence.ingest_run (
    id uuid DEFAULT uuidv7() NOT NULL,
    source_id uuid,
    source_sha256 bytea NOT NULL,
    source_filename text NOT NULL,
    source_bytes bigint,
    parser text NOT NULL,
    parser_version text NOT NULL,
    deriver_version text,
    raw_table text,
    runner text NOT NULL,
    started_at timestamp with time zone DEFAULT now() NOT NULL,
    finished_at timestamp with time zone,
    status text DEFAULT 'running'::text NOT NULL,
    outcome_detail text,
    count_claimed bigint,
    count_parsed bigint,
    count_rejected bigint,
    count_deduped bigint,
    count_raw bigint,
    count_spine bigint,
    count_attestations bigint,
    notes jsonb DEFAULT '{}'::jsonb NOT NULL,
    CONSTRAINT ingest_run_notes_check CHECK ((jsonb_typeof(notes) = 'object'::text)),
    CONSTRAINT ingest_run_source_sha256_check CHECK ((octet_length(source_sha256) = 32)),
    CONSTRAINT ingest_run_status_check CHECK ((status = ANY (ARRAY['running'::text, 'committed'::text, 'rolled_back'::text, 'failed'::text])))
);


--
-- Name: TABLE ingest_run; Type: COMMENT; Schema: evidence; Owner: -
--

COMMENT ON TABLE evidence.ingest_run IS 'One row per ingest ATTEMPT, written outside the ingest transaction so failed and rolled-back runs survive. The count_* columns are the funnel: claimed -> parsed -> rejected/deduped -> raw -> spine -> attestations. Added 2026-08-01 after a parser dropped 516 records with no trace.';


--
-- Name: COLUMN ingest_run.status; Type: COMMENT; Schema: evidence; Owner: -
--

COMMENT ON COLUMN evidence.ingest_run.status IS 'running | committed | rolled_back | failed. A rolled_back row is the record that a load was attempted and refused; it is not noise, it is the audit trail.';


--
-- Name: COLUMN ingest_run.count_claimed; Type: COMMENT; Schema: evidence; Owner: -
--

COMMENT ON COLUMN evidence.ingest_run.count_claimed IS 'What the artifact asserts about itself (e.g. the count attribute on an SMS Backup and Restore root element). Not authoritative - an export can be truncated or lie - but any disagreement with count_parsed is a finding.';


--
-- Name: raw_activity; Type: TABLE; Schema: evidence; Owner: -
--

CREATE TABLE evidence.raw_activity (
    id uuid DEFAULT uuidv7() NOT NULL,
    source_id uuid NOT NULL,
    file_node_id uuid,
    event_serial bigint,
    start_raw text,
    end_raw text,
    start_utc timestamp with time zone,
    end_utc timestamp with time zone,
    tz_offset_min integer,
    duration_s bigint,
    activity_type text,
    activity_probability ai.confidence,
    distance_m numeric(12,2),
    start_geog ai.geo_point,
    end_geog ai.geo_point,
    place_id_start text,
    place_id_end text,
    parent_id uuid,
    memory_id uuid,
    ingest_run_id uuid,
    raw_data jsonb DEFAULT '{}'::jsonb NOT NULL,
    data_tier ai.evidence_tier DEFAULT 'raw'::ai.evidence_tier NOT NULL,
    ingested_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT raw_activity_data_tier_check CHECK ((data_tier = 'raw'::ai.evidence_tier))
);


--
-- Name: raw_ai_chat; Type: TABLE; Schema: evidence; Owner: -
--

CREATE TABLE evidence.raw_ai_chat (
    id uuid DEFAULT uuidv7() NOT NULL,
    source_id uuid NOT NULL,
    device_id uuid,
    acquisition_id uuid,
    medium evidence.record_medium DEFAULT 'export'::evidence.record_medium NOT NULL,
    record_index integer,
    raw jsonb NOT NULL,
    raw_text text,
    content_hash text NOT NULL,
    content_canon text DEFAULT 'h2-rawelement-v1'::text NOT NULL,
    parser_version text,
    superseded_by uuid,
    supersede_note text,
    ingest_run_id uuid,
    deriver_version text,
    ingested_at timestamp with time zone DEFAULT now() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: TABLE raw_ai_chat; Type: COMMENT; Schema: evidence; Owner: -
--

COMMENT ON TABLE evidence.raw_ai_chat IS 'RAW per-source layer for ai_chat. The ONLY insert target for this format. Verbatim and never edited; spine and projection are derived from it. Dedup on (device, medium, content) only - a screenshot of the same message is a separate attestation, not a duplicate.';


--
-- Name: raw_csv; Type: TABLE; Schema: evidence; Owner: -
--

CREATE TABLE evidence.raw_csv (
    id uuid DEFAULT uuidv7() NOT NULL,
    source_id uuid NOT NULL,
    device_id uuid,
    acquisition_id uuid,
    medium evidence.record_medium DEFAULT 'export'::evidence.record_medium NOT NULL,
    record_index integer,
    raw jsonb NOT NULL,
    raw_text text,
    content_hash text NOT NULL,
    content_canon text DEFAULT 'h2-rawelement-v1'::text NOT NULL,
    parser_version text,
    superseded_by uuid,
    supersede_note text,
    ingest_run_id uuid,
    deriver_version text,
    ingested_at timestamp with time zone DEFAULT now() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: TABLE raw_csv; Type: COMMENT; Schema: evidence; Owner: -
--

COMMENT ON TABLE evidence.raw_csv IS 'RAW per-source layer for csv. The ONLY insert target for this format. Verbatim and never edited; spine and projection are derived from it. Dedup on (device, medium, content) only - a screenshot of the same message is a separate attestation, not a duplicate.';


--
-- Name: raw_facebook; Type: TABLE; Schema: evidence; Owner: -
--

CREATE TABLE evidence.raw_facebook (
    id uuid DEFAULT uuidv7() NOT NULL,
    source_id uuid NOT NULL,
    device_id uuid,
    acquisition_id uuid,
    medium evidence.record_medium DEFAULT 'export'::evidence.record_medium NOT NULL,
    record_index integer,
    raw jsonb NOT NULL,
    raw_text text,
    content_hash text NOT NULL,
    content_canon text DEFAULT 'h2-rawelement-v1'::text NOT NULL,
    parser_version text,
    superseded_by uuid,
    supersede_note text,
    ingest_run_id uuid,
    deriver_version text,
    ingested_at timestamp with time zone DEFAULT now() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: TABLE raw_facebook; Type: COMMENT; Schema: evidence; Owner: -
--

COMMENT ON TABLE evidence.raw_facebook IS 'RAW per-source layer for facebook. The ONLY insert target for this format. Verbatim and never edited; spine and projection are derived from it. Dedup on (device, medium, content) only - a screenshot of the same message is a separate attestation, not a duplicate.';


--
-- Name: raw_imessage; Type: TABLE; Schema: evidence; Owner: -
--

CREATE TABLE evidence.raw_imessage (
    id uuid DEFAULT uuidv7() NOT NULL,
    source_id uuid NOT NULL,
    device_id uuid,
    acquisition_id uuid,
    medium evidence.record_medium DEFAULT 'export'::evidence.record_medium NOT NULL,
    record_index integer,
    raw jsonb NOT NULL,
    raw_text text,
    content_hash text NOT NULL,
    content_canon text DEFAULT 'h2-rawelement-v1'::text NOT NULL,
    parser_version text,
    superseded_by uuid,
    supersede_note text,
    ingest_run_id uuid,
    deriver_version text,
    ingested_at timestamp with time zone DEFAULT now() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: TABLE raw_imessage; Type: COMMENT; Schema: evidence; Owner: -
--

COMMENT ON TABLE evidence.raw_imessage IS 'RAW per-source layer for imessage. The ONLY insert target for this format. Verbatim and never edited; spine and projection are derived from it. Dedup on (device, medium, content) only - a screenshot of the same message is a separate attestation, not a duplicate.';


--
-- Name: raw_path; Type: TABLE; Schema: evidence; Owner: -
--

CREATE TABLE evidence.raw_path (
    id uuid DEFAULT uuidv7() NOT NULL,
    source_id uuid NOT NULL,
    file_node_id uuid,
    path_serial bigint,
    point_sequence bigint NOT NULL,
    point_geog ai.geo_point NOT NULL,
    point_ts_raw text,
    point_ts_utc timestamp with time zone,
    tz_offset_min integer,
    aligned_activity_id uuid,
    parent_id uuid,
    ingest_run_id uuid,
    raw_data jsonb DEFAULT '{}'::jsonb NOT NULL,
    data_tier ai.evidence_tier DEFAULT 'raw'::ai.evidence_tier NOT NULL,
    ingested_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT raw_path_data_tier_check CHECK ((data_tier = 'raw'::ai.evidence_tier))
);


--
-- Name: raw_phone; Type: TABLE; Schema: evidence; Owner: -
--

CREATE TABLE evidence.raw_phone (
    id uuid DEFAULT uuidv7() NOT NULL,
    source_id uuid NOT NULL,
    device_id uuid,
    acquisition_id uuid,
    medium evidence.record_medium DEFAULT 'export'::evidence.record_medium NOT NULL,
    record_index integer,
    raw jsonb NOT NULL,
    raw_text text,
    content_hash text NOT NULL,
    content_canon text DEFAULT 'h2-rawelement-v1'::text NOT NULL,
    parser_version text,
    superseded_by uuid,
    supersede_note text,
    ingest_run_id uuid,
    deriver_version text,
    ingested_at timestamp with time zone DEFAULT now() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: TABLE raw_phone; Type: COMMENT; Schema: evidence; Owner: -
--

COMMENT ON TABLE evidence.raw_phone IS 'RAW per-source layer for phone. The ONLY insert target for this format. Verbatim and never edited; spine and projection are derived from it. Dedup on (device, medium, content) only - a screenshot of the same message is a separate attestation, not a duplicate.';


--
-- Name: raw_rejected; Type: TABLE; Schema: evidence; Owner: -
--

CREATE TABLE evidence.raw_rejected (
    id uuid DEFAULT uuidv7() NOT NULL,
    ingest_run_id uuid NOT NULL,
    source_sha256 bytea NOT NULL,
    record_index bigint,
    element_tag text,
    reason text NOT NULL,
    reason_detail text,
    content_hash text,
    raw jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT raw_rejected_reason_check CHECK ((reason = ANY (ARRAY['no_timestamp_no_counterparty'::text, 'dedup_duplicate_in_source'::text, 'parser_returned_none'::text, 'unmapped_element'::text, 'malformed'::text, 'operator_excluded'::text]))),
    CONSTRAINT raw_rejected_source_sha256_check CHECK ((octet_length(source_sha256) = 32))
);


--
-- Name: TABLE raw_rejected; Type: COMMENT; Schema: evidence; Owner: -
--

COMMENT ON TABLE evidence.raw_rejected IS 'Every record a parser refused, stored verbatim with the reason. A dropped record is an absence and cannot be queried after the fact - it must be written at the moment of refusal. dedup_duplicate_in_source rows are the losing side of a raw dedup collapse and are how "raw < parsed" is PROVEN rather than assumed.';


--
-- Name: raw_sms; Type: TABLE; Schema: evidence; Owner: -
--

CREATE TABLE evidence.raw_sms (
    id uuid DEFAULT uuidv7() NOT NULL,
    source_id uuid NOT NULL,
    device_id uuid,
    acquisition_id uuid,
    medium evidence.record_medium DEFAULT 'export'::evidence.record_medium NOT NULL,
    record_index integer,
    raw jsonb NOT NULL,
    raw_text text,
    content_hash text NOT NULL,
    content_canon text DEFAULT 'h2-rawelement-v1'::text NOT NULL,
    parser_version text,
    superseded_by uuid,
    supersede_note text,
    ingest_run_id uuid,
    deriver_version text,
    ingested_at timestamp with time zone DEFAULT now() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: TABLE raw_sms; Type: COMMENT; Schema: evidence; Owner: -
--

COMMENT ON TABLE evidence.raw_sms IS 'RAW per-source layer for sms. The ONLY insert target for this format. Verbatim and never edited; spine and projection are derived from it. Dedup on (device, medium, content) only - a screenshot of the same message is a separate attestation, not a duplicate.';


--
-- Name: raw_trip; Type: TABLE; Schema: evidence; Owner: -
--

CREATE TABLE evidence.raw_trip (
    id uuid DEFAULT uuidv7() NOT NULL,
    source_id uuid NOT NULL,
    file_node_id uuid,
    event_serial bigint,
    start_raw text,
    end_raw text,
    start_utc timestamp with time zone,
    end_utc timestamp with time zone,
    tz_offset_min integer,
    duration_s bigint,
    distance_from_origin_km numeric(12,3),
    destination_place_ids text[],
    parent_id uuid,
    ingest_run_id uuid,
    raw_data jsonb DEFAULT '{}'::jsonb NOT NULL,
    data_tier ai.evidence_tier DEFAULT 'raw'::ai.evidence_tier NOT NULL,
    ingested_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT raw_trip_data_tier_check CHECK ((data_tier = 'raw'::ai.evidence_tier))
);


--
-- Name: raw_visit; Type: TABLE; Schema: evidence; Owner: -
--

CREATE TABLE evidence.raw_visit (
    id uuid DEFAULT uuidv7() NOT NULL,
    source_id uuid NOT NULL,
    file_node_id uuid,
    event_serial bigint,
    hierarchy_level integer,
    start_raw text,
    end_raw text,
    start_utc timestamp with time zone,
    end_utc timestamp with time zone,
    tz_offset_min integer,
    duration_s bigint,
    detection_probability ai.confidence,
    semantic_type text,
    semantic_probability ai.confidence,
    place_id text,
    geog ai.geo_point,
    parent_id uuid,
    memory_id uuid,
    ingest_run_id uuid,
    raw_data jsonb DEFAULT '{}'::jsonb NOT NULL,
    data_tier ai.evidence_tier DEFAULT 'raw'::ai.evidence_tier NOT NULL,
    ingested_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT raw_visit_data_tier_check CHECK ((data_tier = 'raw'::ai.evidence_tier))
);


--
-- Name: source; Type: TABLE; Schema: evidence; Owner: -
--

CREATE TABLE evidence.source (
    id uuid DEFAULT uuidv7() NOT NULL,
    sha256 bytea NOT NULL,
    md5_prefilter bytea,
    byte_size bigint NOT NULL,
    mime_type text,
    original_filename text,
    source_type text NOT NULL,
    source_platform text,
    custodian text DEFAULT 'Matt Salem'::text NOT NULL,
    acquisition_source text NOT NULL,
    acquisition_method text,
    origin_device_id uuid,
    origin_account uuid,
    acquired_at_raw text,
    acquired_at_utc timestamp with time zone,
    acquired_tz_offset text,
    acquired_certainty ai.precision_class DEFAULT 'exact'::ai.precision_class NOT NULL,
    provenance_tier text DEFAULT 'r2_canonical'::text NOT NULL,
    r2_bucket text,
    r2_key text,
    local_path text,
    hash_canon_version text DEFAULT 'h1-rawbytes-v1'::text NOT NULL,
    sensitivity_tier ai.sensitivity_tier DEFAULT 'restricted'::ai.sensitivity_tier NOT NULL,
    legal_sensitivity text DEFAULT 'none'::text NOT NULL,
    privacy_sensitivity text DEFAULT 'none'::text NOT NULL,
    supersedes_source_id uuid,
    custody_status text DEFAULT 'collected'::text NOT NULL,
    extraction_status text DEFAULT 'pending'::text NOT NULL,
    processing_status text DEFAULT 'pending'::text NOT NULL,
    review_status text DEFAULT 'not_reviewed'::text NOT NULL,
    export_status text DEFAULT 'not_exported'::text NOT NULL,
    verified_by text,
    verified_at timestamp with time zone,
    original_metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    derived_metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    ingested_at timestamp with time zone DEFAULT now() NOT NULL,
    acquisition_id uuid,
    CONSTRAINT source_acquisition_method_check CHECK (((acquisition_method IS NULL) OR (acquisition_method = ANY (ARRAY['forensic_image'::text, 'manual_export'::text, 'cloud_pull'::text, 'photograph'::text, 'scan'::text, 'backup'::text])))),
    CONSTRAINT source_custody_status_check CHECK ((custody_status = ANY (ARRAY['collected'::text, 'sealed'::text, 'in_processing'::text, 'verified'::text, 'disputed'::text, 'released'::text]))),
    CONSTRAINT source_export_status_check CHECK ((export_status = ANY (ARRAY['not_exported'::text, 'in_package'::text, 'exported'::text, 'withdrawn'::text]))),
    CONSTRAINT source_extraction_status_check CHECK ((extraction_status = ANY (ARRAY['pending'::text, 'running'::text, 'done'::text, 'failed'::text, 'n/a'::text]))),
    CONSTRAINT source_legal_sensitivity_check CHECK ((legal_sensitivity = ANY (ARRAY['none'::text, 'privileged'::text, 'confidential'::text, 'in_camera'::text]))),
    CONSTRAINT source_privacy_sensitivity_check CHECK ((privacy_sensitivity = ANY (ARRAY['none'::text, 'pii'::text, 'minor'::text, 'sensitive_pii'::text]))),
    CONSTRAINT source_processing_status_check CHECK ((processing_status = ANY (ARRAY['pending'::text, 'enriched'::text, 'analyzed'::text, 'failed'::text]))),
    CONSTRAINT source_provenance_tier_check CHECK ((provenance_tier = ANY (ARRAY['r2_canonical'::text, 'backup_corroborating'::text]))),
    CONSTRAINT source_review_status_check CHECK ((review_status = ANY (ARRAY['not_reviewed'::text, 'in_review'::text, 'reviewed'::text, 'flagged'::text]))),
    CONSTRAINT source_sha256_len CHECK ((octet_length(sha256) = 32)),
    CONSTRAINT source_source_type_check CHECK ((source_type = ANY (ARRAY['device_dump'::text, 'chat_export'::text, 'screenshot'::text, 'call_log'::text, 'pdf'::text, 'media'::text, 'takeout'::text, 'social_export'::text, 'document'::text, 'other'::text])))
);


--
-- Name: COLUMN source.acquisition_source; Type: COMMENT; Schema: evidence; Owner: -
--

COMMENT ON COLUMN evidence.source.acquisition_source IS 'PER-FILE acquisition source (e.g. "sbv", "manual_export"), written at ingest. Describes the ingest CHANNEL, not the legal/physical provenance — that is evidence.acquisition.method + .authority.';


--
-- Name: COLUMN source.acquisition_method; Type: COMMENT; Schema: evidence; Owner: -
--

COMMENT ON COLUMN evidence.source.acquisition_method IS 'PER-FILE acquisition method, written at ingest by server/evidence/custody.py. Retained and live. For the per-EVENT record — device, authority, custodian, time-scoped handoff, one row covering many files — join evidence.acquisition via evidence.source.acquisition_id. On disagreement the acquisition row wins: it is HITL-authored, the per-file value is a pipeline default.';


--
-- Name: vw_raw_all; Type: VIEW; Schema: evidence; Owner: -
--

CREATE VIEW evidence.vw_raw_all AS
 SELECT 'evidence.raw_sms'::text AS raw_table,
    raw_sms.id,
    raw_sms.source_id,
    raw_sms.device_id,
    raw_sms.acquisition_id,
    raw_sms.medium,
    raw_sms.record_index,
    raw_sms.content_hash,
    raw_sms.parser_version,
    raw_sms.superseded_by,
    raw_sms.ingested_at
   FROM evidence.raw_sms
UNION ALL
 SELECT 'evidence.raw_imessage'::text AS raw_table,
    raw_imessage.id,
    raw_imessage.source_id,
    raw_imessage.device_id,
    raw_imessage.acquisition_id,
    raw_imessage.medium,
    raw_imessage.record_index,
    raw_imessage.content_hash,
    raw_imessage.parser_version,
    raw_imessage.superseded_by,
    raw_imessage.ingested_at
   FROM evidence.raw_imessage
UNION ALL
 SELECT 'evidence.raw_facebook'::text AS raw_table,
    raw_facebook.id,
    raw_facebook.source_id,
    raw_facebook.device_id,
    raw_facebook.acquisition_id,
    raw_facebook.medium,
    raw_facebook.record_index,
    raw_facebook.content_hash,
    raw_facebook.parser_version,
    raw_facebook.superseded_by,
    raw_facebook.ingested_at
   FROM evidence.raw_facebook
UNION ALL
 SELECT 'evidence.raw_ai_chat'::text AS raw_table,
    raw_ai_chat.id,
    raw_ai_chat.source_id,
    raw_ai_chat.device_id,
    raw_ai_chat.acquisition_id,
    raw_ai_chat.medium,
    raw_ai_chat.record_index,
    raw_ai_chat.content_hash,
    raw_ai_chat.parser_version,
    raw_ai_chat.superseded_by,
    raw_ai_chat.ingested_at
   FROM evidence.raw_ai_chat
UNION ALL
 SELECT 'evidence.raw_csv'::text AS raw_table,
    raw_csv.id,
    raw_csv.source_id,
    raw_csv.device_id,
    raw_csv.acquisition_id,
    raw_csv.medium,
    raw_csv.record_index,
    raw_csv.content_hash,
    raw_csv.parser_version,
    raw_csv.superseded_by,
    raw_csv.ingested_at
   FROM evidence.raw_csv
UNION ALL
 SELECT 'evidence.raw_phone'::text AS raw_table,
    raw_phone.id,
    raw_phone.source_id,
    raw_phone.device_id,
    raw_phone.acquisition_id,
    raw_phone.medium,
    raw_phone.record_index,
    raw_phone.content_hash,
    raw_phone.parser_version,
    raw_phone.superseded_by,
    raw_phone.ingested_at
   FROM evidence.raw_phone;


--
-- Name: VIEW vw_raw_all; Type: COMMENT; Schema: evidence; Owner: -
--

COMMENT ON VIEW evidence.vw_raw_all IS 'Every raw row across all six per-format raw tables, restricted to the columns they share. The tables stay separate on purpose; this view exists because "how many raw records does this artifact have" is a cross-format question.';


--
-- Name: vw_artifacts_without_claim; Type: VIEW; Schema: evidence; Owner: -
--

CREATE VIEW evidence.vw_artifacts_without_claim AS
 SELECT s.id AS source_id,
    s.original_filename,
    s.source_type,
    s.byte_size,
    s.ingested_at,
    (am.source_id IS NOT NULL) AS has_metadata_row,
    ( SELECT count(*) AS count
           FROM evidence.vw_raw_all r
          WHERE (r.source_id = s.id)) AS raw_rows
   FROM (evidence.source s
     LEFT JOIN evidence.artifact_metadata am ON ((am.source_id = s.id)))
  WHERE ((am.source_id IS NULL) OR (am.record_count_claimed IS NULL));


--
-- Name: VIEW vw_artifacts_without_claim; Type: COMMENT; Schema: evidence; Owner: -
--

COMMENT ON VIEW evidence.vw_artifacts_without_claim IS 'Artifacts that cannot be reconciled because nothing recorded what they claim about themselves - either no artifact_metadata row exists, or its record_count_claimed is NULL. Every row here is a blind spot.';


--
-- Name: vw_dropped_records; Type: VIEW; Schema: evidence; Owner: -
--

CREATE VIEW evidence.vw_dropped_records AS
 SELECT j.id AS rejected_id,
    encode(j.source_sha256, 'hex'::text) AS h1,
    s.original_filename,
    ir.parser,
    ir.parser_version,
    ir.status AS run_status,
    j.record_index,
    j.element_tag,
    j.reason,
    j.reason_detail,
    j.content_hash,
    j.raw,
    j.created_at
   FROM ((evidence.raw_rejected j
     JOIN evidence.ingest_run ir ON ((ir.id = j.ingest_run_id)))
     LEFT JOIN evidence.source s ON ((s.sha256 = j.source_sha256)));


--
-- Name: VIEW vw_dropped_records; Type: COMMENT; Schema: evidence; Owner: -
--

COMMENT ON VIEW evidence.vw_dropped_records IS 'Everything a parser refused, joined to the run that refused it. An empty result means nothing was dropped - which is only believable if vw_reconciliation also says RECONCILED.';


--
-- Name: vw_ingest_history; Type: VIEW; Schema: evidence; Owner: -
--

CREATE VIEW evidence.vw_ingest_history AS
 SELECT id AS run_id,
    source_filename,
    status,
    parser,
    parser_version,
    runner,
    started_at,
    finished_at,
    (EXTRACT(epoch FROM (finished_at - started_at)))::bigint AS duration_s,
    count_claimed,
    count_parsed,
    count_rejected,
    count_deduped,
    count_raw,
    count_spine,
    count_attestations,
    (COALESCE(count_claimed, (0)::bigint) - COALESCE(count_parsed, (0)::bigint)) AS claimed_minus_parsed,
    outcome_detail,
    notes
   FROM evidence.ingest_run ir
  ORDER BY started_at DESC;


--
-- Name: VIEW vw_ingest_history; Type: COMMENT; Schema: evidence; Owner: -
--

COMMENT ON VIEW evidence.vw_ingest_history IS 'Every ingest attempt including failures and rollbacks. A rolled_back row with a populated funnel is the most useful diagnostic in the system: it shows exactly which stage stopped agreeing.';


--
-- Name: processing_run; Type: TABLE; Schema: ops; Owner: -
--

CREATE TABLE ops.processing_run (
    run_id uuid DEFAULT uuidv7() NOT NULL,
    run_type text NOT NULL,
    run_purpose text,
    status text DEFAULT 'queued'::text NOT NULL,
    actor text NOT NULL,
    tool_or_model text,
    code_version text,
    prompt_version_id uuid,
    model_version_id uuid,
    schema_version_id uuid,
    ontology_version_id uuid,
    classification_version_id uuid,
    input_evidence_ids uuid[] DEFAULT '{}'::uuid[] NOT NULL,
    input_artifact_ids uuid[] DEFAULT '{}'::uuid[] NOT NULL,
    output_artifact_ids uuid[] DEFAULT '{}'::uuid[] NOT NULL,
    input_digest jsonb DEFAULT '[]'::jsonb NOT NULL,
    inputs_hash bytea,
    params jsonb DEFAULT '{}'::jsonb NOT NULL,
    ran_local_only boolean DEFAULT false NOT NULL,
    cloud_exposure boolean DEFAULT false NOT NULL,
    counts_processed integer,
    counts_failed integer,
    confidence_summary jsonb,
    human_review_requirement boolean DEFAULT false NOT NULL,
    replayable boolean DEFAULT false NOT NULL,
    error_message text,
    summary text,
    supersedes_run uuid,
    started_at timestamp with time zone,
    finished_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    code_ref text,
    CONSTRAINT processing_run_run_type_check CHECK ((run_type = ANY (ARRAY['acquisition'::text, 'file_scan'::text, 'repository_scan'::text, 'evidence_ingestion'::text, 'extraction'::text, 'ingestion'::text, 'ocr'::text, 'transcription'::text, 'message_parsing'::text, 'entity_extraction'::text, 'temporal_extraction'::text, 'location_extraction'::text, 'gps_processing'::text, 'embedding'::text, 'graph_projection'::text, 'surreal_consolidation'::text, 'ontology_merge'::text, 'schema_generation'::text, 'classification'::text, 'pattern_analysis'::text, 'legal_issue_mapping'::text, 'scoring'::text, 'model_analysis'::text, 'evidence_task_generation'::text, 'redaction'::text, 'export'::text, 'review'::text]))),
    CONSTRAINT processing_run_status_check CHECK ((status = ANY (ARRAY['queued'::text, 'running'::text, 'ok'::text, 'failed'::text, 'partial'::text, 'cancelled'::text, 'superseded'::text])))
);


--
-- Name: COLUMN processing_run.code_ref; Type: COMMENT; Schema: ops; Owner: -
--

COMMENT ON COLUMN ops.processing_run.code_ref IS 'Tracked location of the code that performed this run: "specs/<file> sha256:<hex>" or "repo:<path>@<git sha>". Required to claim replayable=true.';


--
-- Name: tool_call_ledger; Type: TABLE; Schema: ops; Owner: -
--

CREATE TABLE ops.tool_call_ledger (
    tool_call_id uuid DEFAULT uuidv7() NOT NULL,
    run_id uuid,
    tool_name text NOT NULL,
    tool_category text NOT NULL,
    requested_by text,
    input_summary text,
    input_payload_uri text,
    input_hash bytea,
    output_summary text,
    output_payload_uri text,
    output_hash bytea,
    created_artifact_ids uuid[] DEFAULT '{}'::uuid[] NOT NULL,
    updated_record_refs jsonb DEFAULT '[]'::jsonb NOT NULL,
    runtime_ms integer,
    cost_estimate numeric(12,4),
    human_approval_status text DEFAULT 'n/a'::text NOT NULL,
    safety_flags jsonb DEFAULT '[]'::jsonb NOT NULL,
    replayability_status text DEFAULT 'replayable'::text NOT NULL,
    errors text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    prompt_version text,
    CONSTRAINT tool_call_ledger_human_approval_status_check CHECK ((human_approval_status = ANY (ARRAY['n/a'::text, 'pending'::text, 'approved'::text, 'denied'::text]))),
    CONSTRAINT tool_call_ledger_replayability_status_check CHECK ((replayability_status = ANY (ARRAY['replayable'::text, 'inputs_lost'::text, 'nondeterministic'::text]))),
    CONSTRAINT tool_call_ledger_tool_category_check CHECK ((tool_category = ANY (ARRAY['read'::text, 'analysis'::text, 'write'::text, 'transfer'::text, 'deploy'::text, 'llm'::text, 'mcp'::text])))
);


--
-- Name: COLUMN tool_call_ledger.prompt_version; Type: COMMENT; Schema: ops; Owner: -
--

COMMENT ON COLUMN ops.tool_call_ledger.prompt_version IS 'public.prompt_registry.prompt_version used by this call — joins for prompt-performance rollup.';


--
-- Name: workflow_run; Type: TABLE; Schema: ops; Owner: -
--

CREATE TABLE ops.workflow_run (
    run_id uuid DEFAULT uuidv7() NOT NULL,
    workflow text NOT NULL,
    mode text DEFAULT 'auto'::text NOT NULL,
    source_name text,
    source_path text,
    sha256 text,
    artifact_id text,
    domain text,
    status text DEFAULT 'running'::text NOT NULL,
    summary jsonb,
    error text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    gate_state text,
    parent_run_id uuid,
    custody_tier text DEFAULT 'full'::text NOT NULL,
    CONSTRAINT workflow_run_custody_tier_check CHECK ((custody_tier = ANY (ARRAY['full'::text, 'light'::text]))),
    CONSTRAINT workflow_run_gate_state_check CHECK (((gate_state = ANY (ARRAY['waiting'::text, 'released'::text, 'abort'::text])) OR (gate_state IS NULL))),
    CONSTRAINT workflow_run_mode_check CHECK ((mode = ANY (ARRAY['auto'::text, 'supervised'::text]))),
    CONSTRAINT workflow_run_status_check CHECK ((status = ANY (ARRAY['running'::text, 'paused'::text, 'completed'::text, 'failed'::text])))
);


--
-- Name: behavior_category; Type: TABLE; Schema: reference; Owner: -
--

CREATE TABLE reference.behavior_category (
    category_id ai.citext NOT NULL,
    label text NOT NULL,
    description text,
    polarity ai.category_polarity NOT NULL,
    default_severity smallint DEFAULT 5 NOT NULL,
    mcl_factors ai.mcl_factor[] DEFAULT '{}'::ai.mcl_factor[] NOT NULL,
    aliases ai.citext[] DEFAULT '{}'::ai.citext[] NOT NULL,
    is_case_specific boolean DEFAULT false NOT NULL,
    source text,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    is_enabled boolean DEFAULT true NOT NULL,
    CONSTRAINT behavior_category_sev_chk CHECK (((default_severity >= 0) AND (default_severity <= 10)))
);


--
-- Name: COLUMN behavior_category.is_enabled; Type: COMMENT; Schema: reference; Owner: -
--

COMMENT ON COLUMN reference.behavior_category.is_enabled IS 'Category-level detection kill switch. Detection runners MUST honor: skip patterns whose category.is_enabled = false. (detection.py + forensic-detection commit SQL to filter on this.)';


--
-- Name: behavior_category_mcl; Type: TABLE; Schema: reference; Owner: -
--

CREATE TABLE reference.behavior_category_mcl (
    category_id ai.citext NOT NULL,
    factor_code ai.mcl_factor NOT NULL,
    weight text,
    is_critical boolean DEFAULT false NOT NULL,
    note text
);


--
-- Name: custody_factor; Type: TABLE; Schema: reference; Owner: -
--

CREATE TABLE reference.custody_factor (
    factor ai.mcl_factor NOT NULL,
    code_display text NOT NULL,
    name text NOT NULL,
    statutory_text text,
    is_key_factor boolean DEFAULT false NOT NULL,
    notes text
);


--
-- Name: detection_pattern; Type: TABLE; Schema: reference; Owner: -
--

CREATE TABLE reference.detection_pattern (
    id uuid DEFAULT uuidv7() NOT NULL,
    pattern_set_id uuid NOT NULL,
    category_id ai.citext NOT NULL,
    subcategory text,
    match_type ai.pattern_match_type NOT NULL,
    pattern text NOT NULL,
    keywords text[] DEFAULT '{}'::text[] NOT NULL,
    severity smallint DEFAULT 5 NOT NULL,
    score smallint,
    mcl_factors ai.mcl_factor[] DEFAULT '{}'::ai.mcl_factor[] NOT NULL,
    description text,
    is_case_specific boolean DEFAULT false NOT NULL,
    authored_perspective text,
    bias_caution boolean DEFAULT true NOT NULL,
    source text,
    is_active boolean DEFAULT true NOT NULL,
    valid_from timestamp with time zone DEFAULT now() NOT NULL,
    valid_to timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT detection_pattern_score_chk CHECK (((score IS NULL) OR ((score >= 1) AND (score <= 10)))),
    CONSTRAINT detection_pattern_sev_chk CHECK (((severity >= 0) AND (severity <= 10)))
);


--
-- Name: pattern_lexicon; Type: TABLE; Schema: reference; Owner: -
--

CREATE TABLE reference.pattern_lexicon (
    id uuid DEFAULT uuidv7() NOT NULL,
    pattern_set_id uuid NOT NULL,
    lexicon_type text NOT NULL,
    term text NOT NULL,
    variants text[] DEFAULT '{}'::text[] NOT NULL,
    match_type ai.pattern_match_type DEFAULT 'literal'::ai.pattern_match_type NOT NULL,
    relevance_signal text,
    severity smallint DEFAULT 0 NOT NULL,
    mcl_factors ai.mcl_factor[] DEFAULT '{}'::ai.mcl_factor[] NOT NULL,
    is_case_specific boolean DEFAULT true NOT NULL,
    sensitivity_tier ai.sensitivity_tier DEFAULT 'restricted'::ai.sensitivity_tier NOT NULL,
    source text,
    is_active boolean DEFAULT true NOT NULL,
    valid_from timestamp with time zone DEFAULT now() NOT NULL,
    valid_to timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT pattern_lexicon_sev_chk CHECK (((severity >= 0) AND (severity <= 10)))
);


--
-- Name: topic_code; Type: TABLE; Schema: reference; Owner: -
--

CREATE TABLE reference.topic_code (
    code character varying(6) NOT NULL,
    label text NOT NULL,
    keywords text[] DEFAULT '{}'::text[] NOT NULL,
    mcl_factors ai.mcl_factor[],
    is_case_specific boolean DEFAULT false NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: TABLE topic_code; Type: COMMENT; Schema: reference; Owner: -
--

COMMENT ON TABLE reference.topic_code IS 'Human-readable conversation topic codes (6-char). Seed = topic_detector.py TOPIC_MAPPING.';


--
-- Name: attachment; Type: TABLE; Schema: working; Owner: -
--

CREATE TABLE working.attachment (
    id uuid DEFAULT uuidv7() NOT NULL,
    message_id uuid NOT NULL,
    source_artifact_id uuid,
    media_asset_id uuid,
    filename text,
    attachment_type text,
    mime_type text,
    file_sha256 bytea,
    file_size bigint,
    object_uri text,
    thumbnail_uri text,
    width integer,
    height integer,
    duration_s numeric,
    is_screenshot boolean DEFAULT false NOT NULL,
    contains_faces boolean DEFAULT false NOT NULL,
    ocr_text text,
    transcription text,
    exif jsonb,
    ocr_confidence ai.confidence,
    embedding_ref text,
    data_tier ai.evidence_tier DEFAULT 'extracted'::ai.evidence_tier NOT NULL,
    review_status ai.review_state DEFAULT 'unreviewed'::ai.review_state NOT NULL,
    platform_attrs jsonb DEFAULT '{}'::jsonb NOT NULL,
    raw_data jsonb,
    provenance_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT attachment_file_sha256_check CHECK (((file_sha256 IS NULL) OR (octet_length(file_sha256) = 32)))
);


--
-- Name: call_log; Type: TABLE; Schema: working; Owner: -
--

CREATE TABLE working.call_log (
    id uuid NOT NULL,
    source_artifact_id uuid NOT NULL,
    conversation_id uuid,
    from_raw text,
    from_e164 text,
    from_entity_id uuid,
    to_raw text,
    to_e164 text,
    to_entity_id uuid,
    call_type text NOT NULL,
    direction text,
    started_at timestamp with time zone,
    ts_precision ai.precision_class DEFAULT 'exact'::ai.precision_class NOT NULL,
    duration_s integer,
    is_blocked boolean DEFAULT false NOT NULL,
    presentation text,
    data_tier ai.evidence_tier DEFAULT 'extracted'::ai.evidence_tier NOT NULL,
    platform_attrs jsonb DEFAULT '{}'::jsonb NOT NULL,
    raw_data jsonb,
    provenance_id uuid,
    CONSTRAINT call_log_call_type_check CHECK ((call_type = ANY (ARRAY['incoming'::text, 'outgoing'::text, 'missed'::text, 'rejected'::text, 'blocked_incoming'::text, 'blocked_outgoing'::text, 'voicemail'::text]))),
    CONSTRAINT call_log_direction_check CHECK ((direction = ANY (ARRAY['inbound'::text, 'outbound'::text, 'unknown'::text])))
);


--
-- Name: conversation; Type: TABLE; Schema: working; Owner: -
--

CREATE TABLE working.conversation (
    id uuid DEFAULT uuidv7() NOT NULL,
    source_artifact_id uuid NOT NULL,
    platform text NOT NULL,
    external_thread_key text,
    title text,
    participants jsonb DEFAULT '[]'::jsonb NOT NULL,
    participant_count integer,
    primary_participant text,
    primary_participant_e164 text,
    is_group boolean DEFAULT false NOT NULL,
    started_at timestamp with time zone,
    ended_at timestamp with time zone,
    message_count integer DEFAULT 0 NOT NULL,
    is_evidence boolean DEFAULT false NOT NULL,
    exhibit_number text,
    relevance ai.confidence,
    behavior_summary jsonb DEFAULT '{}'::jsonb NOT NULL,
    data_tier ai.evidence_tier DEFAULT 'extracted'::ai.evidence_tier NOT NULL,
    review_status ai.review_state DEFAULT 'unreviewed'::ai.review_state NOT NULL,
    platform_attrs jsonb DEFAULT '{}'::jsonb NOT NULL,
    raw_data jsonb,
    provenance_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    cluster_code text,
    cluster_reason text,
    CONSTRAINT conversation_cluster_reason_check CHECK (((cluster_reason IS NULL) OR (cluster_reason = ANY (ARRAY['time_gap'::text, 'topic_change'::text, 'entity_change'::text, 'first_message'::text]))))
);


--
-- Name: COLUMN conversation.cluster_code; Type: COMMENT; Schema: working; Owner: -
--

COMMENT ON COLUMN working.conversation.cluster_code IS 'Human-readable cluster id PLAT_YYMM_TOPIC_iii (e.g. SMS_1905_KAILAH_001). cluster_reason = split cause.';


--
-- Name: device; Type: TABLE; Schema: working; Owner: -
--

CREATE TABLE working.device (
    id uuid NOT NULL,
    make_model text,
    os text,
    imei_or_serial ai.citext,
    owner_entity_id uuid,
    device_label text,
    acquired_note text
);


--
-- Name: COLUMN device.owner_entity_id; Type: COMMENT; Schema: working; Owner: -
--

COMMENT ON COLUMN working.device.owner_entity_id IS 'CURRENT owner only, kept as a convenience pointer. For any record-level attribution use analysis.device_ownership, which is time-scoped — a hand-me-down device has different owners across its history.';


--
-- Name: COLUMN device.device_label; Type: COMMENT; Schema: working; Owner: -
--

COMMENT ON COLUMN working.device.device_label IS 'Unique human-assigned device name, e.g. "Daughter iPhone 11 (handed down 2024-03)". Required via the ingest form / HITL prompt — make_model cannot distinguish two identical handsets and imei_or_serial is often unknown for second-hand devices.';


--
-- Name: entity; Type: TABLE; Schema: working; Owner: -
--

CREATE TABLE working.entity (
    id uuid DEFAULT uuidv7() NOT NULL,
    entity_type ai.entity_type NOT NULL,
    display_name ai.citext,
    canonical_name ai.citext,
    normalized_name ai.citext,
    sensitivity_tier ai.sensitivity_tier,
    is_party boolean DEFAULT false NOT NULL,
    data_tier ai.evidence_tier DEFAULT 'inferred'::ai.evidence_tier NOT NULL,
    evidence_confidence ai.confidence,
    provenance ai.source_ref[] DEFAULT '{}'::ai.source_ref[] NOT NULL,
    requires_human_review boolean DEFAULT false NOT NULL,
    review_status ai.review_state DEFAULT 'unreviewed'::ai.review_state NOT NULL,
    safe_for_legal_use boolean DEFAULT false NOT NULL,
    merged_into_id uuid,
    first_seen_at timestamp with time zone,
    last_seen_at timestamp with time zone,
    sys_period tstzrange DEFAULT tstzrange(now(), NULL::timestamp with time zone) NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT entity_not_self_merge CHECK ((merged_into_id IS DISTINCT FROM id))
);


--
-- Name: event_source_record; Type: TABLE; Schema: working; Owner: -
--

CREATE TABLE working.event_source_record (
    link_id uuid DEFAULT uuidv7() NOT NULL,
    event_id uuid,
    record_id uuid,
    source_id uuid,
    raw_ref jsonb,
    role text DEFAULT 'primary'::text NOT NULL,
    raw_table text,
    medium evidence.record_medium,
    agrees boolean,
    note text,
    CONSTRAINT esr_has_source CHECK (((record_id IS NOT NULL) OR (source_id IS NOT NULL) OR (raw_ref IS NOT NULL))),
    CONSTRAINT event_source_record_has_anchor CHECK (((event_id IS NOT NULL) OR (record_id IS NOT NULL))),
    CONSTRAINT event_source_record_role_check CHECK ((role = ANY (ARRAY['primary'::text, 'corroborating'::text, 'context'::text, 'contradicting'::text])))
);


--
-- Name: COLUMN event_source_record.event_id; Type: COMMENT; Schema: working; Owner: -
--

COMMENT ON COLUMN working.event_source_record.event_id IS 'Optional. NULL means this row records an ATTESTATION (a spine record citing a source that attests it) rather than an EVENT citation. Ingest writes attestations with event_id NULL because no timeline_event exists until extraction runs and its candidates pass the HITL gate. Made nullable 2026-08-01 after a real end-to-end run showed the NOT NULL forced either placeholder events or dropped attestations.';


--
-- Name: COLUMN event_source_record.agrees; Type: COMMENT; Schema: working; Owner: -
--

COMMENT ON COLUMN working.event_source_record.agrees IS 'Whether this attestation matches the derived spine row. FALSE is a FINDING, not an error — a screenshot that differs from the export is evidence of alteration. Surfaces via analysis.timeline_event.is_conflicted.';


--
-- Name: extraction_candidate; Type: TABLE; Schema: working; Owner: -
--

CREATE TABLE working.extraction_candidate (
    id uuid DEFAULT uuidv7() CONSTRAINT entity_candidate_id_not_null NOT NULL,
    record_id uuid,
    source_id uuid,
    evidence_hash_id uuid,
    entity_text text CONSTRAINT entity_candidate_entity_text_not_null NOT NULL,
    entity_type text,
    normalized_value text,
    span_start integer,
    span_end integer,
    extractor text CONSTRAINT entity_candidate_extractor_not_null NOT NULL,
    extractor_version text,
    confidence numeric(5,4),
    coref_chain_id text,
    relation_predicate text,
    relation_object text,
    occurred_at timestamp with time zone,
    realized_at timestamp with time zone,
    review_status text DEFAULT 'pending'::text CONSTRAINT entity_candidate_review_status_not_null NOT NULL,
    reviewed_by text,
    reviewed_at timestamp with time zone,
    review_note text,
    consumed_by text[] DEFAULT '{}'::text[] CONSTRAINT entity_candidate_consumed_by_not_null NOT NULL,
    dedupe_key text GENERATED ALWAYS AS (((((((((COALESCE((record_id)::text, ''::text) || '|'::text) || extractor) || '|'::text) || COALESCE((span_start)::text, ''::text)) || '|'::text) || COALESCE((span_end)::text, ''::text)) || '|'::text) || entity_text)) STORED,
    extracted_at timestamp with time zone DEFAULT now() CONSTRAINT entity_candidate_extracted_at_not_null NOT NULL,
    created_at timestamp with time zone DEFAULT now() CONSTRAINT entity_candidate_created_at_not_null NOT NULL,
    extraction_batch_id uuid,
    candidate_kind text DEFAULT 'entity'::text NOT NULL,
    target_table text,
    target_id uuid,
    payload jsonb,
    CONSTRAINT entity_candidate_confidence_check CHECK (((confidence IS NULL) OR ((confidence >= (0)::numeric) AND (confidence <= (1)::numeric)))),
    CONSTRAINT entity_candidate_review_status_check CHECK ((review_status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text, 'needs_info'::text]))),
    CONSTRAINT extraction_candidate_candidate_kind_check CHECK ((candidate_kind = ANY (ARRAY['entity'::text, 'event'::text, 'place'::text, 'relation'::text, 'claim'::text])))
);


--
-- Name: TABLE extraction_candidate; Type: COMMENT; Schema: working; Owner: -
--

COMMENT ON TABLE working.extraction_candidate IS 'SUPERSEDED by working.candidate_entity / candidate_fact / candidate_event (sql/0016, 2026-08-02). Was empty at supersession. Do not write here.';


--
-- Name: COLUMN extraction_candidate.candidate_kind; Type: COMMENT; Schema: working; Owner: -
--

COMMENT ON COLUMN working.extraction_candidate.candidate_kind IS 'entity | event | place | relation | claim. Routes an approved candidate to its destination (analysis.entity, timeline_event, location, ...). Deception/"lies" is deliberately NOT a kind — that is contradiction detection across records, computed over the assembled timeline, not extraction from a single message.';


--
-- Name: message_participant; Type: TABLE; Schema: working; Owner: -
--

CREATE TABLE working.message_participant (
    id uuid DEFAULT uuidv7() NOT NULL,
    message_id uuid NOT NULL,
    entity_id uuid,
    participant_raw text,
    participant_e164 text,
    role text NOT NULL,
    conduct_party ai.conduct_party,
    derived_from_raw_id uuid,
    deriver_version text,
    CONSTRAINT message_participant_role_check CHECK ((role = ANY (ARRAY['from'::text, 'to'::text, 'cc'::text, 'bcc'::text, 'group'::text, 'third_party'::text])))
);


--
-- Name: normalized_record; Type: TABLE; Schema: working; Owner: -
--

CREATE TABLE working.normalized_record (
    id uuid DEFAULT uuidv7() NOT NULL,
    artifact_id uuid NOT NULL,
    record_type text NOT NULL,
    source text NOT NULL,
    conversation_id text,
    role text,
    participants jsonb DEFAULT '[]'::jsonb NOT NULL,
    content text DEFAULT ''::text NOT NULL,
    occurred_at timestamp with time zone,
    knowledge_time timestamp with time zone DEFAULT now() NOT NULL,
    disclosure_tier text DEFAULT 'contemporaneous'::text NOT NULL,
    attrs jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    conversation_ref uuid,
    ts_precision ai.precision_class DEFAULT 'exact'::ai.precision_class NOT NULL,
    sensitivity_tier ai.sensitivity_tier,
    data_tier ai.evidence_tier DEFAULT 'extracted'::ai.evidence_tier NOT NULL,
    review_status ai.review_state DEFAULT 'unreviewed'::ai.review_state NOT NULL,
    safe_for_legal_use boolean DEFAULT false NOT NULL,
    provenance_id uuid,
    export_created_at timestamp with time zone,
    acquired_at timestamp with time zone,
    ingested_at timestamp with time zone DEFAULT now() NOT NULL,
    realized_at timestamp with time zone,
    realized_evidence jsonb,
    acquisition_id uuid,
    device_id uuid,
    sender_entity_id uuid,
    derived_from_raw_table text,
    derived_from_raw_id uuid,
    deriver_version text,
    derived_at timestamp with time zone,
    attestation_count integer DEFAULT 0 NOT NULL,
    case_id text DEFAULT 'primary'::text NOT NULL,
    domain text DEFAULT 'evidence'::text NOT NULL,
    topic_tags text[] DEFAULT '{}'::text[] NOT NULL,
    knowledge_actor text DEFAULT 'owner'::text NOT NULL,
    ontology_version text,
    CONSTRAINT normalized_record_case_id_ck CHECK ((length(case_id) > 0)),
    CONSTRAINT normalized_record_disclosure_tier_check CHECK ((disclosure_tier = ANY (ARRAY['contemporaneous'::text, 'hindsight'::text, 'discovered'::text]))),
    CONSTRAINT normalized_record_domain_ck CHECK ((domain = ANY (ARRAY['evidence'::text, 'legal'::text, 'behavioral'::text, 'platform_design'::text, 'context'::text]))),
    CONSTRAINT normalized_record_record_type_check CHECK ((record_type = ANY (ARRAY['message'::text, 'call'::text, 'event'::text, 'media'::text])))
);


--
-- Name: COLUMN normalized_record.knowledge_time; Type: COMMENT; Schema: working; Owner: -
--

COMMENT ON COLUMN working.normalized_record.knowledge_time IS 'SUPERSEDED 2026-08-01 by realized_at/acquired_at/ingested_at. Because of its DEFAULT NOW() this column records row-write time, NOT when the party learned the fact. Retained so existing rows keep their original meaning. Do not use for "when did you know" questions.';


--
-- Name: COLUMN normalized_record.realized_at; Type: COMMENT; Schema: working; Owner: -
--

COMMENT ON COLUMN working.normalized_record.realized_at IS 'When the party actually understood the significance. NULL = not yet established. HITL-confirmed; may be PROPOSED by matching against the AI-chat corpus (which dates when things were first said out loud) but never auto-committed.';


--
-- Name: COLUMN normalized_record.sender_entity_id; Type: COMMENT; Schema: working; Owner: -
--

COMMENT ON COLUMN working.normalized_record.sender_entity_id IS 'Resolved sender. For outbound records this is the device owner AT occurred_at per analysis.device_ownership — NOT the current owner. NULL until resolved; the HITL identity gate forbids guessing an ambiguous participant.';


--
-- Name: COLUMN normalized_record.attestation_count; Type: COMMENT; Schema: working; Owner: -
--

COMMENT ON COLUMN working.normalized_record.attestation_count IS 'How many distinct raw attestations support this one spine row. >1 means the same message was captured by multiple devices/mediums — corroboration, not duplication. Maintained from analysis.event_source_record.';


--
-- Name: person; Type: TABLE; Schema: working; Owner: -
--

CREATE TABLE working.person (
    id uuid NOT NULL,
    relationship_type text,
    connection_to text,
    role_in_case text,
    gender text,
    is_minor boolean DEFAULT false NOT NULL,
    is_flagged boolean DEFAULT false NOT NULL,
    notes text,
    CONSTRAINT person_connection_to_check CHECK ((connection_to = ANY (ARRAY['petitioner'::text, 'respondent'::text, 'child'::text, 'mutual'::text, 'third_party'::text, 'unknown'::text]))),
    CONSTRAINT person_role_in_case_check CHECK ((role_in_case = ANY (ARRAY['user'::text, 'partner'::text, 'child'::text, 'witness'::text, 'evaluator'::text, 'attorney'::text, 'third_party'::text, 'neutral'::text, 'unknown'::text])))
);


--
-- Name: record_observation; Type: TABLE; Schema: working; Owner: -
--

CREATE TABLE working.record_observation (
    id uuid DEFAULT uuidv7() NOT NULL,
    record_id uuid NOT NULL,
    kind text NOT NULL,
    value_text text,
    value_num numeric,
    scale text,
    confidence numeric(5,4),
    observer text NOT NULL,
    observer_version text,
    prompt_version text,
    evidence jsonb,
    review_status text DEFAULT 'unreviewed'::text NOT NULL,
    safe_for_legal_use boolean DEFAULT false NOT NULL,
    observed_at timestamp with time zone DEFAULT now() NOT NULL,
    dedupe_key text GENERATED ALWAYS AS ((((((((record_id)::text || '|'::text) || kind) || '|'::text) || observer) || '|'::text) || COALESCE(observer_version, ''::text))) STORED,
    extraction_batch_id uuid,
    CONSTRAINT record_observation_confidence_check CHECK (((confidence IS NULL) OR ((confidence >= (0)::numeric) AND (confidence <= (1)::numeric)))),
    CONSTRAINT record_observation_review_status_check CHECK ((review_status = ANY (ARRAY['unreviewed'::text, 'approved'::text, 'rejected'::text])))
);


--
-- Name: TABLE record_observation; Type: COMMENT; Schema: working; Owner: -
--

COMMENT ON TABLE working.record_observation IS 'SUPERSEDED by the working.candidate_* family + working.review_decision (sql/0016, 2026-08-02). Was empty at supersession. Do not write here.';


--
-- Name: vw_layer_map; Type: VIEW; Schema: evidence; Owner: -
--

CREATE VIEW evidence.vw_layer_map AS
 SELECT sort_order,
    layer_role,
    table_name,
    rebuild_cost,
    what_it_holds,
    live_rows
   FROM ( VALUES (10,'RAW'::text,'evidence.raw_sms'::text,'re-parse originals'::text,'SMS/MMS/call export records'::text,( SELECT count(*) AS count
                   FROM evidence.raw_sms)), (11,'RAW'::text,'evidence.raw_imessage'::text,'re-parse originals'::text,'iMessage export records'::text,( SELECT count(*) AS count
                   FROM evidence.raw_imessage)), (12,'RAW'::text,'evidence.raw_facebook'::text,'re-parse originals'::text,'Facebook/Messenger records'::text,( SELECT count(*) AS count
                   FROM evidence.raw_facebook)), (13,'RAW'::text,'evidence.raw_ai_chat'::text,'re-parse originals'::text,'AI chat transcript records'::text,( SELECT count(*) AS count
                   FROM evidence.raw_ai_chat)), (14,'RAW'::text,'evidence.raw_csv'::text,'re-parse originals'::text,'Tabular export records'::text,( SELECT count(*) AS count
                   FROM evidence.raw_csv)), (15,'RAW'::text,'evidence.raw_phone'::text,'re-parse originals'::text,'Phone/device log records'::text,( SELECT count(*) AS count
                   FROM evidence.raw_phone)), (20,'SPINE'::text,'working.normalized_record'::text,'re-derive from raw'::text,'One row per real-world record'::text,( SELECT count(*) AS count
                   FROM working.normalized_record)), (30,'PROJECTION'::text,'working.message'::text,'re-derive from raw'::text,'Message view of the spine'::text,( SELECT count(*) AS count
                   FROM working.message)), (31,'PROJECTION'::text,'working.message_participant'::text,'re-derive from raw'::text,'Per-message participants'::text,( SELECT count(*) AS count
                   FROM working.message_participant)), (32,'PROJECTION'::text,'working.conversation'::text,'re-derive from raw'::text,'Conversation groupings'::text,( SELECT count(*) AS count
                   FROM working.conversation)), (33,'PROJECTION'::text,'working.attachment'::text,'re-derive from raw'::text,'Attachments'::text,( SELECT count(*) AS count
                   FROM working.attachment)), (34,'PROJECTION'::text,'working.call_log'::text,'re-derive from raw'::text,'Call records'::text,( SELECT count(*) AS count
                   FROM working.call_log)), (40,'LINK'::text,'working.event_source_record'::text,'re-derive from raw'::text,'Attestations + event citations'::text,( SELECT count(*) AS count
                   FROM working.event_source_record)), (41,'ENTITY'::text,'working.entity'::text,'re-run extraction'::text,'Resolved entities'::text,( SELECT count(*) AS count
                   FROM working.entity)), (42,'ENTITY'::text,'working.person'::text,'re-run extraction'::text,'Resolved people'::text,( SELECT count(*) AS count
                   FROM working.person)), (43,'ENTITY'::text,'working.device'::text,'HITL + extraction'::text,'Devices'::text,( SELECT count(*) AS count
                   FROM working.device)), (50,'STAGING'::text,'working.extraction_candidate'::text,'re-run extraction'::text,'Extraction output, pre-gate'::text,( SELECT count(*) AS count
                   FROM working.extraction_candidate)), (51,'STAGING'::text,'working.record_observation'::text,'re-run observers'::text,'Model/human observations'::text,( SELECT count(*) AS count
                   FROM working.record_observation)), (60,'REFERENCE'::text,'reference.detection_pattern'::text,'re-seed from source'::text,'Detection patterns'::text,( SELECT count(*) AS count
                   FROM reference.detection_pattern)), (61,'REFERENCE'::text,'reference.behavior_category'::text,'re-seed from source'::text,'Behaviour taxonomy'::text,( SELECT count(*) AS count
                   FROM reference.behavior_category)), (62,'REFERENCE'::text,'reference.behavior_category_mcl'::text,'re-seed from source'::text,'MCL 722.23 factor mapping'::text,( SELECT count(*) AS count
                   FROM reference.behavior_category_mcl)), (63,'REFERENCE'::text,'reference.pattern_lexicon'::text,'re-seed from source'::text,'Imported lexicons'::text,( SELECT count(*) AS count
                   FROM reference.pattern_lexicon)), (64,'REFERENCE'::text,'reference.custody_factor'::text,'re-seed from source'::text,'Custody factors'::text,( SELECT count(*) AS count
                   FROM reference.custody_factor)), (65,'REFERENCE'::text,'reference.topic_code'::text,'re-seed from source'::text,'Topic codes'::text,( SELECT count(*) AS count
                   FROM reference.topic_code)), (70,'FINDING'::text,'analysis.finding'::text,'not rebuildable'::text,'Reviewed findings'::text,( SELECT count(*) AS count
                   FROM analysis.finding)), (71,'FINDING'::text,'analysis.pattern_finding'::text,'re-run detection'::text,'Pattern hits'::text,( SELECT count(*) AS count
                   FROM analysis.pattern_finding)), (72,'FINDING'::text,'analysis.timeline_event'::text,'HITL-gated'::text,'Timeline events'::text,( SELECT count(*) AS count
                   FROM analysis.timeline_event)), (73,'FINDING'::text,'analysis.review_decision'::text,'not rebuildable'::text,'Human review decisions'::text,( SELECT count(*) AS count
                   FROM analysis.review_decision)), (80,'GOLD'::text,'analysis.human_label_gold'::text,'not rebuildable'::text,'Hand-labelled gold set (FK-free)'::text,( SELECT count(*) AS count
                   FROM analysis.human_label_gold)), (90,'LEDGER'::text,'evidence.source'::text,'append-only'::text,'Artifacts ingested (per file)'::text,( SELECT count(*) AS count
                   FROM evidence.source)), (91,'LEDGER'::text,'evidence.acquisition'::text,'append-only'::text,'How evidence was acquired'::text,( SELECT count(*) AS count
                   FROM evidence.acquisition)), (92,'LEDGER'::text,'evidence.artifact_metadata'::text,'append-only'::text,'File + embedded metadata'::text,( SELECT count(*) AS count
                   FROM evidence.artifact_metadata)), (93,'LEDGER'::text,'evidence.evidence_hash'::text,'append-only'::text,'Custody hashes (H1/H2/H3)'::text,( SELECT count(*) AS count
                   FROM evidence.evidence_hash)), (94,'LEDGER'::text,'evidence.ingest_run'::text,'append-only'::text,'Ingest attempts incl. failures'::text,( SELECT count(*) AS count
                   FROM evidence.ingest_run)), (95,'REJECTED'::text,'evidence.raw_rejected'::text,'append-only'::text,'Records a parser refused'::text,( SELECT count(*) AS count
                   FROM evidence.raw_rejected)), (99,'OPS'::text,'ops.workflow_run'::text,'prunable'::text,'Workflow run ledger'::text,( SELECT count(*) AS count
                   FROM ops.workflow_run)), (100,'OPS'::text,'ops.processing_run'::text,'prunable'::text,'Processing runs'::text,( SELECT count(*) AS count
                   FROM ops.processing_run)), (101,'OPS'::text,'ops.tool_call_ledger'::text,'prunable'::text,'Tool-call log'::text,( SELECT count(*) AS count
                   FROM ops.tool_call_ledger))) t(sort_order, layer_role, table_name, rebuild_cost, what_it_holds, live_rows);


--
-- Name: VIEW vw_layer_map; Type: COMMENT; Schema: evidence; Owner: -
--

COMMENT ON VIEW evidence.vw_layer_map IS 'Every layer with its architectural role, live row count, and REBUILD COST - the property that actually separates the layers. RAW rebuild means re-parsing the original files; working rebuild reads RAW only; reference is re-seeded, not derived; findings and human labels are not rebuildable at all.';


--
-- Name: vw_pipeline_funnel; Type: VIEW; Schema: evidence; Owner: -
--

CREATE VIEW evidence.vw_pipeline_funnel AS
 SELECT s.id AS source_id,
    s.original_filename,
    s.source_type,
    s.byte_size,
    encode(s.sha256, 'hex'::text) AS h1,
    am.record_count_claimed AS claimed,
    ( SELECT count(*) AS count
           FROM evidence.vw_raw_all r
          WHERE (r.source_id = s.id)) AS raw_rows,
    ( SELECT count(DISTINCT r.raw_table) AS count
           FROM evidence.vw_raw_all r
          WHERE (r.source_id = s.id)) AS raw_tables_used,
    ( SELECT count(*) AS count
           FROM evidence.vw_raw_all r
          WHERE ((r.source_id = s.id) AND (r.superseded_by IS NOT NULL))) AS raw_superseded,
    ( SELECT count(*) AS count
           FROM evidence.raw_rejected j
          WHERE (j.source_sha256 = s.sha256)) AS rejected,
    ( SELECT count(*) AS count
           FROM (working.normalized_record nr
             JOIN evidence.vw_raw_all r ON ((r.id = nr.derived_from_raw_id)))
          WHERE (r.source_id = s.id)) AS spine_rows,
    ( SELECT count(*) AS count
           FROM working.event_source_record e
          WHERE (e.source_id = s.id)) AS attestations,
    am.resolved_export_at,
    am.layer_disagreement,
    s.ingested_at
   FROM (evidence.source s
     LEFT JOIN evidence.artifact_metadata am ON ((am.source_id = s.id)));


--
-- Name: VIEW vw_pipeline_funnel; Type: COMMENT; Schema: evidence; Owner: -
--

COMMENT ON VIEW evidence.vw_pipeline_funnel IS 'Per artifact and across ALL raw formats: what it claimed, what landed in raw, what was rejected, what was derived to the spine, and how many attestations exist. claimed = raw_rows + rejected is the reconciliation.';


--
-- Name: vw_reconciliation; Type: VIEW; Schema: evidence; Owner: -
--

CREATE VIEW evidence.vw_reconciliation AS
 SELECT source_id,
    original_filename,
    claimed,
    raw_rows,
    rejected,
    spine_rows,
    (raw_rows + rejected) AS accounted_for,
    (COALESCE(claimed, 0) - (raw_rows + rejected)) AS unexplained,
        CASE
            WHEN (claimed IS NULL) THEN 'NO CLAIM RECORDED'::text
            WHEN (claimed = (raw_rows + rejected)) THEN 'RECONCILED'::text
            WHEN (claimed > (raw_rows + rejected)) THEN 'SHORTFALL - records unaccounted for'::text
            ELSE 'SURPLUS - more records than the artifact claims'::text
        END AS verdict,
        CASE
            WHEN (spine_rows = raw_rows) THEN 'derived'::text
            WHEN (spine_rows < raw_rows) THEN 'UNDER-DERIVED'::text
            ELSE 'OVER-DERIVED - duplicate derivation'::text
        END AS derivation_verdict
   FROM evidence.vw_pipeline_funnel f;


--
-- Name: VIEW vw_reconciliation; Type: COMMENT; Schema: evidence; Owner: -
--

COMMENT ON VIEW evidence.vw_reconciliation IS 'One verdict per artifact. RECONCILED means every record the artifact claims is either in raw or explicitly recorded as rejected. NO CLAIM RECORDED means the artifact never had its self-declared count captured - the reconciliation cannot be performed at all, which is a gap, not a pass.';


--
-- Name: vw_source_acquisition; Type: VIEW; Schema: evidence; Owner: -
--

CREATE VIEW evidence.vw_source_acquisition AS
 SELECT s.id AS source_id,
    s.original_filename,
    s.sha256,
    s.acquisition_source AS file_acquisition_source,
    s.acquisition_method AS file_acquisition_method,
    s.custodian AS file_custodian,
    s.acquired_at_utc AS file_acquired_at,
    s.provenance_tier,
    a.id AS acquisition_id,
    a.method AS event_method,
    a.authority AS event_authority,
    a.device_custodian AS event_custodian,
    a.acquired_at AS event_acquired_at,
    a.export_created_at,
    a.producible,
        CASE
            WHEN (a.id IS NULL) THEN 'no_acquisition_event'::text
            WHEN (s.acquisition_method IS DISTINCT FROM (a.method)::text) THEN 'METHOD_DIVERGES'::text
            WHEN ((s.acquired_at_utc IS NOT NULL) AND (a.acquired_at IS NOT NULL) AND (abs(EXTRACT(epoch FROM (s.acquired_at_utc - a.acquired_at))) > (86400)::numeric)) THEN 'ACQUIRED_AT_DIVERGES'::text
            ELSE 'consistent'::text
        END AS reconciliation_status
   FROM (evidence.source s
     LEFT JOIN evidence.acquisition a ON ((a.id = s.acquisition_id)));


--
-- Name: VIEW vw_source_acquisition; Type: COMMENT; Schema: evidence; Owner: -
--

COMMENT ON VIEW evidence.vw_source_acquisition IS 'Reconciles the PER-FILE acquisition columns on evidence.source (live, written by custody.py at ingest) against the PER-EVENT evidence.acquisition row. These are different grains, not duplicates: one export session or device handoff covers many files. reconciliation_status flags divergence; no_acquisition_event means the file predates the acquisition intake form and needs one.';


--
-- Name: geocode_audit; Type: TABLE; Schema: ops; Owner: -
--

CREATE TABLE ops.geocode_audit (
    id uuid DEFAULT uuidv7() NOT NULL,
    request_id uuid,
    action text NOT NULL,
    actor_kind text,
    detail jsonb DEFAULT '{}'::jsonb NOT NULL,
    occurred_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: workflow_run_stage; Type: TABLE; Schema: ops; Owner: -
--

CREATE TABLE ops.workflow_run_stage (
    stage_id bigint NOT NULL,
    run_id uuid NOT NULL,
    seq integer NOT NULL,
    name text NOT NULL,
    status text DEFAULT 'pending'::text NOT NULL,
    content text,
    output jsonb,
    started_at timestamp with time zone,
    finished_at timestamp with time zone,
    CONSTRAINT workflow_run_stage_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'running'::text, 'success'::text, 'failed'::text, 'skipped'::text])))
);


--
-- Name: workflow_run_stage_stage_id_seq; Type: SEQUENCE; Schema: ops; Owner: -
--

ALTER TABLE ops.workflow_run_stage ALTER COLUMN stage_id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME ops.workflow_run_stage_stage_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: agent_run; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.agent_run (
    id uuid DEFAULT uuidv7() NOT NULL,
    agent_name text NOT NULL,
    run_type text NOT NULL,
    status text NOT NULL,
    user_prompt text NOT NULL,
    summarized_plan text,
    approval_required boolean DEFAULT true NOT NULL,
    started_at timestamp with time zone DEFAULT now() NOT NULL,
    completed_at timestamp with time zone,
    error_message text,
    CONSTRAINT agent_run_run_type_check CHECK ((run_type = ANY (ARRAY['platform'::text, 'builder'::text]))),
    CONSTRAINT agent_run_status_check CHECK ((status = ANY (ARRAY['queued'::text, 'running'::text, 'awaiting_approval'::text, 'completed'::text, 'failed'::text, 'cancelled'::text])))
);


--
-- Name: app_setting; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.app_setting (
    key text NOT NULL,
    value jsonb NOT NULL,
    value_type text DEFAULT 'json'::text NOT NULL,
    description text,
    updated_by text,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: TABLE app_setting; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.app_setting IS 'Versionable key/value config (clustering thresholds, etc.).';


--
-- Name: approval_request; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.approval_request (
    id uuid DEFAULT uuidv7() NOT NULL,
    agent_run_id uuid,
    run_id uuid,
    paused_tool text,
    requested_action text NOT NULL,
    requested_by_agent text NOT NULL,
    risk_level text NOT NULL,
    approval_status text DEFAULT 'pending'::text NOT NULL,
    requested_at timestamp with time zone DEFAULT now() NOT NULL,
    decided_at timestamp with time zone,
    decided_by text,
    decision_notes text,
    CONSTRAINT approval_request_approval_status_check CHECK ((approval_status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text, 'expired'::text]))),
    CONSTRAINT approval_request_risk_level_check CHECK ((risk_level = ANY (ARRAY['low'::text, 'medium'::text, 'high'::text, 'critical'::text])))
);


--
-- Name: canon_registry; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.canon_registry (
    id uuid DEFAULT uuidv7() NOT NULL,
    canon_name text NOT NULL,
    family text NOT NULL,
    status text DEFAULT 'active'::text NOT NULL,
    recipe text NOT NULL,
    reference_impl text,
    test_vectors jsonb DEFAULT '[]'::jsonb NOT NULL,
    notes text,
    established_at timestamp with time zone DEFAULT now() NOT NULL,
    superseded_by uuid,
    CONSTRAINT canon_registry_status_check CHECK ((status = ANY (ARRAY['active'::text, 'superseded'::text, 'lost'::text])))
);


--
-- Name: TABLE canon_registry; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.canon_registry IS 'Every algorithm/recipe that produces durable artifacts, as data with test vectors. NEVER change a recipe in place — add a new canon_name version and mark the old one superseded.';


--
-- Name: change_log; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.change_log (
    seq bigint NOT NULL,
    change_id uuid DEFAULT uuidv7() NOT NULL,
    table_name text NOT NULL,
    record_id uuid,
    field_name text,
    action text NOT NULL,
    previous_value text,
    new_value text,
    actor text NOT NULL,
    change_origin text NOT NULL,
    reason text,
    related_run_id uuid,
    related_decision_id uuid,
    detail jsonb,
    prev_change_hash bytea,
    row_hash bytea NOT NULL,
    change_timestamp timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT change_log_change_origin_check CHECK ((change_origin = ANY (ARRAY['model_generated'::text, 'human_approved'::text, 'system'::text])))
);


--
-- Name: change_log_seq_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.change_log ALTER COLUMN seq ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.change_log_seq_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: classification_version; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.classification_version (
    classification_version_id uuid DEFAULT uuidv7() NOT NULL,
    version_label text NOT NULL,
    scheme text NOT NULL,
    label_set jsonb DEFAULT '[]'::jsonb NOT NULL,
    source text NOT NULL,
    definition_uri text,
    definition_hash bytea,
    supersedes uuid,
    review_status text DEFAULT 'pending'::text NOT NULL,
    notes text,
    created_by text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT classification_version_review_status_check CHECK ((review_status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text])))
);


--
-- Name: decision_log; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.decision_log (
    decision_id uuid DEFAULT uuidv7() NOT NULL,
    decision_title text NOT NULL,
    decision_type text NOT NULL,
    context text,
    options_considered jsonb DEFAULT '[]'::jsonb NOT NULL,
    decision_made text NOT NULL,
    reasoning_summary text,
    evidence_or_artifacts_considered jsonb DEFAULT '[]'::jsonb NOT NULL,
    owner text NOT NULL,
    reversibility text,
    related_risks text,
    related_open_questions uuid[] DEFAULT '{}'::uuid[] NOT NULL,
    supersedes uuid,
    review_status text DEFAULT 'none'::text NOT NULL,
    decided_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT decision_log_decision_type_check CHECK ((decision_type = ANY (ARRAY['schema'::text, 'ontology'::text, 'legal_relevance'::text, 'evidence_classification'::text, 'tooling'::text, 'storage'::text, 'privacy'::text, 'export'::text, 'human_review'::text]))),
    CONSTRAINT decision_log_reversibility_check CHECK ((reversibility = ANY (ARRAY['reversible'::text, 'costly'::text, 'irreversible'::text]))),
    CONSTRAINT decision_log_review_status_check CHECK ((review_status = ANY (ARRAY['none'::text, 'pending'::text, 'approved'::text, 'rejected'::text])))
);


--
-- Name: decision_precedent; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.decision_precedent (
    precedent_id uuid DEFAULT uuidv7() NOT NULL,
    decision_id uuid NOT NULL,
    source_decision_id uuid NOT NULL,
    similarity_score ai.confidence,
    relationship_type text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT decision_precedent_relationship_type_check CHECK ((relationship_type = ANY (ARRAY['similar_scenario'::text, 'same_policy'::text, 'exception_precedent'::text])))
);


--
-- Name: memory_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.memory_items (
    memory_id uuid DEFAULT uuidv7() NOT NULL,
    memory_type text NOT NULL,
    title text NOT NULL,
    summary text,
    content_inline text,
    content_uri text,
    content_hash bytea,
    source_of_memory text,
    created_by text NOT NULL,
    confidence ai.confidence,
    assertion_type ai.assertion_type,
    status text DEFAULT 'active'::text NOT NULL,
    review_status text DEFAULT 'none'::text NOT NULL,
    is_sensitive boolean DEFAULT false NOT NULL,
    mirror_store ai.source_system,
    superseded_by uuid,
    related_artifact_ids uuid[] DEFAULT '{}'::uuid[] NOT NULL,
    related_evidence_ids uuid[] DEFAULT '{}'::uuid[] NOT NULL,
    related_ontology_id uuid,
    related_schema_id uuid,
    tags jsonb DEFAULT '[]'::jsonb NOT NULL,
    fts tsvector GENERATED ALWAYS AS (to_tsvector('english'::regconfig, ((COALESCE(title, ''::text) || ' '::text) || COALESCE(summary, ''::text)))) STORED,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT memory_items_memory_type_check CHECK ((memory_type = ANY (ARRAY['user_preference'::text, 'project_fact'::text, 'evidence_fact'::text, 'hypothesis'::text, 'analysis_finding'::text, 'design_decision'::text, 'open_question'::text, 'warning'::text, 'artifact_summary'::text, 'run_summary'::text, 'deprecated_memory'::text]))),
    CONSTRAINT memory_items_review_status_check CHECK ((review_status = ANY (ARRAY['none'::text, 'pending'::text, 'approved'::text, 'rejected'::text]))),
    CONSTRAINT memory_items_status_check CHECK ((status = ANY (ARRAY['active'::text, 'draft'::text, 'needs_review'::text, 'superseded'::text, 'deprecated'::text, 'rejected'::text, 'archived'::text])))
);


--
-- Name: model_version; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.model_version (
    model_version_id uuid DEFAULT uuidv7() NOT NULL,
    provider text,
    model_id text NOT NULL,
    role text NOT NULL,
    version text,
    dims integer,
    ran_local_capable boolean DEFAULT false NOT NULL,
    params jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT model_version_role_check CHECK ((role = ANY (ARRAY['llm'::text, 'embedder'::text, 'reranker'::text, 'ocr'::text, 'asr'::text])))
);


--
-- Name: ontology_version; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ontology_version (
    ontology_version_id uuid DEFAULT uuidv7() NOT NULL,
    version_label text NOT NULL,
    source text NOT NULL,
    definition_uri text,
    definition_hash bytea,
    node_types jsonb DEFAULT '[]'::jsonb NOT NULL,
    edge_types jsonb DEFAULT '[]'::jsonb NOT NULL,
    supersedes uuid,
    review_status text DEFAULT 'pending'::text NOT NULL,
    notes text,
    created_by text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT ontology_version_review_status_check CHECK ((review_status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text])))
);


--
-- Name: open_questions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.open_questions (
    question_id uuid DEFAULT uuidv7() NOT NULL,
    question_text text NOT NULL,
    category text NOT NULL,
    raised_by text,
    status text DEFAULT 'open'::text NOT NULL,
    answer_summary text,
    answered_by text,
    answered_at timestamp with time zone,
    related_run_id uuid,
    related_artifact_ids uuid[] DEFAULT '{}'::uuid[] NOT NULL,
    blocks_export boolean DEFAULT false NOT NULL,
    requires_corroboration boolean DEFAULT false NOT NULL,
    priority integer DEFAULT 3 NOT NULL,
    raised_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT open_questions_category_check CHECK ((category = ANY (ARRAY['data_gap'::text, 'schema'::text, 'ontology'::text, 'legal_relevance'::text, 'corroboration_needed'::text, 'privacy'::text, 'technical'::text]))),
    CONSTRAINT open_questions_status_check CHECK ((status = ANY (ARRAY['open'::text, 'investigating'::text, 'answered'::text, 'wont_fix'::text, 'superseded'::text])))
);


--
-- Name: prompt_registry; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.prompt_registry (
    prompt_id uuid DEFAULT uuidv7() NOT NULL,
    prompt_name text NOT NULL,
    prompt_version text NOT NULL,
    prompt_type text NOT NULL,
    full_prompt_text text NOT NULL,
    body_sha256 bytea NOT NULL,
    purpose text,
    inputs_expected text,
    outputs_expected text,
    known_limitations text,
    safety_constraints text,
    human_approval_required boolean DEFAULT false NOT NULL,
    superseded_by uuid,
    status text DEFAULT 'active'::text NOT NULL,
    created_by text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT prompt_registry_prompt_type_check CHECK ((prompt_type = ANY (ARRAY['extraction'::text, 'classification'::text, 'summary'::text, 'agent_instruction'::text, 'tone_style'::text, 'review'::text, 'export'::text]))),
    CONSTRAINT prompt_registry_status_check CHECK ((status = ANY (ARRAY['active'::text, 'superseded'::text, 'deprecated'::text])))
);


--
-- Name: schema_version; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_version (
    schema_version_id uuid DEFAULT uuidv7() NOT NULL,
    version_label text NOT NULL,
    applies_to text NOT NULL,
    ddl_uri text,
    ddl_hash bytea,
    migration_id text,
    supersedes uuid,
    status text DEFAULT 'active'::text NOT NULL,
    notes text,
    created_by text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT schema_version_status_check CHECK ((status = ANY (ARRAY['active'::text, 'superseded'::text, 'deprecated'::text])))
);


--
-- Name: session_summaries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.session_summaries (
    session_id uuid DEFAULT uuidv7() NOT NULL,
    session_start timestamp with time zone NOT NULL,
    session_end timestamp with time zone,
    user_goal text,
    work_completed text,
    files_inspected jsonb DEFAULT '[]'::jsonb NOT NULL,
    artifacts_created jsonb DEFAULT '[]'::jsonb NOT NULL,
    decisions_made uuid[] DEFAULT '{}'::uuid[] NOT NULL,
    open_questions uuid[] DEFAULT '{}'::uuid[] NOT NULL,
    next_actions text,
    blockers text,
    tone_preference_notes text,
    important_warnings text,
    related_run_ids uuid[] DEFAULT '{}'::uuid[] NOT NULL,
    fts tsvector GENERATED ALWAYS AS (to_tsvector('english'::regconfig, ((COALESCE(user_goal, ''::text) || ' '::text) || COALESCE(work_completed, ''::text)))) STORED,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: transcript_insight; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.transcript_insight (
    id uuid DEFAULT uuidv7() NOT NULL,
    source_file text NOT NULL,
    platform text,
    insight_type text NOT NULL,
    content text NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    mined_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: vw_event_evidence_package; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.vw_event_evidence_package AS
 SELECT e.event_id,
    e.serial_id,
    e.title,
    e.event_type,
    ta.valid_earliest,
    ta.valid_latest,
    ta.valid_point,
    ta.ts_utc,
    ta.certainty,
    ta.assertion_type,
    ta.confidence,
    ta.disclosure_horizon,
        CASE
            WHEN ((ta.certainty = 'exact'::ai.precision_class) AND ((ta.confidence)::numeric >= 0.80)) THEN 'HIGH'::text
            WHEN ((ta.certainty = 'approximate'::ai.precision_class) AND ((ta.confidence)::numeric >= 0.60)) THEN 'MEDIUM'::text
            ELSE 'LOW'::text
        END AS temporal_confidence_tier,
    e.mcl_relevance,
    e.source_artifact_id,
    ta.reasoning
   FROM (analysis.timeline_event e
     JOIN analysis.time_assertion ta ON (((ta.event_id = e.event_id) AND upper_inf(ta.sys_period))))
  WHERE (e.safe_for_legal_use AND (NOT e.requires_human_review) AND (NOT ta.requires_human_review));


--
-- Name: vw_llm_cost_rollup; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.vw_llm_cost_rollup AS
 SELECT date_trunc('day'::text, created_at) AS day,
    tool_name,
    tool_category,
    count(*) AS calls,
    sum(cost_estimate) AS total_cost,
    sum(runtime_ms) AS total_ms
   FROM ops.tool_call_ledger
  GROUP BY (date_trunc('day'::text, created_at)), tool_name, tool_category
  ORDER BY (date_trunc('day'::text, created_at)) DESC, (sum(cost_estimate)) DESC NULLS LAST;


--
-- Name: vw_prompt_performance; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.vw_prompt_performance AS
 SELECT pr.prompt_name,
    pr.prompt_version,
    count(l.*) AS uses,
    (avg(l.runtime_ms))::numeric(10,1) AS avg_runtime_ms,
    sum(l.cost_estimate) AS total_cost,
    count(*) FILTER (WHERE (l.errors IS NOT NULL)) AS error_count
   FROM (public.prompt_registry pr
     LEFT JOIN ops.tool_call_ledger l ON ((l.prompt_version = pr.prompt_version)))
  GROUP BY pr.prompt_name, pr.prompt_version;


--
-- Name: detection_pattern_set; Type: TABLE; Schema: reference; Owner: -
--

CREATE TABLE reference.detection_pattern_set (
    id uuid DEFAULT uuidv7() NOT NULL,
    name ai.citext NOT NULL,
    version text NOT NULL,
    source text,
    source_artifact text,
    description text,
    is_active boolean DEFAULT false NOT NULL,
    authored_perspective text,
    valid_from timestamp with time zone DEFAULT now() NOT NULL,
    valid_to timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    provenance_id uuid
);


--
-- Name: format_resolver; Type: TABLE; Schema: reference; Owner: -
--

CREATE TABLE reference.format_resolver (
    id uuid DEFAULT uuidv7() NOT NULL,
    source_signature text NOT NULL,
    source_label text,
    source_fields jsonb NOT NULL,
    mappings jsonb NOT NULL,
    target_schema text DEFAULT 'analysis.message'::text NOT NULL,
    ai_model text,
    used_count integer DEFAULT 0 NOT NULL,
    review_status ai.review_state DEFAULT 'unreviewed'::ai.review_state NOT NULL,
    created_by text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: TABLE format_resolver; Type: COMMENT; Schema: reference; Owner: -
--

COMMENT ON TABLE reference.format_resolver IS 'AI-assisted field-mapping registry for unknown message-export formats. mappings[].method records HOW each field was resolved (exact/fuzzy/content/ai) — court-defensibility: a human can see which columns were deterministic vs model-inferred. Seed dict + cascade ported from schema_resolver.py.';


--
-- Name: geofence; Type: TABLE; Schema: reference; Owner: -
--

CREATE TABLE reference.geofence (
    id uuid DEFAULT uuidv7() NOT NULL,
    name text NOT NULL,
    geog public.geography(Polygon,4326) NOT NULL,
    purpose text,
    data_tier ai.evidence_tier DEFAULT 'analytical'::ai.evidence_tier NOT NULL,
    provenance_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT geofence_data_tier_check CHECK ((data_tier = 'analytical'::ai.evidence_tier))
);


--
-- Name: legal_issue; Type: TABLE; Schema: reference; Owner: -
--

CREATE TABLE reference.legal_issue (
    id uuid DEFAULT uuidv7() NOT NULL,
    case_id uuid NOT NULL,
    issue_key text NOT NULL,
    title text NOT NULL,
    description text,
    issue_type text DEFAULT 'custody'::text NOT NULL,
    statutory_basis text,
    weight ai.confidence,
    weight_basis text,
    created_by text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT legal_issue_issue_type_check CHECK ((issue_type = ANY (ARRAY['custody'::text, 'parenting_time'::text, 'support'::text, 'relocation'::text, 'protective_order'::text, 'property'::text, 'contempt'::text, 'other'::text])))
);


--
-- Name: legal_issue_factor; Type: TABLE; Schema: reference; Owner: -
--

CREATE TABLE reference.legal_issue_factor (
    legal_issue_id uuid NOT NULL,
    factor ai.mcl_factor NOT NULL,
    element_note text
);


--
-- Name: lexicon_sync; Type: TABLE; Schema: reference; Owner: -
--

CREATE TABLE reference.lexicon_sync (
    id uuid DEFAULT uuidv7() NOT NULL,
    lexicon text NOT NULL,
    language text DEFAULT 'en'::text NOT NULL,
    version text,
    level text,
    source_url text,
    source_commit text,
    status text DEFAULT 'pending'::text NOT NULL,
    term_count integer,
    error_message text,
    pattern_set_id uuid,
    last_sync_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT lexicon_sync_level_check CHECK (((level IS NULL) OR (level = ANY (ARRAY['conservative'::text, 'inclusive'::text])))),
    CONSTRAINT lexicon_sync_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'syncing'::text, 'success'::text, 'error'::text])))
);


--
-- Name: TABLE lexicon_sync; Type: COMMENT; Schema: reference; Owner: -
--

COMMENT ON TABLE reference.lexicon_sync IS 'External lexicon import provenance. HurtLex pinned v1.2 (valeriobasile/hurtlex); level conservative|inclusive; isCustom terms protected on resync (enforced in importer, not here).';


--
-- Name: relative_rule; Type: TABLE; Schema: reference; Owner: -
--

CREATE TABLE reference.relative_rule (
    rule_id uuid DEFAULT uuidv7() NOT NULL,
    phrase_pattern text NOT NULL,
    resolution_expr text NOT NULL,
    result_certainty ai.precision_class NOT NULL,
    lower_offset interval,
    upper_offset interval,
    config jsonb DEFAULT '{}'::jsonb NOT NULL,
    ontology_version text,
    prompt_version text,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: score_band_config; Type: TABLE; Schema: reference; Owner: -
--

CREATE TABLE reference.score_band_config (
    config_version text NOT NULL,
    bands jsonb NOT NULL,
    effective_from timestamp with time zone DEFAULT now() NOT NULL,
    changed_by text NOT NULL,
    rationale text NOT NULL
);


--
-- Name: account; Type: TABLE; Schema: working; Owner: -
--

CREATE TABLE working.account (
    id uuid NOT NULL,
    platform text NOT NULL,
    account_key ai.citext NOT NULL,
    owner_entity_id uuid
);


--
-- Name: artifact_registry; Type: TABLE; Schema: working; Owner: -
--

CREATE TABLE working.artifact_registry (
    artifact_id uuid DEFAULT uuidv7() NOT NULL,
    artifact_kind text NOT NULL,
    title text,
    format text,
    sha256 bytea NOT NULL,
    path_or_uri text,
    byte_size bigint,
    content_inline text,
    assertion_type ai.assertion_type NOT NULL,
    confidence ai.confidence,
    evidence_strength ai.strength_class,
    timestamp_certainty ai.precision_class,
    is_sensitive boolean DEFAULT false NOT NULL,
    sensitivity_tier ai.sensitivity_tier,
    producing_run uuid,
    parent_artifact_id uuid,
    derived_from_artifact_ids uuid[] DEFAULT '{}'::uuid[] NOT NULL,
    related_source_evidence uuid[] DEFAULT '{}'::uuid[] NOT NULL,
    status text DEFAULT 'draft'::text NOT NULL,
    review_status ai.review_state DEFAULT 'unreviewed'::ai.review_state NOT NULL,
    superseded_by uuid,
    archive_reason text,
    summary_md text,
    metadata_json jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_by text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT artifact_registry_check CHECK (((status <> 'archived'::text) OR (archive_reason IS NOT NULL))),
    CONSTRAINT artifact_registry_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'needs_review'::text, 'active'::text, 'approved'::text, 'promoted'::text, 'rejected'::text, 'superseded'::text, 'archived'::text])))
);


--
-- Name: block_status; Type: TABLE; Schema: working; Owner: -
--

CREATE TABLE working.block_status (
    id uuid DEFAULT uuidv7() NOT NULL,
    target_kind text NOT NULL,
    target_id uuid NOT NULL,
    blocker_entity_id uuid,
    device_id uuid,
    status text DEFAULT 'unknown'::text NOT NULL,
    confidence numeric(5,4),
    effective_from timestamp with time zone NOT NULL,
    effective_to timestamp with time zone,
    basis text,
    inference_signals jsonb,
    evidence_ref uuid,
    asserted_by text DEFAULT 'human'::text NOT NULL,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT block_status_confidence_check CHECK (((confidence IS NULL) OR ((confidence >= (0)::numeric) AND (confidence <= (1)::numeric)))),
    CONSTRAINT block_status_range CHECK (((effective_to IS NULL) OR (effective_to > effective_from))),
    CONSTRAINT block_status_status_check CHECK ((status = ANY (ARRAY['blocked'::text, 'suspected'::text, 'not_blocked'::text, 'unknown'::text]))),
    CONSTRAINT block_status_supported CHECK (((status <> 'suspected'::text) OR (inference_signals IS NOT NULL) OR (basis IS NOT NULL))),
    CONSTRAINT block_status_target_kind_check CHECK ((target_kind = ANY (ARRAY['phone'::text, 'handle'::text, 'entity'::text])))
);


--
-- Name: TABLE block_status; Type: COMMENT; Schema: working; Owner: -
--

COMMENT ON TABLE working.block_status IS 'Time-scoped block state. analysis.phone.is_blocked / handle.is_blocked are untimed booleans that can only report today; this answers "was it blocked WHEN the message was sent", which is the evidentially relevant question. status is 4-valued because a block is usually INFERRED from delivery behaviour, not confirmed.';


--
-- Name: candidate_entity; Type: TABLE; Schema: working; Owner: -
--

CREATE TABLE working.candidate_entity (
    id uuid DEFAULT uuidv7() NOT NULL,
    extraction_run_id uuid NOT NULL,
    source_raw_table text NOT NULL,
    source_raw_id text NOT NULL,
    entity_type text NOT NULL,
    name text NOT NULL,
    normalized_name text NOT NULL,
    confidence double precision,
    attrs jsonb DEFAULT '{}'::jsonb NOT NULL,
    content_sha256 bytea NOT NULL,
    review_state text DEFAULT 'pending'::text NOT NULL,
    promoted_to_table text,
    promoted_to_id text,
    promoted_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    case_id text DEFAULT 'primary'::text NOT NULL,
    domain text DEFAULT 'evidence'::text NOT NULL,
    topic_tags text[] DEFAULT '{}'::text[] NOT NULL,
    knowledge_actor text DEFAULT 'owner'::text NOT NULL,
    ontology_version text,
    knowledge_time timestamp with time zone,
    CONSTRAINT candidate_entity_attrs_check CHECK ((jsonb_typeof(attrs) = 'object'::text)),
    CONSTRAINT candidate_entity_case_id_ck CHECK ((length(case_id) > 0)),
    CONSTRAINT candidate_entity_confidence_check CHECK (((confidence >= (0)::double precision) AND (confidence <= (1)::double precision))),
    CONSTRAINT candidate_entity_content_sha256_check CHECK ((octet_length(content_sha256) = 32)),
    CONSTRAINT candidate_entity_domain_ck CHECK ((domain = ANY (ARRAY['evidence'::text, 'legal'::text, 'behavioral'::text, 'platform_design'::text, 'context'::text]))),
    CONSTRAINT candidate_entity_entity_type_check CHECK ((entity_type = ANY (ARRAY['person'::text, 'organization'::text, 'location'::text, 'device'::text, 'account'::text, 'other'::text]))),
    CONSTRAINT candidate_entity_name_check CHECK ((length(name) > 0)),
    CONSTRAINT candidate_entity_normalized_name_check CHECK ((length(normalized_name) > 0)),
    CONSTRAINT candidate_entity_promotion_is_complete CHECK ((((promoted_at IS NULL) AND (promoted_to_table IS NULL) AND (promoted_to_id IS NULL)) OR ((promoted_at IS NOT NULL) AND (promoted_to_table IS NOT NULL) AND (promoted_to_id IS NOT NULL)))),
    CONSTRAINT candidate_entity_promotion_requires_approval CHECK (((promoted_at IS NULL) OR (review_state = 'approved'::text))),
    CONSTRAINT candidate_entity_review_state_check CHECK ((review_state = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text, 'needs_info'::text, 'superseded'::text])))
);


--
-- Name: candidate_event; Type: TABLE; Schema: working; Owner: -
--

CREATE TABLE working.candidate_event (
    id uuid DEFAULT uuidv7() NOT NULL,
    extraction_run_id uuid NOT NULL,
    source_raw_table text NOT NULL,
    source_raw_id text NOT NULL,
    event_type text NOT NULL,
    summary text NOT NULL,
    occurred_at timestamp with time zone,
    validity tstzrange,
    temporal_confidence double precision,
    primary_entity_id uuid,
    confidence double precision,
    attrs jsonb DEFAULT '{}'::jsonb NOT NULL,
    content_sha256 bytea NOT NULL,
    review_state text DEFAULT 'pending'::text NOT NULL,
    promoted_to_table text,
    promoted_to_id text,
    promoted_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    case_id text DEFAULT 'primary'::text NOT NULL,
    domain text DEFAULT 'evidence'::text NOT NULL,
    topic_tags text[] DEFAULT '{}'::text[] NOT NULL,
    knowledge_actor text DEFAULT 'owner'::text NOT NULL,
    ontology_version text,
    knowledge_time timestamp with time zone,
    CONSTRAINT candidate_event_attrs_check CHECK ((jsonb_typeof(attrs) = 'object'::text)),
    CONSTRAINT candidate_event_case_id_ck CHECK ((length(case_id) > 0)),
    CONSTRAINT candidate_event_confidence_check CHECK (((confidence >= (0)::double precision) AND (confidence <= (1)::double precision))),
    CONSTRAINT candidate_event_content_sha256_check CHECK ((octet_length(content_sha256) = 32)),
    CONSTRAINT candidate_event_domain_ck CHECK ((domain = ANY (ARRAY['evidence'::text, 'legal'::text, 'behavioral'::text, 'platform_design'::text, 'context'::text]))),
    CONSTRAINT candidate_event_event_type_check CHECK ((length(event_type) > 0)),
    CONSTRAINT candidate_event_has_some_time CHECK (((occurred_at IS NOT NULL) OR (validity IS NOT NULL))),
    CONSTRAINT candidate_event_promotion_is_complete CHECK ((((promoted_at IS NULL) AND (promoted_to_table IS NULL) AND (promoted_to_id IS NULL)) OR ((promoted_at IS NOT NULL) AND (promoted_to_table IS NOT NULL) AND (promoted_to_id IS NOT NULL)))),
    CONSTRAINT candidate_event_promotion_requires_approval CHECK (((promoted_at IS NULL) OR (review_state = 'approved'::text))),
    CONSTRAINT candidate_event_review_state_check CHECK ((review_state = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text, 'needs_info'::text, 'superseded'::text]))),
    CONSTRAINT candidate_event_summary_check CHECK ((length(summary) > 0)),
    CONSTRAINT candidate_event_temporal_confidence_check CHECK (((temporal_confidence >= (0)::double precision) AND (temporal_confidence <= (1)::double precision)))
);


--
-- Name: candidate_fact; Type: TABLE; Schema: working; Owner: -
--

CREATE TABLE working.candidate_fact (
    id uuid DEFAULT uuidv7() NOT NULL,
    extraction_run_id uuid NOT NULL,
    source_raw_table text NOT NULL,
    source_raw_id text NOT NULL,
    subject_entity_id uuid,
    object_entity_id uuid,
    predicate text NOT NULL,
    statement text NOT NULL,
    evidence_quote text,
    confidence double precision,
    attrs jsonb DEFAULT '{}'::jsonb NOT NULL,
    content_sha256 bytea NOT NULL,
    review_state text DEFAULT 'pending'::text NOT NULL,
    promoted_to_table text,
    promoted_to_id text,
    promoted_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    case_id text DEFAULT 'primary'::text NOT NULL,
    domain text DEFAULT 'evidence'::text NOT NULL,
    topic_tags text[] DEFAULT '{}'::text[] NOT NULL,
    knowledge_actor text DEFAULT 'owner'::text NOT NULL,
    ontology_version text,
    knowledge_time timestamp with time zone,
    CONSTRAINT candidate_fact_attrs_check CHECK ((jsonb_typeof(attrs) = 'object'::text)),
    CONSTRAINT candidate_fact_case_id_ck CHECK ((length(case_id) > 0)),
    CONSTRAINT candidate_fact_confidence_check CHECK (((confidence >= (0)::double precision) AND (confidence <= (1)::double precision))),
    CONSTRAINT candidate_fact_content_sha256_check CHECK ((octet_length(content_sha256) = 32)),
    CONSTRAINT candidate_fact_domain_ck CHECK ((domain = ANY (ARRAY['evidence'::text, 'legal'::text, 'behavioral'::text, 'platform_design'::text, 'context'::text]))),
    CONSTRAINT candidate_fact_predicate_check CHECK ((length(predicate) > 0)),
    CONSTRAINT candidate_fact_promotion_is_complete CHECK ((((promoted_at IS NULL) AND (promoted_to_table IS NULL) AND (promoted_to_id IS NULL)) OR ((promoted_at IS NOT NULL) AND (promoted_to_table IS NOT NULL) AND (promoted_to_id IS NOT NULL)))),
    CONSTRAINT candidate_fact_promotion_requires_approval CHECK (((promoted_at IS NULL) OR (review_state = 'approved'::text))),
    CONSTRAINT candidate_fact_review_state_check CHECK ((review_state = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text, 'needs_info'::text, 'superseded'::text]))),
    CONSTRAINT candidate_fact_statement_check CHECK ((length(statement) > 0))
);


--
-- Name: conversation_group; Type: TABLE; Schema: working; Owner: -
--

CREATE TABLE working.conversation_group (
    id uuid DEFAULT uuidv7() NOT NULL,
    label text,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: TABLE conversation_group; Type: COMMENT; Schema: working; Owner: -
--

COMMENT ON TABLE working.conversation_group IS 'Canonical cross-platform conversation. Groups per-platform threads (SMS + iMessage + Facebook) that are one human conversation. Membership is asserted with a basis and reviewed — shared participants alone does not make one conversation.';


--
-- Name: conversation_group_member; Type: TABLE; Schema: working; Owner: -
--

CREATE TABLE working.conversation_group_member (
    id uuid DEFAULT uuidv7() NOT NULL,
    group_id uuid NOT NULL,
    conversation_id uuid NOT NULL,
    platform text,
    match_basis text DEFAULT 'unreviewed'::text NOT NULL,
    match_score numeric(5,4),
    asserted_by text DEFAULT 'human'::text NOT NULL,
    review_status text DEFAULT 'pending'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT conversation_group_member_match_score_check CHECK (((match_score IS NULL) OR ((match_score >= (0)::numeric) AND (match_score <= (1)::numeric)))),
    CONSTRAINT conversation_group_member_review_status_check CHECK ((review_status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text])))
);


--
-- Name: source_provenance; Type: TABLE; Schema: working; Owner: -
--

CREATE TABLE working.source_provenance (
    id uuid DEFAULT uuidv7() NOT NULL,
    source_raw_table text NOT NULL,
    source_raw_id text NOT NULL,
    revision integer DEFAULT 1 NOT NULL,
    occurred_at timestamp with time zone,
    export_created_at timestamp with time zone,
    acquired_at timestamp with time zone,
    ingested_at timestamp with time zone,
    realized_at timestamp with time zone,
    realized_at_source text,
    realized_at_state text DEFAULT 'unset'::text NOT NULL,
    acquisition_method text DEFAULT 'unknown'::text NOT NULL,
    acquisition_authority text DEFAULT 'unclear'::text NOT NULL,
    source_device text,
    device_custodian text,
    custody_transferred_at timestamp with time zone,
    acquisition_notes text,
    asserted_by text NOT NULL,
    asserted_by_kind text DEFAULT 'human'::text NOT NULL,
    producible boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT source_provenance_acquisition_authority_check CHECK ((acquisition_authority = ANY (ARRAY['device_owner'::text, 'parent_guardian'::text, 'account_holder'::text, 'consent_given'::text, 'court_order'::text, 'unclear'::text]))),
    CONSTRAINT source_provenance_acquisition_method_check CHECK ((acquisition_method = ANY (ARRAY['own_device'::text, 'household_device'::text, 'voluntary_third_party'::text, 'legal_process'::text, 'public_source'::text, 'unknown'::text]))),
    CONSTRAINT source_provenance_artifact_clock_order CHECK ((((export_created_at IS NULL) OR (acquired_at IS NULL) OR (acquired_at >= export_created_at)) AND ((acquired_at IS NULL) OR (ingested_at IS NULL) OR (ingested_at >= acquired_at)))),
    CONSTRAINT source_provenance_asserted_by_kind_check CHECK ((asserted_by_kind = 'human'::text)),
    CONSTRAINT source_provenance_realized_after_acquired CHECK (((realized_at IS NULL) OR (acquired_at IS NULL) OR (realized_at >= acquired_at))),
    CONSTRAINT source_provenance_realized_at_state_check CHECK ((realized_at_state = ANY (ARRAY['unset'::text, 'proposed'::text, 'confirmed'::text, 'corrected'::text]))),
    CONSTRAINT source_provenance_realized_state_agrees CHECK (((realized_at IS NULL) = (realized_at_state = 'unset'::text))),
    CONSTRAINT source_provenance_revision_check CHECK ((revision > 0))
);


--
-- Name: TABLE source_provenance; Type: COMMENT; Schema: working; Owner: -
--

COMMENT ON TABLE working.source_provenance IS 'Append-only revisions of the six clocks and the acquisition block for one source row. Never UPDATE — a correction is a new revision. Provenance may only be asserted by a human (asserted_by_kind is CHECKed to human).';


--
-- Name: current_provenance; Type: VIEW; Schema: working; Owner: -
--

CREATE VIEW working.current_provenance AS
 SELECT DISTINCT ON (source_raw_table, source_raw_id) id,
    source_raw_table,
    source_raw_id,
    revision,
    occurred_at,
    export_created_at,
    acquired_at,
    ingested_at,
    realized_at,
    realized_at_source,
    realized_at_state,
    acquisition_method,
    acquisition_authority,
    source_device,
    device_custodian,
    custody_transferred_at,
    acquisition_notes,
    asserted_by,
    asserted_by_kind,
    producible,
    created_at
   FROM working.source_provenance
  ORDER BY source_raw_table, source_raw_id, revision DESC;


--
-- Name: device_ownership; Type: TABLE; Schema: working; Owner: -
--

CREATE TABLE working.device_ownership (
    id uuid DEFAULT uuidv7() NOT NULL,
    device_id uuid NOT NULL,
    owner_entity_id uuid NOT NULL,
    effective_from timestamp with time zone NOT NULL,
    effective_to timestamp with time zone,
    asserted_by text DEFAULT 'human'::text NOT NULL,
    basis text,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT device_ownership_human_only CHECK ((asserted_by = 'human'::text)),
    CONSTRAINT device_ownership_range CHECK (((effective_to IS NULL) OR (effective_to > effective_from)))
);


--
-- Name: TABLE device_ownership; Type: COMMENT; Schema: working; Owner: -
--

COMMENT ON TABLE working.device_ownership IS 'Time-scoped device ownership. Resolves the implicit sender of outbound messages: an export attributes sent messages to "me", and "me" is whoever held the device at occurred_at. HITL-asserted; no export states this.';


--
-- Name: email; Type: TABLE; Schema: working; Owner: -
--

CREATE TABLE working.email (
    id uuid NOT NULL,
    address ai.citext,
    owner_entity_id uuid,
    validity tstzrange DEFAULT tstzrange(now(), NULL::timestamp with time zone) NOT NULL
);


--
-- Name: entity_alias; Type: TABLE; Schema: working; Owner: -
--

CREATE TABLE working.entity_alias (
    id uuid DEFAULT uuidv7() NOT NULL,
    entity_id uuid NOT NULL,
    alias_text ai.citext NOT NULL,
    alias_kind text,
    confidence ai.confidence,
    alias_dmeta text GENERATED ALWAYS AS (ai.dmetaphone((alias_text)::text)) STORED,
    provenance ai.source_ref[] DEFAULT '{}'::ai.source_ref[] NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT entity_alias_alias_kind_check CHECK ((alias_kind = ANY (ARRAY['nickname'::text, 'legal'::text, 'maiden'::text, 'handle'::text, 'misspelling'::text, 'phonetic'::text, 'initials'::text, 'other'::text])))
);


--
-- Name: entity_mention; Type: TABLE; Schema: working; Owner: -
--

CREATE TABLE working.entity_mention (
    id uuid DEFAULT uuidv7() NOT NULL,
    surface_text ai.citext NOT NULL,
    surface_norm text GENERATED ALWAYS AS (lower((surface_text)::text)) STORED,
    mention_kind text,
    subject_type text,
    subject_id uuid,
    start_char integer,
    end_char integer,
    context_snippet text,
    extraction_method text,
    confidence ai.confidence,
    mention_dmeta text GENERATED ALWAYS AS (ai.dmetaphone((surface_text)::text)) STORED,
    data_tier ai.evidence_tier DEFAULT 'extracted'::ai.evidence_tier NOT NULL,
    provenance ai.source_ref[] DEFAULT '{}'::ai.source_ref[] NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT entity_mention_mention_kind_check CHECK ((mention_kind = ANY (ARRAY['name'::text, 'phone'::text, 'handle'::text, 'email'::text, 'pronoun'::text, 'partial'::text, 'address'::text, 'device'::text, 'other'::text])))
);


--
-- Name: entity_merge_event; Type: TABLE; Schema: working; Owner: -
--

CREATE TABLE working.entity_merge_event (
    id uuid DEFAULT uuidv7() NOT NULL,
    op text NOT NULL,
    surviving_entity_id uuid NOT NULL,
    merged_entity_id uuid NOT NULL,
    actor_id uuid,
    actor_kind text,
    rationale text,
    reversible_to uuid,
    requires_human_review boolean DEFAULT true NOT NULL,
    review_status ai.review_state DEFAULT 'unreviewed'::ai.review_state NOT NULL,
    reviewed_by text,
    reviewed_at timestamp with time zone,
    provenance ai.source_ref[] DEFAULT '{}'::ai.source_ref[] NOT NULL,
    occurred_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT entity_merge_event_actor_kind_check CHECK ((actor_kind = ANY (ARRAY['human'::text, 'service'::text, 'agent'::text]))),
    CONSTRAINT entity_merge_event_op_check CHECK ((op = ANY (ARRAY['merge'::text, 'split'::text]))),
    CONSTRAINT merge_distinct CHECK ((surviving_entity_id <> merged_entity_id))
);


--
-- Name: entity_resolution; Type: TABLE; Schema: working; Owner: -
--

CREATE TABLE working.entity_resolution (
    id uuid DEFAULT uuidv7() NOT NULL,
    mention_id uuid NOT NULL,
    canonical_entity_id uuid NOT NULL,
    source_specific_id text,
    match_method ai.match_method NOT NULL,
    resolved_by text,
    match_score ai.confidence,
    similarity_metrics jsonb DEFAULT '{}'::jsonb NOT NULL,
    requires_human_review boolean DEFAULT true NOT NULL,
    review_status ai.review_state DEFAULT 'unreviewed'::ai.review_state NOT NULL,
    reviewed_by text,
    reviewed_at timestamp with time zone,
    review_notes text,
    safe_for_legal_use boolean DEFAULT false NOT NULL,
    data_tier ai.evidence_tier DEFAULT 'analytical'::ai.evidence_tier NOT NULL,
    provenance ai.source_ref[] DEFAULT '{}'::ai.source_ref[] NOT NULL,
    sys_period tstzrange DEFAULT tstzrange(now(), NULL::timestamp with time zone) NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT entity_resolution_resolved_by_check CHECK ((resolved_by = ANY (ARRAY['rule'::text, 'model'::text, 'human'::text])))
);


--
-- Name: event_ordering; Type: TABLE; Schema: working; Owner: -
--

CREATE TABLE working.event_ordering (
    ordering_id uuid DEFAULT uuidv7() NOT NULL,
    before_event uuid NOT NULL,
    after_event uuid NOT NULL,
    relation ai.temporal_relation DEFAULT 'preceded'::ai.temporal_relation NOT NULL,
    basis text NOT NULL,
    confidence ai.confidence,
    requires_human_review boolean DEFAULT false NOT NULL,
    derived_from uuid[] DEFAULT '{}'::uuid[] NOT NULL,
    author text NOT NULL,
    asserted_at timestamp with time zone DEFAULT now() NOT NULL,
    retracted_at timestamp with time zone,
    CONSTRAINT no_self_order CHECK ((before_event <> after_event))
);


--
-- Name: extraction_batch; Type: TABLE; Schema: working; Owner: -
--

CREATE TABLE working.extraction_batch (
    id uuid DEFAULT uuidv7() NOT NULL,
    scope_query text,
    scope_note text,
    record_count integer DEFAULT 0 NOT NULL,
    input_hash text,
    input_canon text DEFAULT 'extraction-batch-v1'::text NOT NULL,
    input_ref text,
    extractor text NOT NULL,
    extractor_version text,
    prompt_version text,
    ontology_version text,
    model_id text,
    status text DEFAULT 'pending'::text NOT NULL,
    error_note text,
    started_at timestamp with time zone,
    completed_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT extraction_batch_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'running'::text, 'completed'::text, 'failed'::text, 'superseded'::text])))
);


--
-- Name: TABLE extraction_batch; Type: COMMENT; Schema: working; Owner: -
--

COMMENT ON TABLE working.extraction_batch IS 'A materialised, hashed report handed to Semantica. Semantica is PUSHED this batch and never queries the DB, preserving the no-credentials boundary and making every extraction reproducible. Runs as its own pass after derivation, never inline with ingest.';


--
-- Name: extraction_run; Type: TABLE; Schema: working; Owner: -
--

CREATE TABLE working.extraction_run (
    id uuid DEFAULT uuidv7() NOT NULL,
    started_at timestamp with time zone DEFAULT now() NOT NULL,
    finished_at timestamp with time zone,
    extractor text NOT NULL,
    extractor_version text NOT NULL,
    model_id text,
    source_summary text NOT NULL,
    status text DEFAULT 'running'::text NOT NULL,
    error text,
    stats jsonb DEFAULT '{}'::jsonb NOT NULL,
    CONSTRAINT extraction_run_finished_after_start CHECK (((finished_at IS NULL) OR (finished_at >= started_at))),
    CONSTRAINT extraction_run_lifecycle_ck CHECK ((((status <> 'completed'::text) OR (finished_at IS NOT NULL)) AND ((status <> 'failed'::text) OR (error IS NOT NULL)))),
    CONSTRAINT extraction_run_stats_check CHECK ((jsonb_typeof(stats) = 'object'::text)),
    CONSTRAINT extraction_run_status_check CHECK ((status = ANY (ARRAY['running'::text, 'completed'::text, 'failed'::text])))
);


--
-- Name: TABLE extraction_run; Type: COMMENT; Schema: working; Owner: -
--

COMMENT ON TABLE working.extraction_run IS 'One extraction pass. Every candidate FKs here so a bad model version can be traced and its output re-reviewed or discarded wholesale.';


--
-- Name: geocode_request; Type: TABLE; Schema: working; Owner: -
--

CREATE TABLE working.geocode_request (
    id uuid DEFAULT uuidv7() NOT NULL,
    query text NOT NULL,
    geog ai.geo_point,
    status text DEFAULT 'pending'::text NOT NULL,
    data_tier ai.evidence_tier DEFAULT 'extracted'::ai.evidence_tier NOT NULL,
    provenance_id uuid,
    requested_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT geocode_request_data_tier_check CHECK ((data_tier = 'extracted'::ai.evidence_tier))
);


--
-- Name: geocode_resolution; Type: TABLE; Schema: working; Owner: -
--

CREATE TABLE working.geocode_resolution (
    id uuid DEFAULT uuidv7() NOT NULL,
    request_id uuid NOT NULL,
    location_id uuid,
    preferred_provider ai.geocode_provider,
    chosen_result_id uuid,
    distance_m numeric(12,2),
    disagreement_flag boolean DEFAULT false NOT NULL,
    tie_break_reason text,
    data_tier ai.evidence_tier DEFAULT 'extracted'::ai.evidence_tier NOT NULL,
    provenance_id uuid,
    resolved_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT geocode_resolution_data_tier_check CHECK ((data_tier = 'extracted'::ai.evidence_tier))
);


--
-- Name: geocode_result; Type: TABLE; Schema: working; Owner: -
--

CREATE TABLE working.geocode_result (
    id uuid DEFAULT uuidv7() NOT NULL,
    request_id uuid NOT NULL,
    provider ai.geocode_provider NOT NULL,
    place_id text,
    address text,
    geog ai.geo_point,
    confidence ai.confidence,
    bounds jsonb,
    raw_json jsonb DEFAULT '{}'::jsonb NOT NULL,
    data_tier ai.evidence_tier DEFAULT 'extracted'::ai.evidence_tier NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT geocode_result_data_tier_check CHECK ((data_tier = 'extracted'::ai.evidence_tier))
);


--
-- Name: gps_track; Type: TABLE; Schema: working; Owner: -
--

CREATE TABLE working.gps_track (
    id uuid DEFAULT uuidv7() NOT NULL,
    device_id uuid,
    source_id uuid,
    geog public.geography(LineString,4326) NOT NULL,
    started_at timestamp with time zone,
    ended_at timestamp with time zone,
    point_count integer,
    data_tier ai.evidence_tier DEFAULT 'extracted'::ai.evidence_tier NOT NULL,
    provenance_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT gps_track_data_tier_check CHECK ((data_tier = 'extracted'::ai.evidence_tier))
);


--
-- Name: handle; Type: TABLE; Schema: working; Owner: -
--

CREATE TABLE working.handle (
    id uuid NOT NULL,
    platform text NOT NULL,
    handle ai.citext NOT NULL,
    owner_entity_id uuid,
    is_blocked boolean DEFAULT false NOT NULL,
    validity tstzrange DEFAULT tstzrange(now(), NULL::timestamp with time zone) NOT NULL
);


--
-- Name: home_base; Type: TABLE; Schema: working; Owner: -
--

CREATE TABLE working.home_base (
    id uuid DEFAULT uuidv7() NOT NULL,
    entity_id uuid,
    location_id uuid,
    spatial_confidence ai.confidence,
    typical_schedule jsonb DEFAULT '{}'::jsonb NOT NULL,
    requires_human_review boolean DEFAULT false NOT NULL,
    review_status ai.review_state DEFAULT 'unreviewed'::ai.review_state NOT NULL,
    data_tier ai.evidence_tier DEFAULT 'inferred'::ai.evidence_tier NOT NULL,
    provenance_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT home_base_data_tier_check CHECK ((data_tier = 'inferred'::ai.evidence_tier))
);


--
-- Name: id_xref; Type: TABLE; Schema: working; Owner: -
--

CREATE TABLE working.id_xref (
    id uuid DEFAULT uuidv7() NOT NULL,
    canonical_entity_id uuid,
    system_a ai.source_system NOT NULL,
    native_id_a text NOT NULL,
    system_b ai.source_system NOT NULL,
    native_id_b text NOT NULL,
    match_method ai.match_method NOT NULL,
    confidence ai.confidence,
    source ai.source_ref,
    is_current boolean DEFAULT true NOT NULL,
    sys_period tstzrange DEFAULT tstzrange(now(), NULL::timestamp with time zone) NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: knowledge_gap; Type: VIEW; Schema: working; Owner: -
--

CREATE VIEW working.knowledge_gap AS
 SELECT source_raw_table,
    source_raw_id,
    occurred_at,
    realized_at,
    (realized_at - occurred_at) AS gap,
    acquisition_method,
    acquisition_authority,
    producible
   FROM working.current_provenance
  WHERE ((occurred_at IS NOT NULL) AND (realized_at IS NOT NULL));


--
-- Name: VIEW knowledge_gap; Type: COMMENT; Schema: working; Owner: -
--

COMMENT ON VIEW working.knowledge_gap IS 'occurred_at vs realized_at. The gap between what was true and when it was understood is the evidence of manipulation, not a discrepancy to reconcile.';


--
-- Name: lineage_edge; Type: TABLE; Schema: working; Owner: -
--

CREATE TABLE working.lineage_edge (
    edge_id uuid DEFAULT uuidv7() NOT NULL,
    child_artifact uuid NOT NULL,
    parent_artifact uuid,
    parent_source uuid,
    producing_run uuid,
    role text NOT NULL,
    note text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT lineage_edge_check CHECK (((parent_artifact IS NOT NULL) OR (parent_source IS NOT NULL))),
    CONSTRAINT lineage_edge_role_check CHECK ((role = ANY (ARRAY['derived_from'::text, 'supersedes'::text, 'corroborates'::text, 'contradicts'::text])))
);


--
-- Name: location; Type: TABLE; Schema: working; Owner: -
--

CREATE TABLE working.location (
    id uuid DEFAULT uuidv7() NOT NULL,
    name text,
    geog ai.geo_point NOT NULL,
    geohash9 text GENERATED ALWAYS AS (public.st_geohash((geog)::public.geometry, 9)) STORED,
    address text,
    place_type text,
    is_fuzzed boolean DEFAULT false NOT NULL,
    sensitivity_tier ai.sensitivity_tier DEFAULT 'restricted'::ai.sensitivity_tier NOT NULL,
    spatial_confidence ai.confidence,
    data_tier ai.evidence_tier DEFAULT 'extracted'::ai.evidence_tier NOT NULL,
    provenance_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT location_data_tier_check CHECK ((data_tier = ANY (ARRAY['extracted'::ai.evidence_tier, 'inferred'::ai.evidence_tier, 'analytical'::ai.evidence_tier])))
);


--
-- Name: message_serial_number_seq; Type: SEQUENCE; Schema: working; Owner: -
--

ALTER TABLE working.message ALTER COLUMN serial_number ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME working.message_serial_number_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: organization; Type: TABLE; Schema: working; Owner: -
--

CREATE TABLE working.organization (
    id uuid NOT NULL,
    org_type text,
    legal_name ai.citext,
    jurisdiction text
);


--
-- Name: phone; Type: TABLE; Schema: working; Owner: -
--

CREATE TABLE working.phone (
    id uuid NOT NULL,
    e164 ai.citext,
    raw_number text,
    owner_entity_id uuid,
    is_blocked boolean DEFAULT false NOT NULL,
    validity tstzrange DEFAULT tstzrange(now(), NULL::timestamp with time zone) NOT NULL
);


--
-- Name: promotion; Type: TABLE; Schema: working; Owner: -
--

CREATE TABLE working.promotion (
    id uuid DEFAULT uuidv7() NOT NULL,
    candidate_kind text NOT NULL,
    candidate_id uuid NOT NULL,
    lane text NOT NULL,
    target_system text NOT NULL,
    target_ref text NOT NULL,
    promoted_by text NOT NULL,
    promoted_at timestamp with time zone DEFAULT now() NOT NULL,
    revoked_at timestamp with time zone,
    revoked_reason text,
    attrs jsonb DEFAULT '{}'::jsonb NOT NULL,
    CONSTRAINT promotion_attrs_check CHECK ((jsonb_typeof(attrs) = 'object'::text)),
    CONSTRAINT promotion_candidate_kind_check CHECK ((candidate_kind = ANY (ARRAY['entity'::text, 'fact'::text, 'event'::text]))),
    CONSTRAINT promotion_lane_check CHECK ((lane = ANY (ARRAY['as_lived'::text, 'hindsight'::text, 'consolidated'::text, 'support'::text]))),
    CONSTRAINT promotion_lane_matches_target CHECK (((lane = 'support'::text) OR ((lane = 'as_lived'::text) AND (target_system = 'graphiti_memory'::text)) OR ((lane = 'hindsight'::text) AND (target_system = ANY (ARRAY['semantica_graph'::text, 'postgres'::text]))) OR ((lane = 'consolidated'::text) AND (target_system = ANY (ARRAY['surrealdb'::text, 'postgres'::text]))))),
    CONSTRAINT promotion_revocation_has_reason CHECK (((revoked_at IS NULL) OR (revoked_reason IS NOT NULL))),
    CONSTRAINT promotion_target_system_check CHECK ((target_system = ANY (ARRAY['postgres'::text, 'surrealdb'::text, 'semantica_graph'::text, 'graphiti_memory'::text, 'weaviate'::text])))
);


--
-- Name: TABLE promotion; Type: COMMENT; Schema: working; Owner: -
--

COMMENT ON TABLE working.promotion IS 'Every crossing of the human gate, labelled by which analysis pass it feeds: as_lived (Graphiti, keyed on realized_at), hindsight (Semantica/Neo4j, keyed on occurred_at), or consolidated (SurrealDB). Revocations are recorded, not deleted.';


--
-- Name: COLUMN promotion.lane; Type: COMMENT; Schema: working; Owner: -
--

COMMENT ON COLUMN working.promotion.lane IS 'as_lived material must be withheld until its realized_at, or the belief state it documents is destroyed. Check working.current_provenance before promoting into the as_lived lane.';


--
-- Name: review_decision; Type: TABLE; Schema: working; Owner: -
--

CREATE TABLE working.review_decision (
    id uuid DEFAULT uuidv7() NOT NULL,
    candidate_kind text NOT NULL,
    candidate_id uuid NOT NULL,
    decision text NOT NULL,
    reviewer text NOT NULL,
    rationale text,
    decided_at timestamp with time zone DEFAULT now() NOT NULL,
    prior_state text NOT NULL,
    attrs jsonb DEFAULT '{}'::jsonb NOT NULL,
    CONSTRAINT review_decision_attrs_check CHECK ((jsonb_typeof(attrs) = 'object'::text)),
    CONSTRAINT review_decision_candidate_kind_check CHECK ((candidate_kind = ANY (ARRAY['entity'::text, 'fact'::text, 'event'::text]))),
    CONSTRAINT review_decision_decision_check CHECK ((decision = ANY (ARRAY['approved'::text, 'rejected'::text, 'needs_info'::text, 'superseded'::text]))),
    CONSTRAINT review_decision_reviewer_check CHECK ((length(reviewer) > 0))
);


--
-- Name: TABLE review_decision; Type: COMMENT; Schema: working; Owner: -
--

COMMENT ON TABLE working.review_decision IS 'Append-only. Never UPDATE or DELETE — this is the provenance of human judgement and must remain defensible after the candidate changes.';


--
-- Name: review_queue; Type: VIEW; Schema: working; Owner: -
--

CREATE VIEW working.review_queue AS
 SELECT 'entity'::text AS kind,
    e.id,
    e.created_at,
    e.confidence,
    e.source_raw_table,
    e.source_raw_id,
    e.name AS label,
    e.review_state
   FROM working.candidate_entity e
  WHERE (e.review_state = 'pending'::text)
UNION ALL
 SELECT 'fact'::text AS kind,
    f.id,
    f.created_at,
    f.confidence,
    f.source_raw_table,
    f.source_raw_id,
    f.statement AS label,
    f.review_state
   FROM working.candidate_fact f
  WHERE (f.review_state = 'pending'::text)
UNION ALL
 SELECT 'event'::text AS kind,
    v.id,
    v.created_at,
    v.confidence,
    v.source_raw_table,
    v.source_raw_id,
    v.summary AS label,
    v.review_state
   FROM working.candidate_event v
  WHERE (v.review_state = 'pending'::text);


--
-- Name: VIEW review_queue; Type: COMMENT; Schema: working; Owner: -
--

COMMENT ON VIEW working.review_queue IS 'Everything awaiting human judgement, lowest-confidence first is the intended read: ORDER BY confidence NULLS FIRST, created_at.';


--
-- Name: stay_point; Type: TABLE; Schema: working; Owner: -
--

CREATE TABLE working.stay_point (
    id uuid DEFAULT uuidv7() NOT NULL,
    track_id uuid,
    location_id uuid,
    device_id uuid,
    geog ai.geo_point NOT NULL,
    arrived_at timestamp with time zone,
    departed_at timestamp with time zone,
    dwell_s bigint,
    spatial_confidence ai.confidence,
    requires_human_review boolean DEFAULT false NOT NULL,
    review_status ai.review_state DEFAULT 'unreviewed'::ai.review_state NOT NULL,
    data_tier ai.evidence_tier DEFAULT 'inferred'::ai.evidence_tier NOT NULL,
    provenance_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT stay_point_data_tier_check CHECK ((data_tier = 'inferred'::ai.evidence_tier))
);


--
-- Name: temporal_anchor; Type: TABLE; Schema: working; Owner: -
--

CREATE TABLE working.temporal_anchor (
    anchor_id uuid DEFAULT uuidv7() NOT NULL,
    anchor_key ai.citext,
    label text NOT NULL,
    anchor_type ai.anchor_kind NOT NULL,
    event_id uuid,
    valid_earliest timestamp with time zone NOT NULL,
    valid_latest timestamp with time zone NOT NULL,
    valid_range tstzrange GENERATED ALWAYS AS (tstzrange(valid_earliest, valid_latest, '[]'::text)) STORED,
    certainty ai.precision_class NOT NULL,
    confidence ai.confidence,
    derived_from uuid[] DEFAULT '{}'::uuid[] NOT NULL,
    requires_human_review boolean DEFAULT false NOT NULL,
    author text NOT NULL,
    asserted_at timestamp with time zone DEFAULT now() NOT NULL,
    retracted_at timestamp with time zone,
    CONSTRAINT anchor_ordering CHECK ((valid_earliest <= valid_latest))
);


--
-- Name: vehicle; Type: TABLE; Schema: working; Owner: -
--

CREATE TABLE working.vehicle (
    id uuid NOT NULL,
    plate ai.citext,
    make_model text,
    owner_entity_id uuid
);


--
-- Name: vw_derivation_lineage; Type: VIEW; Schema: working; Owner: -
--

CREATE VIEW working.vw_derivation_lineage AS
 SELECT nr.id AS record_id,
    nr.record_type,
    nr.occurred_at,
    "left"(nr.content, 120) AS content_preview,
    nr.derived_from_raw_table AS raw_table,
    nr.derived_from_raw_id AS raw_id,
    nr.deriver_version,
    nr.derived_at,
    r.parser_version,
    r.record_index,
    r.content_hash,
    r.superseded_by AS raw_superseded_by,
    s.id AS source_id,
    s.original_filename,
    encode(s.sha256, 'hex'::text) AS h1,
    a.id AS acquisition_id,
    a.method AS acquisition_method,
    a.authority AS acquisition_authority,
    nr.acquired_at,
    nr.export_created_at,
    nr.ingested_at
   FROM (((working.normalized_record nr
     LEFT JOIN evidence.vw_raw_all r ON ((r.id = nr.derived_from_raw_id)))
     LEFT JOIN evidence.source s ON ((s.id = r.source_id)))
     LEFT JOIN evidence.acquisition a ON ((a.id = nr.acquisition_id)));


--
-- Name: VIEW vw_derivation_lineage; Type: COMMENT; Schema: working; Owner: -
--

COMMENT ON VIEW working.vw_derivation_lineage IS 'Every spine record traced back to the raw row it came from, whatever format that was, the artifact it came from, and how that artifact was acquired. A record with a NULL raw_id has no lineage and should not exist.';


--
-- Name: vw_message_imessage; Type: VIEW; Schema: working; Owner: -
--

CREATE VIEW working.vw_message_imessage AS
 SELECT m.id AS message_id,
    m.conversation_id,
    m.ts_utc,
    m.direction,
    m.is_read,
    m.external_id AS apple_guid,
    (m.platform_attrs ->> 'service'::text) AS service,
    (m.platform_attrs ->> 'date_read'::text) AS date_read,
    (m.platform_attrs ->> 'date_edited'::text) AS date_edited,
    (m.platform_attrs ->> 'thread_originator_guid'::text) AS reply_to_guid,
    m.raw_ts,
    nr.content
   FROM (working.message m
     LEFT JOIN working.normalized_record nr ON ((nr.id = m.id)))
  WHERE (m.platform = 'imessage'::text);


--
-- Name: VIEW vw_message_imessage; Type: COMMENT; Schema: working; Owner: -
--

COMMENT ON VIEW working.vw_message_imessage IS 'iMessage typed view. date_read/date_edited/service/reply_to_guid populate only after a chat.db re-export (current HTML export lacks them — see extracted-code-sweep-ADDENDUM.md §4).';


--
-- Name: vw_message_sms; Type: VIEW; Schema: working; Owner: -
--

CREATE VIEW working.vw_message_sms AS
 SELECT m.id AS message_id,
    m.conversation_id,
    m.ts_utc,
    m.direction,
    m.is_read,
    m.sender_e164,
    m.recipient_e164,
    m.delivery_status,
    m.status_code,
    m.is_blocked,
    (m.platform_attrs ->> 'service_center'::text) AS service_center,
    (m.platform_attrs ->> 'sub_id'::text) AS sub_id,
    (m.platform_attrs ->> 'contact_name'::text) AS contact_name,
    m.raw_ts,
    nr.content
   FROM (working.message m
     LEFT JOIN working.normalized_record nr ON ((nr.id = m.id)))
  WHERE (m.platform = 'sms'::text);


--
-- Name: VIEW vw_message_sms; Type: COMMENT; Schema: working; Owner: -
--

COMMENT ON VIEW working.vw_message_sms IS 'SMS-Backup&Restore fields as typed columns from platform_attrs.';


--
-- Name: vw_record_attestations; Type: VIEW; Schema: working; Owner: -
--

CREATE VIEW working.vw_record_attestations AS
 SELECT r.id AS record_id,
    r.occurred_at,
    count(esr.link_id) AS attestation_count,
    count(*) FILTER (WHERE (esr.agrees IS FALSE)) AS disagreeing_count,
    array_agg(DISTINCT esr.medium) FILTER (WHERE (esr.medium IS NOT NULL)) AS mediums,
    array_agg(DISTINCT esr.raw_table) FILTER (WHERE (esr.raw_table IS NOT NULL)) AS raw_tables,
    array_agg(DISTINCT esr.source_id) FILTER (WHERE (esr.source_id IS NOT NULL)) AS source_ids,
        CASE
            WHEN (count(*) FILTER (WHERE (esr.agrees IS FALSE)) > 0) THEN 'CONFLICTED'::text
            WHEN (count(esr.link_id) > 1) THEN 'corroborated'::text
            WHEN (count(esr.link_id) = 1) THEN 'single_source'::text
            ELSE 'unlinked'::text
        END AS attestation_status
   FROM (working.normalized_record r
     LEFT JOIN working.event_source_record esr ON ((esr.record_id = r.id)))
  GROUP BY r.id, r.occurred_at;


--
-- Name: VIEW vw_record_attestations; Type: COMMENT; Schema: working; Owner: -
--

COMMENT ON VIEW working.vw_record_attestations IS 'Every source attesting each spine record. attestation_status: CONFLICTED (an attestation disagrees — a finding), corroborated (multiple independent sources), single_source, unlinked. Multiple mediums for one message is expected and valuable.';


--
-- Name: vw_record_disclosure; Type: VIEW; Schema: working; Owner: -
--

CREATE VIEW working.vw_record_disclosure AS
 SELECT id,
    occurred_at,
    acquired_at,
    realized_at,
    disclosure_tier AS disclosure_tier_asserted,
        CASE
            WHEN ((realized_at IS NULL) AND (acquired_at IS NULL)) THEN NULL::text
            WHEN ((realized_at IS NOT NULL) AND (occurred_at IS NOT NULL) AND (realized_at > (occurred_at + '30 days'::interval))) THEN 'hindsight'::text
            WHEN ((acquired_at IS NOT NULL) AND (occurred_at IS NOT NULL) AND (acquired_at > (occurred_at + '30 days'::interval))) THEN 'discovered'::text
            ELSE 'contemporaneous'::text
        END AS disclosure_tier_derived,
        CASE
            WHEN ((realized_at IS NOT NULL) AND (occurred_at IS NOT NULL)) THEN (realized_at - occurred_at)
            ELSE NULL::interval
        END AS realization_lag
   FROM working.normalized_record r;


--
-- Name: VIEW vw_record_disclosure; Type: COMMENT; Schema: working; Owner: -
--

COMMENT ON VIEW working.vw_record_disclosure IS 'Authoritative disclosure tier, derived from the clocks. disclosure_tier_asserted is the parse-time hint (parsers hardcode contemporaneous and cannot know better). realization_lag = realized_at - occurred_at is the as-lived gap.';


--
-- Name: vw_record_sender_resolution; Type: VIEW; Schema: working; Owner: -
--

CREATE VIEW working.vw_record_sender_resolution AS
 SELECT r.id AS record_id,
    r.occurred_at,
    r.role,
    r.device_id,
    d.device_label,
    r.sender_entity_id AS sender_stored,
    o.owner_entity_id AS owner_at_occurred_at,
        CASE
            WHEN (r.device_id IS NULL) THEN 'no_device'::text
            WHEN (o.owner_entity_id IS NULL) THEN 'no_ownership_record'::text
            WHEN (r.sender_entity_id IS NULL) THEN 'unresolved'::text
            WHEN (r.sender_entity_id = o.owner_entity_id) THEN 'consistent'::text
            ELSE 'MISMATCH'::text
        END AS attribution_status
   FROM ((working.normalized_record r
     LEFT JOIN working.device d ON ((d.id = r.device_id)))
     LEFT JOIN working.device_ownership o ON (((o.device_id = r.device_id) AND (r.occurred_at >= o.effective_from) AND ((o.effective_to IS NULL) OR (r.occurred_at < o.effective_to)))));


--
-- Name: VIEW vw_record_sender_resolution; Type: COMMENT; Schema: working; Owner: -
--

COMMENT ON VIEW working.vw_record_sender_resolution IS 'Cross-checks stored sender against the time-scoped ownership timeline. attribution_status = MISMATCH means an outbound record is attributed to someone who did not hold the device when it was sent — the hand-me-down failure mode.';


--
-- Name: vw_spine_horizon; Type: VIEW; Schema: working; Owner: -
--

CREATE VIEW working.vw_spine_horizon AS
 SELECT id,
    artifact_id,
    record_type,
    source,
    conversation_id,
    role,
    participants,
    content,
    occurred_at,
    knowledge_time,
    disclosure_tier,
    attrs,
    created_at,
    conversation_ref,
    ts_precision,
    sensitivity_tier,
    data_tier,
    review_status,
    safe_for_legal_use,
    provenance_id,
    export_created_at,
    acquired_at,
    ingested_at,
    realized_at,
    realized_evidence,
    acquisition_id,
    device_id,
    sender_entity_id,
    derived_from_raw_table,
    derived_from_raw_id,
    deriver_version,
    derived_at,
    attestation_count,
    case_id,
    domain,
    topic_tags,
    knowledge_actor,
    ontology_version
   FROM working.normalized_record r
  WHERE working.horizon_visible(case_id, knowledge_time, disclosure_tier, knowledge_actor, current_setting('app.case_id'::text, true), (NULLIF(current_setting('app.horizon'::text, true), ''::text))::timestamp with time zone, COALESCE(NULLIF(current_setting('app.actor'::text, true), ''::text), 'owner'::text));


--
-- Name: VIEW vw_spine_horizon; Type: COMMENT; Schema: working; Owner: -
--

COMMENT ON VIEW working.vw_spine_horizon IS 'Spine filtered by the session horizon: SET app.case_id / app.horizon / app.actor first. app.horizon unset or empty = hindsight.';


--
-- Name: waypoint_device_split; Type: TABLE; Schema: working; Owner: -
--

CREATE TABLE working.waypoint_device_split (
    split_id uuid DEFAULT uuidv7() NOT NULL,
    raw_path_id uuid NOT NULL,
    device_index integer NOT NULL,
    split_from_activity uuid,
    threshold_meters numeric DEFAULT 100 NOT NULL,
    certainty ai.precision_class DEFAULT 'inferred'::ai.precision_class NOT NULL,
    confidence ai.confidence,
    requires_human_review boolean DEFAULT false NOT NULL,
    ingest_run_id uuid,
    author text NOT NULL,
    asserted_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: api_keys id; Type: DEFAULT; Schema: ai; Owner: -
--

ALTER TABLE ONLY ai.api_keys ALTER COLUMN id SET DEFAULT nextval('ai.api_keys_id_seq'::regclass);


--
-- Name: agno_approvals agno_approvals_pkey; Type: CONSTRAINT; Schema: ai; Owner: -
--

ALTER TABLE ONLY ai.agno_approvals
    ADD CONSTRAINT agno_approvals_pkey PRIMARY KEY (id);


--
-- Name: agno_component_configs agno_component_configs_pkey; Type: CONSTRAINT; Schema: ai; Owner: -
--

ALTER TABLE ONLY ai.agno_component_configs
    ADD CONSTRAINT agno_component_configs_pkey PRIMARY KEY (component_id, version);


--
-- Name: agno_component_links agno_component_links_pkey; Type: CONSTRAINT; Schema: ai; Owner: -
--

ALTER TABLE ONLY ai.agno_component_links
    ADD CONSTRAINT agno_component_links_pkey PRIMARY KEY (parent_component_id, parent_version, link_kind, link_key);


--
-- Name: agno_components agno_components_pkey; Type: CONSTRAINT; Schema: ai; Owner: -
--

ALTER TABLE ONLY ai.agno_components
    ADD CONSTRAINT agno_components_pkey PRIMARY KEY (component_id);


--
-- Name: agno_eval_runs agno_eval_runs_pkey; Type: CONSTRAINT; Schema: ai; Owner: -
--

ALTER TABLE ONLY ai.agno_eval_runs
    ADD CONSTRAINT agno_eval_runs_pkey PRIMARY KEY (run_id);


--
-- Name: agno_knowledge agno_knowledge_pkey; Type: CONSTRAINT; Schema: ai; Owner: -
--

ALTER TABLE ONLY ai.agno_knowledge
    ADD CONSTRAINT agno_knowledge_pkey PRIMARY KEY (id);


--
-- Name: agno_learnings agno_learnings_pkey; Type: CONSTRAINT; Schema: ai; Owner: -
--

ALTER TABLE ONLY ai.agno_learnings
    ADD CONSTRAINT agno_learnings_pkey PRIMARY KEY (learning_id);


--
-- Name: agno_memories agno_memories_pkey; Type: CONSTRAINT; Schema: ai; Owner: -
--

ALTER TABLE ONLY ai.agno_memories
    ADD CONSTRAINT agno_memories_pkey PRIMARY KEY (memory_id);


--
-- Name: agno_metrics agno_metrics_pkey; Type: CONSTRAINT; Schema: ai; Owner: -
--

ALTER TABLE ONLY ai.agno_metrics
    ADD CONSTRAINT agno_metrics_pkey PRIMARY KEY (id);


--
-- Name: agno_metrics agno_metrics_uq_metrics_date_period; Type: CONSTRAINT; Schema: ai; Owner: -
--

ALTER TABLE ONLY ai.agno_metrics
    ADD CONSTRAINT agno_metrics_uq_metrics_date_period UNIQUE (date, aggregation_period);


--
-- Name: agno_schedule_runs agno_schedule_runs_pkey; Type: CONSTRAINT; Schema: ai; Owner: -
--

ALTER TABLE ONLY ai.agno_schedule_runs
    ADD CONSTRAINT agno_schedule_runs_pkey PRIMARY KEY (id);


--
-- Name: agno_schedules agno_schedules_pkey; Type: CONSTRAINT; Schema: ai; Owner: -
--

ALTER TABLE ONLY ai.agno_schedules
    ADD CONSTRAINT agno_schedules_pkey PRIMARY KEY (id);


--
-- Name: agno_schema_versions agno_schema_versions_pkey; Type: CONSTRAINT; Schema: ai; Owner: -
--

ALTER TABLE ONLY ai.agno_schema_versions
    ADD CONSTRAINT agno_schema_versions_pkey PRIMARY KEY (table_name);


--
-- Name: agno_service_accounts agno_service_accounts_pkey; Type: CONSTRAINT; Schema: ai; Owner: -
--

ALTER TABLE ONLY ai.agno_service_accounts
    ADD CONSTRAINT agno_service_accounts_pkey PRIMARY KEY (id);


--
-- Name: agno_service_accounts agno_service_accounts_token_hash_key; Type: CONSTRAINT; Schema: ai; Owner: -
--

ALTER TABLE ONLY ai.agno_service_accounts
    ADD CONSTRAINT agno_service_accounts_token_hash_key UNIQUE (token_hash);


--
-- Name: agno_sessions agno_sessions_pkey; Type: CONSTRAINT; Schema: ai; Owner: -
--

ALTER TABLE ONLY ai.agno_sessions
    ADD CONSTRAINT agno_sessions_pkey PRIMARY KEY (session_id);


--
-- Name: agno_spans agno_spans_pkey; Type: CONSTRAINT; Schema: ai; Owner: -
--

ALTER TABLE ONLY ai.agno_spans
    ADD CONSTRAINT agno_spans_pkey PRIMARY KEY (span_id);


--
-- Name: agno_traces agno_traces_pkey; Type: CONSTRAINT; Schema: ai; Owner: -
--

ALTER TABLE ONLY ai.agno_traces
    ADD CONSTRAINT agno_traces_pkey PRIMARY KEY (trace_id);


--
-- Name: api_keys api_keys_key_key; Type: CONSTRAINT; Schema: ai; Owner: -
--

ALTER TABLE ONLY ai.api_keys
    ADD CONSTRAINT api_keys_key_key UNIQUE (key);


--
-- Name: api_keys api_keys_pkey; Type: CONSTRAINT; Schema: ai; Owner: -
--

ALTER TABLE ONLY ai.api_keys
    ADD CONSTRAINT api_keys_pkey PRIMARY KEY (id);


--
-- Name: casebible_evidence_contents casebible_evidence_contents_pkey; Type: CONSTRAINT; Schema: ai; Owner: -
--

ALTER TABLE ONLY ai.casebible_evidence_contents
    ADD CONSTRAINT casebible_evidence_contents_pkey PRIMARY KEY (id);


--
-- Name: casebible_evidence_test_contents casebible_evidence_test_contents_pkey; Type: CONSTRAINT; Schema: ai; Owner: -
--

ALTER TABLE ONLY ai.casebible_evidence_test_contents
    ADD CONSTRAINT casebible_evidence_test_contents_pkey PRIMARY KEY (id);


--
-- Name: casebible_ingest_test2_contents casebible_ingest_test2_contents_pkey; Type: CONSTRAINT; Schema: ai; Owner: -
--

ALTER TABLE ONLY ai.casebible_ingest_test2_contents
    ADD CONSTRAINT casebible_ingest_test2_contents_pkey PRIMARY KEY (id);


--
-- Name: casebible_ingest_test_contents casebible_ingest_test_contents_pkey; Type: CONSTRAINT; Schema: ai; Owner: -
--

ALTER TABLE ONLY ai.casebible_ingest_test_contents
    ADD CONSTRAINT casebible_ingest_test_contents_pkey PRIMARY KEY (id);


--
-- Name: platform_context_contents platform_context_contents_pkey; Type: CONSTRAINT; Schema: ai; Owner: -
--

ALTER TABLE ONLY ai.platform_context_contents
    ADD CONSTRAINT platform_context_contents_pkey PRIMARY KEY (id);


--
-- Name: platform_knowledge_contents platform_knowledge_contents_pkey; Type: CONSTRAINT; Schema: ai; Owner: -
--

ALTER TABLE ONLY ai.platform_knowledge_contents
    ADD CONSTRAINT platform_knowledge_contents_pkey PRIMARY KEY (id);


--
-- Name: completion_evidence completion_evidence_pkey; Type: CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.completion_evidence
    ADD CONSTRAINT completion_evidence_pkey PRIMARY KEY (id);


--
-- Name: corroboration_flag corroboration_flag_pkey; Type: CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.corroboration_flag
    ADD CONSTRAINT corroboration_flag_pkey PRIMARY KEY (flag_id);


--
-- Name: discovery_request discovery_request_pkey; Type: CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.discovery_request
    ADD CONSTRAINT discovery_request_pkey PRIMARY KEY (id);


--
-- Name: discovery_request_revision discovery_request_revision_pkey; Type: CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.discovery_request_revision
    ADD CONSTRAINT discovery_request_revision_pkey PRIMARY KEY (revision_id);


--
-- Name: evidence_item evidence_item_case_id_exhibit_number_key; Type: CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.evidence_item
    ADD CONSTRAINT evidence_item_case_id_exhibit_number_key UNIQUE (case_id, exhibit_number);


--
-- Name: evidence_item evidence_item_pkey; Type: CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.evidence_item
    ADD CONSTRAINT evidence_item_pkey PRIMARY KEY (id);


--
-- Name: evidence_task evidence_task_pkey; Type: CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.evidence_task
    ADD CONSTRAINT evidence_task_pkey PRIMARY KEY (id);


--
-- Name: evidence_task evidence_task_task_key_key; Type: CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.evidence_task
    ADD CONSTRAINT evidence_task_task_key_key UNIQUE (task_key);


--
-- Name: export_item export_item_pkey; Type: CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.export_item
    ADD CONSTRAINT export_item_pkey PRIMARY KEY (package_id, evidence_item_id);


--
-- Name: export_package export_package_pkey; Type: CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.export_package
    ADD CONSTRAINT export_package_pkey PRIMARY KEY (id);


--
-- Name: export export_pkey; Type: CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.export
    ADD CONSTRAINT export_pkey PRIMARY KEY (export_id);


--
-- Name: factor_citation factor_citation_evidence_item_id_factor_supports_factor_key; Type: CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.factor_citation
    ADD CONSTRAINT factor_citation_evidence_item_id_factor_supports_factor_key UNIQUE (evidence_item_id, factor, supports_factor);


--
-- Name: factor_citation factor_citation_pkey; Type: CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.factor_citation
    ADD CONSTRAINT factor_citation_pkey PRIMARY KEY (id);


--
-- Name: finding finding_pkey; Type: CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.finding
    ADD CONSTRAINT finding_pkey PRIMARY KEY (id);


--
-- Name: finding_version finding_version_pkey; Type: CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.finding_version
    ADD CONSTRAINT finding_version_pkey PRIMARY KEY (version_id);


--
-- Name: human_label_gold human_label_gold_pkey; Type: CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.human_label_gold
    ADD CONSTRAINT human_label_gold_pkey PRIMARY KEY (conversation_key, seq);


--
-- Name: human_label human_label_pkey; Type: CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.human_label
    ADD CONSTRAINT human_label_pkey PRIMARY KEY (conversation_key, seq);


--
-- Name: legal_timeline_event legal_timeline_event_pkey; Type: CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.legal_timeline_event
    ADD CONSTRAINT legal_timeline_event_pkey PRIMARY KEY (id);


--
-- Name: location_assertion location_assertion_pkey; Type: CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.location_assertion
    ADD CONSTRAINT location_assertion_pkey PRIMARY KEY (id);


--
-- Name: location_contradiction location_contradiction_pkey; Type: CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.location_contradiction
    ADD CONSTRAINT location_contradiction_pkey PRIMARY KEY (id);


--
-- Name: time_assertion no_overlapping_belief; Type: CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.time_assertion
    ADD CONSTRAINT no_overlapping_belief EXCLUDE USING gist (event_id WITH =, sys_period WITH &&);


--
-- Name: pattern_finding pattern_finding_pkey; Type: CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.pattern_finding
    ADD CONSTRAINT pattern_finding_pkey PRIMARY KEY (id);


--
-- Name: redaction redaction_pkey; Type: CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.redaction
    ADD CONSTRAINT redaction_pkey PRIMARY KEY (redaction_id);


--
-- Name: relational_classification relational_classification_pkey; Type: CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.relational_classification
    ADD CONSTRAINT relational_classification_pkey PRIMARY KEY (id);


--
-- Name: resolution_evidence resolution_evidence_pkey; Type: CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.resolution_evidence
    ADD CONSTRAINT resolution_evidence_pkey PRIMARY KEY (id);


--
-- Name: review_decision review_decision_pkey; Type: CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.review_decision
    ADD CONSTRAINT review_decision_pkey PRIMARY KEY (decision_id);


--
-- Name: review_task review_task_pkey; Type: CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.review_task
    ADD CONSTRAINT review_task_pkey PRIMARY KEY (task_id);


--
-- Name: score score_pkey; Type: CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.score
    ADD CONSTRAINT score_pkey PRIMARY KEY (score_id);


--
-- Name: task_dependency task_dependency_pkey; Type: CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.task_dependency
    ADD CONSTRAINT task_dependency_pkey PRIMARY KEY (task_id, depends_on, dep_kind);


--
-- Name: task_event task_event_pkey; Type: CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.task_event
    ADD CONSTRAINT task_event_pkey PRIMARY KEY (event_id);


--
-- Name: task_legal_link task_legal_link_pkey; Type: CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.task_legal_link
    ADD CONSTRAINT task_legal_link_pkey PRIMARY KEY (task_id, legal_issue_id, factor);


--
-- Name: task_person task_person_pkey; Type: CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.task_person
    ADD CONSTRAINT task_person_pkey PRIMARY KEY (task_id, person_id, role);


--
-- Name: task_revision task_revision_pkey; Type: CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.task_revision
    ADD CONSTRAINT task_revision_pkey PRIMARY KEY (revision_id);


--
-- Name: time_assertion time_assertion_pkey; Type: CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.time_assertion
    ADD CONSTRAINT time_assertion_pkey PRIMARY KEY (assertion_id);


--
-- Name: timeline_event timeline_event_event_key_key; Type: CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.timeline_event
    ADD CONSTRAINT timeline_event_event_key_key UNIQUE (event_key);


--
-- Name: timeline_event timeline_event_pkey; Type: CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.timeline_event
    ADD CONSTRAINT timeline_event_pkey PRIMARY KEY (event_id);


--
-- Name: acquisition acquisition_pkey; Type: CONSTRAINT; Schema: evidence; Owner: -
--

ALTER TABLE ONLY evidence.acquisition
    ADD CONSTRAINT acquisition_pkey PRIMARY KEY (id);


--
-- Name: artifact_metadata artifact_metadata_pkey; Type: CONSTRAINT; Schema: evidence; Owner: -
--

ALTER TABLE ONLY evidence.artifact_metadata
    ADD CONSTRAINT artifact_metadata_pkey PRIMARY KEY (id);


--
-- Name: custody_event custody_event_id_key; Type: CONSTRAINT; Schema: evidence; Owner: -
--

ALTER TABLE ONLY evidence.custody_event
    ADD CONSTRAINT custody_event_id_key UNIQUE (id);


--
-- Name: custody_event custody_event_pkey; Type: CONSTRAINT; Schema: evidence; Owner: -
--

ALTER TABLE ONLY evidence.custody_event
    ADD CONSTRAINT custody_event_pkey PRIMARY KEY (seq);


--
-- Name: evidence_hash evidence_hash_pkey; Type: CONSTRAINT; Schema: evidence; Owner: -
--

ALTER TABLE ONLY evidence.evidence_hash
    ADD CONSTRAINT evidence_hash_pkey PRIMARY KEY (id);


--
-- Name: evidence_hash evidence_hash_subject_ck; Type: CHECK CONSTRAINT; Schema: evidence; Owner: -
--

ALTER TABLE evidence.evidence_hash
    ADD CONSTRAINT evidence_hash_subject_ck CHECK (((level = 'H3'::text) OR (source_id IS NOT NULL) OR (file_node_id IS NOT NULL))) NOT VALID;


--
-- Name: file_node file_node_pkey; Type: CONSTRAINT; Schema: evidence; Owner: -
--

ALTER TABLE ONLY evidence.file_node
    ADD CONSTRAINT file_node_pkey PRIMARY KEY (id);


--
-- Name: gps_point gps_point_pkey; Type: CONSTRAINT; Schema: evidence; Owner: -
--

ALTER TABLE ONLY evidence.gps_point
    ADD CONSTRAINT gps_point_pkey PRIMARY KEY (id);


--
-- Name: ingest_run ingest_run_pkey; Type: CONSTRAINT; Schema: evidence; Owner: -
--

ALTER TABLE ONLY evidence.ingest_run
    ADD CONSTRAINT ingest_run_pkey PRIMARY KEY (id);


--
-- Name: raw_activity raw_activity_pkey; Type: CONSTRAINT; Schema: evidence; Owner: -
--

ALTER TABLE ONLY evidence.raw_activity
    ADD CONSTRAINT raw_activity_pkey PRIMARY KEY (id);


--
-- Name: raw_ai_chat raw_ai_chat_pkey; Type: CONSTRAINT; Schema: evidence; Owner: -
--

ALTER TABLE ONLY evidence.raw_ai_chat
    ADD CONSTRAINT raw_ai_chat_pkey PRIMARY KEY (id);


--
-- Name: raw_csv raw_csv_pkey; Type: CONSTRAINT; Schema: evidence; Owner: -
--

ALTER TABLE ONLY evidence.raw_csv
    ADD CONSTRAINT raw_csv_pkey PRIMARY KEY (id);


--
-- Name: raw_facebook raw_facebook_pkey; Type: CONSTRAINT; Schema: evidence; Owner: -
--

ALTER TABLE ONLY evidence.raw_facebook
    ADD CONSTRAINT raw_facebook_pkey PRIMARY KEY (id);


--
-- Name: raw_imessage raw_imessage_pkey; Type: CONSTRAINT; Schema: evidence; Owner: -
--

ALTER TABLE ONLY evidence.raw_imessage
    ADD CONSTRAINT raw_imessage_pkey PRIMARY KEY (id);


--
-- Name: raw_path raw_path_pkey; Type: CONSTRAINT; Schema: evidence; Owner: -
--

ALTER TABLE ONLY evidence.raw_path
    ADD CONSTRAINT raw_path_pkey PRIMARY KEY (id);


--
-- Name: raw_phone raw_phone_pkey; Type: CONSTRAINT; Schema: evidence; Owner: -
--

ALTER TABLE ONLY evidence.raw_phone
    ADD CONSTRAINT raw_phone_pkey PRIMARY KEY (id);


--
-- Name: raw_rejected raw_rejected_pkey; Type: CONSTRAINT; Schema: evidence; Owner: -
--

ALTER TABLE ONLY evidence.raw_rejected
    ADD CONSTRAINT raw_rejected_pkey PRIMARY KEY (id);


--
-- Name: raw_sms raw_sms_pkey; Type: CONSTRAINT; Schema: evidence; Owner: -
--

ALTER TABLE ONLY evidence.raw_sms
    ADD CONSTRAINT raw_sms_pkey PRIMARY KEY (id);


--
-- Name: raw_trip raw_trip_pkey; Type: CONSTRAINT; Schema: evidence; Owner: -
--

ALTER TABLE ONLY evidence.raw_trip
    ADD CONSTRAINT raw_trip_pkey PRIMARY KEY (id);


--
-- Name: raw_visit raw_visit_pkey; Type: CONSTRAINT; Schema: evidence; Owner: -
--

ALTER TABLE ONLY evidence.raw_visit
    ADD CONSTRAINT raw_visit_pkey PRIMARY KEY (id);


--
-- Name: source source_pkey; Type: CONSTRAINT; Schema: evidence; Owner: -
--

ALTER TABLE ONLY evidence.source
    ADD CONSTRAINT source_pkey PRIMARY KEY (id);


--
-- Name: source source_sha256_uniq; Type: CONSTRAINT; Schema: evidence; Owner: -
--

ALTER TABLE ONLY evidence.source
    ADD CONSTRAINT source_sha256_uniq UNIQUE (sha256);


--
-- Name: geocode_audit geocode_audit_pkey; Type: CONSTRAINT; Schema: ops; Owner: -
--

ALTER TABLE ONLY ops.geocode_audit
    ADD CONSTRAINT geocode_audit_pkey PRIMARY KEY (id);


--
-- Name: processing_run processing_run_pkey; Type: CONSTRAINT; Schema: ops; Owner: -
--

ALTER TABLE ONLY ops.processing_run
    ADD CONSTRAINT processing_run_pkey PRIMARY KEY (run_id);


--
-- Name: processing_run processing_run_replayable_needs_code_ref; Type: CHECK CONSTRAINT; Schema: ops; Owner: -
--

ALTER TABLE ops.processing_run
    ADD CONSTRAINT processing_run_replayable_needs_code_ref CHECK (((NOT replayable) OR (code_ref IS NOT NULL))) NOT VALID;


--
-- Name: tool_call_ledger tool_call_ledger_pkey; Type: CONSTRAINT; Schema: ops; Owner: -
--

ALTER TABLE ONLY ops.tool_call_ledger
    ADD CONSTRAINT tool_call_ledger_pkey PRIMARY KEY (tool_call_id);


--
-- Name: workflow_run workflow_run_pkey; Type: CONSTRAINT; Schema: ops; Owner: -
--

ALTER TABLE ONLY ops.workflow_run
    ADD CONSTRAINT workflow_run_pkey PRIMARY KEY (run_id);


--
-- Name: workflow_run_stage workflow_run_stage_pkey; Type: CONSTRAINT; Schema: ops; Owner: -
--

ALTER TABLE ONLY ops.workflow_run_stage
    ADD CONSTRAINT workflow_run_stage_pkey PRIMARY KEY (stage_id);


--
-- Name: workflow_run_stage workflow_run_stage_run_id_seq_key; Type: CONSTRAINT; Schema: ops; Owner: -
--

ALTER TABLE ONLY ops.workflow_run_stage
    ADD CONSTRAINT workflow_run_stage_run_id_seq_key UNIQUE (run_id, seq);


--
-- Name: agent_run agent_run_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agent_run
    ADD CONSTRAINT agent_run_pkey PRIMARY KEY (id);


--
-- Name: app_setting app_setting_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_setting
    ADD CONSTRAINT app_setting_pkey PRIMARY KEY (key);


--
-- Name: approval_request approval_request_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.approval_request
    ADD CONSTRAINT approval_request_pkey PRIMARY KEY (id);


--
-- Name: canon_registry canon_registry_canon_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.canon_registry
    ADD CONSTRAINT canon_registry_canon_name_key UNIQUE (canon_name);


--
-- Name: canon_registry canon_registry_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.canon_registry
    ADD CONSTRAINT canon_registry_pkey PRIMARY KEY (id);


--
-- Name: change_log change_log_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.change_log
    ADD CONSTRAINT change_log_pkey PRIMARY KEY (change_id);


--
-- Name: classification_version classification_version_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.classification_version
    ADD CONSTRAINT classification_version_pkey PRIMARY KEY (classification_version_id);


--
-- Name: classification_version classification_version_version_label_scheme_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.classification_version
    ADD CONSTRAINT classification_version_version_label_scheme_key UNIQUE (version_label, scheme);


--
-- Name: decision_log decision_log_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.decision_log
    ADD CONSTRAINT decision_log_pkey PRIMARY KEY (decision_id);


--
-- Name: decision_precedent decision_precedent_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.decision_precedent
    ADD CONSTRAINT decision_precedent_pkey PRIMARY KEY (precedent_id);


--
-- Name: memory_items memory_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.memory_items
    ADD CONSTRAINT memory_items_pkey PRIMARY KEY (memory_id);


--
-- Name: model_version model_version_model_id_role_version_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.model_version
    ADD CONSTRAINT model_version_model_id_role_version_key UNIQUE (model_id, role, version);


--
-- Name: model_version model_version_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.model_version
    ADD CONSTRAINT model_version_pkey PRIMARY KEY (model_version_id);


--
-- Name: ontology_version ontology_version_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ontology_version
    ADD CONSTRAINT ontology_version_pkey PRIMARY KEY (ontology_version_id);


--
-- Name: ontology_version ontology_version_version_label_source_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ontology_version
    ADD CONSTRAINT ontology_version_version_label_source_key UNIQUE (version_label, source);


--
-- Name: open_questions open_questions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.open_questions
    ADD CONSTRAINT open_questions_pkey PRIMARY KEY (question_id);


--
-- Name: prompt_registry prompt_registry_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.prompt_registry
    ADD CONSTRAINT prompt_registry_pkey PRIMARY KEY (prompt_id);


--
-- Name: prompt_registry prompt_registry_prompt_name_prompt_version_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.prompt_registry
    ADD CONSTRAINT prompt_registry_prompt_name_prompt_version_key UNIQUE (prompt_name, prompt_version);


--
-- Name: schema_version schema_version_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_version
    ADD CONSTRAINT schema_version_pkey PRIMARY KEY (schema_version_id);


--
-- Name: schema_version schema_version_version_label_applies_to_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_version
    ADD CONSTRAINT schema_version_version_label_applies_to_key UNIQUE (version_label, applies_to);


--
-- Name: session_summaries session_summaries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.session_summaries
    ADD CONSTRAINT session_summaries_pkey PRIMARY KEY (session_id);


--
-- Name: transcript_insight transcript_insight_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transcript_insight
    ADD CONSTRAINT transcript_insight_pkey PRIMARY KEY (id);


--
-- Name: behavior_category_mcl behavior_category_mcl_pkey; Type: CONSTRAINT; Schema: reference; Owner: -
--

ALTER TABLE ONLY reference.behavior_category_mcl
    ADD CONSTRAINT behavior_category_mcl_pkey PRIMARY KEY (category_id, factor_code);


--
-- Name: behavior_category behavior_category_pkey; Type: CONSTRAINT; Schema: reference; Owner: -
--

ALTER TABLE ONLY reference.behavior_category
    ADD CONSTRAINT behavior_category_pkey PRIMARY KEY (category_id);


--
-- Name: custody_factor custody_factor_pkey; Type: CONSTRAINT; Schema: reference; Owner: -
--

ALTER TABLE ONLY reference.custody_factor
    ADD CONSTRAINT custody_factor_pkey PRIMARY KEY (factor);


--
-- Name: detection_pattern detection_pattern_pattern_set_id_category_id_match_type_pat_key; Type: CONSTRAINT; Schema: reference; Owner: -
--

ALTER TABLE ONLY reference.detection_pattern
    ADD CONSTRAINT detection_pattern_pattern_set_id_category_id_match_type_pat_key UNIQUE (pattern_set_id, category_id, match_type, pattern);


--
-- Name: detection_pattern detection_pattern_pkey; Type: CONSTRAINT; Schema: reference; Owner: -
--

ALTER TABLE ONLY reference.detection_pattern
    ADD CONSTRAINT detection_pattern_pkey PRIMARY KEY (id);


--
-- Name: detection_pattern_set detection_pattern_set_name_version_key; Type: CONSTRAINT; Schema: reference; Owner: -
--

ALTER TABLE ONLY reference.detection_pattern_set
    ADD CONSTRAINT detection_pattern_set_name_version_key UNIQUE (name, version);


--
-- Name: detection_pattern_set detection_pattern_set_pkey; Type: CONSTRAINT; Schema: reference; Owner: -
--

ALTER TABLE ONLY reference.detection_pattern_set
    ADD CONSTRAINT detection_pattern_set_pkey PRIMARY KEY (id);


--
-- Name: format_resolver format_resolver_pkey; Type: CONSTRAINT; Schema: reference; Owner: -
--

ALTER TABLE ONLY reference.format_resolver
    ADD CONSTRAINT format_resolver_pkey PRIMARY KEY (id);


--
-- Name: format_resolver format_resolver_source_signature_target_schema_key; Type: CONSTRAINT; Schema: reference; Owner: -
--

ALTER TABLE ONLY reference.format_resolver
    ADD CONSTRAINT format_resolver_source_signature_target_schema_key UNIQUE (source_signature, target_schema);


--
-- Name: geofence geofence_pkey; Type: CONSTRAINT; Schema: reference; Owner: -
--

ALTER TABLE ONLY reference.geofence
    ADD CONSTRAINT geofence_pkey PRIMARY KEY (id);


--
-- Name: legal_issue legal_issue_case_id_issue_key_key; Type: CONSTRAINT; Schema: reference; Owner: -
--

ALTER TABLE ONLY reference.legal_issue
    ADD CONSTRAINT legal_issue_case_id_issue_key_key UNIQUE (case_id, issue_key);


--
-- Name: legal_issue_factor legal_issue_factor_pkey; Type: CONSTRAINT; Schema: reference; Owner: -
--

ALTER TABLE ONLY reference.legal_issue_factor
    ADD CONSTRAINT legal_issue_factor_pkey PRIMARY KEY (legal_issue_id, factor);


--
-- Name: legal_issue legal_issue_pkey; Type: CONSTRAINT; Schema: reference; Owner: -
--

ALTER TABLE ONLY reference.legal_issue
    ADD CONSTRAINT legal_issue_pkey PRIMARY KEY (id);


--
-- Name: lexicon_sync lexicon_sync_pkey; Type: CONSTRAINT; Schema: reference; Owner: -
--

ALTER TABLE ONLY reference.lexicon_sync
    ADD CONSTRAINT lexicon_sync_pkey PRIMARY KEY (id);


--
-- Name: pattern_lexicon pattern_lexicon_pkey; Type: CONSTRAINT; Schema: reference; Owner: -
--

ALTER TABLE ONLY reference.pattern_lexicon
    ADD CONSTRAINT pattern_lexicon_pkey PRIMARY KEY (id);


--
-- Name: relative_rule relative_rule_pkey; Type: CONSTRAINT; Schema: reference; Owner: -
--

ALTER TABLE ONLY reference.relative_rule
    ADD CONSTRAINT relative_rule_pkey PRIMARY KEY (rule_id);


--
-- Name: score_band_config score_band_config_pkey; Type: CONSTRAINT; Schema: reference; Owner: -
--

ALTER TABLE ONLY reference.score_band_config
    ADD CONSTRAINT score_band_config_pkey PRIMARY KEY (config_version);


--
-- Name: topic_code topic_code_pkey; Type: CONSTRAINT; Schema: reference; Owner: -
--

ALTER TABLE ONLY reference.topic_code
    ADD CONSTRAINT topic_code_pkey PRIMARY KEY (code);


--
-- Name: account account_pkey; Type: CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.account
    ADD CONSTRAINT account_pkey PRIMARY KEY (id);


--
-- Name: artifact_registry artifact_registry_pkey; Type: CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.artifact_registry
    ADD CONSTRAINT artifact_registry_pkey PRIMARY KEY (artifact_id);


--
-- Name: attachment attachment_pkey; Type: CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.attachment
    ADD CONSTRAINT attachment_pkey PRIMARY KEY (id);


--
-- Name: block_status block_status_pkey; Type: CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.block_status
    ADD CONSTRAINT block_status_pkey PRIMARY KEY (id);


--
-- Name: call_log call_log_pkey; Type: CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.call_log
    ADD CONSTRAINT call_log_pkey PRIMARY KEY (id);


--
-- Name: candidate_entity candidate_entity_pkey; Type: CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.candidate_entity
    ADD CONSTRAINT candidate_entity_pkey PRIMARY KEY (id);


--
-- Name: candidate_event candidate_event_pkey; Type: CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.candidate_event
    ADD CONSTRAINT candidate_event_pkey PRIMARY KEY (id);


--
-- Name: candidate_fact candidate_fact_pkey; Type: CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.candidate_fact
    ADD CONSTRAINT candidate_fact_pkey PRIMARY KEY (id);


--
-- Name: conversation_group_member conversation_group_member_pkey; Type: CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.conversation_group_member
    ADD CONSTRAINT conversation_group_member_pkey PRIMARY KEY (id);


--
-- Name: conversation_group conversation_group_pkey; Type: CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.conversation_group
    ADD CONSTRAINT conversation_group_pkey PRIMARY KEY (id);


--
-- Name: conversation conversation_pkey; Type: CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.conversation
    ADD CONSTRAINT conversation_pkey PRIMARY KEY (id);


--
-- Name: device_ownership device_ownership_no_overlap; Type: CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.device_ownership
    ADD CONSTRAINT device_ownership_no_overlap EXCLUDE USING gist (device_id WITH =, tstzrange(effective_from, COALESCE(effective_to, 'infinity'::timestamp with time zone)) WITH &&);


--
-- Name: device_ownership device_ownership_pkey; Type: CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.device_ownership
    ADD CONSTRAINT device_ownership_pkey PRIMARY KEY (id);


--
-- Name: device device_pkey; Type: CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.device
    ADD CONSTRAINT device_pkey PRIMARY KEY (id);


--
-- Name: email email_address_validity_excl; Type: CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.email
    ADD CONSTRAINT email_address_validity_excl EXCLUDE USING gist (((address)::text) WITH =, validity WITH &&) WHERE ((address IS NOT NULL));


--
-- Name: email email_pkey; Type: CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.email
    ADD CONSTRAINT email_pkey PRIMARY KEY (id);


--
-- Name: entity_alias entity_alias_pkey; Type: CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.entity_alias
    ADD CONSTRAINT entity_alias_pkey PRIMARY KEY (id);


--
-- Name: extraction_candidate entity_candidate_pkey; Type: CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.extraction_candidate
    ADD CONSTRAINT entity_candidate_pkey PRIMARY KEY (id);


--
-- Name: entity_mention entity_mention_pkey; Type: CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.entity_mention
    ADD CONSTRAINT entity_mention_pkey PRIMARY KEY (id);


--
-- Name: entity_merge_event entity_merge_event_pkey; Type: CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.entity_merge_event
    ADD CONSTRAINT entity_merge_event_pkey PRIMARY KEY (id);


--
-- Name: entity entity_pkey; Type: CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.entity
    ADD CONSTRAINT entity_pkey PRIMARY KEY (id);


--
-- Name: entity_resolution entity_resolution_pkey; Type: CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.entity_resolution
    ADD CONSTRAINT entity_resolution_pkey PRIMARY KEY (id);


--
-- Name: event_ordering event_ordering_pkey; Type: CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.event_ordering
    ADD CONSTRAINT event_ordering_pkey PRIMARY KEY (ordering_id);


--
-- Name: event_source_record event_source_record_pkey; Type: CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.event_source_record
    ADD CONSTRAINT event_source_record_pkey PRIMARY KEY (link_id);


--
-- Name: extraction_batch extraction_batch_pkey; Type: CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.extraction_batch
    ADD CONSTRAINT extraction_batch_pkey PRIMARY KEY (id);


--
-- Name: extraction_run extraction_run_pkey; Type: CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.extraction_run
    ADD CONSTRAINT extraction_run_pkey PRIMARY KEY (id);


--
-- Name: geocode_request geocode_request_pkey; Type: CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.geocode_request
    ADD CONSTRAINT geocode_request_pkey PRIMARY KEY (id);


--
-- Name: geocode_resolution geocode_resolution_pkey; Type: CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.geocode_resolution
    ADD CONSTRAINT geocode_resolution_pkey PRIMARY KEY (id);


--
-- Name: geocode_result geocode_result_pkey; Type: CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.geocode_result
    ADD CONSTRAINT geocode_result_pkey PRIMARY KEY (id);


--
-- Name: gps_track gps_track_pkey; Type: CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.gps_track
    ADD CONSTRAINT gps_track_pkey PRIMARY KEY (id);


--
-- Name: handle handle_pkey; Type: CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.handle
    ADD CONSTRAINT handle_pkey PRIMARY KEY (id);


--
-- Name: handle handle_platform_handle_validity_excl; Type: CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.handle
    ADD CONSTRAINT handle_platform_handle_validity_excl EXCLUDE USING gist (platform WITH =, ((handle)::text) WITH =, validity WITH &&);


--
-- Name: home_base home_base_pkey; Type: CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.home_base
    ADD CONSTRAINT home_base_pkey PRIMARY KEY (id);


--
-- Name: id_xref id_xref_pkey; Type: CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.id_xref
    ADD CONSTRAINT id_xref_pkey PRIMARY KEY (id);


--
-- Name: lineage_edge lineage_edge_pkey; Type: CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.lineage_edge
    ADD CONSTRAINT lineage_edge_pkey PRIMARY KEY (edge_id);


--
-- Name: location location_pkey; Type: CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.location
    ADD CONSTRAINT location_pkey PRIMARY KEY (id);


--
-- Name: message_participant message_participant_pkey; Type: CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.message_participant
    ADD CONSTRAINT message_participant_pkey PRIMARY KEY (id);


--
-- Name: message message_pkey; Type: CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.message
    ADD CONSTRAINT message_pkey PRIMARY KEY (id);


--
-- Name: normalized_record normalized_record_pkey; Type: CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.normalized_record
    ADD CONSTRAINT normalized_record_pkey PRIMARY KEY (id);


--
-- Name: normalized_record normrec_clock_ordering; Type: CHECK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE working.normalized_record
    ADD CONSTRAINT normrec_clock_ordering CHECK ((((realized_at IS NULL) OR (occurred_at IS NULL) OR (realized_at >= occurred_at)) AND ((acquired_at IS NULL) OR (occurred_at IS NULL) OR (acquired_at >= occurred_at)))) NOT VALID;


--
-- Name: organization organization_pkey; Type: CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.organization
    ADD CONSTRAINT organization_pkey PRIMARY KEY (id);


--
-- Name: person person_pkey; Type: CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.person
    ADD CONSTRAINT person_pkey PRIMARY KEY (id);


--
-- Name: phone phone_e164_validity_excl; Type: CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.phone
    ADD CONSTRAINT phone_e164_validity_excl EXCLUDE USING gist (((e164)::text) WITH =, validity WITH &&) WHERE ((e164 IS NOT NULL));


--
-- Name: phone phone_pkey; Type: CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.phone
    ADD CONSTRAINT phone_pkey PRIMARY KEY (id);


--
-- Name: promotion promotion_pkey; Type: CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.promotion
    ADD CONSTRAINT promotion_pkey PRIMARY KEY (id);


--
-- Name: record_observation record_observation_pkey; Type: CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.record_observation
    ADD CONSTRAINT record_observation_pkey PRIMARY KEY (id);


--
-- Name: review_decision review_decision_pkey; Type: CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.review_decision
    ADD CONSTRAINT review_decision_pkey PRIMARY KEY (id);


--
-- Name: source_provenance source_provenance_pkey; Type: CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.source_provenance
    ADD CONSTRAINT source_provenance_pkey PRIMARY KEY (id);


--
-- Name: stay_point stay_point_pkey; Type: CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.stay_point
    ADD CONSTRAINT stay_point_pkey PRIMARY KEY (id);


--
-- Name: temporal_anchor temporal_anchor_anchor_key_key; Type: CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.temporal_anchor
    ADD CONSTRAINT temporal_anchor_anchor_key_key UNIQUE (anchor_key);


--
-- Name: temporal_anchor temporal_anchor_pkey; Type: CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.temporal_anchor
    ADD CONSTRAINT temporal_anchor_pkey PRIMARY KEY (anchor_id);


--
-- Name: conversation uq_conversation_thread; Type: CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.conversation
    ADD CONSTRAINT uq_conversation_thread UNIQUE (platform, external_thread_key);


--
-- Name: conversation_group_member uq_convgrp_member; Type: CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.conversation_group_member
    ADD CONSTRAINT uq_convgrp_member UNIQUE (group_id, conversation_id);


--
-- Name: message uq_message_thread_extid; Type: CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.message
    ADD CONSTRAINT uq_message_thread_extid UNIQUE (conversation_id, external_id);


--
-- Name: message_participant uq_msg_part; Type: CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.message_participant
    ADD CONSTRAINT uq_msg_part UNIQUE (message_id, role, participant_raw);


--
-- Name: id_xref uq_xref_pair; Type: CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.id_xref
    ADD CONSTRAINT uq_xref_pair UNIQUE (system_a, native_id_a, system_b, native_id_b);


--
-- Name: vehicle vehicle_pkey; Type: CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.vehicle
    ADD CONSTRAINT vehicle_pkey PRIMARY KEY (id);


--
-- Name: waypoint_device_split waypoint_device_split_pkey; Type: CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.waypoint_device_split
    ADD CONSTRAINT waypoint_device_split_pkey PRIMARY KEY (split_id);


--
-- Name: agno_service_accounts_uq_active_name; Type: INDEX; Schema: ai; Owner: -
--

CREATE UNIQUE INDEX agno_service_accounts_uq_active_name ON ai.agno_service_accounts USING btree (name) WHERE (revoked_at IS NULL);


--
-- Name: idx_agno_approvals_agent_id; Type: INDEX; Schema: ai; Owner: -
--

CREATE INDEX idx_agno_approvals_agent_id ON ai.agno_approvals USING btree (agent_id);


--
-- Name: idx_agno_approvals_approval_type; Type: INDEX; Schema: ai; Owner: -
--

CREATE INDEX idx_agno_approvals_approval_type ON ai.agno_approvals USING btree (approval_type);


--
-- Name: idx_agno_approvals_created_at; Type: INDEX; Schema: ai; Owner: -
--

CREATE INDEX idx_agno_approvals_created_at ON ai.agno_approvals USING btree (created_at);


--
-- Name: idx_agno_approvals_pause_type; Type: INDEX; Schema: ai; Owner: -
--

CREATE INDEX idx_agno_approvals_pause_type ON ai.agno_approvals USING btree (pause_type);


--
-- Name: idx_agno_approvals_run_id; Type: INDEX; Schema: ai; Owner: -
--

CREATE INDEX idx_agno_approvals_run_id ON ai.agno_approvals USING btree (run_id);


--
-- Name: idx_agno_approvals_run_status; Type: INDEX; Schema: ai; Owner: -
--

CREATE INDEX idx_agno_approvals_run_status ON ai.agno_approvals USING btree (run_status);


--
-- Name: idx_agno_approvals_schedule_id; Type: INDEX; Schema: ai; Owner: -
--

CREATE INDEX idx_agno_approvals_schedule_id ON ai.agno_approvals USING btree (schedule_id);


--
-- Name: idx_agno_approvals_schedule_run_id; Type: INDEX; Schema: ai; Owner: -
--

CREATE INDEX idx_agno_approvals_schedule_run_id ON ai.agno_approvals USING btree (schedule_run_id);


--
-- Name: idx_agno_approvals_session_id; Type: INDEX; Schema: ai; Owner: -
--

CREATE INDEX idx_agno_approvals_session_id ON ai.agno_approvals USING btree (session_id);


--
-- Name: idx_agno_approvals_source_type; Type: INDEX; Schema: ai; Owner: -
--

CREATE INDEX idx_agno_approvals_source_type ON ai.agno_approvals USING btree (source_type);


--
-- Name: idx_agno_approvals_status; Type: INDEX; Schema: ai; Owner: -
--

CREATE INDEX idx_agno_approvals_status ON ai.agno_approvals USING btree (status);


--
-- Name: idx_agno_approvals_team_id; Type: INDEX; Schema: ai; Owner: -
--

CREATE INDEX idx_agno_approvals_team_id ON ai.agno_approvals USING btree (team_id);


--
-- Name: idx_agno_approvals_user_id; Type: INDEX; Schema: ai; Owner: -
--

CREATE INDEX idx_agno_approvals_user_id ON ai.agno_approvals USING btree (user_id);


--
-- Name: idx_agno_approvals_workflow_id; Type: INDEX; Schema: ai; Owner: -
--

CREATE INDEX idx_agno_approvals_workflow_id ON ai.agno_approvals USING btree (workflow_id);


--
-- Name: idx_agno_component_configs_created_at; Type: INDEX; Schema: ai; Owner: -
--

CREATE INDEX idx_agno_component_configs_created_at ON ai.agno_component_configs USING btree (created_at);


--
-- Name: idx_agno_component_configs_stage; Type: INDEX; Schema: ai; Owner: -
--

CREATE INDEX idx_agno_component_configs_stage ON ai.agno_component_configs USING btree (stage);


--
-- Name: idx_agno_component_links_created_at; Type: INDEX; Schema: ai; Owner: -
--

CREATE INDEX idx_agno_component_links_created_at ON ai.agno_component_links USING btree (created_at);


--
-- Name: idx_agno_component_links_link_kind; Type: INDEX; Schema: ai; Owner: -
--

CREATE INDEX idx_agno_component_links_link_kind ON ai.agno_component_links USING btree (link_kind);


--
-- Name: idx_agno_components_component_type; Type: INDEX; Schema: ai; Owner: -
--

CREATE INDEX idx_agno_components_component_type ON ai.agno_components USING btree (component_type);


--
-- Name: idx_agno_components_created_at; Type: INDEX; Schema: ai; Owner: -
--

CREATE INDEX idx_agno_components_created_at ON ai.agno_components USING btree (created_at);


--
-- Name: idx_agno_components_current_version; Type: INDEX; Schema: ai; Owner: -
--

CREATE INDEX idx_agno_components_current_version ON ai.agno_components USING btree (current_version);


--
-- Name: idx_agno_components_name; Type: INDEX; Schema: ai; Owner: -
--

CREATE INDEX idx_agno_components_name ON ai.agno_components USING btree (name);


--
-- Name: idx_agno_eval_runs_created_at; Type: INDEX; Schema: ai; Owner: -
--

CREATE INDEX idx_agno_eval_runs_created_at ON ai.agno_eval_runs USING btree (created_at);


--
-- Name: idx_agno_learnings_agent_id; Type: INDEX; Schema: ai; Owner: -
--

CREATE INDEX idx_agno_learnings_agent_id ON ai.agno_learnings USING btree (agent_id);


--
-- Name: idx_agno_learnings_created_at; Type: INDEX; Schema: ai; Owner: -
--

CREATE INDEX idx_agno_learnings_created_at ON ai.agno_learnings USING btree (created_at);


--
-- Name: idx_agno_learnings_entity_id; Type: INDEX; Schema: ai; Owner: -
--

CREATE INDEX idx_agno_learnings_entity_id ON ai.agno_learnings USING btree (entity_id);


--
-- Name: idx_agno_learnings_entity_type; Type: INDEX; Schema: ai; Owner: -
--

CREATE INDEX idx_agno_learnings_entity_type ON ai.agno_learnings USING btree (entity_type);


--
-- Name: idx_agno_learnings_learning_type; Type: INDEX; Schema: ai; Owner: -
--

CREATE INDEX idx_agno_learnings_learning_type ON ai.agno_learnings USING btree (learning_type);


--
-- Name: idx_agno_learnings_namespace; Type: INDEX; Schema: ai; Owner: -
--

CREATE INDEX idx_agno_learnings_namespace ON ai.agno_learnings USING btree (namespace);


--
-- Name: idx_agno_learnings_session_id; Type: INDEX; Schema: ai; Owner: -
--

CREATE INDEX idx_agno_learnings_session_id ON ai.agno_learnings USING btree (session_id);


--
-- Name: idx_agno_learnings_team_id; Type: INDEX; Schema: ai; Owner: -
--

CREATE INDEX idx_agno_learnings_team_id ON ai.agno_learnings USING btree (team_id);


--
-- Name: idx_agno_learnings_user_id; Type: INDEX; Schema: ai; Owner: -
--

CREATE INDEX idx_agno_learnings_user_id ON ai.agno_learnings USING btree (user_id);


--
-- Name: idx_agno_learnings_workflow_id; Type: INDEX; Schema: ai; Owner: -
--

CREATE INDEX idx_agno_learnings_workflow_id ON ai.agno_learnings USING btree (workflow_id);


--
-- Name: idx_agno_memories_created_at; Type: INDEX; Schema: ai; Owner: -
--

CREATE INDEX idx_agno_memories_created_at ON ai.agno_memories USING btree (created_at);


--
-- Name: idx_agno_memories_updated_at; Type: INDEX; Schema: ai; Owner: -
--

CREATE INDEX idx_agno_memories_updated_at ON ai.agno_memories USING btree (updated_at);


--
-- Name: idx_agno_memories_user_id; Type: INDEX; Schema: ai; Owner: -
--

CREATE INDEX idx_agno_memories_user_id ON ai.agno_memories USING btree (user_id);


--
-- Name: idx_agno_metrics_date; Type: INDEX; Schema: ai; Owner: -
--

CREATE INDEX idx_agno_metrics_date ON ai.agno_metrics USING btree (date);


--
-- Name: idx_agno_schedule_runs_created_at; Type: INDEX; Schema: ai; Owner: -
--

CREATE INDEX idx_agno_schedule_runs_created_at ON ai.agno_schedule_runs USING btree (created_at);


--
-- Name: idx_agno_schedule_runs_schedule_id; Type: INDEX; Schema: ai; Owner: -
--

CREATE INDEX idx_agno_schedule_runs_schedule_id ON ai.agno_schedule_runs USING btree (schedule_id);


--
-- Name: idx_agno_schedule_runs_status; Type: INDEX; Schema: ai; Owner: -
--

CREATE INDEX idx_agno_schedule_runs_status ON ai.agno_schedule_runs USING btree (status);


--
-- Name: idx_agno_schedules_created_at; Type: INDEX; Schema: ai; Owner: -
--

CREATE INDEX idx_agno_schedules_created_at ON ai.agno_schedules USING btree (created_at);


--
-- Name: idx_agno_schedules_enabled_next_run_at; Type: INDEX; Schema: ai; Owner: -
--

CREATE INDEX idx_agno_schedules_enabled_next_run_at ON ai.agno_schedules USING btree (enabled, next_run_at);


--
-- Name: idx_agno_schedules_name; Type: INDEX; Schema: ai; Owner: -
--

CREATE INDEX idx_agno_schedules_name ON ai.agno_schedules USING btree (name);


--
-- Name: idx_agno_schedules_next_run_at; Type: INDEX; Schema: ai; Owner: -
--

CREATE INDEX idx_agno_schedules_next_run_at ON ai.agno_schedules USING btree (next_run_at);


--
-- Name: idx_agno_schema_versions_created_at; Type: INDEX; Schema: ai; Owner: -
--

CREATE INDEX idx_agno_schema_versions_created_at ON ai.agno_schema_versions USING btree (created_at);


--
-- Name: idx_agno_service_accounts_created_at; Type: INDEX; Schema: ai; Owner: -
--

CREATE INDEX idx_agno_service_accounts_created_at ON ai.agno_service_accounts USING btree (created_at);


--
-- Name: idx_agno_service_accounts_token_hash; Type: INDEX; Schema: ai; Owner: -
--

CREATE INDEX idx_agno_service_accounts_token_hash ON ai.agno_service_accounts USING btree (token_hash);


--
-- Name: idx_agno_sessions_created_at; Type: INDEX; Schema: ai; Owner: -
--

CREATE INDEX idx_agno_sessions_created_at ON ai.agno_sessions USING btree (created_at);


--
-- Name: idx_agno_sessions_session_type; Type: INDEX; Schema: ai; Owner: -
--

CREATE INDEX idx_agno_sessions_session_type ON ai.agno_sessions USING btree (session_type);


--
-- Name: idx_agno_spans_created_at; Type: INDEX; Schema: ai; Owner: -
--

CREATE INDEX idx_agno_spans_created_at ON ai.agno_spans USING btree (created_at);


--
-- Name: idx_agno_spans_parent_span_id; Type: INDEX; Schema: ai; Owner: -
--

CREATE INDEX idx_agno_spans_parent_span_id ON ai.agno_spans USING btree (parent_span_id);


--
-- Name: idx_agno_spans_start_time; Type: INDEX; Schema: ai; Owner: -
--

CREATE INDEX idx_agno_spans_start_time ON ai.agno_spans USING btree (start_time);


--
-- Name: idx_agno_spans_trace_id; Type: INDEX; Schema: ai; Owner: -
--

CREATE INDEX idx_agno_spans_trace_id ON ai.agno_spans USING btree (trace_id);


--
-- Name: idx_agno_traces_agent_id; Type: INDEX; Schema: ai; Owner: -
--

CREATE INDEX idx_agno_traces_agent_id ON ai.agno_traces USING btree (agent_id);


--
-- Name: idx_agno_traces_created_at; Type: INDEX; Schema: ai; Owner: -
--

CREATE INDEX idx_agno_traces_created_at ON ai.agno_traces USING btree (created_at);


--
-- Name: idx_agno_traces_run_id; Type: INDEX; Schema: ai; Owner: -
--

CREATE INDEX idx_agno_traces_run_id ON ai.agno_traces USING btree (run_id);


--
-- Name: idx_agno_traces_session_id; Type: INDEX; Schema: ai; Owner: -
--

CREATE INDEX idx_agno_traces_session_id ON ai.agno_traces USING btree (session_id);


--
-- Name: idx_agno_traces_start_time; Type: INDEX; Schema: ai; Owner: -
--

CREATE INDEX idx_agno_traces_start_time ON ai.agno_traces USING btree (start_time);


--
-- Name: idx_agno_traces_status; Type: INDEX; Schema: ai; Owner: -
--

CREATE INDEX idx_agno_traces_status ON ai.agno_traces USING btree (status);


--
-- Name: idx_agno_traces_team_id; Type: INDEX; Schema: ai; Owner: -
--

CREATE INDEX idx_agno_traces_team_id ON ai.agno_traces USING btree (team_id);


--
-- Name: idx_agno_traces_user_id; Type: INDEX; Schema: ai; Owner: -
--

CREATE INDEX idx_agno_traces_user_id ON ai.agno_traces USING btree (user_id);


--
-- Name: idx_agno_traces_workflow_id; Type: INDEX; Schema: ai; Owner: -
--

CREATE INDEX idx_agno_traces_workflow_id ON ai.agno_traces USING btree (workflow_id);


--
-- Name: idx_corroboration_flag_status; Type: INDEX; Schema: analysis; Owner: -
--

CREATE INDEX idx_corroboration_flag_status ON analysis.corroboration_flag USING btree (status, created_at DESC);


--
-- Name: idx_corroboration_flag_target; Type: INDEX; Schema: analysis; Owner: -
--

CREATE INDEX idx_corroboration_flag_target ON analysis.corroboration_flag USING btree (target_kind, target_id);


--
-- Name: idx_discreq_task; Type: INDEX; Schema: analysis; Owner: -
--

CREATE INDEX idx_discreq_task ON analysis.discovery_request USING btree (task_id, status);


--
-- Name: idx_event_geo; Type: INDEX; Schema: analysis; Owner: -
--

CREATE INDEX idx_event_geo ON analysis.timeline_event USING gist (primary_geo);


--
-- Name: idx_event_mcl; Type: INDEX; Schema: analysis; Owner: -
--

CREATE INDEX idx_event_mcl ON analysis.timeline_event USING gin (mcl_relevance);


--
-- Name: idx_event_title_trgm; Type: INDEX; Schema: analysis; Owner: -
--

CREATE INDEX idx_event_title_trgm ON analysis.timeline_event USING gin (title public.gin_trgm_ops);


--
-- Name: idx_event_type_point; Type: INDEX; Schema: analysis; Owner: -
--

CREATE INDEX idx_event_type_point ON analysis.timeline_event USING btree (event_type, valid_point);


--
-- Name: idx_event_validrange; Type: INDEX; Schema: analysis; Owner: -
--

CREATE INDEX idx_event_validrange ON analysis.timeline_event USING gist (valid_range);


--
-- Name: idx_evitem_case; Type: INDEX; Schema: analysis; Owner: -
--

CREATE INDEX idx_evitem_case ON analysis.evidence_item USING btree (case_id, review_status);


--
-- Name: idx_evitem_export; Type: INDEX; Schema: analysis; Owner: -
--

CREATE INDEX idx_evitem_export ON analysis.evidence_item USING btree (case_id) WHERE (safe_for_legal_use = true);


--
-- Name: idx_evitem_title_trgm; Type: INDEX; Schema: analysis; Owner: -
--

CREATE INDEX idx_evitem_title_trgm ON analysis.evidence_item USING gin (title public.gin_trgm_ops);


--
-- Name: idx_factcite_factor; Type: INDEX; Schema: analysis; Owner: -
--

CREATE INDEX idx_factcite_factor ON analysis.factor_citation USING btree (factor, supports_factor);


--
-- Name: idx_factcite_item; Type: INDEX; Schema: analysis; Owner: -
--

CREATE INDEX idx_factcite_item ON analysis.factor_citation USING btree (evidence_item_id);


--
-- Name: idx_finding_mcl; Type: INDEX; Schema: analysis; Owner: -
--

CREATE INDEX idx_finding_mcl ON analysis.finding USING gin (mcl_factors);


--
-- Name: idx_finding_review; Type: INDEX; Schema: analysis; Owner: -
--

CREATE INDEX idx_finding_review ON analysis.finding USING btree (review_status);


--
-- Name: idx_finding_type; Type: INDEX; Schema: analysis; Owner: -
--

CREATE INDEX idx_finding_type ON analysis.finding USING btree (finding_type);


--
-- Name: idx_legaltl_case; Type: INDEX; Schema: analysis; Owner: -
--

CREATE INDEX idx_legaltl_case ON analysis.legal_timeline_event USING btree (case_id, event_date);


--
-- Name: idx_legaltl_fact; Type: INDEX; Schema: analysis; Owner: -
--

CREATE INDEX idx_legaltl_fact ON analysis.legal_timeline_event USING gin (mcl_factors);


--
-- Name: idx_locassert_geog; Type: INDEX; Schema: analysis; Owner: -
--

CREATE INDEX idx_locassert_geog ON analysis.location_assertion USING gist (geog);


--
-- Name: idx_locassert_subject; Type: INDEX; Schema: analysis; Owner: -
--

CREATE INDEX idx_locassert_subject ON analysis.location_assertion USING btree (subject_type, subject_id);


--
-- Name: idx_pattern_finding_author; Type: INDEX; Schema: analysis; Owner: -
--

CREATE INDEX idx_pattern_finding_author ON analysis.pattern_finding USING btree (author_party);


--
-- Name: idx_pattern_finding_category; Type: INDEX; Schema: analysis; Owner: -
--

CREATE INDEX idx_pattern_finding_category ON analysis.pattern_finding USING btree (category_id);


--
-- Name: idx_pattern_finding_finding; Type: INDEX; Schema: analysis; Owner: -
--

CREATE INDEX idx_pattern_finding_finding ON analysis.pattern_finding USING btree (finding_id);


--
-- Name: idx_pattern_finding_matched_trgm; Type: INDEX; Schema: analysis; Owner: -
--

CREATE INDEX idx_pattern_finding_matched_trgm ON analysis.pattern_finding USING gin (matched_text public.gin_trgm_ops);


--
-- Name: idx_pattern_finding_subject; Type: INDEX; Schema: analysis; Owner: -
--

CREATE INDEX idx_pattern_finding_subject ON analysis.pattern_finding USING btree (subject_type, subject_id);


--
-- Name: idx_pattern_finding_triage; Type: INDEX; Schema: analysis; Owner: -
--

CREATE INDEX idx_pattern_finding_triage ON analysis.pattern_finding USING btree (severity DESC NULLS LAST, review_status);


--
-- Name: idx_rdec_target; Type: INDEX; Schema: analysis; Owner: -
--

CREATE INDEX idx_rdec_target ON analysis.review_decision USING btree (target_kind, target_id);


--
-- Name: idx_relcls_phase; Type: INDEX; Schema: analysis; Owner: -
--

CREATE INDEX idx_relcls_phase ON analysis.relational_classification USING btree (cycle_phase);


--
-- Name: idx_relcls_review; Type: INDEX; Schema: analysis; Owner: -
--

CREATE INDEX idx_relcls_review ON analysis.relational_classification USING btree (review_status) WHERE requires_human_review;


--
-- Name: idx_relcls_subject; Type: INDEX; Schema: analysis; Owner: -
--

CREATE INDEX idx_relcls_subject ON analysis.relational_classification USING btree (subject_type, subject_id);


--
-- Name: idx_resev_res; Type: INDEX; Schema: analysis; Owner: -
--

CREATE INDEX idx_resev_res ON analysis.resolution_evidence USING btree (resolution_id, polarity);


--
-- Name: idx_rtask_state; Type: INDEX; Schema: analysis; Owner: -
--

CREATE INDEX idx_rtask_state ON analysis.review_task USING btree (state, trigger_code);


--
-- Name: idx_score_current; Type: INDEX; Schema: analysis; Owner: -
--

CREATE INDEX idx_score_current ON analysis.score USING btree (score_type) WHERE (valid_to IS NULL);


--
-- Name: idx_score_target; Type: INDEX; Schema: analysis; Owner: -
--

CREATE INDEX idx_score_target ON analysis.score USING btree (target_kind, target_id);


--
-- Name: idx_ta_current; Type: INDEX; Schema: analysis; Owner: -
--

CREATE INDEX idx_ta_current ON analysis.time_assertion USING btree (event_id) WHERE upper_inf(sys_period);


--
-- Name: idx_ta_validrange; Type: INDEX; Schema: analysis; Owner: -
--

CREATE INDEX idx_ta_validrange ON analysis.time_assertion USING gist (valid_range);


--
-- Name: idx_task_case_status; Type: INDEX; Schema: analysis; Owner: -
--

CREATE INDEX idx_task_case_status ON analysis.evidence_task USING btree (case_id, status);


--
-- Name: idx_task_priority; Type: INDEX; Schema: analysis; Owner: -
--

CREATE INDEX idx_task_priority ON analysis.evidence_task USING btree (priority, due_date);


--
-- Name: idx_task_riskkind; Type: INDEX; Schema: analysis; Owner: -
--

CREATE INDEX idx_task_riskkind ON analysis.evidence_task USING gin (risk_kind);


--
-- Name: idx_taskevent_task; Type: INDEX; Schema: analysis; Owner: -
--

CREATE INDEX idx_taskevent_task ON analysis.task_event USING btree (task_id, ts DESC);


--
-- Name: idx_acquisition_acquired; Type: INDEX; Schema: evidence; Owner: -
--

CREATE INDEX idx_acquisition_acquired ON evidence.acquisition USING btree (acquired_at);


--
-- Name: idx_acquisition_method; Type: INDEX; Schema: evidence; Owner: -
--

CREATE INDEX idx_acquisition_method ON evidence.acquisition USING btree (method);


--
-- Name: idx_acquisition_supersedes; Type: INDEX; Schema: evidence; Owner: -
--

CREATE INDEX idx_acquisition_supersedes ON evidence.acquisition USING btree (supersedes_id) WHERE (supersedes_id IS NOT NULL);


--
-- Name: idx_artmeta_set; Type: INDEX; Schema: evidence; Owner: -
--

CREATE INDEX idx_artmeta_set ON evidence.artifact_metadata USING btree (export_set_id) WHERE (export_set_id IS NOT NULL);


--
-- Name: idx_artmeta_source; Type: INDEX; Schema: evidence; Owner: -
--

CREATE INDEX idx_artmeta_source ON evidence.artifact_metadata USING btree (source_id);


--
-- Name: idx_custody_source; Type: INDEX; Schema: evidence; Owner: -
--

CREATE INDEX idx_custody_source ON evidence.custody_event USING btree (source_id, occurred_at);


--
-- Name: idx_custody_type; Type: INDEX; Schema: evidence; Owner: -
--

CREATE INDEX idx_custody_type ON evidence.custody_event USING btree (event_type, occurred_at DESC);


--
-- Name: idx_evhash_filenode; Type: INDEX; Schema: evidence; Owner: -
--

CREATE INDEX idx_evhash_filenode ON evidence.evidence_hash USING btree (file_node_id);


--
-- Name: idx_evhash_level_source; Type: INDEX; Schema: evidence; Owner: -
--

CREATE INDEX idx_evhash_level_source ON evidence.evidence_hash USING btree (level, source_id);


--
-- Name: idx_evhash_meta; Type: INDEX; Schema: evidence; Owner: -
--

CREATE INDEX idx_evhash_meta ON evidence.evidence_hash USING gin (meta);


--
-- Name: idx_evidence_hash_digest; Type: INDEX; Schema: evidence; Owner: -
--

CREATE INDEX idx_evidence_hash_digest ON evidence.evidence_hash USING btree (digest);


--
-- Name: idx_filenode_parent; Type: INDEX; Schema: evidence; Owner: -
--

CREATE INDEX idx_filenode_parent ON evidence.file_node USING btree (parent_node_id);


--
-- Name: idx_filenode_path; Type: INDEX; Schema: evidence; Owner: -
--

CREATE INDEX idx_filenode_path ON evidence.file_node USING gist (node_path);


--
-- Name: idx_filenode_sha; Type: INDEX; Schema: evidence; Owner: -
--

CREATE INDEX idx_filenode_sha ON evidence.file_node USING btree (sha256);


--
-- Name: idx_filenode_source; Type: INDEX; Schema: evidence; Owner: -
--

CREATE INDEX idx_filenode_source ON evidence.file_node USING btree (source_id);


--
-- Name: idx_gps_point_devtime; Type: INDEX; Schema: evidence; Owner: -
--

CREATE INDEX idx_gps_point_devtime ON evidence.gps_point USING btree (device_id, captured_at);


--
-- Name: idx_gps_point_geog; Type: INDEX; Schema: evidence; Owner: -
--

CREATE INDEX idx_gps_point_geog ON evidence.gps_point USING gist (geog);


--
-- Name: idx_gps_point_raw; Type: INDEX; Schema: evidence; Owner: -
--

CREATE INDEX idx_gps_point_raw ON evidence.gps_point USING gin (raw_data);


--
-- Name: idx_gps_point_seq; Type: INDEX; Schema: evidence; Owner: -
--

CREATE INDEX idx_gps_point_seq ON evidence.gps_point USING btree (source_id, point_sequence);


--
-- Name: idx_ingest_run_open; Type: INDEX; Schema: evidence; Owner: -
--

CREATE INDEX idx_ingest_run_open ON evidence.ingest_run USING btree (status) WHERE (status = ANY (ARRAY['running'::text, 'failed'::text, 'rolled_back'::text]));


--
-- Name: idx_ingest_run_sha; Type: INDEX; Schema: evidence; Owner: -
--

CREATE INDEX idx_ingest_run_sha ON evidence.ingest_run USING btree (source_sha256);


--
-- Name: idx_ingest_run_source; Type: INDEX; Schema: evidence; Owner: -
--

CREATE INDEX idx_ingest_run_source ON evidence.ingest_run USING btree (source_id);


--
-- Name: idx_ingest_run_started; Type: INDEX; Schema: evidence; Owner: -
--

CREATE INDEX idx_ingest_run_started ON evidence.ingest_run USING btree (started_at DESC);


--
-- Name: idx_raw_activity_source; Type: INDEX; Schema: evidence; Owner: -
--

CREATE INDEX idx_raw_activity_source ON evidence.raw_activity USING btree (source_id);


--
-- Name: idx_raw_activity_start; Type: INDEX; Schema: evidence; Owner: -
--

CREATE INDEX idx_raw_activity_start ON evidence.raw_activity USING gist (start_geog);


--
-- Name: idx_raw_activity_utc; Type: INDEX; Schema: evidence; Owner: -
--

CREATE INDEX idx_raw_activity_utc ON evidence.raw_activity USING btree (start_utc);


--
-- Name: idx_raw_ai_chat_device; Type: INDEX; Schema: evidence; Owner: -
--

CREATE INDEX idx_raw_ai_chat_device ON evidence.raw_ai_chat USING btree (device_id);


--
-- Name: idx_raw_ai_chat_hash; Type: INDEX; Schema: evidence; Owner: -
--

CREATE INDEX idx_raw_ai_chat_hash ON evidence.raw_ai_chat USING btree (content_hash);


--
-- Name: idx_raw_ai_chat_live; Type: INDEX; Schema: evidence; Owner: -
--

CREATE INDEX idx_raw_ai_chat_live ON evidence.raw_ai_chat USING btree (source_id) WHERE (superseded_by IS NULL);


--
-- Name: idx_raw_ai_chat_source; Type: INDEX; Schema: evidence; Owner: -
--

CREATE INDEX idx_raw_ai_chat_source ON evidence.raw_ai_chat USING btree (source_id);


--
-- Name: idx_raw_csv_device; Type: INDEX; Schema: evidence; Owner: -
--

CREATE INDEX idx_raw_csv_device ON evidence.raw_csv USING btree (device_id);


--
-- Name: idx_raw_csv_hash; Type: INDEX; Schema: evidence; Owner: -
--

CREATE INDEX idx_raw_csv_hash ON evidence.raw_csv USING btree (content_hash);


--
-- Name: idx_raw_csv_live; Type: INDEX; Schema: evidence; Owner: -
--

CREATE INDEX idx_raw_csv_live ON evidence.raw_csv USING btree (source_id) WHERE (superseded_by IS NULL);


--
-- Name: idx_raw_csv_source; Type: INDEX; Schema: evidence; Owner: -
--

CREATE INDEX idx_raw_csv_source ON evidence.raw_csv USING btree (source_id);


--
-- Name: idx_raw_facebook_device; Type: INDEX; Schema: evidence; Owner: -
--

CREATE INDEX idx_raw_facebook_device ON evidence.raw_facebook USING btree (device_id);


--
-- Name: idx_raw_facebook_hash; Type: INDEX; Schema: evidence; Owner: -
--

CREATE INDEX idx_raw_facebook_hash ON evidence.raw_facebook USING btree (content_hash);


--
-- Name: idx_raw_facebook_live; Type: INDEX; Schema: evidence; Owner: -
--

CREATE INDEX idx_raw_facebook_live ON evidence.raw_facebook USING btree (source_id) WHERE (superseded_by IS NULL);


--
-- Name: idx_raw_facebook_source; Type: INDEX; Schema: evidence; Owner: -
--

CREATE INDEX idx_raw_facebook_source ON evidence.raw_facebook USING btree (source_id);


--
-- Name: idx_raw_imessage_device; Type: INDEX; Schema: evidence; Owner: -
--

CREATE INDEX idx_raw_imessage_device ON evidence.raw_imessage USING btree (device_id);


--
-- Name: idx_raw_imessage_hash; Type: INDEX; Schema: evidence; Owner: -
--

CREATE INDEX idx_raw_imessage_hash ON evidence.raw_imessage USING btree (content_hash);


--
-- Name: idx_raw_imessage_live; Type: INDEX; Schema: evidence; Owner: -
--

CREATE INDEX idx_raw_imessage_live ON evidence.raw_imessage USING btree (source_id) WHERE (superseded_by IS NULL);


--
-- Name: idx_raw_imessage_source; Type: INDEX; Schema: evidence; Owner: -
--

CREATE INDEX idx_raw_imessage_source ON evidence.raw_imessage USING btree (source_id);


--
-- Name: idx_raw_path_geog; Type: INDEX; Schema: evidence; Owner: -
--

CREATE INDEX idx_raw_path_geog ON evidence.raw_path USING gist (point_geog);


--
-- Name: idx_raw_path_source; Type: INDEX; Schema: evidence; Owner: -
--

CREATE INDEX idx_raw_path_source ON evidence.raw_path USING btree (source_id, path_serial, point_sequence);


--
-- Name: idx_raw_phone_device; Type: INDEX; Schema: evidence; Owner: -
--

CREATE INDEX idx_raw_phone_device ON evidence.raw_phone USING btree (device_id);


--
-- Name: idx_raw_phone_hash; Type: INDEX; Schema: evidence; Owner: -
--

CREATE INDEX idx_raw_phone_hash ON evidence.raw_phone USING btree (content_hash);


--
-- Name: idx_raw_phone_live; Type: INDEX; Schema: evidence; Owner: -
--

CREATE INDEX idx_raw_phone_live ON evidence.raw_phone USING btree (source_id) WHERE (superseded_by IS NULL);


--
-- Name: idx_raw_phone_source; Type: INDEX; Schema: evidence; Owner: -
--

CREATE INDEX idx_raw_phone_source ON evidence.raw_phone USING btree (source_id);


--
-- Name: idx_raw_rejected_gin; Type: INDEX; Schema: evidence; Owner: -
--

CREATE INDEX idx_raw_rejected_gin ON evidence.raw_rejected USING gin (raw);


--
-- Name: idx_raw_rejected_reason; Type: INDEX; Schema: evidence; Owner: -
--

CREATE INDEX idx_raw_rejected_reason ON evidence.raw_rejected USING btree (reason);


--
-- Name: idx_raw_rejected_run; Type: INDEX; Schema: evidence; Owner: -
--

CREATE INDEX idx_raw_rejected_run ON evidence.raw_rejected USING btree (ingest_run_id);


--
-- Name: idx_raw_rejected_sha; Type: INDEX; Schema: evidence; Owner: -
--

CREATE INDEX idx_raw_rejected_sha ON evidence.raw_rejected USING btree (source_sha256);


--
-- Name: idx_raw_sms_device; Type: INDEX; Schema: evidence; Owner: -
--

CREATE INDEX idx_raw_sms_device ON evidence.raw_sms USING btree (device_id);


--
-- Name: idx_raw_sms_hash; Type: INDEX; Schema: evidence; Owner: -
--

CREATE INDEX idx_raw_sms_hash ON evidence.raw_sms USING btree (content_hash);


--
-- Name: idx_raw_sms_live; Type: INDEX; Schema: evidence; Owner: -
--

CREATE INDEX idx_raw_sms_live ON evidence.raw_sms USING btree (source_id) WHERE (superseded_by IS NULL);


--
-- Name: idx_raw_sms_source; Type: INDEX; Schema: evidence; Owner: -
--

CREATE INDEX idx_raw_sms_source ON evidence.raw_sms USING btree (source_id);


--
-- Name: idx_raw_trip_source; Type: INDEX; Schema: evidence; Owner: -
--

CREATE INDEX idx_raw_trip_source ON evidence.raw_trip USING btree (source_id);


--
-- Name: idx_raw_trip_utc; Type: INDEX; Schema: evidence; Owner: -
--

CREATE INDEX idx_raw_trip_utc ON evidence.raw_trip USING btree (start_utc);


--
-- Name: idx_raw_visit_geog; Type: INDEX; Schema: evidence; Owner: -
--

CREATE INDEX idx_raw_visit_geog ON evidence.raw_visit USING gist (geog);


--
-- Name: idx_raw_visit_source; Type: INDEX; Schema: evidence; Owner: -
--

CREATE INDEX idx_raw_visit_source ON evidence.raw_visit USING btree (source_id);


--
-- Name: idx_raw_visit_utc; Type: INDEX; Schema: evidence; Owner: -
--

CREATE INDEX idx_raw_visit_utc ON evidence.raw_visit USING btree (start_utc);


--
-- Name: idx_source_acquisition; Type: INDEX; Schema: evidence; Owner: -
--

CREATE INDEX idx_source_acquisition ON evidence.source USING btree (acquisition_id);


--
-- Name: idx_source_custody; Type: INDEX; Schema: evidence; Owner: -
--

CREATE INDEX idx_source_custody ON evidence.source USING btree (custody_status);


--
-- Name: idx_source_filename_trgm; Type: INDEX; Schema: evidence; Owner: -
--

CREATE INDEX idx_source_filename_trgm ON evidence.source USING gin (original_filename public.gin_trgm_ops);


--
-- Name: idx_source_orig_meta; Type: INDEX; Schema: evidence; Owner: -
--

CREATE INDEX idx_source_orig_meta ON evidence.source USING gin (original_metadata);


--
-- Name: idx_source_platform; Type: INDEX; Schema: evidence; Owner: -
--

CREATE INDEX idx_source_platform ON evidence.source USING btree (source_platform, source_type);


--
-- Name: idx_source_supersedes; Type: INDEX; Schema: evidence; Owner: -
--

CREATE INDEX idx_source_supersedes ON evidence.source USING btree (supersedes_source_id);


--
-- Name: uq_raw_ai_chat_dedupe; Type: INDEX; Schema: evidence; Owner: -
--

CREATE UNIQUE INDEX uq_raw_ai_chat_dedupe ON evidence.raw_ai_chat USING btree (device_id, medium, content_hash) NULLS NOT DISTINCT;


--
-- Name: uq_raw_csv_dedupe; Type: INDEX; Schema: evidence; Owner: -
--

CREATE UNIQUE INDEX uq_raw_csv_dedupe ON evidence.raw_csv USING btree (device_id, medium, content_hash) NULLS NOT DISTINCT;


--
-- Name: uq_raw_facebook_dedupe; Type: INDEX; Schema: evidence; Owner: -
--

CREATE UNIQUE INDEX uq_raw_facebook_dedupe ON evidence.raw_facebook USING btree (device_id, medium, content_hash) NULLS NOT DISTINCT;


--
-- Name: uq_raw_imessage_dedupe; Type: INDEX; Schema: evidence; Owner: -
--

CREATE UNIQUE INDEX uq_raw_imessage_dedupe ON evidence.raw_imessage USING btree (device_id, medium, content_hash) NULLS NOT DISTINCT;


--
-- Name: uq_raw_phone_dedupe; Type: INDEX; Schema: evidence; Owner: -
--

CREATE UNIQUE INDEX uq_raw_phone_dedupe ON evidence.raw_phone USING btree (device_id, medium, content_hash) NULLS NOT DISTINCT;


--
-- Name: uq_raw_sms_dedupe; Type: INDEX; Schema: evidence; Owner: -
--

CREATE UNIQUE INDEX uq_raw_sms_dedupe ON evidence.raw_sms USING btree (device_id, medium, content_hash) NULLS NOT DISTINCT;


--
-- Name: idx_geocode_audit_req; Type: INDEX; Schema: ops; Owner: -
--

CREATE INDEX idx_geocode_audit_req ON ops.geocode_audit USING btree (request_id, occurred_at);


--
-- Name: idx_run_inputs_gin; Type: INDEX; Schema: ops; Owner: -
--

CREATE INDEX idx_run_inputs_gin ON ops.processing_run USING gin (input_evidence_ids);


--
-- Name: idx_run_started; Type: INDEX; Schema: ops; Owner: -
--

CREATE INDEX idx_run_started ON ops.processing_run USING btree (started_at DESC);


--
-- Name: idx_run_type_status; Type: INDEX; Schema: ops; Owner: -
--

CREATE INDEX idx_run_type_status ON ops.processing_run USING btree (run_type, status);


--
-- Name: idx_tcl_run; Type: INDEX; Schema: ops; Owner: -
--

CREATE INDEX idx_tcl_run ON ops.tool_call_ledger USING btree (run_id);


--
-- Name: idx_workflow_run_gate_state; Type: INDEX; Schema: ops; Owner: -
--

CREATE INDEX idx_workflow_run_gate_state ON ops.workflow_run USING btree (gate_state) WHERE (gate_state IS NOT NULL);


--
-- Name: idx_workflow_run_parent; Type: INDEX; Schema: ops; Owner: -
--

CREATE INDEX idx_workflow_run_parent ON ops.workflow_run USING btree (parent_run_id) WHERE (parent_run_id IS NOT NULL);


--
-- Name: idx_workflow_run_stage_run; Type: INDEX; Schema: ops; Owner: -
--

CREATE INDEX idx_workflow_run_stage_run ON ops.workflow_run_stage USING btree (run_id);


--
-- Name: idx_workflow_run_status; Type: INDEX; Schema: ops; Owner: -
--

CREATE INDEX idx_workflow_run_status ON ops.workflow_run USING btree (status, created_at DESC);


--
-- Name: idx_agent_run_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_agent_run_status ON public.agent_run USING btree (status, started_at DESC);


--
-- Name: idx_approval_request_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_approval_request_status ON public.approval_request USING btree (approval_status, requested_at DESC);


--
-- Name: idx_clog_record; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_clog_record ON public.change_log USING btree (table_name, record_id);


--
-- Name: idx_clog_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_clog_time ON public.change_log USING btree (change_timestamp);


--
-- Name: idx_mem_fts; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_mem_fts ON public.memory_items USING gin (fts);


--
-- Name: idx_mem_title_trgm; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_mem_title_trgm ON public.memory_items USING gin (title public.gin_trgm_ops);


--
-- Name: idx_mem_type_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_mem_type_status ON public.memory_items USING btree (memory_type, status);


--
-- Name: idx_oq_blocks; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_oq_blocks ON public.open_questions USING btree (blocks_export) WHERE blocks_export;


--
-- Name: idx_sess_fts; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_sess_fts ON public.session_summaries USING gin (fts);


--
-- Name: idx_transcript_insight_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_transcript_insight_type ON public.transcript_insight USING btree (insight_type, mined_at DESC);


--
-- Name: idx_behavior_category_alias; Type: INDEX; Schema: reference; Owner: -
--

CREATE INDEX idx_behavior_category_alias ON reference.behavior_category USING gin (aliases);


--
-- Name: idx_behavior_category_mcl; Type: INDEX; Schema: reference; Owner: -
--

CREATE INDEX idx_behavior_category_mcl ON reference.behavior_category USING gin (mcl_factors);


--
-- Name: idx_behavior_category_mcl_factor; Type: INDEX; Schema: reference; Owner: -
--

CREATE INDEX idx_behavior_category_mcl_factor ON reference.behavior_category_mcl USING btree (factor_code);


--
-- Name: idx_detection_pattern_cat; Type: INDEX; Schema: reference; Owner: -
--

CREATE INDEX idx_detection_pattern_cat ON reference.detection_pattern USING btree (category_id);


--
-- Name: idx_detection_pattern_kw; Type: INDEX; Schema: reference; Owner: -
--

CREATE INDEX idx_detection_pattern_kw ON reference.detection_pattern USING gin (keywords);


--
-- Name: idx_detection_pattern_trgm; Type: INDEX; Schema: reference; Owner: -
--

CREATE INDEX idx_detection_pattern_trgm ON reference.detection_pattern USING gin (pattern public.gin_trgm_ops);


--
-- Name: idx_geofence_geog; Type: INDEX; Schema: reference; Owner: -
--

CREATE INDEX idx_geofence_geog ON reference.geofence USING gist (geog);


--
-- Name: idx_legal_issue_case; Type: INDEX; Schema: reference; Owner: -
--

CREATE INDEX idx_legal_issue_case ON reference.legal_issue USING btree (case_id, issue_type);


--
-- Name: idx_pattern_lexicon_type; Type: INDEX; Schema: reference; Owner: -
--

CREATE INDEX idx_pattern_lexicon_type ON reference.pattern_lexicon USING btree (lexicon_type);


--
-- Name: idx_pattern_lexicon_variants; Type: INDEX; Schema: reference; Owner: -
--

CREATE INDEX idx_pattern_lexicon_variants ON reference.pattern_lexicon USING gin (variants);


--
-- Name: idx_pattern_set_active; Type: INDEX; Schema: reference; Owner: -
--

CREATE INDEX idx_pattern_set_active ON reference.detection_pattern_set USING btree (is_active) WHERE is_active;


--
-- Name: candidate_entity_attrs_gin; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX candidate_entity_attrs_gin ON working.candidate_entity USING gin (attrs);


--
-- Name: candidate_entity_dedup_idx; Type: INDEX; Schema: working; Owner: -
--

CREATE UNIQUE INDEX candidate_entity_dedup_idx ON working.candidate_entity USING btree (source_raw_table, source_raw_id, content_sha256);


--
-- Name: candidate_entity_domain_idx; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX candidate_entity_domain_idx ON working.candidate_entity USING btree (case_id, domain);


--
-- Name: candidate_entity_horizon_idx; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX candidate_entity_horizon_idx ON working.candidate_entity USING btree (case_id, knowledge_time);


--
-- Name: candidate_entity_normalized_idx; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX candidate_entity_normalized_idx ON working.candidate_entity USING btree (normalized_name);


--
-- Name: candidate_entity_pending_idx; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX candidate_entity_pending_idx ON working.candidate_entity USING btree (created_at) WHERE (review_state = 'pending'::text);


--
-- Name: candidate_entity_run_idx; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX candidate_entity_run_idx ON working.candidate_entity USING btree (extraction_run_id);


--
-- Name: candidate_entity_source_idx; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX candidate_entity_source_idx ON working.candidate_entity USING btree (source_raw_table, source_raw_id);


--
-- Name: candidate_entity_topics_gin; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX candidate_entity_topics_gin ON working.candidate_entity USING gin (topic_tags);


--
-- Name: candidate_event_attrs_gin; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX candidate_event_attrs_gin ON working.candidate_event USING gin (attrs);


--
-- Name: candidate_event_dedup_idx; Type: INDEX; Schema: working; Owner: -
--

CREATE UNIQUE INDEX candidate_event_dedup_idx ON working.candidate_event USING btree (source_raw_table, source_raw_id, content_sha256);


--
-- Name: candidate_event_domain_idx; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX candidate_event_domain_idx ON working.candidate_event USING btree (case_id, domain);


--
-- Name: candidate_event_entity_idx; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX candidate_event_entity_idx ON working.candidate_event USING btree (primary_entity_id);


--
-- Name: candidate_event_horizon_idx; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX candidate_event_horizon_idx ON working.candidate_event USING btree (case_id, knowledge_time);


--
-- Name: candidate_event_occurred_idx; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX candidate_event_occurred_idx ON working.candidate_event USING btree (occurred_at);


--
-- Name: candidate_event_pending_idx; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX candidate_event_pending_idx ON working.candidate_event USING btree (created_at) WHERE (review_state = 'pending'::text);


--
-- Name: candidate_event_run_idx; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX candidate_event_run_idx ON working.candidate_event USING btree (extraction_run_id);


--
-- Name: candidate_event_topics_gin; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX candidate_event_topics_gin ON working.candidate_event USING gin (topic_tags);


--
-- Name: candidate_event_validity_gist; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX candidate_event_validity_gist ON working.candidate_event USING gist (validity);


--
-- Name: candidate_fact_attrs_gin; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX candidate_fact_attrs_gin ON working.candidate_fact USING gin (attrs);


--
-- Name: candidate_fact_dedup_idx; Type: INDEX; Schema: working; Owner: -
--

CREATE UNIQUE INDEX candidate_fact_dedup_idx ON working.candidate_fact USING btree (source_raw_table, source_raw_id, content_sha256);


--
-- Name: candidate_fact_domain_idx; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX candidate_fact_domain_idx ON working.candidate_fact USING btree (case_id, domain);


--
-- Name: candidate_fact_horizon_idx; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX candidate_fact_horizon_idx ON working.candidate_fact USING btree (case_id, knowledge_time);


--
-- Name: candidate_fact_object_idx; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX candidate_fact_object_idx ON working.candidate_fact USING btree (object_entity_id);


--
-- Name: candidate_fact_pending_idx; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX candidate_fact_pending_idx ON working.candidate_fact USING btree (created_at) WHERE (review_state = 'pending'::text);


--
-- Name: candidate_fact_run_idx; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX candidate_fact_run_idx ON working.candidate_fact USING btree (extraction_run_id);


--
-- Name: candidate_fact_subject_idx; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX candidate_fact_subject_idx ON working.candidate_fact USING btree (subject_entity_id);


--
-- Name: candidate_fact_topics_gin; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX candidate_fact_topics_gin ON working.candidate_fact USING gin (topic_tags);


--
-- Name: extraction_run_extractor_idx; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX extraction_run_extractor_idx ON working.extraction_run USING btree (extractor, extractor_version);


--
-- Name: extraction_run_started_at_idx; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX extraction_run_started_at_idx ON working.extraction_run USING btree (started_at DESC);


--
-- Name: idx_alias_dmeta; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_alias_dmeta ON working.entity_alias USING btree (alias_dmeta);


--
-- Name: idx_alias_entity; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_alias_entity ON working.entity_alias USING btree (entity_id);


--
-- Name: idx_alias_trgm; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_alias_trgm ON working.entity_alias USING gin (((alias_text)::text) public.gin_trgm_ops);


--
-- Name: idx_anchor_range; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_anchor_range ON working.temporal_anchor USING gist (valid_range);


--
-- Name: idx_art_evid_gin; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_art_evid_gin ON working.artifact_registry USING gin (related_source_evidence);


--
-- Name: idx_art_kind_status; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_art_kind_status ON working.artifact_registry USING btree (artifact_kind, status);


--
-- Name: idx_art_sha256; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_art_sha256 ON working.artifact_registry USING btree (sha256);


--
-- Name: idx_att_exif; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_att_exif ON working.attachment USING gin (exif);


--
-- Name: idx_att_msg; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_att_msg ON working.attachment USING btree (message_id);


--
-- Name: idx_att_ocr_fts; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_att_ocr_fts ON working.attachment USING gin (to_tsvector('english'::regconfig, ((COALESCE(ocr_text, ''::text) || ' '::text) || COALESCE(transcription, ''::text))));


--
-- Name: idx_blockstatus_range; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_blockstatus_range ON working.block_status USING btree (target_id, effective_from, effective_to);


--
-- Name: idx_blockstatus_target; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_blockstatus_target ON working.block_status USING btree (target_kind, target_id);


--
-- Name: idx_call_conv; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_call_conv ON working.call_log USING btree (conversation_id);


--
-- Name: idx_call_started; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_call_started ON working.call_log USING btree (started_at);


--
-- Name: idx_conv_platform; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_conv_platform ON working.conversation USING btree (platform);


--
-- Name: idx_conv_primary; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_conv_primary ON working.conversation USING btree (primary_participant_e164);


--
-- Name: idx_convgrpmem_conv; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_convgrpmem_conv ON working.conversation_group_member USING btree (conversation_id);


--
-- Name: idx_convgrpmem_group; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_convgrpmem_group ON working.conversation_group_member USING btree (group_id);


--
-- Name: idx_devown_device; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_devown_device ON working.device_ownership USING btree (device_id);


--
-- Name: idx_devown_owner; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_devown_owner ON working.device_ownership USING btree (owner_entity_id);


--
-- Name: idx_devown_range; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_devown_range ON working.device_ownership USING btree (device_id, effective_from, effective_to);


--
-- Name: idx_edge_child; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_edge_child ON working.lineage_edge USING btree (child_artifact);


--
-- Name: idx_email_owner; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_email_owner ON working.email USING btree (owner_entity_id);


--
-- Name: idx_entcand_batch; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_entcand_batch ON working.extraction_candidate USING btree (extraction_batch_id);


--
-- Name: idx_entcand_consumed; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_entcand_consumed ON working.extraction_candidate USING gin (consumed_by);


--
-- Name: idx_entcand_coref; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_entcand_coref ON working.extraction_candidate USING btree (coref_chain_id) WHERE (coref_chain_id IS NOT NULL);


--
-- Name: idx_entcand_realized; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_entcand_realized ON working.extraction_candidate USING btree (realized_at) WHERE (realized_at IS NOT NULL);


--
-- Name: idx_entcand_record; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_entcand_record ON working.extraction_candidate USING btree (record_id);


--
-- Name: idx_entcand_review; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_entcand_review ON working.extraction_candidate USING btree (review_status) WHERE (review_status = 'pending'::text);


--
-- Name: idx_entcand_type; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_entcand_type ON working.extraction_candidate USING btree (entity_type);


--
-- Name: idx_entity_dispname_trgm; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_entity_dispname_trgm ON working.entity USING gin (((display_name)::text) public.gin_trgm_ops);


--
-- Name: idx_entity_live; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_entity_live ON working.entity USING btree (id) WHERE (merged_into_id IS NULL);


--
-- Name: idx_entity_normname_trgm; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_entity_normname_trgm ON working.entity USING gin (((normalized_name)::text) public.gin_trgm_ops);


--
-- Name: idx_entity_type; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_entity_type ON working.entity USING btree (entity_type);


--
-- Name: idx_esr_attestation; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_esr_attestation ON working.event_source_record USING btree (record_id) WHERE (event_id IS NULL);


--
-- Name: idx_esr_disagree; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_esr_disagree ON working.event_source_record USING btree (record_id) WHERE (agrees IS FALSE);


--
-- Name: idx_esr_rawref; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_esr_rawref ON working.event_source_record USING btree (raw_ref);


--
-- Name: idx_esr_record; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_esr_record ON working.event_source_record USING btree (record_id);


--
-- Name: idx_esr_source; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_esr_source ON working.event_source_record USING btree (source_id);


--
-- Name: idx_extbatch_hash; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_extbatch_hash ON working.extraction_batch USING btree (input_hash);


--
-- Name: idx_extbatch_status; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_extbatch_status ON working.extraction_batch USING btree (status) WHERE (status = ANY (ARRAY['pending'::text, 'running'::text]));


--
-- Name: idx_extcand_batch; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_extcand_batch ON working.extraction_candidate USING btree (extraction_batch_id);


--
-- Name: idx_extcand_consumed; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_extcand_consumed ON working.extraction_candidate USING gin (consumed_by);


--
-- Name: idx_extcand_kind; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_extcand_kind ON working.extraction_candidate USING btree (candidate_kind);


--
-- Name: idx_extcand_pending; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_extcand_pending ON working.extraction_candidate USING btree (review_status) WHERE (review_status = 'pending'::text);


--
-- Name: idx_extcand_record; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_extcand_record ON working.extraction_candidate USING btree (record_id);


--
-- Name: idx_geocode_result_req; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_geocode_result_req ON working.geocode_result USING btree (request_id);


--
-- Name: idx_gps_track_geog; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_gps_track_geog ON working.gps_track USING gist (geog);


--
-- Name: idx_handle_owner; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_handle_owner ON working.handle USING btree (owner_entity_id);


--
-- Name: idx_handle_trgm; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_handle_trgm ON working.handle USING gin (((handle)::text) public.gin_trgm_ops);


--
-- Name: idx_location_geog; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_location_geog ON working.location USING gist (geog);


--
-- Name: idx_location_name_trgm; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_location_name_trgm ON working.location USING gin (name public.gin_trgm_ops);


--
-- Name: idx_mention_dmeta; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_mention_dmeta ON working.entity_mention USING btree (mention_dmeta);


--
-- Name: idx_mention_subject; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_mention_subject ON working.entity_mention USING btree (subject_type, subject_id);


--
-- Name: idx_mention_trgm; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_mention_trgm ON working.entity_mention USING gin (((surface_text)::text) public.gin_trgm_ops);


--
-- Name: idx_merge_surv; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_merge_surv ON working.entity_merge_event USING btree (surviving_entity_id);


--
-- Name: idx_message_derived; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_message_derived ON working.message USING btree (derived_from_record_id);


--
-- Name: idx_msg_attrs; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_msg_attrs ON working.message USING gin (platform_attrs);


--
-- Name: idx_msg_chash; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_msg_chash ON working.message USING btree (content_sha256);


--
-- Name: idx_msg_conv_time; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_msg_conv_time ON working.message USING btree (conversation_id, ts_utc);


--
-- Name: idx_msg_private; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_msg_private ON working.message USING btree (id) WHERE is_private;


--
-- Name: idx_msg_sender; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_msg_sender ON working.message USING btree (sender_e164);


--
-- Name: idx_msgpart_msg; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_msgpart_msg ON working.message_participant USING btree (message_id);


--
-- Name: idx_normrec_acq_fk; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_normrec_acq_fk ON working.normalized_record USING btree (acquisition_id);


--
-- Name: idx_normrec_acquired; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_normrec_acquired ON working.normalized_record USING btree (acquired_at);


--
-- Name: idx_normrec_artifact; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_normrec_artifact ON working.normalized_record USING btree (artifact_id);


--
-- Name: idx_normrec_attrs; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_normrec_attrs ON working.normalized_record USING gin (attrs);


--
-- Name: idx_normrec_conv; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_normrec_conv ON working.normalized_record USING btree (source, conversation_id);


--
-- Name: idx_normrec_convref_time; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_normrec_convref_time ON working.normalized_record USING btree (conversation_ref, occurred_at);


--
-- Name: idx_normrec_device; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_normrec_device ON working.normalized_record USING btree (device_id);


--
-- Name: idx_normrec_fts; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_normrec_fts ON working.normalized_record USING gin (to_tsvector('english'::regconfig, COALESCE(content, ''::text)));


--
-- Name: idx_normrec_occurred; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_normrec_occurred ON working.normalized_record USING btree (occurred_at);


--
-- Name: idx_normrec_rawid; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_normrec_rawid ON working.normalized_record USING btree (derived_from_raw_id);


--
-- Name: idx_normrec_realized; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_normrec_realized ON working.normalized_record USING btree (realized_at) WHERE (realized_at IS NOT NULL);


--
-- Name: idx_normrec_sender; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_normrec_sender ON working.normalized_record USING btree (sender_entity_id);


--
-- Name: idx_normrec_trgm; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_normrec_trgm ON working.normalized_record USING gin (content public.gin_trgm_ops);


--
-- Name: idx_phone_e164; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_phone_e164 ON working.phone USING btree (((e164)::text));


--
-- Name: idx_phone_owner; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_phone_owner ON working.phone USING btree (owner_entity_id);


--
-- Name: idx_recobs_batch; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_recobs_batch ON working.record_observation USING btree (extraction_batch_id);


--
-- Name: idx_recobs_kind; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_recobs_kind ON working.record_observation USING btree (kind);


--
-- Name: idx_recobs_record; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_recobs_record ON working.record_observation USING btree (record_id);


--
-- Name: idx_recobs_unrev; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_recobs_unrev ON working.record_observation USING btree (review_status) WHERE (review_status = 'unreviewed'::text);


--
-- Name: idx_res_canonical; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_res_canonical ON working.entity_resolution USING btree (canonical_entity_id);


--
-- Name: idx_stay_point_geog; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_stay_point_geog ON working.stay_point USING gist (geog);


--
-- Name: idx_wds_path; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_wds_path ON working.waypoint_device_split USING btree (raw_path_id);


--
-- Name: idx_xref_b; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_xref_b ON working.id_xref USING btree (system_b, native_id_b);


--
-- Name: idx_xref_entity; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX idx_xref_entity ON working.id_xref USING btree (canonical_entity_id);


--
-- Name: normalized_record_domain_idx; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX normalized_record_domain_idx ON working.normalized_record USING btree (case_id, domain);


--
-- Name: normalized_record_horizon_idx; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX normalized_record_horizon_idx ON working.normalized_record USING btree (case_id, knowledge_time);


--
-- Name: normalized_record_topics_gin; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX normalized_record_topics_gin ON working.normalized_record USING gin (topic_tags);


--
-- Name: promotion_candidate_idx; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX promotion_candidate_idx ON working.promotion USING btree (candidate_kind, candidate_id);


--
-- Name: promotion_lane_idx; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX promotion_lane_idx ON working.promotion USING btree (lane, promoted_at DESC);


--
-- Name: promotion_live_idx; Type: INDEX; Schema: working; Owner: -
--

CREATE UNIQUE INDEX promotion_live_idx ON working.promotion USING btree (candidate_kind, candidate_id, lane, target_system) WHERE (revoked_at IS NULL);


--
-- Name: promotion_target_idx; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX promotion_target_idx ON working.promotion USING btree (target_system, promoted_at DESC);


--
-- Name: review_decision_candidate_idx; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX review_decision_candidate_idx ON working.review_decision USING btree (candidate_kind, candidate_id);


--
-- Name: review_decision_decided_idx; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX review_decision_decided_idx ON working.review_decision USING btree (decided_at DESC);


--
-- Name: review_decision_reviewer_idx; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX review_decision_reviewer_idx ON working.review_decision USING btree (reviewer, decided_at DESC);


--
-- Name: source_provenance_occurred_idx; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX source_provenance_occurred_idx ON working.source_provenance USING btree (occurred_at);


--
-- Name: source_provenance_realized_idx; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX source_provenance_realized_idx ON working.source_provenance USING btree (realized_at);


--
-- Name: source_provenance_revision_idx; Type: INDEX; Schema: working; Owner: -
--

CREATE UNIQUE INDEX source_provenance_revision_idx ON working.source_provenance USING btree (source_raw_table, source_raw_id, revision);


--
-- Name: source_provenance_source_idx; Type: INDEX; Schema: working; Owner: -
--

CREATE INDEX source_provenance_source_idx ON working.source_provenance USING btree (source_raw_table, source_raw_id);


--
-- Name: uq_device_label; Type: INDEX; Schema: working; Owner: -
--

CREATE UNIQUE INDEX uq_device_label ON working.device USING btree (device_label) WHERE (device_label IS NOT NULL);


--
-- Name: uq_entity_norm; Type: INDEX; Schema: working; Owner: -
--

CREATE UNIQUE INDEX uq_entity_norm ON working.entity USING btree (entity_type, normalized_name) WHERE ((normalized_name IS NOT NULL) AND (merged_into_id IS NULL));


--
-- Name: uq_esr_record; Type: INDEX; Schema: working; Owner: -
--

CREATE UNIQUE INDEX uq_esr_record ON working.event_source_record USING btree (event_id, record_id) WHERE (record_id IS NOT NULL);


--
-- Name: uq_extraction_candidate_dedupe; Type: INDEX; Schema: working; Owner: -
--

CREATE UNIQUE INDEX uq_extraction_candidate_dedupe ON working.extraction_candidate USING btree (COALESCE((record_id)::text, ''::text), candidate_kind, extractor, COALESCE(span_start, '-1'::integer), COALESCE(span_end, '-1'::integer), entity_text);


--
-- Name: uq_location_dedup; Type: INDEX; Schema: working; Owner: -
--

CREATE UNIQUE INDEX uq_location_dedup ON working.location USING btree (geohash9, COALESCE(name, ''::text));


--
-- Name: uq_recobs_dedupe; Type: INDEX; Schema: working; Owner: -
--

CREATE UNIQUE INDEX uq_recobs_dedupe ON working.record_observation USING btree (dedupe_key);


--
-- Name: uq_res_current; Type: INDEX; Schema: working; Owner: -
--

CREATE UNIQUE INDEX uq_res_current ON working.entity_resolution USING btree (mention_id) WHERE upper_inf(sys_period);


--
-- Name: discovery_request_revision discrev_immutable; Type: TRIGGER; Schema: analysis; Owner: -
--

CREATE TRIGGER discrev_immutable BEFORE DELETE OR UPDATE ON analysis.discovery_request_revision FOR EACH ROW EXECUTE FUNCTION working.forbid_mutation();


--
-- Name: export export_append_only; Type: TRIGGER; Schema: analysis; Owner: -
--

CREATE TRIGGER export_append_only BEFORE DELETE OR UPDATE ON analysis.export FOR EACH ROW EXECUTE FUNCTION working.forbid_mutation();


--
-- Name: finding_version finding_version_immutable; Type: TRIGGER; Schema: analysis; Owner: -
--

CREATE TRIGGER finding_version_immutable BEFORE DELETE OR UPDATE ON analysis.finding_version FOR EACH ROW EXECUTE FUNCTION working.forbid_mutation();


--
-- Name: review_decision rdec_append_only; Type: TRIGGER; Schema: analysis; Owner: -
--

CREATE TRIGGER rdec_append_only BEFORE DELETE OR UPDATE ON analysis.review_decision FOR EACH ROW EXECUTE FUNCTION working.forbid_mutation();


--
-- Name: redaction redaction_append_only; Type: TRIGGER; Schema: analysis; Owner: -
--

CREATE TRIGGER redaction_append_only BEFORE DELETE OR UPDATE ON analysis.redaction FOR EACH ROW EXECUTE FUNCTION working.forbid_mutation();


--
-- Name: evidence_task task_snapshot; Type: TRIGGER; Schema: analysis; Owner: -
--

CREATE TRIGGER task_snapshot BEFORE UPDATE ON analysis.evidence_task FOR EACH ROW EXECUTE FUNCTION analysis.snapshot_task();


--
-- Name: evidence_task task_status_log; Type: TRIGGER; Schema: analysis; Owner: -
--

CREATE TRIGGER task_status_log BEFORE UPDATE OF status ON analysis.evidence_task FOR EACH ROW EXECUTE FUNCTION analysis.log_task_status();


--
-- Name: task_event taskevent_immutable; Type: TRIGGER; Schema: analysis; Owner: -
--

CREATE TRIGGER taskevent_immutable BEFORE DELETE OR UPDATE ON analysis.task_event FOR EACH ROW EXECUTE FUNCTION working.forbid_mutation();


--
-- Name: task_revision taskrev_immutable; Type: TRIGGER; Schema: analysis; Owner: -
--

CREATE TRIGGER taskrev_immutable BEFORE DELETE OR UPDATE ON analysis.task_revision FOR EACH ROW EXECUTE FUNCTION working.forbid_mutation();


--
-- Name: resolution_evidence trg_resev_append; Type: TRIGGER; Schema: analysis; Owner: -
--

CREATE TRIGGER trg_resev_append BEFORE DELETE OR UPDATE ON analysis.resolution_evidence FOR EACH ROW EXECUTE FUNCTION working.reject_mutation();


--
-- Name: custody_event custody_event_chain; Type: TRIGGER; Schema: evidence; Owner: -
--

CREATE TRIGGER custody_event_chain BEFORE INSERT ON evidence.custody_event FOR EACH ROW EXECUTE FUNCTION evidence.chain_custody_event();


--
-- Name: custody_event custody_event_immutable; Type: TRIGGER; Schema: evidence; Owner: -
--

CREATE TRIGGER custody_event_immutable BEFORE DELETE OR UPDATE ON evidence.custody_event FOR EACH ROW EXECUTE FUNCTION evidence.forbid_mutation();


--
-- Name: file_node filenode_immutable; Type: TRIGGER; Schema: evidence; Owner: -
--

CREATE TRIGGER filenode_immutable BEFORE DELETE OR UPDATE ON evidence.file_node FOR EACH ROW EXECUTE FUNCTION evidence.forbid_mutation();


--
-- Name: source source_immutable; Type: TRIGGER; Schema: evidence; Owner: -
--

CREATE TRIGGER source_immutable BEFORE DELETE OR UPDATE ON evidence.source FOR EACH ROW EXECUTE FUNCTION evidence.source_immutable_core();


--
-- Name: raw_ai_chat trg_raw_ai_chat_no_mutate; Type: TRIGGER; Schema: evidence; Owner: -
--

CREATE TRIGGER trg_raw_ai_chat_no_mutate BEFORE DELETE OR UPDATE ON evidence.raw_ai_chat FOR EACH ROW EXECUTE FUNCTION evidence.raw_no_mutate();


--
-- Name: raw_csv trg_raw_csv_no_mutate; Type: TRIGGER; Schema: evidence; Owner: -
--

CREATE TRIGGER trg_raw_csv_no_mutate BEFORE DELETE OR UPDATE ON evidence.raw_csv FOR EACH ROW EXECUTE FUNCTION evidence.raw_no_mutate();


--
-- Name: raw_facebook trg_raw_facebook_no_mutate; Type: TRIGGER; Schema: evidence; Owner: -
--

CREATE TRIGGER trg_raw_facebook_no_mutate BEFORE DELETE OR UPDATE ON evidence.raw_facebook FOR EACH ROW EXECUTE FUNCTION evidence.raw_no_mutate();


--
-- Name: raw_imessage trg_raw_imessage_no_mutate; Type: TRIGGER; Schema: evidence; Owner: -
--

CREATE TRIGGER trg_raw_imessage_no_mutate BEFORE DELETE OR UPDATE ON evidence.raw_imessage FOR EACH ROW EXECUTE FUNCTION evidence.raw_no_mutate();


--
-- Name: raw_phone trg_raw_phone_no_mutate; Type: TRIGGER; Schema: evidence; Owner: -
--

CREATE TRIGGER trg_raw_phone_no_mutate BEFORE DELETE OR UPDATE ON evidence.raw_phone FOR EACH ROW EXECUTE FUNCTION evidence.raw_no_mutate();


--
-- Name: raw_sms trg_raw_sms_no_mutate; Type: TRIGGER; Schema: evidence; Owner: -
--

CREATE TRIGGER trg_raw_sms_no_mutate BEFORE DELETE OR UPDATE ON evidence.raw_sms FOR EACH ROW EXECUTE FUNCTION evidence.raw_no_mutate();


--
-- Name: geocode_audit geocode_audit_immutable; Type: TRIGGER; Schema: ops; Owner: -
--

CREATE TRIGGER geocode_audit_immutable BEFORE DELETE OR UPDATE ON ops.geocode_audit FOR EACH ROW EXECUTE FUNCTION working.forbid_mutation();


--
-- Name: tool_call_ledger tcl_append_only; Type: TRIGGER; Schema: ops; Owner: -
--

CREATE TRIGGER tcl_append_only BEFORE DELETE OR UPDATE ON ops.tool_call_ledger FOR EACH ROW EXECUTE FUNCTION working.forbid_mutation();


--
-- Name: change_log clog_append_only; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER clog_append_only BEFORE DELETE OR UPDATE ON public.change_log FOR EACH ROW EXECUTE FUNCTION public.forbid_mutation();


--
-- Name: change_log clog_chain; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER clog_chain BEFORE INSERT ON public.change_log FOR EACH ROW EXECUTE FUNCTION public.change_log_chain();


--
-- Name: session_summaries sess_append_only; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER sess_append_only BEFORE DELETE OR UPDATE ON public.session_summaries FOR EACH ROW EXECUTE FUNCTION public.forbid_mutation();


--
-- Name: lineage_edge edge_append_only; Type: TRIGGER; Schema: working; Owner: -
--

CREATE TRIGGER edge_append_only BEFORE DELETE OR UPDATE ON working.lineage_edge FOR EACH ROW EXECUTE FUNCTION working.forbid_mutation();


--
-- Name: promotion promotion_revoke_only; Type: TRIGGER; Schema: working; Owner: -
--

CREATE TRIGGER promotion_revoke_only BEFORE DELETE OR UPDATE ON working.promotion FOR EACH ROW EXECUTE FUNCTION working.promotion_revoke_only();


--
-- Name: review_decision review_decision_append_only; Type: TRIGGER; Schema: working; Owner: -
--

CREATE TRIGGER review_decision_append_only BEFORE DELETE OR UPDATE ON working.review_decision FOR EACH ROW EXECUTE FUNCTION working.forbid_mutation();


--
-- Name: source_provenance source_provenance_append_only; Type: TRIGGER; Schema: working; Owner: -
--

CREATE TRIGGER source_provenance_append_only BEFORE DELETE OR UPDATE ON working.source_provenance FOR EACH ROW EXECUTE FUNCTION working.forbid_mutation();


--
-- Name: extraction_candidate trg_extraction_candidate_no_mutate; Type: TRIGGER; Schema: working; Owner: -
--

CREATE TRIGGER trg_extraction_candidate_no_mutate BEFORE UPDATE ON working.extraction_candidate FOR EACH ROW EXECUTE FUNCTION working.extraction_candidate_no_mutate();


--
-- Name: entity_mention trg_mention_append; Type: TRIGGER; Schema: working; Owner: -
--

CREATE TRIGGER trg_mention_append BEFORE DELETE OR UPDATE ON working.entity_mention FOR EACH ROW EXECUTE FUNCTION working.reject_mutation();


--
-- Name: entity_merge_event trg_merge_append; Type: TRIGGER; Schema: working; Owner: -
--

CREATE TRIGGER trg_merge_append BEFORE DELETE OR UPDATE ON working.entity_merge_event FOR EACH ROW EXECUTE FUNCTION working.reject_mutation();


--
-- Name: message trg_message_derived_guard; Type: TRIGGER; Schema: working; Owner: -
--

CREATE TRIGGER trg_message_derived_guard BEFORE INSERT OR UPDATE ON working.message FOR EACH ROW EXECUTE FUNCTION working.derived_write_guard();


--
-- Name: message_participant trg_message_participant_derived_guard; Type: TRIGGER; Schema: working; Owner: -
--

CREATE TRIGGER trg_message_participant_derived_guard BEFORE INSERT OR UPDATE ON working.message_participant FOR EACH ROW EXECUTE FUNCTION working.derived_write_guard();


--
-- Name: normalized_record trg_normalized_record_derived_guard; Type: TRIGGER; Schema: working; Owner: -
--

CREATE TRIGGER trg_normalized_record_derived_guard BEFORE INSERT OR UPDATE ON working.normalized_record FOR EACH ROW EXECUTE FUNCTION working.derived_write_guard();


--
-- Name: agno_component_configs agno_component_configs_component_id_fkey; Type: FK CONSTRAINT; Schema: ai; Owner: -
--

ALTER TABLE ONLY ai.agno_component_configs
    ADD CONSTRAINT agno_component_configs_component_id_fkey FOREIGN KEY (component_id) REFERENCES ai.agno_components(component_id);


--
-- Name: agno_component_links agno_component_links_child_component_id_fkey; Type: FK CONSTRAINT; Schema: ai; Owner: -
--

ALTER TABLE ONLY ai.agno_component_links
    ADD CONSTRAINT agno_component_links_child_component_id_fkey FOREIGN KEY (child_component_id) REFERENCES ai.agno_components(component_id);


--
-- Name: agno_component_links agno_component_links_parent_component_id_parent_version_fkey; Type: FK CONSTRAINT; Schema: ai; Owner: -
--

ALTER TABLE ONLY ai.agno_component_links
    ADD CONSTRAINT agno_component_links_parent_component_id_parent_version_fkey FOREIGN KEY (parent_component_id, parent_version) REFERENCES ai.agno_component_configs(component_id, version);


--
-- Name: agno_schedule_runs agno_schedule_runs_schedule_id_fkey; Type: FK CONSTRAINT; Schema: ai; Owner: -
--

ALTER TABLE ONLY ai.agno_schedule_runs
    ADD CONSTRAINT agno_schedule_runs_schedule_id_fkey FOREIGN KEY (schedule_id) REFERENCES ai.agno_schedules(id) ON DELETE CASCADE;


--
-- Name: agno_spans agno_spans_trace_id_fkey; Type: FK CONSTRAINT; Schema: ai; Owner: -
--

ALTER TABLE ONLY ai.agno_spans
    ADD CONSTRAINT agno_spans_trace_id_fkey FOREIGN KEY (trace_id) REFERENCES ai.agno_traces(trace_id);


--
-- Name: completion_evidence completion_evidence_evidence_hash_id_fkey; Type: FK CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.completion_evidence
    ADD CONSTRAINT completion_evidence_evidence_hash_id_fkey FOREIGN KEY (evidence_hash_id) REFERENCES evidence.evidence_hash(id);


--
-- Name: completion_evidence completion_evidence_evidence_item_id_fkey; Type: FK CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.completion_evidence
    ADD CONSTRAINT completion_evidence_evidence_item_id_fkey FOREIGN KEY (evidence_item_id) REFERENCES analysis.evidence_item(id);


--
-- Name: completion_evidence completion_evidence_source_id_fkey; Type: FK CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.completion_evidence
    ADD CONSTRAINT completion_evidence_source_id_fkey FOREIGN KEY (source_id) REFERENCES evidence.source(id);


--
-- Name: completion_evidence completion_evidence_task_id_fkey; Type: FK CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.completion_evidence
    ADD CONSTRAINT completion_evidence_task_id_fkey FOREIGN KEY (task_id) REFERENCES analysis.evidence_task(id);


--
-- Name: discovery_request_revision discovery_request_revision_request_id_fkey; Type: FK CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.discovery_request_revision
    ADD CONSTRAINT discovery_request_revision_request_id_fkey FOREIGN KEY (request_id) REFERENCES analysis.discovery_request(id);


--
-- Name: discovery_request discovery_request_target_person_id_fkey; Type: FK CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.discovery_request
    ADD CONSTRAINT discovery_request_target_person_id_fkey FOREIGN KEY (target_person_id) REFERENCES working.person(id);


--
-- Name: discovery_request discovery_request_task_id_fkey; Type: FK CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.discovery_request
    ADD CONSTRAINT discovery_request_task_id_fkey FOREIGN KEY (task_id) REFERENCES analysis.evidence_task(id);


--
-- Name: evidence_item evidence_item_evidence_hash_id_fkey; Type: FK CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.evidence_item
    ADD CONSTRAINT evidence_item_evidence_hash_id_fkey FOREIGN KEY (evidence_hash_id) REFERENCES evidence.evidence_hash(id);


--
-- Name: evidence_item evidence_item_file_node_id_fkey; Type: FK CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.evidence_item
    ADD CONSTRAINT evidence_item_file_node_id_fkey FOREIGN KEY (file_node_id) REFERENCES evidence.file_node(id);


--
-- Name: evidence_item evidence_item_normalized_record_id_fkey; Type: FK CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.evidence_item
    ADD CONSTRAINT evidence_item_normalized_record_id_fkey FOREIGN KEY (normalized_record_id) REFERENCES working.normalized_record(id);


--
-- Name: evidence_item evidence_item_source_id_fkey; Type: FK CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.evidence_item
    ADD CONSTRAINT evidence_item_source_id_fkey FOREIGN KEY (source_id) REFERENCES evidence.source(id);


--
-- Name: evidence_item evidence_item_source_run_id_fkey; Type: FK CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.evidence_item
    ADD CONSTRAINT evidence_item_source_run_id_fkey FOREIGN KEY (source_run_id) REFERENCES ops.processing_run(run_id);


--
-- Name: evidence_item evidence_item_supersedes_item_id_fkey; Type: FK CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.evidence_item
    ADD CONSTRAINT evidence_item_supersedes_item_id_fkey FOREIGN KEY (supersedes_item_id) REFERENCES analysis.evidence_item(id);


--
-- Name: evidence_task evidence_task_finding_id_fkey; Type: FK CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.evidence_task
    ADD CONSTRAINT evidence_task_finding_id_fkey FOREIGN KEY (finding_id) REFERENCES analysis.finding(id);


--
-- Name: evidence_task evidence_task_likely_source_id_fkey; Type: FK CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.evidence_task
    ADD CONSTRAINT evidence_task_likely_source_id_fkey FOREIGN KEY (likely_source_id) REFERENCES evidence.source(id);


--
-- Name: evidence_task evidence_task_source_run_id_fkey; Type: FK CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.evidence_task
    ADD CONSTRAINT evidence_task_source_run_id_fkey FOREIGN KEY (source_run_id) REFERENCES ops.processing_run(run_id);


--
-- Name: export export_export_run_fkey; Type: FK CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.export
    ADD CONSTRAINT export_export_run_fkey FOREIGN KEY (export_run) REFERENCES ops.processing_run(run_id);


--
-- Name: export_item export_item_evidence_item_id_fkey; Type: FK CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.export_item
    ADD CONSTRAINT export_item_evidence_item_id_fkey FOREIGN KEY (evidence_item_id) REFERENCES analysis.evidence_item(id);


--
-- Name: export_item export_item_package_id_fkey; Type: FK CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.export_item
    ADD CONSTRAINT export_item_package_id_fkey FOREIGN KEY (package_id) REFERENCES analysis.export_package(id);


--
-- Name: factor_citation factor_citation_evidence_item_id_fkey; Type: FK CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.factor_citation
    ADD CONSTRAINT factor_citation_evidence_item_id_fkey FOREIGN KEY (evidence_item_id) REFERENCES analysis.evidence_item(id);


--
-- Name: factor_citation factor_citation_factor_fkey; Type: FK CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.factor_citation
    ADD CONSTRAINT factor_citation_factor_fkey FOREIGN KEY (factor) REFERENCES reference.custody_factor(factor);


--
-- Name: factor_citation factor_citation_legal_issue_id_fkey; Type: FK CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.factor_citation
    ADD CONSTRAINT factor_citation_legal_issue_id_fkey FOREIGN KEY (legal_issue_id) REFERENCES reference.legal_issue(id);


--
-- Name: factor_citation factor_citation_supersedes_citation_id_fkey; Type: FK CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.factor_citation
    ADD CONSTRAINT factor_citation_supersedes_citation_id_fkey FOREIGN KEY (supersedes_citation_id) REFERENCES analysis.factor_citation(id);


--
-- Name: finding finding_contradicts_finding_id_fkey; Type: FK CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.finding
    ADD CONSTRAINT finding_contradicts_finding_id_fkey FOREIGN KEY (contradicts_finding_id) REFERENCES analysis.finding(id);


--
-- Name: finding finding_provenance_id_fkey; Type: FK CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.finding
    ADD CONSTRAINT finding_provenance_id_fkey FOREIGN KEY (provenance_id) REFERENCES ops.processing_run(run_id);


--
-- Name: finding_version finding_version_finding_id_fkey; Type: FK CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.finding_version
    ADD CONSTRAINT finding_version_finding_id_fkey FOREIGN KEY (finding_id) REFERENCES analysis.finding(id);


--
-- Name: location_assertion location_assertion_location_id_fkey; Type: FK CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.location_assertion
    ADD CONSTRAINT location_assertion_location_id_fkey FOREIGN KEY (location_id) REFERENCES working.location(id);


--
-- Name: location_assertion location_assertion_provenance_id_fkey; Type: FK CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.location_assertion
    ADD CONSTRAINT location_assertion_provenance_id_fkey FOREIGN KEY (provenance_id) REFERENCES ops.processing_run(run_id);


--
-- Name: location_contradiction location_contradiction_claimed_assertion_id_fkey; Type: FK CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.location_contradiction
    ADD CONSTRAINT location_contradiction_claimed_assertion_id_fkey FOREIGN KEY (claimed_assertion_id) REFERENCES analysis.location_assertion(id);


--
-- Name: location_contradiction location_contradiction_observed_assertion_id_fkey; Type: FK CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.location_contradiction
    ADD CONSTRAINT location_contradiction_observed_assertion_id_fkey FOREIGN KEY (observed_assertion_id) REFERENCES analysis.location_assertion(id);


--
-- Name: location_contradiction location_contradiction_provenance_id_fkey; Type: FK CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.location_contradiction
    ADD CONSTRAINT location_contradiction_provenance_id_fkey FOREIGN KEY (provenance_id) REFERENCES ops.processing_run(run_id);


--
-- Name: pattern_finding pattern_finding_category_id_fkey; Type: FK CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.pattern_finding
    ADD CONSTRAINT pattern_finding_category_id_fkey FOREIGN KEY (category_id) REFERENCES reference.behavior_category(category_id);


--
-- Name: pattern_finding pattern_finding_finding_id_fkey; Type: FK CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.pattern_finding
    ADD CONSTRAINT pattern_finding_finding_id_fkey FOREIGN KEY (finding_id) REFERENCES analysis.finding(id);


--
-- Name: pattern_finding pattern_finding_pattern_id_fkey; Type: FK CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.pattern_finding
    ADD CONSTRAINT pattern_finding_pattern_id_fkey FOREIGN KEY (pattern_id) REFERENCES reference.detection_pattern(id);


--
-- Name: pattern_finding pattern_finding_pattern_set_id_fkey; Type: FK CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.pattern_finding
    ADD CONSTRAINT pattern_finding_pattern_set_id_fkey FOREIGN KEY (pattern_set_id) REFERENCES reference.detection_pattern_set(id);


--
-- Name: pattern_finding pattern_finding_provenance_id_fkey; Type: FK CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.pattern_finding
    ADD CONSTRAINT pattern_finding_provenance_id_fkey FOREIGN KEY (provenance_id) REFERENCES ops.processing_run(run_id);


--
-- Name: redaction redaction_redacted_artifact_fkey; Type: FK CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.redaction
    ADD CONSTRAINT redaction_redacted_artifact_fkey FOREIGN KEY (redacted_artifact) REFERENCES working.artifact_registry(artifact_id);


--
-- Name: redaction redaction_redaction_run_fkey; Type: FK CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.redaction
    ADD CONSTRAINT redaction_redaction_run_fkey FOREIGN KEY (redaction_run) REFERENCES ops.processing_run(run_id);


--
-- Name: redaction redaction_source_artifact_fkey; Type: FK CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.redaction
    ADD CONSTRAINT redaction_source_artifact_fkey FOREIGN KEY (source_artifact) REFERENCES working.artifact_registry(artifact_id);


--
-- Name: relational_classification relational_classification_provenance_id_fkey; Type: FK CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.relational_classification
    ADD CONSTRAINT relational_classification_provenance_id_fkey FOREIGN KEY (provenance_id) REFERENCES ops.processing_run(run_id);


--
-- Name: resolution_evidence resolution_evidence_resolution_id_fkey; Type: FK CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.resolution_evidence
    ADD CONSTRAINT resolution_evidence_resolution_id_fkey FOREIGN KEY (resolution_id) REFERENCES working.entity_resolution(id);


--
-- Name: review_decision review_decision_ontology_version_id_fkey; Type: FK CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.review_decision
    ADD CONSTRAINT review_decision_ontology_version_id_fkey FOREIGN KEY (ontology_version_id) REFERENCES public.ontology_version(ontology_version_id);


--
-- Name: review_decision review_decision_prompt_version_id_fkey; Type: FK CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.review_decision
    ADD CONSTRAINT review_decision_prompt_version_id_fkey FOREIGN KEY (prompt_version_id) REFERENCES public.prompt_registry(prompt_id);


--
-- Name: review_decision review_decision_schema_version_id_fkey; Type: FK CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.review_decision
    ADD CONSTRAINT review_decision_schema_version_id_fkey FOREIGN KEY (schema_version_id) REFERENCES public.schema_version(schema_version_id);


--
-- Name: review_decision review_decision_task_id_fkey; Type: FK CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.review_decision
    ADD CONSTRAINT review_decision_task_id_fkey FOREIGN KEY (task_id) REFERENCES analysis.review_task(task_id);


--
-- Name: score score_config_version_fkey; Type: FK CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.score
    ADD CONSTRAINT score_config_version_fkey FOREIGN KEY (config_version) REFERENCES reference.score_band_config(config_version);


--
-- Name: score score_scoring_run_id_fkey; Type: FK CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.score
    ADD CONSTRAINT score_scoring_run_id_fkey FOREIGN KEY (scoring_run_id) REFERENCES ops.processing_run(run_id);


--
-- Name: score score_superseded_by_fkey; Type: FK CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.score
    ADD CONSTRAINT score_superseded_by_fkey FOREIGN KEY (superseded_by) REFERENCES analysis.score(score_id);


--
-- Name: task_dependency task_dependency_depends_on_fkey; Type: FK CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.task_dependency
    ADD CONSTRAINT task_dependency_depends_on_fkey FOREIGN KEY (depends_on) REFERENCES analysis.evidence_task(id);


--
-- Name: task_dependency task_dependency_task_id_fkey; Type: FK CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.task_dependency
    ADD CONSTRAINT task_dependency_task_id_fkey FOREIGN KEY (task_id) REFERENCES analysis.evidence_task(id);


--
-- Name: task_event task_event_task_id_fkey; Type: FK CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.task_event
    ADD CONSTRAINT task_event_task_id_fkey FOREIGN KEY (task_id) REFERENCES analysis.evidence_task(id);


--
-- Name: task_legal_link task_legal_link_factor_fkey; Type: FK CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.task_legal_link
    ADD CONSTRAINT task_legal_link_factor_fkey FOREIGN KEY (factor) REFERENCES reference.custody_factor(factor);


--
-- Name: task_legal_link task_legal_link_legal_issue_id_fkey; Type: FK CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.task_legal_link
    ADD CONSTRAINT task_legal_link_legal_issue_id_fkey FOREIGN KEY (legal_issue_id) REFERENCES reference.legal_issue(id);


--
-- Name: task_legal_link task_legal_link_task_id_fkey; Type: FK CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.task_legal_link
    ADD CONSTRAINT task_legal_link_task_id_fkey FOREIGN KEY (task_id) REFERENCES analysis.evidence_task(id);


--
-- Name: task_person task_person_person_id_fkey; Type: FK CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.task_person
    ADD CONSTRAINT task_person_person_id_fkey FOREIGN KEY (person_id) REFERENCES working.person(id);


--
-- Name: task_person task_person_task_id_fkey; Type: FK CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.task_person
    ADD CONSTRAINT task_person_task_id_fkey FOREIGN KEY (task_id) REFERENCES analysis.evidence_task(id);


--
-- Name: task_revision task_revision_task_id_fkey; Type: FK CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.task_revision
    ADD CONSTRAINT task_revision_task_id_fkey FOREIGN KEY (task_id) REFERENCES analysis.evidence_task(id);


--
-- Name: time_assertion time_assertion_discovery_source_fkey; Type: FK CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.time_assertion
    ADD CONSTRAINT time_assertion_discovery_source_fkey FOREIGN KEY (discovery_source) REFERENCES evidence.evidence_hash(id);


--
-- Name: time_assertion time_assertion_event_id_fkey; Type: FK CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.time_assertion
    ADD CONSTRAINT time_assertion_event_id_fkey FOREIGN KEY (event_id) REFERENCES analysis.timeline_event(event_id) ON DELETE CASCADE;


--
-- Name: time_assertion time_assertion_ingest_run_id_fkey; Type: FK CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.time_assertion
    ADD CONSTRAINT time_assertion_ingest_run_id_fkey FOREIGN KEY (ingest_run_id) REFERENCES ops.processing_run(run_id);


--
-- Name: time_assertion time_assertion_superseded_by_fkey; Type: FK CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.time_assertion
    ADD CONSTRAINT time_assertion_superseded_by_fkey FOREIGN KEY (superseded_by) REFERENCES analysis.time_assertion(assertion_id);


--
-- Name: timeline_event timeline_event_ingest_run_id_fkey; Type: FK CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.timeline_event
    ADD CONSTRAINT timeline_event_ingest_run_id_fkey FOREIGN KEY (ingest_run_id) REFERENCES ops.processing_run(run_id);


--
-- Name: timeline_event timeline_event_location_id_fkey; Type: FK CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.timeline_event
    ADD CONSTRAINT timeline_event_location_id_fkey FOREIGN KEY (location_id) REFERENCES working.location(id);


--
-- Name: timeline_event timeline_event_primary_record_id_fkey; Type: FK CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.timeline_event
    ADD CONSTRAINT timeline_event_primary_record_id_fkey FOREIGN KEY (primary_record_id) REFERENCES working.normalized_record(id);


--
-- Name: timeline_event timeline_event_source_artifact_id_fkey; Type: FK CONSTRAINT; Schema: analysis; Owner: -
--

ALTER TABLE ONLY analysis.timeline_event
    ADD CONSTRAINT timeline_event_source_artifact_id_fkey FOREIGN KEY (source_artifact_id) REFERENCES evidence.evidence_hash(id);


--
-- Name: acquisition acquisition_device_id_fkey; Type: FK CONSTRAINT; Schema: evidence; Owner: -
--

ALTER TABLE ONLY evidence.acquisition
    ADD CONSTRAINT acquisition_device_id_fkey FOREIGN KEY (device_id) REFERENCES working.device(id);


--
-- Name: acquisition acquisition_supersedes_id_fkey; Type: FK CONSTRAINT; Schema: evidence; Owner: -
--

ALTER TABLE ONLY evidence.acquisition
    ADD CONSTRAINT acquisition_supersedes_id_fkey FOREIGN KEY (supersedes_id) REFERENCES evidence.acquisition(id);


--
-- Name: artifact_metadata artifact_metadata_acquisition_id_fkey; Type: FK CONSTRAINT; Schema: evidence; Owner: -
--

ALTER TABLE ONLY evidence.artifact_metadata
    ADD CONSTRAINT artifact_metadata_acquisition_id_fkey FOREIGN KEY (acquisition_id) REFERENCES evidence.acquisition(id);


--
-- Name: artifact_metadata artifact_metadata_source_id_fkey; Type: FK CONSTRAINT; Schema: evidence; Owner: -
--

ALTER TABLE ONLY evidence.artifact_metadata
    ADD CONSTRAINT artifact_metadata_source_id_fkey FOREIGN KEY (source_id) REFERENCES evidence.source(id);


--
-- Name: custody_event custody_event_evidence_hash_id_fkey; Type: FK CONSTRAINT; Schema: evidence; Owner: -
--

ALTER TABLE ONLY evidence.custody_event
    ADD CONSTRAINT custody_event_evidence_hash_id_fkey FOREIGN KEY (evidence_hash_id) REFERENCES evidence.evidence_hash(id);


--
-- Name: custody_event custody_event_file_node_id_fkey; Type: FK CONSTRAINT; Schema: evidence; Owner: -
--

ALTER TABLE ONLY evidence.custody_event
    ADD CONSTRAINT custody_event_file_node_id_fkey FOREIGN KEY (file_node_id) REFERENCES evidence.file_node(id);


--
-- Name: custody_event custody_event_source_id_fkey; Type: FK CONSTRAINT; Schema: evidence; Owner: -
--

ALTER TABLE ONLY evidence.custody_event
    ADD CONSTRAINT custody_event_source_id_fkey FOREIGN KEY (source_id) REFERENCES evidence.source(id);


--
-- Name: evidence_hash evidence_hash_file_node_id_fkey; Type: FK CONSTRAINT; Schema: evidence; Owner: -
--

ALTER TABLE ONLY evidence.evidence_hash
    ADD CONSTRAINT evidence_hash_file_node_id_fkey FOREIGN KEY (file_node_id) REFERENCES evidence.file_node(id);


--
-- Name: evidence_hash evidence_hash_source_id_fkey; Type: FK CONSTRAINT; Schema: evidence; Owner: -
--

ALTER TABLE ONLY evidence.evidence_hash
    ADD CONSTRAINT evidence_hash_source_id_fkey FOREIGN KEY (source_id) REFERENCES evidence.source(id);


--
-- Name: file_node file_node_parent_node_id_fkey; Type: FK CONSTRAINT; Schema: evidence; Owner: -
--

ALTER TABLE ONLY evidence.file_node
    ADD CONSTRAINT file_node_parent_node_id_fkey FOREIGN KEY (parent_node_id) REFERENCES evidence.file_node(id);


--
-- Name: file_node file_node_source_id_fkey; Type: FK CONSTRAINT; Schema: evidence; Owner: -
--

ALTER TABLE ONLY evidence.file_node
    ADD CONSTRAINT file_node_source_id_fkey FOREIGN KEY (source_id) REFERENCES evidence.source(id);


--
-- Name: gps_point gps_point_file_node_id_fkey; Type: FK CONSTRAINT; Schema: evidence; Owner: -
--

ALTER TABLE ONLY evidence.gps_point
    ADD CONSTRAINT gps_point_file_node_id_fkey FOREIGN KEY (file_node_id) REFERENCES evidence.file_node(id);


--
-- Name: gps_point gps_point_source_id_fkey; Type: FK CONSTRAINT; Schema: evidence; Owner: -
--

ALTER TABLE ONLY evidence.gps_point
    ADD CONSTRAINT gps_point_source_id_fkey FOREIGN KEY (source_id) REFERENCES evidence.source(id);


--
-- Name: ingest_run ingest_run_source_id_fkey; Type: FK CONSTRAINT; Schema: evidence; Owner: -
--

ALTER TABLE ONLY evidence.ingest_run
    ADD CONSTRAINT ingest_run_source_id_fkey FOREIGN KEY (source_id) REFERENCES evidence.source(id);


--
-- Name: raw_activity raw_activity_file_node_id_fkey; Type: FK CONSTRAINT; Schema: evidence; Owner: -
--

ALTER TABLE ONLY evidence.raw_activity
    ADD CONSTRAINT raw_activity_file_node_id_fkey FOREIGN KEY (file_node_id) REFERENCES evidence.file_node(id);


--
-- Name: raw_activity raw_activity_source_id_fkey; Type: FK CONSTRAINT; Schema: evidence; Owner: -
--

ALTER TABLE ONLY evidence.raw_activity
    ADD CONSTRAINT raw_activity_source_id_fkey FOREIGN KEY (source_id) REFERENCES evidence.source(id);


--
-- Name: raw_ai_chat raw_ai_chat_acquisition_id_fkey; Type: FK CONSTRAINT; Schema: evidence; Owner: -
--

ALTER TABLE ONLY evidence.raw_ai_chat
    ADD CONSTRAINT raw_ai_chat_acquisition_id_fkey FOREIGN KEY (acquisition_id) REFERENCES evidence.acquisition(id);


--
-- Name: raw_ai_chat raw_ai_chat_device_id_fkey; Type: FK CONSTRAINT; Schema: evidence; Owner: -
--

ALTER TABLE ONLY evidence.raw_ai_chat
    ADD CONSTRAINT raw_ai_chat_device_id_fkey FOREIGN KEY (device_id) REFERENCES working.device(id);


--
-- Name: raw_ai_chat raw_ai_chat_source_id_fkey; Type: FK CONSTRAINT; Schema: evidence; Owner: -
--

ALTER TABLE ONLY evidence.raw_ai_chat
    ADD CONSTRAINT raw_ai_chat_source_id_fkey FOREIGN KEY (source_id) REFERENCES evidence.source(id);


--
-- Name: raw_csv raw_csv_acquisition_id_fkey; Type: FK CONSTRAINT; Schema: evidence; Owner: -
--

ALTER TABLE ONLY evidence.raw_csv
    ADD CONSTRAINT raw_csv_acquisition_id_fkey FOREIGN KEY (acquisition_id) REFERENCES evidence.acquisition(id);


--
-- Name: raw_csv raw_csv_device_id_fkey; Type: FK CONSTRAINT; Schema: evidence; Owner: -
--

ALTER TABLE ONLY evidence.raw_csv
    ADD CONSTRAINT raw_csv_device_id_fkey FOREIGN KEY (device_id) REFERENCES working.device(id);


--
-- Name: raw_csv raw_csv_source_id_fkey; Type: FK CONSTRAINT; Schema: evidence; Owner: -
--

ALTER TABLE ONLY evidence.raw_csv
    ADD CONSTRAINT raw_csv_source_id_fkey FOREIGN KEY (source_id) REFERENCES evidence.source(id);


--
-- Name: raw_facebook raw_facebook_acquisition_id_fkey; Type: FK CONSTRAINT; Schema: evidence; Owner: -
--

ALTER TABLE ONLY evidence.raw_facebook
    ADD CONSTRAINT raw_facebook_acquisition_id_fkey FOREIGN KEY (acquisition_id) REFERENCES evidence.acquisition(id);


--
-- Name: raw_facebook raw_facebook_device_id_fkey; Type: FK CONSTRAINT; Schema: evidence; Owner: -
--

ALTER TABLE ONLY evidence.raw_facebook
    ADD CONSTRAINT raw_facebook_device_id_fkey FOREIGN KEY (device_id) REFERENCES working.device(id);


--
-- Name: raw_facebook raw_facebook_source_id_fkey; Type: FK CONSTRAINT; Schema: evidence; Owner: -
--

ALTER TABLE ONLY evidence.raw_facebook
    ADD CONSTRAINT raw_facebook_source_id_fkey FOREIGN KEY (source_id) REFERENCES evidence.source(id);


--
-- Name: raw_imessage raw_imessage_acquisition_id_fkey; Type: FK CONSTRAINT; Schema: evidence; Owner: -
--

ALTER TABLE ONLY evidence.raw_imessage
    ADD CONSTRAINT raw_imessage_acquisition_id_fkey FOREIGN KEY (acquisition_id) REFERENCES evidence.acquisition(id);


--
-- Name: raw_imessage raw_imessage_device_id_fkey; Type: FK CONSTRAINT; Schema: evidence; Owner: -
--

ALTER TABLE ONLY evidence.raw_imessage
    ADD CONSTRAINT raw_imessage_device_id_fkey FOREIGN KEY (device_id) REFERENCES working.device(id);


--
-- Name: raw_imessage raw_imessage_source_id_fkey; Type: FK CONSTRAINT; Schema: evidence; Owner: -
--

ALTER TABLE ONLY evidence.raw_imessage
    ADD CONSTRAINT raw_imessage_source_id_fkey FOREIGN KEY (source_id) REFERENCES evidence.source(id);


--
-- Name: raw_path raw_path_aligned_activity_id_fkey; Type: FK CONSTRAINT; Schema: evidence; Owner: -
--

ALTER TABLE ONLY evidence.raw_path
    ADD CONSTRAINT raw_path_aligned_activity_id_fkey FOREIGN KEY (aligned_activity_id) REFERENCES evidence.raw_activity(id);


--
-- Name: raw_path raw_path_file_node_id_fkey; Type: FK CONSTRAINT; Schema: evidence; Owner: -
--

ALTER TABLE ONLY evidence.raw_path
    ADD CONSTRAINT raw_path_file_node_id_fkey FOREIGN KEY (file_node_id) REFERENCES evidence.file_node(id);


--
-- Name: raw_path raw_path_parent_id_fkey; Type: FK CONSTRAINT; Schema: evidence; Owner: -
--

ALTER TABLE ONLY evidence.raw_path
    ADD CONSTRAINT raw_path_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES evidence.raw_path(id);


--
-- Name: raw_path raw_path_source_id_fkey; Type: FK CONSTRAINT; Schema: evidence; Owner: -
--

ALTER TABLE ONLY evidence.raw_path
    ADD CONSTRAINT raw_path_source_id_fkey FOREIGN KEY (source_id) REFERENCES evidence.source(id);


--
-- Name: raw_phone raw_phone_acquisition_id_fkey; Type: FK CONSTRAINT; Schema: evidence; Owner: -
--

ALTER TABLE ONLY evidence.raw_phone
    ADD CONSTRAINT raw_phone_acquisition_id_fkey FOREIGN KEY (acquisition_id) REFERENCES evidence.acquisition(id);


--
-- Name: raw_phone raw_phone_device_id_fkey; Type: FK CONSTRAINT; Schema: evidence; Owner: -
--

ALTER TABLE ONLY evidence.raw_phone
    ADD CONSTRAINT raw_phone_device_id_fkey FOREIGN KEY (device_id) REFERENCES working.device(id);


--
-- Name: raw_phone raw_phone_source_id_fkey; Type: FK CONSTRAINT; Schema: evidence; Owner: -
--

ALTER TABLE ONLY evidence.raw_phone
    ADD CONSTRAINT raw_phone_source_id_fkey FOREIGN KEY (source_id) REFERENCES evidence.source(id);


--
-- Name: raw_rejected raw_rejected_ingest_run_id_fkey; Type: FK CONSTRAINT; Schema: evidence; Owner: -
--

ALTER TABLE ONLY evidence.raw_rejected
    ADD CONSTRAINT raw_rejected_ingest_run_id_fkey FOREIGN KEY (ingest_run_id) REFERENCES evidence.ingest_run(id) ON DELETE RESTRICT;


--
-- Name: raw_sms raw_sms_acquisition_id_fkey; Type: FK CONSTRAINT; Schema: evidence; Owner: -
--

ALTER TABLE ONLY evidence.raw_sms
    ADD CONSTRAINT raw_sms_acquisition_id_fkey FOREIGN KEY (acquisition_id) REFERENCES evidence.acquisition(id);


--
-- Name: raw_sms raw_sms_device_id_fkey; Type: FK CONSTRAINT; Schema: evidence; Owner: -
--

ALTER TABLE ONLY evidence.raw_sms
    ADD CONSTRAINT raw_sms_device_id_fkey FOREIGN KEY (device_id) REFERENCES working.device(id);


--
-- Name: raw_sms raw_sms_source_id_fkey; Type: FK CONSTRAINT; Schema: evidence; Owner: -
--

ALTER TABLE ONLY evidence.raw_sms
    ADD CONSTRAINT raw_sms_source_id_fkey FOREIGN KEY (source_id) REFERENCES evidence.source(id);


--
-- Name: raw_trip raw_trip_file_node_id_fkey; Type: FK CONSTRAINT; Schema: evidence; Owner: -
--

ALTER TABLE ONLY evidence.raw_trip
    ADD CONSTRAINT raw_trip_file_node_id_fkey FOREIGN KEY (file_node_id) REFERENCES evidence.file_node(id);


--
-- Name: raw_trip raw_trip_parent_id_fkey; Type: FK CONSTRAINT; Schema: evidence; Owner: -
--

ALTER TABLE ONLY evidence.raw_trip
    ADD CONSTRAINT raw_trip_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES evidence.raw_trip(id);


--
-- Name: raw_trip raw_trip_source_id_fkey; Type: FK CONSTRAINT; Schema: evidence; Owner: -
--

ALTER TABLE ONLY evidence.raw_trip
    ADD CONSTRAINT raw_trip_source_id_fkey FOREIGN KEY (source_id) REFERENCES evidence.source(id);


--
-- Name: raw_visit raw_visit_file_node_id_fkey; Type: FK CONSTRAINT; Schema: evidence; Owner: -
--

ALTER TABLE ONLY evidence.raw_visit
    ADD CONSTRAINT raw_visit_file_node_id_fkey FOREIGN KEY (file_node_id) REFERENCES evidence.file_node(id);


--
-- Name: raw_visit raw_visit_parent_id_fkey; Type: FK CONSTRAINT; Schema: evidence; Owner: -
--

ALTER TABLE ONLY evidence.raw_visit
    ADD CONSTRAINT raw_visit_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES evidence.raw_visit(id);


--
-- Name: raw_visit raw_visit_source_id_fkey; Type: FK CONSTRAINT; Schema: evidence; Owner: -
--

ALTER TABLE ONLY evidence.raw_visit
    ADD CONSTRAINT raw_visit_source_id_fkey FOREIGN KEY (source_id) REFERENCES evidence.source(id);


--
-- Name: source source_acquisition_id_fkey; Type: FK CONSTRAINT; Schema: evidence; Owner: -
--

ALTER TABLE ONLY evidence.source
    ADD CONSTRAINT source_acquisition_id_fkey FOREIGN KEY (acquisition_id) REFERENCES evidence.acquisition(id);


--
-- Name: source source_supersedes_source_id_fkey; Type: FK CONSTRAINT; Schema: evidence; Owner: -
--

ALTER TABLE ONLY evidence.source
    ADD CONSTRAINT source_supersedes_source_id_fkey FOREIGN KEY (supersedes_source_id) REFERENCES evidence.source(id);


--
-- Name: geocode_audit geocode_audit_request_id_fkey; Type: FK CONSTRAINT; Schema: ops; Owner: -
--

ALTER TABLE ONLY ops.geocode_audit
    ADD CONSTRAINT geocode_audit_request_id_fkey FOREIGN KEY (request_id) REFERENCES working.geocode_request(id);


--
-- Name: processing_run processing_run_classification_version_id_fkey; Type: FK CONSTRAINT; Schema: ops; Owner: -
--

ALTER TABLE ONLY ops.processing_run
    ADD CONSTRAINT processing_run_classification_version_id_fkey FOREIGN KEY (classification_version_id) REFERENCES public.classification_version(classification_version_id);


--
-- Name: processing_run processing_run_model_version_id_fkey; Type: FK CONSTRAINT; Schema: ops; Owner: -
--

ALTER TABLE ONLY ops.processing_run
    ADD CONSTRAINT processing_run_model_version_id_fkey FOREIGN KEY (model_version_id) REFERENCES public.model_version(model_version_id);


--
-- Name: processing_run processing_run_ontology_version_id_fkey; Type: FK CONSTRAINT; Schema: ops; Owner: -
--

ALTER TABLE ONLY ops.processing_run
    ADD CONSTRAINT processing_run_ontology_version_id_fkey FOREIGN KEY (ontology_version_id) REFERENCES public.ontology_version(ontology_version_id);


--
-- Name: processing_run processing_run_prompt_version_id_fkey; Type: FK CONSTRAINT; Schema: ops; Owner: -
--

ALTER TABLE ONLY ops.processing_run
    ADD CONSTRAINT processing_run_prompt_version_id_fkey FOREIGN KEY (prompt_version_id) REFERENCES public.prompt_registry(prompt_id);


--
-- Name: processing_run processing_run_schema_version_id_fkey; Type: FK CONSTRAINT; Schema: ops; Owner: -
--

ALTER TABLE ONLY ops.processing_run
    ADD CONSTRAINT processing_run_schema_version_id_fkey FOREIGN KEY (schema_version_id) REFERENCES public.schema_version(schema_version_id);


--
-- Name: processing_run processing_run_supersedes_run_fkey; Type: FK CONSTRAINT; Schema: ops; Owner: -
--

ALTER TABLE ONLY ops.processing_run
    ADD CONSTRAINT processing_run_supersedes_run_fkey FOREIGN KEY (supersedes_run) REFERENCES ops.processing_run(run_id);


--
-- Name: tool_call_ledger tool_call_ledger_run_id_fkey; Type: FK CONSTRAINT; Schema: ops; Owner: -
--

ALTER TABLE ONLY ops.tool_call_ledger
    ADD CONSTRAINT tool_call_ledger_run_id_fkey FOREIGN KEY (run_id) REFERENCES ops.processing_run(run_id);


--
-- Name: workflow_run workflow_run_parent_run_id_fkey; Type: FK CONSTRAINT; Schema: ops; Owner: -
--

ALTER TABLE ONLY ops.workflow_run
    ADD CONSTRAINT workflow_run_parent_run_id_fkey FOREIGN KEY (parent_run_id) REFERENCES ops.workflow_run(run_id);


--
-- Name: workflow_run_stage workflow_run_stage_run_id_fkey; Type: FK CONSTRAINT; Schema: ops; Owner: -
--

ALTER TABLE ONLY ops.workflow_run_stage
    ADD CONSTRAINT workflow_run_stage_run_id_fkey FOREIGN KEY (run_id) REFERENCES ops.workflow_run(run_id) ON DELETE CASCADE;


--
-- Name: approval_request approval_request_agent_run_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.approval_request
    ADD CONSTRAINT approval_request_agent_run_id_fkey FOREIGN KEY (agent_run_id) REFERENCES public.agent_run(id) ON DELETE CASCADE;


--
-- Name: canon_registry canon_registry_superseded_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.canon_registry
    ADD CONSTRAINT canon_registry_superseded_by_fkey FOREIGN KEY (superseded_by) REFERENCES public.canon_registry(id);


--
-- Name: change_log change_log_related_decision_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.change_log
    ADD CONSTRAINT change_log_related_decision_id_fkey FOREIGN KEY (related_decision_id) REFERENCES public.decision_log(decision_id);


--
-- Name: change_log change_log_related_run_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.change_log
    ADD CONSTRAINT change_log_related_run_id_fkey FOREIGN KEY (related_run_id) REFERENCES ops.processing_run(run_id);


--
-- Name: classification_version classification_version_supersedes_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.classification_version
    ADD CONSTRAINT classification_version_supersedes_fkey FOREIGN KEY (supersedes) REFERENCES public.classification_version(classification_version_id);


--
-- Name: decision_log decision_log_supersedes_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.decision_log
    ADD CONSTRAINT decision_log_supersedes_fkey FOREIGN KEY (supersedes) REFERENCES public.decision_log(decision_id);


--
-- Name: decision_precedent decision_precedent_decision_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.decision_precedent
    ADD CONSTRAINT decision_precedent_decision_id_fkey FOREIGN KEY (decision_id) REFERENCES public.decision_log(decision_id);


--
-- Name: decision_precedent decision_precedent_source_decision_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.decision_precedent
    ADD CONSTRAINT decision_precedent_source_decision_id_fkey FOREIGN KEY (source_decision_id) REFERENCES public.decision_log(decision_id);


--
-- Name: memory_items memory_items_related_ontology_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.memory_items
    ADD CONSTRAINT memory_items_related_ontology_id_fkey FOREIGN KEY (related_ontology_id) REFERENCES public.ontology_version(ontology_version_id);


--
-- Name: memory_items memory_items_related_schema_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.memory_items
    ADD CONSTRAINT memory_items_related_schema_id_fkey FOREIGN KEY (related_schema_id) REFERENCES public.schema_version(schema_version_id);


--
-- Name: memory_items memory_items_superseded_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.memory_items
    ADD CONSTRAINT memory_items_superseded_by_fkey FOREIGN KEY (superseded_by) REFERENCES public.memory_items(memory_id);


--
-- Name: ontology_version ontology_version_supersedes_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ontology_version
    ADD CONSTRAINT ontology_version_supersedes_fkey FOREIGN KEY (supersedes) REFERENCES public.ontology_version(ontology_version_id);


--
-- Name: open_questions open_questions_related_run_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.open_questions
    ADD CONSTRAINT open_questions_related_run_id_fkey FOREIGN KEY (related_run_id) REFERENCES ops.processing_run(run_id);


--
-- Name: prompt_registry prompt_registry_superseded_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.prompt_registry
    ADD CONSTRAINT prompt_registry_superseded_by_fkey FOREIGN KEY (superseded_by) REFERENCES public.prompt_registry(prompt_id);


--
-- Name: schema_version schema_version_supersedes_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_version
    ADD CONSTRAINT schema_version_supersedes_fkey FOREIGN KEY (supersedes) REFERENCES public.schema_version(schema_version_id);


--
-- Name: behavior_category_mcl behavior_category_mcl_category_id_fkey; Type: FK CONSTRAINT; Schema: reference; Owner: -
--

ALTER TABLE ONLY reference.behavior_category_mcl
    ADD CONSTRAINT behavior_category_mcl_category_id_fkey FOREIGN KEY (category_id) REFERENCES reference.behavior_category(category_id);


--
-- Name: detection_pattern detection_pattern_category_id_fkey; Type: FK CONSTRAINT; Schema: reference; Owner: -
--

ALTER TABLE ONLY reference.detection_pattern
    ADD CONSTRAINT detection_pattern_category_id_fkey FOREIGN KEY (category_id) REFERENCES reference.behavior_category(category_id);


--
-- Name: detection_pattern detection_pattern_pattern_set_id_fkey; Type: FK CONSTRAINT; Schema: reference; Owner: -
--

ALTER TABLE ONLY reference.detection_pattern
    ADD CONSTRAINT detection_pattern_pattern_set_id_fkey FOREIGN KEY (pattern_set_id) REFERENCES reference.detection_pattern_set(id);


--
-- Name: detection_pattern_set detection_pattern_set_provenance_id_fkey; Type: FK CONSTRAINT; Schema: reference; Owner: -
--

ALTER TABLE ONLY reference.detection_pattern_set
    ADD CONSTRAINT detection_pattern_set_provenance_id_fkey FOREIGN KEY (provenance_id) REFERENCES ops.processing_run(run_id);


--
-- Name: geofence geofence_provenance_id_fkey; Type: FK CONSTRAINT; Schema: reference; Owner: -
--

ALTER TABLE ONLY reference.geofence
    ADD CONSTRAINT geofence_provenance_id_fkey FOREIGN KEY (provenance_id) REFERENCES ops.processing_run(run_id);


--
-- Name: legal_issue_factor legal_issue_factor_factor_fkey; Type: FK CONSTRAINT; Schema: reference; Owner: -
--

ALTER TABLE ONLY reference.legal_issue_factor
    ADD CONSTRAINT legal_issue_factor_factor_fkey FOREIGN KEY (factor) REFERENCES reference.custody_factor(factor);


--
-- Name: legal_issue_factor legal_issue_factor_legal_issue_id_fkey; Type: FK CONSTRAINT; Schema: reference; Owner: -
--

ALTER TABLE ONLY reference.legal_issue_factor
    ADD CONSTRAINT legal_issue_factor_legal_issue_id_fkey FOREIGN KEY (legal_issue_id) REFERENCES reference.legal_issue(id);


--
-- Name: lexicon_sync lexicon_sync_pattern_set_id_fkey; Type: FK CONSTRAINT; Schema: reference; Owner: -
--

ALTER TABLE ONLY reference.lexicon_sync
    ADD CONSTRAINT lexicon_sync_pattern_set_id_fkey FOREIGN KEY (pattern_set_id) REFERENCES reference.detection_pattern_set(id);


--
-- Name: pattern_lexicon pattern_lexicon_pattern_set_id_fkey; Type: FK CONSTRAINT; Schema: reference; Owner: -
--

ALTER TABLE ONLY reference.pattern_lexicon
    ADD CONSTRAINT pattern_lexicon_pattern_set_id_fkey FOREIGN KEY (pattern_set_id) REFERENCES reference.detection_pattern_set(id);


--
-- Name: account account_id_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.account
    ADD CONSTRAINT account_id_fkey FOREIGN KEY (id) REFERENCES working.entity(id) ON DELETE CASCADE;


--
-- Name: account account_owner_entity_id_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.account
    ADD CONSTRAINT account_owner_entity_id_fkey FOREIGN KEY (owner_entity_id) REFERENCES working.entity(id);


--
-- Name: artifact_registry artifact_registry_parent_artifact_id_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.artifact_registry
    ADD CONSTRAINT artifact_registry_parent_artifact_id_fkey FOREIGN KEY (parent_artifact_id) REFERENCES working.artifact_registry(artifact_id);


--
-- Name: artifact_registry artifact_registry_producing_run_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.artifact_registry
    ADD CONSTRAINT artifact_registry_producing_run_fkey FOREIGN KEY (producing_run) REFERENCES ops.processing_run(run_id);


--
-- Name: artifact_registry artifact_registry_superseded_by_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.artifact_registry
    ADD CONSTRAINT artifact_registry_superseded_by_fkey FOREIGN KEY (superseded_by) REFERENCES working.artifact_registry(artifact_id);


--
-- Name: attachment attachment_message_id_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.attachment
    ADD CONSTRAINT attachment_message_id_fkey FOREIGN KEY (message_id) REFERENCES working.message(id) ON DELETE CASCADE;


--
-- Name: attachment attachment_provenance_id_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.attachment
    ADD CONSTRAINT attachment_provenance_id_fkey FOREIGN KEY (provenance_id) REFERENCES ops.processing_run(run_id);


--
-- Name: attachment attachment_source_artifact_id_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.attachment
    ADD CONSTRAINT attachment_source_artifact_id_fkey FOREIGN KEY (source_artifact_id) REFERENCES evidence.evidence_hash(id);


--
-- Name: block_status block_status_blocker_entity_id_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.block_status
    ADD CONSTRAINT block_status_blocker_entity_id_fkey FOREIGN KEY (blocker_entity_id) REFERENCES working.entity(id);


--
-- Name: block_status block_status_device_id_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.block_status
    ADD CONSTRAINT block_status_device_id_fkey FOREIGN KEY (device_id) REFERENCES working.device(id);


--
-- Name: call_log call_log_conversation_id_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.call_log
    ADD CONSTRAINT call_log_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES working.conversation(id);


--
-- Name: call_log call_log_id_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.call_log
    ADD CONSTRAINT call_log_id_fkey FOREIGN KEY (id) REFERENCES working.normalized_record(id) ON DELETE CASCADE;


--
-- Name: call_log call_log_provenance_id_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.call_log
    ADD CONSTRAINT call_log_provenance_id_fkey FOREIGN KEY (provenance_id) REFERENCES ops.processing_run(run_id);


--
-- Name: call_log call_log_source_artifact_id_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.call_log
    ADD CONSTRAINT call_log_source_artifact_id_fkey FOREIGN KEY (source_artifact_id) REFERENCES evidence.evidence_hash(id);


--
-- Name: candidate_entity candidate_entity_extraction_run_id_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.candidate_entity
    ADD CONSTRAINT candidate_entity_extraction_run_id_fkey FOREIGN KEY (extraction_run_id) REFERENCES working.extraction_run(id) ON DELETE CASCADE;


--
-- Name: candidate_event candidate_event_extraction_run_id_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.candidate_event
    ADD CONSTRAINT candidate_event_extraction_run_id_fkey FOREIGN KEY (extraction_run_id) REFERENCES working.extraction_run(id) ON DELETE CASCADE;


--
-- Name: candidate_event candidate_event_primary_entity_id_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.candidate_event
    ADD CONSTRAINT candidate_event_primary_entity_id_fkey FOREIGN KEY (primary_entity_id) REFERENCES working.candidate_entity(id) ON DELETE SET NULL;


--
-- Name: candidate_fact candidate_fact_extraction_run_id_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.candidate_fact
    ADD CONSTRAINT candidate_fact_extraction_run_id_fkey FOREIGN KEY (extraction_run_id) REFERENCES working.extraction_run(id) ON DELETE CASCADE;


--
-- Name: candidate_fact candidate_fact_object_entity_id_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.candidate_fact
    ADD CONSTRAINT candidate_fact_object_entity_id_fkey FOREIGN KEY (object_entity_id) REFERENCES working.candidate_entity(id) ON DELETE SET NULL;


--
-- Name: candidate_fact candidate_fact_subject_entity_id_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.candidate_fact
    ADD CONSTRAINT candidate_fact_subject_entity_id_fkey FOREIGN KEY (subject_entity_id) REFERENCES working.candidate_entity(id) ON DELETE SET NULL;


--
-- Name: conversation_group_member conversation_group_member_conversation_id_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.conversation_group_member
    ADD CONSTRAINT conversation_group_member_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES working.conversation(id);


--
-- Name: conversation_group_member conversation_group_member_group_id_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.conversation_group_member
    ADD CONSTRAINT conversation_group_member_group_id_fkey FOREIGN KEY (group_id) REFERENCES working.conversation_group(id);


--
-- Name: conversation conversation_provenance_id_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.conversation
    ADD CONSTRAINT conversation_provenance_id_fkey FOREIGN KEY (provenance_id) REFERENCES ops.processing_run(run_id);


--
-- Name: conversation conversation_source_artifact_id_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.conversation
    ADD CONSTRAINT conversation_source_artifact_id_fkey FOREIGN KEY (source_artifact_id) REFERENCES evidence.evidence_hash(id);


--
-- Name: device device_id_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.device
    ADD CONSTRAINT device_id_fkey FOREIGN KEY (id) REFERENCES working.entity(id) ON DELETE CASCADE;


--
-- Name: device device_owner_entity_id_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.device
    ADD CONSTRAINT device_owner_entity_id_fkey FOREIGN KEY (owner_entity_id) REFERENCES working.entity(id);


--
-- Name: device_ownership device_ownership_device_id_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.device_ownership
    ADD CONSTRAINT device_ownership_device_id_fkey FOREIGN KEY (device_id) REFERENCES working.device(id);


--
-- Name: device_ownership device_ownership_owner_entity_id_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.device_ownership
    ADD CONSTRAINT device_ownership_owner_entity_id_fkey FOREIGN KEY (owner_entity_id) REFERENCES working.entity(id);


--
-- Name: email email_id_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.email
    ADD CONSTRAINT email_id_fkey FOREIGN KEY (id) REFERENCES working.entity(id) ON DELETE CASCADE;


--
-- Name: email email_owner_entity_id_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.email
    ADD CONSTRAINT email_owner_entity_id_fkey FOREIGN KEY (owner_entity_id) REFERENCES working.entity(id);


--
-- Name: entity_alias entity_alias_entity_id_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.entity_alias
    ADD CONSTRAINT entity_alias_entity_id_fkey FOREIGN KEY (entity_id) REFERENCES working.entity(id) ON DELETE CASCADE;


--
-- Name: extraction_candidate entity_candidate_extraction_batch_id_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.extraction_candidate
    ADD CONSTRAINT entity_candidate_extraction_batch_id_fkey FOREIGN KEY (extraction_batch_id) REFERENCES working.extraction_batch(id);


--
-- Name: extraction_candidate entity_candidate_record_id_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.extraction_candidate
    ADD CONSTRAINT entity_candidate_record_id_fkey FOREIGN KEY (record_id) REFERENCES working.normalized_record(id);


--
-- Name: extraction_candidate entity_candidate_source_id_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.extraction_candidate
    ADD CONSTRAINT entity_candidate_source_id_fkey FOREIGN KEY (source_id) REFERENCES evidence.source(id);


--
-- Name: entity_merge_event entity_merge_event_merged_entity_id_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.entity_merge_event
    ADD CONSTRAINT entity_merge_event_merged_entity_id_fkey FOREIGN KEY (merged_entity_id) REFERENCES working.entity(id);


--
-- Name: entity_merge_event entity_merge_event_reversible_to_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.entity_merge_event
    ADD CONSTRAINT entity_merge_event_reversible_to_fkey FOREIGN KEY (reversible_to) REFERENCES working.entity_merge_event(id);


--
-- Name: entity_merge_event entity_merge_event_surviving_entity_id_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.entity_merge_event
    ADD CONSTRAINT entity_merge_event_surviving_entity_id_fkey FOREIGN KEY (surviving_entity_id) REFERENCES working.entity(id);


--
-- Name: entity entity_merged_into_id_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.entity
    ADD CONSTRAINT entity_merged_into_id_fkey FOREIGN KEY (merged_into_id) REFERENCES working.entity(id);


--
-- Name: entity_resolution entity_resolution_canonical_entity_id_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.entity_resolution
    ADD CONSTRAINT entity_resolution_canonical_entity_id_fkey FOREIGN KEY (canonical_entity_id) REFERENCES working.entity(id);


--
-- Name: entity_resolution entity_resolution_mention_id_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.entity_resolution
    ADD CONSTRAINT entity_resolution_mention_id_fkey FOREIGN KEY (mention_id) REFERENCES working.entity_mention(id);


--
-- Name: event_ordering event_ordering_after_event_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.event_ordering
    ADD CONSTRAINT event_ordering_after_event_fkey FOREIGN KEY (after_event) REFERENCES analysis.timeline_event(event_id) ON DELETE CASCADE;


--
-- Name: event_ordering event_ordering_before_event_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.event_ordering
    ADD CONSTRAINT event_ordering_before_event_fkey FOREIGN KEY (before_event) REFERENCES analysis.timeline_event(event_id) ON DELETE CASCADE;


--
-- Name: event_source_record event_source_record_event_id_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.event_source_record
    ADD CONSTRAINT event_source_record_event_id_fkey FOREIGN KEY (event_id) REFERENCES analysis.timeline_event(event_id) ON DELETE CASCADE;


--
-- Name: event_source_record event_source_record_record_id_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.event_source_record
    ADD CONSTRAINT event_source_record_record_id_fkey FOREIGN KEY (record_id) REFERENCES working.normalized_record(id);


--
-- Name: event_source_record event_source_record_source_id_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.event_source_record
    ADD CONSTRAINT event_source_record_source_id_fkey FOREIGN KEY (source_id) REFERENCES evidence.source(id);


--
-- Name: extraction_candidate extraction_candidate_batch_fk; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.extraction_candidate
    ADD CONSTRAINT extraction_candidate_batch_fk FOREIGN KEY (extraction_batch_id) REFERENCES working.extraction_batch(id);


--
-- Name: message fk_msg_screenshot; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.message
    ADD CONSTRAINT fk_msg_screenshot FOREIGN KEY (screenshot_attachment_id) REFERENCES working.attachment(id);


--
-- Name: normalized_record fk_normrec_conv; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.normalized_record
    ADD CONSTRAINT fk_normrec_conv FOREIGN KEY (conversation_ref) REFERENCES working.conversation(id);


--
-- Name: geocode_request geocode_request_provenance_id_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.geocode_request
    ADD CONSTRAINT geocode_request_provenance_id_fkey FOREIGN KEY (provenance_id) REFERENCES ops.processing_run(run_id);


--
-- Name: geocode_resolution geocode_resolution_chosen_result_id_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.geocode_resolution
    ADD CONSTRAINT geocode_resolution_chosen_result_id_fkey FOREIGN KEY (chosen_result_id) REFERENCES working.geocode_result(id);


--
-- Name: geocode_resolution geocode_resolution_location_id_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.geocode_resolution
    ADD CONSTRAINT geocode_resolution_location_id_fkey FOREIGN KEY (location_id) REFERENCES working.location(id);


--
-- Name: geocode_resolution geocode_resolution_provenance_id_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.geocode_resolution
    ADD CONSTRAINT geocode_resolution_provenance_id_fkey FOREIGN KEY (provenance_id) REFERENCES ops.processing_run(run_id);


--
-- Name: geocode_resolution geocode_resolution_request_id_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.geocode_resolution
    ADD CONSTRAINT geocode_resolution_request_id_fkey FOREIGN KEY (request_id) REFERENCES working.geocode_request(id);


--
-- Name: geocode_result geocode_result_request_id_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.geocode_result
    ADD CONSTRAINT geocode_result_request_id_fkey FOREIGN KEY (request_id) REFERENCES working.geocode_request(id);


--
-- Name: gps_track gps_track_device_id_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.gps_track
    ADD CONSTRAINT gps_track_device_id_fkey FOREIGN KEY (device_id) REFERENCES working.device(id);


--
-- Name: gps_track gps_track_provenance_id_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.gps_track
    ADD CONSTRAINT gps_track_provenance_id_fkey FOREIGN KEY (provenance_id) REFERENCES ops.processing_run(run_id);


--
-- Name: gps_track gps_track_source_id_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.gps_track
    ADD CONSTRAINT gps_track_source_id_fkey FOREIGN KEY (source_id) REFERENCES evidence.source(id);


--
-- Name: handle handle_id_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.handle
    ADD CONSTRAINT handle_id_fkey FOREIGN KEY (id) REFERENCES working.entity(id) ON DELETE CASCADE;


--
-- Name: handle handle_owner_entity_id_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.handle
    ADD CONSTRAINT handle_owner_entity_id_fkey FOREIGN KEY (owner_entity_id) REFERENCES working.entity(id);


--
-- Name: home_base home_base_entity_id_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.home_base
    ADD CONSTRAINT home_base_entity_id_fkey FOREIGN KEY (entity_id) REFERENCES working.entity(id);


--
-- Name: home_base home_base_location_id_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.home_base
    ADD CONSTRAINT home_base_location_id_fkey FOREIGN KEY (location_id) REFERENCES working.location(id);


--
-- Name: home_base home_base_provenance_id_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.home_base
    ADD CONSTRAINT home_base_provenance_id_fkey FOREIGN KEY (provenance_id) REFERENCES ops.processing_run(run_id);


--
-- Name: id_xref id_xref_canonical_entity_id_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.id_xref
    ADD CONSTRAINT id_xref_canonical_entity_id_fkey FOREIGN KEY (canonical_entity_id) REFERENCES working.entity(id);


--
-- Name: lineage_edge lineage_edge_child_artifact_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.lineage_edge
    ADD CONSTRAINT lineage_edge_child_artifact_fkey FOREIGN KEY (child_artifact) REFERENCES working.artifact_registry(artifact_id);


--
-- Name: lineage_edge lineage_edge_parent_artifact_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.lineage_edge
    ADD CONSTRAINT lineage_edge_parent_artifact_fkey FOREIGN KEY (parent_artifact) REFERENCES working.artifact_registry(artifact_id);


--
-- Name: lineage_edge lineage_edge_parent_source_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.lineage_edge
    ADD CONSTRAINT lineage_edge_parent_source_fkey FOREIGN KEY (parent_source) REFERENCES evidence.evidence_hash(id);


--
-- Name: lineage_edge lineage_edge_producing_run_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.lineage_edge
    ADD CONSTRAINT lineage_edge_producing_run_fkey FOREIGN KEY (producing_run) REFERENCES ops.processing_run(run_id);


--
-- Name: location location_provenance_id_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.location
    ADD CONSTRAINT location_provenance_id_fkey FOREIGN KEY (provenance_id) REFERENCES ops.processing_run(run_id);


--
-- Name: message message_conversation_id_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.message
    ADD CONSTRAINT message_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES working.conversation(id);


--
-- Name: message message_derived_from_record_id_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.message
    ADD CONSTRAINT message_derived_from_record_id_fkey FOREIGN KEY (derived_from_record_id) REFERENCES working.normalized_record(id);


--
-- Name: message message_id_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.message
    ADD CONSTRAINT message_id_fkey FOREIGN KEY (id) REFERENCES working.normalized_record(id) ON DELETE CASCADE;


--
-- Name: message message_next_message_id_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.message
    ADD CONSTRAINT message_next_message_id_fkey FOREIGN KEY (next_message_id) REFERENCES working.message(id);


--
-- Name: message_participant message_participant_message_id_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.message_participant
    ADD CONSTRAINT message_participant_message_id_fkey FOREIGN KEY (message_id) REFERENCES working.message(id) ON DELETE CASCADE;


--
-- Name: message message_prev_message_id_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.message
    ADD CONSTRAINT message_prev_message_id_fkey FOREIGN KEY (prev_message_id) REFERENCES working.message(id);


--
-- Name: normalized_record normalized_record_acquisition_id_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.normalized_record
    ADD CONSTRAINT normalized_record_acquisition_id_fkey FOREIGN KEY (acquisition_id) REFERENCES evidence.acquisition(id);


--
-- Name: normalized_record normalized_record_artifact_id_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.normalized_record
    ADD CONSTRAINT normalized_record_artifact_id_fkey FOREIGN KEY (artifact_id) REFERENCES evidence.evidence_hash(id);


--
-- Name: normalized_record normalized_record_device_id_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.normalized_record
    ADD CONSTRAINT normalized_record_device_id_fkey FOREIGN KEY (device_id) REFERENCES working.device(id);


--
-- Name: normalized_record normalized_record_provenance_id_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.normalized_record
    ADD CONSTRAINT normalized_record_provenance_id_fkey FOREIGN KEY (provenance_id) REFERENCES ops.processing_run(run_id);


--
-- Name: normalized_record normalized_record_sender_entity_id_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.normalized_record
    ADD CONSTRAINT normalized_record_sender_entity_id_fkey FOREIGN KEY (sender_entity_id) REFERENCES working.entity(id);


--
-- Name: organization organization_id_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.organization
    ADD CONSTRAINT organization_id_fkey FOREIGN KEY (id) REFERENCES working.entity(id) ON DELETE CASCADE;


--
-- Name: person person_id_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.person
    ADD CONSTRAINT person_id_fkey FOREIGN KEY (id) REFERENCES working.entity(id) ON DELETE CASCADE;


--
-- Name: phone phone_id_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.phone
    ADD CONSTRAINT phone_id_fkey FOREIGN KEY (id) REFERENCES working.entity(id) ON DELETE CASCADE;


--
-- Name: phone phone_owner_entity_id_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.phone
    ADD CONSTRAINT phone_owner_entity_id_fkey FOREIGN KEY (owner_entity_id) REFERENCES working.entity(id);


--
-- Name: record_observation record_observation_extraction_batch_id_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.record_observation
    ADD CONSTRAINT record_observation_extraction_batch_id_fkey FOREIGN KEY (extraction_batch_id) REFERENCES working.extraction_batch(id);


--
-- Name: record_observation record_observation_record_id_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.record_observation
    ADD CONSTRAINT record_observation_record_id_fkey FOREIGN KEY (record_id) REFERENCES working.normalized_record(id);


--
-- Name: stay_point stay_point_device_id_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.stay_point
    ADD CONSTRAINT stay_point_device_id_fkey FOREIGN KEY (device_id) REFERENCES working.device(id);


--
-- Name: stay_point stay_point_location_id_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.stay_point
    ADD CONSTRAINT stay_point_location_id_fkey FOREIGN KEY (location_id) REFERENCES working.location(id);


--
-- Name: stay_point stay_point_provenance_id_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.stay_point
    ADD CONSTRAINT stay_point_provenance_id_fkey FOREIGN KEY (provenance_id) REFERENCES ops.processing_run(run_id);


--
-- Name: stay_point stay_point_track_id_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.stay_point
    ADD CONSTRAINT stay_point_track_id_fkey FOREIGN KEY (track_id) REFERENCES working.gps_track(id);


--
-- Name: temporal_anchor temporal_anchor_event_id_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.temporal_anchor
    ADD CONSTRAINT temporal_anchor_event_id_fkey FOREIGN KEY (event_id) REFERENCES analysis.timeline_event(event_id);


--
-- Name: vehicle vehicle_id_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.vehicle
    ADD CONSTRAINT vehicle_id_fkey FOREIGN KEY (id) REFERENCES working.entity(id) ON DELETE CASCADE;


--
-- Name: vehicle vehicle_owner_entity_id_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.vehicle
    ADD CONSTRAINT vehicle_owner_entity_id_fkey FOREIGN KEY (owner_entity_id) REFERENCES working.entity(id);


--
-- Name: waypoint_device_split waypoint_device_split_ingest_run_id_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.waypoint_device_split
    ADD CONSTRAINT waypoint_device_split_ingest_run_id_fkey FOREIGN KEY (ingest_run_id) REFERENCES ops.processing_run(run_id);


--
-- Name: waypoint_device_split waypoint_device_split_raw_path_id_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.waypoint_device_split
    ADD CONSTRAINT waypoint_device_split_raw_path_id_fkey FOREIGN KEY (raw_path_id) REFERENCES evidence.raw_path(id);


--
-- Name: waypoint_device_split waypoint_device_split_split_from_activity_fkey; Type: FK CONSTRAINT; Schema: working; Owner: -
--

ALTER TABLE ONLY working.waypoint_device_split
    ADD CONSTRAINT waypoint_device_split_split_from_activity_fkey FOREIGN KEY (split_from_activity) REFERENCES evidence.raw_activity(id);


--
-- PostgreSQL database dump complete
--

\unrestrict AN3heiIngjiXbRkuyiNRBKjHgTp2eDWijtBhXcYsjwTwEcne1dwY187Y39S0N2e

