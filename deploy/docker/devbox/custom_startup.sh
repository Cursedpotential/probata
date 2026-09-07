#!/usr/bin/env bash
# Kasm custom startup hook (copied to /dockerstartup/custom_startup.sh by the Dockerfile).
# Starts the backup-access and file-link daemons beside the Kasm desktop session.
# Byline: Claude Code · Fable 5.1 · 2026-09-07 (owner 16:22-16:23: file link + backup access)
set -u
# xrdp needs its two daemons; sudo is passwordless for kasm-user in this sandbox image
sudo /usr/sbin/xrdp-sesman >/dev/null 2>&1 &
sudo /usr/sbin/xrdp --nodaemon >/dev/null 2>&1 &
# Syncthing: GUI on 0.0.0.0:8384 (published on the tailnet IP only), data under the persistent home
mkdir -p "$HOME/work/sync"
nohup syncthing serve --no-browser --gui-address=0.0.0.0:8384 --home="$HOME/.config/syncthing" >"$HOME/.config/syncthing.log" 2>&1 &
exit 0
