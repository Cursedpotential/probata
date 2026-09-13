"""Contract tests for the n8n Proffer operator adapters.

The exports are inactive, sanitized transport wrappers. They expose the
opaque preview-handle API and never expose Temporal workflow/run identities to
the browser-facing n8n contract.
"""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[1]
WORKFLOW_DIR = ROOT / "deploy/docker/n8n/workflows/proffer"
SCRIPT = ROOT / "scripts/n8n/sync_proffer_preview_exports.py"

SPECS = {
    "start": WORKFLOW_DIR / "wf-start-import.json",
    "preview": WORKFLOW_DIR / "wf-preview-status.json",
    "decision": WORKFLOW_DIR / "wf-preview-decision.json",
}


def _load(path: Path) -> dict:
    value = json.loads(path.read_text(encoding="utf-8"))
    assert value["active"] is False
    assert len(value["nodes"]) == 5
    return value


def _sequence(value: dict) -> list[dict]:
    nodes = {node["name"]: node for node in value["nodes"]}
    starts = [node for node in nodes.values() if node["type"] == "n8n-nodes-base.webhook"]
    assert len(starts) == 1
    sequence = [starts[0]]
    while sequence[-1]["name"] in value["connections"]:
        branch = value["connections"][sequence[-1]["name"]]["main"]
        assert len(branch) == 1 and len(branch[0]) == 1
        sequence.append(nodes[branch[0][0]["node"]])
    assert len(sequence) == 5
    assert [node["type"] for node in sequence] == [
        "n8n-nodes-base.webhook",
        "n8n-nodes-base.code",
        "n8n-nodes-base.httpRequest",
        "n8n-nodes-base.code",
        "n8n-nodes-base.respondToWebhook",
    ]
    return sequence


@pytest.mark.parametrize("path", SPECS.values())
def test_operator_exports_are_inactive_authenticated_linear_adapters(path: Path) -> None:
    webhook, request_code, http_request, response_code, response = _sequence(_load(path))
    assert webhook["parameters"]["authentication"] == "headerAuth"
    assert request_code["parameters"]["jsCode"]
    assert http_request["parameters"]["authentication"] == "genericCredentialType"
    assert ".example.invalid" in http_request["parameters"]["url"]
    assert response_code["parameters"]["jsCode"]
    assert response["parameters"]["respondWith"] == "json"


def test_start_uses_scope_and_returns_only_opaque_preview_handle() -> None:
    _, request_code, http_request, response_code, response = _sequence(_load(SPECS["start"]))
    request = request_code["parameters"]["jsCode"]
    for field in (
        "request_id",
        "matter_id",
        "court_case_id",
        "source_ref",
        "declared_format",
        "parser_options_ref",
        "source_context_ref",
    ):
        assert field in request
    assert "workflow_id" in request and "forbidden" in request
    assert "run_id" in request and "forbidden" in request
    assert http_request["parameters"]["url"].endswith("/reference-import/start")
    assert "JSON.stringify($json)" in http_request["parameters"]["jsonBody"]
    assert "preview_handle" in response_code["parameters"]["jsCode"]
    response_body = response["parameters"]["responseBody"]
    assert "preview_handle" in response_body
    assert "workflow_id" not in response_body and "run_id" not in response_body


def test_preview_is_addressed_and_correlated_by_opaque_handle() -> None:
    _, request_code, http_request, response_code, _ = _sequence(_load(SPECS["preview"]))
    request = request_code["parameters"]["jsCode"]
    parameters = http_request["parameters"]
    assert "preview_handle" in request and "workflow_id" not in request
    assert "/reference-import/previews/" in parameters["url"]
    assert "$json.preview_handle" in parameters["url"]
    assert parameters["headerParameters"]["parameters"] == [
        {"name": "X-Preview-Handle", "value": "={{ $json.preview_handle }}"}
    ]
    response = response_code["parameters"]["jsCode"]
    assert "preview_handle" in response and "phase" in response


def test_decision_uses_handle_and_keeps_actor_identity_at_authenticated_service() -> None:
    _, request_code, http_request, response_code, response = _sequence(_load(SPECS["decision"]))
    request = request_code["parameters"]["jsCode"]
    parameters = http_request["parameters"]
    assert "preview_handle" in request
    assert "workflow_id" in request and "forbidden" in request
    assert "run_id" in request and "forbidden" in request
    assert "decider" in request and "forbidden" in request
    assert parameters["url"].endswith("$json.preview_handle + '/decision' }}")
    assert "approved" in parameters["jsonBody"] and "reason" in parameters["jsonBody"]
    assert "decider" not in parameters["jsonBody"]
    validation = response_code["parameters"]["jsCode"]
    assert "preview_handle" in validation
    assert "approved" in validation and "rejected" in validation
    response_body = response["parameters"]["responseBody"]
    assert "preview_handle" in response_body and "status" in response_body


def test_sync_script_and_checked_in_exports_are_identical() -> None:
    spec = importlib.util.spec_from_file_location("sync_proffer_preview_exports", SCRIPT)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    for path, expected in module.expected_documents().items():
        assert json.loads(path.read_text(encoding="utf-8")) == expected
