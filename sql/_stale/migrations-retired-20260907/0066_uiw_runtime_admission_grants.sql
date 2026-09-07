-- 0066_uiw_runtime_admission_grants.sql -- unblock universal-import-worker's
-- fail-closed UIW schema admission probe (modules/engine/postgres/uiw_schema_probe.go).
--
-- Byline: Claude Code · Sonnet 5 · 2026-09-02 (BUILD LANE S1).
--
-- ROOT CAUSE (live-verified 2026-09-02, as platform_runtime, transaction
-- rolled back): the probe's single admission query errors out -- it never
-- reaches its own pass/fail booleans -- because platform_runtime has no
-- USAGE on three schemas the query text touches:
--
--   * registry -- the query casts 'registry.matter'::regclass /
--     'registry.court_case'::regclass while checking the 0054 scope-FK
--     identities. PostgreSQL gates that catalog lookup on schema USAGE even
--     though the query never SELECTs a registry row directly. Live error:
--     `permission denied for schema registry` (SQLSTATE 42501). This alone
--     is what ProbeUIWSchema.go:148 turns into "catalog verification
--     unavailable" and crash-loops the worker.
--   * raw -- the DuckDB structured-ELT lane (activities.ExecuteStructuredELT,
--     modules/engine/postgres/elt_structured_repository.go) is
--     platform_runtime's only writer into schema raw (0058's verbatim
--     landing zone), and it touches exactly one table: raw.raw_csv --
--     SELECT for its idempotent-replay guard, INSERT for the landing write.
--     Live-confirmed missing: `permission denied for schema raw` on a bare
--     `SELECT count(*) FROM raw.raw_csv`.
--   * evidence -- that same ELT insert casts its medium column to
--     evidence.record_medium; PostgreSQL gates the schema-qualified TYPE
--     resolution on schema USAGE exactly like the regclass case above.
--     Live-confirmed missing: `permission denied for schema evidence` on
--     `SELECT 'export'::evidence.record_medium` alone.
--
-- registry.matter/registry.court_case SELECT and analysis.* USAGE/SELECT are
-- already granted to platform_runtime (0054; live-verified true) -- only the
-- schema-level USAGE gates above were missing. No table in schema raw other
-- than raw_csv has a live writer (repo-wide grep 2026-09-02); granting the
-- other 12 raw.<format> tables now would be privilege creep ahead of any
-- code that uses them, so this migration grants raw_csv only.
--
-- ops.migration_ledger is included as forward-provisioning, not a probe fix:
-- modules/engine/postgres/uiw_schema_probe.go currently reads
-- public.schema_version for its migration-ledger check, but migration 0055
-- states in terminal words that public.schema_version "is NOT a migration
-- ledger and never was" and ops.migration_ledger is "THE migration ledger."
-- Live-verified 2026-09-02: public.schema_version has ZERO rows for any of
-- the probe's 9 required migration_ids; ops.migration_ledger has all 9. That
-- mismatch is a Go-code defect in uiw_schema_probe.go's query target, not a
-- grants gap, and is out of this migration's scope (see
-- docs/reviews/2026-09-02-uiw-schema-admission-unblock.md) -- Go source is
-- untouched here. This grant exists so a corrected probe is not blocked by a
-- second missing grant the moment its query target is fixed.
--
-- OWNERSHIP NOTE: schemas registry and raw are owned by platform_admin
-- (0062, 0058) so their GRANTs run under SET LOCAL ROLE platform_admin,
-- matching every prior grants migration's convention. Schemas evidence and
-- ops, and the table raw.raw_csv, are live-owned by the bootstrap superuser
-- -- NOT platform_admin, despite 0054's own DDL comment assuming
-- `AUTHORIZATION platform_admin` project-wide (live drift, reported in the
-- review doc, not corrected here). Their GRANTs below run without a role
-- switch: platform_admin has no grant authority over an object it does not
-- own, so SET LOCAL ROLE platform_admin would fail closed on exactly the
-- objects that need it.

BEGIN;

DO $preflight$
BEGIN
    IF current_database() <> 'platform' THEN
        RAISE EXCEPTION 'migration 0066 may run only in database platform, not %', current_database();
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_roles
        WHERE rolname = 'platform_runtime' AND rolcanlogin
          AND NOT (rolsuper OR rolcreatedb OR rolcreaterole OR rolreplication OR rolbypassrls)
    ) THEN
        RAISE EXCEPTION 'migration 0066 requires a safe LOGIN role platform_runtime';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'platform_admin' AND NOT rolcanlogin) THEN
        RAISE EXCEPTION 'migration 0066 requires bootstrap role platform_admin';
    END IF;
    IF to_regnamespace('registry') IS NULL OR to_regnamespace('raw') IS NULL
       OR to_regnamespace('evidence') IS NULL OR to_regnamespace('ops') IS NULL THEN
        RAISE EXCEPTION 'migration 0066 requires the registry/raw/evidence/ops schemas to already exist';
    END IF;
    IF to_regclass('raw.raw_csv') IS NULL THEN
        RAISE EXCEPTION 'migration 0066 requires raw.raw_csv (0058 landing table)';
    END IF;
    IF to_regclass('ops.migration_ledger') IS NULL THEN
        RAISE EXCEPTION 'migration 0066 requires ops.migration_ledger (0055 real ledger)';
    END IF;
END
$preflight$;

-- ---------------------------------------------------------------------------
-- registry: schema USAGE only. Table-level SELECT on registry.matter and
-- registry.court_case is already in place; this migration must not widen it.
-- ---------------------------------------------------------------------------
SET LOCAL ROLE platform_admin;
GRANT USAGE ON SCHEMA registry TO platform_runtime;
RESET ROLE;

-- ---------------------------------------------------------------------------
-- raw: schema USAGE (platform_admin-owned) plus exactly the two verbs the
-- ELT lane issues against exactly the one table it touches.
-- ---------------------------------------------------------------------------
SET LOCAL ROLE platform_admin;
GRANT USAGE ON SCHEMA raw TO platform_runtime;
RESET ROLE;
GRANT SELECT, INSERT ON TABLE raw.raw_csv TO platform_runtime;

-- ---------------------------------------------------------------------------
-- evidence: schema USAGE only, for the evidence.record_medium type cast.
-- No evidence table is read or written by the platform_runtime pipeline
-- today, so no table-level grant is added.
-- ---------------------------------------------------------------------------
GRANT USAGE ON SCHEMA evidence TO platform_runtime;

-- ---------------------------------------------------------------------------
-- ops: schema USAGE plus SELECT on exactly the one column an
-- existence-only ledger check needs (ops.migration_ledger has no
-- active/superseded/deprecated status column to mirror 0038's narrower
-- (migration_id, status) grant against public.schema_version).
-- ---------------------------------------------------------------------------
GRANT USAGE ON SCHEMA ops TO platform_runtime;
GRANT SELECT (migration_id) ON TABLE ops.migration_ledger TO platform_runtime;

-- ---------------------------------------------------------------------------
-- verify: exactly the privileges above, nothing wider.
-- ---------------------------------------------------------------------------
DO $verify$
BEGIN
    IF NOT has_schema_privilege('platform_runtime', 'registry', 'USAGE')
       OR has_schema_privilege('platform_runtime', 'registry', 'CREATE')
       OR NOT has_schema_privilege('platform_runtime', 'raw', 'USAGE')
       OR has_schema_privilege('platform_runtime', 'raw', 'CREATE')
       OR NOT has_table_privilege('platform_runtime', 'raw.raw_csv', 'SELECT')
       OR NOT has_table_privilege('platform_runtime', 'raw.raw_csv', 'INSERT')
       OR has_table_privilege('platform_runtime', 'raw.raw_csv', 'UPDATE')
       OR has_table_privilege('platform_runtime', 'raw.raw_csv', 'DELETE')
       OR NOT has_schema_privilege('platform_runtime', 'evidence', 'USAGE')
       OR has_schema_privilege('platform_runtime', 'evidence', 'CREATE')
       OR NOT has_schema_privilege('platform_runtime', 'ops', 'USAGE')
       OR has_schema_privilege('platform_runtime', 'ops', 'CREATE')
       OR NOT has_column_privilege('platform_runtime', 'ops.migration_ledger', 'migration_id', 'SELECT')
       OR has_table_privilege('platform_runtime', 'ops.migration_ledger', 'INSERT') THEN
        RAISE EXCEPTION 'migration 0066 runtime admission grants are not exact';
    END IF;
    -- confirm no other raw.<format> table was accidentally widened. Walked via
    -- pg_class/pg_namespace directly (not information_schema.tables), which in
    -- this pg_duckdb-attached database can surface catalog rows outside the
    -- literal schema being filtered on.
    IF EXISTS (
        SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'raw' AND c.relkind = 'r' AND c.relname <> 'raw_csv'
          AND has_table_privilege('platform_runtime', c.oid, 'SELECT')
    ) THEN
        RAISE EXCEPTION 'migration 0066 must not grant any raw.<format> table beyond raw_csv';
    END IF;
END
$verify$;

COMMIT;
