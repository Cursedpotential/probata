#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["httpx>=0.27"]
# ///
"""Register the platform's storages in OpenList (owner 2026-09-07 18:18 / 21:22 "go storages"):
R2 buckets (S3 driver), the B2 bucket (S3 driver), and the two local mounts baked into deploy/openlist.yaml.
Credentials are read from ~/.secrets/*.env by tolerant regex (never `source`d, never printed); nothing
is written to the repo. Idempotent: existing mount paths are skipped. Byline: Claude Code · Fable 5.1 · 2026-09-07

Usage:  uv run scripts/openlist_add_storages.py [--dry-run]
"""
from __future__ import annotations
import json, os, re, sys
from pathlib import Path
import httpx

SECRETS = Path.home() / ".secrets"
DRY = "--dry-run" in sys.argv


def env_all() -> dict[str, str]:
    out: dict[str, str] = {}
    for f in sorted(SECRETS.glob("*.env")):
        for line in f.read_text(encoding="utf-8", errors="replace").splitlines():
            m = re.match(r"^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.+?)\s*$", line)
            if m and m.group(1) not in out:
                v = m.group(2).strip().strip('"').strip("'")
                if v:
                    out[m.group(1)] = v
    return out


E = env_all()
URL = E.get("OPENLIST_URL", "http://100.91.190.107:5244").rstrip("/")
USER = E.get("OPENLIST_ADMIN_USER", "admin")
PASS = E["OPENLIST_ADMIN_PASSWORD"]

R2_ENDPOINT = E.get("R2_ENDPOINT_URL") or E.get("R2_CASE_BIBLE_ENDPOINT") or f"https://{E.get('R2_ACCOUNT_ID', '')}.r2.cloudflarestorage.com"
R2_KEY = E.get("R2_ACCESS_KEY_ID") or E.get("R2_CASE_BIBLE_ACCESS_KEY_ID", "")
R2_SECRET = E.get("R2_SECRET_ACCESS_KEY") or E.get("R2_CASE_BIBLE_SECRET_ACCESS_KEY", "")
R2_BUCKETS = ["casebible-raw", "casebible-sorted", "casebible-quarantine"]
B2_KEY = E.get("B2_KEY_ID", ""); B2_SECRET = E.get("B2_APPLICATION_KEY", "")
B2_BUCKET = E.get("B2_BUCKET_SALEM_DATA", ""); B2_REGION = E.get("B2_REGION", "us-west-004")
B2_ENDPOINT = f"https://s3.{B2_REGION}.backblazeb2.com"


def s3(mount: str, bucket: str, endpoint: str, region: str, key: str, secret: str) -> dict:
    return {
        "mount_path": mount, "driver": "S3", "order": 0, "cache_expiration": 30, "enable_sign": False,
        "addition": json.dumps({
            "bucket": bucket, "endpoint": endpoint, "region": region,
            "access_key_id": key, "secret_access_key": secret, "session_token": "",
            "custom_host": "", "sign_url_expire": 4, "placeholder": "", "force_path_style": True,
            "list_object_version": "v1", "remove_bucket": False, "add_filename_to_disposition": False,
            "root_folder_path": "/",
        }),
    }


def local(mount: str, path: str) -> dict:
    return {"mount_path": mount, "driver": "Local", "order": 0, "cache_expiration": 5,
            "addition": json.dumps({"root_folder_path": path, "thumbnail": False, "thumb_cache_folder": "",
                                    "show_hidden": True, "mkdir_perm": "777", "recycle_bin_path": "delete permanently"})}


WANT: list[dict] = [local("/exchange", "/mnt/exchange"), local("/volumes", "/mnt/probata-volumes")]
if R2_KEY and R2_SECRET:
    WANT += [s3(f"/r2/{b}", b, R2_ENDPOINT, "auto", R2_KEY, R2_SECRET) for b in R2_BUCKETS]
else:
    print("R2: no key pair found in ~/.secrets — skipped")
if B2_KEY and B2_SECRET and B2_BUCKET:
    WANT.append(s3(f"/b2/{B2_BUCKET}", B2_BUCKET, B2_ENDPOINT, B2_REGION, B2_KEY, B2_SECRET))
else:
    print("B2: key/bucket not found in ~/.secrets — skipped")

with httpx.Client(base_url=URL, timeout=30) as c:
    tok = c.post("/api/auth/login", json={"username": USER, "password": PASS}).json()["data"]["token"]
    h = {"Authorization": tok}
    have = {s["mount_path"] for s in c.get("/api/admin/storage/list", headers=h).json()["data"]["content"] or []}
    for st in WANT:
        if st["mount_path"] in have:
            print("exists ", st["mount_path"]); continue
        if DRY:
            print("would add", st["mount_path"], st["driver"]); continue
        r = c.post("/api/admin/storage/create", headers=h, json=st).json()
        print("added  " if r.get("code") == 200 else "FAILED ", st["mount_path"], st["driver"], "" if r.get("code") == 200 else r.get("message"))
    # verify each mount lists
    for st in WANT:
        r = c.post("/api/fs/list", headers=h, json={"path": st["mount_path"], "page": 1, "per_page": 3, "refresh": True}).json()
        n = len((r.get("data") or {}).get("content") or []) if r.get("code") == 200 else -1
        print(f"list {st['mount_path']:28} -> {'ok' if n >= 0 else 'ERR'} {r.get('message','') if n < 0 else f'{n} entries shown'}")
