-- 0037_platform_runtime_connect.sql -- restore the runtime login's database entry right.
--
-- The platform foundation correctly removes PUBLIC database access, but its
-- original bootstrap omitted the corresponding explicit CONNECT grant for the
-- dedicated runtime LOGIN role.  This forward-only correction grants that
-- single required privilege and removes the two database-level privileges the
-- runtime must never receive.  Application/schema privileges remain unchanged.
--
-- Byline: Codex · GPT-5 · 2026-08-27

BEGIN;

DO $$
BEGIN
    IF current_database() <> 'platform' THEN
        RAISE EXCEPTION 'migration 0037 may run only in database platform, not %', current_database();
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'platform_admin') THEN
        RAISE EXCEPTION 'migration 0037 requires bootstrap role platform_admin';
    END IF;
    IF NOT EXISTS (
        SELECT 1
        FROM pg_roles
        WHERE rolname = 'platform_runtime'
          AND rolcanlogin
          AND NOT (rolsuper OR rolcreatedb OR rolcreaterole OR rolreplication OR rolbypassrls)
    ) THEN
        RAISE EXCEPTION 'migration 0037 requires a safe LOGIN role platform_runtime';
    END IF;
END;
$$;

-- Database ACL changes require the database owner.  The migration ledger is
-- also authored under this role by its guarded apply helper.
SET LOCAL ROLE platform_admin;
GRANT CONNECT ON DATABASE platform TO platform_runtime;
REVOKE TEMPORARY, CREATE ON DATABASE platform FROM platform_runtime;

COMMIT;
