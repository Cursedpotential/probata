# Applied 2026-09-16 — memory schema deployment

Dated snapshot of the exact `.surql` files applied to the `surreal-case`
VPS instance (`100.91.190.107:8471`), namespace `probata_memory`, database
`memory`, on 2026-09-16 as part of the Propria Docstore memory-half repair
(see `Consignatio/docs/URGENT-TODO.md`, "2026-09-16 — Propria Docstore
plugin broken for agents").

Root cause: this ns/db had never been created on that instance (`INFO FOR
ROOT` showed only `fct`/`main`, both belonging to other apps sharing the
same SurrealDB container). The memory schema existed only in
`probata/scripts/docstore/memory-schema-fallback/` and had never been
deployed anywhere reachable by the `memory` MCP entry in `.mcp.json`.

Applied via `INFO FOR DB` before/after check, in order:
000_analyzers.surql, 080_memory.surql, 085_memory_functions.surql,
087_memory_access.surql — 0 ERR statuses, additive only, no existing data
touched (there was none).

Source of truth for future changes remains
`probata/scripts/docstore/memory-schema-fallback/`; this directory is a
point-in-time applied record, not a second canonical copy to edit.

Byline: Claude Code · Sonnet 5 · 2026-09-16
