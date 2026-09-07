-- 0017_append_only_guards.sql — make 0016's append-only claims DATABASE-ENFORCED.
--
-- Byline: Claude Code . Fable 5 . 2026-08-02
--
-- Codex deep-analysis C-08: migration 0016 DESCRIBES working.source_provenance,
-- working.review_decision, and working.promotion as append-only, but nothing
-- in the database stops an UPDATE or DELETE — the invariant lived in comments.
-- In a custody case "who approved this and when" must survive later edits at
-- the ENGINE level, same as evidence.source's source_immutable trigger.
--
--   source_provenance : no UPDATE, no DELETE (corrections are new revisions)
--   review_decision   : no UPDATE, no DELETE (the trail of human judgement)
--   promotion         : no DELETE; UPDATE allowed ONLY to revoke — setting
--                       revoked_at/revoked_reason exactly once, every other
--                       column byte-identical ("this was in the record and
--                       then withdrawn" stays visible, nothing is rewritten)
--
-- Also closes 0016's extraction_run lifecycle gap (completed with a NULL
-- finish time was representable).
--
-- Percent-free. Never edit after apply — add 0018.

BEGIN;

CREATE OR REPLACE FUNCTION working.forbid_mutation() RETURNS trigger AS
$fn$
BEGIN
    RAISE EXCEPTION '% is append-only: % blocked (corrections are new rows)',
        TG_TABLE_NAME, TG_OP;
END
$fn$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS source_provenance_append_only ON working.source_provenance;
CREATE TRIGGER source_provenance_append_only
    BEFORE UPDATE OR DELETE ON working.source_provenance
    FOR EACH ROW EXECUTE FUNCTION working.forbid_mutation();

DROP TRIGGER IF EXISTS review_decision_append_only ON working.review_decision;
CREATE TRIGGER review_decision_append_only
    BEFORE UPDATE OR DELETE ON working.review_decision
    FOR EACH ROW EXECUTE FUNCTION working.forbid_mutation();

CREATE OR REPLACE FUNCTION working.promotion_revoke_only() RETURNS trigger AS
$fn$
BEGIN
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION 'working.promotion is append-only: DELETE blocked (revoke instead)';
    END IF;
    -- The ONLY legal update: first-time revocation. Everything else identical.
    IF OLD.revoked_at IS NOT NULL THEN
        RAISE EXCEPTION 'working.promotion: row already revoked; further updates blocked';
    END IF;
    IF NEW.revoked_at IS NULL THEN
        RAISE EXCEPTION 'working.promotion: UPDATE must set revoked_at (revocation is the only legal update)';
    END IF;
    IF to_jsonb(NEW) - 'revoked_at' - 'revoked_reason'
       IS DISTINCT FROM to_jsonb(OLD) - 'revoked_at' - 'revoked_reason' THEN
        RAISE EXCEPTION 'working.promotion: only revoked_at/revoked_reason may change on revocation';
    END IF;
    RETURN NEW;
END
$fn$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS promotion_revoke_only ON working.promotion;
CREATE TRIGGER promotion_revoke_only
    BEFORE UPDATE OR DELETE ON working.promotion
    FOR EACH ROW EXECUTE FUNCTION working.promotion_revoke_only();

-- Lifecycle: a completed run must have a finish time; a failed run must say why.
ALTER TABLE working.extraction_run
    DROP CONSTRAINT IF EXISTS extraction_run_lifecycle_ck;
ALTER TABLE working.extraction_run
    ADD CONSTRAINT extraction_run_lifecycle_ck CHECK (
        (status <> 'completed' OR finished_at IS NOT NULL)
        AND (status <> 'failed' OR error IS NOT NULL)
    );

COMMIT;
