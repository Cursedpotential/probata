"""Workbench adapter for durable Proffer operation projections."""

from __future__ import annotations

from app.service import proffer
from app.types.proffer_operations import (
    ProfferOperationDetail,
    ProfferOperationLifecycle,
    ProfferOperationListResponse,
)


async def list_operations(
    *,
    status: ProfferOperationLifecycle | None,
    cursor: str | None,
    limit: int,
) -> ProfferOperationListResponse:
    params: dict[str, str | int] = {"limit": limit}
    if status:
        params["status"] = status
    if cursor:
        params["cursor"] = cursor
    response = await proffer._request("GET", "/reference-import/operations", params=params)
    return proffer._validated(
        ProfferOperationListResponse,
        proffer._json_payload(response, "operation list"),
        "operation list",
    )


async def operation(preview_handle: str) -> ProfferOperationDetail:
    response = await proffer._request("GET", f"/reference-import/operations/{preview_handle}")
    result = proffer._validated(
        ProfferOperationDetail,
        proffer._json_payload(response, "operation detail"),
        "operation detail",
    )
    if result.preview_handle != preview_handle:
        raise proffer.ProfferError("Proffer operation detail correlation failed", 502)
    return result
