"""HTTP boundary coverage for Matter source resolution and promotion.

Byline: Codex · GPT-5 · 2026-08-15
Byline amendment: Codex · GPT-5 · 2026-08-18 (third-party detail compatibility coverage)
"""

from __future__ import annotations

import pytest
from uuid import UUID
from fastapi import FastAPI
from fastapi.testclient import TestClient
from pydantic import ValidationError

from app.repo.spine_client import SpineError
from app.runtime import case_management as runtime
from app.types.evidence_detail import CourtReadiness, EvidenceDetail

MATTER_ID = "11111111-1111-4111-8111-111111111111"
COURT_CASE_ID = "22222222-2222-4222-8222-222222222222"
ARTIFACT_ID = "33333333-3333-4333-8333-333333333333"
RECORD_ID = "44444444-4444-4444-8444-444444444444"
HASH_ID = "55555555-5555-4555-8555-555555555555"
SOURCE_ID = "66666666-6666-4666-8666-666666666666"
PROMOTION_ID = "77777777-7777-4777-8777-777777777777"
ITEM_ID = "88888888-8888-4888-8888-888888888888"
TASK_ID = "99999999-9999-4999-8999-999999999999"
DECISION_ID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
CONVERSATION_ID = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
ACQUISITION_ID = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"
REALIZATION_ID = "dddddddd-dddd-4ddd-8ddd-dddddddddddd"
SHA256 = "a" * 64
SOURCE_SHA256 = "b" * 64
NOW = "2026-08-15T12:00:00Z"


def _client() -> TestClient:
    app = FastAPI()
    app.include_router(runtime.router)
    return TestClient(app)


def test_capability_503_is_preserved_exactly(monkeypatch):
    detail = "platform-native evidence substrate unavailable"
    monkeypatch.setattr(
        runtime.service,
        "get_case_management_capabilities",
        lambda: (_ for _ in ()).throw(SpineError(detail, 503)),
    )

    response = _client().get("/api/case-management/capabilities")

    assert response.status_code == 503
    assert response.json() == {"detail": detail}


def test_resolve_requires_custody_coordinates():
    response = _client().post(
        f"/api/matters/{MATTER_ID}/knowledge/resolve",
        json={"lane": "evidence", "partition_key": "primary"},
    )
    assert response.status_code == 422


def test_resolve_returns_exact_candidates(monkeypatch):
    candidate = {
        "normalized_record_id": RECORD_ID,
        "artifact_id": ARTIFACT_ID,
        "evidence_hash_id": HASH_ID,
        "source_id": SOURCE_ID,
        "sha256": SHA256,
        "record_type": "message",
        "role": "sender",
        "content": "exact record",
        "disclosure_tier": "contemporaneous",
        "review_status": "unreviewed",
    }
    monkeypatch.setattr(
        runtime.service,
        "resolve_knowledge_source",
        lambda matter_id, payload: {"matter_id": str(matter_id), "candidates": [candidate]},
    )

    response = _client().post(
        f"/api/matters/{MATTER_ID}/knowledge/resolve",
        json={
            "lane": "evidence",
            "partition_key": "primary",
            "artifact_id": ARTIFACT_ID,
            "sha256": SHA256,
            "retrieval_ref": "hit-1",
        },
    )

    assert response.status_code == 200
    assert response.json()["candidates"][0]["normalized_record_id"] == RECORD_ID


def test_promoted_item_is_explicitly_unsafe_and_unreviewed(monkeypatch):
    item = {
        "id": ITEM_ID,
        "matter_id": MATTER_ID,
        "court_case_id": COURT_CASE_ID,
        "title": "Draft message",
        "evidence_type": "communication",
        "normalized_record_id": RECORD_ID,
        "evidence_hash_id": HASH_ID,
        "source_id": SOURCE_ID,
        "review_status": "unreviewed",
        "hitl_required": True,
        "safe_for_legal_use": False,
        "is_authenticated": False,
        "created_by": "owner",
        "created_at": NOW,
    }
    monkeypatch.setattr(
        runtime.service,
        "create_evidence_item",
        lambda matter_id, payload: {
            "item": item,
            "promotion_id": PROMOTION_ID,
            "created": True,
        },
    )
    response = _client().post(
        f"/api/matters/{MATTER_ID}/evidence-items",
        json={
            "court_case_id": COURT_CASE_ID,
            "source": {
                "lane": "evidence",
                "partition_key": "primary",
                "artifact_id": ARTIFACT_ID,
                "sha256": SHA256,
                "retrieval_ref": "hit-1",
                "normalized_record_id": RECORD_ID,
            },
            "title": "Draft message",
        },
    )

    assert response.status_code == 201
    assert response.json()["item"]["review_status"] == "unreviewed"
    assert response.json()["item"]["hitl_required"] is True
    assert response.json()["item"]["safe_for_legal_use"] is False


def test_idempotent_retry_accepts_existing_reviewed_unsafe_item(monkeypatch):
    item = {
        "id": ITEM_ID,
        "matter_id": MATTER_ID,
        "court_case_id": COURT_CASE_ID,
        "title": "Reviewed existing item",
        "evidence_type": "communication",
        "normalized_record_id": RECORD_ID,
        "evidence_hash_id": HASH_ID,
        "source_id": SOURCE_ID,
        "review_status": "approved",
        "hitl_required": False,
        "safe_for_legal_use": False,
        "is_authenticated": False,
        "created_by": "owner",
        "created_at": NOW,
    }
    monkeypatch.setattr(
        runtime.service,
        "create_evidence_item",
        lambda matter_id, payload: {
            "item": item,
            "promotion_id": PROMOTION_ID,
            "created": False,
        },
    )
    response = _client().post(
        f"/api/matters/{MATTER_ID}/evidence-items",
        json={
            "court_case_id": COURT_CASE_ID,
            "source": {
                "lane": "evidence",
                "partition_key": "primary",
                "artifact_id": ARTIFACT_ID,
                "sha256": SHA256,
                "retrieval_ref": "hit-1",
                "normalized_record_id": RECORD_ID,
            },
            "title": "Reviewed existing item",
        },
    )

    assert response.status_code == 201
    assert response.json()["created"] is False
    assert response.json()["item"]["review_status"] == "approved"


def test_workbench_rejects_spoofed_actor_fields():
    response = _client().post(
        "/api/matters",
        json={"title": "Spoof attempt", "partition_key": "primary", "created_by": "attacker"},
    )
    assert response.status_code == 422


def test_spine_cross_matter_denial_is_preserved(monkeypatch):
    monkeypatch.setattr(runtime, "configured_matter_id", lambda mode: UUID(MATTER_ID))
    monkeypatch.setattr(runtime, "require_matter", lambda mode, matter_id: matter_id)
    monkeypatch.setattr(
        runtime.service,
        "get_matter",
        lambda matter_id: (_ for _ in ()).throw(SpineError("matter not found", 404)),
    )
    response = _client().get(f"/api/matters/{MATTER_ID}?mode=TEST")
    assert response.status_code == 404
    assert response.json()["detail"] == "matter not found"


def test_review_approval_remains_unauthenticated_and_legally_unsafe(monkeypatch):
    item = {
        "id": ITEM_ID,
        "matter_id": MATTER_ID,
        "court_case_id": COURT_CASE_ID,
        "title": "Reviewed message",
        "evidence_type": "communication",
        "normalized_record_id": RECORD_ID,
        "evidence_hash_id": HASH_ID,
        "source_id": SOURCE_ID,
        "review_status": "approved",
        "hitl_required": False,
        "safe_for_legal_use": False,
        "is_authenticated": False,
        "created_by": "owner",
        "created_at": NOW,
    }
    monkeypatch.setattr(
        runtime.service,
        "review_evidence_item",
        lambda matter_id, item_id, payload: {
            "item": item,
            "task_id": TASK_ID,
            "decision_id": DECISION_ID,
            "decision": "approved",
            "court_readiness": "review_passed",
        },
    )

    response = _client().post(
        f"/api/matters/{MATTER_ID}/evidence-items/{ITEM_ID}/reviews",
        json={"decision": "approved", "rationale": "Reviewed exact record."},
    )

    assert response.status_code == 200
    assert response.json()["item"]["review_status"] == "approved"
    assert response.json()["item"]["safe_for_legal_use"] is False
    assert response.json()["item"]["is_authenticated"] is False


def test_review_rejects_blank_rationale():
    response = _client().post(
        f"/api/matters/{MATTER_ID}/evidence-items/{ITEM_ID}/reviews",
        json={"decision": "approved", "rationale": "   "},
    )
    assert response.status_code == 422


def test_review_history_exposes_reviewer_rationale_and_time(monkeypatch):
    monkeypatch.setattr(
        runtime.service,
        "list_evidence_reviews",
        lambda matter_id, item_id: {
            "data": [
                {
                    "decision_id": DECISION_ID,
                    "task_id": TASK_ID,
                    "evidence_item_id": str(item_id),
                    "reviewer": "owner",
                    "decision": "needs_context",
                    "court_readiness": "draft",
                    "rationale": "Compare this record with the complete thread.",
                    "decided_at": NOW,
                }
            ],
            "total": 1,
        },
    )

    response = _client().get(f"/api/matters/{MATTER_ID}/evidence-items/{ITEM_ID}/reviews")

    assert response.status_code == 200
    assert response.json()["total"] == 1
    assert response.json()["data"][0] == {
        "decision_id": DECISION_ID,
        "task_id": TASK_ID,
        "evidence_item_id": ITEM_ID,
        "reviewer": "owner",
        "decision": "needs_context",
        "court_readiness": "draft",
        "rationale": "Compare this record with the complete thread.",
        "decided_at": NOW,
    }


def _evidence_detail():
    item = {
        "id": ITEM_ID,
        "matter_id": MATTER_ID,
        "court_case_id": COURT_CASE_ID,
        "title": "Custody-backed message",
        "evidence_type": "communication",
        "normalized_record_id": RECORD_ID,
        "evidence_hash_id": HASH_ID,
        "source_id": SOURCE_ID,
        "review_status": "unreviewed",
        "hitl_required": True,
        "safe_for_legal_use": False,
        "is_authenticated": False,
        "created_by": "owner",
        "created_at": NOW,
    }
    return {
        "item": item,
        "promotion": {
            "id": PROMOTION_ID,
            "partition_key": "primary",
            "knowledge_lane": "evidence",
            "retrieval_item_ref": "hit-1",
            "content_ref": "content-1",
            "chunk_ref": "chunk-1",
            "source_pointer": {
                "matter_id": MATTER_ID,
                "court_case_id": COURT_CASE_ID,
                "partition_key": "primary",
                "lane": "evidence",
                "normalized_record_id": RECORD_ID,
                "evidence_hash_id": HASH_ID,
                "source_id": SOURCE_ID,
                "sha256": SHA256,
                "conversation_id": "thread-1",
                "retrieval_ref": "hit-1",
                "content_ref": "content-1",
                "chunk_ref": "chunk-1",
                "quote": "must be dropped by the BFF",
            },
            "promoted_by": "owner",
            "promoted_at": NOW,
        },
        "record": {
            "id": RECORD_ID,
            "record_type": "message",
            "source": "sms",
            "conversation_id": "thread-1",
            "role": "sender",
            "content": "Exact normalized record text",
            "occurred_at": NOW,
            "source_kind": "unclassified",
            "projection_kind": "authored_normalized",
            "source_available_from": None,
            "third_party_conversation": None,
            "realization_events": [],
            "acquired_at": NOW,
            "ingested_at": NOW,
            "realized_at": None,
            "disclosure_tier": "contemporaneous",
            "review_status": "unreviewed",
            "case_id": "primary",
        },
        "custody_hash": {
            "id": HASH_ID,
            "source_ref": "fixture-export.json",
            "algo": "sha256",
            "digest_sha256": SHA256,
            "level": "H1",
            "canon_version": "h1-rawbytes-v1",
            "hashed_at": NOW,
            "computed_by": "custody.go",
        },
        "source": {
            "id": SOURCE_ID,
            "sha256": SOURCE_SHA256,
            "byte_size": 1024,
            "mime_type": "application/json",
            "original_filename": "fixture-export.json",
            "source_type": "chat_export",
            "source_platform": "fixture",
            "acquisition_source": "manual_export",
            "acquisition_method": "manual_export",
            "acquired_at_utc": NOW,
            "acquired_certainty": "exact",
            "provenance_tier": "r2_canonical",
            "hash_canon_version": "source-container-v2",
            "custody_status": "verified",
            "review_status": "reviewed",
            "verified_by": "owner",
            "verified_at": NOW,
            "local_path": "C:/private/never-expose.json",
            "r2_key": "private/object/key",
        },
        "file_node": None,
    }


def _court_readiness():
    return {
        "evidence_item_id": ITEM_ID,
        "matter_id": MATTER_ID,
        "readiness_passed": False,
        "blockers": [
            "CONTENT_REVIEW_REQUIRED",
            "CUSTODY_NOT_VERIFIED",
        ],
        "gates": {
            "content_review": {"approved": False, "decision_id": None},
            "provenance": {"exact": True},
            "custody": {
                "h1_valid": True,
                "event_chain_valid": True,
                "verified_event_present": True,
                "source_status": "pending",
                "source_reviewed": False,
                "verified_by": None,
                "verified_at": None,
            },
            "authentication": {"authenticated": True, "method": "hash_chain_of_custody"},
            "confidence": {"value": 0.8, "tier": "medium", "export_band": True},
            "assertion": {"not_hypothesis": True},
            "redaction": {
                "privacy_sensitivity": "none",
                "source_privacy_sensitivity": "none",
                "status": "none",
                "clear_for_export": True,
            },
            "sensitivity": {
                "evidence_tier": "restricted",
                "source_tier": "restricted",
                "sealed": False,
            },
            "court_export": {"view_member": True},
        },
        "private_reason": "must be dropped by the BFF",
    }


def test_evidence_detail_is_matter_scoped_and_sanitized(monkeypatch):
    monkeypatch.setattr(
        runtime.service,
        "get_evidence_detail",
        lambda matter_id, item_id: _evidence_detail(),
    )

    response = _client().get(f"/api/matters/{MATTER_ID}/evidence-items/{ITEM_ID}")

    assert response.status_code == 200
    body = response.json()
    assert body["record"]["id"] == RECORD_ID
    assert body["custody_hash"]["level"] == "H1"
    assert body["custody_hash"]["digest_sha256"] == SHA256
    assert body["source"]["sha256"] == SOURCE_SHA256
    assert body["source"]["hash_canon_version"] == "source-container-v2"
    assert body["source"]["sha256"] != body["custody_hash"]["digest_sha256"]
    assert "local_path" not in body["source"]
    assert "r2_key" not in body["source"]
    assert "quote" not in body["promotion"]["source_pointer"]


def test_evidence_detail_preserves_third_party_acquisition_and_realization_history(monkeypatch):
    detail = _evidence_detail()
    detail["record"].update(
        source_kind="third_party_acquired",
        projection_kind="derived_third_party",
        source_available_from=NOW,
        third_party_conversation={
            "id": CONVERSATION_ID,
            "external_thread_key": "thread-friends",
            "platform": "iMessage",
            "acquisition_id": ACQUISITION_ID,
            "acquired_at": NOW,
            "actual_sender": "Friend",
            "actual_recipients": ["Her"],
            "actual_participants": ["Friend", "Her"],
        },
        realization_events=[
            {
                "id": REALIZATION_ID,
                "kind": "deceit",
                "realized_at": NOW,
                "approval_state": "approved",
                "evidence_pointer": {"record_id": RECORD_ID},
                "proposer": "owner",
                "proposed_at": NOW,
                "approved_at": NOW,
                "approved_by": "owner",
            }
        ],
        realized_at=None,
    )
    monkeypatch.setattr(runtime.service, "get_evidence_detail", lambda matter_id, item_id: detail)

    response = _client().get(f"/api/matters/{MATTER_ID}/evidence-items/{ITEM_ID}")

    assert response.status_code == 200
    record = response.json()["record"]
    assert record["third_party_conversation"]["actual_sender"] == "Friend"
    assert record["third_party_conversation"]["actual_recipients"] == ["Her"]
    assert record["realization_events"][0]["id"] == REALIZATION_ID
    assert record["realized_at"] is None


def test_evidence_detail_rejects_non_h1_custody():
    detail = _evidence_detail()
    detail["custody_hash"]["level"] = "H2"

    with pytest.raises(ValidationError, match="requires an H1 SHA-256 custody hash"):
        EvidenceDetail.model_validate(detail)


def test_evidence_detail_rejects_third_party_without_approved_acquisition_context():
    detail = _evidence_detail()
    detail["record"].update(
        source_kind="third_party_acquired",
        projection_kind="derived_third_party",
        source_available_from=None,
        third_party_conversation=None,
    )

    with pytest.raises(ValidationError, match="requires approved acquisition context"):
        EvidenceDetail.model_validate(detail)


def test_original_source_endpoint_is_matter_scoped(monkeypatch):
    monkeypatch.setattr(
        runtime.service,
        "get_original_source_content",
        lambda matter_id, evidence_item_id: {
            "matter_id": matter_id,
            "evidence_item_id": evidence_item_id,
            "normalized_record_id": RECORD_ID,
            "source_id": SOURCE_ID,
            "evidence_hash_id": HASH_ID,
            "sha256": SHA256,
            "byte_size": 8,
            "content_byte_size": 8,
            "mime_type": "text/plain",
            "original_filename": "message.txt",
            "content": "original",
            "encoding": "utf-8",
            "source_pointer": {"source_id": SOURCE_ID},
            "provenance": {"source_id": SOURCE_ID},
            "h1": SHA256,
            "h2": None,
            "h3": None,
        },
    )

    response = _client().get(f"/api/matters/{MATTER_ID}/evidence-items/{ITEM_ID}/source-content")

    assert response.status_code == 200
    assert response.json()["content"] == "original"
    assert response.json()["matter_id"] == MATTER_ID


def test_conversation_context_endpoint_preserves_source_parties_and_bounds(monkeypatch):
    monkeypatch.setattr(
        runtime.service,
        "get_conversation_context",
        lambda matter_id, evidence_item_id, *, before, after: {
            "matter_id": matter_id,
            "evidence_item_id": evidence_item_id,
            "selected_normalized_record_id": RECORD_ID,
            "messages": [
                {
                    "id": RECORD_ID,
                    "normalized_record_id": RECORD_ID,
                    "content": "full source message",
                    "sender": "Actual sender",
                    "recipients": ["Actual recipient"],
                    "occurred_at": NOW,
                    "source_kind": "third_party_acquired",
                    "projection_kind": "derived_third_party",
                    "source_available_from": NOW,
                    "source_pointer": {"normalized_record_id": RECORD_ID},
                }
            ],
            "before": before,
            "after": after,
            "total": 1,
        },
    )

    response = _client().get(
        f"/api/matters/{MATTER_ID}/evidence-items/{ITEM_ID}/conversation-context",
        params={"before": 2, "after": 3},
    )

    assert response.status_code == 200
    assert response.json()["messages"][0]["content"] == "full source message"
    assert response.json()["messages"][0]["sender"] == "Actual sender"
    assert response.json()["messages"][0]["recipients"] == ["Actual recipient"]
    assert response.json()["before"] == 2
    assert response.json()["after"] == 3


def test_court_readiness_is_matter_scoped_explicit_and_fail_closed(monkeypatch):
    monkeypatch.setattr(
        runtime.service,
        "get_court_readiness",
        lambda matter_id, item_id: _court_readiness(),
    )

    response = _client().get(f"/api/matters/{MATTER_ID}/evidence-items/{ITEM_ID}/court-readiness")

    assert response.status_code == 200
    assert response.json()["blockers"] == [
        "CONTENT_REVIEW_REQUIRED",
        "CUSTODY_NOT_VERIFIED",
    ]
    assert response.json()["gates"]["custody"]["h1_valid"] is True
    assert response.json()["gates"]["court_export"]["view_member"] is True
    assert response.json()["readiness_passed"] is False
    assert "private_reason" not in response.json()


def test_court_readiness_rejects_optimistic_or_unexplained_results():
    optimistic = _court_readiness()
    optimistic["readiness_passed"] = True
    optimistic["blockers"] = []
    with pytest.raises(ValidationError, match="blockers do not match"):
        CourtReadiness.model_validate(optimistic)

    unexplained = _court_readiness()
    unexplained["blockers"] = []
    with pytest.raises(ValidationError, match="blockers do not match"):
        CourtReadiness.model_validate(unexplained)


def test_court_readiness_rejects_cross_scope_response(monkeypatch):
    wrong = _court_readiness()
    wrong["matter_id"] = "11111111-1111-4111-8111-999999999999"
    monkeypatch.setattr(runtime.service, "get_court_readiness", lambda *_: wrong)

    response = _client().get(f"/api/matters/{MATTER_ID}/evidence-items/{ITEM_ID}/court-readiness")

    assert response.status_code == 502
