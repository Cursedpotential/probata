-- 0026_realization_event.sql
-- ✅ APPLIED TO PROD — verified live 2026-08-23 against 100.91.190.107:5432 db=ai by direct
--    introspection (Claude Code · Opus 5). realization_event, realization_event_record,
--    message_projection_route, third_party_conversation/message/participant/acquisition,
--    normalized_record_chunk, evidence_vector_projection_job, source_available_from(),
--    visible_from() and vw_horizon_atom all confirmed PRESENT.
-- ~~HELD FOR OWNER / NOT APPLIED FOUNDATION REWRITE -- 2026-08-18~~  (historical)
-- Byline amendment: Codex GPT-5 -- acquired-third-party visibility split.
-- Byline amendment: Codex GPT-5 -- governed projection writer contract.
-- Byline amendment: Codex GPT-5 -- native Weaviate projection outbox.
-- Byline amendment: Codex GPT-5 -- legacy realization-kind forward upgrade.
--
-- This held migration was never applied to production.  The earlier draft
-- conflated source availability with realization and stored derived chunks in
-- the authored spine.  This revision supersedes that draft before first apply:
-- one authored normalized record, separate derived chunks, mutually-exclusive
-- first-party/acquired-third-party projections, acquisition-gated source
-- availability, and plural realization atoms.

BEGIN;

-- Keep the schema's human-only authority vocabulary while retaining the
-- actual human identity separately for audit and approval attribution.
ALTER TABLE evidence.acquisition
  ADD COLUMN IF NOT EXISTS asserted_by_identity TEXT;
UPDATE evidence.acquisition
   SET asserted_by_identity='legacy-human'
 WHERE asserted_by_identity IS NULL;
ALTER TABLE evidence.acquisition
  ALTER COLUMN asserted_by_identity SET NOT NULL;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='acquisition_asserter_identity_ck'
                  AND conrelid='evidence.acquisition'::regclass) THEN
    ALTER TABLE evidence.acquisition ADD CONSTRAINT acquisition_asserter_identity_ck
      CHECK (length(trim(asserted_by_identity))>0);
  END IF;
END $$;
COMMENT ON COLUMN evidence.acquisition.asserted_by_identity IS
  'Identity/name of the human asserter; asserted_by remains the constrained authority category human.';

-- Durable request/receipt replay context for retries. This is deliberately not
-- acquisition authority: evidence.acquisition remains the only authored account
-- of how/when evidence entered possession.
ALTER TABLE ops.workflow_run
  ADD COLUMN IF NOT EXISTS source_context JSONB NOT NULL DEFAULT '{}'::jsonb;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='workflow_run_source_context_ck'
                  AND conrelid='ops.workflow_run'::regclass) THEN
    ALTER TABLE ops.workflow_run ADD CONSTRAINT workflow_run_source_context_ck
      CHECK (jsonb_typeof(source_context)='object');
  END IF;
END $$;
COMMENT ON COLUMN ops.workflow_run.source_context IS
  'Durable ingest request/receipt replay context (source identity, message_corpus, source_principal, acquisition assertion); not acquisition authority.';

-- One authored source record.  Chunks are versioned children below.
ALTER TABLE working.normalized_record
  ADD COLUMN IF NOT EXISTS source_record_key TEXT,
  ADD COLUMN IF NOT EXISTS source_content_sha256 BYTEA,
  ADD COLUMN IF NOT EXISTS sender TEXT,
  ADD COLUMN IF NOT EXISTS recipients JSONB NOT NULL DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS message_corpus TEXT;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='normalized_record_source_hash_ck'
                  AND conrelid='working.normalized_record'::regclass) THEN
    ALTER TABLE working.normalized_record ADD CONSTRAINT normalized_record_source_hash_ck
      CHECK (source_content_sha256 IS NULL OR octet_length(source_content_sha256)=32);
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='normalized_record_recipients_ck'
                  AND conrelid='working.normalized_record'::regclass) THEN
    ALTER TABLE working.normalized_record ADD CONSTRAINT normalized_record_recipients_ck
      CHECK (jsonb_typeof(recipients)='array');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='normalized_record_message_corpus_ck'
                  AND conrelid='working.normalized_record'::regclass) THEN
    ALTER TABLE working.normalized_record ADD CONSTRAINT normalized_record_message_corpus_ck
      CHECK (message_corpus IS NULL OR message_corpus IN ('first_party','acquired_third_party'));
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS normalized_record_source_key_uq
  ON working.normalized_record(artifact_id, source, source_record_key)
  WHERE source_record_key IS NOT NULL;

CREATE TABLE IF NOT EXISTS working.normalized_record_chunk (
  id UUID PRIMARY KEY DEFAULT uuidv7(),
  normalized_record_id UUID NOT NULL REFERENCES working.normalized_record(id) ON DELETE CASCADE,
  chunker_id TEXT NOT NULL CHECK (length(chunker_id)>0),
  chunk_index INTEGER NOT NULL CHECK (chunk_index>=0),
  content TEXT NOT NULL,
  content_sha256 BYTEA NOT NULL CHECK (octet_length(content_sha256)=32),
  source_content_sha256 BYTEA NOT NULL CHECK (octet_length(source_content_sha256)=32),
  char_start INTEGER,
  char_end INTEGER,
  token_count INTEGER,
  attrs JSONB NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(attrs)='object'),
  derived_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (char_start IS NULL OR char_start>=0),
  CHECK (char_end IS NULL OR (char_start IS NOT NULL AND char_end>=char_start)),
  CHECK (token_count IS NULL OR token_count>=0),
  UNIQUE(normalized_record_id, chunker_id, chunk_index)
);
CREATE INDEX IF NOT EXISTS normalized_record_chunk_record_idx
  ON working.normalized_record_chunk(normalized_record_id);
CREATE INDEX IF NOT EXISTS normalized_record_chunk_profile_idx
  ON working.normalized_record_chunk(chunker_id, normalized_record_id);

-- Sole current routing assignment.  Its PK makes the two projections exclusive.
CREATE TABLE IF NOT EXISTS working.message_projection_route (
  normalized_record_id UUID PRIMARY KEY REFERENCES working.normalized_record(id) ON DELETE CASCADE,
  projection_kind TEXT NOT NULL CHECK (projection_kind IN ('first_party','acquired_third_party')),
  decision_state TEXT NOT NULL DEFAULT 'proposed' CHECK (decision_state IN ('proposed','approved')),
  basis JSONB NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(basis)='object'),
  proposed_by TEXT NOT NULL CHECK (length(proposed_by)>0),
  proposed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  approved_by TEXT,
  approved_at TIMESTAMPTZ,
  deriver_version TEXT NOT NULL CHECK (length(deriver_version)>0),
  CHECK ((approved_at IS NULL) = (decision_state='proposed')),
  CHECK ((approved_by IS NULL) = (decision_state='proposed')),
  UNIQUE(normalized_record_id, projection_kind)
);
CREATE INDEX IF NOT EXISTS message_projection_route_kind_idx
  ON working.message_projection_route(projection_kind, decision_state, normalized_record_id);

-- Existing working.message is the first-party projection.  Backfill routes
-- before adding its composite FK.  Duplicate source projections abort safely.
ALTER TABLE working.message ADD COLUMN IF NOT EXISTS projection_kind TEXT NOT NULL DEFAULT 'first_party';
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM working.message WHERE projection_kind <> 'first_party') THEN
    RAISE EXCEPTION 'working.message contains non-first-party projection_kind';
  END IF;
  IF EXISTS (SELECT derived_from_record_id FROM working.message
              WHERE derived_from_record_id IS NOT NULL GROUP BY 1 HAVING count(*)>1) THEN
    RAISE EXCEPTION 'working.message has duplicate derived_from_record_id; rebuild projection before 0026';
  END IF;
END $$;
INSERT INTO working.message_projection_route
  (normalized_record_id, projection_kind, decision_state, basis, proposed_by,
   approved_by, approved_at, deriver_version)
SELECT DISTINCT derived_from_record_id, 'first_party', 'approved',
       '{"migration":"0026-existing-first-party"}'::jsonb,
       'migration-0026', 'migration-0026', now(), 'migration-0026'
FROM working.message WHERE derived_from_record_id IS NOT NULL
ON CONFLICT (normalized_record_id) DO NOTHING;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='message_projection_kind_ck'
                  AND conrelid='working.message'::regclass) THEN
    ALTER TABLE working.message ADD CONSTRAINT message_projection_kind_ck
      CHECK (projection_kind='first_party');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='message_requires_spine_ck'
                  AND conrelid='working.message'::regclass) THEN
    ALTER TABLE working.message ADD CONSTRAINT message_requires_spine_ck
      CHECK (derived_from_record_id IS NOT NULL) NOT VALID;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='message_route_fk'
                  AND conrelid='working.message'::regclass) THEN
    ALTER TABLE working.message ADD CONSTRAINT message_route_fk
      FOREIGN KEY (derived_from_record_id, projection_kind)
      REFERENCES working.message_projection_route(normalized_record_id, projection_kind)
      DEFERRABLE INITIALLY DEFERRED NOT VALID;
  END IF;
END $$;
CREATE UNIQUE INDEX IF NOT EXISTS message_one_per_spine_uq
  ON working.message(derived_from_record_id) WHERE derived_from_record_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS working.third_party_conversation (
  id UUID PRIMARY KEY DEFAULT uuidv7(),
  case_id TEXT NOT NULL DEFAULT 'primary' CHECK (length(case_id)>0),
  source_artifact_id UUID NOT NULL REFERENCES evidence.evidence_hash(id) ON DELETE RESTRICT,
  platform TEXT NOT NULL CHECK (length(platform)>0),
  external_thread_key TEXT NOT NULL CHECK (length(external_thread_key)>0),
  title TEXT,
  started_at TIMESTAMPTZ,
  ended_at TIMESTAMPTZ,
  message_count INTEGER NOT NULL DEFAULT 0 CHECK (message_count>=0),
  review_status TEXT NOT NULL DEFAULT 'pending' CHECK (review_status IN ('pending','approved','rejected')),
  platform_attrs JSONB NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(platform_attrs)='object'),
  deriver_version TEXT NOT NULL CHECK (length(deriver_version)>0),
  derived_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (ended_at IS NULL OR started_at IS NULL OR ended_at>=started_at),
  UNIQUE(source_artifact_id, platform, external_thread_key)
);
CREATE INDEX IF NOT EXISTS third_party_conversation_case_time_idx
  ON working.third_party_conversation(case_id, started_at);

CREATE TABLE IF NOT EXISTS working.third_party_message (
  id UUID PRIMARY KEY DEFAULT uuidv7(),
  conversation_id UUID NOT NULL REFERENCES working.third_party_conversation(id) ON DELETE CASCADE,
  normalized_record_id UUID NOT NULL UNIQUE REFERENCES working.normalized_record(id) ON DELETE RESTRICT,
  projection_kind TEXT NOT NULL DEFAULT 'acquired_third_party' CHECK (projection_kind='acquired_third_party'),
  occurred_at TIMESTAMPTZ,
  platform TEXT NOT NULL CHECK (length(platform)>0),
  external_id TEXT,
  sender_raw TEXT,
  sender_entity_id UUID REFERENCES working.entity(id) ON DELETE RESTRICT,
  message_type TEXT NOT NULL DEFAULT 'text' CHECK (length(message_type)>0),
  temporal_confidence ai.confidence,
  raw_ts TEXT,
  tz TEXT,
  content_sha256 BYTEA CHECK (content_sha256 IS NULL OR octet_length(content_sha256)=32),
  platform_attrs JSONB NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(platform_attrs)='object'),
  raw_data JSONB,
  deriver_version TEXT NOT NULL CHECK (length(deriver_version)>0),
  derived_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT third_party_message_route_fk
    FOREIGN KEY(normalized_record_id, projection_kind)
    REFERENCES working.message_projection_route(normalized_record_id, projection_kind)
    DEFERRABLE INITIALLY DEFERRED
);
CREATE INDEX IF NOT EXISTS third_party_message_conv_time_idx
  ON working.third_party_message(conversation_id, occurred_at, id);
CREATE INDEX IF NOT EXISTS third_party_message_sender_idx
  ON working.third_party_message(sender_entity_id, occurred_at);
CREATE UNIQUE INDEX IF NOT EXISTS third_party_message_external_uq
  ON working.third_party_message(conversation_id, external_id) WHERE external_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS working.third_party_message_participant (
  id UUID PRIMARY KEY DEFAULT uuidv7(),
  message_id UUID NOT NULL REFERENCES working.third_party_message(id) ON DELETE CASCADE,
  entity_id UUID REFERENCES working.entity(id) ON DELETE RESTRICT,
  participant_raw TEXT NOT NULL CHECK (length(participant_raw)>0),
  participant_e164 TEXT,
  role TEXT NOT NULL CHECK (role IN ('from','to','cc','bcc','group')),
  deriver_version TEXT NOT NULL CHECK (length(deriver_version)>0),
  UNIQUE(message_id, entity_id, role)
);
CREATE INDEX IF NOT EXISTS third_party_message_participant_entity_idx
  ON working.third_party_message_participant(entity_id, message_id);
CREATE UNIQUE INDEX IF NOT EXISTS third_party_message_one_sender_uq
  ON working.third_party_message_participant(message_id) WHERE role='from';

CREATE TABLE IF NOT EXISTS working.third_party_conversation_acquisition (
  id UUID PRIMARY KEY DEFAULT uuidv7(),
  conversation_id UUID NOT NULL REFERENCES working.third_party_conversation(id) ON DELETE CASCADE,
  acquisition_id UUID NOT NULL REFERENCES evidence.acquisition(id) ON DELETE RESTRICT,
  approval_state TEXT NOT NULL DEFAULT 'proposed' CHECK (approval_state IN ('proposed','approved','superseded')),
  proposed_by TEXT NOT NULL CHECK (length(proposed_by)>0),
  proposed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  approved_by TEXT,
  approved_at TIMESTAMPTZ,
  supersedes_id UUID REFERENCES working.third_party_conversation_acquisition(id) ON DELETE RESTRICT,
  notes TEXT,
  CHECK ((approved_at IS NULL) = (approval_state='proposed')),
  CHECK ((approved_by IS NULL) = (approval_state='proposed')),
  UNIQUE(conversation_id, acquisition_id)
);
CREATE INDEX IF NOT EXISTS third_party_conv_acq_current_idx
  ON working.third_party_conversation_acquisition(conversation_id, approval_state, acquisition_id);
CREATE INDEX IF NOT EXISTS third_party_conv_acq_acquisition_idx
  ON working.third_party_conversation_acquisition(acquisition_id);

-- Single-case owner identity must be explicit before third-party approval.
CREATE UNIQUE INDEX IF NOT EXISTS person_single_user_role_uq
  ON working.person((role_in_case)) WHERE role_in_case='user';

-- Plural realization events.  They are horizon atoms, not source clocks.
CREATE TABLE IF NOT EXISTS working.realization_event (
  id UUID PRIMARY KEY DEFAULT uuidv7(),
  case_id TEXT NOT NULL DEFAULT 'primary' CHECK (length(case_id)>0),
  kind TEXT NOT NULL CHECK (kind IN ('contradiction','export_read','told_by_person','manual',
                                     'betrayal','deceit','gaslighting','pattern_recognition')),
  realized_at TIMESTAMPTZ NOT NULL,
  trigger_record_id UUID REFERENCES working.normalized_record(id) ON DELETE RESTRICT,
  evidence_pointer JSONB NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(evidence_pointer)='object'),
  proposer TEXT NOT NULL CHECK (proposer IN ('algorithm','owner')),
  approval_state TEXT NOT NULL DEFAULT 'proposed' CHECK (approval_state IN ('proposed','approved','superseded')),
  proposed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  approved_at TIMESTAMPTZ,
  approved_by TEXT,
  notes TEXT,
  CHECK ((approved_at IS NULL) = (approval_state='proposed')),
  CHECK ((approved_by IS NULL) = (approval_state='proposed'))
);

-- The earlier held draft created the same table with only four realization
-- kinds.  Reconcile that legacy CHECK in place; adding the replacement as a
-- validated constraint proves every preserved row already satisfies it.
DO $$ BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conrelid='working.realization_event'::regclass
       AND conname='realization_event_kind_check'
       AND position('pattern_recognition' in pg_get_constraintdef(oid))=0
  ) THEN
    ALTER TABLE working.realization_event
      DROP CONSTRAINT realization_event_kind_check;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conrelid='working.realization_event'::regclass
       AND conname='realization_event_kind_check'
  ) THEN
    ALTER TABLE working.realization_event
      ADD CONSTRAINT realization_event_kind_check
      CHECK (kind IN ('contradiction','export_read','told_by_person','manual',
                      'betrayal','deceit','gaslighting','pattern_recognition'));
  END IF;
END $$;
CREATE INDEX IF NOT EXISTS realization_event_case_state_time_idx
  ON working.realization_event(case_id, approval_state, realized_at);
CREATE TABLE IF NOT EXISTS working.realization_event_record (
  realization_event_id UUID NOT NULL REFERENCES working.realization_event(id) ON DELETE CASCADE,
  normalized_record_id UUID NOT NULL REFERENCES working.normalized_record(id) ON DELETE RESTRICT,
  case_id TEXT NOT NULL DEFAULT 'primary' CHECK (length(case_id)>0),
  PRIMARY KEY(realization_event_id, normalized_record_id)
);
CREATE INDEX IF NOT EXISTS realization_event_record_record_idx
  ON working.realization_event_record(normalized_record_id);

CREATE OR REPLACE FUNCTION working.source_available_from(p_record_id UUID)
RETURNS TIMESTAMPTZ LANGUAGE sql STABLE PARALLEL SAFE AS $$
SELECT CASE
  WHEN nr.record_type <> 'message' THEN nr.occurred_at
  WHEN r.decision_state <> 'approved' OR r.normalized_record_id IS NULL THEN NULL
  WHEN r.projection_kind='first_party' THEN nr.occurred_at
  WHEN r.projection_kind='acquired_third_party' THEN (
    SELECT MIN(a.acquired_at)
      FROM working.third_party_message tm
      JOIN working.third_party_conversation_acquisition ca ON ca.conversation_id=tm.conversation_id
      JOIN evidence.acquisition a ON a.id=ca.acquisition_id
     WHERE tm.normalized_record_id=nr.id
       AND ca.approval_state='approved'
       AND a.acquired_at IS NOT NULL)
END
FROM working.normalized_record nr
LEFT JOIN working.message_projection_route r ON r.normalized_record_id=nr.id
WHERE nr.id=p_record_id;
$$;

CREATE OR REPLACE FUNCTION working.visible_from(p_record_id UUID)
RETURNS TIMESTAMPTZ LANGUAGE sql STABLE PARALLEL SAFE AS $$
  SELECT working.source_available_from(p_record_id);
$$;

CREATE OR REPLACE VIEW working.vw_horizon_atom AS
SELECT nr.case_id, 'normalized_record'::TEXT AS atom_kind, nr.id AS atom_id,
       nr.id AS normalized_record_id, NULL::UUID AS realization_event_id,
       nr.occurred_at, working.source_available_from(nr.id) AS visible_from,
       nr.disclosure_tier, nr.content, nr.attrs
  FROM working.normalized_record nr
UNION ALL
SELECT re.case_id, 'realization_event'::TEXT, re.id, NULL::UUID, re.id,
       re.realized_at, re.realized_at, 'discovered'::TEXT, COALESCE(re.notes,''),
       jsonb_build_object('kind',re.kind,'evidence_pointer',re.evidence_pointer)
  FROM working.realization_event re WHERE re.approval_state='approved';

-- Global deferred validator.  Projection transactions are small and serialized;
-- scanning approved routes at commit favors correctness over a fragile partial check.
CREATE OR REPLACE FUNCTION working.validate_message_projection()
RETURNS trigger LANGUAGE plpgsql AS $$
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
    SELECT count(*) INTO owner_count FROM working.person WHERE role_in_case='user';
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
                   JOIN working.person wp ON wp.id=p.entity_id
                   WHERE p.message_id=tm.id AND wp.role_in_case='user')
        OR NOT EXISTS (SELECT 1 FROM working.third_party_conversation_acquisition ca
                       JOIN evidence.acquisition a ON a.id=ca.acquisition_id
                       WHERE ca.conversation_id=tm.conversation_id
                         AND ca.approval_state='approved' AND a.acquired_at IS NOT NULL
                         AND a.asserted_by='human'))) THEN
    RAISE EXCEPTION 'ACQUIRED_THIRD_PARTY_PROJECTION_INVALID';
  END IF;
  RETURN NULL;
END $$;

CREATE OR REPLACE FUNCTION working.validate_realization_links()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM working.realization_event_record rer
    JOIN working.realization_event re ON re.id=rer.realization_event_id
    JOIN working.normalized_record nr ON nr.id=rer.normalized_record_id
    WHERE rer.case_id<>re.case_id OR rer.case_id<>nr.case_id) THEN
    RAISE EXCEPTION 'REALIZATION_LINK_CASE_MISMATCH';
  END IF;
  IF EXISTS (
    SELECT 1 FROM working.realization_event re
    WHERE re.approval_state='approved' AND re.trigger_record_id IS NULL
      AND NOT EXISTS (SELECT 1 FROM working.realization_event_record rer
                      WHERE rer.realization_event_id=re.id)) THEN
    RAISE EXCEPTION 'APPROVED_REALIZATION_REQUIRES_EVIDENCE_LINK';
  END IF;
  RETURN NULL;
END $$;

DO $$ DECLARE t TEXT; BEGIN
  FOREACH t IN ARRAY ARRAY['normalized_record','message_projection_route','message','person','third_party_conversation',
                            'third_party_message','third_party_message_participant',
                            'third_party_conversation_acquisition'] LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS message_projection_validate ON working.%I', t);
    EXECUTE format('CREATE CONSTRAINT TRIGGER message_projection_validate AFTER INSERT OR UPDATE OR DELETE ON working.%I DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION working.validate_message_projection()', t);
  END LOOP;
END $$;

DROP TRIGGER IF EXISTS realization_link_validate ON working.realization_event;
CREATE CONSTRAINT TRIGGER realization_link_validate
AFTER INSERT OR UPDATE OR DELETE ON working.realization_event
DEFERRABLE INITIALLY DEFERRED FOR EACH ROW
EXECUTE FUNCTION working.validate_realization_links();
DROP TRIGGER IF EXISTS realization_link_validate ON working.realization_event_record;
CREATE CONSTRAINT TRIGGER realization_link_validate
AFTER INSERT OR UPDATE OR DELETE ON working.realization_event_record
DEFERRABLE INITIALLY DEFERRED FOR EACH ROW
EXECUTE FUNCTION working.validate_realization_links();

-- Queue the deferred validator for every migrated route, then force it before
-- commit. This turns legacy projection ambiguity into a rollback, not a latent
-- first read failure.
UPDATE working.message_projection_route
   SET deriver_version=deriver_version;
UPDATE working.realization_event SET notes=notes;
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;

DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema='working' AND table_name='normalized_record'
               AND column_name='acquired_at') THEN
    EXECUTE 'COMMENT ON COLUMN working.normalized_record.acquired_at IS '
         || quote_literal('Deprecated ingest-era clock; never use for horizon visibility. Acquired third-party source availability comes from an approved evidence.acquisition link.');
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema='working' AND table_name='normalized_record'
               AND column_name='realized_at') THEN
    EXECUTE 'COMMENT ON COLUMN working.normalized_record.realized_at IS '
         || quote_literal('Deprecated singular clock; realization is plural in working.realization_event plus working.realization_event_record.');
  END IF;
END $$;

COMMENT ON FUNCTION working.source_available_from(UUID) IS
  'Raw-source availability: occurred_at for first-party/non-message; approved acquisition acquired_at for acquired-third-party; NULL fails closed. Ingest and realization times are not source clocks.';
COMMENT ON FUNCTION working.visible_from(UUID) IS
  'Compatibility alias for source_available_from. Realizations are separate vw_horizon_atom rows at realized_at.';
COMMENT ON TABLE working.third_party_conversation IS
  'Derived acquired conversation projection. Approval requires explicit non-owner participants and an approved human acquisition link.';
COMMENT ON TABLE working.third_party_conversation_acquisition IS
  'Reviewed link from a derived third-party conversation to an authored human acquisition event; acquired_at gates raw-source availability.';

-- Native Weaviate projection outbox. HELD with this migration: no live schema
-- or collection is changed until the migration is separately authorized.
CREATE TABLE IF NOT EXISTS working.evidence_vector_projection_job (
  id UUID PRIMARY KEY DEFAULT uuidv7(),
  chunk_id UUID NOT NULL REFERENCES working.normalized_record_chunk(id) ON DELETE CASCADE,
  projection_version TEXT NOT NULL DEFAULT 'evidence-vector@1' CHECK (length(projection_version)>0),
  reason TEXT NOT NULL CHECK (length(reason)>0),
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','processing','completed','failed')),
  authority_state TEXT CHECK (authority_state IN ('active','revoked','superseded')),
  attempts INTEGER NOT NULL DEFAULT 0 CHECK (attempts>=0),
  generation BIGINT NOT NULL DEFAULT 0 CHECK (generation>=0),
  next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  locked_at TIMESTAMPTZ,
  locked_by TEXT,
  projection_hash TEXT,
  last_error TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  completed_at TIMESTAMPTZ,
  UNIQUE(chunk_id, projection_version),
  CHECK ((locked_at IS NULL) = (locked_by IS NULL))
);
CREATE INDEX IF NOT EXISTS evidence_vector_projection_job_drain_idx
  ON working.evidence_vector_projection_job(status, next_attempt_at, created_at);

CREATE OR REPLACE FUNCTION working.enqueue_evidence_vector_projection(
  p_record_ids UUID[], p_reason TEXT)
RETURNS INTEGER LANGUAGE plpgsql AS $$
DECLARE queued INTEGER;
BEGIN
  IF p_reason IS NULL OR length(trim(p_reason))=0 THEN
    RAISE EXCEPTION 'VECTOR_PROJECTION_REASON_REQUIRED';
  END IF;
  INSERT INTO working.evidence_vector_projection_job(chunk_id, reason)
  SELECT chunk.id, p_reason
    FROM working.normalized_record_chunk chunk
   WHERE chunk.normalized_record_id=ANY(p_record_ids)
  ON CONFLICT (chunk_id, projection_version) DO UPDATE
    SET reason=EXCLUDED.reason, status='pending', generation=working.evidence_vector_projection_job.generation+1,
        next_attempt_at=now(),
        locked_at=NULL, locked_by=NULL, completed_at=NULL, updated_at=now();
  GET DIAGNOSTICS queued = ROW_COUNT;
  RETURN queued;
END $$;

CREATE OR REPLACE FUNCTION working.queue_vector_chunk_on_insert()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  PERFORM working.enqueue_evidence_vector_projection(
    ARRAY[NEW.normalized_record_id], 'normalized_record_chunk_insert');
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS evidence_vector_chunk_enqueue ON working.normalized_record_chunk;
CREATE TRIGGER evidence_vector_chunk_enqueue
AFTER INSERT ON working.normalized_record_chunk
FOR EACH ROW EXECUTE FUNCTION working.queue_vector_chunk_on_insert();

CREATE OR REPLACE FUNCTION working.queue_vector_route_change()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  PERFORM working.enqueue_evidence_vector_projection(
    ARRAY[COALESCE(NEW.normalized_record_id,OLD.normalized_record_id)],
    'message_projection_authority_change');
  RETURN COALESCE(NEW,OLD);
END $$;
DROP TRIGGER IF EXISTS evidence_vector_route_enqueue ON working.message_projection_route;
CREATE TRIGGER evidence_vector_route_enqueue
AFTER INSERT OR UPDATE OR DELETE ON working.message_projection_route
FOR EACH ROW EXECUTE FUNCTION working.queue_vector_route_change();

CREATE OR REPLACE FUNCTION working.queue_vector_third_party_authority_change()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE conversation UUID;
BEGIN
  conversation := COALESCE(NEW.conversation_id,OLD.conversation_id);
  PERFORM working.enqueue_evidence_vector_projection(
    ARRAY(SELECT message.normalized_record_id
            FROM working.third_party_message message
           WHERE message.conversation_id=conversation),
    'third_party_authority_change');
  RETURN COALESCE(NEW,OLD);
END $$;
DROP TRIGGER IF EXISTS evidence_vector_acquisition_enqueue
  ON working.third_party_conversation_acquisition;
CREATE TRIGGER evidence_vector_acquisition_enqueue
AFTER INSERT OR UPDATE OR DELETE ON working.third_party_conversation_acquisition
FOR EACH ROW EXECUTE FUNCTION working.queue_vector_third_party_authority_change();

COMMIT;
