-- seed_dev_case_registry.sql — DEV sentinel case-registry identity + import receipt (D-125, D-126)
-- Byline: Claude Code · Fable 5.1 · 2026-09-07. Lifted verbatim from the retired migration
-- sql/_stale/migrations-retired-20260907/0069_dev_case_registry_identity.sql (D-152/D-153: the
-- snapshot is the database; this seed is part of every rebuild while PLATFORM_DEV_AUTH_BYPASS is on).
-- The Go admission probe (modules/engine/postgres/proffer_schema_probe.go devReceipt* constants)
-- requires EXACTLY these literals; change both files together. Idempotent (ON CONFLICT / NOT EXISTS).
-- Apply: docker exec -i <probata-db> psql -U ai -d platform -v ON_ERROR_STOP=1 < this file

BEGIN;
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
COMMIT;
