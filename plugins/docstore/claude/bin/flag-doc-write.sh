#!/usr/bin/env bash
# PostToolUse (matcher "Write|Edit"): if a markdown file under the docs root
# changed, remind the model the CocoIndex pipeline (not a hand fn::docs_register
# / fn::docs_new_version call) picks it up on its next run. One line, silent
# otherwise. Corrected 2026-09-16: the old wording ("unregistered until
# docs_register or docs_new_version runs") read as an instruction to
# hand-register a pipeline-owned file, which collides on the UNIQUE
# content_hash index and fails the run -- see the docstore/docs-write skills.
# 2026-09-16 (Claude Code · Fable 5.1): bounded stdin read — `$(cat)` left orphaned hook shells alive for minutes per tool call.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/_pybin.sh"
PY="$(pybin)"

INPUT="$(timeout 5 cat 2>/dev/null || true)"
FILE="$(printf '%s' "$INPUT" | "$PY" -c "
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    d = {}
print((d.get('tool_input') or {}).get('file_path', ''))
" 2>/dev/null)"

[ -z "$FILE" ] && exit 0

DOCS_ROOT="${DOCSTORE_DOCS_ROOT:-docs}"
case "$FILE" in
  *"/${DOCS_ROOT}/"*.md|*"/${DOCS_ROOT}/"*.mdx|"${DOCS_ROOT}/"*.md|"${DOCS_ROOT}/"*.mdx)
    echo "[docstore] $FILE changed; the CocoIndex pipeline indexes it on its next run (docstore_index_full / docstore_health). Do NOT hand-call fn::docs_register/fn::docs_new_version on a registry-root file -- see the docstore skill's routing table."
    ;;
esac
exit 0
