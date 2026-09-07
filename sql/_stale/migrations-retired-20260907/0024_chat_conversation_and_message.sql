-- 0024_chat_conversation_and_message.sql — AI-chat landing, chunk routing,
-- selective review, and the human-curated investigation register.
--
-- Raw chat ingestion is deliberately horizon-neutral. As-experienced and
-- hindsight walks are derived later from reviewed temporal assertions; they
-- are not columns or duplicate stores here. AI chat is context, never evidence.
--
-- Byline: Codex · GPT-5 · 2026-08-13

BEGIN;

CREATE TABLE working.chat_conversation (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    source TEXT NOT NULL,
    external_id TEXT NOT NULL,
    title TEXT,
    source_path TEXT,
    created_at TIMESTAMPTZ,
    ingested_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    attrs JSONB NOT NULL DEFAULT '{}' CHECK (jsonb_typeof(attrs) = 'object'),
    UNIQUE (source, external_id)
);

CREATE TABLE working.chat_message (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    conversation_id UUID NOT NULL REFERENCES working.chat_conversation(id) ON DELETE CASCADE,
    message_index INTEGER NOT NULL CHECK (message_index >= 0),
    role TEXT NOT NULL CHECK (role IN ('user','assistant','system','tool','unknown')),
    content TEXT NOT NULL DEFAULT '',
    sent_at TIMESTAMPTZ,
    thinking TEXT,
    attachments JSONB NOT NULL DEFAULT '[]' CHECK (jsonb_typeof(attachments) = 'array'),
    attrs JSONB NOT NULL DEFAULT '{}' CHECK (jsonb_typeof(attrs) = 'object'),
    content_hash TEXT NOT NULL CHECK (length(content_hash) = 64),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (conversation_id, message_index)
);

CREATE INDEX chat_message_conversation_idx
    ON working.chat_message (conversation_id, message_index);
CREATE INDEX chat_message_sent_at_idx ON working.chat_message (sent_at);

-- Extend the already-applied context asset index (0022) so generated works and
-- attachments are first-class multimodal sources rather than filename-only
-- message metadata. One asset may be referenced by several messages.
ALTER TABLE working.context_asset
    ADD COLUMN origin_kind TEXT NOT NULL DEFAULT 'export_asset'
        CHECK (origin_kind IN ('generated_work','attachment','export_asset','derived')),
    ADD COLUMN media_type TEXT,
    ADD COLUMN modality TEXT NOT NULL DEFAULT 'binary'
        CHECK (modality IN ('text','code','image','audio','video','binary')),
    ADD COLUMN extracted_text TEXT,
    ADD COLUMN extraction_tool_id TEXT,
    ADD COLUMN extraction_confidence DOUBLE PRECISION
        CHECK (extraction_confidence IS NULL OR extraction_confidence BETWEEN 0 AND 1),
    ADD COLUMN extraction_status TEXT NOT NULL DEFAULT 'pending'
        CHECK (extraction_status IN ('pending','completed','low_confidence','unsupported','failed'));

CREATE TABLE working.context_asset_message (
    asset_id UUID NOT NULL REFERENCES working.context_asset(id) ON DELETE CASCADE,
    message_id UUID NOT NULL REFERENCES working.chat_message(id) ON DELETE CASCADE,
    relationship TEXT NOT NULL DEFAULT 'referenced'
        CHECK (relationship IN ('generated_by','attached_to','referenced')),
    linked_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    attrs JSONB NOT NULL DEFAULT '{}' CHECK (jsonb_typeof(attrs) = 'object'),
    PRIMARY KEY (asset_id, message_id, relationship)
);

CREATE TABLE working.context_asset_derivation (
    parent_asset_id UUID NOT NULL REFERENCES working.context_asset(id) ON DELETE CASCADE,
    child_asset_id UUID NOT NULL REFERENCES working.context_asset(id) ON DELETE CASCADE,
    derivation_type TEXT NOT NULL
        CHECK (derivation_type IN ('ocr','transcript','keyframe','thumbnail','text_extract','conversion')),
    tool_id TEXT NOT NULL,
    tool_version TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    attrs JSONB NOT NULL DEFAULT '{}' CHECK (jsonb_typeof(attrs) = 'object'),
    PRIMARY KEY (parent_asset_id, child_asset_id, derivation_type),
    CHECK (parent_asset_id <> child_asset_id)
);

CREATE TABLE working.context_asset_projection (
    asset_id UUID NOT NULL REFERENCES working.context_asset(id) ON DELETE CASCADE,
    representation TEXT NOT NULL CHECK (representation IN ('native','extracted_text','ocr','transcript','keyframe')),
    lane TEXT NOT NULL CHECK (lane IN ('platform','legal','personal_history','context')),
    embedder_id TEXT NOT NULL,
    embedding_dimension INTEGER NOT NULL CHECK (embedding_dimension > 0),
    sink TEXT NOT NULL DEFAULT 'weaviate' CHECK (sink = 'weaviate'),
    projection_ref TEXT,
    projected_at TIMESTAMPTZ,
    last_error TEXT,
    attempts INTEGER NOT NULL DEFAULT 0 CHECK (attempts >= 0),
    attrs JSONB NOT NULL DEFAULT '{}' CHECK (jsonb_typeof(attrs) = 'object'),
    PRIMARY KEY (asset_id, representation, lane, embedder_id)
);

CREATE INDEX context_asset_projection_pending_idx
    ON working.context_asset_projection (lane, representation, asset_id)
    WHERE projected_at IS NULL;

-- Canonical chunks are stored once. A chunk may cover several adjacent turns;
-- the mapping retains exact message provenance and ordering.
CREATE TABLE working.chat_chunk (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    conversation_id UUID NOT NULL REFERENCES working.chat_conversation(id) ON DELETE CASCADE,
    chunk_index INTEGER NOT NULL CHECK (chunk_index >= 0),
    content TEXT NOT NULL CHECK (length(content) > 0),
    content_hash TEXT NOT NULL CHECK (length(content_hash) = 64),
    chunker_id TEXT NOT NULL,
    chunker_version TEXT,
    token_count INTEGER CHECK (token_count IS NULL OR token_count >= 0),
    char_start INTEGER CHECK (char_start IS NULL OR char_start >= 0),
    char_end INTEGER CHECK (char_end IS NULL OR char_end >= char_start),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    attrs JSONB NOT NULL DEFAULT '{}' CHECK (jsonb_typeof(attrs) = 'object'),
    UNIQUE (conversation_id, chunk_index),
    UNIQUE (content_hash)
);

CREATE TABLE working.chat_chunk_message (
    chunk_id UUID NOT NULL REFERENCES working.chat_chunk(id) ON DELETE CASCADE,
    message_id UUID NOT NULL REFERENCES working.chat_message(id) ON DELETE RESTRICT,
    ordinal INTEGER NOT NULL CHECK (ordinal >= 0),
    PRIMARY KEY (chunk_id, message_id),
    UNIQUE (chunk_id, ordinal)
);

-- Five global knowledge lanes: platform, legal, personal_history, context,
-- evidence. AI-chat classification may use only the first four. Evidence is
-- populated exclusively through the custody-approved evidence workflow.
CREATE TABLE working.chat_chunk_lane (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    chunk_id UUID NOT NULL REFERENCES working.chat_chunk(id) ON DELETE CASCADE,
    lane TEXT NOT NULL CHECK (lane IN ('platform','legal','personal_history','context')),
    confidence DOUBLE PRECISION NOT NULL CHECK (confidence BETWEEN 0 AND 1),
    classifier_id TEXT NOT NULL,
    classifier_version TEXT,
    review_status TEXT NOT NULL
        CHECK (review_status IN ('auto_accepted','pending_review','human_approved',
                                 'human_corrected','classification_failed')),
    rationale TEXT,
    reviewed_by TEXT,
    reviewed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    attrs JSONB NOT NULL DEFAULT '{}' CHECK (jsonb_typeof(attrs) = 'object'),
    UNIQUE (chunk_id, lane),
    CHECK ((reviewed_at IS NULL) = (reviewed_by IS NULL)),
    CHECK (review_status NOT IN ('human_approved','human_corrected') OR reviewed_at IS NOT NULL)
);

CREATE INDEX chat_chunk_lane_review_idx
    ON working.chat_chunk_lane (review_status, confidence, created_at);
CREATE INDEX chat_chunk_lane_route_idx
    ON working.chat_chunk_lane (lane, chunk_id);

-- Lanes answer "which broad corpus?"; tags provide reusable fine-grained
-- search facets. Tags are normalized rather than stored as comma-separated
-- text, and every assignment records its provenance and confidence.
CREATE TABLE reference.knowledge_tag (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    slug TEXT NOT NULL UNIQUE
        CHECK (slug = lower(slug) AND slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
    label TEXT NOT NULL CHECK (length(label) > 0),
    description TEXT,
    parent_tag_id UUID REFERENCES reference.knowledge_tag(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE working.chat_chunk_tag (
    chunk_id UUID NOT NULL REFERENCES working.chat_chunk(id) ON DELETE CASCADE,
    tag_id UUID NOT NULL REFERENCES reference.knowledge_tag(id) ON DELETE RESTRICT,
    applied_by TEXT NOT NULL,
    confidence DOUBLE PRECISION CHECK (confidence IS NULL OR confidence BETWEEN 0 AND 1),
    review_status TEXT NOT NULL DEFAULT 'suggested'
        CHECK (review_status IN ('suggested','human_approved','human_rejected')),
    applied_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    reviewed_by TEXT,
    reviewed_at TIMESTAMPTZ,
    attrs JSONB NOT NULL DEFAULT '{}' CHECK (jsonb_typeof(attrs) = 'object'),
    PRIMARY KEY (chunk_id, tag_id),
    CHECK ((reviewed_at IS NULL) = (reviewed_by IS NULL)),
    CHECK (review_status = 'suggested' OR reviewed_at IS NOT NULL)
);

CREATE INDEX chat_chunk_tag_tag_idx ON working.chat_chunk_tag (tag_id, chunk_id);

-- Embeddings are computed once per canonical content + embedder and reused by
-- every lane projection. The vector itself remains in the vector store; this
-- table is the durable idempotency/cache ledger.
CREATE TABLE working.chat_chunk_embedding (
    chunk_id UUID NOT NULL REFERENCES working.chat_chunk(id) ON DELETE CASCADE,
    embedder_id TEXT NOT NULL,
    content_hash TEXT NOT NULL CHECK (length(content_hash) = 64),
    embedding VECTOR NOT NULL,
    embedding_dimension INTEGER NOT NULL CHECK (embedding_dimension > 0),
    vector_ref TEXT,
    embedded_at TIMESTAMPTZ,
    attrs JSONB NOT NULL DEFAULT '{}' CHECK (jsonb_typeof(attrs) = 'object'),
    PRIMARY KEY (chunk_id, embedder_id),
    UNIQUE (content_hash, embedder_id)
);

CREATE TABLE working.chat_chunk_projection (
    chunk_id UUID NOT NULL REFERENCES working.chat_chunk(id) ON DELETE CASCADE,
    lane TEXT NOT NULL CHECK (lane IN ('platform','legal','personal_history','context')),
    sink TEXT NOT NULL CHECK (sink IN ('weaviate','graphiti')),
    embedder_id TEXT,
    projection_ref TEXT,
    projected_at TIMESTAMPTZ,
    last_error TEXT,
    attempts INTEGER NOT NULL DEFAULT 0 CHECK (attempts >= 0),
    attrs JSONB NOT NULL DEFAULT '{}' CHECK (jsonb_typeof(attrs) = 'object'),
    PRIMARY KEY (chunk_id, lane, sink),
    CHECK (sink <> 'weaviate' OR embedder_id IS NOT NULL)
);

CREATE INDEX chat_chunk_projection_pending_idx
    ON working.chat_chunk_projection (sink, lane, chunk_id)
    WHERE projected_at IS NULL;

-- Human-curated register: a concern worth investigating is not yet an
-- established event and is never treated as evidence merely because an AI chat
-- mentioned it.
CREATE TABLE working.investigation_event (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    title TEXT NOT NULL CHECK (length(title) > 0),
    summary TEXT NOT NULL CHECK (length(summary) > 0),
    concern_type TEXT NOT NULL,
    priority TEXT NOT NULL DEFAULT 'normal'
        CHECK (priority IN ('low','normal','high','urgent')),
    occurred_at TIMESTAMPTZ,
    validity TSTZRANGE,
    evidence_status TEXT NOT NULL DEFAULT 'needed'
        CHECK (evidence_status IN ('needed','searching','partial','sufficient','conflicting')),
    disposition TEXT NOT NULL DEFAULT 'open'
        CHECK (disposition IN ('open','promoted','unsupported','inconclusive','withdrawn')),
    temporal_status TEXT NOT NULL DEFAULT 'unknown'
        CHECK (temporal_status IN ('unknown','asserted','estimated','disputed')),
    rationale TEXT NOT NULL,
    created_by TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    promoted_timeline_event_id UUID REFERENCES analysis.timeline_event(event_id),
    promoted_by TEXT,
    promoted_at TIMESTAMPTZ,
    attrs JSONB NOT NULL DEFAULT '{}' CHECK (jsonb_typeof(attrs) = 'object'),
    CHECK ((promoted_at IS NULL AND promoted_by IS NULL AND promoted_timeline_event_id IS NULL)
        OR (promoted_at IS NOT NULL AND promoted_by IS NOT NULL AND promoted_timeline_event_id IS NOT NULL)),
    CHECK (disposition <> 'promoted' OR promoted_at IS NOT NULL)
);

CREATE TABLE working.investigation_event_source (
    investigation_event_id UUID NOT NULL REFERENCES working.investigation_event(id) ON DELETE CASCADE,
    source_kind TEXT NOT NULL CHECK (source_kind IN ('chat_chunk','event_candidate','claim_candidate','other')),
    source_ref TEXT NOT NULL,
    relationship TEXT NOT NULL DEFAULT 'origin'
        CHECK (relationship IN ('origin','supports','contradicts','related')),
    note TEXT,
    linked_by TEXT NOT NULL,
    linked_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (investigation_event_id, source_kind, source_ref)
);

CREATE TABLE working.investigation_event_evidence_need (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    investigation_event_id UUID NOT NULL REFERENCES working.investigation_event(id) ON DELETE CASCADE,
    description TEXT NOT NULL CHECK (length(description) > 0),
    evidence_kind TEXT,
    status TEXT NOT NULL DEFAULT 'needed'
        CHECK (status IN ('needed','searching','found','unavailable','waived')),
    decided_by TEXT NOT NULL,
    decided_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    attrs JSONB NOT NULL DEFAULT '{}' CHECK (jsonb_typeof(attrs) = 'object')
);

CREATE TABLE working.investigation_event_evidence_link (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    investigation_event_id UUID NOT NULL REFERENCES working.investigation_event(id) ON DELETE CASCADE,
    evidence_hash_id UUID NOT NULL REFERENCES evidence.evidence_hash(id) ON DELETE RESTRICT,
    relationship TEXT NOT NULL CHECK (relationship IN ('supports','contradicts','related')),
    note TEXT,
    linked_by TEXT NOT NULL,
    linked_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (investigation_event_id, evidence_hash_id, relationship)
);

CREATE TABLE working.investigation_event_tag (
    investigation_event_id UUID NOT NULL REFERENCES working.investigation_event(id) ON DELETE CASCADE,
    tag_id UUID NOT NULL REFERENCES reference.knowledge_tag(id) ON DELETE RESTRICT,
    applied_by TEXT NOT NULL,
    applied_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (investigation_event_id, tag_id)
);

-- ADR-0052: one full-row transactional outbox per source table. NOTIFY is a
-- wakeup only; durable consumers advance their own cursors over event_id.
CREATE OR REPLACE FUNCTION working.emit_chat_row_event() RETURNS trigger AS $$
DECLARE target_table TEXT := TG_TABLE_NAME || '_event';
BEGIN
    EXECUTE format('INSERT INTO working.%I (operation, row_data) VALUES ($1, $2)', target_table)
        USING TG_OP, to_jsonb(NEW);
    PERFORM pg_notify('working_chat_changed', TG_TABLE_NAME);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TABLE working.chat_conversation_event (
    event_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    operation TEXT NOT NULL CHECK (operation IN ('INSERT','UPDATE')),
    row_data JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Define each identity explicitly. INCLUDING ALL would copy the identity
-- sequence, making otherwise independent outboxes contend for one counter.
CREATE TABLE working.chat_message_event (
    event_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    operation TEXT NOT NULL CHECK (operation IN ('INSERT','UPDATE')),
    row_data JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE working.chat_chunk_event (
    event_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    operation TEXT NOT NULL CHECK (operation IN ('INSERT','UPDATE')),
    row_data JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE working.chat_chunk_lane_event (
    event_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    operation TEXT NOT NULL CHECK (operation IN ('INSERT','UPDATE')),
    row_data JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE working.context_asset_event (
    event_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    operation TEXT NOT NULL CHECK (operation IN ('INSERT','UPDATE')),
    row_data JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Consumers are independently restartable and replayable. A cursor is scoped
-- to both sink and source outbox because event ids are table-local.
CREATE TABLE working.chat_cdc_cursor (
    sink_id TEXT NOT NULL,
    source_event_table TEXT NOT NULL CHECK (source_event_table IN (
        'chat_conversation_event','chat_message_event','chat_chunk_event',
        'chat_chunk_lane_event','context_asset_event'
    )),
    last_event_id BIGINT NOT NULL DEFAULT 0 CHECK (last_event_id >= 0),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (sink_id, source_event_table)
);

CREATE TABLE working.chat_projection_dead_letter (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    sink_id TEXT NOT NULL,
    source_event_table TEXT NOT NULL,
    source_event_id BIGINT NOT NULL CHECK (source_event_id > 0),
    row_data JSONB NOT NULL,
    error_class TEXT NOT NULL,
    error_message TEXT NOT NULL,
    attempts INTEGER NOT NULL CHECK (attempts > 0),
    failed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    replay_requested_at TIMESTAMPTZ,
    resolved_at TIMESTAMPTZ,
    resolution_note TEXT,
    UNIQUE (sink_id, source_event_table, source_event_id),
    CHECK (resolved_at IS NULL OR resolved_at >= failed_at)
);

CREATE INDEX chat_projection_dead_letter_open_idx
    ON working.chat_projection_dead_letter (sink_id, failed_at)
    WHERE resolved_at IS NULL;

CREATE TRIGGER chat_conversation_outbox AFTER INSERT OR UPDATE ON working.chat_conversation
    FOR EACH ROW EXECUTE FUNCTION working.emit_chat_row_event();
CREATE TRIGGER chat_message_outbox AFTER INSERT OR UPDATE ON working.chat_message
    FOR EACH ROW EXECUTE FUNCTION working.emit_chat_row_event();
CREATE TRIGGER chat_chunk_outbox AFTER INSERT OR UPDATE ON working.chat_chunk
    FOR EACH ROW EXECUTE FUNCTION working.emit_chat_row_event();
CREATE TRIGGER chat_chunk_lane_outbox AFTER INSERT OR UPDATE ON working.chat_chunk_lane
    FOR EACH ROW EXECUTE FUNCTION working.emit_chat_row_event();
CREATE TRIGGER context_asset_outbox AFTER INSERT OR UPDATE ON working.context_asset
    FOR EACH ROW EXECUTE FUNCTION working.emit_chat_row_event();

COMMENT ON TABLE working.chat_chunk_lane IS
    'Multi-label routing after chunking. Ambiguous/failure chunks remain searchable in context and enter review; no chunk is discarded.';
COMMENT ON TABLE working.investigation_event IS
    'Human-curated investigation register. Entries are concerns/leads, not established facts or evidence; promotion to analysis.timeline_event is an explicit human act.';

COMMIT;
