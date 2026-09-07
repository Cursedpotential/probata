-- 0039_context_source_retention_lock.sql -- narrow row-lock privilege for retain-original.
--
-- retain_original_activity selects context.source_version joined to context.source
-- with an unqualified FOR UPDATE. PostgreSQL therefore requires UPDATE privilege on
-- at least one column of both selected tables. Migration 0036 already grants lifecycle
-- UPDATE on source_version; grant only source.id through the capability role so the
-- existing query can lock the immutable source identity without granting table-wide
-- UPDATE. The source_append_only trigger continues to reject every actual mutation.
--
-- Byline: Codex · GPT-5 · 2026-08-27

BEGIN;

DO $$
BEGIN
    IF current_database() <> 'platform' THEN
        RAISE EXCEPTION 'migration 0039 may run only in database platform, not %', current_database();
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'context_owner' AND NOT rolcanlogin) THEN
        RAISE EXCEPTION 'migration 0039 requires NOLOGIN role context_owner';
    END IF;
    IF NOT EXISTS (
        SELECT 1
        FROM pg_roles
        WHERE rolname = 'context_import_writer'
          AND NOT rolcanlogin
          AND NOT (rolsuper OR rolcreatedb OR rolcreaterole OR rolreplication OR rolbypassrls)
    ) THEN
        RAISE EXCEPTION 'migration 0039 requires safe NOLOGIN role context_import_writer';
    END IF;
    IF NOT pg_has_role('platform_runtime', 'context_import_writer', 'MEMBER') THEN
        RAISE EXCEPTION 'migration 0039 requires platform_runtime membership in context_import_writer';
    END IF;
    IF to_regclass('context.source') IS NULL
       OR NOT EXISTS (
           SELECT 1
           FROM information_schema.columns
           WHERE table_schema = 'context' AND table_name = 'source' AND column_name = 'id'
       ) THEN
        RAISE EXCEPTION 'migration 0039 requires context.source(id)';
    END IF;
    IF NOT EXISTS (
        SELECT 1
        FROM pg_trigger trigger
        WHERE trigger.tgrelid = 'context.source'::regclass
          AND trigger.tgname = 'source_append_only'
          AND NOT trigger.tgisinternal
          AND trigger.tgenabled <> 'D'
    ) THEN
        RAISE EXCEPTION 'migration 0039 requires the enabled source_append_only trigger';
    END IF;
END;
$$;

SET LOCAL ROLE context_owner;
GRANT UPDATE (id) ON TABLE context.source TO context_import_writer;

COMMIT;
