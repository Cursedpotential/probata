-- 0069_dev_case_registry_identity.sql -- force a fixed, obviously-synthetic
-- DEV case-registry identity pre-launch (D-126), self-healing across every
-- ops.reset_test_data('RESET') purge/reset/re-ingest cycle (D-118).
--
-- Byline: Claude Code · Sonnet 5 · 2026-09-02 (BUILD LANE S3).
--
-- OWNER RULING THIS ENCODES (D-126, verbatim + 2026-09-02 refinement):
-- "Until we go live, force an ID of devmode. Put it behind the dev feature
-- flag. And then once we go live, it gets a new UUID." ... "That way while
-- we're testing and ingesting and rewriting and erasing and purging and
-- migrating, it's fucking blank." Refined same day: "The only thing the
-- feature flag should really do is bypass the UUID type requirement. And
-- allow for the UUID to persist. And add a fake one instead of an auto
-- created one, but everything else is still going to look for it, still
-- going to reference it. But it's going to be referencing a fake one that's
-- not an actual UUID."
--
-- CONTEXT: registry.matter/registry.court_case currently hold
-- 01a055b0-c172-.../01a055b0-c173-... (an accidental migration-0030 replay,
-- 2026-08-31, verification_state='proposed', zero referencing rows),
-- while modules/engine/postgres/uiw_schema_probe.go pins a DIFFERENT
-- 2026-08-23 identity (01a03136-...) that was never actually created live.
-- D-126: neither accidental UUID becomes canon -- both are meaningless
-- serial numbers on placeholder rows with zero referencing data.
--
-- CHOSEN SENTINEL IDENTITY -- why these exact values:
--   registry.matter.id / registry.court_case.id are Postgres `uuid`-typed
--   columns with live FK referrers (context.source_version,
--   context.uiw_source_context_revision, analysis.matter_knowledge_partition,
--   analysis.case_registry_import_receipt, plus working.first_party_/
--   third_party_context_thread's own matter_id/court_case_id columns) --
--   a non-UUID-shaped literal ("...dev1" etc, 'v' is not valid hex) cannot
--   be stored without a destabilizing type change across every one of them.
--   So the sentinel is UUID-SHAPED, built entirely from classic "obviously
--   fake" programmer hex magic numbers (every character is valid hex,
--   0-9/a-f): DEADBEEF for the matter, CAFEBABE for the court case.
--     matter:     deadbeef-dead-beef-dead-beefdeadbeef
--     court_case: cafebabe-cafe-babe-cafe-babecafebabe
--   Neither uuidv7() nor any real UUID generator ever emits either
--   pattern, and both are visually unmistakable next to a real
--   time-ordered uuidv7 id (which always starts with a timestamp prefix,
--   e.g. 01a0...). modules/engine/postgres/uiw_schema_probe.go's
--   devMatterID/devCourtCaseID constants must stay byte-identical to these
--   two literals -- the two files are changed together.
--
-- THE DEV RECEIPT IS WRITTEN HONESTLY. D-126 forbids ever recording
-- approved_by='owner' for an approval the owner did not give -- that is
-- exactly the fabricated-record class of defect
-- docs/CLAIMED_COMPLETE_LIKELY_LIES/ exists to catch. This migration writes
-- approved_by='dev-mode-placeholder' (naming the MECHANISM, not a person)
-- and every hash/commit field is a fixed hex "magic number" placeholder
-- (never derived from a real payload) -- DEADBEEF/CAFEBABE/DEADFACE/
-- BAADF00D, matching the identity's own DEADBEEF/CAFEBABE theme so the
-- whole row reads as synthetic at a glance. uiw_schema_probe.go's
-- devReceipt* constants must stay byte-identical to the literals below.
--
-- LIVE-VERIFIED BEFORE WRITING THIS MIGRATION (2026-09-02, as superuser,
-- database platform, read-only): analysis.case_registry_import_receipt
-- carries ZERO triggers today -- the "immutable" BEFORE UPDATE/DELETE/
-- TRUNCATE guard triggers sql/0054's own text defines were among the ~253
-- guard statements D-110 records as DELIBERATELY skipped in the 2026-08-30
-- rebuild ("Nothing is immutable ... Do not ask about this again"). This
-- migration does NOT recreate those triggers -- that replay is explicitly
-- gated on a different precondition per D-110 and is out of this build
-- lane's scope. Consequence for THIS migration: TRUNCATE TABLE analysis....
-- (what ops.reset_test_data issues) succeeds cleanly against
-- case_registry_import_receipt today; there is no immutability-vs-reset
-- conflict to design around.
--
-- RESET-SURVIVAL FINDING (item 2 of this build lane): registry.matter and
-- registry.court_case are UNAFFECTED by ops.reset_test_data('RESET') --
-- confirmed by reading sql/0060: its TRUNCATE loop only ever touches
-- schemas raw/evidence/working/context/timeline/analysis, and 0062 already
-- moved matter/court_case OUT of that blast radius (reference -> registry,
-- neither name appears in the loop). Re-verified live in this build lane's
-- validation transaction (apply 0069, run ops.reset_test_data('RESET'),
-- confirm registry.matter/court_case rows unchanged). NO DEFECT in registry
-- survival -- D-115/D-117's "identity survives purges" ruling holds exactly
-- as designed. The real gap: analysis.matter_knowledge_partition and
-- analysis.case_registry_import_receipt DO live in the truncated `analysis`
-- schema (by design -- 0060 categorizes analysis.* as disposable "test
-- conclusions") and were NOT being re-seeded automatically, which would
-- leave every reset in a broken state (probe failing) until someone
-- remembered to re-run this file by hand. FIXED below: this migration
-- redefines ops.reset_test_data to call the same idempotent seed function
-- this migration itself calls, so the DEV identity is self-healing across
-- every future reset with no manual step.
--
-- SAFETY: the seed function below refuses (RAISE WARNING, no-op) the
-- instant it finds a registry.matter/court_case row it did not itself
-- write -- i.e. the moment real go-live identity exists, this migration's
-- logic (including the auto-call from every future reset) becomes
-- permanently inert rather than clobbering real case identity. See
-- docs/runbooks/go-live-case-registry.md for why a reset run at go-live
-- will still visibly re-seed the DEV sentinel one more time (expected,
-- harmless, and immediately superseded by the go-live identity-creation
-- step) and must never be treated as a reason to skip that step or to
-- re-run it afterward once real identity exists.
--
-- OWNERSHIP DRIFT (live-verified 2026-09-02, additional to sql/0066's
-- OWNERSHIP NOTE, which covered evidence/ops/raw.raw_csv but not this):
-- the `analysis` schema itself, and specifically table
-- analysis.case_registry_import_receipt, are live-owned by the bootstrap
-- superuser -- NOT platform_admin -- despite sql/0054's own DDL running
-- `CREATE SCHEMA IF NOT EXISTS analysis AUTHORIZATION platform_admin`: the
-- schema already existed (created earlier by other analysis.* tables'
-- migrations) so that AUTHORIZATION clause was a silent no-op, and 0054's
-- explicit `ALTER TABLE ... OWNER TO platform_admin` list covers
-- analysis.matter, analysis.court_case and analysis.matter_knowledge_
-- partition but omits analysis.case_registry_import_receipt. Consequence:
-- platform_admin -- the ONLY role granted EXECUTE on ops.reset_test_data,
-- and therefore the role that actually runs this migration's self-heal
-- call in production -- could not previously reach either object (proven
-- live: `SET LOCAL ROLE platform_admin` then touching
-- analysis.matter_knowledge_partition raised `permission denied for
-- schema analysis`, since owning a table does not imply USAGE on its
-- schema). Repaired below with the same narrow, additive, ownership-aware
-- pattern sql/0066 and sql/0067 already established for this exact class
-- of drift: schema USAGE plus exactly the two verbs this migration's own
-- writer needs on the one table it does not already own -- nothing wider,
-- and no other analysis.* table's ownership or grants are touched.

BEGIN;

DO $preflight$
BEGIN
    IF current_database() <> 'platform' THEN
        RAISE EXCEPTION 'migration 0069 may run only in database platform, not %', current_database();
    END IF;
    IF to_regclass('registry.matter') IS NULL OR to_regclass('registry.court_case') IS NULL THEN
        RAISE EXCEPTION 'migration 0069 requires registry.matter/registry.court_case (0054, 0057, 0062)';
    END IF;
    IF to_regclass('analysis.matter_knowledge_partition') IS NULL
       OR to_regclass('analysis.case_registry_import_receipt') IS NULL THEN
        RAISE EXCEPTION 'migration 0069 requires analysis.matter_knowledge_partition/case_registry_import_receipt (0054)';
    END IF;
    IF to_regprocedure('ops.reset_test_data(text)') IS NULL THEN
        RAISE EXCEPTION 'migration 0069 requires ops.reset_test_data (0060)';
    END IF;
    -- Friendly early failure (natural FK RESTRICT would catch this
    -- regardless): refuse if any live referrer already points at a
    -- registry.matter/court_case row that is about to be replaced.
    IF (to_regclass('context.source_version') IS NOT NULL AND EXISTS (
          SELECT 1 FROM context.source_version
           WHERE matter_id IS NOT NULL
             AND matter_id <> 'deadbeef-dead-beef-dead-beefdeadbeef'::uuid))
       OR (to_regclass('context.uiw_source_context_revision') IS NOT NULL AND EXISTS (
          SELECT 1 FROM context.uiw_source_context_revision
           WHERE matter_id <> 'deadbeef-dead-beef-dead-beefdeadbeef'::uuid))
       OR (to_regclass('working.first_party_context_thread') IS NOT NULL AND EXISTS (
          SELECT 1 FROM working.first_party_context_thread
           WHERE matter_id <> 'deadbeef-dead-beef-dead-beefdeadbeef'::uuid))
       OR (to_regclass('working.third_party_context_thread') IS NOT NULL AND EXISTS (
          SELECT 1 FROM working.third_party_context_thread
           WHERE matter_id <> 'deadbeef-dead-beef-dead-beefdeadbeef'::uuid))
       OR (to_regclass('evidence.evidence_item') IS NOT NULL AND EXISTS (
          SELECT 1 FROM evidence.evidence_item
           WHERE matter_id IS NOT NULL
             AND matter_id <> 'deadbeef-dead-beef-dead-beefdeadbeef'::uuid))
       OR (to_regclass('analysis.knowledge_evidence_promotion') IS NOT NULL AND EXISTS (
          SELECT 1 FROM analysis.knowledge_evidence_promotion
           WHERE matter_id IS NOT NULL
             AND matter_id <> 'deadbeef-dead-beef-dead-beefdeadbeef'::uuid)) THEN
        RAISE EXCEPTION 'migration 0069 refuses: a live row already references the old case-registry identity -- this is no longer a zero-referrer pre-launch database';
    END IF;
END
$preflight$;

-- ---------------------------------------------------------------------------
-- Ownership-drift repair (see header note above): analysis schema and
-- analysis.case_registry_import_receipt are owned by the bootstrap
-- superuser, not platform_admin, so these two grants run WITHOUT a role
-- switch -- matching sql/0066's ownership-aware convention exactly.
-- analysis.matter_knowledge_partition already needs no additional grant
-- (platform_admin owns it outright, 0054); it only needed schema USAGE,
-- granted here.
-- ---------------------------------------------------------------------------
GRANT USAGE ON SCHEMA analysis TO platform_admin;
GRANT SELECT, INSERT ON TABLE analysis.case_registry_import_receipt TO platform_admin;

SET LOCAL ROLE platform_admin;

CREATE OR REPLACE FUNCTION registry.reseed_dev_case_identity()
RETURNS VOID LANGUAGE plpgsql SET search_path = pg_catalog AS $fn$
DECLARE
  v_dev_matter CONSTANT UUID := 'deadbeef-dead-beef-dead-beefdeadbeef';
  v_dev_court_case CONSTANT UUID := 'cafebabe-cafe-babe-cafe-babecafebabe';
  v_placeholder_writers CONSTANT TEXT[] := ARRAY['migration-0030','migration-0069-dev-seed'];
  v_foreign_matter_count INT;
  v_foreign_case_count INT;
BEGIN
  -- Safety backstop (D-117: "nothing about [identity] is ever
  -- auto-anything"; D-126: "no fabricated owner-approval receipt is ever
  -- written"). Only ever touch registry.matter/court_case here if every row
  -- currently present is itself placeholder data (the original
  -- migration-0030 replay, or a prior run of this same seed). The moment a
  -- real (non-placeholder) row is found, do nothing but warn loudly -- this
  -- function must never be able to clobber real case identity, including
  -- when it runs automatically from ops.reset_test_data post-go-live.
  SELECT count(*) INTO v_foreign_matter_count FROM registry.matter
   WHERE created_by <> ALL(v_placeholder_writers);
  SELECT count(*) INTO v_foreign_case_count FROM registry.court_case
   WHERE created_by <> ALL(v_placeholder_writers);
  IF v_foreign_matter_count > 0 OR v_foreign_case_count > 0 THEN
    RAISE WARNING 'registry.reseed_dev_case_identity: % non-placeholder matter row(s) and % non-placeholder court_case row(s) exist -- refusing to touch case-registry identity; this database is no longer pre-launch',
      v_foreign_matter_count, v_foreign_case_count;
    RETURN;
  END IF;

  DELETE FROM registry.court_case WHERE id <> v_dev_court_case;
  DELETE FROM registry.matter WHERE id <> v_dev_matter;

  INSERT INTO registry.matter (id, title, status, created_by, verification_state)
  VALUES (v_dev_matter, 'DEV — placeholder matter (pre-launch, disposable)', 'active',
          'migration-0069-dev-seed', 'proposed')
  ON CONFLICT (id) DO UPDATE SET
    title = EXCLUDED.title, status = EXCLUDED.status,
    created_by = EXCLUDED.created_by, verification_state = EXCLUDED.verification_state;

  INSERT INTO registry.court_case (id, matter_id, caption, status, is_primary, created_by, verification_state)
  VALUES (v_dev_court_case, v_dev_matter, 'DEV — placeholder proceeding (pre-launch, disposable)',
          'pre_filing', true, 'migration-0069-dev-seed', 'proposed')
  ON CONFLICT (id) DO UPDATE SET
    matter_id = EXCLUDED.matter_id, caption = EXCLUDED.caption, status = EXCLUDED.status,
    is_primary = EXCLUDED.is_primary, created_by = EXCLUDED.created_by,
    verification_state = EXCLUDED.verification_state;

  INSERT INTO analysis.matter_knowledge_partition (partition_key, matter_id, default_court_case_id, created_by)
  VALUES ('primary', v_dev_matter, v_dev_court_case, 'migration-0069-dev-seed')
  ON CONFLICT (partition_key) DO UPDATE SET
    matter_id = EXCLUDED.matter_id, default_court_case_id = EXCLUDED.default_court_case_id,
    created_by = EXCLUDED.created_by;

  -- No natural upsert target (id is a surrogate uuidv7()); insert only if a
  -- matching dev receipt is not already present so re-running this after a
  -- no-op reset (nothing was truncated) never raises a duplicate/unique
  -- error, and a fresh insert after a real reset (old row truncated away)
  -- always lands with the identical content values.
  INSERT INTO analysis.case_registry_import_receipt (
    manifest_sha256, source_migration_uri, source_migration_sha256, source_git_commit,
    payload_schema_version, payload_byte_length, canonical_payload_sha256, api_payload_sha256,
    source_observed_at, matter_id, court_case_id, partition_key, approved_by, approved_on, imported_by
  )
  SELECT
    decode('baadf00dbaadf00dbaadf00dbaadf00dbaadf00dbaadf00dbaadf00dbaadf00d', 'hex'),
    'sql/0069_dev_case_registry_identity.sql',
    decode('deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef', 'hex'),
    'deadbeefdeadbeefdeadbeefdeadbeefdeadbeef',
    'dev-placeholder-v1',
    1,
    decode('cafebabecafebabecafebabecafebabecafebabecafebabecafebabecafebabe', 'hex'),
    decode('deadfacedeadfacedeadfacedeadfacedeadfacedeadfacedeadfacedeadface', 'hex'),
    TIMESTAMPTZ '2026-09-02 00:00:00+00',
    v_dev_matter, v_dev_court_case, 'primary', 'dev-mode-placeholder', DATE '2026-09-02',
    'migration-0069-dev-seed'
  WHERE NOT EXISTS (
    SELECT 1 FROM analysis.case_registry_import_receipt
     WHERE matter_id = v_dev_matter AND court_case_id = v_dev_court_case
       AND approved_by = 'dev-mode-placeholder'
  );
END
$fn$;

ALTER FUNCTION registry.reseed_dev_case_identity() OWNER TO platform_admin;
REVOKE ALL ON FUNCTION registry.reseed_dev_case_identity() FROM PUBLIC;
COMMENT ON FUNCTION registry.reseed_dev_case_identity() IS
  'D-126: forces the fixed DEV sentinel Matter/CourtCase identity (deadbeef.../cafebabe...) plus its knowledge partition and an honestly-labeled dev receipt (approved_by=''dev-mode-placeholder'', never ''owner''). Idempotent -- refuses (WARNING, no-op) the instant any non-placeholder matter/court_case row exists. Invoked directly by sql/0069 and automatically by ops.reset_test_data so identity self-heals across every purge/reset/re-ingest cycle with no manual re-run.';

SELECT registry.reseed_dev_case_identity();

RESET ROLE;

-- Self-healing reset (item 2 of this build lane): identical to sql/0060's
-- definition except for one added line at the end. ops.reset_test_data
-- truncates analysis.* (which holds matter_knowledge_partition and
-- case_registry_import_receipt) as ordinary test data -- correct, since
-- neither is real identity -- but nothing was restoring them afterward.
-- registry.matter/court_case were never at risk (0062 already moved them
-- out of the truncation loop's schema list; unchanged here).
CREATE OR REPLACE FUNCTION ops.reset_test_data(p_confirm TEXT)
RETURNS TABLE (truncated_schema TEXT, tables_truncated INTEGER)
LANGUAGE plpgsql AS $fn$
DECLARE
  v_schema TEXT;
  v_list   TEXT;
  v_count  INTEGER;
BEGIN
  IF p_confirm IS DISTINCT FROM 'RESET' THEN
    RAISE EXCEPTION 'refusing: call ops.reset_test_data(''RESET'') to confirm a full test-data reset';
  END IF;

  FOREACH v_schema IN ARRAY ARRAY['raw','evidence','working','context','timeline','analysis'] LOOP
    SELECT string_agg(format('%I.%I', nn.nspname, c.relname), ', '), count(*)::INTEGER
      INTO v_list, v_count
      FROM pg_class c JOIN pg_namespace nn ON nn.oid = c.relnamespace
     WHERE c.relkind = 'r' AND nn.nspname = v_schema;
    IF v_list IS NOT NULL THEN
      EXECUTE 'TRUNCATE TABLE ' || v_list || ' RESTART IDENTITY CASCADE';
    END IF;
    truncated_schema := v_schema; tables_truncated := coalesce(v_count,0);
    RETURN NEXT;
  END LOOP;

  -- canon: test traffic resets, rulings survive
  TRUNCATE TABLE canon.recompute_queue, canon.change_application,
                 canon.change_decision, canon.change_proposal
    RESTART IDENTITY CASCADE;
  truncated_schema := 'canon (proposals/decisions/applications/queue only)';
  tables_truncated := 4;
  RETURN NEXT;

  -- reset per-table generations: a fresh test run starts at generation 0
  UPDATE canon.canonical_table SET current_generation = 0;

  -- D-126 self-heal: analysis.matter_knowledge_partition and
  -- analysis.case_registry_import_receipt were just truncated above as
  -- ordinary test data. Restore the DEV sentinel identity's partition and
  -- honest dev receipt immediately so the UIW admission probe (run under
  -- PLATFORM_DEV_AUTH_BYPASS pre-launch) keeps passing after every reset
  -- with no manual step. registry.matter/court_case themselves were never
  -- truncated (outside this function's schema list); this call is a no-op
  -- there unless they were separately removed. This call is itself
  -- fail-safe: it refuses (WARNING, does nothing) the moment a real
  -- (non-placeholder) matter/court_case row exists, so it can never
  -- resurrect the DEV identity over real go-live data -- see
  -- registry.reseed_dev_case_identity()'s own header comment and
  -- docs/runbooks/go-live-case-registry.md.
  PERFORM registry.reseed_dev_case_identity();
END $fn$;

COMMENT ON FUNCTION ops.reset_test_data(TEXT) IS
  'THE reset button (D-118). Truncates test data in raw/evidence/working/context/timeline/analysis and canon traffic; preserves reference (identity is cumulative, incl. test-ingest discoveries), canon rulings, ops ledgers, public, ai. Call with ''RESET'' to confirm. This is the ONLY sanctioned purge. D-126: also self-heals the pre-launch DEV case-registry sentinel identity (analysis.matter_knowledge_partition + the honest dev receipt) via registry.reseed_dev_case_identity(), which is itself a safe no-op once real go-live identity exists.';

GRANT EXECUTE ON FUNCTION ops.reset_test_data(TEXT) TO platform_admin;

DO $verify$
DECLARE
  v_dev_matter CONSTANT UUID := 'deadbeef-dead-beef-dead-beefdeadbeef';
  v_dev_court_case CONSTANT UUID := 'cafebabe-cafe-babe-cafe-babecafebabe';
BEGIN
  IF (SELECT count(*) FROM registry.matter) <> 1
     OR NOT EXISTS (
       SELECT 1 FROM registry.matter
        WHERE id = v_dev_matter
          AND title = 'DEV — placeholder matter (pre-launch, disposable)'
          AND status = 'active' AND verification_state = 'proposed') THEN
    RAISE EXCEPTION 'migration 0069 failed to force the exact DEV sentinel matter identity';
  END IF;

  IF (SELECT count(*) FROM registry.court_case) <> 1
     OR NOT EXISTS (
       SELECT 1 FROM registry.court_case
        WHERE id = v_dev_court_case AND matter_id = v_dev_matter
          AND caption = 'DEV — placeholder proceeding (pre-launch, disposable)'
          AND is_primary AND verification_state = 'proposed') THEN
    RAISE EXCEPTION 'migration 0069 failed to force the exact DEV sentinel court_case identity';
  END IF;

  IF (SELECT count(*) FROM analysis.matter_knowledge_partition) <> 1
     OR NOT EXISTS (
       SELECT 1 FROM analysis.matter_knowledge_partition
        WHERE partition_key = 'primary' AND matter_id = v_dev_matter
          AND default_court_case_id = v_dev_court_case) THEN
    RAISE EXCEPTION 'migration 0069 failed to seed analysis.matter_knowledge_partition(''primary'')';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM analysis.case_registry_import_receipt
     WHERE matter_id = v_dev_matter AND court_case_id = v_dev_court_case
       AND partition_key = 'primary'
       AND source_migration_uri = 'sql/0069_dev_case_registry_identity.sql'
       AND approved_by = 'dev-mode-placeholder' AND approved_on = DATE '2026-09-02'
       AND payload_byte_length = 1) THEN
    RAISE EXCEPTION 'migration 0069 failed to seed the honest dev case_registry_import_receipt';
  END IF;
  IF EXISTS (SELECT 1 FROM analysis.case_registry_import_receipt WHERE approved_by = 'owner') THEN
    RAISE EXCEPTION 'migration 0069 refuses: an owner-approved receipt already exists -- this is no longer a pre-launch database, do not run this migration here';
  END IF;

  IF position('reseed_dev_case_identity' IN pg_get_functiondef('ops.reset_test_data(text)'::regprocedure)) = 0 THEN
    RAISE EXCEPTION 'migration 0069 failed to wire the self-heal reseed into ops.reset_test_data';
  END IF;

  -- Ownership-drift repair grants: exactly USAGE + SELECT/INSERT, nothing
  -- wider (mirrors sql/0066's own verify-block discipline).
  IF NOT has_schema_privilege('platform_admin', 'analysis', 'USAGE')
     OR has_schema_privilege('platform_admin', 'analysis', 'CREATE')
     OR NOT has_table_privilege('platform_admin', 'analysis.case_registry_import_receipt', 'SELECT')
     OR NOT has_table_privilege('platform_admin', 'analysis.case_registry_import_receipt', 'INSERT')
     OR has_table_privilege('platform_admin', 'analysis.case_registry_import_receipt', 'UPDATE')
     OR has_table_privilege('platform_admin', 'analysis.case_registry_import_receipt', 'DELETE') THEN
    RAISE EXCEPTION 'migration 0069 ownership-drift repair grants are not exact';
  END IF;
END
$verify$;

COMMIT;
