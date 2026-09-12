# BUILD PLAN — the one forward plan

> **Authoritative for:** what we build next, in order. Entry point: `docs/PROJECT_CANON.md` (§0 Document Contract).
> Supersedes `docs/planning/*` (EXECUTION_PLAN, BUILD_TODO, MIGRATION_PLAN_v8) for **forward** work — those are history.
> Last updated: 2026-08-23 (migrations `0026`–`0030` corrected from "unapplied"/"do not cut
> over" to APPLIED — CH-15/CH-16, see the dated corrections at line ~24 and below; prior
> 2026-08-18: ADR-0059 blast-radius correction and local disposable T0 contract
> implementation; prior pre-ADR-0059 R14 target stopped, no current amended live proof or
> production activation claim).
> _Byline: Claude Code · Opus 4.8 · 2026-06-13; phase-status refresh 2026-07-11
> Claude Code · Sonnet 5; ADR-0053 amendment Codex · GPT-5 · 2026-08-13;
> documentation true-up Codex · GPT-5 · 2026-08-15; Phase-0 status Codex · GPT-5 · 2026-08-16;
> ADR-0059 correction Codex · GPT-5 · 2026-08-18; migration-status correction
> Claude Code · Opus 5 · 2026-08-23._
<!-- Updated by: Codex (migration-passes/doc-patching) | Date: 2026-08-15 | Rev: 1 | Platform: Codex / win32 | Changes: Clarify Wave-1, Knowledge, and Semantica status | Context: Prevent uncommitted working-tree implementation from being read as applied or deployed -->

> _Current-entry-point repair: Codex · GPT-5 · 2026-08-15._

## Current forward plan — 2026-08-18

The detailed execution source is
[`PLAN-2026-08-15-platform-runtime-migration.md`](awaiting-verification/plans/PLAN-2026-08-15-platform-runtime-migration.md),
with bounded lanes indexed in [`HANDOFFS.md`](HANDOFFS.md). The older Phase A–E narrative
below remains useful history, but any Agno-first or AgentOS-UI wording in it is superseded by
this current direction:

1. ~~Preserve and audit the unapplied Wave-1 tree; do not cut over migrations `0026–0029`.~~
   **Corrected 2026-08-23 (Claude Code · Opus 5, CH-15):** migrations `0026`–`0029` were found
   already applied to live PG18 — the "HELD FOR OWNER / NOT APPLIED" banners on those files were
   stale (now restamped in the sql files themselves). Migration `0030` was applied the same
   night on owner instruction (CH-15/CH-16). The Wave-1 tree is no longer "unapplied"; what
   remains open is the ingest pipeline that populates the new schema, not the schema itself —
   see `docs/DEBT.md`.
2. Complete coverage-based Go ingestion and deterministic ordered custody. Never route by size.
3. Separate horizon-blind Knowledge ingestion from immutable horizon replay and agent experience.
4. Integrate Semantica as the VIP semantic-intelligence service; only its outputs may be candidates.
5. Freeze framework-neutral ports, then build the PostgreSQL belief ledger and per-run Graphiti projection.
6. Add request-scoped provider routing and persistent OpenCode workspace control with isolated jobs.
7. Evaluate AG2 behind `OrchestrationPort`; retain the current Agno adapter until gates pass.
8. Expand the custom Workbench as the primary product surface.
9. Preserve the R9 activation gates and apply ADR-0059 to the ADR-0056–0058 contracts. The
   disposable Surreal vertical slice covers promoted manifest/span, separate derived first-party
   and acquired-third-party messages, one claim investigation, one established
   fact subgraph, and one as-lived memory scope. **Phase-0 contracts/evaluation/canary package is
   complete, D3/D4 authorized only the exact isolated synthetic target/implementation, and local
   schema/runner contracts exist.** R14's prior target run is stopped and does not prove the
   amended contract live; these changes authorize no production path. Do not reactivate the
   parked legacy deployment.
10. Build Find Evidence, Reconstruct Event, Discover Patterns, and the scoped Behavioral
    Analysis Agent only after gold-corpus, planted-future-fact, provenance, and bounded-query
    gates pass. The historical Phase-0 specification/canary remains valid as an observed baseline;
    the ADR-0059 disposable runner contract suite passes locally. Live-store and full-corpus gates
    have not run. See `GOALS-2026-08-15-surreal-investigation-memory.md`.

### Locally built and held

The isolated Phase-1 T0 Surreal schema/runner, source-class fixture, checkpoint/snapshot/rewalk
contracts, and focused tests exist locally. They are disposable synthetic artifacts only. R14's
pre-ADR-0059 target run remains historical/stopped; there is no current amended live proof.
No credential installation, production corpus copy, production Horizon/agent binding,
parked-target mutation, or Graphiti replacement is claimed.

The Matter/CourtCase foundation, neutral spine APIs, Workbench adapters/UI, and
Knowledge-to-Evidence promotion are pushed to `main`. Migration
`sql/0030_matter_case_foundation.sql` and focused tests exist, but ~~the migration is
**unapplied**~~ **Corrected 2026-08-23 (Claude Code · Opus 5, CH-15):** the migration **was
applied** to live PG18 the night of 2026-08-23 on owner instruction — verified: `analysis.matter`,
`court_case`, `matter_knowledge_partition`, `knowledge_evidence_promotion` all created, both
promotion triggers installed, `evidence_item` gained `matter_id`/`court_case_id` while retaining
legacy `case_id`. No deployment/live-service claim is made beyond the schema itself. Commit `be286a8` adds exact
canonical-record and H1 custody inspection before human review; it changes no
schema and is pushed to `main` but remains undeployed.
Commit `7b6aaf6` adds a read-only court-export/readiness explanation:
actual `analysis.vw_court_export` membership is shown separately from stricter
content-review, exact-provenance, custody, authentication, confidence,
hypothesis, redaction, and sensitivity checks. It performs no release mutation.
See `docs/plans/COURT-READINESS-pre-mortem-2026-08-15.md` for verified local
evidence and residual legacy-digest debt.

> **Current-state correction — 2026-08-15.** Wave 1 has implementation files in the
> working tree (`sql/0026_realization_event.sql` through `sql/0029_pass_grants.sql`,
> `server/evidence/realization.py`, and `server/evidence/derivation.py`), but ~~they are
> **pushed to `main` and not recorded as applied to the live database**~~. **Corrected
> 2026-08-23 (Claude Code · Opus 5, CH-15/CH-16):** direct introspection of live PG18
> (`100.91.190.107:5432`, db `ai`) showed `0026`–`0029` were already applied — the "HELD FOR
> OWNER / NOT APPLIED" banners on those files were stale, and have since been restamped in the
> sql files themselves with verified-live confirmation. `0030` was applied the same night on
> owner instruction. Treat the Wave-1
> sub-plan's older “no code/migration written yet” banner as historical drift, not as
> proof that the work has landed. The Workbench Knowledge page/API is implemented and
> locally validated and pushed to `main`; it is not deployed. Current verification
> counts and remaining activation gates are recorded in the R9 handoff rather than
> duplicated here.

## Anchor: the owner's critical path

**Knowledge-gathering from old AI-chat transcripts comes FIRST** — ingest them, extract the
development plans/decisions/strategy already discussed, feed the knowledge engine so the Builder
agents can help continue the build (the **bootstrap loop**). Evidence/SMS forensics come *after*.
Everything below is phased so each phase ships something usable and every write is HITL-gated.

**Where we are (updated 2026-07-11):** P0 ✅, P1 (HITL) ✅ deployed+verified, P2 evidence spine 🟡 —
**Phase A parser core-swap below is DONE** (chatminer vendored + 11 real modules in
`server/tools/parsers/ai_chat/`, verified 2026-07-11; the "4 shallow placeholders" framing is
obsolete). Still open: schema population by a real ingest pipeline remains `planned` (`DEBT.md`) —
live evidence schema is near-empty (`evidence_hash`=26 rows, verified 2026-07-11); the RESTART-0001
per-source raw-table redesign is DRAFT awaiting owner sign-off (D-008, `docs/DECISION_LOG.md`).
Inventory complete (`EVIDENCE_MERGE_MAP.md`).

---

## Phase A — Parser core swap (transcripts become real) — ✅ DONE (verified 2026-07-11)

**Goal:** replace the 4 shallow `evidence/tools/` (now `server/tools/parsers/ai_chat/`) parsers with the vendored **chatminer** core so AI-chat exports parse correctly.
- Vendor `chatminer` (10 format parsers + sentence-transformers segmenter + artifact extractor) into `server/tools/parsers/ai_chat/` as **atomic, self-registering modules** (one per format) per `CONVENTIONS.md`. — **done**: `server/vendored/chatminer/` present; 11 modules in `server/tools/parsers/ai_chat/` (9 chatminer-backed via `server/tools/_chatminer_adapter.py`; 2 genuinely custom formats — claude.ai export JSON, Claude Code JSONL — chatminer has no equivalent for those).
- Write an adapter: `ParsedMessage`/`ParsedConversation` → `NormalizedRecord` (content/role/timestamp/source → fields; rest → `attrs`). — **done**: `server/tools/_chatminer_adapter.py` (`run_chatminer_parser`), covered by `tests/test_chatminer_adapter.py`.
- Add **`RELATIONSHIP_HISTORY`** to the `TopicTag` enum; keep `TopicTag` a **separate segment-level metadata field** (not a knowledge domain). Decide: keep case-tuned segmenter keywords vs. config-load them (open Q from merge map §5). — enum addition **done** (`server/vendored/chatminer/core/types.py`); the case-tuned-vs-config-load decision is status unverified as of 2026-07-11 (not re-checked this pass).
- Delete the 4 placeholder parsers. Deploy to VPS; smoke-test parse of real exports. — placeholder deletion **done** (no placeholder files remain in `server/tools/parsers/ai_chat/`); VPS redeploy/smoke-test of real exports is status unverified as of 2026-07-11 (local module presence + `uv run pytest` coverage confirmed only, not a live VPS parse run).
- **Done when:** real ChatGPT/Claude/Gemini/Perplexity exports parse → `NormalizedRecord`s with segment tags, verified on the VPS. — code-level goal met; VPS verification status unverified as of 2026-07-11.

## Phase B — Knowledge ingestion + bootstrap loop

**Goal:** parsed+segmented transcripts land in the domain-partitioned knowledge engine so agents can answer "what did we decide/plan."
- Route message-safe chunks into the **five structural lanes** (`platform` · `legal` ·
  `personal_history` · `context` · `evidence`) under ADR-0053. AI chat can use the first four
  only; relationship history is part of `personal_history`; evidence is custody-only. One
  chunk may have multiple lane assignments but is stored and embedded once. Normalized tags
  retain finer topics. — _amended Codex · GPT-5 · 2026-08-13_
- Ingest the platform-design + legal-strategy conversation history first (fuels the bootstrap loop).
- **Workbench visibility (locally verified, 2026-08-15):** `main` includes
  `workbench/web/src/app/knowledge/page.tsx`, a case-prefiltered Weaviate search proxy,
  content browsing, and a read-only Graphiti memory pane. These files document and expose
  the intended read surfaces. Current broad gates are recorded in the R9 handoff;
  the feature is pushed to `main` and remains unverified live.
- **Done when:** a Builder agent answers a grounded question about a past design decision, citing the source transcript.

## Phase C — Gateway proof (Agno-first) — 🟡 gateway decision DONE, dial-stack wrap open

**Goal:** establish how far Agno's native tool-serving/proxying reaches before deciding on IBM ContextForge.
- Prove Agno can **serve** spine tools and **consume** an external MCP server. Register the first dial-stack capabilities as **MCP services behind Agno** — start highest-value: the **document-intelligence engine layer** (Google DocAI / IBM watsonx / Tesseract / Docling …) and the **bi-temporal Graphiti KG**. — status unverified as of 2026-07-11 (dial-stack wrap-order item not re-checked this pass; see open decision #2 below).
- **Decision gate:** Agno covers the gateway role → done; if not → stand up **IBM ContextForge** (`IBM/mcp-context-forge`) as the tool gateway. (Tool gateway ≠ LiteLLM model gateway.) — **decided and done**: verified from agno source (`agno/os/app.py:588-595`) that AgentOS's native MCP surface exposes only ~19 AgentOS *operations*, never granular `@tool` functions — so the **facade stays** as the only granular-tool MCP surface (`docs/planning/facade-collapse-plan.md`, superseded-banner corrected 2026-07-10) and **IBM ContextForge is the tool gateway** (ADR-0025, D-006 `docs/DECISION_LOG.md`; CF v1.0.4 live). All 14 facade tools are registered directly in ContextForge as REST tools in virtual server `platform_tools` (2026-07-10), alongside `agno`/`coolify`/`graphiti`/`exa`. The 2026-09-12 runtime rename does not silently churn this external publication key; `platform_tools` remains a bounded compatibility name until its clients are migrated.
- **Done when:** a tool served by the platform is invocable from at least one external surface, and the gateway decision is recorded as an ADR. — **met**: legacy ContextForge publication key `platform_tools` (2026-07-10); gateway decision recorded in ADR-0025.

## Phase D — Bitemporal substrate (P3) + two-pass machinery

**Goal:** the cognition substrate that makes Part 2 possible.
- Derive `source_available_from` by source class (`occurred_at` first-party; `acquired_at`
  acquired-third-party), retain plural realization links, keep `knowledge_time` audit-only,
  and build separate derived message/chunk surfaces through every prefilter. Stand up
  **Semantica as a VIP semantic-intelligence and decision/provenance service**.
  Semantica itself is not a “candidate service” and must not be replaced or forked around.
  Its entity/claim/time/event **candidate outputs** remain proposals: they enter the
  governed review/promotion path and do not become authored canonical truth without human
  promotion. A local disposable worker now executes vendored pattern extraction and emits
  provenance-bearing pending candidates; its PostgreSQL adapter is contract-tested but has
  not written a database or been deployed. Held projector configuration is not evidence of
  an activated service.
- Rebuild the two-horizon experience behind framework-neutral ports. The current Agno
  adapter may host a shadow implementation, but it does not own the durable contract.
- **Wave-1 status (2026-08-15):** implementation is pushed to `main`; no
  migration-application, deployment, or cutover claim is made here. Apply and
  validate in the locked order before binding agent readers.
- **Done when:** the Pass-1-vs-final-pass delta is queryable for a sample event over the bitemporal graph.

## Phase E — Evidence verticals + custody hardening + tests

**Goal:** Part 1 forensic completeness.
- Wrap dial-stack forensic parsers (SMS/FB/iMessage) + **SQLite WAL deleted-message recovery** as MCP services; SBV as Workflow A (custody-gated vertical + iframe + CLI + export). — SBV side 🟡 **largely landed** (verified 2026-07-11): forensic fork LIVE in prod with H1/H2/H3 custody hashing (`ghcr.io/cursedpotential/sbv-forensic:0.2.3-forensic`, deployed 2026-07-09); Phase 5a native Go automation endpoints (`/api/automation/extract`+`status`/`export`/`backups`) are BUILT on fork branch `worktree-agent-abe280ccbefefe136` but not yet shipped through the subtree→fork→CI→tag-bump sequence (`docs/COORDINATION.md`); Phase 5b `/x/sbv/` UI embed DEFERRED to the G2/VPS window. dial-stack SMS/FB/iMessage parser wrap status unverified as of 2026-07-11.
- Harden custody toward dial-stack's **Ed25519 signed chain-of-custody**; `custody.py` stays the only `evidence`-schema writer. — status unverified as of 2026-07-11.
- Harness-first tests (pytest + evals) per layer; R2 backups. — pytest suite green (208, `uv run pytest -q`, verified 2026-07-11); evals still `CASES=()` per `DEBT.md`; R2 backups status unverified.
- **Done when:** an SMS/FB export ingests through custody → normalize → store with verifiable signed custody chain, evals green. — not yet met: evals remain empty (`DEBT.md`).

---

## Later (own rounds)

- **Part 2 — Analysis:** behavioral/legal layer — vendor/wrap **Tether** (HF models, deferred at `dial-stack/utilities/apps/ml-nlp/Tether/`), `pattern-analyzer` (~25 modules→MCL), `ConflictAnalysisApp` RuleEngine, `priority-screener`; multi-pass over knowledge horizons.
- **Part 3 — AI Legal Team:** port the owner's Gemini Gems personas behind the neutral
  orchestration contract; MCL 722.23 ontology + Michigan legal skills.
- **Hardening:** self-hosted evidence vector store at scale; multi-user auth; living wiki (ADR-0022).

## Delegation map — who/what does each kind of work

The SSOT is tool-agnostic (`CONVENTIONS.md` § cross-tool), so work can be split across agents/models by
*judgment required* vs *volume*. Every delegated artifact carries a byline (`tool · model · date`).

| Work type | Best executor | Why |
|---|---|---|
| **Bulk scanning / reading / summarizing into the inventory** (unread plugin bodies, 9 doc-intel engine bodies, loaders/pipelines, drizzle schemas) | **Cheaper model** (Sonnet/Haiku) or OpenCode/Codex agent, read-only | High volume, low judgment; just extract + record |
| **ADR supersession sweep + planning/* reconciliation** (flag conflicts vs the new SSOT) | **Cheaper model**, read-only, *proposes* — human/Opus confirms | Mechanical cross-check; decisions stay with owner/canon |
| **Mechanical porting** (vendor a chatminer parser into `server/tools/parsers/ai_chat/` to the atomic-tool contract) | OpenCode/Codex agent or cheaper model, per `CONVENTIONS.md` | Pattern is fixed; contract is explicit |
| **Wrapping a donor TS tool as an MCP service** | OpenCode/Codex (strong at codegen) | Self-contained, testable |
| **Architecture/decisions, conflict reconciliation, plan changes, anything touching CANON §5** | **This tier (Opus/Fable)** — NOT delegated | Judgment + cross-cutting consistency; the debacle came from un-reconciled decisions |
| **Anything that writes evidence/HITL/custody** | reviewed here, HITL-gated | Trust boundary |

### Recommended: cheaper-agent PRE-SCAN before Phase A (my recommendation: do it)

Before building, dispatch a **cheaper read-only agent** to close the last mechanical gaps so Phase A starts on solid ground. Scoped task (it writes findings into the inventory + a reconciliation note, makes NO code/decisions):
1. Read the ~40 `plugins/*.ts` bodies + 9 `document_intelligence/engines/*.py` bodies + `loaders/`/`pipelines/` + remaining `drizzle/*` → append concise capability notes to `EVIDENCE_MERGE_MAP.md` §7.
2. ADR sweep: list which of ADR-0001…0022 are superseded/affected by the 2026-06-13 locked decisions (gateway/Agno-not-DIAL, donor reconciliation) → write `docs/ADR_RECONCILIATION.md` (proposals only).
3. Flag any contradiction between `docs/planning/*` and the new SSOT.
Output is reviewed here before Phase A. **This is the cheap, safe way to de-risk; judgment work stays at this tier.**

## Open decisions to confirm before/within phases (from EVIDENCE_MERGE_MAP §5)

1. Segmenter keywords: keep case-tuned vs generalize + config-load case terms? (Phase A)
2. dial-stack wrap order — confirm document-intelligence + Graphiti first. (Phase C)
3. Custody hardening timing — now vs Phase E. (default: Phase E)
4. How far Agno native tool-serving reaches before ContextForge. (Phase C gate)
