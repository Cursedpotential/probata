# memory — function reference

Source: `080_memory.surql` / `085_memory_functions.surql` /
`087_memory_access.surql` (canonical copy: `probata/scripts/docstore/
memory-schema-fallback/`, dated snapshot applied 2026-09-16 under
`probata/scripts/docstore/schema/applied-2026-09-16-memory/`). Deployed
and round-trip verified live 2026-09-16. Target store: `surreal-case` on
the VPS, reached via the `memory` MCP server
(`${MEMORY_MCP_URL:-http://100.91.190.107:8471/mcp}`), **namespace
`probata_memory`, database `memory`** — the `.mcp.json` entry must send
`surreal-ns`/`surreal-db` headers with those values (added 2026-09-16;
their absence produced "Specify a namespace to use" on every call).

## fn::remember

```
fn::remember($payload: object) -> object
  -- refused: { written: NONE, conflicts: array<object>, note: string }
  -- ok:      { written: record<memory>, conflicts: [] }
```

`$payload` fields: `kind` (ASSERT `["correction","preference","observation",
"handoff","fact","constraint","decision"]`), `claim` (10–600 chars,
ASSERT'd), `detail?`, `evidence?` (a plain string — doc id + source path,
**never** a live cross-store record link), `scope`, `agent`, `confidence?`
(default 0.6), `observed_at?`, `embedding?`, `force?`, `supersede?`,
`reason?`.

Runs a BM25 (`claim @@ $claim`) + vector (`<|5,40|>` literal KNN, only if
`embedding` is supplied) conflict check against **active** claims in the
same `scope` before writing. If conflicts exist and neither `force:true`
nor `supersede:<id>` is set, the write is refused (soft return, not a
throw) with the conflicting rows attached.

## fn::supersede_memory

```
fn::supersede_memory($old: record<memory>, $new_payload: object) -> object
  -- { new: record<memory>, old: record<memory> }
```

Creates the new row, `RELATE new->supersedes->old`, flips `old.status` to
`"superseded"`.

## fn::forget

```
fn::forget($id: record<memory>, $reason: string) -> object   -- the updated memory row
```

Sets `status: "retracted"`. Writes **two** `decision_log` rows for one call
by design: the `memory_status_changed` EVENT fires (reason-less audit row)
and `fn::forget` itself writes a second, reason-bearing row — this is
intentional redundancy in the append-only audit trail, not a bug.

## fn::recall

```
fn::recall($query: string, $vec: option<array<float>>, $scope: string, $k: int) -> array<object>
  -- {id, claim, kind, confidence, observed_at, evidence, status, rrf_score}
```

RRF fusion (k=60) over BM25 (`claim @1@ $query`, 20 candidates) and KNN
(`<|20,40|>` literal, only if `$vec` given) — matches rows whose `scope`
equals `$scope` OR starts with `$scope + "/"` (prefix-descendant match).
Truncated to `$k` after fusion, `status = "active"` only.

## fn::reflect

```
fn::reflect($scope: string, $since: datetime) -> array<object>   -- the episode rows selected
```

Selects unreflected `episode` rows for `$scope` (+ descendants) since
`$since` and marks them `reflected = true`. Does **not** write memory
itself — condensing episodes into `fn::remember` calls is the caller's job.

## fn::memory_stats

```
fn::memory_stats($scope: string) -> object
  -- { scope, total, active, superseded, retracted, by_kind: array<{kind,n}>, episodes_pending_reflection }
```

Point-in-time counts for `$scope` and its descendants.

## Scope

Every `memory`/`episode` row's `scope` must match `^probata(/[a-z0-9_-]+)*$`
— path form `probata/<domain>/<agent>`, e.g. `probata/docstore/librarian`.
A `principal` row (agent identity) carries a `scope_prefix` grant; the
prefix itself is enforced inside the `fn::` functions' `WHERE` clauses, not
by `DEFINE ACCESS` alone.

## Gotchas

1. **Typed optional/datetime args need the `$ql` sentinel, same as record
   ids.** `fn::recall`'s `$vec` (`option<array<float>>`) and `fn::reflect`'s
   `$since` (`datetime`) both fail to coerce from bare JSON (`null`, a plain
   ISO string) over MCP `run` — reproduced live 2026-09-16. Pass
   `{"$ql": "NONE"}` for no vector and `{"$ql": "d'2026-01-01T00:00:00Z'"}`
   for a datetime.
2. **K/EF are literal** (`<|5,40|>`, `<|20,40|>`) — same constraint as the
   docs store, never pass `$k` into the KNN operator itself.
3. **`evidence` is a plain string, never a live record link** — memory rows
   citing a docs-store id must re-verify with `fn::docs_get` on the docs
   server; a stale doc turns the memory claim into something the
   `reconcile` skill should flag, not something to trust blindly.
4. No `fn::` deletes anything, ever. `forget` retracts; `supersede_memory`
   supersedes. (A hard `DELETE` is still possible via the generic `query`
   tool for genuinely disposable test data — that is how the 2026-09-16
   verification pass purged its QA rows — but no `fn::` function does this,
   and normal agent use should never reach for it.)
5. **The MCP session must select `probata_memory`/`memory`.** The server
   also hosts unrelated `fct`/`main` namespaces for other apps on the same
   VPS instance; a client without the `surreal-ns`/`surreal-db` headers (or
   without an explicit `use` first) gets "Specify a namespace to use", not
   an empty result — it is not silently reading the right store.
