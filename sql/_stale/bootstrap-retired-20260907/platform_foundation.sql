-- sql/bootstrap/platform_foundation.sql — minimal foundation for the NEW `platform` database.
--
-- Applied by scripts/bootstrap_platform_database.py --apply, against the `platform` database
-- ONLY (never against `ai`). Every statement here is idempotent — safe to re-run against a
-- database that already has some or all of this applied.
--
-- This file is NOT part of the numbered sql/NNNN chain (that chain governs the existing `ai`
-- database only — see docs/CONVENTIONS.md "SQL / migrations"). It is a standalone bootstrap
-- artifact, mirroring the existing sql/bootstrap/schema_baseline.sql convention.
--
-- public.schema_version's shape below is NOT this file's own invention — it is the exact
-- contract scripts/apply_0036_live.py already reads and writes (owned by a different/root lane,
-- confirmed by reading that file): INSERT column list (version_label, applies_to, ddl_uri,
-- ddl_hash, migration_id, status, notes, created_by), a bytea ddl_hash, and a query filtered on
-- `migration_id = ... AND status = 'active'` that assumes at most one active row per
-- migration_id — hence the partial unique index below. This bootstrap's own foundation apply
-- records itself as one more row in the SAME ledger, migration_id = '0000_platform_foundation'.
--
-- Roles: platform_admin owns the database and the ledger table. context_owner is a NOLOGIN
-- group role intended to OWN the `context` schema sql/0036_context_import_foundation.sql
-- creates — it is granted CREATE on this database so a connection that `SET LOCAL ROLE
-- context_owner`s before running 0036's DDL can actually create that schema and its objects
-- under context_owner's ownership (see docs/pending-review/plans/apply-0036-set-role-patch.md
-- for the exact required root-lane patch to scripts/apply_0036_live.py — this bootstrap cannot
-- edit that file). platform_admin is granted membership in context_owner so it can administer
-- context-owned objects later via `SET ROLE context_owner`. context_import_writer and
-- context_reader are NOLOGIN placeholder group roles for the future write/read ACL surface over
-- the `context` schema; granting them table-level privileges must wait until that schema exists
-- (ALTER DEFAULT PRIVILEGES ... IN SCHEMA context requires the schema to already be present) —
-- out of this bootstrap's scope, tracked in the same pending-review doc.
--
-- platform_runtime is LOGIN (the eventual application runtime identity) but ships here with NO
-- password — a NULL rolpassword always fails password authentication, so the role is inert until
-- scripts/bootstrap_platform_database.py sets one via a separate, parameterized `ALTER ROLE ...
-- WITH PASSWORD` statement sourced from the PLATFORM_DATABASE_PASSWORD environment variable
-- (never embedded in this git-tracked file, never printed). SUPERUSER/CREATEDB/CREATEROLE/
-- REPLICATION/BYPASSRLS are stated OFF explicitly (owner directive) rather than left to CREATE
-- ROLE's unstated defaults, and the bootstrap script separately walks platform_runtime's full
-- transitive role-membership closure to confirm none of those attributes reach it indirectly
-- either (see runtime_role_violates_safety() and its live query).
--
-- The `platform` database itself has CONNECT/TEMPORARY revoked from PUBLIC below — a freshly
-- created database otherwise inherits the cluster's default ACL, which grants PUBLIC both.
--
-- Byline: Claude Code · Sonnet 5 · 2026-08-27

-- uuidv7() is native on PG18 (see sql/0001_init_extensions.sql) — no extension needed for it.
-- sql/0036_context_import_foundation.sql declares zero CREATE EXTENSION statements of its own
-- (confirmed by reading it) and relies on uuidv7() and digest() (pgcrypto, below) — this
-- bootstrap's extension set already covers it. scripts/bootstrap_platform_database.py's
-- discover_required_extensions() still reads 0036 live rather than trusting this note.
CREATE EXTENSION IF NOT EXISTS pgcrypto;  -- digest()/hmac() for checksum + custody-style hashing

-- Cluster-wide roles. CREATE ROLE has no native IF NOT EXISTS, and roles are cluster-scoped
-- (not database-local), so these are guarded existence checks rather than a CREATE DATABASE-style
-- clause. Running this file against any database in the cluster has the same effect.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'platform_admin') THEN
        CREATE ROLE platform_admin NOLOGIN;
    END IF;
END $$;

-- Explicit, not merely default: SUPERUSER/CREATEDB/CREATEROLE/REPLICATION/BYPASSRLS are stated
-- OFF so intent is grep-able in the DDL itself, not just implied by CREATE ROLE's unstated
-- defaults. LOGIN with no password set (see header) — inert until the bootstrap script sets one.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'platform_runtime') THEN
        CREATE ROLE platform_runtime LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'context_owner') THEN
        CREATE ROLE context_owner NOLOGIN;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'context_import_writer') THEN
        CREATE ROLE context_import_writer NOLOGIN;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'context_reader') THEN
        CREATE ROLE context_reader NOLOGIN;
    END IF;
END $$;

-- Idempotent: re-granting an already-held role membership is a silent no-op in Postgres.
GRANT context_owner TO platform_admin;
GRANT context_import_writer TO platform_runtime;
GRANT context_reader TO platform_runtime;

-- Lets a `SET LOCAL ROLE context_owner` connection (see the header note and
-- docs/pending-review/plans/apply-0036-set-role-patch.md) actually create the `context` schema
-- and its objects — CREATE on a database is an ordinary object-level ACL grant, not a role
-- attribute; it carries none of the SUPERUSER/CREATEDB/CREATEROLE/BYPASSRLS risk this file is
-- otherwise careful to keep off every role.
GRANT CREATE ON DATABASE platform TO context_owner;

-- Revoke the cluster's default PUBLIC access to this database. A freshly created database
-- otherwise inherits the built-in default ACL, which grants PUBLIC both CONNECT and TEMPORARY.
REVOKE CONNECT, TEMPORARY ON DATABASE platform FROM PUBLIC;

-- Bootstrap/migration ledger for the `platform` database — the SAME table
-- scripts/apply_0036_live.py reads and writes for migration 0036 (see header). One row per
-- applied migration/foundation unit; migration_id + the partial unique index below let readers
-- assume at most one 'active' row per migration_id, matching apply_0036_live.py's own assumption.
CREATE TABLE IF NOT EXISTS public.schema_version (
    id            UUID PRIMARY KEY DEFAULT uuidv7(),
    version_label TEXT NOT NULL,
    applies_to    TEXT NOT NULL,
    ddl_uri       TEXT NOT NULL,
    ddl_hash      BYTEA NOT NULL,
    migration_id  TEXT NOT NULL,
    status        TEXT NOT NULL CHECK (status IN ('active', 'superseded', 'rolled_back')),
    notes         TEXT,
    created_by    TEXT NOT NULL DEFAULT current_user,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS schema_version_active_migration_uq
    ON public.schema_version (migration_id)
    WHERE status = 'active';

COMMENT ON TABLE public.schema_version IS
    'Bootstrap/migration ledger shared by scripts/bootstrap_platform_database.py (this file, '
    'migration_id = 0000_platform_foundation) and scripts/apply_0036_live.py (migration_id = '
    '0036). At most one active row per migration_id (schema_version_active_migration_uq).';

ALTER TABLE public.schema_version OWNER TO platform_admin;
