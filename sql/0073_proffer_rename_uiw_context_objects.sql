-- 0073_proffer_rename_uiw_context_objects.sql
-- Byline: Claude Code · Fable 5.1 · 2026-09-06.
--
-- D-140 renamed the import lane UIW -> proffer. The nine `context.uiw_*` tables and every
-- constraint / index / function / trigger carrying the `uiw_` prefix are renamed to `proffer_*`
-- here. Owner, 2026-09-06 18:0x: "Eleven context.uiw_* tables still carry the old lane name in
-- DDL. Only a new migration renames them. FIX IT." and "NOTHING IS LIVE" (D-142: everything in
-- context.* is rehearsal fixture data; 18 rows at apply time).
--
-- Mechanics: table renames keep OIDs, so FKs, views, grants, RLS and stats follow automatically.
-- Constraint and index names do NOT follow a table rename, so they are renamed explicitly.
-- The block is idempotent: it renames only objects whose current name still starts with `uiw_`.
-- A second run is a no-op. Live check 2026-09-06: no functions or triggers exist with a `uiw`
-- name (the guard functions in 0050/0053 were named without the prefix or never applied), but
-- the loop covers them in case a rehearsal database has them.

BEGIN;

DO $$
DECLARE
    r record;
BEGIN
    -- 1. tables (relkind r/p), views, sequences in schema context
    FOR r IN
        SELECT c.relname
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'context'
          AND c.relkind IN ('r', 'p', 'v', 'm', 'S')
          AND c.relname LIKE 'uiw\_%' ESCAPE '\'
    LOOP
        EXECUTE format('ALTER TABLE context.%I RENAME TO %I',
                       r.relname, 'proffer_' || substr(r.relname, 5));
    END LOOP;

    -- 2. constraints (incl. PG18 named NOT NULL constraints) on context tables
    FOR r IN
        SELECT con.conname, con.conrelid::regclass AS rel
        FROM pg_constraint con
        JOIN pg_class c ON c.oid = con.conrelid
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'context'
          AND con.conname LIKE 'uiw\_%' ESCAPE '\'
    LOOP
        EXECUTE format('ALTER TABLE %s RENAME CONSTRAINT %I TO %I',
                       r.rel, r.conname, 'proffer_' || substr(r.conname, 5));
    END LOOP;

    -- 3. indexes not backed by a constraint (constraint-backed indexes were renamed in step 2)
    FOR r IN
        SELECT c.relname
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'context'
          AND c.relkind = 'i'
          AND c.relname LIKE 'uiw\_%' ESCAPE '\'
    LOOP
        EXECUTE format('ALTER INDEX context.%I RENAME TO %I',
                       r.relname, 'proffer_' || substr(r.relname, 5));
    END LOOP;

    -- 4. triggers
    FOR r IN
        SELECT t.tgname, t.tgrelid::regclass AS rel
        FROM pg_trigger t
        JOIN pg_class c ON c.oid = t.tgrelid
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'context'
          AND NOT t.tgisinternal
          AND t.tgname LIKE 'uiw\_%' ESCAPE '\'
    LOOP
        EXECUTE format('ALTER TRIGGER %I ON %s RENAME TO %I',
                       r.tgname, r.rel, 'proffer_' || substr(r.tgname, 5));
    END LOOP;

    -- 5. functions named *_uiw_* in schema context (guard functions from 0050/0053, if present)
    FOR r IN
        SELECT p.oid::regprocedure AS sig, p.proname
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'context'
          AND p.proname LIKE '%uiw%'
    LOOP
        EXECUTE format('ALTER FUNCTION %s RENAME TO %I',
                       r.sig, replace(r.proname, 'uiw', 'proffer'));
    END LOOP;
END $$;

-- Post-condition: nothing in schema context still carries the old lane prefix.
DO $$
DECLARE
    leftovers int;
BEGIN
    SELECT count(*) INTO leftovers
    FROM (
        SELECT c.relname AS nm FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
         WHERE n.nspname = 'context' AND c.relname LIKE 'uiw\_%' ESCAPE '\'
        UNION ALL
        SELECT con.conname FROM pg_constraint con JOIN pg_class c ON c.oid = con.conrelid
          JOIN pg_namespace n ON n.oid = c.relnamespace
         WHERE n.nspname = 'context' AND con.conname LIKE 'uiw\_%' ESCAPE '\'
        UNION ALL
        SELECT t.tgname FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
          JOIN pg_namespace n ON n.oid = c.relnamespace
         WHERE n.nspname = 'context' AND NOT t.tgisinternal AND t.tgname LIKE 'uiw\_%' ESCAPE '\'
        UNION ALL
        SELECT p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'context' AND p.proname LIKE '%uiw%'
    ) x;
    IF leftovers <> 0 THEN
        RAISE EXCEPTION 'PROFFER_RENAME_INCOMPLETE: % context objects still named uiw_*', leftovers;
    END IF;
END $$;

COMMIT;
