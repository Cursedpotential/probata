---
name: docs-write
description: Publish a new version of an existing probata document in the SurrealDB docs store, or register a FILE-LESS note/decision/record (no file on disk). Domains probata/proffer/consignatio/advocatio/vestigia/indagatio/intake/workbench/knowledge/memory/infra/docs. Only the docstore-librarian agent writes.
allowed-tools: mcp__plugin_propria_docstore_docs__run mcp__plugin_propria_docstore_docs__list Read
---

# Docs write

**Read this before calling `fn::docs_register` (owner rule, reinforced
2026-09-16).** A file under a registry root — Probata `docs/**`, Consignatio,
Legal-desktop, family-court, vestigia, Propria root docs — is entered into
the store by **writing the file itself** (with `tags:` front matter or a
`<!-- tags: a, b -->` comment); the CocoIndex pipeline indexes it on its next
run. **Never call `fn::docs_register`/`fn::docs_new_version` for a file the
pipeline owns** — `document.content_hash` is `UNIQUE`, so a hand-written row
collides with the pipeline's own row for that file and fails the run (see
`docstore` skill's routing table). The PostToolUse hook flagging a just-
written docs file as "unregistered" is a reminder that the pipeline hasn't
run yet, not an instruction to hand-register it.

`fn::docs_register` in THIS skill is for **file-less** content only: a note,
decision banner, or record that has no corresponding file on disk. If what
you're registering has a `source_path` under a registry root, stop — write
the file there instead and let CocoIndex index it.

Definition of done for this skill is a **store record id**, not a saved
file. A file on disk that never got registered through this path is a
file-less note that still needs one — not a repo file waiting for a hand
`docs_register` call.

**Record-id arguments over MCP `run`:** every `$old_id`/`$new_id` below is a
placeholder — when you substitute a real id, wrap it in the `$ql` sentinel:
`{"$ql": "document:xyz"}`, never a bare `document:xyz` string. A bare string
fails with `Failed to coerce argument ... Expected record<document> but
found 'document:xyz'` (reproduced live 2026-09-16). See
`references/functions.md` for the worked example.

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
