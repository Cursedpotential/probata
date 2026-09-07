-- 0058_the_reckoning.sql
--
-- Byline: Claude · Opus 5 · 2026-08-31, executing TARGET-SCHEMA-BLUEPRINT.html
-- (owner-reviewed; investigation_* delete re-confirmed after the litigation
-- loop was found already built in analysis).
--
-- 54 deletions, 14 moves, 1 duplicate resolved. Every deleted table is
-- empty-verified at apply time (a non-empty table aborts the whole file).
-- Deletion is permitted and quarantine is wrong here per D-111: empty tables
-- are recreatable from migrations in git; schemas do not get riddle piles.
--
-- THE THREE WARS END HERE:
--   conversation = per-source; thread = cross-platform human. (D-116)
--   chunk = content_chunk only; hash column is content_sha256.
--   review = the canon spine. The 0047 context_review_* apparatus dies.
--
-- THE LITIGATION LOOP (owner requirement, 2026-08-31): finding ->
-- evidence_task (what's needed / has it been found) -> evidence_item
-- (promoted, exhibit, custody) -> factor_citation (MCL 722.23) ->
-- legal_timeline_event. Already existed in analysis; evidence_item moves to
-- the evidence schema because it IS promoted evidence with custody, which is
-- what `evidence` now means. The weaker working.investigation_* duplicate of
-- this loop is deleted.
--
-- NOTHING IMMUTABLE, NO GUARDS (D-110).

-- ===========================================================================
-- SAFETY: abort if any table slated for deletion has rows
-- ===========================================================================
DO $$
DECLARE t TEXT; n BIGINT;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'working.chat_conversation_event','working.chat_message_event','working.chat_chunk_event',
    'working.chat_chunk_lane_event','working.context_asset_event','working.chat_cdc_cursor',
    'working.chat_projection_dead_letter',
    'working.context_review_case','working.context_review_decision',
    'working.context_review_decision_evidence_hash','working.context_review_decision_source_range',
    'working.context_review_decision_source_version','working.context_review_dispatch_attempt',
    'working.context_review_first_party_thread_message','working.context_review_first_party_thread_source',
    'working.context_review_first_party_thread_version','working.context_review_third_party_thread_message',
    'working.context_review_third_party_thread_source','working.context_review_third_party_thread_version',
    'working.context_review_relative_time_anchor','working.context_review_signal_receipt',
    'working.context_review_temporal_run_state','working.context_review_temporal_workflow',
    'working.context_review_terminal_reconciliation','working.context_review_timeline_event_candidate',
    'working.review_decision',
    'working.chat_chunk','working.normalized_record_chunk','working.chat_chunk_lane','working.chat_chunk_embedding','working.chat_chunk_message','working.chat_chunk_projection',
    'working.legacy_chat_chunk_content_chunk_map','working.legacy_normalized_chunk_content_chunk_map',
    'working.conversation','working.conversation_group_member',
    'working.first_party_context_thread_realization_assertion',
    'working.first_party_context_thread_realization_message',
    'working.first_party_context_thread_realization_source',
    'working.third_party_context_thread_realization_assertion',
    'working.third_party_context_thread_realization_message',
    'working.third_party_context_thread_realization_source',
    'working.investigation_event','working.investigation_event_source',
    'working.investigation_event_evidence_need','working.investigation_event_evidence_link',
    'working.investigation_event_tag',
    'working.block_status','working.device_ownership','working.event_ordering',
    'working.lineage_edge','working.entity_merge_event','working.chat_chunk_tag',
    'working.context_asset_projection',
    'public.platform_consolidation_checkpoint','public.platform_consolidation_proof_receipt',
    'analysis.entity_candidate'
  ] LOOP
    IF to_regclass(t) IS NOT NULL THEN
      EXECUTE format('SELECT count(*) FROM %s', t) INTO n;
      IF n > 0 THEN RAISE EXCEPTION 'ABORT: % has % rows — not empty, will not delete', t, n; END IF;
    END IF;
  END LOOP;
END $$;

-- ===========================================================================
-- DELETIONS
-- ===========================================================================
-- dead outbox (7) — canon.recompute_queue is the one fan-out mechanism
DROP TABLE IF EXISTS working.chat_conversation_event,
  working.chat_message_event, working.chat_chunk_event,
  working.chat_chunk_lane_event, working.context_asset_event,
  working.chat_cdc_cursor, working.chat_projection_dead_letter CASCADE;

-- parallel review apparatus (19) — the canon spine is THE review path (D-114)
DROP TABLE IF EXISTS working.context_review_case, working.context_review_decision,
  working.context_review_decision_evidence_hash, working.context_review_decision_source_range,
  working.context_review_decision_source_version, working.context_review_dispatch_attempt,
  working.context_review_first_party_thread_message, working.context_review_first_party_thread_source,
  working.context_review_first_party_thread_version, working.context_review_third_party_thread_message,
  working.context_review_third_party_thread_source, working.context_review_third_party_thread_version,
  working.context_review_relative_time_anchor, working.context_review_signal_receipt,
  working.context_review_temporal_run_state, working.context_review_temporal_workflow,
  working.context_review_terminal_reconciliation, working.context_review_timeline_event_candidate,
  working.review_decision CASCADE;

-- chunk war (8) — content_chunk wins. The WHOLE chat_chunk family dies with
-- it (lane/embedding/message/projection all FK the loser), and the one
-- process worth keeping — projection-state tracking with attempts/errors —
-- gets a successor pointed at the winner, below.
DROP TABLE IF EXISTS working.chat_chunk, working.normalized_record_chunk,
  working.legacy_chat_chunk_content_chunk_map,
  working.legacy_normalized_chunk_content_chunk_map,
  working.chat_chunk_lane, working.chat_chunk_embedding,
  working.chat_chunk_message, working.chat_chunk_projection CASCADE;

-- conversation war (2) — per-source conversations + cross-platform threads win
DROP TABLE IF EXISTS working.conversation, working.conversation_group_member CASCADE;

-- 0047 deepest speculation (6)
DROP TABLE IF EXISTS working.first_party_context_thread_realization_assertion,
  working.first_party_context_thread_realization_message,
  working.first_party_context_thread_realization_source,
  working.third_party_context_thread_realization_assertion,
  working.third_party_context_thread_realization_message,
  working.third_party_context_thread_realization_source CASCADE;

-- weaker duplicate of the litigation loop (5) — analysis suite wins
DROP TABLE IF EXISTS working.investigation_event, working.investigation_event_source,
  working.investigation_event_evidence_need, working.investigation_event_evidence_link,
  working.investigation_event_tag CASCADE;

-- never-wired stragglers (7)
DROP TABLE IF EXISTS working.block_status, working.device_ownership,
  working.event_ordering, working.lineage_edge, working.entity_merge_event,
  working.chat_chunk_tag, working.context_asset_projection CASCADE;

-- finished consolidation (however many of the family exist)
DROP TABLE IF EXISTS public.platform_consolidation_checkpoint,
  public.platform_consolidation_proof_receipt,
  public.platform_consolidation_gate, public.platform_consolidation_run CASCADE;

-- duplicate resolved: working.candidate_entity wins (code-adjacent, 0016)
DROP TABLE IF EXISTS analysis.entity_candidate CASCADE;

-- ===========================================================================
-- MOVES
-- ===========================================================================
-- the landing zone gets its honest name
CREATE SCHEMA IF NOT EXISTS raw AUTHORIZATION platform_admin;
COMMENT ON SCHEMA raw IS
  'Verbatim per-source landing. The ONLY insert targets for parsers; never edited. Formerly the raw_* tables inside evidence. evidence now means PROMOTED material with custody (owner ruling 2026-08-31).';

ALTER TABLE IF EXISTS evidence.raw_ai_chat   SET SCHEMA raw;
ALTER TABLE IF EXISTS evidence.raw_csv       SET SCHEMA raw;
ALTER TABLE IF EXISTS evidence.raw_facebook  SET SCHEMA raw;
ALTER TABLE IF EXISTS evidence.raw_imessage  SET SCHEMA raw;
ALTER TABLE IF EXISTS evidence.raw_phone     SET SCHEMA raw;
ALTER TABLE IF EXISTS evidence.raw_sms       SET SCHEMA raw;
ALTER TABLE IF EXISTS evidence.raw_rejected  SET SCHEMA raw;
ALTER TABLE IF EXISTS evidence.raw_activity  SET SCHEMA raw;
ALTER TABLE IF EXISTS evidence.raw_path      SET SCHEMA raw;
ALTER TABLE IF EXISTS evidence.raw_trip      SET SCHEMA raw;
ALTER TABLE IF EXISTS evidence.raw_visit     SET SCHEMA raw;
ALTER TABLE IF EXISTS evidence.gps_point     SET SCHEMA raw;
ALTER TABLE IF EXISTS evidence.file_node     SET SCHEMA raw;

COMMENT ON SCHEMA evidence IS
  'PROMOTED evidence with custody: acquisition, custody events, hashes, ingest runs, and evidence_item (the exhibit-ready landing for canon-spine promotions). NOT the raw landing — that is the raw schema. Owner ruling 2026-08-31 (D-116).';

-- the promotion landing table joins the evidence layer it belongs to
ALTER TABLE IF EXISTS analysis.evidence_item SET SCHEMA evidence;
COMMENT ON TABLE evidence.evidence_item IS
  'THE promotion target. A row here is promoted evidence: exhibit_number, is_authenticated, chain_of_custody, safe_for_legal_use, anchored to raw via evidence_hash_id/normalized_record_id. Written only via a canon.change_proposal of kind promote, after owner ruling. Part of the litigation loop: finding -> evidence_task -> evidence_item -> factor_citation -> legal_timeline_event.';

-- conclusions move to the conclusions drawer
ALTER TABLE IF EXISTS working.claim_assertion                  SET SCHEMA analysis;
ALTER TABLE IF EXISTS working.claim_assertion_member           SET SCHEMA analysis;
ALTER TABLE IF EXISTS working.claim_assertion_synthesis_member SET SCHEMA analysis;
ALTER TABLE IF EXISTS working.content_chunk_classification_decision SET SCHEMA analysis;

-- ===========================================================================
-- SUCCESSOR: projection-state tracking for the winning chunk model
-- ===========================================================================
-- Process carried over from chat_chunk_projection (deleted above): which chunk
-- has been projected to which sink, with retry/error state. Fresh-ingest
-- projection is THIS table + the workers; canon.recompute_queue handles
-- re-projection after approved changes. Two processes, two tables, on purpose.
CREATE TABLE IF NOT EXISTS working.content_chunk_projection (
  id            UUID PRIMARY KEY DEFAULT uuidv7(),
  chunk_id      UUID NOT NULL REFERENCES working.content_chunk(id) ON DELETE CASCADE,
  sink          TEXT NOT NULL CHECK (sink IN ('weaviate','semantica','sat_temporal','opensearch','surrealdb')),
  embedder_id   TEXT,
  projection_ref TEXT,
  source_generation BIGINT,
  status        TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','projected','failed','skipped')),
  attempts      INTEGER NOT NULL DEFAULT 0,
  last_error    TEXT,
  projected_at  TIMESTAMPTZ,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (chunk_id, sink)
);
CREATE INDEX IF NOT EXISTS content_chunk_projection_pending_idx
  ON working.content_chunk_projection (sink, created_at) WHERE status = 'pending';
COMMENT ON TABLE working.content_chunk_projection IS
  'Fresh-ingest projection state for content_chunk (successor to chat_chunk_projection, 0058). Re-projection after an approved canon change is canon.recompute_queue''s job — deliberately separate processes.';

-- ===========================================================================
-- VOCABULARY RULINGS ON THE SURVIVORS
-- ===========================================================================
COMMENT ON TABLE working.chat_conversation IS
  'PER-SOURCE conversation: one AI-chat export''s conversation. Vocabulary ruling D-116: "conversation" = per-source; "thread" = cross-platform human conversation. Never mixed.';
COMMENT ON TABLE working.third_party_conversation IS
  'PER-SOURCE conversation from an acquired third-party export. See D-116 vocabulary ruling.';
COMMENT ON TABLE working.first_party_context_thread IS
  'THE cross-platform first-party thread model: one human conversation across SMS+iMessage+Facebook+... The winner of the conversation war (D-116). working.conversation and conversation_group are deleted; do not rebuild parallel models.';
COMMENT ON TABLE working.content_chunk IS
  'THE chunk model (D-116). chat_chunk and normalized_record_chunk are deleted. Hash column convention: content_sha256; "content_hash" is banned.';
