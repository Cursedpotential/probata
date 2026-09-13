"""Streaming Proffer transport kept separate from request/response adapters.

Byline: Codex · GPT-5.6-Sol · 2026-08-30.
"""

from __future__ import annotations

import json
from collections.abc import AsyncIterator

import httpx

from app.config import settings
from app.service.matter_mode import MatterModeError, require_preview_mode
from app.service.proffer import (
    ProfferError,
    _json_payload,
    _mode_payload,
    _require_mode_configuration,
    _service_authorization_headers,
    _validated,
)
from app.types.proffer import MatterMode, ProfferPreviewEvent, ProfferUploadResponse


async def _detail_async(response: httpx.Response) -> str:
    payload = (await response.aread())[:500]
    try:
        parsed = json.loads(payload)
    except (UnicodeDecodeError, json.JSONDecodeError):
        return payload.decode("utf-8", errors="replace")
    if isinstance(parsed, dict) and isinstance(parsed.get("detail"), str):
        return parsed["detail"]
    return payload.decode("utf-8", errors="replace")


async def open_preview_event_stream(
    preview_handle: str, *, mode: MatterMode, last_event_id: int | None
) -> tuple[httpx.AsyncClient, httpx.Response]:
    """Open the dedicated Proffer event stream; legacy run events are never consulted."""
    try:
        require_preview_mode(preview_handle, mode)
    except MatterModeError as error:
        raise ProfferError(error.detail, error.status_code) from None
    if not settings.proffer_starter_url.strip():
        raise ProfferError("Proffer starter is not configured", 503)
    headers = {"Accept": "text/event-stream", **_service_authorization_headers()}
    if last_event_id is not None:
        headers["Last-Event-ID"] = str(last_event_id)
    client = httpx.AsyncClient(timeout=httpx.Timeout(connect=15.0, read=None, write=15.0, pool=15.0))
    request = client.build_request(
        "GET",
        f"{settings.proffer_starter_url.rstrip('/')}/reference-import/previews/{preview_handle}/events",
        headers=headers,
    )
    try:
        response = await client.send(request, stream=True)
    except httpx.HTTPError as error:
        await client.aclose()
        raise ProfferError(f"Proffer preview event stream unreachable: {error}") from error
    if response.status_code >= 400:
        detail = await _detail_async(response)
        await response.aclose()
        await client.aclose()
        raise ProfferError(detail or "Proffer preview event stream rejected the request", response.status_code)
    if "text/event-stream" not in response.headers.get("content-type", "").casefold():
        await response.aclose()
        await client.aclose()
        raise ProfferError("Proffer starter did not return a preview event stream", 502)
    return client, response


async def validated_preview_events(
    response: httpx.Response, *, preview_handle: str, mode: MatterMode, last_event_id: int | None
) -> AsyncIterator[str]:
    """Validate and re-emit monotonic, replayable Proffer events."""
    previous = last_event_id if last_event_id is not None else -1
    data_lines: list[str] = []
    upstream_id: int | None = None
    async for line in response.aiter_lines():
        if line.startswith(":"):
            continue
        if line.startswith("id:"):
            try:
                upstream_id = int(line[3:].strip())
            except ValueError as error:
                raise ProfferError("Proffer preview event stream returned a malformed event id", 502) from error
        elif line.startswith("data:"):
            data_lines.append(line[5:].lstrip())
        elif not line:
            if not data_lines:
                upstream_id = None
                continue
            try:
                payload = json.loads("\n".join(data_lines))
            except json.JSONDecodeError as error:
                raise ProfferError("Proffer preview event stream returned malformed JSON", 502) from error
            if not isinstance(payload, dict):
                raise ProfferError("Proffer preview event stream returned an invalid event", 502)
            upstream_mode = payload.get("matter_mode")
            if upstream_mode is not None and upstream_mode != mode:
                raise ProfferError("Proffer preview event belongs to a different matter mode", 502)
            payload = {**payload, "matter_mode": mode}
            event = _validated(ProfferPreviewEvent, payload, "preview event")
            if event.preview_handle != preview_handle or upstream_id != event.event_id:
                raise ProfferError("Proffer preview event correlation failed", 502)
            if event.event_id <= previous:
                raise ProfferError("Proffer preview event sequence is not monotonic", 502)
            previous = event.event_id
            yield f"id: {event.event_id}\nevent: proffer.preview\ndata: {event.model_dump_json()}\n\n"
            upstream_id = None
            data_lines = []


async def open_upload_stream(
    body: AsyncIterator[bytes], *, content_type: str | None, content_length: str | None
) -> tuple[httpx.AsyncClient, httpx.Response]:
    """Open a streaming acquisition upload; caller owns response/client closure."""
    if not settings.proffer_starter_url.strip():
        raise ProfferError("Proffer acquisition upload is not configured", 503)
    headers: dict[str, str] = _service_authorization_headers()
    if content_type:
        headers["Content-Type"] = content_type
    if content_length:
        headers["Content-Length"] = content_length
    client = httpx.AsyncClient(timeout=httpx.Timeout(connect=15.0, read=None, write=30.0, pool=15.0))
    request = client.build_request(
        "POST", f"{settings.proffer_starter_url.rstrip('/')}/acquisition/upload", headers=headers, content=body
    )
    try:
        response = await client.send(request, stream=True)
    except httpx.HTTPError as error:
        await client.aclose()
        raise ProfferError(f"Proffer acquisition upload unreachable: {error}") from error
    if response.status_code >= 400:
        detail = await _detail_async(response)
        await response.aclose()
        await client.aclose()
        raise ProfferError(detail or "Proffer acquisition upload rejected the request", response.status_code)
    return client, response


async def complete_upload_response(client, response, *, mode: MatterMode) -> ProfferUploadResponse:
    """Validate the small upload receipt while preserving request-body streaming."""
    _require_mode_configuration(mode)
    try:
        await response.aread()
        return _validated(
            ProfferUploadResponse,
            _mode_payload(_json_payload(response, "upload response"), "upload response", mode),
            "upload response",
        )
    finally:
        await response.aclose()
        await client.aclose()
