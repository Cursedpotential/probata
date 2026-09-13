"""Typed read-only source inspection contract for immediate Workbench preview.

Byline: Codex · GPT-5.6-Sol · 2026-08-30.
"""

from __future__ import annotations

from datetime import datetime
from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field, StringConstraints

from app.types.matter_mode import MatterMode


SourceKey = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=1024)]
OpaqueETag = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=512)]
Sha256Digest = Annotated[str, StringConstraints(pattern=r"^[0-9a-f]{64}$")]


class SourceInspectionRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    root_id: Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=64)]
    source_ref: Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=2048)]
    key: SourceKey
    expected_byte_length: Annotated[int, Field(ge=0)]
    expected_etag: OpaqueETag | None = None


class ParserPreflight(BaseModel):
    """Non-authoritative routing hint derived only from the source filename."""

    model_config = ConfigDict(extra="forbid")

    declared_format: str
    route_label: str
    basis: Literal["filename_extension"] = "filename_extension"
    authoritative: Literal[False] = False


class SourceInspectionResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    source: str
    root_id: str
    active_root_id: str
    matter_mode: MatterMode
    source_location: Literal["r2"] = "r2"
    bucket: str
    key: SourceKey
    source_ref: str
    name: str
    byte_length: Annotated[int, Field(ge=0)]
    etag: OpaqueETag
    last_modified: datetime | None = None
    content_type: str
    sha256: Sha256Digest
    digest_status: Literal["preview_only"] = "preview_only"
    preview_kind: Literal["pdf", "text", "image", "unsupported"]
    preview_text: str = ""
    preview_url: str | None = None
    parser_preflight: ParserPreflight
