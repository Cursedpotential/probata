#!/usr/bin/env bash
# Mirror the owner's local Claude/OpenCode skills, local plugin marketplace, memories and ~/.ssh into
# the devbox's persistent home on ovh-files (owner orders 2026-09-07 16:22-16:59: "mirror our local
# skills out there", "sync the ssh keys also", "need to sync memories", memsearch on both boxes).
# Runs from the Windows desktop (Git Bash) over tailnet SSH. No rsync on this box, so each mapping is a
# tar-over-ssh pipe with the junk-scrub excludes. DRY RUN by default (counts + sizes only); pass --go
# to transfer. --opencode-server also seeds the headless OpenCode server's home; --transcripts adds
# the large session-transcript tree. Byline: Claude Code · Fable 5.1 · 2026-09-07
set -euo pipefail
HOST="${DEVBOX_HOST:-root@100.91.190.107}"
KEY="${DEVBOX_SSH_KEY:-$HOME/.ssh/ovh}"
DEST="${DEVBOX_HOME:-/data/probata/volumes/devbox/home}"
GO=0; OCS=0; TR=0
for a in "$@"; do case "$a" in --go) GO=1;; --opencode-server) OCS=1;; --transcripts) TR=1;; esac; done
# junk scrub (owner rule): never ship node_modules/.git/__pycache__/venvs/tmp/holding areas
EXCL=(--exclude=node_modules --exclude=.git --exclude=__pycache__ --exclude=.venv --exclude=venv
      --exclude='*.duckdb' --exclude=_stale --exclude=_quarantine --exclude=tmp --exclude='.review_h*')
PAIRS=(
  "$HOME/.claude/skills/|$DEST/.claude/skills/"
  "$HOME/.agents/skills/|$DEST/.agents/skills/"
  "$HOME/.claude/local-plugins/|$DEST/.claude/local-plugins/"
  "$HOME/.claude/CLAUDE.md|$DEST/.claude/CLAUDE.md"
  "$HOME/.claude/rules/|$DEST/.claude/rules/"
  "$HOME/.config/opencode/|$DEST/.config/opencode/"
  "$HOME/.ssh/|$DEST/.ssh/"                      # owner 16:24: "sync the ssh keys also" — dir 0700, files 0600
  # auto-memory -> the devbox's project slug (Claude Code keys memory by cwd: /home/kasm-user/work/probata)
  "$HOME/.claude/projects/E--AI-Workspace-Projects-the-platform-workspace-probata/memory/|$DEST/.claude/projects/-home-kasm-user-work-probata/memory/"
  "/e/AI_Workspace/Projects/the-platform-workspace/probata/.remember/|$DEST/work/probata/.remember/"
  # memsearch (owner 16:59): plugin + marketplace registration so both boxes use the SAME Zilliz collection
  "$HOME/.claude/plugins/marketplaces/memsearch-plugins/|$DEST/.claude/plugins/marketplaces/memsearch-plugins/"
  "$HOME/.claude/plugins/cache/memsearch-plugins/|$DEST/.claude/plugins/cache/memsearch-plugins/"
  "$HOME/.claude/plugins/known_marketplaces.json|$DEST/.claude/plugins/known_marketplaces.json"
  "$HOME/.claude/plugins/installed_plugins.json|$DEST/.claude/plugins/installed_plugins.json"
  "$HOME/.claude/settings.json|$DEST/.claude/settings.desktop-reference.json"   # Windows paths inside; port by hand
  # OpenCode state beyond opencode.json (owner 21:31: "a couple of different auth.json files are needed"):
  # ~/.local/share/opencode holds auth.json (provider keys), mcp-auth.json (MCP OAuth), account.json;
  # ~/.opencode holds agents/commands/prompts/skills/plugin/tools. auth.json is NOT overwritten here —
  # scripts/opencode_server_seed_providers.sh writes the merged one (desktop keys + ~/.secrets keys).
  "$HOME/.local/share/opencode/mcp-auth.json|$DEST/.local/share/opencode/mcp-auth.json"
  "$HOME/.local/share/opencode/account.json|$DEST/.local/share/opencode/account.json"
  "$HOME/.opencode/|$DEST/.opencode/"
  # memsearch config + profile (owner 2026-09-08 "both systems"); digests are per-box, the Zilliz collection is shared
  "$HOME/.memsearch/config.toml|$DEST/.memsearch/config.toml"
  "$HOME/.memsearch/PROJECT.md|$DEST/.memsearch/PROJECT.md"
  "$HOME/.memsearch/USER.md|$DEST/.memsearch/USER.md"
)
if (( TR )); then PAIRS+=("$HOME/.claude/projects/|$DEST/.claude/projects-desktop-mirror/"); fi
if (( OCS )); then
  OC="/data/probata/volumes/opencode/home"
  PAIRS+=("$HOME/.config/opencode/|$OC/.config/opencode/"
          "$HOME/.agents/skills/|$OC/.agents/skills/"
          "$HOME/.claude/skills/|$OC/.claude/skills/"
          "$HOME/.claude/local-plugins/|$OC/.claude/local-plugins/"
          "$HOME/.local/share/opencode/mcp-auth.json|$OC/.local/share/opencode/mcp-auth.json"
          "$HOME/.local/share/opencode/account.json|$OC/.local/share/opencode/account.json"
          "$HOME/.opencode/|$OC/.opencode/")
fi
SSH=(ssh -i "$KEY" -o BatchMode=yes "$HOST")
"${SSH[@]}" "install -d -o 1000 -g 1000 $DEST/.claude $DEST/.agents $DEST/.config $DEST/work ${OCS:+/data/probata/volumes/opencode/home/.config /data/probata/volumes/opencode/home/.agents /data/probata/volumes/opencode/home/.claude}" >/dev/null
total_files=0; total_bytes=0
for pair in "${PAIRS[@]}"; do
  src="${pair%%|*}"; dst="${pair#*|}"
  [[ -e "$src" ]] || { echo "skip (missing): $src"; continue; }
  if [[ -d "$src" ]]; then
    n=$(tar -C "$src" "${EXCL[@]}" -cf - . 2>/dev/null | tar -tf - 2>/dev/null | grep -vc '/$' || true)
    b=$(tar -C "$src" "${EXCL[@]}" -cf - . 2>/dev/null | wc -c)
  else
    n=1; b=$(stat -c %s "$src")
  fi
  total_files=$((total_files+n)); total_bytes=$((total_bytes+b))
  printf '%-7s %6s files %8.1f MB  %s -> %s\n' "$([[ $GO == 1 ]] && echo COPY || echo DRY)" "$n" "$(awk -v b="$b" "BEGIN{printf \"%.1f\", b/1048576}")" "$src" "$dst"
  (( GO )) || continue
  mode=""; [[ "$src" == "$HOME/.ssh/" ]] && mode="&& chmod 700 '$dst' && find '$dst' -type f -exec chmod 600 {} +"
  if [[ -d "$src" ]]; then
    tar -C "$src" "${EXCL[@]}" -czf - . | "${SSH[@]}" "mkdir -p '$dst' && tar -C '$dst' -xzf - && chown -R 1000:1000 '$dst' $mode"
  else
    "${SSH[@]}" "mkdir -p '$(dirname "$dst")'" && scp -q -i "$KEY" "$src" "$HOST:$dst" && "${SSH[@]}" "chown 1000:1000 '$dst'"
  fi
done
printf 'TOTAL %s files, %.1f MB  mode=%s\n' "$total_files" "$(awk -v b="$total_bytes" "BEGIN{printf \"%.1f\", b/1048576}")" "$([[ $GO == 1 ]] && echo TRANSFERRED || echo DRY-RUN)"
echo "inside the devbox afterwards: claude plugin marketplace add ~/.claude/local-plugins && claude plugin install family-court-toolkit@casebible-local"
