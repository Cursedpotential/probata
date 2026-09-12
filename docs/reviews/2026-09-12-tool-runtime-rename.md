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
- Delivery branch: `codex/tool-runtime-rename` (temporary deployment proof); `main` cutover
  waits for the branch CI gate
- Coolify server: `ovh-app` (`fmuao9enq3nxk8qw5hqjzzce`)
- Application UUID: `e1mshujml6bv8ldtoe8n7je0`
- Runtime commit: `708c354067b265b24ed61820d3cc736b5338339d`
- Coolify deployments: `v6bwub7tv2p40ougk2ju4ww8` finished at 2026-09-12 15:17:07 EDT;
  duplicate crash-recovery deployment `o3ocbxl9f5uooadsv8vf50b9` finished at 15:20:42 EDT
- Coolify application after both deployments: `probata-tool-runtime`, `running:healthy`, same UUID
- `GET http://100.72.169.40:8090/health`: HTTP 200, registry `ok`, 43 tools
- `POST /tools/repair.capabilities/run`: all required formats ready — XML, HTML, JSON, NDJSON,
  CSV, PDF, and image
- `POST /tools/engine.poppler-inspect/run`: ready profile `poppler-linux-amd64`, package
  `22.12.0-2+deb12u3`, all checks passed
- `GET /sbv/health`: proxy reports reachable; direct `http://100.72.169.40:8085/` returned HTTP 200
- Local verification: 63 focused Python tests, full `modules/engine` Go suite, Ruff on changed
  Python files, YAML parsing, and `git diff --check` all passed

The first branch pipeline's Go job passed. Its Python job stopped at a pre-existing Ruff format
gate in three `origin/main` files before lint/tests/naming could run. Mechanical-only formatting
is isolated in follow-up commit `d8b0cd1`, and two deliberate retired-name absence checks were
annotated in `61c5478` so the naming gate reports zero hits.

The clean rerun (`34702262280`) passed formatting, Ruff lint, mypy (180 source files), and the
full Go build/vet/test job. It then stopped in the repository's pre-existing documentation-path
and ADR/D-reference resolution gate, before the general Python suite or naming step. The same
Validate workflow was already red on `origin/main` (`34483170186`) before this rename. The open
baseline includes many unrelated retired paths and unresolved decision references and is not
silenced or broadly rewritten in this runtime lane. The focused 63-test runtime suite and the
live runtime proofs above remain the named acceptance evidence. A local attempt at the entire
Python suite was also non-authoritative because this worktree lacks optional test dependencies
and historical SQL files; its collection errors are not reported as runtime test failures.
