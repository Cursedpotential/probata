-- 0019_reconcile_evidence_hash.sql — bring the numbered chain's
-- evidence.evidence_hash (5 columns, sql/0002) up to the live 15-column
-- shape (ADR-0034 multi-level custody hashing), applied out-of-band.
--
-- Byline: Claude Code . Fable 5 . 2026-08-09
--
-- WHY THIS EXISTS
-- ===============
-- The 2026-08-02 hashing audit (finding 1, HIGH — same audit that produced
-- ADR-0034/ADR-0045's provenance work) found custody.py depends on
-- evidence.evidence_hash columns (level, source_id, file_node_id,
-- member_hash_ids, canon_version, computed_by, ...) that NO numbered
-- migration creates: sql/0002_schema.sql only ever defined the original
-- 5-column shape (id, source_ref, algo, digest, hashed_at). The other 10
-- columns, plus custody_event/file_node/source, were applied directly to
-- the live database. That live shape is captured verbatim in
-- sql/_manual/20260802_reconcile_evidence_ddl.sql (pg_dump --schema-only,
-- 2026-08-02) — THIS migration is the promotion of that capture's
-- evidence_hash columns into the append-only numbered chain, so a fresh
-- bootstrap-free replay of 0001..0019 produces the same evidence_hash shape
-- the custody code actually requires.
--
-- SCOPE — evidence.evidence_hash ONLY:
--   * DDL only. No data. evidence.* stays append-only; custody.py remains
--     the sole writer of rows.
--   * sql/0002_schema.sql is NEVER edited — this is a new, additive file.
--   * evidence.source / evidence.file_node / evidence.custody_event are
--     OUT of scope here (still out-of-band; see sql/README.md's honesty
--     pass). The FK constraints below that reference them are added ONLY
--     when those tables are already present (checked at runtime), so this
--     migration is safe to run against BOTH a chain-only database (columns
--     land, FKs skipped) and the live database (everything already exists,
--     whole migration is a no-op).
--
-- IDEMPOTENT: every ADD COLUMN uses IF NOT EXISTS; every constraint/FK is
-- guarded by a pg_constraint existence check; every index uses
-- IF NOT EXISTS. Safe to run any number of times, in any DB that already
-- has some/all/none of these columns.

BEGIN;

-- ---------------------------------------------------------------------------
-- Columns — exact types/defaults from sql/_manual/20260802_reconcile_evidence_ddl.sql
-- ---------------------------------------------------------------------------
ALTER TABLE evidence.evidence_hash
    ADD COLUMN IF NOT EXISTS blob_key        TEXT,
    ADD COLUMN IF NOT EXISTS meta            JSONB NOT NULL DEFAULT '{}'::jsonb,
    ADD COLUMN IF NOT EXISTS level           TEXT NOT NULL DEFAULT 'H1'::text,
    ADD COLUMN IF NOT EXISTS source_id       UUID,
    ADD COLUMN IF NOT EXISTS file_node_id    UUID,
    ADD COLUMN IF NOT EXISTS md5_prefilter   BYTEA,
    ADD COLUMN IF NOT EXISTS record_locator  JSONB,
    ADD COLUMN IF NOT EXISTS member_hash_ids UUID[],
    ADD COLUMN IF NOT EXISTS canon_version   TEXT NOT NULL DEFAULT 'h1-rawbytes-v1'::text,
    ADD COLUMN IF NOT EXISTS computed_by     TEXT;

-- ---------------------------------------------------------------------------
-- Constraints — ALTER TABLE ADD CONSTRAINT has no IF NOT EXISTS, so guard
-- each by name against pg_constraint.
-- ---------------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
         WHERE conrelid = 'evidence.evidence_hash'::regclass
           AND conname  = 'evidence_hash_level_check'
    ) THEN
        ALTER TABLE evidence.evidence_hash
            ADD CONSTRAINT evidence_hash_level_check
            CHECK (level = ANY (ARRAY['H1'::text, 'H2'::text, 'H3'::text]));
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
         WHERE conrelid = 'evidence.evidence_hash'::regclass
           AND conname  = 'evidence_hash_subject_ck'
    ) THEN
        -- NOT VALID in the live capture — matched here verbatim; existing
        -- rows (there are none in a fresh chain-only DB) are not re-checked.
        ALTER TABLE evidence.evidence_hash
            ADD CONSTRAINT evidence_hash_subject_ck
            CHECK ((level = 'H3'::text) OR (source_id IS NOT NULL) OR (file_node_id IS NOT NULL))
            NOT VALID;
    END IF;
END $$;

-- FKs to evidence.source / evidence.file_node — those tables are out-of-band
-- (never created by the numbered chain; see sql/README.md). Only wire the FK
-- when the target already exists, so this migration does not fail on a
-- chain-only scratch database that never applied the out-of-band DDL.
DO $$
BEGIN
    IF to_regclass('evidence.source') IS NOT NULL
       AND NOT EXISTS (
        SELECT 1 FROM pg_constraint
         WHERE conrelid = 'evidence.evidence_hash'::regclass
           AND conname  = 'evidence_hash_source_id_fkey'
    ) THEN
        ALTER TABLE evidence.evidence_hash
            ADD CONSTRAINT evidence_hash_source_id_fkey
            FOREIGN KEY (source_id) REFERENCES evidence.source(id);
    END IF;
END $$;

DO $$
BEGIN
    IF to_regclass('evidence.file_node') IS NOT NULL
       AND NOT EXISTS (
        SELECT 1 FROM pg_constraint
         WHERE conrelid = 'evidence.evidence_hash'::regclass
           AND conname  = 'evidence_hash_file_node_id_fkey'
    ) THEN
        ALTER TABLE evidence.evidence_hash
            ADD CONSTRAINT evidence_hash_file_node_id_fkey
            FOREIGN KEY (file_node_id) REFERENCES evidence.file_node(id);
    END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Indexes — CREATE INDEX IF NOT EXISTS is natively idempotent.
-- idx_evidence_hash_digest already exists from sql/0002; left untouched.
-- ---------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_evhash_filenode
    ON evidence.evidence_hash (file_node_id);
CREATE INDEX IF NOT EXISTS idx_evhash_level_source
    ON evidence.evidence_hash (level, source_id);
CREATE INDEX IF NOT EXISTS idx_evhash_meta
    ON evidence.evidence_hash USING GIN (meta);

COMMIT;
