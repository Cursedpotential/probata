"""Operator-surface contract tests for dead ends, truth, and mode isolation."""

from __future__ import annotations

import asyncio
from uuid import UUID

import pytest

from app.runtime import proffer as runtime
from app.service import matter_mode, proffer, proffer_operator, proffer_operations
from app.types.proffer import ProfferPreviewResponse
from app.types.proffer_operations import ProfferOperationDetail


HANDLE = "operator_preview_handle_abcdefghijklmnop"
MATTER = UUID("11111111-1111-4111-8111-111111111111")
CASE = UUID("22222222-2222-4222-8222-222222222222")


def _preview(phase: str, lifecycle: str) -> ProfferPreviewResponse:
    payload = {
        "preview_handle": HANDLE,
        "phase": phase,
        "matter_mode": "TEST",
        "lifecycle": lifecycle,
        "active_stages": [],
    }
    if phase == "awaiting_repair_decision":
        payload["repair_assessment"] = {
            "assessment_ref": "repair-assessment-ref",
            "source_version_ref": "source-version-ref",
            "review_required": True,
        }
    return ProfferPreviewResponse.model_validate(payload)


def _operation(lifecycle: str, stage: str = "detect_repair_need_activity") -> ProfferOperationDetail:
    return ProfferOperationDetail.model_validate(
        {
            "preview_handle": HANDLE,
            "request_id": "request-1",
            "source_ref": "r2://casebible-sorted/source.xml",
            "service": "proffer",
            "created_at": "2026-09-13T12:00:00Z",
            "lifecycle": lifecycle,
            "current_stage": stage,
            "active_stages": [stage] if lifecycle == "running" else [],
            "terminal": lifecycle == "failed",
            "reason": "exact stage failure" if lifecycle == "failed" else "",
            "source_version_ref": "source-version-ref",
            "completed_stage_count": 2,
            "stages": [
                {
                    "stage": stage,
                    "status": "failed" if lifecycle == "failed" else "completed",
                    "receipt_ref": "receipt://stage/1",
                    "reason": "exact stage failure" if lifecycle == "failed" else "",
                    "attempt": 2,
                }
            ],
        }
    )


def _wire(monkeypatch: pytest.MonkeyPatch, preview, operation) -> None:
    async def fake_preview(*args, **kwargs):
        return preview

    async def fake_operation(*args, **kwargs):
        return operation

    monkeypatch.setattr(proffer, "preview", fake_preview)
    monkeypatch.setattr(proffer_operations, "operation", fake_operation)
    monkeypatch.setattr(matter_mode, "configured_matter_id", lambda mode: MATTER)
    monkeypatch.setattr(matter_mode, "configured_court_case_id", lambda mode: CASE)


def test_repair_wait_has_forward_action_and_does_not_fabricate_repair_tool(monkeypatch) -> None:
    _wire(monkeypatch, _preview("awaiting_repair_decision", "awaiting_repair_decision"), _operation("awaiting_repair_decision"))

    result = asyncio.run(proffer_operator.operator_snapshot(HANDLE, mode="TEST"))

    actions = {item.action for item in result.valid_actions}
    gaps = {item.control: item.reason for item in result.unavailable_controls}
    assert "retain_original" in actions
    assert "apply_repair" in gaps
    assert "applicable repair tool IDs" in gaps["apply_repair"]
    assert result.repair_state.assessment_report.ref == "repair-assessment-ref"
    assert result.repair_state.proposed_action.status == "unavailable"
    assert "not proof that the source is damaged" in result.repair_state.proposed_action.reason
    assert "preserves the original" in result.repair_state.reentry_rule
    assert result.package.original.ref == "r2://casebible-sorted/source.xml"
    assert result.package.package_hash.status == "unavailable"
    assert result.authority_state.custody_state.status == "unavailable"
    assert "does not establish custody" in result.authority_state.custody_state.reason


def test_failed_stage_exposes_truthful_restart_and_exact_missing_controls(monkeypatch) -> None:
    _wire(monkeypatch, _preview("failed", "failed"), _operation("failed", "normalize_generation_activity"))

    result = asyncio.run(proffer_operator.operator_snapshot(HANDLE, mode="TEST"))

    assert result.reason == "exact stage failure"
    assert result.retry_count == 1
    assert {item.action for item in result.valid_actions} >= {"refresh", "restart_new_operation"}
    gaps = {item.control for item in result.unavailable_controls}
    assert {"retry_stage", "resume_checkpoint"}.issubset(gaps)
    assert result.stages[0].receipt_ref == "receipt://stage/1"


def test_operator_projection_marks_newest_package_contract_as_governing(monkeypatch) -> None:
    _wire(monkeypatch, _preview("starting", "running"), _operation("running", "execute_parser_activity"))

    result = asyncio.run(proffer_operator.operator_snapshot(HANDLE, mode="TEST"))

    assert result.contracts[0].contract == "Intake Source Package and source-type context storage"
    assert result.contracts[0].version == "D-158-2026-09-13"
    assert result.storage_state.source_type.status == "unavailable"
    assert "must not duplicate" in result.storage_state.rule
    assert result.layers[1].layer == "n8n"
    assert result.layers[1].status == "active"
    assert result.layers[1].run_or_execution_id.status == "unavailable"
    assert "does not promote context to evidence" in result.write_boundary


def test_operator_projection_fails_closed_on_cross_mode_preview(monkeypatch) -> None:
    _wire(monkeypatch, _preview("starting", "running"), _operation("running"))

    with pytest.raises(proffer.ProfferError, match="correlation failed"):
        asyncio.run(proffer_operator.operator_snapshot(HANDLE, mode="REAL"))


def test_operator_route_returns_the_correlated_projection(monkeypatch) -> None:
    _wire(monkeypatch, _preview("awaiting_repair_decision", "awaiting_repair_decision"), _operation("awaiting_repair_decision"))

    result = asyncio.run(runtime.operator_snapshot_endpoint(HANDLE, "TEST"))

    assert result.preview_handle == HANDLE
    assert result.matter_mode == "TEST"
    assert result.valid_actions[0].action == "refresh"
