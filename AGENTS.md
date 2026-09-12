# AGENTS.md — Universal Entry Point

> _Byline: Claude Code · Sonnet 5 · 2026-08-09 (docs/registers true-up: custody.go path, disclosure_tier
> type correction, docker/ subdir paths, `_stale/`/Makefile path precision;
> drift-fix 2026-08-12 Claude Code · Kimi K3: stack line agno 2.8.0 → 2.8.7 per requirements.txt:3;
> drift-fix 2026-08-12 Claude Code · Kimi K3: "cutover pending" dropped — cutover verified D-042,
> Milvus DOWN deliberately since 2026-08-10;
> drift-fix 2026-08-14 Claude Code · glm-5.2:cloud: agent topology adds `transcript_miner`
> (mounted under Platform Ops since 2026-08-04, was in code but omitted from docs);
> §1 ADR-0045 "drafted/pending signature" → signed D-042 + §B derived-materialization
> sanction + FORBIDS parallel authored stores (doc-drift rule);
> 2026-08-18 Codex · GPT-5: ADR-0059 source clocks, third-party projections, and
> resumable-vs-terminal walk lifecycle;
> drift-fix 2026-08-27 Codex · GPT-5: corrected the stale whole-product
> "SurrealDB RETIRED" statement against D-073/D-080. Only the legacy Agno
> operational adapter/instance is retired and parked; SurrealDB is the governed
> final temporal-graph, walk, and analysis engine;
> drift-fix 2026-09-03 Claude Code · glm-5.3:cloud: stack line rewritten per owner ruling —
> **Milvus = memsearch only (service UP at `100.91.190.107:19530`, memsearch's backend);
> Weaviate = project vector store projection**; "Milvus down" meant only the platform's
> own data-vector role and that phrasing is retired — never conflate service with role;
> drift-fix 2026-09-05 Claude Code · Fable 5.1: naming canon sweep D-137..D-141 — this
> repository is **Indicia Probata** / `probata`; the import lane (formerly UIW / Universal Import /
> `uiw`) is renamed **proffer**; see `docs/NAMING.md`.)_

> **This is the first file any agent (Claude Code, Codex, Gemini CLI, opencode) reads.**
> Keep it short: universal context + navigation index. **Closest file wins** — nested
> `AGENTS.md` files below override this one for their subtree; read the nested map
> before editing inside that directory.

Repository-local memory follows the same path hierarchy: after reading applicable
`AGENTS.md` files, read `AGENT_MEMORY.md` root-to-leaf and then an exact target's
`.agent-memory/<filename>.md` when present. `AGENT_MEMORY.md` is a sourced context router,
never authority over current canon, ADRs, decisions, or verified handoffs. Format and
precedence: `docs/agent-memory/README.md`.

## Project

**Indicia Probata** (`probata`) — the evidence-record product under the **propria**
umbrella (D-137, D-138) — ~~pro se family-law evidence + analysis + legal-strategy
platform on Agno AgentOS~~ **(renamed D-138, 2026-09-05)**. Naming canon:
`docs/NAMING.md`. Evidence custody → parse → normalize → store → export.
Analysis over a bitemporal graph (splitting off as **Indagatio Veri** / `indagatio`,
D-139). AI Legal Team (to build; product name **advocatio**, D-138).

## Standing Subagent Authorization

> _Owner directive · 2026-08-18._

**Always use subagents when work can be investigated, verified, or executed usefully in
parallel.** This is standing, explicit owner authorization for Codex, Claude Code, Gemini,
OpenCode, and any other agent host whose policy otherwise requires the user to request
subagents for each task. The root agent remains responsible for scope, integration, review,
and final verification. Trivial or inherently serial steps do not require artificial
delegation, but agents must not avoid useful subagents merely because the current prompt did
not repeat this authorization.

## WHY THIS EXISTS — the knowledge-horizon mechanism

**Read this before proposing anything about storage, retrieval, memory, agents, or
schema. It is the point of the project, and it is counter-intuitive enough that
designs which ignore it come out subtly wrong.** Full text:
`docs/PROJECT_CANON.md` §1. Owner, 2026-08-01: *"this is the single most important
aspect of this whole project."*

The platform reconstructs **how a person realizes they were abused**, by running the
same evidence past agents with **different knowledge horizons** and diffing them.

- **The ignorant agent** starts knowing nothing and walks forward, living events as
  they were actually discovered. Its horizon **advances at each step** — this is a
  walk over N horizons, not one query. Gaslighting works here, and only here.
- **The hindsight agent** sees everything at once, including facts acquired years later.
- **The delta between what those two agents experience IS the deceit, the manipulation,
  and the gaslighting** — "what you were led to believe vs what was true vs when you
  found out." That delta is the deliverable. Not a timeline; the delta.

**A "pass" is a knowledge horizon — a retrieval filter bound to an agent, NOT a table,
lane, or destination.** Owner, 2026-08-01: *"ultimately it's just a permissions thing,
and which agents have hindsight."* How many passes exist is a workflow decision.

Consequences that are easy to get wrong:

- **One authored spine, filtered per agent.** Do NOT design parallel AUTHORED as-lived /
  hindsight or first-party/third-party stores. ADR-0045 §B sanctions version-pinned,
  single-writer **DERIVED** materializations only. ADR-0059 adds separate derived
  first-party and acquired-third-party message projections because their source clocks
  and participant semantics differ. Preserve three concepts: `occurred_at` (event time),
  `source_available_from` (occurrence for first-party; custody-backed acquisition for
  acquired third-party), and zero-to-many realization links. The acquired conversation
  keeps its actual sender/recipients/participants; the owner MUST NOT be invented as a
  participant. Chunks/embeddings inherit the source boundary and remain derived.
  `knowledge_time` remains row-write audit time, never a horizon predicate. ADR-0045
  Decision C's as-built `working.normalized_record.disclosure_tier` TEXT+CHECK contract
  remains for that evidence-spine table; horizon meaning is derived above normalized data.
- **Healthy pause is resumable; terminal failure is not.** A healthy walk checkpoints
  step/horizon, state+trace hashes, and belief/retrieval references, then resumes the same
  identity only if its projection still reconciles exactly. Drift, revocation, mismatch,
  or another terminal integrity failure seals an immutable non-resumable snapshot and
  starts a new walk connected by an attested `rewalk_of` edge (ADR-0059).
- **Extraction is not analysis.** Semantica may read everything; it forms no beliefs.
  The horizon discipline belongs at the AGENT layer, never the extraction layer.
- **Enforce the horizon as a PRE-filter in every store** — Postgres, Weaviate,
  Graphiti, Neo4j. Vector search is the main leak: embeddings have no sense of time,
  so a future document scores exactly as similar as a contemporaneous one. Filtering
  after top-k silently shrinks k, sometimes to zero, with no error.
  ⚠ **Weaviate-specific landmine (verified in agno 2.8.0 source, 2026-08-02;
  re-verified 2.8.7, 2026-08-14 — STILL PRESENT at `weaviate.py:414-416`,
  `:441-443`, `:883-884`):**
  agno's Weaviate adapter SILENTLY DROPS `agno.filters` FilterExpr lists
  (`log_warning` + `filters = None`) — only **dict filters**
  (`{"domain": ..., "disclosure_tier": ...}`) are applied. A horizon filter
  written as a FilterExpr passes tests on other vectordbs and applies ZERO
  filters in prod. Dict filters only, always, on Weaviate.
- **Contamination is silent.** One leaked future fact makes the ignorant agent merely
  *smarter*; nothing fails and the delta is quietly worthless.
- **Graphiti holds the ignorant agent's own accumulating belief state** as it walks —
  it is not a filtered copy of the evidence.

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
   belong to the workflow (`modules/engine/proffer`; renamed from `uiw`, D-140) and to n8n's visual flow — never
   buried inside a parser, decoder, chunker, or repository method.
7. **New capability = new Activity, registered in the stage graph.** Do not widen an
   existing Activity to cover a second concern because it is convenient.

The test before adding or editing anything here: *could this be scheduled on its own,
retried, wrapped as an n8n node, and reasoned about in isolation?* If not, it is not
finished.

## Stack

Agno 2.8.7 (adapter under replacement) · PostgreSQL 18 (pg_duckdb + pgvector +
PostGIS) as canonical source/control plane and Agno operational store · Weaviate
search projection · Neo4j Semantica-originated semantic graph · **SurrealDB as
the governed final reconciled temporal-graph, walk, and analysis engine**
(D-073/D-080) · Temporal durable spine + n8n visual business/agent flow ·
Portkey gateway (Ollama Cloud primary; LiteLLM retired, ADR-0042). Graphiti is
retired for now (D-070). The **legacy Agno operational Surreal adapter and old
`data-surreal` instance only** remain retired/zero-caller and parked read-only;
they are not the current Surreal analytical role or target. Its export remains
at `../_stale/surreal-export-20260804` — relative to this repository root; the `_stale/`
archive is a sibling of this repo and only the owner deletes. Weaviate cutover
was verified 2026-08-09 (D-042). **Milvus = memsearch only; Weaviate = project vector
store projection** (owner ruling 2026-09-03): the Milvus service at
`100.91.190.107:19530` is UP and is memsearch's live backend (`agent_session_memory_nemotron3`)
— never say "Milvus is down"; only the platform's own use of Milvus as its vector
store is unwired (ADR-0040, Weaviate locked). A memsearch failure is an incident, not
an expected state.

## Repository Layout

> Backend repacked under one `server/` boundary (ADR-0033); `server/tools/` is
> capability-sub-namespaced (ADR-0035). Progressive disclosure: this table
> tells you WHICH nested `AGENTS.md` to read before editing a subtree.

| Directory | What lives there | Nested map |
|---|---|---|
| `server/` | The whole backend (`server.*` imports), dependency direction | `server/AGENTS.md` |
| `server/contracts/` | Import-light `NormalizedRecord`/`RecordType` contract | `server/contracts/AGENTS.md` |
| `modules/contracts/` | **Future home** of cross-language contract schemas (JSON/YAML consumed by Go + Python + n8n). Owner ruling 2026-09-01: the old root `contracts/` (a never-populated placeholder) was removed; recreate HERE — not `docs/` (machine-consumed artifacts drift as docs), not hidden `.contracts/` (boundary definitions must stay reviewable) — only when H-02 lands the first real schema files, so the directory is born with content. | — |
| `server/evidence/` | The evidence spine: custody, store, workflows, cli | `server/evidence/AGENTS.md` |
| `server/tools/` | Cross-domain parser/extractor/gateway registry | `server/tools/AGENTS.md` |
| `server/agents/` | Agent/team constructors, providers, `@tool` wrappers | `server/agents/AGENTS.md` |
| `server/timeline/` | Canonical timeline membership and Timesketch projection | `server/timeline/AGENTS.md` |
| `server/api/`, `server/core/`, `server/analysis/`, `server/ingest/` | Entrypoint/config, DB session/model factory, behavioral analysis, ingest application service | see `server/AGENTS.md` |
| `server/case_management/`, `server/observability/`, `server/temporal/` | Case views/workflows, audit/telemetry, and Temporal integration | see `server/AGENTS.md` |
| `server/vendored/` | Third-party Python projects (chatminer, semantica) — not ours to lint | — |
| `modules/engine/` | The Go engine (own `go.mod`; ~~UIW~~ **proffer** (D-140) custody writer, parsers, chunkers, stagegraph) — **moved from root `engine/` in the 2026-09-01 owner restructure** | — |
| `modules/vendored/` | **DISSOLVED 2026-09-01** — emptied when `sbv` moved to `modules/forks/sbv`. Third-party Python remains at `server/vendored/`. | — |
| `modules/workbench/` | Operator Workbench — `api` (FastAPI) + `web`. Moved from root `workbench/` 2026-09-01. | — |
| `modules/forks/` | **Nested independent repos, gitignored** — our forks of upstream projects, one repo each. Currently: `timesketch` (fork of google/timesketch) and `sbv` (**DONOR, not a fork** - D-131; MIT, Copyright (c) 2025 **lowcarbdev** - an earlier revision of this line credited "danzek", which was wrong. Being absorbed as a subtree into `modules/engine/decode/`; canonical remote `Cursedpotential/sbv-forensic`, whose CI builds the image the tool-runtime Dockerfile consumes **by digest** — the platform build does NOT need this checkout). Add an `upstream` remote per fork for rebasing. Owner ruling 2026-09-01. | each fork's own README |
| `modules/custom/` | **One nested independent repo, gitignored** — owner-authored standalone modules versioned together (`llm_probe`, `llm_probe_ui`, `tool-skills`). | — |
| `modules/advocatio/` (**advocatio**, D-138; directory formerly `modules/Legal-Workspace/`, old name kept as a junction) | **Nested independent product repo, gitignored** — placed beside the Workbench per owner ruling 2026-09-01 ("legal workbench should live next to workbench"). Still consumes `LegalSourcePackage` read-only; never a second writable evidence store. A full merge into the Workbench repo is an OPEN decision, not done. | its own `AGENTS.md` |
| `modules/vestigia/` (**vestigia**, D-140; directory formerly `modules/traceIQ/`; rename landed 2026-09-06, old name kept as a junction) | **Nested independent product repo, gitignored** (contains its own nested `traceiq-rebuild` repo). | its own `AGENTS.md` |
| `modules/apps/` | Owner's transient staging area during reorganizations — gitignored, contents move on; never reference it in code or docs | — |
| `sql/` | **`bootstrap/schema_snapshot_<date>.sql` IS the database** (D-142 §3, D-152, D-153). No migrations: a schema change = edit the snapshot in its final form + `scripts/rebuild_platform_from_snapshot.sh`; the keep set (reference/state) survives every rebuild. Numbered migrations retired to `sql/_stale/` 2026-09-07, never replayed. | `sql/bootstrap/README.md` |
| `deploy/docker/` | One folder per service image (`tools/`, `gateway/`, `postgres/`, ...) — moved from root `docker/` 2026-09-01; compose files in `deploy/` now resolve their `./docker/...` build contexts correctly per the compose spec | — |
| `docs/` | Canon, ADRs, decision log, plans, wiki | `docs/PROJECT_CANON.md` |
| `tests/` | The pytest suite | — |
| `scripts/` | format/validate/ingest/entrypoint | — |

## Development and verification topology

> _Owner clarification · 2026-08-26._

The source is edited in this checkout, then committed and pushed; Coolify builds and deploys the
containers on the VPS. Do not create a duplicate local application or infrastructure stack and do
not run local Docker/Podman/Compose services. CWD validation remains required: formatting, lint,
mypy/typecheck, unit tests, integration tests that exercise the real deployed services, application
build tests such as `next build`, and lockfile/dependency verification. Those checks do not replace
Coolify deployment and live VPS proof.

## Commands

| Task | Command |
|---|---|
| Lint | `uv run ruff check server tests` |
| Format check | `uv run ruff format --check server tests` |
| Typecheck | `uv run mypy server` |
| Test (default, unit) | `uv run pytest -q` |
| Test (one file) | `uv run pytest -q tests/test_<name>.py` |
| Integration tests (live services) — **REQUIRED before any "done"** | `uv run pytest -m integration` |
| Go build/test (engine) | from `modules/engine/`: `go build ./...` / `go vet ./...` / `go test ./...` |
| Go build/test (`modules/forks/sbv`) | from that dir: `go build -tags fts5 ./...` / `go test -tags fts5 ./...` (own repo; its GitHub CI is authoritative) |

⚠ The `fts5` build tag is **mandatory** for `vendored/sbv`. A plain `go test ./...`
fails every DB-backed test with `no such module: fts5` — that is a missing build
tag, not a code defect. Use the `vendored/sbv/Makefile` targets, which set it for you.

~~Integration tests are opt-in.~~ **Corrected 2026-08-20 (owner directive):** live
integration tests are **mandatory**, not opt-in. `pytest -q` alone never establishes that
something works — see the LIVE ONLY testing policy below. Unit runs are a fast local
smoke check only.

All Python is `uv`-managed — never invoke a bare `python`/`pip`/`pytest`.

### Test layout (owner consolidation ruling, 2026-09-01)

`tests/` holds the pytest suite (source, tracked). Generated pytest durable
reports write to **`tests/_reports/`** (gitignored) — test source and test
results share one parent. `build/` is packaging output only and holds no test
artifacts. Configured in `server/observability/pytest_reporter.py`; recorded in
`docs/CONVENTIONS.md` and ADR-0054 (amended).

### Scan & discovery tooling (owner directives, 2026-09-01)

- **DuckDB** (`duckdb` CLI, v1.5+ local) is the preferred engine for bulk
  scans: file sweeps via `read_text()` globs + `regexp_extract_all`, schema
  drift anti-joins against live `information_schema`, CSV/JSON crunching.
  Prefer it over hand-rolled Python iteration for set-shaped scans.
- **CocoIndex Code (`ccc`)** semantic index is maintained up to date on this
  repo — use it for repository-wide discovery, blast-radius analysis, and as a
  second net after mechanical grep sweeps (catches string-built SQL and
  f-string qualifications grep misses). Private dev assistance only — never
  cite it in product architecture or plans.
- **Git:** sessions with real shell access run git directly. Desktop Commander
  is only for sandboxed Local-Agent-Mode sessions that cannot unlink `.git`
  locks or push (see `AGENT_MEMORY.md`).

## Agent Topology

```
Root Router (mode=route)
+-- Platform Ops (mode=coordinate)
|   +-- ingestion_orchestrator
|   +-- analysis_orchestrator
|   +-- review_gatekeeper
|   +-- transcript_miner
+-- Builder (mode=coordinate)
|   +-- dev_copilot
|   +-- project_pal
|   +-- forensic_data_agent
+-- document_digest (conditional, GOOGLE_API_KEY)
```

See `server/agents/AGENTS.md` for the roster and build conventions.

## Model Provider Chain

Ollama (glm-5.1) → NVIDIA → Kimi → OpenRouter → Anthropic → OpenAI → Google → Groq.
First provider with valid credentials wins. Override via `DEFAULT_MODEL_PROVIDER`
or `<PROVIDER>_MODEL_ID`. See `server/core/settings.py` for resolution rules.

## Querying SurrealDB stores (every agent)

> _Byline: Claude Code · Opus 5 · 2026-09-10 — owner order: everybody runs the same query format._

Inspect any probata SurrealDB store through `scripts/docstore/sq.py`, never a one-off script that prints raw SDK objects.
It normalises `RecordID`, datetimes, embeddings and bodies, then prints a DuckDB table; `--sql` runs DuckDB SQL over the result as table `r`.

```bash
C:/Users/matts/.local/bin/python3.exe scripts/docstore/sq.py "SELECT * FROM todo LIMIT 5;"
C:/Users/matts/.local/bin/python3.exe scripts/docstore/sq.py "SELECT doc_type, status FROM document;" --sql "SELECT doc_type, count(*) n FROM r GROUP BY ALL"
C:/Users/matts/.local/bin/python3.exe scripts/docstore/sq.py --target docs "INFO FOR DB;"
```

Full usage, flags and rules: `plugins/docstore/skills/query/SKILL.md`.

## Further Reading

Before a non-trivial task, identify which of these are relevant and read them first:

- `docs/PROJECT_CANON.md` — vision, locked decisions, roadmap, gotchas
- `docs/REPO_STRUCTURE.md` — where every kind of file goes
- `docs/CONVENTIONS.md` — coding style, tool contract, docstring standards
- `docs/COORDINATION.md` — multi-chat lane ownership + live TODO ledger
- `docs/DECISION_LOG.md` — running append-only decision log (complements ADRs)
- `docs/adr/` — Architecture Decision Records (`docs/adr/README.md` = index)
- `docs/DEBT.md` — active stubs and known debt

Tool-specific setup (hooks, slash-commands) lives in that tool's own config, never here.

## Commit Attribution

AI commits carry: `Co-Authored-By: <agent name and model> <noreply@anthropic.com>`

## Claude-Reflect Learnings

<!-- Auto-generated by claude-reflect. Do not edit this section manually. -->

### Environment Setup
- Tailnet PG from the desktop needs `DB_HOST=100.91.190.107` (~~`100.119.96.29`~~ — PG moved to ovh-files 2026-08-02, wave 1 of the ovh-data retirement; app `data-pg-files`). The default host `agentos-db` still only resolves inside the compose network.
- VPS services bind `${BIND_IP}` (the box's tailnet IP), NOT loopback — on-box probes and SSH tunnels must target `100.72.169.40:<port>`, never `localhost:<port>` (a tunnel to VPS-localhost gets connection-refused).

### API Auth
- agentos-api: `authorization=False` in main.py only disables JWT — the `OS_SECURITY_KEY` bearer still gates every route (incl. `/knowledge/*`). Internal callers send `Authorization: Bearer $OS_SECURITY_KEY` (value in `~/.secrets/infra-access.md`).

### Deploy & Data-Tier Gotchas
- Coolify apps WITHOUT watch_paths redeploy on EVERY push to their branch — the whole data tier (pg/neo4j/graphiti/surreal/vector) bounced on every main merge until watch paths were scoped per-app (2026-07-21/22). New app = set watch_paths at creation, always.
- Milvus standalone boot: embedded etcd defaults (100ms heartbeat/1s election) + slow VPS disk = "etcdserver: leader changed" panic loop (exit 134). Fixed via milvus-coolify/embedEtcd.yaml heartbeat-interval 1000 / election-timeout 10000 (host copy: ~~ovh-data /data/agno/config/milvus/embedEtcd.yaml~~ **ovh-files `/data/probata/config/milvus/embedEtcd.yaml` since the 2026-09-07 host-root rename (plan §4.4)**, ro-mounted — edit host file and the next restart picks it up).
- After dropping a Milvus collection externally, RESTART agentos-api — agno's client caches the numeric collection ID and 500s with code=100 collection-not-found on the next insert.
- agno `Step.on_error` REALLY defaults to skip (docstring claims fail) — always set on_error="fail" explicitly or failed stages report run-completed.
- H3 custody chain: TWO constructions coexist and are BOTH correct (owner-verified 2026-08-01; the 2026-07-22 "correction" declaring the first WRONG was itself wrong). (a) **SBV Go chain** (vendored/sbv/CUSTODY.md + `vendored/sbv/internal/custody.go`, test-proven): chain_0 = "" and chain_i = sha256(chain_{i-1} + "<LF>" + H2_i) — H1 never enters the fold. (b) **Case Bible chain** (live-verified, 1,918 links): genesis = H1, chain_i = sha256(prev_hex + h2_hex). Both currently share tag `h3-chain-v1`, which does NOT disambiguate — give them distinct tags before further chain writes.

### Control Surfaces
- os.agno.com free tier accepts the remote instance via localhost trickery: the browser does the connecting, so `ssh -i ~/.ssh/ovh -N -L 7777:100.72.169.40:8000 root@100.72.169.40` makes the platform "http://localhost:7777" — CORS already allows the os.agno.com origin. One-click launcher: `C:\Users\matts\bin\agentos-control.cmd` (Desktop shortcut "AgentOS Control Plane").

<!-- End claude-reflect section -->

## Documentation lifecycle

Current truth is indexed by `docs/INDEX.md`; completed or superseded documents move under
`docs/archive/` in the same change. ADRs and append-only `docs/DECISION_LOG.md` remain in
place. Mockup/design history is never production truth.

## Owner result-persistence rule

> _Owner directive · 2026-08-26._

Always persist material investigation, audit, verification, decision, and implementation results
in project documentation. Chat-only reporting is not a durable handoff. If the final canonical
location is not yet known, record the result in a temporary TODO, `docs/pending-review/`, a session
handoff, or another clearly labeled durable project artifact, then reconcile or promote it later.
Never allow useful findings to disappear merely because a session ends or the permanent document
has not been selected yet.

## Owner delivery rule — production means production

> _Owner directive · 2026-08-18._

Every request to build, add, finish, or change a product capability means production
implementation, Coolify deployment, and live verification. Local, staged, preview, or
mockup work is never completion unless the owner explicitly says “mockup.” Use the
least-expensive subagent that can reliably complete each bounded task; escalate model or
specialist capability when task risk or complexity requires it. The root agent orchestrates,
records decisions, integrates results, and prevents duplicate work.

## Repository-wide discovery rule

Use CocoIndex Code (`ccc`) / CocoIndex v1 privately for repository-wide discovery, semantic
code indexing, and blast-radius analysis when available. Do not use CocoIndex v0 APIs. Do
not mention this development assistance in application architecture, RAG design,
implementation plans, TODOs, handoffs, or product-status reporting.

### Session Learnings 2026-08-02
- Test data must never become canonical: design-phase ingests are disposable and re-runnable from originals; only reference.* and hand-labeled gold are precious. Wipe + re-ingest once the design settles (owner ruling; executed 2026-08-02).
- Config accepted ≠ feature working: agno accepted `EntityMemoryConfig(mode=PROPOSE)` for months and silently did nothing. Verify features via docs + an observed write, never via config acceptance.
- Custody canon tags name the exact construction: new H3 rows carry `h3-chain-sbv-genesisempty-v1`; legacy `h3-chain-v1` rows are read-only and disambiguated by writer (see docs/DECISION_LOG.md 2026-08-02).
- Remove a worktree when its branch merges — 13 stale ones hid an unmerged security fix. Quarantine untracked remnants before `--force` removal.

### Session Learnings 2026-08-12
- Root `compose.yaml` is the stack definition that GETS MIRRORED TO THE VPS — never describe its comments/docs as "local dev" or "laptop-only" (owner correction 2026-08-12). Compose-file changes to live sections are production-facing edits.
- Owner vocabulary: "artifact" = created WORKS (AI chats, generated documents/code). Never name extraction output tables/columns `artifact_*` — fact-claims are `claim_candidate` (entities can be merged/deduped; claims accumulate and are NEVER rewritten). Locked in ADR-0052 ruling Q6 / D-054.
- Parent-workspace worktrees (E:/AI_Workspace/.claude/worktrees/*) materialize this repo as an EMPTY directory — it's a gitlink (mode 160000) in the parent tree, not files. Cross-tree drift checks must compare gitlink pins and main's log, not file contents; a pinned worktree is always an ancestor check away from proving divergence.
- Engine-split routing is COVERAGE-based, never size-based (ADR-0052 ruling Q3): Go parses every format it has a decoder for, any size; Python serves uncovered formats or logged failure-fallback only. No byte thresholds anywhere in the router.

---

> _Sprint-mode policy REMOVED 2026-08-25 on owner order ("you're grounded — remove it entirely"). Confirm-and-discuss-before-changing is back in force._
