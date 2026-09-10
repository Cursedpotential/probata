"""worker_sync - one sync pass for the cloud docstore: incremental ingest -> graph rebuild -> health.

Byline: Claude Code - Opus 5 - 2026-09-10

Owner orders 2026-09-10: run on the server on a cron; use CocoIndex change detection ("the whole point
of ccc") so only changed files re-index; every re-index updates the database.

Runs at container start (each deploy of a docs change is the change event) and from the Coolify
scheduled task. Always FULL scope: CocoIndex deletes whatever a run does not declare, so a partial
run would wipe documents (SETUP.md GOTCHA 9). Change detection keeps a full run cheap.
A lock file prevents overlapping runs. Prints one compact summary line; non-zero exit on failure.
"""
from __future__ import annotations

import asyncio
import json
import os
import pathlib
import re
import subprocess
import sys
import time

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import sq  # noqa: E402

LOCK = pathlib.Path(os.environ.get("DOCSTORE_SYNC_LOCK", "/data/state/sync.lock"))


def _rows(r):
    while isinstance(r, list) and len(r) == 1 and isinstance(r[0], list):
        r = r[0]
    return r if isinstance(r, list) else ([r] if r else [])


def _run(script: str, timeout: int) -> tuple[int, str]:
    env = {k: v for k, v in os.environ.items() if k != "DOCSTORE_ONLY_FILES"}
    p = subprocess.run([sys.executable, str(HERE / script)], capture_output=True, text=True, env=env, timeout=timeout)
    return p.returncode, (p.stdout + p.stderr)


async def _health() -> dict:
    db = await sq.connect("docs", "probata", "docs")
    try:
        out = {}
        for table in ("document", "chunk", "links_to", "cites"):
            r = _rows(await db.query(f"SELECT count() AS n FROM {table} GROUP ALL;"))
            out[table] = r[0]["n"] if r and isinstance(r[0], dict) else 0
        idx = _rows(await db.query("INFO FOR INDEX chunk_embedding ON chunk;"))
        out["hnsw"] = (idx[0] if idx else {}).get("building", {}).get("status")
        orphans = _rows(await db.query("SELECT count() AS n FROM chunk WHERE array::len(->chunk_of->document) = 0 GROUP ALL;"))
        out["orphan_chunks"] = orphans[0]["n"] if orphans and isinstance(orphans[0], dict) else 0
        return out
    finally:
        await db.close()


def main() -> int:
    LOCK.parent.mkdir(parents=True, exist_ok=True)
    try:
        fd = os.open(LOCK, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
    except FileExistsError:
        if time.time() - LOCK.stat().st_mtime < 3600:
            print(json.dumps({"sync": "skipped", "reason": "another sync holds the lock"}))
            return 0
        LOCK.unlink(missing_ok=True)
        fd = os.open(LOCK, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
    os.close(fd)
    t0 = time.time()
    summary: dict = {"sync": "ok"}
    try:
        code, log = _run("flow_docs.py", 3600)
        stats = re.findall(r"process_file: (\d+) total \| ([^\n]*)", log)
        summary["ingest"] = f"exit {code}; " + (stats[-1][1].strip() if stats else "no stats")
        summary["auto_mapped"] = log.count("AUTO-MAPPED")
        if code != 0:
            summary["sync"] = "failed"
            summary["ingest_tail"] = log.strip().splitlines()[-5:]
            return 1
        code, log = _run("graph_build.py", 900)
        summary["graph"] = log.strip().splitlines()[-1] if log.strip() else f"exit {code}"
        if code != 0:
            summary["sync"] = "failed"
            return 1
        summary["health"] = asyncio.run(_health())
        if summary["health"].get("hnsw") != "ready" or summary["health"].get("orphan_chunks"):
            summary["sync"] = "degraded"
        return 0
    finally:
        summary["seconds"] = round(time.time() - t0)
        print(json.dumps(summary, default=str))
        LOCK.unlink(missing_ok=True)


if __name__ == "__main__":
    raise SystemExit(main())
