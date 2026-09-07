# Temporal (P0) — deployment guide

> _Byline: Claude Code · Opus 5 · 2026-08-23_
> Full plan: `docs/plans/TEMPORAL-INTEGRATION-PLAN-2026-08-23.md` (D-067)

P0 stands up Temporal on the fleet as infra only — no pipeline moves onto it
yet. See the plan for P1 (wrap `chat-transcript`), P2 (HITL gate → Signal),
and P3 (observability).

## What each piece is

- **`temporal-server`** (`compose.temporal.yaml`) — `temporalio/auto-setup:1.25`.
  Runs Temporal's frontend/history/matching/worker services in one container
  and auto-initializes schema against an external Postgres on first boot.
  Persists into the **existing** PG18 on `ovh-files` (100.91.190.107) as two
  databases, `temporal` and `temporal_visibility`, via role `temporal` — NOT
  a new database container (see the plan's Milvus/embedded-etcd corruption
  history for why that rule exists). gRPC frontend on `7233`.
- **`temporal-ui`** (`compose.temporal.yaml`) — `temporalio/ui:2.31`. Web UI
  for browsing workflow history, tailnet-only, published on `8233` (not
  `8080` — `coolify-proxy` owns host port 8080 on every node).
- **`temporal-worker`** (`../../docker/temporal-worker/Dockerfile`) — the
  Python worker process. Carries the full `server/` dependency stack (agno,
  sqlalchemy, weaviate client, chonkie, temporalio) because Activities call
  the existing pipeline code (custody, store, knowledge ingest) directly.
  Joins task queue `evidence-pipeline`. This is its **own** Coolify app, per
  separate-everything-separable — it is not declared in `compose.temporal.yaml`.

## Coolify deployment — three apps

1. **`temporal-server`** — Coolify "Docker Compose" app, compose file
   `deploy/temporal/compose.temporal.yaml`, service `temporal-server` only
   (or deploy both services from this file together — they're small and
   share a lifecycle). Watch paths: `deploy/temporal/compose.temporal.yaml`.
   - Env: `TEMPORAL_DB_PASSWORD` — the password for Postgres role `temporal`
     on `100.91.190.107`. **Set this in the Coolify env editor. It is never
     committed to git, never appears in this file or any tracked file.**
2. **`temporal-ui`** — same compose file, service `temporal-ui`. No secrets
   of its own; it only talks to `temporal-server:7233` over the shared
   `probata` docker network.
3. **`temporal-worker`** — Coolify "Dockerfile" app, build context repo
   root, dockerfile `docker/temporal-worker/Dockerfile`. Watch paths:
   `docker/temporal-worker/**`, `server/**`, `scripts/**`, `sql/**`,
   `requirements.txt`.
   - Env: everything `agentos-api` already gets in `deploy/exec.yaml`
     (`DB_HOST`/`DB_PORT`/`DB_USER`/`DB_PASS`/`DB_DATABASE`,
     `WEAVIATE_HTTP_HOST`/`WEAVIATE_HTTP_PORT`/`WEAVIATE_GRPC_PORT`,
     `PORTKEY_BASE_URL`/`PORTKEY_PROVIDER`/`PORTKEY_API_KEY`/etc. — see
     `deploy/exec.yaml` and `deploy/workbench.yaml` for the exact names in
     use), **plus**:
     - `TEMPORAL_ADDRESS` — defaults to `temporal-server:7233` (resolves
       over the shared `probata` network; only override if the worker ever
       runs off-box).

Host prep before first deploy of any of the three apps:

```
docker network inspect probata >/dev/null 2>&1 || docker network create probata
```

The `temporal` / `temporal_visibility` databases and the `temporal` role
already exist live on `100.91.190.107` PG18 (created out-of-band the same
night as this scaffold — see `docs/CHANGE-ORDER.md` CH-16). No migration
step is needed before first deploy; `auto-setup` initializes schema itself.

## Retention

Bounded retention (30 days) is set post-boot, once, against the running
server — not baked into the image:

```
temporal operator namespace update --retention 720h default
```

Run this from anything that can reach `100.91.190.107:7233` (tailnet) with
the `temporal` CLI installed, once `temporal-server`'s healthcheck is green.

## P0 exit test (live, per policy — verbatim from the plan)

> start a trivial workflow, `docker restart` the worker mid-run, confirm it
> resumes from history. That is the one thing today's ledger cannot do.

This is the only acceptance criterion for P0. It requires the worker image
to actually run a workflow, so it can only be exercised once
`server/temporal/worker.py` and a trivial test workflow exist (first task of
P1) — this scaffold makes that runnable, it does not itself satisfy the test.
