---
scope: .
status: current
verified_at: 2026-08-29
superseded_by: null
authority:
  - AGENTS.md
  - docs/INDEX.md
  - docs/PROJECT_CANON.md
  - docs/DECISION_LOG.md
  - docs/MEMORY_ARCHITECTURE.md
watches:
  - AGENTS.md
  - docs/INDEX.md
  - docs/PROJECT_CANON.md
  - docs/DECISION_LOG.md
contains_secrets: false
---

# Repository Agent Memory

> _Byline: Codex · GPT-5 · 2026-08-27; navigation verification refreshed 2026-08-29._
> _Byline: Claude Code · Fable 5.1 · 2026-09-05 — naming canon sweep D-137..D-141; no UIW/proffer rows existed in this router. See `docs/NAMING.md`._

This file is a router, not an encyclopedia. Read only the branches relevant to the current task.

## Durable owner preferences

- **Owner directive:** lead with the result, use labeled sections and plain English, and use an
  HTML/diagram/table when complex relationships materially benefit from a visual surface.
- **Owner directive:** finish one functional vertical slice before adding another feature; never
  substitute an unapproved surface or disconnected stub without explicit disclosure.
- **Owner directive:** persist material findings, decisions, implementation, and verification in
  project documentation; chat-only results are not a handoff.
- **Owner directive:** preserve concurrent work, use bounded ownership, and never hard-delete.
- **Owner directive:** edit and validate source in this checkout; commit and push; Coolify builds
  and deploys on the VPS. Do not create a duplicate local infrastructure stack.

## Current cross-tree corrections

- SurrealDB remains the governed temporal-graph, walk, and analysis target. Only the retired legacy
  operational adapter/instance is parked. See `AGENTS.md` and ADR-0056.
- LanceDB is not part of the current platform stack. **Milvus = memsearch only; Weaviate =
  project vector store projection** (owner ruling 2026-09-03): the Milvus service
  (`100.91.190.107:19530`) is UP and is memsearch's live backend — never say "Milvus is
  down." See `AGENTS.md`.
- PostgreSQL remains canonical. Timesketch, search, graph, RAG, and operator surfaces are governed
  views or projections, not replacement authority.

## Repository boundary router

- Canonical repository checkout: `E:/AI_Workspace/Projects/Propria/Probata/probata`.
- Repository status: separate child Git repository pending controlled Propria monorepo import.
- Canonical linked-worktree root: `E:/AI_Workspace/Projects/Propria/_worktrees/`.
- Codex-managed exception: `C:/Users/matts/.codex/worktrees/`.
- Consignatio authority: `E:/AI_Workspace/Projects/Propria/Consignatio`; read its own routers
  before Consignatio work and do not treat this Probata repository as its authority.

## Path router

| Path in scope | Read next |
|---|---|
| `docs/**` | `docs/AGENT_MEMORY.md` |
| `server/**` | `server/AGENT_MEMORY.md` plus the closest nested memory |
| `modules/engine/**` (was root `engine/`, moved 2026-09-01) | `modules/engine/AGENT_MEMORY.md` |
| `server/contracts/**` | `server/contracts/AGENTS.md` (root `contracts/` removed 2026-09-01) |
| `sql/**` | `sql/AGENT_MEMORY.md` |
| `deploy/**` | `deploy/AGENT_MEMORY.md` |
| `deploy/docker/**` (was root `docker/`, moved 2026-09-01) | `deploy/docker/AGENT_MEMORY.md`; for n8n also `deploy/docker/n8n/AGENT_MEMORY.md` |
| `modules/advocatio-legal_workbench/**` (advocatio) and `modules/vestigia-geodata_processor/**` (vestigia) | each nested repo's own `AGENTS.md` / `AGENT_MEMORY.md` |
| `modules/workbench/**` (was root `workbench/`, moved 2026-09-01) | `modules/workbench/AGENT_MEMORY.md` plus the closest nested memory |
| `tests/**` | `tests/AGENT_MEMORY.md` |
| `knowledge/**` | `knowledge/AGENT_MEMORY.md` |
| `server/vendored/**` | `server/vendored/` project READMEs (modules/vendored dissolved 2026-09-01; sbv now `modules/forks/sbv`, own repo, its memory file at `modules/forks/AGENT_MEMORY.md`) |

Removed from the tree 2026-09-01 (owner restructure; rows retired): root
`timesketch-fork/` (now a workspace sibling), `llm_probe/`, `llm_probe_ui/`.

Format and precedence: `docs/agent-memory/README.md`.

<!-- freshness
watches_hash: 692a4b7
last_verified: 2026-08-29
watches:
  - AGENTS.md
  - docs/INDEX.md
  - docs/PROJECT_CANON.md
  - docs/DECISION_LOG.md
  - docs/MEMORY_ARCHITECTURE.md
-->

## Geo lane is PARKED (D-121, 2026-08-31) — note for every future session
The location/GPS lane (stay_point, gps_track, geocode_*, home_base,
waypoint_device_split, vehicle, geofence, geocode_audit) is REAL, owner-ruled,
and deliberately OUT of the live database until ingest is proven on lesser
data. Complete one-file restore: `sql/parked/geo_lane_parked_20260831.sql`
(restore-proven against a clean target). Do NOT recreate these ad hoc; do NOT
treat their absence as a gap. Owner: "why am I gonna bring in the key to the
application I've been working on even longer than this, just to have it
fucked up too."

## Git on this repo
~~Desktop Commander ONLY~~ **Corrected 2026-09-01 (owner):** sessions with real
shell access (Claude Code desktop) run git directly. The DC-only rule applied
only to sandboxed Local-Agent-Mode sessions that could not unlink .git locks or
push (proven 2026-08-31, commit 15a1d87). Use DC only from such a sandbox.
