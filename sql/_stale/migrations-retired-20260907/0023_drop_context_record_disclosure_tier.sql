-- 0023_drop_context_record_disclosure_tier.sql — DROP disclosure_tier from
-- working.context_record. The context lane is JUST normalized data; the
-- knowledge-horizon (as-lived / how-I-saw-it / discovered / hindsight) lives in
-- a SEPARATE table (ADR-0045 A.4 working.realization_event + the derived
-- vw_record_disclosure view), never on the normalized row.
--
-- REVISES OQ-8 (D-042, signed 2026-08-09), which said "the AI-chat context lane
-- auto-asserts hindsight at write." Owner correction 2026-08-12 (verbatim):
-- "No nothing is fucking written like that at all. Normalized data just
-- normalized fucking data ... all that stuff is a different fucking table."
-- I.e. do NOT stamp a horizon tier on the context record AT ALL — not
-- 'contemporaneous' (the old hardcode, which made every row a false
-- as-lived assertion) and not 'hindsight' (which would re-introduce horizon
-- logic at the ingest layer). The context_record row is the facts only
-- (occurred_at / role / content / participants); the horizon is derived
-- downstream from the clocks + HITL realization events.
--
-- SCOPE: context_record ONLY. working.normalized_record (the evidence spine)
-- KEEPS disclosure_tier as an asserted hint per ADR-0045 Decision C — that
-- ruling is unchanged. This migration touches the context lane, which has no
-- evidence FK and no horizon predicate. The DROP COLUMN takes the column's
-- CHECK constraint (disclosure_tier_check) with it.
--
-- Applied manually on the live DB (idempotent — guards on the column existing).
-- Per sql/README.md the numbered chain is history, not a replay path; the
-- bootstrap baseline (sql/bootstrap/schema_baseline.sql) does NOT currently
-- contain working.context_record at all (0021/0022 were applied live but the
-- baseline was never regenerated — a separate housekeeping drift, not caused
-- by this migration). A proper pg_dump --schema-only regen of the baseline is
-- the follow-up, not a hand-edit.
--
-- Byline: Claude Code · Fable 5 · 2026-08-12 (owner correction: context record = just normalized data; horizon = separate table)

DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'working'
          AND table_name   = 'context_record'
          AND column_name  = 'disclosure_tier'
    ) THEN
        ALTER TABLE working.context_record DROP COLUMN disclosure_tier;
        RAISE NOTICE 'dropped working.context_record.disclosure_tier';
    ELSE
        RAISE NOTICE 'working.context_record.disclosure_tier already absent — no-op';
    END IF;
END $$;