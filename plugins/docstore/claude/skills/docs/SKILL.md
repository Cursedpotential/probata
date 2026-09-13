---
name: docs
description: Retrieve Propria blueprints, infrastructure notes, decisions, todos, handoffs and references from the universal CocoIndex and SurrealDB Docstore. Use first for documented decisions, plans, current state, ADRs, or open work; use the separate CCC index for implementation code.
allowed-tools: mcp__plugin_propria_docstore_control__coco_docstore_search mcp__plugin_propria_docstore_control__docstore_get mcp__plugin_propria_docstore_control__docstore_flags mcp__plugin_propria_docstore_docs__run mcp__plugin_propria_docstore_docs__list mcp__plugin_propria_docstore_docs__info Read
---

# Docs retrieval

<!-- Updated by: Codex | Date: 2026-09-12 | Rev: 1 | Platform: Codex / win32 | Changes: clarify system ownership | Context: owner request to persist CCC / Intake / Docstore distinction -->

Scope: Probata hosts the universal Propria Docstore: CocoIndex ingestion and NIM embeddings, with semantic vectors and document relationships in the dedicated SurrealDB `probata/docs` database. It is not codebase CCC or Intake's multimodal filesystem index. Documentation about Intake is not Intake data. Keep indexing state, credentials and target ownership separate; do not use codebase CCC as documentation ingestion. Current owner scope decisions take precedence over older mirrored descriptions; report any unregistered clarification rather than reverting to superseded intent.

The `docs/` directory is a **mirror**; the SurrealDB store is the **truth**.
If they disagree, the store wins — report the drift.

## Non-negotiable rules

1. Never answer from memory or from a filesystem read. Retrieve first.
2. Always scope: `doc_type` (blueprint/infrastructure/decision/todo/handoff/
   review/reference) and/or `domain`. Unscoped search returns plausible,
   wrong context.
3. Cite record ids. No id, no citation.
4. Empty result is a finding, not a prompt to improvise.

## Primary retrieval call

```
coco_docstore_search: { query: $query, domain: $domain, kind: $kind, status: "active", limit: 10, presentation: "compact" }
docstore_get: { record_id: $returned_document_id }
```

`coco_docstore_search` owns query embedding, SurrealDB KNN plus BM25 fusion,
validation and bounded DuckDB presentation. Do not make the agent manufacture a
vector or use a raw native `run/query` call for ordinary semantic retrieval.
Native functions remain available for exact structured records such as open-work
and provenance queries.

## Reading the result

`coco_docstore_search` returns one row per document: `id`, `source_path`,
`title`, `doc_type`, `domains`, `status`, `score`, `excerpt`.

**Treat `status` as authoritative:** `active` use it · `proposed` flag as
unconfirmed · `unverified` flag and prefer a second source · `superseded`
do NOT act on it — call `fn::docs_get` and follow `superseded_by` ·
`retracted` ignore, mention only if asked about history.

## Escalation

If either MCP server is unreachable (the SessionStart preflight already
checked this), stop and tell the user. No filesystem fallback — that
fallback is the exact drift loop this store exists to eliminate.

See `references/functions.md` for exact signatures, the `document` schema,
a worked example and gotchas (K/EF literals, post-filter KNN, status
default).
