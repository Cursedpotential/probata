"""Keep the checked-in n8n Proffer wrappers aligned with the opaque-preview API.

The exports stay sanitized and inactive. Deployment binds endpoints and
credentials separately. Run with ``--write`` to update the JSON exports, or
without it to fail when an export has drifted from the contract below.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2] / "deploy/docker/n8n/workflows/proffer"


START_REQUEST = """const input=$input.first()||{};const envelope=input.json||{};const body=envelope.body!==undefined?envelope.body:envelope;const allowed=['request_id','matter_id','court_case_id','source_ref','declared_format','parser_options_ref','source_context_ref'];const required=['request_id','matter_id','court_case_id','source_ref','declared_format','parser_options_ref'];const forbidden=['file','files','raw_record','raw_records','record','records','content','data','binary','refs','source_version_ref','original_ref','workflow_id','run_id'];if(!body||typeof body!=='object'||Array.isArray(body))throw new Error('start: request body must be an object');if(input.binary)throw new Error('start: binary/file input is forbidden; send a source_ref only');const keys=Object.keys(body);if(keys.some((key)=>forbidden.includes(key)))throw new Error('start: forbidden payload field');const unknown=keys.filter((key)=>!allowed.includes(key));if(unknown.length)throw new Error('start: unsupported field(s): '+unknown.join(','));if(!required.every((field)=>typeof body[field]==='string'&&body[field].trim()!==''))throw new Error('start: request_id, matter_id, court_case_id, source_ref, declared_format, and parser_options_ref are required');const out=Object.fromEntries(required.map((field)=>[field,body[field].trim()]));if(typeof body.source_context_ref==='string'&&body.source_context_ref.trim()!=='')out.source_context_ref=body.source_context_ref.trim();return[{json:out}];"""

START_RESPONSE = """const response=$input.first()||{};const body=response.json||{};const allowed=['preview_handle'];if(!body||typeof body!=='object'||Array.isArray(body))throw new Error('start: starter returned a non-object response');const unknown=Object.keys(body).filter((key)=>!allowed.includes(key));if(unknown.length)throw new Error('start: response contains unsupported field(s): '+unknown.join(','));if(typeof body.preview_handle!=='string'||body.preview_handle.trim()==='')throw new Error('start: preview_handle is required');return[{json:{preview_handle:body.preview_handle.trim()}}];"""

DECISION_REQUEST = """const input=$input.first()||{};const envelope=input.json||{};const body=envelope.body!==undefined?envelope.body:envelope;const allowed=['preview_handle','approved','reason'];const forbidden=['workflow_id','run_id','decider','file','files','raw_record','raw_records','record','records','content','data','binary'];if(!body||typeof body!=='object'||Array.isArray(body))throw new Error('decision: request body must be an object');if(input.binary)throw new Error('decision: binary/file input is forbidden');const keys=Object.keys(body);if(keys.some((key)=>forbidden.includes(key)))throw new Error('decision: forbidden payload field');const unknown=keys.filter((key)=>!allowed.includes(key));if(unknown.length)throw new Error('decision: unsupported field(s): '+unknown.join(','));if(typeof body.preview_handle!=='string'||body.preview_handle.trim()==='')throw new Error('decision: preview_handle is required');if(typeof body.approved!=='boolean')throw new Error('decision: approved must be a boolean');if(!body.approved&&(typeof body.reason!=='string'||body.reason.trim()===''))throw new Error('decision: a rejection requires a non-empty reason');return[{json:{preview_handle:body.preview_handle.trim(),approved:body.approved,reason:typeof body.reason==='string'?body.reason.trim():''}}];"""

DECISION_RESPONSE = """const response=$input.first()||{};const body=response.json||{};const allowed=['preview_handle','status'];if(!body||typeof body!=='object'||Array.isArray(body))throw new Error('decision: starter returned a non-object response');const unknown=Object.keys(body).filter((key)=>!allowed.includes(key));if(unknown.length)throw new Error('decision: response contains unsupported field(s): '+unknown.join(','));if(typeof body.preview_handle!=='string'||body.preview_handle.trim()===''||!['approved','rejected'].includes(body.status))throw new Error('decision: starter did not return the correlated preview decision');return[{json:{preview_handle:body.preview_handle.trim(),status:body.status}}];"""

PREVIEW_REQUEST = """const input=$input.first()||{};const envelope=input.json||{};const query=envelope.query||{};const previewHandle=query.preview_handle;if(typeof previewHandle!=='string'||previewHandle.trim()==='')throw new Error('preview: preview_handle query parameter is required');return[{json:{preview_handle:previewHandle.trim()}}];"""

PREVIEW_RESPONSE = """const response=$input.first()||{};const body=response.json||{};if(!body||typeof body!=='object'||Array.isArray(body))throw new Error('preview: starter returned a non-object response');if(typeof body.preview_handle!=='string'||body.preview_handle.trim()==='')throw new Error('preview: response requires preview_handle');if(typeof body.phase!=='string'||body.phase.trim()==='')throw new Error('preview: response requires phase');return[{json:body}];"""


def by_name(document: dict, name: str) -> dict:
    return next(node for node in document["nodes"] if node["name"] == name)


def expected_documents() -> dict[Path, dict]:
    documents: dict[Path, dict] = {}

    path = ROOT / "wf-start-import.json"
    document = json.loads(path.read_text(encoding="utf-8"))
    by_name(document, "Validate + Shape Start Request")["parameters"]["jsCode"] = START_REQUEST
    by_name(document, "Validate Compact Start Response")["parameters"]["jsCode"] = START_RESPONSE
    by_name(document, "Respond to Webhook - Start Response")["parameters"]["responseBody"] = (
        "={{ JSON.stringify({preview_handle: $json.preview_handle}) }}"
    )
    documents[path] = document

    path = ROOT / "wf-preview-decision.json"
    document = json.loads(path.read_text(encoding="utf-8"))
    by_name(document, "Validate + Shape Decision Request")["parameters"]["jsCode"] = DECISION_REQUEST
    request = by_name(document, "HTTP - reference import starter decision")["parameters"]
    request["url"] = "={{ 'https://reference-import-starter.example.invalid/reference-import/previews/' + $json.preview_handle + '/decision' }}"
    request["headerParameters"]["parameters"][0] = {
        "name": "X-Preview-Handle",
        "value": "={{ $json.preview_handle }}",
    }
    request["jsonBody"] = "={{ JSON.stringify({approved: $json.approved, reason: $json.reason}) }}"
    by_name(document, "Validate Compact Decision Response")["parameters"]["jsCode"] = DECISION_RESPONSE
    by_name(document, "Respond to Webhook - Decision Response")["parameters"]["responseBody"] = (
        "={{ JSON.stringify({preview_handle: $json.preview_handle, status: $json.status}) }}"
    )
    documents[path] = document

    path = ROOT / "wf-preview-status.json"
    document = json.loads(path.read_text(encoding="utf-8"))
    by_name(document, "Validate + Shape Preview Request")["parameters"]["jsCode"] = PREVIEW_REQUEST
    request = by_name(document, "HTTP - reference import starter preview")["parameters"]
    request["url"] = "={{ 'https://reference-import-starter.example.invalid/reference-import/previews/' + $json.preview_handle }}"
    request["headerParameters"]["parameters"][0] = {
        "name": "X-Preview-Handle",
        "value": "={{ $json.preview_handle }}",
    }
    by_name(document, "Validate Compact Preview Response")["parameters"]["jsCode"] = PREVIEW_RESPONSE
    documents[path] = document

    return documents


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--write", action="store_true")
    args = parser.parse_args()
    dirty: list[str] = []
    for path, expected in expected_documents().items():
        rendered = json.dumps(expected, indent=2) + "\n"
        if path.read_text(encoding="utf-8") == rendered:
            continue
        dirty.append(path.name)
        if args.write:
            path.write_text(rendered, encoding="utf-8")
    if dirty and not args.write:
        raise SystemExit("drifted n8n exports: " + ", ".join(dirty))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
