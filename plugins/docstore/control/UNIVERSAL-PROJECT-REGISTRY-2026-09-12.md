# Universal Propria Docstore source registry — implementation receipt

Date: 2026-09-12

Owner decision: Probata hosts Docstore; every Propria project is a consumer and
all project documentation is progressively registered for governed ingestion.

## Implemented

- A versioned `propria-docstore-source-registry-v1` manifest at the Propria root.
- Strict parsing with bounded size/count, stable lowercase IDs, unique canonical
  prefixes, monorepo-containment checks and required-root validation.
- `docstore_project_sources` and `docstore_project_source` read-only MCP tools.
- `docstore://projects` and `docstore://project/{project_id}` resources.
- Capability output reports registry availability and registered project count.
- Matching `projects` and `project PROJECT_ID` terminal commands.
- Explicit `DOCSTORE_PROJECT_REGISTRY` host configuration.
- Fail-closed tools and visible unconfigured/unavailable resource status.

Registry reads never enumerate, open, hydrate, copy, hash or index document files.
They expose source ownership and declared ingestion status only. The current
Probata docs root is marked `current-full-source`; other roots remain
`pending-multi-root-cdc` until the single CocoIndex app consumes the complete
registry and a worker receipt proves the resulting projection.

## Verification

The complete control suite passed after the transport additions: 256 tests,
with two existing live-only tests skipped. Protocol discovery reports 21 tools,
five static resources, four resource templates and one prompt. A later bounded
local Streamable HTTP probe initialized successfully and listed all 21 tools,
including project sources, related updates and governed flags.

Codex registration now exists under the collision-free name
`probata-docstore`. Claude marketplace package `probata-docstore@probata` 0.5.1
validates strictly, is installed and is enabled. Its package is deliberately
slim and launches the control source from E: rather than copying the control
virtual environment into the C: plugin cache.

## Remaining deployment boundary

This receipt proves source, local protocol behavior and local agent-host
registration. It does not prove production host activation. ContextForge
registration and production multi-root CocoIndex execution still require live
verification. Do not change a registry entry from `pending-multi-root-cdc`
merely because the MCP catalog exposes it.
