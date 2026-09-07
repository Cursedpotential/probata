-- 0028_horizon_repoint.sql — repoint the LIVE horizon predicate to visible_from (W1.3 F1-resolution).
--
-- Byline: Claude Code . glm-5.2:cloud . 2026-08-14
-- Byline amendment: Codex GPT-5 . 2026-08-18
-- Byline amendment: Codex GPT-5 . 2026-08-18 (legacy-cache forward upgrade)
-- Supersession: the HELD draft's cached timestamp could become a stale allow.
-- This revision version-pins cached values, treats NULL as deny, and keeps
-- realization atoms separate from raw-source availability.
--
-- ✅ APPLIED TO PROD — verified live 2026-08-23 against 100.91.190.107:5432 db=ai by direct
--    introspection (Claude Code · Opus 5). record_visible_from and horizon_record_visible()
--    are PRESENT, and working.vw_spine_horizon's WHERE clause calls
--    working.horizon_record_visible(id, app.horizon, app.base_version) — which resolves
--    through working.source_available_from(). The knowledge_time predicate that 0008
--    disowned is GONE from the live view. The wrong-clock defect is fixed in production.
-- ~~⚠ HELD FOR OWNER — DRAFTED + ROLLBACK-VALIDATED 2026-08-14, NOT APPLIED TO PROD.~~  (historical)
-- ⚠ This is the LIVE-BEHAVIOR FLIP (the cutover from the superseded knowledge_time
--   predicate to the ADR-0045 §A visible_from clock). It DEPENDS on the F4 ruling
--   (bundled-doc degenerate visible_from: per-record occurred_at vs occurred_at_max).
--   The draft uses the CURRENT per-record working.visible_from() function; if F4
--   rules occurred_at_max, the function becomes bundle-aware BEFORE this applies.
--
-- WHAT THIS IS
-- ============
-- Wave 1.3 — the F1-resolution. The W1.1 pre-mortem (F1) deferred the
-- working.horizon_visible + working.vw_spine_horizon repoint from 0026 to W1.3,
-- "alongside the materialized pass corpus," because repointing the LIVE spine
-- view at per-row visible_from(r.id) (two correlated subqueries per row) BEFORE a
-- fast read path existed would put a slow correlated scan on every horizon query
-- and risk a prod meltdown if any reader bound early. The pass corpus
-- (working.walk_ledger, 0027) + the derivation engine now exist, so the
-- materialized fast path this migration ships is safe to bind.
--
-- The repoint: the spine view filters on `working.visible_from(r.id) <=
-- app.horizon` (the §A clock) instead of the superseded `r.knowledge_time <=
-- app.horizon` (0008:247 — records row-WRITE time, never a horizon input, ADR-0045
-- §A). `app.horizon` unset/empty = hindsight (whole case, including
-- hindsight-tagged rows); set = ignorant agent at that cutoff.
--
-- THE FAST PATH
-- =============
-- working.record_visible_from (record_id PK, visible_from, refreshed_at) is the
-- materialized projection of visible_from, maintained by the derivation engine's
-- refresher (sole writer, W1.4 grants). The repointed view LEFT JOINs to it and
-- uses COALESCE(rvf.visible_from, working.visible_from(r.id)) — FAST when the
-- refresher has materialized (an indexed equality lookup), CORRECT (function
-- fallback) when it has not. So correctness never depends on the refresh having
-- run; only speed does. This is the F1 mitigation: the slow per-row function
-- scan is the fallback, not the only path.
--
-- SAFETY (when eventually applied)
-- ===============================
-- This migration DOES replace an existing object (CREATE OR REPLACE VIEW
-- working.vw_spine_horizon) — it is the live-behavior change, NOT purely
-- additive. The old knowledge_time predicate is RETAINED on the
-- working.horizon_visible FUNCTION (left intact for any direct caller); only the
-- spine VIEW flips. Applied to LIVE only after (a) the F4 ruling, (b) owner
-- sign-off on this pre-mortem, (c) the refresher is wired to maintain
-- record_visible_from, (d) backup-before-apply. Validated inside a rollback
-- transaction on live before it is applied for real.

BEGIN;

-- ---------------------------------------------------------------------------
-- working.record_visible_from — the materialized fast path (sole-writer: refresher).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS working.record_visible_from (
    record_id    UUID PRIMARY KEY REFERENCES working.normalized_record(id) ON DELETE CASCADE,
    visible_from TIMESTAMPTZ,
    base_version TEXT NOT NULL,
    source_clock_hash TEXT NOT NULL CHECK (length(source_clock_hash)=64),
    refreshed_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Forward-upgrade the earlier three-column cache shape without trusting or
-- deleting its rows.  Legacy values have no base-version proof, so stamp them
-- with an explicit sentinel that horizon_record_visible refuses to consume.
ALTER TABLE working.record_visible_from
  ADD COLUMN IF NOT EXISTS base_version TEXT,
  ADD COLUMN IF NOT EXISTS source_clock_hash TEXT;

UPDATE working.record_visible_from
   SET base_version='__legacy_untrusted__',
       source_clock_hash=repeat('0',64)
 WHERE base_version IS NULL
    OR base_version=''
    OR source_clock_hash IS NULL
    OR length(source_clock_hash)<>64;

ALTER TABLE working.record_visible_from
  ALTER COLUMN visible_from DROP NOT NULL,
  ALTER COLUMN base_version SET NOT NULL,
  ALTER COLUMN source_clock_hash SET NOT NULL;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conrelid='working.record_visible_from'::regclass
       AND conname='record_visible_from_source_clock_hash_check'
  ) THEN
    ALTER TABLE working.record_visible_from
      ADD CONSTRAINT record_visible_from_source_clock_hash_check
      CHECK (length(source_clock_hash)=64);
  END IF;
END $$;

COMMENT ON TABLE working.record_visible_from IS
  'Materialized projection of working.visible_from (ADR-0045 §A) — the FAST path '
  'for the spine view. Sole writer = the derivation-engine refresher (W1.4 grants; '
  'pg_advisory_lock F13). A cached row is trusted only when its base_version '
  'matches app.base_version; otherwise the predicate recomputes from authored '
  'state. NULL source availability always denies. ';

-- ---------------------------------------------------------------------------
-- Repoint working.vw_spine_horizon to the visible_from clock + fast path.
-- ---------------------------------------------------------------------------
-- OLD (superseded, 0018): filtered on r.knowledge_time <= app.horizon.
-- NEW (ADR-0045 §A): filters on visible_from(r) <= app.horizon, via the
-- materialized fast path with a function fallback. app.horizon unset/empty =
-- hindsight (whole case incl. hindsight-tagged); set = ignorant (excludes
-- hindsight-tagged + anything whose visible_from is after the cutoff).
CREATE OR REPLACE FUNCTION working.horizon_record_visible(
  p_record_id UUID, p_horizon TIMESTAMPTZ, p_base_version TEXT DEFAULT NULL)
RETURNS BOOLEAN LANGUAGE sql STABLE PARALLEL SAFE AS $$
  SELECT COALESCE((
    SELECT CASE
      WHEN source_time IS NULL THEN false
      WHEN p_horizon IS NULL THEN true
      ELSE source_time<=p_horizon
    END
    FROM (
      SELECT CASE
        WHEN p_base_version IS NOT NULL
             AND rvf.base_version=p_base_version
             AND rvf.base_version<>'__legacy_untrusted__'
          THEN rvf.visible_from
        ELSE working.source_available_from(nr.id)
      END AS source_time
      FROM working.normalized_record nr
      LEFT JOIN working.record_visible_from rvf ON rvf.record_id=nr.id
      WHERE nr.id=p_record_id
    ) q
  ), false);
$$;

CREATE OR REPLACE VIEW working.vw_spine_horizon AS
SELECT r.*
  FROM working.normalized_record r
 WHERE r.case_id = coalesce(nullif(current_setting('app.case_id', true), ''), 'primary')
   AND working.horizon_record_visible(
         r.id,
         nullif(current_setting('app.horizon', true), '')::timestamptz,
         nullif(current_setting('app.base_version', true), ''))
   AND (
        nullif(current_setting('app.horizon', true), '') IS NULL
        OR r.disclosure_tier <> 'hindsight'
   );

COMMENT ON VIEW working.vw_spine_horizon IS
  'Spine filtered by the ADR-0045 §A horizon clock (visible_from), NOT the '
  'superseded knowledge_time. SET app.case_id / app.horizon / app.actor first. '
  'app.horizon unset/empty = hindsight (whole case incl. hindsight-tagged rows); '
  'set = ignorant agent at that cutoff (excludes hindsight-tagged + anything '
  'whose source_available_from is after the cutoff). Uses a base-version-pinned '
  'materialized fast path and fails closed for NULL availability. '
  'Repointed 2026-08-14 (0028); old knowledge_time predicate retired from the view.';

COMMENT ON FUNCTION working.horizon_record_visible(UUID,TIMESTAMPTZ,TEXT) IS
  'Fail-closed raw-source horizon predicate. A cache row is trusted only for the caller-pinned app.base_version; NULL availability denies even hindsight.';
COMMENT ON COLUMN working.record_visible_from.visible_from IS
  'Materialized source_available_from; NULL is an intentional fail-closed result, never an unknown allow.';
COMMENT ON COLUMN working.record_visible_from.base_version IS
  'Exact vw_walk_base_version_input digest for which this cached source clock was computed.';

COMMIT;
