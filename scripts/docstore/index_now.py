"""index_now.py - one command to get a new/changed doc into the Docstore.

Byline: Claude Code - Opus 5 - 2026-09-16

THE PROBLEM THIS SOLVES (defect 8, owner order 2026-09-16)
  Files outside the Probata repo - Consignatio, Legal-desktop/advocatio,
  family-court-workbench, vestigia - do NOT reach the worker by being written.
  The worker container reads its corpus from `/exchange/sources` on ovh-files,
  which is a PUSHED PROJECTION of the monorepo. Writing a decision file and
  calling docstore_index_full therefore indexes the OLD corpus and the new file
  silently never appears. There was no automation and no single documented
  path; this script is that path.

WHAT IT DOES, in order
  1. build + push the projection      (build_projection.py --push)
  2. start one governed full run      (worker HTTP API: POST /index/full)
  3. poll until the run finishes      (GET /runs/current)
  4. assert CDC attribution verified  (GET /health -> cdc_attribution.status)
  5. report each --path's stored id    (fn::docs_get read-back)

  Step 2 is a FULL run every time, by design: CocoIndex deletes whatever a run
  does not declare, so a partial run would wipe documents (SETUP.md GOTCHA 9).
  Change detection keeps a full run cheap.

USAGE
  cd <repo root>
  "C:/Users/matts/.local/bin/python3.exe" scripts/docstore/index_now.py \
      --path consignatio/docs/decisions/2026-09-16-catalog-source-of-truth.md

  --path            projected source_path to verify afterwards (repeatable).
                    This is the path AFTER projection: the registry's
                    canonical_prefix replaces the project's source_root, so
                    `Consignatio/docs/x.md` is stored as `consignatio/docs/x.md`.
  --no-push         skip the projection build/push (corpus already current)
  --registry        override the source registry path
  --timeout         seconds to wait for the run (default 900)

SAFETY
  Refuses to start when a run is already in flight, so it cannot cancel another
  lane's run. Never deletes anything. The projection push keeps the previous
  corpus on the host as `sources.prev-<stamp>`.
"""
from __future__ import annotations

import argparse
import asyncio
import json
import pathlib
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parents[1]
DEFAULT_REGISTRY = "E:/AI_Workspace/Projects/Propria/docs/docstore-source-registry.json"
PY = sys.executable


def env_file(path: pathlib.Path) -> dict:
    """Tolerant KEY = value parse; never sourced, never printed."""
    out = {}
    if path.is_file():
        for line in path.read_text(encoding="utf-8", errors="ignore").splitlines():
            m = re.match(r"^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.+?)\s*$", line)
            if m:
                out[m.group(1)] = m.group(2).strip().strip('"').strip("'")
    return out


SECRETS = env_file(pathlib.Path.home() / ".secrets" / "probata-docstore.env")
# The worker's own HTTP API - the SAME endpoint and routes the control MCP
# server calls (plugins/docstore/control/server.py): POST /runs starts a run,
# GET /runs/current is the durable status, GET /health carries cdc_attribution.
import os as _os

API = _os.environ.get("DOCSTORE_API_URL") or SECRETS.get("DOCSTORE_API_URL") \
    or "https://docstore-api.tilapia-skilift.ts.net"


def api(path: str, method: str = "GET", body: dict | None = None, timeout: int = 60):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(
        API.rstrip("/") + path, data=data, method=method,
        headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode("utf-8", "replace") or "{}")


def push_projection(registry: str) -> dict:
    print("[1/5] building + pushing the projection ...")
    cmd = [PY, str(HERE / "build_projection.py"), "--registry", registry, "--push"]
    p = subprocess.run(cmd, capture_output=True, text=True, cwd=str(REPO))
    sys.stdout.write(p.stdout)
    if p.returncode != 0:
        sys.stderr.write(p.stderr)
        raise SystemExit(f"projection push failed (exit {p.returncode})")
    for line in reversed(p.stdout.strip().splitlines()):
        if line.strip().startswith("{"):
            return json.loads(line)
    return {}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--path", action="append", default=[],
                    help="projected source_path to verify afterwards (repeatable)")
    ap.add_argument("--no-push", action="store_true")
    ap.add_argument("--registry", default=DEFAULT_REGISTRY)
    ap.add_argument("--timeout", type=int, default=900)
    a = ap.parse_args()

    cur = api("/runs/current")
    if cur.get("sync") in ("queued", "running", "execution_started"):
        raise SystemExit(f"a run is already in flight (run_id {cur.get('run_id')}, "
                         f"sync={cur.get('sync')}); refusing to start another")

    if not a.no_push:
        print(json.dumps(push_projection(a.registry), indent=2))
    else:
        print("[1/5] projection push skipped (--no-push)")

    print("[2/5] starting a full governed run ...")
    started = api("/runs", "POST", {"scope": "full", "paths": [],
                                    "full_reprocess": False,
                                    "tracking_rebuild": False,
                                    "index_kind": "docs"})
    run_id = started.get("run_id")
    print(f"      run_id {run_id} sync={started.get('sync')}")

    print("[3/5] waiting for the run to finish ...")
    deadline = time.time() + a.timeout
    last = None
    while time.time() < deadline:
        time.sleep(10)
        st = api("/runs/current")
        if st.get("sync") != last:
            last = st.get("sync")
            print(f"      {last} ({int(st.get('seconds') or 0)}s)")
        if st.get("sync") in ("execution_finished", "execution_failed", "failed", "cancelled") \
           and st.get("run_id") == run_id:
            break
    else:
        raise SystemExit(f"run {run_id} did not finish within {a.timeout}s")

    final = api("/runs/current")
    if final.get("sync") != "execution_finished":
        print(json.dumps(final, indent=2))
        raise SystemExit(f"run ended as {final.get('sync')}")

    print("[4/5] checking CDC attribution ...")
    health = api("/health")
    latest = health.get("startup_or_latest_sync") or {}
    att = latest.get("cdc_attribution") or {}
    print(f"      status={att.get('status')} expected={att.get('expected_documents')} "
          f"observed={att.get('observed_documents')} missing={att.get('missing_count')} "
          f"mismatch={att.get('hash_mismatch_count')}")
    if att.get("status") != "verified":
        raise SystemExit(f"cdc_attribution.status is {att.get('status')!r}, not 'verified'")

    if not a.path:
        print("[5/5] no --path given; nothing to read back")
        return 0

    print("[5/5] reading back each --path from the store ...")
    from surrealdb import AsyncSurreal

    async def readback():
        db = AsyncSurreal(SECRETS["SURREAL_DOCS_URL"])
        await db.connect()
        await db.signin({"username": SECRETS["SURREAL_DOCS_USER"],
                         "password": SECRETS["SURREAL_DOCS_PASS"]})
        await db.use("probata", "docs")
        bad = 0
        for p in a.path:
            rows = await db.query(
                "SELECT id, status, doc_type, tags, content_hash FROM document "
                "WHERE source_path = $p;", {"p": p})
            while isinstance(rows, list) and len(rows) == 1 and isinstance(rows[0], list):
                rows = rows[0]
            rows = rows if isinstance(rows, list) else [rows]
            if not rows:
                print(f"      MISSING  {p}")
                bad += 1
                continue
            for r in rows:
                print(f"      OK       {p}\n               id={r.get('id')} "
                      f"status={r.get('status')} doc_type={r.get('doc_type')} "
                      f"tags={r.get('tags')}")
        await db.close()
        return bad

    bad = asyncio.run(readback())
    if bad:
        raise SystemExit(f"{bad} path(s) not found in the store after a verified run")
    print("\nindexed and verified.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
