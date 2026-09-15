#!/usr/bin/env bash
# PostToolUse (matcher "Write|Edit"): a markdown file under a Docstore registry root
# is indexed by the CocoIndex pipeline on its next run (owner 2026-09-14: never
# hand-register pipeline-owned files). Remind the model to TAG it: front matter
# `tags: [a, b]` or `<!-- tags: a, b -->` (owner 2026-09-14 21:06: tags required or
# at least recommended when submitting). Also warns on non-UTF-8 bytes (docs_lint.py
# ENC001: the flow decodes via a cp1252 fallback) and on an empty file after write
# (docs_lint.py EMPTY001: the flow silently SKIPS empty files -- it will not be
# indexed as written). A reminder only, never a block: always exits 0.
# Byline: Claude Code · Sonnet 5 · 2026-09-14 (was: tags-only reminder).
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

CHECKS="$("$PY" -c '
import re, sys
try:
    raw = open(sys.argv[1], "rb").read()
except Exception:
    print("skip|skip|skip"); sys.exit()
try:
    text = raw.decode("utf-8")
    enc = "ok"
except UnicodeDecodeError:
    text = raw.decode("cp1252", errors="replace")
    enc = "bad"
empty = "yes" if not text.strip() else "no"
fm = re.match(r"\A﻿?---\r?\n(.*?)\r?\n---", text, re.S)
tags_ok = bool(fm and re.search(r"(?m)^tags:", fm.group(1))) or bool(re.search(r"<!--\s*tags:", text, re.I))
print(enc + "|" + empty + "|" + ("yes" if tags_ok else "no"))
' "$FILE" 2>/dev/null)"

ENC="$(printf '%s' "$CHECKS" | cut -d'|' -f1)"
EMPTY="$(printf '%s' "$CHECKS" | cut -d'|' -f2)"
TAGS="$(printf '%s' "$CHECKS" | cut -d'|' -f3)"

[ "$ENC" = "skip" ] && exit 0

if [ "$ENC" = "bad" ]; then
  echo "[docstore] $FILE is not valid UTF-8 (docs_lint.py ENC001). The pipeline decodes it via a cp1252 fallback; re-save as UTF-8, or run 'python3 scripts/docstore/docs_lint.py --paths $FILE --fix-encoding' to rewrite it in place."
fi
if [ "$EMPTY" = "yes" ]; then
  echo "[docstore] $FILE is empty after strip (docs_lint.py EMPTY001). The CocoIndex flow SKIPS empty files -- this file will not be indexed as written."
fi
if [ "$TAGS" = "no" ]; then
  echo "[docstore] $FILE has NO tags. Add front matter 'tags: [topic, ...]' or '<!-- tags: topic, ... -->' so it surfaces via fn::docs_tagged. The CocoIndex pipeline indexes this file; do not hand-register it."
elif [ "$TAGS" = "yes" ]; then
  echo "[docstore] $FILE is pipeline-indexed on the next run (tags present; do not hand-register)."
fi
exit 0
