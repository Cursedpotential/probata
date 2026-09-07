-- Migration 0053: append-only operator source context and correction receipts.
-- Source-observed values stay immutable; human assertions are versioned separately.
-- Byline: Codex · GPT-5.6-Sol · 2026-08-30.

BEGIN;

DO $prerequisites$
DECLARE v_role TEXT;
BEGIN
    IF current_database() <> 'platform' THEN
        RAISE EXCEPTION 'migration 0053 may run only in database platform, not %', current_database();
    END IF;
    FOREACH v_role IN ARRAY ARRAY[
        'platform_admin', 'platform_runtime', 'context_owner',
        'context_import_writer', 'context_reader'
    ] LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = v_role) THEN
            RAISE EXCEPTION 'migration 0053 requires role %', v_role;
        END IF;
    END LOOP;
    IF to_regclass('context.uiw_preview_binding') IS NULL THEN
        RAISE EXCEPTION 'migration 0053 requires migration 0050';
    END IF;
END
$prerequisites$;

SET LOCAL ROLE context_owner;
SET LOCAL search_path = pg_catalog, context;

CREATE TABLE context.uiw_source_context_revision (
    source_context_ref UUID PRIMARY KEY,
    request_id TEXT NOT NULL CHECK (length(btrim(request_id)) > 0),
    revision INTEGER NOT NULL CHECK (revision >= 1),
    supersedes_ref UUID REFERENCES context.uiw_source_context_revision(source_context_ref) ON DELETE RESTRICT,
    matter_id UUID NOT NULL,
    court_case_id UUID NOT NULL,
    source_ref TEXT NOT NULL CHECK (length(btrim(source_ref)) > 0),
    observed_source JSONB NOT NULL CHECK (jsonb_typeof(observed_source) = 'object'),
    previous_assertions JSONB CHECK (previous_assertions IS NULL OR jsonb_typeof(previous_assertions) = 'object'),
    assertions JSONB NOT NULL CHECK (jsonb_typeof(assertions) = 'object'),
    change_reason TEXT NOT NULL CHECK (length(btrim(change_reason)) > 0 AND octet_length(change_reason) <= 4000),
    actor_subject_uid TEXT NOT NULL CHECK (length(btrim(actor_subject_uid)) > 0),
    actor_username TEXT NOT NULL CHECK (length(btrim(actor_username)) > 0),
    idempotency_key TEXT NOT NULL UNIQUE CHECK (length(btrim(idempotency_key)) > 0),
    content_digest BYTEA NOT NULL CHECK (octet_length(content_digest) = 32),
    receipt_ref TEXT NOT NULL UNIQUE CHECK (length(btrim(receipt_ref)) > 0),
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (request_id, revision),
    CHECK ((revision = 1 AND supersedes_ref IS NULL AND previous_assertions IS NULL)
        OR (revision > 1 AND supersedes_ref IS NOT NULL AND previous_assertions IS NOT NULL))
);

ALTER TABLE context.source_version
    ADD COLUMN source_context_ref UUID
    REFERENCES context.uiw_source_context_revision(source_context_ref) ON DELETE RESTRICT;
CREATE INDEX source_version_source_context_idx
    ON context.source_version(source_context_ref)
    WHERE source_context_ref IS NOT NULL;

COMMENT ON TABLE context.uiw_source_context_revision IS
    'Append-only operator assertions kept separate from immutable preview-only source observations. Preview hashes are not custody hashes. Each revision is actor-bound and receipt-addressed.';
COMMENT ON COLUMN context.source_version.source_context_ref IS
    'Actor-bound source-context revision validated against request, matter, case, and source at registration.';

CREATE OR REPLACE FUNCTION context.guard_uiw_source_context_revision()
RETURNS TRIGGER LANGUAGE plpgsql
SET search_path = pg_catalog, context AS $$
DECLARE prior context.uiw_source_context_revision%ROWTYPE;
BEGIN
    IF NEW.revision = 1 THEN
        RETURN NEW;
    END IF;
    SELECT * INTO STRICT prior
    FROM context.uiw_source_context_revision
    WHERE source_context_ref = NEW.supersedes_ref;
    IF prior.request_id <> NEW.request_id
       OR prior.revision + 1 <> NEW.revision
       OR prior.matter_id <> NEW.matter_id
       OR prior.court_case_id <> NEW.court_case_id
       OR prior.source_ref <> NEW.source_ref
       OR prior.observed_source <> NEW.observed_source
       OR prior.assertions <> NEW.previous_assertions THEN
        RAISE EXCEPTION 'UIW source context correction does not preserve its immutable lineage';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER uiw_source_context_lineage_gate
    BEFORE INSERT ON context.uiw_source_context_revision
    FOR EACH ROW EXECUTE FUNCTION context.guard_uiw_source_context_revision();
CREATE TRIGGER uiw_source_context_append_only
    BEFORE UPDATE OR DELETE ON context.uiw_source_context_revision
    FOR EACH ROW EXECUTE FUNCTION context.forbid_uiw_preview_mutation();
CREATE TRIGGER uiw_source_context_no_truncate
    BEFORE TRUNCATE ON context.uiw_source_context_revision
    FOR EACH STATEMENT EXECUTE FUNCTION context.forbid_uiw_preview_mutation();

REVOKE ALL ON FUNCTION context.guard_uiw_source_context_revision() FROM PUBLIC;
REVOKE ALL ON context.uiw_source_context_revision FROM PUBLIC;
GRANT SELECT, INSERT ON context.uiw_source_context_revision TO context_import_writer;
GRANT SELECT ON context.uiw_source_context_revision TO context_reader;
GRANT EXECUTE ON FUNCTION context.guard_uiw_source_context_revision() TO context_import_writer;

DO $verify$
BEGIN
    IF has_table_privilege('platform_runtime', 'context.uiw_source_context_revision', 'UPDATE')
       OR has_table_privilege('platform_runtime', 'context.uiw_source_context_revision', 'DELETE')
       OR NOT has_table_privilege('platform_runtime', 'context.uiw_source_context_revision', 'SELECT,INSERT') THEN
        RAISE EXCEPTION 'migration 0053 source-context privileges are invalid';
    END IF;
END
$verify$;

COMMIT;
