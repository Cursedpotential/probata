-- 0067_uiw_admission_constraint_repair.sql -- reconcile the 8 UIW source-
-- context scope constraints (originally authored by sql/0054) against the
-- CURRENT registry.* schema shape, and VALIDATE the ones sql/0054 added
-- NOT VALID but that were never finished.
--
-- Byline: Claude Code · Sonnet 5 · 2026-09-02 (BUILD LANE S2).
--
-- CONTEXT: modules/engine/postgres/uiw_schema_probe.go's constraintsExact
-- check requires exactly 5 validated FKs + 2 validated CHECKs + 1 validated
-- UNIQUE across context.source_version / context.uiw_source_context_revision,
-- identity-scoped to registry.matter / registry.court_case. Live drift
-- (docs/reviews/2026-09-02-uiw-schema-admission-unblock.md §4, re-verified
-- live here 2026-09-02 via pg_constraint as database platform): the
-- committed sql/0054_platform_case_registry.sql still targets
-- analysis.matter / analysis.court_case -- tables that no longer exist live.
-- An undocumented reconciliation sometime after 0054 was first applied moved
-- matter/court_case out of analysis (analysis.matter/court_case do not exist:
-- to_regclass returns NULL for both, live-confirmed); sql/0062_registry_split
-- then moved them a second time, reference.matter/court_case -> registry.*.
-- sql/0054 is immutable (already applied; this repo never edits an applied
-- migration) -- this migration repairs the live constraint set without
-- touching sql/0054's text.
--
-- CONSTRAINT INVENTORY -- all 8 constraints the probe requires; live status
-- as of 2026-09-02, verified via pg_constraint against database platform
-- (relation, name, type, live status BEFORE this migration):
--
--   1. context.source_version.source_version_matter_case_pair_check   CHECK   EXISTS, VALIDATED  -- untouched by this migration
--   2. context.source_version.source_version_court_case_scope_fk      FK      EXISTS, VALIDATED  -- untouched by this migration
--   3. context.uiw_source_context_revision.uiw_source_context_scope_key UNIQUE EXISTS, VALIDATED -- untouched by this migration
--   4. context.source_version.source_version_source_context_scope_fk  FK      EXISTS, NOT VALID  -- VALIDATEd below
--   5. context.uiw_source_context_revision.uiw_source_context_matter_fk FK    EXISTS, NOT VALID  -- VALIDATEd below
--   6. context.uiw_source_context_revision.uiw_source_context_court_case_scope_fk FK EXISTS, NOT VALID -- VALIDATEd below
--   7. context.source_version.source_version_matter_fk                FK      MISSING ENTIRELY   -- ADDed NOT VALID (targeting registry.matter, not analysis.matter), then VALIDATEd below
--   8. context.source_version.source_version_source_context_scope_check CHECK MISSING ENTIRELY   -- ADDed NOT VALID (text unchanged from 0054 -- no schema-qualified reference), then VALIDATEd below
--
-- #4-#6 already live-target registry.matter / registry.court_case (the
-- undocumented reconciliation re-created them post-move; only #7 and #8 were
-- dropped and never re-added). #7's shape is otherwise identical to 0054's
-- original DDL, retargeted analysis.matter -> registry.matter. #8's text is
-- unqualified (only references context.source_version's own columns) so it
-- is byte-identical to 0054's original. Both tables are EMPTY live (0 rows
-- each, verified 2026-09-02) so every VALIDATE below is instantaneous and
-- cannot fail on data.
--
-- OWNERSHIP: context.source_version and context.uiw_source_context_revision
-- are live-owned by the bootstrap superuser, not platform_admin, despite the
-- context schema itself being platform_admin-owned -- the same drift 0066
-- found and reported for analysis/evidence/ops (0066 §"OWNERSHIP NOTE").
-- ALTER TABLE ADD CONSTRAINT / VALIDATE CONSTRAINT require table ownership
-- (or superuser); this migration therefore runs those statements without
-- SET LOCAL ROLE platform_admin, matching 0066's ownership-aware convention
-- -- switching to platform_admin here would fail closed on tables it does
-- not own. The preflight below asserts the applying session actually has
-- that ownership (or superuser) instead of failing opaquely mid-DDL.

BEGIN;

DO $preflight$
DECLARE
    v_source_version_owner   TEXT;
    v_uiw_scope_owner        TEXT;
    v_is_super               BOOLEAN;
BEGIN
    IF current_database() <> 'platform' THEN
        RAISE EXCEPTION 'migration 0067 may run only in database platform, not %', current_database();
    END IF;
    IF to_regclass('context.source_version') IS NULL
       OR to_regclass('context.uiw_source_context_revision') IS NULL THEN
        RAISE EXCEPTION 'migration 0067 requires context.source_version and context.uiw_source_context_revision (0036/0053)';
    END IF;
    IF to_regclass('registry.matter') IS NULL OR to_regclass('registry.court_case') IS NULL THEN
        RAISE EXCEPTION 'migration 0067 requires registry.matter and registry.court_case (0062 registry split)';
    END IF;
    IF to_regclass('analysis.matter') IS NOT NULL OR to_regclass('analysis.court_case') IS NOT NULL THEN
        RAISE EXCEPTION 'migration 0067 refuses to run while analysis.matter/analysis.court_case still exist -- retarget is ambiguous while both identities are live';
    END IF;

    SELECT pg_get_userbyid(relowner) INTO v_source_version_owner
      FROM pg_class WHERE oid = 'context.source_version'::regclass;
    SELECT pg_get_userbyid(relowner) INTO v_uiw_scope_owner
      FROM pg_class WHERE oid = 'context.uiw_source_context_revision'::regclass;
    SELECT rolsuper INTO v_is_super FROM pg_roles WHERE rolname = current_user;

    IF NOT COALESCE(v_is_super, false) AND v_source_version_owner <> current_user THEN
        RAISE EXCEPTION 'migration 0067 requires ownership of (or superuser over) context.source_version; current_user=% owner=%',
            current_user, v_source_version_owner;
    END IF;
    IF NOT COALESCE(v_is_super, false) AND v_uiw_scope_owner <> current_user THEN
        RAISE EXCEPTION 'migration 0067 requires ownership of (or superuser over) context.uiw_source_context_revision; current_user=% owner=%',
            current_user, v_uiw_scope_owner;
    END IF;
END
$preflight$;

-- ---------------------------------------------------------------------------
-- #7 source_version_matter_fk -- missing entirely. Same shape as 0054's
-- original DDL, retargeted analysis.matter -> registry.matter.
-- ---------------------------------------------------------------------------
DO $add_matter_fk$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'source_version_matter_fk'
          AND conrelid = 'context.source_version'::regclass
    ) THEN
        ALTER TABLE context.source_version
            ADD CONSTRAINT source_version_matter_fk
            FOREIGN KEY (matter_id) REFERENCES registry.matter(id) ON DELETE RESTRICT NOT VALID;
    END IF;
END
$add_matter_fk$;

-- ---------------------------------------------------------------------------
-- #8 source_version_source_context_scope_check -- missing entirely. Text is
-- unchanged from 0054 (unqualified, no analysis.*/registry.* reference).
-- ---------------------------------------------------------------------------
DO $add_scope_check$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'source_version_source_context_scope_check'
          AND conrelid = 'context.source_version'::regclass
    ) THEN
        ALTER TABLE context.source_version
            ADD CONSTRAINT source_version_source_context_scope_check
            CHECK (source_context_ref IS NULL OR (matter_id IS NOT NULL AND court_case_id IS NOT NULL)) NOT VALID;
    END IF;
END
$add_scope_check$;

-- ---------------------------------------------------------------------------
-- VALIDATE the 5 constraints that are (or, after the two ADDs above, now
-- are) NOT VALID: the 3 pre-existing plus the 2 just added. VALIDATE
-- CONSTRAINT is a documented no-op when a constraint is already valid, so
-- this whole migration is safe to re-run.
-- ---------------------------------------------------------------------------
ALTER TABLE context.source_version
    VALIDATE CONSTRAINT source_version_matter_fk;
ALTER TABLE context.source_version
    VALIDATE CONSTRAINT source_version_source_context_scope_check;
ALTER TABLE context.source_version
    VALIDATE CONSTRAINT source_version_source_context_scope_fk;
ALTER TABLE context.uiw_source_context_revision
    VALIDATE CONSTRAINT uiw_source_context_matter_fk;
ALTER TABLE context.uiw_source_context_revision
    VALIDATE CONSTRAINT uiw_source_context_court_case_scope_fk;

-- ---------------------------------------------------------------------------
-- verify: re-derive uiw_schema_probe.go's own constraintsExact boolean
-- (byte-identical logic to modules/engine/postgres/uiw_schema_probe.go's
-- query, lines ~81-109) and require it to be true before commit.
-- ---------------------------------------------------------------------------
DO $verify$
DECLARE v_constraints_exact BOOLEAN;
BEGIN
    SELECT (NOT EXISTS (
              SELECT 1 FROM (VALUES
                ('context.source_version','source_version_matter_fk','registry.matter',ARRAY['matter_id'],ARRAY['id']),
                ('context.source_version','source_version_court_case_scope_fk','registry.court_case',ARRAY['court_case_id','matter_id'],ARRAY['id','matter_id']),
                ('context.source_version','source_version_source_context_scope_fk','context.uiw_source_context_revision',ARRAY['source_context_ref','matter_id','court_case_id'],ARRAY['source_context_ref','matter_id','court_case_id']),
                ('context.uiw_source_context_revision','uiw_source_context_matter_fk','registry.matter',ARRAY['matter_id'],ARRAY['id']),
                ('context.uiw_source_context_revision','uiw_source_context_court_case_scope_fk','registry.court_case',ARRAY['court_case_id','matter_id'],ARRAY['id','matter_id'])
              ) AS required(relation_name,constraint_name,referenced_name,columns,referenced_columns)
              WHERE NOT EXISTS (
                SELECT 1 FROM pg_constraint c
                WHERE c.conrelid=required.relation_name::regclass
                  AND c.confrelid=required.referenced_name::regclass AND c.contype='f'
                  AND c.conname=required.constraint_name AND c.convalidated AND c.confdeltype='r'
                  AND ARRAY(SELECT a.attname::text FROM unnest(c.conkey) WITH ORDINALITY k(attnum,ord)
                            JOIN pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=k.attnum ORDER BY k.ord)=required.columns
                  AND ARRAY(SELECT a.attname::text FROM unnest(c.confkey) WITH ORDINALITY k(attnum,ord)
                            JOIN pg_attribute a ON a.attrelid=c.confrelid AND a.attnum=k.attnum ORDER BY k.ord)=required.referenced_columns)))
            AND EXISTS (SELECT 1 FROM pg_constraint c
              WHERE c.conrelid='context.source_version'::regclass
                AND c.conname='source_version_matter_case_pair_check' AND c.contype='c' AND c.convalidated)
            AND EXISTS (SELECT 1 FROM pg_constraint c
              WHERE c.conrelid='context.source_version'::regclass
                AND c.conname='source_version_source_context_scope_check' AND c.contype='c' AND c.convalidated)
            AND EXISTS (SELECT 1 FROM pg_constraint c
              WHERE c.conrelid='context.uiw_source_context_revision'::regclass
                AND c.conname='uiw_source_context_scope_key' AND c.contype='u' AND c.convalidated
                AND ARRAY(SELECT a.attname::text FROM unnest(c.conkey) WITH ORDINALITY k(attnum,ord)
                          JOIN pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=k.attnum ORDER BY k.ord)
                      =ARRAY['source_context_ref','matter_id','court_case_id'])
    INTO v_constraints_exact;

    IF NOT v_constraints_exact THEN
        RAISE EXCEPTION 'migration 0067 did not leave the UIW scope constraints in the exact shape uiw_schema_probe.go requires';
    END IF;
END
$verify$;

COMMIT;
