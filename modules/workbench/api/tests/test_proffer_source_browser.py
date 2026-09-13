"""Allowlisted Case Bible source-browser contract tests.

Byline: Codex · GPT-5 · 2026-08-29.
"""

from __future__ import annotations

from datetime import UTC, datetime
import hashlib
import io
import json

from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.repo import object_store_client
from app.runtime import source_inspection as source_runtime
from app.service import proffer, proffer_sources
from app.service import source_inspection
from app.types.source_context import SourceContextReceipt


def test_browser_lists_selected_root_with_delimiter_and_file_details(monkeypatch) -> None:
    captured = {}

    def fake_list(**kwargs):
        captured.update(kwargs)
        return {
            "IsTruncated": True,
            "NextContinuationToken": "opaque-next",
            "CommonPrefixes": [{"Prefix": "exports/messages/"}, {"Prefix": "exports/photos/"}],
            "Contents": [
                {
                    "Key": "exports/messages/thread.json",
                    "Size": 41,
                    "ETag": '"not-a-sha256"',
                    "LastModified": datetime(2026, 8, 29, tzinfo=UTC),
                },
                {"Key": "exports/photos/photo.jpg", "Size": 99},
            ],
        }

    monkeypatch.setattr(proffer_sources, "list_source_objects", fake_list)
    result = proffer.browse_sources(
        mode="TEST", root_id="r2-raw", prefix="exports/", continuation_token="opaque-current", page_size=25
    )

    assert captured == {
        "root_id": "r2-raw",
        "prefix": "exports/",
        "continuation_token": "opaque-current",
        "max_keys": 25,
    }
    assert result.source == "casebible-raw" and result.active_root_id == "r2-raw"
    assert result.delimiter == "/"
    assert result.filter == "" and result.filter_applied is False
    assert result.is_truncated is True and result.continuation_token == "opaque-next"
    assert [item.prefix for item in result.prefixes] == ["exports/messages/", "exports/photos/"]
    assert [item.key for item in result.objects] == ["exports/messages/thread.json", "exports/photos/photo.jpg"]
    assert result.objects[0].source_ref == "r2://casebible-raw/exports/messages/thread.json"
    assert result.objects[0].file_kind == "structured_data"
    assert {root.root_id for root in result.available_roots} == {"r2-raw", "r2-sorted", "r2-quarantine"}
    assert not hasattr(result.objects[0], "sha256"), "remote listings must not claim an acquisition digest"


def test_root_search_scans_beyond_the_first_provider_page_and_filters_type(monkeypatch) -> None:
    calls = []

    def fake_list(**kwargs):
        calls.append(kwargs)
        if len(calls) == 1:
            return {
                "IsTruncated": True,
                "NextContinuationToken": "provider-page-2",
                "Contents": [{"Key": "unrelated/photo.jpg", "Size": 1}],
            }
        return {
            "IsTruncated": False,
            "Contents": [{"Key": "AI_Chats/export.zip", "Size": 14_794_205}],
        }

    monkeypatch.setattr(proffer_sources, "list_source_objects", fake_list)
    result = proffer.browse_sources(
        mode="TEST",
        root_id="r2-raw",
        prefix="ignored-while-root-searching/",
        filter_text="AI_Chats",
        filter_scope="root",
        file_types=("archive",),
        page_size=25,
    )

    assert len(calls) == 2
    assert calls[0]["prefix"] == "" and calls[0]["delimiter"] is None
    assert calls[1]["continuation_token"] == "provider-page-2"
    assert [item.key for item in result.objects] == ["AI_Chats/export.zip"]
    assert result.objects[0].archive_format == "zip"
    assert result.search_complete is True and result.scanned_count == 2


def test_object_store_client_never_accepts_a_bucket_from_the_browser(monkeypatch) -> None:
    class Client:
        def list_objects_v2(self, **kwargs):
            assert kwargs["Bucket"] == "casebible-sorted"
            assert kwargs["Delimiter"] == "/"
            return {"Contents": [], "CommonPrefixes": []}

    monkeypatch.setattr(object_store_client, "get_r2_client", lambda: Client())
    object_store_client.list_casebible_sorted_objects(prefix="", max_keys=10)


def test_runtime_json_accessor_supplies_credentials_without_configurable_bucket(monkeypatch, tmp_path) -> None:
    secret_path = tmp_path / "casebible-r2.json"
    secret_path.write_text(
        json.dumps(
            {
                "endpoint_url": "https://example.r2.cloudflarestorage.com",
                "region": "auto",
                "access_key_id": "test-ak",
                "secret_access_key": "test-sk",
            }
        ),
        encoding="utf-8",
    )
    captured = {}

    def fake_client(service, **kwargs):
        captured.update(service=service, **kwargs)
        return object()

    monkeypatch.setattr(object_store_client, "get_casebible_r2_config_path", lambda: str(secret_path))
    monkeypatch.setattr(object_store_client.boto3, "client", fake_client)
    object_store_client.get_r2_client.cache_clear()
    object_store_client.get_r2_client()

    assert captured["service"] == "s3"
    assert captured["endpoint_url"] == "https://example.r2.cloudflarestorage.com"
    assert "bucket" not in captured
    object_store_client.get_r2_client.cache_clear()


def test_runtime_client_uses_fixed_source_and_staging_buckets(monkeypatch) -> None:
    calls = []

    class Client:
        def head_bucket(self, **kwargs):
            calls.append(("head", kwargs))

        def put_object(self, **kwargs):
            calls.append(("put", kwargs))

        def get_object(self, **kwargs):
            calls.append(("get", kwargs))
            return {"Body": io.BytesIO(b"source")}

        def head_object(self, **kwargs):
            calls.append(("exists", kwargs))

        def generate_presigned_url(self, operation, **kwargs):
            calls.append((operation, kwargs))
            return "https://example.invalid/object"

    client = Client()
    monkeypatch.setattr(object_store_client, "get_r2_client", lambda: client)
    monkeypatch.setattr(object_store_client, "get_client", lambda: client)

    assert object_store_client.check_connectivity() is True
    object_store_client.put_object("workbench/staging/sha/source.md", b"text")
    assert object_store_client.get_object("workbench/staging/sha/source.md") == b"source"
    assert object_store_client.object_exists("workbench/staging/sha/source.md") is True
    assert object_store_client.presigned_get("workbench/staging/sha/source.md")

    assert [call[1]["Bucket"] for call in calls[:2]] == ["casebible-sorted", "nexus"]
    assert calls[2][0] == "put"
    assert calls[2][1]["Bucket"] == "nexus"
    assert calls[3][1]["Bucket"] == "nexus"
    assert calls[4][1]["Bucket"] == "nexus"
    assert calls[5][1]["Params"]["Bucket"] == "nexus"


def test_browser_rejects_escape_prefix_before_object_store_call(monkeypatch) -> None:
    monkeypatch.setattr(
        proffer_sources,
        "list_source_objects",
        lambda **_: (_ for _ in ()).throw(AssertionError("object store must not be called")),
    )
    try:
        proffer.browse_sources(mode="TEST", prefix="../wrong-case/")
    except proffer.ProfferError as error:
        assert error.status_code == 422
    else:
        raise AssertionError("escaping prefix accepted")


def test_source_inspection_hashes_immediately_without_claiming_a_custody_digest(monkeypatch) -> None:
    payload = b"%PDF-1.7\nsmall source preview"
    modified = datetime(2026, 8, 30, tzinfo=UTC)
    monkeypatch.setattr(
        source_inspection,
        "head_source_object",
        lambda root_id, key: {
            "ContentLength": len(payload),
            "ETag": '"object-etag"',
            "ContentType": "application/pdf",
            "LastModified": modified,
        },
    )
    monkeypatch.setattr(
        source_inspection,
        "open_source_object",
        lambda root_id, key, **kwargs: {"Body": io.BytesIO(payload)},
    )
    app = FastAPI()
    app.include_router(source_runtime.router)

    response = TestClient(app).post(
        "/api/proffer/source-inspection?mode=TEST&root_id=r2-raw",
        json={
            "root_id": "r2-raw",
            "source_ref": "r2://casebible-raw/filings/source.pdf",
            "key": "filings/source.pdf",
            "expected_byte_length": len(payload),
            "expected_etag": '"object-etag"',
        },
    )

    assert response.status_code == 200
    body = response.json()
    assert body["sha256"] == hashlib.sha256(payload).hexdigest()
    assert body["digest_status"] == "preview_only"
    assert body["matter_mode"] == "TEST"
    assert body["active_root_id"] == "r2-raw"
    assert body["preview_kind"] == "pdf"
    assert body["preview_url"].startswith("/api/proffer/source-content?")
    assert body["parser_preflight"] == {
        "declared_format": "pdf",
        "route_label": "PDF document route",
        "basis": "filename_extension",
        "authoritative": False,
    }


def test_image_extensions_share_one_preview_and_preflight_classification() -> None:
    expected_extensions = {".avif", ".bmp", ".gif", ".jpeg", ".jpg", ".png", ".tif", ".tiff", ".webp"}

    assert source_inspection._IMAGE_EXTENSIONS == expected_extensions
    for extension in expected_extensions:
        preflight = source_inspection._preflight(f"photos/source{extension}")
        assert preflight.declared_format == "image"
        assert preflight.route_label == "Image processing route"
        assert preflight.basis == "filename_extension"
        assert preflight.authoritative is False


def test_source_inspection_rejects_a_changed_listing_identity(monkeypatch) -> None:
    monkeypatch.setattr(
        source_inspection,
        "head_source_object",
        lambda root_id, key: {"ContentLength": 12, "ETag": '"new-etag"'},
    )
    app = FastAPI()
    app.include_router(source_runtime.router)

    response = TestClient(app).post(
        "/api/proffer/source-inspection?mode=TEST&root_id=r2-sorted",
        json={
            "root_id": "r2-sorted",
            "source_ref": "r2://casebible-sorted/source.pdf",
            "key": "source.pdf",
            "expected_byte_length": 11,
            "expected_etag": '"old-etag"',
        },
    )

    assert response.status_code == 409
    assert "choose it again" in response.json()["detail"]


def test_source_content_is_same_origin_etag_pinned_and_range_bounded(monkeypatch) -> None:
    payload = b"0123456789"
    captured = {}
    monkeypatch.setattr(
        source_inspection,
        "head_source_object",
        lambda root_id, key: {"ContentLength": len(payload), "ETag": '"etag"', "ContentType": "application/pdf"},
    )

    def fake_open(root_id, key, **kwargs):
        captured.update(kwargs)
        return {"Body": io.BytesIO(payload[2:6])}

    monkeypatch.setattr(source_inspection, "open_source_object", fake_open)
    app = FastAPI()
    app.include_router(source_runtime.router)

    response = TestClient(app).get(
        "/api/proffer/source-content",
        params={"root_id": "r2-sorted", "key": "source.pdf", "etag": '"etag"'},
        headers={"Range": "bytes=2-5"},
    )

    assert response.status_code == 206
    assert response.content == b"2345"
    assert response.headers["content-range"] == "bytes 2-5/10"
    assert response.headers["accept-ranges"] == "bytes"
    assert captured == {"if_match": '"etag"', "byte_range": "bytes=2-5"}


def test_source_context_route_uses_authenticated_actor_and_returns_only_receipt(monkeypatch) -> None:
    captured = {}

    async def fake_create(body, actor, *, mode):
        captured.update(body=body, actor=actor, mode=mode)
        return SourceContextReceipt(
            source_context_ref="33333333-3333-3333-3333-333333333333",
            receipt_ref="proffer-source-context://33333333-3333-3333-3333-333333333333",
            content_digest="a" * 64,
            revision=1,
            recorded_at=datetime(2026, 8, 30, tzinfo=UTC),
            matter_mode="TEST",
        )

    monkeypatch.setattr(source_runtime, "create_source_context", fake_create)
    app = FastAPI()

    @app.middleware("http")
    async def identity(request, call_next):
        request.state.subject_uid = "authentik-user-1"
        request.state.principal = "operator"
        return await call_next(request)

    app.include_router(source_runtime.router)
    response = TestClient(app).post(
        "/api/proffer/source-contexts?mode=TEST",
        json={
            "request_id": "request-1",
            "matter_id": "deadbeef-dead-beef-dead-beefdeadbeef",
            "court_case_id": "cafebabe-cafe-babe-cafe-babecafebabe",
            "source_ref": "r2://casebible-sorted/source.pdf",
            "observed_source": {
                "key": "source.pdf",
                "name": "source.pdf",
                "byte_length": 10,
                "etag": '"etag"',
                "preview_sha256": "b" * 64,
            },
            "assertions": {"source_class": "acquired_third_party", "other_party": "Other party"},
            "change_reason": "Operator supplied source context during intake",
            "matter_mode": "TEST",
        },
    )

    assert response.status_code == 201
    assert response.json()["source_context_ref"] == "33333333-3333-3333-3333-333333333333"
    assert captured["actor"].subject_uid == "authentik-user-1"
    assert captured["actor"].username == "operator"
    assert captured["body"].assertions.other_party == "Other party"
    assert captured["mode"] == "TEST"
