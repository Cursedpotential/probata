"""agents/tools/sbv_tools.py — agno ``@tool`` wrappers over ``SBVClient``
(``server/tools/_sbv_client.py``), the SBV REST API (``:8085``). Mirrors the
old facade's ``/sbv/*`` proxy surface (``deploy/docker/tool-runtime/tools/facade.py``)
plus ``sbv_hashes`` (forensic H1/H3 custody chain — used internally by the
SBV client but never exposed as its own route by the facade; the custody
chain is the whole point of the SBV fork, so it belongs in the toolkit).

Error convention (OQ-8): unlike the facade (an HTTP layer, which mapped
``SBVError`` -> ``HTTPException``), these tools do NOT catch ``SBVError`` and
re-shape it into an ``{"error": ...}`` dict. They let it propagate. Two
things make "raise" the right call here, not just the simplest one:

1. It matches the dominant convention actually used by the layer these tools
   sit next to (``server/tools/*.py``, ``server/tools/gateway/``) —
   atomic tools and the G4 meta-ops raise (``KeyError``, ``ValueError``,
   ``FileNotFoundError``, ...) and let the caller/framework handle it, they
   do not return ad-hoc error dicts.
2. agno's own ``Function.execute()`` (``agno/tools/function.py``) already
   catches any exception raised inside a ``@tool`` entrypoint and reports a
   structured ``FunctionExecutionResult(status="failure", error=str(e))``
   back to the calling agent. Catching ``SBVError`` here ourselves and
   returning ``{"error": ...}`` inside a *successful* tool call would throw
   away that ``status="failure"`` signal for no benefit — the codebase's one
   other ``@tool`` (``apply_db_modification``, ``factory.py``) uses a
   string-prefixed ``"ERROR: ..."`` return instead of raising, but that tool
   is a different shape entirely (a HITL-approval-gated write that needs to
   report a tri-state OK/REJECTED/ERROR *outcome* as natural language within
   a successful call) — not a precedent for read-only, dict/list-returning
   tools like these.

``SBVError.args[0]`` already includes the HTTP status/method/path in its
message text (see ``_sbv_client.py:137-142``), so nothing useful is lost by
not also surfacing ``.status`` as a separate field.
"""

from __future__ import annotations

from typing import Any

from agno.tools import tool

from server.tools._sbv_client import SBVClient

_client: SBVClient | None = None


def _sbv() -> SBVClient:
    global _client
    if _client is None:
        _client = SBVClient()
    return _client


@tool
def sbv_health() -> dict[str, Any]:
    """SBV service health (public endpoint, no auth)."""
    return {"healthy": _sbv().health()}


@tool
def sbv_version() -> Any:
    """SBV build/version info (public endpoint, no auth)."""
    return _sbv().version()


@tool
def sbv_upload(path: str, wait: bool = True) -> Any:
    """Upload an SMS backup XML for parsing (path must be visible to this
    process — use the shared /r2 mount). Waits for processing to complete by
    default."""
    client = _sbv()
    result = client.upload(path)
    if wait and isinstance(result, dict) and result.get("processing"):
        client.wait_for_processing()
        result = {**result, "processing": False, "waited": True}
    return result


@tool
def sbv_progress() -> Any:
    """Current SBV upload/processing job status."""
    return _sbv().progress()


@tool
def sbv_messages(
    address: str | None = None,
    limit: int | None = None,
    offset: int | None = None,
    start_date: str | None = None,
    end_date: str | None = None,
) -> Any:
    """SMS/MMS messages for one conversation. SBV requires `address`
    (returns 400 without it); there is no "all messages" endpoint — use
    sbv_export to gather everything."""
    return _sbv().messages(address=address, limit=limit, offset=offset, start_date=start_date, end_date=end_date)


@tool
def sbv_conversations() -> Any:
    """All conversations (thread list)."""
    return _sbv().conversations()


@tool
def sbv_calls(limit: int | None = None, offset: int | None = None) -> Any:
    """Call log."""
    return _sbv().calls(limit=limit, offset=offset)


@tool
def sbv_analytics() -> Any:
    """SBV's aggregate analytics for the current import."""
    return _sbv().analytics()


@tool
def sbv_search(query: str, limit: int | None = None) -> Any:
    """Full-text search across messages."""
    return _sbv().search(query, limit=limit)


@tool
def sbv_hashes(import_id: str = "latest") -> dict[str, Any]:
    """Forensic custody hashes (H1 file hash, H3 chain hash) for an SBV
    import batch. Ported from the SBV forensic fork's custody-chain feature;
    never exposed by the old facade proxy even though it was used
    internally — the custody chain is the whole point of the SBV fork."""
    return _sbv().hashes(import_id)


@tool
def sbv_export(format: str = "json", address: str | None = None, include_calls: bool = True) -> Any:
    """Export-as-a-function. SBV's deployed build has no server-side
    /api/export (export is client-side in the GUI); this synthesizes the
    export from messages+calls, porting deploy/docker/tool-runtime/tools/facade.py
    so that logic isn't lost when the facade is removed."""
    client = _sbv()
    messages = client.all_messages(address=address)
    calls = client.all_calls() if include_calls else []
    if format == "csv":
        import csv
        import io

        buf = io.StringIO()
        if isinstance(messages, list) and messages:
            cols = sorted({k for m in messages for k in m.keys()})
            w = csv.DictWriter(buf, fieldnames=cols, extrasaction="ignore")
            w.writeheader()
            w.writerows(messages)
        return {
            "format": "csv",
            "csv": buf.getvalue(),
            "message_count": len(messages) if isinstance(messages, list) else 0,
            "call_count": len(calls) if isinstance(calls, list) else 0,
        }
    return {"format": "json", "messages": messages, "calls": calls}


SBV_TOOLS: list[Any] = [
    sbv_health,
    sbv_version,
    sbv_upload,
    sbv_progress,
    sbv_messages,
    sbv_conversations,
    sbv_calls,
    sbv_analytics,
    sbv_search,
    sbv_hashes,
    sbv_export,
]
