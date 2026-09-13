"""Exact source-to-Surreal attribution for a completed Docstore run.

This module deliberately contains no CocoIndex imports.  The worker snapshots the
complete declared source before execution and proves the same snapshot against the
stored document projection afterwards.  A selected request still executes the
complete source; selection only narrows the caller's requested verification set.
"""
from __future__ import annotations

import fnmatch
import hashlib
import os
import unicodedata
from dataclasses import dataclass
from pathlib import Path

from source_registry import SourceSpec, load_sources


@dataclass(frozen=True)
class SourceDocument:
    project_id: str
    source_path: str
    content_hash: str


def _fold_non_bmp(value: str) -> str:
    """Mirror flow_docs.fold_non_bmp without importing the CocoIndex graph."""
    folded: list[str] = []
    for char in value:
        if ord(char) <= 0xFFFF:
            folded.append(char)
            continue
        try:
            folded.append(":" + unicodedata.name(char).lower().replace(" ", "_") + ":")
        except ValueError:
            folded.append(f":u{ord(char):04x}:")
    return "".join(folded)


def _matches(relative: str, source: SourceSpec) -> bool:
    def match(pattern: str) -> bool:
        return fnmatch.fnmatchcase(relative, pattern) or (
            pattern.startswith("**/") and fnmatch.fnmatchcase(relative, pattern[3:])
        )
    included = any(match(pattern) for pattern in source.included_patterns)
    excluded = any(match(pattern) for pattern in source.excluded_patterns)
    return included and not excluded


def snapshot_sources() -> tuple[tuple[SourceDocument, ...], str]:
    here = Path(__file__).resolve().parent
    repo_root = here.parents[1]
    registry = Path(os.environ["DOCSTORE_PROJECT_REGISTRY"]) if os.environ.get("DOCSTORE_PROJECT_REGISTRY") else None
    sources, _ = load_sources(
        registry,
        repo_root / "docs",
        multi_root_enabled=os.environ.get("DOCSTORE_MULTI_ROOT_ENABLED", "").strip() == "1",
    )
    rows: list[SourceDocument] = []
    for source in sources:
        if not source.root.is_dir():
            continue
        for path in source.root.rglob("*.md"):
            if not path.is_file() or path.is_symlink():
                continue
            relative = path.relative_to(source.root).as_posix()
            if not _matches(relative, source):
                continue
            body = _fold_non_bmp(path.read_text(encoding="utf-8"))
            rows.append(SourceDocument(
                project_id=source.project_id,
                source_path=source.canonical_prefix + relative,
                content_hash=hashlib.sha256(body.encode("utf-8")).hexdigest(),
            ))
    rows.sort(key=lambda row: row.source_path)
    if not rows:
        raise RuntimeError("Declared Docstore source snapshot is empty")
    if len({row.source_path for row in rows}) != len(rows):
        raise RuntimeError("Declared Docstore source paths collide")
    digest = hashlib.sha256("".join(
        f"{row.project_id}\0{row.source_path}\0{row.content_hash}\n" for row in rows
    ).encode("utf-8")).hexdigest()
    return tuple(rows), digest


async def verify_projection(expected: tuple[SourceDocument, ...]) -> dict:
    import sq

    db = await sq.connect("docs", "probata", "docs")
    try:
        result = await db.query("SELECT source_path, content_hash FROM document;")
    finally:
        await db.close()
    while isinstance(result, list) and len(result) == 1 and isinstance(result[0], list):
        result = result[0]
    records = result if isinstance(result, list) else []
    expected_by_path = {row.source_path: row.content_hash for row in expected}
    prefixes = tuple(sorted({row.source_path.split("/", 1)[0] + "/" for row in expected}))
    observed = {
        str(row.get("source_path")): str(row.get("content_hash"))
        for row in records if isinstance(row, dict)
        and isinstance(row.get("source_path"), str)
        and row["source_path"].startswith(prefixes)
    }
    missing = sorted(set(expected_by_path) - set(observed))
    unexpected = sorted(set(observed) - set(expected_by_path))
    mismatched = sorted(path for path in set(expected_by_path) & set(observed)
                        if expected_by_path[path] != observed[path])
    verified = not missing and not unexpected and not mismatched
    return {
        "status": "verified" if verified else "mismatch",
        "expected_documents": len(expected_by_path),
        "observed_documents": len(observed),
        "missing_count": len(missing),
        "unexpected_count": len(unexpected),
        "hash_mismatch_count": len(mismatched),
        "missing_sample": missing[:20],
        "unexpected_sample": unexpected[:20],
        "hash_mismatch_sample": mismatched[:20],
    }


async def retire_unexpected_projection(expected: tuple[SourceDocument, ...]) -> dict:
    """Retire only stored document/chunk identities absent from the complete source."""
    import sq
    expected_paths = {row.source_path for row in expected}
    prefixes = tuple(sorted({row.source_path.split("/", 1)[0] + "/" for row in expected}))
    db = await sq.connect("docs", "probata", "docs")
    try:
        result = await db.query("SELECT VALUE source_path FROM document;")
        while isinstance(result, list) and len(result) == 1 and isinstance(result[0], list):
            result = result[0]
        observed = {str(path) for path in (result if isinstance(result, list) else [])
                    if isinstance(path, str) and path.startswith(prefixes)}
        unexpected = sorted(observed - expected_paths)
        if len(unexpected) > 1000:
            raise RuntimeError("Unexpected projection retirement exceeds safety bound")
        if unexpected:
            await db.query("""
BEGIN TRANSACTION;
DELETE chunk_of WHERE in.source_path IN $paths OR out.source_path IN $paths;
DELETE links_to WHERE in.source_path IN $paths OR out.source_path IN $paths;
DELETE cites WHERE in.source_path IN $paths OR out.source_path IN $paths;
DELETE supersedes WHERE in.source_path IN $paths OR out.source_path IN $paths;
DELETE chunk WHERE source_path IN $paths;
DELETE document WHERE source_path IN $paths;
COMMIT TRANSACTION;
""", {"paths": unexpected})
        return {"retired_count": len(unexpected), "retired_paths": unexpected}
    finally:
        await db.close()
