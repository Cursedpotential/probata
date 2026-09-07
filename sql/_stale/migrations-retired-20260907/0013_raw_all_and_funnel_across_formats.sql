-- 0013_raw_all_and_funnel_across_formats.sql
--
-- Byline: Claude Code . Opus 5 (1M) . 2026-08-01
--
-- Found by reading the first generated pipeline report rather than by testing.
--
-- evidence.vw_pipeline_funnel (0012) counted raw rows from evidence.raw_sms ONLY.
-- For the three chat_export artifacts already in evidence.source it therefore
-- reported "0 raw rows" - which is currently true, but true by accident. The
-- moment an iMessage, Facebook, or AI-chat export is ingested, the funnel would
-- report zero raw rows for it and the reconciliation view would call it a
-- SHORTFALL. A report that cries wolf on correct data is worse than no report.
--
-- Fix: one union view over every per-format raw table, and a funnel that reads it.
--
-- The union is the only place the six raw tables are treated as one thing. They
-- are deliberately separate tables (per-format columns, per-format dedup) but
-- "how many raw records exist for this artifact" is a cross-format question.
--
-- Idempotent. Percent-free. Never edit after apply - add 0014.

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. Every raw row, whatever format it arrived in.
--
--    Only the columns all six share. Anything format-specific stays in its own
--    table - this view is for counting and lineage, not for reading payloads.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE VIEW evidence.vw_raw_all AS
SELECT 'evidence.raw_sms'::TEXT AS raw_table, id, source_id, device_id, acquisition_id,
       medium, record_index, content_hash, parser_version, superseded_by, ingested_at
  FROM evidence.raw_sms
UNION ALL
SELECT 'evidence.raw_imessage', id, source_id, device_id, acquisition_id,
       medium, record_index, content_hash, parser_version, superseded_by, ingested_at
  FROM evidence.raw_imessage
UNION ALL
SELECT 'evidence.raw_facebook', id, source_id, device_id, acquisition_id,
       medium, record_index, content_hash, parser_version, superseded_by, ingested_at
  FROM evidence.raw_facebook
UNION ALL
SELECT 'evidence.raw_ai_chat', id, source_id, device_id, acquisition_id,
       medium, record_index, content_hash, parser_version, superseded_by, ingested_at
  FROM evidence.raw_ai_chat
UNION ALL
SELECT 'evidence.raw_csv', id, source_id, device_id, acquisition_id,
       medium, record_index, content_hash, parser_version, superseded_by, ingested_at
  FROM evidence.raw_csv
UNION ALL
SELECT 'evidence.raw_phone', id, source_id, device_id, acquisition_id,
       medium, record_index, content_hash, parser_version, superseded_by, ingested_at
  FROM evidence.raw_phone;

COMMENT ON VIEW evidence.vw_raw_all IS
  'Every raw row across all six per-format raw tables, restricted to the columns '
  'they share. The tables stay separate on purpose; this view exists because '
  '"how many raw records does this artifact have" is a cross-format question.';

-- ---------------------------------------------------------------------------
-- 2. Funnel, rebuilt on the union. Column list changes, so DROP then CREATE -
--    CREATE OR REPLACE cannot change a view's shape.
--    vw_reconciliation depends on it, so it is dropped and rebuilt too.
-- ---------------------------------------------------------------------------

DROP VIEW IF EXISTS evidence.vw_reconciliation;
DROP VIEW IF EXISTS evidence.vw_pipeline_funnel;

CREATE VIEW evidence.vw_pipeline_funnel AS
SELECT
  s.id                     AS source_id,
  s.original_filename,
  s.source_type,
  s.byte_size,
  encode(s.sha256, 'hex')  AS h1,
  am.record_count_claimed  AS claimed,
  (SELECT count(*) FROM evidence.vw_raw_all r WHERE r.source_id = s.id)      AS raw_rows,
  (SELECT count(DISTINCT r.raw_table) FROM evidence.vw_raw_all r
    WHERE r.source_id = s.id)                                                AS raw_tables_used,
  (SELECT count(*) FROM evidence.vw_raw_all r
    WHERE r.source_id = s.id AND r.superseded_by IS NOT NULL)                AS raw_superseded,
  (SELECT count(*) FROM evidence.raw_rejected j
    WHERE j.source_sha256 = s.sha256)                                        AS rejected,
  (SELECT count(*) FROM analysis.normalized_record nr
     JOIN evidence.vw_raw_all r ON r.id = nr.derived_from_raw_id
    WHERE r.source_id = s.id)                                                AS spine_rows,
  (SELECT count(*) FROM analysis.event_source_record e
    WHERE e.source_id = s.id)                                                AS attestations,
  am.resolved_export_at,
  am.layer_disagreement,
  s.ingested_at
FROM evidence.source s
LEFT JOIN evidence.artifact_metadata am ON am.source_id = s.id;

COMMENT ON VIEW evidence.vw_pipeline_funnel IS
  'Per artifact and across ALL raw formats: what it claimed, what landed in raw, '
  'what was rejected, what was derived to the spine, and how many attestations '
  'exist. claimed = raw_rows + rejected is the reconciliation.';

CREATE VIEW evidence.vw_reconciliation AS
SELECT
  f.source_id,
  f.original_filename,
  f.claimed,
  f.raw_rows,
  f.rejected,
  f.spine_rows,
  (f.raw_rows + f.rejected)                            AS accounted_for,
  (COALESCE(f.claimed, 0) - (f.raw_rows + f.rejected)) AS unexplained,
  CASE
    WHEN f.claimed IS NULL                   THEN 'NO CLAIM RECORDED'
    WHEN f.claimed = f.raw_rows + f.rejected THEN 'RECONCILED'
    WHEN f.claimed > f.raw_rows + f.rejected THEN 'SHORTFALL - records unaccounted for'
    ELSE                                          'SURPLUS - more records than the artifact claims'
  END                                                  AS verdict,
  CASE
    WHEN f.spine_rows = f.raw_rows THEN 'derived'
    WHEN f.spine_rows < f.raw_rows THEN 'UNDER-DERIVED'
    ELSE                                'OVER-DERIVED - duplicate derivation'
  END                                                  AS derivation_verdict
FROM evidence.vw_pipeline_funnel f;

COMMENT ON VIEW evidence.vw_reconciliation IS
  'One verdict per artifact. RECONCILED means every record the artifact claims is '
  'either in raw or explicitly recorded as rejected. NO CLAIM RECORDED means the '
  'artifact never had its self-declared count captured - the reconciliation cannot '
  'be performed at all, which is a gap, not a pass.';

-- ---------------------------------------------------------------------------
-- 3. Lineage across formats too, for the same reason.
-- ---------------------------------------------------------------------------

DROP VIEW IF EXISTS analysis.vw_derivation_lineage;

CREATE VIEW analysis.vw_derivation_lineage AS
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
LEFT JOIN evidence.vw_raw_all r ON r.id = nr.derived_from_raw_id
LEFT JOIN evidence.source     s ON s.id = r.source_id
LEFT JOIN evidence.acquisition a ON a.id = nr.acquisition_id;

COMMENT ON VIEW analysis.vw_derivation_lineage IS
  'Every spine record traced back to the raw row it came from, whatever format '
  'that was, the artifact it came from, and how that artifact was acquired. A '
  'record with a NULL raw_id has no lineage and should not exist.';

-- ---------------------------------------------------------------------------
-- 4. Artifacts whose self-declared count was never captured.
--
--    The 0012 integrity check looked for NULL record_count_claimed in
--    artifact_metadata, which misses the worse case entirely: an artifact with NO
--    artifact_metadata row at all. Three such artifacts already exist. Recording
--    what a source claims about itself is the one control that catches silent
--    record loss, so its ABSENCE has to be visible.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE VIEW evidence.vw_artifacts_without_claim AS
SELECT s.id AS source_id, s.original_filename, s.source_type, s.byte_size,
       s.ingested_at,
       (am.source_id IS NOT NULL) AS has_metadata_row,
       (SELECT count(*) FROM evidence.vw_raw_all r WHERE r.source_id = s.id) AS raw_rows
FROM evidence.source s
LEFT JOIN evidence.artifact_metadata am ON am.source_id = s.id
WHERE am.source_id IS NULL OR am.record_count_claimed IS NULL;

COMMENT ON VIEW evidence.vw_artifacts_without_claim IS
  'Artifacts that cannot be reconciled because nothing recorded what they claim '
  'about themselves - either no artifact_metadata row exists, or its '
  'record_count_claimed is NULL. Every row here is a blind spot.';

COMMIT;
