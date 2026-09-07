-- 0036_context_import_foundation.sql — additive, context-only persistence
-- foundation for the UniversalImportWorkflow.
--
-- Apply/status is recorded by the production migration ledger and deployment
-- handoff, never by editing this immutable migration.  This file deliberately
-- makes no evidence.* reference and does not promote context into the
-- custody/evidence spine.
--
-- The immutable original object is the byte authority.  A raw record must
-- retain either its exact byte range in a retained object OR its exact stored
-- bytes.  Rejected, malformed, unknown, unparsed, and envelope spans are rows,
-- not dropped parser warnings.  Normalization is a separate, later generation
-- and can seal only through real raw-record lineage FKs and successful receipts.
--
-- Byline: Codex · GPT-5 · 2026-08-26

BEGIN;

-- This migration belongs only to the fresh platform database.  Role creation,
-- database creation, and the public.schema_version ledger are bootstrap
-- responsibilities; refusing here keeps a legacy `ai` connection from ever
-- acquiring context objects by accident.
DO $$
DECLARE
    v_role TEXT;
BEGIN
    IF current_database() <> 'platform' THEN
        RAISE EXCEPTION 'migration 0036 may run only in database platform, not %', current_database();
    END IF;
    FOREACH v_role IN ARRAY ARRAY[
        'platform_admin', 'platform_runtime', 'context_owner',
        'context_import_writer', 'context_reader'
    ] LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = v_role) THEN
            RAISE EXCEPTION 'migration 0036 requires bootstrap role %', v_role;
        END IF;
    END LOOP;
    IF NOT pg_has_role('platform_admin', 'context_owner', 'MEMBER') THEN
        RAISE EXCEPTION 'platform_admin must be a member of context_owner';
    END IF;
    IF NOT pg_has_role('platform_runtime', 'context_import_writer', 'MEMBER') THEN
        RAISE EXCEPTION 'platform_runtime must be a member of context_import_writer';
    END IF;
    IF EXISTS (
        SELECT 1
        FROM pg_roles
        WHERE rolname IN ('platform_admin', 'platform_runtime', 'context_owner',
                          'context_import_writer', 'context_reader')
          AND (rolsuper OR rolcreatedb OR rolcreaterole OR rolreplication OR rolbypassrls)
    ) THEN
        RAISE EXCEPTION 'runtime and context roles must not hold elevated PostgreSQL attributes';
    END IF;
    IF EXISTS (
        SELECT 1 FROM pg_roles
        WHERE rolname IN ('platform_admin', 'context_owner',
                          'context_import_writer', 'context_reader')
          AND rolcanlogin
    ) THEN
        RAISE EXCEPTION 'platform ownership and grant roles must be NOLOGIN';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_roles WHERE rolname = 'platform_runtime' AND rolcanlogin
    ) THEN
        RAISE EXCEPTION 'platform_runtime must be the dedicated LOGIN role';
    END IF;
END;
$$;

-- platform_admin owns the database and creates the schema for its member role;
-- this does not require granting database-level CREATE to the runtime writer.
-- All relations/functions are then authored as the dedicated NOLOGIN owner,
-- never as the bootstrap login (historically `ai`).
SET LOCAL ROLE platform_admin;
CREATE SCHEMA IF NOT EXISTS context AUTHORIZATION context_owner;
DO $$
BEGIN
    IF (SELECT pg_get_userbyid(nspowner) FROM pg_namespace WHERE nspname = 'context')
       IS DISTINCT FROM 'context_owner' THEN
        RAISE EXCEPTION 'context schema exists with an unexpected owner';
    END IF;
END;
$$;
SET LOCAL ROLE context_owner;

-- Retained objects are context intake objects, not evidence/custody objects.
-- The storage reference is immutable by contract and content-addressed here so
-- an exact locator can never silently become a mutable filesystem path.
CREATE TABLE IF NOT EXISTS context.retained_object (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    storage_class TEXT NOT NULL
        CHECK (storage_class IN ('immutable_object_store', 'filesystem', 'inline')),
    object_uri TEXT NOT NULL,
    content_sha256 BYTEA NOT NULL CHECK (octet_length(content_sha256) = 32),
    byte_length BIGINT NOT NULL CHECK (byte_length >= 0),
    inline_bytes BYTEA,
    immutable_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (storage_class, object_uri),
    UNIQUE (content_sha256, byte_length),
    CHECK ((storage_class = 'inline' AND inline_bytes IS NOT NULL
            AND octet_length(inline_bytes) = byte_length
            AND digest(inline_bytes, 'sha256') = content_sha256)
        OR (storage_class <> 'inline' AND inline_bytes IS NULL))
);

CREATE TABLE IF NOT EXISTS context.source (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    source_key TEXT NOT NULL CHECK (length(btrim(source_key)) > 0),
    provenance_class TEXT NOT NULL
        CHECK (provenance_class IN ('first_party_authored', 'acquired_third_party',
                                   'system_generated', 'unknown')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (source_key)
);

-- source_version_id is both a particular source version and the durable
-- idempotency coordinate used by the UniversalImportWorkflow. Registration is
-- deliberately possible before retention; the narrow registered -> retained
-- transition below is the only operation that attaches original bytes.
CREATE TABLE IF NOT EXISTS context.source_version (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    source_id UUID NOT NULL REFERENCES context.source(id) ON DELETE RESTRICT,
    version_ordinal INTEGER NOT NULL CHECK (version_ordinal > 0),
    workflow_id TEXT NOT NULL CHECK (length(btrim(workflow_id)) > 0),
    submission_idempotency_key TEXT NOT NULL CHECK (length(btrim(submission_idempotency_key)) > 0),
    declared_format TEXT NOT NULL CHECK (length(btrim(declared_format)) > 0),
    original_filename TEXT,
    acquired_at TIMESTAMPTZ NOT NULL,
    original_object_id UUID REFERENCES context.retained_object(id) ON DELETE RESTRICT,
    status TEXT NOT NULL DEFAULT 'registered' CHECK (status IN ('registered', 'retained')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (source_id, version_ordinal),
    UNIQUE (workflow_id),
    UNIQUE (source_id, submission_idempotency_key),
    UNIQUE (id, original_object_id),
    CHECK ((status = 'registered' AND original_object_id IS NULL)
        OR (status = 'retained' AND original_object_id IS NOT NULL))
);

-- A source version may include original bytes, archive members, and retained
-- attachments.  The composite key lets raw locators prove they are part of the
-- same source version without a polymorphic table/id pointer.
CREATE TABLE IF NOT EXISTS context.source_version_object (
    source_version_id UUID NOT NULL REFERENCES context.source_version(id) ON DELETE RESTRICT,
    object_id UUID NOT NULL REFERENCES context.retained_object(id) ON DELETE RESTRICT,
    object_role TEXT NOT NULL
        CHECK (object_role IN ('original', 'container_member', 'attachment', 'derived_reference')),
    parent_object_id UUID REFERENCES context.retained_object(id) ON DELETE RESTRICT,
    member_locator JSONB NOT NULL DEFAULT '{}'::jsonb
        CHECK (jsonb_typeof(member_locator) = 'object'),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (source_version_id, object_id),
    FOREIGN KEY (source_version_id, parent_object_id)
        REFERENCES context.source_version_object(source_version_id, object_id)
        ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED,
    CHECK ((object_role = 'original') = (parent_object_id IS NULL))
);

CREATE UNIQUE INDEX IF NOT EXISTS source_version_object_one_original_uq
    ON context.source_version_object (source_version_id)
    WHERE object_role = 'original';

ALTER TABLE context.source_version
    ADD CONSTRAINT source_version_original_object_membership_fk
    FOREIGN KEY (id, original_object_id)
    REFERENCES context.source_version_object(source_version_id, object_id)
    DEFERRABLE INITIALLY DEFERRED;

CREATE TABLE IF NOT EXISTS context.raw_generation (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    source_version_id UUID NOT NULL REFERENCES context.source_version(id) ON DELETE RESTRICT,
    generation_ordinal INTEGER NOT NULL CHECK (generation_ordinal > 0),
    format_id TEXT NOT NULL CHECK (length(btrim(format_id)) > 0),
    parser_id TEXT NOT NULL CHECK (length(btrim(parser_id)) > 0),
    parser_version TEXT NOT NULL CHECK (length(btrim(parser_version)) > 0),
    extraction_bundle_object_id UUID REFERENCES context.retained_object(id) ON DELETE RESTRICT,
    status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'sealed')),
    sealed_at TIMESTAMPTZ,
    sealed_by TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (source_version_id, generation_ordinal),
    UNIQUE (id, source_version_id),
    UNIQUE (id, format_id),
    CHECK ((status = 'open' AND sealed_at IS NULL AND sealed_by IS NULL)
        OR (status = 'sealed' AND sealed_at IS NOT NULL AND sealed_by IS NOT NULL))
);

-- This registry contains relation identities (regclass), not a raw-table TEXT
-- pointer.  Raw records use format_id as an FK; the registration function below
-- creates and validates the physical subtype table sharing raw_record_id.
CREATE TABLE IF NOT EXISTS context.raw_format_registry (
    format_id TEXT PRIMARY KEY CHECK (format_id ~ '^[a-z][a-z0-9_]{0,58}$'),
    subtype_relation REGCLASS NOT NULL UNIQUE,
    registered_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE context.raw_generation
    ADD CONSTRAINT raw_generation_format_registry_fk
    FOREIGN KEY (format_id) REFERENCES context.raw_format_registry(format_id)
    DEFERRABLE INITIALLY DEFERRED;

CREATE TABLE IF NOT EXISTS context.raw_record_identity (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    raw_generation_id UUID NOT NULL REFERENCES context.raw_generation(id) ON DELETE RESTRICT,
    source_version_id UUID NOT NULL REFERENCES context.source_version(id) ON DELETE RESTRICT,
    format_id TEXT NOT NULL REFERENCES context.raw_format_registry(format_id) ON DELETE RESTRICT,
    record_ordinal BIGINT NOT NULL CHECK (record_ordinal >= 0),
    record_status TEXT NOT NULL
        CHECK (record_status IN ('parsed', 'rejected', 'malformed', 'unknown', 'unparsed', 'envelope')),
    raw_hash_construction TEXT NOT NULL
        CHECK (raw_hash_construction IN (
            'h2-rawelement-v1', 'h2-rawrecord-v1', 'h2-rawspan-v1'
        )),
    status_reason TEXT,
    locator_object_id UUID,
    byte_offset BIGINT,
    byte_length BIGINT,
    stored_bytes BYTEA,
    native_metadata JSONB NOT NULL DEFAULT '{}'::jsonb
        CHECK (jsonb_typeof(native_metadata) = 'object'),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (raw_generation_id, record_ordinal),
    UNIQUE (id, raw_generation_id),
    UNIQUE (id, source_version_id),
    FOREIGN KEY (raw_generation_id, source_version_id)
        REFERENCES context.raw_generation(id, source_version_id) ON DELETE RESTRICT,
    FOREIGN KEY (raw_generation_id, format_id)
        REFERENCES context.raw_generation(id, format_id) ON DELETE RESTRICT,
    FOREIGN KEY (source_version_id, locator_object_id)
        REFERENCES context.source_version_object(source_version_id, object_id)
        DEFERRABLE INITIALLY DEFERRED,
    CHECK ((record_status = 'parsed') OR status_reason IS NOT NULL),
    CHECK (
        record_status NOT IN ('envelope', 'unparsed')
        OR raw_hash_construction = 'h2-rawspan-v1'
    ),
    CHECK (
        (stored_bytes IS NOT NULL
            AND locator_object_id IS NULL AND byte_offset IS NULL AND byte_length IS NULL)
        OR
        (stored_bytes IS NULL
            AND locator_object_id IS NOT NULL
            AND byte_offset IS NOT NULL AND byte_offset >= 0
            AND byte_length IS NOT NULL AND byte_length >= 0)
    )
);

CREATE INDEX IF NOT EXISTS raw_record_identity_generation_idx
    ON context.raw_record_identity (raw_generation_id, record_ordinal);
CREATE INDEX IF NOT EXISTS raw_record_identity_source_version_idx
    ON context.raw_record_identity (source_version_id, id);

COMMENT ON TABLE context.raw_record_identity IS
    'The sole persistence home for every parser-emitted ordered span. Parsed records and rejected, malformed, unknown, unparsed, and envelope spans are all rows here; no orphan span table is permitted.';
COMMENT ON COLUMN context.raw_record_identity.raw_hash_construction IS
    'The persist stage, not the parser, assigns the exact H2 construction. Envelope and unparsed spans must use h2-rawspan-v1.';

-- Metadata may be source-wide or per raw record.  It retains the entire native
-- object alongside the precise extractor/tool provenance that produced it.
CREATE TABLE IF NOT EXISTS context.source_metadata (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    source_version_id UUID NOT NULL REFERENCES context.source_version(id) ON DELETE RESTRICT,
    raw_record_id UUID REFERENCES context.raw_record_identity(id) ON DELETE RESTRICT,
    metadata_class TEXT NOT NULL
        CHECK (metadata_class IN ('filesystem', 'embedded', 'container', 'media_tool', 'record_native')),
    metadata JSONB NOT NULL CHECK (jsonb_typeof(metadata) = 'object'),
    extractor_id TEXT NOT NULL CHECK (length(btrim(extractor_id)) > 0),
    extractor_version TEXT,
    extraction_activity_receipt_id UUID NOT NULL,
    generated_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (id, source_version_id),
    FOREIGN KEY (raw_record_id, source_version_id)
        REFERENCES context.raw_record_identity(id, source_version_id) ON DELETE RESTRICT
);

-- Every registered format gets a physical table with this exact shared key.
-- Parsed and rejected/envelope rows alike receive an empty payload object if
-- the format supplied no native fields, which makes subtype completeness
-- mechanically checkable at raw-generation seal time.
CREATE FUNCTION context.register_raw_format_subtype(p_format_id TEXT)
RETURNS REGCLASS
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, context
AS $$
DECLARE
    v_table_name TEXT;
    v_relation REGCLASS;
    v_relation_kind "char";
    v_raw_record_attnum SMALLINT;
    v_raw_identity_id_attnum SMALLINT;
    v_native_fields_attnum SMALLINT;
    v_native_metadata_attnum SMALLINT;
BEGIN
    IF p_format_id !~ '^[a-z][a-z0-9_]{0,58}$' THEN
        RAISE EXCEPTION 'invalid raw format id %', p_format_id;
    END IF;

    v_table_name := 'raw_' || p_format_id;
    EXECUTE format(
        'CREATE TABLE IF NOT EXISTS context.%I (
            raw_record_id UUID PRIMARY KEY
                REFERENCES context.raw_record_identity(id) ON DELETE RESTRICT,
            native_fields JSONB NOT NULL DEFAULT ''{}''::jsonb
                CHECK (jsonb_typeof(native_fields) = ''object''),
            native_metadata JSONB NOT NULL DEFAULT ''{}''::jsonb
                CHECK (jsonb_typeof(native_metadata) = ''object''),
            created_at TIMESTAMPTZ NOT NULL DEFAULT now()
        )',
        v_table_name
    );
    v_relation := to_regclass(format('context.%I', v_table_name));

    SELECT relkind INTO v_relation_kind
    FROM pg_class
    WHERE oid = v_relation;
    IF v_relation_kind IS DISTINCT FROM 'r'::"char" THEN
        RAISE EXCEPTION 'raw subtype % must be an ordinary table, found relation kind %',
            v_relation::TEXT, v_relation_kind;
    END IF;

    SELECT attnum INTO v_raw_identity_id_attnum
    FROM pg_attribute
    WHERE attrelid = 'context.raw_record_identity'::regclass
      AND attname = 'id'
      AND atttypid = 'uuid'::regtype
      AND attnotnull
      AND NOT attisdropped;

    SELECT attnum INTO v_raw_record_attnum
    FROM pg_attribute
    WHERE attrelid = v_relation
      AND attname = 'raw_record_id'
      AND atttypid = 'uuid'::regtype
      AND attnotnull
      AND NOT attisdropped;

    IF v_raw_record_attnum IS NULL OR v_raw_identity_id_attnum IS NULL THEN
        RAISE EXCEPTION 'raw subtype % must have a NOT NULL UUID raw_record_id key column',
            v_relation::TEXT;
    END IF;
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid = v_relation
          AND contype = 'p'
          AND conkey = ARRAY[v_raw_record_attnum]::SMALLINT[]
    ) THEN
        RAISE EXCEPTION 'raw subtype % must have raw_record_id as its exact primary key',
            v_relation::TEXT;
    END IF;
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid = v_relation
          AND contype = 'f'
          AND confrelid = 'context.raw_record_identity'::regclass
          AND conkey = ARRAY[v_raw_record_attnum]::SMALLINT[]
          AND confkey = ARRAY[v_raw_identity_id_attnum]::SMALLINT[]
          AND confdeltype = 'r'
    ) THEN
        RAISE EXCEPTION 'raw subtype % must have an exact raw_record_id FK to context.raw_record_identity(id) ON DELETE RESTRICT',
            v_relation::TEXT;
    END IF;

    SELECT attnum INTO v_native_fields_attnum
    FROM pg_attribute
    WHERE attrelid = v_relation
      AND attname = 'native_fields'
      AND atttypid = 'jsonb'::regtype
      AND attnotnull
      AND NOT attisdropped;
    SELECT attnum INTO v_native_metadata_attnum
    FROM pg_attribute
    WHERE attrelid = v_relation
      AND attname = 'native_metadata'
      AND atttypid = 'jsonb'::regtype
      AND attnotnull
      AND NOT attisdropped;
    IF v_native_fields_attnum IS NULL OR v_native_metadata_attnum IS NULL THEN
        RAISE EXCEPTION 'raw subtype % must have NOT NULL JSONB native_fields and native_metadata columns',
            v_relation::TEXT;
    END IF;

    INSERT INTO context.raw_format_registry (format_id, subtype_relation)
    VALUES (p_format_id, v_relation)
    ON CONFLICT (format_id) DO NOTHING;
    IF (SELECT subtype_relation FROM context.raw_format_registry WHERE format_id = p_format_id)
       IS DISTINCT FROM v_relation THEN
        RAISE EXCEPTION 'raw format % is already registered to a different subtype relation', p_format_id;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_trigger
        WHERE tgrelid = v_relation
          AND tgname = 'raw_subtype_append_only'
          AND NOT tgisinternal
    ) THEN
        EXECUTE format(
            'CREATE TRIGGER raw_subtype_append_only
             BEFORE UPDATE OR DELETE ON context.%I
             FOR EACH ROW EXECUTE FUNCTION context.forbid_mutation()',
            v_table_name
        );
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_trigger
        WHERE tgrelid = v_relation
          AND tgname = 'raw_subtype_open_generation_gate'
          AND NOT tgisinternal
    ) THEN
        EXECUTE format(
            'CREATE TRIGGER raw_subtype_open_generation_gate
             BEFORE INSERT ON context.%I
             FOR EACH ROW EXECUTE FUNCTION context.guard_raw_subtype_insert()',
            v_table_name
        );
    END IF;
    RETURN v_relation;
END;
$$;

CREATE TABLE IF NOT EXISTS context.normalized_generation (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    source_version_id UUID NOT NULL REFERENCES context.source_version(id) ON DELETE RESTRICT,
    raw_generation_id UUID NOT NULL REFERENCES context.raw_generation(id) ON DELETE RESTRICT,
    generation_ordinal INTEGER NOT NULL CHECK (generation_ordinal > 0),
    normalizer_id TEXT NOT NULL CHECK (length(btrim(normalizer_id)) > 0),
    normalizer_version TEXT NOT NULL CHECK (length(btrim(normalizer_version)) > 0),
    status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'sealed', 'published')),
    sealed_at TIMESTAMPTZ,
    sealed_by TEXT,
    published_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (source_version_id, generation_ordinal),
    UNIQUE (id, source_version_id),
    UNIQUE (id, raw_generation_id),
    FOREIGN KEY (raw_generation_id, source_version_id)
        REFERENCES context.raw_generation(id, source_version_id) ON DELETE RESTRICT,
    CHECK ((status = 'open' AND sealed_at IS NULL AND sealed_by IS NULL AND published_at IS NULL)
        OR (status = 'sealed' AND sealed_at IS NOT NULL AND sealed_by IS NOT NULL AND published_at IS NULL)
        OR (status = 'published' AND sealed_at IS NOT NULL AND sealed_by IS NOT NULL AND published_at IS NOT NULL))
);

CREATE TABLE IF NOT EXISTS context.normalized_record_identity (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    normalized_generation_id UUID NOT NULL REFERENCES context.normalized_generation(id) ON DELETE RESTRICT,
    source_version_id UUID NOT NULL REFERENCES context.source_version(id) ON DELETE RESTRICT,
    record_ordinal BIGINT NOT NULL CHECK (record_ordinal >= 0),
    record_type TEXT NOT NULL CHECK (record_type IN ('message', 'call', 'event', 'media', 'document', 'other')),
    occurred_at TIMESTAMPTZ,
    canonical_bytes BYTEA NOT NULL,
    canonicalization TEXT NOT NULL
        CHECK (canonicalization = 'normalized-record-postgresql18-jsonb-text-utf8-sha256-v1'),
    normalized_payload JSONB NOT NULL DEFAULT '{}'::jsonb
        CHECK (jsonb_typeof(normalized_payload) = 'object'),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (normalized_generation_id, record_ordinal),
    UNIQUE (id, normalized_generation_id),
    UNIQUE (id, source_version_id),
    FOREIGN KEY (normalized_generation_id, source_version_id)
        REFERENCES context.normalized_generation(id, source_version_id) ON DELETE RESTRICT,
    CHECK (canonical_bytes = convert_to(normalized_payload::text, 'UTF8'))
);

-- This real M:N join is the only raw-to-normalized derivation coordinate.  It
-- intentionally has no raw_table/raw_id polymorphic pointer.
CREATE TABLE IF NOT EXISTS context.normalization_lineage (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    normalized_generation_id UUID NOT NULL REFERENCES context.normalized_generation(id) ON DELETE RESTRICT,
    raw_generation_id UUID NOT NULL REFERENCES context.raw_generation(id) ON DELETE RESTRICT,
    normalized_record_id UUID NOT NULL REFERENCES context.normalized_record_identity(id) ON DELETE RESTRICT,
    raw_record_id UUID NOT NULL REFERENCES context.raw_record_identity(id) ON DELETE RESTRICT,
    derivation_role TEXT NOT NULL
        CHECK (derivation_role IN ('primary_source', 'supplementary', 'merge_source',
                                   'attachment_source', 'correction_source')),
    source_span_offset BIGINT CHECK (source_span_offset IS NULL OR source_span_offset >= 0),
    source_span_length BIGINT CHECK (source_span_length IS NULL OR source_span_length >= 0),
    field_map JSONB NOT NULL DEFAULT '[]'::jsonb CHECK (jsonb_typeof(field_map) = 'array'),
    normalizer_id TEXT NOT NULL CHECK (length(btrim(normalizer_id)) > 0),
    normalizer_version TEXT NOT NULL CHECK (length(btrim(normalizer_version)) > 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (normalized_record_id, raw_record_id, derivation_role),
    FOREIGN KEY (normalized_record_id, normalized_generation_id)
        REFERENCES context.normalized_record_identity(id, normalized_generation_id) ON DELETE RESTRICT,
    FOREIGN KEY (normalized_generation_id, raw_generation_id)
        REFERENCES context.normalized_generation(id, raw_generation_id) ON DELETE RESTRICT,
    FOREIGN KEY (raw_record_id, raw_generation_id)
        REFERENCES context.raw_record_identity(id, raw_generation_id) ON DELETE RESTRICT
);

CREATE INDEX IF NOT EXISTS normalization_lineage_raw_record_idx
    ON context.normalization_lineage (raw_record_id, normalized_record_id);

-- Activity execution is the retry-safe idempotency coordinate.  Every attempt
-- gets one immutable receipt, preserving both idempotency and the retry audit.
CREATE TABLE IF NOT EXISTS context.activity_execution (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    source_version_id UUID NOT NULL REFERENCES context.source_version(id) ON DELETE RESTRICT,
    workflow_id TEXT NOT NULL CHECK (length(btrim(workflow_id)) > 0),
    activity_name TEXT NOT NULL CHECK (length(btrim(activity_name)) > 0),
    idempotency_key TEXT NOT NULL CHECK (length(btrim(idempotency_key)) > 0),
    request_digest BYTEA CHECK (request_digest IS NULL OR octet_length(request_digest) = 32),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (source_version_id, activity_name, idempotency_key),
    UNIQUE (id, source_version_id)
);

CREATE TABLE IF NOT EXISTS context.activity_receipt (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    activity_execution_id UUID NOT NULL REFERENCES context.activity_execution(id) ON DELETE RESTRICT,
    attempt INTEGER NOT NULL CHECK (attempt > 0),
    status TEXT NOT NULL CHECK (status IN ('success', 'failed', 'not_applicable')),
    started_at TIMESTAMPTZ NOT NULL,
    completed_at TIMESTAMPTZ,
    result_ref JSONB,
    error_detail JSONB,
    not_applicable_reason TEXT CHECK (not_applicable_reason IS NULL OR length(btrim(not_applicable_reason)) > 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (activity_execution_id, attempt),
    CHECK (result_ref IS NULL OR jsonb_typeof(result_ref) = 'object'),
    CHECK (error_detail IS NULL OR jsonb_typeof(error_detail) = 'object'),
    CHECK ((status = 'success' AND completed_at IS NOT NULL
            AND result_ref IS NOT NULL AND error_detail IS NULL AND not_applicable_reason IS NULL)
        OR (status = 'failed' AND completed_at IS NOT NULL
            AND result_ref IS NULL AND error_detail IS NOT NULL AND not_applicable_reason IS NULL)
        OR (status = 'not_applicable' AND completed_at IS NOT NULL
            AND result_ref IS NULL AND error_detail IS NULL AND not_applicable_reason IS NOT NULL))
);

-- Hash Activities stream potentially large sources and generations. Their
-- member staging is durable and uses short transactions: no worker holds a
-- PostgreSQL transaction or pool connection while reading an external object.
-- One batch is one Activity attempt; a retry may verify/reuse a completed
-- earlier attempt or create a new batch without losing immutable history.
CREATE TABLE IF NOT EXISTS context.hash_batch (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    activity_execution_id UUID NOT NULL REFERENCES context.activity_execution(id) ON DELETE RESTRICT,
    source_version_id UUID NOT NULL REFERENCES context.source_version(id) ON DELETE RESTRICT,
    attempt INTEGER NOT NULL CHECK (attempt > 0),
    hash_kind TEXT NOT NULL CHECK (hash_kind IN (
        'h1_source', 'raw_record_digest', 'h3_raw_generation',
        'normalized_record_digest', 'normalized_generation_manifest_digest')),
    raw_generation_id UUID REFERENCES context.raw_generation(id) ON DELETE RESTRICT,
    normalized_generation_id UUID REFERENCES context.normalized_generation(id) ON DELETE RESTRICT,
    status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'completed', 'aborted')),
    member_count BIGINT,
    result_ref JSONB,
    activity_receipt_id UUID REFERENCES context.activity_receipt(id) ON DELETE RESTRICT,
    completed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (activity_execution_id, attempt),
    CHECK (result_ref IS NULL OR jsonb_typeof(result_ref) = 'object'),
    CHECK ((hash_kind = 'h1_source' AND raw_generation_id IS NULL AND normalized_generation_id IS NULL)
        OR (hash_kind IN ('raw_record_digest', 'h3_raw_generation')
            AND raw_generation_id IS NOT NULL AND normalized_generation_id IS NULL)
        OR (hash_kind IN ('normalized_record_digest', 'normalized_generation_manifest_digest')
            AND raw_generation_id IS NULL AND normalized_generation_id IS NOT NULL)),
    CHECK ((status = 'open' AND member_count IS NULL AND result_ref IS NULL
            AND activity_receipt_id IS NULL AND completed_at IS NULL)
        OR (status = 'completed' AND member_count IS NOT NULL AND member_count > 0
            AND result_ref IS NOT NULL AND activity_receipt_id IS NOT NULL AND completed_at IS NOT NULL)
        OR (status = 'aborted' AND member_count IS NULL AND result_ref IS NULL
            AND activity_receipt_id IS NULL AND completed_at IS NOT NULL))
);

CREATE TABLE IF NOT EXISTS context.hash_batch_member (
    hash_batch_id UUID NOT NULL REFERENCES context.hash_batch(id) ON DELETE RESTRICT,
    ordinal BIGINT NOT NULL CHECK (ordinal >= 0),
    source_version_id UUID REFERENCES context.source_version(id) ON DELETE RESTRICT,
    raw_record_id UUID REFERENCES context.raw_record_identity(id) ON DELETE RESTRICT,
    normalized_record_id UUID REFERENCES context.normalized_record_identity(id) ON DELETE RESTRICT,
    digest BYTEA NOT NULL CHECK (octet_length(digest) = 32),
    construction TEXT NOT NULL CHECK (length(btrim(construction)) > 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (hash_batch_id, ordinal),
    CHECK (num_nonnulls(source_version_id, raw_record_id, normalized_record_id) = 1)
);

ALTER TABLE context.source_metadata
    ADD CONSTRAINT source_metadata_extraction_receipt_fk
    FOREIGN KEY (extraction_activity_receipt_id)
    REFERENCES context.activity_receipt(id) ON DELETE RESTRICT;

-- These five kinds are deliberately named so normalized digests cannot ever be
-- mistaken for raw H2/H3 custody hashes.
--
-- A generation digest has a bounded relational manifest.  Membership is written
-- while its manifest is open; inserting the corresponding hash receipt seals
-- the manifest only after its members exactly equal generation membership.
CREATE TABLE IF NOT EXISTS context.hash_manifest (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    hash_kind TEXT NOT NULL CHECK (hash_kind IN (
        'h3_raw_generation', 'normalized_generation_manifest_digest')),
    raw_generation_id UUID REFERENCES context.raw_generation(id) ON DELETE RESTRICT,
    normalized_generation_id UUID REFERENCES context.normalized_generation(id) ON DELETE RESTRICT,
    status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'sealed')),
    member_count BIGINT,
    sealed_hash_receipt_id UUID,
    sealed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (id, hash_kind),
    CHECK ((hash_kind = 'h3_raw_generation' AND raw_generation_id IS NOT NULL
            AND normalized_generation_id IS NULL)
        OR (hash_kind = 'normalized_generation_manifest_digest'
            AND raw_generation_id IS NULL AND normalized_generation_id IS NOT NULL)),
    CHECK ((status = 'open' AND member_count IS NULL
            AND sealed_hash_receipt_id IS NULL AND sealed_at IS NULL)
        OR (status = 'sealed' AND member_count IS NOT NULL AND member_count > 0
            AND sealed_hash_receipt_id IS NOT NULL AND sealed_at IS NOT NULL))
);

CREATE UNIQUE INDEX IF NOT EXISTS hash_manifest_raw_generation_kind_uq
    ON context.hash_manifest (raw_generation_id, hash_kind)
    WHERE raw_generation_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS hash_manifest_normalized_generation_kind_uq
    ON context.hash_manifest (normalized_generation_id, hash_kind)
    WHERE normalized_generation_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS context.hash_manifest_member (
    hash_manifest_id UUID NOT NULL REFERENCES context.hash_manifest(id) ON DELETE RESTRICT,
    ordinal BIGINT NOT NULL CHECK (ordinal >= 0),
    raw_record_id UUID REFERENCES context.raw_record_identity(id) ON DELETE RESTRICT,
    normalized_record_id UUID REFERENCES context.normalized_record_identity(id) ON DELETE RESTRICT,
    member_digest BYTEA NOT NULL CHECK (octet_length(member_digest) = 32),
    member_canon TEXT NOT NULL CHECK (length(btrim(member_canon)) > 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (hash_manifest_id, ordinal),
    CHECK ((raw_record_id IS NOT NULL) <> (normalized_record_id IS NOT NULL))
);

CREATE UNIQUE INDEX IF NOT EXISTS hash_manifest_member_raw_record_uq
    ON context.hash_manifest_member (hash_manifest_id, raw_record_id)
    WHERE raw_record_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS hash_manifest_member_normalized_record_uq
    ON context.hash_manifest_member (hash_manifest_id, normalized_record_id)
    WHERE normalized_record_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS context.hash_receipt (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    activity_receipt_id UUID NOT NULL REFERENCES context.activity_receipt(id) ON DELETE RESTRICT,
    hash_kind TEXT NOT NULL CHECK (hash_kind IN (
        'h1_source', 'raw_record_digest', 'h3_raw_generation',
        'normalized_record_digest', 'normalized_generation_manifest_digest')),
    algorithm TEXT NOT NULL DEFAULT 'sha256' CHECK (algorithm = 'sha256'),
    digest BYTEA NOT NULL CHECK (octet_length(digest) = 32),
    construction TEXT NOT NULL,
    hash_manifest_id UUID REFERENCES context.hash_manifest(id) ON DELETE RESTRICT,
    source_version_id UUID REFERENCES context.source_version(id) ON DELETE RESTRICT,
    raw_record_id UUID REFERENCES context.raw_record_identity(id) ON DELETE RESTRICT,
    raw_generation_id UUID REFERENCES context.raw_generation(id) ON DELETE RESTRICT,
    normalized_record_id UUID REFERENCES context.normalized_record_identity(id) ON DELETE RESTRICT,
    normalized_generation_id UUID REFERENCES context.normalized_generation(id) ON DELETE RESTRICT,
    computed_at TIMESTAMPTZ NOT NULL,
    computed_by TEXT NOT NULL CHECK (length(btrim(computed_by)) > 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (
        (hash_kind = 'h1_source' AND source_version_id IS NOT NULL AND raw_record_id IS NULL
            AND raw_generation_id IS NULL AND normalized_record_id IS NULL AND normalized_generation_id IS NULL
            AND hash_manifest_id IS NULL)
        OR (hash_kind = 'raw_record_digest' AND source_version_id IS NULL AND raw_record_id IS NOT NULL
            AND raw_generation_id IS NULL AND normalized_record_id IS NULL AND normalized_generation_id IS NULL
            AND hash_manifest_id IS NULL)
        OR (hash_kind = 'h3_raw_generation' AND source_version_id IS NULL AND raw_record_id IS NULL
            AND raw_generation_id IS NOT NULL AND normalized_record_id IS NULL AND normalized_generation_id IS NULL
            AND construction IS NOT NULL AND hash_manifest_id IS NOT NULL)
        OR (hash_kind = 'normalized_record_digest' AND source_version_id IS NULL AND raw_record_id IS NULL
            AND raw_generation_id IS NULL AND normalized_record_id IS NOT NULL AND normalized_generation_id IS NULL
            AND hash_manifest_id IS NULL)
        OR (hash_kind = 'normalized_generation_manifest_digest' AND source_version_id IS NULL AND raw_record_id IS NULL
            AND raw_generation_id IS NULL AND normalized_record_id IS NULL AND normalized_generation_id IS NOT NULL
            AND construction IS NOT NULL AND hash_manifest_id IS NOT NULL)
    ),
    CHECK (
        (hash_kind = 'h1_source' AND construction = 'h1-rawbytes-v1')
        OR (hash_kind = 'raw_record_digest'
            AND construction IN ('h2-rawelement-v1', 'h2-rawrecord-v1', 'h2-rawspan-v1'))
        OR (hash_kind = 'h3_raw_generation'
            AND construction = 'h3-chain-platform-rawall-genesisempty-v1')
        OR (hash_kind = 'normalized_record_digest'
            AND construction = 'normalized-record-postgresql18-jsonb-text-utf8-sha256-v1')
        OR (hash_kind = 'normalized_generation_manifest_digest'
            AND construction = 'normalized-generation-ordered-digests-lengthframed-sha256-v1')
    )
);

ALTER TABLE context.hash_manifest
    ADD CONSTRAINT hash_manifest_sealed_receipt_fk
    FOREIGN KEY (sealed_hash_receipt_id) REFERENCES context.hash_receipt(id) ON DELETE RESTRICT;

CREATE UNIQUE INDEX IF NOT EXISTS hash_receipt_h1_source_uq
    ON context.hash_receipt (source_version_id) WHERE hash_kind = 'h1_source';
CREATE UNIQUE INDEX IF NOT EXISTS hash_receipt_h2_raw_record_uq
    ON context.hash_receipt (raw_record_id) WHERE hash_kind = 'raw_record_digest';
CREATE INDEX IF NOT EXISTS hash_receipt_raw_generation_idx
    ON context.hash_receipt (raw_generation_id) WHERE hash_kind = 'h3_raw_generation';
CREATE UNIQUE INDEX IF NOT EXISTS hash_receipt_h3_raw_generation_uq
    ON context.hash_receipt (raw_generation_id) WHERE hash_kind = 'h3_raw_generation';
CREATE UNIQUE INDEX IF NOT EXISTS hash_receipt_normalized_record_uq
    ON context.hash_receipt (normalized_record_id) WHERE hash_kind = 'normalized_record_digest';
CREATE INDEX IF NOT EXISTS hash_receipt_normalized_generation_idx
    ON context.hash_receipt (normalized_generation_id)
    WHERE hash_kind = 'normalized_generation_manifest_digest';
CREATE UNIQUE INDEX IF NOT EXISTS hash_receipt_normalized_generation_manifest_uq
    ON context.hash_receipt (normalized_generation_id)
    WHERE hash_kind = 'normalized_generation_manifest_digest';

CREATE TABLE IF NOT EXISTS context.reconciliation_receipt (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    activity_receipt_id UUID NOT NULL REFERENCES context.activity_receipt(id) ON DELETE RESTRICT,
    reconciliation_kind TEXT NOT NULL CHECK (reconciliation_kind IN (
        'record_accounting', 'byte_coverage', 'raw_source_verification',
        'raw_lineage_validation', 'normalized_generation_verification')),
    raw_generation_id UUID REFERENCES context.raw_generation(id) ON DELETE RESTRICT,
    normalized_generation_id UUID REFERENCES context.normalized_generation(id) ON DELETE RESTRICT,
    status TEXT NOT NULL CHECK (status IN ('success', 'failed', 'not_applicable')),
    expected JSONB NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(expected) = 'object'),
    observed JSONB NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(observed) = 'object'),
    discrepancies JSONB NOT NULL DEFAULT '[]'::jsonb CHECK (jsonb_typeof(discrepancies) = 'array'),
    verified_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK ((reconciliation_kind IN ('record_accounting', 'byte_coverage', 'raw_source_verification')
            AND raw_generation_id IS NOT NULL AND normalized_generation_id IS NULL)
        OR (reconciliation_kind IN ('raw_lineage_validation', 'normalized_generation_verification')
            AND raw_generation_id IS NULL AND normalized_generation_id IS NOT NULL)),
    CHECK ((status = 'success' AND discrepancies = '[]'::jsonb)
        OR status IN ('failed', 'not_applicable')),
    CHECK (status <> 'not_applicable' OR discrepancies = '[]'::jsonb),
    -- These verification receipts are independently recomputed proofs, not a
    -- re-label of the earlier hash Activity output.
    CHECK (reconciliation_kind <> 'raw_source_verification' OR (
        expected ? 'h3_raw_generation'
        AND observed ? 'h3_raw_generation'
        AND expected->>'verification_mode' = 'independent_recomputation'
        AND observed->>'verification_mode' = 'independent_recomputation'
        AND (status <> 'success'
             OR expected->'h3_raw_generation' = observed->'h3_raw_generation')
    )),
    CHECK (reconciliation_kind <> 'normalized_generation_verification' OR (
        expected ? 'normalized_generation_manifest_digest'
        AND observed ? 'normalized_generation_manifest_digest'
        AND expected->>'verification_mode' = 'independent_recomputation'
        AND observed->>'verification_mode' = 'independent_recomputation'
        AND (status <> 'success'
             OR expected->'normalized_generation_manifest_digest'
                = observed->'normalized_generation_manifest_digest')
    ))
);

CREATE TABLE IF NOT EXISTS context.normalized_generation_publication (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    normalized_generation_id UUID NOT NULL
        REFERENCES context.normalized_generation(id) ON DELETE RESTRICT,
    activity_receipt_id UUID NOT NULL REFERENCES context.activity_receipt(id) ON DELETE RESTRICT,
    idempotency_key TEXT NOT NULL CHECK (length(btrim(idempotency_key)) > 0),
    publication_ref JSONB NOT NULL CHECK (jsonb_typeof(publication_ref) = 'object'),
    published_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (normalized_generation_id),
    UNIQUE (idempotency_key)
);

-- Generic append-only protection for immutable intake facts, derivation edges,
-- and receipts.  Generation state has its own narrow transition guard below.
CREATE FUNCTION context.forbid_mutation()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION '% is append-only: % blocked', TG_TABLE_NAME, TG_OP;
END;
$$;

CREATE FUNCTION context.assert_source_version_retained(p_source_version_id UUID)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_status TEXT;
    v_original_object_id UUID;
BEGIN
    SELECT status, original_object_id
      INTO v_status, v_original_object_id
    FROM context.source_version
    WHERE id = p_source_version_id
    FOR UPDATE;
    IF NOT FOUND OR v_status <> 'retained' OR v_original_object_id IS NULL THEN
        RAISE EXCEPTION 'source version % is not retained for downstream writes', p_source_version_id;
    END IF;
END;
$$;

CREATE FUNCTION context.assert_raw_generation_open(p_raw_generation_id UUID)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_status TEXT;
BEGIN
    SELECT status INTO v_status
    FROM context.raw_generation
    WHERE id = p_raw_generation_id
    FOR UPDATE;
    IF NOT FOUND OR v_status <> 'open' THEN
        RAISE EXCEPTION 'raw generation % is not open for member writes', p_raw_generation_id;
    END IF;
END;
$$;

CREATE FUNCTION context.assert_normalized_generation_open(p_normalized_generation_id UUID)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_status TEXT;
BEGIN
    SELECT status INTO v_status
    FROM context.normalized_generation
    WHERE id = p_normalized_generation_id
    FOR UPDATE;
    IF NOT FOUND OR v_status <> 'open' THEN
        RAISE EXCEPTION 'normalized generation % is not open for member writes', p_normalized_generation_id;
    END IF;
END;
$$;

CREATE FUNCTION context.guard_source_version_mutation()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION 'source_version is append-only: DELETE blocked';
    END IF;
    IF OLD.status = 'registered' AND NEW.status = 'retained'
       AND NEW.id IS NOT DISTINCT FROM OLD.id
       AND NEW.source_id IS NOT DISTINCT FROM OLD.source_id
       AND NEW.version_ordinal IS NOT DISTINCT FROM OLD.version_ordinal
       AND NEW.workflow_id IS NOT DISTINCT FROM OLD.workflow_id
       AND NEW.submission_idempotency_key IS NOT DISTINCT FROM OLD.submission_idempotency_key
       AND NEW.declared_format IS NOT DISTINCT FROM OLD.declared_format
       AND NEW.original_filename IS NOT DISTINCT FROM OLD.original_filename
       AND NEW.acquired_at IS NOT DISTINCT FROM OLD.acquired_at
       AND NEW.created_at IS NOT DISTINCT FROM OLD.created_at
       AND NEW.original_object_id IS NOT NULL
       AND EXISTS (
           SELECT 1 FROM context.source_version_object source_object
           WHERE source_object.source_version_id = NEW.id
             AND source_object.object_id = NEW.original_object_id
             AND source_object.object_role = 'original'
       )
       AND EXISTS (
           SELECT 1
           FROM context.activity_receipt receipt
           JOIN context.activity_execution execution ON execution.id = receipt.activity_execution_id
           WHERE receipt.status = 'success'
             AND execution.source_version_id = NEW.id
             AND execution.activity_name = 'retain_original_activity'
             AND receipt.result_ref->>'ref_kind' = 'retained_object'
             AND receipt.result_ref->>'ref_id' = NEW.original_object_id::TEXT
       ) THEN
        RETURN NEW;
    END IF;
    RAISE EXCEPTION 'source version lifecycle only permits registered -> retained with its original object';
END;
$$;

CREATE FUNCTION context.guard_source_version_object_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_status TEXT;
BEGIN
    SELECT status INTO v_status
    FROM context.source_version
    WHERE id = NEW.source_version_id
    FOR UPDATE;
    IF v_status = 'registered' AND NEW.object_role <> 'original' THEN
        RAISE EXCEPTION 'only the original object may be attached before source version retention';
    END IF;
    IF v_status = 'retained' AND NEW.object_role = 'original' THEN
        RAISE EXCEPTION 'a retained source version cannot replace its original object';
    END IF;
    IF v_status IS NULL THEN
        RAISE EXCEPTION 'source version % does not exist', NEW.source_version_id;
    END IF;
    RETURN NEW;
END;
$$;

CREATE FUNCTION context.guard_raw_generation_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM context.assert_source_version_retained(NEW.source_version_id);
    RETURN NEW;
END;
$$;

CREATE FUNCTION context.guard_normalized_generation_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM context.assert_source_version_retained(NEW.source_version_id);
    PERFORM 1
    FROM context.raw_generation
    WHERE id = NEW.raw_generation_id
      AND source_version_id = NEW.source_version_id
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'normalized generation requires its same-source raw generation parent';
    END IF;
    RETURN NEW;
END;
$$;

CREATE FUNCTION context.guard_activity_execution_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_status TEXT;
BEGIN
    SELECT status INTO v_status
    FROM context.source_version
    WHERE id = NEW.source_version_id
    FOR UPDATE;
    IF v_status = 'retained' THEN
        RETURN NEW;
    END IF;
    IF v_status = 'registered'
       AND NEW.activity_name IN ('register_source_activity', 'retain_original_activity') THEN
        RETURN NEW;
    END IF;
    RAISE EXCEPTION 'activity % requires a retained source version', NEW.activity_name;
END;
$$;

CREATE FUNCTION context.guard_hash_batch_member_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_batch context.hash_batch%ROWTYPE;
BEGIN
    SELECT * INTO v_batch
    FROM context.hash_batch
    WHERE id = NEW.hash_batch_id
      AND status = 'open'
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'hash batch % is not open for member writes', NEW.hash_batch_id;
    END IF;
    IF v_batch.raw_generation_id IS NOT NULL THEN
        PERFORM context.assert_raw_generation_open(v_batch.raw_generation_id);
    ELSIF v_batch.normalized_generation_id IS NOT NULL THEN
        PERFORM context.assert_normalized_generation_open(v_batch.normalized_generation_id);
    ELSE
        PERFORM context.assert_source_version_retained(v_batch.source_version_id);
    END IF;

    IF v_batch.hash_kind = 'h1_source' THEN
        IF NEW.ordinal <> 0
           OR NEW.source_version_id IS DISTINCT FROM v_batch.source_version_id
           OR NEW.raw_record_id IS NOT NULL OR NEW.normalized_record_id IS NOT NULL
           OR NEW.construction <> 'h1-rawbytes-v1' THEN
            RAISE EXCEPTION 'H1 batch member must be its source version at ordinal zero';
        END IF;
    ELSIF v_batch.hash_kind IN ('raw_record_digest', 'h3_raw_generation') THEN
        IF NEW.source_version_id IS NOT NULL OR NEW.raw_record_id IS NULL
           OR NEW.normalized_record_id IS NOT NULL OR NOT EXISTS (
                SELECT 1 FROM context.raw_record_identity raw
                WHERE raw.id = NEW.raw_record_id
                  AND raw.raw_generation_id = v_batch.raw_generation_id
                  AND raw.source_version_id = v_batch.source_version_id
                  AND raw.record_ordinal = NEW.ordinal
                  AND raw.raw_hash_construction = NEW.construction
           ) THEN
            RAISE EXCEPTION 'raw hash batch member must match its ordered persisted raw row';
        END IF;
    ELSE
        IF NEW.source_version_id IS NOT NULL OR NEW.raw_record_id IS NOT NULL
           OR NEW.normalized_record_id IS NULL OR NOT EXISTS (
                SELECT 1 FROM context.normalized_record_identity normalized
                WHERE normalized.id = NEW.normalized_record_id
                  AND normalized.normalized_generation_id = v_batch.normalized_generation_id
                  AND normalized.source_version_id = v_batch.source_version_id
                  AND normalized.record_ordinal = NEW.ordinal
                  AND normalized.canonicalization = NEW.construction
           ) THEN
            RAISE EXCEPTION 'normalized hash batch member must match its ordered persisted normalized row';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE FUNCTION context.guard_hash_batch_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM context.assert_source_version_retained(NEW.source_version_id);
    IF NEW.raw_generation_id IS NOT NULL THEN
        PERFORM context.assert_raw_generation_open(NEW.raw_generation_id);
        IF NOT EXISTS (
            SELECT 1 FROM context.raw_generation
            WHERE id = NEW.raw_generation_id
              AND source_version_id = NEW.source_version_id
        ) THEN
            RAISE EXCEPTION 'raw hash batch must belong to its source version';
        END IF;
    ELSIF NEW.normalized_generation_id IS NOT NULL THEN
        PERFORM context.assert_normalized_generation_open(NEW.normalized_generation_id);
        IF NOT EXISTS (
            SELECT 1 FROM context.normalized_generation
            WHERE id = NEW.normalized_generation_id
              AND source_version_id = NEW.source_version_id
        ) THEN
            RAISE EXCEPTION 'normalized hash batch must belong to its source version';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE FUNCTION context.guard_hash_batch_transition()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION 'hash_batch is append-only: DELETE blocked';
    END IF;
    IF OLD.status <> 'open' OR NEW.status NOT IN ('completed', 'aborted')
       OR NEW.id IS DISTINCT FROM OLD.id
       OR NEW.activity_execution_id IS DISTINCT FROM OLD.activity_execution_id
       OR NEW.source_version_id IS DISTINCT FROM OLD.source_version_id
       OR NEW.attempt IS DISTINCT FROM OLD.attempt
       OR NEW.hash_kind IS DISTINCT FROM OLD.hash_kind
       OR NEW.raw_generation_id IS DISTINCT FROM OLD.raw_generation_id
       OR NEW.normalized_generation_id IS DISTINCT FROM OLD.normalized_generation_id
       OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
        RAISE EXCEPTION 'hash batch lifecycle only permits immutable open -> completed/aborted';
    END IF;
    IF NEW.status = 'completed' THEN
        IF NEW.raw_generation_id IS NOT NULL THEN
            PERFORM context.assert_raw_generation_open(NEW.raw_generation_id);
        ELSIF NEW.normalized_generation_id IS NOT NULL THEN
            PERFORM context.assert_normalized_generation_open(NEW.normalized_generation_id);
        END IF;
        IF NEW.member_count <> (
            SELECT count(*) FROM context.hash_batch_member member
            WHERE member.hash_batch_id = NEW.id
        ) OR NOT EXISTS (
            SELECT 1
            FROM context.activity_receipt receipt
            WHERE receipt.id = NEW.activity_receipt_id
              AND receipt.activity_execution_id = NEW.activity_execution_id
              AND receipt.attempt = NEW.attempt
              AND receipt.status = 'success'
              AND receipt.result_ref = NEW.result_ref
        ) THEN
            RAISE EXCEPTION 'completed hash batch requires exact durable membership and Activity result';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE FUNCTION context.assert_hash_manifest_complete(p_hash_manifest_id UUID)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_manifest context.hash_manifest%ROWTYPE;
BEGIN
    SELECT * INTO v_manifest
    FROM context.hash_manifest
    WHERE id = p_hash_manifest_id
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'hash manifest % does not exist', p_hash_manifest_id;
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM context.hash_manifest_member
        WHERE hash_manifest_id = p_hash_manifest_id
    ) THEN
        RAISE EXCEPTION 'hash manifest % cannot seal with zero members', p_hash_manifest_id;
    END IF;

    IF v_manifest.hash_kind = 'h3_raw_generation' THEN
        IF EXISTS (
            SELECT 1
            FROM context.raw_record_identity raw
            WHERE raw.raw_generation_id = v_manifest.raw_generation_id
              AND NOT EXISTS (
                  SELECT 1 FROM context.hash_manifest_member member
                  WHERE member.hash_manifest_id = v_manifest.id
                    AND member.raw_record_id = raw.id
                    AND member.ordinal = raw.record_ordinal
              )
        ) OR EXISTS (
            SELECT 1
            FROM context.hash_manifest_member member
            LEFT JOIN context.raw_record_identity raw ON raw.id = member.raw_record_id
            WHERE member.hash_manifest_id = v_manifest.id
              AND (member.normalized_record_id IS NOT NULL
                   OR raw.raw_generation_id IS DISTINCT FROM v_manifest.raw_generation_id
                   OR member.ordinal IS DISTINCT FROM raw.record_ordinal)
        ) THEN
            RAISE EXCEPTION 'raw hash manifest % is partial or has incorrect ordered membership', p_hash_manifest_id;
        END IF;
    ELSE
        IF EXISTS (
            SELECT 1
            FROM context.normalized_record_identity normalized
            WHERE normalized.normalized_generation_id = v_manifest.normalized_generation_id
              AND NOT EXISTS (
                  SELECT 1 FROM context.hash_manifest_member member
                  WHERE member.hash_manifest_id = v_manifest.id
                    AND member.normalized_record_id = normalized.id
                    AND member.ordinal = normalized.record_ordinal
              )
        ) OR EXISTS (
            SELECT 1
            FROM context.hash_manifest_member member
            LEFT JOIN context.normalized_record_identity normalized
              ON normalized.id = member.normalized_record_id
            WHERE member.hash_manifest_id = v_manifest.id
              AND (member.raw_record_id IS NOT NULL
                   OR normalized.normalized_generation_id IS DISTINCT FROM v_manifest.normalized_generation_id
                   OR member.ordinal IS DISTINCT FROM normalized.record_ordinal)
        ) THEN
            RAISE EXCEPTION 'normalized hash manifest % is partial or has incorrect ordered membership',
                p_hash_manifest_id;
        END IF;
    END IF;
END;
$$;

CREATE FUNCTION context.guard_hash_manifest_member_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_hash_kind TEXT;
    v_raw_generation_id UUID;
    v_normalized_generation_id UUID;
BEGIN
    SELECT hash_kind, raw_generation_id, normalized_generation_id
      INTO v_hash_kind, v_raw_generation_id, v_normalized_generation_id
    FROM context.hash_manifest
    WHERE id = NEW.hash_manifest_id AND status = 'open'
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'hash manifest % is not open for member writes', NEW.hash_manifest_id;
    END IF;

    IF v_hash_kind = 'h3_raw_generation' THEN
        IF NEW.raw_record_id IS NULL OR NEW.normalized_record_id IS NOT NULL
           OR NOT EXISTS (
                SELECT 1
                FROM context.raw_record_identity raw
                JOIN context.hash_receipt h ON h.raw_record_id = raw.id
                  AND h.hash_kind = 'raw_record_digest'
                  AND h.digest = NEW.member_digest
                  AND h.construction = NEW.member_canon
                WHERE raw.id = NEW.raw_record_id
                  AND raw.raw_generation_id = v_raw_generation_id
                  AND raw.record_ordinal = NEW.ordinal
           ) THEN
            RAISE EXCEPTION 'raw hash manifest member must match ordered H2 receipt in its raw generation';
        END IF;
    ELSE
        IF NEW.normalized_record_id IS NULL OR NEW.raw_record_id IS NOT NULL
           OR NOT EXISTS (
                SELECT 1
                FROM context.normalized_record_identity normalized
                JOIN context.hash_receipt h ON h.normalized_record_id = normalized.id
                  AND h.hash_kind = 'normalized_record_digest'
                  AND h.digest = NEW.member_digest
                  AND h.construction = NEW.member_canon
                WHERE normalized.id = NEW.normalized_record_id
                  AND normalized.normalized_generation_id = v_normalized_generation_id
                  AND normalized.record_ordinal = NEW.ordinal
           ) THEN
            RAISE EXCEPTION 'normalized hash manifest member must match ordered normalized digest receipt';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE FUNCTION context.guard_hash_manifest_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.raw_generation_id IS NOT NULL THEN
        PERFORM context.assert_raw_generation_open(NEW.raw_generation_id);
    ELSE
        PERFORM context.assert_normalized_generation_open(NEW.normalized_generation_id);
    END IF;
    RETURN NEW;
END;
$$;

CREATE FUNCTION context.guard_hash_manifest_transition()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF OLD.status <> 'open' OR NEW.status <> 'sealed'
       OR NEW.id IS DISTINCT FROM OLD.id
       OR NEW.hash_kind IS DISTINCT FROM OLD.hash_kind
       OR NEW.raw_generation_id IS DISTINCT FROM OLD.raw_generation_id
       OR NEW.normalized_generation_id IS DISTINCT FROM OLD.normalized_generation_id
       OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
        RAISE EXCEPTION 'hash manifest lifecycle only permits its immutable open -> sealed transition';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM context.hash_receipt h
        WHERE h.id = NEW.sealed_hash_receipt_id
          AND h.hash_manifest_id = NEW.id
          AND h.hash_kind = NEW.hash_kind
          AND (h.raw_generation_id = NEW.raw_generation_id
               OR h.normalized_generation_id = NEW.normalized_generation_id)
    ) THEN
        RAISE EXCEPTION 'sealed hash manifest requires its matching generation hash receipt';
    END IF;
    PERFORM context.assert_hash_manifest_complete(NEW.id);
    IF NEW.member_count <> (SELECT count(*) FROM context.hash_manifest_member
                            WHERE hash_manifest_id = NEW.id) THEN
        RAISE EXCEPTION 'sealed hash manifest member count does not equal durable membership rows';
    END IF;
    RETURN NEW;
END;
$$;

CREATE FUNCTION context.guard_hash_receipt_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_subject_source_version_id UUID;
    v_expected_activity TEXT;
    v_raw_generation_id UUID;
    v_normalized_generation_id UUID;
BEGIN
    IF NEW.hash_kind = 'h1_source' THEN
        PERFORM context.assert_source_version_retained(NEW.source_version_id);
    ELSIF NEW.hash_kind = 'raw_record_digest' THEN
        SELECT raw_generation_id INTO v_raw_generation_id
        FROM context.raw_record_identity
        WHERE id = NEW.raw_record_id;
        PERFORM context.assert_raw_generation_open(v_raw_generation_id);
    ELSIF NEW.hash_kind = 'h3_raw_generation' THEN
        PERFORM context.assert_raw_generation_open(NEW.raw_generation_id);
    ELSIF NEW.hash_kind = 'normalized_record_digest' THEN
        SELECT normalized_generation_id INTO v_normalized_generation_id
        FROM context.normalized_record_identity
        WHERE id = NEW.normalized_record_id;
        PERFORM context.assert_normalized_generation_open(v_normalized_generation_id);
    ELSE
        PERFORM context.assert_normalized_generation_open(NEW.normalized_generation_id);
    END IF;

    SELECT COALESCE(
        NEW.source_version_id,
        (SELECT source_version_id FROM context.raw_record_identity WHERE id = NEW.raw_record_id),
        (SELECT source_version_id FROM context.raw_generation WHERE id = NEW.raw_generation_id),
        (SELECT source_version_id FROM context.normalized_record_identity WHERE id = NEW.normalized_record_id),
        (SELECT source_version_id FROM context.normalized_generation WHERE id = NEW.normalized_generation_id)
    ) INTO v_subject_source_version_id;
    v_expected_activity := CASE NEW.hash_kind
        WHEN 'h1_source' THEN 'hash_source_activity'
        WHEN 'raw_record_digest' THEN 'hash_raw_records_activity'
        WHEN 'h3_raw_generation' THEN 'hash_raw_generation_activity'
        WHEN 'normalized_record_digest' THEN 'hash_normalized_records_activity'
        WHEN 'normalized_generation_manifest_digest' THEN 'hash_normalized_generation_activity'
    END;
    -- H1 and generation hashes produce one row per Activity result. H2 and
    -- normalized-record digest Activities stream an exact source-generation
    -- set, so their receipt is bound to that generation rather than each row.
    IF NOT EXISTS (
        SELECT 1
        FROM context.activity_receipt receipt
        JOIN context.activity_execution execution ON execution.id = receipt.activity_execution_id
        WHERE receipt.id = NEW.activity_receipt_id
          AND receipt.status = 'success'
          AND execution.source_version_id = v_subject_source_version_id
          AND execution.activity_name = v_expected_activity
          AND (
              (NEW.hash_kind IN (
                    'h1_source', 'h3_raw_generation', 'normalized_generation_manifest_digest')
                  AND receipt.result_ref->>'ref_kind' = 'hash_receipt'
                  AND receipt.result_ref->>'ref_id' = NEW.id::TEXT)
              OR (NEW.hash_kind = 'raw_record_digest'
                  AND receipt.result_ref->>'ref_kind' = 'raw_hash_receipt_set'
                  AND receipt.result_ref->>'ref_id' = (
                      SELECT raw_generation_id::TEXT
                      FROM context.raw_record_identity
                      WHERE id = NEW.raw_record_id
                  ))
              OR (NEW.hash_kind = 'normalized_record_digest'
                  AND receipt.result_ref->>'ref_kind' = 'normalized_hash_receipt_set'
                  AND receipt.result_ref->>'ref_id' = (
                      SELECT normalized_generation_id::TEXT
                      FROM context.normalized_record_identity
                      WHERE id = NEW.normalized_record_id
                  ))
          )
    ) OR NEW.computed_by <> v_expected_activity THEN
        RAISE EXCEPTION 'hash receipt requires successful same-source % receipt', v_expected_activity;
    END IF;
    IF NEW.hash_kind = 'h1_source' AND NOT EXISTS (
        SELECT 1
        FROM context.source_version source_version
        JOIN context.retained_object original_object
          ON original_object.id = source_version.original_object_id
        WHERE source_version.id = NEW.source_version_id
          AND original_object.content_sha256 = NEW.digest
    ) THEN
        RAISE EXCEPTION 'H1 receipt must equal the retained original content_sha256';
    END IF;
    IF NEW.hash_kind = 'raw_record_digest' AND NOT EXISTS (
        SELECT 1
        FROM context.raw_record_identity raw
        LEFT JOIN context.retained_object locator_object
          ON locator_object.id = raw.locator_object_id
        WHERE raw.id = NEW.raw_record_id
          AND raw.raw_hash_construction = NEW.construction
          AND (
              (raw.stored_bytes IS NOT NULL
                  AND digest(raw.stored_bytes, 'sha256') = NEW.digest)
              OR (raw.stored_bytes IS NULL
                  AND locator_object.storage_class = 'inline'
                  AND raw.byte_offset + raw.byte_length <= locator_object.byte_length
                  AND digest(
                      substring(locator_object.inline_bytes
                                FROM raw.byte_offset + 1 FOR raw.byte_length),
                      'sha256'
                  ) = NEW.digest)
              OR (raw.stored_bytes IS NULL
                  AND locator_object.storage_class <> 'inline')
          )
    ) THEN
        RAISE EXCEPTION 'raw H2 receipt does not match DB-resident stored bytes or inline byte range';
    END IF;
    IF NEW.hash_kind = 'normalized_record_digest' AND NOT EXISTS (
        SELECT 1
        FROM context.normalized_record_identity normalized
        WHERE normalized.id = NEW.normalized_record_id
          AND normalized.canonicalization = NEW.construction
          AND digest(normalized.canonical_bytes, 'sha256') = NEW.digest
    ) THEN
        RAISE EXCEPTION 'normalized record digest must hash its exact canonical_bytes and canonicalization';
    END IF;
    IF NEW.hash_kind IN ('h3_raw_generation', 'normalized_generation_manifest_digest') THEN
        PERFORM 1
        FROM context.hash_manifest manifest
        WHERE manifest.id = NEW.hash_manifest_id
          AND manifest.status = 'open'
          AND manifest.hash_kind = NEW.hash_kind
          AND (manifest.raw_generation_id = NEW.raw_generation_id
               OR manifest.normalized_generation_id = NEW.normalized_generation_id)
        FOR UPDATE;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'generation hash receipt requires its matching open manifest';
        END IF;
        PERFORM context.assert_hash_manifest_complete(NEW.hash_manifest_id);
    END IF;
    RETURN NEW;
END;
$$;

CREATE FUNCTION context.seal_hash_manifest_from_receipt()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.hash_kind IN ('h3_raw_generation', 'normalized_generation_manifest_digest') THEN
        UPDATE context.hash_manifest
        SET status = 'sealed',
            member_count = (SELECT count(*) FROM context.hash_manifest_member
                            WHERE hash_manifest_id = NEW.hash_manifest_id),
            sealed_hash_receipt_id = NEW.id,
            sealed_at = NEW.computed_at
        WHERE id = NEW.hash_manifest_id;
    END IF;
    RETURN NEW;
END;
$$;

CREATE FUNCTION context.guard_reconciliation_receipt_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_subject_source_version_id UUID;
    v_expected_activity TEXT;
BEGIN
    IF NEW.raw_generation_id IS NOT NULL THEN
        PERFORM context.assert_raw_generation_open(NEW.raw_generation_id);
    ELSE
        PERFORM context.assert_normalized_generation_open(NEW.normalized_generation_id);
    END IF;

    SELECT COALESCE(
        (SELECT source_version_id FROM context.raw_generation WHERE id = NEW.raw_generation_id),
        (SELECT source_version_id FROM context.normalized_generation WHERE id = NEW.normalized_generation_id)
    ) INTO v_subject_source_version_id;
    v_expected_activity := CASE NEW.reconciliation_kind
        WHEN 'record_accounting' THEN 'reconcile_record_accounting_activity'
        WHEN 'byte_coverage' THEN 'reconcile_byte_coverage_activity'
        WHEN 'raw_source_verification' THEN 'verify_raw_coverage_against_source_activity'
        WHEN 'raw_lineage_validation' THEN 'validate_raw_lineage_activity'
        WHEN 'normalized_generation_verification' THEN 'verify_normalized_generation_activity'
    END;

    -- Some formats cannot expose meaningful byte offsets without inventing
    -- provenance.  They remain admissible only when every raw record retains
    -- its exact bytes in stored_bytes.  Record accounting and all normalized
    -- verification stages remain mandatory successes.
    IF NEW.status = 'not_applicable' THEN
        IF NEW.reconciliation_kind <> 'byte_coverage' THEN
            RAISE EXCEPTION 'not_applicable reconciliation is permitted only for byte_coverage';
        END IF;
        IF NOT (NEW.expected ? 'source_byte_length')
           OR NEW.observed->>'locator_based_records' IS DISTINCT FROM '0'
           OR EXISTS (
               SELECT 1
               FROM context.raw_record_identity raw
               WHERE raw.raw_generation_id = NEW.raw_generation_id
                 AND (raw.stored_bytes IS NULL
                      OR raw.locator_object_id IS NOT NULL
                      OR raw.byte_offset IS NOT NULL
                      OR raw.byte_length IS NOT NULL)
           ) THEN
            RAISE EXCEPTION 'not_applicable byte coverage requires exact stored bytes for every raw record';
        END IF;
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM context.activity_receipt receipt
        JOIN context.activity_execution execution ON execution.id = receipt.activity_execution_id
        WHERE receipt.id = NEW.activity_receipt_id
          -- The Activity itself completed successfully even when its governed
          -- reconciliation finding is failed or not_applicable.
          AND receipt.status = 'success'
          AND execution.source_version_id = v_subject_source_version_id
          AND execution.activity_name = v_expected_activity
          AND receipt.result_ref->>'ref_kind' = 'reconciliation_receipt'
          AND receipt.result_ref->>'ref_id' = NEW.id::TEXT
    ) THEN
        RAISE EXCEPTION 'reconciliation receipt requires successful same-source % activity receipt',
            v_expected_activity;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER retained_object_append_only
    BEFORE UPDATE OR DELETE ON context.retained_object
    FOR EACH ROW EXECUTE FUNCTION context.forbid_mutation();
CREATE TRIGGER raw_record_identity_append_only
    BEFORE UPDATE OR DELETE ON context.raw_record_identity
    FOR EACH ROW EXECUTE FUNCTION context.forbid_mutation();
CREATE TRIGGER source_metadata_append_only
    BEFORE UPDATE OR DELETE ON context.source_metadata
    FOR EACH ROW EXECUTE FUNCTION context.forbid_mutation();
CREATE TRIGGER normalized_record_identity_append_only
    BEFORE UPDATE OR DELETE ON context.normalized_record_identity
    FOR EACH ROW EXECUTE FUNCTION context.forbid_mutation();
CREATE TRIGGER normalization_lineage_append_only
    BEFORE UPDATE OR DELETE ON context.normalization_lineage
    FOR EACH ROW EXECUTE FUNCTION context.forbid_mutation();
CREATE TRIGGER activity_receipt_append_only
    BEFORE UPDATE OR DELETE ON context.activity_receipt
    FOR EACH ROW EXECUTE FUNCTION context.forbid_mutation();
CREATE TRIGGER hash_batch_insert_gate
    BEFORE INSERT ON context.hash_batch
    FOR EACH ROW EXECUTE FUNCTION context.guard_hash_batch_insert();
CREATE TRIGGER hash_batch_member_append_only
    BEFORE UPDATE OR DELETE ON context.hash_batch_member
    FOR EACH ROW EXECUTE FUNCTION context.forbid_mutation();
CREATE TRIGGER hash_batch_member_open_gate
    BEFORE INSERT ON context.hash_batch_member
    FOR EACH ROW EXECUTE FUNCTION context.guard_hash_batch_member_insert();
CREATE TRIGGER hash_batch_transition_gate
    BEFORE UPDATE OR DELETE ON context.hash_batch
    FOR EACH ROW EXECUTE FUNCTION context.guard_hash_batch_transition();
CREATE TRIGGER hash_receipt_append_only
    BEFORE UPDATE OR DELETE ON context.hash_receipt
    FOR EACH ROW EXECUTE FUNCTION context.forbid_mutation();
CREATE TRIGGER reconciliation_receipt_append_only
    BEFORE UPDATE OR DELETE ON context.reconciliation_receipt
    FOR EACH ROW EXECUTE FUNCTION context.forbid_mutation();
CREATE TRIGGER normalized_generation_publication_append_only
    BEFORE UPDATE OR DELETE ON context.normalized_generation_publication
    FOR EACH ROW EXECUTE FUNCTION context.forbid_mutation();
CREATE TRIGGER source_append_only
    BEFORE UPDATE OR DELETE ON context.source
    FOR EACH ROW EXECUTE FUNCTION context.forbid_mutation();
CREATE TRIGGER source_version_append_only
    BEFORE UPDATE OR DELETE ON context.source_version
    FOR EACH ROW EXECUTE FUNCTION context.guard_source_version_mutation();
CREATE TRIGGER source_version_object_append_only
    BEFORE UPDATE OR DELETE ON context.source_version_object
    FOR EACH ROW EXECUTE FUNCTION context.forbid_mutation();
CREATE TRIGGER source_version_object_insert_gate
    BEFORE INSERT ON context.source_version_object
    FOR EACH ROW EXECUTE FUNCTION context.guard_source_version_object_insert();
CREATE TRIGGER activity_execution_append_only
    BEFORE UPDATE OR DELETE ON context.activity_execution
    FOR EACH ROW EXECUTE FUNCTION context.forbid_mutation();
CREATE TRIGGER activity_execution_retention_gate
    BEFORE INSERT ON context.activity_execution
    FOR EACH ROW EXECUTE FUNCTION context.guard_activity_execution_insert();
CREATE TRIGGER raw_generation_retention_gate
    BEFORE INSERT ON context.raw_generation
    FOR EACH ROW EXECUTE FUNCTION context.guard_raw_generation_insert();
CREATE TRIGGER normalized_generation_retention_gate
    BEFORE INSERT ON context.normalized_generation
    FOR EACH ROW EXECUTE FUNCTION context.guard_normalized_generation_insert();
CREATE TRIGGER raw_format_registry_append_only
    BEFORE UPDATE OR DELETE ON context.raw_format_registry
    FOR EACH ROW EXECUTE FUNCTION context.forbid_mutation();
CREATE TRIGGER hash_manifest_insert_gate
    BEFORE INSERT ON context.hash_manifest
    FOR EACH ROW EXECUTE FUNCTION context.guard_hash_manifest_insert();
CREATE TRIGGER hash_manifest_member_append_only
    BEFORE UPDATE OR DELETE ON context.hash_manifest_member
    FOR EACH ROW EXECUTE FUNCTION context.forbid_mutation();
CREATE TRIGGER hash_manifest_delete_forbidden
    BEFORE DELETE ON context.hash_manifest
    FOR EACH ROW EXECUTE FUNCTION context.forbid_mutation();
CREATE TRIGGER hash_manifest_member_open_gate
    BEFORE INSERT ON context.hash_manifest_member
    FOR EACH ROW EXECUTE FUNCTION context.guard_hash_manifest_member_insert();
CREATE TRIGGER hash_manifest_seal_gate
    BEFORE UPDATE ON context.hash_manifest
    FOR EACH ROW EXECUTE FUNCTION context.guard_hash_manifest_transition();
CREATE TRIGGER hash_receipt_insert_gate
    BEFORE INSERT ON context.hash_receipt
    FOR EACH ROW EXECUTE FUNCTION context.guard_hash_receipt_insert();
CREATE TRIGGER hash_receipt_seal_manifest
    AFTER INSERT ON context.hash_receipt
    FOR EACH ROW EXECUTE FUNCTION context.seal_hash_manifest_from_receipt();
CREATE TRIGGER reconciliation_receipt_insert_gate
    BEFORE INSERT ON context.reconciliation_receipt
    FOR EACH ROW EXECUTE FUNCTION context.guard_reconciliation_receipt_insert();

CREATE FUNCTION context.guard_raw_record_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM context.assert_raw_generation_open(NEW.raw_generation_id);
    RETURN NEW;
END;
$$;

CREATE TRIGGER raw_record_identity_open_generation_gate
    BEFORE INSERT ON context.raw_record_identity
    FOR EACH ROW EXECUTE FUNCTION context.guard_raw_record_insert();

CREATE FUNCTION context.guard_raw_subtype_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_raw_generation_id UUID;
BEGIN
    SELECT raw_generation_id INTO v_raw_generation_id
    FROM context.raw_record_identity
    WHERE id = NEW.raw_record_id;
    PERFORM context.assert_raw_generation_open(v_raw_generation_id);
    RETURN NEW;
END;
$$;

CREATE FUNCTION context.guard_source_metadata_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_raw_generation_id UUID;
    v_expected_activity TEXT;
BEGIN
    PERFORM context.assert_source_version_retained(NEW.source_version_id);
    v_expected_activity := CASE NEW.metadata_class
        WHEN 'filesystem' THEN 'capture_filesystem_metadata_activity'
        WHEN 'container' THEN 'inventory_container_activity'
        WHEN 'embedded' THEN 'extract_embedded_metadata_activity'
        WHEN 'media_tool' THEN 'extract_embedded_metadata_activity'
        WHEN 'record_native' THEN 'execute_parser_activity'
    END;
    IF NOT EXISTS (
        SELECT 1
        FROM context.activity_receipt receipt
        JOIN context.activity_execution execution ON execution.id = receipt.activity_execution_id
        WHERE receipt.id = NEW.extraction_activity_receipt_id
          AND receipt.status = 'success'
          AND execution.source_version_id = NEW.source_version_id
          AND execution.activity_name = v_expected_activity
    ) THEN
        RAISE EXCEPTION 'source metadata requires successful same-source % receipt', v_expected_activity;
    END IF;
    IF NEW.raw_record_id IS NOT NULL THEN
        SELECT raw_generation_id INTO v_raw_generation_id
        FROM context.raw_record_identity
        WHERE id = NEW.raw_record_id;
        PERFORM context.assert_raw_generation_open(v_raw_generation_id);
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER source_metadata_open_generation_gate
    BEFORE INSERT ON context.source_metadata
    FOR EACH ROW EXECUTE FUNCTION context.guard_source_metadata_insert();

CREATE FUNCTION context.guard_normalized_record_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM context.assert_normalized_generation_open(NEW.normalized_generation_id);
    RETURN NEW;
END;
$$;

CREATE TRIGGER normalized_record_identity_open_generation_gate
    BEFORE INSERT ON context.normalized_record_identity
    FOR EACH ROW EXECUTE FUNCTION context.guard_normalized_record_insert();

CREATE FUNCTION context.guard_normalization_lineage_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM context.assert_normalized_generation_open(NEW.normalized_generation_id);
    PERFORM 1
    FROM context.raw_generation
    WHERE id = NEW.raw_generation_id
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'normalization lineage requires its raw generation parent';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER normalization_lineage_open_generation_gate
    BEFORE INSERT ON context.normalization_lineage
    FOR EACH ROW EXECUTE FUNCTION context.guard_normalization_lineage_insert();

CREATE FUNCTION context.assert_raw_subtype_completeness(p_raw_generation_id UUID)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_format RECORD;
    v_missing BOOLEAN;
BEGIN
    FOR v_format IN
        SELECT format_id, subtype_relation FROM context.raw_format_registry
    LOOP
        EXECUTE format(
            'SELECT EXISTS (
                SELECT 1
                FROM context.raw_record_identity raw
                WHERE raw.raw_generation_id = $1
                  AND raw.format_id = $2
                  AND NOT EXISTS (
                    SELECT 1 FROM %s subtype
                    WHERE subtype.raw_record_id = raw.id
                  )
            )',
            v_format.subtype_relation
        ) INTO v_missing USING p_raw_generation_id, v_format.format_id;
        IF v_missing THEN
            RAISE EXCEPTION 'raw generation % has raw records without their registered subtype payload',
                p_raw_generation_id;
        END IF;
    END LOOP;
END;
$$;

-- Gate only legitimate lifecycle transitions.  At raw seal it requires H1,
-- every H2, H3, complete registered subtypes, and successful accounting,
-- coverage, and raw/source verification receipts.
CREATE FUNCTION context.guard_raw_generation_transition()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF OLD.status <> 'open' OR NEW.status <> 'sealed' THEN
        RAISE EXCEPTION 'raw generation lifecycle only permits open -> sealed';
    END IF;
    IF NEW.id IS DISTINCT FROM OLD.id
       OR NEW.source_version_id IS DISTINCT FROM OLD.source_version_id
       OR NEW.generation_ordinal IS DISTINCT FROM OLD.generation_ordinal
       OR NEW.format_id IS DISTINCT FROM OLD.format_id
       OR NEW.parser_id IS DISTINCT FROM OLD.parser_id
       OR NEW.parser_version IS DISTINCT FROM OLD.parser_version
       OR NEW.extraction_bundle_object_id IS DISTINCT FROM OLD.extraction_bundle_object_id
       OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
        RAISE EXCEPTION 'sealed raw generation identity and parser provenance are immutable';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM context.raw_record_identity raw
        WHERE raw.raw_generation_id = NEW.id
    ) THEN
        RAISE EXCEPTION 'raw generation % cannot seal with zero records or envelope spans', NEW.id;
    END IF;
    IF EXISTS (
        SELECT 1
        FROM (
            SELECT record_ordinal,
                   row_number() OVER (ORDER BY record_ordinal) - 1 AS expected_ordinal
            FROM context.raw_record_identity
            WHERE raw_generation_id = NEW.id
        ) ordinals
        WHERE record_ordinal <> expected_ordinal
    ) THEN
        RAISE EXCEPTION 'raw generation % has non-contiguous record ordinals', NEW.id;
    END IF;
    PERFORM context.assert_raw_subtype_completeness(NEW.id);
    IF NOT EXISTS (SELECT 1 FROM context.hash_receipt h
                   WHERE h.hash_kind = 'h1_source' AND h.source_version_id = NEW.source_version_id)
       OR EXISTS (SELECT 1 FROM context.raw_record_identity raw
                  WHERE raw.raw_generation_id = NEW.id
                    AND NOT EXISTS (SELECT 1 FROM context.hash_receipt h
                                    WHERE h.hash_kind = 'raw_record_digest' AND h.raw_record_id = raw.id))
       OR NOT EXISTS (
            SELECT 1
            FROM context.hash_receipt h
            JOIN context.hash_manifest manifest ON manifest.id = h.hash_manifest_id
            WHERE h.hash_kind = 'h3_raw_generation'
              AND h.raw_generation_id = NEW.id
              AND manifest.status = 'sealed'
              AND manifest.member_count = (
                  SELECT count(*) FROM context.raw_record_identity raw
                  WHERE raw.raw_generation_id = NEW.id
              )
       ) THEN
        RAISE EXCEPTION 'raw generation % lacks required H1/H2/H3 receipts', NEW.id;
    END IF;
    IF EXISTS (
        SELECT 1
        FROM (VALUES ('record_accounting'), ('byte_coverage'), ('raw_source_verification')) required(kind)
        WHERE NOT EXISTS (
            SELECT 1 FROM context.reconciliation_receipt r
            WHERE r.raw_generation_id = NEW.id
              AND r.reconciliation_kind = required.kind
              AND r.status = 'success'
        )
    ) THEN
        RAISE EXCEPTION 'raw generation % lacks required successful reconciliation receipts', NEW.id;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER raw_generation_seal_gate
    BEFORE UPDATE ON context.raw_generation
    FOR EACH ROW EXECUTE FUNCTION context.guard_raw_generation_transition();

-- A normalized publication itself must have a successful publish activity
-- receipt.  The generation status update below then requires this row.
CREATE FUNCTION context.guard_normalized_publication()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_generation_status TEXT;
BEGIN
    SELECT status INTO v_generation_status
    FROM context.normalized_generation
    WHERE id = NEW.normalized_generation_id
    FOR UPDATE;
    IF NOT FOUND OR v_generation_status <> 'sealed' THEN
        RAISE EXCEPTION 'normalized publication requires a sealed generation';
    END IF;
    IF NOT EXISTS (
        SELECT 1
        FROM context.activity_receipt receipt
        JOIN context.activity_execution execution ON execution.id = receipt.activity_execution_id
        JOIN context.normalized_generation generation
          ON generation.id = NEW.normalized_generation_id
        WHERE receipt.id = NEW.activity_receipt_id
          AND receipt.status = 'success'
          AND execution.activity_name = 'publish_generation_activity'
          AND execution.source_version_id = generation.source_version_id
          AND receipt.result_ref->>'ref_kind' = 'normalized_generation_publication'
          AND receipt.result_ref->>'ref_id' = NEW.id::TEXT
    ) THEN
        RAISE EXCEPTION 'normalized publication requires a successful publish_generation_activity receipt';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER normalized_generation_publication_receipt_gate
    BEFORE INSERT ON context.normalized_generation_publication
    FOR EACH ROW EXECUTE FUNCTION context.guard_normalized_publication();

-- Fail closed: a normalized generation cannot seal without an already-sealed
-- raw generation, one or more real raw FKs for every normalized record, every
-- normalized-record digest, the normalized manifest digest, and successful
-- raw-lineage + normalized-manifest verification receipts.  It cannot publish
-- without the publication row/receipt above.
CREATE FUNCTION context.guard_normalized_generation_transition()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF OLD.status = 'open' AND NEW.status = 'sealed' THEN
        IF NEW.id IS DISTINCT FROM OLD.id
           OR NEW.source_version_id IS DISTINCT FROM OLD.source_version_id
           OR NEW.raw_generation_id IS DISTINCT FROM OLD.raw_generation_id
           OR NEW.generation_ordinal IS DISTINCT FROM OLD.generation_ordinal
           OR NEW.normalizer_id IS DISTINCT FROM OLD.normalizer_id
           OR NEW.normalizer_version IS DISTINCT FROM OLD.normalizer_version
           OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
            RAISE EXCEPTION 'sealed normalized generation identity and normalizer provenance are immutable';
        END IF;
        IF NOT EXISTS (SELECT 1 FROM context.raw_generation raw
                       WHERE raw.id = NEW.raw_generation_id AND raw.status = 'sealed') THEN
            RAISE EXCEPTION 'normalized generation % cannot seal before raw generation % is sealed',
                NEW.id, NEW.raw_generation_id;
        END IF;
        IF NOT EXISTS (
            SELECT 1 FROM context.normalized_record_identity normalized
            WHERE normalized.normalized_generation_id = NEW.id
        ) THEN
            RAISE EXCEPTION 'normalized generation % cannot seal with zero records', NEW.id;
        END IF;
        IF EXISTS (
            SELECT 1
            FROM (
                SELECT record_ordinal,
                       row_number() OVER (ORDER BY record_ordinal) - 1 AS expected_ordinal
                FROM context.normalized_record_identity
                WHERE normalized_generation_id = NEW.id
            ) ordinals
            WHERE record_ordinal <> expected_ordinal
        ) THEN
            RAISE EXCEPTION 'normalized generation % has non-contiguous record ordinals', NEW.id;
        END IF;
        IF EXISTS (
            SELECT 1 FROM context.normalized_record_identity normalized
            WHERE normalized.normalized_generation_id = NEW.id
              AND NOT EXISTS (
                  SELECT 1 FROM context.normalization_lineage lineage
                  WHERE lineage.normalized_record_id = normalized.id
              )
        ) THEN
            RAISE EXCEPTION 'normalized generation % cannot seal without raw-record lineage for every member', NEW.id;
        END IF;
        IF EXISTS (
            SELECT 1 FROM context.normalized_record_identity normalized
            WHERE normalized.normalized_generation_id = NEW.id
              AND NOT EXISTS (
                  SELECT 1 FROM context.hash_receipt h
                  WHERE h.hash_kind = 'normalized_record_digest'
                    AND h.normalized_record_id = normalized.id
              )
        ) OR NOT EXISTS (
            SELECT 1
            FROM context.hash_receipt h
            JOIN context.hash_manifest manifest ON manifest.id = h.hash_manifest_id
            WHERE h.hash_kind = 'normalized_generation_manifest_digest'
              AND h.normalized_generation_id = NEW.id
              AND manifest.status = 'sealed'
              AND manifest.member_count = (
                  SELECT count(*) FROM context.normalized_record_identity normalized
                  WHERE normalized.normalized_generation_id = NEW.id
              )
        ) THEN
            RAISE EXCEPTION 'normalized generation % lacks required normalized digest receipts', NEW.id;
        END IF;
        IF EXISTS (
            SELECT 1
            FROM (VALUES ('raw_lineage_validation'), ('normalized_generation_verification')) required(kind)
            WHERE NOT EXISTS (
                SELECT 1 FROM context.reconciliation_receipt r
                WHERE r.normalized_generation_id = NEW.id
                  AND r.reconciliation_kind = required.kind
                  AND r.status = 'success'
            )
        ) THEN
            RAISE EXCEPTION 'normalized generation % lacks required successful reconciliation receipts', NEW.id;
        END IF;
        RETURN NEW;
    END IF;

    IF OLD.status = 'sealed' AND NEW.status = 'published' THEN
        IF NEW.id IS DISTINCT FROM OLD.id
           OR NEW.source_version_id IS DISTINCT FROM OLD.source_version_id
           OR NEW.raw_generation_id IS DISTINCT FROM OLD.raw_generation_id
           OR NEW.generation_ordinal IS DISTINCT FROM OLD.generation_ordinal
           OR NEW.normalizer_id IS DISTINCT FROM OLD.normalizer_id
           OR NEW.normalizer_version IS DISTINCT FROM OLD.normalizer_version
           OR NEW.sealed_at IS DISTINCT FROM OLD.sealed_at
           OR NEW.sealed_by IS DISTINCT FROM OLD.sealed_by
           OR NEW.created_at IS DISTINCT FROM OLD.created_at
           OR NEW.published_at IS NULL THEN
            RAISE EXCEPTION 'published normalized generation may only add its publication timestamp';
        END IF;
        IF EXISTS (
            SELECT 1
            FROM context.normalized_generation_publication publication
            WHERE publication.normalized_generation_id = NEW.id
        ) THEN
            RETURN NEW;
        END IF;
        RAISE EXCEPTION 'normalized generation % cannot publish without a publication receipt', NEW.id;
    END IF;

    RAISE EXCEPTION 'normalized generation lifecycle only permits open -> sealed -> published';
END;
$$;

CREATE TRIGGER normalized_generation_seal_publish_gate
    BEFORE UPDATE ON context.normalized_generation
    FOR EACH ROW EXECUTE FUNCTION context.guard_normalized_generation_transition();

COMMENT ON SCHEMA context IS
    'Context-only universal-import landing schema. Canonical raw and normalized context remains unredacted; redaction is permitted only in on-demand derived court/export output. No evidence/custody FKs or promotion are permitted here.';
COMMENT ON TABLE context.normalization_lineage IS
    'Real raw-to-normalized M:N lineage through FKs. Replaces any format-table/id polymorphic pointer.';
COMMENT ON TABLE context.hash_receipt IS
    'Five distinct computations: raw H1/H2/H3 custody hashes plus separately named normalized digests.';

-- Least privilege.  The writer can append every intake relation and may update
-- only lifecycle relations whose triggers enforce the exact legal transition.
-- Readers cannot mutate.  Dynamic raw-format subtype tables are created by the
-- SECURITY DEFINER registry function as context_owner and inherit these same
-- default grants.
REVOKE ALL ON SCHEMA context FROM PUBLIC;
GRANT USAGE ON SCHEMA context TO context_import_writer, context_reader;

REVOKE ALL ON ALL TABLES IN SCHEMA context FROM PUBLIC;
GRANT SELECT, INSERT ON ALL TABLES IN SCHEMA context TO context_import_writer;
-- Format registration must pass the SECURITY DEFINER validator; callers may
-- not bypass it with a direct registry insert.
REVOKE INSERT ON context.raw_format_registry FROM context_import_writer;
GRANT SELECT ON ALL TABLES IN SCHEMA context TO context_reader;
GRANT UPDATE ON context.source_version,
                context.raw_generation,
                context.normalized_generation,
                context.hash_batch,
                context.hash_manifest
    TO context_import_writer;

REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA context FROM PUBLIC;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA context TO context_import_writer;

ALTER DEFAULT PRIVILEGES FOR ROLE context_owner IN SCHEMA context
    REVOKE ALL ON TABLES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE context_owner IN SCHEMA context
    GRANT SELECT, INSERT ON TABLES TO context_import_writer;
ALTER DEFAULT PRIVILEGES FOR ROLE context_owner IN SCHEMA context
    GRANT SELECT ON TABLES TO context_reader;
ALTER DEFAULT PRIVILEGES FOR ROLE context_owner IN SCHEMA context
    REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE context_owner IN SCHEMA context
    GRANT EXECUTE ON FUNCTIONS TO context_import_writer;

RESET ROLE;

COMMIT;
