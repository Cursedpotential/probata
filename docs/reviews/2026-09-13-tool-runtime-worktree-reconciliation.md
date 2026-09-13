# Tool-runtime worktree reconciliation receipt — 2026-09-13

## Scope and starting state

- Linked worktree: `E:/AI_Workspace/Projects/_worktrees/probata-tool-runtime-rename`
- Branch: `codex/tool-runtime-rename`
- Git common directory: `E:/AI_Workspace/Projects/Propria/Probata/probata/.git`
- Starting HEAD: `90140202e4c2f123cb75c559db1f80c2d0e10e5a`
- Starting `origin/main`: `90140202e4c2f123cb75c559db1f80c2d0e10e5a`
- Starting remote feature branch: `a4a926f9d2b3d15a002a688761ac7882e7cb5f5a`
- The 16 commits reported as ahead of the remote feature branch were already present on `origin/main`; none was replayed or duplicated.
- The worktree contained a later uncommitted owner-portal build kit and a cross-stack Proffer operation-lifecycle slice. Every tracked and untracked source artifact was preserved.

## Reconciled commits

1. `085f1d3` — `docs(intake): add owner portal implementation buildkit`
2. `007a0de` — `feat(proffer): expose durable operation lifecycle`
3. This receipt commit.

The implementation adds an opaque-handle operation list/detail projection across the Go workflow, PostgreSQL preview store, runtime API, Workbench BFF, and browser ledger. Temporal workflow/run identities remain internal. It also registers the optional, fail-closed n8n flow-binding Activity without activating a production binding document.

During validation, the Workbench API file-size gate found `app/service/proffer.py` and `app/types/proffer.py` over their 300-line limit. Operation services/models and preview-event models were separated into focused modules. The full API suite then passed.

## Verification

- `go test ./...` from `modules/engine`: PASS.
- `go vet ./...` from `modules/engine`: PASS.
- `uv run --with-requirements requirements.txt pytest -q` from `modules/workbench/api`: PASS, 261 tests.
- `npm run build` from `modules/workbench/web`: PASS.
- Changed Proffer browser contract suite: PASS, 31 tests.
- Ruff lint over Workbench API source/tests: PASS.
- `git diff --check`: PASS before each commit.
- Broad Matter browser smoke remains unverified: both existing CDP cases abort immediately under Edge and Chrome and leave the fixture close waiting. The changed Proffer contracts do not depend on those Matter paths and pass independently. No live deployment or live integration claim is made.

## DuckDB branch collision map

After the DuckDB lane was reconciled and pushed at `5a7715670437557308ebbedfdbe45befc581eef9`, it was three commits ahead of `origin/main`. It overlaps this branch in 23 paths:

```text
modules/engine/postgres/proffer_preview_store_test.go
modules/engine/proffer/preview.go
modules/engine/proffer/workflow.go
modules/engine/proffer/workflow_test.go
modules/engine/profferworker/worker.go
modules/engine/profferworker/worker_test.go
modules/engine/runtimeapi/previewmodel/model.go
modules/engine/runtimeapi/proffer_preview.go
modules/engine/runtimeapi/proffer_preview_test.go
modules/engine/temporal/cmd/starter/upload_ingress_test.go
modules/engine/temporal/httpapi_test.go
modules/engine/temporal/starter.go
modules/workbench/api/app/runtime/proffer.py
modules/workbench/api/app/service/proffer_streams.py
modules/workbench/api/app/service/source_inspection.py
modules/workbench/api/app/types/proffer.py
modules/workbench/api/tests/test_proffer_contract.py
modules/workbench/api/tests/test_proffer_source_browser.py
modules/workbench/web/smoke/proffer-repair-gate.contract.test.mjs
modules/workbench/web/smoke/unified-intake-anatomy.contract.test.mjs
modules/workbench/web/src/components/intake/unified-intake.tsx
modules/workbench/web/src/lib/api-client.ts
modules/workbench/web/src/lib/shared/types.ts
```

Integration must preserve both semantics: DuckDB's governed parser selection/execution, timestamp normalization, and preview data; and this branch's lifecycle query, operation ledger, stable keyset pagination, and generic n8n flow registration. Merge or cherry-pick these commits onto the integration branch after the DuckDB commits, resolve the 23 overlaps deliberately, then rerun full Go, API, web build, Proffer contracts, and live integration gates.

## Worktree relocation handoff

This checkout remains at the external path while its branch is active. After integration and with no active writer, move it with `git worktree move` to `E:/AI_Workspace/Projects/Propria/_worktrees/probata-tool-runtime-rename`. Verify HEAD, branch, clean status, `.git` pointer, `git rev-parse --git-common-dir`, and content hashes after the move. Do not use a raw filesystem move.
