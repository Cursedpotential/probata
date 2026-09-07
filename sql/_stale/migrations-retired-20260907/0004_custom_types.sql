-- 0004_custom_types.sql — domain-specific field types (handoff: "no generic
-- bullshit field types"). Enums/domains/composites that map to the H0 evidence
-- schemas (Entity / Relationship / Event) so columns are self-describing and
-- validated at the DB instead of being free-text.
--
-- Byline: Claude Code · Opus 4.8 · 2026-06-14
--
-- RUNS ONCE on an EMPTY data dir (via /docker-entrypoint-initdb.d, after 0001-0003).
-- On an EXISTING pgdata volume these do NOT auto-apply — run this file by hand:
--     psql -U "$DB_USER" -d "$DB_DATABASE" -f sql/0004_custom_types.sql
-- All objects are idempotent-guarded so re-running is safe.

-- ---------------------------------------------------------------------------
-- ENUMS — closed vocabularies (replace status/type text columns)
-- ---------------------------------------------------------------------------
DO $$ BEGIN
    CREATE TYPE entity_type AS ENUM
        ('person','org','project','tech','location','concept');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE temporal_class AS ENUM ('historical','current','future');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE event_type AS ENUM
        ('milestone','decision','meeting','incident','change','memory','upcoming');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    -- disclosure tier for bitemporal knowledge-time gating (NormalizedRecord)
    CREATE TYPE disclosure_tier AS ENUM ('public','restricted','sealed');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    -- MCL 722.23 best-interest factors (a)-(l). Letter-coded; descriptions live
    -- in the mcl_722_23 reference table / ontology, not the enum.
    CREATE TYPE mcl_factor AS ENUM
        ('a','b','c','d','e','f','g','h','i','j','k','l');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    -- which store an id/record came from (pairs with the id_xref crosswalk)
    CREATE TYPE source_system AS ENUM ('postgres','neo4j','milvus','surrealdb');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    -- how an id_xref link was established (mechanical vs resolved vs human)
    CREATE TYPE match_method AS ENUM ('exact','resolved','manual');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ---------------------------------------------------------------------------
-- DOMAINS — constrained scalar aliases (validation travels with the type)
-- ---------------------------------------------------------------------------
DO $$ BEGIN
    -- 0.000-1.000 confidence used across Entity/Relationship/Event + id_xref
    CREATE DOMAIN confidence AS numeric(4,3)
        CHECK (VALUE IS NULL OR (VALUE >= 0 AND VALUE <= 1));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    -- canonical lowercase-hyphenated uuid string for cross-store correlation.
    -- (PG keys stay native `uuid`; this is for text contexts / external refs.)
    CREATE DOMAIN canonical_id AS uuid;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    -- WGS84 point for GPS evidence. PostGIS geography has a REAL spatial index
    -- (GiST) — this is why heavy geo lives in PG, with a GeoJSON projection to
    -- SurrealDB (which lacks a spatial index). 4326 = lat/lon.
    CREATE DOMAIN geo_point AS geography(Point, 4326);
EXCEPTION WHEN duplicate_object THEN NULL;
         WHEN undefined_object THEN
            RAISE NOTICE 'postgis geography type absent — geo_point domain skipped';
END $$;

-- ---------------------------------------------------------------------------
-- COMPOSITE TYPES — structured, non-generic fields
-- ---------------------------------------------------------------------------
DO $$ BEGIN
    -- a provenance pointer: which system + native id + a free locator (page,
    -- offset, line). Use as source_ref[] on evidence/entity/event rows.
    CREATE TYPE source_ref AS (
        system     source_system,
        native_id  text,
        locator    text
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ---------------------------------------------------------------------------
-- USAGE NOTES (not executed)
-- ---------------------------------------------------------------------------
-- Bitemporal Relationship validity + no-overlap (needs btree_gist, enabled 0001):
--     validity tstzrange NOT NULL,
--     EXCLUDE USING gist (from_entity WITH =, to_entity WITH =,
--                         rel_type WITH =, validity WITH &&)
-- Hierarchies:  category ltree         -- e.g. 'evidence.comms.sms'
-- Fuzzy match:  WHERE name % $1        -- pg_trgm; or levenshtein(name,$1) <= 2
-- Geo proximity: ORDER BY geo <-> $1 LIMIT k   -- GiST KNN on geo_point
