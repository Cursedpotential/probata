# Byline amendment: Codex · GPT-5 · 2026-08-18 (combined-change hygiene)
"""server/analysis/sbv_transcript.py — the GO parse engine for the context lane.

The Go half of the engine-dynamic parse seam (owner, 2026-08-12: "the pipeline
needs to be dynamic ... it shouldn't be dedicated to one format or the other").
Where `context_chat_ingest.parse_chat_export(engine="python")` runs the
in-process Python registry parsers, `engine="go"` routes HERE: the file is
handed to the SBV Go service (the universal, memory-safe decoder — ADR-0049),
which parses it with whichever Go importer matches (or the `format` override),
and the canonical records are read back and mapped to the SAME
`NormalizedRecord` shape the Python path emits. Downstream is byte-for-byte
identical — PG `working.context_record` → change-detection → Weaviate/Graphiti
— so the ONLY thing the engine choice changes is who does the parsing (exactly
the owner's invariant: destination fixed, parser swappable).

CONTEXT tier = LIGHT custody (ADR-0051: custody tier is the only evidence/
context branch): this path deliberately does NOT run the heavy H1/H3 custody
reconciliation that `server/tools/parsers/messaging/sbv_sms.py` does for
evidence-tier SMS — it imports and reads records only. SBV still computes its
own hashes; capturing them for context is a later, optional enrichment.

Depends on `server.tools._sbv_client` (analysis -> tools is the allowed
dependency direction, server/AGENTS.md). SBV service URL comes from
`SBV_BASE_URL` (in-cluster `http://tool-runtime:8085`; off-box use the
tailnet `http://100.72.169.40:8085`); auth is the client's service account
(`SBV_SERVICE_USER`/`SBV_SERVICE_PASS`), handled transparently.
"""
# Byline: Claude Code · Opus 4.8 · 2026-08-12
# Byline: Codex · GPT-5 · 2026-08-13 (reject malformed SBV import responses)

from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from server.contracts.records import DisclosureTier, NormalizedRecord, RecordType
from server.tools.parsers.messaging._source_parties import enrich_message_parties


def _parse_ts(value: Any) -> datetime | None:
    """Tolerant timestamp parse for SBV record rows: ISO-8601 (incl. trailing
    'Z'), or epoch seconds/milliseconds. Returns None on anything unparseable
    (NormalizedRecord's validator makes the result tz-aware)."""
    if value in (None, ""):
        return None
    if isinstance(value, (int, float)):
        # heuristic: >1e12 => milliseconds
        secs = value / 1000.0 if value > 1_000_000_000_000 else float(value)
        try:
            return datetime.fromtimestamp(secs, tz=timezone.utc)
        except (OverflowError, OSError, ValueError):
            return None
    if isinstance(value, str):
        s = value.strip()
        if not s:
            return None
        try:
            return datetime.fromisoformat(s.replace("Z", "+00:00"))
        except ValueError:
            return None
    return None


def _row_to_record(
    row: dict[str, Any], default_source: str, source_meta: dict[str, Any] | None = None
) -> NormalizedRecord:
    """Map ONE SBV canonical record row -> NormalizedRecord (chat-aware).

    SBV emits chat context/role/conversation in the record's `metadata` map
    (the Go importers put conversation_id / conversation_title / role there —
    SourceRecord has no dedicated role column). We read them with fallbacks so
    this works across the ChatGPT decoder and any future AI-chat Go importer.
    """
    metadata = row.get("metadata")
    if not isinstance(metadata, dict):
        metadata = {}
    participants = row.get("participants")
    if not isinstance(participants, list):
        participants = []
    participants = [str(v) for v in participants if v not in (None, "")]

    # Preserve the legacy display/compatibility role.  This is not reused as
    # the neutral sender field: enrich_message_parties resolves sender under
    # the source-principal rules below.
    role = (
        metadata.get("role")
        or metadata.get("author_role")
        or metadata.get("author")
        or (participants[0] if participants else None)
    )
    conversation_id = metadata.get("conversation_id") or metadata.get("conversation") or row.get("conversation_id")
    source = str(row.get("format") or default_source)

    attrs: dict[str, Any] = {
        "parser": "sbv-go",
        "engine": "go",
        "import_id": row.get("import_id"),
        "source_pos": row.get("source_pos"),
        "record_hash": row.get("record_hash") or "",
        "record_hash_canon": row.get("record_hash_canon") or "",
        "format": source,
        "status": row.get("status") or "accepted",
        **{k: v for k, v in metadata.items() if k not in ("role", "author_role", "author")},
    }
    title = metadata.get("conversation_title") or metadata.get("title")
    if title:
        attrs["conversation_title"] = title

    record = NormalizedRecord(
        record_type=RecordType.call if row.get("kind") == "call" else RecordType.message,
        source=source,
        conversation_id=str(conversation_id) if conversation_id else None,
        role=str(role) if role else None,
        participants=participants,
        sender=str(row.get("sender")) if row.get("sender") else None,
        recipients=row.get("recipients") if isinstance(row.get("recipients"), list) else [],
        content=str(row.get("content") or ""),
        occurred_at=_parse_ts(row.get("occurred_at")),
        disclosure_tier=DisclosureTier.contemporaneous,
        attrs=attrs,
    )
    return enrich_message_parties([record], {"source_meta": source_meta or {}})[0]


def parse_via_sbv(
    path: Path,
    *,
    format: str | None = None,
    source_meta: dict[str, Any] | None = None,
    timeout_s: float = 600.0,
    client: Any | None = None,
) -> tuple[list[NormalizedRecord], str, list[dict[str, Any]]]:
    """Parse `path` with the SBV Go engine and return
    (records, parser_id, attempts) — the SAME contract as
    `context_chat_ingest._parse_via_registry`, so the two engines are
    interchangeable behind the dispatcher.

    `format` is the OVERRIDE the owner asked for (MVP, detection router
    deferred): pass e.g. 'chatgpt-official-json' to force a specific Go
    importer; omit to let SBV's own priority detection pick. `client` is
    injectable for tests; otherwise the module builds a real SBVClient
    (SBV_BASE_URL + service account).
    """
    if not path.is_file():
        raise FileNotFoundError(path)
    if client is None:
        from server.tools._sbv_client import SBVClient  # lazy: http.client + env-driven service creds

        client = SBVClient()

    attempts: list[dict[str, Any]] = []
    summary = client.import_file(str(path), filename=path.name, format=format)
    import_id = summary.get("import_id")
    if import_id is None:
        raise RuntimeError("SBV import response did not include import_id")
    client.wait_for_import(int(import_id), timeout_s=timeout_s)
    rows = client.import_records(int(import_id))

    default_source = f"sbv-go:{format}" if format else "sbv-go"
    records = [
        _row_to_record(row, default_source, source_meta) for row in rows if str(row.get("content") or "").strip()
    ]
    parser_id = f"sbv-go:{format or 'auto-detect'}"
    attempts.append({"tool": parser_id, "ok": True, "import_id": import_id, "record_count": len(records)})
    return records, parser_id, attempts
