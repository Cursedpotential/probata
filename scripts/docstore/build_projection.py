"""build_projection.py — registry-driven projection builder for the Docstore worker.

Replaces the ad-hoc scratchpad script that first built this projection by hand. Walks
every ACTIVE, non-excluded root in a docstore-source-registry.json (all six Propria
roots, not just the one flagged current-full-source -- the projection is the complete
multi-root corpus the worker will eventually read from `/exchange/sources`), and for
each `*.md` file:

    1. decode with cdc_verify.decode_markdown on the raw bytes (no newline translation
       -- CRLF survives verbatim, exactly like FileLike.read() in flow_docs.py)
    2. fold non-BMP characters the same way flow_docs.fold_non_bmp does
    3. OMIT the file if it is empty after that fold+strip (the flow silently skips
       empty files; a copy that isn't skipped would be a permanent phantom document)
    4. OMIT the file if its folded content is byte-identical (sha256) to a file
       already kept elsewhere in the projection (document.content_hash is UNIQUE
       across the whole store) -- every omission is recorded in
       docstore-projection-duplicates.json beside the container registry copy
    5. otherwise write the folded text, re-encoded as UTF-8, at the SAME path the
       file has relative to the registry's monorepo_root (so the container registry
       copy, with monorepo_root replaced by --container-root, resolves every
       project's source_root to exactly where this script put it)

No CocoIndex import: this runs on the desktop, not inside the worker container.

Usage:
    python3 build_projection.py --registry <path> [--out-dir <dir>] \\
        [--container-root /exchange/sources] [--push]

Default is a DRY RUN: it builds the projection under --out-dir (a fresh temp
directory if omitted) and prints per-root counts. --push additionally scp's the
built projection to the worker host and swaps it in; nothing pushes without that
flag, and this script never invokes --push on its own.

Byline: Claude Code · Sonnet 5 · 2026-09-14
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import sys
import tarfile
import tempfile
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

from source_registry import SourceSpec, load_sources  # noqa: E402
from cdc_verify import decode_markdown, _fold_non_bmp, _matches  # noqa: E402

BYLINE = "Claude Code · Sonnet 5 · 2026-09-14"

REMOTE_HOST = "root@100.91.190.107"
REMOTE_BASE = "/data/probata/exchange/docstore-worker"
SSH_KEY = "~/.ssh/ovh"


def _read_monorepo_root(registry_path: Path) -> Path:
    payload = json.loads(registry_path.read_bytes())
    value = payload.get("monorepo_root")
    if not isinstance(value, str) or not Path(value).is_absolute():
        raise ValueError("monorepo_root must be absolute")
    return Path(value).resolve(strict=True)


def iter_source_files(source: SourceSpec) -> list[tuple[Path, str]]:
    if not source.root.is_dir():
        return []
    out: list[tuple[Path, str]] = []
    for path in sorted(source.root.rglob("*.md")):
        if not path.is_file() or path.is_symlink():
            continue
        relative = path.relative_to(source.root).as_posix()
        if not _matches(relative, source):
            continue
        out.append((path, relative))
    return out


def build_projection(registry_path: Path, out_dir: Path, container_root: str) -> dict:
    monorepo_root = _read_monorepo_root(registry_path)
    # multi_root_enabled=True deliberately: the projection is the complete corpus for
    # every active root, independent of which single root the live flow currently
    # treats as current-full-source. "excluded" roots are dropped by load_sources
    # itself, before this ever sees them.
    sources, _ = load_sources(registry_path, Path("."), multi_root_enabled=True)
    out_dir.mkdir(parents=True, exist_ok=True)

    hash_index: dict[str, str] = {}
    duplicates: list[dict] = []
    per_root: dict[str, dict] = {}
    total_kept = 0

    for source in sources:
        if not source.root.is_relative_to(monorepo_root):
            raise ValueError(f"{source.project_id}: source root escapes monorepo_root")
        source_relative = source.root.relative_to(monorepo_root)
        stats = {"files": 0, "kept": 0, "omitted_empty": 0, "omitted_dup": 0}

        for fs_path, relative in iter_source_files(source):
            stats["files"] += 1
            raw = fs_path.read_bytes()
            text = decode_markdown(raw)
            folded = _fold_non_bmp(text)
            display = (source_relative / relative).as_posix()

            if not folded.strip():
                stats["omitted_empty"] += 1
                continue

            digest = hashlib.sha256(folded.encode("utf-8")).hexdigest()
            if digest in hash_index:
                stats["omitted_dup"] += 1
                duplicates.append({"skipped": display, "kept": hash_index[digest], "sha256_folded": digest})
                continue
            hash_index[digest] = display

            dest = out_dir / source_relative / relative
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes(folded.encode("utf-8"))
            stats["kept"] += 1
            total_kept += 1

        per_root[source.project_id] = stats

    duplicates_path = out_dir / "docstore-projection-duplicates.json"
    duplicates_path.write_text(
        json.dumps({"byline": BYLINE, "omitted_duplicates": duplicates}, indent=1, ensure_ascii=False),
        encoding="utf-8",
    )

    container_registry = json.loads(registry_path.read_bytes())
    container_registry["monorepo_root"] = container_root
    container_registry["projection"] = {
        "built_at_utc": datetime.now(timezone.utc).isoformat(),
        "built_by": BYLINE,
        "desktop_root": str(monorepo_root),
        "policy": (
            "complete source projection for multi-root CocoIndex; empty files omitted; "
            "byte-identical files after the first occurrence omitted (document.content_hash "
            "is UNIQUE) and listed in docstore-projection-duplicates.json; rebuild and "
            "re-push to refresh (no automatic sync yet)"
        ),
    }
    (out_dir / "docstore-source-registry.json").write_text(
        json.dumps(container_registry, indent=2, ensure_ascii=False), encoding="utf-8"
    )

    return {
        "out_dir": str(out_dir),
        "container_root": container_root,
        "total_kept": total_kept,
        "total_duplicates": len(duplicates),
        "per_root": per_root,
    }


def push_projection(out_dir: Path) -> dict:
    """scp the built projection to the worker host and swap it in. Never called
    unless --push is passed explicitly on the command line -- see the module
    docstring. On Windows Git-Bash, run this with MSYS_NO_PATHCONV=1 so the
    /unix/paths in the ssh/scp commands are not mangled into Windows paths."""
    ts = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    archive = Path(tempfile.gettempdir()) / f"docstore-projection-{ts}.tgz"
    with tarfile.open(archive, "w:gz") as tar:
        tar.add(out_dir, arcname=".")

    remote_archive = f"{REMOTE_BASE}/projection-{ts}.tgz"
    remote_new = f"{REMOTE_BASE}/sources.new"
    remote_current = f"{REMOTE_BASE}/sources"
    remote_prev = f"{REMOTE_BASE}/sources.prev-{ts}"

    subprocess.run(["scp", "-i", os.path.expanduser(SSH_KEY), str(archive),
                    f"{REMOTE_HOST}:{remote_archive}"], check=True)
    remote_script = (
        f"mkdir -p {remote_new} && tar -xzf {remote_archive} -C {remote_new} && "
        f"if [ -d {remote_current} ]; then mv {remote_current} {remote_prev}; fi && "
        f"mv {remote_new} {remote_current}"
    )
    subprocess.run(["ssh", "-i", os.path.expanduser(SSH_KEY), REMOTE_HOST, remote_script], check=True)
    return {"pushed": True, "remote_archive": remote_archive, "swapped_to": remote_current,
            "previous_kept_at": remote_prev, "timestamp": ts}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Build the Docstore multi-root projection")
    parser.add_argument("--registry", required=True, help="path to docstore-source-registry.json")
    parser.add_argument("--out-dir", help="output directory (default: a fresh temp dir)")
    parser.add_argument("--container-root", default="/exchange/sources",
                         help="monorepo_root written into the container registry copy")
    parser.add_argument("--push", action="store_true",
                         help="scp the built projection to the worker host and swap it in (default: dry run)")
    args = parser.parse_args(argv)

    registry_path = Path(args.registry).resolve(strict=True)
    out_dir = Path(args.out_dir).resolve() if args.out_dir else Path(
        tempfile.mkdtemp(prefix="docstore-projection-")
    )

    result = build_projection(registry_path, out_dir, args.container_root)

    print(f"Docstore projection built at {result['out_dir']} (container_root={result['container_root']})")
    header = f"{'project':30} {'files':>7} {'kept':>7} {'omit_empty':>11} {'omit_dup':>9}"
    print(header)
    totals = {"files": 0, "kept": 0, "omitted_empty": 0, "omitted_dup": 0}
    for project_id, stats in result["per_root"].items():
        print(f"{project_id:30} {stats['files']:>7} {stats['kept']:>7} "
              f"{stats['omitted_empty']:>11} {stats['omitted_dup']:>9}")
        for key in totals:
            totals[key] += stats[key]
    print(f"{'TOTAL':30} {totals['files']:>7} {totals['kept']:>7} "
          f"{totals['omitted_empty']:>11} {totals['omitted_dup']:>9}")
    print(f"duplicate pairs recorded: {result['total_duplicates']}")

    if args.push:
        pushed = push_projection(out_dir)
        print(json.dumps(pushed))
    else:
        print("dry run: pass --push to scp this projection to "
              f"{REMOTE_HOST}:{REMOTE_BASE}/ and swap it in (never automatic)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
