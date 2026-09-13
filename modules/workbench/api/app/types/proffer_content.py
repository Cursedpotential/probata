"""Generic package, record, attachment, attempt, and chunk preview projection."""

from __future__ import annotations

from datetime import datetime
from typing import Annotated, Any, Literal

from pydantic import BaseModel, ConfigDict, Field, StringConstraints

from app.types.matter_mode import MatterMode
from app.types.proffer_messages import BoundedReason, NonBlank, OpaqueCursor, OpaquePreviewHandle, Sha256Digest


class ProfferContentParser(BaseModel):
    model_config = ConfigDict(extra="ignore")

    parser_id: NonBlank
    parser_version: NonBlank
    config_digest: Sha256Digest


class ProfferContentReceipt(BaseModel):
    model_config = ConfigDict(extra="ignore")

    receipt_type: NonBlank
    receipt_ref: NonBlank
    status: NonBlank
    digest: Sha256Digest | None = None
    recorded_at: datetime


class ProfferPackageProjection(BaseModel):
    model_config = ConfigDict(extra="ignore")

    source_version_ref: NonBlank
    original_ref: str | None = None
    original_filename: str | None = None
    declared_format: NonBlank
    status: NonBlank
    original_sha256: Sha256Digest | None = None
    original_bytes: Annotated[int, Field(ge=0)] | None = None
    storage_class: str | None = None
    metadata_count: Annotated[int, Field(ge=0)]
    attachment_count: Annotated[int, Field(ge=0)]


class ProfferAttemptProjection(BaseModel):
    model_config = ConfigDict(extra="ignore")

    attempt_ref: str = ""
    projection_ref: NonBlank
    source_version_ref: NonBlank
    raw_generation_ref: NonBlank
    normalized_generation_ref: NonBlank
    parser: ProfferContentParser | None = None
    selection_ref: str = ""
    parser_options_ref: str = ""
    receipts: Annotated[list[ProfferContentReceipt], Field(max_length=32)]


class ProfferGenericRecord(BaseModel):
    model_config = ConfigDict(extra="ignore")

    record_id: NonBlank
    ordinal: Annotated[int, Field(ge=0)]
    record_type: Literal["message", "call", "event", "media", "document", "other"]
    occurred_at: datetime | None = None
    payload: dict[str, Any]
    source_locator_ref: NonBlank


class ProfferPackageAttachment(BaseModel):
    model_config = ConfigDict(extra="ignore")

    object_ref: NonBlank
    parent_object_ref: str | None = None
    member_locator: dict[str, Any]
    sha256: Sha256Digest
    byte_length: Annotated[int, Field(ge=0)]
    storage_class: NonBlank


class ProfferChunkGeneration(BaseModel):
    model_config = ConfigDict(extra="ignore")

    generation_ref: NonBlank
    generation_ordinal: Annotated[int, Field(ge=1)]
    status: Literal["open", "sealed", "aborted"]
    policy_id: NonBlank
    policy_version: NonBlank
    chunker_id: NonBlank
    chunker_version: NonBlank
    schema_version: NonBlank
    source_view: NonBlank
    source_sha256: Sha256Digest
    manifest_sha256: Sha256Digest | None = None
    chunk_count: Annotated[int, Field(ge=0)] | None = None
    receipt_ref: NonBlank
    reassembly_result: str | None = None
    sealed_at: datetime | None = None


class ProfferContentChunk(BaseModel):
    model_config = ConfigDict(extra="ignore")

    chunk_ref: NonBlank
    index: Annotated[int, Field(ge=0)]
    content: Annotated[str, StringConstraints(min_length=1, max_length=4_194_304)]
    sha256: Sha256Digest
    derivation_mode: Literal["verbatim_span", "composed", "unverified_derived"]
    token_count: Annotated[int, Field(ge=0)] | None = None
    locator_ref: NonBlank
    byte_start: Annotated[int, Field(ge=0)]
    byte_end: Annotated[int, Field(gt=0)]


class ProfferContentResponse(BaseModel):
    model_config = ConfigDict(extra="ignore")

    preview_handle: OpaquePreviewHandle
    matter_mode: MatterMode
    package: ProfferPackageProjection
    attempt: ProfferAttemptProjection
    attempts_complete: bool
    attempts_reason: BoundedReason = ""
    records: Annotated[list[ProfferGenericRecord], Field(max_length=250)]
    attachments: Annotated[list[ProfferPackageAttachment], Field(max_length=1024)]
    chunk_generation: ProfferChunkGeneration | None = None
    chunks: Annotated[list[ProfferContentChunk], Field(max_length=250)]
    next_record_cursor: OpaqueCursor | None = None
    next_chunk_cursor: OpaqueCursor | None = None
