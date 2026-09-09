# HANDOFF — Platform development orchestration takeover (2026-08-27)

> _Byline: Codex · GPT-5 · 2026-08-27._

STATUS: PARTIAL
BUILD_STATUS: UNKNOWN

## Purpose and scope

This is the cold-start entry point for a new agent/thread taking over **Platform product-development
orchestration** in:

`E:/AI_Workspace/Projects/the-platform-workspace/Agno-MCP-Platform`

The takeover agent owns recovery and coordination of active implementation lanes, bounded delegation,
integration review, required validation, explicit commits, Coolify deployment, live verification, and
durable product-status reporting.

### Explicitly out of scope

The takeover agent must not absorb or redirect work remaining in the original thread:

- parent-workspace Git boundaries or gitlink/submodule repair;
- repository setup, Git configuration, remotes, or sister-repository reconciliation;
- progressive `AGENTS.md`, `AGENT_MEMORY.md`, Claude shim, or memory-system work;
- TraceIQ, MITECH, or Legal Workspace implementation;
- the resolved Windows `.sh`/`cmd.exe` hook and popup investigation.

Those concerns stay with the original thread. If one blocks Platform delivery, report the exact blocker
without independently changing that area.

## Verified starting state

| Item | Verified state |
|---|---|
| Platform branch | `main`; commit `fdc6f93` was pushed to `origin/main` before this handoff was drafted. Recheck current HEAD at takeover because concurrent work may have advanced it. |
| Worktree safety | The checkout was highly concurrent/dirty at the last census: 4,771 status entries, 50 modified, 4,721 untracked, 0 staged, 0 deleted. Never sweep, reset, clean, stash, or broad-stage this worktree. Recover ownership before touching overlapping paths. |
| Semantic index | `ccc index` completed on 2026-08-27 with 3,425 files listed, 32 added, 4 reprocessed, zero errors, and 52,351 chunks. Refresh after material code changes. |
| Existing Claude lanes | Processes associated with `fresh-db` (session `71bb3bf9-1d32-4d95-8be0-3a69c465b419`) and `raw-pipeline` (`17d5015a-330d-4297-922a-7c26adcf463b`) were resident. Their output/current activity was not verified; process existence is not progress proof. |
| Database direction | D-091 supersedes older forward-database instructions: new application work targets fresh database `platform`. Preserve legacy `ai`/`agno_app`; migration 0036 must never target `ai`. |
| Unified UI | The approved unified-surface Vite prototype responded locally at `http://127.0.0.1:4178`, but that is preview evidence only—not implemented, deployed, or live product proof. Do not substitute another application or expand disconnected stubs. |
| Validation boundary | No full current-platform Ruff, format, mypy, Python test, Go test/build, Workbench build, mandatory live integration, Coolify deployment, or production verification was completed during handoff preparation. |

## Authority and first reads

Read these before assigning or changing product code:

1. `AGENTS.md`, followed by the closest nested `AGENTS.md` for every owned path.
2. `docs/INDEX.md`, `docs/PROJECT_CANON.md`, `docs/DECISION_LOG.md`, and relevant signed ADRs.
3. `docs/COORDINATION.md`; reconcile every claimed lane with current Git/process state before trusting it.
4. `docs/HANDOFF-2026-08-24-ingest-testing.md`, including its D-091 fresh-`platform` correction.
5. `docs/BUILD_PLAN.md`, `docs/URGENT-TODO.md`, and `docs/MASTER-TODO-2026-08-18.md`; inspect provenance because they were concurrently modified.

## Immediate takeover procedure

1. Capture current branch/HEAD, remotes, staged paths, focused status, running agents/processes, and
   current Coolify/live service state without mutating anything.
2. Reattach to or inspect the two named Claude sessions. Determine exact file ownership, deliverables,
   diffs, test evidence, and whether each is active, finished, failed, or stale.
3. Reconcile `docs/COORDINATION.md` with observed state. Do not dispatch a replacement into an owned
   path until the prior lane is accounted for.
4. Select the smallest incomplete production vertical slice already sanctioned by canon/current plans.
5. Divide only non-overlapping work, integrate reviewed allowlists, run the full relevant validation
   chain, commit and push from this repository, let Coolify deploy, and verify live behavior.
6. Record what is proven, failed, deferred, or still unknown. Local/static checks never count as live
   proof.

## Orchestration contract

- Complete functional vertical slices. Do not expand the surface with placeholders, decorative cards,
  disconnected routes, fake data, or speculative modules.
- Give each worker an exact outcome and exact file/module allowlist. Tell every worker it is not alone
  in the checkout and must preserve other agents' work.
- Workers do not reset, clean, stash, checkout, delete, broad-stage, commit, push, deploy, or mutate
  Coolify unless the root orchestrator explicitly assigns that exact operation.
- The root orchestrator reviews all diffs, resolves integration boundaries, stages only explicit paths,
  runs required validation, commits with attribution, pushes, monitors Coolify, and performs live proof.
- One writer owns each file at a time. Parallelize by semantic domain only when imports, migrations,
  generated contracts, and shared registries cannot collide.
- PostgreSQL/custody remain canonical. Timesketch, Workbench/SBV, Neo4j, SurrealDB, Weaviate, n8n,
  Temporal, and other surfaces/services interact with governed canonical data; none silently takes
  authority.
- AI chat is context, never evidence. Extracted event/claim candidates require independent actual
  evidence and governed review.

## Claude Code directions

Claude Code is the preferred implementation workforce while available. The new root thread remains
the authority and integrator.

- Use Opus for architecture, ambiguity, security, migrations, and cross-domain reasoning.
- Use Sonnet for well-bounded implementation and test work.
- Use Fable sparingly as a genuinely independent second judge, not routine duplication.
- Recover the existing `fresh-db` and `raw-pipeline` lanes before starting substitutes.
- Every prompt must include exact repository root, precise owned files, forbidden neighboring paths,
  acceptance criteria, commands to run, output/receipt location, and the rule not to revert other work.
- Prefer independent lanes such as one migration/schema slice, one Go parser/activity slice, one API
  slice, one Workbench vertical slice, one Timesketch projection slice, or one test/verification slice.
  Do not run them concurrently when they share contracts, migrations, routing, or generated artifacts.
- A Claude completion claim is input to root review, never completion evidence by itself.

## Ollama Cloud offload directive

Offload bounded, non-sensitive supporting work to Ollama Cloud when it preserves momentum without
creating integration risk. Suitable work includes code explanation, test-case enumeration,
documentation-cleanup proposals, focused independent review, and low-risk drafts with a narrow file
contract.

Never send evidence bodies, PII, credentials, secret-bearing configuration, privileged legal content,
or unredacted case material to an external worker.

### Preferred route — native Ollama CLI

The installed Ollama client was version `0.32.14`. This project is remote-only: do not start
`ollama serve`, pull ordinary local models, or enable local inference.

After verifying Ollama Cloud authentication, use explicit cloud models:

```powershell
ollama run qwen3-coder:480b-cloud "<bounded code task with no secrets or case data>"
ollama run gpt-oss:120b-cloud "<bounded review or synthesis task>"
```

Save the prompt, scope, model, output path, and root review result in the lane receipt. Treat output as
a proposal until reconciled with source and verified by tests.

### Fallback route — Ollama Cloud through OpenCode

The installed OpenCode client was version `1.18.23`. First discover the configured provider/model:

```powershell
opencode models ollama
```

The last probe returned no model listing within 30 seconds, so authentication/provider mapping remains
unverified. Never guess the identifier or silently switch providers. Once a valid mapping is returned:

```powershell
opencode run -m <verified-ollama-provider/model> "<bounded task and exact file ownership>"
```

If both Ollama Cloud routes fail, keep the lane with Codex/Claude or mark it blocked. Never fall back to
local model execution on this machine.

## Product-development priorities to recover, not assume

These are known active domains, not a license to redesign them. Recover live status and current owner
before choosing the next slice:

- fresh `platform` database baseline, migrations, roles, and superuser/developer access;
- universal raw extraction and normalized provenance links;
- Go-based orchestration and atomic Temporal/n8n activity boundaries;
- hash/custody stages and distinct H3 construction tags;
- approved unified operator surface with one fully working ingest/preview/review path;
- Timesketch as a governed timeline viewing/editing projection with candidate re-review on return;
- Workbench/SBV API coverage and manual-operation surface;
- mandatory ingest/integration tests and live deployment receipts.

## Required validation and delivery loop

Use applicable scoped checks during development, then the complete relevant chain before calling a
slice done:

```powershell
uv run ruff check server tests
uv run ruff format --check server tests
uv run mypy server
uv run pytest -q
uv run pytest -m integration
```

For `vendored/sbv`, use documented `fts5` Makefile targets or equivalent tagged commands; a plain
untagged Go test is invalid. Run relevant Workbench build/tests for UI/API changes. Then:

1. inspect the diff and stage only the owned allowlist;
2. commit in this Platform repository with required attribution;
3. push the intended branch;
4. verify Coolify selected and built the intended commit;
5. run live behavior/integration checks against the deployed service;
6. persist a receipt with commit, deployment, checks, failures, and exact validation boundary.

## UNRESOLVED

- **Lane recovery** — WHAT: determine actual state of `fresh-db`, `raw-pipeline`, and any other active
  implementation agents. WHY: duplicating them risks collisions and false progress. SHORTCOMING: only
  resident process/session identifiers were observed; outputs were not verified.
- **Dirty-worktree provenance** — WHAT: assign ownership or disposition to relevant modified/untracked
  product paths before integration. WHY: the checkout contains thousands of concurrent entries.
  SHORTCOMING: Git status alone cannot distinguish valid work, snapshots, vendored trees, and debris.
- **Build and live status** — WHAT: establish current full validation, deployed commit, service health,
  and functional ingest path. WHY: no complete product verification was performed in the preparation
  thread. SHORTCOMING: `BUILD_STATUS` must remain `UNKNOWN` until the takeover agent proves it.
- **Ollama Cloud routing** — WHAT: verify sign-in and one non-sensitive native CLI smoke task, then
  verify OpenCode mapping only if needed. WHY: the fallback provider listing did not complete.
  SHORTCOMING: no Ollama/OpenCode output should be assigned code ownership until routing is proven.

## Starter prompt for the new thread

> Work only in `E:/AI_Workspace/Projects/the-platform-workspace/Agno-MCP-Platform`. Read `AGENTS.md`
> and `docs/HANDOFF-2026-08-27-platform-development-takeover.md` completely. Take over Platform
> product-development orchestration: recover active lanes first, reconcile exact ownership, choose the
> smallest sanctioned production vertical slice, delegate only non-colliding bounded work, integrate
> and test it, commit/push explicitly, let Coolify deploy it, and live-verify it. Use Claude Code as the
> preferred workforce and Ollama Cloud for bounded non-sensitive supporting tasks under the handoff
> rules. Do not take over parent-repository, Git-boundary, sister-project, `AGENTS.md`,
> `AGENT_MEMORY.md`, memory-system, or shell-hook work; those remain in the original thread. Do not
> claim completion from local checks or process existence.
