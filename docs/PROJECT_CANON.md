# PROJECT CANON — the durable source of truth

> **Read this first on any resume.** This file exists so a long conversation +
> repeated compaction never loses the vision, decisions, or plan. It is kept
> current as decisions are made. If something here conflicts with an older ADR,
> this file's "Locked Decisions" section wins and the ADR should be updated.
> _Byline amendment: Claude Code · Opus 5 · 2026-08-23 — doc-sync to tonight's executed
> reality: migrations 0026–0030 confirmed/applied live (CH-15/CH-16); D-067 Temporal
> persistence + role ruling; TODO-212 framework roles ruled; TODO-101/207 custody-mandatory
> ruling; Graphiti retirement direction recorded._
> _Byline amendment: Claude Code · Fable 5.1 · 2026-09-05 — naming canon sweep
> D-137..D-141 (repo = **Indicia Probata** / `probata`; analysis engine splitting off as
> **Indagatio Veri** / `indagatio`; vault = **consignatio**; legal workbench = **advocatio**;
> geo = **vestigia**; import lane UIW → **proffer**). See `docs/NAMING.md`. No canon
> assertion in this file named an old product brand as current truth, so no strike-through
> was needed here beyond this note._
> Last updated: 2026-08-23 (§4 ovh-files PG18 row gains `temporal`/`temporal_visibility`
> databases + `agno_app`/`temporal` roles per D-067/CH-16; §4 `data-graphiti` row gains the
> owner's retirement-direction note; §5 gains D-067, the TODO-212 framework-roles line, and the
> TODO-101/207 custody-mandatory-at-capture line; §6 notes 0026–0030 are no longer held and the
> Temporal P0 scaffold is underway; §10's native-evidence-vector entry corrected — SCHEMA
> (migrations 0026–0029) is applied, only the collection/backfill/alias/deploy activation
> remains held; prior 2026-08-18: ADR-0059 separates first-party/acquired-third-party
> derived message projections, source availability, plural realizations, and healthy resume
> from terminal rewalk; prior 2026-08-16: ADR-0056–0058 Phase-0 logical contracts, synthetic
> planted-future-fact tests, evaluation gates, and S1–S6 owner review are complete;
> no implementation/activation authority; prior 2026-08-15: governed Surreal analytical/walk-memory
> projection, claim-centered evidence assembly, Investigation Search, and scoped
> hindsight/as-lived behavioral analysis; prior: framework-neutral runtime/custom
> Workbench target, Semantica VIP, Postgres belief authority + Graphiti projection,
> OpenCode provider/workspace role, and ADR-0055 Matter/CourtCase boundary; prior 2026-08-13:
> ADR-0054 durable run reports and correlated observability;
> ADR-0053 five-lane chat-ingestion, multimodal asset,
> selective HITL, and investigation-register decisions; prior: 2026-08-09 — §4 data-tier host defaults corrected to
> ovh-files per commits 5e829ab/a68fabd; §5 SurrealDB entry restated RETIRED/zero-callers;
> §6 P4 updated for PR #18 (universal import engine + SBV promotion) — exact Phase-5a wording
> pends OQ-9, see the marked TODO below; prior: 2026-07-29, §4 rewritten to the 4-box Coolify
> fleet from live inventory; §5/§6/§7/§8 doc-sync — ADR-0040 Weaviate, ADR-0041 Memgraph,
> ADR-0042 Portkey/LiteLLM-retired, agno 2.8.0; ADR-0036–0039 accepted same day; before that:
> 2026-06-13, §6 refresh 2026-07-11).
> _Byline: Claude Code · Opus 4.8 · 2026-06-13 (created 2026-06; this revision Opus 4.8;
> drift-fix 2026-08-12: §5 LiteLLM-gateway/embedder/Milvus rows + §10 SurrealDB row corrected
> against ADR-0040/0042/0043 and D-042 (Claude Code · Kimi K3);
> §6 status refresh 2026-07-11 Claude Code · Sonnet 5; §5/§6/§8 sync 2026-07-29
> (drift-fix 2026-08-12 round 2, Claude Code · Kimi K3: §4 data-vector down-note + §6 OpenCode LiteLLM mention corrected)
> Claude Code · Fable 5; §4/§5/§6 sync 2026-08-09 Claude Code · Sonnet 5;
> §3/§5 chat-ingestion amendment 2026-08-13 Codex · GPT-5;
> Phase-0 Surreal/investigation review status 2026-08-16 Codex · GPT-5;
> drift-fix 2026-08-14 Claude Code · glm-5.2:cloud: §1 visible_from/derived-passes (ADR-0045 §A/§B), §4+§6 Weaviate cutover-verified, §8 agno 2.8.0→2.8.7, transcript_miner topology)_

---


> **Schema doctrine (D-152/D-153, 2026-09-07):** `sql/bootstrap/schema_snapshot_<date>.sql` IS the database. No numbered
> migrations exist or may be proposed; a schema change is made in its final form in the snapshot and applied by
> `scripts/rebuild_platform_from_snapshot.sh`. Reference and state tables (the keep set) never change or delete across
> rebuilds; everything else is created fresh. Every mention of migrations below this line is history.

## 0. Document Contract (ONE of each — read this to know what's authoritative)

To stop architecture/plan drift, **each concern has exactly ONE authoritative file.**
This canon is the entry point and names them. Everything else (the ADR set through ADR-0059, `docs/planning/*`,
the wiki, `glossary.md`) is **subordinate history/reference**, not a competing source of truth.

| Concern ("one X") | Authoritative file |
|---|---|
| **Vision + locked decisions** (the index) | `docs/PROJECT_CANON.md` ← you are here |
| **Inventory** (what code exists, where, what's the best version) | `docs/EVIDENCE_MERGE_MAP.md` |
| **Plan** (what we build next, phased) | `docs/BUILD_PLAN.md` |
| **Structure** (where every kind of file goes) | `docs/REPO_STRUCTURE.md` |
| **Style** (how we write code — Python/TS, tool contract) | `docs/CONVENTIONS.md` |
| **Handoffs** (forward build as small agent-executable units) | `docs/HANDOFFS.md` |

**Drift rules (non-negotiable):**
1. If any doc conflicts with another, **§5 Locked Decisions here wins**; fix the others to match.
2. When a locked decision is made, **update this canon in the SAME change** — never let it lag.
3. New capabilities become platform-owned **ports/contracts**, atomic tools, or
   MCP/API services behind those contracts. Agno is one current adapter, never
   the owner of evidence, horizon, memory, provider, HITL, or admin truth. See
   `REPO_STRUCTURE.md` and `PLAN-2026-08-15-platform-runtime-migration.md`.
4. `dev-resources/Archives/` is **read-only donor material** — mine it, never edit or build inside it.

---

## 1. What we are building (the three-part arc)

A personal **evidence-processing + analysis + legal-strategy platform** for the
owner's **pro se** family-law (custody) case. It currently runs through an Agno
AgentOS adapter while migrating to framework-neutral platform contracts and a
custom Workbench. It bootstraps itself: the early agents help build the rest of
the platform.

1. **Part 1 — Evidence.** Custody → parse → normalize → store → court-ready export.
   Many sources (SMS, Facebook, iMessage-PDF, Google Voice/Location, chat
   exports, Drive/OneDrive). Immutable, hashed, chain-of-custody.
2. **Part 2 — Analysis.** Multi-pass psychological / abuse / toxicity analysis of
   scoped events and conversations (gaslighting, DARVO, coercive control,
   misleading events, corroboration, contradiction, and missed-pattern discovery).
   Runs may be hindsight, as-lived-so-far, or paired to expose the realization delta.
3. **Part 3 — AI Legal Team.** A third agent family that uses the evidence +
   the knowledge base to build legal strategy, documents, and filings. Already
   prototyped by the owner as **Gemini Gems + personas**; to be ported behind
   the platform orchestration contract. AG2 is a bake-off candidate, not an
   adopted replacement.
   This is where the imported Michigan legal skills + MCL 722.23 ontology engage.

**The killer mechanism (why the memory is bitemporal):** Part 2 replays how a
person realizes they were abused, in passes with widening knowledge —
**Pass 1 contemporaneous** (agent sees only what was knowable at that moment —
where gaslighting works), **Pass 2/3 assembled hindsight** (all conversations
connected), **Final pass full disclosure** (incl. facts discovered later). A
"pass" is a **knowledge horizon** — a filter over a bitemporal graph. The
**delta between Pass 1 and the final pass for the same event IS the abuse made
legible** ("what you were led to believe vs what was true vs when you found
out"). Every horizon-eligible projection must preserve event time, source
availability, plural realization provenance, and disclosure policy. This is why
Graphiti/Neo4j is the cognition substrate.

**Current clock and projection ruling (ADR-0059, owner 2026-08-18; narrowly
supersedes ADR-0045 §A/A.4):** keep three concepts separate. `occurred_at` is
event time. `source_available_from` is the source-retrieval horizon: occurrence
for a first-party message, custody-backed acquisition for an acquired-third-party
message. A message has zero-to-many separate realization links; realization does
not overwrite or backdate source availability. First-party and acquired-third-party
message surfaces are separate **derived projections** from one authored normalized
spine. The acquired thread preserves its real sender, recipients, and participants;
the owner is not one of those participants. Chunks/embeddings are derived and carry
the same source boundary. ADR-0045 §B still sanctions version-pinned derived pass
materializations (single-writer, hash-attested) and still forbids parallel AUTHORED
as-lived/hindsight stores.

**The end-goal frame (the platform itself):** beneath the three-part arc, the
durable product is a **multi-surface tool-platform GATEWAY** — it **serves** its
own tools, **consumes** external tools, and **routes/proxies** between them, exposed
across surfaces (Claude MCP / Gemini / OpenAI / Agno itself). The evidence/analysis/
legal arc is the **first domain application** running on that gateway. The Builder
agents help build the gateway out (the bootstrap loop). **Gateway core = Agno**
(see §5); the abandoned prior attempt (AI DIAL, in `dev-resources/Archives/dial-stack`)
is a parts/pattern donor only.

---

## 2. Agent families (topology)

Root **Router** (`mode=route`) dispatches to one of three families:

1. **Platform Ops** (`coordinate`) — Ingestion Orchestrator, Analysis
   Orchestrator, Review Gatekeeper, **Transcript Miner**. Runs the evidence pipeline.
2. **Builder** (`coordinate`) — Dev Copilot, Project PAL, Forensic Data Agent.
   Helps build/port the platform itself (the bootstrap).
3. **AI Legal Team** (`coordinate`, **to build — Part 3**) — ported from the
   owner's Gemini Gems personas. Pro se case assistance: strategy, motions,
   filings, discovery. Uses evidence + knowledge + the Michigan legal skills.

Plus standalone: Document Digest (Gemini long-context). Stable agent keys —
UI/tests depend on them. (Cloud Drive Cleanup: removed from the active topology
2026-06-12 — owner decision, separate future feature, not part of this platform.)

---

## 3. The knowledge engine — five lanes, segment-routed, source-preserving

Knowledge is gathered from conversations covering everything. The five structural
lanes are `platform`, `legal`, `personal_history`, `context`, and `evidence`.
`personal_history` includes relationship history; relationship-specific meaning is
captured with tags and later entity/event extraction, not a separate storage lane.
Weaviate uses one collection per lane. The evidence collection is custody-only and
never receives AI-chat auto-routing.

AI chats land first as horizon-neutral parent conversations and ordered child messages.
They are chunked at message-safe boundaries and only then classified. One chunk can have
several lane assignments, but PG stores it once and embedding is computed once per
embedder; that vector is reused across eligible lane projections. Ambiguous or failed
classification remains searchable in `context` and enters selective human review.

Lanes answer “which broad corpus?” while normalized tags answer “what is this about?”.
Tags retain provenance, confidence, and review state. Raw messages do not carry lane,
horizon, disclosure, as-experienced, or hindsight judgments.

Message source class is likewise not an analytical belief. Governed derived projections
separate first-party conversations from acquired-third-party conversations (ADR-0059).
Third-party rows preserve actual sender/recipients/participants with the owner absent;
their source becomes walk-visible at acquisition. Realization remains a plural linked
derivation above the normalized message, never a replacement message date.

All created works and attachments are ingested with the archive. Original bytes remain in
R2 and PG records provenance plus derived text/OCR/transcript/keyframe representations.
Extraction escalates from lightweight/native parsing to Docling, then to a configurable
vision model; Colab driven through MCP is a backup only. Provider selection is not locked.

Entity, claim, time, and event-candidate extraction runs asynchronously after landing and
chunking. Human-curated concerns graduate first into an investigation register linked to
candidates, evidence needs, and primary evidence; only a human promotes them to an official
timeline event. As-experienced versus hindsight walk views/tables are designed later
(~~"designed later"~~ → **amended 2026-08-14:** DERIVED pass materializations are
**sanctioned** by ADR-0045 §B — decided but unbuilt; Wave 1 builds the single-writer
refresher. Parallel AUTHORED stores remain forbidden). See ADR-0053 + ADR-0045 §B.

**The comprehensive living wiki (ADR-0022) — the human-readable face of this engine.**
One wiki, **dual-rendered**: human-readable navigable markdown AND AI-queryable
(ingested into the domains above). **Covers everything** — every library used
(purpose/version/gotchas), every application/service, every bit of code created,
every decision (ADRs flow in), every strategy (platform + legal). It is *living*
(agents keep it current, a Builder-family doc responsibility), absorbs the three
archived wikis in `dev-resources`, and is the superset of which ADRs + this canon
are sections. Big build, **deferred** — until then this canon is the interim truth.

**Knowledge gathering is phased:** (a) help build the missing/incomplete
platform components → (b) process evidence against historical timelines/events
→ (c) produce legal strategy + docs + filings.

---

## 4. Current stack (deployed — 4-box Coolify fleet; rewritten 2026-07-29 from live Coolify inventory)

**Coolify is the deploy plane** (control plane on `ion-control`): deploy = git push → Coolify
build, with per-app **Watch Paths** scoping the blast radius (set watch_paths at app creation,
always — an app without them redeploys on EVERY push). Boxes are Tailscale-meshed
(`tilapia-skilift.ts.net`); services bind `${BIND_IP}` (the box's tailnet IP), never loopback —
probes and tunnels target the tailnet IP, not `localhost`. Coolify projects: `agno-platform`,
`Case Bible`. (The original single-VPS `~/agno-mvp` compose layout this section used to describe
is preserved in git history + `docs/planning/`.)

| Box (tailnet IP) | Role | Coolify apps (live, verified 2026-07-29) |
|---|---|---|
| `ion-control` (Ionos 3.8 GB) | Coolify control plane | — (Coolify itself) |
| `ovh-app` `100.72.169.40` | Exec tier (the old exec bundle split into independent apps, owner rule "separate everything separable") | `exec-tier` (agentos-api + db rump) · `exec-gateway` (OpenCode; LiteLLM deprecated → teardown pending, ADR-0042) · `exec-contextforge` (tool gateway) · `probata-tool-runtime` (SBV forensic fork + registry-backed parser/extractor/repair facade; renamed in place from `exec-platform-tools`, owner ruling 2026-09-12) · `exec-sandbox` · `exec-desktop` (Kasm) · `portkey` (THE model gateway, ADR-0042) · `knowledge-workbench` (staged-ingest console, :8020) · `agent-ui` · `browser` · `coolify-mcp` |
| `ovh-data` `100.119.96.29` | Data tier — independent apps on the shared external ~~`agno`~~ docker network (**renamed `probata` on 2026-09-07, plan §4.3; `agno` removed on both live boxes**) (172.30.0.0/16; cross-app DNS — `neo4j:7687`, `milvus:19530`, …). **Stale as of 2026-08-06/07** (see the ovh-files row): the `data-neo4j`/`data-weaviate` apps here went `exited:unhealthy` and code defaults were repointed away from them; do not treat this row as live for those two. | `data-surreal` (the ONE app that legitimately stays here — PARKED read-only since 2026-08-04, ADR-0043, RETIRED/zero-callers per `server/core/session.py`, owner-gated deletion) · `data-neo4j` (⚠ unhealthy since ≥2026-08-06, superseded by its ovh-files twin) · `data-weaviate` (⚠ unhealthy since ≥2026-08-06, superseded by its ovh-files twin; sidelined-Milvus framing below is otherwise unaffected) · `data-vector` (Milvus — sidelined per ADR-0040; **DOWN deliberately since 2026-08-10** — 6th embedded-etcd corruption, docs/COORDINATION.md; D-042 cutover verified 2026-08-09) · `nocodb` (review front-end, ADR-0029 lineage) |
| `ovh-files` `100.91.190.107` | Files + chat surfaces — **also now the live data-tier host for PG/Neo4j/Weaviate**, migrated off ovh-data in two waves: PG (`data-pg-files`, PG18: pg_duckdb + pgvector + PostGIS; tailnet `DB_HOST=100.91.190.107`) moved 2026-08-02 (`docs/DECISION_LOG.md`); Neo4j (Graphiti's graph, `bolt://100.91.190.107:7687`) + Weaviate (ADR-0040 substrate, `http://100.91.190.107:8081`) defaults corrected 2026-08-06/07 after their ovh-data twins went unhealthy — verified live from inside agentos-api, commits `75ec196`/`5e829ab`/`a68fabd` (`server/core/session.py`, `server/analysis/semantica_wiring.py`). **Added 2026-08-23 (D-067, CH-16):** the same PG18 instance now also owns two new databases, `temporal` + `temporal_visibility` (Temporal's own persistence — no second Postgres container, per the data-vector six-corruption lesson), under a new non-superuser role `temporal` (connection limit 30, password delivered out-of-band, never in git). A second new role, `agno_app` (non-superuser, `sql/0029` grants), was created the same night for the app itself but the app **still connects as the superuser `ai`** — cutover to `agno_app` is an owner-gated Coolify env change + redeploy, not yet done (see `docs/DEBT.md`). | `data-pg-files` · `data-neo4j` (live twin) · `data-graphiti` (Graphiti MCP — **retirement direction confirmed by owner 2026-08-23**: the self-hosted MCP server never worked like Zep's hosted service, the case-lane client is write-only, zero rows have ever been drained; it stays only as a bake-off comparison point while an agent-memory replacement — Cognee frontrunner, Memgraph/ADR-0041, Surreal, Postgres-native also candidates — is evaluated, judged on self-hosted operability first; see `docs/reviews/2026-08-23-cross-repo-evidence-audit/ISSUES-AND-TODO.md` TODO-211) · `data-weaviate` (live twin) · `librechat` (:3080) · `librechat-mongo` (real Mongo — owner waiver of the FerretDB rule) · file services (Cloudreve, casebible rclone lane) |

**Off-Coolify:** Homepage dashboard `http://100.72.169.40:3010` (plain compose,
`/data/dashboards` on ovh-app); n8n on its own server (tailnet `100.98.98.38`); AgentOS
control plane = os.agno.com via the localhost tunnel (`agentos-control.cmd`, Desktop
shortcut). **Storage:** Cloudflare R2 (`nexus` + the casebible buckets) — rclone mounts +
S3 API + pg_duckdb httpfs (`read_text('s3://nexus/...')`).

---

## 5. Locked decisions

- **Temporal adoption ruled = D-067 (2026-08-23):** persistence lands inside the existing
  PG18 on `ovh-files` — two new databases, `temporal` + `temporal_visibility`, no second
  database server (see §4). The chat-transcript ingest cutover happens in ONE move on live
  traffic, fix-forward — no shadow deploy, no parallel v2. Approvals route through the
  existing knowledge-workbench console (`:8020`); the reference project's separate
  approval web-UI is discarded. The workbench is **not live yet**, so deploying it is now a
  P2 prerequisite of this ruling, not an assumption. Plan: `docs/plans/TEMPORAL-INTEGRATION-PLAN-2026-08-23.md`;
  P0 infra (roles, databases, Coolify compose scaffold, worker Dockerfile) executed same
  night — CH-16. Full ruling text: `docs/DECISION_LOG.md` D-067.
- **Framework roles under Temporal ruled (2026-08-23, TODO-212):** Temporal owns sequencing/
  retries/gates/durability. Classification and extraction model calls move to **DSPy**
  programs — compiled against owner-labeled gold sets, schema-enforced JSON via Portkey, run
  inside Activities (owner-named; operationalizes the debt register's own human-labeled-eval/
  challenger/audit demands). Tool-rich single agents and knowledge/RAG stay on **Agno as a
  library** (no rip-out). Multi-agent deliberation (investigation/analysis) stays **AG2**,
  though its 2026-08-15 handoff needs review against this ruling. The Workbench remains the
  visual pipeline surface. PydanticAI-vs-Agno-as-library for the knowledge step specifically is
  being settled by a live two-implementation bake (`server/temporal/knowledge_harness/`,
  `KNOWLEDGE_HARNESS=agno|pydantic_ai` env flip) inside Temporal P1 — in progress, not yet
  decided. LangGraph is benched (Temporal covers its durable-graph niche here; AG2 covers
  deliberation). Dify is struck (was a misreading of "DSPy"). See
  `docs/reviews/2026-08-23-cross-repo-evidence-audit/ISSUES-AND-TODO.md` TODO-212.
- **Custody hashing ruled mandatory at capture (2026-08-23, TODO-101/207):** evidence-lane
  ingest must refuse when hashing is unavailable — silent degradation is not acceptable. Owner's
  decisive follow-up: custody hashing must first be extracted into a **standalone callable
  process** (wraps `vendored/sbv/pkg/custodyhash`) usable from the SBV path, the fallback path,
  or anything else, so either path can call it regardless of which one fails. Sequencing:
  TODO-207 (the standalone process) lands **before** the mandatory-at-capture rule (TODO-101)
  is enforced.
- **Message source clocks and walk lifecycle = ADR-0059:** one authored normalized
  spine feeds separate first-party and acquired-third-party derived message projections.
  First-party source availability equals occurrence; acquired-third-party availability
  equals acquisition, and the owner is absent from its actual participant set. Messages
  may have zero-to-many realization links; chunks remain derived. A healthy reconciled
  checkpoint resumes the same walk identity. Projection drift/revocation/mismatch or
  another terminal integrity failure seals a non-resumable snapshot and starts an
  explicitly linked rewalk. This supersedes ADR-0045 A/A.4 and ADR-0056 decision 10 only
  to that extent; their remaining one-store/governance decisions stand.
- **Surreal analytical/walk-memory surface = ADR-0056:** PostgreSQL remains
  canonical; SurrealDB is a governed, rebuildable projection and experimental
  platform-owned Spectron-compatible memory/runtime. Original binaries stay in
  custody storage. Partial source approval exposes approved spans only. Graphiti
  remains the baseline until bake-off. One shared product/environment Context carries
  Matter-scoped promoted knowledge; first-class walks and walk-bound experiential state
  isolate executions. Healthy reconciled pauses resume the same walk; terminally failed or
  superseded walks are sealed for replay and compared to linked rewalks. The parked legacy
  deployment is not activated.
- **Claim-centered fact assembly = ADR-0057:** candidate claims generate bounded,
  auditable cross-system investigations. Human/governed review creates immutable
  established facts linked to exact supporting, contradicting, and qualifying spans;
  corrections relate/supersede and never silently rewrite history. Corroboration counts
  independent source families, while raw derivative hits remain separately visible.
- **Investigation and behavioral analysis = ADR-0058:** Find Evidence, Reconstruct
  Event, and Discover Patterns operate on immutable scopes and bounded traces.
  Behavioral runs separate closed-set analysis from outward discovery and support
  hindsight, as-lived-so-far, and paired delta. Internal diagnostic-adjacent terms are
  behavioral lenses, not diagnoses; Case Prep uses conduct-first evidence language.
- **AI-chat knowledge ingestion = ADR-0053:** five global lanes; explicit
  conversation/message/chunk source truth; post-chunk multi-label routing; selective
  confidence HITL; created works + attachments included; OCR escalation is
  lightweight/native → Docling → configurable VLM; human investigation register;
  horizon-walk realization deferred and never stamped on raw chat rows.
- **Run observability = ADR-0054:** every run/test produces an itemized,
  versioned durable report explaining what ran, what skipped, why, outputs,
  remediation, and append-only human decisions. Postgres + ADR-0047 are the
  authority. Agno OpenTelemetry traces may mirror to explicitly enabled
  Langfuse and are correlated by `trace_id`; Langfuse is diagnostic only.
- **Deploy on the VPS** (ADR-0009), not local podman. n8n on its own server.
- **pg_duckdb inside Postgres** (ADR-0013, supersedes ADR-0003 no-DuckDB).
- **Neo4j for Graphiti** (ADR-0014, supersedes FalkorDB). Bitemporal cognition substrate.
- **Ollama Cloud `glm-5.1` = PRIMARY LLM** ~~via LiteLLM gateway~~ **via Portkey
  (Corrected 2026-08-12: LiteLLM RETIRED — ADR-0042, owner ruling 2026-07-29; see
  the Portkey entry below; glm-5.1 stays primary).** NVIDIA NIM =
  embeddings + rerank + LLM backup only (NVIDIA rate-limited the owner).
- **Models:** ~~embedder `nvidia/llama-nemotron-embed-vl-1b-v2` (2048-d, asymmetric —
  query vs passage modes, `server/core/embedder.py`)~~ **Corrected 2026-08-12: the LIVE
  text embedder is `nvidia/nv-embed-v1` (4096-d, symmetric) — live contract since
  2026-07-19 (`server/core/settings.py:71-80`, `server/core/session.py`, docs/DEBT.md);
  the nemotron asymmetric models are FALLBACK-only and NOT banned (owner correction
  2026-08-07 — they need a per-call `input_type`, usable wherever the caller can send it)**;
  reranker `nvidia/rerank-qa-mistral-4b`
  (`server/core/reranker.py`, custom — Agno's CohereReranker leaks to Cohere). Gemini 2.5 Pro
  for Document Digest. Groq/OpenRouter in reserve.
- ~~**Memory = LearningMachine authority + Graphiti/Neo4j evidentiary memory.**~~
  **Corrected 2026-08-15:** Postgres is the authority for durable belief/memory
  events and canonical Knowledge metadata; Graphiti is a run-scoped belief
  projection, not canonical evidence. Agno LearningMachine is a current adapter
  capability to preserve or replace deliberately during decoupling. Semantica
  is a VIP extraction/intelligence service; it forms no agent beliefs.
- **Tool architecture = polyglot orchestration mesh:** universal custody gate →
  named workflows A/B/C per evidence type → registered atomic tools (one
  library/language each) → agent re-composition in the sandbox on step failure.
- **Minimize custom code (locked 2026-06-13).** Default to **off-the-shelf open-source**;
  write custom code ONLY for what is genuinely situation-specific (the evidence custody/
  bitemporal logic, MCL/legal analysis, the owner's parsers/taxonomy). Everything generic
  uses a proven component.
- ~~**VIP components include Agno and its native UI.**~~ **Corrected 2026-08-15:**
  Agno/AgentOS is the current runtime adapter and may be removed after parity;
  its useful capabilities must be preserved deliberately, not treated as
  product authority. **Semantica is VIP/first-class**, as are the custody and
  horizon invariants, the forked SBV Go engine, and platform-owned contracts.
  Custom Graphiti remains valuable but must prove OSS parity/usage; evaluate a
  replacement if it cannot satisfy the memory contract. ContextForge remains
  the tool-gateway adapter. The custom Workbench is the primary product UI.
- **Serve/consume topology (locked 2026-06-13) — the layered picture; nothing here gets dropped:**
  - **Model gateway = LiteLLM** (`gateway` container): routes ALL models — remote (Gemini/Groq/
    OpenRouter/NVIDIA/Anthropic) AND in-stack/local (Ollama Cloud primary `glm-5.1`). Every
    agent/LLM gets its model through LiteLLM. ⚠ **Superseded 2026-07-29 → Portkey (ADR-0042)**;
    LiteLLM deprecated pending teardown — see the Portkey entry below.
  - **Tool gateway = IBM ContextForge**: serves/federates MCP tools to any MCP client — Agno
    agents (`MCPTools`, stdio + HTTP), **remote** LLMs (Claude/Gemini), and **local-stack** runners.
  - **Current agent runtime/outbound adapter = Agno AgentOS.** Accepted target:
    framework-neutral orchestration ports, with Agno retained only until parity;
    AG2 is evaluated behind the same ports.
  - **OpenCode** = coding agent, persistent workspace, flexible provider bridge,
    and isolated code-execution control surface. It consumes platform MCP tools
    and complements Portkey for subscription/payment paths Portkey cannot expose.
  - **agent-sandbox** = isolated code-exec for agent re-composition (no secrets, no ports). KEEP.
  - **Kasm desktop** (`desktop` profile) = **persistent** browser desktop for agent/human GUI work. KEEP (persistence matters).
  - ~~**Store/session/Knowledge/memory = SurrealDB candidate.**~~ The **Agno operational
    Surreal adapter remains retired** and the legacy deployment remains parked read-only.
    **ADR-0056 adds a different role:** a governed analytical projection and experimental
    Spectron-compatible walk-memory runtime behind platform-owned contracts. PostgreSQL
    remains canonical; Graphiti stays the belief-memory baseline during bake-off; Weaviate
    remains broad vector retrieval.
  - ⚠️ A raw local model consumes tools ONLY through an MCP-capable harness (Agno / OpenCode /
    MCP client) — never directly. Two distinct gateways: **models** (Portkey since ADR-0042,
    formerly LiteLLM) and **ContextForge = tools**.
- **Universal exposure — API-first + MCP-wrapped (locked 2026-06-13; needs ADR).** EVERYTHING is
  atomically addressable — **every tool, every agent, every workflow** exposes:
  1. an **internal API** (FastAPI/HTTP) that in-platform ("platform-surface") consumers call directly;
  2. an **MCP wrapper over that API** for ALL external/any-surface consumers — federated by IBM ContextForge.
  Each unit is callable **atomically**; tools also **compose into workflows** (a workflow may declare a
  slot for a *variable set* of tools). **Workflows are first-class** and reachable **inside or outside**
  the platform from any surface, via the same API+MCP pattern. **Rule: everything gets an API; every API
  gets an MCP.** Exposed **token-efficiently via progressive disclosure** — `search_tools` → `describe_tool`
  on demand → `invoke_tool` → `get_ref` (paged); start with a search tool + name-only catalog, never dump all
  schemas into context (dial-stack `gateway.ts` pattern; ADR-0023, Phase C). (Implements minimize-custom +
  the serve/consume topology; registry + ContextForge carry it. Workflow *design* = a future brainstorm — see HANDOFFS.)
- ~~**SurrealDB = store/session/memory + bitemporal-record layer (LOCKED 2026-06-13; ADR-0024, amended by ADR-0027).**~~
  **SUPERSEDED by ADR-0043 (2026-08-02 accepted; flatten executed 2026-08-04): SurrealDB exits the critical path.**
  The Agno operational store (sessions/memory/metrics/eval/traces/spans) is **PostgresDb** — `server/core/session.py::get_agno_db`
  delegates to `get_postgres_db()`. Two drivers of the reversal: agno's SurrealDb backend implements none of the
  learning protocol (every memory lane was a silent no-op), and a second registered `db.id` armed agno's multi-db
  gate so any route omitting `db_id` returned 400. **SurrealDB is RETIRED, zero callers** (owner ruling
  2026-08-06, stated plainly in `server/core/session.py`'s `SURREALDB_*` comment — nothing in the platform
  uses it: `get_agno_db()` is Postgres, and `get_surrealdb_legacy()` has ZERO callers) — reversible by design,
  exported with sha256 manifests to `_stale/surreal-export-20260804` + `/data/agno/backups/`, container still
  answering read-only on ovh-data (100.119.96.29 — the one data-tier host default that legitimately did NOT
  move to ovh-files, since the parked container itself never moved), **only the owner deletes**.
  `get_surrealdb_legacy()` exists solely to construct a one-off read-only reconciliation handle.
  _Recorded unchanged below for provenance — it was true when locked on 2026-06-13:_ consolidate AgentOS
  sessions+state + memory + the **bitemporal evidence-record store** (native valid+transaction time) onto
  **SurrealDB**. ⚠ The vector/Knowledge role moved to Milvus (ADR-0027) — and has since moved again to **Weaviate**
  (ADR-0040). **Custom Graphiti STAYS** the bitemporal *cognition* substrate (VIP — NOT replaced; different altitude).
- **Milvus = the platform-wide VECTOR/ANN substrate (LOCKED 2026-06-13; ADR-0026 + ADR-0027). LIVE on ovh2.**
  Self-hosted **Milvus 3.0 standalone (embedded etcd + local storage + WoodPecker) + Attu v3**, Coolify-deployed
  on ovh2 from the `milvus-coolify` repo — **off** the managed Zilliz `aws-eu-central-1` cluster. **Everything
  that needs similarity search lands in Milvus** (one collection per embedder/domain): the `claude-context` code
  index, the **Case Bible** corpus, the **domain-partitioned Knowledge engine**, and evidence-text embeddings —
  via **Agno's native Milvus integration** (off-the-shelf). Gains **hybrid dense+sparse/BM25** retrieval. Reachable
  over Tailscale (`100.91.190.107`: gRPC 19530, Attu UI 3000); mapped (bind-mount) volumes at `/data/milvus/volumes/*`
  (owner backup preference); auth on (`root:Milvus`, rotate). Embedder unchanged (OpenRouter `codestral-embed-2505`,
  1536-d). Beta-aware: code/Case-Bible now; **Knowledge-engine migration off pgvector = Phase B/D** (accept beta or
  pin GA then). Deploy gotchas recorded in [[milvus-coolify-decision]] memory.
  ⚠ **Engine choice superseded by ADR-0040 (2026-07-27): Weaviate LOCKED** — see the next entry;
  ~~Milvus stays sidelined-but-up until cutover is verified, then parks (FalkorDB status).~~
  **Corrected 2026-08-12:** the Milvus→Weaviate cutover was ruled **VERIFIED 2026-08-09**
  (D-042; pymilvus removed from the image, Dockerfile) and the `data-vector` app has been
  **DOWN deliberately since 2026-08-10** (6th embedded-etcd corruption — docs/COORDINATION.md).
  The "LOCKED / LIVE on ovh2" claims above are historical; **Weaviate is THE vector store.**
- **Weaviate = the platform-wide VECTOR/ANN substrate (LOCKED 2026-07-27; ADR-0040 — supersedes
  ADR-0026/ADR-0027 on the engine choice).** Single Go binary on the data tier replaces the
  Milvus 4-container convoy (etcd fragility — lived 07-21→23 outage — plus data corruption and
  a heavy footprint for unused components). No practical HNSW dim cap → keeps the nv-embed-v1
  4096-d embed contract with NO re-embed; native hybrid BM25+vector. Collection-shape ADRs
  0010/0011 carry over unchanged. **Execution underway:** the `data-weaviate` Coolify app is
  deployed & healthy on ovh-data (verified live 2026-07-29); ~~data cutover + verification still
  pending~~ → **corrected 2026-08-14:** cutover + verification VERIFIED 2026-08-09 (D-042;
  pymilvus removed from the image, `data-vector` down deliberately since 2026-08-10) — steps in ADR-0040.
- **Memgraph = ADDITIVE temporal GraphRAG layer, read-side only (LOCKED 2026-07-28; ADR-0041).**
  Variant B (classic Memgraph analytical projection). NEVER a system of record — Neo4j/DozerDB
  stays (Semantica is Neo4j-bound; Graphiti's supported backends exclude Memgraph). Orchestration
  is Agno-native. Variant A (MemGQL federation) parked as an experiment.
- **Portkey = the MODEL gateway; LiteLLM RETIRED (owner ruling 2026-07-29; ADR-0042 — supersedes
  ADR-0015).** Portkey has carried the Graphiti lane + exec-tier since 2026-07-19 (11-provider
  failover, 4-key Gemini rotation, configs committed under `docker/gateway/portkey/`; decoupling
  proven through a 40-min exec-tier outage). LiteLLM is deprecated pending teardown — a separate
  owner-gated task (incl. remapping OpenCode's model config); until then nothing NEW points at it.
- **Graphiti/memory-lane ADRs 0036–0039 ACCEPTED (owner 2026-07-29; Proposed 2026-07-13):**
  DozerDB multi-DB with RBAC-scoped writers — `memory` vs `evidence` isolation (0036; **LIVE
  2026-07-30** — `data-neo4j` = `graphstack/dozerdb:5.26.27.0`, same upstream version so no
  store migration; `memory` + `evidence` created and isolation-verified. ⚠ Two caveats: DozerDB
  only accepts the PLAIN `CREATE DATABASE x` form — `IF NOT EXISTS`/`WAIT` return a misleading
  "Unsupported administration command"; and **RBAC roles are unimplemented upstream**, so the
  wall is database-scoped (blocks accidents) not permission-scoped (does not block a caller
  holding the `neo4j` superuser credential). Phase 2 = move Graphiti onto `memory`) · Graphiti
  MCP as a write-enabled ContextForge virtual server, standalone `:8071` no-auth door to be
  retired (0037) · Agno agents use `graphiti-core` in-process, the MCP door serves GUI clients
  only (0038) · Graphiti extraction LLM = hosted structured-output provider, never small/local
  (0039 — live in practice since 2026-07-04: NIM nemotron guided-JSON, lane routed via Portkey).
- **Use Agno's NATIVE surface — do NOT rebuild it (validated against agno docs 2026-06-13).**
  AgentOS = Runtime (FastAPI serving agents/teams/workflows) + **Control-plane UI** (manage/
  monitor/debug) + a **Chat UI** (chat with agents, run workflows; open-source Next.js "AgentUI",
  self-hosted, DB-only). **Multi-surface interfaces are built in**: AG-UI (CopilotKit/Dojo),
  Slack, WhatsApp, Telegram, A2A — one agent answers on all, memory follows the user across
  surfaces. Plus native: sessions, memory, knowledge, evals, config (quick-prompts/per-domain
  models), auth/JWT. → We **do not build** a custom chat UI, control UI, or multi-surface
  serving; we configure Agno's. (Note: this reframes the "multi-surface gateway" — Agno already
  serves agents to many surfaces; IBM ContextForge is specifically the *MCP-tool* gateway layer.)
- **Tool gateway = IBM ContextForge, NOT custom, NOT DIAL (locked 2026-06-13).** The
  multi-surface tool-gateway (serve/consume/route/proxy MCP tools across surfaces) is
  **IBM ContextForge MCP Gateway (`IBM/mcp-context-forge`)** — off-the-shelf, per the
  minimize-custom rule. **Agno is the agent-orchestration core** (not the gateway). The
  prior AI-DIAL attempt (`dev-resources/Archives/dial-stack`) is a **parts/pattern donor
  only** (DIAL runtime dropped). ⚠ The ContextForge **tool gateway** is distinct from the
  **LLM/model gateway** (LiteLLM, ADR-0015) — don't conflate the layers. *(Needs an ADR;
  supersedes the earlier "Agno-native gateway, ContextForge fallback" framing.)*
- **Donor reconciliation (locked 2026-06-13):** Python `chatminer` (10 AI-chat parsers
  + segmenter) gets **vendored** into `server/tools/parsers/ai_chat/` as atomic modules
  (replacing the 4 shallow placeholder parsers; done — see ADR-0035). dial-stack's
  TypeScript capabilities (forensic parsers,
  pattern-analyzer, timeline, bi-temporal Graphiti, document-intelligence engines incl.
  Google DocAI + IBM watsonx, ~100-tool catalog) are **wrapped as MCP services behind
  Agno** — no mass rewrite. Full inventory: `docs/EVIDENCE_MERGE_MAP.md`.
- **No-stub rule:** unavoidable stubs get `# STUB:` markers + a row in
  `docs/DEBT.md`. Tests are harness-first.
- **HITL is first-class:** every write (ingestion/normalization/evidence/config/db)
  pauses for recorded human approval. Trash-only for any cloud cleanup; never
  permanent-delete. `Secrets/` and case-data dirs are NEVER ingested into Knowledge.

---

## 6. Roadmap

**This round (~~plan: `plans/logical-herding-forest.md`~~ — that file/dir never
shipped into this repo; forward planning lives in `docs/BUILD_PLAN.md`, see the
pointer below — corrected 2026-08-09) — Part 1 complete + memory substrate:**
- P0 ✅ debt register + embedding query-mode fix + persistent duckdb R2 secret
- P1 ✅ (2026-06-12) HITL fully NATIVE on agno 2.6.13: `@approval` +
  `requires_confirmation` → pause persists pending row; `POST /approvals/{id}/resolve`
  records decision; continue gated by `require_approval_resolved`; real
  `apply_db_modification` (analysis-only write, evidence-ref guard). Custom
  approval table/routes removed. Cloud Drive Cleanup agent removed from active
  topology (owner: separate future feature).
- P2 evidence spine 🟡 **parser core-swap DONE** (verified 2026-07-11), **pipeline/schema
  population still open**. Directory layout repacked twice since this line was written:
  ADR-0033 server/ repack merged+deployed 2026-07-09; ADR-0035 tools sub-namespacing
  merged+deployed 2026-07-10 (see that ADR's Outcome section). Chatminer vendoring landed —
  `server/vendored/chatminer/` + 11 real parser modules in `server/tools/parsers/ai_chat/`
  (9 chatminer-backed, 2 genuinely custom formats — claude.ai export JSON, Claude Code
  JSONL — chatminer has no equivalent); `DEBT.md` marks "Backend atomic tools attached"
  resolved 2026-07-10. Still open: "Evidence schemas populated by a real pipeline" remains
  `planned` (`DEBT.md`) — live PG evidence schema is near-empty (`evidence_hash`=26 rows,
  verified 2026-07-11); the RESTART-0001 per-source raw-table redesign (6 `source.*` tables
  + `file_custody` anchor, h1/h2/h3 as row columns) is DRAFT awaiting owner sign-off (D-008,
  `docs/DECISION_LOG.md`) and the old ingestion schema is DEAD per owner. **Corrected
  2026-08-23 (CH-15/CH-16):** migrations `0026`–`0030` are no longer "held" — direct
  introspection of live PG18 (`100.91.190.107:5432`, db `ai`) showed `0026`–`0029` were
  already applied despite stale "HELD FOR OWNER / NOT APPLIED" banners (now restamped in the
  sql files themselves), and `0030` was applied that same night on owner instruction. The
  `working.vw_spine_horizon` wrong-clock defect that `0028` fixes is confirmed live in
  production. This does not close "Evidence schemas populated by a real pipeline": the new
  tables (`realization_event`, `walk_ledger`, `matter`/`court_case`, …) exist and are
  schema-only — the gap is the ingest pipeline populating them, not the schema. See
  `docs/DEBT.md` and §10 below for the activation steps (collection creation, backfill,
  alias switch, deploy) that remain held.
- **Temporal P0 scaffold underway (2026-08-23, D-067/CH-16):** live `temporal` role +
  `temporal`/`temporal_visibility` databases created on the existing PG18; Coolify compose
  scaffold (`deploy/temporal/compose.temporal.yaml`) and the worker image
  (`docker/temporal-worker/Dockerfile`) committed. Not yet done: `server/temporal/worker.py`
  (the worker entrypoint) and any workflow/Activity code — tracked as P1. See
  `docs/plans/TEMPORAL-INTEGRATION-PLAN-2026-08-23.md`.
- P3 bitemporal substrate (valid/knowledge-time + disclosure-tier; Semantica stand-up)
- P4 SBV as Workflow A (custody-gated vertical + iframe + CLI + export) 🟡 **largely landed,
  updated 2026-08-09**: forensic fork LIVE in prod with H1/H2/H3 custody hashing
  (`ghcr.io/cursedpotential/sbv-forensic:0.2.3-forensic`, deployed 2026-07-09); all 14 facade
  tools registered in ContextForge virtual server `platform_tools` (2026-07-10; this remains a
  bounded external publication key after the 2026-09-12 runtime rename). **PR #18
  merged 2026-08-06 (`aacf21c`, landing `feat/sbv-universal-parser`, 19 commits) — the
  universal import engine + governed repair slice**: `vendored/sbv` (Go) becomes a plugin
  import engine (Facebook JSON, Google Chat, Google Voice HTML, messaging CSV/HTML/TXT,
  NDJSON, SMS XML, email .eml/.mbox importers); the platform client moved from whole-corpus
  reads to import-scoped records/rejections/custody/attachments (`server/tools/_sbv_client.py`
  — closes the false-provenance risk behind the 2026-08-02 SBV demotion, `docs/DECISION_LOG.md`);
  `server/tools/gateway/execution_audit.py` writes an append-only SHA-256 hash chain of
  operation metadata; `server/api/repair_routes.py` keeps approval-required writes
  operator-authenticated; the Operator Workbench gained a Repair Lab (`/repairs`). **SBV
  promoted from shadow back to primary** on this basis (owner directive 2026-08-05: "sbv
  lives inside the Agno mono repo"; D-040). Still open, tracked in `docs/DEBT.md`'s
  parser-lane queue: streaming/batch ingestion contract (item 2), registry priority/quality
  metadata (item 3), ChatMiner hardening (item 4), repair-layer wiring sequencing (item 5).
  Phase 5a: **SHIPPED** (verified 2026-08-09, D-042): the automation branch was merged in the
  fork, tagged `v0.2.4-forensic` (fork `main` == tag head), CI published the image, and
  `deploy/docker/tool-runtime/Dockerfile` pins `ghcr.io/cursedpotential/sbv-forensic:0.2.4-forensic`.
  ~~TODO(OQ-9)~~ resolved. The stale "not yet pushed through subtree→fork→CI→tag-bump" note in
  `docs/COORDINATION.md` predates this. Residual (minor): confirm whether v0.2.4 restored the
  `heic` build tag dropped in v0.2.3, or HEIC stays routed around. Phase 5b `/x/sbv/` UI embed
  remains deferred to the G2/VPS window.
- P5 harness-first tests + backups to R2

> **Forward build sequencing now lives in `docs/BUILD_PLAN.md`** (Phases A–E + Part 2/3),
> derived from the owner's critical path (transcript knowledge-gathering FIRST → bootstrap
> loop) and `EVIDENCE_MERGE_MAP.md` §5. `docs/planning/*` (EXECUTION_PLAN, BUILD_TODO,
> MIGRATION_PLAN_v8, …) is **build history**, superseded for forward work by BUILD_PLAN.

**Next rounds:**
- **Part 2** — multi-pass analysis engine (knowledge horizons, pass-delta surfacing).
- **Part 3** — AI Legal Team (port Gemini Gems personas to Agno; strategy/docs/filings).
- **Knowledge engine** — domain-partitioned collections + ingestion of all
  conversation domains (timeline/personal/design/legal).
- **Hardening** — evidence-text embeddings at scale in **Weaviate** (the locked platform-wide
  vector substrate — ADR-0040 2026-07-27, superseding the Milvus lock ADR-0026/ADR-0027;
  ~~Milvus stays sidelined-but-up on the `data-vector` Coolify app until cutover is verified~~
  → **corrected 2026-08-14:** cutover VERIFIED 2026-08-09 (D-042) and `data-vector` is DOWN
  deliberately since 2026-08-10 (6th embedded-etcd corruption); Weaviate is THE vector store);
  multi-user auth; V2 slim Graphiti image.

---

## 7. Access & credentials (POINTERS — secrets live in gitignored `.env`, local + VPS)

- VPS: `ssh -i ~/.ssh/ovh debian@40.160.5.19` (sudo passwordless). n8n box:
  same key, `debian@74.208.130.34` (sudo password-gated).
- Tailscale: admin API key in `.env` (`TAILSCALE_API_KEY`) mints auth keys.
- R2 `nexus`: `R2_*` in `.env` (account `1a7406c497493a52128bb282f499e7b8`).
- Providers in `.env`: `OLLAMA_API_KEY` (primary), `NVIDIA_API_KEY`,
  `GOOGLE_API_KEY` (gemini-2.5-pro), `GROQ_API_KEY`, `OPENROUTER_API_KEY`,
  `LITELLM_MASTER_KEY`. Kasm `KASM_VNC_PW`. Neo4j `NEO4J_PASSWORD`.
- URLs (tailnet; box IPs in §4): AgentOS `ovh-app:8000` (`/config`, `/docs`, `/approvals`),
  SBV `:8080`, OpenCode `:4096`, Kasm `:6901` (https), Neo4j Browser `ovh-data:7474`,
  Graphiti MCP `:8071/mcp` (Host-header override; door retirement pending per ADR-0037),
  LibreChat `ovh-files:3080`, Homepage `ovh-app:3010`, workbench console `:8020`.
  LiteLLM `:4000` deprecated (ADR-0042 — do not wire anything new to it).

---

## 8. Gotchas (hard-won, do not relearn)

- agno ~~2.8.0~~ **2.8.7** (2.6.9→2.6.13 on 2026-06-12; →2.8.0 on 2026-07-23; →**2.8.7** pin per `requirements.txt:3`, drift-fixed 2026-08-14): embedders/rerankers under `agno.knowledge.embedder/.reranker`; Team
  mode needs `TeamMode` enum (strings break `/config`); `requirements.txt` is
  `uv pip sync`'d → new pkg needs its transitive deps listed; EntityMemoryStore
  has no PROPOSE mode (falls back to ALWAYS); 2.8.0 stopped bundling per-provider
  model SDKs as transitive deps → every provider in the ADR-0008 chain must be an
  explicit dependency (see the comment in `pyproject.toml`).
- NIM embedqa REQUIRES `input_type`; asymmetric (passage for docs, query for search).
- Graphiti image (zepai): embeds an UNUSED FalkorDB (`BROWSER=0`); `CONFIG_PATH`
  env ignored → mount config OVER `/app/mcp/config/config.yaml`; MCP endpoint
  `/mcp` (no trailing slash); Host-header DNS-rebind guard → `header_provider`
  `{"Host":"localhost:8000"}`; LLM factory drops `api_url` → `OPENAI_BASE_URL` env.
- SBV binary is musl-linked → carries `ld-musl` + Alpine `/usr/lib` +
  `LD_LIBRARY_PATH=/opt/sbv-libs`; listens :8085 internal; data dir `/opt/sbv/data`.
- AgentOS: `base_app=` + `get_app()`, NEVER `app.mount`; NEVER uvicorn reload with MCP.

---

## 9. Where things live

- **The 5 authoritative docs (§0 Document Contract):** `docs/PROJECT_CANON.md` (this),
  `docs/EVIDENCE_MERGE_MAP.md` (inventory), `docs/BUILD_PLAN.md` (plan),
  `docs/REPO_STRUCTURE.md` (structure), `docs/CONVENTIONS.md` (style).
- Subordinate: ADRs `docs/adr/` (index `README.md`); Debt `docs/DEBT.md`; build
  history `docs/planning/*`; living wiki `docs/wiki/` (ADR-0022, deferred); glossary.
- Mined reusable code: `extracted-code/` (+ `MANIFEST.md`) — SBV, parsers,
  extractors, schemas, ontologies (MCL 722.23, behavioral patterns).
  **LOCATED** (~~TODO(OQ-2)~~ resolved 2026-08-09, owner ruling + device
  verification): lives at `E:\AI_Workspace\Projects\the-platform-workspace\extracted-code\`
  — sibling of this repo, one level up — with a backup `extracted-code.zip`
  beside it (25 MB, fresh as of 2026-08-06). Reference is workspace-relative
  (`../extracted-code/` from this repo's root).
- **Donor archives (READ-ONLY)**: `dev-resources/Archives/` — `dial-stack` (TS
  forensic/analysis/gateway donor, DIAL dropped), `Agno-MCP-Platform-alpha/chatminer`
  (parser core to vendor). **Part-2 behavioral ML "Tether"** lives at
  `dial-stack/utilities/apps/ml-nlp/Tether/` (deferred external-libs area;
  `SamanthaStorm/tether-*` HF models — dig in when Part 2 is built).
  **All three paths above (`dev-resources/Archives/`, `Agno-MCP-Platform-alpha/chatminer`,
  `dial-stack/…/Tether/`) are WORKSPACE-ROOT-relative** — siblings of this repo under the
  workspace root (see the workspace-root `CLAUDE.md`: `dev-resources/` = read-only donors),
  NOT paths inside this repo. Verified 2026-08-09: none of them resolve under this repo's root.
- Agent auto-memory (loads on session start): `C:\Users\matts\.claude\projects\E--AI-Workspace\memory\`.
- **Matter/case identity (amended 2026-08-15 by ADR-0055 / D-060):**
  `working.normalized_record.case_id TEXT NOT NULL DEFAULT 'primary'`
  (`sql/0018_retrieval_axes.sql`) remains a Knowledge **partition key** and is
  never cast to UUID. It is no longer the universal identity for every case-work
  concept. One enduring `Matter` may contain multiple `CourtCase` proceedings;
  `analysis.matter_knowledge_partition` maps legacy text partitions such as `primary` to
  the Matter explicitly. New case-work carries `matter_id` and `court_case_id`;
  historical UUID `case_id` columns remain compatibility fields until their
  provenance is reconciled. This narrowly supersedes D-041's identity-model
  consequence while preserving its single-owner and single-client/matter scope.

---

## 10. Open threads / parking lot

- **ADR-0056–0059 Phase 0/Phase 1 design — owner review complete; activation still held:** logical
  contracts, unresolved-question inventory, gold/evaluation specification, synthetic
  planted-future-fact contract tests, and the compact owner packet are indexed in
  `docs/HANDOFF-2026-08-16-R12-surreal-investigation-owner-rulings.md`. D-064 records S1–S6:
  exclusive post-parity Surreal retrieval, shared-Context walks, sealed historical
  snapshots plus linked rewalks, horizon-local candidate beliefs, midpoint-plus-HITL
  realization, source-family corroboration, separate acquired-third-party projections,
  three-clock semantics, and resumable-vs-terminal walk transitions. Disposable Phase-1
  design may proceed;
  target creation, physical schema, activation, corpus copy, deploy, production agent binding,
  and Graphiti replacement remain held; all R9 activation holds continue unchanged.
- **Native evidence vectors accepted; cutover held (ADR-0059 / D-066):** the evidence-vector
  projection moves off Agno's JSON metadata schema to immutable `EvidenceChunkV1`, with typed
  `occurred_at` and range-indexed `source_available_from`, self-provided 4096-d nv-embed vectors,
  and the stable `EvidenceChunks` reader alias. The old Agno evidence collection stays intact as
  rollback. ~~Collection creation, migrations `0026`–`0029`, backfill, alias movement, live
  reader binding, and deployment remain owner-gated~~ **Corrected 2026-08-23 (CH-15/CH-16):
  the SCHEMA is applied** — direct introspection of live PG18 confirmed `0026`–`0029` were
  already live (stale banners, now restamped in the sql files). **Still held:** live Weaviate
  collection creation, PG-chunk backfill, the count/hash/canary reconciliation, the
  `EvidenceChunks` alias switch, reader rebinding, and deploy — none of those activation steps
  have run. Follow the held runbook in
  `docs/plans/WEAVIATE-NATIVE-EVIDENCE-CUTOVER-RUNBOOK-2026-08-18.md`.
- Owner had one more idea that slipped away (2026-06-11) — to be added when recalled.
- Knowledge-engine domain separation: finalize collection scheme + ingestion routing.
- Legal Team: inventory the Gemini Gems personas to port.
- ~~**SurrealDB — strong consolidation candidate (validated 2026-06-13).**~~ **Historical
  operational design superseded by ADR-0043. New role accepted 2026-08-15 by ADR-0056:**
  governed analytical projection plus experimental platform-owned Spectron-compatible walk
  memory; the parked legacy deployment remains read-only and no activation is implied. Historical
  rationale, kept for provenance: Multi-model
  (document + relational + vector + graph + live queries), AND **Agno supports it natively
  as a database (agent/team/workflow sessions+state) + vector store (Knowledge/RAG) + memory
  backend** (`/database/providers/surrealdb`, `/knowledge/vector-stores/surrealdb`,
  `/examples/integrations/surrealdb`). So it could **consolidate** AgentOS db + pgvector
  Knowledge + memory into one off-the-shelf engine (fits minimize-custom). **NOT a replacement
  for custom Graphiti** (VIP — stays the bitemporal evidence substrate), and weigh against the
  already-LIVE pg_duckdb stack (ADR-0013). **DECIDED 2026-06-13 → see §5 Locked Decisions;**
  sequence the migration in Phase D. Does NOT block Phase A (parsers emit storage-agnostic
  `NormalizedRecord`s).
