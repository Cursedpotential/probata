# Framework-neutral ingest restart recovery

> _Byline: Codex · GPT-5.6 · 2026-08-29; host paths re-rooted `/data/agno` → `/data/probata` 2026-09-07 by Claude Code · Fable 5.1 (infra rename plan §4.4)._
>
> **Status: SOURCE IMPLEMENTED / NOT DEPLOYED / NOT LIVE-PROVEN.**

## Implemented contract

- API startup schedules a bounded background scan instead of blocking readiness while large inputs
  replay.
- Only stale `framework-neutral-ingest` rows whose run status is `running` are eligible. Intentional
  pauses, waiting gates, terminal runs, failed stages, unexpected stage graphs, and fresh activity are
  excluded.
- Every newly reserved run persists the complete `IngestRequest` replay inputs in
  `ops.workflow_run.source_context`; recovery reuses the same receipt ID and reconstructs those exact
  values.
- Normal execution and recovery use the same session-level PostgreSQL advisory lock keyed by receipt
  ID. A concurrent replica that cannot acquire the lock does not execute the pipeline.
- Replay reruns the idempotent custody/parse/store/projection sequence. The framework-neutral store
  call uses its existing retry transaction contract; canonical duplicates remain guarded by existing
  artifact-record checks.
- Candidate execution has explicit age, scan, candidate, and concurrency bounds. One failed replay
  does not stop another. A stale run whose durable source or request can no longer be reconstructed is
  marked failed instead of remaining falsely `running` forever.

## Static verification

- `uv run pytest -q tests/test_ingest_staging_deploy_contract.py tests/test_ingest_recovery.py
  tests/test_ingest_routes.py` — **25 passed**, with one pre-existing Starlette/httpx deprecation
  warning.
- `uv run ruff check server/ingest/service.py server/api/main.py tests/test_ingest_recovery.py`
- `uv run ruff format --check server/ingest/service.py server/api/main.py tests/test_ingest_recovery.py`
- `uv run mypy server/ingest/service.py server/api/main.py`
- `git diff --check -- server/api/main.py server/ingest/service.py tests/test_ingest_recovery.py`
- `uv run ruff check tests/test_ingest_staging_deploy_contract.py` and
  `uv run ruff format --check tests/test_ingest_staging_deploy_contract.py` — passed.
- `deploy/exec.yaml` loaded with `yaml.safe_load`; the resulting service contract has the exact
  literal staging root and bind described below.
- Docker Compose's current official service reference documents that long bind syntax with
  `create_host_path: false` prevents the legacy short-syntax behavior of creating a missing host
  directory: <https://docs.docker.com/reference/compose-file/services/#long-syntax-5>.

## Production staging contract

`deploy/exec.yaml`, the actual manifest for Coolify app `exec-tier`
(`rz41wqhpjfh1rj796ixvjhfs`), now declares the production recovery boundary:

- host source: `/data/probata/volumes/ingest-staging`;
- container target and literal `INGEST_STAGING_ROOT`: `/data/ingest-staging`;
- read/write bind with `bind.create_host_path: false`, so a missing host directory stops deployment
  instead of silently creating an unprotected replacement; and
- a separate mount from `/srv/ingest:/data/ingest`, which remains the operator drop directory rather
  than becoming API-upload custody.

The current repo image inherits root execution from `agnohq/python:3.12` and does not set a later
`USER`. Before deployment, prepare the host path on OVH-1 with:

```sh
sudo install -d -m 0700 -o root -g root /data/probata/volumes/ingest-staging
```

Do not place a password, access token, or other secret in this path contract or in
`INGEST_STAGING_ROOT`.

## Live prerequisites and release hold

1. **Fix the live Coolify watch paths before relying on automatic deployment.** A read-only Coolify
   query on 2026-08-29 found the actual app at `/deploy/exec.yaml`, but its watch paths remain
   `compose.exec.yaml`, `Dockerfile`, and `server/**`. Replace the retired first entry with
   `deploy/exec.yaml`; then re-query the app and preserve that result as live evidence. This source
   lane did not mutate Coolify.
2. On OVH-1, run the exact host-prep command above and verify the directory is root-owned with mode
   `0700` before requesting deployment. A missing directory must cause the Compose bind to fail.
3. Deploy the current revision and inspect the resulting `agentos-api` container. Prove the mount is
   read/write, its source and target match the paths above, the effective environment names the same
   target, and the upload route writes staged bytes onto the host bind rather than container `/tmp`.
4. Terminate an ingest after receipt reservation, restart the API, and
   prove exactly one replica acquires the advisory lock and completes the original receipt.
5. Repeat with two API replicas starting concurrently, a missing staged source, a parser failure, and
   a store-stage interruption. Verify stage/run terminal states and absence of duplicate canonical
   records.
6. No deployment, Coolify configuration change, host mutation, or live database mutation was
   performed in this lane. Until gates 1-5 have evidence, status remains **SOURCE IMPLEMENTED / NOT
   DEPLOYED / NOT LIVE-PROVEN**.
