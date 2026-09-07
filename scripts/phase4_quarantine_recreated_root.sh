#!/usr/bin/env bash
# After the §4.4 host-root rename, Coolify re-creates EMPTY directories under /data/agno on every deploy
# (stale per-app storage rows still name the old root and old proffer names). This moves that empty tree to
# /data/.review_hold/agno-recreated-<stamp> so nothing is deleted and the old root stays absent.
# Refuses if any regular file exists under /data/agno (then it is not the empty re-creation and a human looks).
# Byline: Claude Code · Fable 5.1 · 2026-09-07
set -euo pipefail
OLD=/data/agno
[ -e "$OLD" ] || { echo "$(hostname): $OLD absent — nothing to quarantine"; exit 0; }
files=$(find "$OLD" -type f | wc -l); links=$(find "$OLD" -type l | wc -l)
if [ "$files" != "0" ] || [ "$links" != "0" ]; then echo "$(hostname): REFUSING — $OLD holds $files files / $links links; inspect by hand:"; find "$OLD" -type f -o -type l | head -20; exit 2; fi
stamp=$(date -u +%Y%m%dT%H%M%SZ); dest="/data/.review_hold/agno-recreated-$stamp"
mkdir -p /data/.review_hold
mv "$OLD" "$dest"
echo "$(hostname): moved empty tree $OLD -> $dest ($(find "$dest" -type d | wc -l) dirs)"
find "$dest" -type d | sed "s#$dest##" | grep . | sort | head -30
[ -e "$OLD" ] && echo "WARN: $OLD exists again" || echo "$OLD absent"
