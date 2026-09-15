"""docs_lint.py — normalization/validation linter for Docstore markdown sources.

Checks the same registry roots the CocoIndex flow (flow_docs.py) will read, reusing
the identical decode / fold / hash / glob logic from cdc_verify.py so a finding here
predicts a flow outcome exactly (an ENC001 file decodes the same way, a DUP001 pair
collides on the same content_hash, a PATH001 file gets the same digest slug).

No CocoIndex import anywhere in this module: it must run on the desktop (the
build_projection.py CLI) and inside the worker's pre-run snapshot (worker_sync.py
calls lint_summary_from_env() before flow_docs.py starts).

Checks (code -> default severity):
    ENC001      error    file is not valid UTF-8 (would decode via the cp1252 fallback)
    EMPTY001    error    empty after decode + fold + strip (the flow silently skips it)
    DUP001      error    byte-identical content (post decode+fold, sha256) at >1 path
    PATH001     error    the record-id slug for this source_path would exceed 120 chars
    BLOCK001    error    path matches a registry blocked_patterns entry (see below)
    TAGS001     warning  no tags: neither front-matter `tags:` nor `<!-- tags: ... -->`
    BYLINE001   warning  no `Byline:` marker found in the body
    NBMP001     warning  a non-BMP character in the path or the body
    JUNK001     warning  path passes through a memory/junk folder (.remember, node_modules, ...)
    DATAURI001  warning  a `data:...;base64,` payload in the body
    SIZE001     dual     >= --max-warn-bytes is a warning, >= --max-error-bytes is an error
                         (both apply to raw file bytes; message carries the size and an
                         estimated chunk count at flow_docs.py's chunk size)

BLOCK001 is defense-in-depth, not the primary mechanism: source_registry.py's
`blocked_patterns` (owner directive 2026-09-14) is merged into every registry root's
excluded_patterns at load time, so a registry-driven lint run (--registry) never even
sees a blocked file in the first place -- it is filtered out of iter_registry_files()
before lint_files() runs. BLOCK001 exists for --paths mode (which bypasses per-root
excluded_patterns entirely) and to catch a future bug in that merge.

`--strict` promotes every warning to error severity for the exit-code decision only;
findings keep their inherent severity in output. `--fix-encoding` is the only thing in
this module that writes anything, and only when passed explicitly.

Byline: Claude Code · Sonnet 5 · 2026-09-14
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
from dataclasses import dataclass
from pathlib import Path

HERE = Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

from source_registry import SourceSpec, load_sources, load_blocked_patterns  # noqa: E402
from cdc_verify import decode_markdown, _fold_non_bmp, _matches, _slug, _glob_re  # noqa: E402

ERROR_CODES = {"ENC001", "EMPTY001", "DUP001", "PATH001", "BLOCK001"}
WARNING_CODES = {"TAGS001", "BYLINE001", "NBMP001", "JUNK001", "DATAURI001"}
# SIZE001 does not have one fixed severity: see DEFAULT_MAX_WARN_BYTES/DEFAULT_MAX_ERROR_BYTES.
DUAL_SEVERITY_CODES = {"SIZE001"}
ALL_CODES = ERROR_CODES | WARNING_CODES | DUAL_SEVERITY_CODES

# Mirrors flow_docs.CHUNK_SIZE. Not imported from flow_docs.py: importing it would pull
# in cocoindex at import time, which this module must never do (desktop CLI + worker
# pre-run lint stage both need to run without a CocoIndex environment configured).
FLOW_CHUNK_SIZE = int(os.environ.get("DOCSTORE_CHUNK_SIZE", "1200"))

DEFAULT_MAX_WARN_BYTES = 1 * 1024 * 1024
DEFAULT_MAX_ERROR_BYTES = 4 * 1024 * 1024


def _estimated_chunks(size_bytes: int, chunk_size: int = FLOW_CHUNK_SIZE) -> int:
    return max(1, -(-size_bytes // chunk_size))  # ceil division

# Mirrors the six registry entries' excluded_patterns (docstore-source-registry.json)
# plus the flow's own memory/junk conventions. Kept as an explicit set here so a file
# that slipped past a project's own excluded_patterns is still flagged.
JUNK_SEGMENTS = {
    ".remember", ".cnf", ".codex", ".agents", ".claude", ".memsearch",
    ".venv", "node_modules", ".pytest_cache", "_stale", "_v1-superseded",
}

_SLUG_RE = re.compile(r"[^a-z0-9]+")
# Same pattern as flow_docs._DATA_URI_RE (payload optional; any MIME type counts).
_DATA_URI_RE = re.compile(r"data:[a-zA-Z0-9.+/-]+;base64,[A-Za-z0-9+/=]*")
_FRONT_MATTER_RE = re.compile(r"\A﻿?---\r?\n(.*?)\r?\n---", re.S)
_BYLINE_RE = re.compile(r"(?i)byline\s*:")


@dataclass
class Finding:
    code: str
    path: str
    message: str
    # Explicit only for DUAL_SEVERITY_CODES (SIZE001); every other code infers its
    # severity from ERROR_CODES/WARNING_CODES in __post_init__.
    severity: str = ""

    def __post_init__(self) -> None:
        if self.code not in ALL_CODES:
            raise ValueError(f"unknown lint code: {self.code}")
        if self.severity:
            if self.severity not in ("error", "warning"):
                raise ValueError("severity must be 'error' or 'warning'")
            return
        if self.code in DUAL_SEVERITY_CODES:
            raise ValueError(f"{self.code} requires an explicit severity")
        self.severity = "error" if self.code in ERROR_CODES else "warning"

    def as_dict(self) -> dict:
        return {"code": self.code, "severity": self.severity, "path": self.path, "message": self.message}


# ---------------------------------------------------------------------------
# Small, self-contained predicates (mirror flag-doc-write.sh / flow_docs.py)
# ---------------------------------------------------------------------------


def _has_tags(body: str) -> bool:
    """Same test as plugins/docstore/claude/bin/flag-doc-write.sh's HAS_TAGS."""
    fm = _FRONT_MATTER_RE.match(body)
    if fm and re.search(r"(?m)^tags:", fm.group(1)):
        return True
    return bool(re.search(r"<!--\s*tags:", body, re.I))


def _has_byline(body: str) -> bool:
    return bool(_BYLINE_RE.search(body))


def _has_non_bmp(text: str) -> bool:
    return any(ord(ch) > 0xFFFF for ch in text)


def _junk_hit(*path_strings: str) -> bool:
    for value in path_strings:
        parts = value.replace("\\", "/").split("/")
        if any(part in JUNK_SEGMENTS for part in parts):
            return True
    return False


def _slug_would_truncate(source_path: str) -> bool:
    base = _SLUG_RE.sub("_", source_path.lower()).strip("_")
    return len(base) > 120


def _blocked_hit(candidates: tuple[str, ...], blocked_patterns: tuple[str, ...]) -> bool:
    if not blocked_patterns:
        return False
    return any(_glob_re(pattern).match(value) for pattern in blocked_patterns for value in candidates if value)


# ---------------------------------------------------------------------------
# Source discovery (mirrors cdc_verify.snapshot_sources' walk, without skipping
# empty files -- lint reports them instead of silently dropping them)
# ---------------------------------------------------------------------------


def iter_registry_files(sources: tuple[SourceSpec, ...]) -> list[tuple[SourceSpec, Path, str]]:
    """Return (source, filesystem_path, path_relative_to_source_root) for every
    markdown file each source's included/excluded patterns select."""
    out: list[tuple[SourceSpec, Path, str]] = []
    for source in sources:
        if not source.root.is_dir():
            continue
        for path in sorted(source.root.rglob("*.md")):
            if not path.is_file() or path.is_symlink():
                continue
            relative = path.relative_to(source.root).as_posix()
            if not _matches(relative, source):
                continue
            out.append((source, path, relative))
    return out


def _ad_hoc_source(root: Path) -> SourceSpec:
    return SourceSpec(
        project_id="ad-hoc",
        root=root,
        canonical_prefix="",
        domains=(),
        included_patterns=("**/*.md",),
        excluded_patterns=(),
        ingestion_status="current-full-source",
    )


def entries_from_paths(paths: list[str]) -> list[tuple[SourceSpec, Path, str]]:
    """`--paths` mode: lint explicit files, each treated as its own one-file root so
    the same iter_registry_files-shaped tuples flow through lint_files unchanged."""
    out: list[tuple[SourceSpec, Path, str]] = []
    for raw in paths:
        p = Path(raw).resolve()
        source = _ad_hoc_source(p.parent)
        out.append((source, p, p.name))
    return out


# ---------------------------------------------------------------------------
# Linting
# ---------------------------------------------------------------------------


def lint_files(
    entries: list[tuple[SourceSpec, Path, str]],
    *,
    strict: bool = False,
    blocked_patterns: tuple[str, ...] = (),
    max_warn_bytes: int = DEFAULT_MAX_WARN_BYTES,
    max_error_bytes: int = DEFAULT_MAX_ERROR_BYTES,
) -> list[Finding]:
    """strict is accepted for API symmetry with exit_code()/CLI callers but does not
    change which findings are produced -- only exit_code() promotes severity."""
    del strict
    findings: list[Finding] = []
    hash_index: dict[str, list[str]] = {}

    for source, fs_path, relative in entries:
        canonical = (source.canonical_prefix or "") + relative
        display = _fold_non_bmp(canonical) or relative

        try:
            raw = fs_path.read_bytes()
        except OSError as exc:
            findings.append(Finding("ENC001", display, f"could not read file: {exc}"))
            continue

        try:
            raw.decode("utf-8")
            enc_ok = True
        except UnicodeDecodeError:
            enc_ok = False
        text = decode_markdown(raw)
        if not enc_ok:
            findings.append(Finding("ENC001", display, "not valid UTF-8; decodes via the cp1252 fallback"))

        folded = _fold_non_bmp(text)
        if not folded.strip():
            findings.append(Finding("EMPTY001", display, "empty after decode + fold + strip"))
        else:
            digest = hashlib.sha256(folded.encode("utf-8")).hexdigest()
            hash_index.setdefault(digest, []).append(display)

        if canonical and _slug_would_truncate(canonical):
            findings.append(Finding(
                "PATH001", display,
                f"source_path slug exceeds 120 chars; digest slug would be {_slug(canonical)!r}",
            ))

        if _blocked_hit((relative, canonical), blocked_patterns):
            findings.append(Finding("BLOCK001", display, "path matches a registry blocked_patterns entry"))

        size_bytes = len(raw)
        if size_bytes >= max_error_bytes:
            size_severity = "error"
        elif size_bytes >= max_warn_bytes:
            size_severity = "warning"
        else:
            size_severity = None
        if size_severity:
            findings.append(Finding(
                "SIZE001", display,
                f"{size_bytes} bytes (~{_estimated_chunks(size_bytes)} estimated chunks "
                f"at chunk_size={FLOW_CHUNK_SIZE})",
                severity=size_severity,
            ))

        if _has_non_bmp(canonical) or _has_non_bmp(text):
            findings.append(Finding("NBMP001", display, "non-BMP character in the path or the body"))

        if _junk_hit(str(fs_path), canonical):
            findings.append(Finding("JUNK001", display, "path passes through a memory/junk folder"))

        if _DATA_URI_RE.search(text):
            findings.append(Finding("DATAURI001", display, "data:...;base64 payload found in body"))

        if not _has_tags(text):
            findings.append(Finding("TAGS001", display, "no tags: front matter `tags:` or `<!-- tags: ... -->`"))

        if not _has_byline(text):
            findings.append(Finding("BYLINE001", display, "no `Byline:` marker found"))

    for digest, paths in hash_index.items():
        if len(paths) > 1:
            for p in paths:
                others = len(paths) - 1
                findings.append(Finding(
                    "DUP001", p,
                    f"byte-identical content ({digest[:12]}...) shared with {others} other path(s)",
                ))

    findings.sort(key=lambda f: (f.path, f.code))
    return findings


def exit_code(findings: list[Finding], *, strict: bool) -> int:
    for f in findings:
        if f.severity == "error" or (strict and f.severity == "warning"):
            return 1
    return 0


# ---------------------------------------------------------------------------
# --fix-encoding (the only thing in this module that writes, and only on request)
# ---------------------------------------------------------------------------


def fix_encoding_pass(entries: list[tuple[SourceSpec, Path, str]]) -> list[str]:
    """Rewrite non-UTF-8 files to UTF-8 in place. No other transformation: newline
    bytes and content are otherwise untouched (decode_markdown does not translate
    newlines). Returns the filesystem paths actually rewritten."""
    fixed: list[str] = []
    for _source, fs_path, _relative in entries:
        raw = fs_path.read_bytes()
        try:
            raw.decode("utf-8")
            continue
        except UnicodeDecodeError:
            pass
        text = decode_markdown(raw)
        fs_path.write_bytes(text.encode("utf-8"))
        fixed.append(str(fs_path))
    return fixed


# ---------------------------------------------------------------------------
# Worker integration (worker_sync.py records this in the run receipt)
# ---------------------------------------------------------------------------


def resolve_env_sources() -> tuple[SourceSpec, ...]:
    """Load exactly the sources the current run would use: same env vars,
    same legacy-docs fallback path, as flow_docs.py / cdc_verify.py."""
    registry_env = os.environ.get("DOCSTORE_PROJECT_REGISTRY")
    registry_path = Path(registry_env) if registry_env else None
    multi_root = os.environ.get("DOCSTORE_MULTI_ROOT_ENABLED", "").strip() == "1"
    repo_root = HERE.parents[1]
    sources, _ = load_sources(registry_path, repo_root / "docs", multi_root_enabled=multi_root)
    return sources


def lint_summary_for_receipt(
    sources: tuple[SourceSpec, ...],
    *,
    limit: int = 200,
    blocked_patterns: tuple[str, ...] = (),
    max_warn_bytes: int = DEFAULT_MAX_WARN_BYTES,
    max_error_bytes: int = DEFAULT_MAX_ERROR_BYTES,
) -> dict:
    entries = iter_registry_files(sources)
    findings = lint_files(
        entries, blocked_patterns=blocked_patterns,
        max_warn_bytes=max_warn_bytes, max_error_bytes=max_error_bytes,
    )
    errors = sum(1 for f in findings if f.severity == "error")
    warnings = sum(1 for f in findings if f.severity == "warning")

    # Owner directive 2026-09-14: record per-file byte size and chunk-count estimate
    # in the receipt too, not just inside SIZE001 finding text. Bounded to the 20
    # largest files -- write_current_status() caps the whole receipt at 64 KiB and
    # this list must never risk blowing that budget on a ~1,235-file corpus.
    sized: list[tuple[int, str]] = []
    for _source, fs_path, relative in entries:
        try:
            sized.append((fs_path.stat().st_size, relative))
        except OSError:
            continue
    sized.sort(reverse=True)
    largest_files = [
        {"path": relative, "bytes": size, "estimated_chunks": _estimated_chunks(size)}
        for size, relative in sized[:20]
    ]

    return {
        "files_scanned": len(entries),
        "errors": errors,
        "warnings": warnings,
        "findings": [f.as_dict() for f in findings[:limit]],
        "findings_truncated": len(findings) > limit,
        "largest_files": largest_files,
        "chunk_size_bytes": FLOW_CHUNK_SIZE,
    }


def lint_summary_from_env(*, limit: int = 200) -> dict:
    """Called by worker_sync.py before the ingest stage. Never raises for lint
    findings (only for a genuine registry-load failure, same as snapshot_sources())."""
    registry_env = os.environ.get("DOCSTORE_PROJECT_REGISTRY")
    registry_path = Path(registry_env) if registry_env else None
    blocked_patterns = load_blocked_patterns(registry_path)
    return lint_summary_for_receipt(resolve_env_sources(), limit=limit, blocked_patterns=blocked_patterns)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def _load_target_entries(args: argparse.Namespace) -> tuple[list[tuple[SourceSpec, Path, str]], tuple[str, ...]]:
    """Returns (entries, blocked_patterns). blocked_patterns is only non-empty for
    --registry (see the BLOCK001 note in the module docstring)."""
    if args.paths:
        return entries_from_paths(args.paths), ()
    registry_path = Path(args.registry).resolve(strict=True) if args.registry else None
    repo_root = HERE.parents[1]
    # Ad-hoc CLI use means "check the whole declared registry", so every active,
    # non-excluded root is included whenever a registry is given -- unlike the
    # worker's own lint_summary_from_env(), which mirrors that run's actual
    # DOCSTORE_MULTI_ROOT_ENABLED setting because it must lint what will really be
    # ingested this run. Both are correct for what they are used for.
    multi_root = bool(registry_path)
    sources, _ = load_sources(registry_path, repo_root / "docs", multi_root_enabled=multi_root)
    blocked_patterns = load_blocked_patterns(registry_path)
    return iter_registry_files(sources), blocked_patterns


def _print_table(findings: list[Finding], entries_count: int) -> None:
    counts: dict[tuple[str, str], int] = {}
    for f in findings:
        key = (f.code, f.severity)
        counts[key] = counts.get(key, 0) + 1
    print(f"docs_lint: {entries_count} files scanned")
    print(f"{'code':10} {'severity':9} count")
    for (code, severity), n in sorted(counts.items()):
        print(f"{code:10} {severity:9} {n}")
    total_errors = sum(n for (_code, severity), n in counts.items() if severity == "error")
    total_warnings = sum(n for (_code, severity), n in counts.items() if severity == "warning")
    print(f"TOTAL errors={total_errors} warnings={total_warnings}")
    sample = findings[:50]
    if sample:
        print(f"\nfirst {len(sample)} finding(s) (use --json for the full list):")
        for f in sample:
            print(f"  [{f.severity[:4]}] {f.code:10} {f.path}: {f.message}")
        if len(findings) > len(sample):
            print(f"  ... {len(findings) - len(sample)} more")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Lint Docstore markdown sources")
    parser.add_argument("--registry", help="path to a docstore-source-registry.json")
    parser.add_argument("--paths", nargs="+", help="lint explicit files instead of a registry")
    parser.add_argument("--json", action="store_true", help="machine-readable output")
    parser.add_argument("--strict", action="store_true", help="warnings also fail (exit 1)")
    parser.add_argument("--fix-encoding", action="store_true",
                         help="rewrite non-UTF-8 files to UTF-8 in place (never the default)")
    parser.add_argument("--max-warn-bytes", type=int, default=DEFAULT_MAX_WARN_BYTES,
                         help=f"SIZE001 warning threshold in bytes (default {DEFAULT_MAX_WARN_BYTES})")
    parser.add_argument("--max-error-bytes", type=int, default=DEFAULT_MAX_ERROR_BYTES,
                         help=f"SIZE001 error threshold in bytes (default {DEFAULT_MAX_ERROR_BYTES})")
    args = parser.parse_args(argv)

    if args.paths and args.registry:
        parser.error("--paths and --registry are mutually exclusive")

    entries, blocked_patterns = _load_target_entries(args)

    fixed: list[str] = []
    if args.fix_encoding:
        fixed = fix_encoding_pass(entries)

    findings = lint_files(
        entries, strict=args.strict, blocked_patterns=blocked_patterns,
        max_warn_bytes=args.max_warn_bytes, max_error_bytes=args.max_error_bytes,
    )

    if args.json:
        payload = {
            "files_scanned": len(entries),
            "errors": sum(1 for f in findings if f.severity == "error"),
            "warnings": sum(1 for f in findings if f.severity == "warning"),
            "fixed_encoding": fixed,
            "findings": [f.as_dict() for f in findings],
        }
        print(json.dumps(payload, indent=2, ensure_ascii=False))
    else:
        if fixed:
            print(f"docs_lint: rewrote {len(fixed)} file(s) to UTF-8:")
            for path in fixed:
                print(f"  {path}")
        _print_table(findings, len(entries))

    return exit_code(findings, strict=args.strict)


if __name__ == "__main__":
    raise SystemExit(main())
