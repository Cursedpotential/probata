# Build Phases — Probata Intake and Owner Portal Recovery: Frontend Workstream

The frontend workstream owns `modules/workbench/web/**` and explicitly approved shared UI/contract packages only. It never edits FastAPI, Go, SQL, n8n, deployment manifests, Authentik, or Coolify state.

Every fresh task begins by reading repository/subtree `AGENTS.md`, [STACK.md](STACK.md), [SPLIT.md](SPLIT.md), [GOTCHAS.md](GOTCHAS.md), [PHASES.md](PHASES.md), and the current coordination/handoff files. Existing dirty/untracked files are contributor work, not a scratch area.

## Phase F0 — Preflight and existing-work reconciliation

**Status at handoff:** **PARTIAL / fresh-task gate.** The current Workbench stack and dirty Intake/operations work have been inventoried, but no clean baseline has been handed to a new frontend task.

**Already done:**

- Browser-first React/Vite SPA and same-origin FastAPI hosting are established.
- Current repository lock is React 19.2.3, TypeScript 5.9.3, TanStack Router 1.170.32, Storybook 10.5.10, and Vite 8.2.2.
- Current dirty work includes image preview, preview/metadata/parser tabs, operation URL state, a polling operation table, pagination, and BFF/engine contracts. The operations table and its smoke test are untracked in the inspected worktree.
- Exact Glide alpha24 passed an isolated React 19.2.3 compatibility suite; it is not yet integrated into Probata.

**Goal:** Establish the exact frontend starting point without losing, overwriting, or falsely adopting concurrent work.

**Relevant gotchas:** A-5, A-8, A-11, A-30.

**Work boundary:** Read only. Do not write application files, install with force/legacy peer overrides, stage, stash, reset, clean, merge, delete, or deploy.

**Exit criterion:** A preflight report records the correct Propria/Probata repository root, HEAD/branch, complete tracked/untracked status, current package and lock versions, owners/status of every dirty frontend file, and PASS/FAIL output for the unmodified frontend lint/build/smoke/Storybook commands; every existing change is assigned to preserve, supersede-by-owner, or out-of-scope, with no file mutation.

**Verification commands:**

```powershell
git rev-parse --show-toplevel
git status --short --branch
git diff -- modules/workbench/web
git ls-files --others --exclude-standard -- modules/workbench/web
Set-Location modules/workbench/web
npm.cmd ci
npm.cmd run lint
npm.cmd run build
npm.cmd run smoke
npm.cmd run build-storybook
```

## Phase F1 — Browser-contract generation and fixture harness

**Status at handoff:** **NOT STARTED.** Current TypeScript Proffer types are handwritten and already differ in optionality from Pydantic.

**Goal:** Consume one checked-in browser OpenAPI snapshot and render every lifecycle/error/repair/capability state without a live backend.

**Relevant gotchas:** S-4, S-5, A-1, A-2, A-4.

> **Sync point:** Backend Phase B1 must publish the versioned OpenAPI snapshot, error envelope, lifecycle/command matrix, and JSON fixtures before this phase freezes generated types.

**Allowed paths:**

- `modules/workbench/web/src/lib/api-client.ts`
- `modules/workbench/web/src/lib/shared/**`
- `modules/workbench/web/src/test-fixtures/**` or the existing approved fixture location
- `modules/workbench/web/.storybook/**`
- focused `modules/workbench/web/smoke/**`
- package manifest/lock only if the chosen generator requires it and the change is exact-pinned

**Exit criterion:** The browser client compiles solely against the checked-in v1 contract for all new Intake operation fields; fixtures render queued, running, capability wait, repair wait, preview wait, held, completed, failed, canceled, unavailable, stale-revision, timeout-unknown, and empty states; CI fails when the OpenAPI snapshot and generated TypeScript drift.

**Verification commands:**

```powershell
Set-Location modules/workbench/web
npm.cmd ci
npm.cmd run lint
npm.cmd run build
node --test --test-concurrency=1 smoke/proffer-contract-generation.contract.test.mjs
npm.cmd run build-storybook
```

## Phase F2 — Shared Glide adapter on React 19

**Status at handoff:** **ISOLATED COMPATIBILITY PASS; PRODUCT INTEGRATION NOT STARTED.** Native Tauri linking remains unproven because the isolated Windows environment could not resolve `kernel32.lib`.

**Goal:** Integrate exact `@glideapps/glide-data-grid@6.0.4-alpha24` behind one shared adapter without changing React 19.2.3 or scattering prerelease imports.

**Relevant gotchas:** A-5, A-6, A-8, A-30.

**Allowed paths:**

- `modules/workbench/web/package.json`
- `modules/workbench/web/package-lock.json`
- one approved shared grid adapter under `modules/workbench/web/src/components/ui/` or an existing shared-components location
- adapter stories/tests only

**Exit criterion:** `npm ls` shows one deduplicated React/ReactDOM 19.2.3 tree and exact Glide alpha24 with no force/legacy-peer override; all product code imports Glide only through the shared adapter; a 100,000-row fixture supports stable-handle selection, Arrow navigation, boolean/text editing, 2x2 paste, sorting/reorder refresh, and screen-readable fallback; lint, build, smoke, Storybook static build, and real-browser checks pass; reverting the isolated adapter/lock commit restores the pre-Glide table path.

**Verification commands:**

```powershell
Set-Location modules/workbench/web
npm.cmd ci
npm.cmd ls react react-dom @glideapps/glide-data-grid
npm.cmd run lint
npm.cmd run build
node --test --test-concurrency=1 smoke/glide-adapter.contract.test.mjs
npm.cmd run build-storybook
```

Also record the real-browser interaction script/output and compare it with the isolated artifact at `C:\Users\matts\.codex\visualizations\2026\09\12\01a09663-e9bb-72c2-bfce-c0714cba8d66\glide-alpha-compat`.

## Phase F3 — Source selection, persistent preview tabs, and Back behavior

**Status at handoff:** **PARTIAL in dirty working tree.** Local image object URLs and three tabs exist; browser-format failures, remote preview consistency, filters, and navigation proof remain.

**Goal:** Make source choice and preview review usable before any workflow starts.

**Relevant gotchas:** S-6, A-7, B-1, B-2, A-30.

**Allowed paths:**

- `modules/workbench/web/src/components/intake/unified-intake.tsx`
- focused child components under `modules/workbench/web/src/components/intake/**`
- `modules/workbench/web/src/app/intake/page.tsx`
- typed route/search state and focused stories/smoke tests

**Exit criterion:** Selecting a normal JPG cat photo immediately displays a non-empty Source Preview and Metadata tab; undecodable image formats display an explicit browser-capability explanation rather than an empty panel; Source Preview, Metadata, and Parser tabs stay present through inspection/start/waits/errors; Change source and browser Back restore the prior source/tab/filters/selected-operation URL state without canceling work or leaking object URLs.

**Verification commands:**

```powershell
Set-Location modules/workbench/web
npm.cmd run lint
npm.cmd run build
node --test --test-concurrency=1 smoke/unified-intake-anatomy.contract.test.mjs smoke/intake-preview-navigation.contract.test.mjs
npm.cmd run build-storybook
```

Use real small JPG, PNG, PDF, text, and a browser-undecodable fixture; do not substitute a mock image for the real decode check.

## Phase F4 — Current-purpose, capability, OCR/vision, and parser choices

**Status at handoff:** **NOT IMPLEMENTED.** Current code derives route text from the extension and always sends `parser-options://default-v1`; there is no live OCR/vision/metadata/preserve capability negotiation.

**Goal:** Give the owner visible control over what happens now without turning that choice into permanent evidence eligibility.

**Relevant gotchas:** S-3, S-10, S-19, S-20, S-22.

> **Sync point:** Backend Phases B2/B3 and the separate D-149 DuckDB/XML lane must freeze capability IDs, availability, package binding, and `/api/proffer/start` before this phase submits decisions.

**Allowed paths:** Intake UI components, generated contract bindings, focused stories and smoke tests only.

**Exit criterion:** For each inspected source, the UI shows current-purpose choices (`context_elt`, `metadata_only`, `ocr`, `vision`, `preserve_only`, and eligible `evidence_admission`), registered parser/tool capability name and version, recommendation basis, unavailable reasons, and viable alternatives; the owner can override with a recorded reason; a selected context route explicitly says later evidence admission remains possible through the retained Intake Source Package; no extension label is presented as a recorded parser selection.

**Verification commands:**

```powershell
Set-Location modules/workbench/web
npm.cmd run lint
npm.cmd run build
node --test --test-concurrency=1 smoke/intake-capabilities.contract.test.mjs smoke/intake-purpose-and-parser.contract.test.mjs
npm.cmd run build-storybook
```

## Phase F5 — Repair/no-repair decision and original override

**Status at handoff:** **PARTIAL AND WRONG FOR THE REQUIRED JOB.** Current dirty UI can confirm only “use original”; it cannot show a real derived repair choice, and upstream omission previously caused false repair gates.

**Goal:** Render repair only when a concrete issue exists and always explain what is happening.

**Relevant gotchas:** S-2, S-5, S-11, A-1, A-4.

> **Sync point:** Backend Phase B4 must provide schema-validated issues/options and prove missing flags do not yield repair before decision submission is enabled.

**Allowed paths:** Repair/intake components, generated types, stories, and focused smoke tests.

**Exit criterion:** A no-issue cat-photo fixture never shows a repair gate; malformed/missing detector output shows a detector failure while the original can continue under policy; a true repair fixture names issue, severity, detector/version/evidence, original option, and an actual derived option only when its immutable version exists; override requires a reason and stale/double submissions produce clear `409` handling; no panel says “repair required” with no repair process offered.

**Verification commands:**

```powershell
Set-Location modules/workbench/web
npm.cmd run lint
npm.cmd run build
node --test --test-concurrency=1 smoke/proffer-repair-gate.contract.test.mjs smoke/proffer-repair-options.contract.test.mjs
npm.cmd run build-storybook
```

## Phase F6 — All-operation registry with global filters

**Status at handoff:** **PARTIAL in dirty/untracked work.** A polling table, lifecycle filter, page-local source/service refinement, cursor pagination, URL selection, and separate legacy-run label exist; Glide/global-filter behavior is not done or committed.

**Goal:** Show every in-flight, waiting, failed, canceled, completed, and unavailable Intake operation without conflating legacy Workbench runs.

**Relevant gotchas:** A-1, A-3, A-6, A-30, B-1.

**Allowed paths:**

- `modules/workbench/web/src/components/intake/proffer-operations-table.tsx`
- focused operation-grid child components/stories/tests
- `modules/workbench/web/src/app/intake/page.tsx`
- generated client only if contract already changed in F1

**Exit criterion:** The Glide-backed registry uses stable operation handles and supports server-backed lifecycle, source/reference, service/capability, time range, and needs-my-decision filters; cursor Next/Previous and polling preserve selected detail and URL state; separate states exist for loading, API error, no operations, no server matches, and no current-page refinement; inserting/reordering rows cannot open or command the wrong operation; legacy staged files remain explicitly separate.

**Verification commands:**

```powershell
Set-Location modules/workbench/web
npm.cmd run lint
npm.cmd run build
node --test --test-concurrency=1 smoke/proffer-operations.contract.test.mjs smoke/proffer-operation-grid.contract.test.mjs
npm.cmd run build-storybook
```

## Phase F7 — Operation detail and entire-process visibility

**Status at handoff:** **PARTIAL CONTRACT ONLY.** Current detail has stages, attempts, refs, receipts, reason, and times; complete service/n8n/Temporal/package/decision correlation is not yet rendered or fully served.

**Goal:** Answer “what is it doing, what is it waiting for, who/service owns the next step, and what happened?” for any operation.

**Relevant gotchas:** A-1, A-2, A-4, S-8, A-29.

**Allowed paths:** Operation-detail components/stories/smoke tests and generated client only.

**Exit criterion:** Opening an operation shows package/source version, declared purpose, lifecycle, current/active stages, each stage’s service/status/attempt/elapsed/progress/reason/outputs/receipts, human wait and required action, sanitized Temporal/n8n/service/projection bindings, decisions/overrides, last authoritative observation, and explicit unavailable state; a tiny running file never displays a spinner without stage, owner/service, elapsed time, and last update.

**Verification commands:**

```powershell
Set-Location modules/workbench/web
npm.cmd run lint
npm.cmd run build
node --test --test-concurrency=1 smoke/proffer-operation-detail.contract.test.mjs smoke/proffer-process-visibility.contract.test.mjs
npm.cmd run build-storybook
```

## Phase F8 — Background/reopen and truthful workflow controls

**Status at handoff:** **BACKGROUND/REOPEN PARTIAL; CONTROLS CORRECTLY ABSENT.** Current code can reopen by opaque handle; no durable cancel/retry/hold/resume receipt contract exists yet.

**Goal:** Let the owner keep working while operations continue, then expose only controls the durable backend actually permits.

**Relevant gotchas:** S-5, S-9, A-12, B-1.

> **Sync point:** Backend Phase B7 must prove `allowed_commands`, expected revision, idempotency, transition semantics, and append-only receipts before controls are enabled.

**Allowed paths:** Operation registry/detail/control components, URL state, stories, focused smoke tests.

**Exit criterion:** Starting work returns immediately to an operation-aware Intake surface; the owner can change source, navigate elsewhere, return, and reopen the same operation; closing/navigating never cancels it; only commands listed by the backend render; Hold/Resume/Cancel/Retry show accepted versus completed semantics and immutable receipt references; duplicate/stale commands cannot produce misleading success.

**Verification commands:**

```powershell
Set-Location modules/workbench/web
npm.cmd run lint
npm.cmd run build
node --test --test-concurrency=1 smoke/proffer-background-reopen.contract.test.mjs smoke/proffer-operation-commands.contract.test.mjs
npm.cmd run build-storybook
```

## Phase F9 — Authenticated owner portal and explicit surface launcher

**Status at handoff:** **NOT STARTED AS A COMPLETE PORTAL.** Workbench/Intake routes exist, but one Authentik-protected Workbench is not the required multi-surface launcher.

**Goal:** Present every explicitly admitted human-facing surface after one owner session while keeping infrastructure private.

**Relevant gotchas:** S-14, S-18, S-23, S-24, A-28, B-3, B-4.

> **Sync point:** Backend Phases B11/B12 must publish the allowlisted catalog and prove exposure/auth modes before links render.

**Allowed paths:** Portal route/components/stories/tests and generated catalog client. Do not edit deploy/auth configuration in this phase.

**Exit criterion:** After authenticated actor context, the portal renders only server-allowlisted surfaces with label, purpose, category, exposure, health, and canonical URL; Workbench/Intake is one destination; `advocatio` is labeled “Advocatio — Legal Workdesk” only after route verification; Coolify uses `https://coolify.mitechconsult.com/`, is labeled Tailscale/private-by-default, and never exposes a direct port; tool runtimes, gateways, APIs, workers, databases, storage, webhooks, and native bridges never appear.

**Verification commands:**

```powershell
Set-Location modules/workbench/web
npm.cmd run lint
npm.cmd run build
node --test --test-concurrency=1 smoke/owner-portal-catalog.contract.test.mjs smoke/owner-portal-private-surfaces.contract.test.mjs
npm.cmd run build-storybook
```

## Phase F10 — Frontend release-candidate proof

**Status at handoff:** **NOT STARTED.** Existing focused tests do not prove the complete owner workflow.

**Goal:** Prove the complete frontend against versioned fixtures and an integrated candidate without hiding environment limitations.

**Relevant gotchas:** all frontend/cross-tier entries, especially S-1 through S-6, A-5 through A-9, A-29, A-30.

**Exit criterion:** The production build and Storybook pass; keyboard-only and supported-browser checks cover source selection, tabs, choices, override, Start, background/reopen, global filters, detail, waits, and truthful commands; all error/empty/unavailable states are visible; an integrated candidate completes the photo/no-repair path and one genuine repair path; no direct/private URL or secret appears in the browser bundle or UI.

**Verification commands:**

```powershell
Set-Location modules/workbench/web
npm.cmd ci
npm.cmd run lint
npm.cmd run build
npm.cmd run smoke
npm.cmd run build-storybook
```

Also run the agreed real-browser matrix against the integrated candidate and archive screenshots/network/status evidence without credentials.

## Phase F11 — Tauri host verification, not a UI fork

**Status at handoff:** **BLOCKED FOR NATIVE PROOF, NOT FOR BROWSER DELIVERY.** The isolated frontend stack passed; native linking failed in the Windows SDK environment at `kernel32.lib` resolution.

**Goal:** Prove the shared UI can be hosted by Tauri with only explicit native file capabilities.

**Relevant gotchas:** A-5, A-9, S-6.

**Allowed paths:** The existing approved Tauri host/package only. Do not create a second React application or local workflow database.

**Exit criterion:** On a documented Windows toolchain with the required SDK libraries, the Tauri package compiles, launches the same built React UI, stages an allowlisted local file through a typed native command, returns a version/digest-bound opaque reference, and then uses the same Intake REST contract; browser delivery remains independently releasable if native packaging is still unavailable.

**Verification commands:** Use the Tauri package’s checked-in build/test commands after its exact location is verified; record `rustc`, Cargo, MSVC, Windows SDK, and Tauri versions plus the full non-secret linker outcome. Do not report PASS from the Vite build alone.
