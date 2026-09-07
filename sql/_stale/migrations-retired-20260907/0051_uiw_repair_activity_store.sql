-- Migration 0051: durable UIW source-repair assessment, decision, and resolution store.
-- Reference-only activity results; source bytes remain in retained_object storage.
-- Byline: Codex · GPT-5.6 · 2026-08-29.

BEGIN;

DO $prerequisites$
DECLARE v_role TEXT;
BEGIN
    IF current_database() <> 'platform' THEN
        RAISE EXCEPTION 'migration 0051 may run only in database platform, not %', current_database();
    END IF;
    FOREACH v_role IN ARRAY ARRAY['platform_admin','platform_runtime','context_owner','context_import_writer','context_reader'] LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = v_role) THEN
            RAISE EXCEPTION 'migration 0051 requires role %', v_role;
        END IF;
    END LOOP;
    IF NOT pg_has_role('platform_admin','context_owner','MEMBER')
       OR NOT pg_has_role('platform_runtime','context_import_writer','MEMBER') THEN
        RAISE EXCEPTION 'migration 0051 requires the governed context role topology';
    END IF;
    IF to_regclass('context.source_version') IS NULL
       OR to_regclass('context.retained_object') IS NULL
       OR to_regclass('context.activity_execution') IS NULL
       OR to_regclass('context.activity_receipt') IS NULL THEN
        RAISE EXCEPTION 'migration 0051 requires the context import foundation';
    END IF;
END
$prerequisites$;

SET LOCAL ROLE context_owner;
SET LOCAL search_path = pg_catalog, context;

CREATE TABLE context.repair_assessment (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    source_version_id UUID NOT NULL REFERENCES context.source_version(id) ON DELETE RESTRICT,
    original_object_id UUID NOT NULL REFERENCES context.retained_object(id) ON DELETE RESTRICT,
    activity_receipt_id UUID NOT NULL UNIQUE REFERENCES context.activity_receipt(id) ON DELETE RESTRICT,
    declared_format TEXT NOT NULL CHECK (length(btrim(declared_format)) > 0),
    detection JSONB NOT NULL CHECK (jsonb_typeof(detection) = 'object' AND octet_length(detection::text) <= 2097152),
    preview JSONB NOT NULL CHECK (jsonb_typeof(preview) = 'object' AND octet_length(preview::text) <= 2097152),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (source_version_id, original_object_id, activity_receipt_id)
);

CREATE TABLE context.repair_decision (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    source_version_id UUID NOT NULL REFERENCES context.source_version(id) ON DELETE RESTRICT,
    assessment_id UUID NOT NULL REFERENCES context.repair_assessment(id) ON DELETE RESTRICT,
    actor_ref TEXT NOT NULL CHECK (length(btrim(actor_ref)) > 0),
    approved BOOLEAN NOT NULL,
    apply_repair BOOLEAN NOT NULL,
    tool_id TEXT,
    tool_payload JSONB NOT NULL DEFAULT '{}'::jsonb
        CHECK (jsonb_typeof(tool_payload) = 'object' AND octet_length(tool_payload::text) <= 65536),
    decision_idempotency_key TEXT NOT NULL UNIQUE CHECK (length(btrim(decision_idempotency_key)) > 0),
    decided_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK ((approved AND apply_repair AND tool_id IN ('repair.write-derived','repair.pdf-derived'))
        OR (approved AND NOT apply_repair AND tool_id IS NULL AND tool_payload = '{}'::jsonb)
        OR (NOT approved AND NOT apply_repair AND tool_id IS NULL AND tool_payload = '{}'::jsonb)),
    UNIQUE (id, source_version_id, assessment_id)
);

CREATE TABLE context.repair_resolution (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    source_version_id UUID NOT NULL REFERENCES context.source_version(id) ON DELETE RESTRICT,
    assessment_id UUID NOT NULL REFERENCES context.repair_assessment(id) ON DELETE RESTRICT,
    decision_id UUID NOT NULL REFERENCES context.repair_decision(id) ON DELETE RESTRICT,
    original_object_id UUID NOT NULL REFERENCES context.retained_object(id) ON DELETE RESTRICT,
    active_object_id UUID NOT NULL REFERENCES context.retained_object(id) ON DELETE RESTRICT,
    activity_receipt_id UUID NOT NULL UNIQUE REFERENCES context.activity_receipt(id) ON DELETE RESTRICT,
    actor_ref TEXT NOT NULL CHECK (length(btrim(actor_ref)) > 0),
    applied BOOLEAN NOT NULL,
    tool_id TEXT,
    tool_result JSONB NOT NULL DEFAULT '{}'::jsonb
        CHECK (jsonb_typeof(tool_result) = 'object' AND octet_length(tool_result::text) <= 2097152),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (decision_id),
    CHECK ((applied AND tool_id IN ('repair.write-derived','repair.pdf-derived') AND active_object_id <> original_object_id)
        OR (NOT applied AND tool_id IS NULL AND tool_result = '{}'::jsonb AND active_object_id = original_object_id))
);

CREATE OR REPLACE FUNCTION context.forbid_repair_activity_mutation()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path = pg_catalog AS $$
BEGIN
    RAISE EXCEPTION '% is append-only', TG_TABLE_NAME;
END;
$$;

DO $guards$
DECLARE v_relation REGCLASS;
BEGIN
    FOREACH v_relation IN ARRAY ARRAY[
        'context.repair_assessment'::REGCLASS,
        'context.repair_decision'::REGCLASS,
        'context.repair_resolution'::REGCLASS
    ] LOOP
        EXECUTE format('CREATE TRIGGER repair_append_only BEFORE UPDATE OR DELETE ON %s FOR EACH ROW EXECUTE FUNCTION context.forbid_repair_activity_mutation()', v_relation);
        EXECUTE format('CREATE TRIGGER repair_no_truncate BEFORE TRUNCATE ON %s FOR EACH STATEMENT EXECUTE FUNCTION context.forbid_repair_activity_mutation()', v_relation);
    END LOOP;
END
$guards$;

REVOKE ALL ON FUNCTION context.forbid_repair_activity_mutation() FROM PUBLIC;
REVOKE ALL ON context.repair_assessment, context.repair_decision, context.repair_resolution FROM PUBLIC;
GRANT SELECT, INSERT ON context.repair_assessment, context.repair_decision, context.repair_resolution TO context_import_writer;
GRANT SELECT ON context.repair_assessment, context.repair_decision, context.repair_resolution TO context_reader;

DO $verify$
BEGIN
    IF has_table_privilege('platform_runtime','context.repair_decision','UPDATE')
       OR has_table_privilege('platform_runtime','context.repair_resolution','DELETE') THEN
        RAISE EXCEPTION 'migration 0051 refuses mutable repair privileges';
    END IF;
    IF NOT has_table_privilege('platform_runtime','context.repair_assessment','SELECT,INSERT')
       OR NOT has_table_privilege('platform_runtime','context.repair_resolution','SELECT,INSERT') THEN
        RAISE EXCEPTION 'migration 0051 runtime grants are incomplete';
    END IF;
END
$verify$;

COMMIT;
