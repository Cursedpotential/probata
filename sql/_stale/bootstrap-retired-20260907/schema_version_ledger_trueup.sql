-- Forward-only true-up from the legacy schema_version_id ledger shape to the
-- rich ledger contract already declared by platform_foundation.sql.
-- Byline: Codex · GPT-5.6-Sol · 2026-08-30.

BEGIN;

DO $guard$
BEGIN
    IF current_database() <> 'platform' THEN
        RAISE EXCEPTION 'schema-version ledger true-up may run only in platform';
    END IF;
    IF (SELECT pg_get_userbyid(relowner) FROM pg_class
        WHERE oid = 'public.schema_version'::regclass) NOT IN ('ai', 'platform_admin') THEN
        RAISE EXCEPTION 'public.schema_version has an unrecognized legacy owner';
    END IF;
    IF EXISTS (SELECT 1 FROM public.schema_version) THEN
        RAISE EXCEPTION 'legacy schema-version ledger is not empty; manual reconciliation required';
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_schema='public' AND table_name='schema_version' AND column_name='schema_version_id')
       AND NOT EXISTS (SELECT 1 FROM information_schema.columns
                       WHERE table_schema='public' AND table_name='schema_version' AND column_name='id') THEN
        ALTER TABLE public.schema_version RENAME COLUMN schema_version_id TO id;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema='public' AND table_name='schema_version' AND column_name='id') THEN
        RAISE EXCEPTION 'public.schema_version has no recognized identity column';
    END IF;
    IF (SELECT pg_get_userbyid(relowner) FROM pg_class
        WHERE oid = 'public.schema_version'::regclass) = 'ai' THEN
        ALTER TABLE public.schema_version OWNER TO platform_admin;
    END IF;
END
$guard$;

-- Create the schema-owned object under the authorized migration identity.
-- platform_admin owns the table after the guard but deliberately has no
-- CREATE privilege on public, so doing this after SET ROLE would fail.
CREATE UNIQUE INDEX IF NOT EXISTS schema_version_active_migration_uq
    ON public.schema_version (migration_id)
    WHERE status = 'active';

SET LOCAL ROLE platform_admin;

ALTER TABLE public.schema_version
    ALTER COLUMN ddl_uri SET NOT NULL,
    ALTER COLUMN ddl_hash SET NOT NULL,
    ALTER COLUMN migration_id SET NOT NULL,
    ALTER COLUMN status SET DEFAULT 'active',
    ALTER COLUMN created_by SET DEFAULT current_user;

ALTER TABLE public.schema_version
    DROP CONSTRAINT IF EXISTS schema_version_status_check,
    DROP COLUMN IF EXISTS supersedes;

ALTER TABLE public.schema_version
    ADD CONSTRAINT schema_version_status_check
    CHECK (status IN ('active', 'superseded', 'rolled_back'));

COMMIT;
