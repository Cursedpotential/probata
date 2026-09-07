-- 0009_raw_layer_and_derivation.sql
--
-- Byline: Claude Code · Opus 5 (1M) · 2026-08-01
--
-- WHY THIS EXISTS
--   Owner ruling 2026-08-01: "they should all be linked and derived, only one raw
--   written to." Three layers, ONE insert target:
--
--     RAW per-source   the ONLY thing the parser writes. Verbatim, never edited.
--          | derive + dedup
--     SPINE            analysis.normalized_record — ONE row per real-world message,
--          |           deduped across every artifact that attests it.
--          | derive
--     PROJECTION       analysis.message / message_participant / conversation.
--
--   Consequence: "reprocess everything" becomes RE-DERIVE, not re-ingest. The
--   original devices and export files are never touched again after acquisition.
--
--   THE RAW LAYER EXISTS TODAY ONLY FOR GEO (evidence.raw_activity/raw_path/
--   raw_trip/raw_visit). Messaging never got one — the RESTART-0001 six per-source
--   tables were staged and never applied, so analysis.message.raw_data has been
--   standing in for it. That is why `message` looks like both a raw and a working
--   table. This migration supplies the missing layer.
--
-- DEDUPLICATION RULE (owner, verbatim intent)
--   "They won't get de-duped unless it's the exact same device and the exact same
--    medium in which it's been saved. It will make it only into the normalized
--    record once. However we will record all of the sources."
--
--   So: dedup at RAW on (device, medium, content) only. An XML export, a screenshot,
--   a screen capture, and a screenshot forwarded inside another message are FOUR
--   separate raw rows. They collapse to ONE normalized_record, and every one of them
--   is recorded in analysis.event_source_record.
--
--   Duplicates are not waste — they are corroboration. Attestations that AGREE
--   strengthen the record; one that DIFFERS is a finding, surfaced via
--   analysis.timeline_event.is_conflicted. Never dedup them away.
--
-- Idempotent. Safe to re-run. Never edit after it is applied — add 0010.

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. Medium — HOW a record reached us. Distinct from format: the same message can
--    arrive as parsed export rows AND as pixels in a screenshot, and those carry
--    very different evidentiary weight.
-- ---------------------------------------------------------------------------

DO $$ BEGIN
  CREATE TYPE evidence.record_medium AS ENUM (
    'export',          -- structured export from the app (XML/JSON/CSV)
    'screenshot',      -- image of a screen, OCR'd
    'screen_capture',  -- video/scrolling capture
    'forwarded',       -- a screenshot/quote embedded inside another message
    'transcript',      -- typed or dictated reproduction
    'unknown'
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ---------------------------------------------------------------------------
-- 2. The six per-source RAW tables (RESTART-0001 shape).
--
--    Created from one template so the shared spine of columns cannot drift between
--    sources, with a per-source `raw` JSONB for format-specific fields. Six tables
--    rather than one wide table because the owner's design calls for per-source
--    isolation: a parser change for Facebook must not be able to touch iMessage rows.
--
--    Each carries H2 (content_hash) over the RAW SOURCE BYTES — not over a derived
--    row. A hash of a derived row attests to our own transformation, not to the
--    evidence.
-- ---------------------------------------------------------------------------

-- NOTE: built with || concatenation rather than plpgsql format() with positional
-- specifiers, on purpose. Percent signs anywhere in the statement text collide with
-- client-side placeholder parsing in psycopg (and any DB-API driver that scans for
-- them), so a percent-free migration runs under psql AND under a Python migration
-- runner. Verified 2026-08-01 — format() failed, and so did a comment that merely
-- MENTIONED a positional specifier. Keep this file free of percent signs entirely.

DO $$
DECLARE
  src TEXT;
  t   TEXT;
BEGIN
  FOREACH src IN ARRAY ARRAY['imessage','sms','facebook','csv','ai_chat','phone']
  LOOP
    t := 'evidence.raw_' || src;
    -- Dollar-quoted: the DDL body contains its own string literals (DEFAULT 'export',
    -- the canon tag, the dedupe separators). Single-quoting the whole statement would
    -- let the first inner quote terminate it early — which it did, on first run.
    EXECUTE $ddl$
      CREATE TABLE IF NOT EXISTS $ddl$ || t || $ddl$ (
        id             UUID PRIMARY KEY DEFAULT uuidv7(),

        -- Provenance: which artifact, which device, which acquisition.
        source_id      UUID NOT NULL REFERENCES evidence.source(id),
        device_id      UUID REFERENCES analysis.device(id),
        acquisition_id UUID REFERENCES evidence.acquisition(id),
        medium         evidence.record_medium NOT NULL DEFAULT 'export',

        -- Position within the artifact. Order is evidence: permuting records changes
        -- the H3 chain.
        record_index   INT,

        -- The verbatim payload. Never normalized, never edited.
        raw            JSONB NOT NULL,
        raw_text       TEXT,

        -- H2 over the raw source bytes for this record.
        content_hash   TEXT NOT NULL,
        content_canon  TEXT NOT NULL DEFAULT 'h2-rawelement-v1',

        -- DEDUP KEY is a multi-column UNIQUE index, not a generated column: casting
        -- an enum to text is STABLE rather than IMMUTABLE, so medium cannot appear in
        -- a generated expression. The index is also faster and avoids materialising a
        -- redundant string per row. See the UNIQUE index below.

        -- SUPERSESSION. Raw is append-only, so a parser fix cannot overwrite bad
        -- rows: re-parsing the same source produces a different JSONB shape, a
        -- different content_hash, and therefore NEW rows alongside the old ones.
        -- Without an explicit pointer, derivation would face two raw rows describing
        -- the same source record with nothing to say which is authoritative — and
        -- would pick quietly and wrongly.
        --
        -- parser_version identifies what produced this shape; superseded_by points
        -- forward to the row that replaces it. Nothing is deleted: the superseded row
        -- stays as the record of what the old parser saw.
        parser_version TEXT,
        superseded_by  UUID,
        supersede_note TEXT,

        -- Lineage back to the processing run that wrote it.
        ingest_run_id  UUID,
        deriver_version TEXT,

        ingested_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )$ddl$;

    -- Same device + same medium + same content = the same raw row. Different device
    -- OR different medium = a separate attestation and is KEPT.
    -- NULLS NOT DISTINCT so rows with an unknown device still collide on
    -- (medium, content_hash) instead of silently duplicating (PG15+).
    EXECUTE 'CREATE UNIQUE INDEX IF NOT EXISTS uq_raw_' || src || '_dedupe ON ' || t ||
            ' (device_id, medium, content_hash) NULLS NOT DISTINCT';
    EXECUTE 'CREATE INDEX IF NOT EXISTS idx_raw_' || src || '_source ON ' || t || '(source_id)';
    EXECUTE 'CREATE INDEX IF NOT EXISTS idx_raw_' || src || '_device ON ' || t || '(device_id)';
    EXECUTE 'CREATE INDEX IF NOT EXISTS idx_raw_' || src || '_hash   ON ' || t || '(content_hash)';
    -- Derivation reads only live rows; this keeps that filter cheap.
    EXECUTE 'CREATE INDEX IF NOT EXISTS idx_raw_' || src || '_live ON ' || t ||
            ' (source_id) WHERE superseded_by IS NULL';

    EXECUTE 'COMMENT ON TABLE ' || t || ' IS ' || quote_literal(
      'RAW per-source layer for ' || src || '. The ONLY insert target for this format. '
      'Verbatim and never edited; spine and projection are derived from it. '
      'Dedup on (device, medium, content) only - a screenshot of the same message '
      'is a separate attestation, not a duplicate.');
  END LOOP;
END $$;

-- RAW is append-only. Corrections are new rows; a re-parse that produces different
-- bytes is a different artifact, not an edit.
CREATE OR REPLACE FUNCTION evidence.raw_no_mutate()
RETURNS TRIGGER AS $$
BEGIN
  -- INERT UNTIL LIVE (owner, 2026-08-01: "append only only starts once we are
  -- actually live"). During build-out the schema and parsers churn, and a hard
  -- immutability rule would force a DB rebuild for every iteration. The trigger is
  -- installed now so going live is a one-line switch rather than a migration:
  --
  --   ALTER DATABASE <db> SET app.evidence_live = 'on';
  --
  -- Until then raw behaves like an ordinary table.
  IF current_setting('app.evidence_live', true) IS DISTINCT FROM 'on' THEN
    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
  END IF;

  -- One exception: marking a row superseded. That is the ONLY legal mutation, and it
  -- adds a forward pointer rather than changing anything the row asserts. Everything
  -- the row claimed about the source stays exactly as written.
  IF TG_OP = 'UPDATE'
     AND OLD.superseded_by IS NULL
     AND NEW.superseded_by IS NOT NULL
     AND NEW.raw            IS NOT DISTINCT FROM OLD.raw
     AND NEW.raw_text       IS NOT DISTINCT FROM OLD.raw_text
     AND NEW.content_hash   IS NOT DISTINCT FROM OLD.content_hash
     AND NEW.source_id      IS NOT DISTINCT FROM OLD.source_id
     AND NEW.device_id      IS NOT DISTINCT FROM OLD.device_id
     AND NEW.medium         IS NOT DISTINCT FROM OLD.medium
     AND NEW.record_index   IS NOT DISTINCT FROM OLD.record_index
  THEN
    RETURN NEW;
  END IF;

  RAISE EXCEPTION USING MESSAGE =
    'evidence.' || TG_TABLE_NAME ||
    ' is append-only: raw source records are never updated or deleted '
    '(the only permitted change is setting superseded_by on a live row)';
END;
$$ LANGUAGE plpgsql;

DO $$
DECLARE src TEXT; t TEXT;
BEGIN
  FOREACH src IN ARRAY ARRAY['imessage','sms','facebook','csv','ai_chat','phone']
  LOOP
    t := 'evidence.raw_' || src;
    EXECUTE 'DROP TRIGGER IF EXISTS trg_raw_' || src || '_no_mutate ON ' || t;
    EXECUTE 'CREATE TRIGGER trg_raw_' || src || '_no_mutate BEFORE UPDATE OR DELETE ON ' || t ||
            ' FOR EACH ROW EXECUTE FUNCTION evidence.raw_no_mutate()';
  END LOOP;
END $$;

-- ---------------------------------------------------------------------------
-- 3. Derivation lineage — every derived row points at the raw row(s) it came from.
--
--    analysis.event_source_record already exists with exactly the right shape
--    (event_id, record_id, source_id, raw_ref, role) and zero rows. It is the
--    "record all of the sources" table. It is wired here rather than reinvented.
-- ---------------------------------------------------------------------------

-- Which raw table a raw_ref points into. event_source_record.raw_ref carries the id;
-- this says where to look, since the raw layer is six tables rather than one.
ALTER TABLE analysis.event_source_record
  ADD COLUMN IF NOT EXISTS raw_table TEXT,
  ADD COLUMN IF NOT EXISTS medium    evidence.record_medium,
  ADD COLUMN IF NOT EXISTS agrees    BOOLEAN,   -- does this attestation match the spine row?
  ADD COLUMN IF NOT EXISTS note      TEXT;

COMMENT ON COLUMN analysis.event_source_record.agrees IS
  'Whether this attestation matches the derived spine row. FALSE is a FINDING, not '
  'an error — a screenshot that differs from the export is evidence of alteration. '
  'Surfaces via analysis.timeline_event.is_conflicted.';

CREATE INDEX IF NOT EXISTS idx_esr_record ON analysis.event_source_record(record_id);
CREATE INDEX IF NOT EXISTS idx_esr_source ON analysis.event_source_record(source_id);
CREATE INDEX IF NOT EXISTS idx_esr_rawref ON analysis.event_source_record(raw_ref);
CREATE INDEX IF NOT EXISTS idx_esr_disagree ON analysis.event_source_record(record_id)
  WHERE agrees IS FALSE;

-- Derivation stamping on the spine and the projection, so a rebuild is verifiable
-- rather than hopeful: same raw + same deriver version must produce the same output.
ALTER TABLE analysis.normalized_record
  ADD COLUMN IF NOT EXISTS derived_from_raw_table TEXT,
  ADD COLUMN IF NOT EXISTS derived_from_raw_id    UUID,
  ADD COLUMN IF NOT EXISTS deriver_version        TEXT,
  ADD COLUMN IF NOT EXISTS derived_at             TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS attestation_count      INT NOT NULL DEFAULT 0;

COMMENT ON COLUMN analysis.normalized_record.attestation_count IS
  'How many distinct raw attestations support this one spine row. >1 means the same '
  'message was captured by multiple devices/mediums — corroboration, not duplication. '
  'Maintained from analysis.event_source_record.';

CREATE INDEX IF NOT EXISTS idx_normrec_rawid ON analysis.normalized_record(derived_from_raw_id);

ALTER TABLE analysis.message
  ADD COLUMN IF NOT EXISTS derived_from_record_id UUID REFERENCES analysis.normalized_record(id),
  ADD COLUMN IF NOT EXISTS derived_from_raw_table TEXT,
  ADD COLUMN IF NOT EXISTS derived_from_raw_id    UUID,
  ADD COLUMN IF NOT EXISTS deriver_version        TEXT,
  ADD COLUMN IF NOT EXISTS derived_at             TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_message_derived ON analysis.message(derived_from_record_id);

ALTER TABLE analysis.message_participant
  ADD COLUMN IF NOT EXISTS derived_from_raw_id UUID,
  ADD COLUMN IF NOT EXISTS deriver_version     TEXT;

-- ---------------------------------------------------------------------------
-- 4. Derived-layer write guard.
--
--    Derived tables should only be written by the deriving process. Enforced via a
--    session GUC so the guard is INERT until switched on — turning it on right now
--    would break the running ingest pipeline mid-flight.
--
--    To arm:    ALTER DATABASE <db> SET app.enforce_derived_guard = 'on';
--    Deriver:   SET LOCAL app.deriving = 'on';   -- inside its transaction
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION analysis.derived_write_guard()
RETURNS TRIGGER AS $$
BEGIN
  IF current_setting('app.enforce_derived_guard', true) IS DISTINCT FROM 'on' THEN
    RETURN NEW;                      -- guard not armed
  END IF;
  IF current_setting('app.deriving', true) = 'on' THEN
    RETURN NEW;                      -- the deriver is allowed
  END IF;
  RAISE EXCEPTION USING MESSAGE =
    'analysis.' || TG_TABLE_NAME
    || ' is a DERIVED table: write it only from the derivation pass '
    || '(SET LOCAL app.deriving = ''on''). Raw is the single insert target.';
END;
$$ LANGUAGE plpgsql;

DO $$
DECLARE t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY['normalized_record','message','message_participant']
  LOOP
    EXECUTE 'DROP TRIGGER IF EXISTS trg_' || t || '_derived_guard ON analysis.' || t;
    EXECUTE 'CREATE TRIGGER trg_' || t || '_derived_guard BEFORE INSERT OR UPDATE ON analysis.' || t ||
            ' FOR EACH ROW EXECUTE FUNCTION analysis.derived_write_guard()';
  END LOOP;
END $$;

-- ---------------------------------------------------------------------------
-- 5. Attestation view — one row per spine record showing every source that attests
--    it and whether they agree. This is the "record all of the sources" read model.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE VIEW analysis.vw_record_attestations AS
SELECT
  r.id                                   AS record_id,
  r.occurred_at,
  count(esr.link_id)                     AS attestation_count,
  count(*) FILTER (WHERE esr.agrees IS FALSE) AS disagreeing_count,
  array_agg(DISTINCT esr.medium)         FILTER (WHERE esr.medium IS NOT NULL) AS mediums,
  array_agg(DISTINCT esr.raw_table)      FILTER (WHERE esr.raw_table IS NOT NULL) AS raw_tables,
  array_agg(DISTINCT esr.source_id)      FILTER (WHERE esr.source_id IS NOT NULL) AS source_ids,
  CASE
    WHEN count(*) FILTER (WHERE esr.agrees IS FALSE) > 0 THEN 'CONFLICTED'
    WHEN count(esr.link_id) > 1                          THEN 'corroborated'
    WHEN count(esr.link_id) = 1                          THEN 'single_source'
    ELSE 'unlinked'
  END AS attestation_status
FROM analysis.normalized_record r
LEFT JOIN analysis.event_source_record esr ON esr.record_id = r.id
GROUP BY r.id, r.occurred_at;

COMMENT ON VIEW analysis.vw_record_attestations IS
  'Every source attesting each spine record. attestation_status: CONFLICTED (an '
  'attestation disagrees — a finding), corroborated (multiple independent sources), '
  'single_source, unlinked. Multiple mediums for one message is expected and valuable.';

-- ---------------------------------------------------------------------------
-- 6. First-pass OBSERVATIONS — sentiment and other cheap signals.
--
--    analysis.message already carries *_hint columns (surface_sentiment_hint,
--    inferred_intent_hint, topic_hint, relevance_hint, custody_relevance_hint,
--    evidence_strength_hint, extraction_confidence, hint_provenance). Those live on
--    the PROJECTION, which is rebuildable — so anything written there is destroyed
--    on the next re-derive. Observations must outlive derivation, so they get their
--    own append-only table keyed to the SPINE.
--
--    An observation is a CLAIM by a named observer at a version, never a fact. Two
--    models may disagree about sentiment; both rows are kept and the disagreement is
--    queryable. Nothing here is court-facing until reviewed — these are hypotheses,
--    kept strictly separate from findings (Constraints: hypotheses never bypass the
--    review gate).
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS analysis.record_observation (
  id             UUID PRIMARY KEY DEFAULT uuidv7(),
  record_id      UUID NOT NULL REFERENCES analysis.normalized_record(id),

  kind           TEXT NOT NULL,      -- 'sentiment' | 'intent' | 'topic' | 'tone' | ...
  value_text     TEXT,               -- categorical result, e.g. 'hostile'
  value_num      NUMERIC,            -- scalar result, e.g. -0.82
  scale          TEXT,               -- what value_num means, e.g. 'polarity_-1_1'

  confidence     NUMERIC(5,4) CHECK (confidence IS NULL OR (confidence BETWEEN 0 AND 1)),

  -- Who said so, and with what. Required: an unattributed observation is unusable.
  observer       TEXT NOT NULL,      -- 'semantica.sentiment' | 'llm:<model>' | 'human'
  observer_version TEXT,
  prompt_version TEXT,
  evidence       JSONB,              -- spans, rationale, supporting quotes

  -- Hypothesis until a human says otherwise. Mirrors the entity_candidate gate.
  review_status  TEXT NOT NULL DEFAULT 'unreviewed'
    CHECK (review_status IN ('unreviewed','approved','rejected')),
  safe_for_legal_use BOOLEAN NOT NULL DEFAULT FALSE,

  observed_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- Re-running the same observer at the same version must not duplicate.
  dedupe_key     TEXT GENERATED ALWAYS AS (
                   record_id::TEXT || '|' || kind || '|' || observer || '|' ||
                   COALESCE(observer_version,'')
                 ) STORED
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_recobs_dedupe ON analysis.record_observation(dedupe_key);
CREATE INDEX IF NOT EXISTS idx_recobs_record ON analysis.record_observation(record_id);
CREATE INDEX IF NOT EXISTS idx_recobs_kind   ON analysis.record_observation(kind);
CREATE INDEX IF NOT EXISTS idx_recobs_unrev  ON analysis.record_observation(review_status)
  WHERE review_status = 'unreviewed';

COMMENT ON TABLE analysis.record_observation IS
  'First-pass observations (sentiment, intent, topic) keyed to the SPINE so they '
  'survive re-derivation — the *_hint columns on analysis.message do not. Append-only '
  'claims with observer + version + confidence; disagreement between observers is '
  'preserved, not resolved. Hypotheses only: safe_for_legal_use defaults FALSE.';

-- ---------------------------------------------------------------------------
-- 7. CROSS-PLATFORM conversation identity.
--
--    The same human conversation moves between platforms — it starts on SMS,
--    continues on iMessage, resumes on Facebook. analysis.conversation keys on
--    external_thread_key, which is per-platform and therefore cannot express
--    "these three threads are one conversation".
--
--    A thread joins a canonical conversation by ASSERTION, with a stated basis.
--    Same-participants is suggestive, never conclusive: two people can hold several
--    genuinely distinct conversations across platforms.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS analysis.conversation_group (
  id           UUID PRIMARY KEY DEFAULT uuidv7(),
  label        TEXT,
  notes        TEXT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS analysis.conversation_group_member (
  id              UUID PRIMARY KEY DEFAULT uuidv7(),
  group_id        UUID NOT NULL REFERENCES analysis.conversation_group(id),
  conversation_id UUID NOT NULL REFERENCES analysis.conversation(id),
  platform        TEXT,

  -- Why this thread is believed to be part of the group.
  match_basis     TEXT NOT NULL DEFAULT 'unreviewed',   -- 'same_participants' | 'content_continuity' | 'human'
  match_score     NUMERIC(5,4) CHECK (match_score IS NULL OR (match_score BETWEEN 0 AND 1)),
  asserted_by     TEXT NOT NULL DEFAULT 'human',
  review_status   TEXT NOT NULL DEFAULT 'pending'
    CHECK (review_status IN ('pending','approved','rejected')),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT uq_convgrp_member UNIQUE (group_id, conversation_id)
);

CREATE INDEX IF NOT EXISTS idx_convgrpmem_conv  ON analysis.conversation_group_member(conversation_id);
CREATE INDEX IF NOT EXISTS idx_convgrpmem_group ON analysis.conversation_group_member(group_id);

COMMENT ON TABLE analysis.conversation_group IS
  'Canonical cross-platform conversation. Groups per-platform threads (SMS + iMessage '
  '+ Facebook) that are one human conversation. Membership is asserted with a basis '
  'and reviewed — shared participants alone does not make one conversation.';

-- ---------------------------------------------------------------------------
-- 8. BLOCK STATUS — time-scoped, like device ownership.
--
--    analysis.phone.is_blocked and analysis.handle.is_blocked are single booleans
--    with no time dimension, so they can only say "blocked now". Whether a number
--    was blocked AT the time of a message is the question that actually matters —
--    it evidences avoidance, escalation, or an attempt to route around a block.
--    A flat boolean silently answers with today's state, the same failure mode as
--    untimed device ownership.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS analysis.block_status (
  id             UUID PRIMARY KEY DEFAULT uuidv7(),

  -- What was blocked: a phone, a handle, or a resolved entity.
  target_kind    TEXT NOT NULL CHECK (target_kind IN ('phone','handle','entity')),
  target_id      UUID NOT NULL,

  -- Whose side did the blocking, and on which device.
  blocker_entity_id UUID REFERENCES analysis.entity(id),
  device_id      UUID REFERENCES analysis.device(id),

  -- NOT a boolean. A block is rarely confirmable — it is usually INFERRED from
  -- delivery behaviour (outbound stops landing, traffic goes one-way, delivery
  -- receipts vanish). Collapsing "suspected" into "blocked" would assert a fact the
  -- evidence does not support; collapsing it into "not blocked" would discard a real
  -- signal. It gets its own state.
  status         TEXT NOT NULL DEFAULT 'unknown'
    CHECK (status IN ('blocked','suspected','not_blocked','unknown')),
  confidence     NUMERIC(5,4) CHECK (confidence IS NULL OR (confidence BETWEEN 0 AND 1)),

  effective_from TIMESTAMPTZ NOT NULL,
  effective_to   TIMESTAMPTZ,

  basis          TEXT,        -- how this is known: screenshot, settings export, testimony
  -- What suggested it, when status = 'suspected'. Keeps the reasoning inspectable
  -- instead of burying an inference behind a flag, e.g.
  --   {"outbound_undelivered": 14, "last_inbound": "2024-03-02", "one_way_days": 47}
  inference_signals JSONB,
  evidence_ref   UUID,        -- artifact supporting the assertion
  asserted_by    TEXT NOT NULL DEFAULT 'human',
  notes          TEXT,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT block_status_range CHECK (effective_to IS NULL OR effective_to > effective_from),
  -- A suspicion must show its work; a confirmed block must cite a basis.
  CONSTRAINT block_status_supported CHECK (
    status <> 'suspected' OR inference_signals IS NOT NULL OR basis IS NOT NULL
  )
);

CREATE INDEX IF NOT EXISTS idx_blockstatus_target ON analysis.block_status(target_kind, target_id);
CREATE INDEX IF NOT EXISTS idx_blockstatus_range  ON analysis.block_status(target_id, effective_from, effective_to);

COMMENT ON TABLE analysis.block_status IS
  'Time-scoped block state. analysis.phone.is_blocked / handle.is_blocked are untimed '
  'booleans that can only report today; this answers "was it blocked WHEN the message '
  'was sent", which is the evidentially relevant question. status is 4-valued because '
  'a block is usually INFERRED from delivery behaviour, not confirmed.';

-- ---------------------------------------------------------------------------
-- 9. EXTRACTION BATCH — the report handed to Semantica.
--
--    Semantica gets a materialised, hashed batch. It does NOT query the database.
--    That follows the boundary this platform already enforces (SBV holds no DB
--    credentials; custody.py is the sole writer; agent connections are read-only per
--    ADR-0005) and it is what makes an extraction REPRODUCIBLE: if the extractor
--    queried live, the input would move underneath it and the same extraction could
--    never be re-run against the same data.
--
--    Same input_hash + same semantica_version = same output. Verifiable, not hopeful.
--
--    TIMING: extraction is a SEPARATE PASS, not inline with ingest. Extraction is
--    expensive and model-dependent, so it must be possible to re-extract without
--    re-deriving, and to re-derive without re-extracting. A slow model pass must
--    never block evidence from landing.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS analysis.extraction_batch (
  id                UUID PRIMARY KEY DEFAULT uuidv7(),

  -- What went in. scope_query is kept verbatim so the selection itself is auditable,
  -- not just its result.
  scope_query       TEXT,
  scope_note        TEXT,
  record_count      INT NOT NULL DEFAULT 0,

  -- Hash over the materialised batch content. This is the reproducibility anchor.
  input_hash        TEXT,
  input_canon       TEXT NOT NULL DEFAULT 'extraction-batch-v1',
  input_ref         TEXT,            -- where the materialised batch lives (path/URI)

  -- Exactly what processed it.
  extractor         TEXT NOT NULL,   -- 'semantica'
  extractor_version TEXT,
  prompt_version    TEXT,
  ontology_version  TEXT,
  model_id          TEXT,

  status            TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','running','completed','failed','superseded')),
  error_note        TEXT,

  started_at        TIMESTAMPTZ,
  completed_at      TIMESTAMPTZ,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_extbatch_status ON analysis.extraction_batch(status)
  WHERE status IN ('pending','running');
CREATE INDEX IF NOT EXISTS idx_extbatch_hash   ON analysis.extraction_batch(input_hash);

COMMENT ON TABLE analysis.extraction_batch IS
  'A materialised, hashed report handed to Semantica. Semantica is PUSHED this batch '
  'and never queries the DB, preserving the no-credentials boundary and making every '
  'extraction reproducible. Runs as its own pass after derivation, never inline with '
  'ingest.';

-- Every candidate traces back to the batch that produced it, so an extraction can be
-- retracted wholesale when a model or prompt turns out to be wrong.
ALTER TABLE analysis.entity_candidate
  ADD COLUMN IF NOT EXISTS extraction_batch_id UUID REFERENCES analysis.extraction_batch(id);

CREATE INDEX IF NOT EXISTS idx_entcand_batch ON analysis.entity_candidate(extraction_batch_id);

ALTER TABLE analysis.record_observation
  ADD COLUMN IF NOT EXISTS extraction_batch_id UUID REFERENCES analysis.extraction_batch(id);

CREATE INDEX IF NOT EXISTS idx_recobs_batch ON analysis.record_observation(extraction_batch_id);

COMMIT;
