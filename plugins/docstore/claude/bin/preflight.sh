#!/usr/bin/env bash
# SessionStart: verify BOTH SurrealDB stores (docs = cloud surreal-docs since 2026-09-10, memory VPS) are
# reachable before the session trusts either one. Prints <=3 lines. Loud
# failure, no silent filesystem/invented-memory fallback — that fallback is
# exactly the drift loop this plugin exists to break (design doc S2/S3).
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/_pybin.sh"
PY="$(pybin)"

DOCS_URL="${DOCSTORE_DOCS_URL:-https://surreal-docs.tilapia-skilift.ts.net}"
MEM_URL="${MEMORY_MCP_URL:-http://100.91.190.107:8471/mcp}"
MEM_URL="${MEM_URL%/mcp}"

INPUT="$(cat 2>/dev/null || true)"

docs_state="down"
mem_state="down"

docs_code="$(curl -s --max-time 5 -o /dev/null -w '%{http_code}' "${DOCS_URL%/}/health" 2>/dev/null || echo "000")"
case "$docs_code" in 2*) docs_state="up" ;; esac

mem_code="$(curl -s --max-time 5 -o /dev/null -w '%{http_code}' "${MEM_URL%/}/health" 2>/dev/null || echo "000")"
case "$mem_code" in 2*) mem_state="up" ;; esac

# Was this session resumed after a compaction? PreCompact cannot inject
# context (hookSpecificOutput.additionalContext is validated only for
# UserPromptSubmit/PostToolUse/PostToolBatch/Stop/SubagentStop/SessionStart —
# emitting it from PreCompact fails validation and drops the WHOLE hook
# output). So PreCompact only writes a marker file; this hook is the one
# that reads it back and surfaces the reminder, inside the 3-line budget.
SESSION_ID="$(printf '%s' "$INPUT" | "$PY" -c "import sys,json; d=json.load(sys.stdin); print(d.get('session_id','nosession'))" 2>/dev/null || echo "nosession")"
STATE_DIR="${CLAUDE_PLUGIN_ROOT}/.state"
mkdir -p "$STATE_DIR" 2>/dev/null || true
MARKER="$STATE_DIR/precompact_${SESSION_ID}.marker"

if [ "$docs_state" != "up" ] || [ "$mem_state" != "up" ]; then
  echo "DOCSTORE PREFLIGHT FAILED: docs=$docs_state memory=$mem_state — NO fallback to docs/ or invented memory."
  echo "Do not read the filesystem or answer from memory of the subject. Tell the user the store is down and stop."
  exit 0
fi

if [ -f "$MARKER" ]; then
  rm -f "$MARKER" 2>/dev/null || true
  echo "docstore: docs=up memory=up | skills: query docs docs-write decisions todo handoff memory reconcile | commands: /recall-doc /recall-adr /memory /update-adr"
  echo "resumed after compaction — run the handoff skill now to recover the pre-compact handoff record"
else
  echo "docstore: docs=up memory=up | skills: query docs docs-write decisions todo handoff memory reconcile | commands: /recall-doc /recall-adr /memory /update-adr"
  echo "search before you read: fn::docs_search / fn::recall via mcp__plugin_docstore_<server>__run; inspect rows with scripts/docstore/sq.py (DuckDB table)"
fi
exit 0
