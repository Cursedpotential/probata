"""Allowlisted R2 source browsing for the Workbench Proffer surface."""

from __future__ import annotations

import base64
import json
import mimetypes
from pathlib import PurePosixPath
from typing import Any

from app.repo.object_store_client import (
    DEFAULT_SOURCE_ROOT_ID,
    SOURCE_ROOTS,
    get_source_root,
    list_source_objects,
)
from app.service.matter_mode import MatterModeError, configured_matter_id
from app.service.proffer_errors import ProfferError
from app.types.matter_mode import MatterMode
from app.types.proffer_sources import (
    ProfferSourceBrowserResponse,
    ProfferSourceObject,
    ProfferSourcePrefix,
    ProfferSourceRoot,
    SourceFileKind,
)


_AVAILABLE_FILE_TYPES: tuple[SourceFileKind, ...] = (
    "archive",
    "structured_data",
    "message_export",
    "document",
    "image",
    "audio",
    "video",
    "code",
    "other",
)
_ARCHIVES = {".zip", ".7z", ".rar", ".tar", ".tgz", ".tar.gz", ".gz", ".bz2", ".xz"}
_MESSAGE_EXPORTS = {".xml", ".html", ".htm", ".mbox", ".eml", ".msg", ".vcf"}
_STRUCTURED = {".json", ".jsonl", ".ndjson", ".csv", ".tsv", ".parquet", ".sqlite", ".sqlite3", ".db"}
_DOCUMENTS = {".pdf", ".doc", ".docx", ".odt", ".rtf", ".md", ".txt", ".xls", ".xlsx"}
_IMAGES = {".avif", ".bmp", ".gif", ".heic", ".jpeg", ".jpg", ".png", ".tif", ".tiff", ".webp"}
_AUDIO = {".aac", ".amr", ".flac", ".m4a", ".mp3", ".ogg", ".opus", ".wav"}
_VIDEO = {".3gp", ".avi", ".m4v", ".mkv", ".mov", ".mp4", ".mpeg", ".webm"}
_CODE = {".c", ".cpp", ".cs", ".go", ".java", ".js", ".jsx", ".php", ".py", ".rb", ".rs", ".sql", ".ts", ".tsx"}
_SEARCH_SCAN_LIMIT = 25_000


def _require_mode_configuration(mode: MatterMode) -> None:
    try:
        configured_matter_id(mode)
    except MatterModeError as error:
        raise ProfferError(error.detail, error.status_code) from None


def _extension(key: str) -> str:
    lowered = key.casefold()
    if lowered.endswith(".tar.gz"):
        return ".tar.gz"
    return PurePosixPath(lowered).suffix


def _file_kind(key: str) -> SourceFileKind:
    extension = _extension(key)
    for kind, extensions in (
        ("archive", _ARCHIVES),
        ("message_export", _MESSAGE_EXPORTS),
        ("structured_data", _STRUCTURED),
        ("document", _DOCUMENTS),
        ("image", _IMAGES),
        ("audio", _AUDIO),
        ("video", _VIDEO),
        ("code", _CODE),
    ):
        if extension in extensions:
            return kind
    return "other"


def _search_cursor(*, root_id: str, prefix: str, filter_text: str, file_types: tuple[str, ...], after: str) -> str:
    payload = json.dumps(
        {"v": 1, "root": root_id, "prefix": prefix, "filter": filter_text, "types": file_types, "after": after},
        separators=(",", ":"),
        sort_keys=True,
    ).encode()
    return "search." + base64.urlsafe_b64encode(payload).decode().rstrip("=")


def _read_search_cursor(
    value: str | None, *, root_id: str, prefix: str, filter_text: str, file_types: tuple[str, ...]
) -> str | None:
    if value is None:
        return None
    if not value.startswith("search."):
        raise ProfferError("search cursor does not match this source query", 422)
    encoded = value.removeprefix("search.")
    try:
        payload = json.loads(base64.urlsafe_b64decode(encoded + "=" * (-len(encoded) % 4)))
    except (ValueError, TypeError, json.JSONDecodeError):
        raise ProfferError("search cursor is invalid", 422) from None
    if payload.get("v") != 1 or (
        payload.get("root"),
        payload.get("prefix"),
        payload.get("filter"),
        tuple(payload.get("types", ())),
    ) != (root_id, prefix, filter_text, file_types):
        raise ProfferError("search cursor does not match this source query", 422)
    after = payload.get("after")
    if not isinstance(after, str) or not after:
        raise ProfferError("search cursor is invalid", 422)
    return after


def _source_object(root_id: str, row: dict[str, Any]) -> ProfferSourceObject:
    root = get_source_root(root_id)
    key = str(row.get("Key", ""))
    extension = _extension(key)
    kind = _file_kind(key)
    parent = str(PurePosixPath(key).parent)
    return ProfferSourceObject(
        key=key,
        name=key.rsplit("/", 1)[-1],
        source_ref=f"r2://{root.bucket}/{key}",
        bucket=root.bucket,
        relative_parent="" if parent == "." else parent,
        extension=extension,
        file_kind=kind,
        media_type=mimetypes.guess_type(key)[0] or "application/octet-stream",
        archive_format=extension.removeprefix(".") if kind == "archive" else None,
        intake_note=(
            "Archive remains intact for provenance; content inspection determines how its members are processed."
            if kind == "archive"
            else "Content inspection determines the handler; the filename extension is only an intake hint."
        ),
        byte_length=int(row.get("Size", 0)),
        last_modified=row.get("LastModified"),
        etag=str(row["ETag"]).strip('"') if row.get("ETag") else None,
    )


def browse_sources(
    *,
    mode: MatterMode,
    root_id: str = DEFAULT_SOURCE_ROOT_ID,
    prefix: str = "",
    continuation_token: str | None = None,
    filter_text: str = "",
    filter_scope: str = "root",
    file_types: tuple[str, ...] = (),
    page_size: int = 100,
) -> ProfferSourceBrowserResponse:
    """Browse or search an allowlisted R2 root without accepting provider coordinates."""
    _require_mode_configuration(mode)
    normalized_prefix = prefix.strip()
    if normalized_prefix.startswith("/") or "\\" in normalized_prefix or ".." in normalized_prefix.split("/"):
        raise ProfferError("source prefix is outside the selected source root", 422)
    try:
        root = get_source_root(root_id)
    except ValueError as error:
        raise ProfferError(str(error), 422) from None
    if filter_scope not in {"root", "folder"}:
        raise ProfferError("filter_scope must be root or folder", 422)
    normalized_filter = filter_text.strip().casefold()
    normalized_types = tuple(sorted(set(file_types)))
    if any(value not in _AVAILABLE_FILE_TYPES for value in normalized_types):
        raise ProfferError("file_type contains an unsupported value", 422)
    searching = bool(normalized_filter or normalized_types)
    objects: list[ProfferSourceObject] = []
    prefixes: list[ProfferSourcePrefix] = []
    scanned_count = 0
    scan_limit_reached = False
    next_cursor: str | None = None
    is_truncated = False
    search_complete = True

    try:
        if searching:
            search_prefix = normalized_prefix if filter_scope == "folder" else ""
            start_after = _read_search_cursor(
                continuation_token,
                root_id=root_id,
                prefix=search_prefix,
                filter_text=normalized_filter,
                file_types=normalized_types,
            )
            provider_cursor: str | None = None
            last_scanned = start_after
            while len(objects) < page_size and scanned_count < _SEARCH_SCAN_LIMIT:
                page = list_source_objects(
                    root_id=root_id,
                    prefix=search_prefix,
                    continuation_token=provider_cursor,
                    start_after=start_after if provider_cursor is None else None,
                    max_keys=min(1000, _SEARCH_SCAN_LIMIT - scanned_count),
                    delimiter=None,
                )
                rows = list(page.get("Contents", []))
                if not rows:
                    break
                for index, row in enumerate(rows):
                    key = str(row.get("Key", ""))
                    if not key or key.endswith("/"):
                        continue
                    scanned_count += 1
                    last_scanned = key
                    kind = _file_kind(key)
                    if normalized_filter and normalized_filter not in key.casefold():
                        continue
                    if normalized_types and kind not in normalized_types:
                        continue
                    objects.append(_source_object(root_id, row))
                    if len(objects) == page_size:
                        is_truncated = index < len(rows) - 1 or bool(page.get("IsTruncated", False))
                        break
                if len(objects) == page_size:
                    break
                provider_cursor = page.get("NextContinuationToken")
                if not page.get("IsTruncated", False) or not provider_cursor:
                    break
            if len(objects) < page_size and scanned_count >= _SEARCH_SCAN_LIMIT:
                scan_limit_reached = True
                is_truncated = True
            search_complete = not is_truncated
            if is_truncated and last_scanned:
                next_cursor = _search_cursor(
                    root_id=root_id,
                    prefix=search_prefix,
                    filter_text=normalized_filter,
                    file_types=normalized_types,
                    after=last_scanned,
                )
        else:
            page = list_source_objects(
                root_id=root_id,
                prefix=normalized_prefix,
                continuation_token=continuation_token,
                max_keys=page_size,
            )
            scanned_count = len(page.get("CommonPrefixes", [])) + len(page.get("Contents", []))
            prefixes = [
                ProfferSourcePrefix(
                    prefix=str(row["Prefix"]),
                    name=str(row["Prefix"]).rstrip("/").rsplit("/", 1)[-1],
                )
                for row in page.get("CommonPrefixes", [])
                if row.get("Prefix")
            ]
            objects = [
                _source_object(root_id, row)
                for row in page.get("Contents", [])
                if row.get("Key") and not str(row["Key"]).endswith("/")
            ]
            is_truncated = bool(page.get("IsTruncated", False))
            next_cursor = page.get("NextContinuationToken")
    except RuntimeError as error:
        raise ProfferError(str(error), 503) from error

    return ProfferSourceBrowserResponse(
        source=root.bucket,
        active_root_id=root.root_id,
        available_roots=[
            ProfferSourceRoot(
                root_id=item.root_id,
                label=item.label,
                bucket=item.bucket,
                root_ref=item.root_ref,
                temporary=item.temporary,
            )
            for item in SOURCE_ROOTS.values()
        ],
        prefix=normalized_prefix,
        filter=filter_text.strip(),
        filter_applied=searching,
        filter_scope=filter_scope,
        selected_file_types=list(normalized_types),
        available_file_types=list(_AVAILABLE_FILE_TYPES),
        search_complete=search_complete,
        scanned_count=scanned_count,
        scan_limit_reached=scan_limit_reached,
        page_size=page_size,
        is_truncated=is_truncated,
        continuation_token=next_cursor,
        prefixes=prefixes,
        objects=objects,
        matter_mode=mode,
    )
