# docs — function reference

Source: `090_docs_api.surql` and `060_functions.surql` in the docstore
schema (probata docs SurrealDB, local, `127.0.0.1:8462`). Signatures below
are quoted verbatim from the `DEFINE FUNCTION` statements. This file is
**confirmed**, not provisional — the docs schema is applied and live as of
2026-09-09.

## fn::docs_search

```
fn::docs_search(
  $query: string,
  $vec: option<array<float>>,
  $doc_type: option<string>,
  $domain: option<string>,
  $status: option<string>,
  $k: option<int>
) -> array<object>   -- {id, source_path, title, doc_type, domains, status, score, excerpt}
```

Hybrid BM25 (document `title`/`body`) + scoped-KNN (`chunk.embedding`),
fused to document granularity, max score per id. `$status` defaults to
`"active"`. `$k` defaults to 10; above 20 it switches KNN candidate pool
from `<|20,128|>` to `<|50,256|>` (both literal — K/EF cannot be
parameters, even inside a function body).

## fn::docs_get

```
fn::docs_get($id: record<document>) -> object
  -- { document, status, supersedes: array<document>, superseded_by: array<document> }
```

`supersedes` = older docs this one replaces (`$id->supersedes->document`).
`superseded_by` = newer docs that replace this one
(`$id<-supersedes<-document`).

## fn::open_work

```
fn::open_work($project: string) -> array<object>  -- {id, title, owner, priority, due, status}
```

Deterministic, no embeddings. Filters `todo` where
`status IN ["open","in_progress","blocked"]`.

**Gotcha:** `fn::todo_open` (see `docs-write`/`todo` skills) does not set a
`project` field on the rows it creates — only `title`, `priority`, `detail`,
`source_doc`. `fn::open_work($project)` filters `WHERE project = $project`.
Until this is reconciled, `fn::open_work` will not surface todos created
through `fn::todo_open` unless the caller also sets `project` some other
way. Flag this as a known gap when reporting "what's open" — do not assume
an empty result means nothing is open.

## fn::provenance

```
fn::provenance($subject: record) -> object
  -- { record, history: array<decision_log-row>, sources: array<document> }
```

`history` reads `decision_log` (append-only, written only by `DEFINE EVENT`
triggers — never hand-write these rows). `sources` follows
`$subject->derived_from->document`.

## fn::stale_candidates

```
fn::stale_candidates($older_than: duration) -> array<object>
  -- {id, title, doc_type, project, status, observed_at, age_days} (LIMIT 200)
```

Active docs with no `derived_from` incoming edge and `observed_at` older
than `$older_than`. Reconciler's sweep list, not for routine retrieval.

## The `document` schema (for interpreting results)

- `doc_type` ASSERT: `["blueprint","infrastructure","decision","todo","handoff","review","reference"]` (seven, D-156)
- `status` ASSERT: `["active","proposed","unverified","superseded","retracted"]`, default `"unverified"`
- `domains` ASSERT (array, D-156 canon): `["probata","proffer","consignatio","advocatio","vestigia","indagatio","intake","workbench","knowledge","memory","infra","docs"]`
- `content_hash` is `UNIQUE` — a byte-identical second file fails `fn::docs_register` at write time (see `docs-write`).
- `age_days` is `COMPUTED`, not stored: `time::now() - (authored_at OR observed_at)`.

## Worked example

```
run: { function: "fn::docs_search",
       args: ["docstore plugin progressive disclosure", NONE, "blueprint", "docs", "active", 10] }
-- inspect hits, then for the top hit:
run: { function: "fn::docs_get", args: [document:abc123] }
-- if status == "superseded":
run: { function: "fn::docs_get", args: [<id from superseded_by[0]>] }
```

## Gotchas

1. **Post-filter KNN trap.** Never wrap a KNN query in an outer
   `SELECT ... FROM (subquery) WHERE scope`. The scope predicate must sit
   inside the same `WHERE` as `<|K,EF|>` so SurrealDB folds it into the
   `KnnScan` plan node — a wrapping filter only inspects the fixed top-K set
   already returned, silently truncating recall for narrow scopes with
   `status: OK` and no error. `fn::docs_search` already does this correctly;
   never write the query yourself.
2. **K/EF literal.** `<|$k,64|>` is a parse error. `fn::docs_search` carries
   two fixed KNN variants rather than a parameterised K.
3. **Status default is `"active"`.** An unscoped search never silently
   includes superseded/retracted rows unless `$status` is passed explicitly.
4. **A superseded hit is not an answer.** Always traverse `superseded_by`
   before reporting content from a superseded document.

## Optional arguments over MCP: the `$ql` sentinel (corrected 2026-09-09 07:22 EDT)

~~When calling functions through the native MCP `run` tool, a JSON `null` argument arrives as SurrealQL `NULL`, not `NONE`. Every optional parameter in `060_functions.surql` and `090_docs_api.surql` is therefore typed `option<T | null>` and tested with `($p = NONE OR $p = NULL)`. Pass `null` for any optional argument you want to skip; positional order is fixed. Example that returned a real hit: `run fn::docs_search ["no migrations ever snapshot rebuild", null, "decision", null, "active", 3]`.~~

**Correction 2026-09-09 07:22 EDT (owner: "why the hack? look it up").** The `option<T | null>` widening was a patch, not the documented way. It is reverted: every optional parameter in `060_functions.surql` and `090_docs_api.surql` is plain `option<T>` again and bodies test `$p = NONE` (re-applied over `/sql`: 060 7/7, 090 9/9). The documented mechanism is the `$ql` sentinel, published in the `run` tool's own `inputSchema`: "Embed typed SurrealDB values via `{"$ql": "<expr>"}`". Source `surrealdb/mcp/src/tools/mod.rs` (`QL_SENTINEL`): "the canonical way for MCP clients to express types JSON cannot represent natively"; the body is parsed as one SurrealQL *value*, never a query, capped by `SURREAL_MCP_PARAMS_MAX_QL_BYTES` (4 KiB).

Rules:
1. Skip a middle optional: pass `{"$ql": "NONE"}`.
2. Skip trailing optionals: omit them. A shorter `args` list is accepted.
3. Never pass JSON `null` for an optional. It arrives as SurrealQL `NULL` and `option<T>` rejects it loudly (`Expected none | array<float> but found NULL`). That error is intended.
4. The same sentinel carries record ids (`{"$ql": "document:abc"}`), datetimes (`{"$ql": "d'2026-09-09T00:00:00Z'"}`), durations, decimals and uuids.

Verified live 2026-09-09 07:22 EDT on the local store (3.2.x): `run fn::docs_search ["docstore ingest mapping", {"$ql": "NONE"}, {"$ql": "NONE"}, {"$ql": "NONE"}, "active", 3]` returned a hit; `run fn::docs_search ["docstore ingest mapping"]` returned a hit; `run type::is_none [{"$ql": "NONE"}]` returned `true` and `[null]` returned `false`.
