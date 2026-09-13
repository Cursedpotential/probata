---
name: docs
description: Retrieve probata's blueprints, infrastructure notes, decisions, todos, handoffs and reference docs from the SurrealDB docs store — covering domains probata, proffer, consignatio, advocatio, vestigia, indagatio, intake, workbench, knowledge, memory, infra, docs. Use ALWAYS and FIRST for "what did we decide about X", "where is Y documented", "what's the current state of Z", or any question about project docs, ADRs or open work. Never Glob/Grep/Read the docs directory as a primary source — it is a mirror.
allowed-tools: mcp__plugin_docstore_docs__run mcp__plugin_docstore_docs__list mcp__plugin_docstore_docs__info Read
---

# Docs retrieval

The `docs/` directory is a **mirror**; the SurrealDB store is the **truth**.
If they disagree, the store wins — report the drift.

## Non-negotiable rules

1. Never answer from memory or from a filesystem read. Retrieve first.
2. Always scope: `doc_type` (blueprint/infrastructure/decision/todo/handoff/
   review/reference) and/or `domain`. Unscoped search returns plausible,
   wrong context.
3. Cite record ids. No id, no citation.
4. Empty result is a finding, not a prompt to improvise.

## Retrieval calls

```
run: { function: "fn::docs_search", args: [$query, $vec_or_none, $doc_type_or_none, $domain_or_none, "active", 10] }
run: { function: "fn::docs_get", args: [$id] }
run: { function: "fn::open_work", args: [$project] }
run: { function: "fn::provenance", args: [$record_id] }
```

No embedding available? Pass `NONE` for `$vec` — `fn::docs_search` still
runs the BM25 leg; degraded but honest, same principle as the old kit's
`search_text` fallback.

## Reading the result

`fn::docs_search` returns one row per document: `id`, `source_path`,
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
