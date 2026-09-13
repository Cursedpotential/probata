"""Focused contract tests for the Workbench Proffer BFF adapter.

Byline: Codex · GPT-5 · 2026-08-28.
"""

from __future__ import annotations

import asyncio
import json

import httpx

from app.config import Settings
from app.runtime import proffer as runtime
from app.service import proffer
from app.service import proffer_operations
from starlette.requests import Request

from app.types.proffer import (
    ProfferDecisionActor,
    ProfferDecisionRequest,
    ProfferPreviewResponse,
    ProfferRepairDecisionRequest,
    ProfferStartRequest,
)


PREVIEW_HANDLE = "preview_handle_abcdefghijklmnopqrstuvwxyz"
OTHER_PREVIEW_HANDLE = "preview_handle_zyxwvutsrqponmlkjihgfedcba"


def preview_payload(preview_handle: str = PREVIEW_HANDLE) -> dict:
    return {
        "preview_handle": preview_handle,
        "phase": "awaiting_decision",
        "correlation": {
            "request_id": "request-1",
            "source_version_id": "00000000-0000-0000-0000-000000000011",
            "raw_generation_id": "00000000-0000-0000-0000-000000000012",
            "normalized_generation_id": "00000000-0000-0000-0000-000000000013",
        },
        "parser": {
            "parser_id": "messages.sbv-xml-v1",
            "parser_version": "1.0.0",
            "config_digest": "a" * 64,
        },
        "preview_digest": "b" * 64,
        "receipts": [],
    }


def operation_payload(preview_handle: str = PREVIEW_HANDLE) -> dict:
    return {
        "preview_handle": preview_handle,
        "request_id": "request-1",
        "source_ref": "r2://casebible-sorted/photos/cat.jpg",
        "service": "proffer",
        "created_at": "2026-09-12T12:30:00Z",
        "lifecycle": "awaiting_repair_decision",
        "current_stage": "detect_repair_need",
        "active_stages": [],
        "wait": "repair_decision",
        "terminal": False,
        "reason": "detector found a repair issue",
        "source_version_ref": "00000000-0000-0000-0000-000000000011",
        "completed_stage_count": 3,
    }


def authenticated_request() -> Request:
    request = Request({"type": "http", "headers": []})
    request.state.subject_uid = "authentik-subject-123"
    request.state.principal = "matt"
    return request


def test_proffer_service_auth_configuration_contains_only_a_secret_path(monkeypatch) -> None:
    monkeypatch.delenv("PROFFER_SERVICE_TOKEN", raising=False)
    monkeypatch.delenv("PROFFER_SERVICE_TOKEN_FILE", raising=False)
    configured = Settings(_env_file=None)

    assert configured.proffer_service_token_file == "/run/secrets/proffer-service-token"
    assert not hasattr(configured, "proffer_service_token")


def test_models_reject_unknown_fields() -> None:
    try:
        ProfferStartRequest(
            request_id="r1",
            matter_id="00000000-0000-0000-0000-000000000001",
            court_case_id="00000000-0000-0000-0000-000000000002",
            source_ref=f"upload://{'a' * 64}",
            declared_format="pdf",
            parser_options_ref="opts-1",
            content="forbidden",
        )
    except Exception as error:
        assert "extra_forbidden" in str(error)
    else:
        raise AssertionError("unknown Proffer start fields must be rejected")


def test_decision_route_rejects_without_reason() -> None:
    async def exercise():
        return await runtime.decision_endpoint(
            PREVIEW_HANDLE,
            ProfferDecisionRequest(approved=False, reason=""),
            authenticated_request(),
        )

    try:
        asyncio.run(exercise())
    except Exception as error:
        assert getattr(error, "status_code", None) == 422
        assert "reason" in str(error.detail)
    else:
        raise AssertionError("blank rejection reason must be rejected")


def test_service_preserves_exact_upstream_contract(monkeypatch) -> None:
    class Response:
        def json(self):
            return {"preview_handle": PREVIEW_HANDLE}

    captured = {}
    monkeypatch.setattr(proffer.settings, "proffer_starter_url", "https://starter.internal")

    async def fake_request(method, path, **kwargs):
        captured.update(method=method, path=path, kwargs=kwargs)
        return Response()

    monkeypatch.setattr(proffer, "_request", fake_request)

    async def exercise():
        return await proffer.start(
            ProfferStartRequest(
                request_id="r1",
                matter_id="00000000-0000-0000-0000-000000000001",
                court_case_id="00000000-0000-0000-0000-000000000002",
                source_ref="r2://casebible-sorted/intake/source.pdf",
                declared_format="pdf",
                parser_options_ref="opts-1",
            )
        )

    result = asyncio.run(exercise())
    assert result.preview_handle == PREVIEW_HANDLE
    assert captured["method"] == "POST"
    assert captured["path"] == "/reference-import/start"
    assert captured["kwargs"]["json"]["source_ref"] == "r2://casebible-sorted/intake/source.pdf"
    assert captured["kwargs"]["json"]["matter_id"] == "00000000-0000-0000-0000-000000000001"
    assert captured["kwargs"]["json"]["court_case_id"] == "00000000-0000-0000-0000-000000000002"


def test_operation_list_forwards_only_engine_supported_filters(monkeypatch) -> None:
    class Response:
        def json(self):
            return {"items": [operation_payload()], "next_cursor": "next-page"}

    captured = {}

    async def fake_request(method, path, **kwargs):
        captured.update(method=method, path=path, kwargs=kwargs)
        return Response()

    monkeypatch.setattr(proffer, "_request", fake_request)
    result = asyncio.run(
        proffer_operations.list_operations(
            status="awaiting_repair_decision",
            cursor="current-page",
            limit=50,
        )
    )

    assert captured == {
        "method": "GET",
        "path": "/reference-import/operations",
        "kwargs": {
            "params": {
                "status": "awaiting_repair_decision",
                "cursor": "current-page",
                "limit": 50,
            }
        },
    }
    assert result.items[0].preview_handle == PREVIEW_HANDLE
    assert result.items[0].service == "proffer"
    assert result.next_cursor == "next-page"
    assert not hasattr(result.items[0], "workflow_id")
    assert not hasattr(result.items[0], "run_id")


def test_operation_detail_is_addressed_and_correlated_by_preview_handle(monkeypatch) -> None:
    class Response:
        def json(self):
            return {
                **operation_payload(),
                "stages": [
                    {
                        "stage": "register_source",
                        "status": "completed",
                        "receipt_ref": "receipt://register/1",
                        "attempt": 1,
                        "completed_at": "2026-09-12T12:30:01Z",
                    }
                ],
            }

    captured = {}

    async def fake_request(method, path, **kwargs):
        captured.update(method=method, path=path, kwargs=kwargs)
        return Response()

    monkeypatch.setattr(proffer, "_request", fake_request)
    result = asyncio.run(proffer_operations.operation(PREVIEW_HANDLE))

    assert captured == {
        "method": "GET",
        "path": f"/reference-import/operations/{PREVIEW_HANDLE}",
        "kwargs": {},
    }
    assert result.preview_handle == PREVIEW_HANDLE
    assert result.stages[0].stage == "register_source"


def test_operation_detail_rejects_a_different_preview_handle(monkeypatch) -> None:
    class Response:
        def json(self):
            return {**operation_payload(OTHER_PREVIEW_HANDLE), "stages": []}

    async def fake_request(*args, **kwargs):
        return Response()

    monkeypatch.setattr(proffer, "_request", fake_request)
    try:
        asyncio.run(proffer_operations.operation(PREVIEW_HANDLE))
    except proffer.ProfferError as error:
        assert error.status_code == 502
        assert "operation detail correlation failed" in error.detail
    else:
        raise AssertionError("operation detail for another preview handle must fail closed")


def test_start_fails_closed_when_upstream_has_only_temporal_ids(monkeypatch) -> None:
    class Response:
        def json(self):
            return {"workflow_id": "wf-1", "run_id": "run-1"}

    async def fake_request(*args, **kwargs):
        return Response()

    monkeypatch.setattr(proffer, "_request", fake_request)

    async def exercise():
        await proffer.start(
            ProfferStartRequest(
                request_id="r1",
                matter_id="00000000-0000-0000-0000-000000000001",
                court_case_id="00000000-0000-0000-0000-000000000002",
                source_ref=f"upload://{'a' * 64}",
                declared_format="pdf",
                parser_options_ref="opts-1",
            )
        )

    try:
        asyncio.run(exercise())
    except proffer.ProfferError as error:
        assert error.status_code == 502
        assert "invalid start response" in error.detail
    else:
        raise AssertionError("Temporal identifiers must never be relabeled as a preview handle")


def test_decision_identity_is_derived_from_authentik_request_state(monkeypatch) -> None:
    captured = {}

    async def fake_decide(preview_handle, body, actor):
        captured.update(handle=preview_handle, body=body.model_dump(), actor=actor.model_dump())
        return {"preview_handle": PREVIEW_HANDLE, "status": "accepted"}

    monkeypatch.setattr(runtime, "decide", fake_decide)

    result = asyncio.run(
        runtime.decision_endpoint(
            PREVIEW_HANDLE,
            ProfferDecisionRequest(approved=True, reason=""),
            authenticated_request(),
        )
    )
    assert result == {"preview_handle": PREVIEW_HANDLE, "status": "accepted"}
    assert captured["body"] == {"approved": True, "reason": ""}
    assert captured["actor"] == {
        "subject_uid": "authentik-subject-123",
        "username": "matt",
    }


def test_preview_decision_forwards_actor_only_in_trusted_headers(monkeypatch) -> None:
    class Response:
        def json(self):
            return {"preview_handle": PREVIEW_HANDLE, "status": "approved"}

    captured = {}

    async def fake_request(method, path, **kwargs):
        captured.update(method=method, path=path, kwargs=kwargs)
        return Response()

    monkeypatch.setattr(proffer, "_request", fake_request)
    actor = ProfferDecisionActor(subject_uid="authentik-subject-123", username="matt")
    asyncio.run(proffer.decide(PREVIEW_HANDLE, ProfferDecisionRequest(approved=True), actor))

    assert captured["kwargs"]["json"] == {"approved": True, "reason": ""}
    assert "actor" not in captured["kwargs"]["json"]
    assert captured["kwargs"]["headers"] == {
        "X-authentik-uid": "authentik-subject-123",
        "X-authentik-username": "matt",
    }


def test_decision_fails_closed_without_authenticated_subject() -> None:
    request = Request({"type": "http", "headers": []})

    try:
        asyncio.run(
            runtime.decision_endpoint(
                PREVIEW_HANDLE,
                ProfferDecisionRequest(approved=True, reason=""),
                request,
            )
        )
    except Exception as error:
        assert getattr(error, "status_code", None) == 401
    else:
        raise AssertionError("decision must require immutable proxy-authenticated identity")


def test_decision_fails_closed_for_header_unsafe_authenticated_identity() -> None:
    request = authenticated_request()
    request.state.principal = "forged\r\nheader"

    try:
        asyncio.run(
            runtime.decision_endpoint(
                PREVIEW_HANDLE,
                ProfferDecisionRequest(approved=True, reason=""),
                request,
            )
        )
    except Exception as error:
        assert getattr(error, "status_code", None) == 401
        assert "invalid" in error.detail
    else:
        raise AssertionError("header-unsafe actor identity must fail closed")


def test_decision_model_rejects_browser_supplied_actor_fields() -> None:
    for forbidden in ({"decider": "owner"}, {"role": "owner"}, {"subject_uid": "forged"}):
        try:
            ProfferDecisionRequest(approved=True, reason="", **forbidden)
        except Exception as error:
            assert "extra_forbidden" in str(error)
        else:
            raise AssertionError(f"browser actor field accepted: {next(iter(forbidden))}")


def test_upstream_preview_unknown_fields_are_ignored_compatibly() -> None:
    payload = preview_payload()
    payload["future_metadata"] = {"safe": True}
    payload["correlation"]["future_coordinate"] = "ignored"
    payload["parser"]["future_parser_field"] = 1

    result = ProfferPreviewResponse.model_validate(payload)

    assert result.preview_handle == PREVIEW_HANDLE
    assert not hasattr(result, "future_metadata")


def test_repair_assessment_is_readable_only_through_correlated_opaque_handle(monkeypatch) -> None:
    class Response:
        def json(self):
            return {
                "preview_handle": PREVIEW_HANDLE,
                "phase": "awaiting_repair_decision",
                "repair_assessment": {
                    "assessment_ref": "00000000-0000-0000-0000-000000000021",
                    "source_version_ref": "00000000-0000-0000-0000-000000000022",
                    "review_required": True,
                    "future_field": "compatible",
                },
            }

    async def fake_request(method, path, **kwargs):
        assert method == "GET"
        assert path == f"/reference-import/previews/{PREVIEW_HANDLE}"
        return Response()

    monkeypatch.setattr(proffer, "_request", fake_request)
    result = asyncio.run(proffer.preview(PREVIEW_HANDLE))

    assert result.phase == "awaiting_repair_decision"
    assert result.repair_assessment is not None
    assert result.repair_assessment.review_required is True


def test_clean_repair_assessment_is_read_only_and_needs_no_browser_decision(monkeypatch) -> None:
    class Response:
        def json(self):
            return {
                "preview_handle": PREVIEW_HANDLE,
                "phase": "repair_approved",
                "repair_assessment": {
                    "assessment_ref": "00000000-0000-0000-0000-000000000021",
                    "source_version_ref": "00000000-0000-0000-0000-000000000022",
                    "review_required": False,
                },
            }

    async def fake_request(*args, **kwargs):
        return Response()

    monkeypatch.setattr(proffer, "_request", fake_request)
    result = asyncio.run(proffer.preview(PREVIEW_HANDLE))

    assert result.repair_assessment is not None
    assert result.repair_assessment.review_required is False
    assert result.phase != "awaiting_repair_decision"


def test_preview_events_fail_closed_on_non_monotonic_replay() -> None:
    event = {
        "event_id": 5,
        "event_type": "phase_changed",
        "occurred_at": "2026-08-29T18:00:00Z",
        "preview_handle": PREVIEW_HANDLE,
        "phase": "awaiting_decision",
    }
    raw = f"id: 5\ndata: {json.dumps(event)}\n\nid: 5\ndata: {json.dumps(event)}\n\n"
    response = httpx.Response(200, content=raw.encode(), headers={"content-type": "text/event-stream"})

    async def exercise():
        emitted = []
        async for item in proffer.validated_preview_events(response, preview_handle=PREVIEW_HANDLE, last_event_id=4):
            emitted.append(item)
        return emitted

    try:
        asyncio.run(exercise())
    except proffer.ProfferError as error:
        assert error.status_code == 502
        assert "not monotonic" in error.detail
    else:
        raise AssertionError("duplicate Proffer preview event ids must fail closed")


def test_service_replaces_browser_authorization_with_runtime_service_token(monkeypatch, tmp_path) -> None:
    secret = tmp_path / "proffer-service-token"
    service_token = "s" * 32
    secret.write_text(service_token, encoding="utf-8")

    class Client:
        def __init__(self, *args, **kwargs):
            pass

        async def __aenter__(self):
            return self

        async def __aexit__(self, *args):
            return None

        async def request(self, method, url, **kwargs):
            assert kwargs["headers"]["Authorization"] == f"Bearer {service_token}"
            assert "authorization" not in kwargs["headers"]
            return httpx.Response(200, json={"workflow_id": "wf-1", "run_id": "run-1"})

    monkeypatch.setattr(proffer.settings, "proffer_starter_url", "https://starter.internal")
    monkeypatch.setattr(proffer.settings, "proffer_service_token_file", str(secret))
    monkeypatch.setattr(proffer.httpx, "AsyncClient", Client)

    async def exercise():
        return await proffer._request("GET", "/reference-import/wf-1/preview", headers={"Authorization": "forbidden"})

    asyncio.run(exercise())


def test_proffer_service_token_is_read_fresh_for_every_request(monkeypatch, tmp_path) -> None:
    secret = tmp_path / "proffer-service-token"
    monkeypatch.setattr(proffer.settings, "proffer_service_token_file", str(secret))
    first_token = "a" * 32
    rotated_token = "b" * 32
    secret.write_text(first_token, encoding="utf-8")

    assert proffer._service_authorization_headers() == {"Authorization": f"Bearer {first_token}"}

    secret.write_text(rotated_token, encoding="utf-8")
    assert proffer._service_authorization_headers() == {"Authorization": f"Bearer {rotated_token}"}


def test_proffer_service_token_accepts_maximum_token_with_crlf(monkeypatch, tmp_path) -> None:
    secret = tmp_path / "proffer-service-token"
    maximum_token = "m" * 4096
    secret.write_bytes(maximum_token.encode() + b"\r\n")
    monkeypatch.setattr(proffer.settings, "proffer_service_token_file", str(secret))

    assert proffer._service_authorization_headers() == {"Authorization": f"Bearer {maximum_token}"}


def test_invalid_proffer_service_token_fails_closed_without_leaking_value_or_path(monkeypatch, tmp_path) -> None:
    secret = tmp_path / "private-proffer-token"
    secret.write_text("forbidden token value", encoding="utf-8")
    monkeypatch.setattr(proffer.settings, "proffer_service_token_file", str(secret))

    try:
        proffer._service_authorization_headers()
    except proffer.ProfferError as error:
        assert error.status_code == 503
        assert error.detail == "Proffer service authentication is unavailable or invalid"
        assert "forbidden token value" not in error.detail
        assert str(secret) not in error.detail
    else:
        raise AssertionError("invalid Proffer service token must fail closed")


def test_short_proffer_service_token_fails_closed(monkeypatch, tmp_path) -> None:
    secret = tmp_path / "private-proffer-token"
    secret.write_text("s" * 31, encoding="utf-8")
    monkeypatch.setattr(proffer.settings, "proffer_service_token_file", str(secret))

    try:
        proffer._service_authorization_headers()
    except proffer.ProfferError as error:
        assert error.status_code == 503
        assert error.detail == "Proffer service authentication is unavailable or invalid"
    else:
        raise AssertionError("short Proffer service token must fail closed")


def test_missing_proffer_service_token_fails_closed_without_leaking_path(monkeypatch, tmp_path) -> None:
    secret = tmp_path / "missing-private-proffer-token"
    monkeypatch.setattr(proffer.settings, "proffer_service_token_file", str(secret))

    try:
        proffer._service_authorization_headers()
    except proffer.ProfferError as error:
        assert error.status_code == 503
        assert error.detail == "Proffer service authentication is unavailable or invalid"
        assert str(secret) not in error.detail
    else:
        raise AssertionError("missing Proffer service token must fail closed")


def test_preview_event_stream_reads_and_forwards_service_token(monkeypatch, tmp_path) -> None:
    secret = tmp_path / "proffer-service-token"
    stream_token = "e" * 32
    secret.write_text(stream_token, encoding="utf-8")
    captured = {}

    class Client:
        def __init__(self, *args, **kwargs):
            pass

        def build_request(self, method, url, **kwargs):
            request = httpx.Request(method, url, **kwargs)
            captured["request"] = request
            return request

        async def send(self, request, stream=False):
            return httpx.Response(
                200,
                headers={"content-type": "text/event-stream"},
                content=b"",
                request=request,
            )

        async def aclose(self):
            return None

    monkeypatch.setattr(proffer.settings, "proffer_starter_url", "https://starter.internal")
    monkeypatch.setattr(proffer.settings, "proffer_service_token_file", str(secret))
    monkeypatch.setattr(proffer.httpx, "AsyncClient", Client)

    client, response = asyncio.run(proffer.open_preview_event_stream(PREVIEW_HANDLE, last_event_id=4))
    assert captured["request"].headers["Authorization"] == f"Bearer {stream_token}"
    assert captured["request"].headers["Last-Event-ID"] == "4"
    asyncio.run(response.aclose())
    asyncio.run(client.aclose())


def test_upload_stream_reads_and_forwards_service_token(monkeypatch, tmp_path) -> None:
    secret = tmp_path / "proffer-service-token"
    upload_token = "u" * 32
    secret.write_text(upload_token, encoding="utf-8")
    captured = {}

    class Client:
        def __init__(self, *args, **kwargs):
            pass

        def build_request(self, method, url, **kwargs):
            kwargs.pop("content")
            request = httpx.Request(method, url, **kwargs)
            captured["request"] = request
            return request

        async def send(self, request, stream=False):
            return httpx.Response(201, content=b"{}", request=request)

        async def aclose(self):
            return None

    async def body():
        yield b"payload"

    monkeypatch.setattr(proffer.settings, "proffer_starter_url", "https://starter.internal")
    monkeypatch.setattr(proffer.settings, "proffer_service_token_file", str(secret))
    monkeypatch.setattr(proffer.httpx, "AsyncClient", Client)

    client, response = asyncio.run(
        proffer.open_upload_stream(body(), content_type="application/octet-stream", content_length="7")
    )
    assert captured["request"].headers["Authorization"] == f"Bearer {upload_token}"
    assert captured["request"].headers["Content-Length"] == "7"
    asyncio.run(response.aclose())
    asyncio.run(client.aclose())


def test_preview_requires_full_correlation_and_digest() -> None:
    try:
        ProfferPreviewResponse.model_validate({"preview_handle": PREVIEW_HANDLE, "phase": "awaiting_decision"})
    except Exception as error:
        assert "correlation" in str(error)
        assert "preview_digest" in str(error)
    else:
        raise AssertionError("partial preview snapshots must fail closed")


def test_service_fails_closed_without_dedicated_starter_configuration(monkeypatch) -> None:
    monkeypatch.setattr(proffer.settings, "proffer_starter_url", "")

    async def exercise():
        await proffer.start(
            ProfferStartRequest(
                request_id="r1",
                source_ref=f"upload://{'a' * 64}",
                declared_format="pdf",
                parser_options_ref="opts-1",
                matter_id="00000000-0000-0000-0000-000000000001",
                court_case_id="00000000-0000-0000-0000-000000000002",
            )
        )

    try:
        asyncio.run(exercise())
    except proffer.ProfferError as error:
        assert error.status_code == 503
    else:
        raise AssertionError("Proffer must fail closed when its dedicated settings are absent")


def test_start_rejects_malformed_matter_uuid() -> None:
    try:
        ProfferStartRequest(
            request_id="r1",
            matter_id="not-a-uuid",
            court_case_id="00000000-0000-0000-0000-000000000002",
            source_ref=f"upload://{'a' * 64}",
            declared_format="pdf",
            parser_options_ref="opts-1",
        )
    except Exception as error:
        assert "valid UUID" in str(error)
    else:
        raise AssertionError("malformed matter_id must be rejected")


def test_start_accepts_only_upload_or_fixed_casebible_sorted_scope() -> None:
    common = {
        "request_id": "r1",
        "matter_id": "00000000-0000-0000-0000-000000000001",
        "court_case_id": "00000000-0000-0000-0000-000000000002",
        "declared_format": "pdf",
        "parser_options_ref": "opts-1",
    }
    upload_ref = f"upload://{'a' * 64}"
    assert ProfferStartRequest(source_ref=upload_ref, **common).source_ref == upload_ref
    assert (
        ProfferStartRequest(source_ref="r2://casebible-sorted/folder/source.pdf", **common).source_ref
        == "r2://casebible-sorted/folder/source.pdf"
    )
    for forbidden in (
        "file:///etc/passwd",
        "b2://casebible-sorted/source.pdf",
        "r2://another-bucket/source.pdf",
        "r2://casebible-sorted/../source.pdf",
    ):
        try:
            ProfferStartRequest(source_ref=forbidden, **common)
        except Exception as error:
            assert "Case Bible Sorted" in str(error)
        else:
            raise AssertionError(f"forbidden source scope accepted: {forbidden}")


def test_preview_snapshot_requires_exact_requested_handle(monkeypatch) -> None:
    class Response:
        def json(self):
            return preview_payload(OTHER_PREVIEW_HANDLE)

    async def fake_request(*args, **kwargs):
        return Response()

    monkeypatch.setattr(proffer, "_request", fake_request)
    try:
        asyncio.run(proffer.preview(PREVIEW_HANDLE))
    except proffer.ProfferError as error:
        assert error.status_code == 502
        assert "snapshot correlation failed" in error.detail
    else:
        raise AssertionError("a snapshot for another preview handle must fail closed")


def test_preview_messages_require_exact_requested_handle(monkeypatch) -> None:
    class Response:
        def json(self):
            return {
                "preview_handle": OTHER_PREVIEW_HANDLE,
                "participants": [],
                "messages": [],
                "next_cursor": None,
            }

    async def fake_request(*args, **kwargs):
        return Response()

    monkeypatch.setattr(proffer, "_request", fake_request)
    try:
        asyncio.run(proffer.preview_messages(PREVIEW_HANDLE, cursor=None, limit=100))
    except proffer.ProfferError as error:
        assert error.status_code == 502
        assert "message correlation failed" in error.detail
    else:
        raise AssertionError("a message page for another preview handle must fail closed")


def test_malformed_json_is_normalized_to_502(monkeypatch) -> None:
    class Response:
        def json(self):
            raise json.JSONDecodeError("bad", "{", 1)

    async def fake_request(*args, **kwargs):
        return Response()

    monkeypatch.setattr(proffer, "_request", fake_request)
    try:
        asyncio.run(proffer.preview(PREVIEW_HANDLE))
    except proffer.ProfferError as error:
        assert error.status_code == 502
        assert "malformed JSON for preview snapshot" in error.detail
    else:
        raise AssertionError("malformed upstream JSON must use the BFF error contract")


def test_decision_response_requires_exact_requested_handle(monkeypatch) -> None:
    class Response:
        def json(self):
            return {"preview_handle": OTHER_PREVIEW_HANDLE, "status": "accepted"}

    async def fake_request(*args, **kwargs):
        return Response()

    monkeypatch.setattr(proffer, "_request", fake_request)
    try:
        asyncio.run(
            proffer.decide(
                PREVIEW_HANDLE,
                ProfferDecisionRequest(approved=True, reason=""),
                proffer.ProfferDecisionActor(subject_uid="subject-1", username="owner"),
            )
        )
    except proffer.ProfferError as error:
        assert error.status_code == 502
        assert "decision response correlation failed" in error.detail
    else:
        raise AssertionError("a decision response for another preview handle must fail closed")


def test_repair_decision_forwards_bounded_body_actor_headers_and_deterministic_key(monkeypatch) -> None:
    class Response:
        def json(self):
            return {
                "preview_handle": PREVIEW_HANDLE,
                "decision_ref": "00000000-0000-0000-0000-000000000099",
                "status": "signaled",
                "future_field": "compatible",
            }

    calls = []

    async def fake_request(method, path, **kwargs):
        calls.append((method, path, kwargs))
        return Response()

    monkeypatch.setattr(proffer, "_request", fake_request)
    actor = ProfferDecisionActor(subject_uid="authentik-subject-123", username="matt")
    body = ProfferRepairDecisionRequest(
        approved=True,
        apply_repair=True,
        tool_id="repair.write-derived",
        tool_payload={"destination_ref": "derived://repair/result"},
    )

    first = asyncio.run(proffer.decide_repair(PREVIEW_HANDLE, body, actor))
    second = asyncio.run(proffer.decide_repair(PREVIEW_HANDLE, body, actor))

    assert first.status == second.status == "signaled"
    assert calls[0][0:2] == (
        "POST",
        f"/reference-import/previews/{PREVIEW_HANDLE}/repair-decision",
    )
    assert calls[0][2]["json"] == body.model_dump(mode="json")
    assert "actor" not in calls[0][2]["json"]
    assert calls[0][2]["headers"]["X-authentik-uid"] == "authentik-subject-123"
    assert calls[0][2]["headers"]["X-authentik-username"] == "matt"
    assert calls[0][2]["headers"]["Idempotency-Key"].startswith("proffer-repair:")
    assert calls[0][2]["headers"]["Idempotency-Key"] == calls[1][2]["headers"]["Idempotency-Key"]


def test_repair_idempotency_key_changes_with_decision_content_not_username() -> None:
    actor = ProfferDecisionActor(subject_uid="subject-1", username="first-name")
    renamed_actor = ProfferDecisionActor(subject_uid="subject-1", username="renamed")
    approve = ProfferRepairDecisionRequest(approved=True, apply_repair=False)
    reject = ProfferRepairDecisionRequest(approved=False, apply_repair=False)

    first = proffer._repair_idempotency_key(PREVIEW_HANDLE, approve, actor)

    assert first == proffer._repair_idempotency_key(PREVIEW_HANDLE, approve, renamed_actor)
    assert first != proffer._repair_idempotency_key(PREVIEW_HANDLE, reject, actor)
    assert first != proffer._repair_idempotency_key(OTHER_PREVIEW_HANDLE, approve, actor)


def test_repair_decision_route_fails_closed_without_authenticated_identity() -> None:
    request = Request({"type": "http", "headers": []})

    try:
        asyncio.run(
            runtime.repair_decision_endpoint(
                PREVIEW_HANDLE,
                ProfferRepairDecisionRequest(approved=True, apply_repair=False),
                request,
            )
        )
    except Exception as error:
        assert getattr(error, "status_code", None) == 401
    else:
        raise AssertionError("repair decision must require proxy-authenticated identity")


def test_repair_decision_requires_exact_requested_handle(monkeypatch) -> None:
    class Response:
        def json(self):
            return {
                "preview_handle": OTHER_PREVIEW_HANDLE,
                "decision_ref": "00000000-0000-0000-0000-000000000099",
                "status": "signaled",
            }

    async def fake_request(*args, **kwargs):
        return Response()

    monkeypatch.setattr(proffer, "_request", fake_request)
    try:
        asyncio.run(
            proffer.decide_repair(
                PREVIEW_HANDLE,
                ProfferRepairDecisionRequest(approved=True, apply_repair=False),
                ProfferDecisionActor(subject_uid="subject-1", username="owner"),
            )
        )
    except proffer.ProfferError as error:
        assert error.status_code == 502
        assert "repair decision response correlation failed" in error.detail
    else:
        raise AssertionError("a repair decision for another preview handle must fail closed")


def test_repair_decision_route_preserves_upstream_error(monkeypatch) -> None:
    async def fake_decide_repair(*args, **kwargs):
        raise proffer.ProfferError("workflow is not awaiting repair", 409)

    monkeypatch.setattr(runtime, "decide_repair", fake_decide_repair)
    try:
        asyncio.run(
            runtime.repair_decision_endpoint(
                PREVIEW_HANDLE,
                ProfferRepairDecisionRequest(approved=True, apply_repair=False),
                authenticated_request(),
            )
        )
    except Exception as error:
        assert getattr(error, "status_code", None) == 409
        assert error.detail == "workflow is not awaiting repair"
    else:
        raise AssertionError("repair decision upstream errors must retain status and detail")
