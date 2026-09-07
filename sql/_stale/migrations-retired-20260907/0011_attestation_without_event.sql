-- 0011_attestation_without_event.sql
--
-- Byline: Claude Code · Opus 5 (1M) · 2026-08-01
--
-- Found by running a real export end-to-end, not by reading the schema.
--
-- analysis.event_source_record.event_id was NOT NULL, which assumes every link is
-- anchored to an analysis.timeline_event. That holds for the table's original purpose
-- (an EVENT cites the records that evidence it) but not for the attestation model
-- 0009 layered on top: there, a spine RECORD cites every SOURCE that attests it, and
-- at ingest time no timeline event exists yet — events are produced later by
-- extraction, and only after the HITL gate.
--
-- Requiring event_id at ingest would force one of two bad options: invent a
-- placeholder event per message (polluting the timeline with rows that assert
-- nothing), or skip attestation recording entirely (losing the corroboration and
-- conflict signal that is the whole point).
--
-- So event_id becomes nullable. NULL means "attestation recorded, not yet tied to a
-- timeline event" — which is the honest state for freshly ingested evidence. A later
-- extraction pass fills it in.
--
-- Safe: the table is empty (0 rows) at time of writing.
--
-- Idempotent. Percent-free. Never edit after apply — add 0012.

BEGIN;

ALTER TABLE analysis.event_source_record ALTER COLUMN event_id DROP NOT NULL;

COMMENT ON COLUMN analysis.event_source_record.event_id IS
  'Optional. NULL means this row records an ATTESTATION (a spine record citing a '
  'source that attests it) rather than an EVENT citation. Ingest writes attestations '
  'with event_id NULL because no timeline_event exists until extraction runs and its '
  'candidates pass the HITL gate. Made nullable 2026-08-01 after a real end-to-end '
  'run showed the NOT NULL forced either placeholder events or dropped attestations.';

-- At least one anchor must be present, so a row cannot be meaningless.
DO $$ BEGIN
  ALTER TABLE analysis.event_source_record
    ADD CONSTRAINT event_source_record_has_anchor
    CHECK (event_id IS NOT NULL OR record_id IS NOT NULL);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Attestation lookups filter on record_id with no event; keep that path cheap.
CREATE INDEX IF NOT EXISTS idx_esr_attestation
  ON analysis.event_source_record(record_id)
  WHERE event_id IS NULL;

COMMIT;
