-- 0035_timeline_projection.sql — D01/D02/E02 canonical timeline + Timesketch projection foundation.
--
-- Byline: Claude Code · Sonnet 5 · 2026-08-26
--
-- Physical realization of ADR-0060 / D-084 / D-085 / the TIMESKETCH-FORK-CURATION-HANDOFF.md
-- "Required PostgreSQL families" table and R09's Timesketch writer-fence rule, scoped to
-- WP-D01 (canonical timeline membership), WP-D02 (projection generation/mapping), and
-- WP-E02 (PG->Timesketch projector). Curation/amendment commands (WP-F01/F02,
-- timeline_curation_batch/item, timeline_amendment_candidate) are NOT built here — that is a
-- separately owned, not-yet-started packet (see SEMANTIC-AGENT-WORK-PACKAGES.md). This
-- migration only needs to let an approved-entry edit surface later as an amendment candidate;
-- it does not implement the re-review workflow itself.
--
-- Final table/column NAMES are not yet R00-frozen (TIMESKETCH-FORK-CURATION-HANDOFF.md:
-- "this handoff freezes responsibilities and authority, not spelling"). This migration is a
-- faithful, reviewable physical realization of those responsibilities, additive and reversible
-- like every migration in this chain — a later R00 rename is a normal forward migration, not a
-- rewrite of this file.
--
-- WP-B01 (AI-chat typed fan-out) and WP-C02 (context-to-evidence promotion) are themselves
-- "Blocked by physical design" as of this migration, so `event_candidate` deliberately does NOT
-- FK to their not-yet-built candidate tables. Source identity is a bounded, generic envelope
-- (source_system/source_record_id/source_record_version) so any future producer can populate it
-- without a schema change here. Likewise `timeline_member`'s "evidence_approved" branch is a
-- generic polymorphic pointer (schema/table/pk as text), not an FK to `analysis.timeline_event`
-- or any other specific governed table — which one(s) qualify as "evidence-approved" sources is
-- an R00/C02 decision this migration does not presume.
--
-- Schema `timeline` is new and owned by this packet (WP-D01/D02/E02). It does not touch
-- `evidence`, `analysis`, or `working` — see server/timeline/AGENTS.md for the package that
-- reads/writes it.

BEGIN;

CREATE SCHEMA IF NOT EXISTS timeline;
COMMENT ON SCHEMA timeline IS
    'ADR-0060 / D-084 / D-085 canonical timeline + Timesketch-fork projection tables '
    '(WP-D01/D02/E02). Curation/amendment ledger (WP-F01/F02) is a separate, not-yet-built '
    'family; this schema only carries the identity/immutability contract it must slot into.';

-- ---------------------------------------------------------------------------
-- Shared append-only guard (mirrors working.forbid_mutation(), 0017) — scoped
-- to this schema so its error message and ownership are unambiguous.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION timeline.forbid_mutation() RETURNS trigger AS
$fn$
BEGIN
    RAISE EXCEPTION '% is append-only: % blocked (corrections/successors are new rows, never edits)',
        TG_TABLE_NAME, TG_OP;
END
$fn$ LANGUAGE plpgsql;

-- ===========================================================================
-- WP-D01 — canonical timeline membership: candidate identity + curated
-- membership, retaining candidate vs governed authority (ADR-0060 §"Canonical
-- timeline contract").
-- ===========================================================================

-- Any-context event proposal. D-082/D-083: an AI-chat-derived row here is a
-- lead, never evidence. Authority is CANDIDATE ONLY at this table — nothing
-- here may be read as an established fact.
CREATE TABLE IF NOT EXISTS timeline.event_candidate (
    id                      uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    -- Stable source identity (R09 "stable source/version IDs for replay,
    -- reconciliation, and source opening"). Deliberately NOT an FK — WP-B01's
    -- typed extraction-run contract is not yet built; any producer that can
    -- name its own system/record/version may write here.
    source_system           text        NOT NULL,       -- e.g. 'ai_chat','sms','location','court_procedural','manual_lead'
    source_record_id        text        NOT NULL,
    source_record_version   text,
    source_locator          jsonb       NOT NULL DEFAULT '{}'::jsonb,  -- bounded pointer for source-opening (schema/table/pk, offsets, etc.)
    extraction_run_id       text,                        -- which run proposed this; free text until WP-B01 lands a typed run table
    -- Temporal contract (ADR-0060 mapping table): never coerce imprecision
    -- into a false-precision point.
    temporal_precision      text        NOT NULL CHECK (temporal_precision IN ('point', 'interval', 'uncertain')),
    occurred_at              timestamptz,
    valid_from               timestamptz,
    valid_to                 timestamptz,
    temporal_confidence      real        CHECK (temporal_confidence IS NULL OR (temporal_confidence >= 0 AND temporal_confidence <= 1)),
    display_summary          text        NOT NULL,
    event_type               text        NOT NULL,       -- controlled vocabulary; versioned at the projection layer, not enforced here
    entity_refs               text[]      NOT NULL DEFAULT '{}',
    created_at                timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT event_candidate_source_identity_uq
        UNIQUE (source_system, source_record_id, source_record_version)
);

COMMENT ON TABLE timeline.event_candidate IS
    'Any-context event proposal (ADR-0060). CANDIDATE authority only -- D-082: an AI-chat-derived '
    'row is a lead, never evidence. A correction is a NEW row (new extraction_run_id), never an '
    'edit to this one -- see the append-only trigger below.';
COMMENT ON COLUMN timeline.event_candidate.source_locator IS
    'Bounded pointer for source-opening links (e.g. {"schema":"context","table":"chat_message","pk":"..."}). '
    'Not a foreign key -- the producer schema is not yet frozen (WP-B01).';

DROP TRIGGER IF EXISTS event_candidate_append_only ON timeline.event_candidate;
CREATE TRIGGER event_candidate_append_only
    BEFORE UPDATE OR DELETE ON timeline.event_candidate
    FOR EACH ROW EXECUTE FUNCTION timeline.forbid_mutation();

-- Single personal-case timeline collection (D-072: one owner, one case --
-- never multi-tenant). Kept as a real table, not a hardcoded constant, so a
-- future named sub-view (e.g. a court-prep working set) has somewhere to live
-- without a schema change; nothing besides 'primary' is expected to exist.
CREATE TABLE IF NOT EXISTS timeline.timeline_collection (
    id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    slug        text        NOT NULL UNIQUE,
    title       text        NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE timeline.timeline_collection IS
    'D-072 single-case timeline collection(s). Curated membership set -- authority stays with the '
    'member row it points at, never copied here.';

INSERT INTO timeline.timeline_collection (slug, title)
VALUES ('primary', 'Primary case timeline')
ON CONFLICT (slug) DO NOTHING;

-- Curated membership: what is IN the timeline, in what order/group, without
-- copying the source's own authority. Points at exactly one of a candidate
-- row (this migration's event_candidate) or a governed/evidence-approved row
-- living elsewhere (polymorphic on purpose -- see header note).
CREATE TABLE IF NOT EXISTS timeline.timeline_member (
    id                      uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    collection_id           uuid        NOT NULL REFERENCES timeline.timeline_collection(id),
    member_authority        text        NOT NULL CHECK (member_authority IN ('candidate_context', 'evidence_approved')),
    -- candidate_context branch
    candidate_id            uuid        REFERENCES timeline.event_candidate(id),
    -- evidence_approved branch: generic polymorphic anchor (see header note);
    -- source_version lets a governed successor be distinguished from the row
    -- it supersedes without this table needing to know the owning schema's shape.
    governed_source_schema  text,
    governed_source_table   text,
    governed_source_pk      text,
    governed_source_version text,
    display_order            numeric,     -- curated ordering within the collection; NULL = natural temporal order
    group_label              text,
    included                 boolean     NOT NULL DEFAULT true,
    created_at                timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT timeline_member_authority_shape_ck CHECK (
        (member_authority = 'candidate_context'
            AND candidate_id IS NOT NULL
            AND governed_source_schema IS NULL AND governed_source_table IS NULL AND governed_source_pk IS NULL)
        OR
        (member_authority = 'evidence_approved'
            AND candidate_id IS NULL
            AND governed_source_schema IS NOT NULL AND governed_source_table IS NOT NULL AND governed_source_pk IS NOT NULL)
    )
);

COMMENT ON TABLE timeline.timeline_member IS
    'Curated timeline membership (ADR-0060). Retains candidate vs evidence-approved authority via '
    'member_authority; never copies the source row''s own content. An edit to an evidence_approved '
    'member is out of this table''s scope -- it becomes a WP-F02 amendment candidate elsewhere, '
    'never an UPDATE here.';

CREATE UNIQUE INDEX IF NOT EXISTS timeline_member_candidate_uq
    ON timeline.timeline_member (collection_id, candidate_id)
    WHERE candidate_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS timeline_member_governed_uq
    ON timeline.timeline_member (collection_id, governed_source_schema, governed_source_table, governed_source_pk)
    WHERE governed_source_schema IS NOT NULL;
CREATE INDEX IF NOT EXISTS timeline_member_collection_idx ON timeline.timeline_member (collection_id, included);

-- Membership itself is not append-only (curation may include/exclude/reorder
-- per ADR-0060's bulk-edit contract, owned by the not-yet-built WP-F01 API) --
-- but nothing here may repoint an existing member from one source to another,
-- since that would silently launder identity across a projected generation.
CREATE OR REPLACE FUNCTION timeline.forbid_member_source_repoint() RETURNS trigger AS
$fn$
BEGIN
    IF NEW.member_authority IS DISTINCT FROM OLD.member_authority
        OR NEW.candidate_id IS DISTINCT FROM OLD.candidate_id
        OR NEW.governed_source_schema IS DISTINCT FROM OLD.governed_source_schema
        OR NEW.governed_source_table IS DISTINCT FROM OLD.governed_source_table
        OR NEW.governed_source_pk IS DISTINCT FROM OLD.governed_source_pk
    THEN
        RAISE EXCEPTION 'timeline_member: source identity is immutable once created (add a new member row instead)';
    END IF;
    RETURN NEW;
END
$fn$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS timeline_member_source_immutable ON timeline.timeline_member;
CREATE TRIGGER timeline_member_source_immutable
    BEFORE UPDATE ON timeline.timeline_member
    FOR EACH ROW EXECUTE FUNCTION timeline.forbid_member_source_repoint();

-- ===========================================================================
-- WP-D02 — projection generation and mapping: immutable membership/hash,
-- Timesketch field mapping, bounded attributes, clock/uncertainty contract,
-- and the outbox-shaped receipt trail R09 reconciles against.
-- ===========================================================================

-- One immutable, sealed export. Never updated in place -- a re-projection is
-- always a NEW generation row (R09 invariant 13: "every Timesketch/OpenSearch
-- document belongs to one immutable PG projection generation").
CREATE TABLE IF NOT EXISTS timeline.timeline_projection_generation (
    id                      uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    sequence                bigint      GENERATED ALWAYS AS IDENTITY,
    collection_id           uuid        NOT NULL REFERENCES timeline.timeline_collection(id),
    status                  text        NOT NULL DEFAULT 'sealed' CHECK (status IN ('sealed', 'superseded', 'quarantined')),
    policy_version           text        NOT NULL DEFAULT 'adr-0060-timesketch-mapping-v1',
    member_count             int         NOT NULL,
    membership_hash          text        NOT NULL,   -- hash of the ordered stable_member_id set
    content_hash             text        NOT NULL,   -- hash of the full ordered member content
    -- Non-null idempotency identity (deterministic from content_hash) so
    -- rebuilding from an unchanged timeline_member set is a no-op, not a
    -- duplicate generation -- see server/timeline/generation.py.
    idempotency_key          text        NOT NULL UNIQUE,
    since_generation_id      uuid        REFERENCES timeline.timeline_projection_generation(id),
    superseded_by            uuid        REFERENCES timeline.timeline_projection_generation(id),
    created_by               text        NOT NULL DEFAULT 'timeline_projector',
    created_at                timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE timeline.timeline_projection_generation IS
    'Immutable, sealed Timesketch export generation (ADR-0060/D-085). sequence is the '
    'monotonically comparable outbox-style cursor R09 walks; idempotency_key makes rebuilding '
    'from an unchanged member set a no-op instead of a duplicate.';

DROP TRIGGER IF EXISTS timeline_projection_generation_append_only ON timeline.timeline_projection_generation;
CREATE TRIGGER timeline_projection_generation_append_only
    BEFORE DELETE ON timeline.timeline_projection_generation
    FOR EACH ROW EXECUTE FUNCTION timeline.forbid_mutation();

-- The ONLY legal update on a generation row: marking it superseded when a
-- newer generation seals (mirrors 0017's promotion_revoke_only shape).
CREATE OR REPLACE FUNCTION timeline.generation_supersede_only() RETURNS trigger AS
$fn$
BEGIN
    IF OLD.status <> 'sealed' THEN
        RAISE EXCEPTION 'timeline_projection_generation %: already %, no further UPDATE allowed', OLD.id, OLD.status;
    END IF;
    IF NEW.status NOT IN ('superseded', 'quarantined') THEN
        RAISE EXCEPTION 'timeline_projection_generation: UPDATE must set status to superseded or quarantined';
    END IF;
    IF to_jsonb(NEW) - 'status' - 'superseded_by' IS DISTINCT FROM to_jsonb(OLD) - 'status' - 'superseded_by' THEN
        RAISE EXCEPTION 'timeline_projection_generation: only status/superseded_by may change';
    END IF;
    RETURN NEW;
END
$fn$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS timeline_projection_generation_supersede_only ON timeline.timeline_projection_generation;
CREATE TRIGGER timeline_projection_generation_supersede_only
    BEFORE UPDATE ON timeline.timeline_projection_generation
    FOR EACH ROW EXECUTE FUNCTION timeline.generation_supersede_only();

-- Append-only activation log. "Currently active generation" = the latest row
-- here, not a mutable pointer column on the generation itself (R09 Phase 7:
-- "each gate records an immutable attestation... Surreal is last" -- this is
-- that attestation for the Timesketch/OpenSearch reader gate).
CREATE TABLE IF NOT EXISTS timeline.timeline_projection_activation (
    id              uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    generation_id   uuid        NOT NULL REFERENCES timeline.timeline_projection_generation(id),
    activated_by    text        NOT NULL,
    note            text,
    activated_at    timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE timeline.timeline_projection_activation IS
    'Append-only activation attestation log (R09 Phase 7). Current active generation = the row '
    'with the latest activated_at; never mutate a prior row to "deactivate" it.';

DROP TRIGGER IF EXISTS timeline_projection_activation_append_only ON timeline.timeline_projection_activation;
CREATE TRIGGER timeline_projection_activation_append_only
    BEFORE UPDATE OR DELETE ON timeline.timeline_projection_activation
    FOR EACH ROW EXECUTE FUNCTION timeline.forbid_mutation();

-- One row per projected member per generation. Maps 1:1 onto ADR-0060's
-- canonical timeline contract table (display_at_utc -> datetime,
-- display_summary -> message, event_type -> timestamp_desc, everything else
-- a bounded attribute).
CREATE TABLE IF NOT EXISTS timeline.timeline_projection_member (
    id                       uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    generation_id            uuid        NOT NULL REFERENCES timeline.timeline_projection_generation(id),
    source_member_id         uuid        NOT NULL REFERENCES timeline.timeline_member(id),
    -- Stable across generations for the SAME logical member (server/timeline
    -- derives this from source_member_id, not from the generation) so
    -- re-projection always targets the same logical Timesketch/OpenSearch
    -- document -- replay-safe by construction.
    stable_member_id         text        NOT NULL,
    opensearch_doc_id        text        NOT NULL,
    authority_state          text        NOT NULL CHECK (authority_state IN ('candidate_context', 'evidence_approved', 'amendment_candidate')),
    amends_stable_member_id  text,       -- set only when authority_state = 'amendment_candidate'
    -- ADR-0060 required Timesketch fields
    display_at_utc           timestamptz NOT NULL,
    display_summary          text        NOT NULL,
    event_type                text        NOT NULL,
    -- Bounded attributes: temporal/uncertainty contract
    temporal_precision        text        NOT NULL CHECK (temporal_precision IN ('point', 'interval', 'uncertain')),
    occurred_at                timestamptz,
    valid_from                 timestamptz,
    valid_to                   timestamptz,
    temporal_confidence        real        CHECK (temporal_confidence IS NULL OR (temporal_confidence >= 0 AND temporal_confidence <= 1)),
    -- Horizon predicate field (explicitly required by the WP-E02 brief):
    -- occurrence for first-party sources, custody-backed acquisition for
    -- acquired-third-party sources (ADR-0059) -- never backdated by realization.
    source_available_from      timestamptz NOT NULL,
    entity_refs                 text[]      NOT NULL DEFAULT '{}',
    verification_state           text        NOT NULL DEFAULT 'unverified'
        CHECK (verification_state IN ('unverified', 'disputed', 'verified', 'revoked', 'superseded')),
    privacy_level                 text,
    privileged                    boolean     NOT NULL DEFAULT false,
    -- Required for replay, reconciliation, and source opening (R09's
    -- "stable source/version IDs" clause on the canonical projection event).
    source_system                  text        NOT NULL,
    source_record_id               text        NOT NULL,
    source_record_version          text,
    -- Core-vs-annotation change classification (explicitly required by the
    -- WP-E02 brief): two independently hashed slices of the same member so a
    -- later generation can tell "the event itself changed" from "only
    -- enrichment/annotation changed" without re-diffing every field by hand.
    core_content_hash               text        NOT NULL,   -- temporal + display + event_type + lineage
    annotation_content_hash         text        NOT NULL,   -- entity_refs + verification/privacy/privilege
    change_class                    text        NOT NULL DEFAULT 'core' CHECK (change_class IN ('core', 'annotation', 'unchanged')),
    member_content_hash             text        NOT NULL,   -- core_content_hash + annotation_content_hash, R09 manifest unit
    created_at                       timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT timeline_projection_member_amendment_shape_ck CHECK (
        (authority_state = 'amendment_candidate' AND amends_stable_member_id IS NOT NULL)
        OR (authority_state <> 'amendment_candidate' AND amends_stable_member_id IS NULL)
    ),
    CONSTRAINT timeline_projection_member_generation_uq UNIQUE (generation_id, stable_member_id)
);

COMMENT ON TABLE timeline.timeline_projection_member IS
    'One immutable row per member per sealed generation (ADR-0060 canonical mapping). '
    'stable_member_id/opensearch_doc_id are deterministic functions of source_member_id, never of '
    'the generation, so rebuild/replay always targets the same logical OpenSearch document.';
COMMENT ON COLUMN timeline.timeline_projection_member.change_class IS
    'Relative to this stable_member_id''s row in the immediately-prior generation (if any): '
    '"core" = core_content_hash differs, "annotation" = only annotation_content_hash differs, '
    '"unchanged" = neither differs (member_content_hash identical) -- R09 uses this to decide '
    'reindex vs annotation-refresh vs skip.';

CREATE INDEX IF NOT EXISTS timeline_projection_member_generation_idx
    ON timeline.timeline_projection_member (generation_id);
CREATE INDEX IF NOT EXISTS timeline_projection_member_stable_idx
    ON timeline.timeline_projection_member (stable_member_id, generation_id);
CREATE INDEX IF NOT EXISTS timeline_projection_member_opensearch_doc_idx
    ON timeline.timeline_projection_member (opensearch_doc_id);

DROP TRIGGER IF EXISTS timeline_projection_member_append_only ON timeline.timeline_projection_member;
CREATE TRIGGER timeline_projection_member_append_only
    BEFORE UPDATE OR DELETE ON timeline.timeline_projection_member
    FOR EACH ROW EXECUTE FUNCTION timeline.forbid_mutation();

-- Append-only delivery/read-back/reconciliation receipt (R09 "Common PG
-- receipt"). A store API acknowledgement never equals success on its own --
-- only an observed, hashed read-back does.
CREATE TABLE IF NOT EXISTS timeline.timeline_projection_receipt (
    id                      uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    generation_id           uuid        NOT NULL REFERENCES timeline.timeline_projection_generation(id),
    member_id               uuid        REFERENCES timeline.timeline_projection_member(id),  -- NULL = generation-level receipt (e.g. activation attempt)
    sink                    text        NOT NULL DEFAULT 'timesketch_opensearch',
    idempotency_key          text        NOT NULL,
    status                   text        NOT NULL CHECK (status IN
        ('pending', 'attempted', 'succeeded', 'failed_retryable', 'failed_terminal', 'quarantined', 'superseded')),
    attempt                  int         NOT NULL DEFAULT 1,
    expected_content_hash     text,
    observed_content_hash     text,
    opensearch_doc_id         text,
    opensearch_index          text,
    error_code                 text,
    error_digest                text,
    started_at                   timestamptz,
    finished_at                  timestamptz,
    observed_at                  timestamptz,
    previous_receipt_id           uuid        REFERENCES timeline.timeline_projection_receipt(id),
    created_at                     timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE timeline.timeline_projection_receipt IS
    'Append-only delivery/read-back receipt (R09 common-receipt shape). A current-status view is '
    'derived below -- rows here are never updated, a new attempt/observation is a new row.';

DROP TRIGGER IF EXISTS timeline_projection_receipt_append_only ON timeline.timeline_projection_receipt;
CREATE TRIGGER timeline_projection_receipt_append_only
    BEFORE UPDATE OR DELETE ON timeline.timeline_projection_receipt
    FOR EACH ROW EXECUTE FUNCTION timeline.forbid_mutation();

CREATE INDEX IF NOT EXISTS timeline_projection_receipt_generation_idx
    ON timeline.timeline_projection_receipt (generation_id, status);
CREATE INDEX IF NOT EXISTS timeline_projection_receipt_member_idx
    ON timeline.timeline_projection_receipt (member_id, status);

-- Derived current-status view (R09: "Receipts are append-only; a
-- current-status view is derived").
CREATE OR REPLACE VIEW timeline.vw_projection_receipt_current AS
SELECT DISTINCT ON (generation_id, member_id, sink)
    generation_id, member_id, sink, status, attempt,
    expected_content_hash, observed_content_hash,
    opensearch_doc_id, opensearch_index,
    error_code, error_digest,
    started_at, finished_at, observed_at, id AS receipt_id, created_at
FROM timeline.timeline_projection_receipt
ORDER BY generation_id, member_id, sink, created_at DESC, id DESC;

COMMENT ON VIEW timeline.vw_projection_receipt_current IS
    'Latest receipt per (generation, member, sink) -- the derived current-status read, not a '
    'source of truth (the append-only receipt rows are).';

-- Expected manifest for a sealed generation (R09 "expected/observed
-- manifests, reconciliation runs"): ordered member ids + hashes, the exact
-- shape R09/WP-H01 diffs against the observed OpenSearch read-back.
CREATE OR REPLACE VIEW timeline.vw_projection_expected_manifest AS
SELECT
    g.id AS generation_id,
    g.sequence,
    g.status,
    g.membership_hash,
    g.content_hash,
    m.stable_member_id,
    m.opensearch_doc_id,
    m.member_content_hash,
    m.authority_state,
    m.change_class
FROM timeline.timeline_projection_generation g
JOIN timeline.timeline_projection_member m ON m.generation_id = g.id
ORDER BY g.sequence, m.stable_member_id;

COMMENT ON VIEW timeline.vw_projection_expected_manifest IS
    'R09/WP-H01 expected-manifest read: ordered (generation, member) rows with the hashes a '
    'reconciliation run diffs against OpenSearch read-back observations.';

-- ---------------------------------------------------------------------------
-- Roles + default-deny grants (mirrors 0029's pattern). Two separately
-- authenticated identities per R09's writer-fence rule: neither may share
-- credentials with the other, and neither is the curation-command identity
-- (that role belongs to the not-yet-built WP-F01 packet).
-- ---------------------------------------------------------------------------
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'timeline_writer') THEN
        CREATE ROLE timeline_writer NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'timeline_projector') THEN
        CREATE ROLE timeline_projector NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'timeline_reader') THEN
        CREATE ROLE timeline_reader NOLOGIN;
    END IF;
END $$;

COMMENT ON ROLE timeline_writer IS
    'Writer of candidate/curated-membership rows only (timeline.event_candidate, '
    'timeline.timeline_member, timeline.timeline_collection). No grant on the projection '
    'generation/member/receipt tables -- it cannot forge a projection. INERT while the app '
    'connects as the `ai` superuser, same caveat as 0029.';
COMMENT ON ROLE timeline_projector IS
    'R09 "versioned timeline projector service role": reads candidate/membership rows, is the '
    'SOLE writer of timeline_projection_generation/member/activation/receipt. No UPDATE/DELETE '
    'grant anywhere -- every table it writes is append-only by trigger, not just by convention. '
    'Distinct from the not-yet-built curation-command role; neither shares credentials with the '
    'other per R09''s writer-fence rule. INERT while the app connects as the `ai` superuser.';
COMMENT ON ROLE timeline_reader IS
    'Read-only: projection generation/member/receipt/activation + the two manifest views, for '
    'R09/WP-H01 reconciliation and future fork-UI reads. No grant on event_candidate/'
    'timeline_member (agents read the projected generation, not raw candidates).';

GRANT USAGE ON SCHEMA timeline TO timeline_writer, timeline_projector, timeline_reader;

REVOKE ALL ON TABLE
    timeline.event_candidate,
    timeline.timeline_collection,
    timeline.timeline_member,
    timeline.timeline_projection_generation,
    timeline.timeline_projection_activation,
    timeline.timeline_projection_member,
    timeline.timeline_projection_receipt
    FROM PUBLIC;

GRANT SELECT, INSERT ON TABLE
    timeline.event_candidate,
    timeline.timeline_member
    TO timeline_writer;
GRANT SELECT, INSERT ON TABLE timeline.timeline_collection TO timeline_writer;
GRANT UPDATE (included, display_order, group_label) ON TABLE timeline.timeline_member TO timeline_writer;

GRANT SELECT ON TABLE
    timeline.event_candidate,
    timeline.timeline_collection,
    timeline.timeline_member
    TO timeline_projector;
GRANT SELECT, INSERT ON TABLE
    timeline.timeline_projection_generation,
    timeline.timeline_projection_activation,
    timeline.timeline_projection_member,
    timeline.timeline_projection_receipt
    TO timeline_projector;
-- The one legal UPDATE path (supersede-only, trigger-enforced above).
GRANT UPDATE (status, superseded_by) ON TABLE timeline.timeline_projection_generation TO timeline_projector;

GRANT SELECT ON TABLE
    timeline.timeline_projection_generation,
    timeline.timeline_projection_activation,
    timeline.timeline_projection_member,
    timeline.timeline_projection_receipt
    TO timeline_reader;
GRANT SELECT ON timeline.vw_projection_receipt_current, timeline.vw_projection_expected_manifest
    TO timeline_reader, timeline_projector;

COMMIT;
