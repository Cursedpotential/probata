---
name: docs-write
description: Register a new probata document or publish a new version of an existing one in the SurrealDB docs store (blueprint/infrastructure/decision/todo/handoff/review/reference, domains probata/proffer/consignatio/advocatio/vestigia/indagatio/intake/workbench/knowledge/memory/infra/docs). Use whenever a Write/Edit under docs/** just happened (the PostToolUse hook flags it as unregistered), or when content needs to enter the store for the first time. Only the docstore-librarian agent writes.
allowed-tools: mcp__plugin_propria_docstore_docs__run mcp__plugin_propria_docstore_docs__list Read
---

# Docs write

**Scope (owner 2026-09-14):** files under a Docstore registry root (Probata
`docs/**`, Consignatio, Legal-desktop, family-court, vestigia, Propria root docs)
are indexed by the CocoIndex pipeline. **Never hand-register those** with
`fn::docs_register` — the `document.content_hash` UNIQUE index makes a hand row
collide with the pipeline's own row and fail the run. This skill is for
file-less notes and records only.

**Tags are required when submitting (owner 2026-09-14 21:06).** For a file:
front matter `tags: [topic, ...]` or `<!-- tags: topic, ... -->` in the body;
the pipeline carries them into `document.tags`. For a file-less note: put the
same comment in `$body` AND call `fn::docs_set_tags($id, $tags, $actor)` right
after `fn::docs_register`. Query by tag with `fn::docs_tagged`.

Definition of done for a file-less note is a **store record id with tags**.

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
- `tags` is non-empty (`fn::docs_get` shows them); no untagged submissions.
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
