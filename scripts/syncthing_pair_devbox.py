#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["httpx>=0.27"]
# ///
"""Pair the desktop Syncthing with the devbox Syncthing and share the state folders both ways
(owner 2026-09-07 21:33 "we will try and keep the state in sync"; 2026-09-08 00:19 "do that").
Idempotent: devices/folders already present are updated, never duplicated. Nothing deleted.
Byline: Claude Code · Fable 5.1 · 2026-09-08

Desktop side: local Syncthing GUI/API at 127.0.0.1:8384 (config under %LOCALAPPDATA%\\Syncthing).
Devbox side: Syncthing API at 100.91.190.107:8384 (config in the devbox persist tree, read over ssh).
"""
from __future__ import annotations
import os, re, subprocess, sys
from pathlib import Path
import httpx

DESK_HOME = Path(os.environ["LOCALAPPDATA"]) / "Syncthing"
DESK_URL = "http://127.0.0.1:8384"
DEV_URL = "http://100.91.190.107:8384"
DEV_ADDR = "tcp://100.91.190.107:22000"
DEV_CFG = "/data/probata/volumes/devbox/home/.config/syncthing/config.xml"
P = "/home/kasm-user/persist"
FOLDERS = [  # id, label, desktop path, devbox path
    ("fct-memory", "Claude auto-memory (probata)", str(Path.home() / ".claude/projects/E--AI-Workspace-Projects-the-platform-workspace-probata/memory"), f"{P}/.claude/projects/-home-kasm-user-work-probata/memory"),
    ("probata-remember", "probata .remember", r"E:\AI_Workspace\Projects\the-platform-workspace\probata\.remember", f"{P}/work/probata/.remember"),
    ("opencode-home", "~/.opencode", str(Path.home() / ".opencode"), f"{P}/.opencode"),
    ("work-sync", "work sync drop", r"E:\AI_Workspace\sync", f"{P}/work/sync"),
    ("claude-skills", "~/.claude/skills", str(Path.home() / ".claude/skills"), f"{P}/.claude/skills"),
    ("agents-skills", "~/.agents/skills", str(Path.home() / ".agents/skills"), f"{P}/.agents/skills"),
    ("local-plugins", "~/.claude/local-plugins", str(Path.home() / ".claude/local-plugins"), f"{P}/.claude/local-plugins"),
]


def xml_field(text: str, tag: str) -> str:
    m = re.search(rf"<{tag}>([^<]+)</{tag}>", text)
    return m.group(1) if m else ""


desk_cfg = (DESK_HOME / "config.xml").read_text(encoding="utf-8")
desk_key = xml_field(desk_cfg, "apikey")
desk_id = re.search(r'<device id="([A-Z0-9-]+)"', desk_cfg).group(1)
dev_cfg = subprocess.run(["ssh", "-i", str(Path.home() / ".ssh/ovh"), "-o", "BatchMode=yes", "root@100.91.190.107", f"cat {DEV_CFG}"], capture_output=True, text=True, check=True).stdout
dev_key = xml_field(dev_cfg, "apikey")
dev_id = re.search(r'<device id="([A-Z0-9-]+)"', dev_cfg).group(1)
print("desktop", desk_id[:7], "| devbox", dev_id[:7])
Path(r"E:\AI_Workspace\sync").mkdir(exist_ok=True)


IGNORE = "node_modules\n.git\n.review_hold\n__pycache__\n.venv\n*.duckdb\n"   # owner junk-scrub rule; applied as .stignore on both sides
for _fid, _label, dpath, _v in FOLDERS:
    try:
        Path(dpath).mkdir(parents=True, exist_ok=True); (Path(dpath) / ".stignore").write_text(IGNORE, encoding="utf-8")
    except OSError as e: print("stignore skip", dpath, e)
subprocess.run(["ssh", "-i", str(Path.home() / ".ssh/ovh"), "-o", "BatchMode=yes", "root@100.91.190.107",
    " && ".join(f"install -d -o 1000 -g 1000 {v} && printf '{IGNORE}' > {v}/.stignore && chown 1000:1000 {v}/.stignore" for _f,_l,_d,v in FOLDERS)], check=False)

def side(url: str, key: str, my_id: str, peer_id: str, peer_name: str, peer_addr: list[str], path_idx: int) -> None:
    c = httpx.Client(base_url=url, headers={"X-API-Key": key}, timeout=30)
    c.put(f"/rest/config/devices/{peer_id}", json={"deviceID": peer_id, "name": peer_name, "addresses": peer_addr, "autoAcceptFolders": False}).raise_for_status()
    for fid, label, dpath, vpath in FOLDERS:
        path = (dpath, vpath)[path_idx]
        c.put(f"/rest/config/folders/{fid}", json={
            "id": fid, "label": label, "path": path, "type": "sendreceive",
            "devices": [{"deviceID": my_id}, {"deviceID": peer_id}],
            "rescanIntervalS": 3600, "fsWatcherEnabled": True, "fsWatcherDelayS": 10,
            "ignorePerms": True, "minDiskFree": {"value": 1, "unit": "%"},
            "versioning": {"type": "simple", "params": {"keep": "5"}},
        }).raise_for_status()
    st = c.get("/rest/system/status").json()
    print(f"{url}: myID={st['myID'][:7]} folders={len(c.get('/rest/config/folders').json())} devices={len(c.get('/rest/config/devices').json())}")


side(DESK_URL, desk_key, desk_id, dev_id, "devbox", [DEV_ADDR], 0)
side(DEV_URL, dev_key, dev_id, desk_id, "desktop", ["dynamic"], 1)
print("paired; first sync starts automatically. Desktop GUI: http://127.0.0.1:8384  Devbox GUI: http://100.91.190.107:8384")
