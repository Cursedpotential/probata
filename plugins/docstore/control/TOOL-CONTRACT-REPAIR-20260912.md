# Docstore and CCC tool contract repair — in progress

Byline: Codex / GPT-6, 2026-09-12. Verification below is scoped to the observed caller.

The owner requires documentation CocoIndex indexing, semantic search, retrieval,
native Surreal tools, graphs, API resources, existence checks before writes,
DuckDB response shaping, and real validation feedback alongside isolated
project-local CCC indexing/search. Intake remains a third independent system.

## Verified in this task

- Installed Docstore tools: health, semantic search with keyword/vector results,
  DuckDB compact output, full record retrieval and graph retrieval succeeded.
- Installed flags and related-update tools failed for missing native auth.
- Canonical configuration loader now consumes the dedicated existing secret file
  keys, applies explicit precedence, validates the endpoint and preserves literal
  password characters. Both CLI and server entrypoints share this loader.
- Standard canonical CLI related-update query succeeded against the live store
  after that fix, including the previously recorded universal Docstore decision.
- New `docstore://api/openapi` resource returned the deployed OpenAPI 3.1.0 schema.
- New `docstore://api/surreal` resource discovered all 14 native tool schemas from
  the dedicated probata/docs endpoint without executing a database operation.
- Targeted server, CLI, configuration and transport tests: 90 passed.

## Still open — do not mark complete

- Installed cache/task registry has not been refreshed to these source changes.
- Plugin-injected control/surreal/memory entries contain unresolved substitutions;
  explicit probata-docstore registration coexists. Reconcile host packaging.
- CCC search failed: Windows User NVIDIA keys exist, but the caller/daemon did not
  inherit them. No existing owned launch adapter was found; no keys were copied.
- CCC MCP tools/API resources are not exposed in this task.
- Safe scoped documentation indexing execution, exact CDC proof, and live worker
  status are not established. Existing planning tools do not perform indexing.
- Handoff wrapper exists in source, but a successful installed write/readback is
  not proven. Do not replay stale engine handoff over newer active work.

## Next verification

Resolve registration at its source; refresh through the normal plugin installer.
Verify tools and resources through installed stdio. Persist this receipt as a
governed note with pre-write existence lookup and returned record identity.
Continue the independent CCC launcher and indexing-execution work; keep their
identities, credentials, state, locks and validation separate from Docstore.
