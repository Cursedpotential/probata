"""Tests for agents/tools/sbv_tools.py — the agno @tool wrappers over
SBVClient (facade-collapse plan Batch A, §2).

Mocks SBVClient entirely (module has no live-network dependency at import
time; SBVClient.__init__ doesn't connect) via the module-level ``_client``
singleton, so these run with no live SBV service. Covers: the `sbv_export`
CSV/JSON shape (the one piece of business logic being ported from
deploy/docker/tool-runtime/tools/facade.py, not just re-plumbed — this is its
regression test so the port is provably faithful), the `sbv_upload` wait
behavior, and that `SBVError` propagates uncaught (OQ-8: agno's own
Function.execute() converts an uncaught exception into a structured
tool-call failure for the model — these tools do not re-catch and re-shape
it into an ``{"error": ...}`` payload, unlike the old facade's HTTPException
mapping).

``@tool`` turns each module-level function into an agno ``Function`` (a
pydantic model, not directly callable) — the ``_call`` helper below invokes
``.entrypoint(...)`` for it, the same way agno's own ``Function.execute()``
does internally.
"""

from __future__ import annotations

from typing import Any

import pytest
from agno.tools.function import Function

from server.agents.tools import sbv_tools
from server.tools._sbv_client import SBVError


def _call(fn: Function, **kwargs: Any) -> Any:
    """Invoke a ``@tool``-wrapped ``Function`` synchronously, the same way
    agno's own ``Function.execute()`` does. ``.entrypoint`` is typed
    ``Optional[Callable]`` on the pydantic model (only ``None`` before
    ``process_entrypoint()`` runs, which ``@tool`` always calls) — assert
    narrows that for mypy instead of scattering ``# type: ignore``."""
    assert fn.entrypoint is not None
    return fn.entrypoint(**kwargs)


class _FakeSBVClient:
    """Stand-in for SBVClient. Each method returns/raises whatever the test
    pre-loads via the `responses` dict; unset methods raise AssertionError so
    an unexpected call fails loudly instead of returning None silently."""

    def __init__(self, **responses: Any) -> None:
        self._responses = responses
        self.calls: list[tuple[str, tuple, dict]] = []

    def __getattr__(self, name: str):
        def _method(*args: Any, **kwargs: Any) -> Any:
            self.calls.append((name, args, kwargs))
            if name not in self._responses:
                raise AssertionError(f"unexpected call to {name}({args!r}, {kwargs!r})")
            value = self._responses[name]
            if isinstance(value, BaseException):
                raise value
            return value

        return _method


@pytest.fixture(autouse=True)
def _reset_client(monkeypatch):
    """SBVClient is a lazy module-level singleton (_sbv()) — reset it for
    every test so tests don't leak fake clients into each other."""
    monkeypatch.setattr(sbv_tools, "_client", None)
    yield
    monkeypatch.setattr(sbv_tools, "_client", None)


def _install(monkeypatch, **responses: Any) -> _FakeSBVClient:
    fake = _FakeSBVClient(**responses)
    monkeypatch.setattr(sbv_tools, "_client", fake)
    return fake


def test_sbv_tools_list_has_eleven_including_hashes():
    names = {f.name for f in sbv_tools.SBV_TOOLS}
    assert names == {
        "sbv_health",
        "sbv_version",
        "sbv_upload",
        "sbv_progress",
        "sbv_messages",
        "sbv_conversations",
        "sbv_calls",
        "sbv_analytics",
        "sbv_search",
        "sbv_hashes",
        "sbv_export",
    }
    assert "sbv_hashes" in names  # H1/H3 custody chain (plan §0/§2) — must be exposed


def test_sbv_health_wraps_bool(monkeypatch):
    _install(monkeypatch, health=True)
    assert _call(sbv_tools.sbv_health) == {"healthy": True}


def test_sbv_hashes_passes_import_id_and_returns_dict(monkeypatch):
    fake = _install(monkeypatch, hashes={"import_id": "42", "file_hash": "H1abc", "chain_hash": "H3xyz"})
    out = _call(sbv_tools.sbv_hashes, import_id="42")
    assert out == {"import_id": "42", "file_hash": "H1abc", "chain_hash": "H3xyz"}
    assert fake.calls == [("hashes", ("42",), {})]


def test_sbv_hashes_defaults_to_latest(monkeypatch):
    fake = _install(monkeypatch, hashes={"import_id": "99"})
    _call(sbv_tools.sbv_hashes)
    assert fake.calls == [("hashes", ("latest",), {})]


def test_sbv_upload_waits_when_still_processing(monkeypatch):
    fake = _install(
        monkeypatch,
        upload={"import_id": "1", "processing": True},
        wait_for_processing={"status": "completed"},
    )
    out = _call(sbv_tools.sbv_upload, path="/r2/a.xml")
    assert out == {"import_id": "1", "processing": False, "waited": True}
    assert [c[0] for c in fake.calls] == ["upload", "wait_for_processing"]


def test_sbv_upload_skips_wait_when_not_requested(monkeypatch):
    fake = _install(monkeypatch, upload={"import_id": "1", "processing": True})
    out = _call(sbv_tools.sbv_upload, path="/r2/a.xml", wait=False)
    assert out == {"import_id": "1", "processing": True}
    assert [c[0] for c in fake.calls] == ["upload"]


def test_sbv_error_propagates_uncaught(monkeypatch):
    _install(monkeypatch, version=SBVError("SBV GET /version -> HTTP 502: boom", status=502))
    with pytest.raises(SBVError):
        _call(sbv_tools.sbv_version)


# ---- sbv_export: regression test for the ported facade.py:270-296 logic ------


_MESSAGES = [
    {"id": 1, "address": "+15551234567", "body": "hi", "date": "2026-01-01T00:00:00Z"},
    {"id": 2, "address": "+15551234567", "body": "there", "date": "2026-01-02T00:00:00Z"},
]
_CALLS = [{"id": 1, "number": "+15551234567", "duration": 42}]


def test_sbv_export_json_shape(monkeypatch):
    _install(monkeypatch, all_messages=_MESSAGES, all_calls=_CALLS)
    out = _call(sbv_tools.sbv_export)
    assert out == {"format": "json", "messages": _MESSAGES, "calls": _CALLS}


def test_sbv_export_json_without_calls(monkeypatch):
    fake = _install(monkeypatch, all_messages=_MESSAGES, all_calls=_CALLS)
    out = _call(sbv_tools.sbv_export, include_calls=False)
    assert out == {"format": "json", "messages": _MESSAGES, "calls": []}
    assert "all_calls" not in [c[0] for c in fake.calls]


def test_sbv_export_csv_shape_matches_facade_parity(monkeypatch):
    _install(monkeypatch, all_messages=_MESSAGES, all_calls=_CALLS)
    out = _call(sbv_tools.sbv_export, format="csv")
    assert out["format"] == "csv"
    assert out["message_count"] == 2
    assert out["call_count"] == 1
    lines = out["csv"].strip().splitlines()
    header = lines[0].split(",")
    assert set(header) == {"id", "address", "body", "date"}
    assert len(lines) == 3  # header + 2 message rows


def test_sbv_export_csv_empty_messages(monkeypatch):
    _install(monkeypatch, all_messages=[], all_calls=[])
    out = _call(sbv_tools.sbv_export, format="csv")
    assert out == {"format": "csv", "csv": "", "message_count": 0, "call_count": 0}
