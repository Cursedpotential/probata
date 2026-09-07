-- Migration 0052: claim candidates + assertion/synthesis layer (context side only)
--
-- Byline: Claude · Opus 5 · 2026-08-29 · owner-directed.
-- Design: docs/design/CLAIM-AND-ASSERTION-CANDIDATES-2026-08-29.md
--
-- SCOPE, owner-set:
--   Context side ONLY. AI chats are permanently context (D-082 / ADR-0053). Nothing here
--   promotes to anything: no promotion columns exist on any table below, deliberately.
--   Evidence, custody binding, corroboration, and evidence pointers are the NEXT phase.
--
-- ADDITIVE ONLY. This migration creates new objects and does not ALTER, rename, or
-- constrain any raw landing table. working.chat_conversation / chat_message / chat_chunk
-- and the context.* raw tables come from actual sources and are referenced, never modified.
--
-- ADR-0052 ruling Q6 correction (owner, 2026-08-29): Q6 named the LEGAL-DOCUMENT extractor
-- output `claim_candidate`. That output is a created work, not a claim, and needs its own
-- table under a created-work name in a later phase. `working.claim_candidate` is hereby the
-- narrated-assertion row. Q6's merge semantics survive intact: entities dedup-merge,
-- claims accumulate and are NEVER merged or rewritten.
--
-- Placement (owner, 2026-08-29): "just land it next to it." The pre-existing candidate
-- layers (analysis.extraction_candidate, analysis.entity_candidate,
-- working.candidate_entity|fact|event) are NOT reconciled here.

BEGIN;

-- ---------------------------------------------------------------------------
-- 1 · Claim type vocabulary. Table-driven so it grows without a migration.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS reference.claim_type (
    slug        TEXT PRIMARY KEY
                CHECK (slug = lower(slug) AND slug ~ '^[a-z0-9]+(?:_[a-z0-9]+)*$'),
    label       TEXT NOT NULL CHECK (length(btrim(label)) > 0),
    description TEXT NOT NULL CHECK (length(btrim(description)) > 0),
    parent_slug TEXT REFERENCES reference.claim_type(slug) ON DELETE RESTRICT,
    retired_at  TIMESTAMPTZ,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO reference.claim_type (slug, label, description) VALUES
  ('event',              'Event',              'Something stated to have happened at a point in time.'),
  ('condition',          'Condition',          'An ongoing state: housing, health, employment, custody status.'),
  ('statement',          'Statement',          'Something a person said or wrote, reported in the text.'),
  ('authority',          'Authority',          'A statute, case, rule, or form cited.'),
  ('strategy',           'Strategy',           'A plan, tactic, or approach raised.'),
  ('decision',           'Decision',           'A choice stated as settled, with its reasoning.'),
  ('exposure',           'Exposure',           'An adverse fact, mistake, or vulnerability stated by the subject.'),
  ('person_detail',      'Person detail',      'An identifying detail about someone.'),
  ('open_question',      'Open question',      'A question asked in the conversation that was never answered.'),
  ('artifact_reference', 'Artifact reference', 'A claim naming a document, message, or record existing in the world. Pointer resolution is a later phase.'),
  ('other',              'Other',              'No listed type fits; detail belongs in attrs/note.')
ON CONFLICT (slug) DO NOTHING;

-- ---------------------------------------------------------------------------
-- 2 · Extraction windows. Coverage must be queryable, not a footnote in prose.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS working.extraction_window (
    id                   UUID PRIMARY KEY DEFAULT uuidv7(),
    extraction_run_id    UUID NOT NULL REFERENCES working.extraction_run(id) ON DELETE CASCADE,
    chat_conversation_id UUID NOT NULL REFERENCES working.chat_conversation(id) ON DELETE RESTRICT,
    ordinal_range        INT4RANGE NOT NULL,
    -- 'targeted_retrieval' records the real case where a pass answered queries against a
    -- source instead of reading it through. That decides whether it needs re-reading.
    read_mode            TEXT NOT NULL
                         CHECK (read_mode IN ('full','targeted_retrieval','partial_truncated')),
    claims_emitted       INT NOT NULL DEFAULT 0 CHECK (claims_emitted >= 0),
    ordinals_no_claims   INT[] NOT NULL DEFAULT '{}',
    truncated            BOOLEAN NOT NULL DEFAULT false,
    note                 TEXT,
    created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (extraction_run_id, chat_conversation_id, ordinal_range)
);

CREATE INDEX IF NOT EXISTS extraction_window_conversation_idx
    ON working.extraction_window (chat_conversation_id);

-- ---------------------------------------------------------------------------
-- 3 · Claim candidates. One row per MENTION. Redundancy is required.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS working.claim_candidate (
    id                   UUID PRIMARY KEY DEFAULT uuidv7(),
    extraction_run_id    UUID NOT NULL REFERENCES working.extraction_run(id) ON DELETE CASCADE,
    window_id            UUID NOT NULL REFERENCES working.extraction_window(id) ON DELETE CASCADE,

    -- Provenance into the raw chat spine. Referenced, never altered.
    chat_conversation_id UUID NOT NULL REFERENCES working.chat_conversation(id) ON DELETE RESTRICT,
    chat_message_id      UUID NOT NULL REFERENCES working.chat_message(id) ON DELETE RESTRICT,
    chat_chunk_id        UUID REFERENCES working.chat_chunk(id) ON DELETE RESTRICT,
    message_ordinal      BIGINT NOT NULL CHECK (message_ordinal >= 0),
    span_start           INT CHECK (span_start IS NULL OR span_start >= 0),
    span_end             INT CHECK (span_end IS NULL OR span_end >= span_start),

    -- speaker_role is denormalized from the message ON PURPOSE: it is decisive for
    -- claim_class and must be enforceable without a join.
    speaker_role         TEXT NOT NULL
                         CHECK (speaker_role IN ('human','assistant','system','unknown')),
    claim_class          TEXT NOT NULL CHECK (claim_class IN (
                             'SELF_ACCOUNT','SELF_ALLEGATION','REPORTED_SPEECH',
                             'DOCUMENT_QUOTE','AI_PROPOSAL','UNKNOWN')),

    claim_type_slug      TEXT NOT NULL REFERENCES reference.claim_type(slug) ON DELETE RESTRICT,
    title                TEXT NOT NULL CHECK (length(btrim(title)) > 0),
    body                 TEXT NOT NULL CHECK (length(btrim(body)) > 0),

    -- Verbatim is mandatory and unaltered. Paraphrase in this column is a defect.
    verbatim             TEXT NOT NULL CHECK (length(verbatim) BETWEEN 1 AND 300),
    hedged               BOOLEAN NOT NULL,
    hedge_terms          TEXT[] NOT NULL DEFAULT '{}',

    -- Time stays UNRESOLVED here. A claim about a date is not an event; occurred_at and
    -- validity deliberately do not exist on this table. relative_time_anchor_id is an
    -- inert seam to the anchor system and stays NULL until an anchor is reviewed there.
    -- The literal temporal phrase, never resolved. There is deliberately no
    -- `date_relative_to` free-text column: ordering is expressed in
    -- working.claim_temporal_edge, which is computable. Two representations of one
    -- relationship, one of them uncomputable, is a drift generator.
    date_raw             TEXT,
    -- Inert seam to the anchor system: nullable, never populated in this phase. Depends
    -- on migration 0047, which precedes this one in a clean ordered rebuild.
    relative_time_anchor_id UUID REFERENCES context.relative_time_anchor(id) ON DELETE RESTRICT,

    participant_codes    TEXT[] NOT NULL DEFAULT '{}',

    -- fingerprint is a cheap BLOCKING key for downstream clustering. It is NOT an
    -- identity and must never be unique: identical fingerprints across mentions are
    -- expected and are the entire point.
    fingerprint          TEXT NOT NULL CHECK (length(btrim(fingerprint)) > 0),
    content_sha256       BYTEA NOT NULL CHECK (octet_length(content_sha256) = 32),

    extractor            TEXT NOT NULL CHECK (length(btrim(extractor)) > 0),
    extractor_version    TEXT NOT NULL CHECK (length(btrim(extractor_version)) > 0),
    model_id             TEXT,
    confidence           DOUBLE PRECISION
                         CHECK (confidence IS NULL OR confidence BETWEEN 0 AND 1),

    -- NO review gate. A claim is not evidence, is never promoted, and cannot be filed or
    -- cited. A per-claim approval queue would put tens of thousands of rows in front of
    -- one person for no decision that changes anything. Human attention is spent on
    -- promotion, on divergences that block real work, and on assertions about to be
    -- relied on — never on confirming that an extractor read a sentence correctly.
    -- Correction is supersession, not rejection.
    lifecycle            TEXT NOT NULL DEFAULT 'active'
                         CHECK (lifecycle IN ('active','superseded')),
    superseded_by_id     UUID REFERENCES working.claim_candidate(id) ON DELETE RESTRICT,
    superseded_reason    TEXT,

    attrs                JSONB NOT NULL DEFAULT '{}' CHECK (jsonb_typeof(attrs) = 'object'),
    created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- CONTAMINATION GUARD. Assistant text is an AI proposal, full stop; and an
    -- AI_PROPOSAL may not be attributed to a human turn. Both directions, enforced.
    CONSTRAINT claim_candidate_assistant_is_proposal
        CHECK ((speaker_role = 'assistant') = (claim_class = 'AI_PROPOSAL')),

    -- Hedge terms without the flag is a dropped qualifier.
    CONSTRAINT claim_candidate_hedge_consistency
        CHECK (hedged OR cardinality(hedge_terms) = 0),

    CONSTRAINT claim_candidate_supersession_is_complete
        CHECK ((lifecycle = 'active'     AND superseded_by_id IS NULL)
            OR (lifecycle = 'superseded' AND superseded_by_id IS NOT NULL)),
    CONSTRAINT claim_candidate_no_self_supersede
        CHECK (superseded_by_id IS DISTINCT FROM id)
);

-- Re-emission of the same span by the SAME run is a bug. The same span emitted by a
-- different run or extractor version is a NEW observation and must be kept.
CREATE UNIQUE INDEX IF NOT EXISTS claim_candidate_run_span_key
    ON working.claim_candidate (extraction_run_id, chat_message_id, content_sha256);

CREATE INDEX IF NOT EXISTS claim_candidate_fingerprint_idx
    ON working.claim_candidate (fingerprint);
CREATE INDEX IF NOT EXISTS claim_candidate_class_idx
    ON working.claim_candidate (claim_class);
CREATE INDEX IF NOT EXISTS claim_candidate_conversation_idx
    ON working.claim_candidate (chat_conversation_id, message_ordinal);
CREATE INDEX IF NOT EXISTS claim_candidate_type_idx
    ON working.claim_candidate (claim_type_slug);

-- Q6 "never merged, never rewritten", enforced rather than intended. Review columns stay
-- mutable; content is frozen. A correction is a NEW row plus review_state='superseded'.
CREATE OR REPLACE FUNCTION working.claim_candidate_content_is_append_only()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.title            IS DISTINCT FROM OLD.title
    OR NEW.body             IS DISTINCT FROM OLD.body
    OR NEW.verbatim         IS DISTINCT FROM OLD.verbatim
    OR NEW.claim_class      IS DISTINCT FROM OLD.claim_class
    OR NEW.claim_type_slug  IS DISTINCT FROM OLD.claim_type_slug
    OR NEW.speaker_role     IS DISTINCT FROM OLD.speaker_role
    OR NEW.hedged           IS DISTINCT FROM OLD.hedged
    OR NEW.hedge_terms      IS DISTINCT FROM OLD.hedge_terms
    OR NEW.date_raw         IS DISTINCT FROM OLD.date_raw
    OR NEW.date_relative_to IS DISTINCT FROM OLD.date_relative_to
    OR NEW.content_sha256   IS DISTINCT FROM OLD.content_sha256
    OR NEW.chat_message_id  IS DISTINCT FROM OLD.chat_message_id THEN
        RAISE EXCEPTION
          'claim_candidate content is append-only (id=%): supersede with a new row, do not edit',
          OLD.id USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS claim_candidate_append_only ON working.claim_candidate;
CREATE TRIGGER claim_candidate_append_only
    BEFORE UPDATE ON working.claim_candidate
    FOR EACH ROW EXECUTE FUNCTION working.claim_candidate_content_is_append_only();

-- ---------------------------------------------------------------------------
-- 3b · Temporal edges. Ordering AS STATED, never resolved.
--
-- A graph authored relationally. PG stays the authoring home (ADR-0045 §B forbids
-- parallel authored stores); SurrealDB receives a DERIVED projection for traversal
-- (D-073/D-080). Nothing here is ever written directly to a graph engine as authority.
--
-- This is the input to context.relative_time_anchor, not a replacement for it. An edge
-- records what the subject SAID about ordering. An anchor is a reviewed inference about
-- placement. Edges accumulate and are never rewritten, like the claims they connect.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS working.claim_temporal_edge (
    id                 UUID PRIMARY KEY DEFAULT uuidv7(),
    extraction_run_id  UUID NOT NULL REFERENCES working.extraction_run(id) ON DELETE CASCADE,
    from_claim_id      UUID NOT NULL REFERENCES working.claim_candidate(id) ON DELETE RESTRICT,

    relation           TEXT NOT NULL
                       CHECK (relation IN ('before','after','same_window','during','approximately_at')),

    -- The other end is EITHER an extracted claim OR a phrase nothing has extracted yet.
    -- Windowed extraction means most references point outside the current window, so an
    -- edge that required a resolved target would discard nearly all of them.
    target_kind        TEXT NOT NULL CHECK (target_kind IN ('claim','unresolved_phrase')),
    to_claim_id        UUID REFERENCES working.claim_candidate(id) ON DELETE RESTRICT,
    target_phrase      TEXT,
    -- Set when a later pass resolves the phrase to a claim. The original phrase and the
    -- original target_kind are never overwritten; resolution is additive.
    resolved_claim_id  UUID REFERENCES working.claim_candidate(id) ON DELETE RESTRICT,
    resolved_by        TEXT,
    resolved_at        TIMESTAMPTZ,

    -- Magnitude when stated ("five months before", "about a week later"). Literal text
    -- plus an optional parsed interval; the text is authoritative, the interval is a
    -- convenience and may be NULL when the phrase is not parseable.
    offset_raw         TEXT,
    offset_interval    INTERVAL,

    -- The span this ordering was read out of. An edge with no verbatim is an inference,
    -- and inferences belong in relative_time_anchor, not here.
    as_stated_verbatim TEXT NOT NULL CHECK (length(as_stated_verbatim) BETWEEN 1 AND 300),
    hedged             BOOLEAN NOT NULL DEFAULT false,
    confidence         DOUBLE PRECISION
                       CHECK (confidence IS NULL OR confidence BETWEEN 0 AND 1),

    -- No review gate here either, for the same reason. An edge is a recorded statement
    -- about ordering, not a decision. Human judgment lands on the resolved ANCHOR
    -- (context.relative_time_anchor already has review_state), which is one reviewable
    -- inference standing in for many edges — the whole point of that table.
    lifecycle          TEXT NOT NULL DEFAULT 'active'
                       CHECK (lifecycle IN ('active','superseded')),
    attrs              JSONB NOT NULL DEFAULT '{}' CHECK (jsonb_typeof(attrs) = 'object'),
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT claim_temporal_edge_target_is_complete
        CHECK ((target_kind = 'claim'
                    AND to_claim_id IS NOT NULL AND target_phrase IS NULL)
            OR (target_kind = 'unresolved_phrase'
                    AND to_claim_id IS NULL AND target_phrase IS NOT NULL
                    AND length(btrim(target_phrase)) > 0)),
    CONSTRAINT claim_temporal_edge_no_self_reference
        CHECK (from_claim_id IS DISTINCT FROM to_claim_id
           AND from_claim_id IS DISTINCT FROM resolved_claim_id),
    CONSTRAINT claim_temporal_edge_resolution_is_complete
        CHECK ((resolved_claim_id IS NULL AND resolved_by IS NULL AND resolved_at IS NULL)
            OR (resolved_claim_id IS NOT NULL AND resolved_by IS NOT NULL
                    AND resolved_at IS NOT NULL AND target_kind = 'unresolved_phrase'))
);

CREATE INDEX IF NOT EXISTS claim_temporal_edge_from_idx
    ON working.claim_temporal_edge (from_claim_id);
CREATE INDEX IF NOT EXISTS claim_temporal_edge_to_idx
    ON working.claim_temporal_edge (to_claim_id) WHERE to_claim_id IS NOT NULL;
-- The resolution work queue: every dangling phrase, oldest first.
CREATE INDEX IF NOT EXISTS claim_temporal_edge_unresolved_idx
    ON working.claim_temporal_edge (created_at)
    WHERE target_kind = 'unresolved_phrase' AND resolved_claim_id IS NULL;

-- ---------------------------------------------------------------------------
-- 4 · Assertions (gen 1) and syntheses (gen 2). The AI/analysis layer.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS working.claim_assertion (
    id                 UUID PRIMARY KEY DEFAULT uuidv7(),

    -- 1 = grounded directly in claims. 2 = synthesis over generation-1 assertions.
    -- There is no 3. Analysis of analysis is the failure mode this cap prevents.
    assertion_generation SMALLINT NOT NULL CHECK (assertion_generation IN (1, 2)),

    assertion_kind     TEXT NOT NULL CHECK (assertion_kind IN (
                           'connection','significance','decision',
                           'exposure','gap','correction')),
    statement          TEXT NOT NULL CHECK (length(btrim(statement)) > 0),
    rationale          TEXT NOT NULL CHECK (length(btrim(rationale)) > 0),

    -- An owner decision and a model's framing are different objects with different
    -- weight. Never collapsible.
    asserted_by_kind   TEXT NOT NULL CHECK (asserted_by_kind IN ('owner','model')),
    asserted_by        TEXT NOT NULL CHECK (length(btrim(asserted_by)) > 0),
    asserted_at        TIMESTAMPTZ NOT NULL DEFAULT now(),

    salience           TEXT CHECK (salience IS NULL OR salience IN ('hot','good','warm')),
    argument_targets   TEXT[] NOT NULL DEFAULT '{}',

    owner_disposition  TEXT NOT NULL DEFAULT 'unreviewed'
                       CHECK (owner_disposition IN ('unreviewed','accepted','rejected',
                                                    'parked','superseded')),
    disposition_reason TEXT,
    disposition_at     TIMESTAMPTZ,

    source_ref         TEXT,
    supersedes_id      UUID REFERENCES working.claim_assertion(id) ON DELETE RESTRICT,
    attrs              JSONB NOT NULL DEFAULT '{}' CHECK (jsonb_typeof(attrs) = 'object'),
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- Parked deliberately is different from never looked at. Say why.
    CONSTRAINT claim_assertion_parked_has_reason
        CHECK (owner_disposition <> 'parked' OR disposition_reason IS NOT NULL),
    CONSTRAINT claim_assertion_disposition_dated
        CHECK (owner_disposition = 'unreviewed' OR disposition_at IS NOT NULL),
    CONSTRAINT claim_assertion_no_self_supersede
        CHECK (supersedes_id IS DISTINCT FROM id),
    UNIQUE (id, assertion_generation)
);

CREATE INDEX IF NOT EXISTS claim_assertion_generation_idx
    ON working.claim_assertion (assertion_generation);
CREATE INDEX IF NOT EXISTS claim_assertion_disposition_idx
    ON working.claim_assertion (owner_disposition);
CREATE INDEX IF NOT EXISTS claim_assertion_targets_idx
    ON working.claim_assertion USING GIN (argument_targets);

-- Generation 1 membership: assertion -> claims.
CREATE TABLE IF NOT EXISTS working.claim_assertion_member (
    assertion_id       UUID NOT NULL REFERENCES working.claim_assertion(id) ON DELETE CASCADE,
    claim_candidate_id UUID NOT NULL REFERENCES working.claim_candidate(id) ON DELETE RESTRICT,
    member_role        TEXT NOT NULL DEFAULT 'constituent'
                       CHECK (member_role IN ('constituent','supports','contradicts','context')),
    member_ordinal     INT NOT NULL CHECK (member_ordinal >= 0),
    note               TEXT,
    PRIMARY KEY (assertion_id, claim_candidate_id),
    UNIQUE (assertion_id, member_ordinal)
);

-- Generation 2 membership: synthesis -> generation-1 assertions ONLY.
-- The composite FK to (id, assertion_generation) makes "members must be gen 1" a
-- referential fact, not a trigger's opinion.
CREATE TABLE IF NOT EXISTS working.claim_assertion_synthesis_member (
    synthesis_id        UUID NOT NULL REFERENCES working.claim_assertion(id) ON DELETE CASCADE,
    member_assertion_id UUID NOT NULL,
    member_generation   SMALLINT NOT NULL DEFAULT 1 CHECK (member_generation = 1),

    -- Divergence between independent readings is SIGNAL. It is recorded, never resolved
    -- here; adjudication is a new assertion, never an edit.
    agreement_state     TEXT NOT NULL
                        CHECK (agreement_state IN ('concurs','diverges','extends')),
    divergence_note     TEXT,
    member_ordinal      INT NOT NULL CHECK (member_ordinal >= 0),
    PRIMARY KEY (synthesis_id, member_assertion_id),
    UNIQUE (synthesis_id, member_ordinal),
    CONSTRAINT synthesis_member_not_self
        CHECK (synthesis_id <> member_assertion_id),
    CONSTRAINT synthesis_divergence_is_explained
        CHECK (agreement_state <> 'diverges' OR divergence_note IS NOT NULL),
    CONSTRAINT synthesis_member_is_generation_one
        FOREIGN KEY (member_assertion_id, member_generation)
        REFERENCES working.claim_assertion(id, assertion_generation) ON DELETE RESTRICT
);

-- Cardinality and member-kind agreement cannot be a CHECK (they span rows), so they are a
-- DEFERRED constraint trigger: members may be inserted after the parent, but the
-- transaction cannot commit an ungrounded assertion.
CREATE OR REPLACE FUNCTION working.claim_assertion_grounding_is_valid()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    gen        SMALLINT;
    n_claims   INT;
    n_synth    INT;
    target     UUID := COALESCE(NEW.id, OLD.id);
BEGIN
    SELECT assertion_generation INTO gen
      FROM working.claim_assertion WHERE id = target;
    IF gen IS NULL THEN
        RETURN NULL;  -- parent deleted in this transaction
    END IF;

    SELECT count(*) INTO n_claims
      FROM working.claim_assertion_member WHERE assertion_id = target;
    SELECT count(*) INTO n_synth
      FROM working.claim_assertion_synthesis_member WHERE synthesis_id = target;

    IF gen = 1 THEN
        IF n_claims < 1 THEN
            RAISE EXCEPTION
              'generation-1 assertion % must cite at least one claim_candidate', target
              USING ERRCODE = '23514';
        END IF;
        IF n_synth > 0 THEN
            RAISE EXCEPTION
              'generation-1 assertion % may not have synthesis members', target
              USING ERRCODE = '23514';
        END IF;
    ELSE
        IF n_synth < 2 THEN
            RAISE EXCEPTION
              'synthesis % must combine at least two generation-1 assertions', target
              USING ERRCODE = '23514';
        END IF;
        IF n_claims > 0 THEN
            RAISE EXCEPTION
              'synthesis % cites assertions, not claims directly', target
              USING ERRCODE = '23514';
        END IF;
    END IF;
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS claim_assertion_grounding ON working.claim_assertion;
CREATE CONSTRAINT TRIGGER claim_assertion_grounding
    AFTER INSERT OR UPDATE ON working.claim_assertion
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION working.claim_assertion_grounding_is_valid();

DROP TRIGGER IF EXISTS claim_assertion_member_grounding ON working.claim_assertion_member;
CREATE CONSTRAINT TRIGGER claim_assertion_member_grounding
    AFTER INSERT OR UPDATE OR DELETE ON working.claim_assertion_member
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION working.claim_assertion_grounding_is_valid();

DROP TRIGGER IF EXISTS claim_assertion_synthesis_grounding ON working.claim_assertion_synthesis_member;
CREATE CONSTRAINT TRIGGER claim_assertion_synthesis_grounding
    AFTER INSERT OR UPDATE OR DELETE ON working.claim_assertion_synthesis_member
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION working.claim_assertion_grounding_is_valid();

-- Statement/rationale are frozen for the same reason claims are: a revision is a new row
-- with supersedes_id, so the earlier reading stays readable.
CREATE OR REPLACE FUNCTION working.claim_assertion_content_is_append_only()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.statement            IS DISTINCT FROM OLD.statement
    OR NEW.rationale            IS DISTINCT FROM OLD.rationale
    OR NEW.assertion_generation IS DISTINCT FROM OLD.assertion_generation
    OR NEW.asserted_by          IS DISTINCT FROM OLD.asserted_by
    OR NEW.asserted_by_kind     IS DISTINCT FROM OLD.asserted_by_kind THEN
        RAISE EXCEPTION
          'claim_assertion content is append-only (id=%): supersede with a new row',
          OLD.id USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS claim_assertion_append_only ON working.claim_assertion;
CREATE TRIGGER claim_assertion_append_only
    BEFORE UPDATE ON working.claim_assertion
    FOR EACH ROW EXECUTE FUNCTION working.claim_assertion_content_is_append_only();

COMMIT;
