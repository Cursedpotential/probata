# Docstore worker supervision and crash visibility — 2026-09-12

> Byline: Codex · GPT-5 · 2026-09-12

Status: **source implemented and locally verified; existing worker is live, but
this supervision change is not deployed and no index run was performed by this work**.

## Finding

The Docstore state volume was already durable. `deploy/docstore-worker.yaml`
bind-mounts `/data/probata/volumes/docstore-worker` at `/data/state`, which owns
the CocoIndex state database, OS lock and append-only worker receipts.

The mandatory pre-update Docstore query also caught that this diverged working
copy predated verified port-fix commit `7cab671`: it still assigned the worker
host port `8473`, which belongs to `surreal-intake`. Only the already-approved
`8474` correction was reapplied; the dirty branch was not pulled, merged, reset
or broadly reconciled.

Read-only live verification on `ovh-files` then established the authoritative
mapping from both Docker bindings and `tailscale serve status --json`:

| Port | Live service |
|---|---|
| `8471` | `surreal-case` — Case Bible/Probata SurrealDB |
| `8472` | `surreal-docs` — Docstore SurrealDB |
| `8473` | `surreal-intake` — Intake SurrealDB |
| `8474` | `docstore-worker` — Docstore HTTP API/worker |

`svc:docstore-api` currently proxies to the transitional backend on `8474`,
`svc:surreal-intake` to `8473`, and `svc:surreal-docs` to `8472`. The live
`8474/health` response was `ok=true, store=up`, but still had the old two-field
shape. That proves the current API is operational and separately proves the new
supervision/health shape has not been deployed.

The startup process was not supervised. The image used
`worker_sync.py & exec uvicorn ...`; therefore Uvicorn could remain healthy after
the background startup sync exited. The old `/health` response also always used
HTTP 200 and the container healthcheck inspected only that status code, not the
JSON `ok` value. A failed sync or unreachable SurrealDB could consequently look
like a healthy API container.

## Source change

- `container_entrypoint.py` is now PID 1 and owns exactly two child processes:
  Uvicorn and one startup `worker_sync.py` invocation.
- It forwards termination only to those children. It performs no discovery,
  broad process kill, retry, schedule, corpus scan or service restart.
- The API remains available for diagnosis if the startup sync fails; no automatic
  failure loop launches another expensive run.
- Every worker invocation atomically maintains `/data/state/latest-run.json`.
  Append-only `worker-execution-v1` receipts remain the audit trail. The current
  status is a bounded operational projection and always carries
  `cdc_verified=false`.
- A current-status failure occurs before ingest/graph children launch. A terminal
  append-only receipt is still attempted and retained.
- `/health` now separates API liveness, SurrealDB reachability and latest worker
  execution state. The Docker healthcheck parses `ok=true`; it no longer treats
  every HTTP 200 response as healthy.

## Verification

- Full control suite after the addressing/SDK gate: **232 passed, 2 explicitly
  gated live revision tests skipped**.
- Focused worker/status suite: **37 passed**.
- Four changed Python sources compiled from text without creating another runtime.
- `git diff --check` passed for the bounded change set.

The code verification is local/source-level only. The image was not built locally
(repository policy forbids a duplicate local stack), nothing was deployed or
restarted, no model was contacted, and no corpus/indexing pass ran.

## Remaining boundary

The latest remote worker result becomes observable through `/health` after an
approved deployment. Historical `docstore_cdc_runs` remains an explicit local
receipt-directory reader; the local control plugin cannot read the VPS bind mount.
An authenticated, bounded remote receipt-history endpoint and corresponding
control-tool transport remain separate unfinished work. Execution success still
does not prove exact per-document CDC; revision/source/target verification remains
required. Read-only live port/container/service inspection did not query document
content or change any host state.

The later owner-directed port-family source change adds canonical Docstore HTTP
backend `8072` alongside transitional `8474`. It is intentionally dual-published
until a deployed `8072` probe and named-service repoint succeed; removing `8474`
before then would break the currently registered service hostname.
