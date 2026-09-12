# Probata universal Docstore plugin

This directory is the source package for Propria's universal documentation
plane. It is separate from project-local CCC code indexes and from Intake's
filesystem/evidence index.

## Canonical surfaces

- `control/`: the governed FastMCP control server and its tests. It exposes 21
  tools, five static resources, four resource templates and one prompt.
- `claude/`: the slim Claude marketplace package. It contains the user-facing
  skills, commands and agents and launches `control/` from the E-drive source.
- root `.claude-plugin/plugin.json` and `.mcp.json`: the self-contained source
  bundle used by Codex as `probata-docstore@probata` and available for Claude
  packaging. Codex marketplace registration lives at
  `../.agents/plugins/marketplace.json`.

The marketplace entry is `probata-docstore@probata`, version 0.5.2. The older
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
