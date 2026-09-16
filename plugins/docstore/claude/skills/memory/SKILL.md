---
name: memory
description: Write and recall durable agent memory (corrections, preferences, observations, handoffs) in the shared SurrealDB memory store on the VPS (surreal-case), scoped by path probata/<domain>/<agent>. Use when the user corrects you, states a preference, when you discover a non-obvious fact, or when you need to know what a prior session already established before asking again.
allowed-tools: mcp__plugin_propria_docstore_memory__run mcp__plugin_propria_docstore_memory__list Read
---

# Memory

Deployed and verified live end-to-end (remember/recall/supersede_memory/
forget/reflect/memory_stats) on 2026-09-16 to the `surreal-case` VPS
instance, namespace **`probata_memory`**, database **`memory`** — a
different ns/db than the `fct`/`main` namespaces already living on that
same SurrealDB instance for other apps. The `memory` MCP server entry in
`.mcp.json` must carry `surreal-ns: probata_memory` and `surreal-db:
memory` headers (added 2026-09-16 — their absence was the root cause of
every prior "Specify a namespace to use" error); if a session predates
that fix, restart it. Re-read `references/functions.md` each session
rather than trusting recall of exact field names.

## Write

```
run: { function: "fn::remember",
       args: [{ kind: $kind, claim: $claim, detail: $detail_or_none,
                 scope: $scope, agent: $agent, confidence: $confidence,
                 evidence: $evidence_or_none }] }
```

Refuses silently-near-duplicate claims (BM25 + vector conflict check within
the same scope) unless the payload also carries `force: true` or
`supersede: <old_id>`. A refusal returning `conflicts` is not an error —
read them before retrying.

## Recall

```
run: { function: "fn::recall", args: [$query, {"$ql": "NONE"}, $scope, $k] }
```

Matches `scope` exactly OR any scope that is a `/`-descendant of it — a
broader scope pulls in more, not less. `$vec` is a typed `option<array<float>>`
argument: passing bare JSON `null` fails to coerce ("Expected `none |
array<float>` but found `NULL`", reproduced live 2026-09-16) — pass
`{"$ql": "NONE"}` when there is no embedding, the same sentinel pattern
used for record ids below. `fn::reflect`'s `$since` is a typed `datetime`
and has the identical gotcha: pass `{"$ql": "d'2026-01-01T00:00:00Z'"}`,
never a bare ISO string.

## Supersede / retract

```
run: { function: "fn::supersede_memory", args: [{"$ql": "memory:<old id>"}, $new_payload] }
run: { function: "fn::forget", args: [{"$ql": "memory:<id>"}, $reason] }
```

Record ids over MCP `run` always go through the `$ql` sentinel
(`{"$ql": "memory:abc"}`), never a bare `memory:abc` string — a bare string
fails to coerce to the record type (reproduced live 2026-09-16, same bug as
`fn::docs_get`).

Never overwrite, never delete — `forget` sets `status: "retracted"` with a
reason and keeps the row queryable.

## Conflict handling

Two active claims that disagree: surface both with dates, ask the user,
then write the resolution as a new claim and `fn::supersede_memory` the
loser. Never pick silently.

See `references/functions.md` for exact (provisional) signatures, scope
rules, and `fn::reflect`/`fn::memory_stats`.
