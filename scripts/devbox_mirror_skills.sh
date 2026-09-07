#!/usr/bin/env bash
# Mirror the owner's local Claude/OpenCode skills + local plugin marketplace into the devbox's
# persistent home on ovh-files (owner order 2026-09-07 16:22: "mirror our local skills out there").
# Runs from the Windows desktop (Git Bash) over tailnet SSH; rsync with the junk-scrub filter.
# DRY RUN by default — pass --go to transfer. Byline: Claude Code · Fable 5.1 · 2026-09-07
set -euo pipefail
HOST="${DEVBOX_HOST:-root@100.91.190.107}"
KEY="${DEVBOX_SSH_KEY:-$HOME/.ssh/ovh}"
DEST="${DEVBOX_HOME:-/data/probata/volumes/devbox/home}"
MODE="--dry-run"; [[ "${1:-}" == "--go" ]] && MODE=""
# junk scrub (owner rule): never ship node_modules/.git/__pycache__/venvs/tmp/holding areas
EXCL=(--exclude node_modules --exclude .git --exclude __pycache__ --exclude .venv --exclude venv
      --exclude '*.duckdb' --exclude '_stale' --exclude '_quarantine' --exclude 'tmp' --exclude '.review_h*')
declare -A MAP=(
  ["$HOME/.claude/skills/"]="$DEST/.claude/skills/"
  ["$HOME/.agents/skills/"]="$DEST/.agents/skills/"
  ["$HOME/.claude/local-plugins/"]="$DEST/.claude/local-plugins/"
  ["$HOME/.claude/CLAUDE.md"]="$DEST/.claude/CLAUDE.md"
  ["$HOME/.claude/rules/"]="$DEST/.claude/rules/"
  ["$HOME/.config/opencode/"]="$DEST/.config/opencode/"
  ["$HOME/.ssh/"]="$DEST/.ssh/"                      # owner 16:24: "sync the ssh keys also" — private keys land 0600, dir 0700
  # owner 16:55: "need to sync memories somehow" — canonical auto-memory store -> the devbox's project slug
  # (Claude Code keys auto-memory by cwd: /home/kasm-user/work/probata -> -home-kasm-user-work-probata).
  # One-way seed here; continuous two-way sync is the Syncthing folder pair set up after first boot.
  ["$HOME/.claude/projects/E--AI-Workspace-Projects-the-platform-workspace-probata/memory/"]="$DEST/.claude/projects/-home-kasm-user-work-probata/memory/"
  ["/e/AI_Workspace/Projects/the-platform-workspace/probata/.remember/"]="$DEST/work/probata/.remember/"
  ["$HOME/.claude/plugins/memsearch/"]="$DEST/.claude/plugins/memsearch/"   # memsearch config; the index itself is Zilliz Cloud
)
# Session transcripts feed `recall` / read-memories; large, so opt-in: ./devbox_mirror_skills.sh --go --transcripts
if [[ " $* " == *" --transcripts "* ]]; then
  MAP["$HOME/.claude/projects/"]="$DEST/.claude/projects-desktop-mirror/"
fi
ssh -i "$KEY" "$HOST" "install -d -o 1000 -g 1000 $DEST/.claude $DEST/.agents $DEST/.config"
for src in "${!MAP[@]}"; do
  [[ -e "$src" ]] || { echo "skip (missing): $src"; continue; }
  echo "== $src -> $HOST:${MAP[$src]}"
  PERM=(); [[ "$src" == "$HOME/.ssh/" ]] && PERM=(--chmod=D700,F600)
  rsync -az $MODE --stats --chown=1000:1000 "${PERM[@]}" "${EXCL[@]}" -e "ssh -i $KEY" "$src" "$HOST:${MAP[$src]}" \
    | grep -E "Number of (regular )?files|Total transferred file size|Total file size" || true
done
echo "mode: ${MODE:-TRANSFER}"
echo "inside the devbox afterwards: claude plugin marketplace add ~/.claude/local-plugins && claude plugin install family-court-toolkit@casebible-local"
