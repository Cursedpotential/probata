# Propria Search Plugin

This is the only canonical implementation of Smart Explore, CCC command exposure,
selectable memory recall, conflict discovery, and agent-driven reconciliation.
Documentation remains in the separate Docstore index. Smart Explore and CCC ingest
code only; reconciliation queries the isolated stores and preserves provenance.

## CLI

Run `search.cmd --help`. Existing Smart Explore commands remain available:
`index`, `indexes`, `search`, `outline`, `unfold`, `refs`, `lsp`, `imports`,
`changed`, and safe `prune` quarantine.

Direct CCC commands are `semantic`, `ccc-index`, `ccc-status`, `ccc-doctor`, and
`ccc-grep`. Reconciliation commands are `stores`, `recall`, `conflicts`,
`decisions`, `reconcile run`, `reconcile repair`, `reconcile status`, and `export`.
Every selectable-store response reports requested, available, queried, skipped,
error, adapter identity, duration, result count, and normalized result provenance.

Selectable stores: `smart_explore`, `ccc`, `docstore`, `codex_memory`,
`claude_memory`, `cnf`, `remember`, and `memsearch`. Modes: `auto`, `all`, and
`selected`. Selected mode requires an explicit nonempty store list.

Docstore is connected only through the JSON-stdio command named by
`PROPRIA_DOCSTORE_ADAPTER`; it never shares an index with code search.

## MCP tools

- `structural_search`
- `semantic_code_search`
- `code_index_refresh`
- `code_index_status`
- `code_index_doctor`
- `structural_grep`
- `store_inventory`
- `selected_store_recall`
- `conflict_discovery`
- `decisions_final_contracts`
- `reconcile_run`
- `reconcile_repair`
- `reconcile_status`
- `reconcile_export`

## Tool graph

```mermaid
graph TD
  U[User or agent] --> MCP[Propria Search MCP]
  MCP --> SE[Smart Explore structural DuckDB]
  MCP --> CCC[CCC semantic code index]
  MCP --> R[Selectable reconciliation]
  R --> D[Docstore docs adapter]
  R --> CM[Codex memory]
  R --> CL[Claude memory]
  R --> CNF[Claude Never Forgets]
  R --> REM[remember]
  R --> MEM[memsearch]
  R --> SE
  R --> CCC
  R --> P[Conflict and decision packet]
  P --> A[Bounded agent repair]
  A --> V[Tests, reindex, attribution validation]
  V -->|dirty| R
  V -->|clean| X[Export]
```

CCC identity is the resolved project root plus its `.cocoindex_code/settings.yml`
and `target_sqlite.db`. Smart Explore identity is resolved project root plus its
central DuckDB path. No invented application label replaces those identities.
