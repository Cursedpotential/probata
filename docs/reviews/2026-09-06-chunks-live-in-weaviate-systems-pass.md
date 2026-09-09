# Chunks live in Weaviate — systems pass and rulings

> _Byline: Claude Code · Fable 5.1 · 2026-09-06._
> STATUS: RULED 12:2x (owner answered the four questions). Amends D-149 items 7–8.
> Skills applied: thinking-systems, thinking-socratic, thinking-five-whys-plus.

## System map (as built)

```
chunker Activity ──▶ PG working.content_chunk (text + digest)   ← copy A of the words
                 └─▶ PG working.content_chunk_message (ids, sql/0072)
PG row ──outbox──▶ Weaviate feed ──▶ Weaviate chunk object (text + vector)  ← copy B
search hit ──▶ chunk id ──▶ bridge ──▶ PG normalized_record ──▶ messages returned
```

## Five whys (root of the confusion)

1. The question named the PG chunk table, which also holds text → sounded like "chunks leave Weaviate."
2. PG holds text because `content_chunk` (sql/0047) predates the bridge (sql/0072) and the 2026-09-03 "pull atomic messages" rule.
3. A PG row must exist: PG is canon; the outbox needs a row; the bridge needs a parent.
4. The text copy has no remaining reader that needs it: normalized text is immutable (D-136), so the copy can never differ.
5. Root: schema predates the ruling. Ruling unchanged; table not caught up.

## Feedback loops and delays

- Rebuild loop (balancing): embedder change → drop class → re-embed from PG id lists. Requires ids in PG; without them the loop degrades to re-chunking.
- Overlap loop: overlapping windows → duplicate hits → dedupe on centre message id at retrieval.
- Delay: outbox lag. A chunk exists in PG before it is searchable; preview must not promise search on fresh material.

## Rulings (owner, 2026-09-06)

| # | Question | Ruling |
|---|---|---|
| 1 | What lives in Weaviate | the searchable object: vector + member message ids + PG coordinate. No chunk text anywhere. |
| 2 | What a hit returns | messages from PG, never chunk text; neighbour expansion on the message table. |
| 3 | Rebuild on embedder change | from the id lists in PG; same chunks re-embedded; boundaries survive. |
| 4 | Write path | PG row + outbox → Weaviate (ADR-0052 / D-054). Chunker never writes Weaviate directly. |

## Consequences (feed the change map)

- `working.content_chunk`: drop `content` + digest CHECK; keep id, generation, index, sha of the id list if useful; `working.content_chunk_text` view over normalized rows for the remaining readers.
- Weaviate: `EvidenceChunkV2` with no text property; properties = PG coordinate, member ids, generation, validity window.
- Feed: `server/evidence/vector_projection.py` assembles text from normalized rows at embed time only.
- Retrieval unit: returns messages; caller passes K or time-gap for expansion.
