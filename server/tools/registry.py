"""
server/tools/reference.py — the atomic-tool registry (polyglot orchestration mesh).
Cross-domain capability layer (D-026): consumed by evidence, analysis, agents,
workflows, and the CLI — not owned by any single domain.

A tool = ONE capability implemented by ONE library/runtime, registered with a
contract. Workflows resolve steps by CAPABILITY, not by hard-coded function:
when a step fails, the executor can surface same-capability alternatives for
an agent to swap in (re-composition happens in the sandbox; ADR/canon §5).

Python-native tools register in-process via @register. Polyglot tools (TS/Go
binaries, MCP servers, HTTP services like SBV) register with a runner that
shells out / calls HTTP — same contract, different transport.
"""

# Byline amendment: Codex · GPT-5 · 2026-08-18 (stable explicit tool priority)

from __future__ import annotations

import re
from collections.abc import Callable, Mapping
from dataclasses import dataclass, field
from typing import Any, Literal, Protocol, runtime_checkable


_UNVERSIONED = "unversioned"
_VERSION_PATTERN = re.compile(r"^[A-Za-z0-9](?:[A-Za-z0-9._+-]*[A-Za-z0-9])?$")
_FORMAT_ID_PATTERN = re.compile(r"^[a-z](?:[a-z0-9]*|[a-z0-9]*(?:_[a-z0-9]+)+)$")
ToolQuality = Literal["primary", "fallback", "experimental"]
_TOOL_QUALITY_RANKS = frozenset({"primary", "fallback", "experimental"})


def _validate_version(field_name: str, value: str) -> str:
    """Require a stable, transport-safe version token or the explicit default."""
    if not isinstance(value, str) or not value or value != value.strip() or not _VERSION_PATTERN.fullmatch(value):
        raise ValueError(
            f"registry: {field_name} must be a non-empty version token containing only "
            "letters, numbers, '.', '_', '+', or '-'"
        )
    return value


def _validate_format(format_name: str) -> str:
    if (
        not isinstance(format_name, str)
        or len(format_name) < 1
        or len(format_name) > 59
        or not _FORMAT_ID_PATTERN.fullmatch(format_name)
    ):
        raise ValueError("registry: format id must be 1 through 59 characters of canonical lowercase snake_case")
    return format_name


def _normalize_declarations(
    formats: tuple[str, ...] | None,
    quality: Mapping[str, ToolQuality] | None,
) -> tuple[tuple[str, ...], tuple[tuple[str, ToolQuality], ...]]:
    if formats is not None and not isinstance(formats, tuple):
        raise ValueError("registry: formats must be a tuple of format identifiers")
    normalized_formats = tuple(sorted(_validate_format(format_name) for format_name in (formats or ())))
    if len(set(normalized_formats)) != len(normalized_formats):
        raise ValueError("registry: formats must contain unique identifiers")
    if quality is not None and not isinstance(quality, Mapping):
        raise ValueError("registry: quality must map declared formats to selector ranks")

    normalized_quality: list[tuple[str, ToolQuality]] = []
    declared = set(normalized_formats)
    for format_name, rank in sorted((quality or {}).items()):
        _validate_format(format_name)
        if format_name not in declared:
            raise ValueError(f"registry: quality key {format_name!r} is not present in formats")
        if rank not in _TOOL_QUALITY_RANKS:
            raise ValueError(
                f"registry: quality rank for {format_name!r} must be one of 'primary', 'fallback', or 'experimental'"
            )
        normalized_quality.append((format_name, rank))
    return normalized_formats, tuple(normalized_quality)


@runtime_checkable
class ToolPlugin(Protocol):
    """Contract every atomic tool satisfies."""

    @property
    def id(self) -> str: ...

    @property
    def capability(self) -> str: ...

    @property
    def description(self) -> str: ...

    @property
    def execution_policy(self) -> str: ...

    @property
    def side_effect(self) -> str: ...

    @property
    def priority(self) -> int: ...

    @property
    def tool_version(self) -> str: ...

    @property
    def contract_version(self) -> str: ...

    @property
    def input_schema_version(self) -> str: ...

    @property
    def output_schema_version(self) -> str: ...

    @property
    def formats(self) -> tuple[str, ...]: ...

    @property
    def quality(self) -> tuple[tuple[str, ToolQuality], ...]: ...

    def accepts(self, media_hint: str, size_bytes: int) -> bool: ...
    def run(self, payload: dict[str, Any]) -> dict[str, Any]: ...


@dataclass(frozen=True)
class FunctionTool:
    """In-process Python tool: wraps a callable under the ToolPlugin contract."""

    id: str
    capability: str
    description: str
    fn: Callable[[dict[str, Any]], dict[str, Any]]
    accept: Callable[[str, int], bool] = field(default=lambda hint, size: True)
    provenance: str = ""  # where the implementation came from (port source)
    execution_policy: str = "manual_or_auto"
    side_effect: str = "read_only"
    priority: int = 0
    tool_version: str = _UNVERSIONED
    contract_version: str = _UNVERSIONED
    input_schema_version: str = _UNVERSIONED
    output_schema_version: str = _UNVERSIONED
    formats: tuple[str, ...] = ()
    quality: tuple[tuple[str, ToolQuality], ...] = ()

    def __post_init__(self) -> None:
        _validate_version("tool_version", self.tool_version)
        _validate_version("contract_version", self.contract_version)
        _validate_version("input_schema_version", self.input_schema_version)
        _validate_version("output_schema_version", self.output_schema_version)
        if not isinstance(self.quality, tuple) or not all(
            isinstance(declaration, tuple) and len(declaration) == 2 for declaration in self.quality
        ):
            raise ValueError("registry: quality declarations must be an immutable tuple of format/rank pairs")
        quality_mapping = dict(self.quality)
        if len(quality_mapping) != len(self.quality):
            raise ValueError("registry: quality declarations must name each format at most once")
        normalized_formats, normalized_quality = _normalize_declarations(self.formats, quality_mapping)
        if normalized_formats != self.formats:
            raise ValueError("registry: formats must be sorted")
        if normalized_quality != self.quality:
            raise ValueError("registry: quality declarations must be unique and sorted by format")

    def accepts(self, media_hint: str, size_bytes: int) -> bool:
        return self.accept(media_hint, size_bytes)

    def run(self, payload: dict[str, Any]) -> dict[str, Any]:
        return self.fn(payload)


class ToolRegistry:
    def __init__(self) -> None:
        self._tools: dict[str, ToolPlugin] = {}

    def register(self, tool: ToolPlugin) -> ToolPlugin:
        if tool.id in self._tools:
            raise ValueError(f"registry: duplicate tool id {tool.id!r}")
        self._tools[tool.id] = tool
        return tool

    def get(self, tool_id: str) -> ToolPlugin:
        if tool_id not in self._tools:
            raise KeyError(f"registry: unknown tool {tool_id!r}")
        return self._tools[tool_id]

    def all(self) -> list[ToolPlugin]:
        return list(self._tools.values())

    def resolve(self, capability: str, media_hint: str = "", size_bytes: int = 0) -> list[ToolPlugin]:
        """All accepting tools, highest explicit priority first.

        Registration order remains the stable tie-breaker, so existing
        capabilities retain their behavior while a declared primary is not
        accidentally demoted by test/import order.
        """
        matches = [t for t in self._tools.values() if t.capability == capability and t.accepts(media_hint, size_bytes)]
        return sorted(matches, key=lambda tool: getattr(tool, "priority", 0), reverse=True)

    def manifest(self) -> list[dict[str, str]]:
        """Legacy inventory retained for existing in-process Python consumers.

        New direct consumers use contract_manifest() through GET /tools.
        """
        return [
            {
                "id": t.id,
                "capability": t.capability,
                "description": t.description,
                "provenance": getattr(t, "provenance", ""),
                "execution_policy": getattr(t, "execution_policy", "manual_or_auto"),
                "side_effect": getattr(t, "side_effect", "read_only"),
            }
            for t in self._tools.values()
        ]

    def contract_manifest(self) -> list[dict[str, Any]]:
        """Canonical deterministic declarations exposed by the tool-runtime facade.

        Declared quality values are selector ranks only, not observed output-quality
        scores. Execution success, completeness, and observed quality require separate
        version-pinned receipts.
        Direct consumers, including the Go engine, call the facade rather than
        duplicating tool implementations outside the tool runtime.
        """
        return [
            {
                "id": tool.id,
                "capability": tool.capability,
                "description": tool.description,
                "provenance": getattr(tool, "provenance", ""),
                "execution_policy": getattr(tool, "execution_policy", "manual_or_auto"),
                "side_effect": getattr(tool, "side_effect", "read_only"),
                "tool_version": getattr(tool, "tool_version", _UNVERSIONED),
                "contract_version": getattr(tool, "contract_version", _UNVERSIONED),
                "input_schema_version": getattr(tool, "input_schema_version", _UNVERSIONED),
                "output_schema_version": getattr(tool, "output_schema_version", _UNVERSIONED),
                "formats": list(getattr(tool, "formats", ())),
                "quality": dict(getattr(tool, "quality", ())),
            }
            for tool in sorted(self._tools.values(), key=lambda candidate: candidate.id)
        ]


# The process-wide registry. Built-in tools self-register on import.
registry = ToolRegistry()


def register(
    *,
    id: str,
    capability: str,
    description: str,
    accept: Callable[[str, int], bool] | None = None,
    provenance: str = "",
    execution_policy: str = "manual_or_auto",
    side_effect: str = "read_only",
    priority: int = 0,
    tool_version: str = _UNVERSIONED,
    contract_version: str = _UNVERSIONED,
    input_schema_version: str = _UNVERSIONED,
    output_schema_version: str = _UNVERSIONED,
    formats: tuple[str, ...] | None = None,
    quality: Mapping[str, ToolQuality] | None = None,
) -> Callable:
    """Decorator: register a payload->payload function as an atomic tool."""

    def _wrap(fn: Callable[[dict[str, Any]], dict[str, Any]]) -> Callable:
        normalized_formats, normalized_quality = _normalize_declarations(formats, quality)
        registry.register(
            FunctionTool(
                id=id,
                capability=capability,
                description=description,
                fn=fn,
                accept=accept or (lambda hint, size: True),
                provenance=provenance,
                execution_policy=execution_policy,
                side_effect=side_effect,
                priority=priority,
                tool_version=tool_version,
                contract_version=contract_version,
                input_schema_version=input_schema_version,
                output_schema_version=output_schema_version,
                formats=normalized_formats,
                quality=normalized_quality,
            )
        )
        return fn

    return _wrap


def load_builtin_tools() -> int:
    """AUTO-DISCOVER tool modules: RECURSIVELY import every public tool module in
    this package (server.tools — the cross-domain capability layer, D-026 — used
    by evidence/analysis/agents/workflows/CLI alike) so each self-registers (one
    parser = one swappable module — owner architecture). Idempotent: re-imports
    are no-ops, duplicate ids raise at import time.

    Since ADR-0035 the tools live in capability sub-packages
    (parsers/{messaging,ai_chat,generic}/, extractors/), so discovery must walk
    the tree RECURSIVELY — pkgutil.walk_packages, not the old top-level-only
    iter_modules. Skips:
      * any module whose FINAL path segment starts with '_' (shared helpers like
        _common / _chatminer_adapter / _sbv_client — not tools);
      * the `gateway` sub-package (the G4 tool gateway / ex-tool_finder — a
        consumer of the registry, never a registered tool; it also carries the
        heavier FastAPI surface in its api/__main__ modules).
    Sub-package __init__ modules register nothing, so they're skipped too.

    Package-name-AGNOSTIC on purpose (walks tools_pkg.__name__, not a hardcoded
    "server.tools"): this same tree is also included in the tool-runtime
    facade container — see deploy/docker/tool-runtime/tools/facade.py's module
    docstring for the mount<->import contract.

    Memoized after the first successful walk: re-imports were always no-ops,
    but the pkgutil filesystem walk itself ran on EVERY gateway meta-op call
    (categories/search/describe/execute/get_ref each call _ensure_loaded).
    """
    global _BUILTINS_LOADED
    if _BUILTINS_LOADED:
        return len(registry.all())
    import importlib
    import pkgutil

    pkg_name = __package__  # "server.tools" in-repo; "server.tools" in the facade (whole server/ tree mounted)
    assert pkg_name, "load_builtin_tools() requires reference.py to be imported as a package module"
    tools_pkg = importlib.import_module(pkg_name)

    prefix = tools_pkg.__name__ + "."
    for mod in pkgutil.walk_packages(tools_pkg.__path__, prefix=prefix):
        rel = mod.name[len(prefix) :]  # path relative to the tools package
        segments = rel.split(".")
        if segments[-1].startswith("_"):  # shared helper (_common, _sbv_client, ...)
            continue
        if segments[0] == "gateway":  # registry consumer, not a tool
            continue
        if mod.ispkg:  # capability sub-packages register nothing
            continue
        importlib.import_module(mod.name)
    _BUILTINS_LOADED = True
    return len(registry.all())


_BUILTINS_LOADED = False
