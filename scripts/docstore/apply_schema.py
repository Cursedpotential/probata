"""Apply scripts/docstore/schema/*.surql to the EMBEDDED docstore.

Byline: Claude Code · Opus 5 · 2026-09-09

Reads SURREAL_URL from .docstore/.env when no URL argument is given.
Needed because surrealkit / surreal sql / surreal import all require a remote
endpoint and cannot reach an embedded datastore."""
import asyncio, pathlib, sys
from surrealdb import AsyncSurreal

URL = sys.argv[1]
NS, DB = (sys.argv[2], sys.argv[3]) if len(sys.argv) > 3 else ("probata", "docs")
SCHEMA = pathlib.Path("scripts/docstore/schema")

async def main():
    db = AsyncSurreal(URL)
    await db.connect()
    await db.use(NS, DB)
    failed = 0
    for f in sorted(SCHEMA.glob("*.surql")):
        try:
            await db.query(f.read_text(encoding="utf-8"))
            print(f"  ok   {f.name}")
        except Exception as e:
            failed += 1
            print(f"  FAIL {f.name}: {str(e).splitlines()[0][:160]}")
    await db.close()
    print("schema applied clean" if not failed else f"{failed} file(s) FAILED")
    return 1 if failed else 0

raise SystemExit(asyncio.run(main()))
