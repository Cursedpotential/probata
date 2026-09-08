#!/usr/bin/env bash
# Kasm custom startup hook (copied to /dockerstartup/custom_startup.sh by the Dockerfile).
# 1) wires persistent state (~/persist bind mount) into the home dir via symlinks
# 2) starts the backup-access (xrdp) and file-link (Syncthing) daemons beside the desktop session
# Byline: Claude Code · Fable 5.1 · 2026-09-07 (owner 16:22-16:23: file link + backup access)
set -u
P="$HOME/persist"
mkdir -p "$P/work/sync" "$P/.claude" "$P/.agents" "$P/.ssh" "$P/.config/opencode" "$P/.config/syncthing" "$P/.local/share"
chmod 700 "$P/.ssh" 2>/dev/null || true
link() { # link <home-relative path> <persist path>
  local dst="$HOME/$1" src="$2"
  mkdir -p "$(dirname "$dst")"
  if [[ -e "$dst" && ! -L "$dst" ]]; then
    # keep whatever the image shipped, but move it aside once so the persistent copy wins
    mv "$dst" "$dst.image-default" 2>/dev/null || true
  fi
  [[ -L "$dst" ]] || ln -s "$src" "$dst"
}
link work "$P/work"
link .claude "$P/.claude"
link .agents "$P/.agents"
link .ssh "$P/.ssh"
link .config/opencode "$P/.config/opencode"
link .config/syncthing "$P/.config/syncthing"
[[ -f "$P/.gitconfig" ]] && link .gitconfig "$P/.gitconfig"
# memsearch (owner 2026-09-08 "both systems"): persistent config + digests, and a 30-min indexer into the shared
# Zilliz collection — same cadence as the desktop's `memsearch-index` scheduled task
mkdir -p "$P/.memsearch/memory"; link .memsearch "$P/.memsearch"
if command -v memsearch >/dev/null 2>&1; then
  ( while true; do memsearch index "$HOME/.memsearch/memory" >>"$P/.memsearch/index.log" 2>&1; sleep 1800; done ) &
fi
# xrdp needs its two daemons; sudo is passwordless for kasm-user in this sandbox image
sudo /usr/sbin/xrdp-sesman >/dev/null 2>&1 &
sudo /usr/sbin/xrdp --nodaemon >/dev/null 2>&1 &
# (OpenCode's headless server is its own container — deploy/opencode-server.yaml, owner 17:24 — not run here.)
# Syncthing: GUI on 0.0.0.0:8384 (published on the tailnet IP only), config under the persistent tree
nohup syncthing serve --no-browser --gui-address=0.0.0.0:8384 --home="$P/.config/syncthing" >"$P/.config/syncthing.log" 2>&1 &
exit 0
