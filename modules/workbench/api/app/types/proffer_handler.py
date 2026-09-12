"""Human handler-choice and content-backed recommendation contracts."""

from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, StringConstraints

from app.types.matter_mode import MatterMode


NonBlank = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1)]
OpaquePreviewHandle = Annotated[
    str,
    StringConstraints(strip_whitespace=True, pattern=r"^[A-Za-z0-9_-]{32,128}$"),
]


class ProfferHandlerSelectionDecisionRequest(BaseModel):
    """Browser choice persisted upstream before Temporal receives its reference."""

    model_config = ConfigDict(extra="forbid")

    recommendation_ref: NonBlank
    handler_id: NonBlank
    handler_version: NonBlank
    execution_path: Literal["decoder", "duckdb"]
    compatibility_ref: NonBlank


class ProfferHandlerSelectionDecisionResponse(BaseModel):
    model_config = ConfigDict(extra="ignore")

    preview_handle: OpaquePreviewHandle
    matter_mode: MatterMode
    decision_ref: NonBlank
    status: NonBlank


class ProfferHandlerCandidate(BaseModel):
    model_config = ConfigDict(extra="ignore")

    handler_id: NonBlank
    handler_version: NonBlank
    execution_path: Literal["decoder", "duckdb"]
    compatibility_ref: NonBlank
    reason: NonBlank
