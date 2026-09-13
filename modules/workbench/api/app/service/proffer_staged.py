"""Server-authored Nexus acquisition references. No source bytes enter the browser."""

import asyncio
import hashlib
from urllib.parse import quote

from app.config import settings
from app.repo import staging
from app.repo.object_store_client import validate_source_key
from app.repo.staged_acquisition import open_staged_object
from app.service.proffer import ProfferError, _require_mode_configuration
from app.types.matter_mode import MatterMode
from app.types.proffer import ProfferUploadResponse


async def acquire_staged(staged_id: str, *, mode: MatterMode):
    _require_mode_configuration(mode)
    if settings.object_store_prefix.strip("/") != "workbench/staging":
        raise ProfferError("Staging prefix is not admitted by the engine source policy", 503)
    record = await asyncio.to_thread(staging.get, staged_id)
    if record is None:
        raise ProfferError("Staged source not found", 404)
    try:
        key = validate_source_key(record["r2_key"])
        expected_prefix = f"{settings.object_store_prefix.strip('/')}/{staged_id}/"
        if not key.startswith(expected_prefix):
            raise ValueError("source outside staging identity")
        source = await asyncio.to_thread(open_staged_object, key)
    except (RuntimeError, ValueError, KeyError):
        raise ProfferError("Staged source is unavailable or outside its staging identity", 502) from None
    stream = source["Body"]
    digest = hashlib.sha256()
    byte_length = 0
    try:
        while chunk := await asyncio.to_thread(stream.read, 1024 * 1024):
            digest.update(chunk)
            byte_length += len(chunk)
    finally:
        await asyncio.to_thread(stream.close)
    if digest.hexdigest() != staged_id or byte_length != source["ContentLength"]:
        raise ProfferError("Staged source fingerprint changed; import was not started", 409)
    return ProfferUploadResponse(
        acquisition_ref=f"r2://nexus/{quote(key, safe='/')}",
        sha256=digest.hexdigest(),
        byte_length=byte_length,
        matter_mode=mode,
    )
