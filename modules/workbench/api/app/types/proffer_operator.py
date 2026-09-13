"""Truthful operator projection over the existing Proffer contracts.

This is a read model for the Workbench. It does not replace the parser,
normalizer, Temporal, n8n, or DuckDB contracts that it identifies.
"""

from __future__ import annotations

from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field

from app.types.matter_mode import MatterMode
from app.types.proffer import BoundedReason, NonBlank, OpaquePreviewHandle
from app.types.proffer_operations import ProfferOperationStage


class OperatorContractIdentity(BaseModel):
    model_config = ConfigDict(extra="forbid")

    contract: NonBlank
    version: NonBlank
    authority: NonBlank


class OperatorAvailability(BaseModel):
    model_config = ConfigDict(extra="forbid")

    status: Literal["available", "pending", "unavailable"]
    reason: BoundedReason = ""
    ref: NonBlank | None = None
    count: Annotated[int, Field(ge=0)] | None = None


class OperatorExecutionLayer(BaseModel):
    model_config = ConfigDict(extra="forbid")

    layer: Literal["temporal", "n8n"]
    status: Literal["active", "waiting", "completed", "failed", "unavailable", "not_observed"]
    workflow_id: OperatorAvailability
    run_or_execution_id: OperatorAvailability
    version: OperatorAvailability
    current_node_or_stage: NonBlank | None = None
    detail: BoundedReason = ""


class OperatorAction(BaseModel):
    """An action the current backend contract can execute in this state."""

    model_config = ConfigDict(extra="forbid")

    action: Literal[
        "select_handler",
        "retain_original",
        "approve_preview",
        "reject_preview",
        "refresh",
        "restart_new_operation",
    ]
    label: NonBlank
    detail: BoundedReason
    requires_reason: bool = False


class OperatorUnavailableControl(BaseModel):
    """A requested control omitted from valid_actions because no contract backs it."""

    model_config = ConfigDict(extra="forbid")

    control: Literal["apply_repair", "retry_stage", "skip_stage", "cancel", "resume_checkpoint"]
    reason: BoundedReason


class OperatorPackageState(BaseModel):
    """Visible state for the governing context extraction package contract."""

    model_config = ConfigDict(extra="forbid")

    original: OperatorAvailability
    original_fingerprint: OperatorAvailability
    package_identity: OperatorAvailability
    package_hash: OperatorAvailability
    metadata: OperatorAvailability
    attachments: OperatorAvailability
    parsed_or_extracted_products: OperatorAvailability
    normalized_products: OperatorAvailability


class OperatorAuthorityState(BaseModel):
    model_config = ConfigDict(extra="forbid")

    intake_classification: OperatorAvailability
    context_status: OperatorAvailability
    evidence_eligibility: OperatorAvailability
    promotion_prerequisites: OperatorAvailability
    promotion_rehash: OperatorAvailability
    custody_state: OperatorAvailability


class OperatorRepairState(BaseModel):
    """Source-repair projection before routing and extraction."""

    model_config = ConfigDict(extra="forbid")

    assessment_report: OperatorAvailability
    affected_units: OperatorAvailability
    engine_profile: OperatorAvailability
    proposed_action: OperatorAvailability
    decision_receipt: OperatorAvailability
    reentry_rule: BoundedReason


class OperatorStorageState(BaseModel):
    """D-158 source-type storage and publication boundary."""

    model_config = ConfigDict(extra="forbid")

    source_type: OperatorAvailability
    context_target: OperatorAvailability
    postgres_control_state: OperatorAvailability
    searchable_projection: OperatorAvailability
    rule: BoundedReason


class ProfferOperatorSnapshot(BaseModel):
    model_config = ConfigDict(extra="forbid")

    preview_handle: OpaquePreviewHandle
    matter_mode: MatterMode
    matter_id: NonBlank
    court_case_id: NonBlank
    request_id: NonBlank
    source_ref: NonBlank
    source_version_ref: NonBlank | None = None
    lifecycle: NonBlank
    phase: NonBlank
    current_stage: NonBlank | None = None
    active_stages: Annotated[list[NonBlank], Field(max_length=64)] = Field(default_factory=list)
    retry_count: Annotated[int, Field(ge=0)]
    reason: BoundedReason = ""
    terminal: bool
    parser_handler: NonBlank | None = None
    parser_execution_path: Literal["decoder", "duckdb"] | None = None
    contracts: Annotated[list[OperatorContractIdentity], Field(min_length=3, max_length=8)]
    package: OperatorPackageState
    authority_state: OperatorAuthorityState
    repair_state: OperatorRepairState
    storage_state: OperatorStorageState
    layers: Annotated[list[OperatorExecutionLayer], Field(min_length=2, max_length=2)]
    surfaces: dict[
        Literal["source", "records", "chunks", "entities", "graph", "workflow", "duckdb"],
        OperatorAvailability,
    ]
    stages: Annotated[list[ProfferOperationStage], Field(max_length=128)]
    valid_actions: Annotated[list[OperatorAction], Field(max_length=8)]
    unavailable_controls: Annotated[list[OperatorUnavailableControl], Field(max_length=8)]
    write_boundary: BoundedReason
