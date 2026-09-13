# Probata universal Docstore plugin

Byline: Codex / GPT-6, 2026-09-12 — canonical Codex registration repair.

This directory is the source package for Propria's universal documentation
plane. It is separate from project-local CCC code indexes and from Intake's
filesystem/evidence index.

## Canonical surfaces

- `control/`: the governed FastMCP control server and its tests. It exposes 22
  tools, seven resources, four resource templates and one prompt. API resources
  `docstore://api/openapi` and `docstore://api/surreal` retrieve live schemas.
- `claude/`: the slim Claude marketplace package. It contains the user-facing
  skills, commands and agents and launches `control/` from the E-drive source.
- root `.claude-plugin/plugin.json`: the skills bundle used by Codex as
  `probata-docstore@probata`. Root `.mcp.json` is deliberately empty: Codex uses
  one explicitly configured `probata-docstore` server with absolute source paths
  and the canonical configuration loader. It must not also inject unresolved
  `control`, `surreal`, or `memory` aliases. Claude uses the separate `claude/`
  package and its own MCP manifest. Codex marketplace registration lives at
  `../.agents/plugins/marketplace.json`.

The marketplace entry is `probata-docstore@probata`, version 0.5.4. The older
`docstore@probata` 0.4.0 identity is superseded and must remain disabled; it is
not deleted automatically.

## Transport and federation

Local agent hosts use stdio by default. For ContextForge, set:

```text
DOCSTORE_MCP_TRANSPORT=http
DOCSTORE_MCP_HOST=0.0.0.0
DOCSTORE_MCP_PORT=8084
```

The Streamable HTTP endpoint is `/mcp`. The server is stateless and accepts only
`127.0.0.1` or `0.0.0.0` as bind values. ContextForge must register it with
transport `STREAMABLEHTTP`; its default SSE selection is not equivalent.

Do not expose the backend port publicly. Keep it on the shared private network
behind ContextForge, and provide Docstore API/Surreal credentials only through
deployment environment variables.

## Deployment truth

The local stdio and HTTP protocols are verified. Production federation and
multi-root ingestion are not complete until the mandatory gate in the Propria
root `docs/MONOREPO-MIGRATION-PLAN-2026-09-12.md` passes. In particular, the
current Probata-only Docker build context cannot prove access to every Propria
documentation root.

Byline amendment: Codex · GPT-5 · 2026-09-12 (Codex marketplace installation repair)
