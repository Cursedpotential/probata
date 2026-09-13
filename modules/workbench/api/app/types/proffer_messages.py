"""Normalized message preview and live event projections."""

from __future__ import annotations

from datetime import datetime
from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field, StringConstraints

from app.types.matter_mode import MatterMode


NonBlank = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1)]
OpaquePreviewHandle = Annotated[
    str,
    StringConstraints(strip_whitespace=True, pattern=r"^[A-Za-z0-9_-]{32,128}$"),
]
Sha256Digest = Annotated[str, StringConstraints(pattern=r"^[0-9a-f]{64}$")]
BoundedReason = Annotated[str, StringConstraints(max_length=4000)]
OpaqueCursor = Annotated[str, StringConstraints(min_length=1, max_length=512)]


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
    matter_mode: MatterMode


class ProfferPreviewEvent(BaseModel):
    model_config = ConfigDict(extra="ignore")

    event_id: Annotated[int, Field(ge=0)]
    event_type: Literal[
        "phase_changed",
        "receipt_recorded",
        "messages_available",
        "decision_requested",
        "decision_recorded",
        "completed",
        "failed",
    ]
    occurred_at: datetime
    preview_handle: OpaquePreviewHandle
    phase: NonBlank
    receipt_ref: str | None = None
    message_count: Annotated[int, Field(ge=0)] | None = None
    detail: BoundedReason = ""
    matter_mode: MatterMode
