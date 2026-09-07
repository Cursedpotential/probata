-- 0016_working_gate_layer.sql — the extraction gate inside `working`:
-- machine candidates, human review, labelled promotion.
--
-- Byline: Claude Code · Opus 5 · 2026-08-01 (drafted as 0008_working_schema.sql)
--         renumbered + adapted to the post-0014 layout · Claude Code · Fable 5 · 2026-08-02
--
-- WHY THIS EXISTS
-- ===============
-- Owner ruling 2026-08-01: "there's gonna be raw, then there's going to be
-- working tables, and then there's going to be the gated evidence."
--
-- HISTORY OF THIS FILE: drafted 2026-08-01 as `0008_working_schema.sql`, before
-- sql/0014 split the old `analysis` schema and CREATED `working` (spine,
-- projections, links, resolved entities). That made this draft's number collide
-- with the applied 0008_temporal_clocks_and_provenance.sql and its premise
-- ("nothing between raw and court-facing") stale. Renumbered to 0016 and
-- adapted 2026-08-02; the DESIGN is unchanged. DEPENDS ON 0014 having run.
--
-- The layout this migration lands in:
--
--   evidence.raw_*   as-ingested, immutable        (raw_sms alone holds 14,107 rows)
--   working.*        derived working set (0014):   spine normalized_record,
--                    projections, links, resolved entities — plus, from THIS
--                    migration, the extraction gate below
--   analysis.*       human-gated conclusions only  (findings, labels, decisions)
--   reference.*      hand-curated taxonomy
--
-- Anything an LLM or NER pass inferred must be HUMAN-APPROVED before it can be
-- cited. Extractors write CANDIDATES here. A review pass approves, rejects, or
-- supersedes them. Only approved rows are promoted — into the resolved
-- `working.*` entity tables, the gated `analysis.*` conclusions, and onward to
-- SurrealDB / the Semantica graph / Graphiti, each crossing labelled by lane.
--
-- SUPERSEDES (structurally, not by deletion): `working.extraction_candidate`
-- and `working.record_observation` — the 0014-era staging placeholders, both
-- verified 0 rows live on 2026-08-02. They stay in place per the never-delete
-- rule; the candidate_* family below is the richer replacement. COMMENTs are
-- stamped on them at the end of this file.
--
-- DESIGN NOTES
-- ------------
-- * Additive only. This migration creates a NEW schema and touches nothing in
--   evidence.* or analysis.*. It cannot affect existing data.
-- * Provenance is mandatory, not optional: every candidate carries the raw
--   table + row it came from, and the extraction run that produced it. A
--   candidate that cannot be traced back to source is not admissible, so the
--   columns are NOT NULL rather than nullable-and-hopefully-populated.
-- * review_state is TEXT + CHECK, not an ENUM: review vocabularies are business
--   logic and evolve; altering an enum in place is a migration hazard.
-- * uuidv7() (native in PG18) gives time-ordered keys — candidates from one
--   extraction run cluster on disk, which is exactly the access pattern the
--   review UI has (fetch a run's pending items).
-- * Timeline validity uses tstzrange + GiST so "what did we believe was true
--   as of date X" is answerable, and overlapping claims are detectable.
--
-- THE TWO PASSES (owner design, 2026-08-01 14:20-14:34)
-- ----------------------------------------------------
-- Crossing the gate is not one destination. Owner: "there's the strictly as-it-
-- happened analysis that doesn't have the hindsight that is the human
-- experience, and then there's the hindsight analysis that shows the
-- manipulation and the lies and the deceit and what really happened."
--
--   as_lived      Graphiti      keyed on realized_at    what you BELIEVED, when
--   hindsight     Semantica/Neo4j keyed on occurred_at  what was ACTUALLY true
--   consolidated  SurrealDB     keyed on the DELTA      where manipulation worked
--
-- The routing rule is load-bearing and counter-intuitive: the as-lived lane is
-- keyed on realized_at, NOT on acquisition. You can hold a file for two years
-- without reading it; your belief state changed when you understood it, not
-- when the bytes arrived. Injecting late-acquired knowledge into the as-lived
-- record erases the belief state, and the manipulation becomes invisible.
--
-- The gap between "what I knew then" and "what was actually true" is not a
-- discrepancy to reconcile. It is the finding.
--
-- SIX CLOCKS (owner, 2026-08-01 14:28 — discovery_produced_at was REMOVED)
-- ------------------------------------------------------------------------
-- A seventh, discovery_produced_at, was proposed and killed the same session:
-- this corpus came from hand-me-down household devices, not legal process.
-- Do not re-add it.
--
--   Event     occurred_at         when it was sent
--   Artifact  export_created_at   when the backup was taken (COMPLETENESS BOUND:
--                                 a March backup cannot hold April messages, so
--                                 two exports with a window between them mean
--                                 missing coverage)
--             acquired_at         when the file entered possession
--             ingested_at         when the platform loaded it
--   Knowledge realized_at         when its significance was understood
--             transaction_time    when the row was written
--
-- Provenance is a SEPARATE block, not a clock (owner 14:27: "that's going to be
-- a legal argument issue, add provenance or how it was acquired as a followup
-- field"). It is HITL-only, never model-inferred, and append-only: if the
-- account of acquisition changes that is a new row, never an edit. `unclear`
-- is a first-class value — if every option is a justification, weak provenance
-- gets laundered into strong-sounding labels.

BEGIN;

-- Schema exists since 0014; this guard only matters on a fresh database.
CREATE SCHEMA IF NOT EXISTS working;

-- Merges 0014's description (derived working set) with this layer's (the gate).
COMMENT ON SCHEMA working IS
  'Derived working set (0014: spine, projections, links, resolved entities — '
  'rebuilt by re-deriving from evidence.raw_* without touching originals) plus '
  'the extraction gate (0016: machine-extracted CANDIDATES awaiting human '
  'review). Never court-facing; if it disagrees with evidence, evidence wins. '
  'Promotion of candidates requires an approved review_decision.';

-- Shared vocabulary. Kept as CHECK constraints (see design notes) and repeated
-- per table rather than a domain, so a future table can diverge without an
-- ALTER DOMAIN that rewrites everything.
--   pending     — extracted, not yet looked at
--   approved    — human confirmed; eligible for promotion
--   rejected    — human says wrong; retained for audit + model feedback
--   needs_info  — cannot decide without more source material
--   superseded  — replaced by a later, better candidate

-- ---------------------------------------------------------------------------
-- extraction_run — one row per extraction pass. The provenance root.
-- ---------------------------------------------------------------------------
CREATE TABLE working.extraction_run (
    id                UUID PRIMARY KEY DEFAULT uuidv7(),
    started_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    finished_at       TIMESTAMPTZ,
    -- What produced these candidates. Version matters: when a model changes,
    -- you need to know which candidates predate it to decide what to re-run.
    extractor         TEXT NOT NULL,
    extractor_version TEXT NOT NULL,
    model_id          TEXT,
    -- What it read. Free-form because a run may span several raw tables.
    source_summary    TEXT NOT NULL,
    status            TEXT NOT NULL DEFAULT 'running'
                      CHECK (status IN ('running', 'completed', 'failed')),
    error             TEXT,
    stats             JSONB NOT NULL DEFAULT '{}'
                      CHECK (jsonb_typeof(stats) = 'object'),
    CONSTRAINT extraction_run_finished_after_start
        CHECK (finished_at IS NULL OR finished_at >= started_at)
);

CREATE INDEX extraction_run_started_at_idx ON working.extraction_run (started_at DESC);
CREATE INDEX extraction_run_extractor_idx  ON working.extraction_run (extractor, extractor_version);

COMMENT ON TABLE working.extraction_run IS
  'One extraction pass. Every candidate FKs here so a bad model version can be '
  'traced and its output re-reviewed or discarded wholesale.';

-- ---------------------------------------------------------------------------
-- source_provenance — the six clocks + the acquisition block, per source row.
-- ---------------------------------------------------------------------------
-- Append-only REVISIONS, not a mutable row. A silently-edited provenance field
-- is worse than a weak one: the edit is invisible and the whole account becomes
-- impeachable. Corrections are new revisions; `current_provenance` reads the
-- latest. This is what makes realized_at defensible when it is challenged.
--
-- realized_at is the clock that answers "when did you first know", and it is
-- the one that can be DERIVED rather than remembered: the AI-chat corpus
-- timestamps the moment of understanding ("wait — she said X in March but here
-- she says Y"). The extractor PROPOSES it with the transcript line as evidence;
-- a human confirms. Never accept a model-set realized_at as final.
CREATE TABLE working.source_provenance (
    id                UUID PRIMARY KEY DEFAULT uuidv7(),
    source_raw_table  TEXT NOT NULL,
    source_raw_id     TEXT NOT NULL,
    revision          INTEGER NOT NULL DEFAULT 1 CHECK (revision > 0),

    -- Family 1 — the event.
    occurred_at         TIMESTAMPTZ,
    -- Family 2 — the artifact.
    export_created_at   TIMESTAMPTZ,   -- completeness bound, NOT a knowledge clock
    acquired_at         TIMESTAMPTZ,
    ingested_at         TIMESTAMPTZ,
    -- Family 3 — knowledge. transaction_time is created_at below.
    realized_at         TIMESTAMPTZ,
    realized_at_source  TEXT,          -- the transcript line / artifact that dates it
    realized_at_state   TEXT NOT NULL DEFAULT 'unset'
                        CHECK (realized_at_state IN ('unset','proposed','confirmed','corrected')),

    -- Acquisition block. HITL-only. `unclear`/`unknown` are first-class.
    acquisition_method    TEXT NOT NULL DEFAULT 'unknown'
                          CHECK (acquisition_method IN ('own_device','household_device',
                                 'voluntary_third_party','legal_process','public_source','unknown')),
    acquisition_authority TEXT NOT NULL DEFAULT 'unclear'
                          CHECK (acquisition_authority IN ('device_owner','parent_guardian',
                                 'account_holder','consent_given','court_order','unclear')),
    source_device         TEXT,
    device_custodian      TEXT,
    custody_transferred_at TIMESTAMPTZ,
    acquisition_notes     TEXT,
    -- Provenance asserted by a model is not provenance. Enforced.
    asserted_by           TEXT NOT NULL,
    asserted_by_kind      TEXT NOT NULL DEFAULT 'human'
                          CHECK (asserted_by_kind = 'human'),
    -- Until counsel reviews the acquisition story, the row is not producible.
    producible            BOOLEAN NOT NULL DEFAULT false,

    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),   -- transaction_time

    -- An artifact cannot be acquired before it was exported, nor ingested
    -- before it was acquired. Violations mean a clock was guessed.
    CONSTRAINT source_provenance_artifact_clock_order
        CHECK ((export_created_at IS NULL OR acquired_at IS NULL OR acquired_at >= export_created_at)
           AND (acquired_at IS NULL OR ingested_at IS NULL OR ingested_at >= acquired_at)),
    -- You cannot realize the significance of something you do not yet have.
    CONSTRAINT source_provenance_realized_after_acquired
        CHECK (realized_at IS NULL OR acquired_at IS NULL OR realized_at >= acquired_at),
    -- A realized_at with no state, or a state with no timestamp, is a half-fact.
    CONSTRAINT source_provenance_realized_state_agrees
        CHECK ((realized_at IS NULL) = (realized_at_state = 'unset'))
);

CREATE UNIQUE INDEX source_provenance_revision_idx
    ON working.source_provenance (source_raw_table, source_raw_id, revision);
CREATE INDEX source_provenance_source_idx   ON working.source_provenance (source_raw_table, source_raw_id);
CREATE INDEX source_provenance_realized_idx ON working.source_provenance (realized_at);
CREATE INDEX source_provenance_occurred_idx ON working.source_provenance (occurred_at);

COMMENT ON TABLE working.source_provenance IS
  'Append-only revisions of the six clocks and the acquisition block for one '
  'source row. Never UPDATE — a correction is a new revision. Provenance may '
  'only be asserted by a human (asserted_by_kind is CHECKed to human).';

-- Latest revision per source row.
CREATE VIEW working.current_provenance AS
    SELECT DISTINCT ON (source_raw_table, source_raw_id) *
      FROM working.source_provenance
     ORDER BY source_raw_table, source_raw_id, revision DESC;

-- The delta that IS the analysis product: how long between the message being
-- sent and it being understood. A large gap on a manipulative message is the
-- shape of coercive control, not a data-quality problem.
CREATE VIEW working.knowledge_gap AS
    SELECT source_raw_table, source_raw_id, occurred_at, realized_at,
           realized_at - occurred_at AS gap,
           acquisition_method, acquisition_authority, producible
      FROM working.current_provenance
     WHERE occurred_at IS NOT NULL AND realized_at IS NOT NULL;

COMMENT ON VIEW working.knowledge_gap IS
  'occurred_at vs realized_at. The gap between what was true and when it was '
  'understood is the evidence of manipulation, not a discrepancy to reconcile.';

-- ---------------------------------------------------------------------------
-- candidate_entity — a person, place, org, device, account the extractor saw.
-- ---------------------------------------------------------------------------
CREATE TABLE working.candidate_entity (
    id                 UUID PRIMARY KEY DEFAULT uuidv7(),
    extraction_run_id  UUID NOT NULL REFERENCES working.extraction_run(id) ON DELETE CASCADE,

    -- Provenance. NOT NULL by design: an untraceable candidate is not usable.
    source_raw_table   TEXT NOT NULL,
    source_raw_id      TEXT NOT NULL,

    entity_type        TEXT NOT NULL
                       CHECK (entity_type IN ('person','organization','location',
                                              'device','account','other')),
    name               TEXT NOT NULL CHECK (length(name) > 0),
    normalized_name    TEXT NOT NULL CHECK (length(normalized_name) > 0),
    confidence         DOUBLE PRECISION CHECK (confidence >= 0 AND confidence <= 1),
    attrs              JSONB NOT NULL DEFAULT '{}'
                       CHECK (jsonb_typeof(attrs) = 'object'),

    -- Dedup key: same normalized entity from the same source row is one candidate.
    content_sha256     BYTEA NOT NULL CHECK (octet_length(content_sha256) = 32),

    review_state       TEXT NOT NULL DEFAULT 'pending'
                       CHECK (review_state IN ('pending','approved','rejected',
                                               'needs_info','superseded')),
    -- Where it went once approved. NULL until promoted.
    promoted_to_table  TEXT,
    promoted_to_id     TEXT,
    promoted_at        TIMESTAMPTZ,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- Only approved rows may be promoted. Enforced, not merely intended:
    -- this is the whole point of the layer.
    CONSTRAINT candidate_entity_promotion_requires_approval
        CHECK (promoted_at IS NULL OR review_state = 'approved'),
    CONSTRAINT candidate_entity_promotion_is_complete
        CHECK ((promoted_at IS NULL AND promoted_to_table IS NULL AND promoted_to_id IS NULL)
            OR (promoted_at IS NOT NULL AND promoted_to_table IS NOT NULL AND promoted_to_id IS NOT NULL))
);

CREATE UNIQUE INDEX candidate_entity_dedup_idx
    ON working.candidate_entity (source_raw_table, source_raw_id, content_sha256);
CREATE INDEX candidate_entity_run_idx        ON working.candidate_entity (extraction_run_id);
CREATE INDEX candidate_entity_source_idx     ON working.candidate_entity (source_raw_table, source_raw_id);
CREATE INDEX candidate_entity_normalized_idx ON working.candidate_entity (normalized_name);
CREATE INDEX candidate_entity_attrs_gin      ON working.candidate_entity USING GIN (attrs);
-- Partial index: the review queue is the hot read path and is a small slice.
CREATE INDEX candidate_entity_pending_idx
    ON working.candidate_entity (created_at) WHERE review_state = 'pending';

-- ---------------------------------------------------------------------------
-- candidate_fact — an assertion, optionally between two entities.
-- ---------------------------------------------------------------------------
CREATE TABLE working.candidate_fact (
    id                 UUID PRIMARY KEY DEFAULT uuidv7(),
    extraction_run_id  UUID NOT NULL REFERENCES working.extraction_run(id) ON DELETE CASCADE,

    source_raw_table   TEXT NOT NULL,
    source_raw_id      TEXT NOT NULL,

    -- Entity links stay inside `working`. A candidate must never FK into the
    -- gated evidence tables: that would let unreviewed material attach itself
    -- to court-facing rows.
    subject_entity_id  UUID REFERENCES working.candidate_entity(id) ON DELETE SET NULL,
    object_entity_id   UUID REFERENCES working.candidate_entity(id) ON DELETE SET NULL,

    predicate          TEXT NOT NULL CHECK (length(predicate) > 0),
    statement          TEXT NOT NULL CHECK (length(statement) > 0),
    -- Verbatim source span, so a reviewer can judge without leaving the queue.
    evidence_quote     TEXT,
    confidence         DOUBLE PRECISION CHECK (confidence >= 0 AND confidence <= 1),
    attrs              JSONB NOT NULL DEFAULT '{}'
                       CHECK (jsonb_typeof(attrs) = 'object'),
    content_sha256     BYTEA NOT NULL CHECK (octet_length(content_sha256) = 32),

    review_state       TEXT NOT NULL DEFAULT 'pending'
                       CHECK (review_state IN ('pending','approved','rejected',
                                               'needs_info','superseded')),
    promoted_to_table  TEXT,
    promoted_to_id     TEXT,
    promoted_at        TIMESTAMPTZ,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT candidate_fact_promotion_requires_approval
        CHECK (promoted_at IS NULL OR review_state = 'approved'),
    CONSTRAINT candidate_fact_promotion_is_complete
        CHECK ((promoted_at IS NULL AND promoted_to_table IS NULL AND promoted_to_id IS NULL)
            OR (promoted_at IS NOT NULL AND promoted_to_table IS NOT NULL AND promoted_to_id IS NOT NULL))
);

CREATE UNIQUE INDEX candidate_fact_dedup_idx
    ON working.candidate_fact (source_raw_table, source_raw_id, content_sha256);
CREATE INDEX candidate_fact_run_idx     ON working.candidate_fact (extraction_run_id);
CREATE INDEX candidate_fact_subject_idx ON working.candidate_fact (subject_entity_id);
CREATE INDEX candidate_fact_object_idx  ON working.candidate_fact (object_entity_id);
CREATE INDEX candidate_fact_attrs_gin   ON working.candidate_fact USING GIN (attrs);
CREATE INDEX candidate_fact_pending_idx
    ON working.candidate_fact (created_at) WHERE review_state = 'pending';

-- ---------------------------------------------------------------------------
-- candidate_event — a timeline entry. Bitemporal-ish: when it happened vs
-- the window we believe it holds for.
-- ---------------------------------------------------------------------------
CREATE TABLE working.candidate_event (
    id                 UUID PRIMARY KEY DEFAULT uuidv7(),
    extraction_run_id  UUID NOT NULL REFERENCES working.extraction_run(id) ON DELETE CASCADE,

    source_raw_table   TEXT NOT NULL,
    source_raw_id      TEXT NOT NULL,

    event_type         TEXT NOT NULL CHECK (length(event_type) > 0),
    summary            TEXT NOT NULL CHECK (length(summary) > 0),

    -- occurred_at is the point estimate; validity is the range we can defend.
    -- Extracted times are frequently vague ("last Tuesday"), so the range is
    -- the honest representation and the point is the convenience.
    occurred_at        TIMESTAMPTZ,
    validity           TSTZRANGE,
    temporal_confidence DOUBLE PRECISION
                       CHECK (temporal_confidence >= 0 AND temporal_confidence <= 1),

    primary_entity_id  UUID REFERENCES working.candidate_entity(id) ON DELETE SET NULL,
    confidence         DOUBLE PRECISION CHECK (confidence >= 0 AND confidence <= 1),
    attrs              JSONB NOT NULL DEFAULT '{}'
                       CHECK (jsonb_typeof(attrs) = 'object'),
    content_sha256     BYTEA NOT NULL CHECK (octet_length(content_sha256) = 32),

    review_state       TEXT NOT NULL DEFAULT 'pending'
                       CHECK (review_state IN ('pending','approved','rejected',
                                               'needs_info','superseded')),
    promoted_to_table  TEXT,
    promoted_to_id     TEXT,
    promoted_at        TIMESTAMPTZ,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- An event with neither a point nor a range is not a timeline entry.
    CONSTRAINT candidate_event_has_some_time
        CHECK (occurred_at IS NOT NULL OR validity IS NOT NULL),
    CONSTRAINT candidate_event_promotion_requires_approval
        CHECK (promoted_at IS NULL OR review_state = 'approved'),
    CONSTRAINT candidate_event_promotion_is_complete
        CHECK ((promoted_at IS NULL AND promoted_to_table IS NULL AND promoted_to_id IS NULL)
            OR (promoted_at IS NOT NULL AND promoted_to_table IS NOT NULL AND promoted_to_id IS NOT NULL))
);

CREATE UNIQUE INDEX candidate_event_dedup_idx
    ON working.candidate_event (source_raw_table, source_raw_id, content_sha256);
CREATE INDEX candidate_event_run_idx      ON working.candidate_event (extraction_run_id);
CREATE INDEX candidate_event_occurred_idx ON working.candidate_event (occurred_at);
CREATE INDEX candidate_event_entity_idx   ON working.candidate_event (primary_entity_id);
CREATE INDEX candidate_event_attrs_gin    ON working.candidate_event USING GIN (attrs);
-- GiST over the range: "what was believed true as of X" and overlap detection.
CREATE INDEX candidate_event_validity_gist ON working.candidate_event USING GIST (validity);
CREATE INDEX candidate_event_pending_idx
    ON working.candidate_event (created_at) WHERE review_state = 'pending';

-- ---------------------------------------------------------------------------
-- review_decision — append-only audit of every human judgement.
-- ---------------------------------------------------------------------------
-- Deliberately NOT a mutable column on the candidate: in a custody matter the
-- question "who approved this, when, and on what basis" must survive later
-- edits. The candidate's review_state is the current value; this is the trail.
CREATE TABLE working.review_decision (
    id             UUID PRIMARY KEY DEFAULT uuidv7(),
    candidate_kind TEXT NOT NULL CHECK (candidate_kind IN ('entity','fact','event')),
    candidate_id   UUID NOT NULL,

    decision       TEXT NOT NULL
                   CHECK (decision IN ('approved','rejected','needs_info','superseded')),
    reviewer       TEXT NOT NULL CHECK (length(reviewer) > 0),
    rationale      TEXT,
    decided_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    prior_state    TEXT NOT NULL,
    attrs          JSONB NOT NULL DEFAULT '{}'
                   CHECK (jsonb_typeof(attrs) = 'object')
);

-- No FK: candidate_id is polymorphic across three tables. The CHECK on
-- candidate_kind plus the application's write path carries the integrity, and
-- the audit trail must outlive a cascade-deleted candidate anyway.
CREATE INDEX review_decision_candidate_idx ON working.review_decision (candidate_kind, candidate_id);
CREATE INDEX review_decision_reviewer_idx  ON working.review_decision (reviewer, decided_at DESC);
CREATE INDEX review_decision_decided_idx   ON working.review_decision (decided_at DESC);

COMMENT ON TABLE working.review_decision IS
  'Append-only. Never UPDATE or DELETE — this is the provenance of human '
  'judgement and must remain defensible after the candidate changes.';

-- ---------------------------------------------------------------------------
-- promotion — ledger of what crossed the gate, and where it went.
-- ---------------------------------------------------------------------------
CREATE TABLE working.promotion (
    id             UUID PRIMARY KEY DEFAULT uuidv7(),
    candidate_kind TEXT NOT NULL CHECK (candidate_kind IN ('entity','fact','event')),
    candidate_id   UUID NOT NULL,

    -- Which of the two passes this promotion serves. Not optional: an
    -- unlabelled promotion is the failure mode this whole layer exists to
    -- prevent — hindsight material silently entering the as-lived record.
    lane           TEXT NOT NULL
                   CHECK (lane IN ('as_lived','hindsight','consolidated','support')),

    target_system  TEXT NOT NULL
                   CHECK (target_system IN ('postgres','surrealdb','semantica_graph',
                                            'graphiti_memory','weaviate')),
    target_ref     TEXT NOT NULL,
    promoted_by    TEXT NOT NULL,
    promoted_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- Set when a promotion is rolled back; keeps the row rather than deleting,
    -- so "this was in the record and then withdrawn" stays visible.
    revoked_at     TIMESTAMPTZ,
    revoked_reason TEXT,
    attrs          JSONB NOT NULL DEFAULT '{}'
                   CHECK (jsonb_typeof(attrs) = 'object'),

    CONSTRAINT promotion_revocation_has_reason
        CHECK (revoked_at IS NULL OR revoked_reason IS NOT NULL),

    -- Lane and destination are not independent choices. Graphiti IS the
    -- as-lived lane; Semantica/Neo4j IS the hindsight graph; SurrealDB IS the
    -- consolidation. Pairing them wrongly would put hindsight material into
    -- the belief-state record, which is the one error this layer cannot allow.
    -- 'support' covers destinations that are neither pass (e.g. Weaviate as a
    -- retrieval index) and is deliberately unconstrained on target.
    CONSTRAINT promotion_lane_matches_target
        CHECK (lane = 'support'
            OR (lane = 'as_lived'     AND target_system = 'graphiti_memory')
            OR (lane = 'hindsight'    AND target_system IN ('semantica_graph','postgres'))
            OR (lane = 'consolidated' AND target_system IN ('surrealdb','postgres')))
);

-- One live promotion per candidate per lane per target. Lane is part of the
-- key: the same approved fact legitimately belongs in BOTH passes, carrying
-- different timestamps in each.
CREATE UNIQUE INDEX promotion_live_idx
    ON working.promotion (candidate_kind, candidate_id, lane, target_system)
    WHERE revoked_at IS NULL;
CREATE INDEX promotion_candidate_idx ON working.promotion (candidate_kind, candidate_id);
CREATE INDEX promotion_target_idx    ON working.promotion (target_system, promoted_at DESC);
CREATE INDEX promotion_lane_idx      ON working.promotion (lane, promoted_at DESC);

COMMENT ON TABLE working.promotion IS
  'Every crossing of the human gate, labelled by which analysis pass it feeds: '
  'as_lived (Graphiti, keyed on realized_at), hindsight (Semantica/Neo4j, keyed '
  'on occurred_at), or consolidated (SurrealDB). Revocations are recorded, not '
  'deleted.';

COMMENT ON COLUMN working.promotion.lane IS
  'as_lived material must be withheld until its realized_at, or the belief '
  'state it documents is destroyed. Check working.current_provenance before '
  'promoting into the as_lived lane.';

-- ---------------------------------------------------------------------------
-- review_queue — what a reviewer actually opens.
-- ---------------------------------------------------------------------------
CREATE VIEW working.review_queue AS
    SELECT 'entity' AS kind, e.id, e.created_at, e.confidence,
           e.source_raw_table, e.source_raw_id, e.name AS label, e.review_state
      FROM working.candidate_entity e WHERE e.review_state = 'pending'
    UNION ALL
    SELECT 'fact', f.id, f.created_at, f.confidence,
           f.source_raw_table, f.source_raw_id, f.statement, f.review_state
      FROM working.candidate_fact f WHERE f.review_state = 'pending'
    UNION ALL
    SELECT 'event', v.id, v.created_at, v.confidence,
           v.source_raw_table, v.source_raw_id, v.summary, v.review_state
      FROM working.candidate_event v WHERE v.review_state = 'pending';

COMMENT ON VIEW working.review_queue IS
  'Everything awaiting human judgement, lowest-confidence first is the intended '
  'read: ORDER BY confidence NULLS FIRST, created_at.';

-- ---------------------------------------------------------------------------
-- Supersession stamps on the 0014-era staging placeholders (both 0 rows,
-- verified live 2026-08-02). Tables retained per the never-delete rule.
-- These COMMENTs also make the 0014 dependency explicit: this migration
-- fails loudly here if 0014 has not run.
-- ---------------------------------------------------------------------------
COMMENT ON TABLE working.extraction_candidate IS
  'SUPERSEDED by working.candidate_entity / candidate_fact / candidate_event '
  '(sql/0016, 2026-08-02). Was empty at supersession. Do not write here.';
COMMENT ON TABLE working.record_observation IS
  'SUPERSEDED by the working.candidate_* family + working.review_decision '
  '(sql/0016, 2026-08-02). Was empty at supersession. Do not write here.';

COMMIT;
