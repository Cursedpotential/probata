#!/usr/bin/env bash
# UserPromptSubmit: remind the model to search the store before reading
# files or answering from its own knowledge. Suppressed when the immediately
# prior tool call already was a docs/memory MCP call (tracked by
# bin/track-tool-use.sh into .state/last_search_<session_id>.flag) so the
# reminder doesn't repeat on every turn of an already-compliant session.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/_pybin.sh"
PY="$(pybin)"

INPUT="$(cat 2>/dev/null || true)"
SESSION_ID="$(printf '%s' "$INPUT" | "$PY" -c "import sys,json; d=json.load(sys.stdin); print(d.get('session_id','nosession'))" 2>/dev/null || echo "nosession")"

STATE_DIR="${CLAUDE_PLUGIN_ROOT}/.state"
FLAG="$STATE_DIR/last_search_${SESSION_ID}.flag"

if [ -f "$FLAG" ] && [ "$(cat "$FLAG" 2>/dev/null)" = "1" ]; then
  exit 0
fi

echo "[docstore] Before answering about docs, decisions, todos or handoffs:"
echo "call the docs or memory MCP server's run tool with an fn:: function first."
echo "A superseded/stale hit is not an answer; an empty result is a finding."
exit 0
