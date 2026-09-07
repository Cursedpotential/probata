-- 0057_identity_home_reference.sql
--
-- Byline: Claude · Opus 5 · 2026-08-31, owner-ruled.
--
-- Owner, verbatim: "the identity tables and stuff like that both can be
-- cumulative and atomic and just be referential... we could keep it from the
-- test ingest and stuff like that as we come across things... The more
-- completed those are from the very beginning, the less work there is to do
-- down the road."
--
-- IDENTITY GETS A HOME: reference. Its charter was already "not derived from
-- anything, not a conclusion" — identity fits without rewording. This widens
-- the charter from "taxonomy and config" to "taxonomy, config, and IDENTITY:
-- cumulative, atomic registries of real-world things (devices, people,
-- places, entities, cases) that every layer points at and no purge touches."
--
-- Why the move matters (the FK topology finding, 2026-08-31):
--   * ALL 7 backwards evidence->working FKs land on working.device.
--   * The working<->analysis cycle runs through analysis.court_case/matter.
--   * The owner's own purge ruling ("empty everything except the reference
--     data") would have PRESERVED identity had it lived here. It didn't, so
--     a purge of working would delete the registry of phones the evidence
--     came from. Wrong drawer, one-line fix per table.
--
-- Identity discovered during TEST ingests accumulates here and survives the
-- test data's deletion. The more complete these registries are from the very
-- beginning, the less work later.
--
-- SET SCHEMA moves the table with all its FKs, indexes and data intact —
-- inbound references follow automatically. Same mechanism as 0014.
-- NO compatibility views, NO aliases (0014 rule): every code caller moves in
-- the same change.
--
-- timeline_event is deliberately NOT moved: it is arguably a conclusion about
-- events rather than pure identity. Flagged for a separate ruling.
-- entity_mention is NOT moved: a mention is an occurrence in derived text —
-- that is working-layer material. entity_merge_event stays with entity
-- history follow-ups for the same reason pending review.

ALTER TABLE IF EXISTS working.device        SET SCHEMA reference;
ALTER TABLE IF EXISTS working.person        SET SCHEMA reference;
ALTER TABLE IF EXISTS working.entity        SET SCHEMA reference;
ALTER TABLE IF EXISTS working.entity_alias  SET SCHEMA reference;
ALTER TABLE IF EXISTS working.location      SET SCHEMA reference;
ALTER TABLE IF EXISTS working.id_xref       SET SCHEMA reference;
ALTER TABLE IF EXISTS analysis.court_case   SET SCHEMA reference;
ALTER TABLE IF EXISTS analysis.matter       SET SCHEMA reference;

COMMENT ON SCHEMA reference IS
  'Hand-curated taxonomy/config AND identity registries (devices, people, places, entities, cases). Cumulative and atomic: rows accumulate from the very beginning, including from test ingests, and survive every purge of working/analysis. Not derived, not conclusions. Owner-ruled 2026-08-31 (D-115).';

COMMENT ON TABLE reference.device IS
  'Identity registry: physical devices evidence was acquired from. Moved from working (0057) — a purge of working must never delete the registry of phones the evidence came from.';
COMMENT ON TABLE reference.court_case IS
  'Identity registry: legal cases. Moved from analysis (0057) — a case is the coordinate system analysis happens IN, not a conclusion produced by it.';
COMMENT ON TABLE reference.matter IS
  'Identity registry: matters. Moved from analysis (0057), same reasoning as court_case.';
