# Docstore API deployment repair

**Date:** 2026-09-12

**Status:** Complete; Coolify application healthy and Tailscale Service verified

**Scope:** The optional HTTP/front-end API served by `docstore-worker`; not the native SurrealDB MCP endpoint

## What was verified live

- The native Docstore MCP endpoint at `https://surreal-docs.tilapia-skilift.ts.net/mcp` is working. A native probe and governance reads passed, and `note:tool_runtime_rename_20260912` was written and read back at revision 1.
- `https://surreal-docs.tilapia-skilift.ts.net/health` returns HTTP 200.
- `100.91.190.107:8473` is already bound by the healthy `surreal-intake` container and published as `svc:surreal-intake`. Its HTTP 200 health response is SurrealDB, not the Docstore API.
- Coolify application `probata-docstore-worker` (`m6z6thra8hukgjshzx9r35fh`) is `running:healthy` on `ovh-files` from `Cursedpotential/probata:main` using `/deploy/docstore-worker.yaml`.
- Deployment `fddel68smf16jjrw86sh4kkj` completed successfully.
- Direct backend health at `http://100.91.190.107:8474/health` returns HTTP 200 with `{"ok":true,"store":"up"}`.
- Tailscale Service `svc:docstore-api` is registered for `tcp:443`, advertised by tagged device `ovh-files` (`nzyi2dAMrM11CNTRL`), and approved.
- The service FQDN `https://docstore-api.tilapia-skilift.ts.net/health` returns HTTP 200 with `{"ok":true,"store":"up"}`.
- `GET /stats` returns HTTP 200 with 500 documents, 11,688 chunks, 11,688 `chunk_of` edges, 137 `links_to` edges, 1,160 `cites` edges, 43 `supersedes` edges, and vector-index status `ready`.
- `GET /recall?q=tool%20runtime&kind=doc&k=1&status=all&rerank=false` returns HTTP 200 with a ranked document result.

## Source repair

`deploy/docstore-worker.yaml` now publishes the worker API on tailnet host port `8474`, leaving Intake's port `8473` untouched. The compose comment records the ownership boundary so the collision is not reintroduced.

The YAML parses successfully and `git diff --check` passes. Local Docker Compose validation was unavailable because Docker is not installed on this Windows host; the completed Coolify deployment and live health/API probes provide the deployment proof.

## Activation performed

1. Created the dedicated Coolify compose application on `ovh-files`.
2. Provisioned the existing Docstore/database and provider credentials without printing or persisting their values in this receipt.
3. Deployed the application and verified both Coolify health and the direct backend health endpoint.
4. Registered `svc:docstore-api`, advertised its HTTPS proxy to `http://100.91.190.107:8474`, and approved `ovh-files` as the service host.
5. Verified the published FQDN through health, stats, and recall requests from a separate tailnet client.

## Operational notes

- The stale Coolify credential was replaced with a scoped read/write/deploy token; no token value was printed or committed.
- The ContextForge `coolify-write` gateway was restored and the deployed Coolify MCP application was repaired for the current Coolify environment bulk-upsert request shape.
- Final Coolify MCP deployment `yixyuwaa8u5nqnomijdz9pbx` finished successfully, and its repaired `get_deployment` tool returned that status through the upstream MCP endpoint.
- No container was manually launched, no unrelated Tailscale Service was altered, and the healthy native Docstore service was not restarted.
- The repository does not contain the previously referenced `plugins/docstore/control/docstore.ps1`; equivalent health, stats, and recall paths were verified directly against the deployed API.
