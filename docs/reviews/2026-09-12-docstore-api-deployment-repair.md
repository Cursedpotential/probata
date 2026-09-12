# Docstore API deployment repair

**Date:** 2026-09-12  
**Status:** Source collision fixed; Coolify application and Tailscale Service still absent  
**Scope:** The optional HTTP/front-end API served by `docstore-worker`; not the native SurrealDB MCP endpoint

## What was verified live

- The native Docstore MCP endpoint at `https://surreal-docs.tilapia-skilift.ts.net/mcp` is working. A native probe and governance reads passed, and `note:tool_runtime_rename_20260912` was written and read back at revision 1.
- `https://surreal-docs.tilapia-skilift.ts.net/health` returns HTTP 200.
- `docstore-api.tilapia-skilift.ts.net` does not resolve in tailnet DNS.
- No running or stopped Docker container on `ovh-files` has `docstore` in its name.
- `100.91.190.107:8473` is already bound by the healthy `surreal-intake` container and published as `svc:surreal-intake`. Its HTTP 200 health response is SurrealDB, not the Docstore API.
- The host Tailscale Serve configuration has no `svc:docstore-api` entry.

## Source repair

`deploy/docstore-worker.yaml` now publishes the worker API on tailnet host port `8474`, leaving Intake's port `8473` untouched. The compose comment records the ownership boundary so the collision is not reintroduced.

The YAML parses successfully and `git diff --check` passes. Local Docker Compose validation was unavailable because Docker is not installed on this Windows host; live deployment proof therefore remains outstanding.

## Remaining activation work

1. Create a dedicated Coolify compose application for `Cursedpotential/probata:main`, compose `/deploy/docstore-worker.yaml`, on `ovh-files`.
2. Provision its existing dedicated Docstore/database and provider credentials without printing them.
3. Deploy and require the container healthcheck plus `http://100.91.190.107:8474/health` to report `{"ok":true,"store":"up"}`.
4. Publish `svc:docstore-api` over HTTPS to the loopback/tailnet API target and verify the FQDN.
5. Re-run the control client's `health`, `stats`, search, get, and graph paths.

The locally cached Coolify API token returned HTTP 401 during this repair. No container was manually launched, no existing Tailscale Service was altered, and the healthy native Docstore service was not restarted.
