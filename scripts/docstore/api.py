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
  GET /runs                                 bounded durable run history
  GET /runs/current and /runs/{run_id}       bounded durable worker status
  GET /attribution                          fresh exact source-to-store verification
  DELETE /runs/{run_id}                      cancel a run owned by this API process
Auth: tailnet-only by network; if DOCSTORE_API_TOKEN is set, every route but /health requires
`Authorization: Bearer <token>`.
"""
from __future__ import annotations

import os
import pathlib
import re
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
from cdc_verify import snapshot_sources, verify_projection  # noqa: E402

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
INDEX_IDENTITY = {"app": "ProbataDocStore", "environment": "probata-docstore", "index_kind": "docs",
                  "allowed_source_roots": ["docs/"], "allowed_file_classes": ["markdown"],
                  "rejected_file_classes": ["source_code", "configuration", "test"]}


def _docs_index(index_kind: str) -> None:
    if index_kind != "docs":
        raise HTTPException(status_code=400, detail="this endpoint owns only the docs index")


def _identified(value: dict) -> dict:
    return {**INDEX_IDENTITY, **value}


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
                 "source_digest_after", "full_reprocess", "cdc_verified", "cdc_attribution")}
    except FileNotFoundError:
        return {"sync": "unavailable", "cdc_verified": False}
    except (OSError, ValueError, TypeError):
        return {"sync": "invalid", "cdc_verified": False}


def _public_status(value: dict) -> dict:
    allowed = ("sync", "run_id", "at", "seconds", "error_type", "app", "environment",
               "source_scope", "requested_scope", "requested_paths", "source_count",
               "full_reprocess",
               "source_digest_before", "source_digest_after", "cdc_verified", "cdc_attribution")
    return {key: value.get(key) for key in allowed if key in value}


def _read_run(run_id: str) -> dict:
    candidates = sorted(RUN_RECEIPTS.glob(f"{run_id}-[0-9][0-9][0-9].json"))
    if not candidates:
        with _jobs_lock:
            process = _jobs.get(run_id)
        if process is not None:
            return ({"run_id": run_id, "sync": "queued", "cdc_verified": False}
                    if process.poll() is None else
                    {"run_id": run_id, "sync": "failed", "cdc_verified": False,
                     "error_type": "WorkerExitedBeforeReceipt", "exit_code": process.returncode})
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


def _run_history(limit: int) -> list[dict]:
    """Return the newest valid terminal receipt for each run, newest first."""
    found: dict[str, tuple[int, pathlib.Path]] = {}
    try:
        paths = RUN_RECEIPTS.glob("*-[0-9][0-9][0-9].json")
        for path in paths:
            match = path.name.rsplit("-", 1)
            if len(match) != 2 or len(match[0]) != 32 or any(c not in "0123456789abcdef" for c in match[0]):
                continue
            try:
                sequence = int(match[1].removesuffix(".json"))
            except ValueError:
                continue
            previous = found.get(match[0])
            if previous is None or sequence > previous[0]:
                found[match[0]] = (sequence, path)
    except OSError:
        raise HTTPException(status_code=503, detail="run history unavailable") from None
    rows = []
    for run_id, (_, path) in found.items():
        try:
            value = _read_run(run_id)
            rows.append(value)
        except HTTPException:
            continue
    rows.sort(key=lambda row: str(row.get("at", "")), reverse=True)
    return rows[:limit]


@app.get("/pipeline")
def pipeline(index_kind: str = "docs", authorization: str | None = Header(default=None)) -> dict:
    _auth(authorization)
    _docs_index(index_kind)
    status = _sync_status()
    verified = (status.get("app") == "ProbataDocStore"
                and status.get("environment") == "probata-docstore"
                and status.get("sync") in {"running", "failed", "degraded", "cancelled", "execution_finished"})
    return _identified({"identity_verified_live": verified, "latest_run": status})


@app.get("/runs/current")
def current_run(index_kind: str = "docs", authorization: str | None = Header(default=None)) -> dict:
    _auth(authorization)
    _docs_index(index_kind)
    return _identified(_public_status(read_current_status(RUN_STATUS)))


@app.get("/runs")
def run_history(limit: int = Query(20, ge=1, le=100),
                index_kind: str = "docs",
                authorization: str | None = Header(default=None)) -> dict:
    _auth(authorization)
    _docs_index(index_kind)
    rows = _run_history(limit)
    return _identified({"runs": [_identified(row) for row in rows], "count": len(rows), "limit": limit})


@app.get("/runs/{run_id}")
def run_status(run_id: str, index_kind: str = "docs", authorization: str | None = Header(default=None)) -> dict:
    _auth(authorization)
    _docs_index(index_kind)
    if len(run_id) != 32 or any(c not in "0123456789abcdef" for c in run_id):
        raise HTTPException(status_code=400, detail="invalid run ID")
    return _identified(_read_run(run_id))


@app.post("/runs", status_code=202)
def start_run(payload: dict, authorization: str | None = Header(default=None)) -> dict:
    _auth(authorization)
    scope = payload.get("scope", "full")
    paths = payload.get("paths", [])
    full_reprocess = payload.get("full_reprocess", False)
    _docs_index(payload.get("index_kind", "docs"))
    if scope not in {"full", "selected"} or not isinstance(paths, list) or type(full_reprocess) is not bool:
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
    if full_reprocess:
        env["DOCSTORE_FULL_REPROCESS"] = "1"
    with _jobs_lock:
        if any(process.poll() is None for process in _jobs.values()):
            raise HTTPException(status_code=409, detail="a run is already active")
        process = subprocess.Popen([sys.executable, str(pathlib.Path(__file__).with_name("worker_sync.py"))], env=env)
        _jobs[run_id] = process
    return _identified({"run_id": run_id, "sync": "queued", "requested_scope": scope,
            "requested_paths": paths, "full_source_reconciliation": True,
            "full_reprocess": full_reprocess,
            "selected_paths_are_verification_targets": bool(paths)})


@app.delete("/runs/{run_id}", status_code=202)
def cancel_run(run_id: str, index_kind: str = "docs", authorization: str | None = Header(default=None)) -> dict:
    _auth(authorization)
    _docs_index(index_kind)
    with _jobs_lock:
        process = _jobs.get(run_id)
    if process is None or process.poll() is not None:
        raise HTTPException(status_code=409, detail="run is not active")
    process.terminate()
    return _identified({"run_id": run_id, "cancellation_requested": True})


@app.get("/attribution")
async def attribution(index_kind: str = "docs", authorization: str | None = Header(default=None)) -> dict:
    """Run a fresh, read-only exact reconciliation of declared sources and SurrealDB."""
    _auth(authorization)
    _docs_index(index_kind)
    try:
        source, digest = snapshot_sources()
        result = await verify_projection(source)
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(status_code=503, detail=f"attribution unavailable: {type(exc).__name__}") from None
    return _identified({"source_digest": digest, "source_count": len(source),
                        "cdc_verified": result.get("status") == "verified", "cdc_attribution": result})


@app.get("/health")
async def health(index_kind: str = "docs") -> dict:
    _docs_index(index_kind)
    sync = _sync_status()
    try:
        db = await sq.connect("docs", "probata", "docs")
        await db.query("RETURN 1;")
        await db.close()
        store = "up"
    except Exception as e:  # noqa: BLE001
        store = f"down: {type(e).__name__}"
    return _identified({
        "ok": store == "up" and sync["sync"] not in {"failed", "degraded", "invalid"},
        "api": "up",
        "store": store,
        "startup_or_latest_sync": sync,
        "execution_receipt_is_not_cdc_proof": True,
    })


@app.get("/stats")
async def stats(index_kind: str = "docs", authorization: str | None = Header(default=None)) -> dict:
    _auth(authorization)
    _docs_index(index_kind)
    db = await sq.connect("docs", "probata", "docs")
    try:
        out = {}
        for table in ("document", "chunk", "chunk_of", "links_to", "cites", "supersedes"):
            r = _rows(await db.query(f"SELECT count() AS n FROM {table} GROUP ALL;"))
            out[table] = r[0]["n"] if r and isinstance(r[0], dict) else 0
        idx = _rows(await db.query("INFO FOR INDEX chunk_embedding ON chunk;"))
        out["vector_index"] = (idx[0] if idx else {}).get("building", {})
        return _identified(sq.norm(out, False))
    finally:
        await db.close()


@app.get("/recall")
async def recall(q: str = Query(..., min_length=2), kind: str = "doc", k: int = Query(8, ge=1, le=50),
                 status: str = "active", domain: str | None = None, rerank: bool = True,
                 index_kind: str = "docs",
                 authorization: str | None = Header(default=None)) -> dict:
    _auth(authorization)
    _docs_index(index_kind)
    if kind not in recall_mod.KINDS:
        raise HTTPException(status_code=400, detail=f"kind must be one of {sorted(recall_mod.KINDS)}")
    results, st = await recall_mod.recall(q, kind, status, k, domain, rerank)
    return _identified({"query": q, "kind": kind, "results": results, "stats": st})


@app.get("/doc/{record_id}")
async def doc(record_id: str, index_kind: str = "docs", authorization: str | None = Header(default=None)) -> dict:
    _auth(authorization)
    _docs_index(index_kind)
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
    return _identified(row)


@app.get("/graph/{ref:path}")
async def graph(ref: str, limit: int = Query(25, ge=1, le=200), format: str = "json",
                index_kind: str = "docs",
                authorization: str | None = Header(default=None)):
    _auth(authorization)
    _docs_index(index_kind)
    d, edges, totals = await graph_query.neighborhood(ref, limit)
    if d is None:
        raise HTTPException(status_code=404, detail=f"no document matches {ref!r}")
    if format == "mermaid":
        return PlainTextResponse(graph_query.mermaid(d, edges))
    return _identified({"document": sq.norm(d, False), "totals": totals, "edges": sq.norm(edges, False)})


@app.get("/graph-schema")
async def graph_schema(index_kind: str = "docs", authorization: str | None = Header(default=None)) -> dict:
    """Describe the fixed read-only graph contract and live bounded table counts."""
    _auth(authorization)
    _docs_index(index_kind)
    db = await sq.connect("docs", "probata", "docs")
    try:
        counts = {}
        for table in ("document", "links_to", "cites", "supersedes"):
            rows = _rows(await db.query(f"SELECT count() AS n FROM {table} GROUP ALL;"))
            counts[table] = rows[0]["n"] if rows and isinstance(rows[0], dict) else 0
    finally:
        await db.close()
    return _identified({"node_table": "document", "relation_tables": ["links_to", "cites", "supersedes"],
            "directions": ["in", "out", "both"], "max_depth": 1, "max_limit_per_relation_direction": 200,
            "export_formats": ["json", "csv", "graphml", "mermaid"], "counts": counts,
            "arbitrary_surrealql_available": False})


def _graph_spec(ref: str, relations: str, direction: str, limit: int, source_prefix: str,
                observed_from: str, observed_to: str, depth: int, format: str) -> dict:
    relation_types = tuple(item.strip() for item in relations.split(",") if item.strip())
    if not ref.strip() or len(ref) > 256:
        raise HTTPException(status_code=400, detail="subject must contain at most 256 characters")
    if not relation_types or any(item not in {"links_to", "cites", "supersedes"} for item in relation_types):
        raise HTTPException(status_code=400, detail="unsupported relation type")
    if direction not in {"in", "out", "both"} or depth != 1 or format not in {"json", "csv", "graphml", "mermaid"}:
        raise HTTPException(status_code=400, detail="unsupported bounded graph query")
    for value in (observed_from, observed_to):
        if value and not re.fullmatch(r"\d{4}-\d{2}-\d{2}(?:T[^\s]{1,40})?", value):
            raise HTTPException(status_code=400, detail="time bounds must be ISO-8601 dates/timestamps")
    if source_prefix and (len(source_prefix) > 256 or ".." in pathlib.PurePosixPath(source_prefix).parts):
        raise HTTPException(status_code=400, detail="unsafe source prefix")
    return {"subject": ref, "relation_types": relation_types, "direction": direction, "depth": depth,
            "limit": limit, "source_prefix": source_prefix, "observed_from": observed_from,
            "observed_to": observed_to, "format": format,
            "maximum_edges_returned": limit * len(relation_types) * (2 if direction == "both" else 1),
            "read_only": True}


@app.get("/graph-query")
async def graph_query_endpoint(ref: str, relations: str = "links_to,cites,supersedes",
                               direction: str = "both", limit: int = Query(25, ge=1, le=200),
                               source_prefix: str = "", observed_from: str = "", observed_to: str = "",
                               depth: int = Query(1, ge=1, le=1), format: str = "json", preview: bool = False,
                               index_kind: str = "docs",
                               authorization: str | None = Header(default=None)) -> dict:
    _auth(authorization)
    _docs_index(index_kind)
    spec = _graph_spec(ref, relations, direction, limit, source_prefix, observed_from, observed_to, depth, format)
    if preview:
        return _identified({"preview": spec, "executed": False})
    try:
        doc, edges, totals = await graph_query.structured_neighborhood(
            ref, spec["relation_types"], direction, limit, source_prefix, observed_from, observed_to)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from None
    if doc is None:
        raise HTTPException(status_code=404, detail="no document matches subject")
    return _identified({"query": spec, "totals": totals, **graph_query.export_graph(doc, edges, format)})
