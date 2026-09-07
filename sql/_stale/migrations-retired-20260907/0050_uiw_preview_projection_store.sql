-- Migration 0050: durable opaque UIW preview projection store.
-- Reference-only operator projection; no source or normalized payload bytes enter workflow history.
-- Byline: Codex · GPT-5.6 · 2026-08-29.

BEGIN;

DO $prerequisites$
DECLARE v_role TEXT;
BEGIN
    IF current_database() <> 'platform' THEN
        RAISE EXCEPTION 'migration 0050 may run only in database platform, not %', current_database();
    END IF;
    FOREACH v_role IN ARRAY ARRAY[
        'platform_admin', 'platform_runtime', 'context_owner',
        'context_import_writer', 'context_reader'
    ] LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = v_role) THEN
            RAISE EXCEPTION 'migration 0050 requires role %', v_role;
        END IF;
    END LOOP;
    IF NOT pg_has_role('platform_admin', 'context_owner', 'MEMBER')
       OR NOT pg_has_role('platform_runtime', 'context_import_writer', 'MEMBER') THEN
        RAISE EXCEPTION 'migration 0050 requires the governed context role topology';
    END IF;
    IF EXISTS (
        SELECT 1 FROM pg_roles
        WHERE rolname IN ('platform_admin', 'platform_runtime', 'context_owner',
                          'context_import_writer', 'context_reader')
          AND (rolsuper OR rolcreatedb OR rolcreaterole OR rolreplication OR rolbypassrls)
    ) THEN
        RAISE EXCEPTION 'migration 0050 refuses elevated platform/context roles';
    END IF;
    IF to_regclass('context.source_version') IS NULL
       OR to_regclass('context.raw_generation') IS NULL
       OR to_regclass('context.normalized_generation') IS NULL THEN
        RAISE EXCEPTION 'migration 0050 requires the context generation foundation';
    END IF;
END
$prerequisites$;

SET LOCAL ROLE context_owner;
SET LOCAL search_path = pg_catalog, context;

CREATE OR REPLACE FUNCTION context.forbid_uiw_preview_mutation()
RETURNS TRIGGER LANGUAGE plpgsql
SET search_path = pg_catalog AS $$
BEGIN
    RAISE EXCEPTION '% is append-only; append a new UIW preview row', TG_TABLE_NAME;
END;
$$;

CREATE TABLE context.uiw_preview_binding (
    preview_handle TEXT PRIMARY KEY
        CHECK (preview_handle ~ '^[A-Za-z0-9_-]{32,128}$'),
    request_id TEXT NOT NULL UNIQUE CHECK (length(btrim(request_id)) > 0),
    source_ref TEXT NOT NULL CHECK (length(btrim(source_ref)) > 0),
    workflow_id TEXT NOT NULL CHECK (length(btrim(workflow_id)) > 0),
    run_id TEXT NOT NULL CHECK (length(btrim(run_id)) > 0),
    parser_options_ref TEXT NOT NULL CHECK (length(btrim(parser_options_ref)) > 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE context.uiw_preview_binding IS
    'Opaque browser handle bound server-side to the UIW request, source reference, and Temporal identity.';

CREATE TABLE context.uiw_preview_snapshot (
    preview_handle TEXT NOT NULL REFERENCES context.uiw_preview_binding(preview_handle) ON DELETE RESTRICT,
    snapshot_seq BIGINT NOT NULL CHECK (snapshot_seq >= 0),
    phase TEXT NOT NULL CHECK (length(btrim(phase)) > 0),
    source_version_id UUID NOT NULL REFERENCES context.source_version(id) ON DELETE RESTRICT,
    raw_generation_id UUID NOT NULL REFERENCES context.raw_generation(id) ON DELETE RESTRICT,
    normalized_generation_id UUID NOT NULL REFERENCES context.normalized_generation(id) ON DELETE RESTRICT,
    parser_id TEXT,
    parser_version TEXT,
    parser_config_digest BYTEA CHECK (parser_config_digest IS NULL OR octet_length(parser_config_digest) = 32),
    preview_digest BYTEA NOT NULL CHECK (octet_length(preview_digest) = 32),
    reason TEXT NOT NULL DEFAULT '' CHECK (octet_length(reason) <= 4000),
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (preview_handle, snapshot_seq),
    CHECK ((parser_id IS NULL) = (parser_version IS NULL)
       AND (parser_id IS NULL) = (parser_config_digest IS NULL)),
    CHECK (parser_id IS NULL OR (length(btrim(parser_id)) > 0 AND length(btrim(parser_version)) > 0))
);

CREATE TABLE context.uiw_preview_receipt (
    preview_handle TEXT NOT NULL,
    snapshot_seq BIGINT NOT NULL,
    receipt_type TEXT NOT NULL CHECK (receipt_type IN (
        'custody', 'parser_selection', 'parser_execution',
        'normalization', 'storage', 'completeness')),
    receipt_ref TEXT NOT NULL CHECK (length(btrim(receipt_ref)) > 0),
    status TEXT NOT NULL CHECK (status IN ('pending', 'running', 'completed', 'failed', 'skipped')),
    digest BYTEA CHECK (digest IS NULL OR octet_length(digest) = 32),
    recorded_at TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (preview_handle, snapshot_seq, receipt_type),
    FOREIGN KEY (preview_handle, snapshot_seq)
        REFERENCES context.uiw_preview_snapshot(preview_handle, snapshot_seq) ON DELETE RESTRICT
);

CREATE TABLE context.uiw_preview_participant (
    preview_handle TEXT NOT NULL,
    snapshot_seq BIGINT NOT NULL,
    participant_id TEXT NOT NULL CHECK (length(btrim(participant_id)) > 0),
    display_name TEXT NOT NULL CHECK (length(btrim(display_name)) > 0),
    canonical_address TEXT,
    PRIMARY KEY (preview_handle, snapshot_seq, participant_id),
    FOREIGN KEY (preview_handle, snapshot_seq)
        REFERENCES context.uiw_preview_snapshot(preview_handle, snapshot_seq) ON DELETE RESTRICT
);

CREATE TABLE context.uiw_preview_message (
    preview_handle TEXT NOT NULL,
    snapshot_seq BIGINT NOT NULL,
    message_id TEXT NOT NULL CHECK (length(btrim(message_id)) > 0),
    ordinal BIGINT NOT NULL CHECK (ordinal >= 0),
    sent_at TIMESTAMPTZ,
    sender_participant_id TEXT,
    body TEXT NOT NULL CHECK (octet_length(body) <= 4000000),
    participant_ids TEXT[] NOT NULL DEFAULT '{}'::TEXT[] CHECK (cardinality(participant_ids) <= 64),
    source_locator_ref TEXT NOT NULL CHECK (length(btrim(source_locator_ref)) > 0),
    PRIMARY KEY (preview_handle, snapshot_seq, message_id),
    UNIQUE (preview_handle, snapshot_seq, ordinal),
    FOREIGN KEY (preview_handle, snapshot_seq)
        REFERENCES context.uiw_preview_snapshot(preview_handle, snapshot_seq) ON DELETE RESTRICT,
    FOREIGN KEY (preview_handle, snapshot_seq, sender_participant_id)
        REFERENCES context.uiw_preview_participant(preview_handle, snapshot_seq, participant_id)
        ON DELETE RESTRICT
);

CREATE TABLE context.uiw_preview_attachment (
    preview_handle TEXT NOT NULL,
    snapshot_seq BIGINT NOT NULL,
    message_id TEXT NOT NULL,
    attachment_id TEXT NOT NULL CHECK (length(btrim(attachment_id)) > 0),
    filename TEXT,
    media_type TEXT,
    byte_length BIGINT CHECK (byte_length IS NULL OR byte_length >= 0),
    sha256 BYTEA CHECK (sha256 IS NULL OR octet_length(sha256) = 32),
    source_locator_ref TEXT NOT NULL CHECK (length(btrim(source_locator_ref)) > 0),
    PRIMARY KEY (preview_handle, snapshot_seq, attachment_id),
    FOREIGN KEY (preview_handle, snapshot_seq, message_id)
        REFERENCES context.uiw_preview_message(preview_handle, snapshot_seq, message_id)
        ON DELETE RESTRICT
);

CREATE TABLE context.uiw_preview_event (
    preview_handle TEXT NOT NULL REFERENCES context.uiw_preview_binding(preview_handle) ON DELETE RESTRICT,
    event_id BIGINT NOT NULL CHECK (event_id >= 0),
    event_type TEXT NOT NULL CHECK (event_type IN (
        'phase_changed', 'receipt_recorded', 'messages_available',
        'decision_requested', 'decision_recorded', 'completed', 'failed')),
    occurred_at TIMESTAMPTZ NOT NULL,
    phase TEXT NOT NULL CHECK (length(btrim(phase)) > 0),
    receipt_ref TEXT,
    message_count INTEGER CHECK (message_count IS NULL OR message_count >= 0),
    detail TEXT NOT NULL DEFAULT '' CHECK (octet_length(detail) <= 4000),
    PRIMARY KEY (preview_handle, event_id)
);

CREATE TABLE context.uiw_preview_decision (
    id UUID PRIMARY KEY,
    preview_handle TEXT NOT NULL REFERENCES context.uiw_preview_binding(preview_handle) ON DELETE RESTRICT,
    decision_key BYTEA NOT NULL CHECK (octet_length(decision_key) = 32),
    approved BOOLEAN NOT NULL,
    reason TEXT NOT NULL DEFAULT '' CHECK (octet_length(reason) <= 4000),
    actor_subject_uid TEXT NOT NULL CHECK (length(btrim(actor_subject_uid)) > 0),
    selection_ref TEXT NOT NULL CHECK (length(btrim(selection_ref)) > 0),
    parser_options_ref TEXT NOT NULL CHECK (length(btrim(parser_options_ref)) > 0),
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (preview_handle, decision_key)
);

CREATE INDEX uiw_preview_message_page_idx
    ON context.uiw_preview_message (preview_handle, snapshot_seq, ordinal, message_id);
CREATE INDEX uiw_preview_event_replay_idx
    ON context.uiw_preview_event (preview_handle, event_id);

CREATE OR REPLACE FUNCTION context.guard_uiw_preview_event_sequence()
RETURNS TRIGGER LANGUAGE plpgsql
SET search_path = pg_catalog, context AS $$
DECLARE v_last BIGINT;
BEGIN
    PERFORM 1 FROM context.uiw_preview_binding
    WHERE preview_handle = NEW.preview_handle FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'unknown UIW preview handle %', NEW.preview_handle; END IF;
    SELECT max(event_id) INTO v_last FROM context.uiw_preview_event
    WHERE preview_handle = NEW.preview_handle;
    IF NEW.event_id <> COALESCE(v_last + 1, 0) THEN
        RAISE EXCEPTION 'UIW preview event % follows %, expected %',
            NEW.event_id, v_last, COALESCE(v_last + 1, 0);
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION context.assert_uiw_preview_snapshot_complete()
RETURNS TRIGGER LANGUAGE plpgsql
SET search_path = pg_catalog, context AS $$
BEGIN
    IF (SELECT count(*) FROM context.uiw_preview_receipt
        WHERE preview_handle = NEW.preview_handle AND snapshot_seq = NEW.snapshot_seq
          AND status = 'completed') <> 6
       OR EXISTS (
           SELECT required.receipt_type
           FROM unnest(ARRAY['custody','parser_selection','parser_execution',
                             'normalization','storage','completeness']) AS required(receipt_type)
           WHERE NOT EXISTS (
               SELECT 1 FROM context.uiw_preview_receipt receipt
               WHERE receipt.preview_handle = NEW.preview_handle
                 AND receipt.snapshot_seq = NEW.snapshot_seq
                 AND receipt.receipt_type = required.receipt_type
                 AND receipt.status = 'completed')) THEN
        RAISE EXCEPTION 'UIW preview snapshot (%, %) requires all six completed receipts',
            NEW.preview_handle, NEW.snapshot_seq;
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM context.uiw_preview_message
        WHERE preview_handle = NEW.preview_handle AND snapshot_seq = NEW.snapshot_seq
    ) THEN
        RAISE EXCEPTION 'UIW preview snapshot (%, %) requires a normalized message',
            NEW.preview_handle, NEW.snapshot_seq;
    END IF;
    IF EXISTS (
        SELECT 1
        FROM context.uiw_preview_message message
        CROSS JOIN LATERAL unnest(message.participant_ids) AS participant(participant_id)
        WHERE message.preview_handle = NEW.preview_handle
          AND message.snapshot_seq = NEW.snapshot_seq
          AND NOT EXISTS (
              SELECT 1 FROM context.uiw_preview_participant known
              WHERE known.preview_handle = message.preview_handle
                AND known.snapshot_seq = message.snapshot_seq
                AND known.participant_id = participant.participant_id)
    ) THEN
        RAISE EXCEPTION 'UIW preview snapshot (%, %) contains an unresolved participant',
            NEW.preview_handle, NEW.snapshot_seq;
    END IF;
    RETURN NULL;
END;
$$;

CREATE TRIGGER uiw_preview_event_sequence_gate
    BEFORE INSERT ON context.uiw_preview_event
    FOR EACH ROW EXECUTE FUNCTION context.guard_uiw_preview_event_sequence();

CREATE CONSTRAINT TRIGGER uiw_preview_snapshot_complete_gate
    AFTER INSERT ON context.uiw_preview_snapshot
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION context.assert_uiw_preview_snapshot_complete();

DO $guards$
DECLARE v_relation REGCLASS;
BEGIN
    FOREACH v_relation IN ARRAY ARRAY[
        'context.uiw_preview_binding'::REGCLASS,
        'context.uiw_preview_snapshot'::REGCLASS,
        'context.uiw_preview_receipt'::REGCLASS,
        'context.uiw_preview_participant'::REGCLASS,
        'context.uiw_preview_message'::REGCLASS,
        'context.uiw_preview_attachment'::REGCLASS,
        'context.uiw_preview_event'::REGCLASS,
        'context.uiw_preview_decision'::REGCLASS
    ] LOOP
        EXECUTE format('CREATE TRIGGER uiw_preview_append_only BEFORE UPDATE OR DELETE ON %s '
                       'FOR EACH ROW EXECUTE FUNCTION context.forbid_uiw_preview_mutation()', v_relation);
        EXECUTE format('CREATE TRIGGER uiw_preview_no_truncate BEFORE TRUNCATE ON %s '
                       'FOR EACH STATEMENT EXECUTE FUNCTION context.forbid_uiw_preview_mutation()', v_relation);
    END LOOP;
END
$guards$;

REVOKE ALL ON FUNCTION context.forbid_uiw_preview_mutation() FROM PUBLIC;
REVOKE ALL ON FUNCTION context.guard_uiw_preview_event_sequence() FROM PUBLIC;
REVOKE ALL ON FUNCTION context.assert_uiw_preview_snapshot_complete() FROM PUBLIC;
REVOKE ALL ON context.uiw_preview_binding, context.uiw_preview_snapshot,
    context.uiw_preview_receipt, context.uiw_preview_participant, context.uiw_preview_message,
    context.uiw_preview_attachment, context.uiw_preview_event, context.uiw_preview_decision
    FROM PUBLIC;

GRANT SELECT, INSERT ON context.uiw_preview_binding, context.uiw_preview_snapshot,
    context.uiw_preview_receipt, context.uiw_preview_participant, context.uiw_preview_message,
    context.uiw_preview_attachment, context.uiw_preview_event, context.uiw_preview_decision
    TO context_import_writer;
GRANT SELECT ON context.uiw_preview_binding, context.uiw_preview_snapshot,
    context.uiw_preview_receipt, context.uiw_preview_participant, context.uiw_preview_message,
    context.uiw_preview_attachment, context.uiw_preview_event, context.uiw_preview_decision
    TO context_reader;
GRANT EXECUTE ON FUNCTION context.guard_uiw_preview_event_sequence() TO context_import_writer;
GRANT EXECUTE ON FUNCTION context.assert_uiw_preview_snapshot_complete() TO context_import_writer;

DO $verify$
BEGIN
    IF has_table_privilege('platform_runtime', 'context.uiw_preview_binding', 'UPDATE')
       OR has_table_privilege('platform_runtime', 'context.uiw_preview_decision', 'DELETE') THEN
        RAISE EXCEPTION 'migration 0050 refuses mutable UIW preview privileges';
    END IF;
    IF NOT has_table_privilege('platform_runtime', 'context.uiw_preview_binding', 'SELECT,INSERT')
       OR NOT has_table_privilege('platform_runtime', 'context.uiw_preview_event', 'SELECT,INSERT') THEN
        RAISE EXCEPTION 'migration 0050 runtime grants are incomplete';
    END IF;
END
$verify$;

COMMIT;
