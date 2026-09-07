-- Migration 0047: format-neutral content chunks and cross-platform context threads.
--
-- This is an additive foundation only.  It does not choose or run a chunker or route a
-- file format; it does not backfill legacy chunks, infer a thread, or promote context to evidence.
-- All source representations remain independently retained; no "best" export is chosen.
-- Tool implementations remain in Platform Tools.  The Go engine calls that service
-- directly; this migration creates no engine-owned parser/extractor/chunker duplicate.
--
-- Byline: Codex · GPT-5 · 2026-08-29

BEGIN;

DO $$
BEGIN
    IF current_database() <> 'platform' THEN
        RAISE EXCEPTION 'migration 0047 may run only in database platform, not %', current_database();
    END IF;
    IF to_regclass('public.schema_version') IS NULL
       OR to_regclass('context.retained_object') IS NULL
       OR to_regclass('context.source_version') IS NULL
       OR to_regclass('context.source_version_object') IS NULL
       OR to_regclass('context.normalized_generation') IS NULL
       OR to_regclass('context.raw_record_identity') IS NULL
       OR to_regclass('context.normalized_record_identity') IS NULL
       OR to_regclass('context.activity_execution') IS NULL
       OR to_regclass('context.activity_receipt') IS NULL
       OR to_regclass('working.chat_chunk') IS NULL
       OR to_regclass('working.normalized_record_chunk') IS NULL
       OR to_regclass('working.message') IS NULL
       OR to_regclass('working.third_party_message') IS NULL
       OR to_regclass('working.third_party_message_participant') IS NULL
       OR to_regclass('working.third_party_conversation') IS NULL
       OR to_regclass('working.third_party_conversation_acquisition') IS NULL
       OR to_regclass('working.realization_event') IS NULL
       OR to_regclass('working.person') IS NULL
       OR to_regclass('working.entity') IS NULL
       OR to_regclass('working.device') IS NULL
       OR to_regclass('timeline.event_candidate') IS NULL
       OR to_regclass('evidence.acquisition') IS NULL
       OR to_regclass('evidence.evidence_hash') IS NULL
       OR to_regclass('analysis.court_case') IS NULL
       OR to_regprocedure('uuidv7()') IS NULL
       OR to_regprocedure('digest(bytea,text)') IS NULL THEN
        RAISE EXCEPTION 'migration 0047 requires migrations 0024, 0026, 0036, 0043, and 0044';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_roles
        WHERE rolname = 'platform_admin' AND NOT rolcanlogin
          AND NOT (rolsuper OR rolcreatedb OR rolcreaterole OR rolreplication OR rolbypassrls)
    ) THEN
        RAISE EXCEPTION 'migration 0047 requires safe NOLOGIN role platform_admin';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_roles
        WHERE rolname = 'platform_runtime' AND rolcanlogin
          AND NOT (rolsuper OR rolcreatedb OR rolcreaterole OR rolreplication OR rolbypassrls)
    ) THEN
        RAISE EXCEPTION 'migration 0047 requires safe LOGIN role platform_runtime';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_roles
        WHERE rolname = 'context_owner' AND NOT rolcanlogin
          AND NOT (rolsuper OR rolcreatedb OR rolcreaterole OR rolreplication OR rolbypassrls)
    ) OR NOT pg_has_role('platform_admin', 'context_owner', 'MEMBER') THEN
        RAISE EXCEPTION 'migration 0047 requires safe context_owner and platform_admin membership';
    END IF;
    IF NOT has_schema_privilege('platform_admin', 'working', 'CREATE')
       OR NOT has_schema_privilege('platform_admin', 'context', 'CREATE')
       OR NOT has_schema_privilege('platform_admin', 'timeline', 'CREATE') THEN
        RAISE EXCEPTION 'platform_admin requires CREATE on working, context, and timeline schemas';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'context_review_adjudicator') THEN
        CREATE ROLE context_review_adjudicator NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE
            NOREPLICATION NOBYPASSRLS;
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_roles
        WHERE rolname = 'context_review_adjudicator' AND NOT rolcanlogin
          AND NOT (rolsuper OR rolcreatedb OR rolcreaterole OR rolreplication OR rolbypassrls)
    ) THEN
        RAISE EXCEPTION 'migration 0047 requires safe NOLOGIN role context_review_adjudicator';
    END IF;
    IF pg_has_role('platform_runtime', 'context_review_adjudicator', 'MEMBER') THEN
        RAISE EXCEPTION 'platform_runtime must never inherit context_review_adjudicator';
    END IF;
    IF (SELECT count(*) FROM pg_roles
        WHERE rolname IN ('timeline_writer', 'timeline_projector', 'timeline_reader')
          AND NOT rolcanlogin
          AND NOT (rolsuper OR rolcreatedb OR rolcreaterole OR rolreplication OR rolbypassrls)) <> 3 THEN
        RAISE EXCEPTION 'migration 0047 requires safe NOLOGIN timeline roles from migration 0035';
    END IF;
END;
$$;

-- No password or LOGIN role is created here.  The migration/admin group can
-- administer the capability role; a future authenticated reviewer identity must
-- be provisioned out of band and granted this role explicitly.  Runtime is
-- checked above and structurally excluded from this membership.
GRANT context_review_adjudicator TO platform_admin WITH ADMIN OPTION;

SET LOCAL ROLE platform_admin;

CREATE OR REPLACE FUNCTION working.forbid_context_foundation_mutation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog
AS $$
BEGIN
    RAISE EXCEPTION '% is append-only; corrections require a new version or row', TG_TABLE_NAME;
END;
$$;

-- A rerun is a new generation.  Policy/config/source-view identity is immutable;
-- the only permitted update is the one-way open -> sealed|aborted transition.
CREATE TABLE working.content_chunk_generation (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    source_version_id UUID NOT NULL,
    normalized_generation_id UUID,
    generation_ordinal INTEGER NOT NULL CHECK (generation_ordinal > 0),
    status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'sealed', 'aborted')),
    completeness_scope TEXT NOT NULL DEFAULT 'complete'
        CHECK (completeness_scope = 'complete'),
    requires_verbatim_reassembly BOOLEAN NOT NULL DEFAULT true,
    policy_id TEXT NOT NULL CHECK (length(btrim(policy_id)) > 0),
    policy_version TEXT NOT NULL CHECK (length(btrim(policy_version)) > 0),
    chunker_id TEXT NOT NULL CHECK (length(btrim(chunker_id)) > 0),
    chunker_version TEXT NOT NULL CHECK (length(btrim(chunker_version)) > 0),
    config_digest BYTEA NOT NULL CHECK (octet_length(config_digest) = 32),
    schema_version TEXT NOT NULL CHECK (length(btrim(schema_version)) > 0),
    implementation_digest BYTEA NOT NULL CHECK (octet_length(implementation_digest) = 32),
    source_view TEXT NOT NULL CHECK (length(btrim(source_view)) > 0),
    source_canonicalization TEXT NOT NULL CHECK (length(btrim(source_canonicalization)) > 0),
    source_sha256 BYTEA NOT NULL CHECK (octet_length(source_sha256) = 32),
    source_byte_length BIGINT NOT NULL CHECK (source_byte_length >= 0),
    source_codepoint_length BIGINT CHECK (source_codepoint_length IS NULL OR source_codepoint_length >= 0),
    chunk_count BIGINT CHECK (chunk_count IS NULL OR chunk_count >= 0),
    member_count BIGINT CHECK (member_count IS NULL OR member_count >= 0),
    manifest_sha256 BYTEA CHECK (manifest_sha256 IS NULL OR octet_length(manifest_sha256) = 32),
    activity_execution_id UUID NOT NULL,
    activity_receipt_id UUID NOT NULL REFERENCES context.activity_receipt(id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    sealed_at TIMESTAMPTZ,
    sealed_by TEXT,
    aborted_at TIMESTAMPTZ,
    abort_reason TEXT,
    UNIQUE (source_version_id, generation_ordinal),
    UNIQUE (id, source_version_id),
    FOREIGN KEY (source_version_id)
        REFERENCES context.source_version(id) ON DELETE RESTRICT,
    FOREIGN KEY (normalized_generation_id, source_version_id)
        REFERENCES context.normalized_generation(id, source_version_id) ON DELETE RESTRICT,
    FOREIGN KEY (activity_execution_id, source_version_id)
        REFERENCES context.activity_execution(id, source_version_id) ON DELETE RESTRICT,
    CHECK (
        (status = 'open' AND sealed_at IS NULL AND sealed_by IS NULL
                         AND aborted_at IS NULL AND abort_reason IS NULL
                         AND chunk_count IS NULL AND member_count IS NULL AND manifest_sha256 IS NULL)
        OR
        (status = 'sealed' AND sealed_at IS NOT NULL AND length(btrim(sealed_by)) > 0
                           AND aborted_at IS NULL AND abort_reason IS NULL
                           AND chunk_count IS NOT NULL AND member_count IS NOT NULL
                           AND manifest_sha256 IS NOT NULL)
        OR
        (status = 'aborted' AND sealed_at IS NULL AND sealed_by IS NULL
                            AND aborted_at IS NOT NULL AND length(btrim(abort_reason)) > 0)
    )
);

CREATE INDEX content_chunk_generation_source_idx
    ON working.content_chunk_generation (source_version_id, generation_ordinal DESC);
CREATE INDEX content_chunk_generation_normalized_idx
    ON working.content_chunk_generation (normalized_generation_id)
    WHERE normalized_generation_id IS NOT NULL;

-- One exact, typed, reusable half-open source-range primitive.  Chunk and
-- timeline/event-extraction generations are independent sibling passes over the
-- same immutable source_version and reference this primitive separately.
CREATE TABLE context.source_range_locator (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    source_version_id UUID NOT NULL REFERENCES context.source_version(id) ON DELETE RESTRICT,
    coordinate_system TEXT NOT NULL CHECK (coordinate_system IN ('utf8_bytes', 'unicode_codepoints')),
    range_start BIGINT NOT NULL CHECK (range_start >= 0),
    range_end BIGINT NOT NULL CHECK (range_end > range_start),
    exact_slice_sha256 BYTEA NOT NULL CHECK (octet_length(exact_slice_sha256) = 32),
    verification_activity_receipt_id UUID NOT NULL
        REFERENCES context.activity_receipt(id) ON DELETE RESTRICT,
    locator_projection JSONB NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(locator_projection) = 'object'),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (id, source_version_id)
);

CREATE TABLE context.source_object_range_locator (
    source_range_locator_id UUID PRIMARY KEY,
    source_version_id UUID NOT NULL,
    source_object_id UUID NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    FOREIGN KEY (source_range_locator_id, source_version_id)
        REFERENCES context.source_range_locator(id, source_version_id) ON DELETE RESTRICT,
    FOREIGN KEY (source_version_id, source_object_id)
        REFERENCES context.source_version_object(source_version_id, object_id) ON DELETE RESTRICT
);

CREATE TABLE context.raw_record_range_locator (
    source_range_locator_id UUID PRIMARY KEY,
    source_version_id UUID NOT NULL,
    raw_record_id UUID NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    FOREIGN KEY (source_range_locator_id, source_version_id)
        REFERENCES context.source_range_locator(id, source_version_id) ON DELETE RESTRICT,
    FOREIGN KEY (raw_record_id, source_version_id)
        REFERENCES context.raw_record_identity(id, source_version_id) ON DELETE RESTRICT
);

CREATE TABLE context.normalized_record_range_locator (
    source_range_locator_id UUID PRIMARY KEY,
    source_version_id UUID NOT NULL,
    normalized_record_id UUID NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    FOREIGN KEY (source_range_locator_id, source_version_id)
        REFERENCES context.source_range_locator(id, source_version_id) ON DELETE RESTRICT,
    FOREIGN KEY (normalized_record_id, source_version_id)
        REFERENCES context.normalized_record_identity(id, source_version_id) ON DELETE RESTRICT
);

CREATE INDEX source_range_locator_subject_idx
    ON context.source_range_locator (source_version_id, coordinate_system, range_start, range_end);

CREATE TABLE working.content_chunk (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    generation_id UUID NOT NULL,
    source_version_id UUID NOT NULL,
    chunk_index BIGINT NOT NULL CHECK (chunk_index >= 0),
    content TEXT NOT NULL CHECK (length(content) > 0),
    content_sha256 BYTEA NOT NULL CHECK (octet_length(content_sha256) = 32),
    derivation_mode TEXT NOT NULL
        CHECK (derivation_mode IN ('verbatim_span', 'composed', 'unverified_derived')),
    token_count BIGINT CHECK (token_count IS NULL OR token_count >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (generation_id, chunk_index),
    UNIQUE (id, generation_id, source_version_id),
    FOREIGN KEY (generation_id, source_version_id)
        REFERENCES working.content_chunk_generation(id, source_version_id) ON DELETE RESTRICT,
    CHECK (digest(convert_to(content, 'UTF8'), 'sha256') = content_sha256)
);

CREATE INDEX content_chunk_generation_idx
    ON working.content_chunk (generation_id, chunk_index);
-- Deliberately no UNIQUE(content_sha256): identical text in distinct positions/sources is valid.
CREATE INDEX content_chunk_hash_lookup_idx
    ON working.content_chunk (content_sha256);

-- Typed lineage: exactly one immutable coordinate subject.  range_start/range_end
-- are always half-open [start,end); JSON is only a non-authoritative projection.
CREATE TABLE working.content_chunk_source_span (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    chunk_id UUID NOT NULL,
    generation_id UUID NOT NULL,
    source_version_id UUID NOT NULL,
    member_ordinal BIGINT NOT NULL CHECK (member_ordinal >= 0),
    source_range_locator_id UUID NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (chunk_id, member_ordinal),
    FOREIGN KEY (chunk_id, generation_id, source_version_id)
        REFERENCES working.content_chunk(id, generation_id, source_version_id) ON DELETE RESTRICT,
    FOREIGN KEY (source_range_locator_id, source_version_id)
        REFERENCES context.source_range_locator(id, source_version_id) ON DELETE RESTRICT
);

CREATE INDEX content_chunk_source_span_subject_idx
    ON working.content_chunk_source_span (source_version_id, member_ordinal);
CREATE INDEX content_chunk_source_span_generation_idx
    ON working.content_chunk_source_span (generation_id, member_ordinal);

CREATE TABLE timeline.event_candidate_source_range (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    event_candidate_id UUID NOT NULL REFERENCES timeline.event_candidate(id) ON DELETE RESTRICT,
    source_version_id UUID NOT NULL,
    source_range_locator_id UUID NOT NULL,
    member_ordinal BIGINT NOT NULL CHECK (member_ordinal >= 0),
    extractor_id TEXT NOT NULL CHECK (length(btrim(extractor_id)) > 0),
    extractor_version TEXT NOT NULL CHECK (length(btrim(extractor_version)) > 0),
    schema_manifest_digest BYTEA NOT NULL CHECK (octet_length(schema_manifest_digest) = 32),
    extraction_activity_receipt_id UUID NOT NULL REFERENCES context.activity_receipt(id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (event_candidate_id, member_ordinal),
    FOREIGN KEY (source_range_locator_id, source_version_id)
        REFERENCES context.source_range_locator(id, source_version_id) ON DELETE RESTRICT
);

CREATE INDEX event_candidate_source_range_source_idx
    ON timeline.event_candidate_source_range (source_version_id, event_candidate_id);

CREATE TABLE working.content_chunk_reassembly_receipt (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    generation_id UUID NOT NULL UNIQUE,
    source_version_id UUID NOT NULL,
    source_sha256 BYTEA NOT NULL CHECK (octet_length(source_sha256) = 32),
    reassembled_sha256 BYTEA NOT NULL CHECK (octet_length(reassembled_sha256) = 32),
    source_byte_length BIGINT NOT NULL CHECK (source_byte_length >= 0),
    reassembled_byte_length BIGINT NOT NULL CHECK (reassembled_byte_length >= 0),
    covered_range_start BIGINT NOT NULL DEFAULT 0 CHECK (covered_range_start = 0),
    covered_range_end BIGINT NOT NULL CHECK (covered_range_end >= covered_range_start),
    gap_count BIGINT NOT NULL CHECK (gap_count >= 0),
    overlap_count BIGINT NOT NULL CHECK (overlap_count >= 0),
    chunk_count BIGINT NOT NULL CHECK (chunk_count >= 0),
    member_count BIGINT NOT NULL CHECK (member_count >= 0),
    verification_result TEXT NOT NULL
        CHECK (verification_result IN ('exact', 'mismatch', 'incomplete', 'not_applicable')),
    verifier_id TEXT NOT NULL CHECK (length(btrim(verifier_id)) > 0),
    verifier_version TEXT NOT NULL CHECK (length(btrim(verifier_version)) > 0),
    activity_receipt_id UUID NOT NULL REFERENCES context.activity_receipt(id) ON DELETE RESTRICT,
    verified_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    FOREIGN KEY (generation_id, source_version_id)
        REFERENCES working.content_chunk_generation(id, source_version_id) ON DELETE RESTRICT,
    CHECK (
        verification_result <> 'exact'
        OR (source_sha256 = reassembled_sha256
            AND source_byte_length = reassembled_byte_length
            AND covered_range_end = source_byte_length
            AND gap_count = 0 AND overlap_count = 0)
    )
);

-- Context-first routing is a reviewed classification history, never an ingest-time
-- evidence decision.  A trigger writes the immutable initial context assignment.
CREATE TABLE working.content_chunk_classification_decision (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    chunk_id UUID NOT NULL REFERENCES working.content_chunk(id) ON DELETE RESTRICT,
    decision_version INTEGER NOT NULL CHECK (decision_version > 0),
    lane TEXT NOT NULL CHECK (lane IN ('context', 'legal', 'personal_history')),
    decision_kind TEXT NOT NULL
        CHECK (decision_kind IN ('initial_context', 'reviewed_assignment', 'supersession')),
    review_state TEXT NOT NULL
        CHECK (review_state IN ('system_initial', 'pending', 'human_approved', 'human_rejected', 'superseded')),
    classifier_id TEXT NOT NULL CHECK (length(btrim(classifier_id)) > 0),
    classifier_version TEXT NOT NULL CHECK (length(btrim(classifier_version)) > 0),
    confidence DOUBLE PRECISION NOT NULL CHECK (confidence BETWEEN 0 AND 1),
    rationale TEXT,
    supersedes_id UUID REFERENCES working.content_chunk_classification_decision(id) ON DELETE RESTRICT,
    reviewed_by TEXT,
    reviewed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (chunk_id, decision_version),
    CHECK (decision_kind <> 'initial_context' OR (lane = 'context' AND review_state = 'system_initial')),
    CHECK ((reviewed_by IS NULL AND reviewed_at IS NULL)
        OR (reviewed_by IS NOT NULL AND reviewed_at IS NOT NULL)),
    CHECK (review_state NOT IN ('human_approved', 'human_rejected') OR reviewed_at IS NOT NULL)
);

CREATE UNIQUE INDEX content_chunk_one_initial_context_uq
    ON working.content_chunk_classification_decision (chunk_id)
    WHERE decision_kind = 'initial_context';
CREATE INDEX content_chunk_classification_review_idx
    ON working.content_chunk_classification_decision (review_state, lane, created_at);

CREATE VIEW working.content_chunk_current_classification AS
SELECT DISTINCT ON (chunk_id)
       chunk_id, id AS decision_id, decision_version, lane, review_state,
       classifier_id, classifier_version, confidence, reviewed_by, reviewed_at
FROM working.content_chunk_classification_decision
WHERE review_state IN ('system_initial', 'human_approved')
ORDER BY chunk_id, decision_version DESC, created_at DESC, id DESC;

CREATE OR REPLACE FUNCTION working.insert_initial_content_chunk_context()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, working
AS $$
BEGIN
    INSERT INTO working.content_chunk_classification_decision (
        chunk_id, decision_version, lane, decision_kind, review_state,
        classifier_id, classifier_version, confidence, rationale
    ) VALUES (
        NEW.id, 1, 'context', 'initial_context', 'system_initial',
        'context-first-ingest-policy', '0047', 1.0,
        'All intake begins in context; legal/personal_history require reviewed classification.'
    );
    RETURN NEW;
END;
$$;

-- Legacy relations remain readable until a separately verified backfill/cutover.
-- These append-only maps carry cutover proof; they are not a second chunk authority.
CREATE TABLE working.legacy_chat_chunk_content_chunk_map (
    legacy_chat_chunk_id UUID PRIMARY KEY REFERENCES working.chat_chunk(id) ON DELETE RESTRICT,
    content_chunk_id UUID NOT NULL UNIQUE REFERENCES working.content_chunk(id) ON DELETE RESTRICT,
    backfill_receipt_id UUID NOT NULL REFERENCES context.activity_receipt(id) ON DELETE RESTRICT,
    mapped_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE working.legacy_normalized_chunk_content_chunk_map (
    legacy_normalized_chunk_id UUID PRIMARY KEY
        REFERENCES working.normalized_record_chunk(id) ON DELETE RESTRICT,
    content_chunk_id UUID NOT NULL UNIQUE REFERENCES working.content_chunk(id) ON DELETE RESTRICT,
    backfill_receipt_id UUID NOT NULL REFERENCES context.activity_receipt(id) ON DELETE RESTRICT,
    mapped_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Stable thread identities and their immutable inference versions.  Message occurrence
-- bounds and knowledge-horizon availability are separate clocks.
CREATE TABLE working.first_party_context_thread (
    context_thread_id UUID PRIMARY KEY DEFAULT uuidv7(),
    owner_person_id UUID NOT NULL REFERENCES working.person(id) ON DELETE RESTRICT,
    matter_id UUID NOT NULL,
    court_case_id UUID NOT NULL,
    case_key TEXT NOT NULL DEFAULT 'primary' CHECK (case_key = 'primary'),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    FOREIGN KEY (court_case_id, matter_id)
        REFERENCES analysis.court_case(id, matter_id) ON DELETE RESTRICT
);

CREATE TABLE working.third_party_context_thread (
    context_thread_id UUID PRIMARY KEY DEFAULT uuidv7(),
    matter_id UUID NOT NULL,
    court_case_id UUID NOT NULL,
    case_key TEXT NOT NULL DEFAULT 'primary' CHECK (case_key = 'primary'),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    FOREIGN KEY (court_case_id, matter_id)
        REFERENCES analysis.court_case(id, matter_id) ON DELETE RESTRICT
);

CREATE TABLE working.first_party_context_thread_version (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    context_thread_id UUID NOT NULL REFERENCES working.first_party_context_thread(context_thread_id) ON DELETE RESTRICT,
    version_ordinal INTEGER NOT NULL CHECK (version_ordinal > 0),
    classifier_id TEXT NOT NULL CHECK (length(btrim(classifier_id)) > 0),
    classifier_version TEXT NOT NULL CHECK (length(btrim(classifier_version)) > 0),
    assertion_digest BYTEA NOT NULL CHECK (octet_length(assertion_digest) = 32),
    confidence DOUBLE PRECISION NOT NULL CHECK (confidence BETWEEN 0 AND 1),
    review_state TEXT NOT NULL CHECK (review_state IN ('proposed', 'approved', 'rejected', 'superseded')),
    first_occurred_at TIMESTAMPTZ,
    last_occurred_at TIMESTAMPTZ,
    knowledge_available_from TIMESTAMPTZ,
    supersedes_id UUID REFERENCES working.first_party_context_thread_version(id) ON DELETE RESTRICT,
    reviewed_by TEXT,
    reviewed_at TIMESTAMPTZ,
    rationale TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (context_thread_id, version_ordinal),
    UNIQUE (id, context_thread_id),
    CHECK ((first_occurred_at IS NULL) = (last_occurred_at IS NULL)),
    CHECK (last_occurred_at IS NULL OR last_occurred_at >= first_occurred_at),
    CHECK (knowledge_available_from IS NULL OR first_occurred_at IS NULL
           OR knowledge_available_from >= first_occurred_at),
    CHECK (review_state <> 'approved' OR (reviewed_by IS NOT NULL AND reviewed_at IS NOT NULL))
);

CREATE TABLE working.third_party_context_thread_version (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    context_thread_id UUID NOT NULL REFERENCES working.third_party_context_thread(context_thread_id) ON DELETE RESTRICT,
    version_ordinal INTEGER NOT NULL CHECK (version_ordinal > 0),
    classifier_id TEXT NOT NULL CHECK (length(btrim(classifier_id)) > 0),
    classifier_version TEXT NOT NULL CHECK (length(btrim(classifier_version)) > 0),
    assertion_digest BYTEA NOT NULL CHECK (octet_length(assertion_digest) = 32),
    confidence DOUBLE PRECISION NOT NULL CHECK (confidence BETWEEN 0 AND 1),
    review_state TEXT NOT NULL CHECK (review_state IN ('proposed', 'approved', 'rejected', 'superseded')),
    first_occurred_at TIMESTAMPTZ,
    last_occurred_at TIMESTAMPTZ,
    knowledge_available_from TIMESTAMPTZ,
    supersedes_id UUID REFERENCES working.third_party_context_thread_version(id) ON DELETE RESTRICT,
    reviewed_by TEXT,
    reviewed_at TIMESTAMPTZ,
    rationale TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (context_thread_id, version_ordinal),
    UNIQUE (id, context_thread_id),
    CHECK ((first_occurred_at IS NULL) = (last_occurred_at IS NULL)),
    CHECK (last_occurred_at IS NULL OR last_occurred_at >= first_occurred_at),
    CHECK (knowledge_available_from IS NULL OR first_occurred_at IS NULL
           OR knowledge_available_from >= first_occurred_at),
    CHECK (review_state <> 'approved' OR (reviewed_by IS NOT NULL AND reviewed_at IS NOT NULL))
);

CREATE INDEX first_party_context_thread_version_review_idx
    ON working.first_party_context_thread_version (review_state, knowledge_available_from);
CREATE INDEX third_party_context_thread_version_review_idx
    ON working.third_party_context_thread_version (review_state, knowledge_available_from);

-- Thread order is independent of platform/file/message/chunk order.
CREATE TABLE working.first_party_context_thread_message (
    thread_version_id UUID NOT NULL,
    context_thread_id UUID NOT NULL,
    message_id UUID NOT NULL REFERENCES working.message(id) ON DELETE RESTRICT,
    thread_ordinal BIGINT NOT NULL CHECK (thread_ordinal >= 0),
    occurred_at TIMESTAMPTZ,
    source_available_from TIMESTAMPTZ,
    required_for_horizon BOOLEAN NOT NULL DEFAULT true,
    membership_confidence DOUBLE PRECISION NOT NULL CHECK (membership_confidence BETWEEN 0 AND 1),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (thread_version_id, message_id),
    UNIQUE (thread_version_id, thread_ordinal),
    FOREIGN KEY (thread_version_id, context_thread_id)
        REFERENCES working.first_party_context_thread_version(id, context_thread_id) ON DELETE RESTRICT,
    CHECK (source_available_from IS NOT DISTINCT FROM occurred_at)
);

CREATE TABLE working.third_party_context_thread_message (
    thread_version_id UUID NOT NULL,
    context_thread_id UUID NOT NULL,
    message_id UUID NOT NULL REFERENCES working.third_party_message(id) ON DELETE RESTRICT,
    conversation_acquisition_id UUID NOT NULL
        REFERENCES working.third_party_conversation_acquisition(id) ON DELETE RESTRICT,
    thread_ordinal BIGINT NOT NULL CHECK (thread_ordinal >= 0),
    occurred_at TIMESTAMPTZ,
    source_available_from TIMESTAMPTZ,
    required_for_horizon BOOLEAN NOT NULL DEFAULT true,
    membership_confidence DOUBLE PRECISION NOT NULL CHECK (membership_confidence BETWEEN 0 AND 1),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (thread_version_id, message_id),
    UNIQUE (thread_version_id, thread_ordinal),
    FOREIGN KEY (thread_version_id, context_thread_id)
        REFERENCES working.third_party_context_thread_version(id, context_thread_id) ON DELETE RESTRICT
);

-- Every source representation is retained independently.  The row itself is a
-- versioned, reviewable same-thread assertion; it never merges source versions.
CREATE TABLE working.first_party_context_thread_source (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    thread_version_id UUID NOT NULL,
    context_thread_id UUID NOT NULL,
    source_version_id UUID NOT NULL REFERENCES context.source_version(id) ON DELETE RESTRICT,
    source_anchor_ordinal BIGINT NOT NULL CHECK (source_anchor_ordinal >= 0),
    platform TEXT NOT NULL CHECK (length(btrim(platform)) > 0),
    platform_conversation_key TEXT NOT NULL CHECK (length(btrim(platform_conversation_key)) > 0),
    representation_kind TEXT NOT NULL
        CHECK (representation_kind IN ('native_export', 'screenshot', 'ocr_derived', 'pdf', 'html', 'json', 'xml', 'csv', 'other')),
    capture_kind TEXT NOT NULL CHECK (length(btrim(capture_kind)) > 0),
    declared_format TEXT NOT NULL CHECK (length(btrim(declared_format)) > 0),
    originating_device_id UUID REFERENCES working.device(id) ON DELETE RESTRICT,
    perspective_person_id UUID NOT NULL REFERENCES working.person(id) ON DELETE RESTRICT,
    coverage_first_occurred_at TIMESTAMPTZ,
    coverage_last_occurred_at TIMESTAMPTZ,
    coverage_message_count BIGINT CHECK (coverage_message_count IS NULL OR coverage_message_count >= 0),
    source_available_from TIMESTAMPTZ,
    required_for_horizon BOOLEAN NOT NULL DEFAULT true,
    metadata_clock_kind TEXT NOT NULL
        CHECK (metadata_clock_kind IN ('screenshot_capture', 'export_created', 'filesystem_observed', 'other')),
    metadata_timestamp TIMESTAMPTZ,
    metadata_timezone TEXT,
    metadata_clock_basis TEXT NOT NULL CHECK (length(btrim(metadata_clock_basis)) > 0),
    metadata_confidence DOUBLE PRECISION CHECK (metadata_confidence IS NULL OR metadata_confidence BETWEEN 0 AND 1),
    metadata_review_state TEXT NOT NULL CHECK (metadata_review_state IN ('unreviewed', 'approved', 'rejected', 'ambiguous')),
    metadata_ambiguity TEXT,
    raw_metadata JSONB NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(raw_metadata) = 'object'),
    raw_metadata_ref TEXT,
    metadata_extractor_id TEXT NOT NULL CHECK (length(btrim(metadata_extractor_id)) > 0),
    metadata_extractor_version TEXT NOT NULL CHECK (length(btrim(metadata_extractor_version)) > 0),
    assertion_version INTEGER NOT NULL CHECK (assertion_version > 0),
    confidence DOUBLE PRECISION NOT NULL CHECK (confidence BETWEEN 0 AND 1),
    review_state TEXT NOT NULL CHECK (review_state IN ('proposed', 'approved', 'rejected', 'superseded')),
    supersedes_id UUID REFERENCES working.first_party_context_thread_source(id) ON DELETE RESTRICT,
    provenance_digest BYTEA NOT NULL CHECK (octet_length(provenance_digest) = 32),
    asserted_by TEXT NOT NULL CHECK (length(btrim(asserted_by)) > 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (thread_version_id, source_anchor_ordinal),
    UNIQUE (thread_version_id, source_version_id, assertion_version),
    UNIQUE (id, thread_version_id),
    FOREIGN KEY (thread_version_id, context_thread_id)
        REFERENCES working.first_party_context_thread_version(id, context_thread_id) ON DELETE RESTRICT,
    CHECK (coverage_last_occurred_at IS NULL OR coverage_first_occurred_at IS NULL
           OR coverage_last_occurred_at >= coverage_first_occurred_at),
    CHECK (source_available_from IS NOT DISTINCT FROM coverage_last_occurred_at)
);

CREATE TABLE working.third_party_context_thread_source (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    thread_version_id UUID NOT NULL,
    context_thread_id UUID NOT NULL,
    source_version_id UUID NOT NULL REFERENCES context.source_version(id) ON DELETE RESTRICT,
    represented_conversation_id UUID NOT NULL
        REFERENCES working.third_party_conversation(id) ON DELETE RESTRICT,
    conversation_acquisition_id UUID NOT NULL
        REFERENCES working.third_party_conversation_acquisition(id) ON DELETE RESTRICT,
    acquisition_activity_receipt_id UUID NOT NULL
        REFERENCES context.activity_receipt(id) ON DELETE RESTRICT,
    source_anchor_ordinal BIGINT NOT NULL CHECK (source_anchor_ordinal >= 0),
    platform TEXT NOT NULL CHECK (length(btrim(platform)) > 0),
    platform_conversation_key TEXT NOT NULL CHECK (length(btrim(platform_conversation_key)) > 0),
    representation_kind TEXT NOT NULL
        CHECK (representation_kind IN ('native_export', 'screenshot', 'ocr_derived', 'pdf', 'html', 'json', 'xml', 'csv', 'other')),
    capture_kind TEXT NOT NULL CHECK (length(btrim(capture_kind)) > 0),
    declared_format TEXT NOT NULL CHECK (length(btrim(declared_format)) > 0),
    originating_device_id UUID REFERENCES working.device(id) ON DELETE RESTRICT,
    perspective_entity_id UUID NOT NULL REFERENCES working.entity(id) ON DELETE RESTRICT,
    coverage_first_occurred_at TIMESTAMPTZ,
    coverage_last_occurred_at TIMESTAMPTZ,
    coverage_message_count BIGINT CHECK (coverage_message_count IS NULL OR coverage_message_count >= 0),
    source_available_from TIMESTAMPTZ,
    required_for_horizon BOOLEAN NOT NULL DEFAULT true,
    metadata_clock_kind TEXT NOT NULL
        CHECK (metadata_clock_kind IN ('screenshot_capture', 'export_created', 'filesystem_observed', 'other')),
    metadata_timestamp TIMESTAMPTZ,
    metadata_timezone TEXT,
    metadata_clock_basis TEXT NOT NULL CHECK (length(btrim(metadata_clock_basis)) > 0),
    metadata_confidence DOUBLE PRECISION CHECK (metadata_confidence IS NULL OR metadata_confidence BETWEEN 0 AND 1),
    metadata_review_state TEXT NOT NULL CHECK (metadata_review_state IN ('unreviewed', 'approved', 'rejected', 'ambiguous')),
    metadata_ambiguity TEXT,
    raw_metadata JSONB NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(raw_metadata) = 'object'),
    raw_metadata_ref TEXT,
    metadata_extractor_id TEXT NOT NULL CHECK (length(btrim(metadata_extractor_id)) > 0),
    metadata_extractor_version TEXT NOT NULL CHECK (length(btrim(metadata_extractor_version)) > 0),
    assertion_version INTEGER NOT NULL CHECK (assertion_version > 0),
    confidence DOUBLE PRECISION NOT NULL CHECK (confidence BETWEEN 0 AND 1),
    review_state TEXT NOT NULL CHECK (review_state IN ('proposed', 'approved', 'rejected', 'superseded')),
    supersedes_id UUID REFERENCES working.third_party_context_thread_source(id) ON DELETE RESTRICT,
    provenance_digest BYTEA NOT NULL CHECK (octet_length(provenance_digest) = 32),
    asserted_by TEXT NOT NULL CHECK (length(btrim(asserted_by)) > 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (thread_version_id, source_anchor_ordinal),
    UNIQUE (thread_version_id, source_version_id, assertion_version),
    UNIQUE (id, thread_version_id),
    FOREIGN KEY (thread_version_id, context_thread_id)
        REFERENCES working.third_party_context_thread_version(id, context_thread_id) ON DELETE RESTRICT,
    CHECK (coverage_last_occurred_at IS NULL OR coverage_first_occurred_at IS NULL
           OR coverage_last_occurred_at >= coverage_first_occurred_at)
);

CREATE INDEX first_party_context_thread_source_lookup_idx
    ON working.first_party_context_thread_source (source_version_id, platform, platform_conversation_key);
CREATE INDEX third_party_context_thread_source_lookup_idx
    ON working.third_party_context_thread_source (source_version_id, platform, platform_conversation_key);

-- Zero-to-many reviewed links.  These assert a candidate relationship; they do not
-- claim realization actually occurred.  required_source_available_from is the
-- greatest availability clock among all required conflicting/supporting sources.
CREATE TABLE working.first_party_context_thread_realization_assertion (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    thread_version_id UUID NOT NULL REFERENCES working.first_party_context_thread_version(id) ON DELETE RESTRICT,
    realization_event_id UUID NOT NULL REFERENCES working.realization_event(id) ON DELETE RESTRICT,
    assertion_version INTEGER NOT NULL CHECK (assertion_version > 0),
    required_source_available_from TIMESTAMPTZ,
    review_state TEXT NOT NULL CHECK (review_state IN ('proposed', 'approved', 'rejected', 'superseded')),
    supersedes_id UUID REFERENCES working.first_party_context_thread_realization_assertion(id) ON DELETE RESTRICT,
    rationale TEXT NOT NULL CHECK (length(btrim(rationale)) > 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (thread_version_id, realization_event_id, assertion_version),
    UNIQUE (id, thread_version_id)
);

CREATE TABLE working.third_party_context_thread_realization_assertion (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    thread_version_id UUID NOT NULL REFERENCES working.third_party_context_thread_version(id) ON DELETE RESTRICT,
    realization_event_id UUID NOT NULL REFERENCES working.realization_event(id) ON DELETE RESTRICT,
    assertion_version INTEGER NOT NULL CHECK (assertion_version > 0),
    required_source_available_from TIMESTAMPTZ,
    review_state TEXT NOT NULL CHECK (review_state IN ('proposed', 'approved', 'rejected', 'superseded')),
    supersedes_id UUID REFERENCES working.third_party_context_thread_realization_assertion(id) ON DELETE RESTRICT,
    rationale TEXT NOT NULL CHECK (length(btrim(rationale)) > 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (thread_version_id, realization_event_id, assertion_version),
    UNIQUE (id, thread_version_id)
);

CREATE TABLE working.first_party_context_thread_realization_source (
    realization_assertion_id UUID NOT NULL,
    thread_version_id UUID NOT NULL,
    thread_source_id UUID NOT NULL,
    required_for_realization BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (realization_assertion_id, thread_source_id),
    FOREIGN KEY (realization_assertion_id, thread_version_id)
        REFERENCES working.first_party_context_thread_realization_assertion(id, thread_version_id) ON DELETE RESTRICT,
    FOREIGN KEY (thread_source_id, thread_version_id)
        REFERENCES working.first_party_context_thread_source(id, thread_version_id) ON DELETE RESTRICT
);

CREATE TABLE working.first_party_context_thread_realization_message (
    realization_assertion_id UUID NOT NULL,
    thread_version_id UUID NOT NULL,
    message_id UUID NOT NULL,
    required_for_realization BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (realization_assertion_id, message_id),
    FOREIGN KEY (realization_assertion_id, thread_version_id)
        REFERENCES working.first_party_context_thread_realization_assertion(id, thread_version_id) ON DELETE RESTRICT,
    FOREIGN KEY (thread_version_id, message_id)
        REFERENCES working.first_party_context_thread_message(thread_version_id, message_id) ON DELETE RESTRICT
);

CREATE TABLE working.third_party_context_thread_realization_source (
    realization_assertion_id UUID NOT NULL,
    thread_version_id UUID NOT NULL,
    thread_source_id UUID NOT NULL,
    required_for_realization BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (realization_assertion_id, thread_source_id),
    FOREIGN KEY (realization_assertion_id, thread_version_id)
        REFERENCES working.third_party_context_thread_realization_assertion(id, thread_version_id) ON DELETE RESTRICT,
    FOREIGN KEY (thread_source_id, thread_version_id)
        REFERENCES working.third_party_context_thread_source(id, thread_version_id) ON DELETE RESTRICT
);

CREATE TABLE working.third_party_context_thread_realization_message (
    realization_assertion_id UUID NOT NULL,
    thread_version_id UUID NOT NULL,
    message_id UUID NOT NULL,
    required_for_realization BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (realization_assertion_id, message_id),
    FOREIGN KEY (realization_assertion_id, thread_version_id)
        REFERENCES working.third_party_context_thread_realization_assertion(id, thread_version_id) ON DELETE RESTRICT,
    FOREIGN KEY (thread_version_id, message_id)
        REFERENCES working.third_party_context_thread_message(thread_version_id, message_id) ON DELETE RESTRICT
);

-- Shared relative-time subsystem.  Primary tables retain their authoritative
-- occurred_at/acquisition clocks.  These versioned assertions express only an
-- unresolved or approximate placement when a primary clock is unavailable.
-- Typed link tables prevent weak entity_type/entity_id pointers or nullable-FK soup.
CREATE TABLE context.relative_time_anchor (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    anchor_key UUID NOT NULL DEFAULT uuidv7(),
    version_ordinal INTEGER NOT NULL CHECK (version_ordinal > 0),
    placement_kind TEXT NOT NULL
        CHECK (placement_kind IN ('before', 'after', 'between', 'sequence_only', 'metadata_approximation')),
    lower_bound_at TIMESTAMPTZ,
    upper_bound_at TIMESTAMPTZ,
    last_known_before_anchor_id UUID REFERENCES context.relative_time_anchor(id) ON DELETE RESTRICT,
    first_known_after_anchor_id UUID REFERENCES context.relative_time_anchor(id) ON DELETE RESTRICT,
    contextual_sequence_key TEXT,
    contextual_sequence_ordinal BIGINT,
    metadata_basis TEXT NOT NULL CHECK (length(btrim(metadata_basis)) > 0),
    raw_metadata JSONB NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(raw_metadata) = 'object'),
    raw_metadata_ref TEXT,
    confidence DOUBLE PRECISION NOT NULL CHECK (confidence BETWEEN 0 AND 1),
    ambiguity TEXT,
    review_state TEXT NOT NULL CHECK (review_state IN ('proposed', 'approved', 'rejected', 'superseded')),
    reviewed_by TEXT,
    reviewed_at TIMESTAMPTZ,
    provenance_digest BYTEA NOT NULL CHECK (octet_length(provenance_digest) = 32),
    supersedes_id UUID REFERENCES context.relative_time_anchor(id) ON DELETE RESTRICT,
    presentation_payload JSONB NOT NULL DEFAULT '{}'::jsonb
        CHECK (jsonb_typeof(presentation_payload) = 'object'),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (anchor_key, version_ordinal),
    UNIQUE (id, anchor_key),
    CHECK (upper_bound_at IS NULL OR lower_bound_at IS NULL OR upper_bound_at >= lower_bound_at),
    CHECK (contextual_sequence_ordinal IS NULL OR contextual_sequence_key IS NOT NULL),
    CHECK (lower_bound_at IS NOT NULL OR upper_bound_at IS NOT NULL
           OR last_known_before_anchor_id IS NOT NULL OR first_known_after_anchor_id IS NOT NULL
           OR contextual_sequence_key IS NOT NULL),
    CHECK (last_known_before_anchor_id IS DISTINCT FROM id
           AND first_known_after_anchor_id IS DISTINCT FROM id),
    CHECK (review_state <> 'approved' OR (reviewed_by IS NOT NULL AND reviewed_at IS NOT NULL))
);

CREATE INDEX relative_time_anchor_bounds_idx
    ON context.relative_time_anchor (lower_bound_at, upper_bound_at);

CREATE TABLE context.first_party_thread_version_relative_time_anchor (
    anchor_id UUID PRIMARY KEY REFERENCES context.relative_time_anchor(id) ON DELETE RESTRICT,
    thread_version_id UUID NOT NULL REFERENCES working.first_party_context_thread_version(id) ON DELETE RESTRICT,
    link_role TEXT NOT NULL CHECK (link_role IN ('primary_fallback', 'lower_bound', 'upper_bound', 'sequence_context')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (thread_version_id, anchor_id)
);

CREATE TABLE context.third_party_thread_version_relative_time_anchor (
    anchor_id UUID PRIMARY KEY REFERENCES context.relative_time_anchor(id) ON DELETE RESTRICT,
    thread_version_id UUID NOT NULL REFERENCES working.third_party_context_thread_version(id) ON DELETE RESTRICT,
    link_role TEXT NOT NULL CHECK (link_role IN ('primary_fallback', 'lower_bound', 'upper_bound', 'sequence_context')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (thread_version_id, anchor_id)
);

CREATE TABLE context.first_party_thread_source_relative_time_anchor (
    anchor_id UUID PRIMARY KEY REFERENCES context.relative_time_anchor(id) ON DELETE RESTRICT,
    thread_source_id UUID NOT NULL REFERENCES working.first_party_context_thread_source(id) ON DELETE RESTRICT,
    link_role TEXT NOT NULL CHECK (link_role IN ('primary_fallback', 'lower_bound', 'upper_bound', 'sequence_context')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (thread_source_id, anchor_id)
);

CREATE TABLE context.third_party_thread_source_relative_time_anchor (
    anchor_id UUID PRIMARY KEY REFERENCES context.relative_time_anchor(id) ON DELETE RESTRICT,
    thread_source_id UUID NOT NULL REFERENCES working.third_party_context_thread_source(id) ON DELETE RESTRICT,
    link_role TEXT NOT NULL CHECK (link_role IN ('primary_fallback', 'lower_bound', 'upper_bound', 'sequence_context')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (thread_source_id, anchor_id)
);

CREATE TABLE context.first_party_thread_message_relative_time_anchor (
    anchor_id UUID PRIMARY KEY REFERENCES context.relative_time_anchor(id) ON DELETE RESTRICT,
    thread_version_id UUID NOT NULL,
    message_id UUID NOT NULL,
    link_role TEXT NOT NULL CHECK (link_role IN ('primary_fallback', 'lower_bound', 'upper_bound', 'sequence_context')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    FOREIGN KEY (thread_version_id, message_id)
        REFERENCES working.first_party_context_thread_message(thread_version_id, message_id) ON DELETE RESTRICT
);

CREATE TABLE context.third_party_thread_message_relative_time_anchor (
    anchor_id UUID PRIMARY KEY REFERENCES context.relative_time_anchor(id) ON DELETE RESTRICT,
    thread_version_id UUID NOT NULL,
    message_id UUID NOT NULL,
    link_role TEXT NOT NULL CHECK (link_role IN ('primary_fallback', 'lower_bound', 'upper_bound', 'sequence_context')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    FOREIGN KEY (thread_version_id, message_id)
        REFERENCES working.third_party_context_thread_message(thread_version_id, message_id) ON DELETE RESTRICT
);

CREATE TABLE timeline.event_candidate_relative_time_anchor (
    event_candidate_id UUID NOT NULL REFERENCES timeline.event_candidate(id) ON DELETE RESTRICT,
    anchor_id UUID NOT NULL REFERENCES context.relative_time_anchor(id) ON DELETE RESTRICT,
    anchor_role TEXT NOT NULL
        CHECK (anchor_role IN ('occurred_at', 'valid_from', 'valid_to',
                               'source_available_from', 'realizable_from')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (event_candidate_id, anchor_id, anchor_role)
);

COMMENT ON TABLE context.relative_time_anchor IS
    'Append-only reviewed fallback placement when an authoritative primary timestamp is unavailable. JSON payloads are presentation only; typed link tables are authority.';
COMMENT ON TABLE context.first_party_thread_version_relative_time_anchor IS
    'Typed first-party fallback link. Primary availability remains occurred_at, never screenshot/export metadata.';
COMMENT ON TABLE context.third_party_thread_version_relative_time_anchor IS
    'Typed third-party fallback link. Primary availability remains custody-backed acquisition; capture/export clocks never backdate it.';
COMMENT ON TABLE timeline.event_candidate_relative_time_anchor IS
    'Typed append-only relative-time link for event-candidate temporal roles. Corrections are new anchor versions/links, never JSON authority.';
COMMENT ON COLUMN timeline.event_candidate.source_locator IS
    'Compatibility/presentation projection only. Typed source authority is timeline.event_candidate_source_range -> context.source_range_locator.';

-- Shared HITL conflict plane.  Review subjects are linked through dedicated FK
-- tables below; conflict_kind is routing vocabulary, never a polymorphic pointer.
CREATE TABLE working.context_review_case (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    case_key UUID NOT NULL DEFAULT uuidv7(),
    case_version INTEGER NOT NULL CHECK (case_version > 0),
    conflict_kind TEXT NOT NULL
        CHECK (conflict_kind IN ('relative_time', 'first_party_thread', 'third_party_thread',
                                 'source_representation_equivalence', 'timeline_event')),
    status TEXT NOT NULL DEFAULT 'queued'
        CHECK (status IN ('queued', 'resolved', 'withdrawn', 'superseded')),
    priority TEXT NOT NULL DEFAULT 'normal' CHECK (priority IN ('low', 'normal', 'high', 'critical')),
    summary TEXT NOT NULL CHECK (length(btrim(summary)) > 0),
    opened_by TEXT NOT NULL CHECK (length(btrim(opened_by)) > 0),
    provenance_digest BYTEA NOT NULL CHECK (octet_length(provenance_digest) = 32),
    supersedes_case_id UUID,
    supersedes_case_version INTEGER,
    resolution_decision_id UUID,
    resolution_decision_version INTEGER,
    presentation_payload JSONB NOT NULL DEFAULT '{}'::jsonb
        CHECK (jsonb_typeof(presentation_payload) = 'object'),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (case_key, case_version),
    UNIQUE (id, case_version),
    UNIQUE (id, case_version, case_key),
    FOREIGN KEY (supersedes_case_id, supersedes_case_version, case_key)
        REFERENCES working.context_review_case(id, case_version, case_key) ON DELETE RESTRICT,
    CHECK ((supersedes_case_id IS NULL) = (supersedes_case_version IS NULL)),
    CHECK ((resolution_decision_id IS NULL) = (resolution_decision_version IS NULL)),
    CHECK ((case_version = 1 AND supersedes_case_id IS NULL)
        OR (case_version > 1 AND supersedes_case_id IS NOT NULL)),
    CHECK ((status = 'resolved') = (resolution_decision_id IS NOT NULL))
);

CREATE INDEX context_review_case_queue_idx
    ON working.context_review_case (status, priority, created_at);
CREATE INDEX context_review_case_key_version_idx
    ON working.context_review_case (case_key, case_version DESC);

CREATE TABLE working.context_review_decision (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    review_case_id UUID NOT NULL REFERENCES working.context_review_case(id) ON DELETE RESTRICT,
    decision_version INTEGER NOT NULL CHECK (decision_version > 0),
    decision_action TEXT NOT NULL
        CHECK (decision_action IN ('accept', 'reject', 'coexist', 'supersede_correct', 'needs_more_evidence')),
    status TEXT NOT NULL CHECK (status IN ('proposed', 'final', 'superseded')),
    reviewer_id TEXT NOT NULL CHECK (length(btrim(reviewer_id)) > 0),
    rationale TEXT NOT NULL CHECK (length(btrim(rationale)) > 0),
    provenance_digest BYTEA NOT NULL CHECK (octet_length(provenance_digest) = 32),
    decision_activity_receipt_id UUID REFERENCES context.activity_receipt(id) ON DELETE RESTRICT,
    supersedes_decision_id UUID,
    supersedes_decision_version INTEGER,
    decided_at TIMESTAMPTZ NOT NULL,
    presentation_payload JSONB NOT NULL DEFAULT '{}'::jsonb
        CHECK (jsonb_typeof(presentation_payload) = 'object'),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (review_case_id, decision_version),
    UNIQUE (id, review_case_id),
    UNIQUE (id, decision_version),
    FOREIGN KEY (supersedes_decision_id, supersedes_decision_version)
        REFERENCES working.context_review_decision(id, decision_version) ON DELETE RESTRICT,
    CHECK ((supersedes_decision_id IS NULL) = (supersedes_decision_version IS NULL)),
    CHECK ((decision_action = 'supersede_correct') = (supersedes_decision_id IS NOT NULL)),
    CHECK (status <> 'final' OR decision_activity_receipt_id IS NOT NULL)
);

ALTER TABLE working.context_review_case
    ADD CONSTRAINT context_review_case_resolution_decision_fk
    FOREIGN KEY (resolution_decision_id, resolution_decision_version)
    REFERENCES working.context_review_decision(id, decision_version)
    ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED;

CREATE INDEX context_review_decision_case_idx
    ON working.context_review_decision (review_case_id, decision_version DESC);

CREATE VIEW working.context_review_current_decision AS
SELECT DISTINCT ON (review_case_id)
       review_case_id, id AS decision_id, decision_version, decision_action, status,
       reviewer_id, rationale, decided_at, provenance_digest
FROM working.context_review_decision
WHERE status = 'final'
ORDER BY review_case_id, decision_version DESC, decided_at DESC, id DESC;

CREATE VIEW working.context_review_current_case AS
SELECT DISTINCT ON (case_key)
       case_key, id AS review_case_id, case_version, conflict_kind, status,
       priority, summary, opened_by, resolution_decision_id,
       resolution_decision_version, created_at
FROM working.context_review_case
ORDER BY case_key, case_version DESC, created_at DESC, id DESC;

CREATE VIEW working.context_review_open_queue AS
SELECT current_case.*
FROM working.context_review_current_case current_case
WHERE current_case.status = 'queued';

CREATE TABLE working.context_review_relative_time_anchor (
    review_case_id UUID NOT NULL REFERENCES working.context_review_case(id) ON DELETE RESTRICT,
    anchor_id UUID NOT NULL REFERENCES context.relative_time_anchor(id) ON DELETE RESTRICT,
    subject_role TEXT NOT NULL CHECK (subject_role IN ('candidate', 'conflicting', 'context')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (review_case_id, anchor_id, subject_role)
);

CREATE TABLE working.context_review_first_party_thread_version (
    review_case_id UUID NOT NULL REFERENCES working.context_review_case(id) ON DELETE RESTRICT,
    thread_version_id UUID NOT NULL REFERENCES working.first_party_context_thread_version(id) ON DELETE RESTRICT,
    subject_role TEXT NOT NULL CHECK (subject_role IN ('candidate', 'conflicting', 'context')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (review_case_id, thread_version_id, subject_role)
);

CREATE TABLE working.context_review_third_party_thread_version (
    review_case_id UUID NOT NULL REFERENCES working.context_review_case(id) ON DELETE RESTRICT,
    thread_version_id UUID NOT NULL REFERENCES working.third_party_context_thread_version(id) ON DELETE RESTRICT,
    subject_role TEXT NOT NULL CHECK (subject_role IN ('candidate', 'conflicting', 'context')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (review_case_id, thread_version_id, subject_role)
);

CREATE TABLE working.context_review_first_party_thread_message (
    review_case_id UUID NOT NULL REFERENCES working.context_review_case(id) ON DELETE RESTRICT,
    thread_version_id UUID NOT NULL,
    message_id UUID NOT NULL,
    subject_role TEXT NOT NULL CHECK (subject_role IN ('candidate', 'conflicting', 'context')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (review_case_id, thread_version_id, message_id, subject_role),
    FOREIGN KEY (thread_version_id, message_id)
        REFERENCES working.first_party_context_thread_message(thread_version_id, message_id) ON DELETE RESTRICT
);

CREATE TABLE working.context_review_third_party_thread_message (
    review_case_id UUID NOT NULL REFERENCES working.context_review_case(id) ON DELETE RESTRICT,
    thread_version_id UUID NOT NULL,
    message_id UUID NOT NULL,
    subject_role TEXT NOT NULL CHECK (subject_role IN ('candidate', 'conflicting', 'context')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (review_case_id, thread_version_id, message_id, subject_role),
    FOREIGN KEY (thread_version_id, message_id)
        REFERENCES working.third_party_context_thread_message(thread_version_id, message_id) ON DELETE RESTRICT
);

CREATE TABLE working.context_review_first_party_thread_source (
    review_case_id UUID NOT NULL REFERENCES working.context_review_case(id) ON DELETE RESTRICT,
    thread_source_id UUID NOT NULL REFERENCES working.first_party_context_thread_source(id) ON DELETE RESTRICT,
    subject_role TEXT NOT NULL CHECK (subject_role IN ('candidate', 'conflicting', 'context')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (review_case_id, thread_source_id, subject_role)
);

CREATE TABLE working.context_review_third_party_thread_source (
    review_case_id UUID NOT NULL REFERENCES working.context_review_case(id) ON DELETE RESTRICT,
    thread_source_id UUID NOT NULL REFERENCES working.third_party_context_thread_source(id) ON DELETE RESTRICT,
    subject_role TEXT NOT NULL CHECK (subject_role IN ('candidate', 'conflicting', 'context')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (review_case_id, thread_source_id, subject_role)
);

CREATE TABLE working.context_review_timeline_event_candidate (
    review_case_id UUID NOT NULL REFERENCES working.context_review_case(id) ON DELETE RESTRICT,
    event_candidate_id UUID NOT NULL REFERENCES timeline.event_candidate(id) ON DELETE RESTRICT,
    subject_role TEXT NOT NULL CHECK (subject_role IN ('candidate', 'conflicting', 'context')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (review_case_id, event_candidate_id, subject_role)
);

-- Typed provenance supporting an adjudication decision.  JSON remains presentation-only.
CREATE TABLE working.context_review_decision_source_version (
    decision_id UUID NOT NULL REFERENCES working.context_review_decision(id) ON DELETE RESTRICT,
    source_version_id UUID NOT NULL REFERENCES context.source_version(id) ON DELETE RESTRICT,
    basis_role TEXT NOT NULL CHECK (basis_role IN ('supporting', 'contradicting', 'context')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (decision_id, source_version_id, basis_role)
);

CREATE TABLE working.context_review_decision_source_range (
    decision_id UUID NOT NULL REFERENCES working.context_review_decision(id) ON DELETE RESTRICT,
    source_version_id UUID NOT NULL,
    source_range_locator_id UUID NOT NULL,
    basis_role TEXT NOT NULL CHECK (basis_role IN ('supporting', 'contradicting', 'context')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (decision_id, source_range_locator_id, basis_role),
    FOREIGN KEY (source_range_locator_id, source_version_id)
        REFERENCES context.source_range_locator(id, source_version_id) ON DELETE RESTRICT
);

CREATE TABLE working.context_review_decision_evidence_hash (
    decision_id UUID NOT NULL REFERENCES working.context_review_decision(id) ON DELETE RESTRICT,
    evidence_hash_id UUID NOT NULL REFERENCES evidence.evidence_hash(id) ON DELETE RESTRICT,
    basis_role TEXT NOT NULL CHECK (basis_role IN ('supporting', 'contradicting', 'context')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (decision_id, evidence_hash_id, basis_role)
);

-- Durable HITL orchestration coordinates only; Temporal payloads remain external.
-- One stable workflow identity exists per review case. Run/state snapshots are append-only.
CREATE TABLE working.context_review_temporal_workflow (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    review_case_id UUID NOT NULL UNIQUE,
    expected_case_version INTEGER NOT NULL CHECK (expected_case_version > 0),
    temporal_workflow_id TEXT NOT NULL UNIQUE CHECK (length(btrim(temporal_workflow_id)) > 0),
    workflow_idempotency_key TEXT NOT NULL UNIQUE CHECK (length(btrim(workflow_idempotency_key)) > 0),
    reminder_policy_ref TEXT NOT NULL CHECK (length(btrim(reminder_policy_ref)) > 0),
    escalation_policy_ref TEXT NOT NULL CHECK (length(btrim(escalation_policy_ref)) > 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (id, review_case_id),
    FOREIGN KEY (review_case_id, expected_case_version)
        REFERENCES working.context_review_case(id, case_version) ON DELETE RESTRICT
);

CREATE TABLE working.context_review_temporal_run_state (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    review_workflow_id UUID NOT NULL
        REFERENCES working.context_review_temporal_workflow(id) ON DELETE RESTRICT,
    temporal_run_id TEXT NOT NULL CHECK (length(btrim(temporal_run_id)) > 0),
    state_version INTEGER NOT NULL CHECK (state_version > 0),
    workflow_state TEXT NOT NULL
        CHECK (workflow_state IN ('running', 'waiting_for_human', 'reminder_due',
                                  'escalated', 'continued_as_new', 'terminal')),
    state_digest BYTEA NOT NULL CHECK (octet_length(state_digest) = 32),
    trace_ref TEXT,
    supersedes_state_id UUID REFERENCES working.context_review_temporal_run_state(id) ON DELETE RESTRICT,
    observed_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (review_workflow_id, temporal_run_id, state_version),
    UNIQUE (id, review_workflow_id)
);

CREATE INDEX context_review_temporal_run_state_idx
    ON working.context_review_temporal_run_state
       (review_workflow_id, temporal_run_id, state_version DESC);

CREATE TABLE working.context_review_dispatch_attempt (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    review_workflow_id UUID NOT NULL
        REFERENCES working.context_review_temporal_workflow(id) ON DELETE RESTRICT,
    dispatch_attempt INTEGER NOT NULL CHECK (dispatch_attempt > 0),
    dispatch_idempotency_key TEXT NOT NULL CHECK (length(btrim(dispatch_idempotency_key)) > 0),
    n8n_workflow_ref TEXT NOT NULL CHECK (length(btrim(n8n_workflow_ref)) > 0),
    review_service_ref TEXT NOT NULL CHECK (length(btrim(review_service_ref)) > 0),
    request_digest BYTEA NOT NULL CHECK (octet_length(request_digest) = 32),
    dispatch_receipt_digest BYTEA CHECK (dispatch_receipt_digest IS NULL OR octet_length(dispatch_receipt_digest) = 32),
    status TEXT NOT NULL CHECK (status IN ('dispatched', 'acknowledged', 'failed', 'not_applicable')),
    started_at TIMESTAMPTZ NOT NULL,
    completed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (review_workflow_id, dispatch_attempt),
    UNIQUE (review_workflow_id, dispatch_idempotency_key)
);

CREATE INDEX context_review_dispatch_status_idx
    ON working.context_review_dispatch_attempt (status, started_at);

CREATE TABLE working.context_review_signal_receipt (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    review_workflow_id UUID NOT NULL,
    review_case_id UUID NOT NULL,
    decision_id UUID NOT NULL,
    signal_id TEXT NOT NULL CHECK (length(btrim(signal_id)) > 0),
    signal_idempotency_key TEXT NOT NULL CHECK (length(btrim(signal_idempotency_key)) > 0),
    signal_kind TEXT NOT NULL CHECK (signal_kind IN ('decision', 'request_more_evidence', 'cancel')),
    signal_digest BYTEA NOT NULL CHECK (octet_length(signal_digest) = 32),
    validation_status TEXT NOT NULL CHECK (validation_status IN ('accepted', 'rejected', 'duplicate')),
    persisted_decision_version INTEGER NOT NULL CHECK (persisted_decision_version > 0),
    received_at TIMESTAMPTZ NOT NULL,
    persisted_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (review_workflow_id, signal_id),
    UNIQUE (review_workflow_id, signal_idempotency_key),
    FOREIGN KEY (review_workflow_id, review_case_id)
        REFERENCES working.context_review_temporal_workflow(id, review_case_id) ON DELETE RESTRICT,
    FOREIGN KEY (decision_id, review_case_id)
        REFERENCES working.context_review_decision(id, review_case_id) ON DELETE RESTRICT,
    CHECK ((validation_status = 'accepted') = (persisted_at IS NOT NULL))
);

CREATE TABLE working.context_review_terminal_reconciliation (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    review_workflow_id UUID NOT NULL UNIQUE,
    review_case_id UUID NOT NULL,
    final_decision_id UUID,
    expected_case_version INTEGER NOT NULL CHECK (expected_case_version > 0),
    expected_decision_version INTEGER CHECK (expected_decision_version IS NULL OR expected_decision_version > 0),
    terminal_status TEXT NOT NULL CHECK (terminal_status IN ('completed', 'cancelled', 'failed')),
    reconciliation_status TEXT NOT NULL CHECK (reconciliation_status IN ('matched', 'mismatch', 'incomplete')),
    reconciliation_digest BYTEA NOT NULL CHECK (octet_length(reconciliation_digest) = 32),
    downstream_projection_receipt_ref TEXT,
    reconciled_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    FOREIGN KEY (review_workflow_id, review_case_id)
        REFERENCES working.context_review_temporal_workflow(id, review_case_id) ON DELETE RESTRICT,
    FOREIGN KEY (review_case_id, expected_case_version)
        REFERENCES working.context_review_case(id, case_version) ON DELETE RESTRICT,
    FOREIGN KEY (final_decision_id, review_case_id)
        REFERENCES working.context_review_decision(id, review_case_id) ON DELETE RESTRICT,
    CHECK ((terminal_status = 'completed' AND final_decision_id IS NOT NULL
            AND expected_decision_version IS NOT NULL)
           OR terminal_status <> 'completed')
);

CREATE INDEX context_review_terminal_reconciliation_status_idx
    ON working.context_review_terminal_reconciliation (reconciliation_status, reconciled_at);

COMMENT ON TABLE working.context_review_case IS
    'Shared Workbench review queue case. Typed membership tables identify conflicts; presentation_payload is not authority.';
COMMENT ON TABLE working.context_review_decision IS
    'Append-only versioned human adjudication. Current activation is a view; corrections create superseding decision rows.';
COMMENT ON TABLE working.context_review_temporal_workflow IS
    'One durable Temporal ConflictReviewWorkflow identity per PostgreSQL-canonical review case. Stores references/digests only, never Temporal payloads.';
COMMENT ON TABLE working.context_review_dispatch_attempt IS
    'Short activity dispatch receipt. n8n selects/invokes swappable review UI/service/notification adapters but is never approval authority.';
COMMENT ON TABLE working.context_review_signal_receipt IS
    'Idempotent signal receipt binding the Temporal workflow to the PostgreSQL-canonical append-only decision.';
COMMENT ON TABLE working.context_review_terminal_reconciliation IS
    'Terminal reconciliation of expected case/decision versions and downstream reprojection receipt; no workflow payload storage.';

-- -------- fail-closed guards --------

CREATE OR REPLACE FUNCTION working.guard_review_state_authority()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog
AS $$
BEGIN
    IF NEW.review_state <> 'proposed'
       AND NOT pg_has_role(session_user, 'context_review_adjudicator', 'MEMBER') THEN
        RAISE EXCEPTION 'only context_review_adjudicator may assert reviewed or superseded state';
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION working.guard_context_review_case_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, working
AS $$
DECLARE
    v_previous working.context_review_case%ROWTYPE;
    v_decision_case_key UUID;
BEGIN
    IF NEW.case_version = 1 THEN
        IF NEW.status <> 'queued' OR NEW.supersedes_case_id IS NOT NULL THEN
            RAISE EXCEPTION 'initial review case version must be queued and unsuperseded';
        END IF;
    ELSE
        IF NOT pg_has_role(session_user, 'context_review_adjudicator', 'MEMBER') THEN
            RAISE EXCEPTION 'only context_review_adjudicator may append review-case lifecycle versions';
        END IF;
        SELECT * INTO v_previous
        FROM working.context_review_case
        WHERE id = NEW.supersedes_case_id
          AND case_key = NEW.case_key
          AND case_version = NEW.supersedes_case_version;
        IF NOT FOUND OR NEW.case_version <> v_previous.case_version + 1
           OR NEW.conflict_kind <> v_previous.conflict_kind THEN
            RAISE EXCEPTION 'review-case lifecycle version must directly supersede the same logical conflict';
        END IF;
    END IF;
    IF NEW.status = 'resolved' THEN
        SELECT review_case.case_key INTO v_decision_case_key
        FROM working.context_review_decision decision
        JOIN working.context_review_case review_case ON review_case.id = decision.review_case_id
        WHERE decision.id = NEW.resolution_decision_id
          AND decision.decision_version = NEW.resolution_decision_version
          AND decision.status = 'final';
        IF NOT FOUND OR v_decision_case_key <> NEW.case_key THEN
            RAISE EXCEPTION 'resolved review-case version requires a final decision for the same logical case';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION working.guard_context_review_decision_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, working
AS $$
BEGIN
    IF NOT pg_has_role(session_user, 'context_review_adjudicator', 'MEMBER') THEN
        RAISE EXCEPTION 'only context_review_adjudicator may insert adjudication decisions';
    END IF;
    IF NEW.supersedes_decision_id IS NOT NULL AND NOT EXISTS (
        SELECT 1
        FROM working.context_review_decision previous
        WHERE previous.id = NEW.supersedes_decision_id
          AND previous.decision_version = NEW.supersedes_decision_version
          AND previous.review_case_id = NEW.review_case_id
    ) THEN
        RAISE EXCEPTION 'decision correction must supersede a decision for the same review case';
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION working.guard_source_range_locator_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, context
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM context.activity_receipt receipt
        JOIN context.activity_execution execution ON execution.id = receipt.activity_execution_id
        WHERE receipt.id = NEW.verification_activity_receipt_id
          AND receipt.status = 'success'
          AND execution.source_version_id = NEW.source_version_id
    ) THEN
        RAISE EXCEPTION 'source range locator requires a successful same-source verification receipt';
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION working.validate_source_range_locator_subject(p_locator_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, context
AS $$
DECLARE
    v_subject_count BIGINT;
BEGIN
    SELECT (SELECT count(*) FROM context.source_object_range_locator WHERE source_range_locator_id = p_locator_id)
         + (SELECT count(*) FROM context.raw_record_range_locator WHERE source_range_locator_id = p_locator_id)
         + (SELECT count(*) FROM context.normalized_record_range_locator WHERE source_range_locator_id = p_locator_id)
      INTO v_subject_count;
    IF v_subject_count <> 1 THEN
        RAISE EXCEPTION 'source range locator requires exactly one typed subject link';
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION working.check_source_range_locator_subject_deferred()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, working
AS $$
BEGIN
    PERFORM working.validate_source_range_locator_subject(
        CASE WHEN TG_TABLE_NAME = 'source_range_locator' THEN NEW.id
             ELSE NEW.source_range_locator_id END
    );
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION working.guard_source_range_typed_subject_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, context
AS $$
DECLARE
    v_locator context.source_range_locator%ROWTYPE;
    v_bytes BYTEA;
    v_length BIGINT;
    v_slice BYTEA;
BEGIN
    SELECT * INTO v_locator FROM context.source_range_locator
    WHERE id = NEW.source_range_locator_id;
    IF TG_TABLE_NAME = 'source_object_range_locator' THEN
        SELECT object.inline_bytes, object.byte_length INTO v_bytes, v_length
        FROM context.source_version version
        JOIN context.retained_object object ON object.id = version.original_object_id
        WHERE version.id = NEW.source_version_id
          AND version.status = 'retained'
          AND version.original_object_id = NEW.source_object_id;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'source-object locator must bind source_version.original_object_id';
        END IF;
    ELSIF TG_TABLE_NAME = 'raw_record_range_locator' THEN
        SELECT raw.stored_bytes, COALESCE(octet_length(raw.stored_bytes), raw.byte_length)
          INTO v_bytes, v_length
        FROM context.raw_record_identity raw WHERE raw.id = NEW.raw_record_id;
    ELSE
        SELECT normalized.canonical_bytes, octet_length(normalized.canonical_bytes)
          INTO v_bytes, v_length
        FROM context.normalized_record_identity normalized WHERE normalized.id = NEW.normalized_record_id;
    END IF;
    IF v_bytes IS NULL THEN
        RAISE EXCEPTION 'exact source locator requires retained bytes available to PostgreSQL for verification';
    END IF;
    IF v_locator.range_end > 2147483647 OR v_locator.range_start > 2147483647 THEN
        RAISE EXCEPTION 'exact source locator exceeds PostgreSQL substring coordinate range';
    END IF;
    IF v_locator.coordinate_system = 'utf8_bytes' THEN
        v_length := octet_length(v_bytes);
        IF v_locator.range_end > v_length THEN
            RAISE EXCEPTION 'source range locator exceeds its typed subject byte length';
        END IF;
        v_slice := substring(v_bytes FROM (v_locator.range_start + 1)::INTEGER
                             FOR (v_locator.range_end - v_locator.range_start)::INTEGER);
    ELSE
        BEGIN
            v_length := char_length(convert_from(v_bytes, 'UTF8'));
            IF v_locator.range_end > v_length THEN
                RAISE EXCEPTION 'source range locator exceeds its typed subject codepoint length';
            END IF;
            v_slice := convert_to(
                substring(convert_from(v_bytes, 'UTF8')
                          FROM (v_locator.range_start + 1)::INTEGER
                          FOR (v_locator.range_end - v_locator.range_start)::INTEGER),
                'UTF8'
            );
        EXCEPTION WHEN character_not_in_repertoire OR untranslatable_character THEN
            RAISE EXCEPTION 'Unicode-codepoint locator requires valid UTF-8 retained bytes';
        END;
    END IF;
    IF digest(v_slice, 'sha256') <> v_locator.exact_slice_sha256 THEN
        RAISE EXCEPTION 'source range exact slice hash does not match DB-verified bytes';
    END IF;
    IF v_locator.range_end > v_length THEN
        RAISE EXCEPTION 'source range locator exceeds its typed subject length';
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION working.guard_content_chunk_generation_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, working, context
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM context.activity_receipt receipt
        WHERE receipt.id = NEW.activity_receipt_id
          AND receipt.activity_execution_id = NEW.activity_execution_id
          AND receipt.status = 'success'
    ) THEN
        RAISE EXCEPTION 'content chunk generation requires its successful activity receipt';
    END IF;
    IF NEW.requires_verbatim_reassembly AND NOT EXISTS (
        SELECT 1
        FROM context.source_version version
        JOIN context.retained_object object ON object.id = version.original_object_id
        WHERE version.id = NEW.source_version_id
          AND version.status = 'retained'
          AND object.content_sha256 = NEW.source_sha256
          AND object.byte_length = NEW.source_byte_length
    ) THEN
        RAISE EXCEPTION 'verbatim generation source hash/length must match the retained original';
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION working.guard_content_chunk_generation_transition()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, working
AS $$
DECLARE
    v_chunk_count BIGINT;
    v_member_count BIGINT;
    v_bad_chunk_count BIGINT;
    v_range_start BIGINT;
    v_range_end BIGINT;
    v_range_length BIGINT;
    v_gap_count BIGINT;
    v_overlap_count BIGINT;
    v_receipt working.content_chunk_reassembly_receipt%ROWTYPE;
BEGIN
    IF TG_OP = 'DELETE' OR OLD.status <> 'open' OR NEW.status NOT IN ('sealed', 'aborted') THEN
        RAISE EXCEPTION 'content chunk generations allow only open -> sealed|aborted';
    END IF;
    IF (NEW.source_version_id, NEW.normalized_generation_id, NEW.generation_ordinal,
        NEW.completeness_scope, NEW.requires_verbatim_reassembly, NEW.policy_id,
        NEW.policy_version, NEW.chunker_id, NEW.chunker_version, NEW.config_digest,
        NEW.schema_version, NEW.implementation_digest, NEW.source_view,
        NEW.source_canonicalization, NEW.source_sha256, NEW.source_byte_length,
        NEW.source_codepoint_length, NEW.activity_execution_id, NEW.activity_receipt_id,
        NEW.created_at)
       IS DISTINCT FROM
       (OLD.source_version_id, OLD.normalized_generation_id, OLD.generation_ordinal,
        OLD.completeness_scope, OLD.requires_verbatim_reassembly, OLD.policy_id,
        OLD.policy_version, OLD.chunker_id, OLD.chunker_version, OLD.config_digest,
        OLD.schema_version, OLD.implementation_digest, OLD.source_view,
        OLD.source_canonicalization, OLD.source_sha256, OLD.source_byte_length,
        OLD.source_codepoint_length, OLD.activity_execution_id, OLD.activity_receipt_id,
        OLD.created_at) THEN
        RAISE EXCEPTION 'content chunk generation identity/policy/source fields are immutable';
    END IF;
    IF NEW.status = 'sealed' THEN
        SELECT count(*) INTO v_chunk_count FROM working.content_chunk WHERE generation_id = NEW.id;
        SELECT count(*) INTO v_member_count FROM working.content_chunk_source_span WHERE generation_id = NEW.id;
        IF NEW.chunk_count <> v_chunk_count OR NEW.member_count <> v_member_count THEN
            RAISE EXCEPTION 'sealed chunk/member counts do not match materialized rows';
        END IF;
        IF NEW.completeness_scope = 'complete' AND NEW.requires_verbatim_reassembly THEN
            SELECT count(*) INTO v_bad_chunk_count
            FROM working.content_chunk chunk
            LEFT JOIN LATERAL (
                SELECT count(*) AS span_count,
                       bool_and(locator.coordinate_system = 'utf8_bytes') AS byte_coordinates,
                       bool_and(locator.exact_slice_sha256 = chunk.content_sha256) AS exact_hash,
                       bool_and(object_subject.source_object_id = version.original_object_id
                                AND retained.inline_bytes IS NOT NULL
                                AND retained.content_sha256 = NEW.source_sha256
                                AND retained.byte_length = NEW.source_byte_length) AS retained_original
                FROM working.content_chunk_source_span span
                JOIN context.source_range_locator locator
                  ON locator.id = span.source_range_locator_id
                 AND locator.source_version_id = span.source_version_id
                JOIN context.source_object_range_locator object_subject
                  ON object_subject.source_range_locator_id = locator.id
                 AND object_subject.source_version_id = locator.source_version_id
                JOIN context.source_version version
                  ON version.id = locator.source_version_id
                JOIN context.retained_object retained
                  ON retained.id = version.original_object_id
                WHERE span.chunk_id = chunk.id
            ) proof ON true
            WHERE chunk.generation_id = NEW.id
              AND (chunk.derivation_mode <> 'verbatim_span'
                   OR proof.span_count <> 1
                   OR proof.byte_coordinates IS DISTINCT FROM true
                   OR proof.exact_hash IS DISTINCT FROM true
                   OR proof.retained_original IS DISTINCT FROM true);
            IF v_bad_chunk_count <> 0 THEN
                RAISE EXCEPTION 'complete verbatim generation requires one DB-verified UTF-8 byte locator into source_version.original_object_id per chunk';
            END IF;

            WITH ordered AS (
                SELECT locator.range_start,
                       locator.range_end,
                       lag(locator.range_end) OVER (ORDER BY locator.range_start, locator.range_end) AS previous_end
                FROM working.content_chunk_source_span span
                JOIN context.source_range_locator locator
                  ON locator.id = span.source_range_locator_id
                 AND locator.source_version_id = span.source_version_id
                WHERE span.generation_id = NEW.id
            )
            SELECT min(range_start), max(range_end), sum(range_end - range_start),
                   count(*) FILTER (WHERE previous_end IS NOT NULL AND range_start > previous_end),
                   count(*) FILTER (WHERE previous_end IS NOT NULL AND range_start < previous_end)
              INTO v_range_start, v_range_end, v_range_length, v_gap_count, v_overlap_count
            FROM ordered;
            IF v_chunk_count = 0 OR v_member_count <> v_chunk_count
               OR v_range_start <> 0 OR v_range_end <> NEW.source_byte_length
               OR v_range_length <> NEW.source_byte_length
               OR v_gap_count <> 0 OR v_overlap_count <> 0 THEN
                RAISE EXCEPTION 'complete verbatim locator ranges must cover source bytes exactly once without gaps or overlaps';
            END IF;

            SELECT * INTO v_receipt
            FROM working.content_chunk_reassembly_receipt
            WHERE generation_id = NEW.id;
            IF NOT FOUND
               OR v_receipt.verification_result <> 'exact'
               OR v_receipt.source_sha256 <> NEW.source_sha256
               OR v_receipt.reassembled_sha256 <> NEW.source_sha256
               OR v_receipt.source_byte_length <> NEW.source_byte_length
               OR v_receipt.covered_range_start <> v_range_start
               OR v_receipt.covered_range_end <> NEW.source_byte_length
               OR v_receipt.gap_count <> v_gap_count
               OR v_receipt.overlap_count <> v_overlap_count
               OR v_receipt.chunk_count <> NEW.chunk_count
               OR v_receipt.member_count <> NEW.member_count THEN
                RAISE EXCEPTION 'complete verbatim generation requires exact full-coverage reassembly';
            END IF;
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION working.guard_content_chunk_child()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, working
AS $$
DECLARE
    v_generation_id UUID;
BEGIN
    IF TG_OP IN ('UPDATE', 'DELETE') THEN
        RAISE EXCEPTION '% is immutable', TG_TABLE_NAME;
    END IF;
    v_generation_id := NEW.generation_id;
    PERFORM 1 FROM working.content_chunk_generation
    WHERE id = v_generation_id AND status = 'open' FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION '% insert requires an open content chunk generation', TG_TABLE_NAME;
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION working.guard_content_chunk_span()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, working
AS $$
BEGIN
    IF TG_OP IN ('UPDATE', 'DELETE') THEN
        RAISE EXCEPTION 'content chunk source spans are immutable';
    END IF;
    PERFORM 1 FROM working.content_chunk_generation
    WHERE id = NEW.generation_id AND status = 'open' FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'source span insert requires an open content chunk generation';
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION working.guard_content_chunk_receipt()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, working, context
AS $$
DECLARE
    v_execution_id UUID;
BEGIN
    IF TG_OP IN ('UPDATE', 'DELETE') THEN
        RAISE EXCEPTION 'content chunk reassembly receipts are immutable';
    END IF;
    SELECT activity_execution_id INTO v_execution_id
    FROM context.activity_receipt
    WHERE id = NEW.activity_receipt_id AND status = 'success';
    IF v_execution_id IS NULL OR NOT EXISTS (
        SELECT 1 FROM context.activity_execution execution
        WHERE execution.id = v_execution_id
          AND execution.source_version_id = NEW.source_version_id
    ) THEN
        RAISE EXCEPTION 'reassembly receipt requires a successful same-source activity receipt';
    END IF;
    PERFORM 1 FROM working.content_chunk_generation
    WHERE id = NEW.generation_id AND status = 'open' FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'reassembly receipt requires an open generation';
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION working.guard_event_candidate_source_range_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, context
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM context.activity_receipt receipt
        JOIN context.activity_execution execution
          ON execution.id = receipt.activity_execution_id
        WHERE receipt.id = NEW.extraction_activity_receipt_id
          AND receipt.status = 'success'
          AND execution.source_version_id = NEW.source_version_id
    ) THEN
        RAISE EXCEPTION 'timeline source range requires a successful independent same-source extraction receipt';
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION working.guard_first_party_context_thread()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, working
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM working.person
        WHERE id = NEW.owner_person_id AND role_in_case = 'user'
    ) THEN
        RAISE EXCEPTION 'first-party context thread requires the configured owner person';
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION working.guard_third_party_thread_message()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, working, evidence
AS $$
DECLARE
    v_conversation_id UUID;
    v_occurred_at TIMESTAMPTZ;
    v_acquired_at TIMESTAMPTZ;
BEGIN
    SELECT message.conversation_id, message.occurred_at
      INTO v_conversation_id, v_occurred_at
    FROM working.third_party_message message WHERE message.id = NEW.message_id;
    IF NOT FOUND OR NEW.occurred_at IS DISTINCT FROM v_occurred_at THEN
        RAISE EXCEPTION 'third-party thread membership occurred_at must equal the canonical message occurrence';
    END IF;
    SELECT acquisition.acquired_at INTO v_acquired_at
    FROM working.third_party_conversation_acquisition link
    JOIN evidence.acquisition acquisition ON acquisition.id = link.acquisition_id
    WHERE link.id = NEW.conversation_acquisition_id
      AND link.conversation_id = v_conversation_id
      AND link.approval_state = 'approved';
    IF NOT FOUND OR NEW.source_available_from IS DISTINCT FROM v_acquired_at THEN
        RAISE EXCEPTION 'third-party source availability must equal approved custody-backed acquisition time';
    END IF;
    IF EXISTS (
        SELECT 1 FROM working.third_party_message message
        JOIN working.person owner ON owner.role_in_case = 'user'
        WHERE message.id = NEW.message_id AND message.sender_entity_id = owner.id
    ) OR EXISTS (
        SELECT 1 FROM working.third_party_message_participant participant
        JOIN working.person owner ON owner.id = participant.entity_id AND owner.role_in_case = 'user'
        WHERE participant.message_id = NEW.message_id
    ) THEN
        RAISE EXCEPTION 'third-party context cannot include or invent owner participation';
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION working.guard_first_party_thread_message()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, working
AS $$
DECLARE
    v_occurred_at TIMESTAMPTZ;
BEGIN
    SELECT message.ts_utc INTO v_occurred_at
    FROM working.message message
    WHERE message.id = NEW.message_id AND message.projection_kind = 'first_party';
    IF NOT FOUND OR NEW.occurred_at IS DISTINCT FROM v_occurred_at
       OR NEW.source_available_from IS DISTINCT FROM v_occurred_at THEN
        RAISE EXCEPTION 'first-party availability must equal the message occurred_at clock';
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION working.guard_first_party_thread_source()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, working, context
AS $$
DECLARE
    v_owner UUID;
BEGIN
    SELECT thread.owner_person_id INTO v_owner
    FROM working.first_party_context_thread thread
    WHERE thread.context_thread_id = NEW.context_thread_id;
    IF NEW.perspective_person_id <> v_owner THEN
        RAISE EXCEPTION 'first-party source perspective must anchor the configured owner';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM context.source_version version
        JOIN context.source source ON source.id = version.source_id
        WHERE version.id = NEW.source_version_id
          AND source.provenance_class = 'first_party_authored'
          AND version.declared_format = NEW.declared_format
    ) THEN
        RAISE EXCEPTION 'first-party source anchor requires matching first-party source provenance';
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION working.guard_third_party_thread_source()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, working, context, evidence
AS $$
DECLARE
    v_acquired_at TIMESTAMPTZ;
BEGIN
    IF EXISTS (SELECT 1 FROM working.person WHERE id = NEW.perspective_entity_id AND role_in_case = 'user') THEN
        RAISE EXCEPTION 'third-party source perspective cannot be the owner';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM context.source_version version
        JOIN context.source source ON source.id = version.source_id
        WHERE version.id = NEW.source_version_id
          AND source.provenance_class = 'acquired_third_party'
          AND version.declared_format = NEW.declared_format
    ) THEN
        RAISE EXCEPTION 'third-party source anchor requires matching acquired-third-party provenance';
    END IF;
    SELECT acquisition.acquired_at INTO v_acquired_at
    FROM working.third_party_conversation_acquisition link
    JOIN evidence.acquisition acquisition ON acquisition.id = link.acquisition_id
    WHERE link.id = NEW.conversation_acquisition_id
      AND link.conversation_id = NEW.represented_conversation_id
      AND link.approval_state = 'approved';
    IF NOT FOUND OR NEW.source_available_from IS DISTINCT FROM v_acquired_at THEN
        RAISE EXCEPTION 'third-party source availability cannot be backdated to capture/export metadata';
    END IF;
    IF NOT EXISTS (
        SELECT 1
        FROM context.activity_receipt receipt
        JOIN context.activity_execution execution
          ON execution.id = receipt.activity_execution_id
        WHERE receipt.id = NEW.acquisition_activity_receipt_id
          AND receipt.status = 'success'
          AND execution.source_version_id = NEW.source_version_id
    ) THEN
        RAISE EXCEPTION 'third-party source representation requires a successful same-source acquisition receipt';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM working.third_party_conversation conversation
        WHERE conversation.id = NEW.represented_conversation_id
          AND conversation.platform = NEW.platform
          AND conversation.external_thread_key = NEW.platform_conversation_key
    ) THEN
        RAISE EXCEPTION 'third-party source platform key must match its typed represented conversation';
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION working.validate_first_party_context_thread_version(p_version_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, working, context
AS $$
DECLARE
    v_version working.first_party_context_thread_version%ROWTYPE;
    v_message_count BIGINT;
    v_first TIMESTAMPTZ;
    v_last TIMESTAMPTZ;
    v_required_source_count BIGINT;
    v_missing_exact_count BIGINT;
    v_missing_anchor_count BIGINT;
    v_available TIMESTAMPTZ;
BEGIN
    SELECT * INTO v_version FROM working.first_party_context_thread_version WHERE id = p_version_id;
    SELECT count(*), min(occurred_at), max(occurred_at)
      INTO v_message_count, v_first, v_last
    FROM working.first_party_context_thread_message WHERE thread_version_id = p_version_id;
    IF v_message_count = 0 OR (v_version.first_occurred_at, v_version.last_occurred_at)
       IS DISTINCT FROM (v_first, v_last) THEN
        RAISE EXCEPTION 'first-party thread bounds must equal its message occurred_at bounds';
    END IF;
    WITH required_member AS (
        SELECT 'message'::TEXT AS member_kind, message_id AS member_id, source_available_from
        FROM working.first_party_context_thread_message
        WHERE thread_version_id = p_version_id AND required_for_horizon
        UNION ALL
        SELECT 'source', id, source_available_from
        FROM working.first_party_context_thread_source
        WHERE thread_version_id = p_version_id AND required_for_horizon
    )
    SELECT count(*), count(*) FILTER (WHERE source_available_from IS NULL),
           CASE WHEN bool_or(source_available_from IS NULL) THEN NULL
                ELSE max(source_available_from) END
      INTO v_required_source_count, v_missing_exact_count, v_available
    FROM required_member;
    SELECT count(*) INTO v_missing_anchor_count
    FROM (
        SELECT membership.message_id
        FROM working.first_party_context_thread_message membership
        WHERE membership.thread_version_id = p_version_id
          AND membership.required_for_horizon
          AND membership.source_available_from IS NULL
          AND NOT EXISTS (
              SELECT 1
              FROM context.first_party_thread_message_relative_time_anchor link
              JOIN context.relative_time_anchor anchor ON anchor.id = link.anchor_id
              WHERE link.thread_version_id = membership.thread_version_id
                AND link.message_id = membership.message_id
                AND link.link_role = 'primary_fallback'
                AND anchor.review_state IN ('proposed', 'approved')
          )
        UNION ALL
        SELECT source.id
        FROM working.first_party_context_thread_source source
        WHERE source.thread_version_id = p_version_id
          AND source.required_for_horizon
          AND source.source_available_from IS NULL
          AND NOT EXISTS (
              SELECT 1
              FROM context.first_party_thread_source_relative_time_anchor link
              JOIN context.relative_time_anchor anchor ON anchor.id = link.anchor_id
              WHERE link.thread_source_id = source.id
                AND link.link_role = 'primary_fallback'
                AND anchor.review_state IN ('proposed', 'approved')
          )
    ) missing_anchor;
    IF v_required_source_count = 0 OR v_missing_anchor_count <> 0
       OR v_version.knowledge_available_from IS DISTINCT FROM v_available THEN
        RAISE EXCEPTION 'first-party knowledge availability must be the greatest required occurred_at availability';
    END IF;
    IF v_missing_exact_count > 0 AND v_version.knowledge_available_from IS NOT NULL THEN
        RAISE EXCEPTION 'first-party required NULL clocks prohibit an exact thread horizon';
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION working.validate_third_party_context_thread_version(p_version_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, working, context
AS $$
DECLARE
    v_version working.third_party_context_thread_version%ROWTYPE;
    v_message_count BIGINT;
    v_first TIMESTAMPTZ;
    v_last TIMESTAMPTZ;
    v_required_source_count BIGINT;
    v_missing_exact_count BIGINT;
    v_missing_anchor_count BIGINT;
    v_available TIMESTAMPTZ;
BEGIN
    SELECT * INTO v_version FROM working.third_party_context_thread_version WHERE id = p_version_id;
    SELECT count(*), min(occurred_at), max(occurred_at)
      INTO v_message_count, v_first, v_last
    FROM working.third_party_context_thread_message WHERE thread_version_id = p_version_id;
    IF v_message_count = 0 OR (v_version.first_occurred_at, v_version.last_occurred_at)
       IS DISTINCT FROM (v_first, v_last) THEN
        RAISE EXCEPTION 'third-party thread bounds must equal its message occurred_at bounds';
    END IF;
    WITH required_member AS (
        SELECT 'message'::TEXT AS member_kind, message_id AS member_id, source_available_from
        FROM working.third_party_context_thread_message
        WHERE thread_version_id = p_version_id AND required_for_horizon
        UNION ALL
        SELECT 'source', id, source_available_from
        FROM working.third_party_context_thread_source
        WHERE thread_version_id = p_version_id AND required_for_horizon
    )
    SELECT count(*), count(*) FILTER (WHERE source_available_from IS NULL),
           CASE WHEN bool_or(source_available_from IS NULL) THEN NULL
                ELSE max(source_available_from) END
      INTO v_required_source_count, v_missing_exact_count, v_available
    FROM required_member;
    SELECT count(*) INTO v_missing_anchor_count
    FROM (
        SELECT membership.message_id
        FROM working.third_party_context_thread_message membership
        WHERE membership.thread_version_id = p_version_id
          AND membership.required_for_horizon
          AND membership.source_available_from IS NULL
          AND NOT EXISTS (
              SELECT 1
              FROM context.third_party_thread_message_relative_time_anchor link
              JOIN context.relative_time_anchor anchor ON anchor.id = link.anchor_id
              WHERE link.thread_version_id = membership.thread_version_id
                AND link.message_id = membership.message_id
                AND link.link_role = 'primary_fallback'
                AND anchor.review_state IN ('proposed', 'approved')
          )
        UNION ALL
        SELECT source.id
        FROM working.third_party_context_thread_source source
        WHERE source.thread_version_id = p_version_id
          AND source.required_for_horizon
          AND source.source_available_from IS NULL
          AND NOT EXISTS (
              SELECT 1
              FROM context.third_party_thread_source_relative_time_anchor link
              JOIN context.relative_time_anchor anchor ON anchor.id = link.anchor_id
              WHERE link.thread_source_id = source.id
                AND link.link_role = 'primary_fallback'
                AND anchor.review_state IN ('proposed', 'approved')
          )
    ) missing_anchor;
    IF v_required_source_count = 0 OR v_missing_anchor_count <> 0
       OR v_version.knowledge_available_from IS DISTINCT FROM v_available THEN
        RAISE EXCEPTION 'third-party knowledge availability must be the greatest required custody-backed availability';
    END IF;
    IF EXISTS (
        SELECT 1
        FROM working.third_party_context_thread_source source
        WHERE source.thread_version_id = p_version_id
          AND NOT EXISTS (
              SELECT 1
              FROM working.third_party_context_thread_message membership
              JOIN working.third_party_message message ON message.id = membership.message_id
              WHERE membership.thread_version_id = p_version_id
                AND message.conversation_id = source.represented_conversation_id
          )
    ) THEN
        RAISE EXCEPTION 'third-party source represented conversation must belong to the same thread version';
    END IF;
    IF v_missing_exact_count > 0 AND v_version.knowledge_available_from IS NOT NULL THEN
        RAISE EXCEPTION 'third-party required NULL clocks prohibit an exact thread horizon';
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION working.check_context_thread_version_deferred()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, working
AS $$
DECLARE
    v_version_id UUID;
BEGIN
    IF TG_TABLE_NAME LIKE '%_thread_version' THEN
        v_version_id := NEW.id;
    ELSE
        v_version_id := NEW.thread_version_id;
    END IF;
    IF TG_TABLE_NAME LIKE 'first_party_%' THEN
        PERFORM working.validate_first_party_context_thread_version(v_version_id);
    ELSE
        PERFORM working.validate_third_party_context_thread_version(v_version_id);
    END IF;
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION working.validate_context_thread_realization_sources(
    p_assertion_id UUID,
    p_party TEXT
) RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, working
AS $$
DECLARE
    v_required_count BIGINT;
    v_missing_exact_count BIGINT;
    v_missing_anchor_count BIGINT;
    v_available TIMESTAMPTZ;
    v_recorded TIMESTAMPTZ;
BEGIN
    IF p_party = 'first_party' THEN
        WITH required_member AS (
            SELECT 'message'::TEXT AS member_kind, message.message_id AS member_id,
                   message.source_available_from
            FROM working.first_party_context_thread_realization_message link
            JOIN working.first_party_context_thread_message message
              ON message.thread_version_id = link.thread_version_id
             AND message.message_id = link.message_id
            WHERE link.realization_assertion_id = p_assertion_id AND link.required_for_realization
            UNION ALL
            SELECT 'source', source.id, source.source_available_from
            FROM working.first_party_context_thread_realization_source link
            JOIN working.first_party_context_thread_source source
              ON source.id = link.thread_source_id
            WHERE link.realization_assertion_id = p_assertion_id AND link.required_for_realization
        )
        SELECT count(*), count(*) FILTER (WHERE source_available_from IS NULL),
               CASE WHEN bool_or(source_available_from IS NULL) THEN NULL
                    ELSE max(source_available_from) END
          INTO v_required_count, v_missing_exact_count, v_available
        FROM required_member;
        SELECT count(*) INTO v_missing_anchor_count
        FROM (
            SELECT message.message_id
            FROM working.first_party_context_thread_realization_message link
            JOIN working.first_party_context_thread_message message
              ON message.thread_version_id = link.thread_version_id
             AND message.message_id = link.message_id
            WHERE link.realization_assertion_id = p_assertion_id
              AND link.required_for_realization AND message.source_available_from IS NULL
              AND NOT EXISTS (
                  SELECT 1 FROM context.first_party_thread_message_relative_time_anchor anchor_link
                  JOIN context.relative_time_anchor anchor ON anchor.id = anchor_link.anchor_id
                  WHERE anchor_link.thread_version_id = message.thread_version_id
                    AND anchor_link.message_id = message.message_id
                    AND anchor_link.link_role = 'primary_fallback'
                    AND anchor.review_state IN ('proposed', 'approved')
              )
            UNION ALL
            SELECT source.id
            FROM working.first_party_context_thread_realization_source link
            JOIN working.first_party_context_thread_source source ON source.id = link.thread_source_id
            WHERE link.realization_assertion_id = p_assertion_id
              AND link.required_for_realization AND source.source_available_from IS NULL
              AND NOT EXISTS (
                  SELECT 1 FROM context.first_party_thread_source_relative_time_anchor anchor_link
                  JOIN context.relative_time_anchor anchor ON anchor.id = anchor_link.anchor_id
                  WHERE anchor_link.thread_source_id = source.id
                    AND anchor_link.link_role = 'primary_fallback'
                    AND anchor.review_state IN ('proposed', 'approved')
              )
        ) missing_anchor;
        SELECT required_source_available_from INTO v_recorded
        FROM working.first_party_context_thread_realization_assertion WHERE id = p_assertion_id;
    ELSIF p_party = 'third_party' THEN
        WITH required_member AS (
            SELECT 'message'::TEXT AS member_kind, message.message_id AS member_id,
                   message.source_available_from
            FROM working.third_party_context_thread_realization_message link
            JOIN working.third_party_context_thread_message message
              ON message.thread_version_id = link.thread_version_id
             AND message.message_id = link.message_id
            WHERE link.realization_assertion_id = p_assertion_id AND link.required_for_realization
            UNION ALL
            SELECT 'source', source.id, source.source_available_from
            FROM working.third_party_context_thread_realization_source link
            JOIN working.third_party_context_thread_source source ON source.id = link.thread_source_id
            WHERE link.realization_assertion_id = p_assertion_id AND link.required_for_realization
        )
        SELECT count(*), count(*) FILTER (WHERE source_available_from IS NULL),
               CASE WHEN bool_or(source_available_from IS NULL) THEN NULL
                    ELSE max(source_available_from) END
          INTO v_required_count, v_missing_exact_count, v_available
        FROM required_member;
        SELECT count(*) INTO v_missing_anchor_count
        FROM (
            SELECT message.message_id
            FROM working.third_party_context_thread_realization_message link
            JOIN working.third_party_context_thread_message message
              ON message.thread_version_id = link.thread_version_id
             AND message.message_id = link.message_id
            WHERE link.realization_assertion_id = p_assertion_id
              AND link.required_for_realization AND message.source_available_from IS NULL
              AND NOT EXISTS (
                  SELECT 1 FROM context.third_party_thread_message_relative_time_anchor anchor_link
                  JOIN context.relative_time_anchor anchor ON anchor.id = anchor_link.anchor_id
                  WHERE anchor_link.thread_version_id = message.thread_version_id
                    AND anchor_link.message_id = message.message_id
                    AND anchor_link.link_role = 'primary_fallback'
                    AND anchor.review_state IN ('proposed', 'approved')
              )
            UNION ALL
            SELECT source.id
            FROM working.third_party_context_thread_realization_source link
            JOIN working.third_party_context_thread_source source ON source.id = link.thread_source_id
            WHERE link.realization_assertion_id = p_assertion_id
              AND link.required_for_realization AND source.source_available_from IS NULL
              AND NOT EXISTS (
                  SELECT 1 FROM context.third_party_thread_source_relative_time_anchor anchor_link
                  JOIN context.relative_time_anchor anchor ON anchor.id = anchor_link.anchor_id
                  WHERE anchor_link.thread_source_id = source.id
                    AND anchor_link.link_role = 'primary_fallback'
                    AND anchor.review_state IN ('proposed', 'approved')
              )
        ) missing_anchor;
        SELECT required_source_available_from INTO v_recorded
        FROM working.third_party_context_thread_realization_assertion WHERE id = p_assertion_id;
    ELSE
        RAISE EXCEPTION 'unknown context-thread party %', p_party;
    END IF;
    IF v_required_count = 0 OR v_missing_anchor_count <> 0
       OR v_recorded IS DISTINCT FROM v_available
       OR (v_missing_exact_count > 0 AND v_recorded IS NOT NULL) THEN
        RAISE EXCEPTION 'realization assertion availability must equal the greatest required source availability';
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION working.check_context_thread_realization_deferred()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, working
AS $$
DECLARE
    v_assertion_id UUID;
    v_party TEXT;
BEGIN
    IF TG_TABLE_NAME LIKE '%_realization_assertion' THEN
        v_assertion_id := NEW.id;
    ELSE
        v_assertion_id := NEW.realization_assertion_id;
    END IF;
    IF TG_TABLE_NAME LIKE 'first_party_%' THEN
        v_party := 'first_party';
    ELSE
        v_party := 'third_party';
    END IF;
    PERFORM working.validate_context_thread_realization_sources(v_assertion_id, v_party);
    RETURN NULL;
END;
$$;

CREATE TRIGGER content_chunk_generation_insert_gate
    BEFORE INSERT ON working.content_chunk_generation
    FOR EACH ROW EXECUTE FUNCTION working.guard_content_chunk_generation_insert();
CREATE TRIGGER source_range_locator_insert_gate
    BEFORE INSERT ON context.source_range_locator
    FOR EACH ROW EXECUTE FUNCTION working.guard_source_range_locator_insert();
CREATE TRIGGER source_object_range_locator_insert_gate
    BEFORE INSERT ON context.source_object_range_locator
    FOR EACH ROW EXECUTE FUNCTION working.guard_source_range_typed_subject_insert();
CREATE TRIGGER raw_record_range_locator_insert_gate
    BEFORE INSERT ON context.raw_record_range_locator
    FOR EACH ROW EXECUTE FUNCTION working.guard_source_range_typed_subject_insert();
CREATE TRIGGER normalized_record_range_locator_insert_gate
    BEFORE INSERT ON context.normalized_record_range_locator
    FOR EACH ROW EXECUTE FUNCTION working.guard_source_range_typed_subject_insert();
CREATE CONSTRAINT TRIGGER source_range_locator_one_typed_subject
    AFTER INSERT ON context.source_range_locator
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION working.check_source_range_locator_subject_deferred();
CREATE CONSTRAINT TRIGGER source_object_range_locator_one_typed_subject
    AFTER INSERT ON context.source_object_range_locator
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION working.check_source_range_locator_subject_deferred();
CREATE CONSTRAINT TRIGGER raw_record_range_locator_one_typed_subject
    AFTER INSERT ON context.raw_record_range_locator
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION working.check_source_range_locator_subject_deferred();
CREATE CONSTRAINT TRIGGER normalized_record_range_locator_one_typed_subject
    AFTER INSERT ON context.normalized_record_range_locator
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION working.check_source_range_locator_subject_deferred();
CREATE TRIGGER content_chunk_generation_transition_gate
    BEFORE UPDATE OR DELETE ON working.content_chunk_generation
    FOR EACH ROW EXECUTE FUNCTION working.guard_content_chunk_generation_transition();
CREATE TRIGGER content_chunk_open_generation_gate
    BEFORE INSERT OR UPDATE OR DELETE ON working.content_chunk
    FOR EACH ROW EXECUTE FUNCTION working.guard_content_chunk_child();
CREATE TRIGGER content_chunk_source_span_gate
    BEFORE INSERT OR UPDATE OR DELETE ON working.content_chunk_source_span
    FOR EACH ROW EXECUTE FUNCTION working.guard_content_chunk_span();
CREATE TRIGGER content_chunk_reassembly_receipt_gate
    BEFORE INSERT OR UPDATE OR DELETE ON working.content_chunk_reassembly_receipt
    FOR EACH ROW EXECUTE FUNCTION working.guard_content_chunk_receipt();
CREATE TRIGGER event_candidate_source_range_insert_gate
    BEFORE INSERT ON timeline.event_candidate_source_range
    FOR EACH ROW EXECUTE FUNCTION working.guard_event_candidate_source_range_insert();
CREATE TRIGGER content_chunk_initial_context
    AFTER INSERT ON working.content_chunk
    FOR EACH ROW EXECUTE FUNCTION working.insert_initial_content_chunk_context();
CREATE TRIGGER content_chunk_classification_append_only
    BEFORE UPDATE OR DELETE ON working.content_chunk_classification_decision
    FOR EACH ROW EXECUTE FUNCTION working.forbid_context_foundation_mutation();
CREATE TRIGGER context_review_case_insert_gate
    BEFORE INSERT ON working.context_review_case
    FOR EACH ROW EXECUTE FUNCTION working.guard_context_review_case_insert();
CREATE TRIGGER context_review_decision_insert_gate
    BEFORE INSERT ON working.context_review_decision
    FOR EACH ROW EXECUTE FUNCTION working.guard_context_review_decision_insert();

CREATE TRIGGER first_party_thread_version_review_authority
    BEFORE INSERT ON working.first_party_context_thread_version
    FOR EACH ROW EXECUTE FUNCTION working.guard_review_state_authority();
CREATE TRIGGER third_party_thread_version_review_authority
    BEFORE INSERT ON working.third_party_context_thread_version
    FOR EACH ROW EXECUTE FUNCTION working.guard_review_state_authority();
CREATE TRIGGER first_party_thread_source_review_authority
    BEFORE INSERT ON working.first_party_context_thread_source
    FOR EACH ROW EXECUTE FUNCTION working.guard_review_state_authority();
CREATE TRIGGER third_party_thread_source_review_authority
    BEFORE INSERT ON working.third_party_context_thread_source
    FOR EACH ROW EXECUTE FUNCTION working.guard_review_state_authority();
CREATE TRIGGER first_party_realization_review_authority
    BEFORE INSERT ON working.first_party_context_thread_realization_assertion
    FOR EACH ROW EXECUTE FUNCTION working.guard_review_state_authority();
CREATE TRIGGER third_party_realization_review_authority
    BEFORE INSERT ON working.third_party_context_thread_realization_assertion
    FOR EACH ROW EXECUTE FUNCTION working.guard_review_state_authority();
CREATE TRIGGER relative_time_anchor_review_authority
    BEFORE INSERT ON context.relative_time_anchor
    FOR EACH ROW EXECUTE FUNCTION working.guard_review_state_authority();

CREATE TRIGGER first_party_context_thread_owner_gate
    BEFORE INSERT ON working.first_party_context_thread
    FOR EACH ROW EXECUTE FUNCTION working.guard_first_party_context_thread();
CREATE TRIGGER first_party_context_thread_message_gate
    BEFORE INSERT ON working.first_party_context_thread_message
    FOR EACH ROW EXECUTE FUNCTION working.guard_first_party_thread_message();
CREATE TRIGGER third_party_context_thread_message_gate
    BEFORE INSERT ON working.third_party_context_thread_message
    FOR EACH ROW EXECUTE FUNCTION working.guard_third_party_thread_message();
CREATE TRIGGER first_party_context_thread_source_gate
    BEFORE INSERT ON working.first_party_context_thread_source
    FOR EACH ROW EXECUTE FUNCTION working.guard_first_party_thread_source();
CREATE TRIGGER third_party_context_thread_source_gate
    BEFORE INSERT ON working.third_party_context_thread_source
    FOR EACH ROW EXECUTE FUNCTION working.guard_third_party_thread_source();

CREATE CONSTRAINT TRIGGER first_party_context_thread_version_complete
    AFTER INSERT ON working.first_party_context_thread_version
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION working.check_context_thread_version_deferred();
CREATE CONSTRAINT TRIGGER first_party_context_thread_message_complete
    AFTER INSERT ON working.first_party_context_thread_message
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION working.check_context_thread_version_deferred();
CREATE CONSTRAINT TRIGGER first_party_context_thread_source_complete
    AFTER INSERT ON working.first_party_context_thread_source
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION working.check_context_thread_version_deferred();
CREATE CONSTRAINT TRIGGER third_party_context_thread_version_complete
    AFTER INSERT ON working.third_party_context_thread_version
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION working.check_context_thread_version_deferred();
CREATE CONSTRAINT TRIGGER third_party_context_thread_message_complete
    AFTER INSERT ON working.third_party_context_thread_message
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION working.check_context_thread_version_deferred();
CREATE CONSTRAINT TRIGGER third_party_context_thread_source_complete
    AFTER INSERT ON working.third_party_context_thread_source
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION working.check_context_thread_version_deferred();

CREATE CONSTRAINT TRIGGER first_party_context_thread_realization_complete
    AFTER INSERT ON working.first_party_context_thread_realization_assertion
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION working.check_context_thread_realization_deferred();
CREATE CONSTRAINT TRIGGER first_party_context_thread_realization_source_complete
    AFTER INSERT ON working.first_party_context_thread_realization_source
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION working.check_context_thread_realization_deferred();
CREATE CONSTRAINT TRIGGER first_party_context_thread_realization_message_complete
    AFTER INSERT ON working.first_party_context_thread_realization_message
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION working.check_context_thread_realization_deferred();
CREATE CONSTRAINT TRIGGER third_party_context_thread_realization_complete
    AFTER INSERT ON working.third_party_context_thread_realization_assertion
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION working.check_context_thread_realization_deferred();
CREATE CONSTRAINT TRIGGER third_party_context_thread_realization_source_complete
    AFTER INSERT ON working.third_party_context_thread_realization_source
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION working.check_context_thread_realization_deferred();
CREATE CONSTRAINT TRIGGER third_party_context_thread_realization_message_complete
    AFTER INSERT ON working.third_party_context_thread_realization_message
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION working.check_context_thread_realization_deferred();

DO $$
DECLARE
    v_relation REGCLASS;
BEGIN
    FOREACH v_relation IN ARRAY ARRAY[
        'working.legacy_chat_chunk_content_chunk_map'::regclass,
        'working.legacy_normalized_chunk_content_chunk_map'::regclass,
        'context.source_range_locator'::regclass,
        'context.source_object_range_locator'::regclass,
        'context.raw_record_range_locator'::regclass,
        'context.normalized_record_range_locator'::regclass,
        'timeline.event_candidate_source_range'::regclass,
        'working.first_party_context_thread'::regclass,
        'working.third_party_context_thread'::regclass,
        'working.first_party_context_thread_version'::regclass,
        'working.third_party_context_thread_version'::regclass,
        'working.first_party_context_thread_message'::regclass,
        'working.third_party_context_thread_message'::regclass,
        'working.first_party_context_thread_source'::regclass,
        'working.third_party_context_thread_source'::regclass,
        'working.first_party_context_thread_realization_assertion'::regclass,
        'working.third_party_context_thread_realization_assertion'::regclass,
        'working.first_party_context_thread_realization_source'::regclass,
        'working.first_party_context_thread_realization_message'::regclass,
        'working.third_party_context_thread_realization_source'::regclass,
        'working.third_party_context_thread_realization_message'::regclass,
        'context.relative_time_anchor'::regclass,
        'context.first_party_thread_version_relative_time_anchor'::regclass,
        'context.third_party_thread_version_relative_time_anchor'::regclass,
        'context.first_party_thread_source_relative_time_anchor'::regclass,
        'context.third_party_thread_source_relative_time_anchor'::regclass,
        'context.first_party_thread_message_relative_time_anchor'::regclass,
        'context.third_party_thread_message_relative_time_anchor'::regclass,
        'timeline.event_candidate_relative_time_anchor'::regclass
    ] LOOP
        EXECUTE format(
            'CREATE TRIGGER context_foundation_append_only BEFORE UPDATE OR DELETE ON %s '
            'FOR EACH ROW EXECUTE FUNCTION working.forbid_context_foundation_mutation()',
            v_relation
        );
    END LOOP;
END;
$$;

DO $$
DECLARE
    v_relation REGCLASS;
BEGIN
    FOREACH v_relation IN ARRAY ARRAY[
        'working.context_review_case'::regclass,
        'working.context_review_decision'::regclass,
        'working.context_review_relative_time_anchor'::regclass,
        'working.context_review_first_party_thread_version'::regclass,
        'working.context_review_third_party_thread_version'::regclass,
        'working.context_review_first_party_thread_message'::regclass,
        'working.context_review_third_party_thread_message'::regclass,
        'working.context_review_first_party_thread_source'::regclass,
        'working.context_review_third_party_thread_source'::regclass,
        'working.context_review_timeline_event_candidate'::regclass,
        'working.context_review_decision_source_version'::regclass,
        'working.context_review_decision_source_range'::regclass,
        'working.context_review_decision_evidence_hash'::regclass,
        'working.context_review_temporal_workflow'::regclass,
        'working.context_review_temporal_run_state'::regclass,
        'working.context_review_dispatch_attempt'::regclass,
        'working.context_review_signal_receipt'::regclass,
        'working.context_review_terminal_reconciliation'::regclass
    ] LOOP
        EXECUTE format(
            'CREATE TRIGGER context_review_append_only BEFORE UPDATE OR DELETE ON %s '
            'FOR EACH ROW EXECUTE FUNCTION working.forbid_context_foundation_mutation()',
            v_relation
        );
        EXECUTE format('REVOKE ALL ON TABLE %s FROM PUBLIC', v_relation);
        EXECUTE format('GRANT SELECT ON TABLE %s TO platform_runtime, context_review_adjudicator', v_relation);
    END LOOP;
    GRANT USAGE ON SCHEMA working, context, timeline TO platform_runtime, context_review_adjudicator;
    GRANT INSERT ON working.context_review_case,
                    working.context_review_relative_time_anchor,
                    working.context_review_first_party_thread_version,
                    working.context_review_third_party_thread_version,
                    working.context_review_first_party_thread_message,
                    working.context_review_third_party_thread_message,
                    working.context_review_first_party_thread_source,
                    working.context_review_third_party_thread_source,
                    working.context_review_timeline_event_candidate,
                    working.context_review_temporal_workflow,
                    working.context_review_temporal_run_state,
                    working.context_review_dispatch_attempt,
                    working.context_review_signal_receipt,
                    working.context_review_terminal_reconciliation
        TO platform_runtime;
    GRANT SELECT ON working.context_review_current_decision,
                    working.context_review_current_case,
                    working.context_review_open_queue
        TO platform_runtime, context_review_adjudicator;
    GRANT INSERT ON working.context_review_case,
                    working.context_review_decision,
                    working.context_review_decision_source_version,
                    working.context_review_decision_source_range,
                    working.context_review_decision_evidence_hash
        TO context_review_adjudicator;
END;
$$;

COMMENT ON TABLE working.content_chunk_generation IS
    'Version-pinned derived chunk manifest. Reruns create new generations; sealed/aborted generations are immutable.';
COMMENT ON TABLE working.content_chunk IS
    'One format-neutral derived chunk authority. No global content-hash uniqueness; identical text can occur at distinct source positions.';
COMMENT ON TABLE working.content_chunk_source_span IS
    'Same-source ordered chunk membership referencing the typed context.source_range_locator half-open primitive.';
COMMENT ON TABLE context.source_range_locator IS
    'Canonical typed half-open [start,end) UTF-8-byte or Unicode-codepoint source locator. locator_projection is non-authoritative.';
COMMENT ON TABLE timeline.event_candidate_source_range IS
    'Independent event-extraction provenance over the same immutable source_version/range primitive; it never carves content out of or depends on chunks.';
COMMENT ON TABLE working.content_chunk_classification_decision IS
    'Context-first append-only reviewed classification history. It deliberately has no evidence lane.';
COMMENT ON TABLE working.first_party_context_thread IS
    'Stable cross-source/cross-platform first-party human thread identity, explicitly anchored to the one owner.';
COMMENT ON TABLE working.third_party_context_thread IS
    'Stable cross-source/cross-platform acquired-third-party human thread identity. Owner participation is structurally rejected.';
COMMENT ON COLUMN working.first_party_context_thread_version.knowledge_available_from IS
    'Earliest horizon at which every required source for this version was available; distinct from message occurrence and from any claimed realization.';
COMMENT ON COLUMN working.third_party_context_thread_version.knowledge_available_from IS
    'Greatest custody-backed source_available_from among required acquired sources; never backdated to screenshot capture/export metadata.';
COMMENT ON TABLE working.third_party_context_thread_source IS
    'One immutable representation assertion per source version/version. Screenshots, OCR, native exports and device captures coexist; none is collapsed or selected as canonical.';

-- Negative contract fixture (commit f2e9d2a): Semantica StructuralChunker
-- lost 176 characters and 24/35 chunks were non-verbatim.  It is categorically
-- rejected for citation/custody paths.  This records the contract, not an implementation.
COMMENT ON COLUMN working.content_chunk.derivation_mode IS
    'Semantica StructuralChunker negative fixture f2e9d2a: its rebuilt text omitted 176 chars and 24/35 chunks were non-verbatim. Such text cannot seal a complete verbatim generation; exact original-byte offsets remain the authority.';

DO $$
DECLARE
    v_relation REGCLASS;
BEGIN
    FOREACH v_relation IN ARRAY ARRAY[
        'working.content_chunk_generation'::regclass,
        'working.content_chunk'::regclass,
        'working.content_chunk_source_span'::regclass,
        'working.content_chunk_reassembly_receipt'::regclass,
        'working.content_chunk_classification_decision'::regclass,
        'context.source_range_locator'::regclass,
        'context.source_object_range_locator'::regclass,
        'context.raw_record_range_locator'::regclass,
        'context.normalized_record_range_locator'::regclass,
        'timeline.event_candidate_source_range'::regclass,
        'working.legacy_chat_chunk_content_chunk_map'::regclass,
        'working.legacy_normalized_chunk_content_chunk_map'::regclass,
        'working.first_party_context_thread'::regclass,
        'working.third_party_context_thread'::regclass,
        'working.first_party_context_thread_version'::regclass,
        'working.third_party_context_thread_version'::regclass,
        'working.first_party_context_thread_message'::regclass,
        'working.third_party_context_thread_message'::regclass,
        'working.first_party_context_thread_source'::regclass,
        'working.third_party_context_thread_source'::regclass,
        'working.first_party_context_thread_realization_assertion'::regclass,
        'working.third_party_context_thread_realization_assertion'::regclass,
        'working.first_party_context_thread_realization_source'::regclass,
        'working.first_party_context_thread_realization_message'::regclass,
        'working.third_party_context_thread_realization_source'::regclass,
        'working.third_party_context_thread_realization_message'::regclass,
        'context.relative_time_anchor'::regclass,
        'context.first_party_thread_version_relative_time_anchor'::regclass,
        'context.third_party_thread_version_relative_time_anchor'::regclass,
        'context.first_party_thread_source_relative_time_anchor'::regclass,
        'context.third_party_thread_source_relative_time_anchor'::regclass,
        'context.first_party_thread_message_relative_time_anchor'::regclass,
        'context.third_party_thread_message_relative_time_anchor'::regclass,
        'timeline.event_candidate_relative_time_anchor'::regclass
    ] LOOP
        EXECUTE format('REVOKE ALL ON TABLE %s FROM PUBLIC', v_relation);
    END LOOP;
END;
$$;

REVOKE ALL ON working.content_chunk_current_classification,
              working.context_review_current_decision,
              working.context_review_current_case,
              working.context_review_open_queue
    FROM PUBLIC;

GRANT USAGE ON SCHEMA working, context TO platform_runtime;
GRANT SELECT ON TABLE
    working.content_chunk_generation,
    working.content_chunk,
    working.content_chunk_source_span,
    working.content_chunk_reassembly_receipt,
    working.content_chunk_classification_decision,
    working.legacy_chat_chunk_content_chunk_map,
    working.legacy_normalized_chunk_content_chunk_map,
    working.first_party_context_thread,
    working.third_party_context_thread,
    working.first_party_context_thread_version,
    working.third_party_context_thread_version,
    working.first_party_context_thread_message,
    working.third_party_context_thread_message,
    working.first_party_context_thread_source,
    working.third_party_context_thread_source,
    working.first_party_context_thread_realization_assertion,
    working.third_party_context_thread_realization_assertion,
    working.first_party_context_thread_realization_source,
    working.first_party_context_thread_realization_message,
    working.third_party_context_thread_realization_source,
    working.third_party_context_thread_realization_message,
    context.source_range_locator,
    context.source_object_range_locator,
    context.raw_record_range_locator,
    context.normalized_record_range_locator,
    context.relative_time_anchor,
    context.first_party_thread_version_relative_time_anchor,
    context.third_party_thread_version_relative_time_anchor,
    context.first_party_thread_source_relative_time_anchor,
    context.third_party_thread_source_relative_time_anchor,
    context.first_party_thread_message_relative_time_anchor,
    context.third_party_thread_message_relative_time_anchor
    TO platform_runtime, context_review_adjudicator;
GRANT SELECT ON working.content_chunk_current_classification
    TO platform_runtime, context_review_adjudicator;
GRANT INSERT ON TABLE
    working.content_chunk_generation,
    working.content_chunk,
    working.content_chunk_source_span,
    working.content_chunk_reassembly_receipt,
    working.legacy_chat_chunk_content_chunk_map,
    working.legacy_normalized_chunk_content_chunk_map,
    working.first_party_context_thread,
    working.third_party_context_thread,
    working.first_party_context_thread_version,
    working.third_party_context_thread_version,
    working.first_party_context_thread_message,
    working.third_party_context_thread_message,
    working.first_party_context_thread_source,
    working.third_party_context_thread_source,
    working.first_party_context_thread_realization_assertion,
    working.third_party_context_thread_realization_assertion,
    working.first_party_context_thread_realization_source,
    working.first_party_context_thread_realization_message,
    working.third_party_context_thread_realization_source,
    working.third_party_context_thread_realization_message,
    context.source_range_locator,
    context.source_object_range_locator,
    context.raw_record_range_locator,
    context.normalized_record_range_locator,
    context.relative_time_anchor,
    context.first_party_thread_version_relative_time_anchor,
    context.third_party_thread_version_relative_time_anchor,
    context.first_party_thread_source_relative_time_anchor,
    context.third_party_thread_source_relative_time_anchor,
    context.first_party_thread_message_relative_time_anchor,
    context.third_party_thread_message_relative_time_anchor
    TO platform_runtime;
GRANT UPDATE (status, chunk_count, member_count, manifest_sha256, sealed_at, sealed_by,
              aborted_at, abort_reason)
    ON working.content_chunk_generation TO platform_runtime;

GRANT INSERT ON working.content_chunk_classification_decision,
                working.first_party_context_thread_version,
                working.third_party_context_thread_version,
                working.first_party_context_thread_source,
                working.third_party_context_thread_source,
                working.first_party_context_thread_realization_assertion,
                working.third_party_context_thread_realization_assertion,
                context.relative_time_anchor
    TO context_review_adjudicator;

GRANT USAGE ON SCHEMA timeline TO timeline_writer, timeline_projector, timeline_reader;
GRANT SELECT, INSERT ON timeline.event_candidate_source_range,
                        timeline.event_candidate_relative_time_anchor
    TO timeline_writer;
GRANT SELECT ON timeline.event_candidate_source_range,
                timeline.event_candidate_relative_time_anchor
    TO timeline_projector;

REVOKE ALL ON FUNCTION working.forbid_context_foundation_mutation() FROM PUBLIC;
REVOKE ALL ON FUNCTION working.guard_review_state_authority() FROM PUBLIC;
REVOKE ALL ON FUNCTION working.guard_context_review_case_insert() FROM PUBLIC;
REVOKE ALL ON FUNCTION working.guard_context_review_decision_insert() FROM PUBLIC;
REVOKE ALL ON FUNCTION working.guard_source_range_locator_insert() FROM PUBLIC;
REVOKE ALL ON FUNCTION working.validate_source_range_locator_subject(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION working.check_source_range_locator_subject_deferred() FROM PUBLIC;
REVOKE ALL ON FUNCTION working.guard_source_range_typed_subject_insert() FROM PUBLIC;
REVOKE ALL ON FUNCTION working.guard_content_chunk_generation_insert() FROM PUBLIC;
REVOKE ALL ON FUNCTION working.guard_content_chunk_generation_transition() FROM PUBLIC;
REVOKE ALL ON FUNCTION working.guard_content_chunk_child() FROM PUBLIC;
REVOKE ALL ON FUNCTION working.guard_content_chunk_span() FROM PUBLIC;
REVOKE ALL ON FUNCTION working.guard_content_chunk_receipt() FROM PUBLIC;
REVOKE ALL ON FUNCTION working.guard_event_candidate_source_range_insert() FROM PUBLIC;
REVOKE ALL ON FUNCTION working.guard_first_party_context_thread() FROM PUBLIC;
REVOKE ALL ON FUNCTION working.guard_third_party_thread_message() FROM PUBLIC;
REVOKE ALL ON FUNCTION working.guard_first_party_thread_message() FROM PUBLIC;
REVOKE ALL ON FUNCTION working.guard_first_party_thread_source() FROM PUBLIC;
REVOKE ALL ON FUNCTION working.guard_third_party_thread_source() FROM PUBLIC;
REVOKE ALL ON FUNCTION working.validate_first_party_context_thread_version(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION working.validate_third_party_context_thread_version(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION working.check_context_thread_version_deferred() FROM PUBLIC;
REVOKE ALL ON FUNCTION working.validate_context_thread_realization_sources(UUID, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION working.check_context_thread_realization_deferred() FROM PUBLIC;

COMMIT;
