---
tags: [docstore, cocoindex, surrealdb, chunking]
---

> _Byline: Claude Code · Sonnet 5 · 2026-09-14_

# Chunk batching: bounding SurrealDB transaction size in the docs flow

## The problem

Run `ad5a5ced` (2026-09-14) failed on a 2-3 MB document (~1,000+ chunks,
2048-dim `nvidia/nemotron-3-embed-1b` embeddings each). `scripts/docstore/flow_docs.py`'s
`process_file`/`process_project_file` handed every chunk of a file to
`await coco.map(process_chunk, chunks, ...)`. `coco.map` runs its calls
concurrently but does not create a new CocoIndex processing component
("No processing components are created — this is pure concurrent execution
... within the current component", `cocoindex/_internal/api.py`), so every
chunk row, its embedding, and its `chunk_of` relation for the WHOLE file
were declared inside `process_file`'s own target-state batch.

CocoIndex applies a component's target-state changes atomically: "CocoIndex
applies all target state changes ... as a unit for each file ... each target
backend applies its batch atomically when supported (e.g., within a database
transaction)" (cocoindex docs, `programming_guide/core_concepts.md`). The
SurrealDB connector's tables additionally "share a single transaction sink"
(`connectors/surrealdb.md`), and its `_SharedRecordApplier._apply_actions`
(`cocoindex/connectors/surrealdb/_target.py`) joins every statement of one
such batch into a single `BEGIN TRANSACTION; ... COMMIT TRANSACTION;` query.

A large document therefore produced one multi-megabyte transaction, which
exceeded the SurrealDB Python SDK's 30 s RPC reply timeout. The socket
dropped, reconnected unauthenticated mid-transaction, and 296 later
statements in that run failed with "Anonymous access not allowed". Commit
`fc3a402` (branch `codex/docstore-operational-repair-20260913`) raised the
SDK's timeout to 600 s via `DOCSTORE_SURREAL_RPC_TIMEOUT_S` as an immediate
band-aid; it stays in place as defense in depth but does not bound the
transaction itself, so a large enough document could still exceed even that.

## The fix

`process_chunk_group`, a new CocoIndex component (`scripts/docstore/flow_docs.py`),
is mounted once per bounded GROUP of at most `DOCSTORE_CHUNK_BATCH_ROWS`
chunks (default `64`) via `coco.mount_each`, instead of one `coco.map` call
over every chunk in the file. Grouping is a pure function of chunk
*position* in the already-split chunk list (`scripts/docstore/chunk_batching.py`,
`group_for_batching`) — not of chunk content — so:

- the trailing group holds the remainder and may be smaller than the batch
  size (a document's chunk count is never guaranteed to divide evenly);
- appending chunks to the end of a document never reshuffles earlier,
  already-full groups;
- chunk ids (`chunk:<slug(doc_id + "_c" + ordinal)>`) and CDC identity are
  completely unaffected — only which transaction a chunk's write lands in
  changes.

CocoIndex's processing-component docs state the underlying tradeoff
directly: "Fine-grained (more, smaller components): Each component syncs its
target states as soon as it finishes, but target states owned by different
components do not sync together as a unit"
(`docs/programming_guide/processing_component/`), and confirm that mounting
a component inside an already-mounted, memoized component is a supported
pattern ("A memoized component may mount children", same page). Within a
group, chunks still run concurrently via `coco.map`, exactly as before —
only the size of what gets flushed together as one transaction shrank.

### Doc citations

- `programming_guide/core_concepts.md` — component-level atomicity ("as a
  unit for each file ... within a database transaction").
- `connectors/surrealdb.md` — "All tables within the same database share a
  single transaction sink."
- `programming_guide/processing_component/` — granularity tradeoffs
  (coarse- vs fine-grained components) and nested mounting support.
- `programming_guide/function/` — `version` semantics: "Edits to a versioned
  function take effect only when you bump the number", i.e. a same-version
  behavior change risks stale, now-incompatible memoized results being
  reused silently.
- `cocoindex/_internal/api.py` (source, cocoindex 1.0.21) — `coco.map`
  docstring: "No processing components are created."
- `cocoindex/connectors/surrealdb/_target.py` (source, cocoindex 1.0.21) —
  `_SharedRecordApplier._apply_actions` builds the `BEGIN...COMMIT` batch;
  `_RecordHandler.reconcile` fingerprints a declared row and skips a
  redundant UPSERT, but only after the row (and its embedding) is already
  built.

## Memo version bump: reprocessing cost

`process_file`'s memo `version` moved 6 → 7, and `process_project_file`'s
2 → 3, because each function's declared output SHAPE changed — chunk rows
now live one mount level deeper (under a `process_chunk_group` subpath that
did not exist before). Per the `version` semantics above, changing behavior
without bumping the version risks CocoIndex reusing a stale, incompatible
memoized result silently. The bump forces one full reprocess of every
mapped document on the next run: ~10 s per embed request, so hours of
wall-clock time across the ~1,235 tracked documents. This is a one-time cost
paid once, on the first run after this change lands.

## Re-embedding: not avoided, by design

This change bounds **transaction size**, not **embedding cost**. Read the
"CHUNK BATCHING" section of `flow_docs.py`'s module docstring for the full
argument, but in short: `process_chunk` computes the embedding to build the
`ChunkRow` *before* it ever calls `declare_record()`, so the NIM API call
happens unconditionally every time `process_chunk` runs — the connector's
own record-level fingerprint check (`_RecordHandler.reconcile`) only skips a
redundant SurrealDB write, after the embedding is already paid for. Only
`process_file`'s/`process_project_file`'s own whole-file `memo=True` avoids
re-embedding at all today, by skipping the file's body (and therefore every
`process_chunk` call inside it) when the file is unchanged. That was true
before this change and remains true after it: editing a file still re-embeds
every one of its own chunks, just spread across multiple bounded
transactions instead of one large one.

**Considered, not added:** `@coco.fn(memo=True)` on `process_chunk_group`,
which would let CocoIndex skip re-running (and re-embedding) a group whose
arguments are unchanged, independent of the file's own memo state. Left out
because this change was authored and reviewed without running the flow
against a live store (owner instruction, 2026-09-14), and whether a
`list[Chunk]` plus the file's `headings`/`ordinals` structures fingerprint
correctly and *stably* under cocoindex 1.0.21's generic (pickle-based)
memo-key path was never exercised live. A wrong memo key fails silently — a
stale embedding, or a wrongly-skipped group — which is a worse failure mode
than simply re-embedding. This is a follow-up to verify live, not something
to guess into a memoized code path.

## Verification performed

- `python3 -c "import ast; ast.parse(open('scripts/docstore/flow_docs.py', encoding='utf-8').read())"` — syntax OK.
- `pytest scripts/docstore/tests/test_chunk_batching.py -v` — 16 passed,
  covering group sizes (empty, exact multiple, single item, batch size 1,
  batch size larger than input, non-positive batch size raises), the
  trailing partial group at realistic scale (1,237 chunks / 64 per group),
  determinism, and that appending chunks never reshuffles earlier groups.
- The worker was **not** run and the VPS was **not** contacted, per the
  owner's live-testing constraint for this task — the transaction-size claim
  rests on reading `cocoindex` 1.0.21's own connector source
  (`_SharedRecordApplier._apply_actions`, `_RecordHandler.reconcile`) and its
  published docs, not on an observed run.

## Expected effect on transaction size

| | Before | After |
|---|---|---|
| Chunk rows per SurrealDB transaction | up to the entire file's chunk count (1,000+ observed) | at most `DOCSTORE_CHUNK_BATCH_ROWS` (default 64) |
| Document row | its own `declare_record` call, always outside any chunk group | unchanged |
| Chunks per group, concurrency | N/A (all chunks were one `coco.map` under `process_file`) | up to 64 per group, still concurrent via `coco.map` inside `process_chunk_group` |

---

## 2026-09-16 — measured live, and the two things that actually made a full run pass

> _Byline: Claude Code · Opus 5 · 2026-09-16_

The section above was written without contacting the VPS ("the worker was **not**
run"). It has now been run. The transaction-size reasoning held, but it was **not**
what was failing runs, and the batch size turned out to matter in the opposite
direction. Recorded here because this is the same subsystem.

### What was failing

Six consecutive full runs died at a constant **65–68 s** with
`ConnectionUnavailableError: WebSocket connection closed`, always on the largest
*changed* document (`consignatio/docs/URGENT-TODO.md`): runs `c7421349`,
`3d894018`, `bcb623bf`, `f7efca9c`, `9cce2454`, `d48aeaf7`.

Ruled out by measurement, not by argument:

| Suspected cause | Test | Result |
|---|---|---|
| ts.net proxy closing the socket | `SURREAL_DOCS_URL` → `ws://surreal-docs:8000` (same docker network, proxy bypassed) | same failure, 67 s |
| host memory pressure | restarted `surreal-docs` (10.79 GiB → 120 MiB; host free 0 → 11 GB, swap 7/7 → 4/7) | same failure, 66 s |
| transaction too large | `DOCSTORE_CHUNK_BATCH_ROWS` 64 → 12 | same failure, 68 s |
| worker ingest timeout | read the env | 14400 s, not it |
| document too large | a 2,543,430-char document is indexed fine | not it (the big ones are memoized, so they were never re-written) |

### Cause 1 — the SDK closes its own busy socket

The SurrealDB SDK opens its socket as
`websockets.connect(url, max_size=None, subprotocols=["cbor"])` and passes **no
ping settings**, so the `websockets` defaults apply. Read off a live connection
(websockets 17.0.1): `ping_interval=20`, `ping_timeout=20`. The library pings
every 20 s and **closes the connection itself** when the pong is later than 20 s —
which is what a server committing a chunk transaction does while NIM embeds at
~10 s per request. Client-side, which is why every external change above did
nothing.

Fix (`flow_docs._install_ws_keepalive`): keep pinging, set `ping_timeout=None`.
No retry, no change to write semantics. Env: `DOCSTORE_WS_PING_INTERVAL_S`,
`DOCSTORE_WS_PING_TIMEOUT_S`. Asserted by
`scripts/docstore/test_ws_keepalive.py` (20 → None, interval still 20).

Effect: the wall moved from 65–68 s to **162 s**, and WebSocket closes,
`NotAllowedError` and `ConnectionUnavailableError` all dropped to **zero**.

### Cause 2 — per-group components contend for ownership

With the socket fixed, the next failure was different and named itself:

```
Invalid Request: pre_commit gave up after 8 retries waiting for
concurrent ownership transfer at /"project"/"advocatio"/"…md"/@process_chunk_group/1
```

Four documents, all on `@process_chunk_group` — the component this document
introduced. `COCOINDEX_MAX_INFLIGHT_COMPONENTS` was **12** against a code default
of 4, and `DOCSTORE_CHUNK_BATCH_ROWS=12` multiplied the number of groups per
document, so more components contended for the same target rows.

Fix: `COCOINDEX_MAX_INFLIGHT_COMPONENTS` 12 → **4**, `DOCSTORE_CHUNK_BATCH_ROWS`
12 → **64** (this document's own default). Fewer components, fewer groups.

**Result: run `ef60fee3` finished in 53 s — `execution_finished`,
`cdc_verified: true`, expected 1118 / observed 1118, 0 missing, 0 hash mismatch,
0 unexpected.** The first verified full run since 2026-09-15.

### Note for whoever tunes this next

Raising `COCOINDEX_MAX_INFLIGHT_COMPONENTS` above 4 or lowering
`DOCSTORE_CHUNK_BATCH_ROWS` below 64 both increase ownership contention on
`process_chunk_group`. Bounding transaction size and bounding component count
pull in opposite directions; 4 × 64 is the combination that has an observed
clean run behind it.
