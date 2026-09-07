#!/usr/bin/env bash
# Infra rename cutover plan §4.4 (docs/planning/2026-09-06-infra-rename-cutover-plan.md, 19:15 amendment: hard cut,
# no symlink, no dual paths). Renames the host data root /data/agno -> /data/probata on the box it runs on.
# Running containers keep their bind mounts (Linux binds by inode); every compose file in deploy/ already says
# /data/probata, so the next (re)deploy of each app mounts the same directories under the new name.
# Idempotent: exits 0 without touching anything if the rename already happened. Never deletes anything.
# Byline: Claude Code · Fable 5.1 · 2026-09-07
set -euo pipefail
OLD=/data/agno; NEW=/data/probata
if [ -d "$NEW" ] && [ ! -e "$OLD" ]; then echo "$(hostname): already renamed ($NEW present, $OLD absent)"; exit 0; fi
if [ ! -d "$OLD" ]; then echo "$(hostname): $OLD is not a directory — nothing to do"; exit 1; fi
if [ -e "$NEW" ]; then echo "$(hostname): REFUSING — $NEW already exists alongside $OLD"; ls -la "$NEW" | head; exit 2; fi
if findmnt -rn -o TARGET | grep -q "^$OLD"; then echo "$(hostname): REFUSING — a mount point lives under $OLD"; findmnt -rn -o TARGET | grep "^$OLD"; exit 3; fi
before=$(find "$OLD" -maxdepth 1 | wc -l)
mv "$OLD" "$NEW"
after=$(find "$NEW" -maxdepth 1 | wc -l)
echo "$(hostname): renamed $OLD -> $NEW (top-level entries $before -> $after)"
[ "$before" = "$after" ] || { echo "ENTRY COUNT MISMATCH"; exit 4; }
ls -d "$NEW"/volumes "$NEW"/secrets 2>/dev/null || true
[ -e "$OLD" ] && echo "WARN: $OLD reappeared (a container restart re-created it — quarantine it after the redeploy wave)" || echo "$OLD absent"
