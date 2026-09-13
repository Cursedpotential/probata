"""Typed allowlisted source-browser projections for Proffer intake."""

from __future__ import annotations

from datetime import datetime
from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field, StringConstraints

from app.types.matter_mode import MatterMode


NonBlank = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1)]
SourceLocation = Literal["r2"]
SourceFileKind = Literal[
    "archive",
    "structured_data",
    "message_export",
    "document",
    "image",
    "audio",
    "video",
    "code",
    "other",
]


class ProfferSourceObject(BaseModel):
    model_config = ConfigDict(extra="forbid")

    kind: Literal["object"] = "object"
    key: NonBlank
    name: NonBlank
    source_ref: NonBlank
    source_location: SourceLocation = "r2"
    bucket: NonBlank
    relative_parent: str = ""
    extension: str = ""
    file_kind: SourceFileKind
    media_type: NonBlank
    archive_format: str | None = None
    intake_note: NonBlank
    byte_length: int
    last_modified: datetime | None = None
    etag: str | None = None


class ProfferSourcePrefix(BaseModel):
    model_config = ConfigDict(extra="forbid")

    kind: Literal["prefix"] = "prefix"
    prefix: NonBlank
    name: NonBlank


class ProfferSourceRoot(BaseModel):
    model_config = ConfigDict(extra="forbid")

    root_id: NonBlank
    label: NonBlank
    source_location: SourceLocation = "r2"
    bucket: NonBlank
    root_ref: NonBlank
    temporary: bool


class ProfferSourceBrowserResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    source: NonBlank
    active_root_id: NonBlank
    available_roots: list[ProfferSourceRoot]
    prefix: str
    delimiter: Literal["/"] = "/"
    filter: str
    filter_applied: bool
    filter_scope: Literal["root", "folder"]
    selected_file_types: list[SourceFileKind]
    available_file_types: list[SourceFileKind]
    search_complete: bool
    scanned_count: Annotated[int, Field(ge=0)]
    scan_limit_reached: bool
    page_size: int
    is_truncated: bool
    continuation_token: str | None = None
    prefixes: list[ProfferSourcePrefix]
    objects: list[ProfferSourceObject]
    matter_mode: MatterMode
