# CocoIndex ownership and execution

The existing documentation pipeline is CocoIndex v1 App `ProbataDocStore`, explicit Environment `probata-docstore`. The deployed worker uses its dedicated state volume and `DOCSTORE_COCOINDEX_DB`. Preserve identity and tracking state; changing a command label does not justify renaming the app or recreating its state.

The codebase-level CCC is separate. Never point its state or daemon at Docstore, or use `ccc index` as documentation ingestion.

## Current supported operations

Create a plan with `docstore_index_plan(paths=[...])`. Paths are relative to the explicitly configured source root. Its SHA-256 is over original local bytes, not the worker's normalized-content hash, and must not be compared as if they were the same hash algorithm/input.

Use `docstore_index_full()` for one authenticated full-source reconciliation.
Passing one to twenty paths requests exact verification of those paths, but the
worker still declares the complete source set to CocoIndex. This prevents selected
runs from retiring omitted documents. Use `docstore_index_selected(paths=[...])` for
that admitted selected-source request. Read `docstore_run_current`,
`docstore_run_get`, or `docstore_run_list`; a terminal run is CDC-verified only when
the source snapshot remained stable
and every managed source path and normalized content hash matched SurrealDB exactly.
Use `docstore_run_cancel` only for the exact active run returned by this API process.
`docstore_attribution_verify` performs the same complete path/hash comparison fresh
without starting indexing. `docstore_index_execute`, `docstore_run_status`, and
`docstore_cancel_run` remain compatibility aliases.

Index and run controls are registered MCP tools, not REST-only implementation
details: `docstore_pipeline_identity`, `docstore_index_full`,
`docstore_index_selected`, `docstore_run_current`, `docstore_run_get`,
`docstore_run_list`, `docstore_run_cancel`, and `docstore_attribution_verify`.

## Execution boundary

`DOCSTORE_ONLY_FILES` remains prohibited: declaring only a subset can cause CocoIndex
to retire omitted documents. The job API never sets it. Selected requests are
verification targets over a full-source run and incur the normal provider work for
whatever CocoIndex detects as changed.

`docstore_selected_update_plan` is a read-only prerequisite, not that missing job
API. Its request contains 1–20 exact document keys, canonical `docs/...` paths,
expected generations/revision numbers and raw SHA-256 values. Passing means those
source/revision checks matched at the plan snapshot. It never observes or creates a
committed CocoIndex bootstrap, acquires the writer lock, calls a provider or starts
the worker. Revalidate under the eventual exclusive execution boundary.

Before enabling execution, implement and verify: a persistent full-source manifest or genuinely nondeleting scoped reconciliation; a single admission/lock path shared by every launcher; durable run IDs/status; bounded logs/concurrency/timeouts; cancellation; explicit retirement policy; and source-to-store completeness checks. Test changed/unchanged/missing/failed files against an isolated target before production.

Existing audit findings: some settings load before DOCSTORE_ENV_FILE; direct flow launch bypasses the worker lock; stale-lock threshold can expire during a legitimate run; graph rebuild is whole-source and non-atomic. Do not start a worker or reindex merely to diagnose these.
