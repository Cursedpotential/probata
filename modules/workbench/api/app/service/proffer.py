"""Authenticated pass-through to the Proffer starter.

Byline: Codex · GPT-5 · 2026-08-28.
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
import re
import stat
from typing import Any

import httpx
from pydantic import ValidationError

from app.config import settings
from app.service.matter_mode import (
    MatterModeError,
    bind_preview_mode,
    configured_matter_id,
    require_preview_mode,
    require_scope,
)
from app.service.proffer_errors import ProfferError
from app.service.proffer_sources import browse_sources  # noqa: F401
from app.types.matter_mode import MatterMode
from app.types.proffer import (
    ProfferDecisionRequest,
    ProfferDecisionActor,
    ProfferDecisionResponse,
    ProfferHandlerSelectionDecisionRequest,
    ProfferHandlerSelectionDecisionResponse,
    ProfferRepairDecisionRequest,
    ProfferRepairDecisionResponse,
    ProfferPreviewMessagesResponse,
    ProfferContentResponse,
    ProfferPreviewResponse,
    ProfferStartRequest,
    ProfferStartResponse,
    ProfferUploadResponse,
)


_SERVICE_TOKEN = re.compile(r"[A-Za-z0-9\-._~+/]+={0,}")
_MIN_SERVICE_TOKEN_BYTES = 32
_MAX_SERVICE_TOKEN_BYTES = 4096
_MAX_SERVICE_TOKEN_FILE_BYTES = _MAX_SERVICE_TOKEN_BYTES + 2
_SAFE_SERVICE_AUTH_ERROR = "Proffer service authentication is unavailable or invalid"


def _service_authorization_headers() -> dict[str, str]:
    """Read and validate the mounted Proffer service token for one request."""
    path = Path(settings.proffer_service_token_file)
    if not path.is_absolute():
        raise ProfferError(_SAFE_SERVICE_AUTH_ERROR, 503)
    try:
        file_info = path.lstat()
        if not stat.S_ISREG(file_info.st_mode) or not (
            _MIN_SERVICE_TOKEN_BYTES <= file_info.st_size <= _MAX_SERVICE_TOKEN_FILE_BYTES
        ):
            raise ProfferError(_SAFE_SERVICE_AUTH_ERROR, 503)
        with path.open("rb") as secret_file:
            raw = secret_file.read(_MAX_SERVICE_TOKEN_FILE_BYTES + 1)
    except OSError:
        raise ProfferError(_SAFE_SERVICE_AUTH_ERROR, 503) from None
    raw = raw.rstrip(b"\r\n")
    if not (_MIN_SERVICE_TOKEN_BYTES <= len(raw) <= _MAX_SERVICE_TOKEN_BYTES) or b"\x00" in raw:
        raise ProfferError(_SAFE_SERVICE_AUTH_ERROR, 503)
    try:
        token = raw.decode("utf-8")
    except UnicodeDecodeError:
        raise ProfferError(_SAFE_SERVICE_AUTH_ERROR, 503) from None
    if _SERVICE_TOKEN.fullmatch(token) is None:
        raise ProfferError(_SAFE_SERVICE_AUTH_ERROR, 503)
    return {"Authorization": f"Bearer {token}"}


def _detail(response: httpx.Response) -> str:
    try:
        payload: Any = response.json()
    except (ValueError, json.JSONDecodeError):
        return response.text[:500]
    if isinstance(payload, dict) and isinstance(payload.get("detail"), str):
        return payload["detail"]
    return response.text[:500]


async def _request(method: str, path: str, **kwargs: Any) -> httpx.Response:
    if not settings.proffer_starter_url.strip():
        raise ProfferError("Proffer starter is not configured", 503)
    headers = {key: value for key, value in dict(kwargs.pop("headers", {})).items() if key.lower() != "authorization"}
    headers.update(_service_authorization_headers())
    try:
        async with httpx.AsyncClient(timeout=15.0) as client:
            response = await client.request(
                method, f"{settings.proffer_starter_url.rstrip('/')}{path}", headers=headers, **kwargs
            )
    except httpx.HTTPError as error:
        raise ProfferError(f"Proffer starter unreachable: {error}") from error
    if response.status_code >= 400:
        raise ProfferError(_detail(response) or "Proffer starter rejected the request", response.status_code)
    return response


def _mode_call(call, *args):
    try:
        return call(*args)
    except MatterModeError as error:
        raise ProfferError(error.detail, error.status_code) from None


def _mode_payload(payload: Any, label: str, mode: MatterMode) -> dict[str, Any]:
    """Add the BFF-only mode echo while rejecting contradictory upstream data."""
    if not isinstance(payload, dict):
        raise ProfferError(f"Proffer starter returned an invalid {label}", 502)
    upstream_mode = payload.get("matter_mode")
    if upstream_mode is not None and upstream_mode != mode:
        raise ProfferError(f"Proffer starter returned {label} for a different matter mode", 502)
    result = dict(payload)
    result["matter_mode"] = mode
    return result


def _require_mode_configuration(mode: MatterMode) -> None:
    _mode_call(configured_matter_id, mode)


async def start(request: ProfferStartRequest, *, mode: MatterMode) -> ProfferStartResponse:
    if request.matter_mode != mode:
        raise ProfferError("matter_mode in the start body must match the mode query", 409)
    _mode_call(require_scope, mode, request.matter_id, request.court_case_id)
    response = await _request(
        "POST",
        "/reference-import/start",
        json=request.model_dump(mode="json", exclude={"matter_mode"}),
    )
    result = _validated(
        ProfferStartResponse,
        _mode_payload(_json_payload(response, "start response"), "start response", mode),
        "start response",
    )
    _mode_call(bind_preview_mode, result.preview_handle, mode)
    return result


def _validated(model, payload: Any, label: str):
    try:
        return model.model_validate(payload)
    except (ValidationError, ValueError, TypeError) as error:
        raise ProfferError(f"Proffer starter returned an invalid {label}", 502) from error


def _json_payload(response: httpx.Response, label: str) -> Any:
    """Normalize malformed upstream JSON to the BFF's fail-closed 502 contract."""
    try:
        return response.json()
    except (ValueError, json.JSONDecodeError, UnicodeDecodeError, TypeError) as error:
        raise ProfferError(f"Proffer starter returned malformed JSON for {label}", 502) from error


async def decide(
    preview_handle: str,
    request: ProfferDecisionRequest,
    actor: ProfferDecisionActor,
    *,
    mode: MatterMode,
) -> ProfferDecisionResponse:
    _mode_call(require_preview_mode, preview_handle, mode)
    response = await _request(
        "POST",
        f"/reference-import/previews/{preview_handle}/decision",
        json=request.model_dump(mode="json"),
        headers={
            "X-authentik-uid": actor.subject_uid,
            "X-authentik-username": actor.username,
        },
    )
    result = _validated(
        ProfferDecisionResponse,
        _mode_payload(_json_payload(response, "decision response"), "decision response", mode),
        "decision response",
    )
    if result.preview_handle != preview_handle:
        raise ProfferError("Proffer decision response correlation failed", 502)
    return result


async def decide_handler_selection(
    preview_handle: str,
    request: ProfferHandlerSelectionDecisionRequest,
    actor: ProfferDecisionActor,
    *,
    mode: MatterMode,
) -> ProfferHandlerSelectionDecisionResponse:
    from app.service.proffer_handler_selection import decide_handler_selection as implementation

    return await implementation(preview_handle, request, actor, mode=mode)


def _repair_idempotency_key(
    preview_handle: str,
    request: ProfferRepairDecisionRequest,
    actor: ProfferDecisionActor,
) -> str:
    """Bind repair retries to handle, immutable subject, and canonical choice."""
    canonical = json.dumps(
        request.model_dump(mode="json"),
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=False,
    )
    digest = hashlib.sha256(f"{preview_handle}\x00{actor.subject_uid}\x00{canonical}".encode()).hexdigest()
    return f"proffer-repair:{digest}"


async def decide_repair(
    preview_handle: str,
    request: ProfferRepairDecisionRequest,
    actor: ProfferDecisionActor,
    *,
    mode: MatterMode,
) -> ProfferRepairDecisionResponse:
    _mode_call(require_preview_mode, preview_handle, mode)
    response = await _request(
        "POST",
        f"/reference-import/previews/{preview_handle}/repair-decision",
        json=request.model_dump(mode="json"),
        headers={
            "X-authentik-uid": actor.subject_uid,
            "X-authentik-username": actor.username,
            "Idempotency-Key": _repair_idempotency_key(preview_handle, request, actor),
        },
    )
    result = _validated(
        ProfferRepairDecisionResponse,
        _mode_payload(_json_payload(response, "repair decision response"), "repair decision response", mode),
        "repair decision response",
    )
    if result.preview_handle != preview_handle:
        raise ProfferError("Proffer repair decision response correlation failed", 502)
    return result


async def preview(preview_handle: str, *, mode: MatterMode) -> ProfferPreviewResponse:
    _mode_call(require_preview_mode, preview_handle, mode)
    response = await _request("GET", f"/reference-import/previews/{preview_handle}")
    result = _validated(
        ProfferPreviewResponse,
        _mode_payload(_json_payload(response, "preview snapshot"), "preview snapshot", mode),
        "preview snapshot",
    )
    if result.preview_handle != preview_handle:
        raise ProfferError("Proffer preview snapshot correlation failed", 502)
    return result


async def preview_messages(
    preview_handle: str, *, mode: MatterMode, cursor: str | None, limit: int
) -> ProfferPreviewMessagesResponse:
    _mode_call(require_preview_mode, preview_handle, mode)
    params: dict[str, str | int] = {"limit": limit}
    if cursor:
        params["cursor"] = cursor
    response = await _request("GET", f"/reference-import/previews/{preview_handle}/messages", params=params)
    result = _validated(
        ProfferPreviewMessagesResponse,
        _mode_payload(_json_payload(response, "preview message page"), "preview message page", mode),
        "preview message page",
    )
    if result.preview_handle != preview_handle:
        raise ProfferError("Proffer preview message correlation failed", 502)
    return result


async def preview_content(
    preview_handle: str,
    *,
    mode: MatterMode,
    record_cursor: str | None,
    chunk_cursor: str | None,
    limit: int,
) -> ProfferContentResponse:
    """Read exact retained-package, generic-record, and pre-publication chunk data."""
    _mode_call(require_preview_mode, preview_handle, mode)
    params: dict[str, str | int] = {"limit": limit}
    if record_cursor:
        params["record_cursor"] = record_cursor
    if chunk_cursor:
        params["chunk_cursor"] = chunk_cursor
    response = await _request("GET", f"/reference-import/previews/{preview_handle}/content", params=params)
    result = _validated(
        ProfferContentResponse,
        _mode_payload(_json_payload(response, "preview content page"), "preview content page", mode),
        "preview content page",
    )
    if result.preview_handle != preview_handle or result.matter_mode != mode:
        raise ProfferError("Proffer preview content correlation failed", 502)
    return result


async def open_preview_event_stream(preview_handle: str, *, mode: MatterMode, last_event_id: int | None):
    from app.service.proffer_streams import open_preview_event_stream as implementation

    return await implementation(preview_handle, mode=mode, last_event_id=last_event_id)


async def validated_preview_events(response, *, preview_handle: str, mode: MatterMode, last_event_id: int | None):
    from app.service.proffer_streams import validated_preview_events as implementation

    async for event in implementation(response, preview_handle=preview_handle, mode=mode, last_event_id=last_event_id):
        yield event


async def open_upload_stream(body, *, mode: MatterMode, content_type: str | None, content_length: str | None):
    from app.service.proffer_streams import open_upload_stream as implementation

    _require_mode_configuration(mode)
    return await implementation(body, content_type=content_type, content_length=content_length)


async def complete_upload_response(client, response, *, mode: MatterMode) -> ProfferUploadResponse:
    from app.service.proffer_streams import complete_upload_response as implementation

    return await implementation(client, response, mode=mode)
