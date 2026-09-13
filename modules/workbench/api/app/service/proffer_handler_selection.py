"""Validated, actor-bound Proffer handler-choice proxy."""

from __future__ import annotations

import hashlib
import json

from app.service import proffer as adapter
from app.service.matter_mode import MatterModeError, require_preview_mode
from app.types.matter_mode import MatterMode
from app.types.proffer import ProfferDecisionActor
from app.types.proffer_handler import (
    ProfferHandlerSelectionDecisionRequest,
    ProfferHandlerSelectionDecisionResponse,
)


async def decide_handler_selection(
    preview_handle: str,
    request: ProfferHandlerSelectionDecisionRequest,
    actor: ProfferDecisionActor,
    *,
    mode: MatterMode,
) -> ProfferHandlerSelectionDecisionResponse:
    try:
        require_preview_mode(preview_handle, mode)
    except MatterModeError as error:
        raise adapter.ProfferError(error.detail, error.status_code) from None
    snapshot = await adapter.preview(preview_handle, mode=mode)
    if snapshot.phase != "awaiting_handler_selection":
        raise adapter.ProfferError("preview is not awaiting handler selection", 409)
    if request.recommendation_ref != snapshot.handler_recommendation_ref:
        raise adapter.ProfferError("handler choice does not match the active recommendation", 409)
    candidates = [
        candidate
        for candidate in [snapshot.recommended_handler, *(snapshot.alternative_handlers or [])]
        if candidate is not None
    ]
    matching = [
        candidate
        for candidate in candidates
        if (
            candidate.handler_id,
            candidate.handler_version,
            candidate.execution_path,
            candidate.compatibility_ref,
        )
        == (
            request.handler_id,
            request.handler_version,
            request.execution_path,
            request.compatibility_ref,
        )
    ]
    if len(matching) != 1:
        raise adapter.ProfferError("handler choice is not an exact compatible candidate", 409)
    canonical_choice = json.dumps(
        request.model_dump(mode="json"),
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=False,
    )
    digest = hashlib.sha256(f"{preview_handle}\x00{actor.subject_uid}\x00{canonical_choice}".encode()).hexdigest()
    response = await adapter._request(
        "POST",
        f"/reference-import/previews/{preview_handle}/handler-selection",
        json={"compatibility_ref": request.compatibility_ref},
        headers={
            "X-authentik-uid": actor.subject_uid,
            "X-authentik-username": actor.username,
            "Idempotency-Key": f"proffer-handler-selection:{digest}",
        },
    )
    result = adapter._validated(
        ProfferHandlerSelectionDecisionResponse,
        adapter._mode_payload(
            adapter._json_payload(response, "handler-selection decision response"),
            "handler-selection decision response",
            mode,
        ),
        "handler-selection decision response",
    )
    if result.preview_handle != preview_handle:
        raise adapter.ProfferError("Proffer handler-selection response correlation failed", 502)
    return result
