-- 0029_pass_grants.sql — default-deny grants for the pass-corpora derivation lane (ADR-0045 §B / ADR-0052).
--
-- Byline: Claude Code . glm-5.2:cloud . 2026-08-14
-- Byline amendment: Codex GPT-5 . 2026-08-18
-- Byline amendment: Codex GPT-5 . 2026-08-18 (native vector outbox grants)
-- Supersession: the HELD draft now covers the projection/acquisition review
-- boundary, version-pinned materialization, realization atoms, and resumable
-- checkpoints. Role creation is idempotent before first application.
--
-- ✅ APPLIED TO PROD — verified live 2026-08-23 against 100.91.190.107:5432 db=ai by direct
--    introspection (Claude Code · Opus 5). All four roles — pass_refresher, pass_reader,
--    projection_refresher, horizon_reviewer — confirmed PRESENT in pg_roles.
--    ⚠ STILL INERT, exactly as this file's own header below predicted: the app connects as
--    role `ai`, re-verified 2026-08-23 as rolsuper=True AND rolbypassrls=True. Superusers
--    bypass every GRANT and all RLS, so these roles remain the schema contract for the
--    target isolation, not an enforcing guard. Closing that gap needs a connection-model
--    change, not another migration.
-- ~~⚠ HELD FOR OWNER — DRAFTED + ROLLBACK-VALIDATED 2026-08-14, NOT APPLIED TO PROD.~~  (historical)
-- ⚠ INERT WHILE SUPERUSER (the decisive finding): the agno app connects as the role
--   `ai`, which is a SUPERUSER (verified live 2026-08-14: rolsuper=True,
--   rolcreaterole=True; the only login role; owner of every working./ops. table).
--   Superusers bypass ALL grants and BYPASSRLS. These grants are therefore the SCHEMA
--   CONTRACT for the target isolation, NOT an enforcing guard under the current
--   connection model. They become ENFORCING only when the app's derivation path
--   connects as `pass_refresher` and agent read-paths as `pass_reader` (a
--   connection-model change that belongs to W1.5 / agent lane bindings). Until then
--   the F13 app-side advisory lock is the sole EFFECTIVE sole-writer guard.
--
-- WHAT THIS IS
-- ============
-- ADR-0045 §B makes the derivation engine the SOLE writer of pass corpora; ADR-0052
-- is default-deny. This migration expresses that at the DB layer:
--   * pass_refresher (NOLOGIN) — sole writer of working.walk_* + record_visible_from;
--     reads the canonical store to compute base_version; attests each step to
--     ops.audit_ledger. (the §B refresher)
--   * pass_reader (NOLOGIN) — agent read of the pass corpus only
--     (working.walk_run/walk_step/walk_step_retrieval). NO grant on canonical base
--     tables (working.normalized_record etc.) — agents read the DERIVED pass corpus,
--     not the raw canonical store (the §B one-store-filtered-per-agent discipline).
--   * DEFAULT-DENY: REVOKE ALL on the pass tables from PUBLIC so a bare role gets
--     nothing; access flows only through the two roles above.
--
-- OPEN — owner decisions (do NOT treat as resolved; see W1.4 pre-mortem):
--   1. Connection model: introduce a non-superuser app role so these grants bite?
--      (the superuser finding above). This is the gate that turns the schema contract
--      into enforcement.
--   2. Per-agent scoping: pass_reader SELECT on walk_run/walk_step exposes ALL runs,
--      not just the agent's own. True per-agent scoping needs RLS (also inert while
--      superuser) or app-layer filtering — deferred to W1.5.
--   3. Transition: agents today read via working.vw_spine_horizon (needs
--      normalized_record SELECT). The target state (agents read pass corpus only,
--      no canonical SELECT) lands with W1.5's rebind. 0029 expresses the TARGET.
--
-- SAFETY (when eventually applied)
-- ===============================
-- Purely additive DDL (CREATE ROLE + GRANT/REVOKE). Does not touch the app's `ai`
-- superuser role or any existing privilege — the new NOLOGIN roles are inert until
-- something assumes them. Applying to LIVE only after (a) the owner rules on the
-- connection-model question, (b) owner sign-off on the W1.4 pre-mortem, (c) backup.
-- Validated inside a rollback transaction on live before it is applied for real.
--
-- APPLY ORDER: 0026 → 0027 → 0028 → 0029. 0029 grants on working.record_visible_from,
-- which 0028 (the horizon repoint) creates — so 0029 applies AFTER 0028.

BEGIN;

-- ---------------------------------------------------------------------------
-- Roles (NOLOGIN — assumed via SET ROLE or a dedicated non-superuser connection,
-- never logged into directly).
-- ---------------------------------------------------------------------------
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='pass_refresher') THEN
    CREATE ROLE pass_refresher NOLOGIN;
  END IF;
END $$;

COMMENT ON ROLE pass_refresher IS
  'Sole writer of pass corpora (ADR-0045 §B refresher). Owns INSERT/UPDATE '
  'on working.walk_* + record_visible_from; reads canonical to compute '
  'base_version; attests each step to ops.audit_ledger. INERT while the app '
  'connects as the `ai` superuser — see 0029 header + W1.4 pre-mortem.';

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='pass_reader') THEN
    CREATE ROLE pass_reader NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='projection_refresher') THEN
    CREATE ROLE projection_refresher NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='horizon_reviewer') THEN
    CREATE ROLE horizon_reviewer NOLOGIN;
  END IF;
END $$;

COMMENT ON ROLE pass_reader IS
  'Agent read of the DERIVED pass corpus only (working.walk_run/walk_step/'
  'walk_step_retrieval). NO grant on canonical base tables — agents do not '
  'read working.normalized_record directly in the target state. INERT while '
  'the app connects as the `ai` superuser — see 0029 header + W1.4 pre-mortem.';

-- ---------------------------------------------------------------------------
-- Schema USAGE — without it, table-level grants are unreachable (a role must
-- have USAGE on a schema to access ANY object inside it). This is the
-- commonly-missed grant that makes the table grants below actually exercise.
-- ---------------------------------------------------------------------------
GRANT USAGE ON SCHEMA working, ops TO pass_refresher;  -- refresher reaches ops.audit_ledger
GRANT USAGE ON SCHEMA working TO pass_reader;          -- reader reaches only the pass corpus

-- ---------------------------------------------------------------------------
-- DEFAULT-DENY on the pass tables: PUBLIC gets nothing.
-- ---------------------------------------------------------------------------
REVOKE ALL ON TABLE
  working.walk_run, working.walk_step, working.walk_step_retrieval
  FROM PUBLIC;
REVOKE ALL ON TABLE working.record_visible_from FROM PUBLIC;

-- ---------------------------------------------------------------------------
-- pass_refresher — the §B sole writer.
-- ---------------------------------------------------------------------------
-- Read the canonical store to compute base_version (records + approved realizations).
GRANT SELECT ON TABLE
  working.normalized_record,
  working.realization_event,
  working.realization_event_record
  TO pass_refresher;
-- Sole writer of the pass corpus + the visible_from fast path.
GRANT SELECT, INSERT, UPDATE ON TABLE
  working.walk_run, working.walk_step, working.walk_step_retrieval
  TO pass_refresher;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE working.record_visible_from
  TO pass_refresher;
-- Attest each step to ops.audit_ledger (INSERT) + read the prior entry's prev_hash (SELECT).
-- The derivation engine calls audit.record(connection=...) inside its sole-writer txn,
-- so the refresher role must be able to append the attestation atomically.
GRANT SELECT, INSERT ON TABLE ops.audit_ledger TO pass_refresher;
-- Execute the visible_from / horizon_visible functions used in the slice SQL.
-- (Functions default to PUBLIC EXECUTE; stated explicitly so a future PUBLIC REVOKE
--  on the schema does not silently break the refresher.)
GRANT EXECUTE ON FUNCTION
  working.visible_from(UUID),
  working.horizon_visible(TEXT, TIMESTAMPTZ, TEXT, TEXT, TEXT, TIMESTAMPTZ, TEXT)
  TO pass_refresher;

-- ---------------------------------------------------------------------------
-- pass_reader — agent read of own pass corpus only.
-- ---------------------------------------------------------------------------
-- NOTE (open #2): without RLS this exposes ALL runs, not just the agent's own.
-- Per-agent scoping is app-layer until RLS is activated (also inert while superuser).
GRANT SELECT ON TABLE
  working.walk_run, working.walk_step, working.walk_step_retrieval
  TO pass_reader;
-- Readers do NOT get record_visible_from (refresher-maintained projection), canonical
-- base tables, or ops.audit_ledger. They read the pass corpus the refresher produced.

-- ---------------------------------------------------------------------------
-- 2026-08-18 held-draft amendment: complete default-deny object boundary.
-- ---------------------------------------------------------------------------
GRANT USAGE ON SCHEMA working, evidence, ops TO projection_refresher, horizon_reviewer;
GRANT USAGE ON SCHEMA evidence TO pass_refresher;

REVOKE ALL ON TABLE
  working.normalized_record_chunk,
  working.message_projection_route,
  working.conversation,
  working.message,
  working.message_participant,
  working.third_party_conversation,
  working.third_party_message,
  working.third_party_message_participant,
  working.third_party_conversation_acquisition,
  working.evidence_vector_projection_job,
  working.walk_checkpoint,
  working.walk_step_realization_retrieval,
  working.record_visible_from
  FROM PUBLIC;

-- The projection refresher writes only derived projections. It cannot author
-- normalized_record, acquisition, realization_event, entity, or person rows.
GRANT SELECT ON TABLE
  working.normalized_record, working.entity, working.person,
  evidence.acquisition, evidence.evidence_hash
  TO projection_refresher;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE
  working.normalized_record_chunk,
  working.message_projection_route,
  working.conversation,
  working.message,
  working.message_participant,
  working.third_party_conversation,
  working.third_party_message,
  working.third_party_message_participant,
  working.third_party_conversation_acquisition
  TO projection_refresher;
GRANT SELECT, INSERT, UPDATE ON TABLE working.evidence_vector_projection_job
  TO projection_refresher;
GRANT EXECUTE ON FUNCTION working.enqueue_evidence_vector_projection(UUID[], TEXT)
  TO projection_refresher;

-- Human review may transition proposed visibility decisions. Application code
-- remains responsible for the audited transition API; deferred constraints
-- enforce that an invalid approved projection cannot commit.
GRANT SELECT ON TABLE
  working.normalized_record, working.message_projection_route,
  working.conversation, working.message, working.message_participant,
  working.third_party_conversation, working.third_party_message,
  working.third_party_message_participant,
  working.third_party_conversation_acquisition,
  working.realization_event, working.realization_event_record,
  working.person, working.entity, evidence.acquisition
  TO horizon_reviewer;
GRANT UPDATE ON TABLE
  working.message_projection_route,
  working.third_party_conversation,
  working.third_party_message,
  working.third_party_message_participant,
  working.third_party_conversation_acquisition,
  working.realization_event
  TO horizon_reviewer;
GRANT SELECT, INSERT ON TABLE working.realization_event_record TO horizon_reviewer;
GRANT SELECT, INSERT ON TABLE ops.audit_ledger TO horizon_reviewer;
GRANT EXECUTE ON FUNCTION working.source_available_from(UUID) TO horizon_reviewer;

GRANT SELECT ON TABLE
  working.normalized_record_chunk,
  working.message_projection_route,
  working.third_party_conversation,
  working.third_party_message,
  working.third_party_conversation_acquisition,
  working.realization_event_record,
  evidence.acquisition,
  working.vw_horizon_atom,
  working.vw_walk_base_version_input
  TO pass_refresher;
GRANT SELECT, INSERT, UPDATE ON TABLE
  working.walk_checkpoint, working.walk_step_realization_retrieval
  TO pass_refresher;
GRANT SELECT ON TABLE
  working.walk_checkpoint, working.walk_step_realization_retrieval,
  working.vw_walk_contamination, working.vw_walk_delta
  TO pass_reader;

GRANT EXECUTE ON FUNCTION
  working.source_available_from(UUID),
  working.visible_from(UUID),
  working.horizon_record_visible(UUID,TIMESTAMPTZ,TEXT)
  TO pass_refresher;

COMMENT ON ROLE projection_refresher IS
  'Sole writer of derived chunks and mutually-exclusive first/third-party message projections; never an authored-source writer.';
COMMENT ON ROLE horizon_reviewer IS
  'Human-review transition role for route, acquisition-link, conversation, and realization approval state.';

COMMIT;
