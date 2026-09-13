# Docstore CDC worker safety — 2026-09-12

Status: source hardening and isolated validation, **not deployed or corpus-tested**.
No full-source Docstore run, source corpus read, embedding call, graph rebuild or
live service change was performed for this increment.

## Verified constraint

Installed CocoIndex 1.0.21 exposes root-level App.update, not a selected-component
update argument. Reducing the walk's source patterns removes omitted components
from desired state and can retire their targets. `DOCSTORE_ONLY_FILES` is now
rejected before heavy imports, and the full worker no longer silently strips that
request and expands it into a full run.

References: [processing components](https://cocoindex.io/docs/programming_guide/processing_component/),
[App update](https://cocoindex.io/docs/programming_guide/app/),
[live component operators](https://cocoindex.io/docs/advanced_topics/live_component/).

## Source changes

- `flow_docs.py`: full source membership retained; strict raising exception handler
  around mounted files and awaited readiness; final error/in-progress statistics
  checked. Errors retain sanitized type diagnostics. No second app, target writer,
  or tracking store was introduced.
- `worker_sync.py`: nonblocking persistent OS lock; old/unknown sentinel locks are
  refused, not age-stolen or deleted. Explicit partial requests fail before work.
  Failed ingest prevents graph execution. Degraded health now exits nonzero.
- `run_support.py`: bounded retained logs (4 MiB each, excess drained/discarded with
  counters), timeout/cancellation of only this invocation's child, fsynced append-only
  JSON run events, no overwriting or deletion of logs/receipts/lock files.
- Health operations have a 60-second cooperative timeout. This is not a strict
  wall-clock ceiling against a dependency that ignores cancellation.

Receipts live in `DOCSTORE_RUN_RECEIPTS`, defaulting to `runs/` beside the worker
lock. A durable start event must exist before launching a child. Each successful
stage gets an event, followed by execution-finished/degraded/failed. Crash recovery
can identify starts without terminal events. No automatic crash recovery or retry
is claimed. Worker events explicitly retain **cdc_verified=false**: a successful
process exit and aggregate health are not exact per-revision projection proof.
These are worker-owned files, not yet a remote Docstore run-query tool.

## Validation and failure history

- Isolated tests exercise persistent locks, overlap refusal, legacy-lock refusal,
  bounded output, timeout, receipt durability/overwrite prevention, stage failure,
  unhealthy results, start-receipt failure and final CocoIndex error statistics.
- Real installed CocoIndex target-free smoke: child ValueError propagated; total
  error count 2 (child plus parent). Zero source files, target writes and model calls.
  Dedicated synthetic tracking remains at
  `E:/AI_Workspace/.intake-dev/temp/coco-error-proof-3437089f7815469bbc296a0692a7fcb8`.
- Initial real smoke exposed that `coco.runtime()` starts the DEFAULT environment,
  failing for missing default db_path. Removed the wrapper; explicit app.update
  alone succeeded in the failure-propagation test. Never repair that failure by
  pointing the default environment at CCC or another app's tracking state.
- Installed SurrealDB Python 3.0.0b8 checks every query statement error. No custom
  connector shim was added for a historical error-swallowing assumption. These
  versions match the Dockerfile's declared pins, not verified deployed versions.

## Activation gate and unfinished work

All concurrent writers must adopt the same lock protocol. Reconcile any legacy
sentinel and verify no legacy writer is active **before deployment**; never unlink
it merely because it is old. This patch does not perform that deployment.

The next functional change is a designed, tested live-component source migration
using the documented per-child operator update, while preserving existing component
paths, complete initial membership and target ownership. It needs sibling-retention
tests and explicit deployment/state verification before selected-file execution can
be exposed. No claim is made that such migration is already implemented.

Follow-up: [selected CDC synthetic proof](SELECTED-CDC-PROOF-2026-09-12.md)
records failed incremental-only attempts, successful bootstrapped finite-live
updates, guarded rejection, chunk retention, interruption and retry. It does not
activate or migrate the production worker.

Still required: revision/source fingerprint binding, exact chunk/vector readback,
remote run-status tools, durable per-document CDC receipts, and a small real source
edit-to-search proof. Do not mark `cdc_verified=true` from this worker receipt alone.

Canonical note: `note:docstore_cdc_worker_safety_20260912` (persist/read back through
Docstore tools; this file alone is not the canonical note).
