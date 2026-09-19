"""Read-only Docstore scope change set: a candidate registry vs the stored projection.

Byline: Claude Code · Opus 5 · 2026-09-19 (owner order: compute the exact change/retraction set
before any metered embedding work). Runs inside the docstore-worker container so it uses the
worker's own snapshot_sources()/_is_pipeline_row() and hash rules. Writes nothing to the store.

Usage (in the worker container):
  python scope_changeset.py <candidate-registry.json> [--monorepo-root /exchange/sources]
"""
from __future__ import annotations

import asyncio
import collections
import json
import os
import sys

sys.path.insert(0, "/app/scripts/docstore")

# One fixed scratch path inside the container, overwritten on every run.
SCRATCH = "/tmp/docstore-scope-candidate-registry.json"


def _top(paths, depth: int):
    if depth == 1:
        return collections.Counter(p.split("/")[0] for p in paths)
    return collections.Counter("/".join(p.split("/")[:depth]) for p in paths).most_common(40)


def main() -> int:
    registry = sys.argv[1]
    root = sys.argv[sys.argv.index("--monorepo-root") + 1] if "--monorepo-root" in sys.argv else "/exchange/sources"
    with open(registry, encoding="utf-8") as handle:
        payload = json.load(handle)
    payload["monorepo_root"] = root
    with open(SCRATCH, "w", encoding="utf-8") as handle:
        json.dump(payload, handle)
    os.environ["DOCSTORE_PROJECT_REGISTRY"] = SCRATCH
    import cdc_verify as cv
    import sq

    expected, _ = cv.snapshot_sources()
    exp = {d.source_path: d.content_hash for d in expected}

    async def rows():
        db = await sq.connect("docs", "probata", "docs")
        try:
            r = await db.query("SELECT source_path, project, status, content_hash, doc_type FROM document;")
        finally:
            await db.close()
        while isinstance(r, list) and len(r) == 1 and isinstance(r[0], list):
            r = r[0]
        return [x for x in r if isinstance(x, dict)]

    stored = asyncio.run(rows())
    pipe = {x["source_path"]: x for x in stored if cv._is_pipeline_row(x)}
    by_hash = {x.get("content_hash"): x.get("source_path") for x in stored}
    new = sorted(set(exp) - set(pipe))
    out = sorted(set(pipe) - set(exp))
    changed = sorted(p for p in set(exp) & set(pipe) if exp[p] != pipe[p].get("content_hash"))
    counts = collections.Counter(exp.values())
    print(json.dumps({
        "expected": len(exp), "expected_by_project": _top(exp, 1),
        "stored_total": len(stored), "stored_pipeline": len(pipe),
        "stored_non_pipeline": len(stored) - len(pipe),
        "new": len(new), "new_by_project": _top(new, 1), "new_list": new,
        "changed": len(changed), "changed_list": changed,
        "unchanged": len(set(exp) & set(pipe)) - len(changed),
        "out_of_scope": len(out), "out_by_project": _top(out, 1), "out_by_top2": _top(out, 2),
        "duplicate_hash_within_expected": sorted(p for p in exp if counts[exp[p]] > 1),
        "new_colliding_with_stored": [[p, by_hash[exp[p]]] for p in new if exp[p] in by_hash],
        "out_list": out,
        "store_writes": 0,
    }, default=str))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
