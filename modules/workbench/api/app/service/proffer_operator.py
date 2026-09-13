"""Compose a truthful Proffer operator snapshot from existing read models."""

from __future__ import annotations

import asyncio

from app.service import matter_mode, proffer, proffer_operations
from app.types.matter_mode import MatterMode
from app.types.proffer_operator import (
    OperatorAction,
    OperatorAvailability,
    OperatorContractIdentity,
    OperatorExecutionLayer,
    OperatorPackageState,
    OperatorAuthorityState,
    OperatorRepairState,
    OperatorStorageState,
    OperatorUnavailableControl,
    ProfferOperatorSnapshot,
)


def _availability(status: str, reason: str = "", *, ref: str | None = None, count: int | None = None):
    return OperatorAvailability(status=status, reason=reason, ref=ref, count=count)


def _valid_actions(phase: str, lifecycle: str) -> list[OperatorAction]:
    actions = [OperatorAction(action="refresh", label="Refresh status", detail="Read the latest durable workflow projection.")]
    if phase == "awaiting_handler_selection":
        actions.append(OperatorAction(action="select_handler", label="Select handler and continue", detail="Record one content-compatible registered handler against this exact recommendation."))
    if phase == "awaiting_repair_decision":
        actions.append(OperatorAction(action="retain_original", label="Retain sealed original and continue", detail="Record the authenticated override and continue with the byte-identical retained source."))
    if phase == "awaiting_decision" or lifecycle == "awaiting_preview_decision":
        actions.extend(
            [
                OperatorAction(action="approve_preview", label="Approve and continue", detail="Resume this exact durable Proffer operation after correlated preview review."),
                OperatorAction(action="reject_preview", label="Reject with reason", detail="Keep the import unapproved and record why the preview was rejected.", requires_reason=True),
            ]
        )
    if lifecycle in {"failed", "unavailable"} or phase in {"failed", "timed_out", "rejected"}:
        actions.append(OperatorAction(action="restart_new_operation", label="Start a new import", detail="Return to intake and create a new request identity. This does not pretend to resume the failed run."))
    return actions


def _unavailable_controls(phase: str, lifecycle: str) -> list[OperatorUnavailableControl]:
    gaps: list[OperatorUnavailableControl] = []
    if phase == "awaiting_repair_decision":
        gaps.append(OperatorUnavailableControl(control="apply_repair", reason="The preview contract does not yet return applicable repair tool IDs and bounded inputs, so the Workbench cannot safely offer a repair button."))
    if lifecycle in {"failed", "unavailable"} or phase in {"failed", "timed_out"}:
        gaps.extend(
            [
                OperatorUnavailableControl(control="retry_stage", reason="Proffer exposes stage receipts and attempts but no authenticated exact-stage retry command."),
                OperatorUnavailableControl(control="resume_checkpoint", reason="Proffer does not expose a restart-from-checkpoint command or checkpoint token."),
            ]
        )
    gaps.append(OperatorUnavailableControl(control="skip_stage", reason="The executable stage graph has no operator skip-with-reason contract for the current state."))
    if lifecycle in {"running", "awaiting_repair_decision", "awaiting_preview_decision"}:
        gaps.append(OperatorUnavailableControl(control="cancel", reason="The Proffer starter has no authenticated cancel command or append-only cancellation receipt."))
    return gaps


async def operator_snapshot(preview_handle: str, *, mode: MatterMode) -> ProfferOperatorSnapshot:
    """Join the preview and operation by their opaque handle and fail closed on drift."""
    preview, operation = await asyncio.gather(
        proffer.preview(preview_handle, mode=mode),
        proffer_operations.operation(preview_handle),
    )
    if preview.preview_handle != operation.preview_handle or preview.matter_mode != mode:
        raise proffer.ProfferError("Proffer operator projection correlation failed", 502)

    matter_id = str(matter_mode.configured_matter_id(mode))
    court_case_id = str(matter_mode.configured_court_case_id(mode))
    stage_attempts = [stage.attempt or 0 for stage in operation.stages]
    selected = preview.recommended_handler
    handler = preview.parser.parser_id if preview.parser else selected.handler_id if selected else None
    execution_path = selected.execution_path if selected else None
    record_ready = bool(preview.correlation and preview.phase in {"awaiting_decision", "approved", "rejected"})
    n8n_stages = {"select_parser_activity", "execute_parser_activity"}
    n8n_observed = operation.current_stage in n8n_stages or any(stage.stage in n8n_stages for stage in operation.stages)
    layer_status = "waiting" if operation.wait else "failed" if operation.lifecycle == "failed" else "completed" if operation.lifecycle == "completed" else "active" if operation.lifecycle == "running" else "unavailable"

    missing_package_field = "The current browser-safe Proffer API does not expose this extraction-package field."
    package = OperatorPackageState(
        original=_availability("available", "The source reference is available; preservation/sealing state is not exposed by this API.", ref=operation.source_ref),
        original_fingerprint=_availability("unavailable", missing_package_field),
        package_identity=_availability("unavailable", missing_package_field),
        package_hash=_availability("unavailable", missing_package_field),
        metadata=_availability("unavailable", missing_package_field),
        attachments=_availability("unavailable", missing_package_field),
        parsed_or_extracted_products=_availability("available" if preview.correlation else "pending", "Raw generation is not available until extraction completes." if not preview.correlation else "", ref=str(preview.correlation.raw_generation_id) if preview.correlation else None),
        normalized_products=_availability("available" if preview.correlation else "pending", "Normalized generation is not available until normalization completes." if not preview.correlation else "", ref=str(preview.correlation.normalized_generation_id) if preview.correlation else None),
    )
    authority_state = OperatorAuthorityState(
        intake_classification=_availability("unavailable", "The current Proffer API does not return permanent-context versus potentially-evidence classification."),
        context_status=_availability("unavailable", "The current Proffer API does not state whether the preserved package is accepted as context-only material."),
        evidence_eligibility=_availability("unavailable", "Parse or extraction success never grants evidence eligibility; no eligibility projection is returned here."),
        promotion_prerequisites=_availability("unavailable", "The current preview does not return the later-promotion gate, reviewed-record set, or immutable comparison coordinates."),
        promotion_rehash=_availability("unavailable", "Later promotion must reopen the packaged original and rehash/re-extract it, but no promotion operation is exposed by this surface."),
        custody_state=_availability("unavailable", "Context intake does not establish custody. Custody H1/H2/H3 belongs to later governed promotion and is not reported by Proffer."),
    )
    assessment = preview.repair_assessment
    repair_state = OperatorRepairState(
        assessment_report=_availability(
            "available" if assessment else "pending",
            "No repair assessment report has been projected for the current phase." if not assessment else "The assessment reference is available; detailed findings are not included in the current preview DTO.",
            ref=assessment.assessment_ref if assessment else None,
        ),
        affected_units=_availability("unavailable", "The repair assessment DTO does not return affected archive members, pages, records, or byte ranges."),
        engine_profile=_availability("unavailable", "The repair assessment DTO does not return tool engine, operating-system profile, version, or result hash."),
        proposed_action=_availability("unavailable", "The engine allowlists repair.write-derived and repair.pdf-derived after a non-clean report, but the preview DTO returns no applicable tool ID or bounded input. Detector or tool failure is an operational error, not proof that the source is damaged."),
        decision_receipt=_availability("unavailable", "The preview read model does not return the durable repair-decision receipt after the workflow resumes."),
        reentry_rule="repair.detect then repair.preview runs before routing; only report.clean=false opens review. An approved derived repair preserves the original, writes and hashes a separate artifact, then re-enters validation, routing, and handler selection. The current browser contract cannot execute or verify that path.",
    )
    storage_state = OperatorStorageState(
        source_type=_availability("unavailable", "The current preview does not classify this package as messaging or non-messaging for D-158 storage routing."),
        context_target=_availability("unavailable", "No package-level projection reports the selected source-type context target or publication state."),
        postgres_control_state=_availability("pending", "PostgreSQL retains package/source identity, provenance, locators, fingerprints, template and attempt references, workflow state, decisions, projection coordinates, and receipts when those contracts are supplied."),
        searchable_projection=_availability("unavailable", "The preview does not return a governed Weaviate context-projection receipt or exact pre-publication chunks."),
        rule="Messaging text remains canonical in PostgreSQL with ordered chunk membership. Non-messaging content may stay in the retained package or durable DuckDB-derived files; PostgreSQL must not duplicate it into a generic text table. Context publication is not evidence admission or custody.",
    )
    surfaces = {
        "source": _availability("available", ref=operation.source_ref),
        "records": _availability("available" if record_ready else "pending", "Normalized records become readable only after the projected preview and completeness receipts exist." if not record_ready else "", ref=str(preview.correlation.normalized_generation_id) if preview.correlation else None),
        "chunks": _availability("unavailable", "The current Proffer preview API exposes no content-chunk projection or chunk-generation reference."),
        "entities": _availability("unavailable", "The current Proffer preview API exposes normalized messages only; it has no extracted-entity projection."),
        "graph": _availability("unavailable", "Graph candidates are a governed downstream proposal lane and are not returned by the Proffer preview API."),
        "workflow": _availability("available", ref=operation.preview_handle, count=len(operation.stages)),
        "duckdb": _availability("available" if execution_path == "duckdb" else "pending", "Governed DuckDB actions are discovered from the monitored tool catalog; no arbitrary SQL or browser-side execution is allowed."),
    }

    return ProfferOperatorSnapshot(
        preview_handle=preview_handle,
        matter_mode=mode,
        matter_id=matter_id,
        court_case_id=court_case_id,
        request_id=operation.request_id,
        source_ref=operation.source_ref,
        source_version_ref=operation.source_version_ref,
        lifecycle=operation.lifecycle,
        phase=preview.phase,
        current_stage=operation.current_stage,
        active_stages=operation.active_stages,
        retry_count=max((max(stage_attempts, default=1) - 1), 0),
        reason=preview.reason or operation.reason,
        terminal=operation.terminal,
        parser_handler=handler,
        parser_execution_path=execution_path,
        contracts=[
            OperatorContractIdentity(contract="Intake Source Package and source-type context storage", version="D-158-2026-09-13", authority="docs/DECISION_LOG.md D-154/D-158"),
            OperatorContractIdentity(contract="Context extraction package and promotion boundary", version="owner-package-ruling-2026-09-03-amended-D-152-2026-09-07", authority="docs/reviews/2026-09-06-naming-and-rename-session-digest.md; docs/DECISION_LOG.md D-149/D-152/D-154"),
            OperatorContractIdentity(contract="Source repair detect/preview/decision/derived-artifact boundary", version="tool-runtime-current-2026-09-13", authority="repair.capabilities/detect/preview/write-derived/pdf-inspect/pdf-derived/flag-damaged/quarantine-plan/audit-verify"),
            OperatorContractIdentity(contract="ParserInput / RawRecordEnvelope (inner record contract)", version="1.0.0", authority="modules/engine/parser/parser.go"),
            OperatorContractIdentity(contract="NormalizerInput / RecordEnvelope (inner record contract)", version="1.0.0", authority="modules/engine/normalize/normalize.go"),
            OperatorContractIdentity(contract="Proffer StageRequest / StageResult", version="stagegraph-current", authority="modules/engine/proffer/types.go"),
        ],
        package=package,
        authority_state=authority_state,
        repair_state=repair_state,
        storage_state=storage_state,
        layers=[
            OperatorExecutionLayer(
                layer="temporal", status=layer_status, current_node_or_stage=operation.current_stage,
                workflow_id=_availability("unavailable", "Temporal workflow IDs are intentionally not exposed by the current browser-safe Proffer contract; request_id and preview_handle remain visible correlation coordinates."),
                run_or_execution_id=_availability("unavailable", "Temporal run IDs stay behind the starter boundary in the current executable contract."),
                version=_availability("unavailable", "The operation projection does not return the Temporal workflow build/version identity."),
                detail="Temporal owns the durable Proffer stage graph and human waits.",
            ),
            OperatorExecutionLayer(
                layer="n8n", status="not_observed" if not n8n_observed else layer_status,
                current_node_or_stage=operation.current_stage if operation.current_stage in n8n_stages else None,
                workflow_id=_availability("unavailable", "The Proffer operation projection does not return an n8n workflow ID."),
                run_or_execution_id=_availability("unavailable", "The n8n activity adapter does not persist an execution ID in the browser-facing stage receipt."),
                version=_availability("unavailable", "Activation and workflow version are not included in the current Proffer API."),
                detail="n8n is the visual activity-body layer for registered parser flows; the API currently exposes only the enclosing Proffer stage and receipt.",
            ),
        ],
        surfaces=surfaces,
        stages=operation.stages,
        valid_actions=_valid_actions(preview.phase, operation.lifecycle),
        unavailable_controls=_unavailable_controls(preview.phase, operation.lifecycle),
        write_boundary="This surface reads projections and records authenticated workflow decisions. It does not promote context to evidence, accept graph candidates, or write canonical facts.",
    )
