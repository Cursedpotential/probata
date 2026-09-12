# server/ — the backend boundary

> _Byline: Claude Code · 2026-07-27; navigation refresh by Codex · GPT-5.6-Sol · 2026-08-29._

> Nested map. Root map: `../AGENTS.md`. Closest file wins — if you're editing inside
> `contracts/`, `evidence/`, `timeline/`, `tools/`, or `agents/`, read THAT directory's `AGENTS.md` too.

## What's here

One backend boundary, domain-separated inside (ADR-0033 repacked every top-level
package — `agents/`, `app/`, `db/`, `evidence/`, `tools/` — under here; every import
is `server.*`). ADR-0035 sub-namespaced `server/tools/` by capability.

| Package | Role |
|---|---|
| `api/` | FastAPI/AgentOS entrypoint (`main.py`), MCP mount (`mcp_main.py`) |
| `core/` | Settings/model-provider factory, DB session, embedder, reranker |
| `contracts/` | Import-light record contract (`NormalizedRecord`) — see `contracts/AGENTS.md` |
| `evidence/` | The evidence spine (custody/store/workflows/cli) — see `evidence/AGENTS.md` |
| `tools/` | Cross-domain parser/extractor/gateway registry — see `tools/AGENTS.md` |
| `agents/` | Agent/team constructors, providers, `@tool` wrappers — see `agents/AGENTS.md` |
| `analysis/` | Behavioral domain: `detection.py`, `patterns.py`, `court_language.py`, `semantica_wiring.py` |
| `ingest/` | Framework-neutral ingest application service + PostgreSQL knowledge read model |
| `case_management/` | Case-management application services and governed case views |
| `observability/` | Audit, telemetry, and operational visibility helpers |
| `temporal/` | Temporal activities/workflows and durable orchestration integration |
| `timeline/` | Canonical timeline membership + Timesketch projection — see `timeline/AGENTS.md` |
| `vendored/` | Third-party projects (`chatminer`, `semantica`) — import-only, excluded from ruff/mypy/pytest |

## Dependency direction (downward only)

```
contracts/   <- innermost. No imports of anything else in server/.
core/        <- settings/session/embedder. No imports of evidence/tools/agents/api.
evidence/    <- imports contracts/, core/. THE spine (custody -> store -> workflows).
tools/       <- imports contracts/ (records), vendored/chatminer. Parsers depend
                INWARD on server.contracts.records, never on evidence/ or agents/.
analysis/    <- imports contracts/, core/, tools/ (registry).
ingest/      <- imports contracts/; composes evidence/tools lazily behind neutral ports.
case_management/, observability/, temporal/, timeline/ <- application/integration packages;
                preserve their governed source and dependency boundaries.
agents/      <- outermost domain layer. Imports evidence/, tools/, analysis/, core/.
api/         <- outermost. Mounts agents/ + evidence/ + tools/ into FastAPI/AgentOS.
```

Never import upward (e.g. `contracts/` must never import `evidence/` or `agents/`) —
`contracts/` in particular is imported by the dep-light `docker/tool-runtime` facade
container, so a heavy import there FATAL-loops that container (ADR-0035).

## Relevant ADRs

- ADR-0033 — the `server/` repack (this boundary's origin)
- ADR-0035 — `server/tools/` sub-namespacing + record contract home (`contracts/`)

## When to read deeper

| Task | Read |
|---|---|
| Adding/changing a parser or extractor | `tools/AGENTS.md` |
| Evidence custody/normalize/store work | `evidence/AGENTS.md` |
| Building/changing an agent or team | `agents/AGENTS.md` |
| Touching the record schema | `contracts/AGENTS.md` |
| Timeline membership or Timesketch projection | `timeline/AGENTS.md` |
| DB session, embedder, model provider chain | `core/settings.py`, `core/session.py` (no nested map — small, read the file) |

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
