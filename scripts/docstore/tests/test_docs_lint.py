"""Tests for docs_lint.py against small tmp_path fixtures -- no registry JSON, no
network, no cocoindex. Each test targets one lint code in isolation plus the
strict/--fix-encoding behaviours.

Byline: Claude Code · Sonnet 5 · 2026-09-14
"""
from __future__ import annotations

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCRIPTS_DOCSTORE = HERE.parent
if str(SCRIPTS_DOCSTORE) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DOCSTORE))

from source_registry import SourceSpec  # noqa: E402
import docs_lint  # noqa: E402

TAGGED_BYLINE_BODY = (
    "# Title\n\n<!-- tags: sample -->\n\n> _Byline: Claude Code · Sonnet 5 · 2026-09-14_\n\nBody text.\n"
)


def _source(root: Path, canonical_prefix: str = "test/") -> SourceSpec:
    return SourceSpec(
        project_id="test",
        root=root,
        canonical_prefix=canonical_prefix,
        domains=("docs",),
        included_patterns=("**/*.md",),
        excluded_patterns=(),
        ingestion_status="current-full-source",
    )


def _codes_for(findings, suffix: str) -> set[str]:
    return {f.code for f in findings if f.path.endswith(suffix)}


def test_enc001_cp1252_file_is_flagged(tmp_path):
    (tmp_path / "bad.md").write_bytes("café — confidentiel".encode("cp1252"))
    entries = docs_lint.iter_registry_files((_source(tmp_path),))
    findings = docs_lint.lint_files(entries)
    assert "ENC001" in _codes_for(findings, "bad.md")


def test_valid_utf8_file_has_no_enc001(tmp_path):
    (tmp_path / "good.md").write_text(TAGGED_BYLINE_BODY, encoding="utf-8")
    entries = docs_lint.iter_registry_files((_source(tmp_path),))
    findings = docs_lint.lint_files(entries)
    assert "ENC001" not in _codes_for(findings, "good.md")


def test_empty001_after_strip(tmp_path):
    (tmp_path / "empty.md").write_text("   \n\n\t\n", encoding="utf-8")
    entries = docs_lint.iter_registry_files((_source(tmp_path),))
    findings = docs_lint.lint_files(entries)
    assert "EMPTY001" in _codes_for(findings, "empty.md")


def test_non_empty_file_has_no_empty001(tmp_path):
    (tmp_path / "full.md").write_text(TAGGED_BYLINE_BODY, encoding="utf-8")
    entries = docs_lint.iter_registry_files((_source(tmp_path),))
    findings = docs_lint.lint_files(entries)
    assert "EMPTY001" not in _codes_for(findings, "full.md")


def test_dup001_flags_both_sides_of_a_duplicate_pair(tmp_path):
    (tmp_path / "a.md").write_text(TAGGED_BYLINE_BODY, encoding="utf-8")
    (tmp_path / "b.md").write_text(TAGGED_BYLINE_BODY, encoding="utf-8")
    entries = docs_lint.iter_registry_files((_source(tmp_path),))
    findings = docs_lint.lint_files(entries)
    dup_paths = {f.path for f in findings if f.code == "DUP001"}
    assert len(dup_paths) == 2
    assert any(p.endswith("a.md") for p in dup_paths)
    assert any(p.endswith("b.md") for p in dup_paths)


def test_distinct_content_has_no_dup001(tmp_path):
    (tmp_path / "a.md").write_text(TAGGED_BYLINE_BODY, encoding="utf-8")
    (tmp_path / "b.md").write_text(TAGGED_BYLINE_BODY + "\nextra line.\n", encoding="utf-8")
    entries = docs_lint.iter_registry_files((_source(tmp_path),))
    findings = docs_lint.lint_files(entries)
    assert not any(f.code == "DUP001" for f in findings)


def test_path001_long_source_path(tmp_path):
    long_name = ("x" * 130) + ".md"
    (tmp_path / long_name).write_text(TAGGED_BYLINE_BODY, encoding="utf-8")
    entries = docs_lint.iter_registry_files((_source(tmp_path),))
    findings = docs_lint.lint_files(entries)
    assert any(f.code == "PATH001" for f in findings)


def test_short_path_has_no_path001(tmp_path):
    (tmp_path / "short.md").write_text(TAGGED_BYLINE_BODY, encoding="utf-8")
    entries = docs_lint.iter_registry_files((_source(tmp_path),))
    findings = docs_lint.lint_files(entries)
    assert not any(f.code == "PATH001" for f in findings)


def test_nbmp001_emoji_in_filename(tmp_path):
    name = "note-\U0001F600.md"
    (tmp_path / name).write_text(TAGGED_BYLINE_BODY, encoding="utf-8")
    entries = docs_lint.iter_registry_files((_source(tmp_path),))
    findings = docs_lint.lint_files(entries)
    assert any(f.code == "NBMP001" for f in findings)


def test_nbmp001_emoji_in_body(tmp_path):
    (tmp_path / "plain.md").write_text(TAGGED_BYLINE_BODY + "\U0001F600\n", encoding="utf-8")
    entries = docs_lint.iter_registry_files((_source(tmp_path),))
    findings = docs_lint.lint_files(entries)
    assert any(f.code == "NBMP001" for f in findings)


def test_tags_and_byline_present_no_findings(tmp_path):
    (tmp_path / "tagged.md").write_text(TAGGED_BYLINE_BODY, encoding="utf-8")
    entries = docs_lint.iter_registry_files((_source(tmp_path),))
    findings = docs_lint.lint_files(entries)
    codes = _codes_for(findings, "tagged.md")
    assert "TAGS001" not in codes
    assert "BYLINE001" not in codes


def test_tags_and_byline_absent_flagged(tmp_path):
    (tmp_path / "untagged.md").write_text("# Title\n\nJust body text, no tags, no byline.\n", encoding="utf-8")
    entries = docs_lint.iter_registry_files((_source(tmp_path),))
    findings = docs_lint.lint_files(entries)
    codes = _codes_for(findings, "untagged.md")
    assert "TAGS001" in codes
    assert "BYLINE001" in codes


def test_frontmatter_tags_also_satisfy_tags001(tmp_path):
    body = "---\ntags: [alpha, beta]\n---\n\n# Title\n\n> _Byline: x_\n\nBody.\n"
    (tmp_path / "fm.md").write_text(body, encoding="utf-8")
    entries = docs_lint.iter_registry_files((_source(tmp_path),))
    findings = docs_lint.lint_files(entries)
    assert "TAGS001" not in _codes_for(findings, "fm.md")


def test_junk001_node_modules_segment(tmp_path):
    junky = tmp_path / "node_modules"
    junky.mkdir()
    (junky / "x.md").write_text(TAGGED_BYLINE_BODY, encoding="utf-8")
    entries = docs_lint.iter_registry_files((_source(tmp_path),))
    findings = docs_lint.lint_files(entries)
    assert any(f.code == "JUNK001" for f in findings)


def test_junk001_absent_for_ordinary_path(tmp_path):
    (tmp_path / "ordinary.md").write_text(TAGGED_BYLINE_BODY, encoding="utf-8")
    entries = docs_lint.iter_registry_files((_source(tmp_path),))
    findings = docs_lint.lint_files(entries)
    assert not any(f.code == "JUNK001" for f in findings)


def test_datauri001_flagged(tmp_path):
    body = TAGGED_BYLINE_BODY + "\ndata:image/png;base64,AAAABBBB\n"
    (tmp_path / "d.md").write_text(body, encoding="utf-8")
    entries = docs_lint.iter_registry_files((_source(tmp_path),))
    findings = docs_lint.lint_files(entries)
    assert any(f.code == "DATAURI001" for f in findings)


def test_fix_encoding_rewrites_file_to_utf8(tmp_path):
    p = tmp_path / "bad.md"
    original_text = "café — test"
    p.write_bytes(original_text.encode("cp1252"))
    entries = docs_lint.iter_registry_files((_source(tmp_path),))
    fixed = docs_lint.fix_encoding_pass(entries)
    assert str(p) in fixed
    assert p.read_bytes().decode("utf-8") == original_text
    # Re-linting the fixed file must no longer raise ENC001.
    entries_after = docs_lint.iter_registry_files((_source(tmp_path),))
    findings_after = docs_lint.lint_files(entries_after)
    assert "ENC001" not in _codes_for(findings_after, "bad.md")


def test_fix_encoding_never_touches_utf8_files(tmp_path):
    p = tmp_path / "good.md"
    p.write_text(TAGGED_BYLINE_BODY, encoding="utf-8")
    before = p.read_bytes()
    entries = docs_lint.iter_registry_files((_source(tmp_path),))
    fixed = docs_lint.fix_encoding_pass(entries)
    assert str(p) not in fixed
    assert p.read_bytes() == before


def test_exit_code_error_findings_fail_without_strict():
    findings = [docs_lint.Finding("EMPTY001", "x.md", "empty")]
    assert docs_lint.exit_code(findings, strict=False) == 1
    assert docs_lint.exit_code(findings, strict=True) == 1


def test_exit_code_warning_only_findings_pass_unless_strict():
    findings = [docs_lint.Finding("TAGS001", "x.md", "no tags")]
    assert docs_lint.exit_code(findings, strict=False) == 0
    assert docs_lint.exit_code(findings, strict=True) == 1


def test_exit_code_clean_run_passes():
    assert docs_lint.exit_code([], strict=False) == 0
    assert docs_lint.exit_code([], strict=True) == 0


def test_entries_from_paths_lints_explicit_files(tmp_path):
    p = tmp_path / "explicit.md"
    p.write_text("# Title\n\nno tags here.\n", encoding="utf-8")
    entries = docs_lint.entries_from_paths([str(p)])
    findings = docs_lint.lint_files(entries)
    assert any(f.code == "TAGS001" for f in findings)


def test_lint_summary_for_receipt_shape(tmp_path):
    (tmp_path / "tagged.md").write_text(TAGGED_BYLINE_BODY, encoding="utf-8")
    (tmp_path / "empty.md").write_text("\n", encoding="utf-8")
    summary = docs_lint.lint_summary_for_receipt((_source(tmp_path),), limit=10)
    assert summary["files_scanned"] == 2
    assert summary["errors"] >= 1  # the empty file
    assert isinstance(summary["findings"], list)
    assert summary["findings_truncated"] is False
    assert "largest_files" in summary
    assert summary["chunk_size_bytes"] == docs_lint.FLOW_CHUNK_SIZE


def test_block001_flags_path_under_blocked_pattern(tmp_path):
    junky = tmp_path / "node_modules"
    junky.mkdir()
    (junky / "x.md").write_text(TAGGED_BYLINE_BODY, encoding="utf-8")
    entries = docs_lint.iter_registry_files((_source(tmp_path),))
    findings = docs_lint.lint_files(entries, blocked_patterns=("**/node_modules/**",))
    assert any(f.code == "BLOCK001" for f in findings)


def test_block001_absent_without_blocked_patterns(tmp_path):
    junky = tmp_path / "node_modules"
    junky.mkdir()
    (junky / "x.md").write_text(TAGGED_BYLINE_BODY, encoding="utf-8")
    entries = docs_lint.iter_registry_files((_source(tmp_path),))
    findings = docs_lint.lint_files(entries)  # blocked_patterns defaults to ()
    assert not any(f.code == "BLOCK001" for f in findings)


def test_block001_absent_for_non_matching_path(tmp_path):
    (tmp_path / "ordinary.md").write_text(TAGGED_BYLINE_BODY, encoding="utf-8")
    entries = docs_lint.iter_registry_files((_source(tmp_path),))
    findings = docs_lint.lint_files(entries, blocked_patterns=("**/node_modules/**",))
    assert not any(f.code == "BLOCK001" for f in findings)


def test_size001_warns_above_warn_threshold(tmp_path):
    (tmp_path / "big.md").write_text(TAGGED_BYLINE_BODY + ("x" * 2000) + "\n", encoding="utf-8")
    entries = docs_lint.iter_registry_files((_source(tmp_path),))
    findings = docs_lint.lint_files(entries, max_warn_bytes=1000, max_error_bytes=10_000)
    size_findings = [f for f in findings if f.code == "SIZE001"]
    assert len(size_findings) == 1
    assert size_findings[0].severity == "warning"


def test_size001_errors_above_error_threshold(tmp_path):
    (tmp_path / "huge.md").write_text(TAGGED_BYLINE_BODY + ("x" * 2000) + "\n", encoding="utf-8")
    entries = docs_lint.iter_registry_files((_source(tmp_path),))
    findings = docs_lint.lint_files(entries, max_warn_bytes=100, max_error_bytes=1000)
    size_findings = [f for f in findings if f.code == "SIZE001"]
    assert len(size_findings) == 1
    assert size_findings[0].severity == "error"


def test_size001_absent_below_thresholds(tmp_path):
    (tmp_path / "small.md").write_text(TAGGED_BYLINE_BODY, encoding="utf-8")
    entries = docs_lint.iter_registry_files((_source(tmp_path),))
    findings = docs_lint.lint_files(entries)  # default 1 MiB / 4 MiB thresholds
    assert not any(f.code == "SIZE001" for f in findings)


def test_finding_rejects_dual_code_without_severity():
    import pytest
    with pytest.raises(ValueError):
        docs_lint.Finding("SIZE001", "x.md", "no severity given")


def test_finding_rejects_explicit_severity_for_fixed_code():
    import pytest
    with pytest.raises(ValueError):
        docs_lint.Finding("TAGS001", "x.md", "bad", severity="bogus")


def test_load_blocked_patterns_merges_into_excluded_patterns(tmp_path):
    import json as _json
    from source_registry import load_sources

    monorepo = tmp_path / "mono"
    proj = monorepo / "proj"
    (proj / "node_modules").mkdir(parents=True)
    (proj / "node_modules" / "x.md").write_text("blocked\n", encoding="utf-8")
    (proj / "keep.md").write_text(TAGGED_BYLINE_BODY, encoding="utf-8")

    registry = {
        "schema": "propria-docstore-source-registry-v1",
        "monorepo_root": str(monorepo.resolve()),
        "blocked_patterns": ["**/node_modules/**"],
        "projects": [{
            "project_id": "proj",
            "source_root": "proj",
            "canonical_prefix": "proj",
            "domains": ["docs"],
            "included_patterns": ["**/*.md"],
            "excluded_patterns": [],
            "registration_status": "active",
            "ingestion_status": "current-full-source",
            "required": True,
        }],
    }
    registry_path = tmp_path / "registry.json"
    registry_path.write_text(_json.dumps(registry), encoding="utf-8")

    sources, _fp = load_sources(registry_path, tmp_path, multi_root_enabled=False)
    assert len(sources) == 1
    assert "**/node_modules/**" in sources[0].excluded_patterns

    entries = docs_lint.iter_registry_files(sources)
    relatives = {relative for _source, _path, relative in entries}
    assert relatives == {"keep.md"}


def test_load_blocked_patterns_fails_closed_on_malformed_key(tmp_path):
    import json as _json
    import pytest
    from source_registry import load_sources

    monorepo = tmp_path / "mono2"
    proj = monorepo / "proj"
    proj.mkdir(parents=True)
    (proj / "a.md").write_text(TAGGED_BYLINE_BODY, encoding="utf-8")

    registry = {
        "schema": "propria-docstore-source-registry-v1",
        "monorepo_root": str(monorepo.resolve()),
        "blocked_patterns": "not-a-list",
        "projects": [{
            "project_id": "proj",
            "source_root": "proj",
            "canonical_prefix": "proj",
            "domains": ["docs"],
            "included_patterns": ["**/*.md"],
            "excluded_patterns": [],
            "registration_status": "active",
            "ingestion_status": "current-full-source",
            "required": True,
        }],
    }
    registry_path = tmp_path / "registry.json"
    registry_path.write_text(_json.dumps(registry), encoding="utf-8")

    with pytest.raises(ValueError):
        load_sources(registry_path, tmp_path, multi_root_enabled=False)


def test_load_blocked_patterns_absent_key_is_backward_compatible(tmp_path):
    import json as _json
    from source_registry import load_sources

    monorepo = tmp_path / "mono3"
    proj = monorepo / "proj"
    proj.mkdir(parents=True)
    (proj / "a.md").write_text(TAGGED_BYLINE_BODY, encoding="utf-8")

    registry = {
        "schema": "propria-docstore-source-registry-v1",
        "monorepo_root": str(monorepo.resolve()),
        "projects": [{
            "project_id": "proj",
            "source_root": "proj",
            "canonical_prefix": "proj",
            "domains": ["docs"],
            "included_patterns": ["**/*.md"],
            "excluded_patterns": [],
            "registration_status": "active",
            "ingestion_status": "current-full-source",
            "required": True,
        }],
    }
    registry_path = tmp_path / "registry.json"
    registry_path.write_text(_json.dumps(registry), encoding="utf-8")

    sources, _fp = load_sources(registry_path, tmp_path, multi_root_enabled=False)
    assert sources[0].excluded_patterns == ()
