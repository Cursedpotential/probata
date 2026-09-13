"""Governed Propria documentation-source registry and MCP discovery surface.

The registry describes source ownership and intended ingestion. It never walks,
hydrates, copies, indexes, or mutates a registered source. CocoIndex remains the
only document projection writer.
"""
from __future__ import annotations

import json
import re
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Any

from fastmcp.exceptions import ToolError


MAX_REGISTRY_BYTES = 256 * 1024
MAX_PROJECTS = 64
_ID = re.compile(r"[a-z][a-z0-9-]{1,47}")
_STATES = {"active", "planned", "blocked", "retired"}
_INGESTION = {"current-full-source", "pending-multi-root-cdc", "excluded"}


@dataclass(frozen=True)
class ProjectSource:
    project_id: str
    title: str
    root: Path
    root_relative: str
    canonical_prefix: str
    domains: tuple[str, ...]
    included_patterns: tuple[str, ...]
    excluded_patterns: tuple[str, ...]
    registration_status: str
    ingestion_status: str
    required: bool

    def public(self) -> dict[str, Any]:
        return {
            "project_id": self.project_id,
            "title": self.title,
            "source_root": str(self.root),
            "source_root_relative": self.root_relative,
            "canonical_prefix": self.canonical_prefix,
            "domains": list(self.domains),
            "included_patterns": list(self.included_patterns),
            "excluded_patterns": list(self.excluded_patterns),
            "registration_status": self.registration_status,
            "ingestion_status": self.ingestion_status,
            "required": self.required,
            "index_kind": "docs",
            "allowed_file_classes": ["markdown"],
            "source_exists": self.root.is_dir(),
        }


@dataclass(frozen=True)
class ProjectRegistry:
    path: Path
    monorepo_root: Path
    projects: tuple[ProjectSource, ...]

    def public(self) -> dict[str, Any]:
        values = [project.public() for project in self.projects]
        return {
            "schema": "propria-docstore-source-registry-v1",
            "registry_path": str(self.path),
            "monorepo_root": str(self.monorepo_root),
            "project_count": len(values),
            "active_count": sum(p["registration_status"] == "active" for p in values),
            "current_ingestion_count": sum(
                p["ingestion_status"] == "current-full-source" for p in values
            ),
            "projects": values,
            "indexing_triggered": False,
            "source_files_read": False,
        }

    def get(self, project_id: str) -> ProjectSource:
        for project in self.projects:
            if project.project_id == project_id:
                return project
        raise ToolError(
            f"Unknown Docstore project ID {project_id!r}; read docstore://projects first"
        )


def _safe_relative(value: object, field: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{field} must be a non-empty relative path")
    normalized = value.replace("\\", "/").strip()
    if normalized.startswith("/") or re.match(r"^[A-Za-z]:/", normalized):
        raise ValueError(f"{field} must stay within the monorepo")
    normalized = normalized.rstrip("/")
    path = PurePosixPath(normalized)
    if path.is_absolute() or ".." in path.parts:
        raise ValueError(f"{field} must stay within the monorepo")
    return path.as_posix()


def _strings(value: object, field: str, *, allow_empty: bool = False) -> tuple[str, ...]:
    if not isinstance(value, list) or (not value and not allow_empty):
        raise ValueError(f"{field} must be a bounded string list")
    if len(value) > 64 or any(not isinstance(item, str) or not item.strip() for item in value):
        raise ValueError(f"{field} must be a bounded string list")
    return tuple(item.strip() for item in value)


def load_registry(path: Path) -> ProjectRegistry:
    resolved_path = path.resolve(strict=True)
    if not resolved_path.is_file():
        raise ValueError("Docstore project registry must be a file")
    raw = resolved_path.read_bytes()
    if len(raw) > MAX_REGISTRY_BYTES:
        raise ValueError("Docstore project registry exceeds 256 KiB")
    payload = json.loads(raw)
    if not isinstance(payload, dict) or payload.get("schema") != "propria-docstore-source-registry-v1":
        raise ValueError("Unsupported Docstore project registry schema")
    root_value = payload.get("monorepo_root")
    if not isinstance(root_value, str) or not Path(root_value).is_absolute():
        raise ValueError("monorepo_root must be an explicit absolute path")
    monorepo_root = Path(root_value).resolve(strict=True)
    entries = payload.get("projects")
    if not isinstance(entries, list) or not 1 <= len(entries) <= MAX_PROJECTS:
        raise ValueError("projects must contain between 1 and 64 registrations")

    projects: list[ProjectSource] = []
    seen_ids: set[str] = set()
    seen_prefixes: set[str] = set()
    for entry in entries:
        if not isinstance(entry, dict):
            raise ValueError("Each project registration must be an object")
        project_id = entry.get("project_id")
        if not isinstance(project_id, str) or not _ID.fullmatch(project_id):
            raise ValueError("project_id must be a lowercase stable identifier")
        if project_id in seen_ids:
            raise ValueError(f"Duplicate project_id: {project_id}")
        seen_ids.add(project_id)
        root_relative = _safe_relative(entry.get("source_root"), "source_root")
        root = (monorepo_root / Path(root_relative)).resolve(strict=False)
        if not root.is_relative_to(monorepo_root):
            raise ValueError(f"{project_id}: source root escapes the monorepo")
        required = bool(entry.get("required", True))
        if required and not root.is_dir():
            raise ValueError(f"{project_id}: required source root does not exist")
        prefix = _safe_relative(entry.get("canonical_prefix"), "canonical_prefix") + "/"
        if prefix in seen_prefixes:
            raise ValueError(f"Duplicate canonical_prefix: {prefix}")
        seen_prefixes.add(prefix)
        state = entry.get("registration_status")
        ingestion = entry.get("ingestion_status")
        if state not in _STATES or ingestion not in _INGESTION:
            raise ValueError(f"{project_id}: invalid registration or ingestion status")
        title = entry.get("title")
        if not isinstance(title, str) or not title.strip() or len(title) > 200:
            raise ValueError(f"{project_id}: title must be 1-200 characters")
        included = _strings(entry.get("included_patterns"), "included_patterns")
        if any(not pattern.lower().endswith(".md") for pattern in included):
            raise ValueError(f"{project_id}: docs index permits only Markdown source patterns")
        projects.append(ProjectSource(
            project_id=project_id,
            title=title.strip(),
            root=root,
            root_relative=root_relative,
            canonical_prefix=prefix,
            domains=_strings(entry.get("domains"), "domains"),
            included_patterns=included,
            excluded_patterns=_strings(
                entry.get("excluded_patterns", []), "excluded_patterns", allow_empty=True
            ),
            registration_status=state,
            ingestion_status=ingestion,
            required=required,
        ))
    return ProjectRegistry(resolved_path, monorepo_root, tuple(projects))


def read_registry(config: Any) -> ProjectRegistry:
    if config.project_registry is None:
        raise ToolError(
            "Universal Docstore project registry is not configured; set DOCSTORE_PROJECT_REGISTRY"
        )
    try:
        return load_registry(config.project_registry)
    except (OSError, ValueError, json.JSONDecodeError):
        raise ToolError("Universal Docstore project registry is invalid or unavailable") from None


def registry_status(config: Any) -> dict[str, Any]:
    if config.project_registry is None:
        return {
            "status": "unconfigured",
            "project_count": 0,
            "indexing_triggered": False,
            "source_files_read": False,
        }
    try:
        return {"status": "available", **load_registry(config.project_registry).public()}
    except (OSError, ValueError, json.JSONDecodeError):
        return {
            "status": "unavailable",
            "project_count": 0,
            "indexing_triggered": False,
            "source_files_read": False,
        }


def register(mcp: Any, config: Any, read_annotations: dict[str, bool]) -> None:
    @mcp.tool(annotations={**read_annotations, "title": "List Docstore project sources"})
    def docstore_project_sources() -> dict[str, Any]:
        """List governed Propria documentation roots and declared ingestion state; does not scan or index files."""
        return read_registry(config).public()

    @mcp.tool(annotations={**read_annotations, "title": "Get Docstore project source"})
    def docstore_project_source(project_id: str) -> dict[str, Any]:
        """Get one registered documentation source by stable project ID; read docstore_project_sources for IDs."""
        registry = read_registry(config)
        return {
            "schema": "propria-docstore-source-registry-v1",
            "project": registry.get(project_id).public(),
            "indexing_triggered": False,
            "source_files_read": False,
        }

    @mcp.resource("docstore://projects")
    def projects_resource() -> dict[str, Any]:
        """Governed Propria project documentation-source registry."""
        return registry_status(config)

    @mcp.resource("docstore://project/{project_id}")
    def project_resource(project_id: str) -> dict[str, Any]:
        """One governed project documentation-source registration."""
        registry = read_registry(config)
        return {
            "schema": "propria-docstore-source-registry-v1",
            "project": registry.get(project_id).public(),
            "indexing_triggered": False,
            "source_files_read": False,
        }
