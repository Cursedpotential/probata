-- 0061_confidence_gated_tiers.sql
--
-- Byline: Claude · Opus 5 · 2026-08-31, owner-ruled.
--
-- Owner, verbatim: "if it's super clear signal what device it's from —
-- fucking awesome. If it's this sketchy fucking signal, then it has to
-- fucking wait for approval."
--
-- Confidence decides the lane. Every identification carries a confidence
-- (the ai.confidence domain: numeric 0..1) and how it was made. Each
-- canon-governed table carries a threshold AS DATA — retunable without a
-- migration. Routing:
--
--   confidence >= auto_confirm_min_confidence  ->  auto_adopt (applied, logged, reversible)
--   below threshold, or threshold NULL         ->  the table's default tier (waits for you)
--
-- court_case / matter / evidence_item keep threshold NULL: NOTHING about
-- them is ever auto, at any confidence (D-117).

-- how sure, and based on what
ALTER TABLE reference.device   ADD COLUMN IF NOT EXISTS identification_confidence ai.confidence;
ALTER TABLE reference.device   ADD COLUMN IF NOT EXISTS identification_signal     TEXT;
ALTER TABLE reference.person   ADD COLUMN IF NOT EXISTS identification_confidence ai.confidence;
ALTER TABLE reference.person   ADD COLUMN IF NOT EXISTS identification_signal     TEXT;
ALTER TABLE reference.location ADD COLUMN IF NOT EXISTS identification_confidence ai.confidence;
ALTER TABLE reference.location ADD COLUMN IF NOT EXISTS identification_signal     TEXT;

COMMENT ON COLUMN reference.device.identification_signal IS
  'What the identification rests on, human-readable: e.g. "IMEI in export metadata" (clear) vs "inferred from message styling" (sketchy). The confidence number decides the lane; this column lets a human sanity-check the number.';

-- threshold as data, per governed table
ALTER TABLE canon.canonical_table ADD COLUMN IF NOT EXISTS auto_confirm_min_confidence ai.confidence;
COMMENT ON COLUMN canon.canonical_table.auto_confirm_min_confidence IS
  'Proposals at or above this confidence route to auto_adopt (applied immediately, logged, reversible). Below it — or NULL — they wait in the table''s default tier. NULL = never auto, regardless of confidence.';

UPDATE canon.canonical_table SET auto_confirm_min_confidence = 0.95
 WHERE table_schema='reference' AND table_name IN ('device','person','location','entity','entity_alias');
-- court_case, matter, evidence_item: stay NULL. Never auto.

-- the router
CREATE OR REPLACE FUNCTION canon.route_tier(p_canonical_table_id UUID, p_confidence NUMERIC)
RETURNS TEXT
LANGUAGE sql STABLE AS $fn$
  SELECT CASE
    WHEN ct.auto_confirm_min_confidence IS NOT NULL
     AND p_confidence IS NOT NULL
     AND p_confidence >= ct.auto_confirm_min_confidence
    THEN 'auto_adopt'
    ELSE ct.default_tier
  END
  FROM canon.canonical_table ct WHERE ct.id = p_canonical_table_id
$fn$;
COMMENT ON FUNCTION canon.route_tier(UUID, NUMERIC) IS
  'Clear signal rides through logged; sketchy signal waits for the owner. Producers call this when filing a change_proposal to set its tier.';
