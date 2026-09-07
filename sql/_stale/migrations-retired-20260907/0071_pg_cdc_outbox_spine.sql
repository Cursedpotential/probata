-- 0071_pg_cdc_outbox_spine.sql -- ADR-0052 Part 1: the PG-CDC spine
-- (transactional per-table outbox + NOTIFY-as-wakeup + per-sink cursors +
-- dead-letter). PostgreSQL side ONLY; the drainer is Part 2 (Go/Temporal).
--
-- Byline: Claude Code · Opus 5 · 2026-09-04.
--
-- AUTHORITY
--   ADR-0052 (ACCEPTED, owner sign-off 2026-08-12 "sign 52"), Part 1.
--   D-054 -- all 8 owner rulings, notably:
--     (1) mechanism = transactional outbox + NOTIFY wakeup + per-sink cursors
--         (logical replication rejected; polling is a worker fallback only);
--     (2) outbox shape = PER-TABLE, never one shared working.ingest_event;
--     (4) FULL outbox row per write, TRIGGER-written -- "no commit without its
--         event" is enforced by the database, not by code-path convention;
--     (7) dead-letter TABLE + replay + mandatory alert on count > 0.
--   D-107 -- Temporal owns projection fan-out; **SurrealDB is
--     manual-promotion-only**: change detection may create only a promotion
--     CANDIDATE. Encoded below as a CHECK on working.cdc_sink, not a comment.
--   D-116 -- the reckoning: chunk = working.content_chunk only; the chat_chunk
--     family (and sql/0024's chat_chunk_event / chat_chunk_lane_event
--     outboxes) are deleted. This migration remaps 0024's never-applied intent
--     onto the post-reckoning source tables.
--   Owner order 2026-09-04 23:46: "I said build it... fix it."
--
-- WHAT ALREADY EXISTED (reused, NOT duplicated -- one authored spine):
--   working.content_chunk_projection       per-(chunk,sink) fresh-ingest
--                                          projection STATE. A sink-state
--                                          table, not an outbox. Untouched.
--   working.evidence_vector_projection_job vector-projection work queue
--                                          (owned by migration 0070).
--                                          Untouched.
--   canon.recompute_queue                  re-projection AFTER an approved
--                                          canon change (D-116: deliberately a
--                                          separate process from fresh
--                                          ingest). Untouched.
--   working.emit_chat_row_event()          sql/0024's trigger function, live
--                                          but ORPHAN: zero triggers reference
--                                          it and its target *_event tables
--                                          were never created live. Left in
--                                          place (never-delete rule);
--                                          superseded by
--                                          working.emit_row_event() below.
--
-- DELIBERATE SHAPE NOTES
--   * The outbox is APPEND-ONLY and carries NO per-row status/processed/error
--     columns. One event fans out to many sinks; per-sink progress is the
--     cursor (working.cdc_cursor) and per-sink failure is the dead-letter
--     (working.cdc_dead_letter). A status column on the event row would bake
--     one sink's progress into a shared event -- exactly what ADR-0052's
--     "subscribers hold their own cursors" forbids.
--   * The "pending predicate" is therefore event_id > cursor.last_event_id,
--     served by the outbox PRIMARY KEY; created_at is additionally indexed
--     because the worker reconstructs cross-table causal order from
--     (created_at, event_id) per ADR-0052 Part 1.
--   * ADR-0052 ruled AFTER INSERT OR UPDATE. DELETE is also captured here
--     (row_data from OLD) so a delete can never propagate as silence; the
--     operation CHECK admits all three.
--   * Horizon fields RIDE the event (occurred_at / knowledge_time /
--     disclosure_tier) and the spine NEVER filters by them -- ADR-0052
--     invariant 3, canon section 1. Extraction is not analysis.

BEGIN;

-- ---------------------------------------------------------------------------
-- 1 - Sink registry. Data, not an enum, so a sink is added without a migration.
--     The surrealdb row encodes D-107 structurally.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS working.cdc_sink (
  sink_id        TEXT PRIMARY KEY,
  description    TEXT NOT NULL,
  auto_drain     BOOLEAN NOT NULL DEFAULT TRUE,
  promotion_only BOOLEAN NOT NULL DEFAULT FALSE,
  registered_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  notes          TEXT,
  CONSTRAINT cdc_sink_drain_xor_promotion CHECK (NOT (auto_drain AND promotion_only)),
  -- D-107, structural: SurrealDB can never be an automatically drained sink.
  CONSTRAINT cdc_sink_surreal_is_promotion_only
    CHECK (sink_id <> 'surrealdb' OR (auto_drain = FALSE AND promotion_only = TRUE))
);
COMMENT ON TABLE working.cdc_sink IS
  'Subscribers of the ADR-0052 spine. auto_drain sinks are drained by the Part-2 worker; promotion_only sinks (surrealdb, D-107) may only have promotion CANDIDATES raised for an explicit owner decision -- Temporal executes and receipts that decision and MUST NOT infer it.';

INSERT INTO working.cdc_sink (sink_id, description, auto_drain, promotion_only, notes) VALUES
  ('weaviate',     'Project vector-store projection (ADR-0040, locked; dict filters ONLY on Weaviate).', TRUE,  FALSE, NULL),
  ('semantica',    'Semantica-originated Neo4j semantic graph (ADR-0043).',                              TRUE,  FALSE, NULL),
  ('sat_temporal', 'SAT-RAG temporal graph lane (sql/0055).',                                            TRUE,  FALSE, NULL),
  ('opensearch',   'Lexical/BM25 search projection (sql/0055).',                                         TRUE,  FALSE, NULL),
  ('extraction',   'Stage-2 extraction runner (ADR-0052 Part 3). Always extracts, regardless of custody-approval state (D-054 ruling 5).', TRUE, FALSE, NULL),
  ('surrealdb',    'Governed final temporal-graph / walk / analysis engine (D-073/D-080).',              FALSE, TRUE,
     'D-107: MANUAL PROMOTION ONLY. A drained event here is a promotion CANDIDATE, never a write to Surreal.')
ON CONFLICT (sink_id) DO NOTHING;

-- ---------------------------------------------------------------------------
-- 2 - Source registry. One row per (source table -> its own outbox table).
--     Cursors FK to this, so adding a lane never edits a CHECK list
--     (sql/0024's chat_cdc_cursor CHECK list was that mistake).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS working.cdc_source (
  event_table     TEXT PRIMARY KEY,
  source_schema   TEXT NOT NULL,
  source_table    TEXT NOT NULL,
  notify_channel  TEXT NOT NULL DEFAULT 'working_cdc',
  registered_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  notes           TEXT,
  UNIQUE (source_schema, source_table)
);
COMMENT ON TABLE working.cdc_source IS
  'The per-table outbox registry (D-054 ruling 2). event_table is always <source_table>_event in the same schema; event ids are table-local, so a cursor is always scoped to (sink_id, event_table).';

INSERT INTO working.cdc_source (event_table, source_schema, source_table, notes) VALUES
  ('context_record_event',    'working', 'context_record',    'ADR-0052 Phase 1: the AI-chat CONTEXT ingest spine.'),
  ('normalized_record_event', 'working', 'normalized_record', 'ADR-0052 Phase 2: the evidence spine (replaces the inline Weaviate write).'),
  ('content_chunk_event',     'working', 'content_chunk',     'D-116: THE chunk model. Feeds working.content_chunk_projection.'),
  ('chat_conversation_event', 'working', 'chat_conversation', 'Per-source conversation (D-116 vocabulary).'),
  ('chat_message_event',      'working', 'chat_message',      NULL),
  ('context_asset_event',     'working', 'context_asset',     'Materialization unit (ADR-0052 Part 3).')
ON CONFLICT (event_table) DO NOTHING;

-- ---------------------------------------------------------------------------
-- 3 - The per-table outboxes. Identical shape, separate IDENTITY sequences.
--     Do NOT use INCLUDING ALL / LIKE with identity: it would make otherwise
--     independent outboxes contend for one counter (sql/0024's own note).
-- ---------------------------------------------------------------------------
DO $outboxes$
DECLARE r RECORD;
BEGIN
  FOR r IN SELECT source_schema, source_table, event_table FROM working.cdc_source LOOP
    EXECUTE format($ddl$
      CREATE TABLE IF NOT EXISTS %I.%I (
        event_id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
        operation         TEXT NOT NULL CHECK (operation IN ('INSERT','UPDATE','DELETE')),
        source_pk         UUID NOT NULL,
        row_data          JSONB NOT NULL,
        source_generation BIGINT,
        occurred_at       TIMESTAMPTZ,
        knowledge_time    TIMESTAMPTZ,
        disclosure_tier   TEXT,
        xact_id           BIGINT NOT NULL,
        created_at        TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp()
      )$ddl$, r.source_schema, r.event_table);
    EXECUTE format(
      'CREATE INDEX IF NOT EXISTS %I ON %I.%I (created_at, event_id)',
      r.event_table || '_order_idx', r.source_schema, r.event_table);
    EXECUTE format(
      'CREATE INDEX IF NOT EXISTS %I ON %I.%I (source_pk)',
      r.event_table || '_source_pk_idx', r.source_schema, r.event_table);
    EXECUTE format($c$COMMENT ON TABLE %I.%I IS
      'ADR-0052 transactional outbox for %I.%I. APPEND-ONLY, full row per write, trigger-written in the SAME transaction as the data row. No status column by design: per-sink progress is working.cdc_cursor, per-sink failure is working.cdc_dead_letter. Horizon fields ride the event and are NEVER filtered here.'$c$,
      r.source_schema, r.event_table, r.source_schema, r.source_table);
  END LOOP;
END
$outboxes$;

-- ---------------------------------------------------------------------------
-- 4 - Per-sink cursors. A lane is rebuilt by resetting its cursor (ADR-0052
--     invariant 4) -- no schema change, no source re-ingest.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS working.cdc_cursor (
  sink_id            TEXT NOT NULL REFERENCES working.cdc_sink(sink_id) ON DELETE RESTRICT,
  source_event_table TEXT NOT NULL REFERENCES working.cdc_source(event_table) ON DELETE RESTRICT,
  last_event_id      BIGINT NOT NULL DEFAULT 0 CHECK (last_event_id >= 0),
  last_advanced_at   TIMESTAMPTZ,
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (sink_id, source_event_table)
);
COMMENT ON TABLE working.cdc_cursor IS
  'Durable per-sink, per-outbox cursor. The pending predicate is event_id > last_event_id. The cursor row is also the drain LOCK: working.cdc_claim_batch takes FOR UPDATE SKIP LOCKED on it, so two workers never drain one (sink, outbox) pair at once.';

-- ---------------------------------------------------------------------------
-- 5 - Dead letter (D-054 ruling 7). Full payload retained; nothing is ever
--     dropped. Alerting on the open count is MANDATORY on the Part-2 side.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS working.cdc_dead_letter (
  id                  UUID PRIMARY KEY DEFAULT uuidv7(),
  sink_id             TEXT NOT NULL REFERENCES working.cdc_sink(sink_id) ON DELETE RESTRICT,
  source_event_table  TEXT NOT NULL REFERENCES working.cdc_source(event_table) ON DELETE RESTRICT,
  source_event_id     BIGINT NOT NULL CHECK (source_event_id > 0),
  row_data            JSONB NOT NULL,
  error_class         TEXT NOT NULL,
  error_message       TEXT NOT NULL,
  attempts            INTEGER NOT NULL CHECK (attempts > 0),
  failed_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
  replay_requested_at TIMESTAMPTZ,
  resolved_at         TIMESTAMPTZ,
  resolution_note     TEXT,
  UNIQUE (sink_id, source_event_table, source_event_id),
  CHECK (resolved_at IS NULL OR resolved_at >= failed_at)
);
CREATE INDEX IF NOT EXISTS cdc_dead_letter_open_idx
  ON working.cdc_dead_letter (sink_id, failed_at) WHERE resolved_at IS NULL;
COMMENT ON TABLE working.cdc_dead_letter IS
  'Poison-pill quarantine (D-054 ruling 7). The cursor advances PAST a dead-lettered event so one bad row never stalls the lane; the replay tool drains this table after a fix. Alert on count(*) WHERE resolved_at IS NULL > 0 is mandatory.';

-- ---------------------------------------------------------------------------
-- 6 - The trigger function. Table-driven, so a new lane needs a row in
--     working.cdc_source + a CREATE TRIGGER, never a function edit.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION working.emit_row_event() RETURNS trigger
LANGUAGE plpgsql AS $fn$
DECLARE
  v_payload JSONB;
  v_channel TEXT := COALESCE(TG_ARGV[0], 'working_cdc');
  v_event_table TEXT := TG_TABLE_NAME || '_event';
BEGIN
  IF TG_OP = 'DELETE' THEN
    v_payload := to_jsonb(OLD);
  ELSE
    v_payload := to_jsonb(NEW);
  END IF;

  EXECUTE format(
    'INSERT INTO %I.%I (operation, source_pk, row_data, source_generation,'
    ' occurred_at, knowledge_time, disclosure_tier, xact_id)'
    ' VALUES ($1,$2,$3,$4,$5,$6,$7,$8)', TG_TABLE_SCHEMA, v_event_table)
  USING
    TG_OP,
    (v_payload ->> 'id')::UUID,
    v_payload,
    NULLIF(v_payload ->> 'source_generation', '')::BIGINT,
    NULLIF(v_payload ->> 'occurred_at', '')::TIMESTAMPTZ,
    NULLIF(v_payload ->> 'knowledge_time', '')::TIMESTAMPTZ,
    v_payload ->> 'disclosure_tier',
    pg_current_xact_id()::TEXT::BIGINT;

  -- NOTIFY is a WAKEUP, never the transport (ADR-0052 Part 1). Aggregate id
  -- only; the payload lives in the outbox row. A lost notification is healed
  -- by the worker timed poll -- the notification only buys latency.
  PERFORM pg_notify(v_channel, v_event_table || ':' || COALESCE(v_payload ->> 'id', ''));

  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END;
$fn$;
COMMENT ON FUNCTION working.emit_row_event() IS
  'ADR-0052 D-054 ruling 4: FULL outbox row per write, trigger-written, same transaction. Supersedes the orphaned working.emit_chat_row_event() (sql/0024, never wired live), which is retained under the never-delete rule.';

-- ---------------------------------------------------------------------------
-- 7 - The triggers. CREATE OR REPLACE TRIGGER (PG 14+) makes this idempotent.
-- ---------------------------------------------------------------------------
DO $triggers$
DECLARE r RECORD;
BEGIN
  FOR r IN SELECT source_schema, source_table, notify_channel FROM working.cdc_source LOOP
    EXECUTE format(
      'CREATE OR REPLACE TRIGGER %I AFTER INSERT OR UPDATE OR DELETE ON %I.%I'
      ' FOR EACH ROW EXECUTE FUNCTION working.emit_row_event(%L)',
      r.source_table || '_outbox', r.source_schema, r.source_table, r.notify_channel);
  END LOOP;
END
$triggers$;

-- ---------------------------------------------------------------------------
-- 8 - Helper functions. These ARE the drainer contract (Part 2 calls them;
--     it does not hand-roll the SQL).
-- ---------------------------------------------------------------------------

-- 8a - claim a pending batch. Locks the cursor row FOR UPDATE SKIP LOCKED, so
--      a second worker on the same (sink, outbox) pair gets zero rows instead
--      of a duplicate batch. Refuses a promotion_only sink unless the caller
--      explicitly opts in (p_allow_promotion_only) -- D-107.
CREATE OR REPLACE FUNCTION working.cdc_claim_batch(
  p_sink_id TEXT,
  p_event_table TEXT,
  p_limit INTEGER DEFAULT 100,
  p_allow_promotion_only BOOLEAN DEFAULT FALSE
) RETURNS TABLE (
  event_id BIGINT, operation TEXT, source_pk UUID, row_data JSONB,
  source_generation BIGINT, occurred_at TIMESTAMPTZ, knowledge_time TIMESTAMPTZ,
  disclosure_tier TEXT, created_at TIMESTAMPTZ
) LANGUAGE plpgsql AS $fn$
DECLARE
  v_schema TEXT;
  v_promotion_only BOOLEAN;
  v_last BIGINT;
BEGIN
  IF p_limit IS NULL OR p_limit < 1 OR p_limit > 10000 THEN
    RAISE EXCEPTION 'cdc_claim_batch: p_limit must be between 1 and 10000';
  END IF;

  SELECT s.source_schema INTO v_schema FROM working.cdc_source s WHERE s.event_table = p_event_table;
  IF v_schema IS NULL THEN
    RAISE EXCEPTION 'cdc_claim_batch: % is not a registered outbox (working.cdc_source)', p_event_table;
  END IF;

  SELECT k.promotion_only INTO v_promotion_only FROM working.cdc_sink k WHERE k.sink_id = p_sink_id;
  IF v_promotion_only IS NULL THEN
    RAISE EXCEPTION 'cdc_claim_batch: % is not a registered sink (working.cdc_sink)', p_sink_id;
  END IF;
  IF v_promotion_only AND NOT p_allow_promotion_only THEN
    -- D-107: SurrealDB and any other promotion_only sink is never drained into
    -- automatically. A caller that wants to RAISE PROMOTION CANDIDATES says so.
    RAISE EXCEPTION 'cdc_claim_batch: sink % is promotion_only (D-107); pass p_allow_promotion_only => TRUE and write a promotion CANDIDATE, never the sink itself', p_sink_id;
  END IF;

  INSERT INTO working.cdc_cursor (sink_id, source_event_table)
  VALUES (p_sink_id, p_event_table)
  ON CONFLICT (sink_id, source_event_table) DO NOTHING;

  SELECT c.last_event_id INTO v_last
    FROM working.cdc_cursor c
   WHERE c.sink_id = p_sink_id AND c.source_event_table = p_event_table
     FOR UPDATE SKIP LOCKED;

  IF NOT FOUND THEN
    RETURN;   -- another worker holds this lane
  END IF;

  RETURN QUERY EXECUTE format(
    'SELECT e.event_id, e.operation, e.source_pk, e.row_data, e.source_generation,'
    ' e.occurred_at, e.knowledge_time, e.disclosure_tier, e.created_at'
    ' FROM %I.%I e WHERE e.event_id > $1 ORDER BY e.event_id LIMIT $2', v_schema, p_event_table)
  USING v_last, p_limit;
END;
$fn$;
COMMENT ON FUNCTION working.cdc_claim_batch(TEXT,TEXT,INTEGER,BOOLEAN) IS
  'Part-2 drainer entry point. Claim = FOR UPDATE SKIP LOCKED on the cursor row for the whole batch; call working.cdc_ack in the SAME transaction.';

-- 8b - advance the cursor. Monotonic (GREATEST), never rewinds except via
--      cdc_reset_cursor, and idempotent: acking the same batch twice is a
--      no-op, because a Temporal Activity may be retried (AGENTS.md ATOMICITY
--      rule 3). Upserts the cursor row so a first-ack without a prior claim
--      (e.g. the dead-letter path below) self-heals instead of raising.
CREATE OR REPLACE FUNCTION working.cdc_ack(
  p_sink_id TEXT, p_event_table TEXT, p_last_event_id BIGINT
) RETURNS BIGINT LANGUAGE plpgsql AS $fn$
DECLARE v_new BIGINT;
BEGIN
  IF p_last_event_id IS NULL OR p_last_event_id < 0 THEN
    RAISE EXCEPTION 'cdc_ack: p_last_event_id must be >= 0';
  END IF;
  INSERT INTO working.cdc_cursor (sink_id, source_event_table, last_event_id, last_advanced_at)
  VALUES (p_sink_id, p_event_table, p_last_event_id, now())
  ON CONFLICT (sink_id, source_event_table) DO UPDATE
    SET last_event_id    = GREATEST(working.cdc_cursor.last_event_id, EXCLUDED.last_event_id),
        last_advanced_at = now(),
        updated_at       = now()
  RETURNING last_event_id INTO v_new;
  RETURN v_new;
END;
$fn$;
COMMENT ON FUNCTION working.cdc_ack(TEXT,TEXT,BIGINT) IS
  'Monotonic, idempotent cursor advance. Safe to retry: a re-ack of an already-acked batch changes nothing (GREATEST), which is what makes the Part-2 drainer a legal Temporal Activity.';

-- 8c - dead-letter one event and let the cursor pass it (D-054 ruling 7).
CREATE OR REPLACE FUNCTION working.cdc_dead_letter_event(
  p_sink_id TEXT, p_event_table TEXT, p_event_id BIGINT,
  p_row_data JSONB, p_error_class TEXT, p_error_message TEXT, p_attempts INTEGER
) RETURNS UUID LANGUAGE plpgsql AS $fn$
DECLARE v_id UUID;
BEGIN
  INSERT INTO working.cdc_dead_letter
    (sink_id, source_event_table, source_event_id, row_data, error_class, error_message, attempts)
  VALUES (p_sink_id, p_event_table, p_event_id, p_row_data, p_error_class, p_error_message, p_attempts)
  ON CONFLICT (sink_id, source_event_table, source_event_id) DO UPDATE
    SET attempts = EXCLUDED.attempts, error_class = EXCLUDED.error_class,
        error_message = EXCLUDED.error_message, failed_at = now()
  RETURNING id INTO v_id;
  PERFORM working.cdc_ack(p_sink_id, p_event_table, p_event_id);
  RETURN v_id;
END;
$fn$;

-- 8d - rebuild a lane: reset the cursor (ADR-0052 invariant 4).
CREATE OR REPLACE FUNCTION working.cdc_reset_cursor(
  p_sink_id TEXT, p_event_table TEXT, p_to_event_id BIGINT DEFAULT 0
) RETURNS BIGINT LANGUAGE plpgsql AS $fn$
DECLARE v_new BIGINT;
BEGIN
  INSERT INTO working.cdc_cursor (sink_id, source_event_table, last_event_id)
  VALUES (p_sink_id, p_event_table, p_to_event_id)
  ON CONFLICT (sink_id, source_event_table) DO UPDATE
    SET last_event_id = EXCLUDED.last_event_id, updated_at = now()
  RETURNING last_event_id INTO v_new;
  RETURN v_new;
END;
$fn$;
COMMENT ON FUNCTION working.cdc_reset_cursor(TEXT,TEXT,BIGINT) IS
  'Lane rebuild / contamination recovery. A reset is an audited operator act (ADR-0047) -- the caller writes the ledger row.';

-- ---------------------------------------------------------------------------
-- 9 - The cdc-status surface (D-054 ruling 7: lag + dead letters must be
--     visible or the dead-letter table is a black hole).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION working.cdc_lag()
RETURNS TABLE (
  sink_id TEXT, source_event_table TEXT, auto_drain BOOLEAN, promotion_only BOOLEAN,
  last_event_id BIGINT, max_event_id BIGINT, pending BIGINT,
  open_dead_letters BIGINT, last_advanced_at TIMESTAMPTZ
) LANGUAGE plpgsql AS $fn$
DECLARE r RECORD; v_max BIGINT;
BEGIN
  FOR r IN
    SELECT k.sink_id AS s, src.event_table AS et, src.source_schema AS sch,
           k.auto_drain AS ad, k.promotion_only AS po
      FROM working.cdc_sink k CROSS JOIN working.cdc_source src
  LOOP
    EXECUTE format('SELECT COALESCE(max(event_id),0) FROM %I.%I', r.sch, r.et) INTO v_max;
    sink_id := r.s; source_event_table := r.et; auto_drain := r.ad; promotion_only := r.po;
    last_event_id := NULL; last_advanced_at := NULL;
    SELECT c.last_event_id, c.last_advanced_at INTO last_event_id, last_advanced_at
      FROM working.cdc_cursor c WHERE c.sink_id = r.s AND c.source_event_table = r.et;
    last_event_id := COALESCE(last_event_id, 0);
    max_event_id := v_max;
    pending := GREATEST(v_max - last_event_id, 0);
    SELECT count(*) INTO open_dead_letters FROM working.cdc_dead_letter d
     WHERE d.sink_id = r.s AND d.source_event_table = r.et AND d.resolved_at IS NULL;
    RETURN NEXT;
  END LOOP;
END;
$fn$;
COMMENT ON FUNCTION working.cdc_lag() IS
  'Operator console cdc-status source. Alert when open_dead_letters > 0 (mandatory, D-054 ruling 7) and when pending grows monotonically for an auto_drain sink.';

-- ---------------------------------------------------------------------------
-- 10 - Grants. The Part-2 drainer runs as platform_worker.
-- ---------------------------------------------------------------------------
DO $grants$
DECLARE r RECORD;
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'platform_worker') THEN
    GRANT USAGE ON SCHEMA working TO platform_worker;
    GRANT SELECT ON working.cdc_sink, working.cdc_source TO platform_worker;
    GRANT SELECT, INSERT, UPDATE ON working.cdc_cursor, working.cdc_dead_letter TO platform_worker;
    FOR r IN SELECT source_schema, event_table FROM working.cdc_source LOOP
      EXECUTE format('GRANT SELECT ON %I.%I TO platform_worker', r.source_schema, r.event_table);
    END LOOP;
    GRANT EXECUTE ON FUNCTION
      working.cdc_claim_batch(TEXT,TEXT,INTEGER,BOOLEAN),
      working.cdc_ack(TEXT,TEXT,BIGINT),
      working.cdc_dead_letter_event(TEXT,TEXT,BIGINT,JSONB,TEXT,TEXT,INTEGER),
      working.cdc_lag()
      TO platform_worker;
  END IF;
END
$grants$;

-- ---------------------------------------------------------------------------
-- 11 - Post-conditions. The migration fails loudly rather than half-applying.
-- ---------------------------------------------------------------------------
DO $verify$
DECLARE v_missing TEXT;
BEGIN
  SELECT string_agg(src.source_schema || '.' || src.event_table, ', ') INTO v_missing
    FROM working.cdc_source src
   WHERE to_regclass(src.source_schema || '.' || src.event_table) IS NULL;
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION '0071: outbox table(s) missing: %', v_missing;
  END IF;

  SELECT string_agg(src.source_schema || '.' || src.source_table, ', ') INTO v_missing
    FROM working.cdc_source src
   WHERE NOT EXISTS (
     SELECT 1 FROM pg_trigger t
      WHERE t.tgrelid = (src.source_schema || '.' || src.source_table)::regclass
        AND t.tgname = src.source_table || '_outbox' AND NOT t.tgisinternal);
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION '0071: outbox trigger(s) missing on: %', v_missing;
  END IF;

  IF EXISTS (SELECT 1 FROM working.cdc_sink WHERE sink_id = 'surrealdb' AND (auto_drain OR NOT promotion_only)) THEN
    RAISE EXCEPTION '0071: D-107 violated -- surrealdb must be promotion_only and never auto_drain';
  END IF;
END
$verify$;

COMMIT;
