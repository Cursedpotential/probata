"""
chunk_batching.py — pure helper for bounding SurrealDB transaction size in
scripts/docstore/flow_docs.py.

WHY THIS IS A SEPARATE MODULE. flow_docs.py has import-time side effects
(reads DOCSTORE_MAPPING_CSV, requires NVIDIA_API_KEY, starts the RSS-guard
thread, connects an environment) that make it unsafe/impossible to import in
a plain unit test without standing up the whole app. The grouping logic
itself has none of that: it is a pure function over a list length and a
batch size. Kept here so scripts/docstore/tests/test_chunk_batching.py can
exercise it directly, with no cocoindex/env dependency at all.

THE PROBLEM THIS SOLVES. flow_docs.py's process_file/process_project_file
used to hand ALL of a file's chunks to `await coco.map(process_chunk, chunks,
...)`. `coco.map` runs concurrently but declares no new processing
component (cocoindex/_internal/api.py: "No processing components are
created -- this is pure concurrent execution ... within the current
component"), so every chunk row, embedding and chunk_of relation for the
WHOLE file landed in the one target-state batch belonging to process_file
itself. CocoIndex's own docs (core_concepts.md) state target-state changes
are applied "as a unit for each file ... atomically ... within a database
transaction", and the SurrealDB connector (connectors/surrealdb.md) says
"All tables within the same database share a single transaction sink" --
cocoindex/connectors/surrealdb/_target.py's `_SharedRecordApplier._apply_actions`
joins every statement of one such batch into one `BEGIN ... COMMIT` query.
A 2-3 MB document (1,000+ chunks x 2048-float embeddings) therefore produced
ONE multi-megabyte transaction, which exceeded the SurrealDB Python SDK's
30 s RPC reply timeout (run ad5a5ced, 2026-09-14).

THE FIX. flow_docs.py now mounts one CHILD COMPONENT per bounded GROUP of
chunks (`coco.mount_each(process_chunk_group, ...)`) instead of a single
`coco.map` over every chunk. cocoindex's processing_component docs state the
granularity tradeoff explicitly: "Fine-grained (more, smaller components):
Each component syncs its target states as soon as it finishes, but target
states owned by different components do not sync together as a unit" -- and
confirm nesting is supported ("A memoized component may mount children").
So each group's chunk rows + embeddings + chunk_of relations become their
own target-state batch, hence their own transaction, bounding transaction
size to at most DOCSTORE_CHUNK_BATCH_ROWS chunk rows regardless of how large
the source document is. The document row itself is unaffected -- it is
still declared once, directly in process_file/process_project_file, outside
any group.

Byline: Claude Code · Sonnet 5 · 2026-09-14.
"""

from __future__ import annotations

from typing import Sequence, TypeVar

T = TypeVar("T")


def group_for_batching(items: Sequence[T], batch_rows: int) -> list[list[T]]:
    """Split `items` into consecutive, order-preserving groups of at most
    `batch_rows` items each.

    Group `i` always holds `items[i*batch_rows : (i+1)*batch_rows]` -- a pure
    function of each item's POSITION in `items`, not of its content. That
    matters for stability: as long as the chunker produces the same ordinal
    for a given chunk across runs (it does; ordinals come from `char_offset`
    order, deterministic for the same text), a given ordinal always lands in
    the same group index, so `coco.mount_each`'s per-item stable key
    (the group index) does not thrash on an unrelated edit elsewhere in the
    same run.

    The trailing group holds the remainder and may be smaller than
    `batch_rows` (including a single item) -- this is expected, not an
    error: a document's chunk count is never guaranteed to be a multiple of
    the batch size.

    Args:
        items: the ordered sequence to split (e.g. a file's chunk list).
        batch_rows: maximum items per group. Must be a positive integer.

    Returns:
        A list of groups (lists), in the original order, covering every
        input item exactly once. Empty `items` returns `[]` (zero groups,
        not one empty group) -- mount_each over zero items mounts nothing.

    Raises:
        ValueError: if `batch_rows` is not a positive integer.
    """
    if batch_rows <= 0:
        raise ValueError(f"batch_rows must be positive, got {batch_rows}")
    return [list(items[i : i + batch_rows]) for i in range(0, len(items), batch_rows)]


def group_index_for_ordinal(ordinal: int, batch_rows: int) -> int:
    """The group index `group_for_batching` places ordinal `ordinal` into,
    for the same `batch_rows`. Exposed so a caller (or a test) can check
    group/ordinal consistency without re-deriving the arithmetic.
    """
    if batch_rows <= 0:
        raise ValueError(f"batch_rows must be positive, got {batch_rows}")
    if ordinal < 0:
        raise ValueError(f"ordinal must be non-negative, got {ordinal}")
    return ordinal // batch_rows
