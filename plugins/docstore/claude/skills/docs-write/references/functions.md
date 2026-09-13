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
