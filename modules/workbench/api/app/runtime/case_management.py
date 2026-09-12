"""Workbench Matter routes: validated, same-origin proxies to the spine.

Byline: Codex · GPT-5 · 2026-08-15 (Matter routes and read-only readiness)
"""

from __future__ import annotations

from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, HTTPException, Query
from pydantic import ValidationError

from app.service import case_management as service
from app.service.matter_mode import MatterModeError, configured_matter_id, require_matter
from app.types.case_management import (
    CaseManagementCapabilities,
    CourtCase,
    CourtCaseCreate,
    EvidenceItemCreate,
    EvidenceItemList,
    EvidencePromotionResult,
    EvidenceReviewCreate,
    EvidenceReviewList,
    EvidenceReviewResult,
    KnowledgeSourceRef,
    KnowledgeSourceResolution,
    Matter,
    MatterCreate,
    OriginalSourceContent,
)
from app.types.case_management_mode import ModeBoundMatter, ModeBoundMatterDetail, ModeBoundMatterList
from app.types.matter_mode import MatterMode
from app.types.conversation_context import ConversationContext
from app.types.evidence_detail import CourtReadiness, EvidenceDetail

router = APIRouter(prefix="/api", tags=["matters"])


def _raise_spine(error: service.SpineError) -> None:
    raise HTTPException(status_code=error.status_code, detail=error.detail) from None


@router.get("/case-management/capabilities", response_model=CaseManagementCapabilities)
def get_case_management_capabilities_endpoint():
    try:
        return service.get_case_management_capabilities()
    except service.SpineError as error:
        _raise_spine(error)


def _configured_mode_matter(mode: MatterMode) -> tuple[UUID, dict]:
    try:
        matter_id = configured_matter_id(mode)
    except MatterModeError as error:
        raise HTTPException(status_code=error.status_code, detail=error.detail) from None
    try:
        payload = service.get_matter(matter_id)
    except service.SpineError as error:
        _raise_spine(error)
    if not isinstance(payload, dict) or str(payload.get("id")) != str(matter_id):
        raise HTTPException(status_code=502, detail="Spine returned a different configured matter")
    return matter_id, payload


@router.get("/matters", response_model=ModeBoundMatterList)
def list_matters_endpoint(
    mode: Annotated[MatterMode, Query()],
    limit: Annotated[int, Query(ge=1, le=200)] = 50,
    offset: Annotated[int, Query(ge=0)] = 0,
):
    _, payload = _configured_mode_matter(mode)
    try:
        matter = ModeBoundMatter.model_validate({**payload, "matter_mode": mode})
    except (ValidationError, ValueError, TypeError):
        raise HTTPException(status_code=502, detail="Spine returned an invalid configured matter") from None
    return ModeBoundMatterList(
        data=[matter] if offset == 0 else [],
        total=1,
        limit=limit,
        offset=offset,
        matter_mode=mode,
    )


@router.post("/matters", response_model=Matter, status_code=201)
def create_matter_endpoint(payload: MatterCreate):
    try:
        return service.create_matter(payload)
    except service.SpineError as error:
        _raise_spine(error)


@router.get("/matters/{matter_id}", response_model=ModeBoundMatterDetail)
def get_matter_endpoint(matter_id: UUID, mode: Annotated[MatterMode, Query()]):
    try:
        require_matter(mode, matter_id)
    except MatterModeError as error:
        raise HTTPException(status_code=error.status_code, detail=error.detail) from None
    _, payload = _configured_mode_matter(mode)
    try:
        return ModeBoundMatterDetail.model_validate({**payload, "matter_mode": mode})
    except (ValidationError, ValueError, TypeError):
        raise HTTPException(status_code=502, detail="Spine returned an invalid configured matter") from None


@router.post("/matters/{matter_id}/court-cases", response_model=CourtCase, status_code=201)
def create_court_case_endpoint(matter_id: UUID, payload: CourtCaseCreate):
    try:
        return service.create_court_case(matter_id, payload)
    except service.SpineError as error:
        _raise_spine(error)


@router.post(
    "/matters/{matter_id}/knowledge/resolve",
    response_model=KnowledgeSourceResolution,
)
def resolve_knowledge_source_endpoint(matter_id: UUID, payload: KnowledgeSourceRef):
    try:
        return service.resolve_knowledge_source(matter_id, payload)
    except service.SpineError as error:
        _raise_spine(error)


@router.post(
    "/matters/{matter_id}/evidence-items",
    response_model=EvidencePromotionResult,
    status_code=201,
)
def create_evidence_item_endpoint(matter_id: UUID, payload: EvidenceItemCreate):
    try:
        return service.create_evidence_item(matter_id, payload)
    except service.SpineError as error:
        _raise_spine(error)


@router.get("/matters/{matter_id}/evidence-items", response_model=EvidenceItemList)
def list_evidence_items_endpoint(
    matter_id: UUID,
    limit: Annotated[int, Query(ge=1, le=200)] = 50,
    offset: Annotated[int, Query(ge=0)] = 0,
):
    try:
        return service.list_evidence_items(matter_id, limit=limit, offset=offset)
    except service.SpineError as error:
        _raise_spine(error)


@router.get(
    "/matters/{matter_id}/evidence-items/{evidence_item_id}",
    response_model=EvidenceDetail,
)
def get_evidence_detail_endpoint(matter_id: UUID, evidence_item_id: UUID):
    try:
        return service.get_evidence_detail(matter_id, evidence_item_id)
    except service.SpineError as error:
        _raise_spine(error)


@router.get(
    "/matters/{matter_id}/evidence-items/{evidence_item_id}/court-readiness",
    response_model=CourtReadiness,
)
def get_court_readiness_endpoint(matter_id: UUID, evidence_item_id: UUID):
    try:
        readiness = CourtReadiness.model_validate(service.get_court_readiness(matter_id, evidence_item_id))
    except service.SpineError as error:
        _raise_spine(error)
    if readiness.matter_id != matter_id or readiness.evidence_item_id != evidence_item_id:
        raise HTTPException(status_code=502, detail="Spine returned court readiness for a different evidence item")
    return readiness


@router.get(
    "/matters/{matter_id}/evidence-items/{evidence_item_id}/source-content",
    response_model=OriginalSourceContent,
)
def get_original_source_content_endpoint(matter_id: UUID, evidence_item_id: UUID):
    try:
        return service.get_original_source_content(matter_id, evidence_item_id)
    except service.SpineError as error:
        _raise_spine(error)


@router.get(
    "/matters/{matter_id}/evidence-items/{evidence_item_id}/conversation-context",
    response_model=ConversationContext,
)
def get_conversation_context_endpoint(
    matter_id: UUID,
    evidence_item_id: UUID,
    before: Annotated[int, Query(ge=0, le=100)] = 25,
    after: Annotated[int, Query(ge=0, le=100)] = 25,
):
    try:
        return service.get_conversation_context(
            matter_id,
            evidence_item_id,
            before=before,
            after=after,
        )
    except service.SpineError as error:
        _raise_spine(error)


@router.post(
    "/matters/{matter_id}/evidence-items/{evidence_item_id}/reviews",
    response_model=EvidenceReviewResult,
)
def review_evidence_item_endpoint(
    matter_id: UUID,
    evidence_item_id: UUID,
    payload: EvidenceReviewCreate,
):
    try:
        return service.review_evidence_item(matter_id, evidence_item_id, payload)
    except service.SpineError as error:
        _raise_spine(error)


@router.get(
    "/matters/{matter_id}/evidence-items/{evidence_item_id}/reviews",
    response_model=EvidenceReviewList,
)
def list_evidence_reviews_endpoint(matter_id: UUID, evidence_item_id: UUID):
    try:
        return service.list_evidence_reviews(matter_id, evidence_item_id)
    except service.SpineError as error:
        _raise_spine(error)
