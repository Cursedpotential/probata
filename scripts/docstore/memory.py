"""memory - recall agent session memory (memsearch) as a compact DuckDB table.

Byline: Claude Code - Opus 5 - 2026-09-10

Owner order 2026-09-10: "/memory" pulls it up, results compact, no noise. Backs the docstore plugin
/memory command. memsearch is the live agent-memory backend (Zilliz); its raw chunks carry session
comment tags and tool-call dumps, which are stripped here before anything is printed.

Usage:
  python scripts/docstore/memory.py "why did the docstore move to the cloud"
  python scripts/docstore/memory.py "tailscale serve" --k 8 --json
"""
from __future__ import annotations

import argparse
import json
import pathlib
import re
import subprocess
import sys
import types

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import sq  # noqa: E402


def clean(text: str) -> str:
    text = re.sub(r"<!--.*?-->", " ", text, flags=re.S)
    text = re.sub(r"\[Tool:[^\]]*\]", " ", text)
    text = re.sub(r"^#{1,6} +\d{1,2}:\d{2} *$", " ", text, flags=re.M)
    return " ".join(text.split())


def search(query: str, k: int) -> list[dict]:
    p = subprocess.run(["memsearch", "search", query, "-k", str(k), "-j"], capture_output=True, text=True,
                       encoding="utf-8", errors="replace", timeout=180)
    if p.returncode != 0:
        raise SystemExit(f"memsearch failed: {(p.stderr or p.stdout).strip().splitlines()[-1:]}")
    out = []
    for i, it in enumerate(json.loads(p.stdout), 1):
        src = pathlib.PureWindowsPath(it.get("source", "")).name or it.get("source", "")
        out.append({"rank": i, "score": round(float(it.get("score", 0)), 3), "date": src.removesuffix(".md"),
                    "heading": " ".join(str(it.get("heading", "")).split()), "text": clean(str(it.get("content", ""))),
                    "source": it.get("source"), "lines": f"{it.get('start_line')}-{it.get('end_line')}"})
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description="Recall agent session memory (memsearch).")
    ap.add_argument("query", nargs="+")
    ap.add_argument("--k", type=int, default=6)
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()
    rows = search(" ".join(a.query), a.k)
    if a.json:
        print(json.dumps(rows, ensure_ascii=False))
        return 0
    clip = lambda s, n: s if len(s) <= n else s[: n - 1] + "…"
    view = types.SimpleNamespace(sql=None, width=400, cell=120, max_rows=a.k, show_hidden=False)
    sq.render([{"#": r["rank"], "score": r["score"], "date": r["date"], "heading": clip(r["heading"], 30),
                "memory": clip(r["text"], 110)} for r in rows], view)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
