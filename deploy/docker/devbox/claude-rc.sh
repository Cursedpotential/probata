#!/usr/bin/env bash
# Start Claude Code in the devbox with Remote Control so the session is visible/controllable from the
# owner's other devices (owner 2026-09-08 10:40: "make sure to set up /rc so we can see it work here").
# Byline: Claude Code · Fable 5.1 · 2026-09-08
# Byline: Claude Code · Sonnet 5 · 2026-09-08 (whole-home mapped volume — owner decisions 11:41-11:44:
# /home/kasm-user IS the persistent volume now; dated correction of the paths below, which referenced
# the retired ~/persist bind + symlink indirection).
#
# One-time on the DESKTOP:  claude setup-token   -> paste the token into ~/.secrets/claude-oauth.env as
#                           CLAUDE_CODE_OAUTH_TOKEN=...   (the devbox never generates or stores it anywhere else)
# Then in a Kasm terminal:   claude-rc            (this script; it is on PATH via /usr/local/bin)
set -euo pipefail
ENVF="$HOME/.secrets/claude-oauth.env"
if [[ -f "$ENVF" ]]; then
  export CLAUDE_CODE_OAUTH_TOKEN="$(sed -n 's/^CLAUDE_CODE_OAUTH_TOKEN=//p' "$ENVF" | tail -1 | tr -d '\r')"
fi
[[ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]] || echo "no token in $ENVF — claude will prompt for browser login instead" >&2
cd "${1:-$HOME/work/probata}" 2>/dev/null || cd "$HOME/work"
# register the local plugin marketplace once (idempotent), then start with remote control enabled
claude plugin marketplace add "$HOME/.claude/local-plugins" >/dev/null 2>&1 || true
exec claude --remote-control "${@:2}"
