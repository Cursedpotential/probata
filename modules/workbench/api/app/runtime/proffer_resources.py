"""Read-only Workbench route for discovering reviewable Proffer operations."""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, HTTPException, Query

from app.service.proffer import ProfferError
from app.service.proffer_resources import list_proposal_resources
from app.types.matter_mode import MatterMode
from app.types.proffer_operations import ProfferOperationLifecycle
from app.types.proffer_resources import ProfferProposalResourceCatalog

router = APIRouter(prefix="/api/proffer", tags=["proffer"])


@router.get("/proposal-resources", response_model=ProfferProposalResourceCatalog)
async def proposal_resources_endpoint(
    mode: Annotated[MatterMode, Query()],
    status: Annotated[ProfferOperationLifecycle | None, Query()] = None,
    cursor: Annotated[str | None, Query(max_length=512)] = None,
    limit: Annotated[int, Query(ge=1, le=100)] = 50,
):
    try:
        return await list_proposal_resources(mode=mode, status=status, cursor=cursor, limit=limit)
    except ProfferError as error:
        raise HTTPException(status_code=error.status_code, detail=error.detail) from None
