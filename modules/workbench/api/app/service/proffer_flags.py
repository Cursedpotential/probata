"""Durable, reversible preview annotations backed by the existing flag spine."""

from __future__ import annotations

import json
from datetime import datetime
from typing import Any

from app.service import flags as flags_service
from app.service.proffer_errors import ProfferError
from app.types.matter_mode import MatterMode
from app.types.proffer import ProfferDecisionActor
from app.types.proffer_flags import (
    PotentialPromotionScope,
    ProfferPotentialPromotionFlag,
    ProfferPotentialPromotionFlagRequest,
)

_TARGET_PREFIX = "proffer_preview_"
_NOTES_VERSION = "proffer-potential-promotion/v1"


def _target_kind(scope: PotentialPromotionScope) -> str:
    return f"{_TARGET_PREFIX}{scope}"


def _metadata(
    preview_handle: str,
    mode: MatterMode,
    request: ProfferPotentialPromotionFlagRequest,
    actor: ProfferDecisionActor,
) -> dict[str, str]:
    return {
        "contract": _NOTES_VERSION,
        "classification": "potential_promotion",
        "preview_handle": preview_handle,
        "matter_mode": mode,
        "scope": request.scope,
        "target_id": request.target_id,
        "attempt_id": request.attempt_id,
        "actor_subject_uid": actor.subject_uid,
        "actor_username": actor.username,
    }


def _normalize(row: dict[str, Any]) -> ProfferPotentialPromotionFlag | None:
    try:
        metadata = json.loads(str(row.get("notes") or ""))
        if metadata.get("contract") != _NOTES_VERSION:
            return None
        return ProfferPotentialPromotionFlag(
            flag_id=str(row["id"]),
            preview_handle=metadata["preview_handle"],
            matter_mode=metadata["matter_mode"],
            scope=metadata["scope"],
            target_id=metadata["target_id"],
            attempt_id=metadata["attempt_id"],
            reason=str(row["claim"]),
            actor_subject_uid=metadata["actor_subject_uid"],
            actor_username=metadata["actor_username"],
            flagged_at=datetime.fromisoformat(str(row["created_at"])),
            status=str(row.get("status") or "open"),
        )
    except (KeyError, TypeError, ValueError, json.JSONDecodeError) as error:
        raise ProfferError("Potential-promotion flag store returned an invalid governed row", 502) from error


def create_potential_promotion_flag(
    preview_handle: str,
    mode: MatterMode,
    request: ProfferPotentialPromotionFlagRequest,
    actor: ProfferDecisionActor,
) -> ProfferPotentialPromotionFlag:
    metadata = _metadata(preview_handle, mode, request, actor)
    row = flags_service.create_flag(
        {
            "target_kind": _target_kind(request.scope),
            "target_id": request.target_id,
            "claim": request.reason,
            "evidence_wanted": [],
            "notes": json.dumps(metadata, sort_keys=True, separators=(",", ":")),
        }
    )
    normalized = _normalize(row)
    if normalized is None:
        raise ProfferError("Potential-promotion flag store omitted its Proffer contract", 502)
    return normalized


def list_potential_promotion_flags(preview_handle: str, mode: MatterMode) -> list[ProfferPotentialPromotionFlag]:
    result: list[ProfferPotentialPromotionFlag] = []
    for scope in ("record", "chunk", "entity"):
        for row in flags_service.list_flags(target_kind=_target_kind(scope)):
            normalized = _normalize(row)
            if normalized and normalized.preview_handle == preview_handle and normalized.matter_mode == mode:
                result.append(normalized)
    return sorted(result, key=lambda item: (item.flagged_at, item.flag_id))
