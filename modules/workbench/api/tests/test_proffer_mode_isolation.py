"""Focused TEST/REAL isolation checks for the Workbench Proffer BFF."""

from __future__ import annotations

import asyncio
from datetime import UTC, datetime
import json

from fastapi import FastAPI
from fastapi.testclient import TestClient
import httpx
import pytest

from app.runtime import case_management, proffer as proffer_runtime, source_inspection
from app.service import matter_mode, proffer, proffer_sources, source_context
from app.service.matter_mode import _clear_preview_modes_for_tests, require_preview_mode
from app.types.proffer import (
    ProfferDecisionActor,
    ProfferHandlerSelectionDecisionRequest,
    ProfferPreviewResponse,
    ProfferStartRequest,
)
from app.types.source_context import SourceContextCreateRequest


TEST_MATTER_ID = "deadbeef-dead-beef-dead-beefdeadbeef"
TEST_COURT_CASE_ID = "cafebabe-cafe-babe-cafe-babecafebabe"
PREVIEW_HANDLE = "preview_handle_abcdefghijklmnopqrstuvwxyz"

CASE_MANAGEMENT_SCOPED_OPERATIONS = [
    ("/api/matters", "get"),
    ("/api/matters", "post"),
    ("/api/matters/{matter_id}", "get"),
    ("/api/matters/{matter_id}/court-cases", "post"),
    ("/api/matters/{matter_id}/knowledge/resolve", "post"),
    ("/api/matters/{matter_id}/evidence-items", "post"),
    ("/api/matters/{matter_id}/evidence-items", "get"),
    ("/api/matters/{matter_id}/evidence-items/{evidence_item_id}", "get"),
    (
        "/api/matters/{matter_id}/evidence-items/{evidence_item_id}/source-content",
        "get",
    ),
    (
        "/api/matters/{matter_id}/evidence-items/{evidence_item_id}/conversation-context",
        "get",
    ),
    (
        "/api/matters/{matter_id}/evidence-items/{evidence_item_id}/court-readiness",
        "get",
    ),
    ("/api/matters/{matter_id}/evidence-items/{evidence_item_id}/reviews", "post"),
    ("/api/matters/{matter_id}/evidence-items/{evidence_item_id}/reviews", "get"),
]


@pytest.fixture(autouse=True)
def clear_bindings():
    _clear_preview_modes_for_tests()
    yield
    _clear_preview_modes_for_tests()


def _start_request(*, mode: str = "TEST", matter_id: str = TEST_MATTER_ID) -> ProfferStartRequest:
    return ProfferStartRequest(
        request_id="request-1",
        matter_id=matter_id,
        court_case_id=TEST_COURT_CASE_ID,
        source_ref="r2://casebible-raw/source.xml",
        declared_format="xml",
        parser_options_ref="parser-options://default",
        matter_mode=mode,
    )


def test_real_mode_fails_closed_before_source_io(monkeypatch) -> None:
    monkeypatch.setattr(proffer.settings, "proffer_real_matter_id", "")
    monkeypatch.setattr(
        proffer_sources,
        "list_source_objects",
        lambda **_: (_ for _ in ()).throw(AssertionError("source I/O must not run")),
    )

    with pytest.raises(proffer.ProfferError) as captured:
        proffer.browse_sources(mode="REAL")

    assert captured.value.status_code == 503
    assert "REAL matter identity is not configured" in captured.value.detail


def test_start_strips_bff_mode_binds_handle_and_rejects_cross_mode(monkeypatch) -> None:
    class Response:
        def json(self):
            return {"preview_handle": PREVIEW_HANDLE}

    captured: dict = {}

    async def fake_request(method, path, **kwargs):
        captured.update(method=method, path=path, kwargs=kwargs)
        return Response()

    monkeypatch.setattr(proffer, "_request", fake_request)
    result = asyncio.run(proffer.start(_start_request(), mode="TEST"))

    assert result.matter_mode == "TEST"
    assert "matter_mode" not in captured["kwargs"]["json"]
    require_preview_mode(PREVIEW_HANDLE, "TEST")
    with pytest.raises(proffer.ProfferError) as denied:
        asyncio.run(proffer.preview(PREVIEW_HANDLE, mode="REAL"))
    assert denied.value.status_code == 409
    assert "different matter mode" in denied.value.detail


def test_start_body_query_and_exact_test_scope_are_enforced_before_upstream(monkeypatch) -> None:
    monkeypatch.setattr(
        proffer,
        "_request",
        lambda *args, **kwargs: (_ for _ in ()).throw(AssertionError("upstream must not run")),
    )

    with pytest.raises(proffer.ProfferError) as mode_error:
        asyncio.run(proffer.start(_start_request(mode="TEST"), mode="REAL"))
    assert mode_error.value.status_code == 409

    with pytest.raises(proffer.ProfferError) as matter_error:
        asyncio.run(
            proffer.start(
                _start_request(matter_id="11111111-1111-4111-8111-111111111111"),
                mode="TEST",
            )
        )
    assert matter_error.value.status_code == 409
    assert "matter_id does not belong to TEST" in matter_error.value.detail


def test_unknown_handle_fails_closed_after_process_binding_loss() -> None:
    with pytest.raises(proffer.ProfferError) as captured:
        asyncio.run(proffer.preview(PREVIEW_HANDLE, mode="TEST"))

    assert captured.value.status_code == 409
    assert "no active TEST/REAL binding" in captured.value.detail


def test_generic_content_projection_preserves_exact_chunks_and_mode(monkeypatch) -> None:
    from app.service.matter_mode import bind_preview_mode

    bind_preview_mode(PREVIEW_HANDLE, "TEST")

    async def fake_request(method, path, **kwargs):
        assert method == "GET"
        assert path.endswith("/content")
        assert kwargs["params"] == {"limit": 25, "record_cursor": "records-next"}
        return httpx.Response(
            200,
            json={
                "preview_handle": PREVIEW_HANDLE,
                "package": {
                    "source_version_ref": "source-version-1",
                    "declared_format": "document",
                    "status": "retained",
                    "metadata_count": 2,
                    "attachment_count": 0,
                },
                "attempt": {
                    "attempt_ref": "",
                    "projection_ref": "normalized-1",
                    "source_version_ref": "source-version-1",
                    "raw_generation_ref": "raw-1",
                    "normalized_generation_ref": "normalized-1",
                    "receipts": [],
                },
                "attempts_complete": False,
                "attempts_reason": "complete history is unavailable",
                "records": [{
                    "record_id": "record-1", "ordinal": 0, "record_type": "document",
                    "payload": {"title": "Exact record"},
                    "source_locator_ref": "context.normalized_record_identity/record-1",
                }],
                "attachments": [],
                "chunk_generation": {
                    "generation_ref": "generation-1", "generation_ordinal": 1, "status": "sealed",
                    "policy_id": "document", "policy_version": "1", "chunker_id": "offsets",
                    "chunker_version": "1", "schema_version": "1", "source_view": "original",
                    "source_sha256": "a" * 64, "receipt_ref": "receipt-1",
                },
                "chunks": [{
                    "chunk_ref": "chunk-1", "index": 0, "content": "Exact chunk",
                    "sha256": "b" * 64, "derivation_mode": "verbatim_span",
                    "locator_ref": "locator-1", "byte_start": 0, "byte_end": 11,
                }],
            },
        )

    monkeypatch.setattr(proffer, "_request", fake_request)
    result = asyncio.run(proffer.preview_content(
        PREVIEW_HANDLE, mode="TEST", record_cursor="records-next", chunk_cursor=None, limit=25
    ))

    assert result.matter_mode == "TEST"
    assert result.records[0].payload == {"title": "Exact record"}
    assert result.chunks[0].content == "Exact chunk"
    with pytest.raises(proffer.ProfferError, match="different matter mode"):
        asyncio.run(proffer.preview_content(
            PREVIEW_HANDLE, mode="REAL", record_cursor=None, chunk_cursor=None, limit=25
        ))


def test_handler_choice_is_flat_actor_bound_and_mode_correlated(monkeypatch) -> None:
    calls: list[tuple[str, str, dict]] = []

    async def fake_request(method, path, **kwargs):
        calls.append((method, path, kwargs))
        if method == "GET":
            return httpx.Response(
                200,
                json={
                    "preview_handle": PREVIEW_HANDLE,
                    "phase": "awaiting_handler_selection",
                    "handler_recommendation_ref": "handler-recommendation://123",
                    "detected_format": "callsbackuprestore_xml",
                    "detected_format_ref": "detected-format://123",
                    "signature_ref": "signature://calls-root-v1",
                    "recommended_handler": {
                        "handler_id": "duckdb.calls",
                        "handler_version": "1.0.0",
                        "execution_path": "duckdb",
                        "compatibility_ref": "compatibility://123",
                        "reason": "The root element is calls.",
                    },
                    "alternative_handlers": [],
                },
            )
        return httpx.Response(
            200,
            json={
                "preview_handle": PREVIEW_HANDLE,
                "decision_ref": "handler-decision://123",
                "status": "persisted",
            },
        )

    monkeypatch.setattr(proffer, "_request", fake_request)
    from app.service.matter_mode import bind_preview_mode

    bind_preview_mode(PREVIEW_HANDLE, "TEST")
    choice = ProfferHandlerSelectionDecisionRequest(
        recommendation_ref="handler-recommendation://123",
        handler_id="duckdb.calls",
        handler_version="1.0.0",
        execution_path="duckdb",
        compatibility_ref="compatibility://123",
    )
    actor = ProfferDecisionActor(subject_uid="subject-1", username="operator")

    result = asyncio.run(proffer.decide_handler_selection(PREVIEW_HANDLE, choice, actor, mode="TEST"))

    assert result.matter_mode == "TEST"
    assert calls[1][2]["json"] == {"compatibility_ref": "compatibility://123"}
    assert calls[1][2]["headers"]["X-authentik-uid"] == "subject-1"
    assert calls[1][2]["headers"]["X-authentik-username"] == "operator"
    assert calls[1][2]["headers"]["Idempotency-Key"].startswith("proffer-handler-selection:")
    assert result.decision_ref == "handler-decision://123"


def test_handler_choice_outside_current_recommendation_never_posts(monkeypatch) -> None:
    calls: list[str] = []

    async def fake_request(method, path, **kwargs):
        calls.append(method)
        return httpx.Response(
            200,
            json={
                "preview_handle": PREVIEW_HANDLE,
                "phase": "awaiting_handler_selection",
                "handler_recommendation_ref": "handler-recommendation://123",
                "detected_format": "callsbackuprestore_xml",
                "detected_format_ref": "detected-format://123",
                "signature_ref": "signature://calls-root-v1",
                "recommended_handler": {
                    "handler_id": "duckdb.calls",
                    "handler_version": "1.0.0",
                    "execution_path": "duckdb",
                    "compatibility_ref": "compatibility://123",
                    "reason": "The root element is calls.",
                },
                "alternative_handlers": [],
            },
        )

    monkeypatch.setattr(proffer, "_request", fake_request)
    from app.service.matter_mode import bind_preview_mode

    bind_preview_mode(PREVIEW_HANDLE, "TEST")
    actor = ProfferDecisionActor(subject_uid="subject-1", username="operator")
    incompatible = ProfferHandlerSelectionDecisionRequest(
        recommendation_ref="handler-recommendation://123",
        handler_id="decoder.sms",
        handler_version="1.0.0",
        execution_path="decoder",
        compatibility_ref="compatibility://not-offered",
    )

    with pytest.raises(proffer.ProfferError) as denied:
        asyncio.run(proffer.decide_handler_selection(PREVIEW_HANDLE, incompatible, actor, mode="TEST"))

    assert denied.value.status_code == 409
    assert calls == ["GET"]


def test_source_context_mode_is_validated_but_not_forwarded_upstream(monkeypatch) -> None:
    class Response:
        def json(self):
            return {
                "source_context_ref": "33333333-3333-4333-8333-333333333333",
                "receipt_ref": "source-context://33333333-3333-4333-8333-333333333333",
                "content_digest": "a" * 64,
                "revision": 1,
                "recorded_at": "2026-09-12T20:00:00Z",
            }

    captured: dict = {}

    async def fake_request(method, path, **kwargs):
        captured.update(method=method, path=path, kwargs=kwargs)
        return Response()

    monkeypatch.setattr(source_context, "_request", fake_request)
    body = SourceContextCreateRequest.model_validate(
        {
            "request_id": "request-1",
            "matter_id": TEST_MATTER_ID,
            "court_case_id": TEST_COURT_CASE_ID,
            "source_ref": "r2://casebible-raw/source.xml",
            "observed_source": {
                "key": "source.xml",
                "name": "source.xml",
                "byte_length": 10,
                "etag": '"etag"',
                "preview_sha256": "b" * 64,
            },
            "assertions": {"source_class": "unknown"},
            "change_reason": "Initial operator context",
            "matter_mode": "TEST",
        }
    )
    actor = ProfferDecisionActor(subject_uid="subject-1", username="operator")

    receipt = asyncio.run(source_context.create_source_context(body, actor, mode="TEST"))

    assert receipt.matter_mode == "TEST"
    assert "matter_mode" not in captured["kwargs"]["json"]
    assert captured["kwargs"]["json"]["matter_id"] == TEST_MATTER_ID


def test_preview_exposes_complete_content_backed_recommendation() -> None:
    preview = ProfferPreviewResponse.model_validate(
        {
            "preview_handle": PREVIEW_HANDLE,
            "matter_mode": "TEST",
            "phase": "awaiting_handler_selection",
            "handler_recommendation_ref": "recommendation://123",
            "detected_format": "callsbackuprestore_xml",
            "detected_format_ref": "detected-format://123",
            "signature_ref": "signature://calls-root-v1",
            "recommended_handler": {
                "handler_id": "duckdb.calls",
                "handler_version": "1.0.0",
                "execution_path": "duckdb",
                "compatibility_ref": "compatibility://123",
                "reason": "The root element is calls.",
            },
            "alternative_handlers": [],
        }
    )

    assert preview.detected_format == "callsbackuprestore_xml"
    assert preview.recommended_handler is not None
    assert preview.recommended_handler.execution_path == "duckdb"


def test_preview_event_is_re_emitted_with_mode() -> None:
    raw = {
        "event_id": 1,
        "event_type": "phase_changed",
        "occurred_at": "2026-09-12T20:00:00Z",
        "preview_handle": PREVIEW_HANDLE,
        "phase": "parser_execution",
    }
    response = httpx.Response(
        200,
        content=f"id: 1\ndata: {json.dumps(raw)}\n\n".encode(),
        headers={"content-type": "text/event-stream"},
    )

    async def collect() -> list[str]:
        return [
            item
            async for item in proffer.validated_preview_events(
                response,
                preview_handle=PREVIEW_HANDLE,
                mode="TEST",
                last_event_id=None,
            )
        ]

    emitted = asyncio.run(collect())
    assert '"matter_mode":"TEST"' in emitted[0]


def test_mode_is_required_on_every_scoped_http_operation() -> None:
    app = FastAPI()
    app.include_router(case_management.router)
    app.include_router(proffer_runtime.router)
    app.include_router(source_inspection.router)
    schema = app.openapi()
    operations = CASE_MANAGEMENT_SCOPED_OPERATIONS + [
        ("/api/proffer/sources", "get"),
        ("/api/proffer/upload", "post"),
        ("/api/proffer/source-inspection", "post"),
        ("/api/proffer/source-contexts", "post"),
        ("/api/proffer/start", "post"),
        ("/api/proffer/previews/{preview_handle}", "get"),
        ("/api/proffer/previews/{preview_handle}/messages", "get"),
        ("/api/proffer/previews/{preview_handle}/content", "get"),
        ("/api/proffer/previews/{preview_handle}/events", "get"),
        ("/api/proffer/previews/{preview_handle}/decision", "post"),
        ("/api/proffer/previews/{preview_handle}/repair-decision", "post"),
        ("/api/proffer/previews/{preview_handle}/handler-selection", "post"),
    ]
    for path, method in operations:
        parameters = schema["paths"][path][method]["parameters"]
        mode = next(item for item in parameters if item["name"] == "mode" and item["in"] == "query")
        assert mode["required"] is True, f"{method.upper()} {path} must require mode"
        assert mode["schema"]["enum"] == ["TEST", "REAL"]


def test_matters_route_fetches_only_exact_configured_id_and_echoes_mode(monkeypatch) -> None:
    calls: list[str] = []
    now = datetime(2026, 9, 12, tzinfo=UTC).isoformat()

    def fake_get(matter_id):
        calls.append(str(matter_id))
        return {
            "id": TEST_MATTER_ID,
            "title": "Configured DEV matter",
            "description": None,
            "status": "active",
            "partition_keys": ["test"],
            "court_cases": [],
            "created_at": now,
            "updated_at": now,
        }

    monkeypatch.setattr(case_management.service, "get_matter", fake_get)
    monkeypatch.setattr(
        case_management.service,
        "list_matters",
        lambda **_: (_ for _ in ()).throw(AssertionError("title/list inference is forbidden")),
    )
    app = FastAPI()
    app.include_router(case_management.router)

    response = TestClient(app).get("/api/matters?mode=TEST")

    assert response.status_code == 200
    assert calls == [TEST_MATTER_ID]
    assert response.json()["matter_mode"] == "TEST"
    assert response.json()["data"][0]["matter_mode"] == "TEST"


def _case_route_requests(matter_id: str) -> list[tuple[str, str, dict | None]]:
    evidence_item_id = "88888888-8888-4888-8888-888888888888"
    source = {
        "lane": "evidence",
        "partition_key": "primary",
        "artifact_id": "33333333-3333-4333-8333-333333333333",
        "sha256": "a" * 64,
        "retrieval_ref": "hit-1",
    }
    return [
        ("POST", f"/api/matters/{matter_id}/court-cases", {"caption": "Configured case"}),
        ("POST", f"/api/matters/{matter_id}/knowledge/resolve", source),
        (
            "POST",
            f"/api/matters/{matter_id}/evidence-items",
            {
                "court_case_id": TEST_COURT_CASE_ID,
                "source": {
                    **source,
                    "normalized_record_id": "44444444-4444-4444-8444-444444444444",
                },
                "title": "Draft evidence",
            },
        ),
        ("GET", f"/api/matters/{matter_id}/evidence-items", None),
        ("GET", f"/api/matters/{matter_id}/evidence-items/{evidence_item_id}", None),
        (
            "GET",
            f"/api/matters/{matter_id}/evidence-items/{evidence_item_id}/source-content",
            None,
        ),
        (
            "GET",
            f"/api/matters/{matter_id}/evidence-items/{evidence_item_id}/conversation-context",
            None,
        ),
        (
            "GET",
            f"/api/matters/{matter_id}/evidence-items/{evidence_item_id}/court-readiness",
            None,
        ),
        (
            "POST",
            f"/api/matters/{matter_id}/evidence-items/{evidence_item_id}/reviews",
            {"decision": "approved", "rationale": "Exact record reviewed."},
        ),
        ("GET", f"/api/matters/{matter_id}/evidence-items/{evidence_item_id}/reviews", None),
    ]


def _deny_all_case_management_upstream(monkeypatch) -> None:
    def forbidden(*args, **kwargs):
        raise AssertionError("case-management upstream must not run")

    for name in (
        "create_matter",
        "create_court_case",
        "resolve_knowledge_source",
        "create_evidence_item",
        "list_evidence_items",
        "get_evidence_detail",
        "get_original_source_content",
        "get_conversation_context",
        "get_court_readiness",
        "review_evidence_item",
        "list_evidence_reviews",
    ):
        monkeypatch.setattr(case_management.service, name, forbidden)


@pytest.mark.parametrize(
    ("method", "path", "payload"),
    _case_route_requests("11111111-1111-4111-8111-111111111111"),
)
def test_arbitrary_matter_ids_fail_before_case_management_upstream(
    monkeypatch,
    method: str,
    path: str,
    payload: dict | None,
) -> None:
    _deny_all_case_management_upstream(monkeypatch)
    app = FastAPI()
    app.include_router(case_management.router)

    response = TestClient(app).request(method, path, params={"mode": "TEST"}, json=payload)

    assert response.status_code == 409
    assert response.json() == {"detail": "matter_id does not belong to TEST mode"}


@pytest.mark.parametrize(("method", "path", "payload"), _case_route_requests(TEST_MATTER_ID))
def test_cross_mode_matter_ids_fail_before_case_management_upstream(
    monkeypatch,
    method: str,
    path: str,
    payload: dict | None,
) -> None:
    _deny_all_case_management_upstream(monkeypatch)
    monkeypatch.setattr(
        case_management.service,
        "get_matter",
        lambda *_: (_ for _ in ()).throw(AssertionError("case-management upstream must not run")),
    )
    monkeypatch.setattr(
        matter_mode.settings,
        "proffer_real_matter_id",
        "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
    )
    monkeypatch.setattr(
        matter_mode.settings,
        "proffer_real_court_case_id",
        "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
    )
    app = FastAPI()
    app.include_router(case_management.router)

    response = TestClient(app).request(method, path, params={"mode": "REAL"}, json=payload)

    assert response.status_code == 409
    assert response.json() == {"detail": "matter_id does not belong to REAL mode"}


def test_evidence_create_rejects_arbitrary_court_scope_before_upstream(monkeypatch) -> None:
    _deny_all_case_management_upstream(monkeypatch)
    method, path, payload = _case_route_requests(TEST_MATTER_ID)[2]
    assert payload is not None
    payload["court_case_id"] = "22222222-2222-4222-8222-222222222222"
    app = FastAPI()
    app.include_router(case_management.router)

    response = TestClient(app).request(method, path, params={"mode": "TEST"}, json=payload)

    assert response.status_code == 409
    assert response.json() == {"detail": "court_case_id does not belong to TEST mode"}


def test_matter_creation_is_explicitly_disabled_without_upstream(monkeypatch) -> None:
    _deny_all_case_management_upstream(monkeypatch)
    app = FastAPI()
    app.include_router(case_management.router)

    response = TestClient(app).post(
        "/api/matters",
        params={"mode": "TEST"},
        json={"title": "A generated identity cannot satisfy the fixed scope"},
    )

    assert response.status_code == 409
    assert response.json() == {
        "detail": (
            "Matter creation is disabled in fixed TEST/REAL mode; "
            "provision the configured matter identity outside this scoped runtime"
        )
    }


@pytest.mark.parametrize(
    ("method", "path", "payload"),
    [("GET", "/api/matters", None), ("POST", "/api/matters", {"title": "Unavailable"})]
    + _case_route_requests(TEST_MATTER_ID),
)
def test_unconfigured_real_scope_fails_closed_before_case_management_upstream(
    monkeypatch,
    method: str,
    path: str,
    payload: dict | None,
) -> None:
    _deny_all_case_management_upstream(monkeypatch)
    monkeypatch.setattr(matter_mode.settings, "proffer_real_matter_id", "")
    app = FastAPI()
    app.include_router(case_management.router)

    response = TestClient(app).request(method, path, params={"mode": "REAL"}, json=payload)

    assert response.status_code == 503
    assert response.json() == {"detail": "REAL matter identity is not configured"}
