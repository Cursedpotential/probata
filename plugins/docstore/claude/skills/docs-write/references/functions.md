# docs-write — function reference

Source: `090_docs_api.surql`. Confirmed, live schema as of 2026-09-09.

## fn::docs_register

```
fn::docs_register(
  $source_path: string,
  $title: string,
  $doc_type: string,
  $domains: array<string>,
  $status: string,
  $body: string,
  $authored_at: option<datetime>
) -> object
  -- ok: {ok: true, id: record<document>}
  -- refused: {ok: false, error: "duplicate_active_document", source_path, existing_id}
```

`content_hash = crypto::sha256($body)` is computed server-side and is
`UNIQUE` on `document` — two byte-identical bodies at different paths still
collide and the write errors (a real throw, not the soft `{ok:false}`
shape, which is reserved for the path-uniqueness check).

## fn::docs_new_version

```
fn::docs_new_version(
  $old: record<document>,
  $body: string,
  $title: option<string>
) -> object  -- { new: record<document>, old: record<document> }
```

## fn::docs_supersede

```
fn::docs_supersede(
  $new: record<document>,
  $old: record<document>
) -> object  -- { new: record<document>, old: record<document> }
```

## fn::docs_retract

```
fn::docs_retract(
  $id: record<document>,
  $reason: string
) -> object  -- { ok, id, original_content_hash, content_hash } | { ok: true, unchanged: true } | { ok: false, error: "not_found" }
```

Retires a row and **releases its `content_hash`** (the `document_hash` index
is UNIQUE with no status predicate). Use it when a hand-registered row
carries the same bytes as a file the CocoIndex pipeline owns; the pipeline
row cannot land until the hash is released. Original digest is preserved in
`retracted_reason`; a `decision_log` row (`document_retracted`) is appended;
nothing is deleted. Rule (owner, 2026-09-14): do not hand-register files the
pipeline owns in the first place.

## ASSERT lists to satisfy before calling

- `$doc_type` ∈ `["blueprint","infrastructure","decision","todo","handoff","review","reference"]`
- `$status` ∈ `["active","proposed","unverified","superseded","retracted"]`
- every entry of `$domains` ∈ `["probata","proffer","consignatio","advocatio","vestigia","indagatio","intake","workbench","knowledge","memory","infra","docs"]`

A bad value throws a real ASSERT error from the schema, not a soft
`{ok:false}` — surface that error text to the user verbatim rather than
retrying blind.

## Worked example

```
run: { function: "fn::docs_register",
       args: [
         "docs/design/2026-09-09-docstore-memory-plugin-design.md",
         "The docstore + memory plugin",
         "blueprint",
         ["probata","docs","memory"],
         "active",
         "<full body text>",
         "2026-09-09T06:35:00Z"
       ] }
-- returns {ok:false, error:"duplicate_active_document", existing_id: document:xyz}
--   if this path is already registered and active -> use fn::docs_new_version instead:
run: { function: "fn::docs_new_version", args: [document:xyz, "<revised body>", NONE] }
```

## Gotchas

1. **Never race two `docs_register` calls on the same new path.** The
   uniqueness check and the `CREATE` are not one atomic statement from the
   caller's perspective if two agents call concurrently — prefer having a
   single writer (the librarian) serialize registrations.
2. **A superseded row at an active path is expected, not an error** — that
   is exactly what `fn::docs_new_version` produces. Only a second
   *non-superseded* row at the same path is refused.
3. **`chunk`/`entity`/`mentions` are not touched by any of these
   functions.** They belong to the ingestion pipeline; a document written
   through `fn::docs_register` has no chunks or embeddings until ingest
   runs over it.

## Tags (required on submission — owner 2026-09-14)

Files: front matter `tags: [ui-components, shadcn]` or `<!-- tags: a, b -->`;
the pipeline stores them in `document.tags` (lower-kebab, de-duplicated).
File-less notes/handoffs: same comment in the body, then

```
fn::docs_set_tags($id: record<document>, $tags: array<string>, $actor: string)
  -> {ok, id, unchanged, tags}      -- content/hash untouched; decision_log "tags_set"
fn::docs_tagged($tag: string, $query: option<string>, $domain: option<string>, $k: option<int>)
  -> [{id, source_path, title, doc_type, domains, tags, status, project, score?, excerpt?}]
```

Old files: run `python scripts/docstore/tags_backfill.py` (reads each registry
root's files, computes tags, writes only changed rows via fn::docs_set_tags;
no re-embedding). Files without author tags stay untagged.
