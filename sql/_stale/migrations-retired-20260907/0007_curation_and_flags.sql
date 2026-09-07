-- 0007_curation_and_flags.sql — C3 operator-console additive migration on top
-- of sql/0006_run_gates_and_custody_tier.sql (NEVER edit 0001-0006 once
-- applied to a live DB — this is the new numbered migration instead).
--
-- analysis.corroboration_flag (operator-console-requirements.md addendum 6):
--   "flag events/claims as needing corroborating evidence" while reviewing —
--   the AI chats are the owner's STORY, not evidence; flags operationalize
--   the story->evidence map. Pure analysis-lane metadata: NEVER references
--   or mutates an evidence blob/hash directly (linked_artifacts is a jsonb
--   array of {artifact_id, sha256, note} pointers the operator attaches once
--   corroborating evidence is found — an informational cross-reference, not
--   a foreign key into evidence.evidence_hash, so a flag can point at
--   artifacts that don't exist yet in this DB, e.g. "need to subpoena X").
--
-- Curation columns (addendum 3 — "label/tag/retitle from the record browser
-- ... analysis/metadata lane ONLY"): server/evidence/store.py's
-- analysis.normalized_record (sql/0003_normalized_records.sql) has NO
-- title/labels columns and this migration deliberately does not add any —
-- see docs note below. Labels/titles route through the EXISTING
-- normalized_record.attrs jsonb (attrs['labels'] / attrs['title']), merged
-- via server/api/inspect_routes.py's PATCH /v1/records/{id}/meta. That is a
-- decision this migration makes, not a code change it makes.
--
-- DECISION (attrs vs new columns) — made by reading store.py/0003 first, per
-- the task's own instruction, before writing any DDL:
--   normalized_record already carries `attrs jsonb NOT NULL DEFAULT '{}'`
--   (sql/0003_normalized_records.sql:29) and store.py's parser-provenance
--   stamp (workflows.py's `_store_step_impl`, `rec.attrs.setdefault(...)`)
--   already treats attrs as the free-form per-record metadata bag. Adding
--   dedicated `title text` / `labels text[]` columns would (a) duplicate
--   that existing extension point, (b) require touching store_records()'s
--   fixed INSERT column list for a feature that only ever needs READ+jsonb-
--   merge from the curation route, and (c) buy nothing attrs jsonb ->>
--   doesn't already give a GIN index over (added below). Reusing attrs is
--   strictly additive/no-schema-churn and keeps store.py's insert path
--   untouched — exactly the "prefer reusing... over new columns" guidance.
--
-- Byline: Claude Code · Sonnet (agent) · 2026-07-22
--
-- Idempotent: safe to re-run against an existing DB (IF NOT EXISTS guards
-- throughout). NEVER edit this file (or 0001-0006) once applied to a live
-- DB — add a new numbered migration.

CREATE TABLE IF NOT EXISTS analysis.corroboration_flag (
  flag_id           uuid PRIMARY KEY DEFAULT uuidv7(),   -- PG18 native; timestamp-ordered
  target_kind       text NOT NULL
    CHECK (target_kind IN ('record','knowledge','run')),
  target_id         text NOT NULL,                        -- normalized_record.id / knowledge doc id / workflow_run.run_id (loose text — cross-schema, see note above)
  claim             text NOT NULL,                         -- the story claim being flagged ("X happened on...")
  claim_date_start  date,
  claim_date_end    date,
  evidence_wanted   text[],                                -- e.g. {sms,photo,call_log,financial,witness}
  status            text NOT NULL DEFAULT 'open'
    CHECK (status IN ('open','partial','corroborated','unobtainable')),
  linked_artifacts  jsonb NOT NULL DEFAULT '[]'::jsonb,     -- [{artifact_id, sha256, note}] — informational, not FK (see header)
  notes             text,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- Indexes
-- ---------------------------------------------------------------------------

-- The corroboration queue (C4, requirements addendum 6b) lists open/partial
-- flags newest-first — this is that page's primary access pattern.
CREATE INDEX IF NOT EXISTS idx_corroboration_flag_status
  ON analysis.corroboration_flag(status, created_at DESC);

-- "every flag on this record/doc/run" — the record-browser/knowledge-view
-- curation surfaces (addendum 3a: "flag action in every review view").
CREATE INDEX IF NOT EXISTS idx_corroboration_flag_target
  ON analysis.corroboration_flag(target_kind, target_id);

-- Curation (addendum 3): normalized_record.attrs already exists
-- (sql/0003_normalized_records.sql) — this is the ONLY new index this
-- migration adds against it, so PATCH /v1/records/{id}/meta's merged
-- attrs->>'labels' / attrs->>'title' are filterable/searchable without a
-- full-table scan. Additive; does not touch normalized_record's columns.
CREATE INDEX IF NOT EXISTS idx_normrec_attrs
  ON analysis.normalized_record USING gin (attrs);
