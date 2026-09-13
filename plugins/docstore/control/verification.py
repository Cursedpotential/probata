"""Bounded source/store verification. Never imports/starts the CocoIndex flow.

Hash algorithm mirrors flow_docs.py fold_non_bmp at the inspected v6 contract.
Matching hashes do not prove CDC execution or complete fresh embeddings.
"""
from __future__ import annotations

import hashlib
import re
import unicodedata
from datetime import datetime, timezone
from pathlib import Path
from typing import Annotated

from fastmcp.exceptions import ToolError
from pydantic import Field

from governance import query


def fingerprint(content: bytes) -> str:
    text = content.decode("utf-8")
    def fold(match):
        ch = match.group(0)
        try:
            name = unicodedata.name(ch).lower().replace(" ", "_")
        except ValueError:
            name = f"u{ord(ch):04x}"
        return ":" + name + ":"
    folded = re.sub(r"[\U00010000-\U0010ffff]", fold, text)
    return hashlib.sha256(folded.encode("utf-8")).hexdigest()


def read_selected(root: Path, name: str) -> bytes:
    relative = Path(name)
    if relative.is_absolute() or ".." in relative.parts or ":" in name:
        raise ToolError("Only relative Markdown paths within the configured source root")
    path = (root.resolve() / relative).resolve()
    if not path.is_relative_to(root.resolve()) or path.suffix.lower() != ".md":
        raise ToolError("Only Markdown files within the configured source root")
    try:
        info = path.stat()
        if getattr(info, "st_file_attributes", 0) & (0x1000 | 0x40000 | 0x400000):
            raise ToolError("Cloud placeholder not read; hydration was not started")
        if not path.is_file() or info.st_size > 1024 * 1024:
            raise ToolError("Expected regular file no larger than 1 MiB")
        with path.open("rb") as handle:
            content = handle.read(1024 * 1024 + 1)
        if len(content) > 1024 * 1024:
            raise ToolError("File grew beyond verification limit")
        return content
    except OSError:
        raise ToolError("Selected source missing or unreadable; no indexing started") from None


VERIFY_QUERY = """RETURN {
 documents: (SELECT id, source_path, content_hash, status, updated, observed_at FROM document WHERE source_path = $source LIMIT 2),
 chunks: (SELECT id, ordinal, array::len(embedding) AS dimensions, ->chunk_of->document.id AS linked_documents FROM chunk WHERE source_path = $source LIMIT 5001)
};"""


def assess(source: str, expected: str, snapshot: dict) -> dict:
    docs = snapshot.get("documents", [])
    chunks = snapshot.get("chunks", [])
    if (not isinstance(docs, list) or not isinstance(chunks, list)
            or any(not isinstance(row, dict) for row in docs + chunks)):
        raise ToolError("Malformed document/chunk verification response")
    expected_id = "document:" + re.sub(r"[^a-z0-9]+", "_", source.lower()).strip("_")[:120]
    document_state = "missing"
    lifecycle = None
    if len(docs) > 1 or (docs and docs[0].get("id") != expected_id):
        document_state = "identity_conflict"
    elif docs:
        document_state = "hash_match" if docs[0].get("content_hash") == expected else "hash_mismatch"
        lifecycle = docs[0].get("status")
    malformed = sum(c.get("dimensions") != 2048 for c in chunks)
    broken = sum(c.get("linked_documents") != [expected_id] for c in chunks)
    ordinals = [c.get("ordinal") for c in chunks]
    ordinal_error = (any(not isinstance(i, int) for i in ordinals)
                     or sorted(ordinals) != list(range(len(chunks))))
    projection = "absent" if not chunks else "present_unverified"
    if malformed or broken or ordinal_error or len(chunks) > 5000:
        projection = "incomplete"
    return {"source_path": source, "document_status": document_state,
            "expected_hash": expected, "stored_document": docs[0] if len(docs) == 1 else None,
            "projection_status": projection, "chunk_count_observed": len(chunks),
            "invalid_embedding_dimensions": malformed, "broken_document_links": broken,
            "chunk_result_truncated": len(chunks) > 5000,
            "active_search_eligible": lifecycle == "active", "stored_lifecycle": lifecycle,
            "cdc_execution": "unproven", "exact_projection_freshness": "unproven",
            "reason": "Current worker has no durable correlated per-document CDC receipt; hash agreement is not execution proof"}


async def verify(config, paths: list[str], execute=query):
    if not 1 <= len(paths) <= 20:
        raise ToolError("Verification accepts 1 to 20 explicit paths")
    if execute is query:
        from governance import native_client
        from functools import partial
        async with native_client(config) as client:
            return await verify(config, paths, execute=partial(query, client=client))
    files = []
    for name in paths:
        content = read_selected(config.source_root, name)
        try:
            expected = fingerprint(content)
        except UnicodeDecodeError:
            raise ToolError("Source is not UTF-8; cannot reproduce worker fingerprint") from None
        source = "docs/" + Path(name).as_posix()
        result = await execute(config, VERIFY_QUERY, {"source": source})
        if isinstance(result, list) and len(result) == 1:
            result = result[0]
        if not isinstance(result, dict):
            raise ToolError("Unexpected verification response")
        files.append(assess(source, expected, result))
    return {"checked_at": datetime.now(timezone.utc).isoformat(), "files": files,
            "fingerprint_profile": "docstore-fold-non-bmp-v1", "namespace": "probata", "database": "docs",
            "indexing_triggered": False, "worker_started": False, "all_cdc_verified": False}


def register(mcp, config, read_annotations):
    @mcp.tool(annotations={**read_annotations, "title": "Verify document indexing"})
    async def docstore_verify_index(paths: Annotated[list[str], Field(min_length=1, max_length=20)]) -> dict:
        """Compare selected source fingerprints with stored documents/chunks; reports lag without running CDC or claiming execution proof."""
        return await verify(config, paths)
