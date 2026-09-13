"""Human note/decision flags through the dedicated native Docstore MCP connection.

No CocoIndex import or automatic schema setup. Bound values; overlay survives CDC.
"""
from __future__ import annotations

import hashlib
import json
import re
from contextlib import asynccontextmanager
from typing import Annotated, Literal
from urllib.parse import urlsplit

import httpx
from fastmcp import Client
from native_transport import DocstoreTransport
from fastmcp.exceptions import ToolError
from pydantic import BaseModel, ConfigDict, Field


class FlagInput(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    subject: str = Field(pattern=r"^(document|adr|todo|note):[A-Za-z0-9_-]{1,128}$")
    title: str = Field(min_length=1, max_length=300)
    summary: str = Field(min_length=1, max_length=4000)
    priority: Literal["critical", "high", "normal"]
    authority: Literal["owner_decision", "verified_finding", "proposal"]
    status: Literal["active", "superseded", "retracted"] = "active"
    domains: list[Literal["probata", "proffer", "consignatio", "advocatio", "vestigia", "indagatio", "intake", "workbench", "knowledge", "memory", "infra", "docs"]] = Field(min_length=1, max_length=12)
    source_ref: str = Field(min_length=1, max_length=1000)
    rationale: str = Field(min_length=1, max_length=2000)
    actor: str = Field(min_length=1, max_length=100)
    expected_revision: int = Field(ge=0)


@asynccontextmanager
async def native_client(config):
    endpoint = config.native_url
    u = urlsplit(endpoint)
    if u.scheme != "https" or not u.hostname or u.username or u.password or u.query or u.fragment:
        raise ToolError("Dedicated native Docstore endpoint must be credential-free HTTPS")
    if not config.native_auth:
        raise ToolError("DOCSTORE_BASIC_AUTH is required for native documentation operations")
    def factory(**kwargs):
        kwargs.update(timeout=20, follow_redirects=False, trust_env=False)
        return httpx.AsyncClient(**kwargs)
    transport = DocstoreTransport(endpoint,
        headers={"Authorization": "Basic " + config.native_auth, "surreal-ns": "probata", "surreal-db": "docs"},
        httpx_client_factory=factory)
    async with Client(transport, timeout=25) as client:
        yield client


async def query(config, sql: str, parameters: dict | None = None, *, client=None):
    try:
        if client is None:
            async with native_client(config) as owned_client:
                return await query(config, sql, parameters, client=owned_client)
        else:
            result = await client.call_tool("query", {"query": sql, "parameters": parameters or {}}, raise_on_error=False)
        texts = [c.text for c in result.content if c.type == "text"]
        if result.is_error:
            if any("revision_conflict" in t for t in texts):
                raise ToolError("Revision conflict: read the current record and review before retrying")
            raise ToolError("Native Docstore query failed; schema/permissions may need attention")
        raw = "\n".join(texts)
        if len(raw) > 2 * 1024 * 1024:
            raise ToolError("Native Docstore response exceeds limit")
        # The deployed native MCP emits human-readable statement headers around JSON.
        # Parse each statement, including failures, rather than treating transport success as query success.
        headers = list(re.finditer(r"(?m)^Statement (\d+) \(([^)]+)\):[ \t]*(?:\r?\n)?", raw))
        if headers:
            if headers[0].start() != 0:
                raise ToolError("Unexpected native statement prefix")
            values = []
            for index, header in enumerate(headers):
                if int(header.group(1)) != index:
                    raise ToolError("Unexpected native statement sequence")
                body = raw[header.end():headers[index + 1].start() if index + 1 < len(headers) else len(raw)].strip()
                if header.group(2).lower() != "ok":
                    if "revision_conflict" in body:
                        raise ToolError("Revision conflict: read the current record before retrying")
                    raise ToolError("Native Docstore statement failed")
                values.append(json.loads(body))
            value = values[0] if len(values) == 1 else [v for v in values if v is not None]
        else:
            value = json.loads(raw)
        # Native query returns statement envelopes; an HTTP/MCP success can contain ERR.
        if isinstance(value, list) and value and all(isinstance(v, dict) and "status" in v and "result" in v for v in value):
            if any(v["status"] != "OK" for v in value):
                if any("revision_conflict" in str(v.get("result")) for v in value):
                    raise ToolError("Revision conflict: read the current record before retrying")
                raise ToolError("Native Docstore statement failed")
            value = [v["result"] for v in value]
        while isinstance(value, list) and len(value) == 1 and isinstance(value[0], list):
            value = value[0]
        return value
    except ToolError:
        raise
    except Exception:
        raise ToolError("Native Docstore unavailable or invalid response") from None


def flag_parameters(flag: FlagInput) -> dict:
    payload = flag.model_dump(exclude={"expected_revision"})
    payload["domains"] = sorted(set(payload["domains"]))
    digest = hashlib.sha256(json.dumps(payload, sort_keys=True).encode()).hexdigest()
    key = hashlib.sha256(flag.subject.encode()).hexdigest()
    payload.update(revision=flag.expected_revision + 1, change_hash=digest)
    return {"rid": "docstore_flag:" + key, "expected": flag.expected_revision,
            "payload": payload, "hash": digest, "audit_id": f"docstore_flag_audit:{key}_{flag.expected_revision + 1}",
            "snapshot": json.dumps(payload, sort_keys=True)}


SET_FLAGS = """
BEGIN TRANSACTION;
LET $old = (SELECT * FROM ONLY type::record($rid));
LET $saved = IF $old != NONE AND $old.change_hash = $hash {
    $old
} ELSE {
    IF ($old.revision ?? 0) != $expected { THROW 'revision_conflict'; };
    LET $row = (UPSERT ONLY type::record($rid) MERGE $payload);
    CREATE type::record($audit_id) SET subject = $payload.subject, revision = $payload.revision, snapshot = $snapshot;
    $row
};
RETURN $saved;
COMMIT TRANSACTION;
"""


async def set_flags(config, flag: FlagInput, execute=query):
    parameters = flag_parameters(flag)
    result = await execute(config, SET_FLAGS, parameters)
    rows = result if isinstance(result, list) else [result]
    row = next((r for r in reversed(rows) if isinstance(r, dict) and r.get("subject") == flag.subject), None)
    expected = parameters["payload"]
    if (row is None or any(row.get(k) != v for k, v in expected.items() if k != "revision")
            or not isinstance(row.get("revision"), int) or row["revision"] < 1):
        raise ToolError("Flag write returned no verifiable record; read back before retrying")
    return {"flag": row, "source_document_modified": False, "indexing_triggered": False}


async def list_flags(config, domain: str, priority: str = "critical", status: str = "active", limit: int = 20, execute=query):
    # A live composite array-index plan returned one copy per domain. NOINDEX keeps
    # this small control table's result cardinality faithful, without client dedup masking it.
    rows = await execute(config, "SELECT * FROM docstore_flag WITH NOINDEX WHERE domains CONTAINS $domain AND priority = $priority AND status = $status ORDER BY updated_at DESC LIMIT $limit;",
                         {"domain": domain, "priority": priority, "status": status, "limit": limit + 1})
    if not isinstance(rows, list):
        raise ToolError("Invalid flag-list response")
    return {"flags": rows[:limit], "truncated": len(rows) > limit,
            "priority": priority, "status": status, "domain": domain,
            "authority_is_separate_from_priority": True}


def register(mcp, config, read_annotations):
    @mcp.tool(annotations={"title": "Set note/decision flags", "readOnlyHint": False,
                          "destructiveHint": False, "idempotentHint": True, "openWorldHint": True})
    async def docstore_set_flags(flag: FlagInput) -> dict:
        """Set priority/authority/status with expected revision and audit history; does not modify source or trigger CDC."""
        return await set_flags(config, flag)

    @mcp.tool(annotations={**read_annotations, "title": "Read critical notes and decisions"})
    async def docstore_flags(domain: Annotated[str, Field(min_length=1, max_length=64)],
                             priority: Literal["critical", "high", "normal"] = "critical",
                             status: Literal["active", "superseded", "retracted"] = "active",
                             limit: Annotated[int, Field(ge=1, le=50)] = 20) -> dict:
        """Read scoped flags independently of semantic similarity, with authority and lifecycle status."""
        return await list_flags(config, domain, priority, status, limit)

    @mcp.resource("docstore://critical/{domain}", mime_type="application/json")
    async def critical_resource(domain: str) -> dict:
        """Active critical scoped notes/decisions, including their separate authority labels."""
        return await list_flags(config, domain)
