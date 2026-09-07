-- 0031_dev_mode_immutability_gate.sql
-- ✅ APPLIED TO PROD 2026-08-24 on owner instruction (see docs/CHANGE-ORDER.md CH-18).
--
-- Byline: Claude Code · Opus 5 · 2026-08-24
--
-- OWNER RULING (2026-08-24, verbatim intent): "Program a dev flag — disables immutability
-- for now until it gets switched to prod." And earlier the same night: "nothing is
-- immutable until we go live."
--
-- This migration extends the EXISTING dev/prod flag — `app.evidence_live`, invented by
-- sql/0009 for the six evidence.raw_* guards — to the three remaining immutability
-- trigger functions, which until now blocked unconditionally:
--
--   evidence.source_immutable_core()   (write-once evidence.source)
--   evidence.forbid_mutation()         (append-only evidence tables, e.g. custody_event)
--   working.forbid_mutation()          (append-only working/ops ledgers, 0017/0020/0025)
--
-- Semantics after this migration (identical to raw_no_mutate's pattern, 0009:174-176):
--   app.evidence_live unset or <> 'on'  -> DEV MODE: guards pass through, mutation allowed
--   app.evidence_live = 'on'            -> PROD MODE: full immutability, byte-for-byte the
--                                          original blocking behaviour
--
-- ── PROD SWITCH (the one command that arms EVERYTHING at go-live) ─────────────────────
--     ALTER DATABASE ai SET app.evidence_live = 'on';
--   (then reconnect sessions). This single flag now arms: the six raw_* guards (0009),
--   evidence.source write-once, evidence append-only tables, and the working/ops
--   append-only ledgers. Un-arming is the same statement with 'off' — intended only
--   while pre-live.
-- ──────────────────────────────────────────────────────────────────────────────────────
--
-- NOTE: evidence.chain_custody_event() (the hash-chain COMPUTATION on custody_event
-- insert) is deliberately NOT gated — it computes rather than blocks, and dev-mode rows
-- should still get correct digests.
--
-- The DB trigger definitions themselves are unchanged; only the three function bodies
-- gain the gate, preserving their original logic verbatim in the armed branch.

BEGIN;

CREATE OR REPLACE FUNCTION evidence.source_immutable_core()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    -- DEV GATE (0031): immutability armed only when the platform is live.
    -- Mirrors evidence.raw_no_mutate() (0009). Owner ruling 2026-08-24.
    IF COALESCE(current_setting('app.evidence_live', true), '') <> 'on' THEN
        IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
        RETURN NEW;
    END IF;

    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION 'evidence.source is write-once: DELETE blocked (never-delete -> _stale)';
    END IF;
    IF  NEW.sha256 IS DISTINCT FROM OLD.sha256
     OR NEW.md5_prefilter IS DISTINCT FROM OLD.md5_prefilter
     OR NEW.byte_size IS DISTINCT FROM OLD.byte_size
     OR NEW.mime_type IS DISTINCT FROM OLD.mime_type
     OR NEW.original_filename IS DISTINCT FROM OLD.original_filename
     OR NEW.source_type IS DISTINCT FROM OLD.source_type
     OR NEW.custodian IS DISTINCT FROM OLD.custodian
     OR NEW.acquisition_source IS DISTINCT FROM OLD.acquisition_source
     OR NEW.r2_bucket IS DISTINCT FROM OLD.r2_bucket
     OR NEW.r2_key IS DISTINCT FROM OLD.r2_key
     OR NEW.provenance_tier IS DISTINCT FROM OLD.provenance_tier
     OR NEW.hash_canon_version IS DISTINCT FROM OLD.hash_canon_version
     OR NEW.supersedes_source_id IS DISTINCT FROM OLD.supersedes_source_id
     OR NEW.original_metadata IS DISTINCT FROM OLD.original_metadata
     OR NEW.ingested_at IS DISTINCT FROM OLD.ingested_at THEN
        RAISE EXCEPTION 'evidence.source core/identity columns immutable (only lifecycle status may change)';
    END IF;
    RETURN NEW;
END $function$;

CREATE OR REPLACE FUNCTION evidence.forbid_mutation()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  -- DEV GATE (0031): armed only when live. Owner ruling 2026-08-24.
  IF COALESCE(current_setting('app.evidence_live', true), '') <> 'on' THEN
      IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
      RETURN NEW;
  END IF;

  RAISE EXCEPTION 'evidence.% is immutable (originals/append-only): % blocked (never-delete -> _stale)',
    TG_TABLE_NAME, TG_OP;
END $function$;

CREATE OR REPLACE FUNCTION working.forbid_mutation()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    -- DEV GATE (0031): armed only when live. Owner ruling 2026-08-24.
    IF COALESCE(current_setting('app.evidence_live', true), '') <> 'on' THEN
        IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
        RETURN NEW;
    END IF;

    RAISE EXCEPTION '% is append-only: % blocked (corrections are new rows)',
        TG_TABLE_NAME, TG_OP;
END
$function$;

COMMENT ON FUNCTION evidence.source_immutable_core() IS
  'Write-once guard for evidence.source. DEV-GATED (0031): inert unless app.evidence_live=on. '
  'Arm at go-live: ALTER DATABASE ai SET app.evidence_live = ''on''.';
COMMENT ON FUNCTION evidence.forbid_mutation() IS
  'Append-only guard for evidence tables. DEV-GATED (0031): inert unless app.evidence_live=on.';
COMMENT ON FUNCTION working.forbid_mutation() IS
  'Append-only guard for working/ops ledgers (0017/0020/0025). DEV-GATED (0031): inert unless '
  'app.evidence_live=on.';

COMMIT;
