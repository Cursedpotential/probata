#!/usr/bin/env bash
# Kasm custom startup hook (copied to /dockerstartup/custom_startup.sh by the Dockerfile).
# Starts the backup-access (xrdp) and file-link (Syncthing) daemons beside the desktop session,
# plus memsearch indexing and the OpenList (rclone WebDAV) mount at ~/files.
# Byline: Claude Code · Sonnet 5 · 2026-09-08 (whole-home mapped volume — owner decisions
# 2026-09-08 11:41-11:44: /home/kasm-user IS the persistent volume now, no more ~/persist
# bind + symlink indirection. All state paths below are real directories in the volume.)
# Byline: Claude Code · Sonnet 5 · 2026-09-08 (devbox v2: glances web dashboard + ollama serve
# added, both tailnet-only via the sidecar; plan "rosy-wibbling-cosmos", owner-approved 12:10 EDT).
set -u
mkdir -p "$HOME/work/sync" "$HOME/.claude" "$HOME/.agents" "$HOME/.ssh" "$HOME/.config/opencode" \
         "$HOME/.config/syncthing" "$HOME/.local/share" "$HOME/.memsearch/memory"
chmod 700 "$HOME/.ssh" 2>/dev/null || true
# memsearch (owner 2026-09-08 "both systems"): persistent config + digests, and a 30-min indexer into the shared
# Zilliz collection — same cadence as the desktop's `memsearch-index` scheduled task
if command -v memsearch >/dev/null 2>&1; then
  ( while true; do memsearch index "$HOME/.memsearch/memory" >>"$HOME/.memsearch/index.log" 2>&1; sleep 1800; done ) &
fi
# OpenList (R2/B2/VPS volumes/desktop share) mounted as a filesystem at ~/files via rclone WebDAV (owner 2026-09-08)
if command -v rclone >/dev/null 2>&1 && [[ -n "${OPENLIST_PASS:-}" ]]; then
  mkdir -p "$HOME/files" "$HOME/.config/rclone"
  OBS=$(rclone obscure "$OPENLIST_PASS")
  printf '[openlist]\ntype = webdav\nurl = %s/dav\nvendor = other\nuser = %s\npass = %s\n' "$OPENLIST_URL" "$OPENLIST_USER" "$OBS" > "$HOME/.config/rclone/rclone.conf"
  chmod 600 "$HOME/.config/rclone/rclone.conf"
  nohup rclone mount openlist: "$HOME/files" --vfs-cache-mode writes --dir-cache-time 30s --allow-non-empty >"$HOME/.config/rclone-mount.log" 2>&1 &
fi
# xrdp needs its two daemons; sudo is passwordless for kasm-user in this sandbox image (container also runs as root now)
sudo /usr/sbin/xrdp-sesman >/dev/null 2>&1 &
sudo /usr/sbin/xrdp --nodaemon >/dev/null 2>&1 &
# Monitoring dashboard (owner 11:52 "dashboard monitor"): glances web UI on :61208, tailnet-only
# through the sidecar/BIND_IP publish in devbox.yaml, not the public internet.
if command -v glances >/dev/null 2>&1; then
  nohup glances -w --bind 0.0.0.0 -p 61208 >"$HOME/.config/glances.log" 2>&1 &
fi
# ollama (CPU-only, no models baked — owner addition): loopback-only, not published on any port
if command -v ollama >/dev/null 2>&1; then
  OLLAMA_HOST=127.0.0.1:11434 nohup ollama serve >"$HOME/.config/ollama.log" 2>&1 &
fi
# (OpenCode's headless server is its own container — deploy/opencode-server.yaml, owner 17:24 — not run here.)
# Syncthing: GUI on 0.0.0.0:8384 (published on the tailnet IP only), config under the persistent home
nohup syncthing serve --no-browser --gui-address=0.0.0.0:8384 --home="$HOME/.config/syncthing" >"$HOME/.config/syncthing.log" 2>&1 &
exit 0
