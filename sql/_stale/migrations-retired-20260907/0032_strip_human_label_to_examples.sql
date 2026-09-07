-- 0032_strip_human_label_to_examples.sql
-- ✅ APPLIED TO PROD 2026-08-24 — verified live (9 columns, 1,918 rows; gold archive untouched).
--
-- Byline: Claude Code · Fable 5 · 2026-08-24
--
-- OWNER RULING (2026-08-24, verbatim intent): the 1,918-row analysis.human_label table is
-- EXAMPLE data — labeled messages for few-shot prompting / model training. It is deliberately
-- UNLINKED from live tables (linking caused problems in every test). "Strip the IDs, strip
-- the hashes, strip anything that's not necessary for a labeled message to prompt examples."
--
-- What this does:
--   * Drops from analysis.human_label everything except the example essentials:
--       conversation_key, seq (the natural PK, already in place), occurred_at, who,
--       message_text, labels, is_clean, severity, notes
--   * Rebuilds analysis.vw_human_label_long over the surviving columns only.
--   * Leaves analysis.human_label_gold COMPLETELY UNTOUCHED — it is the full-fidelity
--     pre-strip archive (legacy ids, ai_* fields, relink_status all survive there),
--     satisfying never-delete/mine-before-retiring.
--
-- NOTE: as of 2026-08-24 the label fields (labels/is_clean/severity) are empty on all rows
-- in BOTH copies — the labeling pass itself is still to be done ("we'll make it a golden
-- example later" — owner). This migration shapes the table; it does not add labels.

BEGIN;

DROP VIEW analysis.vw_human_label_long;

ALTER TABLE analysis.human_label
    DROP COLUMN message_id,
    DROP COLUMN ai_flagged,
    DROP COLUMN ai_flag_count,
    DROP COLUMN relink_status,
    DROP COLUMN created_at,
    DROP COLUMN labeled_by,
    DROP COLUMN labeled_at;

CREATE VIEW analysis.vw_human_label_long AS
    SELECT conversation_key, seq, occurred_at, who, message_text,
           unnest(labels) AS label, is_clean, severity, notes
    FROM analysis.human_label
    WHERE cardinality(labels) > 0;

COMMENT ON TABLE analysis.human_label IS
    'Prompt-example set: labeled messages for few-shot prompting / model training. '
    'Deliberately UNLINKED from live tables (owner ruling 2026-08-24 — linking caused problems every test). '
    'Stripped to message+label essentials by 0032; full-fidelity pre-strip copy = analysis.human_label_gold.';

COMMIT;
