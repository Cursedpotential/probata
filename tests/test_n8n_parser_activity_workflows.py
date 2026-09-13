"""Contract tests for the n8n parser Activity adapters.

These workflows are deliberately tiny transport adapters.  n8n owns the
visual HTTP boundary, while the Go runtime owns parser selection/execution and
all durable state.  The tests therefore inspect the exported n8n JSON rather
than starting n8n, Temporal, a database, or a parser worker.
"""

from __future__ import annotations

import json
import re
from pathlib import Path
from urllib.parse import urlparse

import pytest


ROOT = Path(__file__).resolve().parents[1]
WORKFLOW_SPECS = {
    ROOT / "deploy/docker/n8n/workflows/proffer/wf-select-parser-activity.json": "select_parser_activity",
    ROOT / "deploy/docker/n8n/workflows/proffer/wf-execute-parser-activity.json": "execute_parser_activity",
}
ALL_PROFFER_WORKFLOWS = tuple(sorted((ROOT / "deploy/docker/n8n/workflows/proffer").glob("wf-*.json")))

REQUEST_FIELDS = {"request_id", "source_version_ref", "declared_format", "refs"}
RESULT_FIELDS = {"stage", "status", "ref", "receipt_ref"}
HANDLER_SELECTION_REFS = {
    "handler_recommendation",
    "handler_decision",
    "handler_validation",
    "detected_format",
    "content_signature",
    "handler_compatibility",
}
FORBIDDEN_PAYLOAD_TERMS = {
    "file_bytes",
    "raw_records",
    "normalized_records",
    "source_bytes",
    "records",
    "file_content",
}
FORBIDDEN_NODE_TERMS = {
    "postgres",
    "mysql",
    "mongodb",
    "redis",
    "supabase",
    "hash",
    "normalize",
    "classif",
    "persist",
    "datastore",
    "loop",
    "splitinbatches",
    "retry",
    "attempt",
}


def _load_workflow(path: Path) -> dict:
    assert path.is_file(), f"expected workflow has not been materialized: {path}"
    try:
        workflow = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        pytest.fail(f"{path} is not importable JSON: {exc}")
    assert isinstance(workflow, dict), f"{path} must contain one JSON object"
    assert isinstance(workflow.get("nodes"), list), f"{path} must export a nodes array"
    assert isinstance(workflow.get("connections"), dict), f"{path} must export connections"
    return workflow


def _nodes_by_name(workflow: dict) -> dict[str, dict]:
    nodes = workflow["nodes"]
    names = [node.get("name") for node in nodes]
    assert all(isinstance(name, str) and name for name in names), "every node needs a name"
    assert len(names) == len(set(names)), "node names must be unique"
    return {node["name"]: node for node in nodes}


def _main_edges(workflow: dict, nodes: dict[str, dict]) -> dict[str, list[str]]:
    edges: dict[str, list[str]] = {name: [] for name in nodes}
    for source, connection in workflow["connections"].items():
        assert source in nodes, f"connection source {source!r} is not a node"
        main = connection.get("main", [])
        assert isinstance(main, list), f"{source} main connections must be a list"
        for branch in main:
            assert isinstance(branch, list), f"{source} main branch must be a list"
            for edge in branch:
                assert edge.get("type") == "main", f"{source} has a non-main edge"
                target = edge.get("node")
                assert target in nodes, f"connection target {target!r} is not a node"
                edges[source].append(target)
    return edges


def _linear_nodes(workflow: dict) -> tuple[list[dict], dict[str, dict], dict[str, list[str]]]:
    nodes = _nodes_by_name(workflow)
    edges = _main_edges(workflow, nodes)
    assert len(nodes) == 5, "parser Activity adapter must contain exactly five nodes"
    assert sum(len(targets) for targets in edges.values()) == 4, "adapter must have exactly four edges"

    starts = [node for node in nodes.values() if node.get("type") == "n8n-nodes-base.webhook"]
    assert len(starts) == 1, "adapter must have one Webhook trigger"
    sequence = [starts[0]]
    seen = {starts[0]["name"]}
    while edges[sequence[-1]["name"]]:
        targets = edges[sequence[-1]["name"]]
        assert len(targets) == 1, "adapter path must not branch"
        target = targets[0]
        assert target not in seen, "adapter path must not contain a cycle"
        seen.add(target)
        sequence.append(nodes[target])
    assert len(sequence) == len(nodes), "all five nodes must be on the Webhook response path"
    assert [node.get("type") for node in sequence] == [
        "n8n-nodes-base.webhook",
        "n8n-nodes-base.code",
        "n8n-nodes-base.httpRequest",
        "n8n-nodes-base.code",
        "n8n-nodes-base.respondToWebhook",
    ]
    return sequence, nodes, edges


def _parameter_text(parameters: dict) -> str:
    return json.dumps(parameters, sort_keys=True)


def _code(parameters: dict) -> str:
    code = parameters.get("jsCode") or parameters.get("code")
    assert isinstance(code, str) and code.strip(), "Code node must contain executable validation code"
    return code


@pytest.mark.parametrize("path,stage", WORKFLOW_SPECS.items())
def test_parser_activity_workflow_is_valid_json_and_exact_linear_shape(path: Path, stage: str):
    workflow = _load_workflow(path)
    sequence, _, _ = _linear_nodes(workflow)

    webhook, input_validation, http_request, result_validation, response = sequence
    assert webhook["parameters"].get("httpMethod") == "POST"
    assert webhook["parameters"].get("responseMode") == "responseNode"
    webhook_path = str(webhook["parameters"].get("path", "")).strip("/")
    assert webhook_path
    assert stage in webhook_path.replace("-", "_")

    assert _code(input_validation["parameters"])
    assert http_request["parameters"].get("method") == "POST"
    assert _code(result_validation["parameters"])
    assert response["parameters"].get("respondWith") == "json"


def test_parser_activity_workflows_use_separate_webhook_paths():
    path_pairs = []
    for path, stage in WORKFLOW_SPECS.items():
        workflow = _load_workflow(path)
        sequence, _, _ = _linear_nodes(workflow)
        path_pairs.append((sequence[0]["parameters"].get("path"), stage))
    paths = [path for path, _ in path_pairs]
    assert len(paths) == 2
    assert len(set(paths)) == 2
    for value, stage in path_pairs:
        assert stage in str(value).strip("/").replace("-", "_")


@pytest.mark.parametrize("path,stage", WORKFLOW_SPECS.items())
def test_request_body_is_compact_references_only(path: Path, stage: str):
    workflow = _load_workflow(path)
    sequence, _, _ = _linear_nodes(workflow)
    input_validation, http_request = sequence[1], sequence[2]
    input_code = _code(input_validation["parameters"])
    http_parameters = http_request["parameters"]
    body_text = _parameter_text({key: value for key, value in http_parameters.items() if "body" in key.lower()})

    assert http_parameters.get("sendBody") is True
    assert "jsonBody" in http_parameters or "bodyParametersJson" in http_parameters
    assert "JSON.stringify" in body_text
    for field in REQUEST_FIELDS:
        assert re.search(rf"(?<![A-Za-z0-9_]){re.escape(field)}(?![A-Za-z0-9_])", input_code)
    assert "$json" in body_text
    assert not any(term in body_text.lower() for term in FORBIDDEN_PAYLOAD_TERMS)

    # Unknown keys must fail closed at the n8n boundary.  This makes the
    # absence of forbidden fields a contract, rather than an accidental sample.
    lowered = input_code.lower()
    assert "object.keys" in lowered
    assert "allowed" in lowered
    assert "includes" in lowered or "every" in lowered or ".has(" in lowered
    assert not any(
        re.search(rf"(?:\$json|input|body|payload)[^\n;]{{0,100}}{re.escape(term)}", input_code, re.I)
        for term in FORBIDDEN_PAYLOAD_TERMS
    )


@pytest.mark.parametrize("path,stage", WORKFLOW_SPECS.items())
def test_handler_selection_refs_are_exactly_validated_and_forwarded(path: Path, stage: str):
    workflow = _load_workflow(path)
    sequence, _, _ = _linear_nodes(workflow)
    input_code = _code(sequence[1]["parameters"])

    for reference in HANDLER_SELECTION_REFS:
        assert reference in input_code, f"{stage} drops validated handler ref {reference}"
    assert "allowedRefSets" in input_code
    assert "refKeys.length===set.length" in input_code
    assert "Object.fromEntries(requiredRefs.map" in input_code
    assert "exact legacy set or the exact content-validated handler set" in input_code


@pytest.mark.parametrize("path,stage", WORKFLOW_SPECS.items())
def test_platform_call_is_authenticated_and_uses_literal_placeholder_base_url(path: Path, stage: str):
    workflow = _load_workflow(path)
    sequence, _, _ = _linear_nodes(workflow)
    parameters = sequence[2]["parameters"]
    auth = parameters.get("authentication")
    assert auth in {"genericCredentialType", "predefinedCredentialType", "basicAuth"}
    assert parameters.get("genericAuthType") or parameters.get("nodeCredentialType") or sequence[2].get("credentials")

    url = str(parameters.get("url", ""))
    assert "$env" not in url and "process.env" not in url
    literal = re.search(r"https?://[^\s'\"}]+", url)
    assert literal, "checked-in workflow must contain an explicit fail-closed URL placeholder"
    host = urlparse(literal.group(0)).hostname
    assert host and host.endswith(".example.invalid"), f"unexpected non-placeholder host: {host}"


@pytest.mark.parametrize("path", ALL_PROFFER_WORKFLOWS)
def test_all_uiw_workflows_keep_env_access_blocked_and_fail_closed(path: Path):
    workflow = _load_workflow(path)
    workflow_text = json.dumps(workflow, sort_keys=True)
    assert "$env" not in workflow_text
    assert "process.env" not in workflow_text

    http_nodes = [node for node in workflow["nodes"] if node.get("type") == "n8n-nodes-base.httpRequest"]
    assert len(http_nodes) == 1, f"{path.name} must have exactly one downstream HTTP call"
    url = str(http_nodes[0].get("parameters", {}).get("url", ""))
    literal = re.search(r"https?://[^\s'\"}]+", url)
    assert literal, f"{path.name} must contain an explicit URL placeholder"
    host = urlparse(literal.group(0)).hostname
    assert host and host.endswith(".example.invalid"), (
        f"{path.name} checked-in endpoint must fail closed until deployment binds it"
    )


@pytest.mark.parametrize("path,stage", WORKFLOW_SPECS.items())
def test_response_validates_exact_stage_and_returns_compact_stage_result(path: Path, stage: str):
    workflow = _load_workflow(path)
    sequence, _, _ = _linear_nodes(workflow)
    result_code = _code(sequence[3]["parameters"])
    response_text = _parameter_text(sequence[4]["parameters"])

    assert stage in result_code
    assert "status" in result_code
    assert "receipt_ref" in result_code and "ref" in result_code
    result_lowered = result_code.lower()
    assert "object.keys" in result_lowered and "allowed" in result_lowered
    assert "unsupported" in result_lowered or "unknown" in result_lowered
    assert "return" in result_lowered
    for field in RESULT_FIELDS:
        assert field in response_text
    assert not any(term in response_text.lower() for term in FORBIDDEN_PAYLOAD_TERMS)
    assert any(f"$json.{field}" in response_text for field in RESULT_FIELDS)


@pytest.mark.parametrize("path,stage", WORKFLOW_SPECS.items())
def test_parser_activity_adapter_has_no_stateful_or_load_bearing_work(path: Path, stage: str):
    workflow = _load_workflow(path)
    sequence, _, _ = _linear_nodes(workflow)
    node_names = " ".join(str(node.get("name", "")) for node in sequence).lower()
    assert not any(term in node_names for term in FORBIDDEN_NODE_TERMS)
    for node in sequence:
        parameters = node.get("parameters", {})
        if node.get("type") == "n8n-nodes-base.code":
            code = _code(parameters)
            assert not re.search(r"\b(?:createHash|crypto|normalize|classif\w*|persist\w*)\s*\(", code, re.I)
        assert not re.search(r'"(?:retry|attempt)[^"]*"\s*:', json.dumps(parameters), re.I)
