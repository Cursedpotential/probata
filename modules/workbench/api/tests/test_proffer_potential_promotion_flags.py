"""Potential-promotion annotations stay reversible, attempt-bound, and actor-bound."""

from __future__ import annotations

import json

from app.runtime import proffer as proffer_runtime
from app.service import proffer_flags
from app.types.proffer import ProfferContentResponse, ProfferDecisionActor
from app.types.proffer_flags import (
    ProfferPotentialPromotionFlag,
    ProfferPotentialPromotionFlagRequest,
)
from fastapi import FastAPI, Request
from fastapi.testclient import TestClient

PREVIEW_HANDLE = "preview_handle_abcdefghijklmnopqrstuvwxyz"
ATTEMPT_ID = "attempt://normalized-1"


def _content() -> ProfferContentResponse:
    return ProfferContentResponse.model_validate(
        {
            "preview_handle": PREVIEW_HANDLE,
            "matter_mode": "TEST",
            "package": {
                "source_version_ref": "source-version-1",
                "declared_format": "document",
                "status": "retained",
                "metadata_count": 1,
                "attachment_count": 0,
            },
            "attempt": {
                "attempt_ref": ATTEMPT_ID,
                "projection_ref": "normalized-1",
                "source_version_ref": "source-version-1",
                "raw_generation_ref": "raw-1",
                "normalized_generation_ref": "normalized-1",
                "receipts": [],
            },
            "attempts_complete": False,
            "attempts_reason": "Current attempt only",
            "records": [
                {
                    "record_id": "record-1",
                    "ordinal": 0,
                    "record_type": "document",
                    "payload": {"title": "Visible record"},
                    "source_locator_ref": "locator://record-1",
                }
            ],
            "attachments": [],
            "chunk_generation": {
                "generation_ref": "generation-1",
                "generation_ordinal": 1,
                "status": "sealed",
                "policy_id": "document",
                "policy_version": "1",
                "chunker_id": "offsets",
                "chunker_version": "1",
                "schema_version": "1",
                "source_view": "original",
                "source_sha256": "a" * 64,
                "receipt_ref": "receipt-1",
            },
            "chunks": [
                {
                    "chunk_ref": "chunk-1",
                    "index": 0,
                    "content": "Visible chunk",
                    "sha256": "b" * 64,
                    "derivation_mode": "verbatim_span",
                    "locator_ref": "locator://chunk-1",
                    "byte_start": 0,
                    "byte_end": 13,
                }
            ],
        }
    )


def _app() -> FastAPI:
    app = FastAPI()

    @app.middleware("http")
    async def actor(request: Request, call_next):
        request.state.subject_uid = "subject-1"
        request.state.principal = "operator"
        return await call_next(request)

    app.include_router(proffer_runtime.router)
    return app


def test_flag_route_binds_visible_target_attempt_and_authenticated_actor(monkeypatch) -> None:
    captured: dict = {}

    async def content(*args, **kwargs):
        return _content()

    def create(preview_handle, mode, body, actor):
        captured.update(
            preview_handle=preview_handle,
            mode=mode,
            body=body,
            actor=actor,
        )
        return ProfferPotentialPromotionFlag(
            flag_id="flag-1",
            preview_handle=preview_handle,
            matter_mode=mode,
            scope=body.scope,
            target_id=body.target_id,
            attempt_id=body.attempt_id,
            reason=body.reason,
            actor_subject_uid=actor.subject_uid,
            actor_username=actor.username,
            flagged_at="2026-09-13T20:00:00Z",
            status="open",
        )

    monkeypatch.setattr(proffer_runtime, "preview_content", content)
    monkeypatch.setattr(proffer_runtime, "create_potential_promotion_flag", create)
    response = TestClient(_app()).post(
        f"/api/proffer/previews/{PREVIEW_HANDLE}/potential-promotion-flags",
        params={"mode": "TEST"},
        json={
            "scope": "record",
            "target_id": "record-1",
            "attempt_id": ATTEMPT_ID,
            "reason": "Review this record later",
        },
    )

    assert response.status_code == 201
    assert response.json()["classification"] == "potential_promotion"
    assert captured["actor"] == ProfferDecisionActor(
        subject_uid="subject-1", username="operator"
    )
    assert captured["body"].attempt_id == ATTEMPT_ID


def test_flag_route_rejects_stale_attempt_and_unseen_target_before_write(monkeypatch) -> None:
    async def content(*args, **kwargs):
        return _content()

    monkeypatch.setattr(proffer_runtime, "preview_content", content)
    monkeypatch.setattr(
        proffer_runtime,
        "create_potential_promotion_flag",
        lambda *_: (_ for _ in ()).throw(AssertionError("flag store must not run")),
    )
    client = TestClient(_app())
    base = {
        "scope": "chunk",
        "target_id": "chunk-1",
        "attempt_id": ATTEMPT_ID,
        "reason": "Review this chunk later",
    }

    stale = client.post(
        f"/api/proffer/previews/{PREVIEW_HANDLE}/potential-promotion-flags",
        params={"mode": "TEST"},
        json={**base, "attempt_id": "attempt://stale"},
    )
    unseen = client.post(
        f"/api/proffer/previews/{PREVIEW_HANDLE}/potential-promotion-flags",
        params={"mode": "TEST"},
        json={**base, "target_id": "chunk-unseen"},
    )

    assert stale.status_code == 409
    assert "does not match" in stale.json()["detail"]
    assert unseen.status_code == 409
    assert "not present" in unseen.json()["detail"]


def test_flag_service_persists_governed_metadata_without_promoting(monkeypatch) -> None:
    captured: dict = {}

    def create(payload):
        captured.update(payload)
        return {
            "id": "flag-1",
            "claim": payload["claim"],
            "notes": payload["notes"],
            "created_at": "2026-09-13T20:00:00Z",
            "status": "open",
        }

    monkeypatch.setattr(proffer_flags.flags_service, "create_flag", create)
    request = ProfferPotentialPromotionFlagRequest(
        scope="chunk",
        target_id="chunk-1",
        attempt_id=ATTEMPT_ID,
        reason="Review this chunk later",
    )
    actor = ProfferDecisionActor(subject_uid="subject-1", username="operator")

    result = proffer_flags.create_potential_promotion_flag(
        PREVIEW_HANDLE, "TEST", request, actor
    )

    notes = json.loads(captured["notes"])
    assert captured["target_kind"] == "proffer_preview_chunk"
    assert captured["evidence_wanted"] == []
    assert notes == {
        "actor_subject_uid": "subject-1",
        "actor_username": "operator",
        "attempt_id": ATTEMPT_ID,
        "classification": "potential_promotion",
        "contract": "proffer-potential-promotion/v1",
        "matter_mode": "TEST",
        "preview_handle": PREVIEW_HANDLE,
        "scope": "chunk",
        "target_id": "chunk-1",
    }
    assert result.classification == "potential_promotion"
    assert result.attempt_id == ATTEMPT_ID

