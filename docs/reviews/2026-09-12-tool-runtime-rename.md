# Tool runtime rename receipt — 2026-09-12

> _Byline: Codex · GPT-5 · 2026-09-12._

## Owner ruling and boundary

The owner directed that the important component formerly called `platform-tools` be renamed.
The canonical internal component name is now `tool-runtime`; the existing Coolify application,
local image, compose service, and container use `probata-tool-runtime` or `tool-runtime` as
appropriate. This is an in-place cutover of Coolify application UUID
`e1mshujml6bv8ldtoe8n7je0`, not a second application.

| Surface | Before | Canonical after |
|---|---|---|
| Coolify application | `exec-platform-tools` | `probata-tool-runtime` |
| Compose manifest | `/deploy/platform-tools.yaml` | `/deploy/tool-runtime.yaml` |
| Compose service/container | `platform-tools` | `tool-runtime` |
| Local image | `agno-platform-tools` | `probata-tool-runtime` |
| Runtime URL variable | `PLATFORM_TOOLS_BASE_URL` | `TOOL_RUNTIME_BASE_URL` |
| Go HTTP adapter | `PlatformToolsClient` | `ToolRuntimeClient` |

The Go type, URL variable, and Docker-network hostname retain narrow compatibility shims while
callers move. `tool-gateway` remains the locator/materialization boundary, and the separate
`parser-runtime` is not part of this rename.

## Preserved unpublished work

The rename carries forward the orphaned runtime-hardening changes rather than overwriting them:

- the digest-pinned Python base and pinned Poppler package;
- the `engine.poppler-inspect` profile and health gate;
- explicit read-root enforcement for `/r2` and the shared tool-gateway materialization path;
- the read-only materialization volume used by the existing Go gateway boundary.

## Compatibility boundaries

- Docker network alias `platform-tools` remains temporarily so `deploy/exec.yaml` and any
  external callers using the old hostname survive the in-place cutover.
- ContextForge publication key `platform_tools` remains external compatibility state; it is not
  the runtime's canonical component name.
- `PLATFORM_TOOLS_BASE_URL` is accepted by `tool-gateway` only as a deprecated fallback.
- The similarly named variable in the proffer worker currently addresses `tool-gateway`, not
  this Python runtime, and is deliberately excluded from this rename.

## Source and verification

- Source repository: `Cursedpotential/probata`
- Delivery branch: `codex/tool-runtime-rename` (temporary deployment proof), then `main`
- Coolify server: `ovh-app` (`fmuao9enq3nxk8qw5hqjzzce`)
- Application UUID: `e1mshujml6bv8ldtoe8n7je0`
- Deployment status: **pending**
- Live facade proof: **pending**
- Live SBV proof: **pending**
- Exact commit: **pending**

This receipt must be updated with the deployment UUID, final branch/commit, Coolify health, and
live endpoint results before the rename is claimed complete.
