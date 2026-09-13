"""api - HTTP API over the cloud docstore, for a front end.

Byline: Claude Code - Opus 5 - 2026-09-10

Owner order 2026-09-10: "make sure there's an API exposed so I can put a front end on this."
Runs inside the docstore-worker container (uvicorn --app-dir scripts/docstore api:app), tailnet-only.
Recall, rerank and graph logic live in the same modules the CLI and slash commands use, so the API,
the commands and agents all get identical results.

Endpoints (JSON unless noted):
  /health                                   liveness + store reachability
  /stats                                    document/chunk/edge counts, vector index status
  /recall?q=&kind=doc|adr|handoff|...&k=8&status=active|all&domain=&rerank=true
  /doc/{record_id}                          one document (body included)
  /graph/{ref}?limit=25&format=json|mermaid ref = ADR-NNNN, document:<id>, or a path fragment
  GET /pipeline                              live app/environment identity from durable status
  POST /runs                                start full reconciliation or selected verification
  GET /runs/current and /runs/{run_id}       bounded durable worker status
  DELETE /runs/{run_id}                      cancel a run owned by this API process
Auth: tailnet-only by network; if DOCSTORE_API_TOKEN is set, every route but /health requires
`Authorization: Bearer <token>`.
"""
from __future__ import annotations

import os
import pathlib
import subprocess
import sys
import threading
import uuid

from fastapi import FastAPI, Header, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import PlainTextResponse

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import graph_query  # noqa: E402
import recall as recall_mod  # noqa: E402
import sq  # noqa: E402
from run_support import read_current_status  # noqa: E402

TOKEN = os.environ.get("DOCSTORE_API_TOKEN")
RUN_STATUS = pathlib.Path(os.environ.get(
    "DOCSTORE_RUN_STATUS",
    "/data/state/latest-run.json" if os.name != "nt" else
    str(pathlib.Path(__file__).resolve().parents[1] / ".docstore/latest-run.json"),
))
RUN_RECEIPTS = pathlib.Path(os.environ.get("DOCSTORE_RUN_RECEIPTS", str(RUN_STATUS.parent / "runs")))
_jobs: dict[str, subprocess.Popen] = {}
_jobs_lock = threading.Lock()
app = FastAPI(title="probata docstore API", version="0.2.0")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["GET", "POST", "DELETE"], allow_headers=["*"])


def _auth(authorization: str | None) -> None:
    if TOKEN and authorization != f"Bearer {TOKEN}":
        raise HTTPException(status_code=401, detail="missing or wrong bearer token")


def _rows(r):
    while isinstance(r, list) and len(r) == 1 and isinstance(r[0], list):
        r = r[0]
    return r if isinstance(r, list) else ([r] if r else [])


def _sync_status() -> dict:
    try:
        value = read_current_status(RUN_STATUS)
        return {key: value.get(key) for key in
                ("sync", "run_id", "at", "seconds", "error_type", "app", "environment",
                 "source_scope", "requested_scope", "source_count", "source_digest_before",
                 "source_digest_after", "cdc_verified", "cdc_attribution")}
    except FileNotFoundError:
        return {"sync": "unavailable", "cdc_verified": False}
    except (OSError, ValueError, TypeError):
        return {"sync": "invalid", "cdc_verified": False}


def _public_status(value: dict) -> dict:
    allowed = ("sync", "run_id", "at", "seconds", "error_type", "app", "environment",
               "source_scope", "requested_scope", "requested_paths", "source_count",
               "source_digest_before", "source_digest_after", "cdc_verified", "cdc_attribution")
    return {key: value.get(key) for key in allowed if key in value}


def _read_run(run_id: str) -> dict:
    candidates = sorted(RUN_RECEIPTS.glob(f"{run_id}-[0-9][0-9][0-9].json"))
    if not candidates:
        with _jobs_lock:
            process = _jobs.get(run_id)
        if process is not None:
            return {"run_id": run_id, "sync": "queued", "cdc_verified": False}
        raise HTTPException(status_code=404, detail="run not found")
    import json
    path = candidates[-1]
    info = path.stat()
    if path.is_symlink() or not path.is_file() or info.st_size > 65536:
        raise HTTPException(status_code=503, detail="run receipt invalid")
    value = json.loads(path.read_bytes())
    if value.get("run_id") != run_id or value.get("receipt_kind") != "worker-execution-v1":
        raise HTTPException(status_code=503, detail="run receipt invalid")
    return _public_status(value)


@app.get("/pipeline")
def pipeline(authorization: str | None = Header(default=None)) -> dict:
    _auth(authorization)
    status = _sync_status()
    verified = (status.get("app") == "ProbataDocStore"
                and status.get("environment") == "probata-docstore"
                and status.get("sync") == "execution_finished")
    return {"app": "ProbataDocStore", "environment": "probata-docstore",
            "identity_verified_live": verified, "latest_run": status}


@app.get("/runs/current")
def current_run(authorization: str | None = Header(default=None)) -> dict:
    _auth(authorization)
    return _public_status(read_current_status(RUN_STATUS))


@app.get("/runs/{run_id}")
def run_status(run_id: str, authorization: str | None = Header(default=None)) -> dict:
    _auth(authorization)
    if len(run_id) != 32 or any(c not in "0123456789abcdef" for c in run_id):
        raise HTTPException(status_code=400, detail="invalid run ID")
    return _read_run(run_id)


@app.post("/runs", status_code=202)
def start_run(payload: dict, authorization: str | None = Header(default=None)) -> dict:
    _auth(authorization)
    scope = payload.get("scope", "full")
    paths = payload.get("paths", [])
    if scope not in {"full", "selected"} or not isinstance(paths, list):
        raise HTTPException(status_code=400, detail="scope must be full or selected")
    if scope == "full" and paths:
        raise HTTPException(status_code=400, detail="full scope does not accept paths")
    if scope == "selected" and (not 1 <= len(paths) <= 20 or len(set(paths)) != len(paths)
                                or any(not isinstance(path, str) or not path.startswith("docs/")
                                       or ".." in pathlib.PurePosixPath(path).parts for path in paths)):
        raise HTTPException(status_code=400, detail="selected scope requires 1-20 unique docs/... paths")
    run_id = uuid.uuid4().hex
    env = dict(os.environ)
    env["DOCSTORE_RUN_ID"] = run_id
    if paths:
        env["DOCSTORE_REQUESTED_PATHS"] = "\n".join(paths)
    with _jobs_lock:
        if any(process.poll() is None for process in _jobs.values()):
            raise HTTPException(status_code=409, detail="a run is already active")
        process = subprocess.Popen([sys.executable, str(pathlib.Path(__file__).with_name("worker_sync.py"))], env=env)
        _jobs[run_id] = process
    return {"run_id": run_id, "sync": "queued", "requested_scope": scope,
            "requested_paths": paths, "full_source_reconciliation": True,
            "selected_paths_are_verification_targets": bool(paths)}


@app.delete("/runs/{run_id}", status_code=202)
def cancel_run(run_id: str, authorization: str | None = Header(default=None)) -> dict:
    _auth(authorization)
    with _jobs_lock:
        process = _jobs.get(run_id)
    if process is None or process.poll() is not None:
        raise HTTPException(status_code=409, detail="run is not active")
    process.terminate()
    return {"run_id": run_id, "cancellation_requested": True}


@app.get("/health")
async def health() -> dict:
    sync = _sync_status()
    try:
        db = await sq.connect("docs", "probata", "docs")
        await db.query("RETURN 1;")
        await db.close()
        store = "up"
    except Exception as e:  # noqa: BLE001
        store = f"down: {type(e).__name__}"
    return {
        "ok": store == "up" and sync["sync"] not in {"failed", "degraded", "invalid"},
        "api": "up",
        "store": store,
        "startup_or_latest_sync": sync,
        "execution_receipt_is_not_cdc_proof": True,
    }


@app.get("/stats")
async def stats(authorization: str | None = Header(default=None)) -> dict:
    _auth(authorization)
    db = await sq.connect("docs", "probata", "docs")
    try:
        out = {}
        for table in ("document", "chunk", "chunk_of", "links_to", "cites", "supersedes"):
            r = _rows(await db.query(f"SELECT count() AS n FROM {table} GROUP ALL;"))
            out[table] = r[0]["n"] if r and isinstance(r[0], dict) else 0
        idx = _rows(await db.query("INFO FOR INDEX chunk_embedding ON chunk;"))
        out["vector_index"] = (idx[0] if idx else {}).get("building", {})
        return sq.norm(out, False)
    finally:
        await db.close()


@app.get("/recall")
async def recall(q: str = Query(..., min_length=2), kind: str = "doc", k: int = Query(8, ge=1, le=50),
                 status: str = "active", domain: str | None = None, rerank: bool = True,
                 authorization: str | None = Header(default=None)) -> dict:
    _auth(authorization)
    if kind not in recall_mod.KINDS:
        raise HTTPException(status_code=400, detail=f"kind must be one of {sorted(recall_mod.KINDS)}")
    results, st = await recall_mod.recall(q, kind, status, k, domain, rerank)
    return {"query": q, "kind": kind, "results": results, "stats": st}


@app.get("/doc/{record_id}")
async def doc(record_id: str, authorization: str | None = Header(default=None)) -> dict:
    _auth(authorization)
    rid = record_id if record_id.startswith("document:") else f"document:{record_id}"
    db = await sq.connect("docs", "probata", "docs")
    try:
        r = _rows(await db.query(
            "SELECT id, source_path, title, doc_type, domains, status, observed_at, body FROM type::record($r);",
            {"r": rid}))
    finally:
        await db.close()
    if not r:
        raise HTTPException(status_code=404, detail=f"{rid} not found")
    row = sq.norm(r[0], True)
    return row


@app.get("/graph/{ref:path}")
async def graph(ref: str, limit: int = Query(25, ge=1, le=200), format: str = "json",
                authorization: str | None = Header(default=None)):
    _auth(authorization)
    d, edges, totals = await graph_query.neighborhood(ref, limit)
    if d is None:
        raise HTTPException(status_code=404, detail=f"no document matches {ref!r}")
    if format == "mermaid":
        return PlainTextResponse(graph_query.mermaid(d, edges))
    return {"document": sq.norm(d, False), "totals": totals, "edges": sq.norm(edges, False)}
