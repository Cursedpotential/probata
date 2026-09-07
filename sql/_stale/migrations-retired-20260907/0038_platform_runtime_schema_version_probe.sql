-- 0038_platform_runtime_schema_version_probe.sql -- least-privilege schema probe access.
--
-- platform_runtime must evaluate the migration-ledger probe used during worker
-- startup.  Grant only the two predicate columns; this intentionally does not
-- grant table-wide SELECT or access to any ledger payload/provenance columns.
--
-- Byline: Codex · GPT-5 · 2026-08-27

BEGIN;

DO $$
BEGIN
    IF current_database() <> 'platform' THEN
        RAISE EXCEPTION 'migration 0038 may run only in database platform, not %', current_database();
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'platform_admin') THEN
        RAISE EXCEPTION 'migration 0038 requires bootstrap role platform_admin';
    END IF;
    IF NOT EXISTS (
        SELECT 1
        FROM pg_roles
        WHERE rolname = 'platform_runtime'
          AND rolcanlogin
          AND NOT (rolsuper OR rolcreatedb OR rolcreaterole OR rolreplication OR rolbypassrls)
    ) THEN
        RAISE EXCEPTION 'migration 0038 requires a safe LOGIN role platform_runtime';
    END IF;
    IF to_regclass('public.schema_version') IS NULL
       OR NOT EXISTS (
           SELECT 1
           FROM information_schema.columns
           WHERE table_schema = 'public' AND table_name = 'schema_version'
             AND column_name IN ('migration_id', 'status')
           GROUP BY table_schema, table_name
           HAVING count(*) = 2
       ) THEN
        RAISE EXCEPTION 'migration 0038 requires public.schema_version(migration_id, status)';
    END IF;
END;
$$;

SET LOCAL ROLE platform_admin;
GRANT SELECT (migration_id, status) ON TABLE public.schema_version TO platform_runtime;

COMMIT;
