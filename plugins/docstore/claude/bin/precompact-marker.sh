#!/usr/bin/env bash
# PreCompact: cannot inject context into the compacted session — emitting
# hookSpecificOutput.additionalContext from PreCompact fails schema
# validation and discards the hook's ENTIRE output (verified live,
# 2026-07-31; additionalContext is only accepted from UserPromptSubmit,
# PostToolUse, PostToolBatch, Stop, SubagentStop, SessionStart). PreCompact
# may only return top-level fields (continue, suppressOutput, systemMessage).
# So the durable half of this hook is the marker file: the next SessionStart
# (source="compact") reads it in bin/preflight.sh and surfaces the handoff
# reminder there, inside its 3-line budget. The systemMessage below is a
# best-effort belt-and-suspenders for the *current* transcript only — it
# does not survive into the post-compact session.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/_pybin.sh"
PY="$(pybin)"

INPUT="$(cat 2>/dev/null || true)"
SESSION_ID="$(printf '%s' "$INPUT" | "$PY" -c "import sys,json
try:
    d = json.load(sys.stdin)
except Exception:
    d = {}
print(d.get('session_id','nosession'))" 2>/dev/null || echo "nosession")"

STATE_DIR="${CLAUDE_PLUGIN_ROOT}/.state"
mkdir -p "$STATE_DIR" 2>/dev/null || true
printf '%s' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$STATE_DIR/precompact_${SESSION_ID}.marker" 2>/dev/null || true

echo '{"systemMessage":"[docstore] Compaction is about to discard this context. Run the handoff skill now (fn::handoff_write) before it does."}'
exit 0
