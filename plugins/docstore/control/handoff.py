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


WRITE_HANDOFF = """
BEGIN TRANSACTION;
LET $written = fn::handoff_write($title, $body, $domains);
LET $created = (SELECT id, title, body, doc_type, domains, status, source_path
                FROM ONLY $written.id);
LET $previous = IF $written.superseded != NONE {
    (SELECT id, status FROM ONLY $written.superseded)
} ELSE {
    NONE
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


async def write_handoff(config, item: HandoffWrite, execute=query) -> dict:
    domains = sorted(item.domains)
    result = _object(await execute(config, WRITE_HANDOFF, {
        "title": item.title,
        "body": item.body,
        "domains": domains,
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

    superseded = written.get("superseded")
    previous = result.get("previous")
    if superseded is None:
        if previous is not None:
            raise ToolError("Handoff supersession response is inconsistent; inspect state")
    else:
        if not isinstance(previous, dict) or str(previous.get("id")) != str(superseded):
            raise ToolError("Superseded handoff could not be read back; inspect state")
        if previous.get("status") != "superseded":
            raise ToolError("Previous handoff was not superseded atomically; inspect state")

    return {
        "id": record_id,
        "superseded": str(superseded) if superseded is not None else None,
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
        """Write and verify one governed Docstore handoff; supersedes overlapping active domains."""
        return await write_handoff(config, handoff)
