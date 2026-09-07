# Byline: Codex · GPT-5 · 2026-08-18
"""Static contract checks for the held 0026-0029 temporal/projection rewrite.

These tests deliberately do not connect to any database.  The migrations are
HELD/unapplied and must remain reviewable and rollback-safe until release.
"""

from pathlib import Path


SQL_DIR = Path(__file__).resolve().parents[1] / "sql"


def _sql(number: str) -> str:
    return (SQL_DIR / number).read_text(encoding="utf-8")


def test_0026_has_one_authored_record_and_separate_chunks() -> None:
    sql = _sql("0026_realization_event.sql")
    assert "source_record_key TEXT" in sql
    assert "source_content_sha256 BYTEA" in sql
    assert "CREATE TABLE IF NOT EXISTS working.normalized_record_chunk" in sql
    assert "UNIQUE(normalized_record_id, chunker_id, chunk_index)" in sql


def test_0026_preserves_retry_source_context_without_claiming_authority() -> None:
    sql = _sql("0026_realization_event.sql")
    assert "ALTER TABLE ops.workflow_run" in sql
    assert "source_context JSONB NOT NULL DEFAULT '{}'::jsonb" in sql
    assert "jsonb_typeof(source_context)='object'" in sql
    assert "not acquisition authority" in sql


def test_0026_projection_route_is_exclusive_and_approval_gated() -> None:
    sql = _sql("0026_realization_event.sql")
    assert "working.message_projection_route" in sql
    assert "normalized_record_id UUID PRIMARY KEY" in sql
    assert "('first_party','acquired_third_party')" in sql
    assert "decision_state='approved'" in sql
    assert "FIRST_PARTY_PROJECTION_CARDINALITY" in sql
    assert "ACQUIRED_THIRD_PARTY_PROJECTION_INVALID" in sql


def test_0026_third_party_requires_human_acquisition_and_excludes_owner() -> None:
    sql = _sql("0026_realization_event.sql")
    for table in (
        "third_party_conversation",
        "third_party_message",
        "third_party_message_participant",
        "third_party_conversation_acquisition",
    ):
        assert f"working.{table}" in sql
    assert "a.asserted_by='human'" in sql
    assert "wp.role_in_case='user'" in sql
    assert "OWNER_IDENTITY_NOT_CONFIGURED" in sql


def test_0026_separates_source_availability_from_realization() -> None:
    sql = _sql("0026_realization_event.sql")
    source_fn = sql.split("CREATE OR REPLACE FUNCTION working.source_available_from", maxsplit=1)[1].split(
        "CREATE OR REPLACE FUNCTION working.visible_from", maxsplit=1
    )[0]
    assert "a.acquired_at" in source_fn
    assert "nr.occurred_at" in source_fn
    assert "realized_at" not in source_fn
    assert "CREATE TABLE IF NOT EXISTS working.realization_event_record" in sql
    assert "'realization_event'::TEXT" in sql


def test_0026_forward_upgrades_legacy_realization_kind_constraint() -> None:
    sql = _sql("0026_realization_event.sql")
    assert "conname='realization_event_kind_check'" in sql
    assert "position('pattern_recognition' in pg_get_constraintdef(oid))=0" in sql
    assert "DROP CONSTRAINT realization_event_kind_check" in sql
    assert "ADD CONSTRAINT realization_event_kind_check" in sql
    for realization_kind in (
        "betrayal",
        "deceit",
        "gaslighting",
        "pattern_recognition",
    ):
        assert f"'{realization_kind}'" in sql


def test_0027_distinguishes_resumable_checkpoint_from_failure_seal() -> None:
    sql = _sql("0027_walk_ledger.sql")
    assert "CREATE TABLE IF NOT EXISTS working.walk_checkpoint" in sql
    assert "('healthy','failure_seal')" in sql
    assert "checkpoint_kind='healthy' AND is_resumable" in sql
    assert "checkpoint_kind='failure_seal' AND NOT is_resumable" in sql
    assert "rewalk_of_id UUID" in sql
    assert "resume_from_checkpoint_id UUID" in sql


def test_0027_versions_every_visibility_bearing_input() -> None:
    sql = _sql("0027_walk_ledger.sql")
    assert "working.vw_walk_base_version_input" in sql
    for input_kind in (
        "normalized_record",
        "message_projection_route",
        "third_party_acquisition",
        "realization_event",
        "realization_event_record",
    ):
        assert f"'{input_kind}'" in sql
    assert "working.walk_step_realization_retrieval" in sql
    assert "source_available_from(ret.record_id) IS NULL" in sql


def test_0027_preserves_legacy_walk_delta_columns_during_forward_upgrade() -> None:
    sql = _sql("0027_walk_ledger.sql")
    assert sql.count("CREATE OR REPLACE VIEW working.vw_walk_delta AS") == 1
    replacement = sql.rsplit("CREATE OR REPLACE VIEW working.vw_walk_delta AS", maxsplit=1)[1].split(
        "COMMENT ON TABLE working.walk_checkpoint", maxsplit=1
    )[0]

    # PostgreSQL only permits CREATE OR REPLACE VIEW to append columns.  The
    # legacy view's ninth column is realization_lag, so keep it in place and
    # append the new first_realized_at column after it.
    assert replacement.index("AS realization_lag") < replacement.index("rz.first_realized_at\n")


def test_0028_materialization_is_version_pinned_and_fail_closed() -> None:
    sql = _sql("0028_horizon_repoint.sql")
    assert "base_version TEXT NOT NULL" in sql
    assert "source_clock_hash TEXT NOT NULL" in sql
    assert "rvf.base_version=p_base_version" in sql
    assert "WHEN source_time IS NULL THEN false" in sql
    assert "working.horizon_record_visible(" in sql


def test_0028_forward_upgrades_empty_and_nonempty_legacy_cache_shapes() -> None:
    sql = _sql("0028_horizon_repoint.sql")

    # Empty/fresh databases get the complete table; nonempty legacy caches gain
    # the columns in place and their unversioned rows can never be trusted.
    assert "CREATE TABLE IF NOT EXISTS working.record_visible_from" in sql
    assert "ADD COLUMN IF NOT EXISTS base_version TEXT" in sql
    assert "ADD COLUMN IF NOT EXISTS source_clock_hash TEXT" in sql
    assert "SET base_version='__legacy_untrusted__'" in sql
    assert "source_clock_hash=repeat('0',64)" in sql
    assert "ALTER COLUMN visible_from DROP NOT NULL" in sql
    assert "ALTER COLUMN base_version SET NOT NULL" in sql
    assert "ALTER COLUMN source_clock_hash SET NOT NULL" in sql
    assert "rvf.base_version<>'__legacy_untrusted__'" in sql


def test_0029_grants_cover_projection_review_and_walk_roles() -> None:
    sql = _sql("0029_pass_grants.sql")
    assert "projection_refresher NOLOGIN" in sql
    assert "horizon_reviewer NOLOGIN" in sql
    assert "working.walk_checkpoint" in sql
    assert "working.walk_step_realization_retrieval" in sql
    assert "working.vw_walk_base_version_input" in sql
    assert "working.horizon_record_visible(UUID,TIMESTAMPTZ,TEXT)" in sql
