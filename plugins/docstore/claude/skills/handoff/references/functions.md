# handoff — function reference

Source: `090_docs_api.surql`. Confirmed, live schema as of 2026-09-09.

## fn::handoff_write

```
fn::handoff_write(
  $title: string,
  $body: string,
  $domains: array<string>
) -> object   -- { id: record<document>, superseded: record<document>|NONE }
```

Implementation detail worth knowing: `source_path` for a handoff document
is synthesized as `"handoff://" + slug(title) + "/" + rand::uuid()`, so
handoffs never collide with each other or with a real file path the way
`fn::docs_register` path-uniqueness would — every call creates a genuinely
new row. Supersession is by **domain overlap with the previously active
handoff**, not by path.

## Supersede rule, precisely

```sql
SELECT id FROM document
WHERE doc_type = "handoff" AND status = "active"
  AND array::len(array::intersect(domains, $domains)) > 0
LIMIT 1
```

Only the **first** matching previous active handoff (by whatever order the
store returns) gets superseded. If two unrelated active handoffs both
happen to share one domain tag, only one gets replaced — check
`fn::docs_search(..., doc_type="handoff", status="active", ...)` after
writing if domain tags are broad, to make sure a stale handoff wasn't left
behind.

## Worked example

```
run: { function: "fn::handoff_write",
       args: [
         "docstore plugin build — 2026-09-09",
         "<full HANDOFF v2 body: STATUS, BUILD_STATUS, UNRESOLVED, ...>",
         ["docs","memory","probata"]
       ] }
```

## Gotchas

1. `$domains` must satisfy the same D-156 ASSERT as any other document
   (`["probata","proffer","consignatio","advocatio","vestigia","indagatio",
   "intake","workbench","knowledge","memory","infra","docs"]`).
2. Domain-overlap supersession means a handoff tagged very broadly
   (e.g. all twelve domains) will supersede almost any prior active
   handoff — prefer the narrowest accurate domain set.
3. This function never touches `chunk`; a written handoff has no
   embeddings/chunks until the ingest pipeline processes it, so it will not
   show up in `fn::docs_search`'s vector leg (BM25 leg over `title`/`body`
   still works immediately).
