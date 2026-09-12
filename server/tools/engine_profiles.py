"""Versioned runtime identity and extraction certification for tool-runtime.

The tools in this module are deliberately read-only and transport-neutral.  The
same functions can run in-process, through the internal tool-runtime REST
facade, behind Context Forge, or from one Temporal Activity.  They never persist
receipts or orchestrate another step; the caller owns those concerns.

Only stdlib modules are imported at module scope because the tool-runtime
registry discovers this module inside its dependency-light container.
"""

from __future__ import annotations

import codecs
import hashlib
import json
import os
import platform
import shutil
import subprocess
import tempfile
import time
from pathlib import Path
from typing import Any

from server.tools.registry import register


_PROVENANCE = "Debian poppler-utils plus server/tools/engine_profiles.py"
_HASH_BLOCK_BYTES = 1024 * 1024
_MAX_TIMEOUT_SECONDS = 300.0
_STDERR_LIMIT = 8_192
_POPPLER_PACKAGE = "poppler-utils"
_ALLOWED_ROOTS_ENV = "TOOL_RUNTIME_ALLOWED_READ_ROOTS_JSON"
_LEGACY_ALLOWED_ROOTS_ENV = "PLATTOOLS_ALLOWED_READ_ROOTS_JSON"
_LINE_BREAKS = frozenset("\n\r\v\f\x1c\x1d\x1e\x85\u2028\u2029")


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(_HASH_BLOCK_BYTES), b""):
            digest.update(block)
    return digest.hexdigest()


def _source_path(value: Any) -> Path:
    source = Path(str(value)).resolve()
    if not source.is_file():
        raise FileNotFoundError(source)

    configured_name = _ALLOWED_ROOTS_ENV
    configured = os.environ.get(configured_name)
    if not configured:
        configured_name = _LEGACY_ALLOWED_ROOTS_ENV
        configured = os.environ.get(configured_name)
    if not configured:
        return source
    try:
        values = json.loads(configured)
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"{configured_name} is not valid JSON") from exc
    if not isinstance(values, list) or not values or not all(isinstance(value, str) for value in values):
        raise RuntimeError(f"{configured_name} must be a non-empty JSON array of paths")
    roots = tuple(Path(value).resolve() for value in values)
    if not any(source == root or root in source.parents for root in roots):
        raise ValueError("source path is outside the tool runtime's allowed read roots")
    return source


def _utf8_metrics(path: Path, glyph: str) -> dict[str, Any]:
    """Hash and inspect an extraction stream without retaining its content."""

    decoder = codecs.getincrementaldecoder("utf-8")(errors="strict")
    digest = hashlib.sha256()
    unicode_characters = 0
    line_count = 0
    replacement_count = 0
    glyph_count = 0
    previous_character = ""
    utf8_valid = True

    def consume(text: str) -> None:
        nonlocal unicode_characters, line_count, replacement_count, glyph_count, previous_character
        unicode_characters += len(text)
        replacement_count += text.count("\ufffd")
        glyph_count += text.count(glyph)
        for character in text:
            if character in _LINE_BREAKS and not (character == "\n" and previous_character == "\r"):
                line_count += 1
            previous_character = character

    try:
        with path.open("rb") as handle:
            for block in iter(lambda: handle.read(_HASH_BLOCK_BYTES), b""):
                digest.update(block)
                consume(decoder.decode(block, final=False))
            consume(decoder.decode(b"", final=True))
    except UnicodeDecodeError:
        utf8_valid = False

    if unicode_characters and previous_character not in _LINE_BREAKS:
        line_count += 1
    return {
        "output_sha256": digest.hexdigest(),
        "unicode_characters": unicode_characters,
        "line_count": line_count,
        "replacement_count": replacement_count,
        "glyph_count": glyph_count,
        "utf8_valid": utf8_valid,
    }


def _architecture() -> str:
    machine = platform.machine().lower()
    return {
        "amd64": "amd64",
        "x86_64": "amd64",
        "arm64": "arm64",
        "aarch64": "arm64",
    }.get(machine, machine or "unknown")


def _operating_system() -> str:
    return platform.system().lower() or "unknown"


def _profile_id() -> str:
    return f"poppler-{_operating_system()}-{_architecture()}"


def _bounded_timeout(value: Any) -> float:
    try:
        timeout = float(value)
    except (TypeError, ValueError) as exc:
        raise ValueError("timeout_seconds must be numeric") from exc
    if timeout <= 0 or timeout > _MAX_TIMEOUT_SECONDS:
        raise ValueError(f"timeout_seconds must be greater than 0 and at most {_MAX_TIMEOUT_SECONDS:g}")
    return timeout


def _run(command: list[str], *, timeout: float) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        check=False,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=timeout,
    )


def _package_version(timeout: float) -> str | None:
    if _operating_system() != "linux" or shutil.which("dpkg-query") is None:
        return None
    result = _run(
        ["dpkg-query", "--show", "--showformat=${Version}", _POPPLER_PACKAGE],
        timeout=timeout,
    )
    value = result.stdout.strip()
    return value if result.returncode == 0 and value else None


def _inspect_poppler(payload: dict[str, Any]) -> dict[str, Any]:
    timeout = _bounded_timeout(payload.get("timeout_seconds", 10))
    executable_name = "pdftotext.exe" if _operating_system() == "windows" else "pdftotext"
    resolved = shutil.which(executable_name) or shutil.which("pdftotext")
    profile_id = _profile_id()
    expected_profile_id = payload.get("expected_profile_id")
    expected_package_version = payload.get("expected_package_version")

    if resolved is None:
        return {
            "ready": False,
            "engine_id": "poppler",
            "profile_id": profile_id,
            "operating_system": _operating_system(),
            "architecture": _architecture(),
            "executable": None,
            "executable_sha256": None,
            "version": None,
            "package": _POPPLER_PACKAGE,
            "package_version": None,
            "capabilities": ["pdf.text.extract"],
            "command": [executable_name, "-v"],
            "checks": [{"id": "executable-resolved", "passed": False, "expected": True, "observed": False}],
        }

    executable = Path(resolved).resolve()
    command = [str(executable), "-v"]
    result = _run(command, timeout=timeout)
    version_text = (result.stderr or result.stdout).splitlines()
    version = version_text[0].strip() if version_text else None
    package_version = _package_version(timeout)
    checks: list[dict[str, Any]] = [
        {"id": "executable-resolved", "passed": True, "expected": True, "observed": True},
        {
            "id": "version-command-exit-zero",
            "passed": result.returncode == 0,
            "expected": 0,
            "observed": result.returncode,
        },
        {"id": "version-reported", "passed": bool(version), "expected": True, "observed": bool(version)},
    ]
    if expected_profile_id is not None:
        checks.append(
            {
                "id": "profile-id",
                "passed": profile_id == str(expected_profile_id),
                "expected": str(expected_profile_id),
                "observed": profile_id,
            }
        )
    if expected_package_version is not None:
        checks.append(
            {
                "id": "package-version",
                "passed": package_version == str(expected_package_version),
                "expected": str(expected_package_version),
                "observed": package_version,
            }
        )

    return {
        "ready": all(check["passed"] for check in checks),
        "engine_id": "poppler",
        "profile_id": profile_id,
        "operating_system": _operating_system(),
        "architecture": _architecture(),
        "executable": str(executable),
        "executable_sha256": _sha256(executable),
        "version": version,
        "package": _POPPLER_PACKAGE,
        "package_version": package_version,
        "capabilities": ["pdf.text.extract"],
        "command": command,
        "checks": checks,
    }


@register(
    id="engine.poppler-inspect",
    capability="engine.inspect",
    description="Report the exact Poppler platform profile, executable identity, and readiness",
    provenance=_PROVENANCE,
    tool_version="1.0.0",
    contract_version="1.0.0",
    input_schema_version="1.0.0",
    output_schema_version="1.0.0",
    formats=("pdf",),
    quality={"pdf": "primary"},
)
def inspect_poppler(payload: dict[str, Any]) -> dict[str, Any]:
    """Inspect Poppler without reading or changing a corpus artifact."""

    return _inspect_poppler(payload)


def _check(check_id: str, expected: Any, observed: Any) -> dict[str, Any]:
    return {"id": check_id, "passed": expected == observed, "expected": expected, "observed": observed}


@register(
    id="engine.poppler-certify-text",
    capability="engine.certify",
    description="Run bounded Poppler text extraction and return content-free reproducibility checks",
    provenance=_PROVENANCE,
    tool_version="1.0.0",
    contract_version="1.0.0",
    input_schema_version="1.0.0",
    output_schema_version="1.0.0",
    formats=("pdf",),
    quality={"pdf": "primary"},
)
def certify_poppler_text(payload: dict[str, Any]) -> dict[str, Any]:
    """Certify one PDF by locator/path without returning its extracted content.

    ``expected`` may contain ``input_sha256``, ``input_bytes``, ``glyph``,
    ``glyph_count``, ``replacement_count``, or ``output_sha256``.  Omitting a
    comparison field records the observed value without fabricating a pass.
    """

    if "path" not in payload:
        raise ValueError("payload must include 'path'")
    source = _source_path(payload["path"])

    timeout = _bounded_timeout(payload.get("timeout_seconds", 30))
    expected = payload.get("expected") or {}
    if not isinstance(expected, dict):
        raise ValueError("expected must be an object")

    profile = _inspect_poppler(
        {
            "timeout_seconds": min(timeout, 10),
            "expected_profile_id": payload.get("expected_profile_id"),
            "expected_package_version": payload.get("expected_package_version"),
        }
    )
    if not profile["ready"] or not profile["executable"]:
        return {
            "passed": False,
            "profile": profile,
            "source": str(source),
            "command": None,
            "checks": profile["checks"],
            "error": "Poppler profile is not ready",
        }

    input_bytes = source.stat().st_size
    input_sha256 = _sha256(source)
    started = time.monotonic()
    with tempfile.TemporaryDirectory(prefix="tool-runtime-poppler-") as temp_dir:
        output = Path(temp_dir) / "extracted.txt"
        command = [
            str(profile["executable"]),
            "-enc",
            "UTF-8",
            "-eol",
            "unix",
            str(source),
            str(output),
        ]
        try:
            result = _run(command, timeout=timeout)
            timed_out = False
        except subprocess.TimeoutExpired as exc:
            result = subprocess.CompletedProcess(command, 124, "", str(exc))
            timed_out = True

        output_exists = output.is_file()
        output_bytes = output.stat().st_size if output_exists else 0
        output_sha256 = _sha256(output) if output_exists else None
        utf8_valid = False
        unicode_characters = 0
        line_count = 0
        replacement_count = 0
        glyph = str(expected.get("glyph", "\u25a0"))
        if len(glyph) != 1:
            raise ValueError("expected.glyph must be exactly one Unicode character")
        glyph_count = 0
        if output_exists:
            metrics = _utf8_metrics(output, glyph)
            output_sha256 = metrics["output_sha256"]
            utf8_valid = metrics["utf8_valid"]
            unicode_characters = metrics["unicode_characters"]
            line_count = metrics["line_count"]
            replacement_count = metrics["replacement_count"]
            glyph_count = metrics["glyph_count"]

    checks: list[dict[str, Any]] = [
        _check("profile-ready", True, profile["ready"]),
        _check("command-exit-zero", 0, result.returncode),
        _check("command-did-not-time-out", False, timed_out),
        _check("output-created", True, output_exists),
        _check("output-nonempty", True, output_bytes > 0),
        _check("utf8-valid", True, utf8_valid),
    ]
    observed = {
        "input_sha256": input_sha256,
        "input_bytes": input_bytes,
        "output_sha256": output_sha256,
        "output_bytes": output_bytes,
        "unicode_characters": unicode_characters,
        "line_count": line_count,
        "replacement_count": replacement_count,
        "glyph": glyph,
        "glyph_count": glyph_count,
    }
    for field in ("input_sha256", "input_bytes", "output_sha256", "replacement_count", "glyph_count"):
        if field in expected:
            checks.append(_check(field.replace("_", "-"), expected[field], observed[field]))

    return {
        "passed": all(check["passed"] for check in checks),
        "profile": profile,
        "source": str(source),
        "command": command,
        "duration_ms": round((time.monotonic() - started) * 1000, 3),
        "observed": observed,
        "checks": checks,
        "stderr": (result.stderr or "")[:_STDERR_LIMIT] or None,
        "error": None if result.returncode == 0 else "Poppler extraction failed",
    }
