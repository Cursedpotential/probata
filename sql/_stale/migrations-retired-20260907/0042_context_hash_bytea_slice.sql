-- Migration 0042: repair the guard_hash_receipt_insert inline byte-range slice.
--
-- The 0036 definition digests inline raw-record byte ranges with
-- substring(bytea FROM bigint FOR bigint), which fails at runtime when the
-- guard executes on live H1 receipt inserts. This migration redefines the
-- function forward-only with CREATE OR REPLACE, preserving every other 0036
-- behavior byte-for-byte, and changes only the inline arm to cast the
-- substring bounds to int4 with explicit non-negative and end-exclusive
-- range guards against both locator_object.byte_length and
-- octet_length(locator_object.inline_bytes).
--
-- Byline: Claude Code · glm-5.3:cloud · 2026-08-28

BEGIN;

DO $$
BEGIN
    IF current_database() <> 'platform' THEN
        RAISE EXCEPTION 'migration 0042 may run only in database platform, not %', current_database();
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_roles
        WHERE rolname = 'context_owner' AND NOT rolcanlogin
    ) THEN
        RAISE EXCEPTION 'migration 0042 requires NOLOGIN role context_owner';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_roles
        WHERE rolname = 'context_import_writer'
          AND NOT rolcanlogin
          AND NOT (rolsuper OR rolcreatedb OR rolcreaterole OR rolreplication OR rolbypassrls)
    ) THEN
        RAISE EXCEPTION 'migration 0042 requires safe NOLOGIN role context_import_writer';
    END IF;
    IF NOT pg_has_role('platform_runtime', 'context_import_writer', 'MEMBER') THEN
        RAISE EXCEPTION 'migration 0042 requires platform_runtime membership in context_import_writer';
    END IF;
    IF to_regprocedure('context.guard_hash_receipt_insert()') IS NULL THEN
        RAISE EXCEPTION 'migration 0042 requires context.guard_hash_receipt_insert()';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_trigger trigger
        WHERE trigger.tgrelid = 'context.hash_receipt'::regclass
          AND trigger.tgname = 'hash_receipt_insert_gate'
          AND NOT trigger.tgisinternal
          AND trigger.tgenabled <> 'D'
    ) THEN
        RAISE EXCEPTION 'migration 0042 requires the enabled hash_receipt_insert_gate trigger';
    END IF;
END;
$$;

SET LOCAL ROLE context_owner;

CREATE OR REPLACE FUNCTION context.guard_hash_receipt_insert()
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
                  AND raw.byte_offset >= 0
                  AND raw.byte_offset <= 2147483646
                  AND raw.byte_length >= 0
                  AND raw.byte_length <= 2147483647
                  AND raw.byte_offset + raw.byte_length <= locator_object.byte_length
                  AND raw.byte_offset + raw.byte_length <= octet_length(locator_object.inline_bytes)
                  AND digest(
                      substring(locator_object.inline_bytes
                                FROM (raw.byte_offset + 1)::int4
                                FOR raw.byte_length::int4),
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

COMMIT;
