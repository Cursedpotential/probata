# Byline: Claude Code · Sonnet (agent) · 2026-07-19
# Byline: Codex · GPT-5.6-Sol · 2026-08-30 (fixed source/staging buckets and runtime credentials)
"""S3-compatible object store repo layer for allowlisted Platform-owned R2 roots.

Adapted from the donor kit's b2_client.py. All boto3 usage is confined to this
module (enforced by tests/test_structure.py::test_boto3_only_in_repo). B2-specific
naming (user-agent string, "B2" identifiers) has been stripped in favor of the
The runtime credential document configures the account endpoint and credentials;
Browser input can select only a named root from :data:`SOURCE_ROOTS`; it can
never supply an arbitrary provider, endpoint, or bucket.  Every Case Bible root
is read-only. Workbench staging writes remain fixed to ``nexus``.
"""

from __future__ import annotations

import io
import json
import logging
import mimetypes
import re
from dataclasses import dataclass
from pathlib import Path
from typing import IO

import boto3
from botocore.config import Config
from botocore.exceptions import ClientError
from functools import lru_cache

from app.config import settings

logger = logging.getLogger(__name__)

CASEBIBLE_SORTED_BUCKET = "casebible-sorted"
CASEBIBLE_SORTED_PREFIX = ""
STAGING_BUCKET = "nexus"
MAX_SOURCE_KEY_LENGTH = 1024
_SAFE_SOURCE_KEY = re.compile(r"^[^\x00\r\n\\]+$")


@dataclass(frozen=True)
class SourceRoot:
    root_id: str
    label: str
    bucket: str
    root_ref: str
    temporary: bool = True


SOURCE_ROOTS: dict[str, SourceRoot] = {
    "r2-raw": SourceRoot("r2-raw", "R2 / Case Bible Raw", "casebible-raw", "r2://casebible-raw/"),
    "r2-sorted": SourceRoot(
        "r2-sorted", "R2 / Case Bible Sorted", CASEBIBLE_SORTED_BUCKET, "r2://casebible-sorted/"
    ),
    "r2-quarantine": SourceRoot(
        "r2-quarantine",
        "R2 / Case Bible Quarantine",
        "casebible-quarantine",
        "r2://casebible-quarantine/",
    ),
}
DEFAULT_SOURCE_ROOT_ID = "r2-sorted"


@dataclass(frozen=True)
class R2Config:
    endpoint_url: str
    region: str
    access_key_id: str
    secret_access_key: str
    session_token: str | None = None


def get_casebible_r2_config_path() -> str:
    """Return the runtime secret path; settings integration may replace this accessor."""
    return str(getattr(settings, "casebible_r2_config_path", "")).strip()


@lru_cache(maxsize=1)
def get_r2_client():
    """Build the shared R2 client from the runtime-mounted credential document."""
    config_path = get_casebible_r2_config_path()
    if not config_path:
        raise RuntimeError("Platform R2 configuration is unavailable")
    try:
        payload = json.loads(Path(config_path).read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        raise RuntimeError("Platform R2 configuration could not be loaded") from error
    allowed = {"endpoint_url", "region", "access_key_id", "secret_access_key", "session_token"}
    if not isinstance(payload, dict) or set(payload) - allowed:
        raise RuntimeError("Platform R2 configuration is invalid")
    required = ("endpoint_url", "region", "access_key_id", "secret_access_key")
    if any(not isinstance(payload.get(key), str) or not payload[key].strip() for key in required):
        raise RuntimeError("Platform R2 configuration is invalid")
    if payload.get("session_token") is not None and not isinstance(payload["session_token"], str):
        raise RuntimeError("Platform R2 configuration is invalid")
    config = R2Config(**payload)
    return boto3.client(
        "s3",
        endpoint_url=config.endpoint_url,
        region_name=config.region,
        aws_access_key_id=config.access_key_id,
        aws_secret_access_key=config.secret_access_key,
        aws_session_token=config.session_token,
        config=Config(signature_version="s3v4", s3={"addressing_style": "path"}),
    )


def get_casebible_sorted_client():
    """Return the shared client used for fixed Case Bible Sorted reads."""
    return get_r2_client()


def get_source_root(root_id: str) -> SourceRoot:
    """Resolve a browser root through the code-owned allowlist."""
    try:
        return SOURCE_ROOTS[root_id]
    except KeyError:
        raise ValueError("unknown or unavailable source root") from None


def validate_source_key(key: str, *, allow_empty: bool = False) -> str:
    """Validate a relative object key without allowing a root escape."""
    normalized = key.strip()
    if allow_empty and not normalized:
        return ""
    if (
        not normalized
        or len(normalized) > MAX_SOURCE_KEY_LENGTH
        or normalized.startswith("/")
        or not _SAFE_SOURCE_KEY.fullmatch(normalized)
        or ".." in normalized.split("/")
    ):
        raise ValueError("invalid source object key")
    return normalized


def list_source_objects(
    *,
    root_id: str,
    prefix: str = "",
    continuation_token: str | None = None,
    start_after: str | None = None,
    max_keys: int = 100,
    delimiter: str | None = "/",
) -> dict:
    """List one page from an allowlisted read-only source root."""
    root = get_source_root(root_id)
    validated_prefix = validate_source_key(prefix, allow_empty=True)
    if validated_prefix and prefix.endswith("/") and not validated_prefix.endswith("/"):
        validated_prefix += "/"
    request: dict[str, object] = {
        "Bucket": root.bucket,
        "Prefix": validated_prefix,
        "MaxKeys": max_keys,
    }
    if delimiter is not None:
        request["Delimiter"] = delimiter
    if continuation_token:
        request["ContinuationToken"] = continuation_token
    if start_after:
        request["StartAfter"] = validate_source_key(start_after)
    try:
        return get_r2_client().list_objects_v2(**request)
    except ClientError as error:
        raise RuntimeError(f"{root.label} source listing failed") from error


def head_source_object(root_id: str, key: str) -> dict:
    root = get_source_root(root_id)
    validated = validate_source_key(key)
    try:
        return get_r2_client().head_object(Bucket=root.bucket, Key=validated)
    except ClientError as error:
        raise RuntimeError(f"{root.label} source inspection failed") from error


def open_source_object(
    root_id: str,
    key: str,
    *,
    if_match: str | None = None,
    byte_range: str | None = None,
) -> dict:
    root = get_source_root(root_id)
    request: dict[str, str] = {"Bucket": root.bucket, "Key": validate_source_key(key)}
    if if_match:
        request["IfMatch"] = if_match
    if byte_range:
        request["Range"] = byte_range
    try:
        return get_r2_client().get_object(**request)
    except ClientError as error:
        raise RuntimeError(f"{root.label} source read failed") from error


def list_casebible_sorted_objects(
    *, prefix: str = "", continuation_token: str | None = None, max_keys: int = 100
) -> dict:
    """List one delimiter-bounded page from the fixed Case Bible Sorted bucket."""
    return list_source_objects(
        root_id=DEFAULT_SOURCE_ROOT_ID,
        prefix=prefix,
        continuation_token=continuation_token,
        max_keys=max_keys,
    )


def validate_casebible_sorted_key(key: str) -> str:
    """Validate one browser-supplied coordinate inside the fixed source bucket."""
    try:
        return validate_source_key(key)
    except ValueError:
        raise ValueError("invalid Case Bible Sorted object key") from None


def head_casebible_sorted_object(key: str) -> dict:
    """Read immutable-object coordinates from the fixed source bucket."""
    return head_source_object(DEFAULT_SOURCE_ROOT_ID, validate_casebible_sorted_key(key))


def open_casebible_sorted_object(
    key: str,
    *,
    if_match: str | None = None,
    byte_range: str | None = None,
) -> dict:
    """Open a source stream without allowing the caller to choose storage scope."""
    return open_source_object(
        DEFAULT_SOURCE_ROOT_ID,
        validate_casebible_sorted_key(key),
        if_match=if_match,
        byte_range=byte_range,
    )


def get_client():
    """Compatibility accessor for the fixed Nexus staging client."""
    return get_r2_client()


def check_connectivity() -> bool:
    """Prove that both fixed buckets are reachable with the runtime credential."""
    try:
        client = get_r2_client()
        client.head_bucket(Bucket=CASEBIBLE_SORTED_BUCKET)
        client.head_bucket(Bucket=STAGING_BUCKET)
        return True
    except Exception:
        logger.warning("Object store connectivity check failed", exc_info=True)
        return False


def put_object(key: str, data: bytes | IO[bytes], content_type: str | None = None) -> None:
    """Upload bytes or a file-like object to `key`. Raises RuntimeError on failure."""
    body = data if hasattr(data, "read") else io.BytesIO(data)  # type: ignore[arg-type]
    guessed_type = content_type or mimetypes.guess_type(key)[0] or "application/octet-stream"
    try:
        get_client().put_object(
            Bucket=STAGING_BUCKET,
            Key=key,
            Body=body,
            ContentType=guessed_type,
        )
    except ClientError as e:
        raise RuntimeError(f"Object store upload failed for '{key}': {e}") from e


def get_object(key: str) -> bytes:
    """Download and return the raw bytes stored at `key`. Raises RuntimeError on failure."""
    try:
        response = get_client().get_object(Bucket=STAGING_BUCKET, Key=key)
        return response["Body"].read()
    except ClientError as e:
        raise RuntimeError(f"Object store download failed for '{key}': {e}") from e


def object_exists(key: str) -> bool:
    """Check whether `key` exists in the bucket. Re-raises on non-404 errors."""
    try:
        get_client().head_object(Bucket=STAGING_BUCKET, Key=key)
        return True
    except ClientError as e:
        code = e.response.get("Error", {}).get("Code", "")
        if code in ("404", "NoSuchKey"):
            return False
        raise


def presigned_get(key: str, expires: int = 600) -> str:
    """Generate a presigned GET URL for `key`, valid for `expires` seconds."""
    try:
        return get_client().generate_presigned_url(
            "get_object",
            Params={"Bucket": STAGING_BUCKET, "Key": key},
            ExpiresIn=expires,
        )
    except ClientError as e:
        raise RuntimeError(f"Object store presign failed for '{key}': {e}") from e
