"""Static release contract for persistent framework-neutral ingest staging.

Byline: Codex · GPT-5.6 · 2026-08-29.

These tests parse the tracked production manifest only. They do not run a
container, change Coolify, prepare the host, or establish live deployment.
"""

from __future__ import annotations

from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[1]
DEPLOY_PATH = ROOT / "deploy" / "exec.yaml"
RECEIPT_PATH = ROOT / "docs" / "reviews" / "2026-08-29-framework-neutral-ingest-recovery.md"
DEPLOY_TEXT = DEPLOY_PATH.read_text(encoding="utf-8")
RECEIPT_TEXT = RECEIPT_PATH.read_text(encoding="utf-8")

HOST_STAGING_ROOT = "/data/probata/volumes/ingest-staging"
CONTAINER_STAGING_ROOT = "/data/ingest-staging"


def _platform_api() -> dict:
    return yaml.safe_load(DEPLOY_TEXT)["services"]["platform-api"]


def _staging_mount() -> dict:
    matches = [
        mount
        for mount in _platform_api()["volumes"]
        if isinstance(mount, dict) and mount.get("target") == CONTAINER_STAGING_ROOT
    ]
    assert len(matches) == 1
    return matches[0]


def test_production_api_uses_literal_persistent_staging_root() -> None:
    environment = _platform_api()["environment"]
    staging_root = environment["INGEST_STAGING_ROOT"]

    assert staging_root == CONTAINER_STAGING_ROOT
    assert staging_root.startswith("/")
    assert "/tmp" not in staging_root
    assert "${" not in staging_root


def test_staging_is_a_fail_closed_protected_host_bind() -> None:
    mount = _staging_mount()

    assert mount["type"] == "bind"
    assert mount["source"] == HOST_STAGING_ROOT
    assert mount.get("read_only", False) is False
    assert mount["bind"]["create_host_path"] is False


def test_upload_staging_does_not_reuse_the_operator_drop_directory() -> None:
    volumes = _platform_api()["volumes"]

    assert "/srv/ingest:/data/ingest" in volumes
    assert _staging_mount()["source"] != "/srv/ingest"
    assert _staging_mount()["target"] != "/data/ingest"


def test_host_prep_and_release_hold_are_documented_exactly() -> None:
    host_prep = f"sudo install -d -m 0700 -o root -g root {HOST_STAGING_ROOT}"

    assert host_prep in DEPLOY_TEXT
    assert host_prep in RECEIPT_TEXT
    assert "create_host_path: false" in RECEIPT_TEXT
    assert "SOURCE IMPLEMENTED / NOT DEPLOYED / NOT LIVE-PROVEN" in RECEIPT_TEXT


def test_actual_coolify_app_and_stale_watch_path_are_named_as_release_gates() -> None:
    assert "rz41wqhpjfh1rj796ixvjhfs" in RECEIPT_TEXT
    assert "compose.exec.yaml" in RECEIPT_TEXT
    assert "deploy/exec.yaml" in RECEIPT_TEXT
    assert "did not mutate Coolify" in RECEIPT_TEXT


def test_staging_contract_contains_no_secret_or_password_setting() -> None:
    environment = _platform_api()["environment"]
    staging_keys = {key for key in environment if "STAGING" in key or "INGEST_STAGING" in key}

    assert staging_keys == {"INGEST_STAGING_ROOT"}
    assert all(token not in environment["INGEST_STAGING_ROOT"].upper() for token in ("PASS", "SECRET", "TOKEN", "KEY"))
