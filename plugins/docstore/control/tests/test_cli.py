"""CLI packaging and environment boundaries; no live requests."""
import importlib.util
import json
import sys
import tomllib
from pathlib import Path
from types import SimpleNamespace

import pytest

ROOT = Path(__file__).parents[1]
sys.path.insert(0, str(ROOT))
spec = importlib.util.spec_from_file_location("docstore_control_cli_test", ROOT / "cli.py")
cli = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cli)


def test_plugin_manifest_references_real_entrypoints():
    plugin = json.loads((ROOT / ".claude-plugin/plugin.json").read_text())
    assert plugin["name"] == "probata-docstore-control"
    assert (ROOT / plugin["skills"]).is_dir()
    manifest = json.loads((ROOT / ".mcp.json").read_text())
    assert set(manifest["mcpServers"]) == {"docstore-control", "docstore-surreal"}
    native = manifest["mcpServers"]["docstore-surreal"]
    assert native["headers"]["surreal-ns"] == "probata"
    assert native["headers"]["surreal-db"] == "docs"
    assert native["headers"]["Authorization"] == "Basic ${DOCSTORE_BASIC_AUTH}"
    assert "--no-sync" in manifest["mcpServers"]["docstore-control"]["args"]
    assert manifest['mcpServers']['docstore-control']['env']['DOCSTORE_WORKER_RECEIPTS_DIR']=='${DOCSTORE_WORKER_RECEIPTS_DIR:-}'
    assert manifest['mcpServers']['docstore-control']['env']['DOCSTORE_PROJECT_REGISTRY'].endswith('docs/docstore-source-registry.json}')
    codex = tomllib.loads((ROOT / "codex.config.example.toml").read_text())
    assert set(codex["mcp_servers"]) == set(manifest["mcpServers"])
    assert 'DOCSTORE_WORKER_RECEIPTS_DIR' in codex['mcp_servers']['docstore-control']['env_vars']
    assert 'DOCSTORE_PROJECT_REGISTRY' in codex['mcp_servers']['docstore-control']['env_vars']


def test_control_project_includes_pinned_surreal_sdk():
    project = tomllib.loads((ROOT / 'pyproject.toml').read_text(encoding='utf-8'))
    assert 'surrealdb==3.0.0b8' in project['project']['dependencies']


def test_explicit_env_file_only_loads_docstore_values(monkeypatch, tmp_path):
    settings = tmp_path / "control.env"
    settings.write_text("DOCSTORE_INSTANCE_ID=docstore-file\nCOCOINDEX_DB=bad\nUNRELATED=bad\n")
    monkeypatch.setenv("DOCSTORE_CONTROL_ENV_FILE", str(settings))
    monkeypatch.setenv("COCOINDEX_DB", "keep")
    monkeypatch.delenv("UNRELATED", raising=False)
    monkeypatch.delenv("DOCSTORE_INSTANCE_ID", raising=False)
    assert cli.environment()["DOCSTORE_INSTANCE_ID"] == "docstore-file"
    assert cli.environment()["COCOINDEX_DB"] == "keep"
    assert "UNRELATED" not in cli.environment()
    monkeypatch.setenv("DOCSTORE_INSTANCE_ID", "docstore-process")
    assert cli.environment()["DOCSTORE_INSTANCE_ID"] == "docstore-process"


async def test_catalog_via_cli_is_real_protocol(monkeypatch):
    # No credentials or API calls required to discover operations.
    config = cli.configuration()
    result = await cli.run(SimpleNamespace(command="catalog"), config)
    assert len(result["tools"]) == 40
    assert "coco_docstore_search" in {tool["name"] for tool in result["tools"]}
    assert len(result["resources"]) == 8
    assert {"docstore://api/openapi", "docstore://api/surreal"} <= {r["uri"] for r in result["resources"]}
    assert len(result["resource_templates"]) == 4
    assert len(result["prompts"]) == 2


async def test_project_registry_cli_uses_mcp_tools():
    config = cli.configuration()
    projects = await cli.run(SimpleNamespace(command="projects"), config)
    assert projects["schema"] == "propria-docstore-source-registry-v1"
    assert projects["project_count"] >= 4
    detail = await cli.run(
        SimpleNamespace(command="project", project_id="propria"), config
    )
    assert detail["project"]["project_id"] == "propria"
    assert detail["indexing_triggered"] is False


def test_unhealthy_cli_body_exits_nonzero(monkeypatch, capsys):
    async def unhealthy(*_):
        return {"ok": False, "store": "down"}
    monkeypatch.setattr(cli, "run", unhealthy)
    monkeypatch.setattr(sys, "argv", ["cli.py", "health"])
    assert cli.main() == 1
    assert json.loads(capsys.readouterr().out)["ok"] is False


async def test_revision_cli_rejects_bad_identity_before_network():
    with pytest.raises(Exception):
        await cli.run(SimpleNamespace(command='revision-state',document_key='../not-a-key'),cli.configuration())


async def test_revision_cli_validates_bounded_json_before_network(tmp_path):
    source=tmp_path/'invalid.json'
    source.write_text('{"document_key":"adr:test"}')
    with pytest.raises(Exception):
        await cli.run(SimpleNamespace(command='capture-revision',json_file=str(source)),cli.configuration())


@pytest.mark.asyncio
async def test_selected_plan_cli_rejects_oversized_json_before_server_call(tmp_path):
    source=tmp_path/'oversized.json'
    source.write_bytes(b'x'*65537)
    with pytest.raises(ValueError,match='64 KiB'):
        await cli.run(SimpleNamespace(command='selected-update-plan',json_file=str(source)),cli.configuration())
