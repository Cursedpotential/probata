"""recall - hybrid recall over the cloud docstore: keyword + vector legs, RRF fusion, Voyage rerank.

Byline: Claude Code - Opus 5 - 2026-09-10

Owner orders 2026-09-10: "/recall doc", "/recall adr" pull the answer up; results compact, no noise;
all processing happens inside the tool; add a reranker. Backs the docstore plugin commands and the
worker HTTP API (import `recall()`).

Pipeline (all inside this tool, the caller only sees the final table or JSON):
  1. keyword leg  - chunk-level BM25 (chunk_text_ft), filler words stripped (the index ANDs every term)
  2. vector leg   - query embedded with NIM nemotron-3-embed-1b (runs concurrently with step 1),
                    chunk-level HNSW KNN
  3. fusion       - each document's best chunk per leg, reciprocal-rank fused (k=60)
  4. rerank       - top 25 candidates re-scored against title + best chunk: NIM llama-nemotron-rerank-vl-1b-v2
                    (primary, D-158), Voyage rerank-2.5 fallback
Chunk-level legs matter: document-level BM25 lets long hub docs match every question.
fn::docs_search is not used: it adds raw BM25 (5-10) to cosine similarity (<=1), so vectors never move it.

Usage:
  python scripts/docstore/recall.py doc "what did we decide about migrations"
  python scripts/docstore/recall.py adr "surreal as analysis engine" --k 5 --why
  python scripts/docstore/recall.py handoff "docstore rebuild" --status all --json
"""
from __future__ import annotations

import argparse
import asyncio
import json
import math
import os
import pathlib
import re
import sys
import time
import types
import urllib.error
import urllib.request

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import sq  # noqa: E402  (same directory: connect, render, env parsing)

KINDS = {"doc": None, "adr": "decision", "decision": "decision", "handoff": "handoff", "todo": "todo",
         "review": "review", "blueprint": "blueprint", "reference": "reference", "infrastructure": "infrastructure"}
RRF_K = 60
RERANK_POOL = 25
STOPWORDS = set("""a an and are as at be been but by can could did do does for from had has have how i if in into
is it its me my no not of on or our should so than that the their them then there these they this to was we were
what when where which who why will with would you your about any all also just more most other over same some such
only very""".split())


def _secret(name: str) -> str | None:
    if os.environ.get(name):
        return os.environ[name]
    for f in sorted((pathlib.Path.home() / ".secrets").glob("*.env")):
        v = sq._env(f).get(name)
        if v:
            return v
    return None


def embed(text: str) -> list[float]:
    key = _secret("NVIDIA_API_KEY") or _secret("NVIDIA_NIM_API_KEY")
    if not key:
        raise RuntimeError("NVIDIA_API_KEY not set (needed to embed the question)")
    req = urllib.request.Request(
        "https://integrate.api.nvidia.com/v1/embeddings",
        data=json.dumps({"model": "nvidia/nemotron-3-embed-1b", "input": [text], "encoding_format": "float"}).encode(),
        headers={"Authorization": "Bearer " + key, "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)["data"][0]["embedding"]


LAST_RERANK_NOTE: str | None = None
LAST_RERANKER: str | None = None
NIM_RERANK_MODEL = "nvidia/llama-nemotron-rerank-vl-1b-v2"


def _nim_rerank(query: str, docs: list[str]):
    """NIM reranker. Rerankers are NOT in /models: each lives on its own retrieval endpoint (dots ->
    underscores). llama-nemotron-rerank-vl-1b-v2 verified live 2026-09-10: ~260 ms, 10240-token
    query+passage ceiling. Logits are mapped to 0..1 with a sigmoid."""
    key = _secret("NVIDIA_API_KEY") or _secret("NVIDIA_NIM_API_KEY")
    if not key:
        return None, "no NVIDIA_API_KEY"
    url = "https://ai.api.nvidia.com/v1/retrieval/" + NIM_RERANK_MODEL.replace(".", "_") + "/reranking"
    body = json.dumps({"model": NIM_RERANK_MODEL, "query": {"text": query},
                       "passages": [{"text": d} for d in docs], "truncate": "END"}).encode()
    req = urllib.request.Request(url, data=body, headers={"Authorization": "Bearer " + key,
                                 "Content-Type": "application/json", "Accept": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            ranks = json.load(r)["rankings"]
        return [(x["index"], 1.0 / (1.0 + math.exp(-x["logit"]))) for x in ranks], None
    except urllib.error.HTTPError as e:
        return None, f"nim HTTP {e.code}"
    except (urllib.error.URLError, KeyError, ValueError) as e:
        return None, f"nim {type(e).__name__}"


def _voyage_rerank(query: str, docs: list[str]):
    """Voyage rerank-2.5 fallback. Free tier rate-limits bursts: one retry on 429 after Retry-After (<=5 s)."""
    key = _secret("VOYAGE_API_KEY")
    if not key:
        return None, "no VOYAGE_API_KEY"
    body = json.dumps({"query": query, "documents": docs, "model": "rerank-2.5", "top_k": len(docs),
                       "truncation": True}).encode()
    note = None
    for attempt in (1, 2):
        req = urllib.request.Request("https://api.voyageai.com/v1/rerank", data=body,
                                     headers={"Authorization": "Bearer " + key, "Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                return [(d["index"], d["relevance_score"]) for d in json.load(r)["data"]], None
        except urllib.error.HTTPError as e:
            note = f"voyage HTTP {e.code}"
            if e.code == 429 and attempt == 1:
                try:
                    time.sleep(min(float(e.headers.get("Retry-After", "2")), 5.0))
                except ValueError:
                    time.sleep(2.0)
                continue
            return None, note
        except (urllib.error.URLError, KeyError, ValueError) as e:
            return None, f"voyage {type(e).__name__}"
    return None, note


def rerank(query: str, docs: list[str]) -> list[tuple[int, float]] | None:
    """NIM first (D-158: NIM is the provider; fast; no free-tier limit), Voyage as fallback.
    Returns [(index, score 0..1)] best-first, or None with the reason in LAST_RERANK_NOTE."""
    global LAST_RERANK_NOTE, LAST_RERANKER
    LAST_RERANK_NOTE = LAST_RERANKER = None
    if not docs:
        return None
    order, nim_note = _nim_rerank(query, docs)
    if order:
        LAST_RERANKER = "nim rerank-vl-1b-v2"
        return order
    order, voyage_note = _voyage_rerank(query, docs)
    if order:
        LAST_RERANKER, LAST_RERANK_NOTE = "voyage rerank-2.5", nim_note
        return order
    LAST_RERANK_NOTE = "; ".join(n for n in (nim_note, voyage_note) if n)
    return None


def _rows(r):
    while isinstance(r, list) and len(r) == 1 and isinstance(r[0], list):
        r = r[0]
    return r if isinstance(r, list) else ([r] if r else [])


def keyword_terms(query: str) -> str:
    terms = [t for t in re.findall(r"[A-Za-z0-9][A-Za-z0-9_.-]*", query) if t.lower() not in STOPWORDS]
    return " ".join(terms) or query


async def recall(query: str, kind: str = "doc", status: str = "active", k: int = 8, domain: str | None = None,
                 use_rerank: bool = True) -> tuple[list[dict], dict]:
    doc_type = KINDS[kind]
    t0 = time.perf_counter()
    status_arg = None if status == "all" else status
    filters = (["status = $st"] if status_arg else []) + (["doc_type = $dt"] if doc_type else []) + \
              (["$dom INSIDE domains"] if domain else [])
    extra = "".join(" AND " + f for f in filters)
    params = {"st": status_arg, "dt": doc_type, "dom": domain, "q": keyword_terms(query)}

    db = await sq.connect("docs", "probata", "docs")
    embed_task = asyncio.create_task(asyncio.to_thread(embed, query))
    kw = _rows(await db.query(
        "SELECT id, text, search::score(1) AS score, (->chunk_of->document)[0] AS doc FROM chunk "
        "WHERE text @1@ $q" + extra + " ORDER BY score DESC LIMIT 80;", params))
    kw_mode = "all-terms"
    terms = params["q"].split()
    if len({str(c["doc"]) for c in kw if c.get("doc") is not None}) < 3 and len(terms) > 1:
        # The BM25 index ANDs every term; a single OR query scores ~10k chunks (4.4 s), so run each
        # term separately (fast, indexed) and sum scores per chunk instead.
        merged = {str(c["id"]): dict(c) for c in kw}
        for term in terms:
            for c in _rows(await db.query(
                    "SELECT id, text, search::score(1) AS score, (->chunk_of->document)[0] AS doc FROM chunk "
                    "WHERE text @1@ $t" + extra + " ORDER BY score DESC LIMIT 30;", dict(params, t=term))):
                key = str(c["id"])
                if key in merged:
                    merged[key]["score"] += c["score"]
                else:
                    merged[key] = dict(c)
        kw = list(merged.values())
        kw_mode = "any-term"
    params["v"] = await embed_task
    vec = _rows(await db.query(
        "SELECT id, text, vector::distance::knn() AS dist, (->chunk_of->document)[0] AS doc FROM chunk "
        "WHERE embedding <|80,200|> $v" + extra + " ORDER BY dist;", params))
    t_search = time.perf_counter()

    def best(chunks, better):
        out = {}
        for c in chunks:
            if c.get("doc") is None:
                continue
            key = str(c["doc"])
            if key not in out or better(c, out[key]):
                out[key] = c
        return out

    kw_best = best(kw, lambda a, b: a["score"] > b["score"])
    vec_best = best(vec, lambda a, b: a["dist"] < b["dist"])
    kw_rank = {key: i for i, key in enumerate(sorted(kw_best, key=lambda x: -kw_best[x]["score"]), 1)}
    vec_rank = {key: i for i, key in enumerate(sorted(vec_best, key=lambda x: vec_best[x]["dist"]), 1)}

    pool = []
    for key in set(kw_rank) | set(vec_rank):
        rrf = sum(1.0 / (RRF_K + r[key]) for r in (kw_rank, vec_rank) if key in r)
        src = vec_best.get(key) or kw_best.get(key)
        pool.append({"key": key, "doc": src["doc"], "rrf": rrf, "kw": kw_rank.get(key), "vec": vec_rank.get(key),
                     "text": str(src.get("text") or "")})
    pool.sort(key=lambda e: -e["rrf"])
    pool = pool[:max(RERANK_POOL, k)]

    meta = {}
    if pool:
        docs = _rows(await db.query("SELECT id, source_path, title, doc_type, status FROM $ids;",
                                    {"ids": [e["doc"] for e in pool]}))
        meta = {str(d["id"]): d for d in docs}
    await db.close()

    reranked = False
    if use_rerank and pool:
        order = rerank(query, [f"{meta.get(e['key'], {}).get('title', '')}\n{e['text'][:1500]}" for e in pool])
        if order:
            for idx, score in order:
                pool[idx]["score"] = score
            pool.sort(key=lambda e: -e.get("score", -1))
            reranked = True
    for e in pool:
        e.setdefault("score", e["rrf"])

    results = []
    for i, e in enumerate(pool[:k], 1):
        m = meta.get(e["key"], {})
        results.append({
            "rank": i,
            "score": round(float(e["score"]), 3),
            "title": m.get("title") or "",
            "type": m.get("doc_type"),
            "status": m.get("status"),
            "path": (m.get("source_path") or "").removeprefix("docs/"),
            "via": "+".join(n for n, r in (("kw", e["kw"]), ("vec", e["vec"])) if r),
            "snippet": " ".join(e["text"].split())[:300],
            "id": e["key"],
        })
    stats = {"ms": round((time.perf_counter() - t0) * 1000), "search_ms": round((t_search - t0) * 1000),
             "kw_docs": len(kw_best), "vec_docs": len(vec_best), "reranked": reranked,
             "keyword_query": params["q"], "kw_mode": kw_mode, "rerank_note": LAST_RERANK_NOTE, "reranker": LAST_RERANKER}
    return results, stats


def _clip(s: str, n: int) -> str:
    return s if len(s) <= n else s[: n - 1] + "…"


def main() -> int:
    ap = argparse.ArgumentParser(description="Hybrid recall over the cloud docstore.")
    ap.add_argument("kind", choices=sorted(KINDS), help="doc = any type; adr = decision documents; or a doc_type")
    ap.add_argument("query", nargs="+")
    ap.add_argument("--k", type=int, default=8)
    ap.add_argument("--status", default="active", help="active (default), all, superseded, unverified, proposed")
    ap.add_argument("--domain", default=None)
    ap.add_argument("--no-rerank", action="store_true")
    ap.add_argument("--why", action="store_true", help="show the matching passage instead of type/via")
    ap.add_argument("--json", action="store_true", help="machine-readable output (API, agents)")
    a = ap.parse_args()
    query = " ".join(a.query)
    results, stats = asyncio.run(recall(query, a.kind, a.status, a.k, a.domain, not a.no_rerank))
    if a.json:
        print(json.dumps({"query": query, "kind": a.kind, "results": results, "stats": stats}, ensure_ascii=False))
        return 0
    if a.why:
        rows = [{"#": r["rank"], "score": r["score"], "title": _clip(r["title"], 50), "status": r["status"],
                 "passage": _clip(r["snippet"], 110)} for r in results]
    else:
        rows = [{"#": r["rank"], "score": r["score"], "title": _clip(r["title"], 58), "type": r["type"],
                 "status": r["status"], "path": _clip(r["path"], 52), "via": r["via"]} for r in results]
    view = types.SimpleNamespace(sql=None, width=400, cell=120, max_rows=a.k, show_hidden=False)
    sq.render(rows, view)
    print(f"[{stats['ms']} ms | kw {stats['kw_docs']} docs \"{stats['keyword_query']}\" | vec {stats['vec_docs']} docs"
          f" | {'reranked ' + str(stats['reranker']) if stats['reranked'] else 'RRF only: ' + str(stats['rerank_note'])}]")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
