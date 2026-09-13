---
name: docs-write
description: Register a new probata document or publish a new version of an existing one in the SurrealDB docs store (blueprint/infrastructure/decision/todo/handoff/review/reference, domains probata/proffer/consignatio/advocatio/vestigia/indagatio/intake/workbench/knowledge/memory/infra/docs). Use whenever a Write/Edit under docs/** just happened (the PostToolUse hook flags it as unregistered), or when content needs to enter the store for the first time. Only the docstore-librarian agent writes.
allowed-tools: mcp__plugin_propria_docstore_docs__run mcp__plugin_propria_docstore_docs__list Read
---

# Docs write

Definition of done for this skill is a **store record id**, not a saved
file. A file on disk that never got registered is exactly the drift this
plugin exists to prevent.

## New document

```
run: { function: "fn::docs_register",
       args: [$source_path, $title, $doc_type, $domains, $status, $body, $authored_at_or_none] }
```

Refuses (returns `{ok:false, error:"duplicate_active_document", existing_id}`,
never throws) if a non-superseded row already exists at `$source_path` — in
that case call `fn::docs_new_version` instead.

## New version of an existing document

```
run: { function: "fn::docs_new_version", args: [$old_id, $new_body, $new_title_or_none] }
```

Inherits `doc_type`/`domains`/`source_path` from `$old_id`, creates the new
row `active`, `RELATE`s `new->supersedes->old`, flips `$old_id` to
`superseded` — all in one call. This is the only way an already-active
`source_path` legitimately gets a second live row.

## Linking an already-created document as a replacement

```
run: { function: "fn::docs_supersede", args: [$new_id, $old_id] }
```

Edge + status flip only, no new document created — use when `$new_id`
already exists (e.g. registered separately) and now needs to replace
`$old_id`.

## Definition of done

- A record id was returned, not just a file write.
- `doc_type` and `domains` are set from the real D-156 lists (see
  `references/functions.md`), never left to defaults you didn't check.
- If this replaces something, the `supersedes` edge exists and the old row
  is `superseded` — verify with `fn::docs_get` on the old id.

## Refusals

Refuse to hand-write `document`/`chunk`/`entity`/`mentions` any other way,
refuse to `DELETE`, refuse to skip the duplicate-check by racing
`docs_register` twice for the same path.

See `references/functions.md` for exact signatures, the ASSERT lists, and a
worked example.
