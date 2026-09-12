# server/contracts/ — the import-light record contract

> _Byline: Claude Code · 2026-07-27; verification refresh by Codex · GPT-5.6-Sol · 2026-08-29._

> Nested map. Parent: `../AGENTS.md`. Root: `../../AGENTS.md`.

## What's here

```
records.py    NormalizedRecord / RecordType / DisclosureTier
```

One shape every parser emits into (message / call / event / media) — storage,
analysis, and export never care which of the 20+ parsers produced a record.
Carries the bitemporal substrate: `occurred_at` (valid time) vs `knowledge_time`
(when the platform learned it) vs `disclosure_tier` (contemporaneous / hindsight /
discovered).

## The one hard rule: MUST stay dependency-free

`server/contracts/__init__.py` is deliberately empty of heavy imports (no
sqlalchemy / agno / duckdb) — **do not change that.** Why: the `docker/tool-runtime`
facade is a dep-light container that mounts the whole `server/` tree
and imports every parser to build its registry; every parser imports
`server.contracts.records`. If this package's `__init__` ever pulls in a heavy
dependency, the facade FATAL-loops on startup — the exact failure mode ADR-0033
already paid a 2-day outage for once. Keep new code in `records.py` itself
free of heavy deps too; if you need something heavier, it belongs in
`server/core/` or `server/evidence/`, not here.

## Why it lives here, not `server/core/`

ADR-0035 (Option A, owner-confirmed): `server/core/__init__.py` eagerly imports
`server.core.session` (postgres/agno/duckdb), so `server/core/records.py` would have
run that whole chain on any import — including from the facade. `server/contracts/`
is a new, deliberately minimal package created to be facade-safe by construction.
`server/evidence/normalize.py` is a thin deprecated re-export shim pointing here —
don't add new code to it.

## Relevant ADR

- ADR-0035 — full rationale, the two candidate homes considered (`server/core/` vs
  here), and the as-built Outcome section. Read it before moving or extending this
  contract — don't restate the tradeoff here.

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
