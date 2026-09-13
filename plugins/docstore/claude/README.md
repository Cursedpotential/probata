# propria-docstore — universal documentation retrieval with bounded routing

<!-- Updated by: Codex | Date: 2026-09-12 | Rev: 1 | Platform: Codex / win32 | Changes: clarify system ownership | Context: owner request to persist CCC / Intake / Docstore distinction -->

Current owner scope: **Probata hosts the universal Propria Docstore: CocoIndex + NVIDIA NIM embeddings + the dedicated SurrealDB `probata/docs` database**. The memory connection below is a separate service integration. **CCC** is project-local codebase-only CocoIndex Code; **Intake** is the multifaceted CocoIndex/Weaviate/SurrealDB filesystem workstation. The `propria-search` skill routes among them without merging state or ownership. See [shared boundaries](../../../../../SYSTEM-BOUNDARIES.md).

> _Byline: Claude Code · Fable 5.1 · 2026-09-09 (skeleton built by Claude Code · Sonnet 5 the same day; validated with `claude plugin validate --strict`)_

Design: `docs/design/2026-09-09-docstore-memory-plugin-design.md`. Rulings: D-155 (docs local, embedded), D-156 (taxonomy), D-157/D-158 (memory = self-hosted SurrealDB Agent Memory on the VPS; NIM/Gemini via Portkey).

## Install

```
claude --plugin-dir E:/AI_Workspace/Projects/Propria/Probata/probata/plugins/docstore/claude
```

Environment (never commit values):

| Variable | Meaning |
|---|---|
| `DOCSTORE_BASIC_AUTH` | base64 of `SURREAL_USER:SURREAL_PASS` from `probata/.docstore/.env`; the local docs store listens on `http://127.0.0.1:8462/mcp` |
| `MEMORY_MCP_URL` | the memory server's `/mcp` URL; provisional default points at the plain SurrealDB on the VPS and will move to the Agent Memory server's port once D-157 is deployed |
| `MEMORY_BASIC_AUTH` | credentials for that server (a Bearer context key once Agent Memory is live; the `.mcp.json` header changes with it) |

## What loads when (progressive disclosure)

| Layer | Loads | When |
|---|---|---|
| 0 | bounded `SessionStart` health plus the `propria-search` routing reminder | every session |
| 1 | the nine skill descriptions | every turn, by the harness |
| 2 | one `SKILL.md` (≤ 60 lines): the `run` calls it wraps, exact SurrealQL, definition of done | when the skill matches |
| 3 | `references/functions.md` under that skill: full signatures, schema, worked example, gotchas | on demand |
| 4 | the MCP servers' generic tool schemas | deferred by the harness; never eagerly loaded |

Skills: `propria-search` (primary Docs/CCC/mixed router), `query` (ad-hoc SurrealQL through `scripts/docstore/sq.py`, rendered as a DuckDB table), `docs` (semantic search, get, provenance), `docs-write` (register, new version in place, supersede), `decisions` (ADR banners, D-rows), `todo` (open, close), `handoff` (write and mirror), `memory` (remember, recall, supersede, forget, reflect), `reconcile` (stale candidates, ingest mapping).

_2026-09-12 (Codex): `propria-search` added as the primary routing skill; eight skills → nine. `coco_docstore_search` is the ordinary documentation-search entry point and owns NIM query embedding plus Surreal BM25/KNN fusion._

Agents: `docstore-librarian` (Sonnet, the only writer), `docstore-reconciler` (Opus, interactive, never batch-writes), `memory-curator` (Sonnet). None run on the frontier model.

## Hooks (each prints at most three lines)

- `SessionStart` → `bin/preflight.sh`: pings both `/health`; loud failure, no filesystem fallback.
- `UserPromptSubmit` → `bin/read-gate.sh`: the read-gate reminder, suppressed when the last tool call was already a store search (state under `.state/`).
- `PostToolUse` on `Write|Edit` under `docs/**` → `bin/flag-doc-write.sh`: "unregistered until `docs_register` or `docs_new_version` runs".
- `PreCompact` → `bin/precompact-marker.sh`: writes a marker the next `SessionStart` reads (PreCompact cannot inject context).

## Tool boundary

Ordinary document retrieval uses the typed `control` MCP tool
`coco_docstore_search`; it owns input validation, NIM query embedding, Surreal
BM25/KNN fusion and bounded DuckDB presentation. Exact structured records and
database/graph inspection may use the native `docs` MCP functions. Raw arbitrary
querying is not the semantic-search entry point. CCC remains an independent CLI
and CocoIndex Code application for each source repository.

## Codex

~~`.codex/docstore/` mirrors the two servers in `config.toml` and the seven skills as prompts.~~ **CORRECTED 2026-09-09 (Claude Code · Opus 5):** `config.toml` and `AGENTS.md` exist and are current, but `.codex/docstore/prompts/` is **EMPTY** — the seven prompts were never written. The Codex side is a stub, not a mirror. A stale partial duplicate `.codex/codex-docstore/` (older `AGENTS.md`, no `prompts/`) was quarantined to `to_be_deleted/2026-09-09-restructure/`. Codex has no hooks, so the read and write gates are instructions only.
