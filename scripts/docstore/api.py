"""api - HTTP API over the cloud docstore, for a front end.

Byline: Claude Code - Opus 5 - 2026-09-10

Owner order 2026-09-10: "make sure there's an API exposed so I can put a front end on this."
Runs inside the docstore-worker container (uvicorn --app-dir scripts/docstore api:app), tailnet-only.
Recall, rerank and graph logic live in the same modules the CLI and slash commands use, so the API,
the commands and agents all get identical results.

Endpoints (GET, JSON unless noted):
  /health                                   liveness + store reachability
  /stats                                    document/chunk/edge counts, vector index status
  /recall?q=&kind=doc|adr|handoff|...&k=8&status=active|all&domain=&rerank=true
  /doc/{record_id}                          one document (body included)
  /graph/{ref}?limit=25&format=json|mermaid ref = ADR-NNNN, document:<id>, or a path fragment
Auth: tailnet-only by network; if DOCSTORE_API_TOKEN is set, every route but /health requires
`Authorization: Bearer <token>`.
"""
from __future__ import annotations

import os
import pathlib
import sys

from fastapi import FastAPI, Header, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import PlainTextResponse

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import graph_query  # noqa: E402
import recall as recall_mod  # noqa: E402
import sq  # noqa: E402

TOKEN = os.environ.get("DOCSTORE_API_TOKEN")
app = FastAPI(title="probata docstore API", version="0.1.0")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["GET"], allow_headers=["*"])


def _auth(authorization: str | None) -> None:
    if TOKEN and authorization != f"Bearer {TOKEN}":
        raise HTTPException(status_code=401, detail="missing or wrong bearer token")


def _rows(r):
    while isinstance(r, list) and len(r) == 1 and isinstance(r[0], list):
        r = r[0]
    return r if isinstance(r, list) else ([r] if r else [])


@app.get("/health")
async def health() -> dict:
    try:
        db = await sq.connect("docs", "probata", "docs")
        await db.query("RETURN 1;")
        await db.close()
        return {"ok": True, "store": "up"}
    except Exception as e:  # noqa: BLE001
        return {"ok": False, "store": f"down: {type(e).__name__}"}


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
