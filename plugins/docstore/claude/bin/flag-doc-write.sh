#!/usr/bin/env bash
# PostToolUse (matcher "Write|Edit"): a markdown file under a Docstore registry root
# is indexed by the CocoIndex pipeline on its next run (owner 2026-09-14: never
# hand-register pipeline-owned files). Remind the model to TAG it: front matter
# `tags: [a, b]` or `<!-- tags: a, b -->` (owner 2026-09-14 21:06: tags required or
# at least recommended when submitting). One line, silent otherwise.
# Byline: Claude Code · Fable 5.1 · 2026-09-14 (was: "unregistered until docs_register").
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/_pybin.sh"
PY="$(pybin)"

INPUT="$(cat 2>/dev/null || true)"
FILE="$(printf '%s' "$INPUT" | "$PY" -c "
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    d = {}
print((d.get('tool_input') or {}).get('file_path', ''))
" 2>/dev/null)"

[ -z "$FILE" ] && exit 0
case "$FILE" in
  *.md|*.mdx) ;;
  *) exit 0 ;;
esac
case "$FILE" in
  */docs/*|docs/*|*/AGENTS.md|*/AGENT_MEMORY.md|*/CLAUDE.md|*/README.md) ;;
  *) exit 0 ;;
esac

HAS_TAGS="$("$PY" -c '
import re, sys
try:
    t = open(sys.argv[1], encoding="utf-8", errors="replace").read()
except Exception:
    print("skip"); sys.exit()
fm = re.match(r"\A﻿?---\r?\n(.*?)\r?\n---", t, re.S)
ok = bool(fm and re.search(r"(?m)^tags:", fm.group(1))) or bool(re.search(r"<!--\s*tags:", t, re.I))
print("yes" if ok else "no")
' "$FILE" 2>/dev/null)"
if [ "$HAS_TAGS" = "no" ]; then
  echo "[docstore] $FILE has NO tags. Add front matter 'tags: [topic, ...]' or '<!-- tags: topic, ... -->' so it surfaces via fn::docs_tagged. The CocoIndex pipeline indexes this file; do not hand-register it."
elif [ "$HAS_TAGS" = "yes" ]; then
  echo "[docstore] $FILE is pipeline-indexed on the next run (tags present; do not hand-register)."
fi
exit 0
