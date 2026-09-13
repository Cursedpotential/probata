"""Typed boundary models for the Proffer starter.

Byline: Codex · GPT-5 · 2026-08-28.
"""

from __future__ import annotations

from datetime import datetime
import json
import re
from typing import Annotated, Any, Literal
from urllib.parse import unquote, urlsplit
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, StringConstraints, field_validator, model_validator

from app.types.matter_mode import MatterMode
from app.types.proffer_handler import (
    ProfferHandlerCandidate,
    ProfferHandlerSelectionDecisionRequest,  # noqa: F401
    ProfferHandlerSelectionDecisionResponse,  # noqa: F401
)
from app.types.proffer_sources import (
    ProfferSourceBrowserResponse,  # noqa: F401
    ProfferSourceObject,  # noqa: F401
    ProfferSourcePrefix,  # noqa: F401
    ProfferSourceRoot,  # noqa: F401
    SourceFileKind,  # noqa: F401
    SourceLocation,  # noqa: F401
)
from app.types.proffer_messages import (
    ProfferPreviewAttachment,  # noqa: F401
    ProfferPreviewEvent,  # noqa: F401
    ProfferPreviewMessage,  # noqa: F401
    ProfferPreviewMessagesResponse,  # noqa: F401
    ProfferPreviewParticipant,  # noqa: F401
)


NonBlank = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1)]
OpaquePreviewHandle = Annotated[
    str,
    StringConstraints(strip_whitespace=True, pattern=r"^[A-Za-z0-9_-]{32,128}$"),
]
Sha256Digest = Annotated[str, StringConstraints(pattern=r"^[0-9a-f]{64}$")]
BoundedReason = Annotated[str, StringConstraints(max_length=4000)]
OpaqueCursor = Annotated[str, StringConstraints(min_length=1, max_length=512)]
BoundedActorIdentity = Annotated[
    str,
    StringConstraints(strip_whitespace=True, min_length=1, max_length=512, pattern=r"^[^\x00\r\n]+$"),
]
BoundedToolID = Annotated[str, StringConstraints(strip_whitespace=True, max_length=256)]


def validate_authorized_source_ref(value: str) -> str:
    """Accept only opaque uploads or objects in the fixed read-only source bucket."""
    parsed = urlsplit(value)
    upload_digest = parsed.netloc.casefold()
    if (
        parsed.scheme == "upload"
        and len(upload_digest) == 64
        and all(character in "0123456789abcdef" for character in upload_digest)
        and not parsed.path
        and not parsed.query
        and not parsed.fragment
    ):
        return value
    if (
        parsed.scheme == "r2"
        and (
            parsed.netloc in {"casebible-raw", "casebible-sorted", "casebible-quarantine"}
            or (parsed.netloc == "nexus" and re.fullmatch(r"/workbench/staging/[0-9a-f]{64}/.+", unquote(parsed.path)))
        )
        and not parsed.query
        and not parsed.fragment
    ):
        key = unquote(parsed.path.removeprefix("/"))
        if key and not key.startswith("/") and "\\" not in key and ".." not in key.split("/"):
            return value
    raise ValueError("source_ref must be an upload reference or an allowlisted Case Bible R2 object")


class ProfferStartRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    request_id: NonBlank
    matter_id: UUID
    court_case_id: UUID
    source_ref: NonBlank
    declared_format: NonBlank
    parser_options_ref: NonBlank
    source_context_ref: UUID | None = None
    matter_mode: MatterMode

    @field_validator("source_ref")
    @classmethod
    def source_must_be_authorized(cls, value: str) -> str:
        return validate_authorized_source_ref(value)


class ProfferStartResponse(BaseModel):
    # Go may add non-security response metadata without breaking this typed BFF.
    model_config = ConfigDict(extra="ignore")

    preview_handle: OpaquePreviewHandle
    matter_mode: MatterMode


class ProfferUploadResponse(BaseModel):
    model_config = ConfigDict(extra="ignore")

    acquisition_ref: NonBlank
    sha256: Sha256Digest
    byte_length: Annotated[int, Field(ge=0)]
    matter_mode: MatterMode


class ProfferDecisionRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    approved: bool
    reason: BoundedReason = ""


class ProfferDecisionResponse(BaseModel):
    model_config = ConfigDict(extra="ignore")

    preview_handle: OpaquePreviewHandle
    status: NonBlank
    matter_mode: MatterMode


class ProfferDecisionActor(BaseModel):
    """Immutable identity forwarded by the authenticated BFF, never the browser."""

    model_config = ConfigDict(extra="forbid")

    subject_uid: BoundedActorIdentity
    username: BoundedActorIdentity


class ProfferRepairDecisionRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    approved: bool
    apply_repair: bool
    tool_id: BoundedToolID = ""
    tool_payload: Annotated[dict[str, Any], Field(max_length=128)] = Field(default_factory=dict)

    @model_validator(mode="after")
    def validate_repair_choice(self) -> ProfferRepairDecisionRequest:
        if self.apply_repair and (not self.approved or not self.tool_id):
            raise ValueError("an applied repair requires approval and a tool_id")
        if not self.apply_repair and (self.tool_id or self.tool_payload):
            raise ValueError("a non-applied repair decision must not carry tool state")
        try:
            canonical = json.dumps(
                self.tool_payload,
                sort_keys=True,
                separators=(",", ":"),
                ensure_ascii=False,
                allow_nan=False,
            )
        except (TypeError, ValueError):
            raise ValueError("tool_payload must be canonical JSON") from None
        if len(canonical.encode("utf-8")) > 32 * 1024:
            raise ValueError("tool_payload exceeds the 32 KiB decision limit")
        return self


class ProfferRepairDecisionResponse(BaseModel):
    model_config = ConfigDict(extra="ignore")

    preview_handle: OpaquePreviewHandle
    decision_ref: NonBlank
    status: NonBlank
    matter_mode: MatterMode


class ProfferParserIdentity(BaseModel):
    model_config = ConfigDict(extra="ignore")

    parser_id: NonBlank
    parser_version: NonBlank
    config_digest: Sha256Digest


class ProfferPreviewCorrelation(BaseModel):
    model_config = ConfigDict(extra="ignore")

    request_id: NonBlank
    source_version_id: UUID
    raw_generation_id: UUID
    normalized_generation_id: UUID


class ProfferPreviewReceipt(BaseModel):
    """Reference-only receipt; raw or normalized payload bytes are forbidden here."""

    model_config = ConfigDict(extra="ignore")

    receipt_type: Literal[
        "raw_source_verification",
        "parser_selection",
        "parser_execution",
        "normalization",
        "storage",
        "completeness",
    ]
    receipt_ref: NonBlank
    status: Literal["pending", "running", "completed", "failed", "skipped"]
    digest: Sha256Digest | None = None
    recorded_at: datetime


class ProfferPreviewCheckpoint(BaseModel):
    """Live context-import progress before the normalized preview is ready."""

    model_config = ConfigDict(extra="ignore")

    checkpoint: Literal[
        "raw_source_verification",
        "parser_selection",
        "parser_execution",
        "normalization",
        "storage",
        "completeness",
    ]
    status: Literal["pending", "running", "completed", "failed"]
    receipt_ref: NonBlank | None = None
    reason: BoundedReason = ""


class ProfferRepairAssessmentView(BaseModel):
    model_config = ConfigDict(extra="ignore")

    assessment_ref: Annotated[NonBlank, StringConstraints(max_length=512)]
    source_version_ref: Annotated[NonBlank, StringConstraints(max_length=512)]
    review_required: bool


class ProfferPreviewResponse(BaseModel):
    model_config = ConfigDict(extra="ignore")

    preview_handle: OpaquePreviewHandle
    phase: NonBlank
    correlation: ProfferPreviewCorrelation | None = None
    parser: ProfferParserIdentity | None = None
    preview_digest: Sha256Digest | None = None
    receipts: Annotated[list[ProfferPreviewReceipt], Field(max_length=64)] | None = None
    reason: BoundedReason = ""
    repair_assessment: ProfferRepairAssessmentView | None = None
    checkpoints: Annotated[list[ProfferPreviewCheckpoint], Field(max_length=6)] | None = None
    handler_recommendation_ref: NonBlank | None = None
    handler_decision_ref: NonBlank | None = None
    detected_format: NonBlank | None = None
    detected_format_ref: NonBlank | None = None
    signature_ref: NonBlank | None = None
    recommended_handler: ProfferHandlerCandidate | None = None
    alternative_handlers: Annotated[list[ProfferHandlerCandidate], Field(max_length=3)] | None = None
    matter_mode: MatterMode

    @model_validator(mode="after")
    def validate_snapshot_shape(self) -> ProfferPreviewResponse:
        if self.checkpoints is not None:
            names = [checkpoint.checkpoint for checkpoint in self.checkpoints]
            if len(names) != len(set(names)):
                raise ValueError("preview checkpoints must be unique")
        if self.phase == "awaiting_handler_selection" and any(
            value is None
            for value in (
                self.handler_recommendation_ref,
                self.detected_format,
                self.detected_format_ref,
                self.signature_ref,
                self.recommended_handler,
            )
        ):
            raise ValueError("an awaiting handler selection snapshot requires a durable content recommendation")
        if self.phase == "awaiting_repair_decision":
            if self.repair_assessment is None or not self.repair_assessment.review_required:
                raise ValueError("an awaiting repair decision snapshot requires a review assessment")
            return self
        if self.phase == "awaiting_decision" or any(
            value is not None for value in (self.correlation, self.preview_digest, self.receipts)
        ):
            if self.correlation is None or self.preview_digest is None or self.receipts is None:
                raise ValueError("a projected preview snapshot requires correlation, preview_digest, and receipts")
        return self
