-- 0062_registry_split.sql
--
-- Byline: Claude · Opus 5 · 2026-08-31, owner vocabulary ruling.
--
-- Owner: "When I say a reference table, I'm just meaning something that does
-- not necessarily link to anything else and is just there to reference
-- against... like a key-value store."
--
-- That is reference's ORIGINAL charter (taxonomy, lexicons, MCL factors,
-- score bands) and identity tables are its opposite: they are the most
-- linked-TO tables in the database. The Occam collapse of "widen reference
-- vs new registry" (2026-08-31, earlier today) optimized entity count over
-- the owner's vocabulary. The owner's vocabulary wins.
--
--   registry   = the ID cards everything points at: device, person, entity,
--                aliases, location, id_xref, court_case, matter.
--                Cumulative, atomic, survives every reset (D-115, D-118).
--   reference  = standalone lookups, linked to nothing: taxonomies, factors,
--                lexicons, patterns, bands. Just there to reference against.
--
-- CANON, restated correctly (owner: "doesn't canonical mean supposed to be
-- THE point of truth?"): yes. The canon schema is the GATE, not the truth.
-- A row BECOMES canon by passing through it — owner ruling or clear-signal
-- auto-adopt. verification_state: proposed = not canon yet; confirmed = this
-- is now the truth everything references.

CREATE SCHEMA IF NOT EXISTS registry AUTHORIZATION platform_admin;
COMMENT ON SCHEMA registry IS
  'Identity: the ID-card tables everything points at (device, person, entity, location, case). Cumulative and atomic from the very beginning, including test-ingest discoveries; survives every reset. Rows become trusted canon via the canon spine (verification_state). Owner vocabulary ruling D-120: registry = linked-to identity; reference = standalone lookups.';

ALTER TABLE IF EXISTS reference.device       SET SCHEMA registry;
ALTER TABLE IF EXISTS reference.person       SET SCHEMA registry;
ALTER TABLE IF EXISTS reference.entity       SET SCHEMA registry;
ALTER TABLE IF EXISTS reference.entity_alias SET SCHEMA registry;
-- entity_mention line removed 2026-09-01 (pre-apply amendment): the table
-- lives in working, not reference, so this was a no-op — and pg_duckdb's
-- duckdb_alter_table_trigger (ddl_command_end) errors on IF-EXISTS no-ops
-- (UndefinedTable on the skipped relation). Mentions are occurrences, not
-- ID cards; working is the correct home.
ALTER TABLE IF EXISTS reference.location     SET SCHEMA registry;
ALTER TABLE IF EXISTS reference.id_xref      SET SCHEMA registry;
ALTER TABLE IF EXISTS reference.court_case   SET SCHEMA registry;
ALTER TABLE IF EXISTS reference.matter       SET SCHEMA registry;

COMMENT ON SCHEMA reference IS
  'Standalone lookups, linked to nothing — "just there to reference against": taxonomies, MCL factors, lexicons, detection patterns, score bands, key-value config. Not derived, not conclusions, not identity (identity = registry). Owner vocabulary ruling D-120.';

-- the canon boundary follows the tables
UPDATE canon.canonical_table SET table_schema = 'registry'
 WHERE table_schema = 'reference'
   AND table_name IN ('device','person','entity','entity_alias','location','court_case','matter');

GRANT USAGE ON SCHEMA registry TO platform_api, platform_worker, platform_reader;
GRANT SELECT ON ALL TABLES IN SCHEMA registry TO platform_reader, platform_api, platform_worker;
