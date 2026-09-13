"""Protocol-level checks: synthetic files and intercepted HTTP only, no live store."""
import hashlib
import importlib.util
import json
import subprocess
import sys
from dataclasses import replace
from pathlib import Path
from types import SimpleNamespace

import httpx
import pytest
from fastmcp import Client

# The parent repository also has a `server` package. Load this entrypoint by
# exact file so running tests from the repository root cannot import that app.
_spec = importlib.util.spec_from_file_location("docstore_control_test_target", Path(__file__).parents[1] / "server.py")
_module = importlib.util.module_from_spec(_spec)
sys.modules[_spec.name] = _module
_spec.loader.exec_module(_module)
Config, build_server = _module.Config, _module.build_server


@pytest.fixture
def config(tmp_path):
    source = tmp_path / "docs"
    source.mkdir()
    return Config("https://docstore.invalid", source, tmp_path / "state", "docstore-test", "synthetic-token")


def harness(config, handler=None):
    requests = []

    def respond(request):
        requests.append(request)
        if handler:
            return handler(request)
        return httpx.Response(200, json={"ok": True, "path": request.url.path})

    return build_server(config, httpx.MockTransport(respond)), requests


async def test_discovery_and_capabilities_have_no_network_or_state_writes(config):
    server, requests = harness(config)
    async with Client(server) as client:
        tools = {tool.name: tool for tool in await client.list_tools()}
        assert {"docstore_capabilities", "docstore_health", "docstore_stats", "docstore_search",
                "coco_docstore_search",
                "docstore_get", "docstore_graph", "docstore_index_plan", "docstore_graph_schema",
                "docstore_graph_query_preview", "docstore_graph_query", "docstore_run_current",
                "docstore_run_get", "docstore_run_list", "docstore_attribution_verify"} <= tools.keys()
        assert {"docstore_reconcile_query", "docstore_reconcile_packet",
                "docstore_reconcile_validate"} <= tools.keys()
        assert 'docstore_selected_update_plan' in tools
        assert 'docstore_cdc_runs' in tools
        writes = {"docstore_set_flags", "docstore_capture_revision", "docstore_approve_revision",
                  "docstore_index_execute", "docstore_cancel_run", "docstore_index_full",
                  "docstore_index_selected", "docstore_run_cancel"}
        writes.add("docstore_reconcile_packet")
        writes.add("docstore_handoff_write")
        assert writes <= tools.keys()
        assert all(not tools[name].annotations.readOnlyHint for name in writes)
        assert all(tool.annotations.readOnlyHint for name, tool in tools.items() if name not in writes)
        assert all(not tool.annotations.destructiveHint for tool in tools.values())
        resources = await client.list_resources()
        assert {"docstore://capabilities", "docstore://health"} <= {str(r.uri) for r in resources}
        templates = await client.list_resource_templates()
        assert "docstore://document/{record_id}" in {r.uriTemplate for r in templates}
        prompts = await client.list_prompts()
        assert "reconcile_documentation" in {p.name for p in prompts}
        assert "plan_docstore_graph_query" in {p.name for p in prompts}
        capabilities = (await client.call_tool("docstore_capabilities", {})).data
        assert capabilities["ambient_COCOINDEX_DB_consumed"] is False
        assert capabilities["pipeline_identity_verification_available"] is True
        assert capabilities["index_execution_available"] is True
        assert capabilities["write_registration_available"] is True
        assert capabilities["worker_run_status_available"] is True
        assert capabilities["worker_run_history_available"] is True
        assert capabilities["cdc_attribution_available"] is True
        resource = await client.read_resource("docstore://capabilities")
        assert json.loads(resource[0].text)["instance"] == config.instance
        viewer = (await client.call_tool("docstore_surrealist", {})).data
        assert viewer["opened"] is False
        assert viewer["identity_verified_live"] is False
        assert config.token not in json.dumps(viewer)
        assert json.loads((await client.read_resource("docstore://surrealist"))[0].text) == viewer
        prompt = await client.get_prompt("reconcile_documentation", {"domain": "intake", "subject": "indexing"})
        assert "Do not start indexing" in prompt.messages[0].content.text
    assert not requests
    assert not config.state_root.exists()


async def test_live_api_schema_resource_uses_configured_transport(config):
    # Codex | 2026-09-12: API reference must be fetched, not a static promise.
    expected = {"openapi": "3.1.0", "paths": {"/recall": {"get": {}}}}
    server, requests = harness(config, lambda request: httpx.Response(200, json=expected))
    async with Client(server) as client:
        result = await client.read_resource("docstore://api/openapi")
    assert json.loads(result[0].text) == expected
    assert requests[0].url.path == "/openapi.json"
    assert requests[0].headers["authorization"] == "Bearer synthetic-token"


async def test_api_schema_resource_rejects_invalid_response(config):
    server, _ = harness(config)
    async with Client(server) as client:
        with pytest.raises(Exception, match="no valid OpenAPI schema"):
            await client.read_resource("docstore://api/openapi")


async def test_handoff_write_is_typed_and_read_back(config, monkeypatch):
    import handoff as handoff_module

    calls = []

    async def execute(_config, sql, parameters):
        calls.append((sql, parameters))
        return {
            "written": {"id": "document:new_handoff", "superseded": "document:old_handoff"},
            "created": {
                "id": "document:new_handoff",
                "title": parameters["title"],
                "body": parameters["body"],
                "doc_type": "handoff",
                "domains": parameters["domains"],
                "status": "active",
                "source_path": "handoff://engine-recovery/synthetic",
            },
            "previous": {"id": "document:old_handoff", "status": "superseded"},
        }

    original = handoff_module.write_handoff

    async def injected(config_value, item):
        return await original(config_value, item, execute=execute)

    monkeypatch.setattr(handoff_module, "write_handoff", injected)
    server, requests = harness(config)
    async with Client(server) as client:
        result = (await client.call_tool("docstore_handoff_write", {"handoff": {
            "title": "Engine recovery",
            "body": "STATUS: paused\nUNRESOLVED: live proof",
            "domains": ["workbench", "proffer"],
        }})).data
    assert result == {
        "id": "document:new_handoff",
        "superseded": "document:old_handoff",
        "doc_type": "handoff",
        "domains": ["proffer", "workbench"],
        "status": "active",
        "verified_readback": True,
        "indexing_triggered": False,
    }
    assert "fn::handoff_write" in calls[0][0]
    assert calls[0][1]["domains"] == ["proffer", "workbench"]
    assert not requests


@pytest.mark.parametrize("payload", [
    {"title": "", "body": "body", "domains": ["docs"]},
    {"title": "title", "body": "", "domains": ["docs"]},
    {"title": "title", "body": "body", "domains": []},
    {"title": "title", "body": "body", "domains": ["docs", "docs"]},
    {"title": "title", "body": "body", "domains": ["unknown"]},
])
async def test_handoff_write_rejects_invalid_payload_without_network(config, payload):
    server, requests = harness(config)
    async with Client(server) as client:
        result = await client.call_tool(
            "docstore_handoff_write", {"handoff": payload}, raise_on_error=False
        )
    assert result.is_error
    assert not requests


@pytest.mark.parametrize("tool,path", [("docstore_health", "/health"), ("docstore_stats", "/stats")])
async def test_health_and_stats(config, tool, path):
    server, requests = harness(config)
    async with Client(server) as client:
        assert (await client.call_tool(tool, {})).data["ok"]
    assert requests[0].method == "GET"
    assert requests[0].url.path == path
    assert requests[0].headers["authorization"] == "Bearer synthetic-token"


async def test_search_defaults_and_explicit_options(config):
    server, requests = harness(config)
    async with Client(server) as client:
        await client.call_tool("docstore_search", {"query": "index isolation", "domain": "intake"})
        assert dict(requests[-1].url.params) == {
            "q": "index isolation", "domain": "intake", "kind": "doc", "status": "active", "k": "8", "rerank": "false"}
        await client.call_tool("docstore_search", {"query": "index isolation", "domain": "intake",
            "kind": "adr", "status": "all", "limit": 3, "rerank": True})
    assert dict(requests[-1].url.params) == {
        "q": "index isolation", "domain": "intake", "kind": "adr", "status": "all", "k": "3", "rerank": "true"}


async def test_coco_search_is_primary_surreal_vector_path_with_duckdb_presentation(config):
    server, requests = harness(config, lambda request: httpx.Response(200, json={
        "query": "docstore vectors", "results": [{"id": "document:x", "title": "Vector design",
        "snippet": "SurrealDB vector search", "via": "kw+vec"}], "stats": {"vec_docs": 1}}))
    async with Client(server) as client:
        compact = (await client.call_tool("coco_docstore_search", {
            "query": "docstore vectors", "domain": "docs"})).data
        assert compact["format"] == "compact-columns-v1"
        assert compact["data"]["results"]["row_count"] == 1
        full = (await client.call_tool("coco_docstore_search", {
            "query": "docstore vectors", "domain": "docs", "presentation": "full"})).data
        assert full["results"][0]["via"] == "kw+vec"
        assert full["retrieval"] == {
            "indexer": "CocoIndex", "query_embedding": "NVIDIA NIM",
            "vector_store": "SurrealDB", "namespace": "probata", "database": "docs",
            "ranking": "BM25+KNN RRF", "duckdb_role": "result presentation/filtering only",
            "secondary_vector_store": None}
    assert len(requests) == 2
    assert all(request.url.path == "/recall" for request in requests)


async def test_compact_tool_uses_existing_document_transport(config):
    server, requests = harness(config, lambda request: httpx.Response(200, json={
        'id': 'document:test', 'body': 'a'*2000, 'status': 'active'}))
    async with Client(server) as client:
        result = (await client.call_tool('docstore_compact', {
            'operation': 'document', 'record_id': 'document:test'})).data
        assert result['format'] == 'compact-columns-v1'
        assert result['data']['id'] == 'document:test'
        assert result['omissions'][0]['original_chars'] == 2000
        full = (await client.call_tool('docstore_get', {'record_id':'document:test'})).data
        assert len(full['body']) == 2000
    assert len(requests) == 2


@pytest.mark.parametrize("arguments", [
    {"query": " ", "domain": "intake"}, {"query": "   ", "domain": "intake"},
    {"query": "valid", "domain": "unknown"}, {"query": "valid", "domain": "intake", "limit": 21},
    {"query": "valid", "domain": "intake", "limit": 0}, {"query": "x" * 2049, "domain": "intake"},
])
async def test_search_rejects_invalid_input_without_http(config, arguments):
    server, requests = harness(config)
    async with Client(server) as client:
        result = await client.call_tool("docstore_search", arguments, raise_on_error=False)
        assert result.is_error
    assert not requests


async def test_documents_graph_and_resources(config):
    server, requests = harness(config)
    async with Client(server) as client:
        await client.call_tool("docstore_get", {"record_id": "document:abc_123"})
        assert requests[-1].url.path == "/doc/document:abc_123"
        await client.call_tool("docstore_graph", {"record_id": "document:abc_123"})
        assert requests[-1].url.path == "/graph/document:abc_123"
        assert dict(requests[-1].url.params) == {"limit": "25", "format": "json"}
        await client.read_resource("docstore://document/document:abc_123")
        assert requests[-1].url.path == "/doc/document:abc_123"
        await client.read_resource("docstore://health")
        assert requests[-1].url.path == "/health"
        await client.read_resource("docstore://stats")
        assert requests[-1].url.path == "/stats"
        await client.read_resource("docstore://graph/document:abc_123")
        assert requests[-1].url.path == "/graph/document:abc_123"


@pytest.mark.parametrize("tool,record_id", [
    ("docstore_get", "../secrets"), ("docstore_get", "document:a?x=1"),
    ("docstore_graph", "abc"), ("docstore_graph", "document:../abc"),
])
async def test_record_injection_rejected(config, tool, record_id):
    server, requests = harness(config)
    async with Client(server) as client:
        assert (await client.call_tool(tool, {"record_id": record_id}, raise_on_error=False)).is_error
    assert not requests


@pytest.mark.parametrize("failure", ["status", "invalid_json", "transport", "redirect", "non_object"])
async def test_failures_are_sanitized(config, failure):
    secret = "synthetic-upstream-private-detail"

    def respond(request):
        if failure == "transport":
            raise httpx.ConnectError(secret, request=request)
        if failure == "status":
            return httpx.Response(500, text=secret)
        if failure == "redirect":
            return httpx.Response(302, headers={"location": "https://other.invalid/" + secret})
        if failure == "non_object":
            return httpx.Response(200, json=[secret])
        return httpx.Response(200, text=secret)

    server, requests = harness(config, respond)
    async with Client(server) as client:
        result = await client.call_tool("docstore_health", {}, raise_on_error=False)
        assert result.is_error
        text = " ".join(c.text for c in result.content)
        assert "Docstore unavailable" in text
        assert secret not in text
        assert config.token not in text
    assert len(requests) == 1


async def test_oversized_response_rejected(config):
    server, _ = harness(config, lambda _: httpx.Response(200, content=b"x" * (2 * 1024 * 1024 + 1)))
    async with Client(server) as client:
        result = await client.call_tool("docstore_health", {}, raise_on_error=False)
        assert result.is_error
        assert "too large" in result.content[0].text


async def test_index_plan_hashes_without_network_or_source_mutation(config):
    content = b"# Synthetic document\n"
    (config.source_root / "note.md").write_bytes(content)
    server, requests = harness(config)
    async with Client(server) as client:
        result = (await client.call_tool("docstore_index_plan", {"paths": ["note.md"]})).data
    assert result["executed"] is False
    assert result["source_changed"] is False
    assert result["files"] == [{"path": "note.md", "bytes": len(content), "sha256": hashlib.sha256(content).hexdigest()}]
    assert (config.source_root / "note.md").read_bytes() == content
    assert not requests
    assert not config.state_root.exists()


async def test_governed_run_tools_use_live_job_api(config):
    (config.source_root / "note.md").write_text("# note\n")
    server, requests = harness(config)
    async with Client(server) as client:
        started = (await client.call_tool("docstore_index_execute", {"paths": ["note.md"]})).data
        assert started["ok"] is True
        await client.call_tool("docstore_run_status", {"run_id": "a" * 32})
        await client.call_tool("docstore_cancel_run", {"run_id": "a" * 32})
        await client.call_tool("docstore_pipeline_identity", {})
        await client.call_tool("docstore_index_full", {})
        await client.call_tool("docstore_index_selected", {"paths": ["note.md"]})
        await client.call_tool("docstore_run_current", {})
        await client.call_tool("docstore_run_get", {"run_id": "b" * 32})
        await client.call_tool("docstore_run_list", {"limit": 7})
        await client.call_tool("docstore_run_cancel", {"run_id": "b" * 32})
        await client.call_tool("docstore_attribution_verify", {})
    assert requests[0].method == "POST" and requests[0].url.path == "/runs"
    assert json.loads(requests[0].content) == {"scope": "selected", "paths": ["docs/note.md"],
                                               "full_reprocess": False, "index_kind": "docs"}
    assert requests[1].method == "GET" and requests[1].url.path == "/runs/" + "a" * 32
    assert requests[2].method == "DELETE" and requests[2].url.path == "/runs/" + "a" * 32
    assert requests[3].url.path == "/pipeline"
    assert requests[4].method == "POST" and json.loads(requests[4].content) == {
        "scope": "full", "paths": [], "full_reprocess": False, "tracking_rebuild": False,
        "index_kind": "docs"}
    assert requests[5].method == "POST" and json.loads(requests[5].content) == {
        "scope": "selected", "paths": ["docs/note.md"], "full_reprocess": False, "index_kind": "docs"}
    assert requests[6].url.path == "/runs/current"
    assert requests[7].url.path == "/runs/" + "b" * 32
    assert requests[8].url.path == "/runs" and requests[8].url.params["limit"] == "7"
    assert requests[9].method == "DELETE" and requests[9].url.path == "/runs/" + "b" * 32
    assert requests[10].url.path == "/attribution"


async def test_bounded_graph_management_tools_are_first_class(config):
    server, requests = harness(config)
    arguments = {"subject": "document:abc", "relation_types": ["cites"], "direction": "out",
                 "limit": 9, "source_prefix": "docs/adr/", "observed_from": "2026-01-01",
                 "observed_to": "2026-12-31", "export_format": "csv"}
    async with Client(server) as client:
        await client.call_tool("docstore_graph_schema", {})
        await client.call_tool("docstore_graph_query_preview", arguments)
        await client.call_tool("docstore_graph_query", arguments)
        contract = json.loads((await client.read_resource("docstore://graph-query-contract"))[0].text)
        assert contract["mutation_allowed"] is False
    assert requests[0].url.path == "/graph-schema"
    assert requests[1].url.path == "/graph-query" and requests[1].url.params["preview"] == "true"
    assert requests[2].url.path == "/graph-query" and requests[2].url.params["preview"] == "false"
    assert requests[2].url.params["relations"] == "cites"
    assert requests[2].url.params["index_kind"] == "docs"


async def test_reconciliation_adapter_contract_has_explicit_per_store_state(config, tmp_path, monkeypatch):
    launcher=tmp_path/'reconcile.cmd'; launcher.write_text('@echo off\n')
    config=replace(config,reconciliation_launcher=launcher)
    calls=[]
    response={"schema":"propria-reconcile/v1","operation":"query","query":"contract",
              "mode":"selected","project_root":str(tmp_path),"store_runs":[{
              "store":"ccc","requested":True,"available":True,"queried":True,"skipped":False,
              "error":None,"adapter":"ccc","identity":{"root":str(tmp_path)},"duration_ms":1,
              "result_count":0}],"results":[],"decisions":[],"contracts":[],"conflicts":[],
              "attribution_clean":None,"packet_path":None,"errors":[]}
    def run(args,**kwargs):
        calls.append((args,json.loads(kwargs['input'])))
        return subprocess.CompletedProcess(args,0,json.dumps(response),'')
    monkeypatch.setattr(_module.subprocess,'run',run)
    server,_=harness(config)
    async with Client(server) as client:
        value=(await client.call_tool("docstore_reconcile_query",{
            "query":"contract","mode":"selected","stores":["ccc"],
            "project_root":str(tmp_path)})).data
        assert value['store_runs'][0]['queried'] is True
        invalid=await client.call_tool("docstore_reconcile_query",{
            "query":"contract","mode":"selected","stores":[]},raise_on_error=False)
        assert invalid.is_error
    assert calls[0][0][1:]==['query','--request-stdin']
    assert calls[0][1]['schema']=='propria-reconcile/v1'


@pytest.mark.parametrize("paths", [["../outside.md"], ["missing.md"], ["wrong.txt"], [], ["a.md"] * 21])
async def test_index_plan_rejects_unsafe_or_unreadable_inputs(config, paths):
    server, requests = harness(config)
    async with Client(server) as client:
        assert (await client.call_tool("docstore_index_plan", {"paths": paths}, raise_on_error=False)).is_error
    assert not requests


async def test_index_plan_rejects_absolute_path_and_large_file(config):
    (config.source_root / "large.md").write_bytes(b"x" * (1024 * 1024 + 1))
    server, requests = harness(config)
    async with Client(server) as client:
        for path in [str(config.source_root / "large.md"), "large.md"]:
            assert (await client.call_tool("docstore_index_plan", {"paths": [path]}, raise_on_error=False)).is_error
    assert not requests


@pytest.mark.parametrize("attribute", [0x1000, 0x40000, 0x400000])
async def test_cloud_placeholder_never_opened(config, monkeypatch, attribute):
    target = config.source_root / "cloud.md"
    original_stat, original_open = Path.stat, Path.open
    opened = []

    def fake_stat(path, *args, **kwargs):
        if path == target:
            return SimpleNamespace(st_file_attributes=attribute, st_size=1)
        return original_stat(path, *args, **kwargs)

    def guarded_open(path, *args, **kwargs):
        if path == target:
            opened.append(path)
            raise AssertionError("Hydration attempted")
        return original_open(path, *args, **kwargs)

    server, requests = harness(config)
    async with Client(server) as client:
        with monkeypatch.context() as patch:
            patch.setattr(Path, "stat", fake_stat)
            patch.setattr(Path, "open", guarded_open)
            result = await client.call_tool("docstore_index_plan", {"paths": ["cloud.md"]}, raise_on_error=False)
            assert result.is_error
            assert "hydration" in result.content[0].text
    assert not opened
    assert not requests


def test_environment_does_not_consume_ambient_codebase_state(config, monkeypatch):
    values = {"DOCSTORE_API_URL": config.api_url, "DOCSTORE_SOURCE_ROOT": str(config.source_root),
              "DOCSTORE_CONTROL_STATE_DIR": str(config.state_root), "DOCSTORE_INSTANCE_ID": config.instance,
              "COCOINDEX_DB": "C:/should-never-be-used/ccc.db"}
    for name, value in values.items():
        monkeypatch.setenv(name, value)
    loaded = Config.from_env()
    assert loaded.state_root == config.state_root
    assert loaded.instance == config.instance
    assert config.token not in repr(config)


@pytest.mark.parametrize("changes", [
    {"api_url": "https://user:password@host.invalid"}, {"api_url": "file:///tmp/db"},
    {"api_url": "https://host.invalid/path"}, {"api_url": "https://host.invalid/?secret=x"},
    {"instance": "ccc"}, {"instance": "docstore-INVALID"},
])
def test_config_rejects_ambiguous_identity_and_origin(config, changes):
    with pytest.raises(ValueError):
        replace(config, **changes)


def test_config_rejects_shared_and_nested_state(config):
    for state in [config.source_root / "state", config.state_root.parent / ".cocoindex_code" / "state",
                  config.state_root.parent / "ccc" / "state"]:
        with pytest.raises(ValueError):
            replace(config, state_root=state)
