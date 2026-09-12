# server/agents/ — agent/team constructors

> _Byline: Claude Code · 2026-07-27; verification refresh by Codex · GPT-5.6-Sol · 2026-08-29._

> Nested map. Parent: `../AGENTS.md`. Root: `../../AGENTS.md`.

## What's here

The outermost domain layer — builds every Agno `Agent`/`Team` and wires the
runtime context they share. Imports `evidence/`, `tools/`, `analysis/`, `core/`
(never the reverse — see the dependency direction in `../AGENTS.md`).

| File | Role |
|---|---|
| `factory.py` | Every `Agent`/`Team` built by a `build_<name>()` function; `build_agent_team(ctx)` assembles the full topology (see root `AGENTS.md` for the diagram) and returns a dict keyed by stable public name — UI/tests depend on these keys. |
| `providers.py` | Builds `PlatformContext` (context providers, `LearningMachine`, MCP wiring). `source_tools` is the single append point for new agno `@tool` lists (Graphiti, `gateway_tools`, `sbv_tools` all append here). |
| `instructions.py` | Authoritative role/guardrail text for every agent — change the docstring first, then the instruction strings. `GLOBAL_GUARDRAILS` prepends to every agent. |
| `*_orchestrator.py`, `dev_copilot.py`, `project_pal.py`, `forensic_data_agent.py`, `review_gatekeeper.py`, `document_digest.py`, `transcript_miner.py` | Individual agent/team builders — see the topology diagram in the root map. |
| `claude_code_agent.py` | `build_claude_code_agent()` — Claude Code (`agno.agents.claude.ClaudeAgent`) wrapped for AgentOS. **Staged, NOT mounted** into `build_agent_team()` / the Root Router — needs the `claude-code` extra installed and an explicit owner decision on where it sits in the topology (see the module docstring, 2026-08-01). |
| `tools/gateway_tools.py` | agno `@tool` wrappers over the G4 gateway (`server/tools/gateway/toolfinder.py`) — 5 thin functions instead of one per parser. |
| `tools/sbv_tools.py` | agno `@tool` wrappers over `SBVClient` (`server/tools/_sbv_client.py`) — mirrors the old facade's `/sbv/*` proxy surface + `sbv_hashes` (H1/H3 custody chain). |

## Conventions

- `agents/tools/` (this package) is distinct from `server/tools/` (the atomic parser
  registry) and `server/tools/gateway/` (the G4 meta-ops themselves) — this package
  holds only the thin agno-facing `@tool` adapters, kept next to `providers.py` which
  wires them into `source_tools`.
- Error convention (OQ-8, `docs/COORDINATION.md`): `@tool` wrappers do NOT catch and
  reshape exceptions into `{"error": ...}` dicts — they let `KeyError`/`ValueError`/
  `SBVError` propagate. agno's `Function.execute()` already catches and reports a
  structured `status="failure"` result; re-catching here would throw that signal away.

## Relevant ADRs / docs

- ADR-0006 — two-layer team topology (root Router over coordinate families)
- ADR-0033 — `server/` repack (this package's current home, was top-level `agents/`)
- `docs/planning/facade-collapse-plan.md` — why `gateway_tools`/`sbv_tools` exist as
  agno `@tool`s alongside (not instead of) the `deploy/docker/tool-runtime` facade (superseded banner
  explains the corrected architecture — read it before touching this area)

---

> _Sprint-mode policy REMOVED 2026-08-25 on owner order ("you're grounded — remove it entirely"). Confirm-and-discuss-before-changing is back in force._

## ATOMICITY — every unit must be assignable to a Temporal Activity

> _Owner directive · 2026-09-02. Binding on every directory below this file.
> Reinforces the 2026-08-25 boundary ruling, ADR-0061, and D-077._

**Write every unit of work so it can be handed to one Temporal Activity, and never
conflate multiple processes into one unit.**

Owner, 2026-09-02: *"Everything needs to be modular so that it can be assigned to
Temporal activities. We can't be conflating or mixing a bunch of processes into one.
Yes, the engine can call individual ones, but it's going to be calling the Activity
more likely than 99.9% of the time."* And: *"Or to be added into an n8n node which
gets run as an activity, however that shape looks."*

Rules, in force everywhere:

1. **One unit does one thing.** A parser parses and does nothing else (owner,
   2026-08-29: *"they parse, they do nothing more"*). A chunker chunks. A hasher
   hashes. If a function does two of those, it is wrong and must be split before it
   is wired to anything.
2. **Hashing is its own Activity family and is never folded into parsing, chunking,
   or normalization.** Custody hashing is separate machinery with its own boundary
   (D-077, four hash moments; see `docs/reference/HASH-TAXONOMY-2026-08-29.md`).
3. **The Activity is the normal caller.** Direct in-process calls stay legitimate —
   but the overwhelmingly common path is invocation *as*, or from *within*, a
   Temporal Activity. Design signatures for that: bounded inputs, bounded outputs,
   no ambient state, no hidden I/O, deterministic given its inputs, safely
   retryable. An Activity may be retried; anything that breaks on a second identical
   call is a defect.
4. **Three call shapes, one unit.** The same unit must serve all of them without
   knowing which is in play: (a) called directly in-process; (b) invoked as a
   Temporal Activity; (c) **wrapped as an n8n node that is itself executed as, or
   from within, an Activity.** n8n owns the visual flow, Temporal owns durability,
   the unit owns one job. A unit that needs to know its caller has a boundary
   violation in it.
5. **Pass references, never payloads.** Source bytes and bundles move by locator
   (`upload://`, `r2://`, sealed `file://`), never through Temporal history, an n8n
   payload, or a PostgreSQL activity request.
6. **No orchestration inside a unit.** Sequencing, fan-out, retries, and human gates
   belong to the workflow (`modules/engine/proffer` (formerly `uiw`, renamed D-140)) and to n8n's visual flow — never
   buried inside a parser, decoder, chunker, or repository method.
7. **New capability = new Activity, registered in the stage graph.** Do not widen an
   existing Activity to cover a second concern because it is convenient.

The test before adding or editing anything here: *could this be scheduled on its own,
retried, wrapped as an n8n node, and reasoned about in isolation?* If not, it is not
finished.
