"""Authenticated adapter for durable Proffer source-context receipts.

Byline: Codex · GPT-5.6-Sol · 2026-08-30.
"""

from __future__ import annotations

import hashlib
import json

from app.service.matter_mode import MatterModeError, require_scope
from app.service.proffer import ProfferError, _json_payload, _mode_payload, _request, _validated
from app.types.source_context import SourceContextCreateRequest, SourceContextReceipt
from app.types.proffer import MatterMode, ProfferDecisionActor


async def create_source_context(
    request: SourceContextCreateRequest,
    actor: ProfferDecisionActor,
    *,
    mode: MatterMode,
) -> SourceContextReceipt:
    if request.matter_mode != mode:
        raise ProfferError("matter_mode in the source-context body must match the mode query", 409)
    try:
        require_scope(mode, request.matter_id, request.court_case_id)
    except MatterModeError as error:
        raise ProfferError(error.detail, error.status_code) from None
    canonical = json.dumps(
        request.model_dump(mode="json"),
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=False,
    )
    key = hashlib.sha256(f"{actor.subject_uid}\x00{canonical}".encode()).hexdigest()
    response = await _request(
        "POST",
        "/reference-import/source-contexts",
        json=request.model_dump(mode="json", exclude={"matter_mode"}),
        headers={
            "X-authentik-uid": actor.subject_uid,
            "X-authentik-username": actor.username,
            "Idempotency-Key": f"proffer-source-context:{key}",
        },
    )
    return _validated(
        SourceContextReceipt,
        _mode_payload(_json_payload(response, "source context response"), "source context response", mode),
        "source context response",
    )
