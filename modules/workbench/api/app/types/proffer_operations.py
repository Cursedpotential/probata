"""Typed lifecycle projections for durable Proffer operations."""

from __future__ import annotations

from datetime import datetime
from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field

from app.types.proffer import (
    BoundedReason,
    NonBlank,
    OpaqueCursor,
    OpaquePreviewHandle,
    ProfferOperationLifecycle,
    ProfferOperationWait,
)


class ProfferOperationSummary(BaseModel):
    """Reference-only lifecycle projection for one durable Proffer execution."""

    model_config = ConfigDict(extra="ignore")

    preview_handle: OpaquePreviewHandle
    request_id: NonBlank
    source_ref: NonBlank
    service: Literal["proffer"]
    created_at: datetime
    lifecycle: ProfferOperationLifecycle
    current_stage: NonBlank | None = None
    active_stages: Annotated[list[NonBlank], Field(max_length=64)] = Field(default_factory=list)
    wait: ProfferOperationWait | None = None
    terminal: bool
    reason: BoundedReason = ""
    source_version_ref: NonBlank | None = None
    completed_stage_count: Annotated[int, Field(ge=0)]


class ProfferOperationStage(BaseModel):
    model_config = ConfigDict(extra="ignore")

    stage: NonBlank
    status: NonBlank
    ref: NonBlank | None = None
    receipt_ref: NonBlank | None = None
    reason: BoundedReason = ""
    attempt: Annotated[int, Field(ge=0)] | None = None
    started_at: datetime | None = None
    completed_at: datetime | None = None


class ProfferOperationDetail(ProfferOperationSummary):
    stages: Annotated[list[ProfferOperationStage], Field(max_length=128)]


class ProfferOperationListResponse(BaseModel):
    model_config = ConfigDict(extra="ignore")

    items: Annotated[list[ProfferOperationSummary], Field(max_length=100)]
    next_cursor: OpaqueCursor | None = None
