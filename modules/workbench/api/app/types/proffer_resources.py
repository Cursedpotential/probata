"""Read-only catalog projections for reviewable Proffer Context proposals."""

from __future__ import annotations

from datetime import datetime
from typing import Annotated, Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field

from app.types.matter_mode import MatterMode
from app.types.proffer import BoundedReason, NonBlank, OpaqueCursor, OpaquePreviewHandle
from app.types.proffer_operations import ProfferOperationLifecycle, ProfferOperationWait


class ProfferProposalResource(BaseModel):
    """One real Proffer operation that the Review workspace can open."""

    model_config = ConfigDict(extra="forbid")

    resource_id: NonBlank
    preview_handle: OpaquePreviewHandle | None = None
    request_id: NonBlank
    source_ref: NonBlank
    created_at: datetime
    lifecycle: ProfferOperationLifecycle
    current_stage: NonBlank | None = None
    wait: ProfferOperationWait | None = None
    terminal: bool
    reason: BoundedReason = ""
    source_version_ref: NonBlank | None = None
    completed_stage_count: Annotated[int, Field(ge=0)]
    representation_state: Literal["committed_readback", "precommit_proposal"]
    representation_detail: BoundedReason
    content_status: Literal["available", "pending", "unavailable"]
    content_reason: BoundedReason = ""
    record_preview_available: bool
    chunk_preview_available: bool
    chunk_count: Annotated[int, Field(ge=0)] | None = None
    open_path: NonBlank
    detail_path: NonBlank | None = None
    content_path: NonBlank | None = None
    operator_path: NonBlank | None = None


class ProfferProposalCatalogNotice(BaseModel):
    """Truthful availability or validation information for the Review catalog."""

    model_config = ConfigDict(extra="forbid")

    code: NonBlank
    detail: BoundedReason
    resource_id: NonBlank | None = None


class ProfferProposalResourceCatalog(BaseModel):
    """Mode-bound catalog of Context resources available to Review."""

    model_config = ConfigDict(extra="forbid")

    scope: Literal["context_review_resources"] = "context_review_resources"
    matter_mode: MatterMode
    matter_id: UUID
    court_case_id: UUID
    approval_destination: Literal["neo4j"] = "neo4j"
    later_manual_projection: Literal["surrealdb"] = "surrealdb"
    items: Annotated[list[ProfferProposalResource], Field(max_length=100)]
    notices: Annotated[list[ProfferProposalCatalogNotice], Field(max_length=100)] = Field(default_factory=list)
    next_cursor: OpaqueCursor | None = None
