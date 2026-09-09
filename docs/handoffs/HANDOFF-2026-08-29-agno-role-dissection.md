# HANDOFF — Agno role dissection (what Agno still does, and what it should)

> _Byline: Claude · Opus 5 · 2026-08-29, from an owner directive._
> _Ruling reconciliation: Codex · GPT-5.6-Sol · 2026-08-29._
> _Naming: written before the 2026-09-05 rename (D-137..D-141); see docs/NAMING.md for the old->new glossary._

STATUS: IMPLEMENTING — production-host, direct-caller, runtime-auth, Workbench object-store, and
stable private-surface slices are live. Temporal workflow and Agno Knowledge/provider replacement
remain active follow-on slices.
BUILD_STATUS: LIVE CUTOVER VERIFIED / BOUNDED RELEASE HOLDS — plain FastAPI, runtime-file auth,
private deployment naming, Workbench callers and fixed R2 source/staging buckets are deployed and
live-proven. LibreChat/hosted-Portkey MCP publication, native evidence activation prerequisites,
and later Agno workflow/Knowledge replacement remain explicitly held below.

## Implementation receipt — production-host slice (2026-08-29)

_Byline: Codex · GPT-5.6-Sol · 2026-08-29._

Implemented locally:

- `server.api.main` is a plain FastAPI composition root. A fresh-process import loads **zero Agno
  modules**; AgentOS routes, registry, generic agents/teams/workflows, scheduler, tracing, model
  picker, Knowledge construction, and `/mcp` are absent.
- Ordinary Platform API routes use one runtime-mounted bearer file, read again on every request.
  Missing/empty/unreadable state fails closed; rotation needs no rebuild or redeploy. Exact signed
  walk and owner-evidence routes retain their distinct local credentials.
- The exec service is named `platform-api`, has no public Traefik router, and is reached privately
  by Workbench as `http://platform-api:8000` on the shared Coolify network.
- Workbench document promotion uses `/v1/ingest` plus the durable `/v1/runs/{run_id}` receipt. It
  never substitutes extracted text for unavailable original bytes, never lets editable metadata
  override original SHA/name provenance, and keeps timed-out or temporarily unavailable receipt
  polling in `promoting` state with the accepted `run_id` intact. Only a durable terminal receipt
  may mark the staged item promoted or failed.
- Workbench semantic search is evidence-only. Unsupported cross-lane/non-evidence search fails
  closed in the API and is not offered by the UI; canonical catalog browsing remains multi-lane.
- Workbench repair review no longer discovers or invokes generic AgentOS agents/teams. It stays
  disabled until a bounded Temporal task contract exists. Repair tools publish through
  ContextForge/Portkey.
- LibreChat now bakes its tracked, secret-free MCP configuration into a digest-pinned derived
  image and requires the Portkey-published ContextForge URL/credential at deployment. The former
  host-staged config cannot silently drift.
- OpenCode ops and the Matter activation preflight use the Platform API/runtime-file bearer and
  ContextForge. Retired `/info`, `/knowledge/search`, AgentOS MCP, `AGENTOS_API_URL`, and
  `AGENTOS_API_TOKEN` runtime paths are gone.
- Platform API and Workbench now apply the same bearer-file byte contract: UTF-8, bounded length,
  surrounding file whitespace normalized, and an allowlisted token alphabet. A newline written by
  an ordinary secret-file provisioning command cannot authenticate one side while disabling the
  other.
- Live Workbench evidence-search proof exposed the remaining operator capability as an unset
  environment secret. It now follows the same runtime-file pattern on both services through the
  distinct `/run/secrets/evidence-operator-security-key` mount; it remains separate from the
  Platform owner bearer and is read again for every search request.

Verified locally:

- Expanded Platform host/auth/deployment/ingest/resilience suite: **296 passed**.
- Matter-preflight plus OpenCode-ops cutover: **17 passed**.
- Workbench cutover tests and production Next.js build pass; 17 static routes generated. The full
  Workbench API run is **224 passed / 1 pre-existing structure failure** because clean-tree
  `app/service/uiw.py` (301 lines) and `app/types/case_management.py` (315 lines) exceed its
  300-line policy; neither file belongs to this cutover slice.
- `ruff`, focused `mypy`, requirements regeneration, and `git diff --check` pass for the slice.

Release holds:

1. LibreChat now tracks `main` and `deploy/librechat.yaml`, but activation remains held until the
   hosted/hybrid Portkey `platform-tools` MCP publication and MCP-Invoke-only key exist.
2. Native evidence search remains held behind D-104/D-066: `EvidenceChunkV1`, alias, backfill,
   canary receipt, and owner activation are absent. Keep `NATIVE_EVIDENCE_ENABLED=false`.
3. Do not quarantine the historical AgentOS modules or legacy `deploy/compose.yaml` until
   zero-caller, retained-state, rollback, and live-parity proof are complete.
4. Continue the ordered replacement of `server/evidence/workflows.py` and Agno-owned
   Knowledge/provider/vector/session code; this host slice deliberately does not pretend those
   later changes are complete.

Live cutover update (2026-08-30): commits `7440772`, `e08c0a8`, `43675cb`, and `a6f9286` deployed
successfully to the applicable `exec-tier` and `knowledge-workbench` resources. Platform `/health`,
the stable Tailscale Workbench `/health`, `/`, `/evidence/preview`, and fixed source browser all
returned HTTP 200. Platform owner and evidence-operator bearer files are live runtime mounts with
the old secret env records absent from both containers. Native evidence search reaches the
Platform boundary but remains intentionally unavailable while D-104/D-066 prerequisites are
unmet; do not enable `NATIVE_EVIDENCE_ENABLED` merely to turn that 404 into a response.

### Live Workbench R2/source/upload receipt — 2026-08-30

_Byline: Codex · GPT-5.6-Sol · 2026-08-30._

- Commit `a6f9286` fixes one runtime JSON credential for two non-selectable buckets:
  read-only `casebible-sorted` source browsing and `nexus` Workbench staging. Object-store endpoint,
  bucket, and credential environment settings were removed from the Workbench contract.
- The malformed empty host directory at `/data/agno/secrets/casebible-r2.json` was moved intact to
  `/data/agno/to_be_deleted/platform-secret-paths-20260830T0855Z/`; only the owner deletes it. The
  existing live R2 credential was preserved without printing or rotating it in a regular `0400`
  runtime JSON file at the mounted path.
- Coolify deployment `se4ozjscbq6665pois690exn` finished from exact commit `a6f9286`. The stricter
  Docker healthcheck now parses `/health` and rejects `status=degraded`; the live container reports
  `healthy` and the stable service returns `{"status":"ok","lancedb":true,"object_store":true}`.
- `GET https://workbench.tilapia-skilift.ts.net/api/uiw/sources?page_size=5` returned HTTP 200,
  `source=casebible-sorted`, real objects, delimiter pagination, and an opaque continuation token.
- A real Markdown upload through the same UI route (`POST /api/uiw/upload`) returned HTTP 201 with
  acquisition SHA-256 `ea9f93939589dcad8631d5b0b26b9ca9a1ef654660eafee1136f68a9cf6ac820`.
- A real JSON staging upload through `POST /api/upload` returned HTTP 200 with key
  `workbench/staging/49d046ac1257d3334a1c2af8eefa19429ff1f9c9da5a9471da6298fff135cb9f/package.json`;
  the running container then verified that exact object exists in fixed bucket `nexus`.
- Verification: fixed object-store/source tests **5 passed**; root deployment contracts **14
  passed**; the full Workbench API suite is **228 passed / 1 pre-existing structure failure** for
  the already-known 301-line `app/service/uiw.py` and 315-line `app/types/case_management.py`.

LibreChat MCP activation remains held at the approved gateway boundary. The live ContextForge
`platform_tools` virtual server passed read-only initialize and tools/list proof with 14 tools, but
the self-hosted Portkey gateway has no MCP workspace/server/key capability and the active LibreChat
resource has no hosted Portkey MCP endpoint or scoped invocation key. The client header contract
was corrected to Portkey's `x-portkey-api-key`; do not substitute the retired AgentOS token or a
direct ContextForge bypass. Activation requires the hosted/hybrid Portkey `platform-tools`
publication and an MCP-Invoke-only workspace key, followed by downstream parity proof.

## Owner rulings after the dissection — current authority

> _Owner, 2026-08-29: "AgentOS dies"; "Temporal and n8n and ContextForge and Portkey handle most
> of that"; and Surreal promotion is manual until a governed automatic process is designed._

- **AgentOS is retired completely.** Plain FastAPI replaces it as the process/API host. AgentOS
  generic agents, teams, workflows, registry, session/Knowledge ownership, scheduler, tracing,
  approvals, authentication surface, and MCP mount do not survive the cutover.
- **Agno may remain only as a bounded atomic-agent library adapter.** All nine current agent
  definitions are preserved but disabled. None is callable until it has an explicit Temporal task
  ID, reference-only input/output contract, case/horizon/authority scope, tool allowlist, and tested
  approval path. Agno owns no database, Knowledge/vector, provider registry, workflow, team, router,
  scheduler, tracing, or public API surface.
- **Temporal owns durable execution:** workflow/run state, retries, timers, long human waits,
  signals, activity history, agent invocation state, and projection fan-out/reconciliation. n8n is
  the visual business/integration layer, ContextForge is the MCP gateway, and Portkey is the only
  model/embedding/reranking gateway.
- **PostgreSQL remains canonical and detects committed changes through its transactional
  outbox/CDC contract.** Temporal consumes immutable change references; it does not poll or rewrite
  canonical rows. PostgreSQL retains only domain-facing, independently queryable receipts and
  decisions rather than recreating Agno's operational session tables.
- **SurrealDB is manual-promotion-only for now.** A PostgreSQL change may automatically drive the
  governed Weaviate search projection and the Semantica/Neo4j plus SAT-RAG analysis paths, but it
  MUST NOT automatically update SurrealDB. Change detection may create a promotion candidate.
  Surreal changes only after the owner explicitly promotes material as worthy of a governed walk,
  evidence/reference use, or another approved analytical purpose. Temporal durably executes and
  receipts that decision; neither Temporal nor a model may infer promotion authority from change
  detection alone. An approved Surreal materialization may assemble inputs from canonical
  PostgreSQL plus either Neo4j projection independently or both together: the Semantica `evidence`
  graph and the SAT-RAG `sat-temporal` graph. Its receipt must pin the PostgreSQL projection
  generation and every graph snapshot/version used so the Surreal result remains reproducible,
  provenance-complete, and strictly derived. Approval to include material in Surreal authorizes a
  derived analytical projection only; it does not itself promote a source or claim to evidentiary
  status, which remains a separate PostgreSQL-governed decision.
- **No destructive cleanup is authorized.** Retired code/configuration moves to `to_be_deleted/`
  only after zero-caller, retained-state, rollback, and live-parity proof. Only the owner deletes
  anything from that directory.

These rulings supersede this handoff's original analysis-only boundary and the undecided session/
factory language below. They do not authorize touching the concurrent evolving files
`example.env`, `docs/design/CLAIM-AND-ASSERTION-CANDIDATES-2026-08-29.md`, or
`sql/0052_claim_and_assertion_candidates.sql`.

### Verified current Surreal enforcement boundary

_Read-only caller audit: Codex subagent · 2026-08-29._

- No production caller in `server/`, `engine/`, Workbench, n8n, Temporal, or the PostgreSQL
  CDC/outbox consumers currently writes to the governed Surreal target.
- The isolated `docker/surreal-phase1-runner/` synthetic harness is the only writer. Its network,
  target-identity allowlist, and T0-only schema currently prevent it from reaching canonical data.
- That runner is **not** a production promotion mechanism. It trusts `authority_state` and
  `promotion_state` strings from its bundled manifest and changes a projection from `building` to
  `active` without a PostgreSQL human-decision receipt or Temporal approval signal.
- Keep the runner synthetic-only. Do not add a Surreal CDC sink, outbox consumer, Temporal
  projection activity, n8n projection node, or real-data caller until a PostgreSQL-authored
  promotion manifest pins the approved sources/spans and source generations, the human actor and
  decision receipt, and a separate Temporal signal gates activation after reconciliation.
- The future production projector must be able to select canonical PostgreSQL plus Semantica
  `evidence`, SAT-RAG `sat-temporal`, or both Neo4j projections. Selection is explicit in the
  promotion manifest; graph-derived input never displaces PostgreSQL authority.

## Why this exists

Agno used to be the primary home of the knowledge bases, the sole writer of the tables, and the
viewing/work surface. **It is none of those things now.** Agents may still be used for specific
tasks inside n8n and Temporal.

The code never got the memo. Agno is still imported by **28 production files** and is still the
process host for the API. On 2026-08-29 the owner asked for a task that *"completely dissects what
Agno's role still is in the code, so that we can decide how best to address that — and if it needs
to be addressed at all."*

The last time a retirement ruling failed to propagate (Graphiti, 2026-08-27), the register still
said "implementation pending" two days later and blocked a lane that was already closed. This
packet exists so that does not repeat: **decide from an inventory, not from an assumption.**

## Owner rulings already made — treat as settled input, not open questions

| Ruling | Owner language (2026-08-29) |
|---|---|
| Agno must have **no role in the knowledge vector** | "Agno should definitely not have anything to do with the knowledge vector." |
| **Providers and model registry are not needed** | "We don't need the providers or the model registry because I'm not going to be doing chat through there." |
| Session and factory are **undecided, possibly load-bearing** | "Session might be important, factory might be important… maybe these things are necessary for the couple of agents that actually happen." |
| `server/api/main.py` is **unknown to the owner** — explain it before proposing anything | "I don't know what main dot pie does." |
| Agents survive **only inside n8n/Temporal** | "We might utilize some agents to do certain tasks within the confines of n8n and temporal." |

## Inventory — verified 2026-08-29 by import scan

28 production files plus 3 test files import Agno. Grouped by surface, not by folder.

### S1 · Process host and API surface — **the largest and least understood dependency**
- `server/api/main.py` — `agno.os.AgentOS`, `agno.registry.Registry`, `agno.team.team.Team`,
  `agno.workflow.factory.WorkflowFactory`, `agno.workflow.remote.RemoteWorkflow`,
  `agno.workflow.workflow.Workflow`, `agno.utils.log`
- `server/api/workflow_registry.py` — `WorkflowFactory`, `agno.utils.log`
- `server/api/mcp_main.py` — `agno.utils.log`

**This is the answer to "I don't know what main.py does": Agno is not a library here, it is the
application server.** `AgentOS` hosts the API. Any Agno decision is therefore a decision about how
the platform is served. Dissect this first — everything else is downstream of it.

### S2 · Knowledge / vector / embedding — **owner has ruled Agno out; confirm blast radius**
- `server/core/knowledge_vectordb.py` — `agno.vectordb.weaviate.Weaviate`, `agno.knowledge.document`
- `server/core/embedder.py` — `agno.knowledge.embedder.openai.OpenAIEmbedder`
- `server/core/reranker.py` — `agno.knowledge.reranker.base.Reranker`, `agno.knowledge.document`
  (**note: zero callers as of the 2026-08-29 audit — likely deletable outright**)
- `server/core/session.py` — `agno.knowledge.Knowledge`, `agno.vectordb.search.SearchType`

### S3 · Session and database handles — **undecided; highest coupling risk**
- `server/core/session.py` — `agno.db.postgres.PostgresDb`, `agno.db.surrealdb.SurrealDb`

Agno owns the Postgres **and** SurrealDB handles. Flag: this sits directly against ADR-0056/D-061,
where Surreal is a governed projection and PostgreSQL is the canonical authority. Determine whether
Agno's DB layer is in the write path for anything canonical. **If it is, that is a finding, not a
refactor ticket — report it.**

### S4 · Model providers and registry — **owner has ruled these out**
- `server/core/settings.py` — 8 model imports (`OpenAILike` ×3, `Ollama`, `OpenAIChat`, `Claude`,
  `Gemini`, `Groq`)
- `server/core/model_registry.py` — `agno.utils.log` only (trivial coupling)
- `server/agents/providers.py` — `agno.context.database.DatabaseContextProvider`,
  `agno.context.workspace.WorkspaceContextProvider`, `agno.learn`

Check against D-093: model-backed work is supposed to route through **Portkey**, never a direct
provider call. If `settings.py` still constructs providers directly, that is an existing violation
independent of any Agno decision.

### S5 · Agents and agent tooling — **survive only inside n8n/Temporal**
- `server/agents/factory.py` — `Agent`, `Team`, `TeamMode`, `approval`, `tool`,
  `FileGenerationTools`, `UserControlFlowTools`
- Agent modules: `analysis_orchestrator.py`, `dev_copilot.py`, `document_digest.py`,
  `forensic_data_agent.py`, `ingestion_orchestrator.py`, `project_pal.py`,
  `review_gatekeeper.py`, `transcript_miner.py`, `claude_code_agent.py`
- Agent tools: `tools/gateway_tools.py`, `tools/realization_tools.py`, `tools/sbv_tools.py`

**The central question for this surface:** which of these nine agents actually runs in production,
and which are dead? The owner expects "a couple." Nine exist. Establish the real number by call-site
and workflow-registration evidence, not by file presence.

### S6 · Workflow engine — **direct conflict with the durable-spine ruling**
- `server/evidence/workflows.py` — `agno.workflow.Step`, `Workflow`, `OnError`, `StepInput`,
  `StepOutput`

D-068 states **Temporal is the durable spine and n8n is the agent/integration layer.** Agno
workflows in the evidence path contradict that. Determine whether these execute in production or are
vestigial.

### S7 · Chunking — **partially superseded already**
- `server/analysis/chonkie_chunkers.py`, `server/analysis/chunking_policy.py` —
  `agno.knowledge.chunking.*`

The 2026-08-29 chunker bake-off concluded document-class markdown needs **no chunking library at
all** and belongs in Go beside the coordinator. Determine what still legitimately routes through
Agno chunking after that finding.

### S8 · Scripts and tests — lowest priority
- `scripts/check_model.py`, `scripts/verify_direct_providers.py`, `scripts/migrate_milvus_to_weaviate.py`
- `tests/test_agent_authority_boundary.py`, `tests/test_c26_resilience.py`, `tests/test_chonkie_chunkers.py`

## What the dissection must produce

One document. For **every** file above:

1. **Live or dead** — is it reachable from a running entry point? Cite the call path or state that
   none exists. File presence is not evidence of use.
2. **What Agno actually provides** — the specific capability, not the import name.
3. **Canonical write path?** — does it write anything the platform treats as authoritative? This is
   the question that decides whether an item is a cleanup or a governance finding.
4. **Replacement cost** — trivial (logging shim), bounded (one adapter), or structural (API host).
5. **Conflicts with a standing decision** — especially D-068 (Temporal spine), D-093 (Portkey
   routing), ADR-0056 (Surreal as projection).

Then a single ranked table: **remove now · replace later · keep deliberately · needs owner ruling.**

## Boundaries — read these before starting

- **Do not remove, replace, or refactor anything.** The output is analysis. The owner decides after
  reading it, including deciding to do nothing.
- **Do not delete files.** If something is provably dead, say so and cite the evidence; moving it to
  `to_be_deleted/` requires a separate owner go.
- **Do not start the Workbench/UIW lane's work**, and do not touch files in flight there.
- **`server/api/main.py` is explained first.** The owner has said plainly he does not know what it
  does; every other recommendation depends on that answer.
- Agno currently starts the API. **Any proposal that breaks startup is not a proposal, it is an
  outage.** State the startup impact of every suggested change.
- Record the ruling in `DECISION_LOG.md` in the same change that closes this task — per **D-096**.

## Related

D-095 (Graphiti retired — the precedent for a ruling that failed to propagate), D-096 (no task
closes without a logged ruling), D-093 (Portkey routing / SATemporal-Semantica A/B), D-068
(Temporal spine, n8n integration layer), ADR-0056 (Surreal governed projection), ADR-0061 (unified
operator surface).
