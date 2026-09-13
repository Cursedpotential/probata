"""Canonical config compatibility checks; Codex / GPT-6, 2026-09-12.

Uses synthetic configuration only, without network or actual credential reads.
"""
import base64
import importlib.util
import os
import sys
from pathlib import Path

import pytest

CONTROL = Path(__file__).parents[1]
sys.path.insert(0, str(CONTROL))
_spec = importlib.util.spec_from_file_location("docstore_config_test_cli", CONTROL / "cli.py")
cli = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(cli)


@pytest.fixture(autouse=True)
def isolated_env(monkeypatch):
    for key in list(os.environ):
        if key.startswith("DOCSTORE_") or key in cli._DEDICATED_KEYS:
            monkeypatch.delenv(key)


def use_settings(monkeypatch, settings):
    import dotenv
    # The existing test file stands in for a readable path; contents are mocked.
    monkeypatch.setenv("DOCSTORE_CONTROL_ENV_FILE", __file__)
    def read(path, *, interpolate):
        assert path == Path(__file__)
        assert interpolate is False
        return settings
    monkeypatch.setattr(dotenv, "dotenv_values", read)


def test_dedicated_file_loads_canonical_config_without_global_mutation(monkeypatch):
    use_settings(monkeypatch, {"SURREAL_DOCS_URL": "wss://surreal-docs.tilapia-skilift.ts.net/rpc",
        "SURREAL_DOCS_USER": "fixture-user", "SURREAL_DOCS_PASS": "literal-${SECRET}-password",
        "UNRELATED_SECRET": "must-not-enter-config"})
    config = cli.configuration()
    assert config.native_url == "https://surreal-docs.tilapia-skilift.ts.net/mcp"
    assert base64.b64decode(config.native_auth).decode() == "fixture-user:literal-${SECRET}-password"
    values = cli.environment()
    assert not cli._DEDICATED_KEYS.intersection(values)
    assert "UNRELATED_SECRET" not in values
    assert "DOCSTORE_BASIC_AUTH" not in os.environ
    assert config.native_auth not in repr(config)
    assert "literal-${SECRET}-password" not in repr(config)


def test_nonblank_canonical_names_take_precedence(monkeypatch):
    use_settings(monkeypatch, {"DOCSTORE_MCP_URL": "https://explicit.invalid/mcp",
        "DOCSTORE_BASIC_AUTH": "file-auth", "SURREAL_DOCS_URL": "invalid",
        "SURREAL_DOCS_USER": "ignored", "SURREAL_DOCS_PASS": "ignored"})
    assert cli.environment()["DOCSTORE_BASIC_AUTH"] == "file-auth"
    monkeypatch.setenv("DOCSTORE_BASIC_AUTH", "process-auth")
    monkeypatch.setenv("DOCSTORE_MCP_URL", "https://process.invalid/mcp")
    values = cli.environment()
    assert values["DOCSTORE_BASIC_AUTH"] == "process-auth"
    assert values["DOCSTORE_MCP_URL"] == "https://process.invalid/mcp"


def test_blank_process_values_do_not_erase_file_values(monkeypatch):
    use_settings(monkeypatch, {"DOCSTORE_BASIC_AUTH": "file-auth", "DOCSTORE_INSTANCE_ID": "docstore-fixture"})
    monkeypatch.setenv("DOCSTORE_BASIC_AUTH", "   ")
    monkeypatch.setenv("DOCSTORE_INSTANCE_ID", "")
    assert cli.environment()["DOCSTORE_BASIC_AUTH"] == "file-auth"
    assert cli.configuration().instance == "docstore-fixture"


def test_blank_file_values_allow_legacy_aliases(monkeypatch):
    use_settings(monkeypatch, {"DOCSTORE_BASIC_AUTH": "", "DOCSTORE_MCP_URL": " ",
        "SURREAL_DOCS_USER": "fixture", "SURREAL_DOCS_PASS": "pass",
        "SURREAL_DOCS_URL": "https://surreal-docs.tilapia-skilift.ts.net"})
    assert cli.configuration().native_auth == base64.b64encode(b"fixture:pass").decode()


@pytest.mark.parametrize("endpoint", [
    "http://surreal-docs.tilapia-skilift.ts.net", "ws://surreal-docs.tilapia-skilift.ts.net",
    "wss://other.invalid", "wss://surreal-docs.tilapia-skilift.ts.net.evil.invalid",
    "wss://user:secret@surreal-docs.tilapia-skilift.ts.net",
    "wss://surreal-docs.tilapia-skilift.ts.net:8000",
    "wss://surreal-docs.tilapia-skilift.ts.net:invalid",
    "wss://surreal-docs.tilapia-skilift.ts.net/sql",
    "wss://surreal-docs.tilapia-skilift.ts.net?token=secret",
    "wss://surreal-docs.tilapia-skilift.ts.net#secret",
    "wss://surreal-docs.tilapia-skilift.ts.net/\nrpc", "wss://[secret",
])
def test_legacy_endpoint_rejected_without_echoing_input(monkeypatch, endpoint):
    monkeypatch.setenv("SURREAL_DOCS_URL", endpoint)
    with pytest.raises(ValueError) as error:
        cli.environment()
    assert str(error.value) == "SURREAL_DOCS_URL must identify the dedicated secure Docstore endpoint"
    assert error.value.__cause__ is None


@pytest.mark.parametrize("user,password", [("fixture", ""), ("", "secret"), ("bad:user", "secret"), ("fixture", "secret\nvalue")])
def test_incomplete_or_invalid_credentials_are_sanitized(monkeypatch, user, password):
    monkeypatch.setenv("SURREAL_DOCS_USER", user)
    monkeypatch.setenv("SURREAL_DOCS_PASS", password)
    with pytest.raises(ValueError, match="Dedicated Docstore credentials require a valid user and password"):
        cli.environment()


def test_missing_explicit_file_fails_without_path_disclosure(monkeypatch):
    monkeypatch.setenv("DOCSTORE_CONTROL_ENV_FILE", "E:/nonexistent-docstore-synthetic/secret.env")
    with pytest.raises(ValueError) as error:
        cli.environment()
    assert str(error.value) == "DOCSTORE_CONTROL_ENV_FILE must be a readable env file"
