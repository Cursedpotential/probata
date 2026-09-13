---
name: memory
description: Write and recall durable agent memory (corrections, preferences, observations, handoffs) in the shared SurrealDB memory store on the VPS (surreal-case), scoped by path probata/<domain>/<agent>. Use when the user corrects you, states a preference, when you discover a non-obvious fact, or when you need to know what a prior session already established before asking again.
allowed-tools: mcp__plugin_propria_docstore_memory__run mcp__plugin_propria_docstore_memory__list Read
---

# Memory

**PROVISIONAL:** the memory schema and its `fn::` signatures are still
being finalized by another agent as of 2026-09-09. Everything below is
drawn from the draft schema files and may change before it ships — re-read
`references/functions.md` each session rather than trusting recall of it.

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
run: { function: "fn::recall", args: [$query, $vec_or_none, $scope, $k] }
```

Matches `scope` exactly OR any scope that is a `/`-descendant of it — a
broader scope pulls in more, not less.

## Supersede / retract

```
run: { function: "fn::supersede_memory", args: [$old_id, $new_payload] }
run: { function: "fn::forget", args: [$id, $reason] }
```

Never overwrite, never delete — `forget` sets `status: "retracted"` with a
reason and keeps the row queryable.

## Conflict handling

Two active claims that disagree: surface both with dates, ask the user,
then write the resolution as a new claim and `fn::supersede_memory` the
loser. Never pick silently.

See `references/functions.md` for exact (provisional) signatures, scope
rules, and `fn::reflect`/`fn::memory_stats`.
