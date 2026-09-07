-- 0015_layer_map_after_schema_split.sql
--
-- Byline: Claude Code . Opus 5 (1M) . 2026-08-02
--
-- evidence.vw_layer_map (0012) lists each layer's table name as a literal STRING.
-- ALTER TABLE ... SET SCHEMA moved the tables and every view's parse tree followed
-- automatically - but a string literal is not a reference, so the map kept
-- displaying `analysis.message` for a table that now lives in `working`. The view
-- returned correct COUNTS against wrong NAMES, which is the worst kind of wrong: it
-- looks right.
--
-- Rebuilt here against the four schemas 0014 established, and extended with the
-- rebuild-cost column, because that is the property that actually distinguishes
-- the layers (owner correction 2026-08-02: everything is rebuildable as long as
-- the original files survive - what differs is whether the rebuild has to go back
-- to them).
--
-- Idempotent. Percent-free. Never edit after apply - add 0016.

BEGIN;

-- Column list changes (rebuild_cost is new), and CREATE OR REPLACE cannot
-- change a view's shape - it rejects the rename rather than guessing.
DROP VIEW IF EXISTS evidence.vw_layer_map;

CREATE VIEW evidence.vw_layer_map AS
SELECT * FROM (
  VALUES
    (10,'RAW',       'evidence.raw_sms',              're-parse originals','SMS/MMS/call export records',      (SELECT count(*) FROM evidence.raw_sms)),
    (11,'RAW',       'evidence.raw_imessage',         're-parse originals','iMessage export records',          (SELECT count(*) FROM evidence.raw_imessage)),
    (12,'RAW',       'evidence.raw_facebook',         're-parse originals','Facebook/Messenger records',       (SELECT count(*) FROM evidence.raw_facebook)),
    (13,'RAW',       'evidence.raw_ai_chat',          're-parse originals','AI chat transcript records',       (SELECT count(*) FROM evidence.raw_ai_chat)),
    (14,'RAW',       'evidence.raw_csv',              're-parse originals','Tabular export records',           (SELECT count(*) FROM evidence.raw_csv)),
    (15,'RAW',       'evidence.raw_phone',            're-parse originals','Phone/device log records',         (SELECT count(*) FROM evidence.raw_phone)),

    (20,'SPINE',     'working.normalized_record',     're-derive from raw','One row per real-world record',    (SELECT count(*) FROM working.normalized_record)),
    (30,'PROJECTION','working.message',               're-derive from raw','Message view of the spine',        (SELECT count(*) FROM working.message)),
    (31,'PROJECTION','working.message_participant',   're-derive from raw','Per-message participants',         (SELECT count(*) FROM working.message_participant)),
    (32,'PROJECTION','working.conversation',          're-derive from raw','Conversation groupings',           (SELECT count(*) FROM working.conversation)),
    (33,'PROJECTION','working.attachment',            're-derive from raw','Attachments',                      (SELECT count(*) FROM working.attachment)),
    (34,'PROJECTION','working.call_log',              're-derive from raw','Call records',                     (SELECT count(*) FROM working.call_log)),
    (40,'LINK',      'working.event_source_record',   're-derive from raw','Attestations + event citations',   (SELECT count(*) FROM working.event_source_record)),
    (41,'ENTITY',    'working.entity',                're-run extraction', 'Resolved entities',                (SELECT count(*) FROM working.entity)),
    (42,'ENTITY',    'working.person',                're-run extraction', 'Resolved people',                  (SELECT count(*) FROM working.person)),
    (43,'ENTITY',    'working.device',                'HITL + extraction', 'Devices',                          (SELECT count(*) FROM working.device)),
    (50,'STAGING',   'working.extraction_candidate',  're-run extraction', 'Extraction output, pre-gate',      (SELECT count(*) FROM working.extraction_candidate)),
    (51,'STAGING',   'working.record_observation',    're-run observers',  'Model/human observations',         (SELECT count(*) FROM working.record_observation)),

    (60,'REFERENCE', 'reference.detection_pattern',   're-seed from source','Detection patterns',              (SELECT count(*) FROM reference.detection_pattern)),
    (61,'REFERENCE', 'reference.behavior_category',   're-seed from source','Behaviour taxonomy',              (SELECT count(*) FROM reference.behavior_category)),
    (62,'REFERENCE', 'reference.behavior_category_mcl','re-seed from source','MCL 722.23 factor mapping',      (SELECT count(*) FROM reference.behavior_category_mcl)),
    (63,'REFERENCE', 'reference.pattern_lexicon',     're-seed from source','Imported lexicons',               (SELECT count(*) FROM reference.pattern_lexicon)),
    (64,'REFERENCE', 'reference.custody_factor',      're-seed from source','Custody factors',                 (SELECT count(*) FROM reference.custody_factor)),
    (65,'REFERENCE', 'reference.topic_code',          're-seed from source','Topic codes',                     (SELECT count(*) FROM reference.topic_code)),

    (70,'FINDING',   'analysis.finding',              'not rebuildable',   'Reviewed findings',                (SELECT count(*) FROM analysis.finding)),
    (71,'FINDING',   'analysis.pattern_finding',      're-run detection',  'Pattern hits',                     (SELECT count(*) FROM analysis.pattern_finding)),
    (72,'FINDING',   'analysis.timeline_event',       'HITL-gated',        'Timeline events',                  (SELECT count(*) FROM analysis.timeline_event)),
    (73,'FINDING',   'analysis.review_decision',      'not rebuildable',   'Human review decisions',           (SELECT count(*) FROM analysis.review_decision)),
    (80,'GOLD',      'analysis.human_label_gold',     'not rebuildable',   'Hand-labelled gold set (FK-free)', (SELECT count(*) FROM analysis.human_label_gold)),

    (90,'LEDGER',    'evidence.source',               'append-only',       'Artifacts ingested (per file)',    (SELECT count(*) FROM evidence.source)),
    (91,'LEDGER',    'evidence.acquisition',          'append-only',       'How evidence was acquired',        (SELECT count(*) FROM evidence.acquisition)),
    (92,'LEDGER',    'evidence.artifact_metadata',    'append-only',       'File + embedded metadata',         (SELECT count(*) FROM evidence.artifact_metadata)),
    (93,'LEDGER',    'evidence.evidence_hash',        'append-only',       'Custody hashes (H1/H2/H3)',        (SELECT count(*) FROM evidence.evidence_hash)),
    (94,'LEDGER',    'evidence.ingest_run',           'append-only',       'Ingest attempts incl. failures',   (SELECT count(*) FROM evidence.ingest_run)),
    (95,'REJECTED',  'evidence.raw_rejected',         'append-only',       'Records a parser refused',         (SELECT count(*) FROM evidence.raw_rejected)),

    (99,'OPS',       'ops.workflow_run',              'prunable',          'Workflow run ledger',              (SELECT count(*) FROM ops.workflow_run)),
    (100,'OPS',      'ops.processing_run',            'prunable',          'Processing runs',                  (SELECT count(*) FROM ops.processing_run)),
    (101,'OPS',      'ops.tool_call_ledger',          'prunable',          'Tool-call log',                    (SELECT count(*) FROM ops.tool_call_ledger))
) AS t(sort_order, layer_role, table_name, rebuild_cost, what_it_holds, live_rows);

COMMENT ON VIEW evidence.vw_layer_map IS
  'Every layer with its architectural role, live row count, and REBUILD COST - the '
  'property that actually separates the layers. RAW rebuild means re-parsing the '
  'original files; working rebuild reads RAW only; reference is re-seeded, not '
  'derived; findings and human labels are not rebuildable at all.';

COMMIT;
