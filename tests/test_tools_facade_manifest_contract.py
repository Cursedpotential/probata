"""Format-neutral declaration contract for the tool-runtime facade.

_Byline: Codex · GPT-5 · 2026-08-29._
"""

from __future__ import annotations

import importlib.util
import sys
from dataclasses import FrozenInstanceError
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from server.tools import registry as registry_module
from server.tools.registry import FunctionTool, ToolRegistry, register


_FACADE_PATH = Path(__file__).resolve().parents[1] / "deploy" / "docker" / "tool-runtime" / "tools" / "facade.py"
_FACADE_SPEC = importlib.util.spec_from_file_location("tool_runtime_facade", _FACADE_PATH)
assert _FACADE_SPEC is not None and _FACADE_SPEC.loader is not None
facade = importlib.util.module_from_spec(_FACADE_SPEC)
sys.modules[_FACADE_SPEC.name] = facade
_FACADE_SPEC.loader.exec_module(facade)


def _tool(tool_id: str, **overrides) -> FunctionTool:
    values = {
        "id": tool_id,
        "capability": "parse.content",
        "description": f"{tool_id} tool",
        "fn": lambda payload: payload,
    }
    values.update(overrides)
    return FunctionTool(**values)


def test_contract_manifest_has_deterministic_tool_format_and_quality_order() -> None:
    registry = ToolRegistry()
    registry.register(
        _tool(
            "z-tool",
            tool_version="2.1.0",
            contract_version="v1",
            input_schema_version="input-v2",
            output_schema_version="output-v3",
            formats=("json_export", "markdown"),
            quality=(
                ("json_export", "fallback"),
                ("markdown", "primary"),
            ),
        )
    )
    registry.register(_tool("a-tool"))

    assert registry.contract_manifest() == [
        {
            "id": "a-tool",
            "capability": "parse.content",
            "description": "a-tool tool",
            "provenance": "",
            "execution_policy": "manual_or_auto",
            "side_effect": "read_only",
            "tool_version": "unversioned",
            "contract_version": "unversioned",
            "input_schema_version": "unversioned",
            "output_schema_version": "unversioned",
            "formats": [],
            "quality": {},
        },
        {
            "id": "z-tool",
            "capability": "parse.content",
            "description": "z-tool tool",
            "provenance": "",
            "execution_policy": "manual_or_auto",
            "side_effect": "read_only",
            "tool_version": "2.1.0",
            "contract_version": "v1",
            "input_schema_version": "input-v2",
            "output_schema_version": "output-v3",
            "formats": ["json_export", "markdown"],
            "quality": {"json_export": "fallback", "markdown": "primary"},
        },
    ]


def test_legacy_manifest_stays_compatible_while_contract_manifest_expands() -> None:
    registry = ToolRegistry()
    registry.register(_tool("z-compatible-tool", tool_version="1.0.0"))
    registry.register(_tool("a-compatible-tool"))

    legacy_manifest = registry.manifest()
    contract_manifest = registry.contract_manifest()
    legacy = legacy_manifest[0]
    contract = contract_manifest[1]
    assert [entry["id"] for entry in legacy_manifest] == ["z-compatible-tool", "a-compatible-tool"]
    assert [entry["id"] for entry in contract_manifest] == ["a-compatible-tool", "z-compatible-tool"]
    assert set(legacy) == {
        "id",
        "capability",
        "description",
        "provenance",
        "execution_policy",
        "side_effect",
    }
    assert contract | legacy == contract
    assert contract["tool_version"] == "1.0.0"


def test_registered_function_tool_declarations_are_immutable() -> None:
    tool = _tool("immutable-tool", tool_version="1.0.0")

    with pytest.raises(FrozenInstanceError):
        tool.tool_version = "2.0.0"


@pytest.mark.parametrize("field", ["tool_version", "contract_version", "input_schema_version", "output_schema_version"])
@pytest.mark.parametrize("invalid", ["", " leading", "trailing ", "has spaces", "v1/unsafe"])
def test_version_tokens_are_validated(field: str, invalid: str) -> None:
    with pytest.raises(ValueError, match=field):
        _tool("invalid-version", **{field: invalid})


@pytest.mark.parametrize("rank", ["", "verified", "Primary", "primary ", True])
def test_per_format_quality_rejects_non_selector_ranks(rank) -> None:
    with pytest.raises(ValueError, match="quality rank"):
        _tool("invalid-rank", formats=("plain_text",), quality=(("plain_text", rank),))


def test_quality_keys_must_name_a_declared_format() -> None:
    with pytest.raises(ValueError, match="not present in formats"):
        _tool("orphan-quality", formats=("plain_text",), quality=(("json_export", "primary"),))


def test_quality_cannot_declare_the_same_format_twice() -> None:
    with pytest.raises(ValueError, match="at most once"):
        _tool(
            "duplicate-quality",
            formats=("plain_text",),
            quality=(("plain_text", "primary"), ("plain_text", "fallback")),
        )


def test_declared_format_may_omit_optional_quality_rank() -> None:
    tool = _tool("unranked-format", formats=("plain_text",))
    registry = ToolRegistry()
    registry.register(tool)

    [entry] = registry.contract_manifest()
    assert entry["formats"] == ["plain_text"]
    assert entry["quality"] == {}


@pytest.mark.parametrize(
    "invalid_format",
    [
        "",
        "a" * 60,
        "application/json",
        "Text",
        "_leading",
        "trailing_",
        "double__underscore",
        "9starts_with_digit",
        "hyphen-id",
    ],
)
def test_format_ids_match_go_canonical_validation(invalid_format: str) -> None:
    with pytest.raises(ValueError, match="canonical lowercase snake_case"):
        _tool("invalid-format", formats=(invalid_format,))


def test_facade_get_tools_exposes_json_contract_in_deterministic_order(monkeypatch: pytest.MonkeyPatch) -> None:
    registry = ToolRegistry()
    registry.register(_tool("z-facade-tool", tool_version="1.0.0"))
    registry.register(
        _tool(
            "a-facade-tool",
            formats=("plain_text",),
            quality=(("plain_text", "primary"),),
        )
    )
    monkeypatch.setattr(facade, "registry", registry)
    monkeypatch.setattr(facade, "REGISTRY_OK", True)

    response = TestClient(facade.app).get("/tools")

    assert response.status_code == 200
    manifest = response.json()
    assert [entry["id"] for entry in manifest] == ["a-facade-tool", "z-facade-tool"]
    assert manifest[0]["formats"] == ["plain_text"]
    assert manifest[0]["quality"] == {"plain_text": "primary"}
    assert manifest[1]["tool_version"] == "1.0.0"
    assert manifest[1]["formats"] == []
    assert manifest[1]["quality"] == {}
    assert all("complete" not in entry and "execution" not in entry for entry in manifest)


def test_register_decorator_normalizes_immutable_format_declarations(monkeypatch: pytest.MonkeyPatch) -> None:
    registry = ToolRegistry()
    monkeypatch.setattr(registry_module, "registry", registry)

    @register(
        id="decorated-tool",
        capability="extract.text",
        description="decorated tool",
        tool_version="1.2.0",
        contract_version="v1",
        input_schema_version="source-v1",
        output_schema_version="records-v2",
        formats=("plain_text", "json_export"),
        quality={"plain_text": "primary", "json_export": "experimental"},
    )
    def decorated(payload):
        return payload

    tool = registry.get("decorated-tool")
    assert decorated({"ok": True}) == {"ok": True}
    assert tool.formats == ("json_export", "plain_text")
    assert tool.quality == (("json_export", "experimental"), ("plain_text", "primary"))
    assert registry.contract_manifest()[0]["formats"] == ["json_export", "plain_text"]
    assert registry.contract_manifest()[0]["quality"] == {
        "json_export": "experimental",
        "plain_text": "primary",
    }
