-- Migration 0048: repair R02 context-fingerprint vocabulary against the real
-- 0036 context schema. Migration 0045 is immutable; this is the fix-forward.
-- Context intake integrity is not evidence custody. H1/H2/H3 remain reserved
-- for the later owner-promotion boundary.
-- Byline: Codex · GPT-5 · 2026-08-29.

BEGIN;

DO $prerequisites$
DECLARE
    v_role TEXT;
    v_relation TEXT;
    v_function TEXT;
BEGIN
    IF current_database() <> 'platform' THEN
        RAISE EXCEPTION 'migration 0048 may run only in database platform, not %', current_database();
    END IF;
    FOREACH v_role IN ARRAY ARRAY[
        'platform_admin', 'platform_runtime', 'context_owner',
        'context_import_writer', 'context_reader'
    ] LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = v_role) THEN
            RAISE EXCEPTION 'migration 0048 requires bootstrap role %', v_role;
        END IF;
    END LOOP;
    IF NOT pg_has_role('platform_admin', 'context_owner', 'MEMBER')
       OR NOT pg_has_role('platform_runtime', 'context_import_writer', 'MEMBER') THEN
        RAISE EXCEPTION 'migration 0048 requires the 0036 role membership topology';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_roles
               WHERE rolname IN ('platform_admin', 'platform_runtime', 'context_owner',
                                  'context_import_writer', 'context_reader')
                 AND (rolsuper OR rolcreatedb OR rolcreaterole OR rolreplication OR rolbypassrls)) THEN
        RAISE EXCEPTION 'migration 0048 refuses elevated platform/context roles';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_roles
               WHERE rolname IN ('platform_admin', 'context_owner',
                                  'context_import_writer', 'context_reader')
                 AND rolcanlogin)
       OR NOT EXISTS (SELECT 1 FROM pg_roles
                      WHERE rolname = 'platform_runtime' AND rolcanlogin) THEN
        RAISE EXCEPTION 'migration 0048 requires NOLOGIN grant roles and LOGIN platform_runtime';
    END IF;
    FOREACH v_relation IN ARRAY ARRAY[
        'context.retained_object', 'context.source_version', 'context.raw_generation',
        'context.raw_record_identity', 'context.activity_execution', 'context.activity_receipt',
        'context.hash_batch', 'context.hash_batch_member', 'context.hash_manifest',
        'context.hash_manifest_member', 'context.hash_receipt', 'context.reconciliation_receipt'
    ] LOOP
        IF to_regclass(v_relation) IS NULL THEN
            RAISE EXCEPTION 'migration 0048 requires relation % from migration 0036', v_relation;
        END IF;
    END LOOP;
    FOREACH v_function IN ARRAY ARRAY[
        'context.guard_hash_batch_insert()', 'context.guard_hash_batch_member_insert()',
        'context.assert_hash_manifest_complete(uuid)', 'context.guard_hash_manifest_member_insert()',
        'context.guard_hash_receipt_insert()', 'context.seal_hash_manifest_from_receipt()',
        'context.guard_raw_generation_transition()'
    ] LOOP
        IF to_regprocedure(v_function) IS NULL THEN
            RAISE EXCEPTION 'migration 0048 requires function % from migration 0036', v_function;
        END IF;
    END LOOP;
END
$prerequisites$;

SET LOCAL ROLE context_owner;
SET LOCAL search_path = pg_catalog, context;

-- The original 0036 append-only trigger correctly prevents application
-- mutation. This narrowly bounded migration relabels only the three legacy R02
-- intake kinds, then restores the same trigger before adding new constraints.
-- Drop the anonymous inline 0036 checks by meaning rather than guessed names;
-- otherwise PostgreSQL would reject the relabel before the new checks exist.
DO $migration$
DECLARE c record;
BEGIN
    FOR c IN
        SELECT conrelid::regclass AS relation_name, conname
        FROM pg_constraint
        WHERE contype = 'c'
          AND conrelid IN (
              'context.hash_batch'::regclass,
              'context.hash_manifest'::regclass,
              'context.hash_receipt'::regclass,
              'context.reconciliation_receipt'::regclass,
              'context.raw_record_identity'::regclass)
          AND (
              pg_get_constraintdef(oid) LIKE '%hash_kind%'
              OR pg_get_constraintdef(oid) LIKE '%h3_raw_generation%'
              OR pg_get_constraintdef(oid) LIKE '%raw_hash_construction%'
          )
    LOOP
        EXECUTE format('ALTER TABLE %s DROP CONSTRAINT %I', c.relation_name, c.conname);
    END LOOP;
END
$migration$;

ALTER TABLE context.raw_record_identity DISABLE TRIGGER raw_record_identity_append_only;
UPDATE context.raw_record_identity
SET raw_hash_construction = CASE
    WHEN raw_hash_construction = 'h2-rawspan-v1' THEN 'context-rawspan-fingerprint-v1'
    ELSE 'context-rawrecord-fingerprint-v1'
END;
ALTER TABLE context.raw_record_identity ENABLE TRIGGER raw_record_identity_append_only;

ALTER TABLE context.raw_record_identity
    ADD CONSTRAINT raw_record_context_fingerprint_canon_check CHECK (
        raw_hash_construction IN (
            'context-rawrecord-fingerprint-v1', 'context-rawspan-fingerprint-v1')),
    ADD CONSTRAINT raw_record_context_span_canon_check CHECK (
        record_status NOT IN ('envelope', 'unparsed')
        OR raw_hash_construction = 'context-rawspan-fingerprint-v1');

ALTER TABLE context.hash_receipt DISABLE TRIGGER hash_receipt_append_only;

UPDATE context.hash_receipt
SET hash_kind = CASE hash_kind
        WHEN 'h1_source' THEN 'context_source_fingerprint'
        WHEN 'raw_record_digest' THEN 'context_raw_record_fingerprint'
        WHEN 'h3_raw_generation' THEN 'context_raw_generation_fingerprint'
    END,
    construction = CASE hash_kind
        WHEN 'h1_source' THEN 'context-source-fingerprint-v1'
        WHEN 'raw_record_digest' THEN CASE
            WHEN construction = 'h2-rawspan-v1' THEN 'context-rawspan-fingerprint-v1'
            ELSE 'context-rawrecord-fingerprint-v1'
        END
        WHEN 'h3_raw_generation' THEN 'context-rawgen-fingerprint-chain-v1'
    END
WHERE hash_kind IN ('h1_source', 'raw_record_digest', 'h3_raw_generation');

ALTER TABLE context.hash_receipt ENABLE TRIGGER hash_receipt_append_only;

ALTER TABLE context.hash_batch DISABLE TRIGGER hash_batch_transition_gate;
UPDATE context.hash_batch
SET hash_kind = CASE hash_kind
        WHEN 'h1_source' THEN 'context_source_fingerprint'
        WHEN 'raw_record_digest' THEN 'context_raw_record_fingerprint'
        WHEN 'h3_raw_generation' THEN 'context_raw_generation_fingerprint'
    END
WHERE hash_kind IN ('h1_source', 'raw_record_digest', 'h3_raw_generation');
ALTER TABLE context.hash_batch ENABLE TRIGGER hash_batch_transition_gate;

ALTER TABLE context.hash_manifest DISABLE TRIGGER hash_manifest_seal_gate;
UPDATE context.hash_manifest
SET hash_kind = 'context_raw_generation_fingerprint'
WHERE hash_kind = 'h3_raw_generation';
ALTER TABLE context.hash_manifest ENABLE TRIGGER hash_manifest_seal_gate;

ALTER TABLE context.hash_batch
    ADD CONSTRAINT hash_batch_context_kind_check CHECK (hash_kind IN (
        'context_source_fingerprint', 'context_raw_record_fingerprint',
        'context_raw_generation_fingerprint', 'normalized_record_digest',
        'normalized_generation_manifest_digest')),
    ADD CONSTRAINT hash_batch_context_subject_check CHECK (
        (hash_kind = 'context_source_fingerprint' AND raw_generation_id IS NULL AND normalized_generation_id IS NULL)
        OR (hash_kind IN ('context_raw_record_fingerprint', 'context_raw_generation_fingerprint')
            AND raw_generation_id IS NOT NULL AND normalized_generation_id IS NULL)
        OR (hash_kind IN ('normalized_record_digest', 'normalized_generation_manifest_digest')
            AND raw_generation_id IS NULL AND normalized_generation_id IS NOT NULL));

ALTER TABLE context.hash_manifest
    ADD CONSTRAINT hash_manifest_context_kind_check CHECK (hash_kind IN (
        'context_raw_generation_fingerprint', 'normalized_generation_manifest_digest')),
    ADD CONSTRAINT hash_manifest_context_subject_check CHECK (
        (hash_kind = 'context_raw_generation_fingerprint' AND raw_generation_id IS NOT NULL
            AND normalized_generation_id IS NULL)
        OR (hash_kind = 'normalized_generation_manifest_digest'
            AND raw_generation_id IS NULL AND normalized_generation_id IS NOT NULL));

ALTER TABLE context.hash_receipt
    ADD CONSTRAINT hash_receipt_context_kind_check CHECK (hash_kind IN (
        'context_source_fingerprint', 'context_raw_record_fingerprint',
        'context_raw_generation_fingerprint', 'normalized_record_digest',
        'normalized_generation_manifest_digest')),
    ADD CONSTRAINT hash_receipt_context_subject_check CHECK (
        (hash_kind = 'context_source_fingerprint' AND source_version_id IS NOT NULL
            AND raw_record_id IS NULL AND raw_generation_id IS NULL
            AND normalized_record_id IS NULL AND normalized_generation_id IS NULL
            AND hash_manifest_id IS NULL)
        OR (hash_kind = 'context_raw_record_fingerprint' AND source_version_id IS NULL
            AND raw_record_id IS NOT NULL AND raw_generation_id IS NULL
            AND normalized_record_id IS NULL AND normalized_generation_id IS NULL
            AND hash_manifest_id IS NULL)
        OR (hash_kind = 'context_raw_generation_fingerprint' AND source_version_id IS NULL
            AND raw_record_id IS NULL AND raw_generation_id IS NOT NULL
            AND normalized_record_id IS NULL AND normalized_generation_id IS NULL
            AND hash_manifest_id IS NOT NULL)
        OR (hash_kind = 'normalized_record_digest' AND source_version_id IS NULL
            AND raw_record_id IS NULL AND raw_generation_id IS NULL
            AND normalized_record_id IS NOT NULL AND normalized_generation_id IS NULL
            AND hash_manifest_id IS NULL)
        OR (hash_kind = 'normalized_generation_manifest_digest' AND source_version_id IS NULL
            AND raw_record_id IS NULL AND raw_generation_id IS NULL
            AND normalized_record_id IS NULL AND normalized_generation_id IS NOT NULL
            AND hash_manifest_id IS NOT NULL)),
    ADD CONSTRAINT hash_receipt_context_canon_check CHECK (
        (hash_kind = 'context_source_fingerprint' AND construction = 'context-source-fingerprint-v1')
        OR (hash_kind = 'context_raw_record_fingerprint' AND construction IN (
            'context-rawrecord-fingerprint-v1', 'context-rawspan-fingerprint-v1'))
        OR (hash_kind = 'context_raw_generation_fingerprint'
            AND construction = 'context-rawgen-fingerprint-chain-v1')
        OR (hash_kind = 'normalized_record_digest'
            AND construction = 'normalized-record-postgresql18-jsonb-text-utf8-sha256-v1')
        OR (hash_kind = 'normalized_generation_manifest_digest'
            AND construction = 'normalized-generation-ordered-digests-lengthframed-sha256-v1'));

ALTER TABLE context.reconciliation_receipt
    ADD CONSTRAINT reconciliation_context_raw_source_check CHECK (
        reconciliation_kind <> 'raw_source_verification' OR (
            expected ? 'context_raw_generation_fingerprint'
            AND expected ? 'context_source_fingerprint'
            AND observed ? 'context_raw_generation_fingerprint'
            AND observed ? 'context_source_fingerprint'
            AND expected->>'verification_mode' = 'retained_bytes_recomputation'
            AND observed->>'verification_mode' = 'retained_bytes_recomputation'
            AND (status <> 'success' OR expected->'context_raw_generation_fingerprint'
                = observed->'context_raw_generation_fingerprint')
            AND (status <> 'success' OR expected->'context_source_fingerprint'
                = observed->'context_source_fingerprint')));

DROP INDEX IF EXISTS context.hash_receipt_h1_source_uq;
DROP INDEX IF EXISTS context.hash_receipt_h2_raw_record_uq;
DROP INDEX IF EXISTS context.hash_receipt_h3_raw_generation_uq;
DROP INDEX IF EXISTS context.hash_receipt_raw_generation_idx;
CREATE UNIQUE INDEX hash_receipt_context_source_fingerprint_uq
    ON context.hash_receipt (source_version_id)
    WHERE hash_kind = 'context_source_fingerprint';
CREATE UNIQUE INDEX hash_receipt_context_raw_record_fingerprint_uq
    ON context.hash_receipt (raw_record_id)
    WHERE hash_kind = 'context_raw_record_fingerprint';
CREATE UNIQUE INDEX hash_receipt_context_raw_generation_fingerprint_uq
    ON context.hash_receipt (raw_generation_id)
    WHERE hash_kind = 'context_raw_generation_fingerprint';

ALTER TABLE context.raw_generation
    ADD COLUMN IF NOT EXISTS context_source_fingerprint_ref UUID,
    ADD COLUMN IF NOT EXISTS context_raw_fingerprint_manifest_ref UUID,
    ADD COLUMN IF NOT EXISTS context_raw_generation_fingerprint_ref UUID,
    ADD COLUMN IF NOT EXISTS context_raw_source_verification_ref UUID;

-- The triggers already point at these function identities. Replacing their
-- bodies repairs the real 0036 enforcement surface without trigger churn.
CREATE OR REPLACE FUNCTION context.guard_hash_batch_insert()
RETURNS TRIGGER LANGUAGE plpgsql
SET search_path = pg_catalog, context AS $$
BEGIN
    PERFORM context.assert_source_version_retained(NEW.source_version_id);
    IF NEW.hash_kind IN ('context_raw_record_fingerprint', 'context_raw_generation_fingerprint') THEN
        PERFORM context.assert_raw_generation_open(NEW.raw_generation_id);
    ELSIF NEW.hash_kind IN ('normalized_record_digest', 'normalized_generation_manifest_digest') THEN
        PERFORM context.assert_normalized_generation_open(NEW.normalized_generation_id);
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION context.guard_hash_batch_member_insert()
RETURNS TRIGGER LANGUAGE plpgsql
SET search_path = pg_catalog, context AS $$
DECLARE v_batch context.hash_batch%ROWTYPE;
BEGIN
    SELECT * INTO v_batch FROM context.hash_batch
    WHERE id = NEW.hash_batch_id AND status = 'open' FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'hash batch % is not open', NEW.hash_batch_id; END IF;
    IF v_batch.hash_kind = 'context_source_fingerprint' THEN
        IF NEW.source_version_id IS DISTINCT FROM v_batch.source_version_id
           OR NEW.raw_record_id IS NOT NULL OR NEW.normalized_record_id IS NOT NULL THEN
            RAISE EXCEPTION 'context source fingerprint member has the wrong subject';
        END IF;
    ELSIF v_batch.hash_kind IN ('context_raw_record_fingerprint', 'context_raw_generation_fingerprint') THEN
        IF NEW.raw_record_id IS NULL OR NEW.source_version_id IS NOT NULL OR NEW.normalized_record_id IS NOT NULL
           OR NOT EXISTS (SELECT 1 FROM context.raw_record_identity r
                          WHERE r.id = NEW.raw_record_id AND r.raw_generation_id = v_batch.raw_generation_id
                            AND r.record_ordinal = NEW.ordinal) THEN
            RAISE EXCEPTION 'context raw fingerprint member is outside its ordered generation';
        END IF;
    ELSE
        IF NEW.normalized_record_id IS NULL OR NEW.source_version_id IS NOT NULL OR NEW.raw_record_id IS NOT NULL
           OR NOT EXISTS (SELECT 1 FROM context.normalized_record_identity n
                          WHERE n.id = NEW.normalized_record_id
                            AND n.normalized_generation_id = v_batch.normalized_generation_id
                            AND n.record_ordinal = NEW.ordinal) THEN
            RAISE EXCEPTION 'normalized digest member is outside its ordered generation';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION context.assert_hash_manifest_complete(p_hash_manifest_id UUID)
RETURNS VOID LANGUAGE plpgsql
SET search_path = pg_catalog, context AS $$
DECLARE v_manifest context.hash_manifest%ROWTYPE;
BEGIN
    SELECT * INTO v_manifest FROM context.hash_manifest WHERE id = p_hash_manifest_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'hash manifest % does not exist', p_hash_manifest_id; END IF;
    IF v_manifest.hash_kind = 'context_raw_generation_fingerprint' THEN
        IF EXISTS (SELECT 1 FROM context.raw_record_identity raw
                   WHERE raw.raw_generation_id = v_manifest.raw_generation_id
                     AND NOT EXISTS (SELECT 1 FROM context.hash_manifest_member m
                                     WHERE m.hash_manifest_id = v_manifest.id
                                       AND m.raw_record_id = raw.id AND m.ordinal = raw.record_ordinal))
           OR EXISTS (SELECT 1 FROM context.hash_manifest_member m
                      LEFT JOIN context.raw_record_identity raw ON raw.id = m.raw_record_id
                      WHERE m.hash_manifest_id = v_manifest.id
                        AND (m.normalized_record_id IS NOT NULL
                             OR raw.raw_generation_id IS DISTINCT FROM v_manifest.raw_generation_id
                             OR m.ordinal IS DISTINCT FROM raw.record_ordinal)) THEN
            RAISE EXCEPTION 'context raw fingerprint manifest % is incomplete', p_hash_manifest_id;
        END IF;
    ELSE
        IF EXISTS (SELECT 1 FROM context.normalized_record_identity n
                   WHERE n.normalized_generation_id = v_manifest.normalized_generation_id
                     AND NOT EXISTS (SELECT 1 FROM context.hash_manifest_member m
                                     WHERE m.hash_manifest_id = v_manifest.id
                                       AND m.normalized_record_id = n.id AND m.ordinal = n.record_ordinal)) THEN
            RAISE EXCEPTION 'normalized digest manifest % is incomplete', p_hash_manifest_id;
        END IF;
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION context.guard_hash_manifest_member_insert()
RETURNS TRIGGER LANGUAGE plpgsql
SET search_path = pg_catalog, context AS $$
DECLARE v_manifest context.hash_manifest%ROWTYPE;
BEGIN
    SELECT * INTO v_manifest FROM context.hash_manifest
    WHERE id = NEW.hash_manifest_id AND status = 'open' FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'hash manifest % is not open', NEW.hash_manifest_id; END IF;
    IF v_manifest.hash_kind = 'context_raw_generation_fingerprint' THEN
        IF NEW.raw_record_id IS NULL OR NEW.normalized_record_id IS NOT NULL
           OR NOT EXISTS (SELECT 1 FROM context.raw_record_identity raw
                          JOIN context.hash_receipt h ON h.raw_record_id = raw.id
                            AND h.hash_kind = 'context_raw_record_fingerprint'
                            AND h.digest = NEW.member_digest AND h.construction = NEW.member_canon
                          WHERE raw.id = NEW.raw_record_id
                            AND raw.raw_generation_id = v_manifest.raw_generation_id
                            AND raw.record_ordinal = NEW.ordinal) THEN
            RAISE EXCEPTION 'raw manifest member must match its context fingerprint receipt';
        END IF;
    ELSE
        IF NEW.normalized_record_id IS NULL OR NEW.raw_record_id IS NOT NULL THEN
            RAISE EXCEPTION 'normalized manifest member has the wrong subject';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION context.guard_hash_receipt_insert()
RETURNS TRIGGER LANGUAGE plpgsql
SET search_path = pg_catalog, context AS $$
DECLARE v_source UUID; v_expected_activity TEXT; v_expected_ref_kind TEXT; v_expected_ref_id TEXT;
BEGIN
    IF NEW.hash_kind = 'context_source_fingerprint' THEN
        PERFORM context.assert_source_version_retained(NEW.source_version_id);
        v_source := NEW.source_version_id;
        IF NEW.computed_by NOT IN ('fingerprint_source_activity', 'hash_source_activity') THEN
            RAISE EXCEPTION 'context source fingerprint has unsupported activity %', NEW.computed_by;
        END IF;
        v_expected_activity := NEW.computed_by; v_expected_ref_kind := 'hash_receipt';
        v_expected_ref_id := NEW.id::TEXT;
    ELSIF NEW.hash_kind = 'context_raw_record_fingerprint' THEN
        SELECT source_version_id INTO v_source FROM context.raw_record_identity WHERE id = NEW.raw_record_id;
        PERFORM context.assert_raw_generation_open((SELECT raw_generation_id FROM context.raw_record_identity WHERE id = NEW.raw_record_id));
        IF NEW.computed_by NOT IN ('fingerprint_raw_records_activity', 'hash_raw_records_activity') THEN
            RAISE EXCEPTION 'context raw-record fingerprint has unsupported activity %', NEW.computed_by;
        END IF;
        v_expected_activity := NEW.computed_by;
        v_expected_ref_kind := CASE NEW.computed_by
            WHEN 'hash_raw_records_activity' THEN 'raw_hash_receipt_set'
            ELSE 'context_raw_fingerprint_receipt_set' END;
        SELECT raw_generation_id::TEXT INTO v_expected_ref_id FROM context.raw_record_identity WHERE id = NEW.raw_record_id;
    ELSIF NEW.hash_kind = 'context_raw_generation_fingerprint' THEN
        SELECT source_version_id INTO v_source FROM context.raw_generation WHERE id = NEW.raw_generation_id;
        PERFORM context.assert_raw_generation_open(NEW.raw_generation_id);
        IF NEW.computed_by NOT IN ('fingerprint_raw_generation_activity', 'hash_raw_generation_activity') THEN
            RAISE EXCEPTION 'context raw-generation fingerprint has unsupported activity %', NEW.computed_by;
        END IF;
        v_expected_activity := NEW.computed_by; v_expected_ref_kind := 'hash_receipt';
        v_expected_ref_id := NEW.id::TEXT;
    ELSIF NEW.hash_kind = 'normalized_record_digest' THEN
        SELECT source_version_id INTO v_source FROM context.normalized_record_identity WHERE id = NEW.normalized_record_id;
        PERFORM context.assert_normalized_generation_open((SELECT normalized_generation_id FROM context.normalized_record_identity WHERE id = NEW.normalized_record_id));
        v_expected_activity := 'hash_normalized_records_activity'; v_expected_ref_kind := 'normalized_hash_receipt_set';
        SELECT normalized_generation_id::TEXT INTO v_expected_ref_id FROM context.normalized_record_identity WHERE id = NEW.normalized_record_id;
    ELSE
        SELECT source_version_id INTO v_source FROM context.normalized_generation WHERE id = NEW.normalized_generation_id;
        PERFORM context.assert_normalized_generation_open(NEW.normalized_generation_id);
        v_expected_activity := 'hash_normalized_generation_activity'; v_expected_ref_kind := 'hash_receipt';
        v_expected_ref_id := NEW.id::TEXT;
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM context.activity_receipt receipt
        JOIN context.activity_execution execution ON execution.id = receipt.activity_execution_id
        WHERE receipt.id = NEW.activity_receipt_id AND receipt.status = 'success'
          AND execution.source_version_id = v_source AND execution.activity_name = v_expected_activity
          AND receipt.result_ref->>'ref_kind' = v_expected_ref_kind
          AND receipt.result_ref->>'ref_id' = v_expected_ref_id) THEN
        RAISE EXCEPTION 'hash receipt requires successful same-source % receipt', v_expected_activity;
    END IF;
    IF NEW.hash_kind = 'context_source_fingerprint' AND NOT EXISTS (
        SELECT 1 FROM context.source_version sv JOIN context.retained_object ro ON ro.id = sv.original_object_id
        WHERE sv.id = NEW.source_version_id AND ro.content_sha256 = NEW.digest) THEN
        RAISE EXCEPTION 'context source fingerprint must match retained bytes';
    END IF;
    IF NEW.hash_kind = 'context_raw_record_fingerprint' AND NOT EXISTS (
        SELECT 1 FROM context.raw_record_identity raw LEFT JOIN context.retained_object ro ON ro.id = raw.locator_object_id
        WHERE raw.id = NEW.raw_record_id AND raw.raw_hash_construction = NEW.construction
          AND ((raw.stored_bytes IS NOT NULL AND digest(raw.stored_bytes, 'sha256') = NEW.digest)
            OR (raw.stored_bytes IS NULL AND ro.storage_class = 'inline'
                AND digest(substring(ro.inline_bytes FROM raw.byte_offset + 1 FOR raw.byte_length), 'sha256') = NEW.digest)
            OR (raw.stored_bytes IS NULL AND ro.storage_class <> 'inline'
                AND EXISTS (
                    SELECT 1 FROM context.activity_receipt receipt
                    JOIN context.activity_execution execution
                      ON execution.id = receipt.activity_execution_id
                    WHERE receipt.id = NEW.activity_receipt_id
                      AND receipt.status = 'success'
                      AND execution.activity_name = NEW.computed_by
                      AND execution.source_version_id = raw.source_version_id)))) THEN
        RAISE EXCEPTION 'context raw-record fingerprint does not match retained bytes';
    END IF;
    IF NEW.hash_kind = 'normalized_record_digest' AND NOT EXISTS (
        SELECT 1 FROM context.normalized_record_identity normalized
        WHERE normalized.id = NEW.normalized_record_id
          AND normalized.canonicalization = NEW.construction
          AND digest(normalized.canonical_bytes, 'sha256') = NEW.digest) THEN
        RAISE EXCEPTION 'normalized record digest must hash exact canonical bytes';
    END IF;
    IF NEW.hash_kind IN ('context_raw_generation_fingerprint', 'normalized_generation_manifest_digest') THEN
        IF NOT EXISTS (
            SELECT 1 FROM context.hash_manifest manifest
            WHERE manifest.id = NEW.hash_manifest_id AND manifest.status = 'open'
              AND manifest.hash_kind = NEW.hash_kind
              AND (manifest.raw_generation_id = NEW.raw_generation_id
                   OR manifest.normalized_generation_id = NEW.normalized_generation_id)) THEN
            RAISE EXCEPTION 'generation hash receipt requires its matching open manifest';
        END IF;
        PERFORM context.assert_hash_manifest_complete(NEW.hash_manifest_id);
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION context.seal_hash_manifest_from_receipt()
RETURNS TRIGGER LANGUAGE plpgsql
SET search_path = pg_catalog, context AS $$
BEGIN
    IF NEW.hash_kind IN ('context_raw_generation_fingerprint', 'normalized_generation_manifest_digest') THEN
        UPDATE context.hash_manifest SET status = 'sealed',
            member_count = (SELECT count(*) FROM context.hash_manifest_member WHERE hash_manifest_id = NEW.hash_manifest_id),
            sealed_hash_receipt_id = NEW.id, sealed_at = NEW.computed_at
        WHERE id = NEW.hash_manifest_id;
    END IF;
    RETURN NEW;
END;
$$;

-- Repair the raw-generation seal gate's old custody labels and reconciliation
-- JSON keys while retaining every other 0036 lifecycle check.
DO $migration$
DECLARE definition TEXT;
BEGIN
    SELECT pg_get_functiondef(to_regprocedure('context.guard_raw_generation_transition()')) INTO definition;
    IF definition ~* 'SET[[:space:]]+search_path[[:space:]]*(=|TO)' THEN
        RAISE EXCEPTION
            'migration 0048 refuses to rewrite context.guard_raw_generation_transition(): search_path is already configured';
    END IF;
    IF regexp_count(definition, 'LANGUAGE[[:space:]]+plpgsql', 1, 'i') <> 1 THEN
        RAISE EXCEPTION
            'migration 0048 refuses to rewrite context.guard_raw_generation_transition(): expected exactly one LANGUAGE plpgsql clause';
    END IF;
    definition := replace(definition, '''h1_source''', '''context_source_fingerprint''');
    definition := replace(definition, '''raw_record_digest''', '''context_raw_record_fingerprint''');
    definition := replace(definition, '''h3_raw_generation''', '''context_raw_generation_fingerprint''');
    definition := replace(definition, 'H1/H2/H3 receipts', 'context fingerprint receipts');
    definition := replace(definition, 'LANGUAGE plpgsql',
        'LANGUAGE plpgsql SET search_path = pg_catalog, context');
    EXECUTE definition;
END
$migration$;

COMMENT ON TABLE context.hash_receipt IS
    'R02 context integrity fingerprints plus normalized reproducibility digests. These rows are not custody H1/H2/H3.';

REVOKE ALL ON context.hash_batch, context.hash_batch_member, context.hash_manifest,
    context.hash_manifest_member, context.hash_receipt, context.reconciliation_receipt FROM PUBLIC;
GRANT SELECT, INSERT ON context.hash_batch, context.hash_batch_member, context.hash_manifest,
    context.hash_manifest_member, context.hash_receipt, context.reconciliation_receipt
    TO context_import_writer;
GRANT UPDATE ON context.hash_batch, context.hash_manifest TO context_import_writer;
GRANT SELECT ON context.hash_batch, context.hash_batch_member, context.hash_manifest,
    context.hash_manifest_member, context.hash_receipt, context.reconciliation_receipt
    TO context_reader;
REVOKE EXECUTE ON FUNCTION context.guard_hash_batch_insert(),
    context.guard_hash_batch_member_insert(), context.assert_hash_manifest_complete(UUID),
    context.guard_hash_manifest_member_insert(), context.guard_hash_receipt_insert(),
    context.seal_hash_manifest_from_receipt(), context.guard_raw_generation_transition()
    FROM PUBLIC;
GRANT EXECUTE ON FUNCTION context.assert_hash_manifest_complete(UUID)
    TO context_import_writer;

RESET ROLE;
COMMIT;
