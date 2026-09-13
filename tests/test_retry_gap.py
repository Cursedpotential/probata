"""Unit tests for the C3 "retry gap" fix (server/api/run_routes.py's
`retry_run`): `POST /v1/runs/{run_id}/retry {"from_stage": "knowledge"}` is
now ALSO allowed on a COMPLETED parent (not only 'failed') when the
knowledge collection can be shown to LACK the parent's doc — closing the
"reingest after collection loss" hole. 409 only when the doc VERIFIABLY
exists; a query failure/unknown result must be treated as "allow", never as
an implicit block.

Style matches tests/test_run_ledger.py's existing `run_routes_client` C2
TestClient section (same monkeypatch-the-module-under-test-by-name pattern).
"""
# Byline: Claude Code · Sonnet (agent) · 2026-07-22
# Byline: Codex · GPT-5 · 2026-08-13 (durable retry action contract)

from __future__ import annotations

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

import server.api.run_routes as run_routes


@pytest.mark.parametrize("body", [None, {"from_stage": "knowledge"}])
def test_unknown_retry_workflow_rejected_before_child_or_source_io(monkeypatch, body):
    """The exact orphan-producing workflow cannot commit or schedule a child."""
    historical = {"run_id": "failed-context", "status": "failed", "workflow": "framework-neutral-ingest"}
    monkeypatch.setattr(run_routes, "get_run", lambda _: historical.copy())

    def forbidden(*args, **kwargs):
        pytest.fail("unsupported retry attempted a mutation or source access")

    for name in ("create_run", "seed_stages", "record_review_action", "blob_root"):
        monkeypatch.setattr(run_routes, name, forbidden)
    app = FastAPI()
    run_routes.register_run_routes(app, knowledge=None)
    with TestClient(app) as client:
        response = client.post("/v1/runs/failed-context/retry", json=body)
    assert response.status_code == 410
    assert "Go Proffer" in response.json()["detail"]
    assert historical["status"] == "failed"


class _FakeWeaviateClient:
    """Mimics the v4-client call chain the existence check uses:
    client.collections.get(name).query.fetch_objects(limit=, filters=).objects"""

    def __init__(self, rows=None, raise_exc=None):
        self._rows = rows if rows is not None else []
        self._raise = raise_exc

    @property
    def collections(self):
        outer = self

        class _Collections:
            def get(self, name):
                class _Query:
                    def fetch_objects(self, limit=1, filters=None):
                        if outer._raise is not None:
                            raise outer._raise

                        class _Result:
                            objects = outer._rows

                        return _Result()

                class _Handle:
                    query = _Query()

                return _Handle()

        return _Collections()


class _FakeVectorDb:
    def __init__(self, client):
        self._client = client
        self.collection = "platform_knowledge"

    def get_client(self):
        return self._client


class _FakeKnowledge:
    def __init__(self, client):
        self.vector_db = _FakeVectorDb(client)


def _completed_run(**overrides):
    run = {
        "status": "completed",
        "workflow": "chat-transcript",
        "domain": "platform_design",
        "mode": "auto",
        "custody_tier": "light",
        "source_name": "f.txt",
        "artifact_id": "art-1",
        "sha256": "ab" * 32,
        "stages": [
            {"name": "custody", "status": "success", "output": {"blob_key": "ab/abc/f.txt"}},
            {"name": "parse", "status": "success", "output": {}},
            {"name": "store", "status": "success", "output": {}},
            {"name": "knowledge", "status": "success", "output": {}},
        ],
    }
    run.update(overrides)
    return run


@pytest.fixture
def client_with_knowledge(monkeypatch):
    monkeypatch.setattr(
        run_routes,
        "record_review_action",
        lambda run_id, action_type, reason, **kwargs: {
            "action_id": "action-1",
            "run_id": run_id,
            "action_type": action_type,
            "actor": "owner",
            "reason": reason,
            **kwargs,
        },
    )

    def _make(knowledge):
        app = FastAPI()
        run_routes.register_run_routes(app, knowledge=knowledge)
        return TestClient(app)

    return _make


def _stub_retry_from_knowledge_plumbing(monkeypatch):
    """Stub create_run/seed_stages/asyncio.create_task the same way
    test_run_ledger.py's C2 retry tests do, so `_retry_from_knowledge`'s
    background task never actually touches the DB/workflow machinery."""
    monkeypatch.setattr(run_routes, "create_run", lambda **kwargs: "new-run-id")
    monkeypatch.setattr(run_routes, "seed_stages", lambda run_id, names: None)

    created_tasks = []

    def fake_create_task(coro):
        created_tasks.append(coro)
        coro.close()
        return None

    monkeypatch.setattr(run_routes.asyncio, "create_task", fake_create_task)
    return created_tasks


def test_retry_gap_completed_run_doc_exists_is_409(client_with_knowledge, monkeypatch):
    monkeypatch.setattr(run_routes, "get_run", lambda run_id: _completed_run())
    client = client_with_knowledge(_FakeKnowledge(_FakeWeaviateClient(rows=[{"id": 1}])))

    resp = client.post("/v1/runs/run-1/retry", json={"from_stage": "knowledge"})

    assert resp.status_code == 409
    assert "VERIFIABLY EXISTS" in resp.json()["detail"]


def test_retry_gap_completed_run_doc_missing_is_allowed(client_with_knowledge, monkeypatch):
    monkeypatch.setattr(run_routes, "get_run", lambda run_id: _completed_run())
    _stub_retry_from_knowledge_plumbing(monkeypatch)
    client = client_with_knowledge(_FakeKnowledge(_FakeWeaviateClient(rows=[])))

    resp = client.post("/v1/runs/run-1/retry", json={"from_stage": "knowledge"})

    assert resp.status_code == 202
    assert resp.json() == {"run_id": "new-run-id", "parent_run_id": "run-1"}


def test_retry_gap_completed_run_query_failure_is_treated_as_allow(client_with_knowledge, monkeypatch):
    monkeypatch.setattr(run_routes, "get_run", lambda run_id: _completed_run())
    _stub_retry_from_knowledge_plumbing(monkeypatch)
    client = client_with_knowledge(_FakeKnowledge(_FakeWeaviateClient(raise_exc=RuntimeError("Weaviate down"))))

    resp = client.post("/v1/runs/run-1/retry", json={"from_stage": "knowledge"})

    assert resp.status_code == 202  # unknown -> allow, never an implicit block


def test_retry_gap_completed_run_no_knowledge_handle_is_treated_as_allow(client_with_knowledge, monkeypatch):
    monkeypatch.setattr(run_routes, "get_run", lambda run_id: _completed_run())
    _stub_retry_from_knowledge_plumbing(monkeypatch)
    client = client_with_knowledge(None)  # no knowledge at all — e.g. Milvus never came up

    resp = client.post("/v1/runs/run-1/retry", json={"from_stage": "knowledge"})

    assert resp.status_code == 202


def test_retry_gap_completed_run_without_sha256_is_409(client_with_knowledge, monkeypatch):
    monkeypatch.setattr(run_routes, "get_run", lambda run_id: _completed_run(sha256=None))
    client = client_with_knowledge(None)

    resp = client.post("/v1/runs/run-1/retry", json={"from_stage": "knowledge"})

    assert resp.status_code == 409


def test_retry_gap_running_run_from_stage_knowledge_is_409(client_with_knowledge, monkeypatch):
    monkeypatch.setattr(run_routes, "get_run", lambda run_id: _completed_run(status="running"))
    client = client_with_knowledge(None)

    resp = client.post("/v1/runs/run-1/retry", json={"from_stage": "knowledge"})

    assert resp.status_code == 409


def test_retry_gap_failed_run_from_stage_knowledge_skips_doc_check_entirely(client_with_knowledge, monkeypatch):
    """Pre-existing C2.6 behavior, UNCHANGED: a 'failed' parent's
    from_stage='knowledge' retry never even calls the doc-existence check —
    only 'completed' parents are gated by it."""
    queried = []

    class _WatchedClient(_FakeWeaviateClient):
        @property
        def collections(self):
            queried.append(1)
            return super().collections

    monkeypatch.setattr(run_routes, "get_run", lambda run_id: _completed_run(status="failed"))
    _stub_retry_from_knowledge_plumbing(monkeypatch)
    client = client_with_knowledge(_FakeKnowledge(_WatchedClient(rows=[{"id": 1}])))

    resp = client.post("/v1/runs/run-1/retry", json={"from_stage": "knowledge"})

    assert resp.status_code == 202
    assert queried == []  # doc-existence check never ran for a 'failed' parent


def test_retry_gap_plain_retry_still_requires_failed_status(client_with_knowledge, monkeypatch):
    """No from_stage given: the pre-C3 full-rerun path is UNCHANGED — a
    completed run still can't be fully rerun via a bare retry."""
    monkeypatch.setattr(run_routes, "get_run", lambda run_id: _completed_run())
    client = client_with_knowledge(None)

    resp = client.post("/v1/runs/run-1/retry")

    assert resp.status_code == 409
