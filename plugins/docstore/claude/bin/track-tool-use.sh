#!/usr/bin/env bash
# PostToolUse (matcher "*"): silent bookkeeping only — never prints on
# success. Records whether the just-completed tool call was a docs/memory
# MCP call, so the next UserPromptSubmit read-gate can suppress its
# reminder when the model already searched the store. State is keyed by
# session_id so parallel sessions never clobber each other.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/_pybin.sh"
PY="$(pybin)"

INPUT="$(cat 2>/dev/null || true)"
PARSED="$(printf '%s' "$INPUT" | "$PY" -c "
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    d = {}
print(d.get('session_id', 'nosession'))
print(d.get('tool_name', ''))
" 2>/dev/null)"
SESSION_ID="$(printf '%s\n' "$PARSED" | sed -n '1p')"
TOOL_NAME="$(printf '%s\n' "$PARSED" | sed -n '2p')"

STATE_DIR="${CLAUDE_PLUGIN_ROOT}/.state"
mkdir -p "$STATE_DIR" 2>/dev/null || true
FLAG="$STATE_DIR/last_search_${SESSION_ID:-nosession}.flag"

# The plugin's real tool prefix is mcp__plugin_propria-docstore_<server>__ with
# a HYPHEN in the plugin name (verified live 2026-09-16 by calling the tools).
# This matcher only listed the underscore spelling, so it never matched a single
# docstore tool call and the search-tracking flag was always written as 0. The
# legacy/underscore patterns are kept so an older install still matches.
case "$TOOL_NAME" in
  mcp__plugin_propria-docstore_control__*|mcp__plugin_propria-docstore_docs__*|mcp__plugin_propria-docstore_memory__*|mcp__plugin_propria_docstore_control__*|mcp__plugin_propria_docstore_docs__*|mcp__plugin_propria_docstore_memory__*|mcp__docs__*|mcp__memory__*)
    printf '1' > "$FLAG" 2>/dev/null || true
    ;;
  *)
    printf '0' > "$FLAG" 2>/dev/null || true
    ;;
esac
exit 0
