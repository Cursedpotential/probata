# HANDOFF — Evidence Operations Desk backend vertical (2026-08-18)

> _Byline: Codex · GPT-5 · 2026-08-18_
STATUS: PARTIAL
BUILD_STATUS: PASS

## Verified-live state (do not re-derive)

| Thing | State |
|---|---|
| Spine endpoints | Implemented in `server/api/case_management_routes.py`; no live HTTP/DB verification performed. |
| Workbench proxies | Implemented in `workbench/api/app/runtime/case_management.py`; Workbench authentication remains the existing global middleware boundary. |
| Deployment | Not performed. Existing coordination records the exec tier as down, so production deployment/live verification remains blocked outside this subtask. |

## Findings / work done

- Added import-light contracts for `OriginalSourceContent`, `ConversationMessage`, and `ConversationContext` in `server/contracts/case_management.py`; Workbench mirrors them in `workbench/api/app/types/case_management.py`.
- Added `GET /v1/matters/{matter_id}/evidence-items/{evidence_item_id}/source-content`. It first resolves the exact matter-scoped promotion/detail chain, then reads only `evidence.evidence_hash.blob_key` below `EVIDENCE_BLOB_ROOT`, verifies H1 SHA-256, rejects path escape/missing/binary/invalid UTF-8/oversized content, and never falls back to normalized content.
- Added `GET /v1/matters/{matter_id}/evidence-items/{evidence_item_id}/conversation-context?before=25&after=25`, bounded to 0..100. It orders by occurred time then normalized UUID, returns full normalized content, source-party sender/recipients from first-party or approved acquired-third-party projections, source/projection kind, source clock, and lineage pointers.
- Added Workbench service/runtime proxies at `/api/.../source-content` and `/api/.../conversation-context`; existing global Workbench authentication applies.
- Added dated backups with suffix `.backup_20260818_evidence_desk_backend` for every modified assigned file.

## UNRESOLVED (mandatory)

- Live deployment and DB/schema verification — blocked by the documented down exec tier and unavailable live endpoint; local tests cannot prove Coolify state.
## Pending owner decisions

- Deploy and live-verify this vertical — WHAT: run the production Coolify deployment and authenticated drill-through; WHY: local tests do not prove live source blobs/projection joins; APPROACH considered: direct local verification only (insufficient); SHORTCOMINGS: deployment target/exec tier availability is external to this subtask.

## Verification performed

1. `uv run pytest -q tests/test_case_management_routes.py` — 47 passed.
2. From `workbench/api`, `uv run pytest -q tests/test_case_management_service.py tests/test_case_management_runtime.py` — 27 passed.
3. Focused Ruff check and format check — passed.
4. Focused `uv run mypy server/contracts/case_management.py server/case_management/repository.py server/case_management/service.py server/api/case_management_routes.py` — passed.

## Next steps (work in order)

1. Restore/identify the production exec/Workbench deployment target.
2. Deploy the committed backend with the existing Workbench client release.
3. Authenticated-live verify source-content H1 read, binary/missing fail-closed behavior, and deterministic conversation context with first-party and approved third-party records.
