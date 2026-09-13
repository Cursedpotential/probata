# memory — function reference (PROVISIONAL)

Source: draft `080_memory.surql` / `085_memory_functions.surql` /
`087_memory_access.surql`, being finalized by another agent in parallel
with this build (2026-09-09). Everything in this file may still change —
treat it as the best available draft, not a locked contract. Target store:
`surreal-case` on the VPS, reached via the `memory` MCP server
(`${MEMORY_MCP_URL:-http://100.91.190.107:8471/mcp}`).

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

1. **Provisional.** The finalizing agent may rename fields or change the
   conflict-check thresholds before this ships — diff this file against
   the live schema before relying on exact field names in a script.
2. **K/EF are literal** (`<|5,40|>`, `<|20,40|>`) — same constraint as the
   docs store, never pass `$k` into the KNN operator itself.
3. **`evidence` is a plain string, never a live record link** — memory rows
   citing a docs-store id must re-verify with `fn::docs_get` on the docs
   server; a stale doc turns the memory claim into something the
   `reconcile` skill should flag, not something to trust blindly.
4. No `fn::` deletes anything, ever. `forget` retracts; `supersede_memory`
   supersedes.
