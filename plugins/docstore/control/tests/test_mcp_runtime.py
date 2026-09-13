from __future__ import annotations

import pytest

from cli import mcp_runtime


def test_stdio_is_safe_default():
    assert mcp_runtime({}) == {"transport": "stdio", "show_banner": False}


def test_http_runtime_is_explicit_and_stateless():
    assert mcp_runtime({
        "DOCSTORE_MCP_TRANSPORT": "http",
        "DOCSTORE_MCP_HOST": "0.0.0.0",
        "DOCSTORE_MCP_PORT": "8084",
    }) == {
        "transport": "http",
        "host": "0.0.0.0",
        "port": 8084,
        "path": "/mcp",
        "stateless_http": True,
        "show_banner": False,
    }


@pytest.mark.parametrize("host", ["", "localhost", "10.0.0.1", "example.com"])
def test_http_runtime_rejects_ambiguous_hosts(host):
    with pytest.raises(ValueError, match="DOCSTORE_MCP_HOST"):
        mcp_runtime({"DOCSTORE_MCP_TRANSPORT": "http", "DOCSTORE_MCP_HOST": host})


@pytest.mark.parametrize("port", ["text", "0", "1023", "65536"])
def test_http_runtime_rejects_invalid_ports(port):
    with pytest.raises(ValueError, match="DOCSTORE_MCP_PORT"):
        mcp_runtime({"DOCSTORE_MCP_TRANSPORT": "http", "DOCSTORE_MCP_PORT": port})


def test_http_runtime_rejects_unknown_transport():
    with pytest.raises(ValueError, match="DOCSTORE_MCP_TRANSPORT"):
        mcp_runtime({"DOCSTORE_MCP_TRANSPORT": "sse"})
