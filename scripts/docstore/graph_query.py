"""graph_query - one document's neighborhood in the derived graph, as a compact table or Mermaid.

Byline: Claude Code - Opus 5 - 2026-09-10

Owner question 2026-09-10: "should the graph be exported to mermaid so you can read it, or can you read
it from the tables?" Agents read the edge tables directly (this tool); Mermaid is generated on demand
for ONE neighborhood - a whole-graph diagram of ~500 nodes / ~1,300 edges is unreadable. Edges come
from graph_build.py: links_to, cites (adr|decision), supersedes (reason=mapping).

Usage:
  python scripts/docstore/graph_query.py ADR-0056
  python scripts/docstore/graph_query.py docs/NAMING.md --mermaid
  python scripts/docstore/graph_query.py document:docs_decision_log_md --limit 10
"""
from __future__ import annotations

import argparse
import asyncio
import csv
import io
import pathlib
import re
import sys
import types

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import sq  # noqa: E402

EDGES = (("links_to", "kind"), ("cites", "kind"), ("supersedes", "reason"))


def _rows(r):
    while isinstance(r, list) and len(r) == 1 and isinstance(r[0], list):
        r = r[0]
    return r if isinstance(r, list) else ([r] if r else [])


async def neighborhood(ref: str, limit: int = 25) -> tuple[dict | None, list[dict], dict]:
    """Resolve ref (ADR-NNNN, record id, or path fragment) and return (doc, edges, totals)."""
    db = await sq.connect("docs", "probata", "docs")
    try:
        m = re.fullmatch(r"(?i)ADR-(\d{4})", ref.strip())
        if ref.startswith("document:"):
            where, params = "id = type::record($r)", {"r": ref}
        elif m:
            where, params = "string::starts_with(source_path, $r)", {"r": f"docs/adr/{m.group(1)}-"}
        else:
            where, params = "string::contains(source_path, $r)", {"r": ref}
        docs = _rows(await db.query(f"SELECT id, source_path, title, doc_type, status FROM document WHERE {where} LIMIT 1;", params))
        if not docs:
            return None, [], {}
        doc = docs[0]
        out, totals = [], {}
        for table, detail in EDGES:
            for direction, me, other in (("out", "in", "out"), ("in", "out", "in")):
                n = _rows(await db.query(f"SELECT count() AS n FROM {table} WHERE {me} = $id GROUP ALL;", {"id": doc["id"]}))
                totals[f"{table}_{direction}"] = n[0]["n"] if n and isinstance(n[0], dict) else 0
                for e in _rows(await db.query(
                        f"SELECT {other}.source_path AS path, {other}.title AS title, {detail} AS detail"
                        + (", ids" if table == "cites" else "")
                        + f" FROM {table} WHERE {me} = $id LIMIT $lim;", {"id": doc["id"], "lim": limit})):
                    out.append({"edge": table, "dir": direction, "detail": e.get("detail"),
                                "ids": e.get("ids") or [], "path": e.get("path"), "title": e.get("title")})
        return doc, out, totals
    finally:
        await db.close()


async def structured_neighborhood(ref: str, relations: tuple[str, ...] = ("links_to", "cites", "supersedes"),
                                  direction: str = "both", limit: int = 25,
                                  source_prefix: str = "", observed_from: str = "",
                                  observed_to: str = "") -> tuple[dict | None, list[dict], dict]:
    """Bounded typed graph query. All identifiers come from fixed allowlists."""
    allowed = {table: detail for table, detail in EDGES}
    if not relations or any(table not in allowed for table in relations):
        raise ValueError("Unsupported relation type")
    if direction not in {"in", "out", "both"} or not 1 <= limit <= 200:
        raise ValueError("Unsupported graph direction or limit")
    if source_prefix and (len(source_prefix) > 256 or ".." in pathlib.PurePosixPath(source_prefix).parts):
        raise ValueError("Unsafe source prefix")
    db = await sq.connect("docs", "probata", "docs")
    try:
        m = re.fullmatch(r"(?i)ADR-(\d{4})", ref.strip())
        if ref.startswith("document:"):
            where, params = "id = type::record($r)", {"r": ref}
        elif m:
            where, params = "string::starts_with(source_path, $r)", {"r": f"docs/adr/{m.group(1)}-"}
        else:
            where, params = "string::contains(source_path, $r)", {"r": ref}
        docs = _rows(await db.query(
            f"SELECT id, source_path, title, doc_type, status, observed_at FROM document WHERE {where} LIMIT 1;",
            params))
        if not docs:
            return None, [], {}
        doc, rows, totals = docs[0], [], {}
        directions = (("out", "in", "out"), ("in", "out", "in")) if direction == "both" else (
            ("out", "in", "out"),) if direction == "out" else (("in", "out", "in"),)
        for table in relations:
            detail = allowed[table]
            for label, me, other in directions:
                filters = [f"{me} = $id"]
                bound = {"id": doc["id"], "lim": limit}
                if source_prefix:
                    filters.append(f"string::starts_with({other}.source_path, $prefix)")
                    bound["prefix"] = source_prefix
                if observed_from:
                    filters.append(f"{other}.observed_at >= <datetime>$from")
                    bound["from"] = observed_from
                if observed_to:
                    filters.append(f"{other}.observed_at <= <datetime>$to")
                    bound["to"] = observed_to
                predicate = " AND ".join(filters)
                count = _rows(await db.query(
                    f"SELECT count() AS n FROM {table} WHERE {predicate} GROUP ALL;", bound))
                totals[f"{table}_{label}"] = count[0]["n"] if count and isinstance(count[0], dict) else 0
                selected = f"{other}.source_path AS path, {other}.title AS title, {other}.observed_at AS observed_at, {detail} AS detail"
                if table == "cites":
                    selected += ", ids"
                for edge in _rows(await db.query(
                    f"SELECT {selected} FROM {table} WHERE {predicate} LIMIT $lim;", bound)):
                    rows.append({"edge": table, "dir": label, "detail": edge.get("detail"),
                                 "ids": edge.get("ids") or [], "path": edge.get("path"),
                                 "title": edge.get("title"), "observed_at": edge.get("observed_at")})
        return doc, rows, totals
    finally:
        await db.close()


def export_graph(doc: dict, edges: list[dict], format: str) -> dict:
    """Serialize one bounded neighborhood without writing server-side files."""
    if format == "json":
        return {"document": sq.norm(doc, False), "edges": sq.norm(edges, False)}
    if format == "mermaid":
        return {"mermaid": mermaid(doc, edges)}
    nodes = {doc["source_path"]: {"path": doc["source_path"], "title": doc.get("title"), "root": True}}
    for edge in edges:
        if edge.get("path"):
            nodes.setdefault(edge["path"], {"path": edge["path"], "title": edge.get("title"), "root": False})
    if format == "csv":
        output = {}
        for name, fields, rows in (
            ("nodes_csv", ("path", "title", "root"), nodes.values()),
            ("edges_csv", ("edge", "dir", "detail", "path", "title", "observed_at"), edges),
        ):
            stream = io.StringIO(newline="")
            writer = csv.DictWriter(stream, fieldnames=fields, extrasaction="ignore")
            writer.writeheader(); writer.writerows(rows)
            output[name] = stream.getvalue()
        return output
    if format == "graphml":
        def esc(value):
            import html
            return html.escape(str(value or ""), quote=True)
        ids = {path: f"n{index}" for index, path in enumerate(nodes)}
        lines = ['<?xml version="1.0" encoding="UTF-8"?>',
                 '<graphml xmlns="http://graphml.graphdrawing.org/xmlns">', '<graph edgedefault="directed">']
        for path, node in nodes.items():
            lines.append(f'<node id="{ids[path]}"><data key="path">{esc(path)}</data><data key="title">{esc(node["title"])}</data></node>')
        for index, edge in enumerate(edges):
            if not edge.get("path"): continue
            source, target = (ids[doc["source_path"]], ids[edge["path"]]) if edge["dir"] == "out" else (ids[edge["path"]], ids[doc["source_path"]])
            lines.append(f'<edge id="e{index}" source="{source}" target="{target}"><data key="relation">{esc(edge["edge"])}</data></edge>')
        lines.extend(['</graph>', '</graphml>'])
        return {"graphml": "".join(lines)}
    raise ValueError("Unsupported graph export format")


def mermaid(doc: dict, edges: list[dict]) -> str:
    def label(text: str) -> str:
        return re.sub(r"[\"\[\]{}()<>|`]", " ", str(text or ""))[:60].strip()

    lines = ["graph LR", f'  n0["{label(doc["title"])}"]']
    nodes = {doc["source_path"]: "n0"}
    for e in edges:
        if not e["path"]:
            continue
        nid = nodes.setdefault(e["path"], f"n{len(nodes)}")
        if len(nodes) - 1 == int(nid[1:]) and nid != "n0":
            lines.append(f'  {nid}["{label(e["title"] or e["path"])}"]')
        tag = e["edge"] if not e["detail"] or e["detail"] in ("md_link",) else f'{e["edge"]} {e["detail"]}'
        a, b = ("n0", nid) if e["dir"] == "out" else (nid, "n0")
        lines.append(f"  {a} -->|{label(tag)}| {b}")
    return chr(10).join(lines)


def main() -> int:
    ap = argparse.ArgumentParser(description="Neighborhood of one document in the docstore graph.")
    ap.add_argument("ref", help="ADR-NNNN, document:<id>, or a path fragment")
    ap.add_argument("--limit", type=int, default=25, help="max edges listed per edge type and direction")
    ap.add_argument("--mermaid", action="store_true")
    a = ap.parse_args()
    doc, edges, totals = asyncio.run(neighborhood(a.ref, a.limit))
    if doc is None:
        print(f"no document matches {a.ref!r}")
        return 1
    if a.mermaid:
        print(mermaid(doc, edges))
        return 0
    view = types.SimpleNamespace(sql=None, width=400, cell=70, max_rows=a.limit * 6, show_hidden=False)
    print(f"{doc['title']} | {doc['doc_type']}/{doc['status']} | {doc['source_path']}")
    print("totals: " + " ".join(f"{k}={v}" for k, v in totals.items() if v))
    sq.render([{"edge": e["edge"], "dir": e["dir"], "detail": e["detail"], "ids": e["ids"],
                "path": (e["path"] or "").removeprefix("docs/")} for e in edges], view)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
