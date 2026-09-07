-- 0065_repair_validate_message_projection_person_home.sql
--
-- Byline: Claude Code · Fable 5 · 2026-09-01 (H-08a full-tree drift sweep).
--
-- ALTER TABLE ... SET SCHEMA does not rewrite plpgsql function bodies.
-- working.validate_message_projection() still queried working.person after the
-- identity home moved (working -> reference by 0057, reference -> registry by
-- 0062), so any approved acquired_third_party route would have raised
-- UndefinedTable at trigger time. Found by regenerating the baseline from live
-- and anti-joining every qualified name against information_schema (the only
-- function body in live with a stale moved-table qualification; the companion
-- finding, working.enqueue_evidence_vector_projection targeting the dropped
-- working.normalized_record_chunk, is deferred to the H-04 chunk-model
-- retarget because its target table no longer exists at all).
--
-- Change: two working.person references -> registry.person. Nothing else.

CREATE OR REPLACE FUNCTION working.validate_message_projection()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE owner_count INTEGER;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtext('working.message_projection'));
  IF EXISTS (SELECT 1 FROM working.message_projection_route r
             JOIN working.normalized_record nr ON nr.id=r.normalized_record_id
             WHERE r.decision_state='approved' AND nr.record_type<>'message') THEN
    RAISE EXCEPTION 'MESSAGE_ROUTE_REQUIRES_MESSAGE_RECORD';
  END IF;
  IF EXISTS (
    SELECT 1 FROM working.message_projection_route r
    WHERE r.decision_state='approved' AND r.projection_kind='first_party'
      AND ((SELECT count(*) FROM working.message m WHERE m.derived_from_record_id=r.normalized_record_id)<>1
        OR EXISTS (SELECT 1 FROM working.third_party_message tm WHERE tm.normalized_record_id=r.normalized_record_id))) THEN
    RAISE EXCEPTION 'FIRST_PARTY_PROJECTION_CARDINALITY';
  END IF;
  IF EXISTS (SELECT 1 FROM working.message_projection_route
             WHERE decision_state='approved' AND projection_kind='acquired_third_party') THEN
    SELECT count(*) INTO owner_count FROM registry.person WHERE role_in_case='user';
    IF owner_count<>1 THEN RAISE EXCEPTION 'OWNER_IDENTITY_NOT_CONFIGURED'; END IF;
  END IF;
  IF EXISTS (
    SELECT 1 FROM working.message_projection_route r
    JOIN working.normalized_record nr ON nr.id=r.normalized_record_id
    LEFT JOIN working.third_party_message tm ON tm.normalized_record_id=r.normalized_record_id
    LEFT JOIN working.third_party_conversation tc ON tc.id=tm.conversation_id
    WHERE r.decision_state='approved' AND r.projection_kind='acquired_third_party'
      AND (tm.id IS NULL OR tc.review_status<>'approved' OR tc.case_id<>nr.case_id
        OR tc.source_artifact_id<>nr.artifact_id
        OR tm.occurred_at IS DISTINCT FROM nr.occurred_at
        OR tm.sender_raw IS NULL OR length(trim(tm.sender_raw))=0
        OR tm.sender_entity_id IS NULL
        OR (nr.attrs ? 'source_party_review_required'
            AND r.basis->>'source_party_review_resolved' IS DISTINCT FROM 'true')
        OR EXISTS (SELECT 1 FROM working.message m WHERE m.derived_from_record_id=r.normalized_record_id)
        OR (SELECT count(*) FROM working.third_party_message_participant p
            WHERE p.message_id=tm.id AND p.role='from')<>1
        OR NOT EXISTS (SELECT 1 FROM working.third_party_message_participant p
                       WHERE p.message_id=tm.id AND p.role IN ('to','cc','bcc','group'))
        OR EXISTS (SELECT 1 FROM working.third_party_message_participant p
                   WHERE p.message_id=tm.id AND p.entity_id IS NULL)
        OR NOT EXISTS (SELECT 1 FROM working.third_party_message_participant p
                       WHERE p.message_id=tm.id AND p.role='from' AND p.entity_id=tm.sender_entity_id)
        OR EXISTS (SELECT 1 FROM working.third_party_message_participant p
                   JOIN registry.person wp ON wp.id=p.entity_id
                   WHERE p.message_id=tm.id AND wp.role_in_case='user')
        OR NOT EXISTS (SELECT 1 FROM working.third_party_conversation_acquisition ca
                       JOIN evidence.acquisition a ON a.id=ca.acquisition_id
                       WHERE ca.conversation_id=tm.conversation_id
                         AND ca.approval_state='approved' AND a.acquired_at IS NOT NULL
                         AND a.asserted_by='human'))) THEN
    RAISE EXCEPTION 'ACQUIRED_THIRD_PARTY_PROJECTION_INVALID';
  END IF;
  RETURN NULL;
END $function$;
