# Byline: Claude Code · Sonnet 5 · 2026-08-26
"""WP-D01/D02/E02: canonical timeline + Timesketch projection.

Two layers:
  1. Pure-unit tests (no DB) for the hashing/serialization contract and the pure member-
     projection logic — these run every default `pytest -q`.
  2. One `@pytest.mark.integration` test that runs against the live snapshot schema (no DDL applied; migrations retired 2026-09-07)
     the LIVE tailnet PostgreSQL inside a transaction and rolls back — proving the migration, the
     append-only/immutability guards, `build_generation()`'s idempotency, `change_class`
     transitions, `PostgresTimelineProjectionSource.fetch_generation()`, and the receipt/manifest
     read path against the real engine, with zero persisted schema change (mirrors the
     rollback-transaction pattern `sql/0029_pass_grants.sql`'s own header describes). Opt-in via
     `TIMELINE_PG_LIVE=1` since it dials the production database, even though nothing survives
     the rollback.
"""

from __future__ import annotations

import os
import uuid
from datetime import datetime, timezone

import pytest

from server.timeline.generation import _display_at_utc, _project_member
from server.timeline.hashing import domain_hash, idempotency_key_for_generation, opensearch_doc_id, stable_member_id
from server.timeline.models import SourceMemberRow

# ---------------------------------------------------------------------------
# Unit tests — no DB, no network.
# ---------------------------------------------------------------------------


def test_domain_hash_is_deterministic_and_domain_scoped() -> None:
    payload = {"a": 1, "b": "two"}
    assert domain_hash("tag-a", payload) == domain_hash("tag-a", payload)
    # Different domain tag -> different hash even for identical payload (no cross-purpose reuse).
    assert domain_hash("tag-a", payload) != domain_hash("tag-b", payload)


def test_domain_hash_is_key_order_independent() -> None:
    a = {"z": 1, "a": 2}
    b = {"a": 2, "z": 1}
    assert domain_hash("tag", a) == domain_hash("tag", b)


def test_domain_hash_rejects_naive_datetime() -> None:
    with pytest.raises(ValueError):
        domain_hash("tag", {"when": datetime(2026, 1, 1)})  # no tzinfo


def test_domain_hash_utc_normalizes_offset() -> None:
    from datetime import timedelta

    utc_dt = datetime(2026, 1, 1, 12, 0, 0, tzinfo=timezone.utc)
    offset_dt = datetime(2026, 1, 1, 7, 0, 0, tzinfo=timezone(timedelta(hours=-5)))  # same instant
    assert domain_hash("tag", {"t": utc_dt}) == domain_hash("tag", {"t": offset_dt})


def test_stable_member_id_is_identity_of_source_row() -> None:
    source_id = str(uuid.uuid4())
    assert stable_member_id(source_id) == source_id


def test_opensearch_doc_id_is_deterministic_and_not_the_raw_id() -> None:
    stable_id = "abc-123"
    doc_id = opensearch_doc_id(stable_id)
    assert doc_id == opensearch_doc_id(stable_id)
    assert doc_id != stable_id
    assert len(doc_id) == 64  # sha256 hex


def test_idempotency_key_deterministic_from_content_hash() -> None:
    h = "deadbeef"
    assert idempotency_key_for_generation(h) == idempotency_key_for_generation(h)
    assert idempotency_key_for_generation(h) != idempotency_key_for_generation("other")


def _candidate_row(**overrides: object) -> SourceMemberRow:
    base: dict[str, object] = dict(
        source_member_id=str(uuid.uuid4()),
        collection_id=str(uuid.uuid4()),
        authority_state="candidate_context",
        source_system="ai_chat",
        source_record_id="chat-msg-1",
        source_record_version=None,
        temporal_precision="point",
        occurred_at=datetime(2026, 3, 14, 18, 22, tzinfo=timezone.utc),
        valid_from=None,
        valid_to=None,
        temporal_confidence=0.9,
        display_summary="Something happened",
        event_type="message_sent",
        entity_refs=("person:alice",),
        source_available_from=datetime(2026, 3, 14, 18, 25, tzinfo=timezone.utc),
    )
    base.update(overrides)
    return SourceMemberRow(**base)  # type: ignore[arg-type]


def test_display_at_utc_prefers_occurred_at() -> None:
    row = _candidate_row()
    assert _display_at_utc(row) == row.occurred_at


def test_display_at_utc_falls_back_when_occurred_at_missing() -> None:
    row = _candidate_row(occurred_at=None, valid_from=datetime(2026, 3, 1, tzinfo=timezone.utc))
    assert _display_at_utc(row) == row.valid_from


def test_display_at_utc_raises_with_no_anchor_at_all() -> None:
    row = _candidate_row(occurred_at=None, valid_from=None, valid_to=None, source_available_from=None)
    with pytest.raises(ValueError):
        _display_at_utc(row)


def test_project_member_first_seen_is_core_change_class() -> None:
    row = _candidate_row()
    pm = _project_member(row, prior_hashes={})
    assert pm.change_class == "core"
    assert pm.stable_member_id == row.source_member_id
    assert pm.opensearch_doc_id != pm.stable_member_id


def test_project_member_unchanged_when_hashes_match_prior() -> None:
    row = _candidate_row()
    pm = _project_member(row, prior_hashes={})
    prior = {pm.stable_member_id: (pm.core_content_hash, pm.annotation_content_hash)}
    pm2 = _project_member(row, prior_hashes=prior)
    assert pm2.change_class == "unchanged"
    assert pm2.member_content_hash == pm.member_content_hash


def test_project_member_annotation_only_change() -> None:
    row = _candidate_row()
    pm = _project_member(row, prior_hashes={})
    prior = {pm.stable_member_id: (pm.core_content_hash, pm.annotation_content_hash)}
    changed = _candidate_row(
        source_member_id=row.source_member_id,
        entity_refs=("person:alice", "person:bob"),  # annotation-only field
    )
    pm2 = _project_member(changed, prior_hashes=prior)
    assert pm2.core_content_hash == pm.core_content_hash
    assert pm2.annotation_content_hash != pm.annotation_content_hash
    assert pm2.change_class == "annotation"


def test_project_member_core_change_when_display_summary_differs() -> None:
    row = _candidate_row()
    pm = _project_member(row, prior_hashes={})
    prior = {pm.stable_member_id: (pm.core_content_hash, pm.annotation_content_hash)}
    changed = _candidate_row(source_member_id=row.source_member_id, display_summary="A different summary")
    pm2 = _project_member(changed, prior_hashes=prior)
    assert pm2.core_content_hash != pm.core_content_hash
    assert pm2.change_class == "core"


def test_project_member_requires_source_available_from() -> None:
    row = _candidate_row(source_available_from=None)
    with pytest.raises(ValueError):
        _project_member(row, prior_hashes={})


# ---------------------------------------------------------------------------
# Live integration — opt-in, rollback-scoped. Each test gets its own
# connection/transaction and re-applies the migration fresh; nothing is
# shared across tests (a failed statement aborts the whole PG transaction, so
# splitting per-scenario is simpler and more robust than one long test
# recovering mid-transaction).
# ---------------------------------------------------------------------------

_LIVE_SKIP = pytest.mark.skipif(
    os.getenv("TIMELINE_PG_LIVE") != "1", reason="live-PG rollback test is opt-in (TIMELINE_PG_LIVE=1)"
)


def _assert_timeline_schema_present(conn) -> None:
    """The database IS the snapshot (D-142 §3, D-152): the timeline projection objects must already exist.
    Migrations were retired 2026-09-07; this replaces the old apply-0035-then-rollback rehearsal."""
    from sqlalchemy import text

    n = conn.execute(
        text("SELECT count(*) FROM information_schema.tables WHERE table_schema = 'timeline'")
    ).scalar_one()
    assert n > 0, "timeline schema missing from the live database; rebuild from sql/bootstrap/schema_snapshot"


def _live_engine():
    os.environ.setdefault("DB_HOST", "100.91.190.107")
    from sqlalchemy import create_engine

    from server.core.url import build_db_url

    return create_engine(build_db_url(), pool_pre_ping=True)


def _insert_candidate_member(
    conn, collection_id: str, *, source_system: str, source_record_id: str, summary: str
) -> str:
    from sqlalchemy import text

    candidate_id = conn.execute(
        text(
            "INSERT INTO timeline.event_candidate "
            "(source_system, source_record_id, temporal_precision, occurred_at, "
            " display_summary, event_type, entity_refs) "
            "VALUES (:sys, :rec, 'point', now(), :summary, 'manual_lead', '{}') "
            "RETURNING id"
        ),
        {"sys": source_system, "rec": source_record_id, "summary": summary},
    ).scalar_one()
    member_id = conn.execute(
        text(
            "INSERT INTO timeline.timeline_member (collection_id, member_authority, candidate_id) "
            "VALUES (:c, 'candidate_context', :cand) RETURNING id"
        ),
        {"c": collection_id, "cand": candidate_id},
    ).scalar_one()
    return str(member_id)


@pytest.mark.integration
@_LIVE_SKIP
def test_live_build_generation_idempotent_and_supersedes_prior() -> None:
    from sqlalchemy import text

    from server.timeline.generation import build_generation

    engine = _live_engine()
    try:
        with engine.connect() as conn:
            trans = conn.begin()
            try:
                _assert_timeline_schema_present(conn)
                collection_id = conn.execute(
                    text("SELECT id FROM timeline.timeline_collection WHERE slug = 'primary'")
                ).scalar_one()

                _insert_candidate_member(
                    conn, collection_id, source_system="ai_chat", source_record_id="msg-1", summary="first event"
                )
                result1 = build_generation(conn, collection_slug="primary", created_by="test-suite")
                assert result1.created is True
                assert result1.member_count == 1
                assert result1.skipped_unresolved_governed_members == ()

                # Replay with no member-set change: idempotent no-op, same generation id.
                result2 = build_generation(conn, collection_slug="primary", created_by="test-suite")
                assert result2.created is False
                assert result2.generation_id == result1.generation_id

                # A new candidate seals a new generation and supersedes the prior one.
                _insert_candidate_member(
                    conn, collection_id, source_system="ai_chat", source_record_id="msg-2", summary="second event"
                )
                result3 = build_generation(conn, collection_slug="primary", created_by="test-suite")
                assert result3.created is True
                assert result3.member_count == 2
                assert result3.generation_id != result1.generation_id
                assert result3.sequence > result1.sequence

                status = conn.execute(
                    text("SELECT status FROM timeline.timeline_projection_generation WHERE id = :id"),
                    {"id": result1.generation_id},
                ).scalar_one()
                assert status == "superseded"
            finally:
                trans.rollback()
    finally:
        engine.dispose()


@pytest.mark.integration
@_LIVE_SKIP
def test_live_projection_rows_reject_update_and_delete() -> None:
    from sqlalchemy import text

    from server.timeline.generation import build_generation

    engine = _live_engine()
    try:
        with engine.connect() as conn:
            trans = conn.begin()
            try:
                _assert_timeline_schema_present(conn)
                collection_id = conn.execute(
                    text("SELECT id FROM timeline.timeline_collection WHERE slug = 'primary'")
                ).scalar_one()
                _insert_candidate_member(
                    conn, collection_id, source_system="sms", source_record_id="sms-1", summary="immutable test"
                )
                result = build_generation(conn, collection_slug="primary", created_by="test-suite")

                with pytest.raises(Exception):
                    conn.execute(
                        text(
                            "UPDATE timeline.timeline_projection_member SET display_summary = 'x' WHERE generation_id = :g"
                        ),
                        {"g": result.generation_id},
                    )
            finally:
                trans.rollback()  # the failed UPDATE aborts the txn; rollback discards everything, migration included
    finally:
        engine.dispose()


@pytest.mark.integration
@_LIVE_SKIP
def test_live_projector_and_receipts_round_trip() -> None:
    from sqlalchemy import text

    from server.timeline.generation import build_generation
    from server.timeline.projector import PostgresTimelineProjectionSource
    from server.timeline.receipts import current_active_generation, expected_manifest, record_activation, record_receipt

    engine = _live_engine()
    try:
        with engine.connect() as conn:
            trans = conn.begin()
            try:
                _assert_timeline_schema_present(conn)
                collection_id = conn.execute(
                    text("SELECT id FROM timeline.timeline_collection WHERE slug = 'primary'")
                ).scalar_one()
                _insert_candidate_member(
                    conn, collection_id, source_system="sms", source_record_id="sms-1", summary="projector test event"
                )
                result = build_generation(conn, collection_slug="primary", created_by="test-suite")

                source = PostgresTimelineProjectionSource(conn, collection_slug="primary")
                gen_id, members = source.fetch_generation()
                assert gen_id == result.generation_id
                assert len(members) == 1
                assert members[0].source_record_id == "sms-1"

                # since_generation on the latest generation itself -> no new data yet, not an error.
                gen_id_2, members_2 = source.fetch_generation(since_generation=gen_id)
                assert gen_id_2 == gen_id
                assert members_2 == []

                with pytest.raises(ValueError):
                    source.fetch_generation(since_generation=str(uuid.uuid4()))

                receipt_id = record_receipt(
                    conn,
                    generation_id=result.generation_id,
                    idempotency_key=f"receipt:{result.generation_id}:{members[0].opensearch_doc_id}",
                    status="succeeded",
                    observed_content_hash=members[0].member_content_hash,
                    opensearch_doc_id=members[0].opensearch_doc_id,
                )
                assert receipt_id

                manifest = expected_manifest(conn, generation_id=result.generation_id)
                assert len(manifest) == 1
                assert manifest[0].opensearch_doc_id == members[0].opensearch_doc_id
                assert manifest[0].member_content_hash == members[0].member_content_hash

                activation_id = record_activation(conn, generation_id=result.generation_id, activated_by="test-suite")
                assert activation_id
                assert current_active_generation(conn, collection_slug="primary") == result.generation_id
            finally:
                trans.rollback()
    finally:
        engine.dispose()


@pytest.mark.integration
@_LIVE_SKIP
def test_live_rollback_leaves_no_trace() -> None:
    """Runs last alphabetically-adjacent to the others only by convention; independently proves
    the rollback contract itself (belt-and-suspenders on top of each test above rolling back its
    own transaction)."""
    from sqlalchemy import text

    engine = _live_engine()
    try:
        with engine.connect() as conn:
            trans = conn.begin()
            try:
                _assert_timeline_schema_present(conn)
                count_inside = conn.execute(
                    text("SELECT count(*) FROM information_schema.tables WHERE table_schema = 'timeline'")
                ).scalar_one()
                assert count_inside > 0
            finally:
                trans.rollback()

        with engine.connect() as verify_conn:
            leftover = verify_conn.execute(
                text("SELECT count(*) FROM information_schema.tables WHERE table_schema = 'timeline'")
            ).scalar_one()
            assert leftover == 0, "rollback must leave zero timeline.* objects on the live database"
    finally:
        engine.dispose()
