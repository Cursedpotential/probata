"""Reversible potential-promotion annotations for Proffer preview content."""

from __future__ import annotations

from datetime import datetime
from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field, StringConstraints

from app.types.matter_mode import MatterMode
from app.types.proffer_messages import NonBlank, OpaquePreviewHandle

PotentialPromotionScope = Literal["record", "chunk", "entity"]
BoundedFlagReason = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=2000)]


class ProfferPotentialPromotionFlagRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    scope: PotentialPromotionScope
    target_id: NonBlank
    attempt_id: NonBlank
    reason: BoundedFlagReason


class ProfferPotentialPromotionFlag(BaseModel):
    model_config = ConfigDict(extra="forbid")

    flag_id: NonBlank
    classification: Literal["potential_promotion"] = "potential_promotion"
    preview_handle: OpaquePreviewHandle
    matter_mode: MatterMode
    scope: PotentialPromotionScope
    target_id: NonBlank
    attempt_id: NonBlank
    reason: BoundedFlagReason
    actor_subject_uid: NonBlank
    actor_username: NonBlank
    flagged_at: datetime
    status: Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=64)]


class ProfferPotentialPromotionFlagList(BaseModel):
    model_config = ConfigDict(extra="forbid")

    flags: Annotated[list[ProfferPotentialPromotionFlag], Field(max_length=2000)]
