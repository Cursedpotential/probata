"""Same Docstore tools from a terminal; no independent pipeline or datastore."""
from __future__ import annotations

import argparse
import asyncio
import base64
import json
import os
import sys
from pathlib import Path
from urllib.parse import urlsplit

from fastmcp import Client
from fastmcp.client.transports import StdioTransport
from native_transport import DocstoreTransport
import httpx

from server import Config, build_server


# Byline: Codex / GPT-6, 2026-09-12 — canonical dedicated-store configuration.
_DEDICATED_KEYS = {"SURREAL_DOCS_URL", "SURREAL_DOCS_USER", "SURREAL_DOCS_PASS"}


def _dedicated_mcp_url(endpoint: str) -> str:
    """Map only the known dedicated Docstore RPC origin to its native MCP door."""
    message = "SURREAL_DOCS_URL must identify the dedicated secure Docstore endpoint"
    try:
        parsed = urlsplit(endpoint)
        if (any(ord(char) <= 32 or ord(char) == 127 for char in endpoint)
                or parsed.scheme not in {"https", "wss"}
                or parsed.hostname != "surreal-docs.tilapia-skilift.ts.net"
                or parsed.port not in {None, 443}
                or parsed.username is not None or parsed.password is not None
                or parsed.query or parsed.fragment
                or parsed.path not in {"", "/", "/rpc", "/mcp"}):
            raise ValueError(message)
    except ValueError:
        # Parser errors can include supplied URL text; never propagate it.
        raise ValueError(message) from None
    return "https://surreal-docs.tilapia-skilift.ts.net/mcp"


def environment() -> dict:
    """Load one explicit env file without changing the process environment.

    Nonblank process values override nonblank file values. DOCSTORE_* names
    override legacy SURREAL_DOCS_* aliases regardless of source. Empty values
    mean unset. Only the dedicated URL/user/password aliases are supported;
    unrelated database credentials are never inherited. Dotenv interpolation
    is disabled so password characters and ${...} remain literal.
    """
    values = {k: v for k, v in os.environ.items() if v.strip()}
    if values.get("DOCSTORE_CONTROL_ENV_FILE"):
        from dotenv import dotenv_values
        settings_path = Path(values["DOCSTORE_CONTROL_ENV_FILE"])
        try:
            if not settings_path.is_file():
                raise ValueError()
            settings = dotenv_values(settings_path, interpolate=False)
        except (OSError, ValueError):
            raise ValueError("DOCSTORE_CONTROL_ENV_FILE must be a readable env file") from None
        values = {**{k: v for k, v in settings.items()
                     if (k.startswith("DOCSTORE_") or k in _DEDICATED_KEYS)
                     and v is not None and v.strip()}, **values}
    if not values.get("DOCSTORE_MCP_URL") and values.get("SURREAL_DOCS_URL"):
        values["DOCSTORE_MCP_URL"] = _dedicated_mcp_url(values["SURREAL_DOCS_URL"])
    if not values.get("DOCSTORE_BASIC_AUTH"):
        user, password = values.get("SURREAL_DOCS_USER"), values.get("SURREAL_DOCS_PASS")
        if user or password:
            if (not user or not password or ":" in user
                    or any(ord(char) < 32 or ord(char) == 127 for char in user + password)):
                raise ValueError("Dedicated Docstore credentials require a valid user and password")
            values["DOCSTORE_BASIC_AUTH"] = base64.b64encode(
                (user + ":" + password).encode("utf-8")).decode("ascii")
    # Callers need only the canonical names; avoid retaining redundant secrets.
    return {k: v for k, v in values.items() if k not in _DEDICATED_KEYS}


def configuration() -> Config:
    root = Path(__file__).resolve().parents[3]
    propria_root = root.parents[1]
    values = environment()
    return Config(values.get("DOCSTORE_API_URL", "https://docstore-api.tilapia-skilift.ts.net"),
                  Path(values.get("DOCSTORE_SOURCE_ROOT", str(root / "docs"))),
                  Path(values.get("DOCSTORE_CONTROL_STATE_DIR", str(root / ".docstore-control"))),
                  values.get("DOCSTORE_INSTANCE_ID", "docstore-probata"),
                  values.get("DOCSTORE_API_TOKEN", ""),
                  values.get("DOCSTORE_MCP_URL", "https://surreal-docs.tilapia-skilift.ts.net/mcp"),
                  values.get("DOCSTORE_BASIC_AUTH", ""),
                  Path(values['DOCSTORE_WORKER_RECEIPTS_DIR']) if values.get('DOCSTORE_WORKER_RECEIPTS_DIR') else None,
                  Path(values.get("DOCSTORE_PROJECT_REGISTRY", str(propria_root / "docs/docstore-source-registry.json"))))


def mcp_runtime(values: dict[str, str]) -> dict:
    """Validate the deliberately small transport surface used by deployment."""
    transport = values.get("DOCSTORE_MCP_TRANSPORT", "stdio").strip().lower()
    if transport == "stdio":
        return {"transport": "stdio", "show_banner": False}
    if transport != "http":
        raise ValueError("DOCSTORE_MCP_TRANSPORT must be stdio or http")
    host = values.get("DOCSTORE_MCP_HOST", "127.0.0.1").strip()
    if host not in {"127.0.0.1", "0.0.0.0"}:
        raise ValueError("DOCSTORE_MCP_HOST must be 127.0.0.1 or 0.0.0.0")
    try:
        port = int(values.get("DOCSTORE_MCP_PORT", "8084"))
    except ValueError as exc:
        raise ValueError("DOCSTORE_MCP_PORT must be an integer") from exc
    if not 1024 <= port <= 65535:
        raise ValueError("DOCSTORE_MCP_PORT must be between 1024 and 65535")
    return {"transport": "http", "host": host, "port": port, "path": "/mcp",
            "stateless_http": True, "show_banner": False}


async def inspect(client: Client) -> dict:
    async with client:
        return {"tools": [t.model_dump(mode="json") for t in await client.list_tools()],
                "resources": [r.model_dump(mode="json") for r in await client.list_resources()],
                "resource_templates": [r.model_dump(mode="json") for r in await client.list_resource_templates()],
                "prompts": [p.model_dump(mode="json") for p in await client.list_prompts()]}


async def run(args, config: Config):
    server = build_server(config)
    if args.command == "resource":
        # Codex | 2026-09-12: exercise the published resource protocol from the CLI.
        async with Client(server, timeout=40) as client:
            contents = await client.read_resource(args.uri)
        return {"uri": args.uri, "contents": [item.model_dump(mode="json") for item in contents]}
    if args.command == "related-updates":
        from updates import related_updates
        return await related_updates(config, args.term, args.limit)
    if args.command == 'selected-update-plan':
        with Path(args.json_file).open('rb') as handle:
            raw=handle.read(65537)
        if len(raw)>65536:
            raise ValueError('Selected update plan input exceeds 64 KiB')
        params={'request':json.loads(raw)}
        async with Client(server,timeout=60) as client:
            return (await client.call_tool('docstore_selected_update_plan',params)).data
    if args.command=='runs':
        async with Client(server,timeout=20) as client:
            return (await client.call_tool('docstore_cdc_runs',{'run_id':args.run_id,'limit':args.limit})).data
    if args.command in {"capture-revision", "approve-revision", "revision-state"}:
        names = {"capture-revision": "docstore_capture_revision",
                 "approve-revision": "docstore_approve_revision", "revision-state": "docstore_revision_state"}
        if args.command == "revision-state":
            params = {"document_key": args.document_key}
        else:
            # JSON escaping may expand a 1 MiB UTF-8 body; the tool validates decoded size.
            with Path(args.json_file).open("rb") as handle:
                raw = handle.read(8 * 1024 * 1024 + 1)
            if len(raw) > 8 * 1024 * 1024:
                raise ValueError("Revision input exceeds limit")
            params = {"revision" if args.command == "capture-revision" else "approval": json.loads(raw)}
        async with Client(server, timeout=40) as client:
            return (await client.call_tool(names[args.command], params)).data
    if args.command == "install-flags-schema":
        from governance import query
        schema = Path(__file__).resolve().parents[3] / "scripts/docstore/schema/095_flags.surql"
        await query(config, schema.read_text(encoding="utf-8"))
        return {"schema_applied": "095_flags.surql", "target": "probata/docs", "indexing_triggered": False}
    if args.command == "set-flags":
        from governance import FlagInput, set_flags
        with Path(args.json_file).open("rb") as handle:
            raw = handle.read(65537)
        if len(raw) > 65536:
            raise ValueError("Flag input exceeds limit")
        return await set_flags(config, FlagInput.model_validate_json(raw))
    if args.command in {"flags", "flags-view"}:
        from governance import list_flags
        result = await list_flags(config, args.domain, args.priority, args.status)
        if args.command == "flags-view":
            from flag_view import render
            from datetime import datetime, timezone
            config.state_root.mkdir(parents=True, exist_ok=True)
            output = config.state_root / ("flags-" + datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%f") + ".html")
            with output.open("x", encoding="utf-8") as handle:
                handle.write(render(result))
            return {"path": str(output), "opened": False, "flags": len(result["flags"])}
        return result
    if args.command == "verify-index":
        from verification import verify
        return await verify(config, args.paths)
    if args.command == "catalog":
        return await inspect(Client(server))
    if args.command in {"native-catalog", "native-probe"}:
        values = environment()
        endpoint = values.get("DOCSTORE_MCP_URL", "https://surreal-docs.tilapia-skilift.ts.net/mcp")
        from urllib.parse import urlsplit
        parsed = urlsplit(endpoint)
        if parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password or parsed.query or parsed.fragment:
            raise ValueError("Native MCP requires an explicit credential-free HTTPS endpoint")
        headers = {"surreal-ns": "probata", "surreal-db": "docs"}
        if values.get("DOCSTORE_BASIC_AUTH"):
            headers["Authorization"] = "Basic " + values["DOCSTORE_BASIC_AUTH"]
        def factory(**kwargs):
            kwargs.update(timeout=15, follow_redirects=False, trust_env=False)
            return httpx.AsyncClient(**kwargs)
        async with Client(DocstoreTransport(endpoint, headers=headers, httpx_client_factory=factory), timeout=20) as client:
            if args.command == "native-probe":
                result = await client.call_tool("select", {"target": "document", "fields": "id", "limit_clause": 1}, raise_on_error=False)
                return {"ok": not result.is_error, "server": "docstore-surreal", "operation": "select document id limit 1",
                        "namespace_header": "probata", "database_header": "docs",
                        "content": [c.text for c in result.content if c.type == "text"]}
            return {"server": "docstore-surreal", "tools": [t.model_dump(mode="json") for t in await client.list_tools()],
                    "tools_executed": False}
    if args.command == "verify-stdio":
        env = {"DOCSTORE_API_URL": config.api_url, "DOCSTORE_SOURCE_ROOT": str(config.source_root),
               "DOCSTORE_CONTROL_STATE_DIR": str(config.state_root), "DOCSTORE_INSTANCE_ID": config.instance,
               "PYTHONDONTWRITEBYTECODE": "1"}
        # Catalog-only subprocess needs no credentials and makes no upstream calls.
        return await inspect(Client(StdioTransport(command=sys.executable,
            args=[str(Path(__file__).with_name("server.py"))], env=env,
            cwd=str(Path(__file__).parent)), timeout=20))
    names = {"health": "docstore_health", "stats": "docstore_stats", "search": "docstore_search",
             "semantic-search": "coco_docstore_search",
             "get": "docstore_get", "graph": "docstore_graph", "plan": "docstore_index_plan",
             "capabilities": "docstore_capabilities", "surrealist": "docstore_surrealist",
             "projects": "docstore_project_sources", "project": "docstore_project_source"}
    params = {}
    if args.command in {"search", "semantic-search"}:
        params = {"query": args.query, "domain": args.domain, "limit": args.limit,
                  "kind": args.kind, "status": args.status, "rerank": args.rerank}
        if args.command == "semantic-search":
            params["presentation"] = args.presentation
    elif args.command in {"get", "graph"}:
        params = {"record_id": args.record_id}
    elif args.command == "plan":
        params = {"paths": args.paths}
    elif args.command == "project":
        params = {"project_id": args.project_id}
    async with Client(server, timeout=40) as client:
        result = await client.call_tool(names[args.command], params)
        return result.data


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compact', action='store_true', help='DuckDB compact presentation; precedes the command. No arbitrary SQL.')
    commands = parser.add_subparsers(dest="command", required=True)
    for name in ("serve", "catalog", "native-catalog", "native-probe", "verify-stdio", "health", "stats", "capabilities", "surrealist", "projects", "install-flags-schema"):
        commands.add_parser(name)
    for name in ("search", "semantic-search"):
        search = commands.add_parser(name)
        search.add_argument("query")
        search.add_argument("--domain", required=True)
        search.add_argument("--limit", type=int, default=8)
        search.add_argument("--kind", default="doc")
        search.add_argument("--status", default="active", choices=["active", "all"])
        search.add_argument("--rerank", action="store_true")
        if name == "semantic-search":
            search.add_argument("--presentation", default="compact", choices=["compact", "full"])
    for name in ("get", "graph"):
        commands.add_parser(name).add_argument("record_id")
    commands.add_parser("plan").add_argument("paths", nargs="+")
    commands.add_parser("project").add_argument("project_id")
    commands.add_parser("resource").add_argument("uri")
    related = commands.add_parser("related-updates")
    related.add_argument("term")
    related.add_argument("--limit", type=int, default=10)
    commands.add_parser("verify-index").add_argument("paths", nargs="+")
    commands.add_parser("set-flags").add_argument("json_file")
    commands.add_parser("capture-revision").add_argument("json_file")
    commands.add_parser("approve-revision").add_argument("json_file")
    commands.add_parser("revision-state").add_argument("document_key")
    commands.add_parser('selected-update-plan').add_argument('json_file')
    runs=commands.add_parser('runs')
    runs.add_argument('--run-id')
    runs.add_argument('--limit',type=int,default=20)
    for name in ("flags", "flags-view"):
        flags = commands.add_parser(name)
        flags.add_argument("--domain", required=True)
        flags.add_argument("--priority", choices=["critical", "high", "normal"], default="critical")
        flags.add_argument("--status", choices=["active", "superseded", "retracted"], default="active")
    args = parser.parse_args()
    try:
        values = environment()
        config = configuration()
        if args.command == "serve":
            build_server(config).run(**mcp_runtime(values))
            return 0
        value = asyncio.run(run(args, config))
        if args.compact:
            from compact import compact_result
            # Windows consoles are not guaranteed to be UTF-8. JSON escapes keep the
            # compact path machine-readable without failing on smart quotes/dashes.
            print(json.dumps(compact_result(value), separators=(',', ':'), ensure_ascii=True))
        else:
            print(json.dumps(value, indent=2, ensure_ascii=True))
        return 1 if args.command in {"health", "native-probe"} and value.get("ok") is not True else 0
    except Exception as exc:
        # No exception payloads: upstream errors may contain credentials or document bodies.
        print(json.dumps({"ok": False, "error_type": type(exc).__name__,
                          "message": "Docstore operation failed; inspect configuration and service health"}), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
