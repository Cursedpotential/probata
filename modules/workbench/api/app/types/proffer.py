"""Typed boundary models for the Proffer starter.

Byline: Codex · GPT-5 · 2026-08-28.
"""

from __future__ import annotations

from datetime import datetime
import json
from typing import Annotated, Any, Literal
from urllib.parse import unquote, urlsplit
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, StringConstraints, field_validator, model_validator


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
ProfferOperationLifecycle = Literal[
    "running",
    "awaiting_repair_decision",
    "awaiting_preview_decision",
    "completed",
    "failed",
    "unavailable",
]
ProfferOperationWait = Literal["repair_decision", "preview_decision"]


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
    if parsed.scheme == "r2" and parsed.netloc == "casebible-sorted" and not parsed.query and not parsed.fragment:
        key = unquote(parsed.path.removeprefix("/"))
        if key and not key.startswith("/") and "\\" not in key and ".." not in key.split("/"):
            return value
    raise ValueError("source_ref must be an upload reference or a Case Bible Sorted object")


class ProfferStartRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    request_id: NonBlank
    matter_id: UUID
    court_case_id: UUID
    source_ref: NonBlank
    declared_format: NonBlank
    parser_options_ref: NonBlank
    source_context_ref: UUID | None = None

    @field_validator("source_ref")
    @classmethod
    def source_must_be_authorized(cls, value: str) -> str:
        return validate_authorized_source_ref(value)


class ProfferSourceObject(BaseModel):
    model_config = ConfigDict(extra="forbid")

    kind: Literal["object"] = "object"
    key: NonBlank
    name: NonBlank
    byte_length: int
    last_modified: datetime | None = None
    etag: str | None = None


class ProfferSourcePrefix(BaseModel):
    model_config = ConfigDict(extra="forbid")

    kind: Literal["prefix"] = "prefix"
    prefix: NonBlank
    name: NonBlank


class ProfferSourceBrowserResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    source: Literal["casebible-sorted"] = "casebible-sorted"
    prefix: str
    delimiter: Literal["/"] = "/"
    filter: str
    filter_applied: bool
    page_size: int
    is_truncated: bool
    continuation_token: str | None = None
    prefixes: list[ProfferSourcePrefix]
    objects: list[ProfferSourceObject]


class ProfferStartResponse(BaseModel):
    # Go may add non-security response metadata without breaking this typed BFF.
    model_config = ConfigDict(extra="ignore")

    preview_handle: OpaquePreviewHandle


class ProfferDecisionRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    approved: bool
    reason: BoundedReason = ""


class ProfferDecisionResponse(BaseModel):
    model_config = ConfigDict(extra="ignore")

    preview_handle: OpaquePreviewHandle
    status: NonBlank


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
        "custody",
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
    lifecycle: ProfferOperationLifecycle | None = None
    current_stage: NonBlank | None = None
    active_stages: Annotated[list[NonBlank], Field(max_length=64)] = Field(default_factory=list)
    wait: ProfferOperationWait | None = None
    terminal: bool | None = None
    completed_stage_count: Annotated[int, Field(ge=0)] | None = None

    @model_validator(mode="after")
    def validate_snapshot_shape(self) -> ProfferPreviewResponse:
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


class ProfferPreviewParticipant(BaseModel):
    model_config = ConfigDict(extra="ignore")

    participant_id: NonBlank
    display_name: NonBlank
    canonical_address: str | None = None


class ProfferPreviewAttachment(BaseModel):
    model_config = ConfigDict(extra="ignore")

    attachment_id: NonBlank
    filename: str | None = None
    media_type: str | None = None
    byte_length: Annotated[int, Field(ge=0)] | None = None
    sha256: Sha256Digest | None = None
    source_locator_ref: NonBlank


class ProfferPreviewMessage(BaseModel):
    model_config = ConfigDict(extra="ignore")

    message_id: NonBlank
    ordinal: Annotated[int, Field(ge=0)]
    sent_at: datetime | None = None
    sender_participant_id: str | None = None
    body: Annotated[str, StringConstraints(max_length=1_000_000)]
    participant_ids: Annotated[list[str], Field(max_length=64)]
    attachments: Annotated[list[ProfferPreviewAttachment], Field(max_length=128)]
    source_locator_ref: NonBlank


class ProfferPreviewMessagesResponse(BaseModel):
    model_config = ConfigDict(extra="ignore")

    preview_handle: OpaquePreviewHandle
    participants: Annotated[list[ProfferPreviewParticipant], Field(max_length=256)]
    messages: Annotated[list[ProfferPreviewMessage], Field(max_length=250)]
    next_cursor: OpaqueCursor | None = None
