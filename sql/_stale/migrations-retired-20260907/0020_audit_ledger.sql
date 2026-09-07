-- 0020_audit_ledger.sql — ops.audit_ledger: ONE append-only, hash-chained
-- record of every decision, action, modification, and READ (owner ruling
-- 2026-08-09, R-1: "every decision, every action, every modification, every
-- read — everything needs to be audited, with that information on my call").
--
-- ADR-0047 (docs/adr/0047-audit-everything-ledger.md, Accepted 2026-08-09,
-- D-042) is the ratified decision this migration implements. Pattern donors:
-- evidence.custody_event's hash chain (sql/bootstrap/schema_baseline.sql,
-- evidence.chain_custody_event) and sql/0017_append_only_guards.sql's
-- forbid-mutation trigger style.
--
-- Byline: Claude Code · Sonnet (agent) · 2026-08-09
--
--   id               bigint identity PK — insertion order IS chain order.
--   ts               when the ledger recorded the event (not necessarily
--                    when the underlying thing happened — see
--                    horizon_context for the knowledge-time axis).
--   actor            who/what did it (agent id, tool name, "owner", ...).
--   action_type      decision | write | read | tool_call | approval |
--                    derivation — the six kinds ADR-0047 names. TEXT+CHECK,
--                    never an enum (0016 rule: vocabularies evolve, ALTER
--                    TYPE rewrites everything).
--   object_schema    the schema the event concerns (e.g. 'evidence',
--                    'working'), when applicable. Nullable — a tool_call
--                    with no DB object has none.
--   object_ref       a reference into that schema (row id, custody_event id,
--                    approval id, ...) — NEVER the content itself.
--   horizon_context  JSONB: case_id/pass_id/horizon/actor, OR NULL for an
--                    explicit hindsight grant (ADR-0047 decision 1).
--   base_version     the version/generation this event was computed against
--                    (derivation provenance; nullable elsewhere).
--   payload_hash     sha256 of whatever payload this event carries — NEVER
--                    the raw payload (ADR-0047 decision 3: hashes/refs only,
--                    so the ledger is always safely dumpable).
--   prev_hash        the previous chain entry's entry_hash (NULL for the
--                    genesis row).
--   entry_hash       sha256(prev_hash || canonical-serialization(row)),
--                    computed by server/core/audit.py::record() — the ONLY
--                    insert path. UNLIKE evidence.custody_event's DB-trigger
--                    hash (evidence.chain_custody_event), this hash is
--                    computed in application code BEFORE insert, so the
--                    single writer (audit.record) can hold the chain-head
--                    lock across the read-prev/compute/insert sequence. The
--                    DB only enforces append-only; it does not compute or
--                    verify the hash on write (server/core/audit.py's
--                    verify_chain() does that, on demand and at startup).
--
-- Single-operator schema (owner ruling: never multi-user) — no user_id, no
-- tenant column beyond what horizon_context already carries for case_id.
--
-- Idempotent: safe to re-run against an existing DB (IF NOT EXISTS
-- throughout). NEVER edit this file once applied to a live DB — add 0021.

BEGIN;

CREATE SCHEMA IF NOT EXISTS ops;

CREATE TABLE IF NOT EXISTS ops.audit_ledger (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ts              TIMESTAMPTZ NOT NULL DEFAULT now(),
    actor           TEXT NOT NULL,
    action_type     TEXT NOT NULL
      CHECK (action_type IN ('decision', 'write', 'read', 'tool_call', 'approval', 'derivation')),
    object_schema   TEXT,
    object_ref      TEXT,
    horizon_context JSONB,
    base_version    BIGINT,
    payload_hash    TEXT,
    prev_hash       TEXT,
    entry_hash      TEXT NOT NULL
);

COMMENT ON TABLE ops.audit_ledger IS
  'ADR-0047 / D-042: ONE append-only, hash-chained ledger of every decision, '
  'action, modification, and READ. server/core/audit.py::record() is the '
  'sole writer. No raw case content — hashes and references only.';
COMMENT ON COLUMN ops.audit_ledger.horizon_context IS
  'case_id/pass_id/horizon/actor the event was performed under; NULL means '
  'an explicit hindsight grant (ADR-0047 decision 1).';
COMMENT ON COLUMN ops.audit_ledger.payload_hash IS
  'sha256 of the event payload. NEVER the raw payload — this ledger must '
  'always be safely dumpable (scripts/audit_dump.py).';
COMMENT ON COLUMN ops.audit_ledger.entry_hash IS
  'sha256(prev_hash || canonical-serialization(row business fields)), '
  'computed by server/core/audit.py::record() before insert (not a DB '
  'trigger — the chain-head lock is held in application code so appends '
  'serialize). server/core/audit.py::verify_chain() re-derives and checks.';

-- Append-only, unconditionally: corrections are new rows (0017 pattern).
-- Reuses working.forbid_mutation() rather than defining a duplicate
-- ops-local copy — the same cross-schema reuse ops.tool_call_ledger's own
-- tcl_append_only trigger already relies on (sql/bootstrap/schema_baseline.sql).
DROP TRIGGER IF EXISTS audit_ledger_append_only ON ops.audit_ledger;
CREATE TRIGGER audit_ledger_append_only
    BEFORE UPDATE OR DELETE ON ops.audit_ledger
    FOR EACH ROW EXECUTE FUNCTION working.forbid_mutation();

-- ---------------------------------------------------------------------------
-- Indexes — the retrieval axes scripts/audit_dump.py filters on.
-- ---------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_audit_ledger_ts
    ON ops.audit_ledger (ts);
CREATE INDEX IF NOT EXISTS idx_audit_ledger_action_ts
    ON ops.audit_ledger (action_type, ts);
CREATE INDEX IF NOT EXISTS idx_audit_ledger_actor_ts
    ON ops.audit_ledger (actor, ts);

COMMIT;
