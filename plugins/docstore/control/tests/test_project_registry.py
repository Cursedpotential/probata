"""Universal project registry is bounded, read-only, and path-safe."""
from __future__ import annotations

import json
from pathlib import Path
from types import SimpleNamespace

import pytest
from fastmcp import Client
from fastmcp.exceptions import ToolError

from project_registry import load_registry, register


def write_registry(tmp_path: Path, projects: list[dict] | None = None) -> Path:
    root = tmp_path / "propria"
    (root / "docs").mkdir(parents=True)
    (root / "projects" / "consignatio").mkdir(parents=True)
    payload = {
        "schema": "propria-docstore-source-registry-v1",
        "monorepo_root": str(root),
        "projects": projects or [
            {
                "project_id": "propria",
                "title": "Propria governance",
                "source_root": "docs",
                "canonical_prefix": "propria/docs",
                "domains": ["docs"],
                "included_patterns": ["**/*.md"],
                "excluded_patterns": ["**/to_be_deleted/**"],
                "registration_status": "active",
                "ingestion_status": "pending-multi-root-cdc",
                "required": True,
            },
            {
                "project_id": "consignatio",
                "title": "Consignatio",
                "source_root": "projects/consignatio",
                "canonical_prefix": "consignatio",
                "domains": ["consignatio", "intake"],
                "included_patterns": ["**/*.md"],
                "excluded_patterns": [],
                "registration_status": "active",
                "ingestion_status": "pending-multi-root-cdc",
                "required": True,
            },
        ],
    }
    path = tmp_path / "registry.json"
    path.write_text(json.dumps(payload), encoding="utf-8")
    return path


def test_registry_loads_stable_owned_sources_without_reading_documents(tmp_path):
    registry = load_registry(write_registry(tmp_path))
    result = registry.public()
    assert result["project_count"] == 2
    assert result["source_files_read"] is False
    assert result["indexing_triggered"] is False
    assert registry.get("consignatio").canonical_prefix == "consignatio/"
    assert all(project["source_exists"] for project in result["projects"])


@pytest.mark.parametrize("mutation", ["duplicate", "escape", "missing", "absolute-prefix"])
def test_registry_rejects_ambiguous_or_unsafe_sources(tmp_path, mutation):
    path = write_registry(tmp_path)
    payload = json.loads(path.read_text(encoding="utf-8"))
    if mutation == "duplicate":
        payload["projects"][1]["project_id"] = "propria"
    elif mutation == "escape":
        payload["projects"][0]["source_root"] = "../outside"
    elif mutation == "missing":
        payload["projects"][0]["source_root"] = "missing"
    else:
        payload["projects"][0]["canonical_prefix"] = "/absolute"
    path.write_text(json.dumps(payload), encoding="utf-8")
    with pytest.raises((ValueError, ToolError)):
        load_registry(path)


async def test_registry_tools_and_resources_are_discoverable(tmp_path):
    from fastmcp import FastMCP

    path = write_registry(tmp_path)
    config = SimpleNamespace(project_registry=path)
    read = {"readOnlyHint": True, "destructiveHint": False,
            "idempotentHint": True, "openWorldHint": False}
    mcp = FastMCP("registry-test")
    register(mcp, config, read)
    async with Client(mcp) as client:
        tools = {tool.name: tool for tool in await client.list_tools()}
        assert {"docstore_project_sources", "docstore_project_source"} <= tools.keys()
        assert all(tool.annotations.readOnlyHint for tool in tools.values())
        result = (await client.call_tool("docstore_project_sources", {})).data
        assert result["project_count"] == 2
        detail = (await client.call_tool(
            "docstore_project_source", {"project_id": "propria"}
        )).data
        assert detail["project"]["canonical_prefix"] == "propria/docs/"
        resources = {str(resource.uri) for resource in await client.list_resources()}
        assert "docstore://projects" in resources
        payload = json.loads((await client.read_resource("docstore://projects"))[0].text)
        assert payload["project_count"] == 2
        templates = {template.uriTemplate for template in await client.list_resource_templates()}
        assert "docstore://project/{project_id}" in templates


async def test_unconfigured_registry_is_visible_but_tools_fail_closed():
    from fastmcp import FastMCP

    config = SimpleNamespace(project_registry=None)
    mcp = FastMCP("registry-test")
    register(mcp, config, {"readOnlyHint": True, "destructiveHint": False})
    async with Client(mcp) as client:
        resource = json.loads((await client.read_resource("docstore://projects"))[0].text)
        assert resource["status"] == "unconfigured"
        result = await client.call_tool("docstore_project_sources", {}, raise_on_error=False)
        assert result.is_error
