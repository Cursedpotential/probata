"""Load the complete, governed source set for the single Docstore CocoIndex app."""
from __future__ import annotations

import hashlib
import json
import re
from dataclasses import dataclass
from pathlib import Path, PurePosixPath


MAX_REGISTRY_BYTES = 256 * 1024
_ID = re.compile(r"[a-z][a-z0-9-]{1,47}")


@dataclass(frozen=True)
class SourceSpec:
    project_id: str
    root: Path
    canonical_prefix: str
    domains: tuple[str, ...]
    included_patterns: tuple[str, ...]
    excluded_patterns: tuple[str, ...]
    ingestion_status: str


def _relative(value: object, field: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{field} must be a non-empty relative path")
    normalized = value.replace("\\", "/").strip()
    if normalized.startswith("/") or re.match(r"^[A-Za-z]:/", normalized):
        raise ValueError(f"{field} must be relative")
    path = PurePosixPath(normalized.rstrip("/"))
    if path.is_absolute() or ".." in path.parts:
        raise ValueError(f"{field} escapes the monorepo")
    return path.as_posix()


def _strings(value: object, field: str, *, empty: bool = False) -> tuple[str, ...]:
    if not isinstance(value, list) or (not value and not empty) or len(value) > 64:
        raise ValueError(f"{field} must be a bounded string list")
    if any(not isinstance(item, str) or not item.strip() for item in value):
        raise ValueError(f"{field} must be a bounded string list")
    return tuple(item.strip() for item in value)


def load_sources(
    registry_path: Path | None,
    legacy_docs_root: Path,
    *,
    multi_root_enabled: bool,
) -> tuple[tuple[SourceSpec, ...], str]:
    """Return the entire declared run set and a content-derived registry key.

    Without explicit registry configuration, preserve the existing Probata-only
    source. Multi-root activation requires both the path and the enable flag.
    """
    if registry_path is None:
        if multi_root_enabled:
            raise ValueError("DOCSTORE_MULTI_ROOT_ENABLED requires DOCSTORE_PROJECT_REGISTRY")
        legacy = SourceSpec(
            "probata", legacy_docs_root.resolve(), "docs/", ("docs",),
            ("**/*.md",), ("private/**", "**/to_be_deleted/**"),
            "current-full-source",
        )
        return (legacy,), "legacy-probata-docs-v1"

    path = registry_path.resolve(strict=True)
    raw = path.read_bytes()
    if len(raw) > MAX_REGISTRY_BYTES:
        raise ValueError("Docstore source registry exceeds 256 KiB")
    payload = json.loads(raw)
    if not isinstance(payload, dict) or payload.get("schema") != "propria-docstore-source-registry-v1":
        raise ValueError("Unsupported Docstore source registry schema")
    root_value = payload.get("monorepo_root")
    if not isinstance(root_value, str) or not Path(root_value).is_absolute():
        raise ValueError("monorepo_root must be absolute")
    monorepo_root = Path(root_value).resolve(strict=True)
    entries = payload.get("projects")
    if not isinstance(entries, list) or not 1 <= len(entries) <= 64:
        raise ValueError("projects must contain 1-64 registrations")

    all_sources: list[SourceSpec] = []
    seen_ids: set[str] = set()
    seen_prefixes: set[str] = set()
    for entry in entries:
        if not isinstance(entry, dict) or entry.get("registration_status") != "active":
            continue
        project_id = entry.get("project_id")
        if not isinstance(project_id, str) or not _ID.fullmatch(project_id):
            raise ValueError("Invalid project_id")
        if project_id in seen_ids:
            raise ValueError(f"Duplicate project_id: {project_id}")
        seen_ids.add(project_id)
        source_relative = _relative(entry.get("source_root"), "source_root")
        source_root = (monorepo_root / Path(source_relative)).resolve(strict=False)
        if not source_root.is_relative_to(monorepo_root):
            raise ValueError(f"{project_id}: source root escapes monorepo")
        required = bool(entry.get("required", True))
        if required and not source_root.is_dir():
            raise ValueError(f"{project_id}: required source root is missing")
        prefix = _relative(entry.get("canonical_prefix"), "canonical_prefix") + "/"
        if prefix in seen_prefixes:
            raise ValueError(f"Duplicate canonical_prefix: {prefix}")
        seen_prefixes.add(prefix)
        ingestion = entry.get("ingestion_status")
        if ingestion not in {"current-full-source", "pending-multi-root-cdc", "excluded"}:
            raise ValueError(f"{project_id}: invalid ingestion status")
        if ingestion == "excluded":
            continue
        all_sources.append(SourceSpec(
            project_id=project_id,
            root=source_root,
            canonical_prefix=prefix,
            domains=_strings(entry.get("domains"), "domains"),
            included_patterns=_strings(entry.get("included_patterns"), "included_patterns"),
            excluded_patterns=_strings(entry.get("excluded_patterns", []), "excluded_patterns", empty=True),
            ingestion_status=ingestion,
        ))

    current = [source for source in all_sources if source.ingestion_status == "current-full-source"]
    if len(current) != 1:
        raise ValueError("Registry must declare exactly one current-full-source root")
    selected = all_sources if multi_root_enabled else current
    return tuple(selected), hashlib.sha256(raw).hexdigest()
