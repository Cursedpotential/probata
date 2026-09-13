---
name: reconcile
description: Audit the probata docs store for stale, duplicated, contradictory or orphaned records; rebuild the truth with the user's adjudication. Use when the store has drifted, retrieval quality degraded, migrating a messy legacy docs directory, or the user asks to clean up, dedupe, or verify probata's docs/DECISION_LOG/MASTER-TODO.
allowed-tools: Bash Read Grep Glob mcp__plugin_propria_docstore_control__coco_docstore_search mcp__plugin_propria_docstore_docs__run mcp__plugin_propria_docstore_docs__list
---

# Reconcile

Auditing, not tidying. Output is adjudicated truth with provenance, or an
escalation to the user — never a silent bulk write.

## Standing prohibitions

- **Never batch-write.** Adjudicate a cluster with the user, then write it.
- **Never `DELETE`.** No `fn::` in this store deletes anything — use
  `fn::docs_new_version`/`fn::docs_supersede` to move a record to
  `status: "retracted"` with a reason instead.
- **Never trust recency alone** over evidence of what actually shipped.

## Phase 1 — stale sweep

```
run: { function: "fn::stale_candidates", args: ["90d"] }
```

## Phase 2 — adjudicate with the user

For each candidate: is this a decision, a task, or noise? Is it still
current — search the store for anything superseding it? Is there evidence
it was acted on? Batch several candidates per message.

## Phase 3 — write confirmed outcomes

```
run: { function: "fn::docs_new_version", args: [$old_id, $revised_body_or_same, NONE] }
run: { function: "fn::decision_amend", args: [$subject_path, $banner, $closes] }
```

## Phase 4 — dedupe

Run the layered strategy in `references/dedupe.md`: exact hash (already
enforced at write time by `content_hash UNIQUE`), MinHash/Jaccard in
DuckDB, block-level within-file, semantic at query time (already handled
inside `fn::docs_search`'s fusion — do not re-implement).

## Phase 5 — verify the loop

```
run: { function: "fn::provenance", args: [$record_id] }
```

Check that `decision_log` rows exist for everything this session changed.

See `references/functions.md` for `fn::stale_candidates` details and
`references/dedupe.md` for the full four-layer dedupe strategy.
