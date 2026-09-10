"""sq - run SurrealQL and render the result through DuckDB.

Byline: Claude Code - Opus 5 - 2026-09-10

Owner order 2026-09-10: strip SDK noise before it reaches an agent's context,
and let DuckDB do the layout. Rows are normalised first:
  RecordID(table_name=x, record_id='y')    ->  x:y
  PreciseDatetime(...)                     ->  2026-09-10 11:03:38
  2048-float embedding / body              ->  <vec 2048> / <N chars>
then loaded into an in-memory DuckDB table `r` and printed with DuckDB's own
column-typed, width-capped table renderer.

Usage:
  python scripts/docstore/sq.py "SELECT * FROM todo LIMIT 5;"
  python scripts/docstore/sq.py "SELECT doc_type, status FROM document;" --sql "SELECT doc_type, count(*) n FROM r GROUP BY ALL ORDER BY n DESC"
  python scripts/docstore/sq.py --target docs "INFO FOR DB;"
  echo "SELECT * FROM chunk LIMIT 3;" | python scripts/docstore/sq.py -

Targets:
  docs   dedicated VPS instance surreal-docs (DEFAULT since 2026-09-10), creds from ~/.secrets/probata-docstore.env
  local  retired embedded store at <repo>/.docstore/kv (kept as a backup). Single-process: stop other holders.
"""
from __future__ import annotations

import argparse
import asyncio
import datetime as _dt
import json
import os
import pathlib
import tempfile
import time

REPO = pathlib.Path(__file__).resolve().parents[2]
HIDE = {"embedding", "body"}
NL = chr(10)


def _env(path: pathlib.Path) -> dict:
    out = {}
    if path.is_file():
        for line in path.read_text(encoding="utf-8", errors="ignore").splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, _, v = line.partition("=")
            out[k.strip()] = v.strip().strip("'").strip('"')
    return out


def norm(v, show_hidden: bool, key: str | None = None):
    """SDK value -> plain JSON-safe value."""
    name = type(v).__name__
    if key in HIDE and not show_hidden and v is not None:
        return f"<{len(v)} chars>" if isinstance(v, str) else f"<vec {len(v)}>" if hasattr(v, "__len__") else "<hidden>"
    if name == "RecordID":
        return f"{v.table_name}:{v.id}"
    if isinstance(v, (_dt.datetime, _dt.date)) or name in ("PreciseDatetime", "IsoDateTimeWrapper", "Datetime"):
        try:
            return v.strftime("%Y-%m-%d %H:%M:%S")
        except Exception:
            return str(v)
    if name == "Duration":
        return str(v)
    if isinstance(v, str):
        return " ".join(v.split())
    if isinstance(v, list):
        if len(v) > 8 and all(isinstance(x, (int, float)) for x in v[:8]):
            return f"<vec {len(v)}>"
        return [norm(x, show_hidden) for x in v]
    if isinstance(v, dict):
        return {k: norm(x, show_hidden, k) for k, x in v.items()}
    if v is None or isinstance(v, (bool, int, float)):
        return v
    return str(v)


def _flat(v, cell: int):
    """Lists/objects -> one short string, so DuckDB never hides columns behind a wide nested cell."""
    if isinstance(v, list):
        items = [str(x) for x in v[:4]]
        text = ", ".join(items) + (f" (+{len(v) - 4})" if len(v) > 4 else "")
    elif isinstance(v, dict):
        text = json.dumps(v, ensure_ascii=False, default=str)
    else:
        return v
    return text if len(text) <= cell else text[: cell - 1] + "…"


def render(rows, a, label: str | None = None) -> None:
    import duckdb

    if label:
        print(f"-- {label}")
    if not isinstance(rows, list):
        rows = [rows]
    if not rows:
        print("(0 rows)")
        return
    if not all(isinstance(r, dict) for r in rows):
        rows = [{"value": r} for r in rows]
    rows = [norm(r, a.show_hidden) for r in rows]
    rows = [({"id": r["id"], **{k: x for k, x in r.items() if k != "id"}} if "id" in r else r) for r in rows]
    if not a.sql:
        rows = [{k: _flat(v, a.cell) for k, v in r.items()} for r in rows]

    fd, path = tempfile.mkstemp(suffix=".ndjson")
    os.close(fd)
    try:
        with open(path, "w", encoding="utf-8") as f:
            for r in rows:
                f.write(json.dumps(r, default=str, ensure_ascii=False) + NL)
        lit = path.replace(chr(92), "/").replace("'", "''")
        con = duckdb.connect()
        con.execute(f"CREATE TABLE r AS SELECT * FROM read_json_auto('{lit}', format='newline_delimited', union_by_name=true, sample_size=-1)")
        rel = con.sql(a.sql) if a.sql else con.sql("SELECT * FROM r")
        rel.show(max_width=a.width, max_rows=a.max_rows, max_col_width=a.cell)
        con.close()
    finally:
        os.remove(path)


async def connect(target: str, ns: str, db_name: str):
    from surrealdb import AsyncSurreal

    if target == "local":
        env = _env(REPO / ".docstore/.env")
        url = env.get("SURREAL_URL", "surrealkv://{REPO_ROOT}/.docstore/kv").replace("{REPO_ROOT}", REPO.as_posix())
        db = AsyncSurreal(url)
        await db.connect()
    else:
        env = _env(pathlib.Path.home() / ".secrets" / "probata-docstore.env")
        # Inside the server worker there is no ~/.secrets: the same keys come from the container env.
        env.update({k: os.environ[k] for k in ("SURREAL_DOCS_URL", "SURREAL_DOCS_USER", "SURREAL_DOCS_PASS") if os.environ.get(k)})
        db = AsyncSurreal(env["SURREAL_DOCS_URL"])
        await db.connect()
        await db.signin({"username": env["SURREAL_DOCS_USER"], "password": env["SURREAL_DOCS_PASS"]})
    await db.use(ns, db_name)
    return db


async def main() -> int:
    ap = argparse.ArgumentParser(description="Run SurrealQL, render through DuckDB.")
    ap.add_argument("query", help="SurrealQL text, or - to read stdin")
    ap.add_argument("--target", default="docs", choices=["docs", "local"])
    ap.add_argument("--ns", default="probata")
    ap.add_argument("--db", default="docs")
    ap.add_argument("--sql", help="DuckDB SQL over the result table `r` (single-statement queries)")
    ap.add_argument("--max-rows", type=int, default=20)
    ap.add_argument("--width", type=int, default=160)
    ap.add_argument("--cell", type=int, default=36, help="max chars per column")
    ap.add_argument("--show-hidden", action="store_true", help="include embedding/body values")
    a = ap.parse_args()
    import sys
    q = sys.stdin.read() if a.query == "-" else a.query

    t0 = time.perf_counter()
    try:
        db = await connect(a.target, a.ns, a.db)
        result = await db.query(q)
        await db.close()
    except Exception as e:
        first = (str(e).strip().splitlines() or [""])[0]
        print(f"ERROR {type(e).__name__}: {first[:300]}")
        return 1
    ms = (time.perf_counter() - t0) * 1000

    statements = [s.strip() for s in q.split(";") if s.strip()]
    if len(statements) > 1 and isinstance(result, list) and len(result) == len(statements):
        for i, part in enumerate(result):
            render(part, a, " ".join(statements[i].split())[:80])
    else:
        while isinstance(result, list) and len(result) == 1 and isinstance(result[0], list):
            result = result[0]
        render(result, a)
    print(f"[{a.target} {ms:.0f} ms]")
    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
