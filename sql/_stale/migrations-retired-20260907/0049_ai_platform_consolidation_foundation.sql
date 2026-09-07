-- Migration 0049: non-destructive ai -> platform consolidation proof foundation.
--
-- This is the forward-only correction to the stale proposal to edit migration 0046.
-- Migration 0046 remains immutable historical state. This migration does not copy data,
-- change runtime database selection, grant a writer to platform, or modify the legacy ai
-- database. A later maintenance-window migration may consume these immutable checkpoints
-- only after an independently verified offline-load and cutover contract exists.
--
-- Byline: Codex · GPT-5.6 · 2026-08-29

BEGIN;

DO $prerequisites$
BEGIN
    IF current_database() <> 'platform' THEN
        RAISE EXCEPTION 'migration 0049 may run only in database platform, not %', current_database();
    END IF;
    IF to_regclass('public.schema_version') IS NULL
       OR to_regprocedure('uuidv7()') IS NULL THEN
        RAISE EXCEPTION 'migration 0049 requires the platform bootstrap foundation';
    END IF;
    IF NOT EXISTS (
        SELECT 1
        FROM pg_roles
        WHERE rolname = 'platform_admin'
          AND NOT rolcanlogin
          AND NOT (rolsuper OR rolcreatedb OR rolcreaterole OR rolreplication OR rolbypassrls)
    ) THEN
        RAISE EXCEPTION 'migration 0049 requires safe NOLOGIN role platform_admin';
    END IF;
    IF EXISTS (
        WITH RECURSIVE inheritors(oid) AS (
            SELECT member
            FROM pg_auth_members
            WHERE roleid = (SELECT oid FROM pg_roles WHERE rolname = 'platform_admin')
          UNION
            SELECT memberships.member
            FROM pg_auth_members AS memberships
            JOIN inheritors ON memberships.roleid = inheritors.oid
        )
        SELECT 1
        FROM inheritors
        JOIN pg_roles ON pg_roles.oid = inheritors.oid
        WHERE pg_roles.rolcanlogin
    ) THEN
        RAISE EXCEPTION 'migration 0049 refuses LOGIN inheritance of platform_admin';
    END IF;
END
$prerequisites$;

-- The platform bootstrap makes platform_admin the database owner in production. A schema-only
-- rehearsal restored under another database owner does not inherit that implicit privilege, so
-- state the bounded administrative schema privilege explicitly before SET ROLE.
GRANT USAGE, CREATE ON SCHEMA public TO platform_admin;

SET LOCAL ROLE platform_admin;
SET LOCAL search_path = pg_catalog, public;

DO $namespace_guard$
BEGIN
    IF to_regclass('public.platform_consolidation_checkpoint') IS NOT NULL
       OR to_regclass('public.platform_consolidation_proof_receipt') IS NOT NULL
       OR to_regclass('public.platform_consolidation_receipt_claim') IS NOT NULL
       OR to_regprocedure('public.forbid_consolidation_proof_mutation_v0049()') IS NOT NULL
       OR to_regprocedure('public.require_consolidation_verified_proof_v0049()') IS NOT NULL
       OR to_regprocedure('public.forbid_bound_receipt_supersession_v0049()') IS NOT NULL THEN
        RAISE EXCEPTION 'migration 0049 refuses to replace an existing consolidation namespace object';
    END IF;
END
$namespace_guard$;

CREATE FUNCTION public.forbid_consolidation_proof_mutation_v0049()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog
AS $function$
BEGIN
    RAISE EXCEPTION '% is append-only; record a new checkpoint or receipt', TG_TABLE_NAME;
END
$function$;

CREATE FUNCTION public.require_consolidation_verified_proof_v0049()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $function$
DECLARE
    v_proof_kind TEXT;
    v_result TEXT;
    v_details JSONB;
BEGIN
    IF NEW.checkpoint_status <> 'verified' THEN
        RETURN NEW;
    END IF;

    SELECT receipt.proof_kind, receipt.result, receipt.details
    INTO v_proof_kind, v_result, v_details
    FROM public.platform_consolidation_proof_receipt AS receipt
    WHERE receipt.id = NEW.verified_receipt_id
      AND receipt.checkpoint_id = NEW.id
      AND NOT EXISTS (
          SELECT 1
          FROM public.platform_consolidation_proof_receipt AS successor
          WHERE successor.supersedes_receipt_id = receipt.id
      );

    IF NOT FOUND OR v_result <> 'pass' OR v_proof_kind <> NEW.required_proof_kind THEN
        RAISE EXCEPTION
            'verified consolidation checkpoint % requires its exact unsuperseded passing % receipt',
            NEW.id, NEW.required_proof_kind;
    END IF;
    IF NOT (v_details ?& ARRAY[
        'phase_key', 'relation_key', 'proof_kind', 'source_snapshot_id',
        'target_snapshot_id', 'source_snapshot_sha256', 'target_snapshot_sha256',
        'manifest_sha256', 'repository_revision'
    ])
       OR v_details->>'phase_key' IS DISTINCT FROM NEW.phase_key
       OR v_details->>'relation_key' IS DISTINCT FROM NEW.relation_key
       OR v_details->>'proof_kind' IS DISTINCT FROM NEW.required_proof_kind
       OR v_details->>'source_snapshot_id' IS DISTINCT FROM NEW.source_snapshot_id
       OR v_details->>'target_snapshot_id' IS DISTINCT FROM NEW.target_snapshot_id
       OR lower(v_details->>'source_snapshot_sha256') IS DISTINCT FROM encode(NEW.source_snapshot_sha256, 'hex')
       OR lower(v_details->>'target_snapshot_sha256') IS DISTINCT FROM encode(NEW.target_snapshot_sha256, 'hex')
       OR lower(v_details->>'manifest_sha256') IS DISTINCT FROM encode(NEW.manifest_sha256, 'hex')
       OR v_details->>'repository_revision' IS DISTINCT FROM NEW.repository_revision THEN
        RAISE EXCEPTION 'verified consolidation checkpoint % has an unbound proof receipt', NEW.id;
    END IF;
    IF NEW.required_proof_kind IN ('caller_inventory', 'zero_active_sessions')
       AND (
           NOT (v_details ?& ARRAY[
               'fence_attestation_id', 'fence_attestation_sha256', 'fence_established_at',
               'fence_valid_until'
           ])
           OR v_details->>'fence_attestation_id' IS DISTINCT FROM NEW.fence_attestation_id
           OR lower(v_details->>'fence_attestation_sha256')
              IS DISTINCT FROM encode(NEW.fence_attestation_sha256, 'hex')
           OR (v_details->>'fence_established_at')::TIMESTAMPTZ
              IS DISTINCT FROM NEW.fence_established_at
           OR (v_details->>'fence_valid_until')::TIMESTAMPTZ IS DISTINCT FROM NEW.fence_valid_until
       ) THEN
        RAISE EXCEPTION 'verified caller checkpoint % requires its exact bound fence attestation', NEW.id;
    END IF;
    BEGIN
        INSERT INTO public.platform_consolidation_receipt_claim (
            receipt_id, claim_kind, checkpoint_id
        ) VALUES (NEW.verified_receipt_id, 'verified', NEW.id);
    EXCEPTION
        WHEN unique_violation THEN
            RAISE EXCEPTION
                'receipt % already has an incompatible immutable claim', NEW.verified_receipt_id
                USING ERRCODE = '23514';
    END;
    RETURN NEW;
END
$function$;

CREATE FUNCTION public.forbid_bound_receipt_supersession_v0049()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, public
AS $function$
BEGIN
    IF NEW.supersedes_receipt_id IS NOT NULL
       AND EXISTS (
           SELECT 1
           FROM public.platform_consolidation_checkpoint AS checkpoint
           WHERE checkpoint.verified_receipt_id = NEW.supersedes_receipt_id
             AND checkpoint.checkpoint_status = 'verified'
       ) THEN
        RAISE EXCEPTION 'receipt % is bound to a verified checkpoint and cannot be superseded',
            NEW.supersedes_receipt_id;
    END IF;
    IF NEW.supersedes_receipt_id IS NOT NULL THEN
        BEGIN
            INSERT INTO public.platform_consolidation_receipt_claim (
                receipt_id, claim_kind, successor_receipt_id
            ) VALUES (NEW.supersedes_receipt_id, 'superseded', NEW.id);
        EXCEPTION
            WHEN unique_violation THEN
                RAISE EXCEPTION
                    'receipt % already has an incompatible immutable claim', NEW.supersedes_receipt_id
                    USING ERRCODE = '23514';
        END;
    END IF;
    RETURN NEW;
END
$function$;

REVOKE ALL ON FUNCTION public.forbid_consolidation_proof_mutation_v0049() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.require_consolidation_verified_proof_v0049() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.forbid_bound_receipt_supersession_v0049() FROM PUBLIC;

CREATE TABLE public.platform_consolidation_checkpoint (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    plan_id UUID NOT NULL,
    source_database TEXT NOT NULL DEFAULT 'ai' CHECK (source_database = 'ai'),
    target_database TEXT NOT NULL DEFAULT 'platform' CHECK (target_database = 'platform'),
    phase_key TEXT NOT NULL CHECK (length(btrim(phase_key)) > 0),
    relation_key TEXT NOT NULL DEFAULT '__phase__' CHECK (length(btrim(relation_key)) > 0),
    attempt_key TEXT NOT NULL CHECK (length(btrim(attempt_key)) > 0),
    required_proof_kind TEXT NOT NULL CHECK (
        required_proof_kind IN (
            'inventory', 'row_parity', 'foreign_key_integrity', 'role_inventory',
            'extension_inventory', 'caller_inventory', 'zero_active_sessions',
            'custody_integrity', 'source_clock_integrity', 'projection_integrity'
        )
    ),
    checkpoint_status TEXT NOT NULL
        CHECK (checkpoint_status IN ('planned', 'verified', 'blocked', 'failed')),
    source_snapshot_id TEXT NOT NULL CHECK (length(btrim(source_snapshot_id)) > 0),
    target_snapshot_id TEXT NOT NULL CHECK (length(btrim(target_snapshot_id)) > 0),
    source_snapshot_sha256 BYTEA NOT NULL CHECK (octet_length(source_snapshot_sha256) = 32),
    target_snapshot_sha256 BYTEA NOT NULL CHECK (octet_length(target_snapshot_sha256) = 32),
    manifest_sha256 BYTEA NOT NULL CHECK (octet_length(manifest_sha256) = 32),
    repository_revision TEXT NOT NULL CHECK (length(btrim(repository_revision)) > 0),
    source_snapshot_observed_at TIMESTAMPTZ NOT NULL,
    target_snapshot_observed_at TIMESTAMPTZ NOT NULL,
    fence_attestation_id TEXT,
    fence_attestation_sha256 BYTEA CHECK (
        fence_attestation_sha256 IS NULL OR octet_length(fence_attestation_sha256) = 32
    ),
    fence_established_at TIMESTAMPTZ,
    fence_valid_until TIMESTAMPTZ,
    source_row_count BIGINT CHECK (source_row_count IS NULL OR source_row_count >= 0),
    target_row_count BIGINT CHECK (target_row_count IS NULL OR target_row_count >= 0),
    copy_order INTEGER CHECK (copy_order IS NULL OR copy_order > 0),
    dependency_keys TEXT[] NOT NULL DEFAULT '{}'::TEXT[],
    proof_ref TEXT NOT NULL CHECK (length(btrim(proof_ref)) > 0),
    verified_receipt_id UUID,
    recorded_by TEXT NOT NULL CHECK (length(btrim(recorded_by)) > 0),
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (plan_id, phase_key, relation_key, attempt_key),
    CHECK (
        required_proof_kind <> 'row_parity'
        OR checkpoint_status <> 'verified'
        OR (
            source_row_count IS NOT NULL
            AND target_row_count IS NOT NULL
            AND source_row_count = target_row_count
        )
    ),
    CHECK ((checkpoint_status = 'verified') = (verified_receipt_id IS NOT NULL)),
    CHECK (
        checkpoint_status <> 'verified'
        OR required_proof_kind NOT IN ('caller_inventory', 'zero_active_sessions')
        OR (
            fence_attestation_id IS NOT NULL
            AND length(btrim(fence_attestation_id)) > 0
            AND fence_attestation_sha256 IS NOT NULL
            AND fence_established_at IS NOT NULL
            AND fence_valid_until IS NOT NULL
            AND fence_established_at <= source_snapshot_observed_at
            AND fence_established_at <= target_snapshot_observed_at
            AND fence_valid_until >= source_snapshot_observed_at
            AND fence_valid_until >= target_snapshot_observed_at
        )
    )
);

COMMENT ON TABLE public.platform_consolidation_checkpoint IS
    'Immutable, idempotently keyed proof checkpoints for a future ai-to-platform copy. '
    'This table authorizes no copy or cutover and stores no source payload bytes.';
COMMENT ON COLUMN public.platform_consolidation_checkpoint.relation_key IS
    'Schema-qualified relation name, or __phase__ for a phase-wide checkpoint.';
COMMENT ON COLUMN public.platform_consolidation_checkpoint.attempt_key IS
    'Caller-supplied idempotency key. Repeating a phase/relation attempt cannot create a duplicate.';

CREATE INDEX platform_consolidation_checkpoint_phase_idx
    ON public.platform_consolidation_checkpoint (plan_id, phase_key, copy_order, relation_key);

CREATE TABLE public.platform_consolidation_proof_receipt (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    checkpoint_id UUID NOT NULL
        REFERENCES public.platform_consolidation_checkpoint(id) ON DELETE RESTRICT,
    supersedes_receipt_id UUID
        REFERENCES public.platform_consolidation_proof_receipt(id) ON DELETE RESTRICT,
    proof_kind TEXT NOT NULL CHECK (
        proof_kind IN (
            'inventory', 'row_parity', 'foreign_key_integrity', 'role_inventory',
            'extension_inventory', 'caller_inventory', 'zero_active_sessions',
            'custody_integrity', 'source_clock_integrity', 'projection_integrity'
        )
    ),
    result TEXT NOT NULL CHECK (result IN ('pass', 'fail', 'blocked')),
    proof_sha256 BYTEA NOT NULL CHECK (octet_length(proof_sha256) = 32),
    details JSONB NOT NULL CHECK (jsonb_typeof(details) = 'object' AND details <> '{}'::JSONB),
    observed_by TEXT NOT NULL CHECK (length(btrim(observed_by)) > 0),
    observed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (checkpoint_id, proof_kind, proof_sha256),
    UNIQUE (supersedes_receipt_id)
);

ALTER TABLE public.platform_consolidation_checkpoint
    ADD CONSTRAINT platform_consolidation_verified_receipt_fk
    FOREIGN KEY (verified_receipt_id)
    REFERENCES public.platform_consolidation_proof_receipt(id)
    ON DELETE RESTRICT
    DEFERRABLE INITIALLY DEFERRED;

CREATE TABLE public.platform_consolidation_receipt_claim (
    receipt_id UUID PRIMARY KEY
        REFERENCES public.platform_consolidation_proof_receipt(id) ON DELETE RESTRICT,
    claim_kind TEXT NOT NULL CHECK (claim_kind IN ('verified', 'superseded')),
    checkpoint_id UUID
        REFERENCES public.platform_consolidation_checkpoint(id) ON DELETE RESTRICT,
    successor_receipt_id UUID
        REFERENCES public.platform_consolidation_proof_receipt(id) ON DELETE RESTRICT,
    claimed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (
        (claim_kind = 'verified' AND checkpoint_id IS NOT NULL AND successor_receipt_id IS NULL)
        OR
        (claim_kind = 'superseded' AND checkpoint_id IS NULL AND successor_receipt_id IS NOT NULL)
    )
);

COMMENT ON TABLE public.platform_consolidation_receipt_claim IS
    'One immutable claim per receipt. The primary key serializes verified binding against '
    'supersession, including concurrent transactions.';

COMMENT ON TABLE public.platform_consolidation_proof_receipt IS
    'Append-only proof results. Corrections and reruns are new receipts, never row mutation.';

CREATE INDEX platform_consolidation_receipt_checkpoint_idx
    ON public.platform_consolidation_proof_receipt (checkpoint_id, proof_kind, observed_at);

CREATE TRIGGER platform_consolidation_checkpoint_append_only
    BEFORE UPDATE OR DELETE ON public.platform_consolidation_checkpoint
    FOR EACH ROW EXECUTE FUNCTION public.forbid_consolidation_proof_mutation_v0049();

CREATE TRIGGER platform_consolidation_checkpoint_no_truncate
    BEFORE TRUNCATE ON public.platform_consolidation_checkpoint
    FOR EACH STATEMENT EXECUTE FUNCTION public.forbid_consolidation_proof_mutation_v0049();

CREATE TRIGGER platform_consolidation_proof_receipt_append_only
    BEFORE UPDATE OR DELETE ON public.platform_consolidation_proof_receipt
    FOR EACH ROW EXECUTE FUNCTION public.forbid_consolidation_proof_mutation_v0049();

CREATE TRIGGER platform_consolidation_proof_receipt_no_truncate
    BEFORE TRUNCATE ON public.platform_consolidation_proof_receipt
    FOR EACH STATEMENT EXECUTE FUNCTION public.forbid_consolidation_proof_mutation_v0049();

CREATE TRIGGER platform_consolidation_receipt_claim_append_only
    BEFORE UPDATE OR DELETE ON public.platform_consolidation_receipt_claim
    FOR EACH ROW EXECUTE FUNCTION public.forbid_consolidation_proof_mutation_v0049();

CREATE TRIGGER platform_consolidation_receipt_claim_no_truncate
    BEFORE TRUNCATE ON public.platform_consolidation_receipt_claim
    FOR EACH STATEMENT EXECUTE FUNCTION public.forbid_consolidation_proof_mutation_v0049();

CREATE CONSTRAINT TRIGGER platform_consolidation_bound_receipt_no_supersede
    AFTER INSERT ON public.platform_consolidation_proof_receipt
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION public.forbid_bound_receipt_supersession_v0049();

CREATE CONSTRAINT TRIGGER platform_consolidation_verified_requires_pass
    AFTER INSERT ON public.platform_consolidation_checkpoint
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION public.require_consolidation_verified_proof_v0049();

REVOKE ALL ON TABLE public.platform_consolidation_checkpoint FROM PUBLIC;
REVOKE ALL ON TABLE public.platform_consolidation_proof_receipt FROM PUBLIC;
REVOKE ALL ON TABLE public.platform_consolidation_receipt_claim FROM PUBLIC;

DO $verify$
DECLARE
    v_relation REGCLASS;
BEGIN
    FOREACH v_relation IN ARRAY ARRAY[
        'public.platform_consolidation_checkpoint'::REGCLASS,
        'public.platform_consolidation_proof_receipt'::REGCLASS,
        'public.platform_consolidation_receipt_claim'::REGCLASS
    ] LOOP
        IF (SELECT pg_get_userbyid(relowner) FROM pg_class WHERE oid = v_relation)
           IS DISTINCT FROM 'platform_admin' THEN
            RAISE EXCEPTION 'migration 0049 relation % has unexpected owner', v_relation;
        END IF;
        IF NOT EXISTS (
            SELECT 1
            FROM pg_trigger
            WHERE tgrelid = v_relation
              AND NOT tgisinternal
              AND tgname LIKE 'platform_consolidation_%_append_only'
        ) THEN
            RAISE EXCEPTION 'migration 0049 relation % is missing append-only guard', v_relation;
        END IF;
        IF NOT EXISTS (
            SELECT 1
            FROM pg_trigger
            WHERE tgrelid = v_relation
              AND NOT tgisinternal
              AND tgname LIKE 'platform_consolidation_%_no_truncate'
        ) THEN
            RAISE EXCEPTION 'migration 0049 relation % is missing truncate guard', v_relation;
        END IF;
    END LOOP;
END
$verify$;

COMMIT;
