"""Contracts for versioned Poppler identity and content-free certification."""

from __future__ import annotations

import hashlib
import subprocess
from pathlib import Path

import pytest

from server.tools import engine_profiles


def _fake_poppler(monkeypatch: pytest.MonkeyPatch, executable: Path, extracted: str) -> None:
    def fake_which(name: str) -> str | None:
        if name in {"pdftotext", "pdftotext.exe"}:
            return str(executable)
        if name == "dpkg-query":
            return "/usr/bin/dpkg-query"
        return None

    def fake_run(command: list[str], *, timeout: float) -> subprocess.CompletedProcess[str]:
        del timeout
        if command[0] == "dpkg-query":
            return subprocess.CompletedProcess(command, 0, "22.12.0-2+deb12u3", "")
        if command[-1] == "-v":
            return subprocess.CompletedProcess(command, 0, "", "pdftotext version 22.12.0")
        Path(command[-1]).write_text(extracted, encoding="utf-8", newline="")
        return subprocess.CompletedProcess(command, 0, "", "")

    monkeypatch.setattr(engine_profiles.shutil, "which", fake_which)
    monkeypatch.setattr(engine_profiles, "_run", fake_run)
    monkeypatch.setattr(engine_profiles.platform, "system", lambda: "Linux")
    monkeypatch.setattr(engine_profiles.platform, "machine", lambda: "x86_64")


def test_poppler_inspection_reports_platform_executable_hash_and_exact_command(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    executable = tmp_path / "pdftotext"
    executable.write_bytes(b"pinned-poppler-binary")
    _fake_poppler(monkeypatch, executable, "")

    result = engine_profiles.inspect_poppler(
        {
            "expected_profile_id": "poppler-linux-amd64",
            "expected_package_version": "22.12.0-2+deb12u3",
        }
    )

    assert result["ready"] is True
    assert result["engine_id"] == "poppler"
    assert result["profile_id"] == "poppler-linux-amd64"
    assert result["executable"] == str(executable.resolve())
    assert result["executable_sha256"] == hashlib.sha256(executable.read_bytes()).hexdigest()
    assert result["package_version"] == "22.12.0-2+deb12u3"
    assert result["command"] == [str(executable.resolve()), "-v"]


def test_poppler_certification_records_metrics_without_returning_content(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    executable = tmp_path / "pdftotext"
    executable.write_bytes(b"pinned-poppler-binary")
    extracted = "alpha\n" + "\u25a0" * 33 + "\n"
    _fake_poppler(monkeypatch, executable, extracted)
    fixture = tmp_path / "reference.pdf"
    fixture.write_bytes(b"%PDF-1.7\nreference fixture\n%%EOF\n")

    result = engine_profiles.certify_poppler_text(
        {
            "path": str(fixture),
            "expected_profile_id": "poppler-linux-amd64",
            "expected_package_version": "22.12.0-2+deb12u3",
            "expected": {
                "input_sha256": hashlib.sha256(fixture.read_bytes()).hexdigest(),
                "input_bytes": fixture.stat().st_size,
                "glyph": "\u25a0",
                "glyph_count": 33,
                "replacement_count": 0,
            },
        }
    )

    assert result["passed"] is True
    assert result["observed"]["glyph_count"] == 33
    assert result["observed"]["replacement_count"] == 0
    assert result["observed"]["output_sha256"] == hashlib.sha256(extracted.encode()).hexdigest()
    assert extracted not in str(result)
    assert result["command"][1:5] == ["-enc", "UTF-8", "-eol", "unix"]


def test_profile_mismatch_fails_closed(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    executable = tmp_path / "pdftotext"
    executable.write_bytes(b"binary")
    _fake_poppler(monkeypatch, executable, "")

    result = engine_profiles.inspect_poppler({"expected_profile_id": "poppler-windows-amd64"})

    assert result["ready"] is False
    profile_check = next(check for check in result["checks"] if check["id"] == "profile-id")
    assert profile_check == {
        "id": "profile-id",
        "passed": False,
        "expected": "poppler-windows-amd64",
        "observed": "poppler-linux-amd64",
    }


def test_certification_rejects_paths_outside_configured_runtime_roots(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    fixture = tmp_path / "outside.pdf"
    fixture.write_bytes(b"%PDF-1.7\n%%EOF\n")
    allowed = tmp_path / "materialized"
    allowed.mkdir()
    monkeypatch.setenv(engine_profiles._ALLOWED_ROOTS_ENV, f'["{allowed.as_posix()}"]')

    with pytest.raises(ValueError, match="outside the tool runtime"):
        engine_profiles.certify_poppler_text({"path": str(fixture)})


def test_source_path_accepts_legacy_read_roots_only_as_fallback(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    fixture = tmp_path / "legacy-root.pdf"
    fixture.write_bytes(b"%PDF-1.7\n%%EOF\n")
    monkeypatch.delenv(engine_profiles._ALLOWED_ROOTS_ENV, raising=False)
    monkeypatch.setenv(engine_profiles._LEGACY_ALLOWED_ROOTS_ENV, f'["{tmp_path.as_posix()}"]')

    assert engine_profiles._source_path(fixture) == fixture.resolve()
