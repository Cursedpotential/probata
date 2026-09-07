-- seed_dev_case_registry.sql — DEV sentinel case-registry identity + import receipt (D-125, D-126)
-- Byline: Claude Code · Fable 5.1 · 2026-09-07 (corrects the first cut, which replayed bare INSERTs
-- that referenced the retired migration's PL/pgSQL variables and could not run).
--
-- Under D-152/D-153 the snapshot is the database. The rebuild from
-- sql/bootstrap/schema_snapshot_20260907.sql keeps the function
-- registry.reseed_dev_case_identity() (defined by the retired
-- sql/_stale/migrations-retired-20260907/0069_dev_case_registry_identity.sql and captured
-- in the snapshot) but NOT the rows it writes. The proffer admission probe
-- (modules/engine/postgres/proffer_schema_probe.go, devReceipt* constants) refuses to start
-- the starter/worker until exactly those rows exist while PLATFORM_DEV_AUTH_BYPASS is on.
-- Run this after every rebuild. Idempotent (the function only ever touches placeholder rows and
-- refuses loudly if a real matter/court_case row is present — D-117/D-126).
--
-- Apply (as the bootstrap superuser):
--   docker exec -i <probata-db> psql -U ai -d platform -v ON_ERROR_STOP=1 < sql/bootstrap/seed_dev_case_registry.sql
-- Live application 2026-09-07 ~15:35 EDT: run once against ovh-files probata-db; receipt row present afterwards.

BEGIN;
SELECT registry.reseed_dev_case_identity();
COMMIT;

-- Post-check (expected: one row, deadbeef… / cafebabe… / sql/0069_dev_case_registry_identity.sql / dev-mode-placeholder / 2026-09-02)
SELECT matter_id, court_case_id, source_migration_uri, approved_by, approved_on
  FROM analysis.case_registry_import_receipt;
