#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["httpx>=0.27"]
# ///
"""Run a delegated task on the headless OpenCode server (ovh-files :4096) — the executor for delegated
work per owner rule 2026-09-07 21:23 (no Claude subagents; NIM/Ollama Cloud/OpenRouter models, spread out).
Byline: Claude Code · Fable 5.1 · 2026-09-08

usage: uv run scripts/oc_task.py --dir /home/opencode/path --model nvidia/nvidia/nemotron-3-super-120b-a12b \
           --prompt-file task.md [--title "…"] [--timeout 3600]
Creates a session in <dir>, posts the prompt, waits for the assistant turn, prints the final text and the
session id (resume with --session <id> --prompt-file followup.md). Password from ~/.secrets/opencode-server.env.
"""
from __future__ import annotations
import argparse, os, re, sys, time
from pathlib import Path
import httpx

ap = argparse.ArgumentParser()
ap.add_argument("--dir", required=True); ap.add_argument("--model", default="nvidia/nvidia/nemotron-3-super-120b-a12b")
ap.add_argument("--prompt-file", required=True); ap.add_argument("--title", default="delegated task")
ap.add_argument("--session"); ap.add_argument("--timeout", type=int, default=3600); ap.add_argument("--url", default="http://100.91.190.107:4096")
a = ap.parse_args()
pw = next((m.group(1) for line in (Path.home() / ".secrets/opencode-server.env").read_text().splitlines() if (m := re.match(r"^\s*OPENCODE_SERVER_PASSWORD\s*=\s*(.+?)\s*$", line))), None)
if not pw: sys.exit("no OPENCODE_SERVER_PASSWORD in ~/.secrets/opencode-server.env")
provider, model = a.model.split("/", 1)
c = httpx.Client(base_url=a.url, auth=("opencode", pw), timeout=httpx.Timeout(a.timeout, connect=30), params={"directory": a.dir})
sid = a.session
if not sid:
    sid = c.post("/session", json={"title": a.title}).json()["id"]
print(f"session {sid} dir={a.dir} model={a.model}", file=sys.stderr)
t0 = time.time()
r = c.post(f"/session/{sid}/message", json={"model": {"providerID": provider, "modelID": model},
                                            "parts": [{"type": "text", "text": Path(a.prompt_file).read_text(encoding="utf-8")}]})
r.raise_for_status()
msg = r.json()
text = "\n".join(p.get("text", "") for p in msg.get("parts", []) if p.get("type") == "text")
tools = [p.get("tool") for p in msg.get("parts", []) if p.get("type") == "tool"]
if not text.strip():  # the POST body is not always the final assistant turn — fetch the transcript and take the last one
    msgs = c.get(f"/session/{sid}/message").json()
    for m in reversed(msgs):
        if m.get("info", {}).get("role") == "assistant":
            t = "\n".join(p.get("text", "") for p in m.get("parts", []) if p.get("type") == "text")
            if t.strip():
                text, msg = t, m
                break
print(text)
print(f"\n--- session={sid} elapsed={time.time()-t0:.0f}s tool_calls={len(tools)} tokens={msg.get('info',{}).get('tokens')}", file=sys.stderr)
