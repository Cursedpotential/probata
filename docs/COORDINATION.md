# COORDINATION — multi-chat war room for ~~Agno-MCP-Platform~~ **Indicia Probata / `probata`** (renamed D-138, 2026-09-05; see `docs/NAMING.md`)

> _Byline: Claude Code · Fable 5 · 2026-07-08 (TODO/Ledger update: Claude Opus 4.8 · 2026-07-10)_
> _Byline amendment: Codex · GPT-5 · 2026-08-18 (combined-change hygiene)._
> _Byline amendment: Claude Code · Fable 5.1 · 2026-09-05 (naming canon sweep D-137..D-141)._
> **Purpose:** two (or more) Claude chats work this repo concurrently. This file is the
> shared ledger: who owns what, what's in flight, what's frozen, and handoffs. **Append,
> don't rewrite history** — add timestamped entries under your lane; strike (~~…~~) items
> you complete. Commit this file with your changes so the other lane sees it on pull.

> **2026-08-13 current-architecture correction:** historical lane entries below accurately
> describe the earlier ADR-0050 work, but their six-lane vocabulary is superseded by
> ADR-0053. Current vocabulary is five lanes; relationship history is inside
> `personal_history`, and `tuned=True` treats only `context` as the transcript lane.
> _Byline: Codex · GPT-5 · 2026-08-13._

## 2026-08-29 — AgentOS retirement implementation lane

_Owner: Codex · GPT-5.6-Sol. Source: `docs/HANDOFF-2026-08-29-agno-role-dissection.md`._

- **Locally implemented:** plain FastAPI host, zero-Agno startup import, runtime-file Platform API
  bearer, private `platform-api` service naming, Workbench caller/search/repair cutover,
  LibreChat tracked ContextForge/Portkey config, OpenCode ops, and activation preflight.
- **Release HOLD:** exec/Workbench/LibreChat are not live-proven on the cutover SHA. LibreChat is
  still branch-scoped and must be repointed from `infra/librechat` before a main-branch push can
  deploy its new image/config.
- **Protected concurrent files:** `example.env`,
  `docs/design/CLAIM-AND-ASSERTION-CANDIDATES-2026-08-29.md`, and
  `sql/0052_claim_and_assertion_candidates.sql` are outside this lane.
- **Next ordered slice after the host release is integrated:** replace Agno evidence workflows with
  Temporal-owned execution, then remove Agno Knowledge/provider/vector/session ownership.

## Lanes & ownership (as of 2026-07-08)

### LANE A — "Restructure" (this file created by Lane A)
**Scope:** repo structure + seed reconciliation. Branch: `restructure/option-a`.
- Tier 0/1 hygiene + planning consolidation (in flight)
- Seed reconciliation: read-only dump of live ontology → committed seed catches up
  (live drifted: behavior_category 153→164, detection_pattern 512→527); promote applied
  0005/0006 into `sql/`; retire the parallel P2.1 tables (`analysis_module`,
  `pattern_phrase`, `mcl_factor_ref`, `contradiction_rule` — never applied live)
- Tier 3 Option A code repack: `server/{api,core,agents,evidence,analysis,vendored}` —
  **moves every Python package; imports rewritten** (~200 sites)
- Contract rewrite (`docs/REPO_STRUCTURE.md`) + final HTML report with diagrams
- **Lane A does NOT touch:** ingestion/detection LOGIC, table schema design, live DB
  writes (read-only dumps only), `analytics/` (untracked, not Lane A's)

### LANE B — "Ingestion/table redesign" (the other chat)
**Scope (per owner):** table structure + question/ingestion workflow redesign — the
"solid brainstorm". Data in live PG stays frozen meanwhile.
- Owns: future schema of `analysis.*` ontology/finding tables, ingestion flow redesign,
  detection/analysis rework
- Untracked `analytics/visit-locations/` presumed Lane B / owner-local — Lane A won't touch
- **Requested of Lane B:** log your in-flight items below; avoid committing to `main`
  while Lane A's repack PR is open (or coordinate here first); after the repack merges,
  note that **import paths change** (`evidence.*` → `server.evidence.*` etc.)

### LANE C — "Infra/gateway" (Coolify + ContextForge + Portkey chat)
**Scope:** VPS/Coolify ops, ContextForge, Portkey/LiteLLM, MCP wiring, tailnet. Does NOT
touch repo structure, schema design, or ingestion logic. Repo footprint is minimal and
listed here so Lane A can carry it through the repack:
- **exec-tier Coolify app now deploys from `main`** (was `hotfix/agent-ui-lockfile`,
  repointed 2026-07-08 per owner). ⚠️ Any merge to main auto-redeploys the exec tier on
  ovh-app (gateway/CF/agentos/sandbox/desktop/agent-ui). When the Lane-A repack merges,
  expect that redeploy — and note `docker/` Dockerfiles COPY configs at build time
  (gateway bakes `docker/gateway/litellm-config.yaml`), so keep `docker/` paths stable or
  flag here.
- Lane C commits on main: `6ad0c25` (agent-ui Dockerfile pnpm9/OOM fix ported from the
  hotfix branch — main was unbuildable without it). On `hotfix/agent-ui-lockfile`:
  `740675b` (embed-text → nv-embed-v1). **Stray commit `6bcfddc` on
  `claude/ingestion-offline-work-hu8eud`** (Lane B's branch?) — same embed fix, landed
  there by accident mid-rebase; content harmless (touches only
  `docker/gateway/litellm-config.yaml`); drop or keep at Lane B's discretion.
- embed-text MUST stay `nvidia/nv-embed-v1` (4096-d): the graphiti Neo4j graph is
  embedded at 4096-d; any dim change breaks vector search (bit us twice).
- In flight: exec-tier redeploy-from-main verification (background watcher);
  Portkey routing configs pending an owner planning session.

### LANE D — "Knowledge/Memory redesign (ADR-0050)" — ACTIVE 2026-08-10→11 (smart-explore session)
**Scope:** the six-lane knowledge architecture + memory namespaces, owner-approved plan
(ADR-0050 Accepted). Executing phases in order; each phase ships to `main` when its tests pass.
- **SHIPPED on main already (pull before you commit):**
  - `e5297a9` audit(2026-08-09) S1-S5 + tonight's doc reconciliation
  - `106aacb` **S10 compose consolidation (D-043): root `compose.<name>.yaml` files MOVED to
    `deploy/<name>.yaml`** — 13 Coolify apps repointed live via API; root keeps only
    `compose.yaml` + `compose.data-surreal.yaml` (PARKED marker). Any doc/script that
    references old root compose paths is stale.
  - `2b37a4b` C1 done — `sql/bootstrap/schema_baseline.sql` regenerated from LIVE (verify
    PASS, 156 tables; live DB is FULLY migrated incl. ops.audit_ledger + working gate layer —
    the June "only 0001-0003 applied" fear is dead)
  - `5c27336` DEBT parser-lane **item 0**: ADR-0044 blob ban unenforced
    (`whole_file_fallback` reachable from evidence workflows) — assigned to **S7**; if your
    lane is the SBV/parser lane (ADR-0049), item 0 is probably yours — both fix options are
    written in `docs/DEBT.md`.
  - `a5e67d1` ADR-0050 Accepted + ADR-0020/0030 amendments (rclone = transport ONLY —
    owner emphatic; pg_duckdb = bulk-ingestion point)
  - `0b0402a` **Phase 1**: `get_postgres_db(contents_table=…)` now HONORED (per-table
    PostgresDb cache, all `id="agentos-db"`); `register_run_routes` grew an
    `evidence_knowledge=` param — **sms-xml workflow now vectors into `evidence_knowledge`,
    not the platform collection**; `store.py` `derived_dir` default moved to
    `data/derived/transcripts` (out of the ingest roots).
- **IN FLIGHT (Lane D owns these files — coordinate here before editing):**
  `server/core/session.py` · `server/api/main.py` · `server/api/run_routes.py` ·
  `server/evidence/store.py` · `scripts/ingest_knowledge.py` ·
  `server/analysis/context_chat_ingest.py` · (Phases 4-5) `server/agents/factory.py`,
  `server/agents/providers.py` · `docs/adr/0050-*`
- **Phase queue:** ~~2 = six-lane registry + unified `lane` vocabulary + re-ingest~~ **DONE
  2026-08-11** (`11929ed` + `8327bcb`): 6 lanes registered; `lane` vocabulary live (old domain
  values 422/raise); platform+legal collections dropped + re-ingested with new metadata
  (Platform_knowledge=208, Legal_knowledge=30 objects, live-verified); evidence stays 0 until
  the exec tier returns (custody is its only writer); Platform_context untouched (its ledgered
  ingest re-run is coordinated separately). **Your `chunking_policy.lane_chunker` seam is
  WIRED + LIVE-VERIFIED** — chunks land ≤1500 (RecursiveChunking baseline); note agno 2.8.6
  gotcha we hit: readers are lazy (`Knowledge._get_reader` caches on first use), so the
  wire-up pre-warms the reader cache — mutating `knowledge.readers` post-construction is a
  silent no-op. ~~3 = evidence horizon-gated retrieval seam~~ **DONE 2026-08-11** (`b283958` —
  `server/evidence/retrieval.py`, first live caller of audit.record_read; 7 tests);
  4 = agent→lane wiring — NEXT; 5 = memory namespaces; ~~6 = chunking baseline~~
  (your seam + our wire-up = shipped; the evals A/B harness remains); 7 = pg_duckdb staging.
- **Lane D does NOT touch:** SBV Go code (`vendored/sbv/`), parser modules
  (`server/tools/parsers/**`), ADR-0049 scope, sql/ migrations (additive staging migration in
  Phase 7 only).

## Hazards / heads-up board (2026-08-10→11 additions, Lane D)
- **Milvus (`data-vector`) — REBUILD IN PROGRESS (memsearch-only), 2026-08-12:** owner
  reframed the 08-10 "leave it down" ruling — Milvus is memsearch-ONLY (Agno stays on
  Weaviate, ADR-0040). Fresh Milvus v3 + Cloudflare R2 object store, image
  3.0-20260811-7169df25-amd64, fresh volume /data/agno/volumes/milvus-memsearch (now `/data/probata/volumes/milvus-memsearch` since the 2026-09-07 host-root rename) on ovh-files
  (ovh2). Do NOT restart the OLD app/config — it will crash-loop (6th etcd corruption,
  08-10); the rebuild uses a fresh volume + R2. See Lane C ledger entry (2026-08-12).
  Old volume /data/agno/volumes/milvus retired in place, NOT deleted. memsearch lane
  offline until re-index (task #6).
- **exec-tier is DOWN (OVH VPS 40.160.5.19 unreachable — bill)** — all exec Coolify apps
  `exited`; live end-to-end verification of anything API-side is blocked until the box
  returns. Phase 1 live verification is queued on this.
- **Weaviate/PG/Neo4j on ovh-files are UP and healthy** (verified 2026-08-10, incl. after the
  S10 push auto-redeployed the data apps on their new `deploy/` paths).
- **`get_postgres_db` semantics changed** (Phase 1): passing `contents_table` now returns a
  per-table instance instead of warning + returning the platform singleton. If your lane
  constructs PostgresDb or relies on the old warning behavior, re-check.
- Coolify apps now point at `deploy/<name>.yaml` on main. Workbench was repointed to
  `deploy/workbench.yaml` (including watch paths) and live-verified before `workbench/sprint`
  was fast-forwarded on 2026-08-13. **Merging main into `infra/librechat` or
  `infra/nocodb` will still silently break those branch-scoped deploys** unless their Coolify
  `docker_compose_location` is updated first (warning also in REPO_STRUCTURE.md, D-043).

## FROZEN (owner mandate, 2026-07-08)
- Live PG data: unchanged until the Lane-B brainstorm lands
- Ingestion + detection logic: as-is (structure moves it; behavior identical)

## Hazards / heads-up board
- **2026-07-08 (A):** repack will move every top-level Python package under `server/`.
  If Lane B edits `.py` files on main between now and the repack merge, say so HERE —
  Lane A will rebase and carry the edits through the move.
- **2026-07-08 (A):** live ontology drift (+11 categories, +15 patterns beyond committed
  0006) — being captured into the committed seed by Lane A, **content-faithful, no
  redesign** (redesign is Lane B's).
- **2026-07-08 (A):** sealed-lexicon rows: committed seeds keep `[REDACTED:]` placeholders
  ONLY; real values never enter git (0006 court-safety rule).

## TODO / carried tasks
- [x] ~~**CHANGELOG backfill**~~ — done on branch `docs/changelog-backfill`, folded into
  `docs/autonomous-doc-sync` (`9fd032c`); `CHANGELOG.md` now carries the full backfilled history
  (`ac14385`) plus a corrected `[Unreleased]` section.
- [ ] **Cloudflare global API key rotation** (owner-only; leaked in old repos, redacted 2026-07-04).
- [ ] **Lane C:** confirm n8n isn't deployed from the old `deploy/n8n/` path (now `docker/n8n/`).
- [x] ~~**SBV Phase 5a — native Go automation endpoints**~~ — BUILT, not shipped: `POST
  /api/automation/extract` + `status`/`export`/`backups` implemented in the SBV fork on branch
  `worktree-agent-abe280ccbefefe136` (`813f3b2`), custody ordering preserved (H1 → parse/H2/H3 →
  record). Not yet pushed through the locked subtree → fork → CI → tag-bump sequence, so it isn't
  live — see `docs/planning/sbv-fork-plan.md` §5a before shipping.
- [ ] **SBV Phase 5b — storage-free `/evidence/preview` client inside Workbench** (supersedes the
  older `/x/sbv/` embed framing; owner ruling + accepted ADR-0061, 2026-08-29): Workbench owns shell,
  fixed case context, and Authentik/Traefik boundary. SBV retains message and pipeline-preview UX but
  loses SQLite/auth/ingest/canonical ownership. Use same-origin routing; the proxy choice is no longer
  open. Retained source XML, not lossy SQLite MMS blobs, is the migration authority.
- [x] ~~**SBV — run the ContextForge registration**~~ — DONE 2026-07-10: all 14 facade tools
  (`docker/tools/tools/facade.py`) registered directly as ContextForge REST tools in a 5th virtual
  server `platform_tools`, alongside the existing `agno`/`coolify`/`graphiti`/`exa` servers. (This
  superseded running `scripts/register_sbv_contextforge.sh` as originally planned — see the
  FACADE COLLAPSE entry below for why the facade-REST-wrap path won instead of an MCP repoint.)
- [ ] **restore-heic — FIND A BETTER SOLUTION** (owner: wants HEIC functional someday, DOWN THE ROAD,
  not urgent). Today the SBV fork image (`v0.2.3-forensic`) has the `heic` tag DROPPED because pinned
  `strukturag/libheif-go@20250130` no longer compiles vs current Alpine libheif (CGO enum drift). HEIC
  attachment BYTES are still ingested + custody-hashed; only in-app HEIC transcode/display is off.
  Owner wants a ROBUST long-term fix, not a brittle version pin. Options to explore (best→worth-trying):
  - (a) **Decouple HEIC from SBV's build entirely** — transcode HEIC→JPEG via a separate path (ffmpeg
    is already in the platform-tools image; or a standalone `heif-convert`/libheif CLI, or a small
    media-conversion tool/app) so SBV never needs the fragile CGO libheif binding. Cleanest, most durable.
  - (b) bump `strukturag/libheif-go` to a version matching current Alpine libheif (may break SBV's
    `heic_enabled.go` if the binding API changed — test).
  - (c) pin a compatible libheif + libheif-go PAIR in `vendored/sbv/Dockerfile` (brittle; ties us to
    an old Alpine).
  Whichever: re-add `-tags "fts5 heic"` (or route HEIC around it), rebuild the fork image, bump the tag
  in `docker/tools/Dockerfile`. NOTE: this also relates to the broader media pipeline (HEIC/3GP/AMR/etc.
  from iPhone MMS = real forensic evidence), so a general media-conversion capability may be the right
  home rather than SBV-internal HEIC.
- [x] **FACADE COLLAPSE — Batches B/C now MOOT, the facade STAYS** (corrected 2026-07-10). Batch A
  (add the G4 gateway + SBV toolkit as agno `@tool`s) was built, merged, and deployed (`bec5596`).
  This item's original premise — that `enable_mcp_server` re-exports granular `@tool` functions
  over `agentos-mcp`, so ContextForge could be repointed there (Batch B) and the facade removed
  (Batch C) — was **DISPROVEN 2026-07-10**: verified from agno source (`agno/os/app.py:588-595`),
  AgentOS's MCP surface only ever exposes ~19 AgentOS *operations*, never the parser/SBV `@tool`s.
  The facade therefore stays as the only granular-tool MCP surface; all 14 facade tools were
  instead registered directly in ContextForge as REST tools (see the "SBV — run the ContextForge
  registration" entry above). Full corrected plan + superseded banner:
  `docs/planning/facade-collapse-plan.md`.
- [x] ~~**SEMANTICA MOVE**~~ — done on `restructure/semantica-vendor` (branch, not merged); see Ledger
  entry below. Landed as a **`git mv` relocate**, not a subtree add (see rationale in the entry) —
  correcting this line item's original "subtree" wording.

## SBV build path (LOCKED 2026-07-09) — do NOT rebuild SBV from source in the exec tier

> **Target-boundary amendment, 2026-08-29:** this locked build path describes the current legacy
> self-contained SBV artifact. It does not authorize preserving SQLite, local auth, or bespoke ingest.
> The cutover separates the storage-free client from the common Go parser/custody pipeline; obsolete
> artifacts are quarantined only after complete XML re-ingest and live Workbench preview proof.

The SBV app is built by **GitHub Actions in the fork** `Cursedpotential/sbv-forensic` (workflow
`docker-build.yml`, publishes `ghcr.io/cursedpotential/sbv-forensic:<tag>`), because the 4CPU/8GB exec
box can't/shouldn't compile Go+CGO+node. `docker/tools/Dockerfile` LIFTS the binary via
`FROM ghcr.io/cursedpotential/sbv-forensic:<tag> AS sbv`. To ship SBV source changes: edit
`vendored/sbv/**` → `git subtree split --prefix=vendored/sbv` → force-push to fork `main` + a `v*.*.*`
tag → CI builds → bump the tag in `docker/tools/Dockerfile`. Image name MUST be lowercase (hardcoded
`cursedpotential/sbv-forensic` in the workflow — `${{ github.repository }}`'s capital C breaks the push).

## Ledger (append below; newest on top)
- **2026-08-12 — LANE C: Milvus memsearch-only REBUILD (gated → deploying):** owner
  reframed the 08-10 "leave it down" ruling — Milvus is **memsearch ONLY** (Agno platform
  stays on Weaviate, ADR-0040). Fresh Milvus v3 standalone (embedded etcd, fresh) +
  Cloudflare R2 object store, on ovh-files (100.91.190.107). Image pinned to
  3.0-20260811-7169df25-amd64 (dated, explicit amd64). Compose config embedded via
  `configs:` (no host bind-mount → no SSH to edit). R2 bucket `milvus-memsearch` created;
  creds set as Coolify app envs. LOCAL access = claude-context stdio MCP hits Milvus
  DIRECTLY over tailnet (bypasses ContextForge); embeddings via NVIDIA OpenAI-compatible
  endpoint (not OpenAI). Web/ContextForge facade DEFERRED. Commit: deploy/data-vector.yaml
  + docker/milvus/{embedEtcd,user}.yaml only — no schema/ingestion/structure files.
  Follow-on (separate gates): #6 repoint+re-index memsearch from ~89 journals; #7 fix the
  broken claude-context stdio entry (MILVUS_ADDRESS=100.91.190.107:19530 + token +
  OPENAI_BASE_URL=integrate.api.nvidia.com/v1). — _Claude Code · Fable 5 · 2026-08-12_
- **2026-08-12 — CONTEXT ingest went PG-first (PARSER/CHUNKING lane · D-048):** owner ruling
  "it's all supposed to go back into pg And then change detection will move it into vector db."
  `server/analysis/context_chat_ingest.py` no longer dual-writes chat chunks straight to Weaviate/
  Graphiti — it now writes **`working.context_record`** (new source-of-truth table, migration
  `sql/0021`, **Option B = separate table, NO evidence FK** so context stays out of the evidence
  spine; ~~source-of-truth~~ — **superseded 2026-08-13 by ADR-0053** (chat_conversation/message/chunk;
  see CHANGE-ORDER CH-4); context_record is retained as a legacy row but no longer the SoT for the
  chat lane) then `sync_pending_context(sink)` projects pending rows (`*_synced_at IS NULL`) to the
  `platform_context` Weaviate collection + the Graphiti CASE lane. SQLite `IngestLedger` retired
  (PG `content_hash` UNIQUE + `*_synced_at` are the dedup/sync authority). 20/20 tests pass.
  **APPLIED to live** (0021 committed to the DB, table present) + **batch-drain tool built**:
  registered capability `ingest.context-drain` (`server/tools/ingest/context_drain.py`) + CLI
  `scripts/drain_context.py` — the manual "project pending rows now" trigger until the CDC worker
  exists (owner: "written as a tool ... so we can easily trigger that batch process"). **KB-STRUCTURE
  lane:** this touches only the CONTEXT write path + a NEW
  `working.*` table + parser-lane docs (ADR-0051 current-reality, DECISION_LOG, this ledger) — it
  does NOT edit your six-lane KB-structure files or the `ai.*` contents tables.
- **2026-07-10 — DOCUMENTATION SYNC (branch `docs/autonomous-doc-sync`):** AGENTS.md
  progressive-disclosure reconfiguration after ADR-0033/0035 left the root `AGENTS.md`
  describing the pre-repack flat-package layout and promising per-directory `README.md`
  files that never existed. Rewrote root `AGENTS.md` as a concise map (`server/*` layout,
  `## Commands` table, closest-file-wins pointer) and added 5 nested `AGENTS.md` drill-downs:
  `server/AGENTS.md` (dependency direction), `server/tools/AGENTS.md` (registry + "how to add
  a parser"), `server/evidence/AGENTS.md`, `server/agents/AGENTS.md`, `server/contracts/AGENTS.md`
  (facade-safety rule). Reconciled `docs/COORDINATION.md` (this entry + the TODO closures above),
  `docs/DECISION_LOG.md`, `docs/adr/README.md` (added the missing ADR-0033 index row), and
  `docs/REPO_STRUCTURE.md` (ADR-0035 tree: `contracts/`, sub-namespaced `tools/`, `gateway/`).
  Fixed a stale comment in `docker/tools/Dockerfile` (said `server.evidence.registry`, real import
  is `server.tools.registry`). Doc-only; gates re-run to confirm no regression.
- **2026-07-10 — ADR-0035 EXECUTED, MERGED, DEPLOYED:** tools sub-namespacing
  (`parsers/{messaging,ai_chat,generic}/`, `extractors/`), G4 gateway extraction
  (`server/evidence/tool_finder/` → `server/tools/gateway/`), and the record contract's new home
  (Option A, `server/contracts/records.py`; `server/evidence/normalize.py` now a deprecated
  re-export shim). Merged to `main` (`8240205`), deployed to the exec tier, verified healthy
  (facade `/health` 23 tools, `agentos-api :8000/health` 200, `agentos-mcp` up). Behavior-neutral:
  23 tool IDs unchanged, no ContextForge re-registration needed. Gates green: ruff/mypy/pytest 208.
  Full as-built record: `docs/adr/0035-tools-subnamespacing-and-record-contract-home.md` (Outcome
  section).
- **2026-07-09 — FORENSIC GUARD: no fabricated timestamps (branch
  `test/forensic-no-fabricated-timestamps`):** `tests/test_no_fabricated_timestamps.py` AST-scans
  every parser/extractor module and fails on any wall-clock call (`datetime.now/utcnow/today`,
  `date.today`, `time.time`), plus a behavioral check that `imessage._parse_ts` returns `None`
  (never `now()`) on unparseable input. Encodes the parser-inventory finding that TS-lineage
  parsers fabricate event times while the Python lane preserves the raw value. Not yet merged.
- **2026-07-09 (A) — FACADE COLLAPSE BATCH A (branch, not merged):** built Batch A of
  `docs/planning/facade-collapse-plan.md` on `feature/facade-collapse-batch-a` (off `main`) —
  the additive half of the FACADE COLLAPSE TODO (line ~98). **Does NOT close that TODO**;
  only Batch A of 3 (Batch B repoints ContextForge, Batch C removes the facade — both still
  gated on live deploy verification per the plan §6). New `server/agents/tools/` package:
  `gateway_tools.py` (5 agno `@tool` wrappers over the G4 progressive-disclosure meta-ops,
  `server/evidence/tool_finder/toolfinder.py` — `get_tool_categories`, `search_tools`,
  `describe_tool`, `execute_tool`, `get_ref`) and `sbv_tools.py` (11 agno `@tool` wrappers
  over `SBVClient`, `server/tools/_sbv_client.py` — mirrors the old facade's `/sbv/*` proxy
  surface, PLUS `sbv_hashes` which exposes the H1/H3 forensic custody hashes that
  `SBVClient.hashes()` already had but the facade never routed — the custody chain is the
  whole point of the SBV fork). Both wired into `source_tools` in
  `server/agents/providers.py:169` (one import + one list-splice, same append pattern already
  used for Graphiti), so every agent built off `PlatformContext` — and therefore
  `agentos-mcp`'s MCP surface — picks them up with zero other file changes.
  **Error convention (OQ-8) resolved:** neither module catches/re-shapes exceptions into an
  `{"error": ...}` dict. Both let exceptions propagate (`KeyError`/`ValueError` from the
  registry/toolfinder layer, `SBVError` from `SBVClient`) — this matches the convention
  already dominant one layer down (`server/tools/*.py`, `server/evidence/tool_finder/`, which
  raise and document raising), and agno's own `Function.execute()` already catches any
  exception raised inside a `@tool` entrypoint and reports a structured
  `status="failure"` result to the calling agent — so re-catching here would only throw that
  signal away. The codebase's other `@tool` (`apply_db_modification`, `factory.py`) uses a
  string-prefixed `"ERROR: ..."` return instead, but that's a different tool shape (a
  HITL-approval-gated write reporting a tri-state OK/REJECTED/ERROR outcome), not a precedent
  for these read-only, dict/list-returning tools.
  `deploy/exec.yaml` (S10 path; `agentos-api` + `agentos-mcp` env blocks) and `compose.yaml`
  (`agentos-api` only — no `agentos-mcp` service exists in the local/dev compose) both get
  `SBV_BASE_URL` (defaults to `http://platform-tools:8085`, the docker-network hostname —
  `_sbv_client.py`'s own default of `localhost:8085` is wrong from inside these containers),
  `SBV_SERVICE_USER`, `SBV_SERVICE_PASS`, ~~`SBV_PRIMARY_ENABLED` (default UNSET — SBV demoted to
  shadow 2026-08-02, gap-review P0-1; setting it re-enables SBV auto-selection and is an owner
  decision)~~ — **CORRECTED 2026-08-10: `SBV_PRIMARY_ENABLED` is INERT.** The 2026-08-02 demotion
  was lifted when PR #18 (`aacf21c`, 2026-08-06) delivered its restore condition; SBV is PRIMARY
  again per DECISION_LOG D-040, `_sbv_enabled()` gates only on `SBV_SERVICE_PASS`, and
  `tests/test_sbv_demotion.py` pins that this env var no longer gates anything. It is still
  declared in `compose.yaml` / `deploy/exec.yaml` but has no effect — removing it is an owner
  call (deploy-config change). `SBV_SERVICE_PASS` is now the only switch that decides whether
  SBV is selected. — _Claude Code · Opus 5 · 2026-08-10_
  On the exec tier `SBV_SERVICE_PASS` is a **hard**
  `${SBV_SERVICE_PASS:?...}` per the plan (unset = container won't start, checked BEFORE
  merging); on local/dev it's a soft `${SBV_SERVICE_PASS:-}` default (matches every other
  local-compose secret, none of which are hard-required there) — a judgment call, not
  explicitly specified by the plan for the local file.
  Tests: `tests/test_gateway_tools.py` (9 tests) + `tests/test_sbv_tools.py` (11 tests, incl.
  a CSV/JSON shape-parity regression test for the ported `sbv_export` synthesis logic —
  the one piece of real business logic moving, not just re-plumbing) — mock `SBVClient`
  entirely, no live SBV dependency. Gates on the branch: `ruff format`/`ruff check` clean,
  `mypy` clean (112 files), `pytest` 208 passed (191 baseline + 17 new — up, not down).
  **Deploy-only, cannot be verified from the repo:** whether `agentos-mcp`'s MCP `tools/list`
  actually surfaces these 16 tools over the wire once this merges (FastMCP standalone-app
  extraction is an integration property unit tests don't exercise — plan §1.4/§6 Batch-A
  post-deploy gate) — do not proceed to Batch B/C until that's confirmed. Facade
  (`docker/tools/tools/facade.py`) untouched this batch, exactly as scoped. Branch NOT
  merged — pushed to origin for a watched-deploy review before Batch B/C proceed.
- **2026-07-09 (A) — SEMANTICA VENDOR MOVE (branch, not merged):** ADR-0033 amendment
  ("2026-07-09b") on `restructure/semantica-vendor` (off `main`): relocated
  `docs/wiki/tools/semantica/` (12MB, 615 tracked files) to `server/vendored/semantica/` via
  `git mv` — **NOT** a `git subtree add`. Rationale: our vendored copy is a modified snapshot
  (`pyproject` says `0.3.0-alpha`, `__init__.py` says `0.2.7`, no `README.md` despite
  `pyproject` declaring one) that diverges from upstream HEAD; the discoverable upstream URL
  (`github.com/Hawksight-AI/semantica` in `mkdocs.yml`/`FUNDING.yml`) could not be reliably
  confirmed as canonical (a WebFetch resolved a *different* org, `semantica-agi/semantica` —
  unverified, possible org-rename or fetch noise); `server/analysis/semantica_wiring.py`
  hard-codes config-key names that an upstream version bump could silently rename; and the
  chatminer precedent (same vendored/ class) was itself a plain relocate, no subtree/remote.
  A future live-upstream adoption is a **separate, deliberate upgrade** (verify the real
  remote first) — appendix commands left in the ADR amendment, not run here.
  Symlinked `docs/semantica` → `../server/vendored/semantica/docs` and
  `docs/semantica-benchmarks` → `../server/vendored/semantica/benchmarks`, git-tracked as real
  mode-`120000` symlink blobs (via `git update-index --cacheinfo 120000`, since this dev
  sandbox has `core.symlinks=false` and no Developer-Mode/admin symlink privilege — the
  working tree here shows plain text placeholder files, but the git objects are correct and
  Linux checkouts/CI/containers will resolve them as functional symlinks).
  `server/vendored/` excluded from ruff+mypy (`pyproject.toml`, closing a latent gap where
  chatminer was previously unexcluded too) and added to pytest `norecursedirs` — semantica's
  test suite pulls heavy ML deps (torch/spacy/transformers, present even in its "safe
  default" install) that aren't in our env, so it stays **opt-in only**
  (`uv pip install -e "server/vendored/semantica[dev]"` then
  `uv run pytest server/vendored/semantica/tests`), never in the default run. Nothing in-tree
  imports semantica yet — behavior-neutral. Gates: see commit message for the exact numbers
  from this run. Branch NOT merged — pushed to origin for review only.
- **2026-07-09 (A) — TOOLS LAYER PROMOTED (branch, not merged):** D-026 / ADR-0033 amendment on
  `restructure/tools-layer` (off `main`, post-repack): moved the atomic-tools capability layer +
  registry OUT of the evidence spine to a top-level `server/tools/` (cross-domain — evidence,
  analysis, agents, workflows, and the CLI all consume it). `git mv server/evidence/tools
  server/tools`; `git mv server/evidence/registry.py server/tools/registry.py`; registry
  auto-discovery made package-name-agnostic + intra-package imports relativized. Also fixed a
  LIVE mount regression: `compose.yaml`/`deploy/exec.yaml` (S10 path) still mounted
  `./evidence:/opt/tools/evidence:ro` for the `docker/tools` platform-tools facade — that host
  dir stopped existing the moment the D-025 repack landed, so the facade was serving **zero**
  parser modules. Now mounts the WHOLE `server/` tree (`./server:/opt/tools/server:ro`, not just
  `server/tools/` — `server.tools.*` transitively needs `server.evidence.normalize` +
  `server.vendored.chatminer`, both lightweight), with `docker/tools/tools/facade.py` importing
  plain `server.tools.registry`/`server.tools._sbv_client`, same as the main app. Verified via an
  isolated-Python simulation of the container's real import graph (not the repo venv, which has
  `server` editable-installed and would mask the bug) — loads all 23 tools.
  **⚠ ALL LANES: import paths changed AGAIN** — `server.evidence.tools.*` → `server.tools.*`,
  `server.evidence.registry` → `server.tools.registry`; rebase before further `.py` work. Gates
  GREEN: ruff clean, mypy clean, **pytest 186**. Branch NOT merged (merge auto-deploys exec
  tier, D-011) — pushed to origin for review only.
- **2026-07-09 (A) — REPACK EXECUTED (branch, not merged):** ADR-0033 `server/` repack done on
  `restructure/option-a`. Every backend package now under `server/{api,core,agents,evidence,
  analysis,vendored/chatminer}`; imports are `server.*`. 152 files, 240 import rewrites; fixed
  path-depth (`patterns.py::_REPO`, chatminer sys.path), string-module refs (registry loops,
  `evidence/__init__` lazy map, test monkeypatches), config split (analysis configs →
  `server/analysis/config/`), entrypoint (`server.api.main:app` in Dockerfile+compose×3),
  pyproject packages+mypy. Gates GREEN: ruff, mypy (106), pytest (186). **⚠ ALL LANES: import
  paths changed — rebase onto this before further `.py` work.** `podman build` proof + merge
  DEFERRED (owner configs podman later; merge auto-deploys exec tier → needs the watched window).
  Reproducible via `scripts/repack_to_server_layout.py`.
- **2026-07-09 (A):** owner decided the open questions (while driving). DONE on
  `restructure/option-a`: `visualizations/`→`docs/visualizations/`; `configs/`→`docker/milvus/`;
  `deploy/n8n/`→`docker/n8n/` (compose mounts Milvus configs from absolute VPS host paths, so
  these are DEPLOY-NEUTRAL — no re-up needed; scp comment repointed). **Lane C: confirm n8n
  isn't deployed from the old `deploy/n8n/` path.** DECISIONS: repack = Option A (full `server/`)
  LOCKED; UI/G1 DEFERRED (repack proceeds in its own coordinated window, not racing the shell);
  `shared/` deferred. Repack still NOT executed — pending the keyboard-present window. Branch not
  merged (merge = exec-tier auto-deploy; owner is driving).
- **2026-07-09 (A→C):** the old untracked `.planning/build/` = **live architecture directives**
  (owner: "most of that was good directives"), now committed at
  `docs/planning/architecture-directives/` (+ `INDEX.md` mapping each doc to a lane). These are
  YOUR infra directives (ContextForge/SurrealDB/DNS/Traefik/topology) — reconcile against what's
  now live (CF v1.0.4, Portkey, coolify-mcp), capture deltas as ADRs. Not archive, not stale.
- **2026-07-08 late (C):** coolify-write MCP deployed as HTTP service. NEW Lane-C files on
  `main`: `deploy/coolify-mcp.yaml` (S10 path) + `docker/coolify-mcp/` (server.py/requirements/Dockerfile
  — patched repo copy of the local stdio skill; keep paths stable through the repack, same as
  `docker/gateway`). Commits `82cd8c8` + `c6e3e66` (Host-check fix). New Coolify app
  `coolify-mcp` (uuid `oyzznioap03u34xz125l90oq`, ovh-app, tailnet-only 100.72.169.40:8765,
  token via app envs — never in git). CF gateway `coolify-write`
  (`fe0789de7cdb47cc9bec10eb7a0ddfc0`, transport STREAMABLEHTTP — CF defaults to SSE and hangs
  on streamable-http servers without the explicit field). `coolify` virtual server
  (`d8a45fe53fa4415cadfb3982d9026d43`) re-pointed 10 read tools → 14 coolify-write tools
  (read names mirrored, so callers keep working); verified end-to-end (initialize/tools-list/
  list-projects with real data). Old read-only `coolify` gateway
  (`5a2c512b6e0e43bfa62471a9461ad83f` → 100.98.98.38:8000/mcp) left registered but now
  REDUNDANT (doors policy). ⚠️ Reminder: any push to `main` auto-redeploys exec-tier AND
  the webhooked coolify-mcp/portkey/data-* apps.
- **2026-07-08 (A):** SEED RECONCILIATION RESOLVED — no action needed: live (164/527) ==
  exact `0007` prefix of Lane B's committed migration chain (0006+0007+0008);
  `evidence/patterns.py` chain validator OK; corpus fully homed (0 missing); only the 4
  contradiction rules remain unhomed (pending owner table decision). My earlier "drift"
  read compared live against 0006 alone — wrong baseline, withdrawn. Full gates green
  (186 tests) + live smoke ALL-PASS (PG ontology/source/detection-dry-run, Milvus,
  wiring). Added `scripts/dump_live_ontology.py` (read-only → gitignored `live-dumps/`).
  NEXT: Tier 3 Option A repack — built and gated ON BRANCH `restructure/option-a`,
  **NOT merged** (Lane C: main auto-deploys the exec tier; merge needs owner + Lane C go,
  Docker paths move in lockstep in the same commit).
- **2026-07-08 (C):** CF v1.0.4 live + federation verified (41 tools / 4 gateways); graphiti
  hostfix sidecar (`0f2cd16`); graphiti CF virtual server + Claude Code rewire (restart
  pending); Portkey 1.15.2 live on ovh-app:8787; exec-tier repointed hotfix→main + agent-ui
  Dockerfile fix ported (`6ad0c25`); redeploy-from-main verification in flight.
- **2026-07-08 ~AM (A):** Tier 0/1 done on `restructure/option-a` (dead venvs deleted,
  recall fragments → `../_stale/repo-recall-fragments-2026-07-08/`, goals/.planning/plans
  consolidated into `docs/planning/`). Next: seed reconciliation (read-only vs live), then
  Tier 3 repack. Final deliverable: illustrated HTML report in `docs/planning/`.

## 2026-08-11 — Lanes now: KB-STRUCTURE chat + PARSER/CHUNKING chat (this one)

> Owner 2026-08-10/11: "the team is you + me + the other chat." The other chat is **strictly
> KB-based structure** (six-lane ADR-0050 build). THIS chat owns the **parser + chunking** lane.
> Nothing is live yet — correctness first, get it deployable soon. Owner will have the KB chat log
> its own entry; below is the parser/chunking lane so we don't collide.

### KB-STRUCTURE lane (the other chat) — DO NOT edit these from the parser/chunking chat
Owns the six-lane KB build (ADR-0050 + `plans/…glittery-summit`): `server/core/session.py`
(per-contents-table PG cache — DONE `0b0402a`), `server/api/main.py` knowledge handles,
`server/evidence/store.py` lane vocabulary + `ingest_into_knowledge`, `create_knowledge` /
`KnowledgeHandle`, evidence retrieval seam, agent→lane wiring. **Committed so far:** Phase 0
`a5e67d1` (ADR-0050 accepted), Phase 1 `0b0402a` (stop evidence/platform conflation). Phases 2–4
(six-lane vocab in store.py, re-ingest, retrieval seam, agent→lane) are theirs and NOT done yet.

### PARSER / CHUNKING lane (this chat) — what I own + committed
- **Parser lane (ADR-0049/0048 docs):** SBV = universal parser; corrected SBV-shadow drift;
  ADR-0051 (ingest pipeline: parse→[PG change-detection]→extract→HITL); DEBT 0b (Python SMS parser
  iterative+spill). Commits `3a156bf`→`9c8d329`, D-045.
- **Chunking lane (Phase 6 — independent):** Chonkie installed torch-free (`chonkie 1.7.0`,
  `chonkie[semantic,code,table]`, model2vec, NO torch); wrapped as Agno `ChunkingStrategy` in
  `server/analysis/chonkie_chunkers.py` (CPU-friendly local; Neural/Late/Slumber = remote-MCP
  stubs that RAISE, never local torch — D-046). Commits `1c7e95b`+`849c1d0`.
- **THE SEAM for the KB lane to consume:** `server/analysis/chunking_policy.py` →
  `lane_chunker(lane, tuned=False)`. Baseline = Agno-native `RecursiveChunking` (**no chonkie
  dep** — adopt today); `tuned=True` gives transcript lanes (context, relationship_timeline) the
  Chonkie semantic+fixed hybrid. **KB chat: import this in `create_knowledge` for Phase 6 instead
  of hardcoding a chunker** — that's the clean handoff, no file collision.
- **Not colliding:** I only touch `server/analysis/{chonkie_chunkers,chunking_policy}.py`, `tests/`,
  and parser/chunking docs. I do NOT edit the KB-structure files above.
- **Next in my lane (non-colliding):** chonkie[api]→MCP tool; remote GPU executor (Colab/RunPod
  scale-to-zero) for the heavy chunkers; add `chonkie[semantic,code,table]` to requirements via
  proper lockfile regen. Follow-up: Docling (separate).

## 2026-08-15 — Current framework-neutral migration lanes

> _Byline: Codex · GPT-5 · 2026-08-15. Append-only status block; it does not rewrite the
> historical lane record above._

| Lane | Current boundary | State |
|---|---|---|
| R0 Wave-1 | Audit/salvage only; migrations `0026–0029` remain held | Complete audit; build gate failed |
| R1 Go | Decoder-coverage routing, bounded ordered parallelism, custody equivalence | Partial |
| R2 Horizon | Immutable manifests, replay, quarantine, store prefilters | Partial; no cutover |
| R3 Semantica | VIP semantic intelligence with governed candidate/provenance boundary | Partial; no production worker claim |
| R4 Memory | PostgreSQL belief events → per-run Graphiti projection | Research complete; implementation pending |
| R5 Runtime | Current Agno adapter versus bounded AG2 candidate spike | No AG2 runtime cutover |
| R6 Providers | Platform route registry over Portkey/OpenCode/authorized direct paths | Research complete |
| R7 Workspace | Persistent OpenCode control plus isolated execution jobs | Partial |
| R8 Workbench | Custom framework-neutral operator product | Partial |
| R9 Matter MVP | Matter/CourtCase, source resolution, unsafe promotion, custody inspection, read-only court readiness | Built/tested and pushed; readiness `7b6aaf6`; migration unapplied, undeployed |

Cross-lane invariant: Knowledge ingestion remains horizon-blind and independent from agent
horizon replay. Graphiti stores derived run-scoped beliefs, not canonical evidence. AG2 is a
candidate adapter only. No lane may claim a local build is live without deployment proof.

## 2026-08-15 — R10 Surreal analytical memory and investigation design

> _Byline: Codex · GPT-5 · 2026-08-15. Documentation/decision capture only._

| Lane | Boundary | State |
|---|---|---|
| R10A Surreal | Governed analytical projection + experimental Spectron-compatible walk memory; PG remains authority | Accepted design; no activation |
| R10B Facts | Candidate-driven federated evidence assembly → reviewed immutable fact subgraphs | Accepted design; no schema |
| R10C Investigation | Find Evidence, Reconstruct Event, Discover Patterns | Accepted product target; no implementation |
| R10D Behavior | Frozen scopes, bounded outward discovery, hindsight/as-lived/paired modes, internal pattern lenses | Accepted product target; no implementation |
| R10E Retrieval | Source-aware chunks, multi-axis routing, versioned isolated embedding profiles, rank fusion + reranking | Proposed contracts; bake-off required |

R10 must not leapfrog the R9 activation gates or silently repurpose the parked legacy Surreal
deployment. ~~Graphiti remains the baseline until an observed bake-off.~~ Exact Surreal isolation,
physical schemas, embedding profiles, TraceIQ projection, behavior taxonomy/budgets, and exclusive
walk-agent retrieval remain owner decisions.

> **Memory-substrate correction — Claude · Opus 5 · 2026-08-29, owner ruling.** The "Graphiti
> remains the baseline until an observed bake-off" sentence above is **void**. Graphiti was retired
> by owner order on 2026-08-27 (P-09 / GAP-008 retired-Graphiti zero-caller path: "Graphiti is
> retired, the target is zero callers, there is no replacement store, and no new ledger is
> authorized"). **There is no baseline to bake off against and no bake-off is pending.** Owner,
> 2026-08-29: *"Every time I try to deploy it, it doesn't work right."* Graphiti is not a
> dependency, not a gate, and must not appear as a blocker in any lane.
>
> **Where memory/graph work actually lives now (owner, 2026-08-29):**
> - **PostgreSQL** remains the belief/canonical authority. Unchanged.
> - **SurrealDB** is the governed analytical/walk projection lane (R10/R11) — already the route of
>   record for bringing this together.
> - **Two temporally-aware RAG paths** are in use. Both remain in service; neither depends on
>   Graphiti.
> - **Memgraph** is a named candidate, discussed repeatedly, for the graph tier. Not selected, not
>   scheduled, not blocking.
> - **The agent-layer implementation of all of the above is explicitly DEFERRED** by owner ruling —
>   "it can wait." Deferred is not blocked: no lane may cite agent-memory work as its gate.

## 2026-08-16 — R11 Surreal investigation Phase 0 review package

> _Byline: Codex · GPT-5 · 2026-08-16. Contracts/evaluation/test-only lane._

| Deliverable | State |
|---|---|
| Logical data/service contracts | Complete for owner review; no physical schema |
| Unresolved-question inventory | 33 routed questions; none silently resolved |
| Gold/evaluation specification | Complete; T0 synthetic only, T1/T2 not authorized |
| Planted-future-fact canary | 14 synthetic contract tests pass; no live adapter proof |
| Owner packet | Six immediate choices S1–S6 pending; empirical/later choices deferred |

R11 changed no application, database, migration, deployment, corpus, or service state. The parked
Surreal deployment was not contacted. Phase 1 and every R9 activation hold remain in force.

## 2026-08-18 — R14/ADR-0059 source-clock and resumable-walk correction

> _Byline: Codex · GPT-5 · 2026-08-18. Append-only status block; it does not rewrite the
> historical R10/R11 observations above._

| Boundary | Current contract/state |
|---|---|
| Authorship | One canonical normalized message spine; first-party and acquired-third-party tables are derived projections only |
| Temporal | First-party `source_available_from=occurred_at`; acquired-third-party `source_available_from=acquired_at`; zero-to-many realization links remain separate |
| Attribution | Acquired threads retain actual sender/recipients/participants; owner absent from participants |
| Chunking | Chunks/embeddings are derived from the correct source-class projection and inherit its source boundary |
| Healthy walk | Exact checkpoint resumes the same identity only with equal projection/state/trace/belief/retrieval references |
| Terminal walk | Drift/revocation/mismatch seals immutable non-resumable state and requires an exact linked `rewalk_of` |
| Execution | Disposable ADR-0059 artifacts/tests exist locally; pre-amendment R14 target run is historical/stopped and no amended live rerun is claimed |

Production migrations/corpus copy, production Horizon activation, production-agent binding,
Graphiti replacement, and any use of the parked legacy Surreal deployment remain held. Do not
infer live readiness from local contract tests or D3/D4's narrowly named synthetic authority.

## 2026-08-18 — Production delivery rule and authoritative resume documents

> _Byline: Codex · GPT-5 · 2026-08-18._

All build/add/finish/change requests mean production implementation + Coolify deployment +
live verification. Local, staged, and mockup work are not completion unless the owner
explicitly requests a mockup. Root coordinates; the least-expensive subagent capable of
reliable completion executes each bounded task, with escalation for complexity or risk.
Resume documents: `docs/MASTER-TODO-2026-08-18.md` (entire application) and
`docs/HANDOFF-2026-08-18-evidence-operations-desk-mvp.md` (immediate MVP).
