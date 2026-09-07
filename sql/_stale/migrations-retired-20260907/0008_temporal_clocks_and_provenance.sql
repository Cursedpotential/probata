-- 0008_temporal_clocks_and_provenance.sql
--
-- Byline: Claude Code · Opus 5 (1M) · 2026-08-01
--
-- WHY THIS EXISTS
--   The corpus is being fully reprocessed from source (owner, 2026-08-01: "all this
--   data is MONTHS AND MONTHS OLD.. we will reprocess everything when we get it
--   right"). That removes any migration burden, so the temporal model is corrected
--   at the root rather than retrofitted.
--
--   Two defects in the current model are fixed here:
--
--   1. analysis.normalized_record.knowledge_time is DEFAULT NOW() (0003:26), so it
--      records WHEN THE ROW WAS WRITTEN, not when the party learned the fact. It
--      therefore cannot answer "when did you first know X" — the question that
--      actually matters. It is superseded below, not redefined, so old rows keep
--      meaning what they meant.
--
--   2. `disclosure_tier` names two different concepts: a TEXT column with CHECK
--      ('contemporaneous','hindsight','discovered') in 0003:27-28 (a KNOWLEDGE
--      concept) and a TYPE with ('public','restricted','sealed') in 0004:32 (a
--      SENSITIVITY concept). Same identifier, two meanings. This migration adds no
--      third meaning; the knowledge concept moves to the explicit clocks below and
--      the 0003 column becomes derivable rather than authoritative.
--
-- THE SIX CLOCKS (owner design, 2026-08-01) — three families:
--
--   EVENT      occurred_at          when the message was actually sent
--   ARTIFACT   export_created_at    when the backup/export file was generated
--              acquired_at          when the file entered the party's possession
--              ingested_at          when the platform loaded it
--   KNOWLEDGE  realized_at          when the party understood its significance
--              transaction_time     when the DB row was written
--
--   These are independent. A message sent 2023-04 can sit in an export made
--   2024-01, acquired 2024-06, ingested 2026-02, and not be understood until
--   2026-07. Collapsing any pair destroys the as-lived timeline, and with it the
--   ability to show what was believed at the time versus what was true.
--
--   ROUTING RULE: the as-lived memory lane (Graphiti) keys on realized_at. The
--   hindsight/analysis lane keys on occurred_at. The delta between them is a
--   first-class analytical product, not a discrepancy to reconcile.
--
-- Idempotent. Safe to re-run. Never edit after it is applied — add 0009.

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. Acquisition provenance — one row per acquisition EVENT, not per message.
--    Provenance is a property of how an artifact came into the party's hands, so
--    it is stored once per device/export and referenced, never duplicated across
--    every message row.
-- ---------------------------------------------------------------------------

-- How the artifact was obtained. Deliberately generic: it must describe ordinary
-- channels AND household/hand-me-down devices without implying a legal posture.
DO $$ BEGIN
  CREATE TYPE evidence.acquisition_method AS ENUM (
    'own_device',            -- the party's own device
    'household_device',      -- a device within the household (incl. hand-me-down)
    'voluntary_third_party', -- handed over willingly by someone else
    'legal_process',         -- subpoena, court order, formal production
    'public_source',         -- publicly available
    'unknown'
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- The basis on which the party had access. 'unclear' is a FIRST-CLASS value, not a
-- failure state: if every option were a justification, weak provenance would get
-- laundered into a strong-sounding label, which collapses the first time it is
-- tested. Record what is true; let counsel decide how to characterize it.
DO $$ BEGIN
  CREATE TYPE evidence.acquisition_authority AS ENUM (
    'device_owner',
    'parent_guardian',
    'account_holder',
    'consent_given',
    'court_order',
    'unclear'
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS evidence.acquisition (
  id                     UUID PRIMARY KEY DEFAULT uuidv7(),

  method                 evidence.acquisition_method    NOT NULL DEFAULT 'unknown',
  authority              evidence.acquisition_authority NOT NULL DEFAULT 'unclear',

  -- Which physical thing it came off, and who held it.
  source_device          TEXT,            -- free text: make/model/identifier
  device_custodian       TEXT,            -- who owned/used the device
  custody_transferred_at TIMESTAMPTZ,     -- when the device changed hands, if it did

  -- The artifact clock that belongs to the acquisition itself.
  acquired_at            TIMESTAMPTZ,     -- when it entered the party's possession
  export_created_at      TIMESTAMPTZ,     -- when the backup/export was generated;
                                          -- ALSO a completeness bound: an export made
                                          -- at T cannot contain records after T.

  -- The party's own narrative of how this happened. HITL-authored only.
  notes                  TEXT,

  -- Provenance narrative may be work product. Default to withholding; clearing this
  -- flag is a deliberate, reviewed act.
  producible             BOOLEAN NOT NULL DEFAULT FALSE,

  -- Append-only discipline: a changed account of acquisition is a NEW row that
  -- supersedes the old one. Never an UPDATE — a silently edited provenance field is
  -- worth less than a weak one.
  supersedes_id          UUID REFERENCES evidence.acquisition(id),

  -- These fields are never model-inferred. A pipeline cannot know how a device was
  -- obtained; only the party can state it.
  asserted_by            TEXT NOT NULL DEFAULT 'human',
  created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT acquisition_human_only CHECK (asserted_by = 'human')
);

COMMENT ON TABLE evidence.acquisition IS
  'One row per acquisition event (device/export). HITL-authored, append-only, '
  'non-producible by default. Referenced by evidence.source; never duplicated per message.';

CREATE INDEX IF NOT EXISTS idx_acquisition_method    ON evidence.acquisition(method);
CREATE INDEX IF NOT EXISTS idx_acquisition_acquired  ON evidence.acquisition(acquired_at);
CREATE INDEX IF NOT EXISTS idx_acquisition_supersedes ON evidence.acquisition(supersedes_id)
  WHERE supersedes_id IS NOT NULL;

-- Link artifacts to how they were acquired.
ALTER TABLE evidence.source
  ADD COLUMN IF NOT EXISTS acquisition_id UUID REFERENCES evidence.acquisition(id);

CREATE INDEX IF NOT EXISTS idx_source_acquisition ON evidence.source(acquisition_id);

-- ---------------------------------------------------------------------------
-- 1b. Artifact metadata — WIDE, COLD, and deliberately in its own table.
--
--     Kept off evidence.source and evidence.acquisition on purpose: this is a wide,
--     write-once, rarely-joined record. Inlining it would fatten every row on the
--     hot ingest/query path for data that is read during disputes and audits, not
--     during normal work.
--
--     THREE LAYERS, all recorded, none trusted over the others by default —
--     verified against a real export 2026-08-01:
--
--       EMBEDDED    <calls count="445" backup_set="009c4636-..."
--                          backup_date="1764821798190" type="full">
--                   Written by the exporting app. AUTHORITATIVE for export time.
--
--       FILENAME    calls-20251203231638.xml  ->  2025-12-03 23:16:38
--                   Strong corroboration; survives copying, unlike mtime.
--
--       FILESYSTEM  mtime 2025-12-03 23:16:46  ->  ALREADY 8s LATE on an untouched
--                   file, and becomes the transfer date after any OneDrive sync,
--                   R2 upload, or copy. Recorded as an OBSERVATION, never as truth.
--
--     Disagreement between layers is a FINDING, not an error. Seconds of drift is
--     normal; months of drift means the file moved through something and the
--     chain deserves scrutiny.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS evidence.artifact_metadata (
  id               UUID PRIMARY KEY DEFAULT uuidv7(),
  source_id        UUID NOT NULL REFERENCES evidence.source(id),
  acquisition_id   UUID REFERENCES evidence.acquisition(id),

  -- LAYER 1: filesystem. Observed at ingest; weakest evidence.
  fs_original_path TEXT,
  fs_filename      TEXT,
  fs_size_bytes    BIGINT,
  fs_mtime         TIMESTAMPTZ,
  fs_ctime         TIMESTAMPTZ,
  fs_birthtime     TIMESTAMPTZ,   -- often NULL; not all filesystems keep it
  fs_observed_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- LAYER 2: embedded. Format-specific, so JSONB rather than a column per exporter
  -- — iMessage/Facebook/etc. carry entirely different keys. For SMS Backup & Restore
  -- this holds {"backup_date","backup_set","type","count"}.
  embedded         JSONB NOT NULL DEFAULT '{}'::jsonb,

  -- Promoted out of `embedded` because they are cross-format concepts worth
  -- indexing and constraining.
  embedded_export_at TIMESTAMPTZ,  -- e.g. epoch-ms backup_date, decoded
  export_set_id      TEXT,         -- e.g. backup_set UUID — groups sms+calls from one run
  export_kind        TEXT,         -- e.g. 'full' | 'incremental'; completeness fact
  record_count_claimed INT,        -- the exporter's own count; diff vs parsed = QC signal

  -- LAYER 3: derived.
  filename_export_at TIMESTAMPTZ,  -- parsed from the filename convention

  -- Which layer won, and by how much the others disagreed. Written by the resolver
  -- so the decision is auditable rather than implicit.
  resolved_export_at TIMESTAMPTZ,
  resolved_source    TEXT CHECK (resolved_source IN ('embedded','filename','filesystem','manual')),
  layer_disagreement JSONB,        -- {"filename_vs_embedded_s": 0, "fs_vs_embedded_s": 8}

  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE evidence.artifact_metadata IS
  'Wide, cold, one row per artifact. Records filesystem / embedded / derived metadata '
  'layers separately and never collapses them. Precedence for export time: embedded > '
  'filename > filesystem. Filesystem times are observations — they do not survive '
  'copying or cloud sync.';

COMMENT ON COLUMN evidence.artifact_metadata.record_count_claimed IS
  'The exporter''s own record count. Diffing it against rows actually parsed detects '
  'truncated/interrupted exports — sbv currently reads this only to drive a progress '
  'bar and never compares it.';

-- Deliberately sparse indexing: this table is written once and read rarely, so extra
-- indexes would cost ingest throughput for no query benefit.
CREATE INDEX IF NOT EXISTS idx_artmeta_source  ON evidence.artifact_metadata(source_id);
CREATE INDEX IF NOT EXISTS idx_artmeta_set     ON evidence.artifact_metadata(export_set_id)
  WHERE export_set_id IS NOT NULL;

-- ---------------------------------------------------------------------------
-- 2. The missing clocks on normalized_record.
-- ---------------------------------------------------------------------------

ALTER TABLE analysis.normalized_record
  -- ARTIFACT family. Denormalized from evidence.acquisition for query speed on the
  -- hot path; evidence.acquisition remains authoritative.
  ADD COLUMN IF NOT EXISTS export_created_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS acquired_at       TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS ingested_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- KNOWLEDGE family. realized_at is deliberately NULLable with NO default: null
  -- means "not yet established", which is honest. Defaulting it to NOW() would
  -- silently assert knowledge the party did not have — the exact defect in
  -- knowledge_time that this migration exists to correct.
  ADD COLUMN IF NOT EXISTS realized_at       TIMESTAMPTZ,

  -- How realized_at was arrived at, so it is a provenanced fact rather than a bare
  -- assertion. Expected shape:
  --   {"basis":"ai_chat_transcript","ref":"<record_id>","quote":"...","confirmed_by":"human"}
  ADD COLUMN IF NOT EXISTS realized_evidence JSONB,

  ADD COLUMN IF NOT EXISTS acquisition_id    UUID REFERENCES evidence.acquisition(id);

COMMENT ON COLUMN analysis.normalized_record.realized_at IS
  'When the party actually understood the significance. NULL = not yet established. '
  'HITL-confirmed; may be PROPOSED by matching against the AI-chat corpus (which dates '
  'when things were first said out loud) but never auto-committed.';

COMMENT ON COLUMN analysis.normalized_record.knowledge_time IS
  'SUPERSEDED 2026-08-01 by realized_at/acquired_at/ingested_at. Because of its '
  'DEFAULT NOW() this column records row-write time, NOT when the party learned the '
  'fact. Retained so existing rows keep their original meaning. Do not use for '
  '"when did you know" questions.';

CREATE INDEX IF NOT EXISTS idx_normrec_realized  ON analysis.normalized_record(realized_at)
  WHERE realized_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_normrec_acquired  ON analysis.normalized_record(acquired_at);
CREATE INDEX IF NOT EXISTS idx_normrec_acq_fk    ON analysis.normalized_record(acquisition_id);

-- A record cannot be understood before it was sent, nor acquired before it existed.
-- Left as NOT VALID so a reprocess can load first and validate after.
ALTER TABLE analysis.normalized_record
  DROP CONSTRAINT IF EXISTS normrec_clock_ordering;
ALTER TABLE analysis.normalized_record
  ADD CONSTRAINT normrec_clock_ordering CHECK (
    (realized_at IS NULL OR occurred_at IS NULL OR realized_at >= occurred_at)
    AND (acquired_at IS NULL OR occurred_at IS NULL OR acquired_at >= occurred_at)
  ) NOT VALID;

-- ---------------------------------------------------------------------------
-- 2b. Device identity + TIME-SCOPED ownership.
--
--     WHY THIS IS A CORRECTNESS FIX, NOT A CONVENIENCE FIELD:
--     In an SMS Backup & Restore export, a sent message (`type="2"`) carries no
--     sender address — the sender is implicitly "whoever owned the phone". So the
--     device owner IS the speaker attribution for every outbound record.
--
--     On a HAND-ME-DOWN device that assumption silently breaks, and the failure is
--     worse than it first appears. This corpus came off devices that passed through
--     MULTIPLE hands (owner-stated 2026-08-01: originally the opposing party's, then
--     the daughter's, then the case owner's). Outbound messages sent by the OPPOSING
--     PARTY on that device would be attributed to the CHILD who later held it —
--     putting an adult party's statements in a minor's mouth. That error is
--     invisible in the data, survives every hash check (the bytes are untouched),
--     and is fatal under scrutiny.
--
--     Hence: N owners per device, each with a time range, and attribution resolved
--     against occurred_at rather than against whoever holds the device today.
--
--     analysis.device already exists (make_model, os, imei_or_serial,
--     owner_entity_id) but carries a SINGLE, untimed owner. That single column
--     cannot express "my daughter until 2024-03, me after", so ownership moves to
--     its own time-scoped table and the flat column becomes a convenience pointer
--     to the current owner.
-- ---------------------------------------------------------------------------

-- A unique, human-assigned handle for the physical device. HITL/form-required at
-- ingest: make_model alone cannot distinguish two identical phones, and
-- imei_or_serial is frequently unavailable for a device acquired second-hand.
ALTER TABLE analysis.device
  ADD COLUMN IF NOT EXISTS device_label TEXT,
  ADD COLUMN IF NOT EXISTS acquired_note TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS uq_device_label
  ON analysis.device(device_label) WHERE device_label IS NOT NULL;

COMMENT ON COLUMN analysis.device.device_label IS
  'Unique human-assigned device name, e.g. "Daughter iPhone 11 (handed down 2024-03)". '
  'Required via the ingest form / HITL prompt — make_model cannot distinguish two '
  'identical handsets and imei_or_serial is often unknown for second-hand devices.';

COMMENT ON COLUMN analysis.device.owner_entity_id IS
  'CURRENT owner only, kept as a convenience pointer. For any record-level attribution '
  'use analysis.device_ownership, which is time-scoped — a hand-me-down device has '
  'different owners across its history.';

CREATE TABLE IF NOT EXISTS analysis.device_ownership (
  id              UUID PRIMARY KEY DEFAULT uuidv7(),
  device_id       UUID NOT NULL REFERENCES analysis.device(id),
  owner_entity_id UUID NOT NULL REFERENCES analysis.entity(id),

  -- The window during which this entity was the device's user. effective_to NULL
  -- means "still current".
  effective_from  TIMESTAMPTZ NOT NULL,
  effective_to    TIMESTAMPTZ,

  -- Ownership is asserted by a human, never inferred. Nothing in an export states
  -- who held the phone.
  asserted_by     TEXT NOT NULL DEFAULT 'human',
  basis           TEXT,          -- how this is known: purchase, handoff date, testimony
  notes           TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT device_ownership_human_only CHECK (asserted_by = 'human'),
  CONSTRAINT device_ownership_range CHECK (effective_to IS NULL OR effective_to > effective_from)
);

COMMENT ON TABLE analysis.device_ownership IS
  'Time-scoped device ownership. Resolves the implicit sender of outbound messages: '
  'an export attributes sent messages to "me", and "me" is whoever held the device at '
  'occurred_at. HITL-asserted; no export states this.';

CREATE INDEX IF NOT EXISTS idx_devown_device ON analysis.device_ownership(device_id);
CREATE INDEX IF NOT EXISTS idx_devown_owner  ON analysis.device_ownership(owner_entity_id);
CREATE INDEX IF NOT EXISTS idx_devown_range  ON analysis.device_ownership(device_id, effective_from, effective_to);

-- Two owners cannot hold the same device at the same time.
DO $$ BEGIN
  ALTER TABLE analysis.device_ownership
    ADD CONSTRAINT device_ownership_no_overlap
    EXCLUDE USING gist (
      device_id WITH =,
      tstzrange(effective_from, COALESCE(effective_to, 'infinity'::timestamptz)) WITH &&
    );
EXCEPTION WHEN duplicate_object THEN NULL; WHEN duplicate_table THEN NULL; END $$;

-- Link the acquisition event to the actual device record.
ALTER TABLE evidence.acquisition
  ADD COLUMN IF NOT EXISTS device_id UUID REFERENCES analysis.device(id);

-- Hot-path attribution columns. These live on the MAIN record table (not the cold
-- metadata table) because every query that asks "who said this" needs them without
-- a join through acquisition -> artifact -> device.
ALTER TABLE analysis.normalized_record
  ADD COLUMN IF NOT EXISTS device_id        UUID REFERENCES analysis.device(id),
  ADD COLUMN IF NOT EXISTS sender_entity_id UUID REFERENCES analysis.entity(id);

COMMENT ON COLUMN analysis.normalized_record.sender_entity_id IS
  'Resolved sender. For outbound records this is the device owner AT occurred_at per '
  'analysis.device_ownership — NOT the current owner. NULL until resolved; the HITL '
  'identity gate forbids guessing an ambiguous participant.';

CREATE INDEX IF NOT EXISTS idx_normrec_device ON analysis.normalized_record(device_id);
CREATE INDEX IF NOT EXISTS idx_normrec_sender ON analysis.normalized_record(sender_entity_id);

-- Who actually held the device when each record was created. Surfaces mismatches
-- between the stored sender and the ownership timeline instead of hiding them.
CREATE OR REPLACE VIEW analysis.vw_record_sender_resolution AS
SELECT
  r.id                AS record_id,
  r.occurred_at,
  r.role,
  r.device_id,
  d.device_label,
  r.sender_entity_id  AS sender_stored,
  o.owner_entity_id   AS owner_at_occurred_at,
  CASE
    WHEN r.device_id IS NULL             THEN 'no_device'
    WHEN o.owner_entity_id IS NULL       THEN 'no_ownership_record'
    WHEN r.sender_entity_id IS NULL      THEN 'unresolved'
    WHEN r.sender_entity_id = o.owner_entity_id THEN 'consistent'
    ELSE 'MISMATCH'
  END AS attribution_status
FROM analysis.normalized_record r
LEFT JOIN analysis.device d ON d.id = r.device_id
LEFT JOIN analysis.device_ownership o
       ON o.device_id = r.device_id
      AND r.occurred_at >= o.effective_from
      AND (o.effective_to IS NULL OR r.occurred_at < o.effective_to);

COMMENT ON VIEW analysis.vw_record_sender_resolution IS
  'Cross-checks stored sender against the time-scoped ownership timeline. '
  'attribution_status = MISMATCH means an outbound record is attributed to someone '
  'who did not hold the device when it was sent — the hand-me-down failure mode.';

-- ---------------------------------------------------------------------------
-- 3. Entity staging — the scratch lane both knowledge stores consume.
--
--    Extraction is expensive; destinations are cheap to change. Running NER,
--    coreference and relation extraction ONCE into a staging table means the graph
--    backend can change without re-extracting, and it dissolves the standing
--    Graphiti-vs-Semantica deadlock: both become consumers, neither is a rival.
--
--    This table records a CLAIM (what an extractor asserted, with confidence and
--    provenance). It is not the record of truth. Resolved truth lives downstream,
--    after the HITL gate.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS analysis.entity_candidate (
  id                 UUID PRIMARY KEY DEFAULT uuidv7(),

  -- Provenance back to the exact record and its custody hash. Every candidate must
  -- trace to evidence; an untraceable extraction is not usable.
  record_id          UUID REFERENCES analysis.normalized_record(id),
  source_id          UUID REFERENCES evidence.source(id),
  evidence_hash_id   UUID,          -- the H2 row for the record this came from

  -- What was extracted.
  entity_text        TEXT NOT NULL, -- the surface form as it appeared
  entity_type        TEXT,          -- PERSON / ORG / LOCATION / DATE / ...
  normalized_value   TEXT,          -- canonical form, if resolvable
  span_start         INT,
  span_end           INT,

  -- How it was extracted, so a weak method can be re-run without discarding others.
  extractor          TEXT NOT NULL, -- e.g. 'semantica.ner', 'semantica.coref', 'llm'
  extractor_version  TEXT,
  confidence         NUMERIC(5,4) CHECK (confidence IS NULL OR (confidence >= 0 AND confidence <= 1)),

  -- Coreference: which mentions were judged to be the same entity.
  coref_chain_id     TEXT,

  -- Relations/triples get a subject-predicate-object shape so graph edges survive
  -- staging rather than being re-derived downstream.
  relation_predicate TEXT,
  relation_object    TEXT,

  -- The clocks that drive routing. Copied from the source record so a consumer can
  -- filter without a join.
  occurred_at        TIMESTAMPTZ,
  realized_at        TIMESTAMPTZ,

  -- HITL gate. Nothing propagates to any graph until this is 'approved'. Owner rule:
  -- never guess an ambiguous participant — halt and ask.
  review_status      TEXT NOT NULL DEFAULT 'pending'
    CHECK (review_status IN ('pending','approved','rejected','needs_info')),
  reviewed_by        TEXT,
  reviewed_at        TIMESTAMPTZ,
  review_note        TEXT,

  -- Fan-out bookkeeping: which consumers have already taken this candidate.
  -- Prevents double-writes when a new consumer is added later.
  consumed_by        TEXT[] NOT NULL DEFAULT '{}',

  -- Idempotency: re-running extraction must not duplicate. Same record + extractor +
  -- span + surface form = the same candidate.
  dedupe_key         TEXT GENERATED ALWAYS AS (
                       COALESCE(record_id::TEXT,'') || '|' || extractor || '|' ||
                       COALESCE(span_start::TEXT,'') || '|' || COALESCE(span_end::TEXT,'') || '|' ||
                       entity_text
                     ) STORED,

  extracted_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE analysis.entity_candidate IS
  'Staging lane for extracted entities/relations. Records a CLAIM with confidence and '
  'provenance, not resolved truth. Append-only. Nothing propagates to Graphiti or the '
  'evidence graph until review_status = approved.';

CREATE UNIQUE INDEX IF NOT EXISTS uq_entity_candidate_dedupe
  ON analysis.entity_candidate(dedupe_key);
CREATE INDEX IF NOT EXISTS idx_entcand_record   ON analysis.entity_candidate(record_id);
CREATE INDEX IF NOT EXISTS idx_entcand_review   ON analysis.entity_candidate(review_status)
  WHERE review_status = 'pending';
CREATE INDEX IF NOT EXISTS idx_entcand_type     ON analysis.entity_candidate(entity_type);
CREATE INDEX IF NOT EXISTS idx_entcand_coref    ON analysis.entity_candidate(coref_chain_id)
  WHERE coref_chain_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_entcand_realized ON analysis.entity_candidate(realized_at)
  WHERE realized_at IS NOT NULL;
-- Consumers poll this: approved but not yet taken by a given lane.
CREATE INDEX IF NOT EXISTS idx_entcand_consumed ON analysis.entity_candidate USING GIN(consumed_by);

-- Append-only: corrections are new rows, never mutations of the claim itself.
-- Review columns and consumed_by are the only mutable surface.
CREATE OR REPLACE FUNCTION analysis.entity_candidate_no_mutate()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.entity_text  IS DISTINCT FROM OLD.entity_text
     OR NEW.record_id IS DISTINCT FROM OLD.record_id
     OR NEW.extractor IS DISTINCT FROM OLD.extractor
     OR NEW.span_start IS DISTINCT FROM OLD.span_start
     OR NEW.span_end   IS DISTINCT FROM OLD.span_end THEN
    RAISE EXCEPTION
      'analysis.entity_candidate is append-only: insert a new row instead of editing the claim';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_entity_candidate_no_mutate ON analysis.entity_candidate;
CREATE TRIGGER trg_entity_candidate_no_mutate
  BEFORE UPDATE ON analysis.entity_candidate
  FOR EACH ROW EXECUTE FUNCTION analysis.entity_candidate_no_mutate();

-- ---------------------------------------------------------------------------
-- 4. Resolve the `disclosure_tier` name collision.
--
--    The collision is one-sided, so the fix is not a rename of the live concept:
--
--      LIVE      0003:27-28 — analysis.normalized_record.disclosure_tier TEXT
--                CHECK ('contemporaneous','hindsight','discovered'). A KNOWLEDGE
--                concept. Referenced by server/contracts/records.py:54, every
--                messaging parser, server/evidence/store.py and
--                server/api/inspect_routes.py. This one stays exactly as it is.
--
--      ORPHAN    0004:32 — CREATE TYPE disclosure_tier AS ENUM
--                ('public','restricted','sealed'). A SENSITIVITY concept wearing
--                the knowledge concept's name. NO column anywhere uses it, and its
--                own comment mislabels it as "bitemporal knowledge-time gating"
--                while holding sensitivity values. It is the entire source of the
--                ambiguity and it is dead weight.
--
--    Retiring the orphan is safe precisely because nothing depends on it; DROP TYPE
--    without CASCADE will fail loudly rather than silently break a dependency, which
--    is the behaviour we want if that assumption is ever wrong.
-- ---------------------------------------------------------------------------

--    VERIFIED AGAINST THE LIVE DB 2026-08-01: a correctly-named `sensitivity_tier`
--    type ALREADY EXISTS with labels ('public','restricted','sealed') — byte-identical
--    to what 0004 created under the name `disclosure_tier`. It is in real use on ten
--    columns: evidence.source, analysis.artifact_registry, analysis.entity,
--    analysis.normalized_record, analysis.location, analysis.pattern_lexicon,
--    analysis.evidence_item, analysis.review_decision.tier_approved,
--    analysis.export.tier, analysis.vw_court_export.
--
--    So 0004's type was simply a MISNAMED DUPLICATE of an existing, in-use type.
--    Nothing needs to be created here — only the misnamed duplicate removed.

DROP TYPE IF EXISTS public.disclosure_tier;   -- no CASCADE, on purpose

-- ---------------------------------------------------------------------------
-- 5. Make disclosure_tier DERIVED rather than asserted.
--
--    Today every parser hardcodes disclosure_tier='contemporaneous'
--    (facebook_messenger_json.py:103, imessage_txt.py:357, messaging_csv.py:266,
--    and six more). That is a guess made at parse time, before anyone knows when the
--    artifact was acquired or understood — and for a hand-me-down device corpus it is
--    usually wrong.
--
--    With the six clocks present the value is computable, so the view below is
--    authoritative and the stored column degrades to a parse-time hint.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE VIEW analysis.vw_record_disclosure AS
SELECT
  r.id,
  r.occurred_at,
  r.acquired_at,
  r.realized_at,
  r.disclosure_tier AS disclosure_tier_asserted,
  CASE
    -- Not yet established. Honest null beats a confident guess.
    WHEN r.realized_at IS NULL AND r.acquired_at IS NULL THEN NULL
    -- Understood materially later than it happened: the as-lived gap that makes
    -- manipulation visible.
    WHEN r.realized_at IS NOT NULL AND r.occurred_at IS NOT NULL
         AND r.realized_at > r.occurred_at + INTERVAL '30 days' THEN 'hindsight'
    -- Obtained materially later than it happened, understanding aside.
    WHEN r.acquired_at IS NOT NULL AND r.occurred_at IS NOT NULL
         AND r.acquired_at > r.occurred_at + INTERVAL '30 days' THEN 'discovered'
    ELSE 'contemporaneous'
  END AS disclosure_tier_derived,
  -- The gap itself is the analytical product, not a discrepancy to reconcile.
  CASE WHEN r.realized_at IS NOT NULL AND r.occurred_at IS NOT NULL
       THEN r.realized_at - r.occurred_at END AS realization_lag
FROM analysis.normalized_record r;

COMMENT ON VIEW analysis.vw_record_disclosure IS
  'Authoritative disclosure tier, derived from the clocks. disclosure_tier_asserted is '
  'the parse-time hint (parsers hardcode contemporaneous and cannot know better). '
  'realization_lag = realized_at - occurred_at is the as-lived gap.';

COMMIT;
