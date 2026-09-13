"""Immediate, read-only inspection of one fixed Case Bible Sorted object.

The digest produced here is a preview checksum. Acquisition independently
re-reads, seals, and receipts the object before it can enter custody.

Byline: Codex · GPT-5.6-Sol · 2026-08-30.
"""

from __future__ import annotations

from dataclasses import dataclass
import hashlib
import mimetypes
from pathlib import PurePosixPath
import re
from typing import Iterator
from urllib.parse import quote

from app.repo.object_store_client import (
    get_source_root,
    head_source_object,
    open_source_object,
    validate_source_key,
)
from app.service.proffer import _require_mode_configuration
from app.types.proffer import MatterMode
from app.types.source_inspection import ParserPreflight, SourceInspectionRequest, SourceInspectionResponse


MAX_IMMEDIATE_HASH_BYTES = 256 * 1024 * 1024
MAX_TEXT_PREVIEW_BYTES = 250_000
STREAM_CHUNK_BYTES = 1024 * 1024
_RANGE_PATTERN = re.compile(r"^bytes=(\d*)-(\d*)$")
_TEXT_EXTENSIONS = {".csv", ".htm", ".html", ".json", ".md", ".txt", ".xml"}
_IMAGE_EXTENSIONS = {".avif", ".bmp", ".gif", ".jpeg", ".jpg", ".png", ".tif", ".tiff", ".webp"}
_DECLARED_FORMATS = {
    ".avif": "image",
    ".bmp": "image",
    ".csv": "delimited_text",
    ".docx": "docx",
    ".gif": "image",
    ".htm": "html",
    ".html": "html",
    ".jpeg": "image",
    ".jpg": "image",
    ".json": "message_export_json",
    ".md": "markdown",
    ".pdf": "pdf",
    ".png": "image",
    ".tif": "image",
    ".tiff": "image",
    ".txt": "delimited_text",
    ".webp": "image",
    ".xml": "sms_export_xml",
    ".zip": "archive",
}


class SourceInspectionError(RuntimeError):
    def __init__(self, status_code: int, detail: str):
        self.status_code = status_code
        self.detail = detail
        super().__init__(detail)


@dataclass(frozen=True)
class SourceContent:
    body: object
    content_type: str
    content_length: int
    etag: str
    status_code: int
    content_range: str | None = None


def _metadata(request: SourceInspectionRequest) -> tuple[str, dict]:
    try:
        root = get_source_root(request.root_id)
        key = validate_source_key(request.key)
        if request.source_ref != f"r2://{root.bucket}/{key}":
            raise ValueError("source reference does not belong to the selected source root")
        head = head_source_object(root.root_id, key)
    except ValueError as error:
        raise SourceInspectionError(422, str(error)) from None
    except RuntimeError:
        raise SourceInspectionError(502, "The selected source could not be inspected") from None
    size = int(head.get("ContentLength", -1))
    etag = str(head.get("ETag") or "").strip()
    if size < 0 or not etag:
        raise SourceInspectionError(502, "The selected source returned incomplete object metadata")
    listed_etag = request.expected_etag.strip('"') if request.expected_etag else None
    if size != request.expected_byte_length or (listed_etag and etag.strip('"') != listed_etag):
        raise SourceInspectionError(409, "The selected source changed after it was listed; choose it again")
    return key, head


def _preflight(key: str) -> ParserPreflight:
    extension = PurePosixPath(key).suffix.casefold()
    declared_format = _DECLARED_FORMATS.get(extension, "unknown_binary")
    label = {
        "pdf": "PDF document route",
        "docx": "Word document route",
        "html": "HTML document route",
        "markdown": "Markdown document route",
        "message_export_json": "JSON message-export route",
        "sms_export_xml": "SMS XML route",
        "delimited_text": "Delimited text route",
        "image": "Image processing route",
        "archive": "Archive inventory route",
    }.get(declared_format, "Format inspection required")
    return ParserPreflight(declared_format=declared_format, route_label=label)


def inspect_source(request: SourceInspectionRequest, *, mode: MatterMode) -> SourceInspectionResponse:
    """Hash one small source immediately and return a truthful preview descriptor."""
    _require_mode_configuration(mode)
    key, head = _metadata(request)
    size = int(head["ContentLength"])
    etag = str(head["ETag"])
    if size > MAX_IMMEDIATE_HASH_BYTES:
        raise SourceInspectionError(
            413,
            "This source is too large for immediate inspection; start governed batch acquisition instead",
        )
    try:
        root = get_source_root(request.root_id)
        response = open_source_object(root.root_id, key, if_match=etag)
        body = response["Body"]
        digest = hashlib.sha256()
        captured = bytearray()
        byte_count = 0
        while True:
            chunk = body.read(STREAM_CHUNK_BYTES)
            if not chunk:
                break
            byte_count += len(chunk)
            digest.update(chunk)
            if len(captured) < MAX_TEXT_PREVIEW_BYTES:
                captured.extend(chunk[: MAX_TEXT_PREVIEW_BYTES - len(captured)])
    except RuntimeError:
        raise SourceInspectionError(502, "The selected source could not be read for inspection") from None
    finally:
        if "body" in locals():
            body.close()
    if byte_count != size:
        raise SourceInspectionError(409, "The selected source changed while it was being inspected")

    extension = PurePosixPath(key).suffix.casefold()
    content_type = str(head.get("ContentType") or mimetypes.guess_type(key)[0] or "application/octet-stream")
    preview_kind = (
        "pdf"
        if extension == ".pdf" or content_type == "application/pdf"
        else "text"
        if extension in _TEXT_EXTENSIONS or content_type.startswith("text/")
        else "image"
        if extension in _IMAGE_EXTENSIONS or content_type.startswith("image/")
        else "unsupported"
    )
    preview_text = bytes(captured).decode("utf-8", errors="replace") if preview_kind == "text" else ""
    preview_url = (
        f"/api/proffer/source-content?root_id={quote(request.root_id, safe='')}&key={quote(key, safe='')}&etag={quote(etag, safe='')}"
        if preview_kind in {"pdf", "text", "image"}
        else None
    )
    return SourceInspectionResponse(
        source=root.bucket,
        root_id=root.root_id,
        active_root_id=root.root_id,
        matter_mode=mode,
        bucket=root.bucket,
        key=key,
        source_ref=request.source_ref,
        name=PurePosixPath(key).name,
        byte_length=size,
        etag=etag,
        last_modified=head.get("LastModified"),
        content_type=content_type,
        sha256=digest.hexdigest(),
        preview_kind=preview_kind,
        preview_text=preview_text,
        preview_url=preview_url,
        parser_preflight=_preflight(key),
    )


def _range_header(range_header: str | None, size: int) -> tuple[str | None, int, str | None]:
    if not range_header:
        return None, size, None
    match = _RANGE_PATTERN.fullmatch(range_header.strip())
    if not match or (not match.group(1) and not match.group(2)):
        raise SourceInspectionError(416, "Only one valid byte range is supported")
    if match.group(1):
        start = int(match.group(1))
        end = int(match.group(2)) if match.group(2) else size - 1
    else:
        suffix = int(match.group(2))
        if suffix <= 0:
            raise SourceInspectionError(416, "The requested byte range is invalid")
        start = max(size - suffix, 0)
        end = size - 1
    if start >= size or end < start:
        raise SourceInspectionError(416, "The requested byte range is outside the source")
    end = min(end, size - 1)
    return f"bytes={start}-{end}", end - start + 1, f"bytes {start}-{end}/{size}"


def open_source_content(root_id: str, key: str, etag: str, range_header: str | None) -> SourceContent:
    """Open same-origin preview content, pinned to the inspected object identity."""
    try:
        root = get_source_root(root_id)
        validated = validate_source_key(key)
        head = head_source_object(root.root_id, validated)
    except (ValueError, RuntimeError):
        raise SourceInspectionError(404, "The selected source is unavailable") from None
    size = int(head.get("ContentLength", -1))
    current_etag = str(head.get("ETag") or "")
    if size < 0 or not current_etag:
        raise SourceInspectionError(502, "The selected source returned incomplete object metadata")
    if current_etag != etag:
        raise SourceInspectionError(409, "The selected source changed after inspection; inspect it again")
    byte_range, content_length, content_range = _range_header(range_header, size)
    try:
        response = open_source_object(root.root_id, validated, if_match=current_etag, byte_range=byte_range)
    except RuntimeError:
        raise SourceInspectionError(502, "The selected source preview could not be opened") from None
    content_type = str(head.get("ContentType") or mimetypes.guess_type(validated)[0] or "application/octet-stream")
    return SourceContent(
        body=response["Body"],
        content_type=content_type,
        content_length=content_length,
        etag=current_etag,
        status_code=206 if byte_range else 200,
        content_range=content_range,
    )


def stream_source_content(content: SourceContent) -> Iterator[bytes]:
    try:
        while True:
            chunk = content.body.read(STREAM_CHUNK_BYTES)  # type: ignore[attr-defined]
            if not chunk:
                break
            yield chunk
    finally:
        content.body.close()  # type: ignore[attr-defined]
