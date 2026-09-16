# handoff — function reference

Source: `090_docs_api.surql`. **Fixed 2026-09-15/16** (see the file's
comment block above `fn::handoff_write`) — this file previously described
the pre-fix 3-arg "any domain overlap, LIMIT 1" behavior, which is retired.
Confirmed against `INFO FOR DB` on the live docs store 2026-09-16.

## fn::handoff_write

```
fn::handoff_write(
  $title: string,
  $body: string,
  $domains: array<string>,
  $supersedes: none | array<record<document>> | null
) -> object   -- { id: record<document>, superseded: array<record<document>>, match: "explicit"|"same_domain_set" }
```

Implementation detail worth knowing: `source_path` for a handoff document
is synthesized as `"handoff://" + slug(title) + "/" + rand::uuid()`, so
handoffs never collide with each other or with a real file path the way
`fn::docs_register` path-uniqueness would — every call creates a genuinely
new row.

## Supersede rule, precisely (fixed 2026-09-15/16)

If `$supersedes` is a non-empty array (each id through the `$ql` sentinel
over MCP `run`, e.g. `{"$ql": "document:abc"}`), exactly those documents are
superseded — nothing else.

Otherwise (no `$supersedes`, or `{"$ql": "NONE"}`), the function supersedes
**every** currently-active handoff whose `domains` array is the exact same
*set* as `$domains` (order and duplicates ignored):

```sql
SELECT VALUE id FROM document
WHERE doc_type = "handoff" AND status = "active"
  AND array::sort::asc(array::distinct(domains)) = array::sort::asc(array::distinct($domains))
```

**This is ALL matching rows, not "at most one."** Before 2026-09-15 the bug
was the opposite failure mode (any overlap, LIMIT 1 — clobbered one
arbitrary unrelated handoff). The fixed default is narrower (exact set, not
overlap) but is still an unbounded-count supersede: a common single-domain
tag like `["docs"]` can be the exact domain set of many unrelated real
handoffs. **Reproduced live 2026-09-16:** a disposable test call with
`$domains = ["docs"]` and no `$supersedes` matched and superseded *six*
real, unrelated active handoffs in one call (all reverted — edges deleted,
statuses restored to `active`). **Rule: always pass `$supersedes` explicitly**
— the real id(s) this handoff actually replaces, or `{"$ql": "NONE"}` cast
as an empty explicit list is not available, so pass `[]` via `$ql`
(`{"$ql": "[]"}`) to supersede nothing — rather than relying on the
same-domain-set default, unless you have just confirmed via
`fn::docs_search(..., doc_type="handoff", status="active", $domain, ...)`
that the exact-set match is exactly the one (or more) row(s) you intend to
close.

## Worked example

```
-- find what's currently active with this exact domain set FIRST:
run: { function: "fn::docs_search", args: ["", {"$ql": "NONE"}, "handoff", "docs", "active", 20] }
-- then write, superseding only the specific id(s) found above:
run: { function: "fn::handoff_write",
       args: [
         "docstore plugin build — 2026-09-16",
         "<full HANDOFF v2 body: STATUS, BUILD_STATUS, UNRESOLVED, ...>",
         ["docs","memory","probata"],
         [{"$ql": "document:<id to supersede>"}]
       ] }
```

## Gotchas

1. `$domains` must satisfy the same D-156 ASSERT as any other document
   (`["probata","proffer","consignatio","advocatio","vestigia","indagatio",
   "intake","workbench","knowledge","memory","infra","docs"]`).
2. **Do not call this with a broad or common domain set and no
   `$supersedes` "just to be safe"** — that is the exact call shape that
   superseded six real handoffs live on 2026-09-16. Narrow domains do not
   protect you; exact-set duplication among unrelated handoffs is common.
3. This function never touches `chunk`; a written handoff has no
   embeddings/chunks until the ingest pipeline processes it, so it will not
   show up in `fn::docs_search`'s vector leg (BM25 leg over `title`/`body`
   still works immediately).
