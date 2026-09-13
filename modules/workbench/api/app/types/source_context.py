"""Actor-independent browser payloads for append-only intake source context.

Byline: Codex · GPT-5.6-Sol · 2026-08-30.
"""

from __future__ import annotations

from datetime import datetime
from typing import Annotated, Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, StringConstraints, field_validator, model_validator

from app.types.matter_mode import MatterMode
from app.types.proffer import validate_authorized_source_ref


BoundedText = Annotated[str, StringConstraints(strip_whitespace=True, max_length=4000)]
NonBlank = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=1024)]
Sha256Digest = Annotated[str, StringConstraints(pattern=r"^[0-9a-f]{64}$")]


class ObservedSource(BaseModel):
    model_config = ConfigDict(extra="forbid")

    key: NonBlank
    name: NonBlank
    byte_length: Annotated[int, Field(ge=0)]
    etag: NonBlank
    preview_sha256: Sha256Digest
    verification_state: Literal["preview_only"] = "preview_only"


class HumanSourceAssertions(BaseModel):
    model_config = ConfigDict(extra="forbid")

    source_class: Literal["first_party", "acquired_third_party", "unknown"] = "unknown"
    source_principal: BoundedText = ""
    other_party: BoundedText = ""
    acquired_at: datetime | None = None
    acquisition_method: Literal[
        "", "own_device", "household_device", "voluntary_third_party", "legal_process", "public_source", "unknown"
    ] = ""
    acquisition_authority: Literal[
        "", "device_owner", "parent_guardian", "account_holder", "consent_given", "court_order", "unclear"
    ] = ""
    source_device: BoundedText = ""
    device_custodian: BoundedText = ""
    occurred_start: str = ""
    occurred_end: str = ""
    date_certainty: Literal["", "exact", "approximate", "range", "unknown"] = ""
    context: BoundedText = ""
    notes: BoundedText = ""

    @field_validator("acquired_at")
    @classmethod
    def acquired_at_requires_timezone(cls, value: datetime | None) -> datetime | None:
        if value is not None and (value.tzinfo is None or value.utcoffset() is None):
            raise ValueError("acquired_at requires an explicit timezone")
        return value

    @field_validator("occurred_start", "occurred_end")
    @classmethod
    def known_date_is_iso(cls, value: str) -> str:
        normalized = value.strip()
        if not normalized:
            return ""
        try:
            datetime.fromisoformat(normalized.replace("Z", "+00:00"))
        except ValueError:
            try:
                datetime.strptime(normalized, "%Y-%m-%d")
            except ValueError:
                raise ValueError("known dates must use ISO date or timestamp format") from None
        return normalized

    @model_validator(mode="after")
    def date_range_is_ordered(self) -> HumanSourceAssertions:
        if self.occurred_start and self.occurred_end and self.occurred_end < self.occurred_start:
            raise ValueError("occurred_end must not be before occurred_start")
        return self


class SourceContextCreateRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    request_id: NonBlank
    matter_id: UUID
    court_case_id: UUID
    source_ref: NonBlank
    supersedes_ref: UUID | None = None
    observed_source: ObservedSource
    assertions: HumanSourceAssertions
    change_reason: Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=4000)]
    matter_mode: MatterMode

    @field_validator("source_ref")
    @classmethod
    def source_must_be_authorized(cls, value: str) -> str:
        return validate_authorized_source_ref(value)


class SourceContextReceipt(BaseModel):
    model_config = ConfigDict(extra="ignore")

    source_context_ref: UUID
    receipt_ref: NonBlank
    content_digest: Sha256Digest
    revision: Annotated[int, Field(ge=1)]
    recorded_at: datetime
    matter_mode: MatterMode


class HumanCorrection(BaseModel):
    """Versioned correction shape published in the shared semantic contract."""

    model_config = ConfigDict(extra="forbid")

    source_context_ref: UUID
    before: HumanSourceAssertions
    after: HumanSourceAssertions
    reason: Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=4000)]
