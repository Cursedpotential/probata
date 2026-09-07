-- 0012_pipeline_visibility.sql
--
-- Byline: Claude Code . Opus 5 (1M) . 2026-08-01
--
-- WHY THIS EXISTS
--
-- On 2026-08-01 a parser silently discarded 516 of 7,815 MMS from a real export.
-- Nothing recorded the loss. The only reason it was ever found is that
-- evidence.artifact_metadata.record_count_claimed had stored what the file said
-- about itself, and somebody happened to compare.
--
-- That is not a control. A pipeline that can lose evidence without leaving a trace
-- is not auditable, and an evidence pipeline that is not auditable is worthless in
-- front of a court. Every stage must be countable, every rejection must be stored,
-- and every run must leave a ledger row whether it succeeded or not.
--
-- This migration adds the two missing tables and the views that read them.
--
--   evidence.ingest_run    one row per ingest ATTEMPT, including failures
--   evidence.raw_rejected  every record a parser refused, with the reason and the
--                          verbatim element - so "dropped" becomes a queryable
--                          population instead of an absence
--
-- Both are written OUTSIDE the ingest transaction. A rolled-back load must still
-- leave evidence that it was attempted and why it failed; a ledger that vanishes
-- with the rollback records only successes, which is the opposite of an audit log.
--
-- Idempotent. Percent-free. Never edit after apply - add 0013.

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. INGEST RUN LEDGER
--
--    The funnel, one column per stage, so a shortfall is arithmetic rather than
--    a judgement call:
--
--      claimed -> parsed -> rejected/deduped -> raw -> spine -> attestations
--
--    claimed is what the artifact asserts about itself. It is NOT authoritative -
--    an export can lie or be truncated - but a disagreement is always a finding.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS evidence.ingest_run (
  id               UUID PRIMARY KEY DEFAULT uuidv7(),

  -- Identity of the artifact is its H1, not its filename. Recorded even when the
  -- run fails before evidence.source exists, which is why sha256 is NOT NULL and
  -- source_id is nullable.
  source_id        UUID REFERENCES evidence.source(id),
  source_sha256    BYTEA NOT NULL CHECK (octet_length(source_sha256) = 32),
  source_filename  TEXT NOT NULL,
  source_bytes     BIGINT,

  parser           TEXT NOT NULL,
  parser_version   TEXT NOT NULL,
  deriver_version  TEXT,
  raw_table        TEXT,
  runner           TEXT NOT NULL,

  started_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  finished_at      TIMESTAMPTZ,
  status           TEXT NOT NULL DEFAULT 'running'
                   CHECK (status IN ('running','committed','rolled_back','failed')),
  outcome_detail   TEXT,

  -- The funnel. NULL means "not reached", 0 means "reached and empty" - a
  -- distinction that matters when reading a failed run.
  count_claimed      BIGINT,
  count_parsed       BIGINT,
  count_rejected     BIGINT,
  count_deduped      BIGINT,
  count_raw          BIGINT,
  count_spine        BIGINT,
  count_attestations BIGINT,

  notes            JSONB NOT NULL DEFAULT '{}'
                   CHECK (jsonb_typeof(notes) = 'object')
);

COMMENT ON TABLE evidence.ingest_run IS
  'One row per ingest ATTEMPT, written outside the ingest transaction so failed and '
  'rolled-back runs survive. The count_* columns are the funnel: claimed -> parsed '
  '-> rejected/deduped -> raw -> spine -> attestations. Added 2026-08-01 after a '
  'parser dropped 516 records with no trace.';

COMMENT ON COLUMN evidence.ingest_run.count_claimed IS
  'What the artifact asserts about itself (e.g. the count attribute on an SMS '
  'Backup and Restore root element). Not authoritative - an export can be '
  'truncated or lie - but any disagreement with count_parsed is a finding.';

COMMENT ON COLUMN evidence.ingest_run.status IS
  'running | committed | rolled_back | failed. A rolled_back row is the record '
  'that a load was attempted and refused; it is not noise, it is the audit trail.';

CREATE INDEX IF NOT EXISTS idx_ingest_run_source  ON evidence.ingest_run(source_id);
CREATE INDEX IF NOT EXISTS idx_ingest_run_sha     ON evidence.ingest_run(source_sha256);
CREATE INDEX IF NOT EXISTS idx_ingest_run_started ON evidence.ingest_run(started_at DESC);
CREATE INDEX IF NOT EXISTS idx_ingest_run_open    ON evidence.ingest_run(status)
  WHERE status IN ('running','failed','rolled_back');

-- ---------------------------------------------------------------------------
-- 2. REJECTED RECORDS
--
--    "What was dropped" cannot be answered by querying the raw layer, because a
--    dropped record is precisely the thing that is not there. It has to be
--    written down at the moment of refusal or it is gone.
--
--    ON DELETE RESTRICT on the run FK: never-delete applies here too.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS evidence.raw_rejected (
  id             UUID PRIMARY KEY DEFAULT uuidv7(),
  ingest_run_id  UUID NOT NULL REFERENCES evidence.ingest_run(id) ON DELETE RESTRICT,
  source_sha256  BYTEA NOT NULL CHECK (octet_length(source_sha256) = 32),

  record_index   BIGINT,
  element_tag    TEXT,

  reason         TEXT NOT NULL CHECK (reason IN (
                   'no_timestamp_no_counterparty',  -- unusable: nothing to anchor it to
                   'dedup_duplicate_in_source',     -- collapsed onto an identical row
                   'parser_returned_none',          -- parser refused, cause unclassified
                   'unmapped_element',              -- element type the parser has no map for
                   'malformed',                     -- could not be parsed at all
                   'operator_excluded')),           -- a human excluded it, with a note
  reason_detail  TEXT,

  content_hash   TEXT,
  raw            JSONB NOT NULL,   -- verbatim element, payload-free (no base64 blobs)

  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE evidence.raw_rejected IS
  'Every record a parser refused, stored verbatim with the reason. A dropped '
  'record is an absence and cannot be queried after the fact - it must be written '
  'at the moment of refusal. dedup_duplicate_in_source rows are the losing side of '
  'a raw dedup collapse and are how "raw < parsed" is PROVEN rather than assumed.';

CREATE INDEX IF NOT EXISTS idx_raw_rejected_run    ON evidence.raw_rejected(ingest_run_id);
CREATE INDEX IF NOT EXISTS idx_raw_rejected_sha    ON evidence.raw_rejected(source_sha256);
CREATE INDEX IF NOT EXISTS idx_raw_rejected_reason ON evidence.raw_rejected(reason);
CREATE INDEX IF NOT EXISTS idx_raw_rejected_gin    ON evidence.raw_rejected USING GIN (raw);

-- ---------------------------------------------------------------------------
-- 3. LAYER MAP - "what is raw, what is spine, what is derived", with live counts
--
--    The architecture in one queryable place. layer_role is the contract:
--      RAW        the only insert target, verbatim, never edited
--      SPINE      one row per real-world record, the join point, DERIVED
--      PROJECTION rebuildable for one domain, never authoritative
--      LEDGER     provenance and audit, not evidence content
-- ---------------------------------------------------------------------------

CREATE OR REPLACE VIEW evidence.vw_layer_map AS
SELECT * FROM (
  VALUES
    (10, 'RAW',        'evidence.raw_sms',                   'SMS/MMS/call export records',        (SELECT count(*) FROM evidence.raw_sms)),
    (11, 'RAW',        'evidence.raw_imessage',              'iMessage export records',            (SELECT count(*) FROM evidence.raw_imessage)),
    (12, 'RAW',        'evidence.raw_facebook',              'Facebook/Messenger export records',  (SELECT count(*) FROM evidence.raw_facebook)),
    (13, 'RAW',        'evidence.raw_ai_chat',               'AI chat transcript records',         (SELECT count(*) FROM evidence.raw_ai_chat)),
    (14, 'RAW',        'evidence.raw_csv',                   'Tabular export records',             (SELECT count(*) FROM evidence.raw_csv)),
    (15, 'RAW',        'evidence.raw_phone',                 'Phone/device log records',           (SELECT count(*) FROM evidence.raw_phone)),
    (20, 'SPINE',      'analysis.normalized_record',         'One row per real-world record',      (SELECT count(*) FROM analysis.normalized_record)),
    (30, 'PROJECTION', 'analysis.message',                   'Message view of the spine',          (SELECT count(*) FROM analysis.message)),
    (31, 'PROJECTION', 'analysis.message_participant',       'Per-message participants',           (SELECT count(*) FROM analysis.message_participant)),
    (32, 'PROJECTION', 'analysis.conversation',              'Conversation groupings',             (SELECT count(*) FROM analysis.conversation)),
    (33, 'PROJECTION', 'analysis.attachment',                'Attachments',                        (SELECT count(*) FROM analysis.attachment)),
    (40, 'LINK',       'analysis.event_source_record',       'Attestations + event citations',     (SELECT count(*) FROM analysis.event_source_record)),
    (41, 'LINK',       'analysis.timeline_event',            'Timeline events (post-HITL)',        (SELECT count(*) FROM analysis.timeline_event)),
    (50, 'STAGING',    'analysis.extraction_candidate',      'Extraction candidates, pre-gate',    (SELECT count(*) FROM analysis.extraction_candidate)),
    (51, 'STAGING',    'analysis.record_observation',        'Model/human observations',           (SELECT count(*) FROM analysis.record_observation)),
    (60, 'LEDGER',     'evidence.source',                    'Artifacts ingested (per file)',      (SELECT count(*) FROM evidence.source)),
    (61, 'LEDGER',     'evidence.acquisition',               'How evidence was acquired (per event)', (SELECT count(*) FROM evidence.acquisition)),
    (62, 'LEDGER',     'evidence.artifact_metadata',         'Wide/cold file + embedded metadata',  (SELECT count(*) FROM evidence.artifact_metadata)),
    (63, 'LEDGER',     'evidence.evidence_hash',             'Custody hashes (H1/H2/H3)',          (SELECT count(*) FROM evidence.evidence_hash)),
    (64, 'LEDGER',     'evidence.ingest_run',                'Ingest attempts incl. failures',     (SELECT count(*) FROM evidence.ingest_run)),
    (70, 'REJECTED',   'evidence.raw_rejected',              'Records a parser refused',           (SELECT count(*) FROM evidence.raw_rejected)),
    (80, 'GOLD',       'analysis.human_label_gold',          'Hand-labelled gold set (FK-free)',   (SELECT count(*) FROM analysis.human_label_gold))
) AS t(sort_order, layer_role, table_name, what_it_holds, live_rows);

COMMENT ON VIEW evidence.vw_layer_map IS
  'Every layer of the evidence pipeline with its architectural role and live row '
  'count. RAW is the only insert target; SPINE and PROJECTION are derived and '
  'rebuildable; REJECTED is what never made it in.';

-- ---------------------------------------------------------------------------
-- 4. PER-SOURCE FUNNEL - every stage for every artifact, side by side
-- ---------------------------------------------------------------------------

CREATE OR REPLACE VIEW evidence.vw_pipeline_funnel AS
SELECT
  s.id                                   AS source_id,
  s.original_filename,
  s.source_type,
  s.byte_size,
  encode(s.sha256, 'hex')                AS h1,
  am.record_count_claimed                AS claimed,
  (SELECT count(*) FROM evidence.raw_sms r WHERE r.source_id = s.id)          AS raw_rows,
  (SELECT count(*) FROM evidence.raw_sms r
    WHERE r.source_id = s.id AND r.superseded_by IS NOT NULL)                 AS raw_superseded,
  (SELECT count(*) FROM evidence.raw_rejected j WHERE j.source_sha256 = s.sha256) AS rejected,
  (SELECT count(*) FROM analysis.normalized_record nr
     JOIN evidence.raw_sms r ON r.id = nr.derived_from_raw_id
    WHERE r.source_id = s.id)                                                 AS spine_rows,
  (SELECT count(*) FROM analysis.event_source_record e WHERE e.source_id = s.id) AS attestations,
  am.resolved_export_at,
  am.layer_disagreement,
  s.ingested_at
FROM evidence.source s
LEFT JOIN evidence.artifact_metadata am ON am.source_id = s.id;

COMMENT ON VIEW evidence.vw_pipeline_funnel IS
  'Per artifact: what it claimed, what landed in raw, what was rejected, what was '
  'derived to the spine, and how many attestations exist. Read claimed vs raw '
  'together with rejected - claimed = raw + rejected is the reconciliation.';

-- ---------------------------------------------------------------------------
-- 5. RECONCILIATION - one verdict per artifact, no interpretation required
-- ---------------------------------------------------------------------------

CREATE OR REPLACE VIEW evidence.vw_reconciliation AS
SELECT
  f.source_id,
  f.original_filename,
  f.claimed,
  f.raw_rows,
  f.rejected,
  f.spine_rows,
  (f.raw_rows + f.rejected)                       AS accounted_for,
  (COALESCE(f.claimed, 0) - (f.raw_rows + f.rejected)) AS unexplained,
  CASE
    WHEN f.claimed IS NULL                                    THEN 'NO CLAIM RECORDED'
    WHEN f.claimed = f.raw_rows + f.rejected                  THEN 'RECONCILED'
    WHEN f.claimed > f.raw_rows + f.rejected                  THEN 'SHORTFALL - records unaccounted for'
    ELSE                                                           'SURPLUS - more records than the artifact claims'
  END                                             AS verdict,
  CASE
    WHEN f.spine_rows = f.raw_rows THEN 'derived'
    WHEN f.spine_rows < f.raw_rows THEN 'UNDER-DERIVED'
    ELSE                                'OVER-DERIVED - duplicate derivation'
  END                                             AS derivation_verdict
FROM evidence.vw_pipeline_funnel f;

COMMENT ON VIEW evidence.vw_reconciliation IS
  'One verdict per artifact. RECONCILED means every record the artifact claims is '
  'either in raw or explicitly recorded as rejected. SHORTFALL means records went '
  'missing with no trace - the exact failure this schema exists to make impossible.';

-- ---------------------------------------------------------------------------
-- 6. DROPPED RECORDS - the population that used to be an absence
-- ---------------------------------------------------------------------------

CREATE OR REPLACE VIEW evidence.vw_dropped_records AS
SELECT
  j.id                       AS rejected_id,
  encode(j.source_sha256, 'hex') AS h1,
  s.original_filename,
  ir.parser,
  ir.parser_version,
  ir.status                  AS run_status,
  j.record_index,
  j.element_tag,
  j.reason,
  j.reason_detail,
  j.content_hash,
  j.raw,
  j.created_at
FROM evidence.raw_rejected j
JOIN evidence.ingest_run ir ON ir.id = j.ingest_run_id
LEFT JOIN evidence.source s ON s.sha256 = j.source_sha256;

COMMENT ON VIEW evidence.vw_dropped_records IS
  'Everything a parser refused, joined to the run that refused it. An empty result '
  'means nothing was dropped - which is only believable if vw_reconciliation also '
  'says RECONCILED.';

-- ---------------------------------------------------------------------------
-- 7. DERIVATION LINEAGE - spine row back to raw, artifact, and acquisition
-- ---------------------------------------------------------------------------

CREATE OR REPLACE VIEW analysis.vw_derivation_lineage AS
SELECT
  nr.id                     AS record_id,
  nr.record_type,
  nr.occurred_at,
  left(nr.content, 120)     AS content_preview,
  nr.derived_from_raw_table AS raw_table,
  nr.derived_from_raw_id    AS raw_id,
  nr.deriver_version,
  nr.derived_at,
  r.parser_version,
  r.record_index,
  r.content_hash,
  r.superseded_by           AS raw_superseded_by,
  s.id                      AS source_id,
  s.original_filename,
  encode(s.sha256, 'hex')   AS h1,
  a.id                      AS acquisition_id,
  a.method                  AS acquisition_method,
  a.authority               AS acquisition_authority,
  nr.acquired_at,
  nr.export_created_at,
  nr.ingested_at
FROM analysis.normalized_record nr
LEFT JOIN evidence.raw_sms   r ON r.id = nr.derived_from_raw_id
LEFT JOIN evidence.source    s ON s.id = r.source_id
LEFT JOIN evidence.acquisition a ON a.id = nr.acquisition_id;

COMMENT ON VIEW analysis.vw_derivation_lineage IS
  'Every spine record traced back to the raw row it came from, the artifact that '
  'raw row came from, and how that artifact was acquired. A record with a NULL '
  'raw_id has no lineage and should not exist.';

-- ---------------------------------------------------------------------------
-- 8. INGEST HISTORY - the run ledger, most recent first
-- ---------------------------------------------------------------------------

CREATE OR REPLACE VIEW evidence.vw_ingest_history AS
SELECT
  ir.id AS run_id,
  ir.source_filename,
  ir.status,
  ir.parser,
  ir.parser_version,
  ir.runner,
  ir.started_at,
  ir.finished_at,
  EXTRACT(EPOCH FROM (ir.finished_at - ir.started_at))::BIGINT AS duration_s,
  ir.count_claimed,
  ir.count_parsed,
  ir.count_rejected,
  ir.count_deduped,
  ir.count_raw,
  ir.count_spine,
  ir.count_attestations,
  (COALESCE(ir.count_claimed, 0) - COALESCE(ir.count_parsed, 0)) AS claimed_minus_parsed,
  ir.outcome_detail,
  ir.notes
FROM evidence.ingest_run ir
ORDER BY ir.started_at DESC;

COMMENT ON VIEW evidence.vw_ingest_history IS
  'Every ingest attempt including failures and rollbacks. A rolled_back row with a '
  'populated funnel is the most useful diagnostic in the system: it shows exactly '
  'which stage stopped agreeing.';

COMMIT;
