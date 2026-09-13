"""Typed server-sent events emitted by the Proffer preview stream."""

from __future__ import annotations

from datetime import datetime
from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field

from app.types.proffer import BoundedReason, NonBlank, OpaquePreviewHandle


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
