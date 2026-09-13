# Search plugin reconciliation receipt — 2026-09-13

## Governing result

`plugins/search` is the sole implementation owner for Smart Explore structural search, direct CCC semantic code search and index controls, selectable memory recall, conflict discovery, and reconciliation packets. The integration target is `E:\AI_Workspace\Projects\Propria\Probata\probata\plugins\search`; this review branch lives at `E:\AI_Workspace\Projects\Propria\_worktrees\probata-tool-runtime-rename\plugins\search` until integration.

The older `C:\Users\matts\.agents\skills\smart-explore\smart_explore.py` implementation was preserved under `C:\Users\matts\.agents\skills\smart-explore\to_be_deleted\pre-search-plugin-20260913\smart_explore.py` (SHA-256 `07109A42ADB648743EF1C7B974D9CE555D36179A3FD02928FBCBF9C10CE77CC8`). Its former location is now a thin compatibility launcher that prefers the integrated plugin and temporarily falls back to this review worktree. The fallback must be removed after integration so the review worktree cannot become a runtime dependency.

The canonical Windows launcher and MCP manifest use `C:\Users\matts\.local\bin\uv.exe` with the plugin-owned `pyproject.toml` and `uv.lock`. Tree-sitter Language Pack is pinned at 1.9.1 because the engine's node and parser API contract is version-specific. They do not depend on whichever Python happens to be on `PATH` or on the former global Smart Explore virtual environment. Calling `python smart_explore.py` directly is unsupported because it bypasses this declared runtime. The global `se.cmd`, `se`, and Python compatibility entry points delegate to the canonical launcher; their prior forms are preserved under the same `to_be_deleted` quarantine.

## Direct operator surface

The MCP server exposes 16 separately callable tools. Structural code search is `structural_search`. Natural-language CCC search is `semantic_code_search`, with language, path, offset, and limit inputs. CCC controls are `code_index_refresh`, `code_index_status`, `code_index_doctor`, and `structural_grep`. `store_inventory`, `selected_store_recall`, `conflict_discovery`, and `decisions_final_contracts` expose store identity and provenance. `reconcile_run`, `reconcile_repair`, `reconcile_status`, `reconcile_graph_query`, `reconcile_graph_preview`, and `reconcile_export` expose the agent workflow and its durable packet.

Each selected store reports whether it was requested, available, queried, skipped, or failed, plus adapter identity, duration, result count, and normalized source provenance. Supported stores are `smart_explore`, `ccc`, `docstore`, `codex_memory`, `claude_memory`, `cnf`, `remember`, and `memsearch`; modes are `auto`, `all`, and explicit `selected`. Missing stores remain visible as unavailable or errored. The engine does not silently substitute another store. Memsearch currently has an executable, configuration, and memory roots, but its configured `NVIDIA_NIM_API_KEY` environment reference is absent in this task environment. It is therefore reported unavailable with `health: config_error` and the non-secret recovery action to set that named variable and rerun `memsearch stats`.

The direct tools and reconciler are parallel user surfaces: direct tools return immediate search/index diagnostics; the reconciler queries selected stores, deduplicates resumed-session copies, records timestamps and session IDs when present, classifies decisions/contracts/supersession, exports a graph, and emits valid next actions. `reconcile_repair` does not mutate a repository blindly. A dirty packet requires an agent to identify the owning repository, inspect structural and semantic neighbors, consult governing memories and Docstore, make a bounded repair, run tests, reindex the affected store, and prove clean attribution.

Docstore remains a separate docs application and index. Search calls it only through the command configured in `PROPRIA_DOCSTORE_ADAPTER` using JSON stdin with schema `propria-search-reconcile/v1`, operation `query`, query, and limit. CCC and Smart Explore do not ingest documentation. Docstore retains its own search, retrieval, revision, and adjudication tools, so the surfaces do not collide.

The application graph has exactly two products. Application 1 is Probata/Proffer. Application 2 is the combined Xplorer + Case Bible + Consignatio tool: Xplorer supplies the ACP copilot, streaming plan/tool/approval queue, and permissioned MCP host; Case Bible/Consignatio supplies the review and legal-data surfaces. The index graph also has exactly two stores: Docstore/CocoIndex/SurrealDB for documentation with code excluded, and Search/Smart Explore/CCC/tree-sitter/DuckDB for code with documentation excluded. Reconciliation queries both through adapters and never merges their ingestion paths.

Original owner inputs anchor this graph. `F:\Users\matts\Downloads\xplorer-copilot-buildkit\xplorer-copilot-buildkit\BUILD_GUIDE.md` and `docs\01-PHASES.md` require streaming plan, tool-call queue, permission requests, and full permissioned MCP verbs. `F:\Users\matts\Downloads\surreal-docstore.zip` (`plugin/agents/docstore-reconciler.md`, `plugin/skills/reconcile/SKILL.md`, and `schema/060_functions.surql`) requires retrieval functions, explicit supersession, implemented-decision evidence over unsupported proposals, loud unavailable-store failure, and adjudicated writes without silent batch ingestion.

## Routed design decision

The model router classified this as architecture plus coding/debugging plus product risk. The sequence used was Reversibility, then Systems Thinking and Second-Order Thinking, with Scientific Method for the CCC contamination proof.

| Path | Fit | Consequence |
|---|---:|---|
| Canonical plugin owns direct tools and orchestrated recall | 5/5 | Chosen. One implementation, direct operator control, and durable cross-store adjudication. |
| External wrapper owns reconciliation while Smart Explore stays unchanged | 1/5 | Breaks the native-engine and single-copy contract. |
| Docstore owns code and memory orchestration | 1/5 | Collides with the separate code/docs application and index boundary. |
| Global skill and plugin both retain full engines | 1/5 | Creates inevitable behavior and schema drift. |

Consequence guards are part of the implementation: the orchestrator cannot hide direct CCC diagnostics; `selected` requires a nonempty store list; every unavailable/error state remains in output; active DuckDB WAL files are never opened or pruned; stale Smart Explore indexes are quarantined instead of deleted; dirty reconciliation cannot claim completion; and the compatibility fallback is explicitly temporary.

## Verification

- Python compilation passed for `smart_explore.py`, `reconciliation.py`, and `mcp_server.py`.
- Ten unit tests passed for store selection, unavailable-store provenance and recovery actions, memsearch credential-health reporting, persisted agent packets, the exact MCP catalog, bounded concurrent locking, active-WAL safety, and automatic repair of a missing FTS schema.
- MCP `initialize` and `tools/list` passed and returned the 16 tools named above.
- The canonical `search.cmd`, global `se.cmd`, global Python compatibility shim, and MCP process each returned a real structural `inventory` result using the locked plugin runtime. Two simultaneous launcher searches both exited zero after a bounded DuckDB lock retry. The plugin has not yet been integrated or installed from the final path, so that installed-path proof remains open.
- `search.cmd stores --path E:\AI_Workspace --json` passed through the thin compatibility launcher.
- A direct Smart Explore search for `inventory` returned the function in `reconciliation.py` with file, line, signature, and score. A selected Docstore recall reported Docstore unavailable, every unselected store explicitly skipped, `attribution_clean: false`, and the valid next action `configure PROPRIA_DOCSTORE_ADAPTER and retry`; it did not substitute another store or claim a clean result. Direct search/index MCP responses now include context-appropriate next actions. CCC structural grep returned an intelligible no-match result. The safe prune dry run returned `would_quarantine` and the exact `to_be_deleted` action without moving anything.
- The owner acceptance query `assess source repair resolve source repair` returned 40 real Probata engine symbols, led by repair tests and the `AssessSourceRepair` and `ResolveSourceRepair` methods. During this proof, a stale index with symbol state but no FTS schema was detected; search now rebuilds that schema automatically and retries instead of returning a catalog failure.
- The earlier packet `20260913T044215Z-601725e7` is retained as pre-health-check provenance; its filesystem treatment of memsearch is superseded and is not operational proof.
- The focused product-surface reconciliation `20260913T053335Z-a854817c` recorded 89 graph nodes and 106 edges with 16 decision candidates, 12 contract candidates, timestamps, session identifiers where present, store provenance, explicit Docstore/memsearch unavailability, and a critical actionable backlog. `graph-preview` and `graph-query` returned the packet through the direct CLI. Live `all` mode queried Smart Explore, Codex memory, Claude memory, CNF, and remember while reporting CCC, Docstore, and memsearch unavailable for that deliberately small project identity; the earlier focused packet proves explicit `selected` mode.
- CCC uses the project identity `E:\AI_Workspace\.cocoindex_code\settings.yml` plus `target_sqlite.db` and the remote `nvidia_nim/nvidia/nemotron-3-embed-1b` embedding model. The configuration excludes documentation roots and documentation file classes. The contaminated 4,998,172,672-byte database and its tracking state were moved to `E:\AI_Workspace\to_be_deleted\ccc-code-only-20260913`; no files were deleted.

Direct SQLite inspection of the rebuilt CCC auxiliary table found zero chunks and zero distinct files in `docs`, `doc`, `documentation`, `knowledge`, `memory`, `.remember`, `.memories`, `to_be_deleted`, `_worktrees`, or `probata-worktrees`, and zero `.md`, `.mdx`, `.rst`, `.txt`, `.html`, or `.htm` file classes. CCC doctor passed both 2048-dimension indexing and query model checks after loading the registry-backed credential into the process without printing its value.

The runtime-location correction and quarantine evidence are recorded in
`RUNTIME-RECONCILIATION-2026-09-13.md`. Smart Explore generated state now lives
only under the ignored Propria `.runtime/search/smart-explore` root; the engine
remains solely in `plugins/search`.

The clean CCC rebuild and a live semantic query must be recorded after the
running index job finishes. Until then, code-index freshness is **in progress**,
not complete.

## Product-surface acceptance boundary

This checkpoint verifies foundational tool and index plumbing only. The Search product surface is raw, has not received the owner's meaningful teardown, and is **not owner-approved**.

Search-tool exposure does not repair the broader Probata operator surface. The binding gap inventory is in `PROBATA-SURFACE-ACCEPTANCE-2026-09-13.md`. Critical unresolved items include full source-to-graph preview tabs, stage inputs/outputs and run/error/write visibility, correct parser/extractor repair choices, continue/override/retry/skip/cancel/checkpoint actions, n8n workflow and node-stage visibility/control, fail-closed TEST versus REAL matter propagation, actual programmatic SMS/iMessage and AI-chat imports, and DuckDB query/inspect/clean/validate/compare/export in the operator surface. A handoff cannot be called complete while those paths are unusable or while Git, deployment, or live tool invocation remains unproved.
