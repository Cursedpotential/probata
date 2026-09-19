"""Categorized top-level Docstore tool surface.

Byline: Claude Code · Opus 5 · 2026-09-19 — owner orders: one endpoint; tools grouped into
permission CATEGORIES by the first word of the tool name, so the desktop app's allow / ask / block
rules apply per category (`mcp__<server>__ctl-read-*`, `...-write-*`, `...-run-*`, `...-admin-*`);
recall, search and memory are project-wide by default; raw database tools stay reachable but only
through `admin_call`, which carries a disclaimer and ALWAYS requires a second, confirmed call.

Every tool here calls either a governed control tool (in-process) or a governed SurrealDB function
(`fn::*`); nothing below writes rows directly except `admin_call`.
"""
from __future__ import annotations

import hashlib
import hmac
import json
import os
import re
import secrets
import time
from contextlib import asynccontextmanager
from typing import Annotated, Any, Literal

import httpx
from fastmcp import Client, FastMCP
from fastmcp.exceptions import ToolError
from pydantic import Field

MODULES = Literal["probata", "proffer", "consignatio", "advocatio", "vestigia",
                  "indagatio", "intake", "workbench", "knowledge", "memory", "infra", "docs"]

READ = {"readOnlyHint": True, "destructiveHint": False, "idempotentHint": True, "openWorldHint": True}
WRITE = {"readOnlyHint": False, "destructiveHint": False, "idempotentHint": False, "openWorldHint": True}
RUN = {"readOnlyHint": False, "destructiveHint": False, "idempotentHint": False, "openWorldHint": True}
ADMIN = {"readOnlyHint": False, "destructiveHint": True, "idempotentHint": False, "openWorldHint": True}

# Existing governed control tools, by permission category. discover lists these; the matching
# <category>_call tool runs them, so a tool can never be run under a looser category.
CATALOG: dict[str, dict[str, list[str]]] = {
    "read": {
        "search": ["coco_docstore_search", "docstore_search", "docstore_compact", "docstore_related_updates"],
        "documents": ["docstore_get", "docstore_revision_state", "docstore_flags"],
        "graph": ["docstore_graph", "docstore_graph_schema", "docstore_graph_query_preview", "docstore_graph_query"],
        "status": ["docstore_health", "docstore_stats", "docstore_capabilities", "docstore_pipeline_identity",
                   "docstore_run_status", "docstore_run_current", "docstore_run_get", "docstore_run_list",
                   "docstore_cdc_runs"],
        "verification": ["docstore_verify_index", "docstore_attribution_verify", "docstore_index_plan",
                         "docstore_selected_update_plan"],
        "scope": ["docstore_project_sources", "docstore_project_source"],
        "tools": ["docstore_surrealist", "docstore_reconcile_query", "docstore_reconcile_validate"],
    },
    "write": {
        "notes": ["docstore_set_flags", "docstore_handoff_write"],
        "revisions": ["docstore_capture_revision", "docstore_approve_revision"],
        "reconcile": ["docstore_reconcile_packet", "docstore_reconcile_repair"],
    },
    "run": {
        "index": ["docstore_index_full", "docstore_index_execute", "docstore_index_selected",
                  "docstore_run_cancel", "docstore_cancel_run"],
    },
}
# Governed SurrealDB functions (fn::*), by permission category and database. Called as
# <category>_call(tool="docs.open_work", args={"args": [...positional...]}); a record-typed argument
# is passed as {"$ql": "memory:<id>"}. Read-only schema/row reads use tool="docs.info|list|select".
FUNCTIONS: dict[str, dict[str, list[str]]] = {
    "read": {"docs": ["docs_search", "docs_get", "docs_tagged", "open_work", "provenance", "current_decisions",
                      "stale_candidates", "recall", "search_text", "search_vec"],
             "mem": ["recall", "memory_stats"]},
    "write": {"docs": ["docs_register", "docs_new_version", "docs_supersede", "docs_retract", "docs_set_tags",
                       "decision_amend", "todo_open", "todo_close", "handoff_write"],
              "mem": ["remember", "supersede_memory", "forget", "reflect"]},
}
READ_DB_OPS = ["info", "list", "select"]
RAW_OPS = ["query", "select", "create", "insert", "update", "upsert", "delete", "relate", "run",
           "info", "list", "use", "gql", "graphql"]

DISCLAIMER = (
    "ADMIN / RAW DATABASE ACCESS. These operations bypass every Docstore rule: no version history, "
    "no supersede chain, no duplicate check, no audit row, no retract-instead-of-delete. Prefer the "
    "read/write/run tools, which enforce those rules. admin_call ALWAYS double-checks: the first call "
    "only returns a preview and a confirm code; nothing runs until the same call is repeated with that "
    "code within 10 minutes. Re-read the preview before confirming.")


def _native_transport(url: str, auth: str, ns: str, db: str):
    from native_transport import DocstoreTransport

    def factory(**kwargs):
        kwargs.update(timeout=30, follow_redirects=False, trust_env=False)
        return httpx.AsyncClient(**kwargs)
    return DocstoreTransport(url, headers={"Authorization": "Basic " + auth, "surreal-ns": ns, "surreal-db": db},
                             httpx_client_factory=factory)


def register(mcp: FastMCP, config, helpers: dict[str, Any]) -> None:
    get = helpers["get"]
    gate_key = secrets.token_bytes(32)
    mem_url = os.environ.get("MEMORY_MCP_URL", "http://100.91.190.107:8471/mcp")
    mem_auth = os.environ.get("MEMORY_BASIC_AUTH", "")

    @asynccontextmanager
    async def database(target: Literal["docs", "mem"]):
        if target == "docs":
            if not config.native_auth:
                raise ToolError("Docs database login is not configured on the control server")
            transport = _native_transport(config.native_url, config.native_auth, "probata", "docs")
        else:
            if not mem_auth:
                raise ToolError("Memory database login is not configured on the control server")
            transport = _native_transport(mem_url, mem_auth, "probata_memory", "memory")
        async with Client(transport, timeout=40) as client:
            yield client

    async def db_call(target: Literal["docs", "mem"], op: str, args: dict) -> Any:
        async with database(target) as client:
            result = await client.call_tool(op, args, raise_on_error=False)
        texts = [c.text for c in result.content if c.type == "text"]
        payload: Any = result.structured_content if result.structured_content is not None else texts
        if result.is_error:
            raise ToolError("Database call failed: " + " ".join(texts)[:600])
        # Unwrap the native {status, time_ms, truncated, value} envelope so callers get the value.
        if isinstance(payload, dict) and payload.get("status") == "ok" and "value" in payload:
            return payload["value"]
        return payload

    async def fn(target: Literal["docs", "mem"], name: str, arguments: list) -> Any:
        return await db_call(target, "run", {"function": "fn::" + name, "args": arguments})

    def record(value: str, table: str) -> dict:
        # Typed record id for functions declared record<table>; validated so nothing else is embedded.
        if not isinstance(value, str) or not re.fullmatch(table + r":[A-Za-z0-9_]{1,128}", value):
            raise ToolError(f"expected a {table}:<id> record id")
        return {"$ql": value}

    def when(value: str) -> dict:
        if not isinstance(value, str) or not re.fullmatch(r"\d{4}-\d{2}-\d{2}(T[0-9:.]+(Z|[+-]\d{2}:\d{2})?)?", value):
            raise ToolError("expected an ISO date/time, e.g. 2026-09-19 or 2026-09-19T05:00:00Z")
        return {"$ql": "d'" + value + "'"}

    async def control(name: str, arguments: dict) -> Any:
        async with Client(mcp, timeout=300) as client:
            result = await client.call_tool(name, arguments, raise_on_error=False)
        if result.is_error:
            raise ToolError(" ".join(c.text for c in result.content if c.type == "text")[:800])
        return result.structured_content if result.structured_content is not None else result.data

    def category_of(tool: str) -> str | None:
        for category, areas in CATALOG.items():
            if any(tool in names for names in areas.values()):
                return category
        target, _, name = tool.partition(".")
        for category, dbs in FUNCTIONS.items():
            if name in dbs.get(target, []):
                return category
        if target in ("docs", "mem") and name in READ_DB_OPS:
            return "read"
        return None

    async def dispatch(tool: str, args: dict) -> Any:
        target, dot, name = tool.partition(".")
        if dot and target in ("docs", "mem"):
            if name in READ_DB_OPS:
                return await db_call(target, name, args)
            positional = args.get("args", [])
            if not isinstance(positional, list):
                raise ToolError('function arguments go in args={"args": [...]}')
            return await fn(target, name, positional)
        return await control(tool, args)

    # ------------------------------------------------------------------ read
    @mcp.tool(annotations={**READ, "title": "Search all Propria documentation"})
    async def read_search(query: Annotated[str, Field(min_length=2, max_length=2048)],
                          module: MODULES | None = None,
                          kind: Literal["doc", "adr", "decision", "handoff", "todo", "review",
                                        "blueprint", "reference", "infrastructure"] = "doc",
                          status: Literal["all", "active", "unverified", "proposed", "superseded", "retracted"] = "all",
                          limit: Annotated[int, Field(ge=1, le=20)] = 8, rerank: bool = False) -> dict:
        """Project-wide hybrid search (BM25 + vectors) over every Propria doc root. Leave `module`
        empty unless the question concerns exactly one module."""
        params = {"q": query, "kind": kind, "status": status, "k": limit, "rerank": str(rerank).lower()}
        if module:
            params["domain"] = module
        result = await get("/recall", params)
        return {"scope": module or "project (all of Propria)", **result}

    @mcp.tool(annotations={**READ, "title": "Read one document with history"})
    async def read_get(record_id: Annotated[str, Field(pattern=r"^(document:)?[A-Za-z0-9_-]{1,128}$")],
                       with_history: bool = True) -> dict:
        """One document: body, status, and (by default) its supersede chain and provenance."""
        rid = record_id if record_id.startswith("document:") else "document:" + record_id
        doc = await control("docstore_get", {"record_id": rid})
        if not with_history:
            return {"document": doc}
        history = await fn("docs", "docs_get", [rid])
        return {"document": doc, "history": history}

    @mcp.tool(annotations={**READ, "title": "Docstore health and last run"})
    async def read_health() -> dict:
        """Service health, the latest index run and store counts, in one call."""
        return {"health": await control("docstore_health", {}), "stats": await control("docstore_stats", {})}

    @mcp.tool(annotations={**READ, "title": "Discover every Docstore tool"})
    async def read_discover(area: str | None = None) -> dict:
        """List every tool reachable through read_call / write_call / run_call / admin_call, by
        category and area, with their inputs. Pass `area` (e.g. "graph", "index", "raw") to narrow."""
        async with Client(mcp, timeout=60) as client:
            schemas = {t.name: t for t in await client.list_tools()}
        out: dict[str, Any] = {"how": "Run a listed tool with <category>_call(tool=..., args={...}). "
                                      "The category of the call tool must match the tool's category."}
        for category, areas in CATALOG.items():
            for name, tools in areas.items():
                if area and area != name:
                    continue
                out.setdefault(category, {})[name] = [
                    {"tool": t, "description": (schemas[t].description or "").split("\n")[0],
                     "inputs": schemas[t].inputSchema.get("properties", {})}
                    for t in tools if t in schemas]
        if not area or area == "functions":
            for category, dbs in FUNCTIONS.items():
                out.setdefault(category, {})["functions"] = [f"{db}.{name}" for db, names in dbs.items() for name in names]
            out.setdefault("read", {})["database_reads"] = [f"{db}.{op}" for db in ("docs", "mem") for op in READ_DB_OPS]
            out["functions_usage"] = ('<category>_call(tool="docs.open_work", args={"args": ["propria"]}); '
                                      'record ids as {"$ql": "memory:<id>"}; schema reads: '
                                      'read_call(tool="docs.info", args={"target": "db"})')
        if not area or area == "raw":
            out["admin"] = {"raw": {"disclaimer": DISCLAIMER, "targets": ["docs", "mem"], "operations": RAW_OPS,
                                    "usage": "admin_call(target='docs'|'mem', operation=<op>, args={...})"}}
        return out

    @mcp.tool(annotations={**READ, "title": "Run a read-category tool"})
    async def read_call(tool: str, args: dict | None = None) -> Any:
        """Run any READ tool listed by read_discover."""
        if category_of(tool) != "read":
            raise ToolError(f"{tool} is not a read tool; see read_discover for its category")
        return await dispatch(tool, args or {})

    @mcp.tool(annotations={**READ, "title": "Recall shared memory"})
    async def read_memory(action: Literal["recall", "stats"] = "recall", query: str = "",
                          scope: Annotated[str, Field(pattern=r"^propria(/[a-z0-9_-]+)*$")] = "propria",
                          limit: Annotated[int, Field(ge=1, le=50)] = 10) -> Any:
        """Recall or count shared agent memory. Scope `propria` = the whole project (default);
        narrow to e.g. `propria/intake` only when the question concerns that one module."""
        if action == "stats":
            return await fn("mem", "memory_stats", [scope])
        if len(query.strip()) < 2:
            raise ToolError("recall needs a query")
        return await fn("mem", "recall", [query, {"$ql": "NONE"}, scope, limit])

    # ----------------------------------------------------------------- write
    @mcp.tool(annotations={**WRITE, "title": "Write a note, decision, handoff or todo"})
    async def write_note(type: Literal["note", "decision", "handoff", "todo"],
                         fields: dict) -> Any:
        """Governed writes. Cross-module items use the project-wide domain `docs`.
        note     -> docstore_set_flags(flag=fields)   (subject,title,summary,priority,authority,domains,source_ref,rationale,actor,expected_revision)
        decision -> fn::decision_amend(subject, banner, closes[])  (append-only decision log)
        handoff  -> docstore_handoff_write(handoff=fields)  (title,body,domains,supersedes[])
        todo     -> fn::todo_open(item, priority, domains[], source)"""
        if type == "note":
            return await control("docstore_set_flags", {"flag": fields})
        if type == "handoff":
            return await control("docstore_handoff_write", {"handoff": fields})
        if type == "decision":
            return await fn("docs", "decision_amend", [fields["subject"], fields["banner"], fields.get("closes")])
        return await fn("docs", "todo_open", [fields["item"], int(fields.get("priority", 2)),
                                              fields.get("domains") or ["docs"], fields.get("source")])

    @mcp.tool(annotations={**WRITE, "title": "Update a stored record under the rules"})
    async def write_update(action: Literal["new_version", "supersede", "retract", "tags", "close_todo"],
                           fields: dict) -> Any:
        """Governed updates; nothing is overwritten or hard-deleted.
        new_version -> fn::docs_new_version(old, body, title)   (old kept, marked superseded)
        supersede   -> fn::docs_supersede(new, old)
        retract     -> fn::docs_retract(id, reason)              (history kept)
        tags        -> fn::docs_set_tags(id, tags[], actor)
        close_todo  -> fn::todo_close(id, evidence)
        Document CONTENT lives in the repo files: edit the file and run run_index for lasting changes."""
        f = fields
        calls = {"new_version": ("docs_new_version", lambda: [f["old"], f["body"], f.get("title")]),
                 "supersede": ("docs_supersede", lambda: [f["new"], f["old"]]),
                 "retract": ("docs_retract", lambda: [f["id"], f["reason"]]),
                 "tags": ("docs_set_tags", lambda: [f["id"], f["tags"], f.get("actor", "agent")]),
                 "close_todo": ("todo_close", lambda: [f["id"], f["evidence"]])}
        name, args = calls[action]
        try:
            return await fn("docs", name, args())
        except KeyError as missing:
            raise ToolError(f"{action} needs field {missing}") from None

    @mcp.tool(annotations={**WRITE, "title": "Write shared memory under the rules"})
    async def write_memory(action: Literal["remember", "correct", "forget", "reflect"], fields: dict) -> Any:
        """Governed memory writes (never deletes).
        remember -> fn::remember({kind, claim, detail, evidence, scope='propria', agent, confidence})
                    refuses silent duplicates; pass force:true or supersede:<memory:id> deliberately
        correct  -> fn::supersede_memory(old, new_payload)   (old kept, marked superseded)
        forget   -> fn::forget(id, reason)                     (marked retracted, never deleted)
        reflect  -> fn::reflect(scope, since)"""
        if action == "remember":
            payload = {"scope": "propria", **fields}
            return await fn("mem", "remember", [payload])
        try:
            if action == "correct":
                return await fn("mem", "supersede_memory", [record(fields["old"], "memory"), {"scope": "propria", **fields["new_payload"]}])
            if action == "forget":
                return await fn("mem", "forget", [record(fields["id"], "memory"), fields["reason"]])
            return await fn("mem", "reflect", [fields.get("scope", "propria"), when(fields["since"])])
        except KeyError as missing:
            raise ToolError(f"{action} needs field {missing}") from None

    @mcp.tool(annotations={**WRITE, "title": "Run a write-category tool"})
    async def write_call(tool: str, args: dict | None = None) -> Any:
        """Run any WRITE tool listed by read_discover."""
        if category_of(tool) != "write":
            raise ToolError(f"{tool} is not a write tool; see read_discover for its category")
        return await dispatch(tool, args or {})

    # ------------------------------------------------------------------- run
    @mcp.tool(annotations={**RUN, "title": "Index management"})
    async def run_index(action: Literal["start", "status", "cancel", "verify"] = "status",
                        run_id: Annotated[str | None, Field(pattern=r"^[a-f0-9]{32}$")] = None,
                        paths: list[str] | None = None) -> Any:
        """start  -> one full-source incremental reconciliation (only changed docs embed)
        status -> current run, or the run `run_id`
        cancel -> cancel run `run_id`
        verify -> source-to-store comparison (all docs), or verify_index for `paths`"""
        if action == "start":
            return await control("docstore_index_full", {})
        if action == "status":
            return await control("docstore_run_get" if run_id else "docstore_run_current",
                                 {"run_id": run_id} if run_id else {})
        if action == "cancel":
            if not run_id:
                raise ToolError("cancel needs run_id")
            return await control("docstore_run_cancel", {"run_id": run_id})
        if paths:
            return await control("docstore_verify_index", {"paths": paths})
        return await control("docstore_attribution_verify", {})

    @mcp.tool(annotations={**RUN, "title": "Run a run-category tool"})
    async def run_call(tool: str, args: dict | None = None) -> Any:
        """Run any RUN tool listed by read_discover."""
        if category_of(tool) != "run":
            raise ToolError(f"{tool} is not a run tool; see read_discover for its category")
        return await dispatch(tool, args or {})

    # ----------------------------------------------------------------- admin
    def confirm_code(target: str, operation: str, args: dict, window: int) -> str:
        message = json.dumps([target, operation, args, window], sort_keys=True).encode()
        return hmac.new(gate_key, message, hashlib.sha256).hexdigest()[:12]

    @mcp.tool(annotations={**ADMIN, "title": "Raw database access (double-checked)"})
    async def admin_call(target: Literal["docs", "mem"], operation: str, args: dict | None = None,
                         confirm: str = "") -> Any:
        """RAW database operation on the docs or memory store. Bypasses every Docstore rule.
        Always two calls: the first returns a preview and a confirm code; repeat the identical
        call with `confirm=<code>` within 10 minutes to execute."""
        if operation not in RAW_OPS:
            raise ToolError(f"Unknown operation; one of {RAW_OPS}")
        args = args or {}
        window = int(time.time() // 600)
        valid = {confirm_code(target, operation, args, window), confirm_code(target, operation, args, window - 1)}
        if confirm not in valid:
            return {"gate": "confirm_required", "disclaimer": DISCLAIMER,
                    "preview": {"target": target, "operation": operation, "args": args},
                    "confirm_code": confirm_code(target, operation, args, window),
                    "next": "Re-read the preview. To execute, repeat this exact call with confirm=<confirm_code>."}
        return {"executed": True, "target": target, "operation": operation,
                "result": await db_call(target, operation, args)}
