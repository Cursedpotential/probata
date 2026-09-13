"""Synthetic-only governance and freshness checks; never starts CDC or calls a store."""
import hashlib
import json
import sys
from contextlib import asynccontextmanager
from pathlib import Path
from types import SimpleNamespace

import pytest
from fastmcp.exceptions import ToolError
from pydantic import ValidationError

sys.path.insert(0, str(Path(__file__).parents[1]))
import governance as g
import verification as v
import flag_view


def flag(**overrides):
    values = dict(subject="note:boundary", title="Three systems", summary="Separate instances",
                  priority="critical", authority="owner_decision", domains=["docs", "intake"],
                  source_ref="owner conversation", rationale="Explicit instruction", actor="owner",
                  expected_revision=0)
    values.update(overrides)
    return g.FlagInput(**values)


@pytest.mark.parametrize("change", [dict(subject="note:x;DELETE document"), dict(priority="urgent"),
    dict(authority="critical"), dict(status="pending"), dict(expected_revision=-1),
    dict(domains=["unknown"]), dict(title=" "), dict(extra_field=True)])
def test_flags_validate_without_execution(change):
    with pytest.raises(ValidationError):
        flag(**change)


def test_authority_and_priority_are_independent():
    assert flag(priority="critical", authority="proposal").authority == "proposal"
    assert flag(priority="normal", authority="owner_decision").priority == "normal"


def test_key_stable_across_revisions_and_hash_canonicalizes_domains():
    first = g.flag_parameters(flag())
    retry = g.flag_parameters(flag(domains=["intake", "docs", "docs"]))
    revised = g.flag_parameters(flag(priority="high", expected_revision=1))
    assert first["rid"] == revised["rid"] == retry["rid"]
    assert first["hash"] == retry["hash"] != revised["hash"]
    assert first["audit_id"] != revised["audit_id"]
    assert revised["payload"]["revision"] == 2


async def test_write_binds_values_and_does_not_claim_indexing():
    malicious = "'; DELETE document; --"
    wanted = flag(summary=malicious)
    calls = []

    async def execute(config, sql, parameters):
        calls.append((sql, parameters))
        return [parameters["payload"]]

    result = await g.set_flags(None, wanted, execute)
    sql, parameters = calls[0]
    assert malicious not in sql
    assert parameters["payload"]["summary"] == malicious
    assert "$payload" in sql and "revision_conflict" in sql
    assert result["indexing_triggered"] is False
    assert result["source_document_modified"] is False


async def test_write_requires_verifiable_record():
    async def execute(*_):
        return [{"subject": "note:other"}]
    with pytest.raises(ToolError, match="verifiable"):
        await g.set_flags(None, flag(), execute)


async def test_list_binds_filters_and_indicates_truncation():
    calls = []
    async def execute(config, sql, parameters):
        calls.append((sql, parameters))
        return [{"priority": "critical", "authority": "proposal"}] * 3
    result = await g.list_flags(None, "intake", limit=2, execute=execute)
    assert len(result["flags"]) == 2 and result["truncated"]
    assert result["authority_is_separate_from_priority"]
    assert calls[0][1]["limit"] == 3
    assert "$domain" in calls[0][0]
    assert "WITH NOINDEX" in calls[0][0]


@pytest.mark.parametrize("body,is_error,match", [
    ("private sensitive error", True, "query failed"),
    ("revision_conflict private detail", True, "Revision conflict"),
    ('[{"status":"ERR","result":"private sensitive error"}]', False, "statement failed"),
    ('[{"status":"ERR","result":"revision_conflict"}]', False, "Revision conflict"),
    ("invalid-json-private", False, "invalid response"),
])
async def test_native_failures_sanitized(monkeypatch, body, is_error, match):
    class FakeClient:
        async def call_tool(self, *args, **kwargs):
            return SimpleNamespace(is_error=is_error, content=[SimpleNamespace(type="text", text=body)])
    @asynccontextmanager
    async def fake_client(_):
        yield FakeClient()
    monkeypatch.setattr(g, "native_client", fake_client)
    with pytest.raises(ToolError, match=match) as error:
        await g.query(None, "RETURN $value", {"value": "test"})
    assert "private" not in str(error.value)


async def test_native_statement_success_unwraps(monkeypatch):
    calls = []
    class FakeClient:
        async def call_tool(self, *args, **kwargs):
            calls.append((args, kwargs))
            return SimpleNamespace(is_error=False, content=[SimpleNamespace(type="text",
                text=json.dumps([{"status": "OK", "result": [{"subject": "note:x"}]}]))])
    @asynccontextmanager
    async def fake_client(_):
        yield FakeClient()
    monkeypatch.setattr(g, "native_client", fake_client)
    assert await g.query(None, "RETURN $value", {"value": "test"}) == [{"subject": "note:x"}]
    assert calls[0][0][1]["parameters"] == {"value": "test"}


def test_fingerprint_preserves_crlf_and_folds_non_bmp_not_raw_bytes():
    content = "# Test\r\n😀\r\n".encode()
    expected = hashlib.sha256(b"# Test\r\n:grinning_face:\r\n").hexdigest()
    assert v.fingerprint(content) == expected
    assert v.fingerprint(content) != hashlib.sha256(content).hexdigest()
    assert v.fingerprint(content) != v.fingerprint(content.replace(b"\r\n", b"\n"))


def snapshot(**changes):
    value = {"documents": [{"id": "document:docs_note_md", "content_hash": "hash", "status": "active"}],
             "chunks": [{"ordinal": 0, "dimensions": 2048, "linked_documents": ["document:docs_note_md"]}]}
    value.update(changes)
    return value


@pytest.mark.parametrize("data,state,projection", [
    (snapshot(), "hash_match", "present_unverified"),
    (snapshot(documents=[]), "missing", "present_unverified"),
    (snapshot(chunks=[]), "hash_match", "absent"),
    (snapshot(documents=[{"id": "document:wrong"}]), "identity_conflict", "present_unverified"),
    (snapshot(chunks=[{"ordinal": 1, "dimensions": 1024, "linked_documents": []}]), "hash_match", "incomplete"),
])
def test_projection_state_never_proves_cdc(data, state, projection):
    result = v.assess("docs/note.md", "hash", data)
    assert result["document_status"] == state
    assert result["projection_status"] == projection
    assert result["cdc_execution"] == "unproven"
    assert result["exact_projection_freshness"] == "unproven"


@pytest.mark.parametrize("name", ["../escape.md", "note.txt", "C:/private.md", "note.md:stream"])
def test_verification_path_boundaries(tmp_path, name):
    with pytest.raises(ToolError):
        v.read_selected(tmp_path, name)


@pytest.mark.parametrize("attribute", [0x1000, 0x40000, 0x400000])
def test_verification_cloud_placeholder_never_read(tmp_path, monkeypatch, attribute):
    target = tmp_path / "cloud.md"
    original_stat = Path.stat
    def fake_stat(path, *args, **kwargs):
        if path == target:
            return SimpleNamespace(st_file_attributes=attribute, st_size=1)
        return original_stat(path, *args, **kwargs)
    def no_open(*args, **kwargs):
        raise AssertionError("File read attempted")
    with monkeypatch.context() as patch:
        patch.setattr(Path, "stat", fake_stat)
        patch.setattr(Path, "open", no_open)
        with pytest.raises(ToolError, match="hydration"):
            v.read_selected(tmp_path, "cloud.md")


async def test_verify_binds_path_and_reports_only_observation(tmp_path):
    (tmp_path / "note.md").write_bytes(b"# Note\n")
    calls = []
    async def execute(config, sql, parameters):
        calls.append((sql, parameters))
        return [snapshot()]
    result = await v.verify(SimpleNamespace(source_root=tmp_path), ["note.md"], execute)
    assert calls[0][1] == {"source": "docs/note.md"}
    assert "docs/note.md" not in calls[0][0]
    assert result["all_cdc_verified"] is False
    assert result["indexing_triggered"] is False and result["worker_started"] is False
    assert result["files"][0]["document_status"] == "hash_mismatch"


@pytest.mark.parametrize("body,expected", [
    ('Statement 0 (ok):\nnull\n\nStatement 1 (ok):\n{"subject":"note:x"}', [{"subject": "note:x"}]),
    ('Statement 0 (ok):\n[{"subject":"note:x"}]', [{"subject": "note:x"}]),
    ('Statement 0 (ok):\n{"documents":[],"chunks":[]}', {"documents": [], "chunks": []}),
])
async def test_native_deployed_statement_text_parsing(monkeypatch, body, expected):
    class FakeClient:
        async def call_tool(self, *args, **kwargs):
            return SimpleNamespace(is_error=False, content=[SimpleNamespace(type="text", text=body)])
    @asynccontextmanager
    async def fake_client(_):
        yield FakeClient()
    monkeypatch.setattr(g, "native_client", fake_client)
    assert await g.query(None, "RETURN $value", {"value": "test"}) == expected


@pytest.mark.parametrize("body,message", [
    ('Statement 0 (ok):\nnull\n\nStatement 1 (error):\nprivate-sensitive', "statement failed"),
    ('Statement 0 (error):\nrevision_conflict private-sensitive', "Revision conflict"),
    ('Statement 0 (ok):\nnull\n\nStatement 1 (error, Thrown): An error occurred: revision_conflict\n\nStatement 2 (error, Query): Cannot COMMIT: transaction aborted', "Revision conflict"),
    ('Statement 1 (ok):\nnull', "statement sequence"),
    ('Statement 0 (ok):\nnull\n\nStatement 2 (ok):\nnull', "statement sequence"),
    ('Statement 0 (ok):\nnull\n\nStatement 0 (ok):\nnull', "statement sequence"),
    ('private-sensitive\nStatement 0 (ok):\nnull', "statement prefix"),
    ('Statement 0 (ok):\nnot-json-private-sensitive', "invalid response"),
])
async def test_native_statement_headers_fail_closed(monkeypatch, body, message):
    class FakeClient:
        async def call_tool(self, *args, **kwargs):
            return SimpleNamespace(is_error=False, content=[SimpleNamespace(type="text", text=body)])
    @asynccontextmanager
    async def fake_client(_):
        yield FakeClient()
    monkeypatch.setattr(g, "native_client", fake_client)
    with pytest.raises(ToolError, match=message) as error:
        await g.query(None, "RETURN 1")
    assert "private-sensitive" not in str(error.value)


async def test_same_subject_partial_write_response_is_not_success():
    async def execute(*_):
        return [{"subject": "note:boundary", "priority": "critical"}]
    with pytest.raises(ToolError, match="verifiable record"):
        await g.set_flags(None, flag(), execute)


@pytest.mark.parametrize("data", [
    {"documents": None}, {"documents": {}}, {"documents": [None]},
    {"chunks": None}, {"chunks": "private"}, {"chunks": ["private"]},
])
def test_assess_rejects_malformed_projection_payload(data):
    with pytest.raises(ToolError, match="Malformed"):
        v.assess("docs/note.md", "hash", data)


@pytest.mark.parametrize("count", [0, 21])
async def test_direct_verification_path_limits_before_reads(monkeypatch, count):
    def forbidden_read(*_):
        raise AssertionError("No file read allowed for invalid path count")
    monkeypatch.setattr(v, "read_selected", forbidden_read)
    with pytest.raises(ToolError, match="1 to 20"):
        await v.verify(None, ["note.md"] * count)


@pytest.mark.parametrize("count", [1, 20])
async def test_direct_verification_accepts_boundary_path_counts(monkeypatch, count):
    monkeypatch.setattr(v, "read_selected", lambda *_: b"# Synthetic")
    async def execute(*_):
        return {"documents": [], "chunks": []}
    result = await v.verify(SimpleNamespace(source_root=Path(".")), ["note.md"] * count, execute)
    assert len(result["files"]) == count
    assert result["all_cdc_verified"] is False


def test_flag_view_escapes_content_and_renders_independent_badges():
    malicious = '<script>alert("private")</script>'
    row = flag(title=malicious, summary=malicious, source_ref=malicious).model_dump()
    html = flag_view.render({"flags": [row], "domain": malicious, "truncated": True})
    assert "<script>" not in html
    assert "&lt;script&gt;" in html
    assert '<b>CRITICAL</b>' in html
    assert '<span>owner_decision</span>' in html
    assert '<span>active</span>' in html
    assert "Priority is not authority" in html
    assert "Snapshot, not live monitoring" in html
    assert "More flags exist" in html
    assert "default-src 'none'" in html
