#!/usr/bin/env bash
# PostToolUse (matcher "Write|Edit"): if a markdown file under the docs root
# changed, remind the model the file is unregistered until docs_register /
# docs_new_version runs. One line, silent otherwise.
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

DOCS_ROOT="${DOCSTORE_DOCS_ROOT:-docs}"
case "$FILE" in
  *"/${DOCS_ROOT}/"*.md|*"/${DOCS_ROOT}/"*.mdx|"${DOCS_ROOT}/"*.md|"${DOCS_ROOT}/"*.mdx)
    echo "[docstore] $FILE changed and is unregistered until fn::docs_register or fn::docs_new_version runs (skill: docs-write)."
    ;;
esac
exit 0
