"""Compose the Review catalog from existing Proffer operation and content stores."""

from __future__ import annotations

from urllib.parse import urlencode

from app.service import matter_mode, proffer, proffer_operations
from app.types.matter_mode import MatterMode
from app.types.proffer_operations import ProfferOperationLifecycle, ProfferOperationSummary
from app.types.proffer_resources import ProfferProposalResource, ProfferProposalResourceCatalog


def _mode_coordinate(callable_, mode: MatterMode):
    try:
        return callable_(mode)
    except matter_mode.MatterModeError as error:
        raise proffer.ProfferError(error.detail, error.status_code) from None


def _require_catalog_binding(preview_handle: str, mode: MatterMode) -> bool:
    try:
        matter_mode.require_preview_mode(preview_handle, mode)
        return True
    except matter_mode.MatterModeError as error:
        if "different matter mode" in error.detail:
            return False
        raise proffer.ProfferError(
            "Proffer proposal catalog cannot prove TEST/REAL ownership for every listed operation; "
            "restart the import to create an active binding",
            503,
        ) from None


async def _resource(operation: ProfferOperationSummary, mode: MatterMode) -> ProfferProposalResource:
    query = urlencode({"mode": mode})
    root = f"/api/proffer/previews/{operation.preview_handle}"
    content_status = "pending"
    content_reason = "Preview content has not been published by the current operation state"
    record_preview_available = False
    chunk_preview_available = False
    chunk_count = None

    try:
        content = await proffer.preview_content(
            operation.preview_handle,
            mode=mode,
            record_cursor=None,
            chunk_cursor=None,
            limit=1,
        )
    except proffer.ProfferError as error:
        if error.status_code >= 500:
            raise
        content_status = "unavailable" if operation.terminal else "pending"
        content_reason = error.detail
    else:
        content_status = "available"
        content_reason = ""
        record_preview_available = bool(content.records)
        chunk_preview_available = bool(content.chunks)
        if content.chunk_generation is not None:
            chunk_count = content.chunk_generation.chunk_count

    return ProfferProposalResource(
        resource_id=operation.preview_handle,
        preview_handle=operation.preview_handle,
        request_id=operation.request_id,
        source_ref=operation.source_ref,
        created_at=operation.created_at,
        lifecycle=operation.lifecycle,
        current_stage=operation.current_stage,
        wait=operation.wait,
        terminal=operation.terminal,
        reason=operation.reason,
        source_version_ref=operation.source_version_ref,
        completed_stage_count=operation.completed_stage_count,
        representation_state="committed_readback",
        representation_detail=(
            "This resource is read from already-persisted PostgreSQL Context rows; it is not a frozen "
            "precommit proposal. A precommit_proposal requires a per-attempt DuckDB manifest and digest."
        ),
        content_status=content_status,
        content_reason=content_reason,
        record_preview_available=record_preview_available,
        chunk_preview_available=chunk_preview_available,
        chunk_count=chunk_count,
        open_path=f"{root}?{query}",
        content_path=f"{root}/content?{query}",
        operator_path=f"{root}/operator?{query}",
    )


async def list_proposal_resources(
    *,
    mode: MatterMode,
    status: ProfferOperationLifecycle | None,
    cursor: str | None,
    limit: int,
) -> ProfferProposalResourceCatalog:
    matter_id = _mode_coordinate(matter_mode.configured_matter_id, mode)
    court_case_id = _mode_coordinate(matter_mode.configured_court_case_id, mode)
    operations = await proffer_operations.list_operations(status=status, cursor=cursor, limit=limit)

    resources: list[ProfferProposalResource] = []
    for operation in operations.items:
        if _require_catalog_binding(operation.preview_handle, mode):
            resources.append(await _resource(operation, mode))

    return ProfferProposalResourceCatalog(
        matter_mode=mode,
        matter_id=matter_id,
        court_case_id=court_case_id,
        items=resources,
        next_cursor=operations.next_cursor,
    )
