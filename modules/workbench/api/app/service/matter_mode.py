"""Fail-closed TEST/REAL isolation for the Workbench Proffer BFF.

The upstream starter does not yet expose a durable mode binding for opaque
preview handles. Until it does, this module uses a process-local deny-by-
default registry: a restart or a request reaching another replica makes an
old handle unavailable instead of guessing its mode. That is deliberately
safe but not durable; the durable fix is a starter/database binding keyed by
preview handle and matter identity.
"""

from __future__ import annotations

from threading import RLock
from uuid import UUID

from app.config import settings
from app.types.matter_mode import MatterMode


class MatterModeError(Exception):
    def __init__(self, detail: str, status_code: int):
        self.detail = detail
        self.status_code = status_code
        super().__init__(detail)


_preview_modes: dict[str, MatterMode] = {}
_preview_modes_lock = RLock()


def _configured_uuid(raw: str, *, mode: MatterMode, identity: str) -> UUID:
    label = f"{mode} {identity} identity"
    if not raw.strip():
        raise MatterModeError(f"{label} is not configured", 503)
    try:
        return UUID(raw.strip())
    except ValueError:
        raise MatterModeError(f"{label} configuration is invalid", 503) from None


def configured_matter_id(mode: MatterMode) -> UUID:
    raw = settings.proffer_test_matter_id if mode == "TEST" else settings.proffer_real_matter_id
    return _configured_uuid(raw, mode=mode, identity="matter")


def configured_court_case_id(mode: MatterMode) -> UUID:
    raw = settings.proffer_test_court_case_id if mode == "TEST" else settings.proffer_real_court_case_id
    return _configured_uuid(raw, mode=mode, identity="court-case")


def require_matter(mode: MatterMode, matter_id: UUID) -> UUID:
    configured = configured_matter_id(mode)
    if matter_id != configured:
        raise MatterModeError(f"matter_id does not belong to {mode} mode", 409)
    return configured


def require_scope(mode: MatterMode, matter_id: UUID, court_case_id: UUID) -> tuple[UUID, UUID]:
    configured_matter = require_matter(mode, matter_id)
    configured_court_case = configured_court_case_id(mode)
    if court_case_id != configured_court_case:
        raise MatterModeError(f"court_case_id does not belong to {mode} mode", 409)
    return configured_matter, configured_court_case


def bind_preview_mode(preview_handle: str, mode: MatterMode) -> None:
    with _preview_modes_lock:
        existing = _preview_modes.get(preview_handle)
        if existing is not None and existing != mode:
            raise MatterModeError("preview handle is already bound to a different matter mode", 502)
        _preview_modes[preview_handle] = mode


def require_preview_mode(preview_handle: str, mode: MatterMode) -> None:
    with _preview_modes_lock:
        existing = _preview_modes.get(preview_handle)
    if existing is None:
        raise MatterModeError(
            "preview handle has no active TEST/REAL binding; restart the import rather than guessing its mode",
            409,
        )
    if existing != mode:
        raise MatterModeError("preview handle belongs to a different matter mode", 409)


def _clear_preview_modes_for_tests() -> None:
    with _preview_modes_lock:
        _preview_modes.clear()
