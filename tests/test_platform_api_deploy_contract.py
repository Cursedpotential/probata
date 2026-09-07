"""Static production contract for the framework-neutral Platform API cutover.

Byline: Codex · GPT-5.6-Sol · 2026-08-29.

These checks validate tracked deployment/package inputs only. They do not prove
that Coolify has deployed the revision or that the live service is healthy.
"""

from __future__ import annotations

from pathlib import Path

import tomllib

import yaml

ROOT = Path(__file__).resolve().parents[1]
DOCKERFILE = ROOT / "Dockerfile"
MANIFEST = ROOT / "deploy" / "exec.yaml"
PYPROJECT = ROOT / "pyproject.toml"
REQUIREMENTS = ROOT / "requirements.txt"


def _manifest() -> dict:
    return yaml.safe_load(MANIFEST.read_text(encoding="utf-8"))


def _project() -> dict:
    with PYPROJECT.open("rb") as stream:
        return tomllib.load(stream)["project"]


def test_platform_api_is_the_only_exec_service_and_keeps_the_plain_fastapi_entrypoint() -> None:
    services = _manifest()["services"]

    assert set(services) == {"platform-api"}
    service = services["platform-api"]
    assert service["container_name"] == "platform-api"
    assert service["image"] == "${IMAGE_NAME:-platform-api}:${IMAGE_TAG:-latest}"
    assert service["command"] == "uvicorn server.api.main:app --host 0.0.0.0 --port 8000"


def test_platform_api_has_no_public_traefik_or_agentos_mcp_surface() -> None:
    text = MANIFEST.read_text(encoding="utf-8")
    service = _manifest()["services"]["platform-api"]

    assert "labels" not in service
    assert service["ports"] == ["${BIND_IP:-127.0.0.1}:8000:8000"]
    for retired_surface in ("agentos-api", "agentos-mcp", "AgentOS", "enable_mcp_server", "agentos.mitechconsult.com"):
        assert retired_surface not in text


def test_agentos_runtime_settings_are_absent_without_inventing_replacement_secrets() -> None:
    environment = _manifest()["services"]["platform-api"]["environment"]

    assert not any(key.startswith("AGENTOS_") for key in environment)
    assert "PLATFORM_API_PASSWORD" not in environment
    assert "BASIC_AUTH_PASSWORD" not in environment
    assert "OS_SECURITY_KEY" not in environment
    assert "PLATFORM_API_BEARER" not in environment


def test_platform_api_bearer_is_a_read_only_runtime_file_not_an_environment_secret() -> None:
    service = _manifest()["services"]["platform-api"]
    bearer_mounts = [
        volume
        for volume in service["volumes"]
        if isinstance(volume, dict) and volume.get("target") == "/run/secrets/platform-api-bearer"
    ]

    assert bearer_mounts == [
        {
            "type": "bind",
            "source": "/data/probata/secrets/platform/api-bearer",
            "target": "/run/secrets/platform-api-bearer",
            "read_only": True,
            "bind": {"create_host_path": False},
        }
    ]


def test_fastmcp_is_not_a_platform_api_dependency_but_agno_atomic_adapter_remains() -> None:
    project = _project()
    direct_dependencies = project["dependencies"]
    dockerfile = DOCKERFILE.read_text(encoding="utf-8").lower()
    requirements = REQUIREMENTS.read_text(encoding="utf-8").lower().splitlines()

    assert project["name"] == "platform-api"
    assert not any(dependency.lower().startswith("fastmcp") for dependency in direct_dependencies)
    assert "uv pip install --system fastmcp" not in dockerfile
    assert not any(line.startswith("fastmcp") for line in requirements)
    assert "agno" in {dependency.lower() for dependency in direct_dependencies}
    assert not any(dependency.lower().startswith("agno[") for dependency in direct_dependencies)
