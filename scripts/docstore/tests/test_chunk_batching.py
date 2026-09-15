"""Unit tests for scripts/docstore/chunk_batching.py -- the pure grouping
helper behind flow_docs.py's CHUNK BATCHING fix (bounding SurrealDB
transaction size; see the module docstring in flow_docs.py).

Loaded by explicit file path (not `import chunk_batching`), matching the
sibling-module test convention already used in
plugins/docstore/control/tests/test_pipeline_source_registry.py, so this test
needs no sys.path manipulation and no cocoindex/env setup -- flow_docs.py
itself cannot be imported without NVIDIA_API_KEY and a live mapping CSV, but
chunk_batching.py has zero dependencies beyond the standard library.

Byline: Claude Code · Sonnet 5 · 2026-09-14
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

import pytest

MODULE_PATH = Path(__file__).parents[1] / "chunk_batching.py"
SPEC = importlib.util.spec_from_file_location("docstore_chunk_batching", MODULE_PATH)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)
group_for_batching = MODULE.group_for_batching
group_index_for_ordinal = MODULE.group_index_for_ordinal


# ---------------------------------------------------------------------------
# group_for_batching: group sizes
# ---------------------------------------------------------------------------


def test_empty_input_yields_zero_groups() -> None:
    assert group_for_batching([], 64) == []


def test_exact_multiple_yields_full_groups_only() -> None:
    items = list(range(128))
    groups = group_for_batching(items, 64)
    assert len(groups) == 2
    assert [len(g) for g in groups] == [64, 64]


def test_single_item_below_batch_size_yields_one_partial_group() -> None:
    groups = group_for_batching([1], 64)
    assert groups == [[1]]


def test_batch_size_one_yields_one_group_per_item() -> None:
    items = list(range(5))
    groups = group_for_batching(items, 1)
    assert groups == [[0], [1], [2], [3], [4]]


def test_batch_size_larger_than_input_yields_one_group() -> None:
    items = list(range(10))
    groups = group_for_batching(items, 64)
    assert groups == [items]


@pytest.mark.parametrize("batch_rows", [0, -1, -64])
def test_non_positive_batch_rows_raises(batch_rows: int) -> None:
    with pytest.raises(ValueError):
        group_for_batching([1, 2, 3], batch_rows)


# ---------------------------------------------------------------------------
# group_for_batching: last partial group (the case a large document actually
# hits -- e.g. the ~1,000+ chunk document from run ad5a5ced never divides
# evenly by 64)
# ---------------------------------------------------------------------------


def test_last_partial_group_holds_the_remainder() -> None:
    items = list(range(150))  # 150 = 2 * 64 + 22
    groups = group_for_batching(items, 64)
    assert [len(g) for g in groups] == [64, 64, 22]
    # every item covered exactly once, order preserved
    assert [x for g in groups for x in g] == items


def test_large_document_like_run_ad5a5ced_bounds_every_group() -> None:
    # run ad5a5ced: "a 2-3 MB document (~1,000+ chunks)" -- pick a count that
    # does not divide evenly by the default batch size to exercise the
    # trailing partial group under realistic scale.
    items = list(range(1237))
    batch_rows = 64
    groups = group_for_batching(items, batch_rows)
    assert all(len(g) <= batch_rows for g in groups)
    assert sum(len(g) for g in groups) == len(items)
    # bounded: no single transaction ever carries more than batch_rows rows
    assert max(len(g) for g in groups) <= batch_rows


# ---------------------------------------------------------------------------
# group_for_batching: stable ids / stable grouping
#
# CocoIndex's mount_each keys each mounted child component by the group's
# position (its index in `groups`). For that key to be stable across runs
# with unchanged content, a given item's group index must be a pure function
# of its POSITION, not of grouping performed some other way (e.g. by content
# hash bucketing, which would reshuffle on unrelated edits).
# ---------------------------------------------------------------------------


def test_grouping_is_deterministic_across_repeated_calls() -> None:
    items = list(range(300))
    first = group_for_batching(items, 64)
    second = group_for_batching(items, 64)
    assert first == second


def test_item_at_a_given_position_always_lands_in_the_same_group_index() -> None:
    items = list(range(300))
    batch_rows = 64
    groups = group_for_batching(items, batch_rows)
    for position, value in enumerate(items):
        expected_group_index = position // batch_rows
        assert groups[expected_group_index][position % batch_rows] == value


def test_group_index_for_ordinal_matches_group_for_batching_placement() -> None:
    items = list(range(300))
    batch_rows = 64
    groups = group_for_batching(items, batch_rows)
    for ordinal, value in enumerate(items):
        group_index = group_index_for_ordinal(ordinal, batch_rows)
        assert groups[group_index][ordinal % batch_rows] == value


def test_group_index_for_ordinal_rejects_non_positive_batch_rows() -> None:
    with pytest.raises(ValueError):
        group_index_for_ordinal(0, 0)


def test_group_index_for_ordinal_rejects_negative_ordinal() -> None:
    with pytest.raises(ValueError):
        group_index_for_ordinal(-1, 64)


def test_appending_chunks_does_not_change_earlier_groups() -> None:
    # A document growing (more chunks appended at the end) must not reshuffle
    # groups that already exist -- otherwise every group's mount_each key
    # would be considered "changed" on every edit, defeating the bound.
    batch_rows = 64
    base = list(range(140))  # 2 full groups + 1 partial (12 items)
    grown = list(range(140)) + list(range(140, 200))  # 60 more appended
    groups_before = group_for_batching(base, batch_rows)
    groups_after = group_for_batching(grown, batch_rows)
    # every fully-formed prior group is byte-identical after the append
    for i in range(len(groups_before) - 1):
        assert groups_before[i] == groups_after[i]
