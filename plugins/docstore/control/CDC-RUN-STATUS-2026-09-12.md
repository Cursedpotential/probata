# CDC worker run-status surface — 2026-09-12

Status: **source implemented and locally verified; local receipt directory not configured and deployment not performed**.

`docstore_cdc_runs` and `runs [--run-id ID]` read the worker's append-only
`worker-execution-v1` JSON receipts from explicit `DOCSTORE_WORKER_RECEIPTS_DIR`.
The control surface never guesses a location, creates the directory, reads logs,
starts/cancels a worker or contacts a model/database.

The reader validates exact lowercase 32-hex run IDs, filename/record sequence,
receipt kind, timezone-aware timestamp, known state and `cdc_verified=false`.
Receipts are local regular non-reparse files capped at 64 KiB; the directory itself
must resolve to E: on Windows, stay outside indexed source docs and not be a
symlink/reparse location. Unrelated files are ignored. Broad listing fails closed
above 5,000 matching receipt files; exact run lookup is supported. Returned stage
data is bounded and omits log/receipt paths.

States are deliberately honest:

- last `running` receipt → `incomplete`;
- `failed` and `degraded` remain those states;
- `execution_finished` → `execution_finished_unverified`;
- sequence gaps are explicitly reported;
- every returned run keeps `cdc_verified=false`.

An execution receipt can prove what the worker reported, not exact per-document
projection freshness. Correlated revision/source/target verification remains a
separate required step.

The deployed-source compose definition does persist worker receipts under the
`/data/state` bind mount; this was verified statically on 2026-09-12. The local
control plugin still has no path to that VPS directory, so historical remote runs
are not yet available through this tool. Latest remote execution state will be
reported by `/health` after the source-only supervision change is deployed; see
[worker supervision](CDC-WORKER-SUPERVISION-2026-09-12.md).

Current local verification: 37 focused worker/status tests passed; after the
separate service-addressing and SDK gate, the complete control suite passed
**232 tests** with **2 explicitly gated live revision tests skipped**. No
production receipt directory was read by `docstore_cdc_runs`.
