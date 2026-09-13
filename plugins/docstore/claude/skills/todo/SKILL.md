---
name: todo
description: Open or close items on probata's MASTER-TODO register (T-ids) in the SurrealDB docs store. Use when the user says "add a todo", "what's open", "close T-<n>", "what's left to do", or a task surfaces work that isn't done yet.
allowed-tools: mcp__plugin_propria_docstore_docs__run mcp__plugin_propria_docstore_docs__list Read
---

# Todo

Backed by the `todo` table: `status` ∈ `["open","in_progress","blocked",
"done","dropped"]`, `priority` 0–4. `closed_at` is stamped automatically by
a `DEFINE EVENT` on the done/dropped transition — never set it by hand.

## Open an item

```
run: { function: "fn::todo_open", args: [$item_text, $priority, $domains, $source_path_or_none] }
```

## Close an item

```
run: { function: "fn::todo_close", args: [$id, $evidence_text] }
```

`$evidence` is appended to `detail`, not stored separately — write a real
sentence ("closed by commit abc123 / doc docs/x.md"), not "done".

## What's open

```
run: { function: "fn::open_work", args: [$project] }
```

**Known gap (see `references/functions.md`):** `fn::todo_open` does not set
`project`, but `fn::open_work` filters on it. An empty result from
`fn::open_work` does not prove nothing is open — cross-check with
`fn::docs_search(..., doc_type="todo", ...)` before reporting "nothing
open".

## Definition of done

An id was returned from `fn::todo_open`/`fn::todo_close`, `priority` is a
real 0–4 judgement (not always 2), and closing evidence is a real sentence.

## Refusals

Refuse to set `closed_at` directly, refuse to mark something `done` without
evidence, refuse to invent a `source_doc` link that doesn't resolve.

See `references/functions.md` for exact signatures and the domains-folding
gotcha.
