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

`full_reprocess=true` recomputes CocoIndex transforms but can leave external target
drift untouched when CocoIndex's tracked desired target already equals the newly
computed desired target. For that proven condition, the explicit combination
`full_reprocess=true, tracking_rebuild=true` moves the dedicated SQLite tracking
database and sidecars into the worker state's retained `to_be_deleted` quarantine,
bootstraps a fresh target declaration, and retires only Surreal document/chunk/edge
identities absent from the complete source snapshot. It never deletes the retained
tracking files. This repair is full-source only and still must pass exact attribution.

Index and run controls are registered MCP tools, not REST-only implementation
details: `docstore_pipeline_identity`, `docstore_index_full`,
`docstore_index_selected`, `docstore_run_current`, `docstore_run_get`,
`docstore_run_list`, `docstore_run_cancel`, and `docstore_attribution_verify`.

The docs index identity is `ProbataDocStore@probata-docstore`, `index_kind=docs`.
Operational calls accept only that literal kind and admit Markdown from governed
documentation roots. Source code, configuration, and tests are rejected. The
separate CCC identity is its project-root/settings/index tuple; repository/deploy
configuration declares no stable internal CocoIndex app/environment name for it.
Do not invent one or combine its run/attribution state with Docstore.

Cross-store diagnosis delegates through `docstore_reconcile_query`,
`docstore_reconcile_packet`, and `docstore_reconcile_validate` to the canonical
`Propria/tools/agent-reconcile/reconcile.cmd` JSON protocol. These tools query both
systems with provenance; they do not copy Smart Explore/CCC implementation into the
plugin and do not change either system's ingestion boundary. Persist adjudication
through the existing revision-exact Docstore flag/revision tools after human review.

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
