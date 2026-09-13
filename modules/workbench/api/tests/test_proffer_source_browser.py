"""Case Bible Sorted source-browser contract tests.

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
from app.service import proffer
from app.service import source_inspection
from app.types.source_context import SourceContextReceipt


def test_browser_lists_fixed_bucket_with_delimiter_pagination_and_filter(monkeypatch) -> None:
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

    monkeypatch.setattr(proffer, "list_casebible_sorted_objects", fake_list)
    result = proffer.browse_sources(
        prefix="exports/", continuation_token="opaque-current", filter_text="message", page_size=25
    )

    assert captured == {"prefix": "exports/", "continuation_token": "opaque-current", "max_keys": 25}
    assert result.source == "casebible-sorted"
    assert result.delimiter == "/"
    assert result.filter == "message" and result.filter_applied is True
    assert result.is_truncated is True and result.continuation_token == "opaque-next"
    assert [item.prefix for item in result.prefixes] == ["exports/messages/"]
    assert [item.key for item in result.objects] == ["exports/messages/thread.json"]
    assert not hasattr(result.objects[0], "sha256"), "remote listings must not claim an acquisition digest"


def test_object_store_client_never_accepts_a_bucket_from_the_browser(monkeypatch) -> None:
    class Client:
        def list_objects_v2(self, **kwargs):
            assert kwargs["Bucket"] == "casebible-sorted"
            assert kwargs["Delimiter"] == "/"
            return {"Contents": [], "CommonPrefixes": []}

    monkeypatch.setattr(object_store_client, "get_casebible_sorted_client", lambda: Client())
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
        proffer,
        "list_casebible_sorted_objects",
        lambda **_: (_ for _ in ()).throw(AssertionError("object store must not be called")),
    )
    try:
        proffer.browse_sources(prefix="../wrong-case/")
    except proffer.ProfferError as error:
        assert error.status_code == 422
    else:
        raise AssertionError("escaping prefix accepted")


def test_source_inspection_hashes_immediately_without_claiming_a_custody_digest(monkeypatch) -> None:
    payload = b"%PDF-1.7\nsmall source preview"
    modified = datetime(2026, 8, 30, tzinfo=UTC)
    monkeypatch.setattr(
        source_inspection,
        "head_casebible_sorted_object",
        lambda key: {
            "ContentLength": len(payload),
            "ETag": '"object-etag"',
            "ContentType": "application/pdf",
            "LastModified": modified,
        },
    )
    monkeypatch.setattr(
        source_inspection,
        "open_casebible_sorted_object",
        lambda key, **kwargs: {"Body": io.BytesIO(payload)},
    )
    app = FastAPI()
    app.include_router(source_runtime.router)

    response = TestClient(app).post(
        "/api/proffer/source-inspection",
        json={
            "key": "filings/source.pdf",
            "expected_byte_length": len(payload),
            "expected_etag": '"object-etag"',
        },
    )

    assert response.status_code == 200
    body = response.json()
    assert body["sha256"] == hashlib.sha256(payload).hexdigest()
    assert body["digest_status"] == "preview_only"
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
        "head_casebible_sorted_object",
        lambda key: {"ContentLength": 12, "ETag": '"new-etag"'},
    )
    app = FastAPI()
    app.include_router(source_runtime.router)

    response = TestClient(app).post(
        "/api/proffer/source-inspection",
        json={"key": "source.pdf", "expected_byte_length": 11, "expected_etag": '"old-etag"'},
    )

    assert response.status_code == 409
    assert "choose it again" in response.json()["detail"]


def test_source_content_is_same_origin_etag_pinned_and_range_bounded(monkeypatch) -> None:
    payload = b"0123456789"
    captured = {}
    monkeypatch.setattr(
        source_inspection,
        "head_casebible_sorted_object",
        lambda key: {"ContentLength": len(payload), "ETag": '"etag"', "ContentType": "application/pdf"},
    )

    def fake_open(key, **kwargs):
        captured.update(kwargs)
        return {"Body": io.BytesIO(payload[2:6])}

    monkeypatch.setattr(source_inspection, "open_casebible_sorted_object", fake_open)
    app = FastAPI()
    app.include_router(source_runtime.router)

    response = TestClient(app).get(
        "/api/proffer/source-content",
        params={"key": "source.pdf", "etag": '"etag"'},
        headers={"Range": "bytes=2-5"},
    )

    assert response.status_code == 206
    assert response.content == b"2345"
    assert response.headers["content-range"] == "bytes 2-5/10"
    assert response.headers["accept-ranges"] == "bytes"
    assert captured == {"if_match": '"etag"', "byte_range": "bytes=2-5"}


def test_source_context_route_uses_authenticated_actor_and_returns_only_receipt(monkeypatch) -> None:
    captured = {}

    async def fake_create(body, actor):
        captured.update(body=body, actor=actor)
        return SourceContextReceipt(
            source_context_ref="33333333-3333-3333-3333-333333333333",
            receipt_ref="proffer-source-context://33333333-3333-3333-3333-333333333333",
            content_digest="a" * 64,
            revision=1,
            recorded_at=datetime(2026, 8, 30, tzinfo=UTC),
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
        "/api/proffer/source-contexts",
        json={
            "request_id": "request-1",
            "matter_id": "11111111-1111-1111-1111-111111111111",
            "court_case_id": "22222222-2222-2222-2222-222222222222",
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
        },
    )

    assert response.status_code == 201
    assert response.json()["source_context_ref"] == "33333333-3333-3333-3333-333333333333"
    assert captured["actor"].subject_uid == "authentik-user-1"
    assert captured["actor"].username == "operator"
    assert captured["body"].assertions.other_party == "Other party"
