"""Engine registry: which library repairs which format, and is it actually here.

Byline: Claude Code . Opus 5 (1M) . 2026-08-02

WHY EVERY THIRD-PARTY IMPORT IN THIS PACKAGE IS FUNCTION-LOCAL
-------------------------------------------------------------
`reference.load_builtin_tools()` walks `server/tools/` RECURSIVELY and imports
every module whose final path segment does not start with `_`. That walk also
runs inside the dep-light `deploy/docker/tool-runtime` facade container, which includes
the whole `server/` tree but installs almost none of its dependencies.

A module-level `import lxml` anywhere under `server/tools/repair/` would
therefore FATAL-loop the facade on startup — the identical failure mode
`server/tools/AGENTS.md` warns about for `server.contracts`, and which the
ADR-0033-era two-day outage already paid for once.

So: nothing here imports a repair library at module scope. `available()` probes
with `find_spec` (no execution), and `engine_for()` returns None for a format
whose library is missing, which turns "dependency absent" into a routed,
reportable state instead of a crash.
"""

from __future__ import annotations

import importlib.metadata
import importlib.util
from collections.abc import Callable, Iterator
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from server.tools.repair import chunkers
from server.tools.repair.types import Chunk, RepairReport


@dataclass(frozen=True, slots=True)
class EngineSpec:
    name: str
    fmt: str
    requires: tuple[str, ...]  # importable module names, ALL required
    iterator: Callable[..., Iterator[Chunk]]
    chunk_kind: str
    description: str
    #: At least ONE of these must be importable. PDF text can come from pypdf,
    #: pdfplumber, or Tesseract — any one of them makes the engine usable, so
    #: an all-required check would wrongly report it dead.
    any_of: tuple[str, ...] = ()


ENGINES: tuple[EngineSpec, ...] = (
    EngineSpec(
        name="lxml-recover",
        fmt="xml",
        requires=("lxml",),
        iterator=chunkers.iter_xml,
        chunk_kind="element",
        description="libxml2 recover=True over iterparse — recovers WHILE streaming",
    ),
    EngineSpec(
        name="lxml-html",
        fmt="html",
        requires=("lxml",),
        iterator=chunkers.iter_html,
        chunk_kind="element",
        description="libxml2 HTML parser (recovering by design)",
    ),
    EngineSpec(
        name="ijson+json-repair",
        fmt="json",
        requires=("ijson",),
        iterator=chunkers.iter_json,
        chunk_kind="object",
        description="ijson streams array items; json-repair is the capped fallback",
    ),
    EngineSpec(
        name="ndjson-per-line",
        fmt="ndjson",
        requires=(),  # stdlib json is enough; json-repair only improves it
        iterator=chunkers.iter_ndjson,
        chunk_kind="object",
        description="one object per line, each repaired independently",
    ),
    EngineSpec(
        name="clevercsv",
        fmt="csv",
        requires=(),  # degrades to csv.Sniffer when CleverCSV is absent
        iterator=chunkers.iter_csv,
        chunk_kind="row",
        description="CleverCSV dialect detection + non-truncating ragged-row repair",
    ),
    EngineSpec(
        name="extract.text-tiered",
        fmt="pdf",
        requires=(),
        any_of=("pypdf", "pdfplumber", "pytesseract"),
        iterator=chunkers.iter_pdf,
        chunk_kind="page",
        description="native text layer (pypdf/pdfplumber) then Tesseract OCR; OCR is LOSSY",
    ),
    EngineSpec(
        name="extract.text-ocr",
        fmt="image",
        requires=(),
        any_of=("pytesseract",),
        iterator=chunkers.iter_pdf,  # extract.text routes by extension
        chunk_kind="page",
        description="Tesseract OCR over a single image; always LOSSY by construction",
    ),
)

_BY_FORMAT: dict[str, EngineSpec] = {e.fmt: e for e in ENGINES}

#: Everything the repair layer can make use of, including the two libraries that
#: predate it. Reported by `available()` so a caller can see the whole surface.
OPTIONAL_LIBS: tuple[str, ...] = (
    "lxml",
    "ijson",
    "json_repair",
    "clevercsv",
    "charset_normalizer",
    "bs4",
    # document tier (server/tools/extractors/extract_text.py)
    "pypdf",
    "pdfplumber",
    "pytesseract",
    "pdf2image",
    "PIL",
)

#: Import name -> distribution name, where they differ.
_DIST_NAME: dict[str, str] = {
    "json_repair": "json-repair",
    "bs4": "beautifulsoup4",
    "charset_normalizer": "charset-normalizer",
    "PIL": "pillow",
}


def _installed(module: str) -> bool:
    """Presence check that does NOT execute the module."""
    try:
        return importlib.util.find_spec(module) is not None
    except (ImportError, ValueError):
        return False


def available() -> dict[str, str | None]:
    """{import name: version or None}. None means the library is not installed.

    Use this rather than a try/except import when you want to *report* capability
    — it never triggers a module's import side effects.
    """
    out: dict[str, str | None] = {}
    for mod in OPTIONAL_LIBS:
        if not _installed(mod):
            out[mod] = None
            continue
        try:
            out[mod] = importlib.metadata.version(_DIST_NAME.get(mod, mod))
        except importlib.metadata.PackageNotFoundError:
            out[mod] = "present"
    return out


def engine_for(fmt: str) -> str | None:
    """Engine name for a format, or None if the format is unknown OR its
    required libraries are missing."""
    spec = _BY_FORMAT.get(fmt)
    if spec is None:
        return None
    if not all(_installed(m) for m in spec.requires):
        return None
    if spec.any_of and not any(_installed(m) for m in spec.any_of):
        return None
    return spec.name


def spec_for(fmt: str) -> EngineSpec | None:
    return _BY_FORMAT.get(fmt)


def missing_for(fmt: str) -> tuple[str, ...]:
    """Which required libraries are absent for this format."""
    spec = _BY_FORMAT.get(fmt)
    if spec is None:
        return ()
    missing = tuple(m for m in spec.requires if not _installed(m))
    # any_of is reported as a group: none of them present means the whole group
    # is what's missing, and installing ANY ONE clears it.
    if spec.any_of and not any(_installed(m) for m in spec.any_of):
        missing += (f"one of ({', '.join(spec.any_of)})",)
    return missing


def manifest() -> list[dict[str, Any]]:
    """Human/agent-readable capability table — mirrors registry.manifest()."""
    return [
        {
            "engine": e.name,
            "format": e.fmt,
            "chunk_kind": e.chunk_kind,
            "requires": list(e.requires),
            "ready": engine_for(e.fmt) is not None,
            "missing": list(missing_for(e.fmt)),
            "description": e.description,
        }
        for e in ENGINES
    ]


def iter_chunks(
    path: Path,
    fmt: str | None = None,
    report: RepairReport | None = None,
    **kw: Any,
) -> Iterator[Chunk]:
    """THE entry point: detect the format, route to its engine, stream chunks.

    Pass `fmt` only to override detection. `report` collects RepairEvents across
    the whole stream — pass one in if you intend to write the ingest ledger,
    which you should.
    """
    from server.tools.repair.detect import detect

    if fmt is None:
        detection = detect(path)
        fmt = detection.fmt
        if report is not None:
            report.fmt = fmt
            report.encoding = detection.encoding

    spec = _BY_FORMAT.get(fmt)
    if spec is None:
        raise ValueError(f"repair: no engine for format {fmt!r} ({path.name})")

    missing = missing_for(fmt)
    if missing:
        raise ImportError(
            f"repair: engine {spec.name!r} for {fmt!r} needs {', '.join(missing)} "
            f"— install it or route this file elsewhere"
        )

    # Recording lives in the CHUNKERS, not here: a caller who uses iter_csv()
    # directly must get the same populated report as one who routes through
    # iter_chunks(). Recording in both places would double-count instead.
    yield from spec.iterator(path, report=report, **kw)
