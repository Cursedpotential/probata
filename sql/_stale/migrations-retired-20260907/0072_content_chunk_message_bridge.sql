-- 0072_content_chunk_message_bridge.sql -- H-04: the chunk<->message bridge.
--
-- Byline: Claude Code · Opus 5 · 2026-09-05.
--
-- AUTHORITY
--   D-116 (the reckoning) -- chunk = working.content_chunk ONLY.  Migration
--     0058_the_reckoning.sql:97 DROPPED working.normalized_record_chunk; every
--     reader that still named it has been reading a table that does not exist.
--     Verified live 2026-09-05: to_regclass('working.normalized_record_chunk')
--     IS NULL on db `platform`.
--   Q9 (owner ruling, 2026-09-05) -- the bridge between the context chunk spine
--     (working.content_chunk: generation_id / source_version_id /
--     derivation_mode) and the evidence message spine
--     (working.normalized_record) is a SEPARATE append-only association table
--     working.content_chunk_message(chunk_id, message_id, is_center, position).
--     No column is added to the message row (D-136: message content and
--     timestamps are immutable and are never widened for a projection need).
--   H-04 -- chunk-model reconciliation; the deferred item named in
--     sql/0065_repair_validate_message_projection_person_home.sql:13.
--   2026-08-29 dual-graph rule -- every projection row carries the PostgreSQL
--     source coordinate (normalized_record_id + content_chunk_id).  The bridge
--     is what makes that coordinate derivable at all.
--   D-124 -- content_sha256 is INTEGRITY, never custody.  This table stores no
--     digest and asserts no custody.
--   D-130 -- one unit, one job.  The future writer is the Go message-window
--     chunker Activity (redesign plan Stage 3); the Python chunk writer is
--     retired in the same change.
--
-- SAFETY
--   All target tables are EMPTY live (verified 2026-09-05: content_chunk 0,
--   normalized_record 0, evidence_vector_projection_job 0,
--   content_chunk_generation 0).  Nothing to backfill; no rewrite of existing
--   rows is possible.  DDL is idempotent and safe to re-run.

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. The bridge.
-- ---------------------------------------------------------------------------
-- Append-only: rows are inserted by the chunker Activity and never rewritten.
-- UPDATE is refused by the trigger below.  DELETE is reachable only by CASCADE
-- from a deleted parent chunk or message -- deliberately, so a rebuilt
-- generation does not strand association rows.
CREATE TABLE IF NOT EXISTS working.content_chunk_message (
  chunk_id   UUID        NOT NULL,
  message_id UUID        NOT NULL,
  is_center  BOOLEAN     NOT NULL DEFAULT FALSE,
  position   INTEGER     NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT content_chunk_message_pkey PRIMARY KEY (chunk_id, message_id),
  CONSTRAINT content_chunk_message_position_check CHECK (position >= 0),
  CONSTRAINT content_chunk_message_chunk_fk
    FOREIGN KEY (chunk_id) REFERENCES working.content_chunk(id) ON DELETE CASCADE,
  CONSTRAINT content_chunk_message_message_fk
    FOREIGN KEY (message_id) REFERENCES working.normalized_record(id) ON DELETE CASCADE
);

-- Reverse lookup: "which chunks cover this message" is the enqueue path.
CREATE INDEX IF NOT EXISTS content_chunk_message_message_idx
  ON working.content_chunk_message (message_id);

-- Window integrity, derived from what a message-window chunk IS: positions
-- inside one window are distinct, and a window has at most one centre message.
-- Neither index requires a centre to exist (a composed or unverified_derived
-- chunk may legitimately have none).
CREATE UNIQUE INDEX IF NOT EXISTS content_chunk_message_position_uq
  ON working.content_chunk_message (chunk_id, position);
CREATE UNIQUE INDEX IF NOT EXISTS content_chunk_message_center_uq
  ON working.content_chunk_message (chunk_id) WHERE is_center;

COMMENT ON TABLE working.content_chunk_message IS
  'Q9/H-04 bridge: append-only association between working.content_chunk (context spine) '
  'and working.normalized_record (evidence message spine). is_center marks the window '
  'centre, which is the PG source coordinate a projection row carries (2026-08-29 '
  'dual-graph rule). Writer: the Go message-window chunker Activity. No digest, no '
  'custody claim (D-124). Never widen the message row for this (D-136).';

CREATE OR REPLACE FUNCTION working.content_chunk_message_no_mutate()
RETURNS trigger LANGUAGE plpgsql AS $fn$
BEGIN
  RAISE EXCEPTION
    'working.content_chunk_message is append-only: insert a new row instead of editing an association';
END
$fn$;

DROP TRIGGER IF EXISTS content_chunk_message_no_mutate ON working.content_chunk_message;
CREATE TRIGGER content_chunk_message_no_mutate
  BEFORE UPDATE ON working.content_chunk_message
  FOR EACH ROW EXECUTE FUNCTION working.content_chunk_message_no_mutate();

-- Grants mirror working.content_chunk (verified live 2026-09-05), plus the
-- projection drain role, which must join the bridge to resolve a job's message.
GRANT SELECT, INSERT ON working.content_chunk_message TO platform_runtime;
GRANT SELECT ON working.content_chunk_message TO context_review_adjudicator;
GRANT SELECT ON working.content_chunk_message TO projection_refresher;
GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON working.content_chunk_message TO platform_app;

-- ---------------------------------------------------------------------------
-- 2. Re-anchor the vector-projection queue on the surviving chunk table.
-- ---------------------------------------------------------------------------
-- working.evidence_vector_projection_job.chunk_id lost its foreign key when
-- 0058 dropped normalized_record_chunk (verified live 2026-09-05: zero
-- contype='f' constraints on the table).  The queue is EMPTY, so the constraint
-- can be added without validation risk.
DO $reanchor$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conrelid = 'working.evidence_vector_projection_job'::regclass
       AND conname  = 'evidence_vector_projection_job_chunk_fk'
  ) THEN
    ALTER TABLE working.evidence_vector_projection_job
      ADD CONSTRAINT evidence_vector_projection_job_chunk_fk
      FOREIGN KEY (chunk_id) REFERENCES working.content_chunk(id) ON DELETE CASCADE;
  END IF;
END
$reanchor$;

-- ---------------------------------------------------------------------------
-- 3. The enqueue function selects chunks through the bridge.
-- ---------------------------------------------------------------------------
-- Same signature, same ON CONFLICT requeue semantics (generation bump, reason
-- overwrite, lock/completion reset) as the baseline version at
-- sql/bootstrap/schema_baseline_20260830.sql:6868-6883; only the source of
-- chunk ids changes from the dropped table to the bridge.
CREATE OR REPLACE FUNCTION working.enqueue_evidence_vector_projection(p_record_ids uuid[], p_reason text)
RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE queued INTEGER;
BEGIN
  IF p_reason IS NULL OR length(trim(p_reason))=0 THEN
    RAISE EXCEPTION 'VECTOR_PROJECTION_REASON_REQUIRED';
  END IF;
  INSERT INTO working.evidence_vector_projection_job(chunk_id, reason)
  SELECT DISTINCT bridge.chunk_id, p_reason
    FROM working.content_chunk_message bridge
   WHERE bridge.message_id=ANY(p_record_ids)
  ON CONFLICT (chunk_id, projection_version) DO UPDATE
    SET reason=EXCLUDED.reason, status='pending', generation=working.evidence_vector_projection_job.generation+1,
        next_attempt_at=now(),
        locked_at=NULL, locked_by=NULL, completed_at=NULL, updated_at=now();
  GET DIAGNOSTICS queued = ROW_COUNT;
  RETURN queued;
END $function$;

GRANT EXECUTE ON FUNCTION working.enqueue_evidence_vector_projection(uuid[], text)
  TO projection_refresher, platform_app;

-- ---------------------------------------------------------------------------
-- 4. Verify.
-- ---------------------------------------------------------------------------
DO $verify$
BEGIN
  IF to_regclass('working.content_chunk_message') IS NULL THEN
    RAISE EXCEPTION '0072: working.content_chunk_message missing';
  END IF;
  IF to_regclass('working.normalized_record_chunk') IS NOT NULL THEN
    RAISE EXCEPTION '0072: working.normalized_record_chunk still exists -- D-116 not settled here';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conrelid='working.evidence_vector_projection_job'::regclass
       AND conname='evidence_vector_projection_job_chunk_fk') THEN
    RAISE EXCEPTION '0072: evidence_vector_projection_job.chunk_id was not re-anchored';
  END IF;
  IF position('content_chunk_message' in
        pg_get_functiondef('working.enqueue_evidence_vector_projection(uuid[],text)'::regprocedure)) = 0 THEN
    RAISE EXCEPTION '0072: enqueue function does not select through the bridge';
  END IF;
  IF position('normalized_record_chunk' in
        pg_get_functiondef('working.enqueue_evidence_vector_projection(uuid[],text)'::regprocedure)) > 0 THEN
    RAISE EXCEPTION '0072: enqueue function still references the dropped chunk table';
  END IF;
END
$verify$;

COMMIT;
