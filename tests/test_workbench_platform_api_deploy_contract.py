"""Workbench-to-Platform API private-network deployment contract.

Byline: Codex · GPT-5.6-Sol · 2026-08-29
"""

from pathlib import Path

import yaml

_MANIFEST_PATH = Path("deploy/workbench.yaml")


def _workbench() -> dict:
    manifest = yaml.safe_load(_MANIFEST_PATH.read_text(encoding="utf-8"))
    return manifest["services"]["workbench"]


def test_workbench_calls_platform_api_over_private_service_dns() -> None:
    service = _workbench()
    assert service["environment"]["PLATFORM_API_URL"] == "${PLATFORM_API_URL:-http://platform-api:8000}"
    assert "probata" in service["networks"]


def test_platform_api_auth_stays_bearer_file_based_without_basic_auth() -> None:
    service = _workbench()
    environment = service["environment"]
    assert environment["PLATFORM_API_BEARER_SECRET_FILE"] == "/run/secrets/platform-api-bearer"
    assert not any("BASIC" in key or "PASSWORD" in key for key in environment if key.startswith("PLATFORM_API"))
    assert "/data/probata/secrets/platform/api-bearer:/run/secrets/platform-api-bearer:ro" in service["volumes"]


def test_workbench_manifest_has_no_retired_agentos_endpoint() -> None:
    source = _MANIFEST_PATH.read_text(encoding="utf-8").lower()
    assert "agentos-api" not in source
    assert "agentos-mcp" not in source
    assert "agentos.mitechconsult.com" not in source
