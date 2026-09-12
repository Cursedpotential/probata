# todo — function reference

Source: `090_docs_api.surql` (`fn::todo_open`, `fn::todo_close`) and
`060_functions.surql` (`fn::open_work`). Confirmed, live schema as of
2026-09-09.

## fn::todo_open

```
fn::todo_open(
  $item: string,
  $priority: int,
  $domains: array<string>,
  $source: option<string>       -- a document source_path, resolved to source_doc if it matches
) -> object
  -- { id: record<todo>, title: string, priority: int, domains: array<string>, source_doc: record<document>|NONE }
```

## fn::todo_close

```
fn::todo_close($id: record<todo>, $evidence: string) -> object   -- the full updated todo row
```

`closed_at` is set by the `todo_close_stamp` EVENT on the transition into
`["done","dropped"]`, not by this function directly — do not also set it
in a follow-up call.

## fn::open_work

```
fn::open_work($project: string) -> array<object>
  -- {id, title, owner, priority, due, status}, WHERE status IN ["open","in_progress","blocked"]
```

## todo schema

- `title: string`, `detail: option<string>`, `project: string` default
  `"default"`, `owner: string` default `"unassigned"`
- `status` ASSERT: `["open","in_progress","blocked","done","dropped"]`, default `"open"`
- `priority` ASSERT: `0 <= priority <= 4`, default `2`
- `due: option<datetime>`, `source_doc: option<record<document>>`
- **No `domains` column on `todo`.** `fn::todo_open` folds `$domains` into
  `detail` as `"domains:a,b"` rather than dropping it silently.

## Worked example

```
run: { function: "fn::todo_open",
       args: ["Wire SURREAL_MCP_ALLOWED_HOSTS on surreal-case before the memory plugin can reach it",
              1, ["memory","infra"], "docs/design/2026-09-09-docstore-memory-plugin-design.md"] }
-- ... later:
run: { function: "fn::todo_close",
       args: [todo:abc123, "surreal-case redeployed 2026-09-10, /mcp initialize succeeded from desktop over tailnet"] }
```

## Gotchas

1. **No `domains` column on `todo`.** It is folded into `detail` as
   `"domains:a,b"`. Do not expect `fn::docs_search`'s `$domain` filter to
   apply to todos the way it does to documents.
2. **`fn::todo_open` never sets `project`.** `fn::open_work($project)`
   filters `WHERE project = $project`, so items opened through
   `fn::todo_open` will not appear in `fn::open_work` results unless
   `project` is set some other way. This is a real, unresolved gap between
   the two functions — flag it rather than assuming "no open work".
3. `closed_at` comes from the `todo_close_stamp` EVENT; setting it directly
   would just be a redundant second write racing the trigger.
