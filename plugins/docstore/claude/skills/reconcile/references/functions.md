# reconcile — function reference

Source: `090_docs_api.surql` / `060_functions.surql`. Confirmed, live
schema as of 2026-09-09.

## fn::stale_candidates

```
fn::stale_candidates($older_than: duration) -> array<object>
  -- {id, title, doc_type, project, status, observed_at, age_days}, LIMIT 200
```

`WHERE status = "active" AND observed_at < time::now() - $older_than AND
array::len(<-derived_from<-adr) = 0`. Only surfaces documents with **no**
`adr` derived from them — a document that some ADR already cites, however
old, is excluded on the theory it is still load-bearing. That means a
stale-but-still-cited document will never appear here; cross-check
`fn::provenance` manually for those.

## fn::provenance

```
fn::provenance($subject: record) -> object
  -- { record, history: array<decision_log-row>, sources: array<document> }
```

Use after every reconcile write to confirm the audit trail landed.

## fn::docs_new_version / fn::docs_supersede / fn::decision_amend

See `skills/docs-write/references/functions.md` and
`skills/decisions/references/functions.md` for full signatures — the
reconcile agent uses the same functions the librarian does, never a
separate reconciler-only write path.

## Gotchas

1. `fn::stale_candidates` silently excludes anything an `adr` row derives
   from — it is not a complete staleness audit by itself.
2. There is no `fn::` that sets `status = "stale"` on `document` — the
   schema's `status` ASSERT list is `["active","proposed","unverified",
   "superseded","retracted"]`, five values, no `"stale"`. Use
   `fn::stale_candidates`'s output as a worklist and either keep the
   document `active` (confirmed still current) or move it to `retracted`
   via a new version — there is no middle "flagged but not gone" state in
   this schema, unlike the older kit's `document.status` design. Say this
   plainly to the user rather than inventing a status value that would
   fail the ASSERT.
