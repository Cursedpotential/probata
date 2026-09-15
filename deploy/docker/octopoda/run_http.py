"""Run octopoda's FastMCP server over streamable-HTTP instead of stdio.

octopoda==3.3.4 (synrix_runtime.api.mcp_server) only exposes a stdio
entrypoint (`main()` calls `mcp.run(transport="stdio")`, hardcoded). The
underlying `mcp` package (>=1.2,<2) already implements a streamable-HTTP
transport on the same FastMCP object, so this wrapper imports the module
(which builds `mcp` and registers all tools as an import side effect) and
calls `mcp.run(transport="streamable-http")` directly instead of `main()`.

Host/port: FastMCP's constructor passes `host`/`port` explicitly into its
pydantic Settings, so FASTMCP_HOST/FASTMCP_PORT env vars are NOT read (the
env-var path only wins when the constructor doesn't pass a value). We mutate
`mcp.settings` after import instead.

Transport security: FastMCP auto-enables DNS-rebinding Host/Origin checks
whenever host is one of the loopback aliases; since the container's default
host is 127.0.0.1 those checks got enabled and pinned to loopback-only
allowed_hosts. We rebind to 0.0.0.0 and disable that check here because the
container is reachable ONLY over the tailnet (Coolify binds the published
port to the ovh-app tailnet IP, not 0.0.0.0 on the host) and the only client
is ContextForge on the same box, which enforces its own bearer-token auth in
front of this server. Never bind this port to a public interface.

Byline: Claude Code · Sonnet 5 · 2026-09-15
"""
import os
import sys

from mcp.server.transport_security import TransportSecuritySettings

from synrix_runtime.api.mcp_server import mcp

api_key = os.environ.get("OCTOPODA_API_KEY", "")
if not api_key:
    print("Octopoda MCP starting in LOCAL mode (no OCTOPODA_API_KEY set).", file=sys.stderr)

data_dir = os.environ.get("OCTOPODA_DATA_DIR") or os.environ.get("SYNRIX_DATA_DIR")
print(f"Octopoda data dir: {data_dir or '~/.synrix/data (default)'}", file=sys.stderr)

mcp.settings.host = "0.0.0.0"
mcp.settings.port = int(os.environ.get("PORT", "8095"))
mcp.settings.transport_security = TransportSecuritySettings(enable_dns_rebinding_protection=False)

print(f"Octopoda MCP (streamable-http) on {mcp.settings.host}:{mcp.settings.port}{mcp.settings.streamable_http_path}", file=sys.stderr)
mcp.run(transport="streamable-http")
