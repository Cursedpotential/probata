# HANDOFFS — current execution index

> _Byline: Claude Code · Opus 4.8 · 2026-06-13_
> _Current-index conversion: Codex · GPT-5 · 2026-08-15; R14 update 2026-08-17._
> **Historical note:** the original task units are preserved below for provenance, but are
> superseded for forward work by the dated R0–R14 packets in this index.

## Current handoff set

| Lane | Current packet | Status at packet | Boundary |
|---|---|---|---|
| R0 | [Wave-1 audit](awaiting-verification/handoffs/HANDOFF-2026-08-15-R0-wave1-audit.md) | Complete / build failed | Audit only; migrations held |
| R1 | [Go ingestion](awaiting-verification/handoffs/HANDOFF-2026-08-15-R1-go-ingestion.md) | Partial | Coverage-based parsing and ordered custody |
| R2 | [Horizon engine](awaiting-verification/handoffs/HANDOFF-2026-08-15-R2-horizon-engine.md) | Partial | Immutable manifests, replay, contamination gates |
| R3 | [Semantica VIP](awaiting-verification/handoffs/HANDOFF-2026-08-15-R3-semantica.md) | Partial | Full intelligence behind governed candidate boundary |
| R4 | [Graphiti/Zep memory](awaiting-verification/handoffs/HANDOFF-2026-08-15-R4-graphiti-zep-memory.md) | **CLOSED — Graphiti retired 2026-08-27 (owner ruling; P-09 / GAP-008 zero-caller path). No bake-off pending: no candidate, no replacement store.** ~~Research complete~~ | PostgreSQL remains belief authority; ~~Graphiti projection~~ **no graph projection in this lane** |
| R5 | [AG2 coordination](awaiting-verification/handoffs/HANDOFF-2026-08-15-R5-ag2-coordination.md) | Research complete | Candidate adapter only; Agno remains current |
| R6 | [Provider switching](awaiting-verification/handoffs/HANDOFF-2026-08-15-R6-provider-switching.md) | Research complete | Portkey/OpenCode/direct route registry |
| R7 | [OpenCode workspace](awaiting-verification/handoffs/HANDOFF-2026-08-15-R7-opencode-workspace.md) | Partial | Persistent control; isolated execution |
| R8 | [Custom Workbench](awaiting-verification/handoffs/HANDOFF-2026-08-15-R8-workbench.md) | Partial | Framework-neutral operator product |
| R9 | [Knowledge to case MVP](awaiting-verification/handoffs/HANDOFF-2026-08-15-R9-knowledge-to-case-mvp.md) | Superseded in part by local build | Matter/CourtCase + evidence promotion, held/unapplied |
| R10 | [Surreal analytical memory and investigation design](awaiting-verification/handoffs/HANDOFF-2026-08-15-R10-surreal-investigation-design.md) | Complete design / build unknown | Governed Surreal projection, claim assembly, investigation and behavior |
| R11 | [Surreal investigation Phase 0](awaiting-verification/handoffs/HANDOFF-2026-08-16-R11-surreal-investigation-phase0.md) | Complete for owner review | Logical contracts, question inventory, evaluation gates, synthetic horizon canary, owner packet |
| R12 | [Surreal investigation owner rulings](awaiting-verification/handoffs/HANDOFF-2026-08-16-R12-surreal-investigation-owner-rulings.md) | Complete | S1–S6 settled; Phase-1 design authorized, physical work separately gated |
| R13 | [Phase-1 Surreal T0 reboot checkpoint](awaiting-verification/handoffs/HANDOFF-2026-08-16-R13-phase1-surreal-t0-reboot-checkpoint.md) | Paused / target stopped | Local gates pass; live projection fails closed; resume from sealed disposable state |
| R14 | [Phase-1 Surreal live core pass](awaiting-verification/handoffs/HANDOFF-2026-08-17-R14-phase1-surreal-live-core-pass.md) | ~~Core live gates pass / full set partial~~ — **superseded 2026-08-18, see below** | Target stopped; sealed snapshot, linked rewalk, and export/import parity remain |

R9's claim that Matter identity and the Knowledge-to-Evidence slice are missing is now
historical: those components are pushed to `main`, undeployed, and dependent on
unapplied migration `0030`. Commit `be286a8` adds redacted evidence/custody
inspection and blocks human review until the exact Matter-scoped detail loads; its
status is recorded in the newest R9 addendum.

R10 is documentation/design only. It authorizes no Surreal activation, corpus copy,
schema/migration, Graphiti replacement, or production change. Its goal hierarchy is
[`GOALS-2026-08-15-surreal-investigation-memory.md`](awaiting-verification/plans/GOALS-2026-08-15-surreal-investigation-memory.md)
and its consolidated technical contract is
[`SURREAL-INVESTIGATION-BLUEPRINT-2026-08-15.md`](awaiting-verification/plans/SURREAL-INVESTIGATION-BLUEPRINT-2026-08-15.md).

R11 executes the contract/evaluation portion of R10 Phase 0. The synthetic canary passes 14
tests, but no live adapter is verified. Six owner choices remain pending; Phase 1 and every R9
activation hold remain in force.

**R14 correction (Claude Code · Fable 5 · 2026-08-18):** the R14 packet itself now carries a
2026-08-18 ADR-0059 supersession addendum stating its observed results "predate the new
source-class, participant, plural-realization, derived-chunk, checkpoint/resume, and terminal-
rewalk contract and therefore are not current live proof." This index's own R14 row previously
did not surface that — a reader trusting only the table would over-credit R14's "core live gates
pass" as still current. It is not. Treat R14 as historical pending a rerun against the amended
ADR-0059 contract. Full independent audit:
[`OWNER-REVIEW-2026-08-18-verified-todo-audit.md`](OWNER-REVIEW-2026-08-18-verified-todo-audit.md).

## Historical task register — superseded for forward execution

> **Original contract:** the forward build, broken into SMALL self-contained units a cheaper /
> smaller-context agent can pick up and finish **without re-deriving context**. Entry point:
> `PROJECT_CANON.md` (§0). Companion: `BUILD_PLAN.md` (phase narrative).
>
> **How an agent uses one unit:** read (a) `PROJECT_CANON.md`, (b) the unit's *Refs*, (c) `CONVENTIONS.md`.
> Then do *Steps*, satisfy *Accept*, respect *HITL*. One unit = one PR-sized change. Don't exceed scope.
> **Tier:** `S` = small/cheap model ok · `J` = needs judgment (Opus/owner). **All writes are HITL-gated.**

## DONE this session (the ~70% — don't redo)
SSOT docs (canon/merge-map/build-plan/repo-structure/conventions/ADR_RECONCILIATION) · vendored
`chatminer/` (10 parsers + segmenter + artifacts) · `TopicTag` + `RELATIONSHIP_HISTORY` · segmenter
generalized + `_load_case_terms()` (config-load) · `case_terms.example.yaml` + gitignored real file ·
infra (new OVH VPS `51.81.83.191` docker host; gateways topology; VIPs; claude-context embedder = OpenRouter `codestral-embed`).

## VIPs — never overwrite (integrate around)
Agno (+ native chat/AgentOS UI) · **custom Graphiti** · Semantica · **IBM ContextForge** · **forked SBV** · CopilotKit. Keep: LiteLLM (model gateway), OpenCode, agent-sandbox, persistent Kasm.

---

## TRACK 0 — CANONICAL SCHEMAS (the crux; blocks A-normalize, B, D). Schemas already inventoried — see `EVIDENCE_MERGE_MAP.md` §2.2/§2.6/§7-8 and the source files cited per unit.

### H0.1 — `Entity` schema + canonical model `[S]`
- **Goal:** one pydantic `Entity` consolidating every donor entity schema.
- **Refs:** dial-stack `drizzle/schema.ts::documentEntities` (entityType, entityValue, normalizedValue, occurrenceCount, firstOccurrence, confidence, extractorModel) · Chat Parser v2.0 `entities.jsonl` (types person/org/project/tech/location/concept, aliases) · Salem Ontology v3 entities · `server/mcp/storage/graphiti-client.ts::Entity` (mclFactors) · ChatMiner `core/types.py::ArtifactType.ENTITY`.
- **Steps:** create `evidence/schemas/__init__.py` + `evidence/schemas/entity.py` — fields: `id, type, value, normalized_value, aliases[], confidence, first_occurrence, occurrence_count, source_refs[], mcl_factors[], attrs`.
- **Accept:** pydantic model imports; round-trip `to_dict/from_dict` test in `evals/`.
- **HITL:** none (schema only). **Tier S.**

### H0.2 — `Relationship` schema (bitemporal) `[S]`
- **Refs:** `graphiti-client.ts::Relationship` (valid_from/valid_to, mclFactors) · Salem edges.
- **Steps:** `evidence/schemas/relationship.py` — `id, from_entity, to_entity, type, valid_from, valid_to, confidence, mcl_factors[], source_refs[]`.
- **Accept:** model + test. **Tier S.**

### H0.3 — `Event` + relationship-timeline schema `[J]`
- **Refs:** Chat Parser v2.0 `events.jsonl` (subtypes milestone|decision|meeting|incident|change|memory|upcoming; temporal historical|current|future) · `timeline-generator.ts::TimelineEvent` + cycle-of-abuse phases · Salem incidents/statements · `NormalizedRecord` (occurred_at/knowledge_time/disclosure_tier).
- **Steps:** `evidence/schemas/event.py` — `id, event_type, temporal_class, occurred_at, knowledge_time, disclosure_tier, participants[](entity ids), related_entities[], summary, source_refs[], mcl_factors[]`. A **relationship timeline** = ordered Events filtered to a pair/among entities.
- **Accept:** model + a test building a 3-event timeline for two entities. **Tier J** (the crux — judgment on the model).

### H0.4 — Storage tables migration `[J]`
- **Refs:** dial-stack `drizzle/production-message-schemas.ts` + `drizzle/schema.ts` (documents→sections→chunks→spans→summaries→entities, evidenceChains, **mclFactors (12)**, behavior categories, exhibit numbers) · `migrations/004_chain_of_custody.sql` (Ed25519) · spine `sql/0002`, `sql/0003`.
- **Steps:** `sql/0004_entities_events_relationships.sql` — tables for entities, relationships, events (in `analysis` schema), + mcl_factors reference table; FKs to evidence rows; indexes on entity value/type, event occurred_at.
- **Accept:** migration applies clean on the VPS PG18; `\d` shows tables. **HITL:** schema write → owner approve. **Tier J.**

### H0.5 — Entity-extraction atomic tool `[J]`
- **Refs:** `server/python-tools/nlp_runner.py` (spaCy `en_core_web_lg` NER, aliases, confidence) · Chat Parser v2.0 entity design (first-mention, mention counts).
- **Steps:** `evidence/tools/extract_entities.py` — `@register(capability="extract.entities")`; input text/records → `Entity[]` (H0.1) with aliases/confidence/first-mention.
- **Accept:** runs on a sample transcript, emits ≥1 person entity w/ confidence + first_occurrence. **HITL:** none (read-only extract). **Tier J** (entity extraction = crux).

---

## TRACK A — PARSER CORE (most done; storage-agnostic)

### HA.1 — ChatMiner→NormalizedRecord adapter `[J]` — **DONE 2026-07-04** (`evidence/tools/_chatminer_adapter.py`)
- **Refs:** `chatminer/core/types.py` (ParsedMessage/ParsedConversation) · `evidence/normalize.py` (NormalizedRecord).
- **Steps:** `evidence/tools/_chatminer_adapter.py` — map ParsedMessage→NormalizedRecord (content→content, sender_role→role, timestamp→occurred_at, source_format→source, conversation_id, everything else→attrs incl. message_hash, content_type, artifacts, segment topic_tag).
- **Accept:** unit test: a 2-message ParsedConversation → 2 NormalizedRecords with occurred_at set. **Tier J.**

### HA.2 — Per-format `@register` wrappers (10 tiny units) `[S]` — **DONE 2026-07-04** (all 10 under `evidence/tools/`, each gated on the parser's own `can_parse` confidence + hard-fail on zero records)
- **Skeleton** (one file per format under `evidence/tools/`, e.g. `chatgpt_official.py`):
  ```python
  from __future__ import annotations
  from evidence.registry import register
  from evidence.tools._chatminer_adapter import to_normalized_records
  from chatminer.parsers.chatgpt_official import ChatGptOfficialParser
  @register(id="transcripts.chatgpt-official", capability="parse.transcript",
            description="ChatGPT official JSON export -> NormalizedRecords",
            accept=lambda hint, size: hint.endswith(".json"),
            provenance="vendored: chatminer/parsers/chatgpt_official.py")
  def run(payload: dict) -> dict:
      result = ChatGptOfficialParser().parse_file(payload["path"])
      return {"records": [r.model_dump() for r in to_normalized_records(result)]}
  ```
- **The 10 (one sub-unit each):** chatgpt_official, chatgpt_share, gemini_chrome, gemini_json, claude_md, claude_code, perplexity_gdpr, perplexity_plugin, perplexity_md, generic_md.
- **Accept:** `load_builtin_tools()` registers all under `parse.transcript`; each parses its sample. **Tier S** (identical pattern — ideal for a small agent, one file at a time).

### HA.3 — Populate `evidence/config/case_terms.yaml` `[owner]`
Copy `case_terms.example.yaml` → `case_terms.yaml`; fill real names/places/child name per `TopicTag`. **HITL:** owner-only (PII). **Tier owner.**

### HA.4 — Retire 4 placeholders + registry smoke test `[S]` — **DONE 2026-07-04 (amended)**
Only `chatgpt_export.py` was still a duplicate (chatminer `chatgpt_official` covers the same
mapping-tree format) — deleted. The other three had grown into REAL coverage chatminer lacks
and are KEPT: `claude_ai_export.py` (claude.ai `chat_messages` JSON — no chatminer parser),
`claude_code_jsonl.py` (REAL session `type`/`message`/`sessionId` events — chatminer's
`claude_code` only parses the simple role/content lines), and the whole-file fallback
(renamed `markdown_transcript.py` → `whole_file_fallback.py` so it registers LAST: it never
rejects a non-empty file, and alphabetical auto-discovery order = substitution order).
Registry smoke test: `tests/test_transcript_tools.py` (13 `parse.transcript` tools, fallback last).

### HA.5 — Deploy + VPS smoke test `[J]` (RUNBOOK below)
Sync to VPS, rebuild image (chatminer + pyyaml + sentence-transformers deps), parse a real export end-to-end. **HITL:** deploy = owner go. **Tier J.**

---

## TRACK B-E + PART 2/3 (compact stubs — expand when reached; each becomes its own small-unit set)

- **B — Knowledge ingestion + domain routing (bootstrap loop) `[J]`:** route segmented records into domains (`platform_design`/`legal_strategy`/`timeline_relationship`/`personal_history`) by segment tag; ingest design+legal history first so Builder agents can answer "what did we decide". Refs: canon §3.
- **C — IBM ContextForge gateway + serve agents `[J]`:** stand up ContextForge (off-the-shelf) as the MCP tool gateway; register spine + dial-stack tools; serve our agents via Agno MCP-server/A2A/AG-UI. Refs: canon §5 topology.
- **D — Bitemporal substrate + SurrealDB decision `[J]`:** keep **custom Graphiti** (VIP) for cognition; decide **SurrealDB** as store/session/Knowledge/memory consolidation (Agno-native); wire two-pass (multi-pass-classifier=Pass1, forensic-workflow shape on Agno). Refs: canon §10, EVIDENCE_MERGE_MAP §2.6/§8.
- **E — Forensic verticals `[J]`:** **forked SBV** (VIP) + SMS/FB/iMessage parsers + sqlite-WAL deleted-message recovery + Ed25519 custody hardening + harness tests + R2 backups. Refs: EVIDENCE_MERGE_MAP §2.1/§2.7/§8.
- **Part 2 — Behavioral `[J]`:** wrap **Tether** (`dial-stack/utilities/apps/ml-nlp/Tether`, HF models) + ConflictAnalysisApp RuleEngine + pattern-analyzer (~25 MCL modules) as MCP services; map to mcl_factors. Deferred per owner until here.
- **Part 3 — AI LAW FIRM build-out `[J]`:** port the owner's **Gemini Gems personas** to Agno as a third agent family — strategy / motions / filings / discovery agents — using the **MCL 722.23 ontology** + imported Michigan legal skills + the evidence/knowledge/timeline outputs. Refs: canon §2 (Part 3), `ontologies/mcl_722_23.ttl`. (Inventory the Gemini Gems personas as the first sub-unit.)

## TRACK G — ONE-PLATFORM GUI + TOOL SURFACE (GUI scope only; Part-2 engines excluded)
Source: `docs/planning/gui-integration-spec.md` + `port-backlog.md` + `gui-build-plan.html`.
**Build order:** G1 → G4 → **[VPS window]** → G2 → G3 → G5 → G6. G1/G4/G5/G6 are offline-buildable; G2/G3 need the VPS.
**Locked decisions (owner, 2026-07-06):** shell = `ui/` dir IN-REPO · auth = single proxy JWT for everything (fwd-compatible w/ deferred multi-user, DEBT.md) · ContextForge target = **1.0.3** (upgrade the live 0.8.0 box to match before G3) · MVP page = tool catalog first, evidence browser second · `get_ref` store = local **SQLite** on the tool-finder host (SHA-256 keyed, WAL, TTL-swept) — R2 only for deliberate durable artifacts · AgentOS UI framed as-is under `/x/agentos/` first · Kasm + OpenCode each get a nav entry.
**Donor:** `Cursedpotential/mcp-tool-platform/client` (React 19 + Vite + shadcn/Tailwind; **do NOT port its tRPC/Node data layer** — bind FastAPI REST/OpenAPI + AG-UI). Consume only public contracts: AG-UI, agentos-api REST, platform-tools facade OpenAPI, ContextForge catalog API. Never bind parser internals (registry contract frozen).

### G1 — Shell scaffold `[J]` — offline
- **Goal:** one CopilotKit/Next.js shell (sidebar layout + chat) riding Agno AG-UI against agentos-api; the single first-class UI everything else mounts into.
- **Refs:** donor `client/src/components/DashboardLayout.tsx` + `client/src/components/ui/*` (~60 shadcn components — lift wholesale) · gui-spec §4.2, §5 · AG-UI served natively by agentos-api (:8000) · self-hosted `agent-ui` service (`docker/agent-ui/Dockerfile`, :3000) as interim/fallback chat.
- **Steps:** create `ui/` in-repo (Next.js + CopilotKit). Vendor `client/src/components/ui` + `DashboardLayout` into `ui/`. Wire the sidebar nav shell. Chat pane speaks AG-UI; **mock the AG-UI endpoint in dev** so G1 needs no live backend. Do NOT bring tRPC.
- **Accept:** `ui/` runs locally; sidebar nav renders; chat pane exchanges messages with a mocked AG-UI endpoint. No tRPC in the dep tree.
- **HITL:** none (scaffold, no writes to platform data). **Tier J** (shell architecture).

### G4 — `tool-finder` meta-MCP server `[J]` — offline
- **Goal:** port the owner's proven 4-endpoint gateway onto the Python registry so agents carry 5 meta-tools instead of 50+. (This IS port-backlog #8.)
- **Refs:** donor `server/mcp/gateway.ts` (search/describe/invoke/get_ref; 1431 ln) + `server/mcp/store/content-store.ts` (SHA-256, 4 KB paging) · `evidence/registry.py::manifest()` (id/capability/description/provenance) · platform-tools facade `/tools/*` + `/openapi.json` · ContextForge catalog API · gui-spec §4.1, §6 Level 2 · [CF #2230].
- **Steps:** new MCP server `evidence/tools/tool_finder/` exposing 5 meta-tools:
  `get_tool_categories()` (distinct capabilities + counts from `manifest()` + CF catalog) ·
  `search_tools(query, category?)` (compact cards: id/category/one-liner) ·
  `describe_tool(id)` (full schema on demand) ·
  `execute_tool(id, payload)` (**proxied back through ContextForge** so auth/rate-limit apply — no side-channel; large outputs return a content-addressed ref, not the payload) ·
  `get_ref(sha, page?)` (paged read). Build the ref store as **local SQLite** on the tool-finder host: table keyed by SHA-256 (bytes/size/created_at/ttl), WAL mode, byte-offset paging, TTL sweep. Meta-tool names mirror upstream #2230 + the old gateway for later swap-out.
- **Accept:** all 5 meta-tools answer against the live registry; a large result returns a ref; `get_ref` pages it back from SQLite by offset; TTL sweep drops an expired row.
- **HITL:** `execute_tool` runs real tools → all invokes remain HITL-gated per platform rule. **Tier J.**

### G2 — Reverse-proxy embed layer + shell nav `[J; per-embed S]` — needs VPS
- **Goal:** every supporting tool under one origin + one nav; cohesion via nav/origin/auth, not by forcing every app into a frame.
- **Refs:** existing Traefik labels / Caddy · gui-spec §5 (embed table), §4.4 (agent-ui), §4.5 (embed candidates) · services: SBV :8085, Attu :3001, Neo4j :7474, ContextForge Admin :4444, Kasm :6901, LiteLLM :4000, agent-ui :3000.
- **Steps:** mount each tool under `/x/*` on one origin (`/x/sbv/`, `/x/attu/`, `/x/neo4j/`, `/x/forge/`, `/x/kasm/`, `/x/litellm/`, `/x/agentos/`, `/x/chat/`, `/x/reports/` Evidence.dev, `/x/neodash/`, `/x/surreal/`, `/x/claude-history/`). Add shell nav entries (Kasm + OpenCode each get their own). **Single proxy JWT** in front of all of it. Per tool, decide iframe vs new-tab (verify `X-Frame-Options`/path-prefix breakage on the VPS) → record in a decision table. **One embed = one sub-unit (S).**
- **Accept:** every tool reachable under one origin/nav behind one auth; framing-refusers fall back to new-tab; decision table committed.
- **HITL:** proxy/auth config on VPS → owner go. **Tier J** overall, **S** per embed. Ends at DEPLOY RUNBOOK.

### G3 — ContextForge virtual servers + tags `[J]` — needs VPS
- **Goal:** category disclosure (Level 1) — one virtual server per capability family; each agent mounts only what it needs.
- **Prereq (Q5, hard):** live ContextForge is **0.8.0**; compose pins **1.0.3**. Upgrade the live box to 1.0.3 BEFORE this unit — virtual-server/tag APIs differ across versions.
- **Refs:** gui-spec §6 Level 1 · CF `POST /servers` (`associatedTools=[...]`) + universal tags/tag-filtering · Agno `MCPToolbox` mounts · registry capabilities (`parse.*`, `extract.*`, …).
- **Steps:** confirm CF is on 1.0.3. Create virtual servers `parsers`, `sbv`, `graph`, `knowledge`, `analysis` (via `POST /servers` or Admin UI); tag each tool with its category. Register `tool-finder` (G4) as a federated MCP server in CF and grant it CF-catalog read. Narrow each agent's `MCPToolbox` to its virtual server(s).
- **Accept:** an agent mounted on `parsers` sees only parser tools on `tools/list`; tool-finder reachable through CF; category counts match `manifest()`.
- **HITL:** CF config on VPS → owner go. **Tier J.** Ends at DEPLOY RUNBOOK.

### G5 — First-party pages `[J; catalog port S]` — offline vs fixtures
- **Goal:** the situation-specific pages that no off-the-shelf tool covers. **Catalog first (cheap port), evidence browser second.**
- **Refs:** donor `client/src/pages/Tools.tsx` (search → category pills → grouped cards → detail → **schema-driven "Test Tool" form**: enum→Select, bool→Switch, number, array; live invoke + latency) · native Agno `/approvals` · gui-spec §4.2–§4.3, §7 (G5) · `registry.manifest()` + CF catalog as the data source (NOT hardcoded `CATEGORY_INFO`).
- **Steps (sub-units):**
  - **G5a** port `Tools.tsx` → shell tool-catalog page, sourced from manifest + CF catalog; schema-driven tester invokes through tool-finder/CF.
  - **G5b** evidence browser + entity/contradiction timeline (new build; owner-value page).
  - **G5c** native `/approvals` page (HITL diff-preview UX; no custom approval table — Agno-native).
  - **G5d** workflow-runs view.
- **Accept:** catalog renders + invokes live tools with latency; approvals/runs/evidence pages work against fixtures.
- **HITL:** approvals page mediates real HITL gates. **Tier J** (G5a portable at **S**).

### G6 — Client-config generator `[S]` — offline
- **Goal:** one-click export of a capability family to an external MCP client. (Pairs with port-backlog #14.)
- **Refs:** donor `client/src/pages/McpConfig.tsx` + `server/mcp/config/mcp-generator.ts` (Claude Desktop / Gemini / OpenAI adapters) · gui-spec §7 (G6) · ContextForge virtual servers (G3) as the target.
- **Steps:** port `McpConfig.tsx` retargeted at CF virtual servers — "export the `parsers` category to Claude Desktop" emits a ready-to-paste config pointing at that virtual server (mint/scope an API key as needed).
- **Accept:** generates valid paste-ready configs for Claude Desktop, Gemini, and OpenAI, each pointing at a CF virtual server.
- **HITL:** key minting → owner go. **Tier S.**

## DEPLOY RUNBOOK (every Track-A/B/E unit ends here)
```
# from Agno-MCP-Platform/ — sync to VPS, rebuild, restart, verify
tar czf /tmp/sync.tgz chatminer evidence sql requirements.txt
scp -i ~/.ssh/ovh /tmp/sync.tgz debian@40.160.5.19:/tmp/
ssh -i ~/.ssh/ovh debian@40.160.5.19 'cd ~/agno-mvp && tar xzf /tmp/sync.tgz && \
  docker compose --profile tools up -d --build agentos-api && \
  docker compose exec agentos-api python -m evidence smoke'   # smoke = registry load + sample parse
```
(`requirements.txt` must add: `chatminer` deps — sentence-transformers, scikit-learn, pyyaml — and rebuild the image, not just restart.)

## NOT NOW — future brainstorm
**Workflows** (the named `agno.workflow` verticals A/B/C, orchestration, agent-to-agent flows): a **dedicated brainstorming session** with the owner — output gets added here as new units or built directly. Do not design workflows ahead of that session.
