"""graph_build - derive the document graph in the cloud docstore from document bodies + the mapping CSV.

Byline: Claude Code - Opus 5 - 2026-09-10

Owner order 2026-09-10: "set up a graph so we can see how things are interconnected - that is part of
the point of having surreal - and use Surreal's viewer to view it."

Edges (all DERIVED and fully rebuildable; no LLM, no guessing):
  links_to  document -> document   markdown link [..](path.md) resolved against the linking doc's folder
  cites     document -> document   kind='adr':      "ADR-NNNN" -> docs/adr/NNNN-*.md
                                    kind='decision': "D-NNN"    -> docs/DECISION_LOG.md, ids[] = the D-numbers
  supersedes document -> document  from mapping CSV supersedes_path: successor -> superseded doc (reason='mapping')

Idempotent: each run deletes the derived edges it owns (links_to, cites, supersedes WHERE kind='mapping')
and re-inserts them (supersedes rows are matched on reason='mapping'; the kind clause only clears rows
written by the first 2026-09-10 build), so the graph always equals what the current bodies say.
Schema: scripts/docstore/schema/045_doc_graph.surql (applied by this script before writing).

Usage:  python scripts/docstore/graph_build.py            # rebuild + print counts
        python scripts/docstore/graph_build.py --dry-run  # counts only, no writes
"""
from __future__ import annotations

import argparse
import asyncio
import csv
import pathlib
import posixpath
import re
import sys
import time

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import sq  # noqa: E402

SCHEMA = HERE / "schema" / "045_doc_graph.surql"
MAPPING = HERE / "mapping" / "docs-ingest-mapping.csv"
LINK_RE = re.compile(r"\]\(\s*<?([^)<>\s#]+?\.md)>?(?:#[^)]*)?\s*\)")
ADR_RE = re.compile(r"\bADR-(\d{4})\b")
DEC_RE = re.compile(r"\bD-(\d{2,3})\b")
DECISION_LOG = "docs/DECISION_LOG.md"
BATCH = 500


def _rows(r):
    while isinstance(r, list) and len(r) == 1 and isinstance(r[0], list):
        r = r[0]
    return r if isinstance(r, list) else ([r] if r else [])


def resolve_link(source_path: str, target: str) -> str:
    target = target.strip().replace(chr(92), "/")
    if target.startswith(("http://", "https://", "mailto:")):
        return ""
    if target.startswith("/"):
        return posixpath.normpath(target.lstrip("/"))
    if target.startswith("docs/"):
        return posixpath.normpath(target)
    return posixpath.normpath(posixpath.join(posixpath.dirname(source_path), target))


def build_edges(docs: list[dict], csv_rows: list[dict]) -> dict[str, list[dict]]:
    by_path = {d["source_path"]: d["id"] for d in docs}
    adr_by_num = {}
    for path, rid in by_path.items():
        m = re.match(r"docs/adr/(\d{4})-", path)
        if m:
            adr_by_num.setdefault(m.group(1), rid)
    dec_log = by_path.get(DECISION_LOG)

    links, cites, supers = {}, {}, {}
    for d in docs:
        src, body = d["id"], d.get("body") or ""
        for target in LINK_RE.findall(body):
            dst = by_path.get(resolve_link(d["source_path"], target))
            if dst is not None and str(dst) != str(src):
                links.setdefault((str(src), str(dst)), {"in": src, "out": dst, "kind": "md_link"})
        for num in set(ADR_RE.findall(body)):
            dst = adr_by_num.get(num)
            if dst is not None and str(dst) != str(src):
                cites.setdefault((str(src), str(dst), "adr"), {"in": src, "out": dst, "kind": "adr", "ids": []})["ids"].append(f"ADR-{num}")
        if dec_log is not None and str(dec_log) != str(src):
            nums = sorted(set(DEC_RE.findall(body)), key=int)
            if nums:
                cites[(str(src), str(dec_log), "decision")] = {"in": src, "out": dec_log, "kind": "decision",
                                                               "ids": [f"D-{n}" for n in nums]}
    for r in csv_rows:
        old = by_path.get(r["source_path"].replace(chr(92), "/"))
        new = by_path.get((r.get("supersedes_path") or "").strip().replace(chr(92), "/"))
        if old is not None and new is not None and str(old) != str(new):
            supers[(str(new), str(old))] = {"in": new, "out": old, "reason": "mapping"}
    return {"links_to": list(links.values()), "cites": list(cites.values()), "supersedes": list(supers.values())}


async def main() -> int:
    ap = argparse.ArgumentParser(description="Rebuild the derived document graph.")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    t0 = time.perf_counter()
    db = await sq.connect("docs", "probata", "docs")
    docs = _rows(await db.query("SELECT id, source_path, body FROM document;"))
    csv_rows = list(csv.DictReader(open(MAPPING, encoding="utf-8", newline="")))
    edges = build_edges(docs, csv_rows)
    print(f"documents {len(docs)} | links_to {len(edges['links_to'])} | cites {len(edges['cites'])} "
          f"(adr {sum(1 for e in edges['cites'] if e['kind'] == 'adr')}, decision {sum(1 for e in edges['cites'] if e['kind'] == 'decision')}) "
          f"| supersedes(mapping) {len(edges['supersedes'])}")
    if a.dry_run:
        await db.close()
        return 0

    await db.query(SCHEMA.read_text(encoding="utf-8"))
    await db.query("DELETE links_to; DELETE cites; DELETE supersedes WHERE reason = 'mapping' OR kind = 'mapping';")
    for table, rows in edges.items():
        for i in range(0, len(rows), BATCH):
            await db.query(f"INSERT RELATION INTO {table} $rows;", {"rows": rows[i:i + BATCH]})
    counts = {}
    for table in ("links_to", "cites", "supersedes"):
        r = _rows(await db.query(f"SELECT count() AS n FROM {table} GROUP ALL;"))
        counts[table] = r[0].get("n", 0) if r and isinstance(r[0], dict) else 0
    await db.close()
    print(f"written: {counts} in {time.perf_counter() - t0:.1f}s")
    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
