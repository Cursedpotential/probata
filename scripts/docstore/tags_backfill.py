"""Backfill document.tags for already-indexed files without re-embedding.

Byline: Claude Code · Fable 5.1 · 2026-09-14 — owner: "would a rerank do the old docs?"
No: a reranker reorders results. This reads every file the registry declares, computes
author tags exactly as flow_docs.extract_tags does, and writes ONLY rows whose stored tags
differ, through fn::docs_set_tags (governed metadata write; content, hash, status untouched).

Env (same as the worker): DOCSTORE_PROJECT_REGISTRY, DOCSTORE_MULTI_ROOT_ENABLED, SURREAL_*.
Usage inside the worker container:  python scripts/docstore/tags_backfill.py [--dry-run]
"""
from __future__ import annotations

import asyncio
import os
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from source_registry import load_sources  # noqa: E402
from cdc_verify import _fold_non_bmp, _matches, _slug, decode_markdown  # noqa: E402

# Mirror of flow_docs.extract_tags. Not imported: importing flow_docs runs the flow's
# module-level environment setup, which a metadata script must never trigger.
_TAG_TOKEN_RE = re.compile(r"[^a-z0-9]+")
_FRONT_MATTER_RE = re.compile(r"\A﻿?---\r?\n(.*?)\r?\n---", re.S)
_TAGS_COMMENT_RE = re.compile(r"<!--\s*tags:\s*([^>]*?)\s*-->", re.I)


def extract_tags(body: str, limit: int = 32) -> list[str]:
    """Mirror of flow_docs.extract_tags. Author tags the pipeline carries into document.tags (owner 2026-09-14: 'tag or
    label things so they pop up when searching or working on UI components').
    Sources, both optional: YAML front matter `tags: [a, b]` or a dash list, and an
    HTML comment `<!-- tags: a, b -->` anywhere in the body. Lower-kebab, de-duplicated."""
    found: list[str] = []
    fm = _FRONT_MATTER_RE.match(body)
    if fm:
        block = fm.group(1)
        m = re.search(r"(?m)^tags:\s*\[(.*?)\]\s*$", block)
        if m:
            found += [t.strip().strip("'\"") for t in m.group(1).split(",")]
        else:
            m = re.search(r"(?m)^tags:\s*$((?:\r?\n\s*-\s*.*)+)", block)
            if m:
                found += [ln.split("-", 1)[1].strip().strip("'\"") for ln in m.group(1).splitlines() if "-" in ln]
    for m in _TAGS_COMMENT_RE.finditer(body):
        found += [t.strip() for t in m.group(1).split(",")]
    out: list[str] = []
    for raw in found:
        tag = _TAG_TOKEN_RE.sub("-", raw.lower()).strip("-")
        if tag and tag not in out:
            out.append(tag)
    return out[:limit]





async def main(dry_run: bool) -> int:
    import sq
    here = Path(__file__).resolve().parent
    registry = Path(os.environ["DOCSTORE_PROJECT_REGISTRY"]) if os.environ.get("DOCSTORE_PROJECT_REGISTRY") else None
    sources, _ = load_sources(registry, here.parents[1] / "docs",
                              multi_root_enabled=os.environ.get("DOCSTORE_MULTI_ROOT_ENABLED", "").strip() == "1")
    wanted: dict[str, list[str]] = {}
    for source in sources:
        for path in source.root.rglob("*.md"):
            if not path.is_file() or path.is_symlink():
                continue
            rel = path.relative_to(source.root).as_posix()
            if not _matches(rel, source):
                continue
            body = _fold_non_bmp(decode_markdown(path.read_bytes()))
            tags = extract_tags(body)
            if tags:
                wanted[_slug(_fold_non_bmp(source.canonical_prefix + rel))] = tags
    db = await sq.connect("docs", "probata", "docs")
    try:
        rows = await db.query("SELECT record::id(id) AS rid, tags FROM document;")
        while isinstance(rows, list) and len(rows) == 1 and isinstance(rows[0], list):
            rows = rows[0]
        have = {r["rid"]: list(r.get("tags") or []) for r in rows if isinstance(r, dict) and isinstance(r.get("rid"), str)}
        changed = 0
        missing = 0
        for rid, tags in sorted(wanted.items()):
            if rid not in have:
                missing += 1
                continue
            if have[rid] == tags:
                continue
            changed += 1
            print(("DRY " if dry_run else "SET ") + rid + " <- " + ",".join(tags))
            if not dry_run:
                await db.query("RETURN fn::docs_set_tags(type::record('document', $rid), $tags, 'tags_backfill');",
                               {"rid": rid, "tags": tags})
        print(f"files with author tags: {len(wanted)} | rows updated: {changed} | tagged files not yet indexed: {missing}")
    finally:
        await db.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main("--dry-run" in sys.argv)))
