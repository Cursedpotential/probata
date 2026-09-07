-- 0022_context_assets.sql — working.context_archive + working.context_asset:
-- the CONTEXT-tier home for whole chat-export ARCHIVES and the generated
-- documents / code / images they carry.
--
-- WHY (owner, 2026-08-12): real chat exports arrive as a ZIP with the
-- conversation log PLUS sidecar metadata (users/projects/memories.json) and an
-- `assets/` folder of generated PDFs, images, markdown, and code — "whether or
-- not it's zipped or unzipped it's processed as a whole unit and ... the data
-- within it is properly parsed and saved." These two tables are where the
-- non-conversation data lands (conversations already live in
-- working.context_record, sql/0021).
--
-- OPTION B, again (owner pick, carried from D-048): these are SEPARATE context
-- tables, NOT the evidence-tier `working.artifact_registry`. artifact_registry
-- requires assertion_type / evidence_strength / review_status / is_sensitive —
-- it is part of the EVIDENCE spine, and routing context-chat assets through it
-- would breach the CONTEXT-never-EVIDENCE boundary (owner 2026-08-01), the same
-- reason context_record is separate from normalized_record. context_archive /
-- context_asset carry NO evidence FK and are referenced by NO evidence surface.
--
-- BLOBS: asset bytes live in R2 (the lakehouse); this table holds the INDEX
-- (r2_bucket/r2_key + content_hash), plus `content_inline` for small text
-- assets (md/py/sql/txt) so they are queryable without a fetch. content_hash
-- (sha256 of the bytes) is UNIQUE → idempotent re-materialization and natural
-- dedup across archives.
--
-- Applied manually on the live DB (idempotent). Regen the baseline after.
--
-- Byline: Claude Code · Opus 4.8 · 2026-08-12

CREATE TABLE IF NOT EXISTS working.context_archive (
  id UUID PRIMARY KEY DEFAULT uuidv7(),
  archive_path TEXT NOT NULL,                 -- source .zip (or folder) path
  archive_sha256 TEXT NOT NULL,               -- of the archive bytes — dedup / idempotent re-ingest
  provider TEXT,                              -- chatgpt | claude | perplexity | ... (from detection)
  conversation_log_count INTEGER NOT NULL DEFAULT 0,
  asset_count INTEGER NOT NULL DEFAULT 0,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,  -- users/projects/memories.json contents
  manifest JSONB NOT NULL DEFAULT '{}'::jsonb,  -- full classified inventory
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT uq_ctxarchive_sha UNIQUE (archive_sha256)
);

CREATE TABLE IF NOT EXISTS working.context_asset (
  id UUID PRIMARY KEY DEFAULT uuidv7(),
  archive_id UUID REFERENCES working.context_archive(id),
  member_path TEXT NOT NULL,                  -- path of the asset inside the archive
  asset_category TEXT NOT NULL                -- routed class (owner: docs->doc store, code->code store)
    CHECK (asset_category IN ('document','code','image','data','other')),
  file_ext TEXT,
  content_hash TEXT NOT NULL,                 -- sha256 of the bytes — dedup key + R2 object name
  byte_size BIGINT,
  r2_bucket TEXT,                             -- where the blob was written (NULL until materialized)
  r2_key TEXT,
  content_inline TEXT,                        -- small text assets stored inline (md/py/sql/txt)
  conversation_id TEXT,                       -- link to a working.context_record conversation, if known
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT uq_ctxasset_hash UNIQUE (content_hash)
);

CREATE INDEX IF NOT EXISTS idx_ctxasset_archive ON working.context_asset (archive_id);
CREATE INDEX IF NOT EXISTS idx_ctxasset_category ON working.context_asset (asset_category);
CREATE INDEX IF NOT EXISTS idx_ctxasset_conv ON working.context_asset (conversation_id);

COMMENT ON TABLE working.context_archive IS
  'CONTEXT-tier record of a whole chat-export archive (owner 2026-08-12: process the zip as a whole unit). Separate from the evidence spine (no evidence FK). See server/analysis/chat_archive.py + sql/0021.';
COMMENT ON TABLE working.context_asset IS
  'CONTEXT-tier index of generated docs/code/images from a chat-export archive; bytes in R2 (r2_key), small text inline. Option B: NOT the evidence-tier artifact_registry (CONTEXT-never-EVIDENCE boundary). content_hash UNIQUE = idempotent materialization.';
