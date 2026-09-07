-- 0003_normalized_records.sql — evidence spine P2 (plans/logical-herding-forest.md)
--
-- 1. evidence.evidence_hash grows custody columns: where the write-once blob
--    landed (blob_key) and source metadata (meta). Additive, append-only.
-- 2. analysis.normalized_record — the canonical record every parser emits into
--    (message/call/event/media), carrying the BITEMPORAL substrate fields:
--    occurred_at (valid time), knowledge_time (when we learned it), and
--    disclosure_tier (contemporaneous | hindsight | discovered). The Part 2
--    knowledge-horizon replay filters on these (ADR/PROJECT_CANON §1).
--
-- Applied manually on the live DB (idempotent) AND kept here for fresh init.

ALTER TABLE evidence.evidence_hash ADD COLUMN IF NOT EXISTS blob_key TEXT;
ALTER TABLE evidence.evidence_hash ADD COLUMN IF NOT EXISTS meta JSONB NOT NULL DEFAULT '{}'::jsonb;

CREATE TABLE IF NOT EXISTS analysis.normalized_record (
  id UUID PRIMARY KEY DEFAULT uuidv7(),
  artifact_id UUID NOT NULL REFERENCES evidence.evidence_hash(id),
  record_type TEXT NOT NULL CHECK (record_type IN ('message','call','event','media')),
  source TEXT NOT NULL,                     -- parser/source key, e.g. 'chatgpt-export'
  conversation_id TEXT,
  role TEXT,                                -- sender / author role
  participants JSONB NOT NULL DEFAULT '[]'::jsonb,
  content TEXT NOT NULL DEFAULT '',
  occurred_at TIMESTAMPTZ,                  -- VALID TIME (when it happened)
  knowledge_time TIMESTAMPTZ NOT NULL DEFAULT NOW(),  -- when we learned it
  disclosure_tier TEXT NOT NULL DEFAULT 'contemporaneous'
    CHECK (disclosure_tier IN ('contemporaneous','hindsight','discovered')),
  attrs JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_normrec_artifact ON analysis.normalized_record(artifact_id);
CREATE INDEX IF NOT EXISTS idx_normrec_conv ON analysis.normalized_record(source, conversation_id);
CREATE INDEX IF NOT EXISTS idx_normrec_occurred ON analysis.normalized_record(occurred_at);
