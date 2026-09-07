-- 0010_extraction_candidate_and_acquisition_reconcile.sql
--
-- Byline: Claude Code · Opus 5 (1M) · 2026-08-01
--
-- TWO CHANGES
--
-- A. Widen the staging lane from entities to ALL extraction output.
--    0008 created analysis.entity_candidate, which was too narrow. Semantica's
--    semantic_extract already ships event_detector (with TemporalEventProcessor),
--    NER covering GPE/LOC, relation_extractor and triplet_extractor — so extraction
--    yields events, places and relations, not just entities. Destination tables for
--    those already exist and are empty (timeline_event, location, location_assertion,
--    temporal_anchor, time_assertion).
--
--    One staging lane, one HITL gate, a candidate_kind discriminator, fanning out to
--    the right destination. Verified safe to rename: nothing in server/ or tests/
--    references entity_candidate (the only hits are a local variable inside vendored
--    semantica).
--
--    NOT included: "lies". Deception is not extraction — you cannot extract a lie
--    from one message. It is CONTRADICTION DETECTION across records, computed over
--    the assembled timeline, and belongs with analysis.finding / pattern_finding /
--    location_contradiction. Kept deliberately separate.
--
-- B. Reconcile evidence.acquisition against evidence.source.
--    Both describe acquisition, at different grains. Checked against live code
--    before deciding:
--      - evidence.source.acquisition_source and .acquisition_method are LIVE — written
--        on every ingest by server/evidence/custody.py:223 and defaulted by
--        server/tools/parsers/messaging/sbv_sms.py:185. They stay.
--      - evidence.acquisition (0008) is the per-EVENT record: one device handoff or
--        one export session covering MANY files, with authority, custodian and
--        time-scoping that a per-file column cannot express.
--    So they are not duplicates — they are different grains. This migration makes the
--    relationship explicit and adds a view that surfaces divergence rather than
--    letting the two drift silently.
--
-- Idempotent. Handles 0008 being applied or not. Percent-free (psycopg placeholder
-- parsing). Never edit after apply — add 0011.

BEGIN;

-- ---------------------------------------------------------------------------
-- A. entity_candidate -> extraction_candidate (+ candidate_kind)
-- ---------------------------------------------------------------------------

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables
             WHERE table_schema='analysis' AND table_name='entity_candidate')
     AND NOT EXISTS (SELECT 1 FROM information_schema.tables
             WHERE table_schema='analysis' AND table_name='extraction_candidate')
  THEN
    ALTER TABLE analysis.entity_candidate RENAME TO extraction_candidate;
  END IF;
END $$;

-- If 0008 was never applied, create the widened table directly.
CREATE TABLE IF NOT EXISTS analysis.extraction_candidate (
  id                 UUID PRIMARY KEY DEFAULT uuidv7(),
  record_id          UUID REFERENCES analysis.normalized_record(id),
  source_id          UUID REFERENCES evidence.source(id),
  evidence_hash_id   UUID,
  entity_text        TEXT NOT NULL,
  entity_type        TEXT,
  normalized_value   TEXT,
  span_start         INT,
  span_end           INT,
  extractor          TEXT NOT NULL,
  extractor_version  TEXT,
  confidence         NUMERIC(5,4) CHECK (confidence IS NULL OR (confidence >= 0 AND confidence <= 1)),
  coref_chain_id     TEXT,
  relation_predicate TEXT,
  relation_object    TEXT,
  occurred_at        TIMESTAMPTZ,
  realized_at        TIMESTAMPTZ,
  review_status      TEXT NOT NULL DEFAULT 'pending'
    CHECK (review_status IN ('pending','approved','rejected','needs_info')),
  reviewed_by        TEXT,
  reviewed_at        TIMESTAMPTZ,
  review_note        TEXT,
  consumed_by        TEXT[] NOT NULL DEFAULT '{}',
  extracted_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- What KIND of thing this candidate is. The discriminator that lets one staging lane
-- and one HITL gate serve every extractor.
ALTER TABLE analysis.extraction_candidate
  ADD COLUMN IF NOT EXISTS candidate_kind TEXT NOT NULL DEFAULT 'entity'
    CHECK (candidate_kind IN ('entity','event','place','relation','claim')),
  -- Where an approved candidate should land. Written by the fan-out step so routing
  -- is inspectable rather than buried in code.
  ADD COLUMN IF NOT EXISTS target_table TEXT,
  ADD COLUMN IF NOT EXISTS target_id    UUID,
  -- Kind-specific payload: event window, place coordinates, claim polarity. Avoids a
  -- column per extractor while keeping the shared spine typed.
  ADD COLUMN IF NOT EXISTS payload      JSONB,
  ADD COLUMN IF NOT EXISTS extraction_batch_id UUID;

-- Present only when 0009 ran; added there too, so guard the FK.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables
             WHERE table_schema='analysis' AND table_name='extraction_batch')
     AND NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='extraction_candidate_batch_fk')
  THEN
    ALTER TABLE analysis.extraction_candidate
      ADD CONSTRAINT extraction_candidate_batch_fk
      FOREIGN KEY (extraction_batch_id) REFERENCES analysis.extraction_batch(id);
  END IF;
END $$;

-- Idempotency: re-running the same extractor over the same span must not duplicate.
-- candidate_kind is part of the key — the same span can legitimately yield an entity
-- AND an event.
DROP INDEX IF EXISTS analysis.uq_entity_candidate_dedupe;
CREATE UNIQUE INDEX IF NOT EXISTS uq_extraction_candidate_dedupe
  ON analysis.extraction_candidate (
    COALESCE(record_id::TEXT,''), candidate_kind, extractor,
    COALESCE(span_start,-1), COALESCE(span_end,-1), entity_text
  );

CREATE INDEX IF NOT EXISTS idx_extcand_kind    ON analysis.extraction_candidate(candidate_kind);
CREATE INDEX IF NOT EXISTS idx_extcand_record  ON analysis.extraction_candidate(record_id);
CREATE INDEX IF NOT EXISTS idx_extcand_pending ON analysis.extraction_candidate(review_status)
  WHERE review_status = 'pending';
CREATE INDEX IF NOT EXISTS idx_extcand_batch   ON analysis.extraction_candidate(extraction_batch_id);
CREATE INDEX IF NOT EXISTS idx_extcand_consumed ON analysis.extraction_candidate USING GIN(consumed_by);

COMMENT ON TABLE analysis.extraction_candidate IS
  'Staging lane for ALL extraction output — entities, events, places, relations, '
  'claims — discriminated by candidate_kind. Records a CLAIM with confidence and '
  'provenance, never resolved truth. Append-only; nothing propagates to Graphiti, the '
  'evidence graph or the KB until review_status = approved. Renamed from '
  'entity_candidate 2026-08-01: entity-only was too narrow for what Semantica extracts.';

COMMENT ON COLUMN analysis.extraction_candidate.candidate_kind IS
  'entity | event | place | relation | claim. Routes an approved candidate to its '
  'destination (analysis.entity, timeline_event, location, ...). Deception/"lies" is '
  'deliberately NOT a kind — that is contradiction detection across records, computed '
  'over the assembled timeline, not extraction from a single message.';

-- Rename the append-only trigger's function reference if 0008 created it.
CREATE OR REPLACE FUNCTION analysis.extraction_candidate_no_mutate()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.entity_text  IS DISTINCT FROM OLD.entity_text
     OR NEW.record_id IS DISTINCT FROM OLD.record_id
     OR NEW.extractor IS DISTINCT FROM OLD.extractor
     OR NEW.candidate_kind IS DISTINCT FROM OLD.candidate_kind
     OR NEW.span_start IS DISTINCT FROM OLD.span_start
     OR NEW.span_end   IS DISTINCT FROM OLD.span_end THEN
    RAISE EXCEPTION USING MESSAGE =
      'analysis.extraction_candidate is append-only: insert a new row instead of '
      'editing the claim (review columns and consumed_by are the mutable surface)';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_entity_candidate_no_mutate ON analysis.extraction_candidate;
DROP TRIGGER IF EXISTS trg_extraction_candidate_no_mutate ON analysis.extraction_candidate;
CREATE TRIGGER trg_extraction_candidate_no_mutate
  BEFORE UPDATE ON analysis.extraction_candidate
  FOR EACH ROW EXECUTE FUNCTION analysis.extraction_candidate_no_mutate();

-- ---------------------------------------------------------------------------
-- B. Acquisition reconciliation — two grains, one relationship.
-- ---------------------------------------------------------------------------

COMMENT ON COLUMN evidence.source.acquisition_method IS
  'PER-FILE acquisition method, written at ingest by server/evidence/custody.py. '
  'Retained and live. For the per-EVENT record — device, authority, custodian, '
  'time-scoped handoff, one row covering many files — join evidence.acquisition via '
  'evidence.source.acquisition_id. On disagreement the acquisition row wins: it is '
  'HITL-authored, the per-file value is a pipeline default.';

COMMENT ON COLUMN evidence.source.acquisition_source IS
  'PER-FILE acquisition source (e.g. "sbv", "manual_export"), written at ingest. '
  'Describes the ingest CHANNEL, not the legal/physical provenance — that is '
  'evidence.acquisition.method + .authority.';

-- Surfaces divergence between the per-file cache and the per-event record instead of
-- letting the two drift silently apart.
CREATE OR REPLACE VIEW evidence.vw_source_acquisition AS
SELECT
  s.id                        AS source_id,
  s.original_filename,
  s.sha256,
  s.acquisition_source        AS file_acquisition_source,
  s.acquisition_method        AS file_acquisition_method,
  s.custodian                 AS file_custodian,
  s.acquired_at_utc           AS file_acquired_at,
  s.provenance_tier,
  a.id                        AS acquisition_id,
  a.method                    AS event_method,
  a.authority                 AS event_authority,
  a.device_custodian          AS event_custodian,
  a.acquired_at               AS event_acquired_at,
  a.export_created_at,
  a.producible,
  CASE
    WHEN a.id IS NULL THEN 'no_acquisition_event'
    WHEN s.acquisition_method IS DISTINCT FROM a.method::TEXT THEN 'METHOD_DIVERGES'
    WHEN s.acquired_at_utc IS NOT NULL AND a.acquired_at IS NOT NULL
         AND abs(extract(epoch FROM (s.acquired_at_utc - a.acquired_at))) > 86400
      THEN 'ACQUIRED_AT_DIVERGES'
    ELSE 'consistent'
  END AS reconciliation_status
FROM evidence.source s
LEFT JOIN evidence.acquisition a ON a.id = s.acquisition_id;

COMMENT ON VIEW evidence.vw_source_acquisition IS
  'Reconciles the PER-FILE acquisition columns on evidence.source (live, written by '
  'custody.py at ingest) against the PER-EVENT evidence.acquisition row. These are '
  'different grains, not duplicates: one export session or device handoff covers many '
  'files. reconciliation_status flags divergence; no_acquisition_event means the file '
  'predates the acquisition intake form and needs one.';

COMMIT;
