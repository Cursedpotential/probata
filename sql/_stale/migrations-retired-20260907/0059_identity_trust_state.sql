-- 0059_identity_trust_state.sql
--
-- Byline: Claude · Opus 5 · 2026-08-31, owner-ruled.
--
-- Owner, verbatim: "if it's incorrectly identified... I clearly can't trust
-- you, or any system for that matter, to properly do it... it's just working
-- while it's waiting for approval... if I give you a pile and you decide it's
-- from the wrong device, it needs to be fixed."
--
-- The ruling this encodes: WRONG != WIPEABLE. Identity survives purges
-- (reference, D-115) but nothing in it is trusted until the owner rules.
-- "Waiting for approval" is a COLUMN, not a schema address:
--
--   verification_state = 'proposed'   system-identified, unreviewed  (default)
--                        'confirmed'  owner ruled it correct
--                        'disputed'   owner or a diff flagged it wrong
--
-- A misattribution is FIXED through the canon spine: change_proposal on the
-- identity row (or on the rows pointing at it), owner approval, prior values
-- snapshotted, recompute fires. This migration registers the identity tables
-- in canon.canonical_table so that path is live.

-- trust state where it was missing (entity already has review_status)
ALTER TABLE reference.device     ADD COLUMN IF NOT EXISTS verification_state TEXT NOT NULL DEFAULT 'proposed'
  CHECK (verification_state IN ('proposed','confirmed','disputed'));
ALTER TABLE reference.person     ADD COLUMN IF NOT EXISTS verification_state TEXT NOT NULL DEFAULT 'proposed'
  CHECK (verification_state IN ('proposed','confirmed','disputed'));
ALTER TABLE reference.location   ADD COLUMN IF NOT EXISTS verification_state TEXT NOT NULL DEFAULT 'proposed'
  CHECK (verification_state IN ('proposed','confirmed','disputed'));
ALTER TABLE reference.court_case ADD COLUMN IF NOT EXISTS verification_state TEXT NOT NULL DEFAULT 'proposed'
  CHECK (verification_state IN ('proposed','confirmed','disputed'));
ALTER TABLE reference.matter     ADD COLUMN IF NOT EXISTS verification_state TEXT NOT NULL DEFAULT 'proposed'
  CHECK (verification_state IN ('proposed','confirmed','disputed'));

COMMENT ON COLUMN reference.device.verification_state IS
  'proposed = system-identified, untrusted. confirmed = owner ruled. disputed = flagged wrong. Corrections flow through canon.change_proposal, never direct edits.';

-- register identity in the canon boundary: corrections are governed from now on
INSERT INTO canon.canonical_table (table_schema, table_name, default_tier, recompute_targets, registered_by, notes) VALUES
  ('reference','device',     'batch_review',    '{semantica,sat_temporal,timeline}', 'owner ruling 2026-08-31', 'device attribution errors are the canonical example: "you decide it''s from the wrong device, it needs to be fixed"'),
  ('reference','person',     'batch_review',    '{semantica,sat_temporal,timeline}', 'owner ruling 2026-08-31', NULL),
  ('reference','entity',     'batch_review',    '{semantica,sat_temporal}',          'owner ruling 2026-08-31', 'merges are explicit_review regardless of default tier'),
  ('reference','entity_alias','batch_review',   '{semantica,sat_temporal}',          'owner ruling 2026-08-31', NULL),
  ('reference','location',   'batch_review',    '{timeline}',                        'owner ruling 2026-08-31', NULL),
  ('reference','court_case', 'explicit_review', '{}',                                'owner ruling 2026-08-31', 'case identity is never auto-anything'),
  ('reference','matter',     'explicit_review', '{}',                                'owner ruling 2026-08-31', NULL),
  ('evidence','evidence_item','explicit_review','{semantica,sat_temporal,timeline}', 'owner ruling 2026-08-31', 'THE promotion target; every write is an owner act')
ON CONFLICT (table_schema, table_name) DO NOTHING;
