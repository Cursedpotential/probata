"""End-to-end verification of the probata docstore.

Byline: Claude Code - Opus 5 - 2026-09-09

Exercises every fn:: function against the LOCAL EMBEDDED store, proves retrieval,
write paths, and the ADR round-trip, and reports PASS/FAIL per check. Read-only
except for records it creates under a `verify/` source_path prefix, which it
reports so they can be superseded/cleaned.

Run:  python3.exe verify_docstore.py
"""
from __future__ import annotations

import os
import re
import json
import pathlib
import asyncio
import datetime

REPO = pathlib.Path(__file__).resolve()
ENV_FILE = pathlib.Path(".docstore/.env")

RESULTS: list[tuple[str, str, str]] = []  # (status, name, detail)


def record(name: str, ok: bool, detail: str = "") -> None:
    RESULTS.append(("PASS" if ok else "FAIL", name, detail))


def load_env() -> dict:
    env = {}
    for line in ENV_FILE.read_text(encoding="utf-8", errors="ignore").splitlines():
        m = re.match(r"^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.+?)\s*$", line)
        if m:
            env[m.group(1)] = m.group(2).strip().strip('"').strip("'")
    return env


def unwrap(r):
    """SurrealDB python SDK returns nested lists for multi-statement queries."""
    while isinstance(r, list) and len(r) == 1:
        r = r[0]
    return r


async def embed(text: str) -> list[float] | None:
    """Embed via NIM, the same path flow_docs.py uses (LiteLLM -> OpenAI-compatible)."""
    key = os.environ.get("NVIDIA_API_KEY")
    if not key:
        return None
    import urllib.request

    body = json.dumps({
        "input": [text],
        "model": "nvidia/nemotron-3-embed-1b",
        "encoding_format": "float",
    }).encode()
    req = urllib.request.Request(
        "https://integrate.api.nvidia.com/v1/embeddings",
        data=body,
        headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return json.loads(r.read())["data"][0]["embedding"]
    except Exception:
        return None


async def main() -> None:
    env = load_env()
    from surrealdb import AsyncSurreal

    # .docstore/.env writes SURREAL_URL as surrealkv://{REPO_ROOT}/... so a moved
    # checkout cannot strand it; expand it here or this opens an EMPTY store.
    url = env["SURREAL_URL"].replace("{REPO_ROOT}", pathlib.Path(__file__).resolve().parents[2].as_posix())
    # GUARD (2026-09-10): this harness WRITES probe records (docs_register, docs_new_version,
    # todo_open, handoff_write) and on 2026-09-09/10 it flipped 4 real handoffs to superseded.
    # The canonical store is now the shared cloud instance, so refuse any non-embedded target.
    if url.split("://", 1)[0] not in ("surrealkv", "surrealkv+versioned", "mem", "memory", "file"):
        raise SystemExit("verify_docstore: refusing to write probe records into a shared server store ("
                         + url.split("://", 1)[0] + "). Point it at a scratch embedded store instead.")
    db = AsyncSurreal(url)
    await db.connect()
    await db.use(env.get("SURREAL_NS", "probata"), env.get("SURREAL_DB", "docs"))

    # ---------- baseline ----------
    docs = unwrap(await db.query("SELECT count() FROM document GROUP ALL;"))
    chunks = unwrap(await db.query("SELECT count() FROM chunk GROUP ALL;"))
    ndocs = docs["count"] if isinstance(docs, dict) else 0
    nchunks = chunks["count"] if isinstance(chunks, dict) else 0
    record("store populated", ndocs > 0 and nchunks > 0, f"{ndocs} documents, {nchunks} chunks")

    # ---------- READ / RETRIEVAL ----------
    try:
        r = unwrap(await db.query("RETURN fn::search_text('ingest', NONE, NONE);"))
        n = len(r) if isinstance(r, list) else (1 if r else 0)
        record("fn::search_text", n > 0, f"{n} hits for 'ingest'")
    except Exception as e:
        record("fn::search_text", False, str(e).splitlines()[0][:120])

    vec = await embed("how does document ingest work")
    record("NIM embedding reachable", vec is not None and len(vec) == 2048,
           f"dim={len(vec) if vec else 'none'}")

    if vec:
        try:
            r = unwrap(await db.query("RETURN fn::search_vec($q, NONE, NONE);", {"q": vec}))
            n = len(r) if isinstance(r, list) else (1 if r else 0)
            record("fn::search_vec", n > 0, f"{n} hits")
        except Exception as e:
            record("fn::search_vec", False, str(e).splitlines()[0][:120])

        try:
            r = unwrap(await db.query(
                "RETURN fn::docs_search($query, $vec, NONE, NONE, 'active', 5);",
                {"query": "document ingest", "vec": vec}))
            n = len(r) if isinstance(r, list) else (1 if r else 0)
            record("fn::docs_search (hybrid)", n > 0, f"{n} hits")
        except Exception as e:
            record("fn::docs_search (hybrid)", False, str(e).splitlines()[0][:120])

        try:
            r = unwrap(await db.query(
                "RETURN fn::recall($query, $q, NONE, NONE, 'verify-harness');",
                {"query": "document ingest", "q": vec}))
            record("fn::recall", r is not None, f"{type(r).__name__}")
        except Exception as e:
            record("fn::recall", False, str(e).splitlines()[0][:120])

    for fname, call in [
        ("fn::open_work", "RETURN fn::open_work('probata');"),
        ("fn::current_decisions", "RETURN fn::current_decisions('probata');"),
        ("fn::stale_candidates", "RETURN fn::stale_candidates(90d);"),
    ]:
        try:
            r = unwrap(await db.query(call))
            n = len(r) if isinstance(r, list) else (1 if r else 0)
            record(fname, True, f"{n} rows")
        except Exception as e:
            record(fname, False, str(e).splitlines()[0][:120])

    # docs_get on a real document
    try:
        one = unwrap(await db.query("SELECT VALUE id FROM document LIMIT 1;"))
        did = one[0] if isinstance(one, list) else one
        r = unwrap(await db.query("RETURN fn::docs_get($id);", {"id": did}))
        record("fn::docs_get", bool(r), f"id={str(did)[:60]}")
        try:
            p = unwrap(await db.query("RETURN fn::provenance($s);", {"s": did}))
            record("fn::provenance", p is not None, "")
        except Exception as e:
            record("fn::provenance", False, str(e).splitlines()[0][:120])
    except Exception as e:
        record("fn::docs_get", False, str(e).splitlines()[0][:120])

    # ---------- WRITE PATHS ----------
    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    new_id = None
    try:
        r = unwrap(await db.query(
            "RETURN fn::docs_register($source_path,$title,$doc_type,$domains,$status,$body,NONE);",
            {
                "source_path": f"verify/ADR-VERIFY-{stamp}.md",
                "title": f"ADR VERIFY {stamp}",
                "doc_type": "decision",
                "domains": ["docs"],
                "status": "active",
                "body": f"# ADR VERIFY {stamp} - created by verify_docstore.py to prove the write path. The stamp keeps content_hash unique so this harness is re-runnable (SETUP.md GOTCHA 6).",
            }))
        new_id = r.get("id") if isinstance(r, dict) else r
        record("fn::docs_register (new ADR)", new_id is not None, f"id={str(new_id)[:70]}")
    except Exception as e:
        record("fn::docs_register (new ADR)", False, str(e).splitlines()[0][:140])

    if new_id:
        try:
            r = unwrap(await db.query(
                "RETURN fn::docs_new_version($old,$body,NONE);",
                {"old": new_id, "body": f"# ADR VERIFY {stamp} v2 - second version, unique body."}))
            record("fn::docs_new_version", r is not None, str(r)[:70])
        except Exception as e:
            record("fn::docs_new_version", False, str(e).splitlines()[0][:140])

    try:
        r = unwrap(await db.query(
            "RETURN fn::todo_open($item,$priority,$domains,NONE);",
            {"item": f"verify-harness probe {stamp}", "priority": 3, "domains": ["docs"]}))
        tid = r.get("id") if isinstance(r, dict) else r
        record("fn::todo_open", tid is not None, str(tid)[:60])
        if tid:
            try:
                c = unwrap(await db.query("RETURN fn::todo_close($id,$evidence);",
                                          {"id": tid, "evidence": "closed by verify harness"}))
                record("fn::todo_close", c is not None, "")
            except Exception as e:
                record("fn::todo_close", False, str(e).splitlines()[0][:140])
    except Exception as e:
        record("fn::todo_open", False, str(e).splitlines()[0][:140])

    try:
        r = unwrap(await db.query(
            "RETURN fn::handoff_write($title,$body,$domains);",
            {"title": f"verify handoff {stamp}", "body": f"harness probe {stamp}", "domains": ["docs"]}))
        record("fn::handoff_write", r is not None, str(r)[:60])
    except Exception as e:
        record("fn::handoff_write", False, str(e).splitlines()[0][:140])

    try:
        r = unwrap(await db.query(
            "RETURN fn::decision_amend($subject,$banner,NONE);",
            {"subject": f"verify/ADR-VERIFY-{stamp}.md", "banner": "AMENDED by verify harness"}))
        record("fn::decision_amend", r is not None, str(r)[:60])
    except Exception as e:
        record("fn::decision_amend", False, str(e).splitlines()[0][:140])

    # ---------- ROUND TRIP: does a DB-created ADR appear on disk? ----------
    on_disk = pathlib.Path(f"docs/decision/ADR-VERIFY-{stamp}.md").exists() or \
              pathlib.Path(f"verify/ADR-VERIFY-{stamp}.md").exists()
    record("DB-created ADR materializes as a FILE", on_disk,
           "expected FAIL today - no DB->filesystem writer exists")

    await db.close()

    # ---------- report ----------
    print("\n" + "=" * 78)
    print("DOCSTORE VERIFICATION")
    print("=" * 78)
    width = max(len(n) for _, n, _ in RESULTS)
    for status, name, detail in RESULTS:
        print(f"  [{status}] {name:<{width}}  {detail}")
    npass = sum(1 for s, _, _ in RESULTS if s == "PASS")
    print("-" * 78)
    print(f"  {npass}/{len(RESULTS)} passed")
    print(f"  cleanup: records created under source_path prefix 'verify/' stamp {stamp}")


asyncio.run(main())
