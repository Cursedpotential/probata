"""Bounded object-stream opening for the canonical Proffer staged bridge."""

from botocore.exceptions import ClientError

from app.repo.object_store_client import STAGING_BUCKET, get_client, validate_source_key


def open_staged_object(key: str) -> dict:
    """Open a fixed Nexus stream; never accept a browser bucket or URL."""
    key = validate_source_key(key)
    try:
        return get_client().get_object(Bucket=STAGING_BUCKET, Key=key)
    except ClientError as error:
        raise RuntimeError("Staged source read failed") from error
