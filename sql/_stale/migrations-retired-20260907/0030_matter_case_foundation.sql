-- 0030_matter_case_foundation.sql — Matter/CourtCase identity and governed
-- Knowledge-to-Evidence promotion foundation.
--
-- Byline: Codex · GPT-5 · 2026-08-15
--
-- ✅ APPLIED TO PROD 2026-08-23 on owner instruction — 100.91.190.107:5432 db=ai
--    (Claude Code · Opus 5). Applied via the file's own BEGIN/COMMIT, then verified:
--    analysis.matter, analysis.court_case, analysis.matter_knowledge_partition and
--    analysis.knowledge_evidence_promotion all CREATED; both promotion triggers
--    (knowledge_evidence_promotion_guard, knowledge_evidence_promotion_append_only)
--    installed; analysis.evidence_item gained matter_id + court_case_id while retaining
--    the legacy case_id column, and its row count was 0 before and 0 after.
--    Pre-flight confirmed the file contains no DROP/DELETE/TRUNCATE/UPDATE.
-- ~~⚠ HELD FOR OWNER — DRAFTED + STATIC-VALIDATED, NOT APPLIED TO ANY DATABASE.~~  (historical)
-- ⚠ Apply only after migrations 0026-0029 have completed their separate review
--   and promotion path. Never apply this file out of numerical order.
--
-- `partition_key` is the TEXT Knowledge/horizon routing boundary. The existing
-- value `primary` remains intact. Matter and CourtCase are UUID case-management
-- entities; they do not replace or reinterpret the legacy UUID
-- analysis.evidence_item.case_id column.

BEGIN;

CREATE TABLE analysis.matter (
    id          UUID PRIMARY KEY DEFAULT uuidv7(),
    title       TEXT NOT NULL CHECK (length(btrim(title)) > 0),
    description TEXT,
    status      TEXT NOT NULL DEFAULT 'active'
                CHECK (status IN ('active', 'closed', 'archived')),
    created_by  TEXT NOT NULL CHECK (length(btrim(created_by)) > 0),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE analysis.matter IS
  'Enduring operator-authored case-management workspace. A matter may own one '
  'or more court proceedings; it is not a Knowledge partition or tenant.';

CREATE TABLE analysis.court_case (
    id             UUID PRIMARY KEY DEFAULT uuidv7(),
    matter_id      UUID NOT NULL,
    caption        TEXT NOT NULL CHECK (length(btrim(caption)) > 0),
    docket_number  TEXT,
    court_name     TEXT,
    jurisdiction   TEXT,
    case_type      TEXT,
    status         TEXT NOT NULL DEFAULT 'pre_filing'
                   CHECK (status IN (
                       'pre_filing', 'active', 'stayed', 'closed', 'appealed',
                       'archived'
                   )),
    filed_on       DATE,
    closed_on      DATE,
    is_primary     BOOLEAN NOT NULL DEFAULT false,
    created_by     TEXT NOT NULL CHECK (length(btrim(created_by)) > 0),
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT court_case_matter_fkey
        FOREIGN KEY (matter_id) REFERENCES analysis.matter(id) ON DELETE RESTRICT,
    CONSTRAINT court_case_dates_ck
        CHECK (closed_on IS NULL OR filed_on IS NULL OR closed_on >= filed_on),
    CONSTRAINT court_case_id_matter_key UNIQUE (id, matter_id)
);

COMMENT ON TABLE analysis.court_case IS
  'One court proceeding within an enduring matter. Docket metadata is nullable '
  'so a pre-filing proceeding can exist without inventing a case number.';

CREATE INDEX court_case_matter_status_idx
    ON analysis.court_case (matter_id, status);
CREATE UNIQUE INDEX court_case_one_primary_per_matter_idx
    ON analysis.court_case (matter_id) WHERE is_primary;
CREATE UNIQUE INDEX court_case_docket_per_matter_idx
    ON analysis.court_case (matter_id, lower(docket_number))
    WHERE docket_number IS NOT NULL;

CREATE TABLE analysis.matter_knowledge_partition (
    partition_key         TEXT PRIMARY KEY
                          CHECK (length(btrim(partition_key)) > 0),
    matter_id             UUID NOT NULL,
    default_court_case_id UUID NOT NULL,
    created_by            TEXT NOT NULL CHECK (length(btrim(created_by)) > 0),
    created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT matter_knowledge_partition_matter_fkey
        FOREIGN KEY (matter_id) REFERENCES analysis.matter(id) ON DELETE RESTRICT,
    CONSTRAINT matter_knowledge_partition_default_case_fkey
        FOREIGN KEY (default_court_case_id, matter_id)
        REFERENCES analysis.court_case(id, matter_id) ON DELETE RESTRICT,
    CONSTRAINT matter_knowledge_partition_scope_key
        UNIQUE (partition_key, matter_id)
);

COMMENT ON TABLE analysis.matter_knowledge_partition IS
  'Compatibility boundary from the TEXT Knowledge/horizon partition key to an '
  'enduring Matter and its default CourtCase. It is not a tenant mapping.';

CREATE INDEX matter_knowledge_partition_matter_idx
    ON analysis.matter_knowledge_partition (matter_id);
CREATE INDEX matter_knowledge_partition_default_case_idx
    ON analysis.matter_knowledge_partition (default_court_case_id);

-- Idempotent neutral bootstrap. It intentionally does not infer identity from
-- legacy analysis.*.case_id UUID values: those columns keep their old meaning.
WITH inserted_matter AS (
    INSERT INTO analysis.matter (title, description, status, created_by)
    SELECT
        'Primary matter',
        'Neutral bootstrap matter for the existing primary Knowledge partition.',
        'active',
        'migration-0030'
    WHERE NOT EXISTS (
        SELECT 1
          FROM analysis.matter_knowledge_partition
         WHERE partition_key = 'primary'
    )
    RETURNING id
), inserted_case AS (
    INSERT INTO analysis.court_case (
        matter_id, caption, status, is_primary, created_by
    )
    SELECT id, 'Primary proceeding', 'pre_filing', true, 'migration-0030'
      FROM inserted_matter
    RETURNING id, matter_id
)
INSERT INTO analysis.matter_knowledge_partition (
    partition_key, matter_id, default_court_case_id, created_by
)
SELECT 'primary', matter_id, id, 'migration-0030'
  FROM inserted_case
ON CONFLICT (partition_key) DO NOTHING;

-- These nullable columns are the new explicit case-management scope. Existing
-- rows remain valid and the legacy evidence_item.case_id UUID is untouched.
ALTER TABLE analysis.evidence_item
    ADD COLUMN matter_id UUID,
    ADD COLUMN court_case_id UUID,
    ADD CONSTRAINT evidence_item_matter_fkey
        FOREIGN KEY (matter_id) REFERENCES analysis.matter(id) ON DELETE RESTRICT,
    ADD CONSTRAINT evidence_item_court_case_matter_fkey
        FOREIGN KEY (court_case_id, matter_id)
        REFERENCES analysis.court_case(id, matter_id) ON DELETE RESTRICT,
    ADD CONSTRAINT evidence_item_case_management_scope_ck
        CHECK ((matter_id IS NULL) = (court_case_id IS NULL)),
    ADD CONSTRAINT evidence_item_case_management_scope_key
        UNIQUE (id, matter_id, court_case_id);

COMMENT ON COLUMN analysis.evidence_item.matter_id IS
  'Explicit case-management Matter scope. Nullable for legacy rows; promotion '
  'writes both matter_id and court_case_id.';
COMMENT ON COLUMN analysis.evidence_item.court_case_id IS
  'Explicit CourtCase scope. Nullable for legacy rows. This does not replace '
  'the historical evidence_item.case_id UUID column.';

CREATE INDEX evidence_item_matter_case_review_idx
    ON analysis.evidence_item (matter_id, court_case_id, review_status)
    WHERE matter_id IS NOT NULL;

CREATE TABLE analysis.knowledge_evidence_promotion (
    id                  UUID PRIMARY KEY DEFAULT uuidv7(),
    idempotency_key     TEXT NOT NULL
                        CHECK (length(btrim(idempotency_key)) BETWEEN 1 AND 200),
    partition_key       TEXT NOT NULL,
    matter_id           UUID NOT NULL,
    court_case_id       UUID NOT NULL,
    evidence_item_id    UUID NOT NULL,
    normalized_record_id UUID NOT NULL,
    evidence_hash_id    UUID NOT NULL,
    source_id           UUID,
    file_node_id        UUID,
    source_run_id       UUID,
    knowledge_lane      TEXT NOT NULL CHECK (knowledge_lane = 'evidence'),
    retrieval_item_ref  TEXT NOT NULL
                        CHECK (length(btrim(retrieval_item_ref)) > 0),
    content_ref         TEXT,
    chunk_ref           TEXT,
    source_pointer      JSONB NOT NULL
                        CHECK (jsonb_typeof(source_pointer) = 'object'),
    source_pointer_hash BYTEA NOT NULL
                        CHECK (octet_length(source_pointer_hash) = 32),
    promoted_by         TEXT NOT NULL CHECK (length(btrim(promoted_by)) > 0),
    promoted_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT knowledge_evidence_promotion_request_key
        UNIQUE (matter_id, idempotency_key),
    CONSTRAINT knowledge_evidence_promotion_pointer_key
        UNIQUE (court_case_id, source_pointer_hash),
    CONSTRAINT knowledge_evidence_promotion_item_key UNIQUE (evidence_item_id),
    CONSTRAINT knowledge_evidence_promotion_partition_fkey
        FOREIGN KEY (partition_key, matter_id)
        REFERENCES analysis.matter_knowledge_partition(partition_key, matter_id)
        ON DELETE RESTRICT,
    CONSTRAINT knowledge_evidence_promotion_case_fkey
        FOREIGN KEY (court_case_id, matter_id)
        REFERENCES analysis.court_case(id, matter_id) ON DELETE RESTRICT,
    CONSTRAINT knowledge_evidence_promotion_item_scope_fkey
        FOREIGN KEY (evidence_item_id, matter_id, court_case_id)
        REFERENCES analysis.evidence_item(id, matter_id, court_case_id)
        ON DELETE RESTRICT,
    CONSTRAINT knowledge_evidence_promotion_record_fkey
        FOREIGN KEY (normalized_record_id)
        REFERENCES working.normalized_record(id) ON DELETE RESTRICT,
    CONSTRAINT knowledge_evidence_promotion_hash_fkey
        FOREIGN KEY (evidence_hash_id)
        REFERENCES evidence.evidence_hash(id) ON DELETE RESTRICT,
    CONSTRAINT knowledge_evidence_promotion_source_fkey
        FOREIGN KEY (source_id) REFERENCES evidence.source(id) ON DELETE RESTRICT,
    CONSTRAINT knowledge_evidence_promotion_file_node_fkey
        FOREIGN KEY (file_node_id) REFERENCES evidence.file_node(id) ON DELETE RESTRICT,
    CONSTRAINT knowledge_evidence_promotion_run_fkey
        FOREIGN KEY (source_run_id) REFERENCES ops.processing_run(run_id) ON DELETE RESTRICT
);

COMMENT ON TABLE analysis.knowledge_evidence_promotion IS
  'Append-only, idempotent ledger for promoting a canonical Knowledge result '
  'into a default-unsafe evidence_item. Retrieval IDs are supporting metadata; '
  'normalized record, custody hash, source/file, and run references are the '
  'authoritative provenance.';

CREATE INDEX knowledge_evidence_promotion_matter_time_idx
    ON analysis.knowledge_evidence_promotion (matter_id, promoted_at DESC);
CREATE INDEX knowledge_evidence_promotion_case_time_idx
    ON analysis.knowledge_evidence_promotion (court_case_id, promoted_at DESC);
CREATE INDEX knowledge_evidence_promotion_record_idx
    ON analysis.knowledge_evidence_promotion (normalized_record_id);

CREATE OR REPLACE FUNCTION analysis.knowledge_evidence_pointer_hash(pointer JSONB)
RETURNS BYTEA
LANGUAGE sql
IMMUTABLE
STRICT
AS $$
    SELECT public.digest(
        convert_to(
            jsonb_build_object(
                'matter_id', pointer -> 'matter_id',
                'court_case_id', pointer -> 'court_case_id',
                'partition_key', pointer -> 'partition_key',
                'lane', pointer -> 'lane',
                'normalized_record_id', pointer -> 'normalized_record_id',
                'evidence_hash_id', pointer -> 'evidence_hash_id',
                'source_id', pointer -> 'source_id',
                'sha256', pointer -> 'sha256',
                'conversation_id', pointer -> 'conversation_id',
                'quote', pointer -> 'quote'
            )::text,
            'UTF8'
        ),
        'sha256'
    )
$$;

CREATE OR REPLACE FUNCTION analysis.guard_knowledge_evidence_promotion()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    item        analysis.evidence_item%ROWTYPE;
    record_row  working.normalized_record%ROWTYPE;
    hash_source UUID;
    hash_file   UUID;
    hash_algo   TEXT;
    hash_canon  TEXT;
    hash_digest BYTEA;
BEGIN
    IF NEW.knowledge_lane <> 'evidence' THEN
        RAISE EXCEPTION 'only the evidence Knowledge lane may be promoted';
    END IF;

    IF NEW.source_pointer_hash IS DISTINCT FROM
       analysis.knowledge_evidence_pointer_hash(NEW.source_pointer) THEN
        RAISE EXCEPTION 'source pointer hash does not match canonical source pointer';
    END IF;

    IF NEW.source_pointer ->> 'matter_id' IS DISTINCT FROM NEW.matter_id::text
       OR NEW.source_pointer ->> 'court_case_id' IS DISTINCT FROM NEW.court_case_id::text
       OR NEW.source_pointer ->> 'partition_key' IS DISTINCT FROM NEW.partition_key
       OR NEW.source_pointer ->> 'lane' IS DISTINCT FROM NEW.knowledge_lane
       OR NEW.source_pointer ->> 'normalized_record_id' IS DISTINCT FROM NEW.normalized_record_id::text
       OR NEW.source_pointer ->> 'evidence_hash_id' IS DISTINCT FROM NEW.evidence_hash_id::text
       OR NEW.source_pointer ->> 'source_id' IS DISTINCT FROM NEW.source_id::text THEN
        RAISE EXCEPTION 'source pointer fields do not match promotion ledger';
    END IF;

    SELECT * INTO item
      FROM analysis.evidence_item
     WHERE id = NEW.evidence_item_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'evidence_item % does not exist', NEW.evidence_item_id;
    END IF;

    IF item.review_status <> 'unreviewed'::ai.review_state
       OR item.hitl_required IS NOT true
       OR item.safe_for_legal_use IS NOT false
       OR item.is_authenticated IS NOT false THEN
        RAISE EXCEPTION
          'promoted evidence must start unreviewed, HITL-required, unsafe, and unauthenticated';
    END IF;

    IF item.matter_id IS DISTINCT FROM NEW.matter_id
       OR item.court_case_id IS DISTINCT FROM NEW.court_case_id
       OR item.normalized_record_id IS DISTINCT FROM NEW.normalized_record_id
       OR item.evidence_hash_id IS DISTINCT FROM NEW.evidence_hash_id
       OR item.source_id IS DISTINCT FROM NEW.source_id
       OR item.file_node_id IS DISTINCT FROM NEW.file_node_id
       OR item.source_run_id IS DISTINCT FROM NEW.source_run_id THEN
        RAISE EXCEPTION 'evidence_item scope or provenance does not match promotion ledger';
    END IF;

    SELECT * INTO record_row
      FROM working.normalized_record
     WHERE id = NEW.normalized_record_id;
    IF NOT FOUND
       OR record_row.case_id IS DISTINCT FROM NEW.partition_key
       OR record_row.artifact_id IS DISTINCT FROM NEW.evidence_hash_id
       OR record_row.provenance_id IS DISTINCT FROM NEW.source_run_id THEN
        RAISE EXCEPTION
          'normalized record partition, custody hash, or source run does not match promotion';
    END IF;

    SELECT source_id, file_node_id, algo, canon_version, digest
      INTO hash_source, hash_file, hash_algo, hash_canon, hash_digest
      FROM evidence.evidence_hash
      WHERE id = NEW.evidence_hash_id;
    IF NOT FOUND
       OR hash_source IS DISTINCT FROM NEW.source_id
       OR hash_file IS DISTINCT FROM NEW.file_node_id
       OR hash_algo <> 'sha256'
       OR hash_canon <> 'h1-rawbytes-v1'
       OR octet_length(hash_digest) <> 32
       OR encode(hash_digest, 'hex') IS DISTINCT FROM NEW.source_pointer ->> 'sha256' THEN
        RAISE EXCEPTION 'custody hash source/file provenance does not match promotion';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER knowledge_evidence_promotion_guard
    BEFORE INSERT ON analysis.knowledge_evidence_promotion
    FOR EACH ROW EXECUTE FUNCTION analysis.guard_knowledge_evidence_promotion();

CREATE TRIGGER knowledge_evidence_promotion_append_only
    BEFORE UPDATE OR DELETE ON analysis.knowledge_evidence_promotion
    FOR EACH ROW EXECUTE FUNCTION working.forbid_mutation();

CREATE OR REPLACE FUNCTION analysis.set_case_management_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$;

CREATE TRIGGER matter_set_updated_at
    BEFORE UPDATE ON analysis.matter
    FOR EACH ROW EXECUTE FUNCTION analysis.set_case_management_updated_at();
CREATE TRIGGER court_case_set_updated_at
    BEFORE UPDATE ON analysis.court_case
    FOR EACH ROW EXECUTE FUNCTION analysis.set_case_management_updated_at();

COMMIT;
