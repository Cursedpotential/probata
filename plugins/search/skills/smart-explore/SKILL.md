---
name: smart-explore
description: Canonical Propria structural code search, direct CCC semantic search and index controls, selected-store recall, conflict discovery, and reconciliation.
---

# Smart Explore

Use the Search plugin for code discovery before reading whole files. This skill
contains instructions only. The sole engine implementation is
plugins/search/smart_explore.py in the same plugin.

## Runtime and ownership

Run the plugin launcher so the locked uv environment supplies DuckDB and
Tree-sitter:

~~~powershell
plugins\search\search.cmd --help
~~~

Propria-owned paths route to
E:\AI_Workspace\Projects\Propria\.runtime\search\smart-explore\indexes.
Other paths route to C:\Users\matts\.smart-explore\indexes. The user home may
contain profiles, thin launchers, future project customizations, and generated
indexes. It must not contain a second engine copy. A --db override is for an
isolated diagnostic only.

## Structural CLI

~~~powershell
search.cmd search "source repair" --path <root> --max 20 --json
search.cmd outline <file> --json
search.cmd unfold <file> <symbol> --json
search.cmd refs <symbol> --path <root> --json
search.cmd index <root> --json
search.cmd indexes --json
search.cmd changed --path <root> --since 24h --json
search.cmd lsp --json
~~~

The engine incrementally parses supported source files with Tree-sitter and
stores structural symbols in DuckDB. Search results identify the index root,
file, line, symbol, kind, signature, and score.

## Direct CCC natural-language tools

These stay directly user-callable:

~~~powershell
search.cmd semantic "<natural-language code query>" --path <root> --lang python --limit 10
search.cmd ccc-index --path <root>
search.cmd ccc-status --path <root>
search.cmd ccc-doctor --path <root>
search.cmd ccc-grep --path <root> --query "<structural example>"
~~~

MCP exposes semantic_code_search, code_index_refresh, code_index_status,
code_index_doctor, and structural_grep separately. Smart Explore orchestration
does not hide these tools.

## Recall and reconciliation

Selectable stores are smart_explore, ccc, docstore, codex_memory,
claude_memory, cnf, remember, and memsearch. Use auto, all, or selected mode.
Every response must report each store as requested, available, queried, skipped,
or error with adapter identity and provenance.

~~~powershell
search.cmd stores --path <root> --json
search.cmd recall "<query>" --path <root> --mode selected --stores ccc --stores docstore
search.cmd conflicts "<query>" --path <root> --mode all
search.cmd decisions "<query>" --path <root> --mode all
search.cmd reconcile run "<query>" --path <root> --mode all
search.cmd reconcile status <packet>
search.cmd graph-preview <packet>
search.cmd graph-query <packet> --text "<term>"
search.cmd export <packet> --format md
~~~

The MCP catalog separately exposes structural_search, selected_store_recall,
conflict_discovery, decisions_final_contracts, reconcile_run, reconcile_repair,
reconcile_status, reconcile_graph_query, reconcile_graph_preview,
reconcile_export, and store_inventory.

## Index fence

There are exactly two ingestion indexes. Search/Smart Explore/CCC is the code
index and excludes documentation roots and documentation file classes.
Docstore/CocoIndex/SurrealDB is the docs index and excludes code. Reconciliation
queries both through adapters while preserving their separate identities.
Unavailable stores fail visibly with a recovery action; they are never silently
substituted.

Never stage DuckDB, SQLite, WAL, or other runtime state. Stale data may only be
moved into the nearest owner-controlled to_be_deleted quarantine.

