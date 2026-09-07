-- 0063_retire_superseded_legacy.sql
--
-- Byline: Claude · Opus 5 · 2026-08-31, after the origin-trace audit.
--
-- THE METHOD RULING (owner, verbatim): zero rows proves nothing when ingest
-- has never run, and "no code references it" conflates two opposite states —
-- unnecessary table vs missing caller. The tiebreaker is THE CONVERSATION
-- THAT CREATED THE TABLE: migration headers, ADRs, design docs, rulings.
--
-- Applied to all 61 "questionable" tables: 60 are PURPOSE-ALIVE (designed,
-- documented, waiting for code — they go on the BUILD list, not the kill
-- list), 10 of those explicitly PARKED (D-044 geo/Timeline family). Exactly
-- TWO are superseded, by sql/0002's own header text: "LEGACY (2026-06-12):
-- agent_run + approval_request are SUPERSEDED by the native agno approvals
-- store... no code writes here anymore."
DO $$
DECLARE n BIGINT;
BEGIN
  FOR n IN SELECT count(*) FROM public.agent_run LOOP
    IF n > 0 THEN RAISE EXCEPTION 'ABORT: agent_run has % rows', n; END IF;
  END LOOP;
  FOR n IN SELECT count(*) FROM public.approval_request LOOP
    IF n > 0 THEN RAISE EXCEPTION 'ABORT: approval_request has % rows', n; END IF;
  END LOOP;
END $$;
DROP TABLE IF EXISTS public.approval_request CASCADE;
DROP TABLE IF EXISTS public.agent_run CASCADE;
