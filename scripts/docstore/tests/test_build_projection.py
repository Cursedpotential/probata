"""Tests for build_projection.py against a small on-disk registry + fixture tree
under tmp_path. Exercises the normalization (decode/fold/UTF-8 rewrite), the
omit-empty rule, and the cross-root byte-identical dedup, then checks the
container registry copy build_projection writes beside the output.

Byline: Claude Code · Sonnet 5 · 2026-09-14
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCRIPTS_DOCSTORE = HERE.parent
if str(SCRIPTS_DOCSTORE) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DOCSTORE))

import build_projection  # noqa: E402

SHARED_BODY = "# Shared\n\n<!-- tags: shared -->\n\n> _Byline: x_\n\nSame in both roots.\n"


def _write_registry(tmp_path: Path, monorepo: Path) -> Path:
    registry = {
        "schema": "propria-docstore-source-registry-v1",
        "monorepo_root": str(monorepo.resolve()),
        "projects": [
            {
                "project_id": "proj1",
                "source_root": "proj1",
                "canonical_prefix": "proj1",
                "domains": ["docs"],
                "included_patterns": ["**/*.md"],
                "excluded_patterns": [],
                "registration_status": "active",
                "ingestion_status": "current-full-source",
                "required": True,
            },
            {
                "project_id": "proj2",
                "source_root": "proj2",
                "canonical_prefix": "proj2",
                "domains": ["docs"],
                "included_patterns": ["**/*.md"],
                "excluded_patterns": [],
                "registration_status": "active",
                "ingestion_status": "pending-multi-root-cdc",
                "required": True,
            },
        ],
    }
    path = tmp_path / "registry.json"
    path.write_text(json.dumps(registry, indent=2), encoding="utf-8")
    return path


def _build_fixture_tree(tmp_path: Path) -> Path:
    monorepo = tmp_path / "monorepo"
    proj1 = monorepo / "proj1"
    proj2 = monorepo / "proj2"
    proj1.mkdir(parents=True)
    proj2.mkdir(parents=True)

    (proj1 / "a.md").write_text(
        "# A\n\n<!-- tags: a -->\n\n> _Byline: x_\n\nUnique content A.\n", encoding="utf-8"
    )
    # dup.md (proj1) and dup_copy.md (proj2) are byte-identical after decode+fold:
    # sorted-rglob order visits proj1 before proj2, so proj1/dup.md is kept and
    # proj2/dup_copy.md is the one recorded as omitted.
    (proj1 / "dup.md").write_text(SHARED_BODY, encoding="utf-8")
    (proj1 / "empty.md").write_text("   \n\n\t\n", encoding="utf-8")
    (proj1 / "latin1.md").write_bytes("caf\xe9 confidentiel".encode("cp1252"))

    (proj2 / "dup_copy.md").write_text(SHARED_BODY, encoding="utf-8")
    (proj2 / "note.md").write_text(
        "# Note\n\n<!-- tags: note -->\n\n> _Byline: x_\n\nUnique proj2 content.\n", encoding="utf-8"
    )
    return monorepo


def test_build_projection_counts_and_layout(tmp_path):
    monorepo = _build_fixture_tree(tmp_path)
    registry_path = _write_registry(tmp_path, monorepo)
    out_dir = tmp_path / "out"

    result = build_projection.build_projection(registry_path, out_dir, "/exchange/sources")

    assert result["per_root"]["proj1"] == {"files": 4, "kept": 3, "omitted_empty": 1, "omitted_dup": 0}
    assert result["per_root"]["proj2"] == {"files": 2, "kept": 1, "omitted_empty": 0, "omitted_dup": 1}
    assert result["total_kept"] == 4
    assert result["total_duplicates"] == 1

    assert (out_dir / "proj1" / "a.md").is_file()
    assert (out_dir / "proj1" / "dup.md").is_file()
    assert (out_dir / "proj1" / "latin1.md").is_file()
    assert (out_dir / "proj2" / "note.md").is_file()
    assert not (out_dir / "proj1" / "empty.md").exists()
    assert not (out_dir / "proj2" / "dup_copy.md").exists()


def test_build_projection_normalizes_encoding_to_utf8(tmp_path):
    monorepo = _build_fixture_tree(tmp_path)
    registry_path = _write_registry(tmp_path, monorepo)
    out_dir = tmp_path / "out"

    build_projection.build_projection(registry_path, out_dir, "/exchange/sources")

    written = (out_dir / "proj1" / "latin1.md").read_bytes()
    # The copy must decode as clean UTF-8 and preserve the original text exactly.
    assert written.decode("utf-8") == "caf\xe9 confidentiel"
    with __import__("pytest").raises(UnicodeDecodeError):
        # cp1252 bytes for accented chars are not valid UTF-8 on their own; a
        # correctly-normalized copy must NOT still be raw cp1252 bytes.
        "caf\xe9 confidentiel".encode("cp1252").decode("utf-8")


def test_build_projection_folds_non_bmp_in_body(tmp_path):
    monorepo = tmp_path / "monorepo"
    proj1 = monorepo / "proj1"
    proj1.mkdir(parents=True)
    (proj1 / "emoji.md").write_text(
        "# Title\n\n<!-- tags: e -->\n\n> _Byline: x_\n\nHello \U0001F600 world.\n", encoding="utf-8"
    )
    registry_path = _write_registry(tmp_path, monorepo)
    # proj2 does not exist on disk; not required=False would be needed if it were
    # missing, so give proj2 a real (empty) directory to keep load_sources happy.
    (monorepo / "proj2").mkdir(parents=True, exist_ok=True)
    out_dir = tmp_path / "out"

    build_projection.build_projection(registry_path, out_dir, "/exchange/sources")

    written_text = (out_dir / "proj1" / "emoji.md").read_text(encoding="utf-8")
    assert "\U0001F600" not in written_text
    assert ":grinning" in written_text or ":u1f600:" in written_text


def test_build_projection_writes_duplicates_json(tmp_path):
    monorepo = _build_fixture_tree(tmp_path)
    registry_path = _write_registry(tmp_path, monorepo)
    out_dir = tmp_path / "out"

    build_projection.build_projection(registry_path, out_dir, "/exchange/sources")

    dup_path = out_dir / "docstore-projection-duplicates.json"
    assert dup_path.is_file()
    payload = json.loads(dup_path.read_text(encoding="utf-8"))
    assert payload["omitted_duplicates"], "expected at least one recorded duplicate"
    entry = payload["omitted_duplicates"][0]
    assert entry["skipped"] == "proj2/dup_copy.md"
    assert entry["kept"] == "proj1/dup.md"
    assert len(entry["sha256_folded"]) == 64


def test_build_projection_writes_container_registry(tmp_path):
    monorepo = _build_fixture_tree(tmp_path)
    registry_path = _write_registry(tmp_path, monorepo)
    out_dir = tmp_path / "out"

    build_projection.build_projection(registry_path, out_dir, "/exchange/sources")

    container_registry_path = out_dir / "docstore-source-registry.json"
    assert container_registry_path.is_file()
    payload = json.loads(container_registry_path.read_text(encoding="utf-8"))
    assert payload["monorepo_root"] == "/exchange/sources"
    assert payload["schema"] == "propria-docstore-source-registry-v1"
    assert "projection" in payload
    assert payload["projection"]["built_by"]
    project_ids = {p["project_id"] for p in payload["projects"]}
    assert project_ids == {"proj1", "proj2"}


def test_iter_source_files_respects_excluded_patterns(tmp_path):
    monorepo = tmp_path / "monorepo"
    proj1 = monorepo / "proj1"
    (proj1 / "keep").mkdir(parents=True)
    (proj1 / "skip").mkdir(parents=True)
    (proj1 / "keep" / "a.md").write_text("keep me\n", encoding="utf-8")
    (proj1 / "skip" / "b.md").write_text("skip me\n", encoding="utf-8")

    from source_registry import SourceSpec
    source = SourceSpec(
        project_id="proj1",
        root=proj1,
        canonical_prefix="proj1",
        domains=("docs",),
        included_patterns=("**/*.md",),
        excluded_patterns=("skip/**",),
        ingestion_status="current-full-source",
    )
    found = build_projection.iter_source_files(source)
    relatives = {relative for _path, relative in found}
    assert relatives == {"keep/a.md"}
