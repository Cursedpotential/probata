"""Typed read-only projections for a frozen Proffer DuckDB proposal bundle."""

from __future__ import annotations

from datetime import datetime
from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field, JsonValue

from app.types.matter_mode import MatterMode
from app.types.proffer import NonBlank, Sha256Digest


class FrozenProposalSourcePackage(BaseModel):
    model_config = ConfigDict(extra="forbid")

    locator: NonBlank
    digest: Sha256Digest


class FrozenProposalCounts(BaseModel):
    model_config = ConfigDict(extra="forbid")

    source_records: Annotated[int, Field(ge=0)]
    records: Annotated[int, Field(ge=0)]
    metadata: Annotated[int, Field(ge=0)]
    attachments: Annotated[int, Field(ge=0)]
    entity_mentions: Annotated[int, Field(ge=0)]
    entities: Annotated[int, Field(ge=0)]
    relationships: Annotated[int, Field(ge=0)]
    temporal_expressions: Annotated[int, Field(ge=0)]
    chunks: Annotated[int, Field(ge=0)]
    lineage: Annotated[int, Field(ge=0)]
    warnings: Annotated[int, Field(ge=0)]
    sink_operations: Annotated[int, Field(ge=0)]


class FrozenProposalDestination(BaseModel):
    model_config = ConfigDict(extra="forbid")

    destination: Literal[
        "postgres_control",
        "postgres_messages",
        "weaviate_context",
        "neo4j_graph",
        "context_index",
    ]
    selected: bool
    operation_count: Annotated[int, Field(ge=0)]
    snapshot_digest: Sha256Digest | None = None


class FrozenProposalTableIntegrity(BaseModel):
    model_config = ConfigDict(extra="forbid")

    table: NonBlank
    columns: list[NonBlank]
    rows: Annotated[int, Field(ge=0)]
    expected_digest: Sha256Digest
    actual_digest: Sha256Digest


class FrozenProposalExternalArtifact(BaseModel):
    model_config = ConfigDict(extra="forbid")

    name: NonBlank
    locator: NonBlank
    bytes: Annotated[int, Field(ge=0)]
    byte_digest: Sha256Digest


class FrozenProposalIntegrity(BaseModel):
    model_config = ConfigDict(extra="forbid")

    proposal_digest: Sha256Digest
    bundle_digest: Sha256Digest
    database_byte_digest: Sha256Digest
    database_bytes: Annotated[int, Field(gt=0)]
    finalized_at: datetime
    validated_at: datetime
    tables: list[FrozenProposalTableIntegrity]
    external_artifacts: list[FrozenProposalExternalArtifact]


class FrozenProposalSourceRecord(BaseModel):
    model_config = ConfigDict(extra="forbid")

    source_record_id: NonBlank
    ordinal: Annotated[int, Field(ge=0)]
    source_locator_ref: NonBlank
    source_payload: JsonValue


class FrozenProposalRecord(BaseModel):
    model_config = ConfigDict(extra="forbid")

    record_id: NonBlank
    source_record_id: NonBlank
    ordinal: Annotated[int, Field(ge=0)]
    record_type: NonBlank
    occurred_at: datetime | None = None
    normalized_payload: JsonValue
    source_locator_ref: NonBlank


class FrozenProposalMetadata(BaseModel):
    model_config = ConfigDict(extra="forbid")

    metadata_id: NonBlank
    owner_kind: NonBlank
    owner_id: NonBlank
    metadata_key: NonBlank
    metadata_value: JsonValue
    source_locator_ref: NonBlank | None = None


class FrozenProposalAttachment(BaseModel):
    model_config = ConfigDict(extra="forbid")

    attachment_id: NonBlank
    source_record_id: NonBlank | None = None
    record_id: NonBlank | None = None
    object_ref: NonBlank
    sha256: Sha256Digest
    byte_length: Annotated[int, Field(ge=0)]
    media_type: str | None = None
    metadata: JsonValue | None = None


class FrozenProposalEntityMention(BaseModel):
    model_config = ConfigDict(extra="forbid")

    mention_id: NonBlank
    entity_id: NonBlank
    record_id: NonBlank | None = None
    chunk_id: NonBlank | None = None
    mention_text: NonBlank
    entity_type: NonBlank
    confidence: Annotated[float, Field(ge=0, le=1)] | None = None
    locator_ref: NonBlank
    properties: JsonValue | None = None


class FrozenProposalEntity(BaseModel):
    model_config = ConfigDict(extra="forbid")

    entity_id: NonBlank
    entity_type: NonBlank
    canonical_name: NonBlank
    properties: JsonValue
    source_digest: Sha256Digest


class FrozenProposalRelationship(BaseModel):
    model_config = ConfigDict(extra="forbid")

    relationship_id: NonBlank
    from_entity_id: NonBlank
    to_entity_id: NonBlank
    relationship_type: NonBlank
    properties: JsonValue
    source_digest: Sha256Digest


class FrozenProposalTemporalExpression(BaseModel):
    model_config = ConfigDict(extra="forbid")

    temporal_expression_id: NonBlank
    owner_kind: NonBlank
    owner_id: NonBlank
    expression_text: NonBlank
    normalized_start: datetime | None = None
    normalized_end: datetime | None = None
    precision: str | None = None
    confidence: Annotated[float, Field(ge=0, le=1)] | None = None
    source_locator_ref: NonBlank


class FrozenProposalChunk(BaseModel):
    model_config = ConfigDict(extra="forbid")

    chunk_id: NonBlank
    record_id: NonBlank | None = None
    chunk_index: Annotated[int, Field(ge=0)]
    content: str
    sha256: Sha256Digest
    derivation_mode: NonBlank
    locator_ref: NonBlank
    byte_start: Annotated[int, Field(ge=0)]
    byte_end: Annotated[int, Field(gt=0)]
    token_count: Annotated[int, Field(ge=0)] | None = None


class FrozenProposalLineage(BaseModel):
    model_config = ConfigDict(extra="forbid")

    lineage_id: NonBlank
    output_kind: NonBlank
    output_id: NonBlank
    input_kind: NonBlank
    input_id: NonBlank
    transform_stage: NonBlank
    transform_digest: Sha256Digest
    source_locator_ref: str | None = None


class FrozenProposalWarning(BaseModel):
    model_config = ConfigDict(extra="forbid")

    warning_id: NonBlank
    stage: NonBlank
    code: NonBlank
    detail: str
    locator_ref: str | None = None
    blocking: bool


class FrozenProposalSinkOperation(BaseModel):
    model_config = ConfigDict(extra="forbid")

    sink_operation_id: NonBlank
    destination: NonBlank
    operation_ordinal: Annotated[int, Field(ge=0)]
    operation_kind: NonBlank
    operation_payload: JsonValue
    operation_digest: Sha256Digest
    selected: bool


class FrozenProposalToolReceipt(BaseModel):
    model_config = ConfigDict(extra="forbid")

    receipt_id: NonBlank
    stage: NonBlank
    tool_id: NonBlank
    tool_version: NonBlank
    config_digest: Sha256Digest
    input_digest: Sha256Digest
    output_digest: Sha256Digest
    activity_id: str | None = None
    n8n_execution_id: str | None = None


class FrozenProposalDetail(BaseModel):
    """A fully validated, mode-bound, read-only proposal projection."""

    model_config = ConfigDict(extra="forbid")

    scope: Literal["context_precommit_proposal"] = "context_precommit_proposal"
    representation_state: Literal["precommit_proposal"] = "precommit_proposal"
    resource_id: NonBlank
    schema_version: Literal["proffer-proposal/v1"]
    operation_id: NonBlank
    attempt_id: NonBlank
    matter_mode: MatterMode
    matter_id: NonBlank
    court_case_id: NonBlank
    created_at: datetime
    state: Literal["frozen"]
    source_package: FrozenProposalSourcePackage
    config_digest: Sha256Digest
    counts: FrozenProposalCounts
    destinations: list[FrozenProposalDestination]
    integrity: FrozenProposalIntegrity
    source_records: list[FrozenProposalSourceRecord]
    records: list[FrozenProposalRecord]
    metadata: list[FrozenProposalMetadata]
    attachments: list[FrozenProposalAttachment]
    entity_mentions: list[FrozenProposalEntityMention]
    entities: list[FrozenProposalEntity]
    relationships: list[FrozenProposalRelationship]
    temporal_expressions: list[FrozenProposalTemporalExpression]
    chunks: list[FrozenProposalChunk]
    lineage: list[FrozenProposalLineage]
    warnings: list[FrozenProposalWarning]
    sink_operations: list[FrozenProposalSinkOperation]
    tool_receipts: list[FrozenProposalToolReceipt]
