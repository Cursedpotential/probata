-- 0014_split_analysis_into_working_reference_ops.sql
--
-- Byline: Claude Code . Opus 5 (1M) . 2026-08-02
--
-- Owner ruling 2026-08-02: "the second level of tables, the spine and the
-- projection - I don't like the analysis prefix, it's more working, just be like
-- working prefix."
--
-- The rename exposed a bigger problem than the name. `analysis` held FOUR
-- unrelated concepts in one bucket, and no name could have been right for all of
-- them:
--
--   working    derived from evidence. Re-derivable WITHOUT going back to the
--              original files: spine, projections, links, staging, resolved
--              entities and places.
--   reference  hand-curated taxonomy and config. Not derived from anything, not a
--              conclusion about the case: detection patterns, behaviour
--              categories, MCL factors, lexicons, topic codes, score bands.
--   analysis   conclusions. Findings, assertions, scores, review decisions,
--              ground-truth labels, and the litigation work product built on them.
--   ops        plumbing. Run ledgers and tool-call logs. Not evidence, not
--              analysis, and subject to a retention policy the others must never
--              have.
--
-- REBUILD COST is the real axis, not "rebuildable vs not" (owner correction,
-- 2026-08-02: "everything can be rebuilt as long as we have the raw data or the
-- original binary - it's just the derivatives that would have to be re-derived"):
--
--   evidence   rebuild requires re-parsing the ORIGINAL files
--   working    rebuild reads evidence.raw_* only - originals never touched
--   analysis   rebuild re-runs detection over working
--   reference  not derived; re-seeded from its source lexicons
--
-- NO COMPATIBILITY VIEWS, NO ALIASES. A shim that lets `analysis.message` keep
-- resolving would guarantee both names live in the codebase forever. Every caller
-- moves in the same change or the change is not done.
--
-- Idempotent. Percent-free. Never edit after apply - add 0015.

BEGIN;

CREATE SCHEMA IF NOT EXISTS working;
CREATE SCHEMA IF NOT EXISTS reference;
CREATE SCHEMA IF NOT EXISTS ops;

COMMENT ON SCHEMA working IS
  'Derived working set. Rebuilt by re-deriving from evidence.raw_* without ever '
  'touching the original files. Nothing here is authoritative: if it disagrees '
  'with evidence, evidence wins.';
COMMENT ON SCHEMA reference IS
  'Hand-curated taxonomy and configuration. Not derived from evidence and not a '
  'conclusion about the case. Re-seeded from source lexicons, never re-derived.';
COMMENT ON SCHEMA analysis IS
  'Conclusions only: findings, assertions, scores, review decisions, ground-truth '
  'labels and the litigation work product built on them. Derived data lives in '
  'working; taxonomy lives in reference; run ledgers live in ops.';
COMMENT ON SCHEMA ops IS
  'Operational plumbing - run ledgers, stage records, tool-call logs. Safe to '
  'prune under a retention policy, which is exactly why it must not sit beside '
  'evidence or findings.';

-- ---------------------------------------------------------------------------
-- Move tables. ALTER TABLE ... SET SCHEMA carries indexes, constraints, triggers
-- and sequences with it, and every foreign key - including the nine pointing in
-- from evidence and public - keeps working, because FKs bind to OIDs and not to
-- schema-qualified names. Same for views: their stored parse trees track the
-- move automatically. Only TEXT that names a schema has to be hand-edited, which
-- means function bodies and application code.
-- ---------------------------------------------------------------------------

DO $$
DECLARE
  t TEXT;
  target TEXT;
  spec RECORD;
BEGIN
  FOR spec IN
    SELECT 'working' AS sch, unnest(ARRAY[
      -- spine
      'normalized_record',
      -- messaging projection
      'message','message_participant','conversation','attachment','call_log',
      'email','account','handle','phone','conversation_group',
      'conversation_group_member',
      -- links and lineage
      'event_source_record','event_ordering','lineage_edge','id_xref',
      -- staging, pre-gate
      'extraction_batch','extraction_candidate','record_observation','block_status',
      -- resolved entities
      'entity','entity_alias','entity_mention','entity_resolution',
      'entity_merge_event','person','organization','device','device_ownership',
      'vehicle',
      -- resolved places and movement
      'location','geocode_request','geocode_resolution','geocode_result',
      'gps_track','stay_point','home_base','waypoint_device_split',
      'temporal_anchor',
      -- derived registry
      'artifact_registry'
    ]) AS tbl
    UNION ALL
    SELECT 'reference', unnest(ARRAY[
      'behavior_category','behavior_category_mcl','custody_factor',
      'detection_pattern','detection_pattern_set','pattern_lexicon','topic_code',
      'score_band_config','relative_rule','legal_issue','legal_issue_factor',
      'lexicon_sync','format_resolver','geofence'
    ])
    UNION ALL
    SELECT 'ops', unnest(ARRAY[
      'workflow_run','workflow_run_stage','processing_run','tool_call_ledger',
      'geocode_audit'
    ])
  LOOP
    t := spec.tbl; target := spec.sch;
    IF EXISTS (SELECT 1 FROM information_schema.tables
                WHERE table_schema = 'analysis' AND table_name = t) THEN
      EXECUTE 'ALTER TABLE analysis.' || quote_ident(t) ||
              ' SET SCHEMA ' || quote_ident(target);
    END IF;
  END LOOP;
END $$;

-- Views follow their subject. Anything left in analysis is a conclusion.
DO $$
DECLARE
  spec RECORD;
BEGIN
  FOR spec IN
    SELECT 'working' AS sch, unnest(ARRAY[
      'vw_derivation_lineage','vw_record_attestations','vw_record_disclosure',
      'vw_record_sender_resolution','vw_message_sms','vw_message_imessage'
    ]) AS v
  LOOP
    IF EXISTS (SELECT 1 FROM information_schema.views
                WHERE table_schema = 'analysis' AND table_name = spec.v) THEN
      EXECUTE 'ALTER VIEW analysis.' || quote_ident(spec.v) ||
              ' SET SCHEMA ' || quote_ident(spec.sch);
    END IF;
  END LOOP;
END $$;

-- Guard functions move with the tables they guard. log_task_status and
-- snapshot_task stay in analysis: the task tables they fire on are work product.
DO $$
DECLARE
  fn TEXT;
BEGIN
  FOREACH fn IN ARRAY ARRAY['derived_write_guard','entity_candidate_no_mutate',
                            'extraction_candidate_no_mutate','forbid_mutation',
                            'reject_mutation']
  LOOP
    IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                WHERE n.nspname = 'analysis' AND p.proname = fn) THEN
      EXECUTE 'ALTER FUNCTION analysis.' || quote_ident(fn) ||
              '() SET SCHEMA working';
    END IF;
  END LOOP;
END $$;

COMMIT;
