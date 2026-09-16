"""Typed, governed handoff writes through the dedicated Docstore function."""
from __future__ import annotations

import re
from typing import Literal

from fastmcp.exceptions import ToolError
from pydantic import BaseModel, ConfigDict, Field, field_validator

from governance import query


Domain = Literal[
    "probata", "proffer", "consignatio", "advocatio", "vestigia",
    "indagatio", "intake", "workbench", "knowledge", "memory", "infra", "docs",
]


class HandoffWrite(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    title: str = Field(min_length=1, max_length=300)
    body: str = Field(min_length=1, max_length=1024 * 1024)
    domains: list[Domain] = Field(min_length=1, max_length=12)
    # Fixed 2026-09-16: fn::handoff_write's 4th arg, added 2026-09-15 to stop the
    # LIMIT-1/"any overlap" bug. Without an explicit list, the function falls back
    # to superseding EVERY active handoff whose domain set exactly equals $domains
    # -- reproduced live 2026-09-16, a call with domains=["docs"] and no supersedes
    # superseded six unrelated real handoffs in one call (reverted). Callers that
    # know what they are replacing MUST pass those record ids here; pass an empty
    # list explicitly to supersede nothing.
    supersedes: list[str] = Field(default_factory=list, max_length=50)

    @field_validator("body")
    @classmethod
    def bounded_utf8(cls, value: str) -> str:
        if len(value.encode("utf-8")) > 1024 * 1024:
            raise ValueError("Body exceeds 1 MiB UTF-8")
        return value

    @field_validator("domains")
    @classmethod
    def unique_domains(cls, value: list[Domain]) -> list[Domain]:
        if len(set(value)) != len(value):
            raise ValueError("Domains must be unique")
        return value

    @field_validator("supersedes")
    @classmethod
    def valid_document_ids(cls, value: list[str]) -> list[str]:
        for item in value:
            if not re.fullmatch(r"document:[A-Za-z0-9_-]{1,128}", item):
                raise ValueError(f"supersedes id must match document:<id>: {item!r}")
        if len(set(value)) != len(value):
            raise ValueError("supersedes ids must be unique")
        return value


WRITE_HANDOFF = """
BEGIN TRANSACTION;
-- $supersedes_raw is ALWAYS a real array from this tool (the Pydantic field
-- defaults to [], never absent/NONE) -- always forward it as a mapped array,
-- even when empty, so "no supersedes given" safely means "supersede nothing"
-- here. NEVER collapse an empty array to NONE: fn::handoff_write treats
-- NONE/omitted as "fall back to superseding every active handoff with the
-- same domain SET", which is the dangerous default this tool exists to avoid
-- (reproduced live 2026-09-16: collapsing [] to NONE here superseded six
-- real unrelated handoffs even though the caller explicitly passed
-- supersedes=[]; fixed and reverified with the same repro before this line
-- shipped).
LET $supersedes_ids = $supersedes_raw.map(|$s: string| <record<document>> $s);
LET $written = fn::handoff_write($title, $body, $domains, $supersedes_ids);
LET $created = (SELECT id, title, body, doc_type, domains, status, source_path
                FROM ONLY $written.id);
LET $previous = IF array::len($written.superseded) = 0 {
    []
} ELSE {
    (SELECT id, status FROM $written.superseded)
};
RETURN { written: $written, created: $created, previous: $previous };
COMMIT TRANSACTION;
"""


def _object(value):
    while isinstance(value, list) and len(value) == 1:
        value = value[0]
    if not isinstance(value, dict):
        raise ToolError("Handoff write returned no verifiable record; inspect state before retrying")
    return value


def _rows(value):
    """Normalize a SurrealDB embedded-subquery result to a list of dicts.

    `(SELECT ... FROM $ids)` used as a value inside a `RETURN {...}` object
    literal comes back as a bare dict when exactly one row matches, and a
    list for zero or many rows (unlike a standalone top-level SELECT
    statement, which is always an array) -- reproduced live 2026-09-16 while
    fixing this file. Never assume either shape.
    """
    if value is None:
        return []
    if isinstance(value, dict):
        return [value]
    if isinstance(value, list):
        return value
    raise ToolError("Handoff supersession response is inconsistent; inspect state")


async def write_handoff(config, item: HandoffWrite, execute=query) -> dict:
    domains = sorted(item.domains)
    result = _object(await execute(config, WRITE_HANDOFF, {
        "title": item.title,
        "body": item.body,
        "domains": domains,
        "supersedes_raw": list(item.supersedes),
    }))
    written = _object(result.get("written"))
    created = _object(result.get("created"))
    record_id = str(written.get("id", ""))
    if not re.fullmatch(r"document:[A-Za-z0-9_-]{1,128}", record_id):
        raise ToolError("Handoff write returned an invalid record ID; inspect state before retrying")
    if (
        str(created.get("id")) != record_id
        or created.get("title") != item.title
        or created.get("body") != item.body
        or created.get("doc_type") != "handoff"
        or created.get("domains") != domains
        or created.get("status") != "active"
        or not str(created.get("source_path", "")).startswith("handoff://")
    ):
        raise ToolError("Handoff write could not be read back exactly; inspect state before retrying")

    # fn::handoff_write (fixed 2026-09-15/16) always returns `superseded` as an
    # array (possibly empty), never a bare id or NONE -- this wrapper used to
    # assume a single scalar and would hard-error (SurrealQL `ONLY` on >1 row)
    # the moment more than one document was superseded in one call.
    superseded = written.get("superseded")
    if not isinstance(superseded, list):
        raise ToolError("Handoff supersession response is inconsistent; inspect state")
    previous = _rows(result.get("previous"))
    previous_by_id = {str(p.get("id")): p for p in previous if isinstance(p, dict)}
    if len(previous_by_id) != len(superseded):
        raise ToolError("Superseded handoff(s) could not be read back; inspect state")
    for sid in superseded:
        row = previous_by_id.get(str(sid))
        if row is None or row.get("status") != "superseded":
            raise ToolError("Previous handoff was not superseded atomically; inspect state")
    if item.supersedes and sorted(str(s) for s in superseded) != sorted(item.supersedes):
        raise ToolError("Handoff did not supersede exactly the requested ids; inspect state")

    return {
        "id": record_id,
        "superseded": [str(s) for s in superseded],
        "match": written.get("match"),
        "doc_type": "handoff",
        "domains": domains,
        "status": "active",
        "verified_readback": True,
        "indexing_triggered": False,
    }


def register(mcp, config, read_annotations):
    annotations = {
        **read_annotations,
        "title": "Write governed session handoff",
        "readOnlyHint": False,
        "destructiveHint": False,
        "idempotentHint": False,
        "openWorldHint": True,
    }

    @mcp.tool(annotations=annotations)
    async def docstore_handoff_write(handoff: HandoffWrite) -> dict:
        """Write and verify one governed Docstore handoff. Pass `supersedes` (document:<id> list)
        for the specific prior handoff(s) this replaces; omitting it falls back to superseding
        EVERY active handoff whose domain set exactly equals `domains`, which can be more than
        one row for a common domain -- prefer an explicit list."""
        return await write_handoff(config, handoff)
