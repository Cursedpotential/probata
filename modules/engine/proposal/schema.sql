CREATE TABLE proposal_control (
    singleton BOOLEAN PRIMARY KEY DEFAULT TRUE CHECK (singleton),
    schema_version VARCHAR NOT NULL,
    operation_id VARCHAR NOT NULL,
    attempt_id VARCHAR NOT NULL,
    mode VARCHAR NOT NULL CHECK (mode IN ('TEST', 'REAL')),
    matter_id VARCHAR NOT NULL,
    court_case_id VARCHAR NOT NULL,
    source_package_locator VARCHAR NOT NULL,
    source_package_digest VARCHAR NOT NULL,
    config_digest VARCHAR NOT NULL,
    destination_plan JSON NOT NULL,
    logical_table_digests JSON NOT NULL,
    state VARCHAR NOT NULL CHECK (state IN ('building', 'frozen', 'approved', 'committing', 'committed', 'failed', 'stopped', 'superseded')),
    created_at TIMESTAMPTZ NOT NULL,
    proposal_digest VARCHAR,
    frozen_at TIMESTAMPTZ
);

CREATE TABLE proposed_source_records (
    source_record_id VARCHAR PRIMARY KEY,
    ordinal BIGINT NOT NULL CHECK (ordinal >= 0),
    source_locator_ref VARCHAR NOT NULL,
    source_payload JSON NOT NULL
);

CREATE TABLE proposed_records (
    record_id VARCHAR PRIMARY KEY,
    source_record_id VARCHAR NOT NULL,
    ordinal BIGINT NOT NULL CHECK (ordinal >= 0),
    record_type VARCHAR NOT NULL,
    occurred_at TIMESTAMPTZ,
    normalized_payload JSON NOT NULL,
    source_locator_ref VARCHAR NOT NULL
);

CREATE TABLE proposed_metadata (
    metadata_id VARCHAR PRIMARY KEY,
    owner_kind VARCHAR NOT NULL,
    owner_id VARCHAR NOT NULL,
    metadata_key VARCHAR NOT NULL,
    metadata_value JSON NOT NULL,
    source_locator_ref VARCHAR
);

CREATE TABLE proposed_attachments (
    attachment_id VARCHAR PRIMARY KEY,
    source_record_id VARCHAR,
    record_id VARCHAR,
    object_ref VARCHAR NOT NULL,
    sha256 VARCHAR NOT NULL,
    byte_length BIGINT NOT NULL CHECK (byte_length >= 0),
    media_type VARCHAR,
    metadata JSON
);

CREATE TABLE proposed_entity_mentions (
    mention_id VARCHAR PRIMARY KEY,
    entity_id VARCHAR NOT NULL,
    record_id VARCHAR,
    chunk_id VARCHAR,
    mention_text VARCHAR NOT NULL,
    entity_type VARCHAR NOT NULL,
    confidence DOUBLE CHECK (confidence >= 0 AND confidence <= 1),
    locator_ref VARCHAR NOT NULL,
    properties JSON
);

CREATE TABLE proposed_entities (
    entity_id VARCHAR PRIMARY KEY,
    entity_type VARCHAR NOT NULL,
    canonical_name VARCHAR NOT NULL,
    properties JSON NOT NULL,
    source_digest VARCHAR NOT NULL
);

CREATE TABLE proposed_relationships (
    relationship_id VARCHAR PRIMARY KEY,
    from_entity_id VARCHAR NOT NULL,
    to_entity_id VARCHAR NOT NULL,
    relationship_type VARCHAR NOT NULL,
    properties JSON NOT NULL,
    source_digest VARCHAR NOT NULL
);

CREATE TABLE proposed_temporal_expressions (
    temporal_expression_id VARCHAR PRIMARY KEY,
    owner_kind VARCHAR NOT NULL,
    owner_id VARCHAR NOT NULL,
    expression_text VARCHAR NOT NULL,
    normalized_start TIMESTAMPTZ,
    normalized_end TIMESTAMPTZ,
    precision VARCHAR,
    confidence DOUBLE CHECK (confidence >= 0 AND confidence <= 1),
    source_locator_ref VARCHAR NOT NULL
);

CREATE TABLE proposed_chunks (
    chunk_id VARCHAR PRIMARY KEY,
    record_id VARCHAR,
    chunk_index BIGINT NOT NULL CHECK (chunk_index >= 0),
    content VARCHAR NOT NULL,
    sha256 VARCHAR NOT NULL,
    derivation_mode VARCHAR NOT NULL,
    locator_ref VARCHAR NOT NULL,
    byte_start BIGINT NOT NULL CHECK (byte_start >= 0),
    byte_end BIGINT NOT NULL CHECK (byte_end > byte_start),
    token_count BIGINT CHECK (token_count >= 0)
);

CREATE TABLE proposed_lineage (
    lineage_id VARCHAR PRIMARY KEY,
    output_kind VARCHAR NOT NULL,
    output_id VARCHAR NOT NULL,
    input_kind VARCHAR NOT NULL,
    input_id VARCHAR NOT NULL,
    transform_stage VARCHAR NOT NULL,
    transform_digest VARCHAR NOT NULL,
    source_locator_ref VARCHAR
);

CREATE TABLE proposed_warnings (
    warning_id VARCHAR PRIMARY KEY,
    stage VARCHAR NOT NULL,
    code VARCHAR NOT NULL,
    detail VARCHAR NOT NULL,
    locator_ref VARCHAR,
    blocking BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE TABLE proposed_sink_operations (
    sink_operation_id VARCHAR PRIMARY KEY,
    destination VARCHAR NOT NULL CHECK (destination <> 'surrealdb_manual_projection'),
    operation_ordinal BIGINT NOT NULL CHECK (operation_ordinal >= 0),
    operation_kind VARCHAR NOT NULL,
    operation_payload JSON NOT NULL,
    operation_digest VARCHAR NOT NULL,
    selected BOOLEAN NOT NULL
);

CREATE TABLE tool_receipts (
    receipt_id VARCHAR PRIMARY KEY,
    stage VARCHAR NOT NULL,
    tool_id VARCHAR NOT NULL,
    tool_version VARCHAR NOT NULL,
    config_digest VARCHAR NOT NULL,
    input_digest VARCHAR NOT NULL,
    output_digest VARCHAR NOT NULL,
    activity_id VARCHAR,
    n8n_execution_id VARCHAR
);
