-- 0021_context_record.sql — working.context_record: the PG SOURCE OF TRUTH for
-- AI-chat CONTEXT ingest, and the change-detection origin that feeds the
-- `platform_context` Weaviate collection + the Graphiti CASE lane.
--
-- WHY THIS EXISTS (owner ruling, 2026-08-12, verbatim): "it's all supposed to
-- go back into pg And then change detection will move it into vector db" —
-- i.e. EVERY ingest path writes Postgres FIRST (source of truth), and Weaviate
-- is populated downstream by reading pending rows back out of PG. Before this
-- migration, server/analysis/context_chat_ingest.py wrote AI-chat chunks
-- DIRECTLY to Weaviate + Graphiti and deliberately never touched Postgres
-- (its docstring: "no store_records (no normalized_record)"). That direct
-- dual-write is what this table replaces.
--
-- OPTION B (owner pick, 2026-08-12): a SEPARATE context table rather than
-- reusing working.normalized_record. The reason is the hard evidence/context
-- boundary (owner, 2026-08-01: "AI chats are CONTEXT, never EVIDENCE"):
--   * normalized_record REQUIRES artifact_id -> evidence.evidence_hash(id)
--     (a custody-chained blob). Chats have no custody artifact, and forcing
--     one would drag chat text into the evidence spine — the exact thing the
--     boundary forbids.
--   * context_record has NO evidence FK and is referenced by NO evidence view,
--     function, or approval-gated surface. That absence IS the boundary: a
--     chat can never become reachable through an evidence-only read path,
--     while PG still holds the canonical copy the owner's model requires.
--
-- GRAIN: one row per message (mirrors normalized_record's grain), NOT per
-- Weaviate chunk. Chunking stays a property of the vector-population step
-- (sync_pending_context() reads records back, groups by conversation, chunks,
-- writes) exactly as evidence/store.py stores records and re-renders at
-- ingest_into_knowledge() time. The relational home is canonical records; the
-- vector store is a derived, rebuildable projection.
--
-- CHANGE DETECTION: the two *_synced_at columns ARE the signal. NULL = pending
-- for that sink; a non-null stamp = already projected. The consumer is a plain
-- "SELECT ... WHERE weaviate_synced_at IS NULL" (partial-indexed below) — no
-- outbox/trigger/cursor spine yet (that stays deferred, ADR-0051 / DEBT), but
-- the seam is already CDC-shaped: a future worker/cron wraps the same query
-- with zero schema change. This moves the "already sent" source of truth out
-- of the old local SQLite IngestLedger and INTO Postgres, per the ruling.
--
-- IDEMPOTENCY: content_hash is UNIQUE, so re-ingesting the same export is an
-- INSERT ... ON CONFLICT (content_hash) DO NOTHING — the DB is the dedup
-- authority, not a side-car ledger. Re-running a parse never double-writes.
--
-- Applied manually on the live DB (idempotent) AND kept here for the record.
-- Per sql/README.md the numbered chain is history, not a replay path; regen
-- sql/bootstrap/schema_baseline.sql after applying this.
--
-- Byline: Claude Code · Opus 4.8 · 2026-08-12

CREATE TABLE IF NOT EXISTS working.context_record (
  id UUID PRIMARY KEY DEFAULT uuidv7(),
  -- NO artifact_id / NO evidence FK — deliberate (see header). Standalone.
  record_type TEXT NOT NULL DEFAULT 'message'
    CHECK (record_type IN ('message','call','event','media')),
  source TEXT NOT NULL,                     -- parser/source key, e.g. 'chatgpt-official-json'
  conversation_id TEXT,
  conversation_title TEXT,                  -- carried for chunk rendering / provenance
  role TEXT,                                -- author role (user / assistant / ...)
  participants JSONB NOT NULL DEFAULT '[]'::jsonb,
  content TEXT NOT NULL DEFAULT '',
  occurred_at TIMESTAMPTZ,                  -- VALID TIME (message timestamp)
  knowledge_time TIMESTAMPTZ NOT NULL DEFAULT NOW(),  -- when we learned it
  disclosure_tier TEXT NOT NULL DEFAULT 'contemporaneous'
    CHECK (disclosure_tier IN ('contemporaneous','hindsight','discovered')),
  lane TEXT NOT NULL DEFAULT 'context'      -- ADR-0050 vocabulary; always 'context' on this table
    CHECK (lane = 'context'),
  content_hash TEXT NOT NULL,               -- sha256(source:conversation_id:role:occurred_at:content) — dedup key
  attrs JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  -- CDC signal: NULL = pending projection into that sink; timestamp = done.
  weaviate_synced_at TIMESTAMPTZ,
  graphiti_synced_at TIMESTAMPTZ,
  CONSTRAINT uq_ctxrec_content_hash UNIQUE (content_hash)
);

-- Access paths we actually query:
CREATE INDEX IF NOT EXISTS idx_ctxrec_conv
  ON working.context_record (source, conversation_id);
CREATE INDEX IF NOT EXISTS idx_ctxrec_occurred
  ON working.context_record (occurred_at);
-- Change-detection consumers: partial indexes over ONLY the pending rows, so
-- the "what still needs projecting?" scan stays cheap as the table grows.
CREATE INDEX IF NOT EXISTS idx_ctxrec_weaviate_pending
  ON working.context_record (conversation_id)
  WHERE weaviate_synced_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_ctxrec_graphiti_pending
  ON working.context_record (conversation_id)
  WHERE graphiti_synced_at IS NULL;

COMMENT ON TABLE working.context_record IS
  'PG source of truth for AI-chat CONTEXT ingest (owner ruling 2026-08-12: PG first, change-detection projects to Weaviate). Standalone by design — NO evidence FK, referenced by NO evidence surface — which is the CONTEXT-never-EVIDENCE boundary (owner 2026-08-01). *_synced_at NULL = pending projection. See server/analysis/context_chat_ingest.py + ADR-0051.';
