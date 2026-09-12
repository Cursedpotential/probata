"""Core repair types — deliberately import-light (stdlib only).

Byline: Claude Code . Opus 5 (1M) . 2026-08-02

This module is imported by `reference.load_builtin_tools()`'s recursive walk and
is reachable from the dep-light `deploy/docker/tool-runtime` facade, so it must never import
lxml / ijson / clevercsv / bs4. Those live behind function-local imports in
`engines.py`.

THE SEVERITY TAXONOMY IS THE POINT OF THIS FILE.

A repair that silently loses a record is indistinguishable from the parser bug
that dropped 516 body-less MMS: nothing raises, the numbers just come out
smaller. So every repair is classified by whether it can cost evidence:

    cosmetic    nothing informational changed  (BOM stripped, trailing space)
    structural  shape fixed, content preserved (tag auto-closed, row padded)
    lossy       bytes were discarded/replaced  (control char removed, undecodable
                byte -> U+FFFD, field truncated)

Only `lossy` can lose evidence. `Chunk.lossy` and `RepairReport.lossy_count`
exist so an ingest can gate on it, and so the reconciliation view can show
"parsed 13,664, of which 12 required lossy repair" instead of a silent 13,652.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Literal

Severity = Literal["cosmetic", "structural", "lossy"]

COSMETIC: Severity = "cosmetic"
STRUCTURAL: Severity = "structural"
LOSSY: Severity = "lossy"

#: Ordered worst-last, so `max(..., key=SEVERITY_RANK.get)` picks the worst.
SEVERITY_RANK: dict[str, int] = {COSMETIC: 0, STRUCTURAL: 1, LOSSY: 2}


@dataclass(frozen=True, slots=True)
class RepairEvent:
    """One thing that was wrong with the bytes, and what was done about it.

    Frozen because a repair record is evidence: once written it is a statement
    about what we did to the file, and nothing downstream may quietly amend it.
    """

    kind: str  # stable slug: "bare_ampersand", "unclosed_tag", "ragged_row", ...
    detail: str  # human-readable, safe to log (never carries message content)
    severity: Severity = STRUCTURAL
    byte_offset: int | None = None
    line: int | None = None
    chunk_index: int | None = None

    @property
    def loses_evidence(self) -> bool:
        return self.severity == LOSSY

    def as_row(self) -> dict[str, Any]:
        """Shape for the ingest ledger (evidence.raw_rejected / raw_repaired)."""
        return {
            "kind": self.kind,
            "detail": self.detail,
            "severity": self.severity,
            "byte_offset": self.byte_offset,
            "line": self.line,
            "chunk_index": self.chunk_index,
        }


@dataclass(slots=True)
class Chunk:
    """One structural unit of the file — the thing the caller actually processes.

    `node` is the format's natural node, NOT a byte range:
        xml   -> lxml Element (the record subtree; already detached from the doc)
        json  -> dict / list  (one item of the streamed array)
        csv   -> dict[str, str] (one row, keyed by header)
        html  -> lxml HtmlElement

    That is what makes damage containable: a broken <mms> costs you one message,
    not the remaining 600 MB of the export.
    """

    index: int
    kind: str  # "element" | "object" | "row"
    node: Any
    repairs: list[RepairEvent] = field(default_factory=list)
    ok: bool = True
    error: str | None = None

    @property
    def lossy(self) -> bool:
        return any(r.loses_evidence for r in self.repairs)

    @property
    def worst_severity(self) -> Severity | None:
        if not self.repairs:
            return None
        return max((r.severity for r in self.repairs), key=lambda s: SEVERITY_RANK[s])


@dataclass(slots=True)
class Detection:
    """What `detect()` concluded from a BOUNDED head read — never the whole file."""

    fmt: str  # "xml" | "json" | "csv" | "html" | "unknown"
    encoding: str
    engine: str | None = None  # which engine will handle it, or None if unavailable
    confidence: float = 0.0
    had_bom: bool = False
    notes: list[str] = field(default_factory=list)

    @property
    def usable(self) -> bool:
        return self.fmt != "unknown" and self.engine is not None


@dataclass(slots=True)
class RepairReport:
    """Running tally over a stream. Feeds the ingest funnel counters.

    `chunks_failed` is deliberately separate from `lossy_count`: a chunk that
    could not be produced at all is an ABSENCE (it belongs in raw_rejected),
    while a lossy chunk did land but is degraded. Conflating them is how a
    reconciliation ends up claiming a clean run.
    """

    fmt: str = "unknown"
    encoding: str = ""
    chunks_ok: int = 0
    chunks_failed: int = 0
    events: list[RepairEvent] = field(default_factory=list)
    truncated: bool = False  # stream ended mid-structure (file cut off)

    def record(self, chunk: Chunk) -> None:
        if chunk.ok:
            self.chunks_ok += 1
        else:
            self.chunks_failed += 1
        self.events.extend(chunk.repairs)

    @property
    def lossy_count(self) -> int:
        return sum(1 for e in self.events if e.loses_evidence)

    @property
    def clean(self) -> bool:
        """True only if nothing was lost AND nothing failed AND nothing was cut off."""
        return not self.lossy_count and not self.chunks_failed and not self.truncated

    def counts_by_kind(self) -> dict[str, int]:
        out: dict[str, int] = {}
        for e in self.events:
            out[e.kind] = out.get(e.kind, 0) + 1
        return out

    def summary(self) -> dict[str, Any]:
        return {
            "format": self.fmt,
            "encoding": self.encoding,
            "chunks_ok": self.chunks_ok,
            "chunks_failed": self.chunks_failed,
            "repairs": len(self.events),
            "lossy": self.lossy_count,
            "truncated": self.truncated,
            "clean": self.clean,
            "by_kind": self.counts_by_kind(),
        }
