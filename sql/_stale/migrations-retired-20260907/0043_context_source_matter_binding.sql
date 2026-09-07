-- Byline: Codex · GPT-5 · 2026-08-28 (authoritative UIW Matter binding)
-- Migration 0043: bind each UIW source version to its selected matter/case.
--
-- Existing rows remain unassigned for compatibility; new UIW registration
-- supplies both UUIDs and the composite FK prevents cross-matter cases.
BEGIN;

DO $$
BEGIN
    IF current_database() <> 'platform' THEN
        RAISE EXCEPTION 'migration 0043 may run only in database platform, not %', current_database();
    END IF;
END;
$$;

ALTER TABLE context.source_version
    ADD COLUMN IF NOT EXISTS matter_id UUID,
    ADD COLUMN IF NOT EXISTS court_case_id UUID;

ALTER TABLE context.source_version
    DROP CONSTRAINT IF EXISTS source_version_matter_case_pair_check,
    ADD CONSTRAINT source_version_matter_case_pair_check
        CHECK ((matter_id IS NULL) = (court_case_id IS NULL)),
    DROP CONSTRAINT IF EXISTS source_version_court_case_scope_fk,
    ADD CONSTRAINT source_version_court_case_scope_fk
        FOREIGN KEY (court_case_id, matter_id)
        REFERENCES analysis.court_case(id, matter_id)
        ON DELETE RESTRICT;

COMMENT ON COLUMN context.source_version.matter_id IS
    'Canonical matter selected at UIW intake; paired with court_case_id.';
COMMENT ON COLUMN context.source_version.court_case_id IS
    'Canonical court case selected at UIW intake; composite-FK scoped to matter_id.';

COMMIT;
