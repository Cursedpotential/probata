# REPO STRUCTURE — the one structure

> **Authoritative for:** where every kind of file goes. Entry point: `docs/PROJECT_CANON.md` (§0).
> The point of this doc: a new capability has exactly ONE correct home, so iterations never scatter
> into competing architectures again. Last updated: 2026-08-09 (docs/registers true-up: added the
> `analytics/`, `deploy/`, `tool-skills/`, `database/` top-level rows the tree was missing; prior:
> 2026-07-10, ADR-0035: `server/tools/` sub-namespaced by capability, `tool_finder/` →
> `server/tools/gateway/`, record contract → `server/contracts/records.py`). Progressive-disclosure
> detail for each package now lives in that package's own `AGENTS.md` (root map: `../AGENTS.md`) —
> this doc stays the single structural index. 2026-08-13: chat-ingestion modules added to
> the analysis map.
> _Byline: Claude Code · Opus 4.8 · 2026-06-13 (D-026 update: Claude Sonnet 5 · 2026-07-09; ADR-0035
> update: Claude Opus 4.8 · 2026-07-10; 2026-08-09 update: Claude Code · Sonnet 5;
> 2026-08-13 update: Codex · GPT-5; 2026-08-14 visualizer namespace: Codex · GPT-5;
> 2026-08-15 current-entry-point repair: Codex · GPT-5)_
> _Byline amendment: Claude Code · Fable 5.1 · 2026-09-05 — naming canon sweep D-137..D-141; this repository is **Indicia Probata** / `probata`; see `docs/NAMING.md`. `Agno-MCP-Platform-alpha/` path references below are literal filesystem paths (reference-only parts bin), not product-name assertions, and are unchanged._

## The one active build

`probata/ (formerly Agno-MCP-Platform/)` is **the only active repo**. Everything under the workspace root *outside* it
is reference (donor archives, mined code, planning history). **Never build a parallel stack.**

## Canonical layout (`probata/ (formerly Agno-MCP-Platform/)`) — ONE backend boundary (ADR-0033)

> Repacked 2026-07-09 (ADR-0033): every backend package lives under `server/`; import paths
> are `server.*`. The old flat siblings (`app/ agents/ db/ evidence/ gateway/ tools/ chatminer/`)
> are gone. Amended 2026-07-09 (D-026): the atomic-tools capability layer + registry moved OUT
> of `server/evidence/` to top-level `server/tools/` — tools are cross-domain (evidence, analysis,
> agents, workflows, CLI all consume them), not evidence-owned. Amended 2026-07-10 (ADR-0035):
> `server/tools/` sub-namespaced by capability (`parsers/{messaging,ai_chat,generic}/`,
> `extractors/`); the G4 gateway moved `server/evidence/tool_finder/` → `server/tools/gateway/`;
> the record contract (`NormalizedRecord`) moved `server/evidence/normalize.py` →
> `server/contracts/records.py` (import-light, facade-safe — `normalize.py` is now a deprecated
> re-export shim).

```
server/         THE backend — one boundary, domain-separated inside:
  api/          current Agno/AgentOS adapter entrypoint plus framework-neutral HTTP routes
  core/         settings.py (model factory), session.py, embedder.py (NimEmbedder), reranker.py, url.py
  contracts/    IMPORT-LIGHT record contract (ADR-0035) — records.py (NormalizedRecord/RecordType/DisclosureTier); see below
  agents/       factory.py (build_agent_team), providers.py (context providers, learning, Graphiti MCP), instructions, tools/ (@tool wrappers)
  evidence/     THE SPINE (Python chassis) — see below; purely evidence-domain since ADR-0035
  case_management/  Matter/CourtCase repository + service boundary (held locally; migration 0030 unapplied)
  tools/        CROSS-DOMAIN CAPABILITY LAYER (D-026), sub-namespaced by capability (ADR-0035) — registry + parsers/extractors/visualizers/gateway; see below
  analysis/     behavioral + knowledge ingestion: detection.py, patterns.py, chat_parse.py,
                chat_normalizer.py, context_chat_ingest.py, lane_classifier.py,
                chat_archive.py, context_assets.py, semantica_wiring.py + config/
  vendored/
    chatminer/  vendored parser core (import-only)
    semantica/  vendored project (installed dist, not `server.vendored.semantica`-imported)
workbench/      CUSTOM OPERATOR PRODUCT — api/ FastAPI BFF + web/ Next.js; expanding locally
ui/             superseded/deferred shell proposal; do not start a parallel UI
shared/         cross-boundary contracts — created only when ui/ needs them (DEFERRED)
sql/            bootstrap/schema_snapshot_<date>.sql IS the database (no migrations since 2026-09-07, D-153; retired chain in sql/_stale/)
docker/         one folder per service image: postgres/ (pg_duckdb), tools/, sandbox/, gateway/, milvus/, n8n/, coolify-mcp/
compose.yaml    mirrored stack definition with production-facing live sections; never describe
                it as laptop-only. Per-app Coolify compose files live in deploy/ (S10
                consolidation 2026-08-10, D-043): deploy/<app>.yaml, one file per Coolify
                application. Root also keeps compose.data-surreal.yaml (PARKED marker, see its
                header). Dead tiers (browser/ui/data) → _stale/*.SUPERSEDED.
                ⚠ Branch-scoped apps librechat* and nocodb (infra/* branches) still deploy
                root-path compose files FROM THEIR BRANCHES. Workbench was repointed and live-
                verified on 2026-08-13 at deploy/workbench.yaml with matching watch paths before
                workbench/sprint was fast-forwarded to main. For the remaining branch-scoped apps,
                update docker_compose_location before merging main or deployment breaks silently.
evals/          agno-eval cases (harness-first)
scripts/        format.sh, validate.sh, ingest_*, generate_requirements.sh, repack_to_server_layout.py
knowledge/      curated knowledge inputs (NEVER secrets/case-data)
docs/           canon + the authoritative docs + adr/ + planning/ + wiki/ + visualizations/
tests/          the pytest suite (208)
analytics/      ~~standalone Evidence.dev reporting projects, one subdir each~~
                **CORRECTED 2026-09-02 (D-129): this directory does not exist here and is
                gitignored (.gitignore:97).** Its only project, visit-locations, was moved to
                Projects/traceIQ/traceiq-rebuild by owner order 2026-08-25 (commit 557294c).
                Evidence.dev remains the decided reporting lane — see D-129 — but no
                platform-owned Evidence project has been re-established yet. Do not read the
                absence of analytics/ as the tool having been dropped.
deploy/         ONE compose file per Coolify application (S10, 2026-08-10, D-043): exec, gateway,
                contextforge, tool-runtime, sandbox, desktop, portkey, coolify-mcp, data-pg,
                data-neo4j, data-graphiti, data-graphiti-case, data-vector, data-weaviate,
                librechat, librechat-mongo, nocodb, workbench (.yaml each) — plus host-prep +
                security-fix history. Old root paths compose.<name>.yaml are dead on main;
                13 main-branch Coolify apps were repointed live the same day.
tool-skills/    agent-tool "skill" bundles (SKILL.md + scripts/) consumed by CLI agents
                directly, e.g. tool-skills/graphiti-client/ (`grc`), tool-skills/opencode-ops/
database/       (being retired) held SurrealDB schema DRAFTS, never applied. Its one file,
                00_analysis_graph.surql, was reviewed 2026-08-09 (~~TODO(OQ-7)~~, D-042):
                its design — horizon as row-level permissions bound to the agent record,
                an agent that can never widen its own horizon — was already absorbed in
                stronger form by ADR-0045/S6 (grants + derived pass corpora). Archived to
                `_stale/00_analysis_graph.surql.SUPERSEDED`; nothing left to port.
```

Progressive-disclosure detail (files, dependency direction, "how do I add X") for `server/` and
each of `contracts/`, `evidence/`, `tools/`, `agents/` now lives in that directory's own
`AGENTS.md` — this section stays the structural index, not restated blow-by-blow below.

## The record contract — `server/contracts/` (ADR-0035)

```
server/contracts/
  __init__.py     deliberately dependency-free (no sqlalchemy/agno/duckdb) — facade-safety, see below
  records.py      NormalizedRecord (bitemporal: occurred_at / knowledge_time / disclosure_tier / attrs), RecordType, DisclosureTier — the ONE canonical shape
```

Promoted out of `server/evidence/normalize.py` (Option A, owner-confirmed) because 15+ parser
modules + evidence internals + tests + the facade all import it — it's the platform's cross-domain
record contract, not an evidence-private type. Must stay import-light: the dep-light
`deploy/docker/tool-runtime` facade imports every parser, and every parser imports this. `server/core/` was
disqualified as the new home because `server/core/__init__.py` eagerly imports
`server.core.session` (sqlalchemy/agno/duckdb). See `server/contracts/AGENTS.md` and ADR-0035.

## The spine — `server/evidence/`

```
server/evidence/
  __init__.py     lazy (PEP 562) exports so light consumers don't drag in sqlalchemy/agno
                  (re-exports `registry`/`ToolRegistry` from server.tools.registry for back-compat)
  custody.py      THE single entry gate — hash → evidence row → write-once blob. ONLY writer of the `evidence` schema (append-only, immutable).
  normalize.py    DEPRECATED re-export shim (ADR-0035) — `from server.contracts.records import *`. New code imports server.contracts.records directly.
  store.py        normalized records → `analysis` schema + knowledge-engine ingest
  workflows.py    named workflows on native agno.workflow, custody-gated
  cli.py          `python -m server.evidence ...`
```

`tool_finder/` (the G4 gateway) moved to `server/tools/gateway/` in ADR-0035 — `evidence/` is now
purely the evidence bounded context. See `server/evidence/AGENTS.md`.

## The capability layer — `server/tools/` (D-026, sub-namespaced ADR-0035)

Cross-domain: consumed by evidence, analysis, agents, workflows, and the CLI — not owned by any
single domain, so it lives at the top level of `server/`, a sibling of `evidence/`, not nested
inside it.

```
server/tools/
  __init__.py            package marker
  registry.py             capability-based ToolRegistry (@register, load_builtin_tools —
                           pkgutil.walk_packages, recursive since ADR-0035 — over server.tools)
  _common.py               shared helpers (underscore prefix = NOT a tool; skipped by auto-discovery)
  _chatminer_adapter.py    ChatMiner -> NormalizedRecord bridge (underscore-prefixed)
  _sbv_client.py           SBV (SMS Backup & Restore) session-cookie REST client — shared by sbv_sms.py and the tool-runtime facade
  parsers/
    messaging/              imessage_*, sms_xml, sbv_sms, facebook_*, messaging_{csv,transcript}
    ai_chat/                 chatgpt_*, claude_*, gemini_*, perplexity_*
    generic/                  generic_md, whole_file_fallback
  extractors/               extract_text (capability extract.text)
  visualizers/              geo_map (capability viz.geo_map) + vendored Leaflet assets
  gateway/                  G4 token-efficient tool gateway (was server/evidence/tool_finder/) — content_store, toolfinder, api
```

Full file inventory, the capability model, and "how to add a parser" live in
`server/tools/AGENTS.md` — not restated here.

The `tool-runtime` facade (`deploy/docker/tool-runtime/tools/facade.py`) includes the
**whole `server/` tree** at `/opt/tools/server` — not just `server/tools/` — because
`server.tools.*` has real
transitive deps outside itself (`server.contracts.records` for the record schema,
`server.vendored.chatminer` for the parser core; both lightweight, no sqlalchemy/agno at import
time). The tree is baked into the image so Coolify deployments do not depend on relative bind
mounts. With `/opt/tools` on `sys.path`, the facade imports it as plain
`server.tools.registry` / `server.tools._sbv_client` — the same import path the main app uses —
see the facade's module docstring for the full image/import contract.

## Placement rules (where does X go?)

| You are adding… | It goes… |
|---|---|
| A new parser/extractor/visualizer tool (Python) | `server/tools/parsers/{messaging,ai_chat,generic}/<name>.py`, `server/tools/extractors/<name>.py`, or `server/tools/visualizers/<name>.py` (ADR-0035) — one capability, self-register via `@register`; `load_builtin_tools()` auto-discovers it, nothing else to wire |
| A tool that's really a TS/Go binary or external service | expose it behind a framework-neutral HTTP/MCP adapter; the current Agno adapter may consume it, but must not own its public contract |
| A shared helper (not itself a tool) | `server/tools/_helpers.py` (underscore prefix) or `server/evidence/<module>.py` (evidence-domain-specific) |
| A DB schema change | edit `sql/bootstrap/schema_snapshot_<date>.sql` in its final form, then `scripts/rebuild_platform_from_snapshot.sh` (no migrations, D-153) |
| A new service/container | `docker/<service>/` + a block in `compose.yaml` |
| A decision | an ADR in `docs/adr/` (supersede, don't edit) AND update `PROJECT_CANON.md` §5 same change |
| A stub you couldn't avoid | `# STUB: <tag>` in code + a row in `docs/DEBT.md` (ADR-0021) |
| A real-name / case-fact working file | `docs/private/` — gitignored; lives here, never committed, never redacted (owner ruling 2026-09-06; Claude Code · Sonnet) |

## Reference / read-only (never edit, never build inside)

> **WORKSPACE-ROOT-relative** — every path in this block is a sibling of this repo under the
> workspace root (see the workspace-root `CLAUDE.md`), reached via `../`, NOT a path inside this
> repo. Verified 2026-08-09: none of `dev-resources/`, `Agno-MCP-Platform-alpha/`, or
> `extracted-code/` exist under this repo's own root.

```
../dev-resources/Archives/
  dial-stack/                         TS forensic/analysis/gateway DONOR (DIAL runtime dropped; mine capabilities)
    utilities/                        DEFERRED external libs — "good stuff, dig later" (incl. apps/ml-nlp/Tether = Part-2 ML)
    docs/, .plannotator/, .planning/  CONTEXT only (markdown/prompts) — not code
  Agno-MCP-Platform-alpha/chatminer/  Python PARSER CORE to vendor into server/tools/
../extracted-code/                    mined reusable code (+ MANIFEST.md) — VERIFIED
                                       2026-08-09 (~~TODO(OQ-2)~~, D-042): exists at
                                       the-platform-workspace/extracted-code/, sibling
                                       of this repo; backup extracted-code.zip beside it
```

**Never ingest** `Secrets/` or case-data directories into Knowledge. Secrets live only in gitignored `.env` (local + VPS).
