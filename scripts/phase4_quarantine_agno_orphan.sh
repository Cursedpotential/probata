#!/usr/bin/env bash
# Infra rename §4.4 close-out: after every app is on /data/probata, the old /data/agno tree is orphaned
# (Coolify re-created empty stubs, plus stale bytes from containers that have since moved). This moves
# the whole tree to /data/.review_hold/ — never deletes. REFUSES if any RUNNING container still mounts
# a /data/agno path (that would mean an app was not migrated). Idempotent.
# Byline: Claude Code · Fable 5.1 · 2026-09-07
set -euo pipefail
OLD=/data/agno
[ -e "$OLD" ] || { echo "$(hostname): $OLD absent — nothing to do"; exit 0; }
live=""
for c in $(docker ps -q); do
  docker inspect "$c" -f '{{range .Mounts}}{{.Source}}{{"\n"}}{{end}}' 2>/dev/null | grep -q "^$OLD" && live="$live $(docker inspect "$c" -f '{{.Name}}')"
done
if [ -n "${live// /}" ]; then echo "$(hostname): REFUSING — running containers still mount $OLD:$live"; exit 2; fi
stamp=$(date -u +%Y%m%dT%H%M%SZ); dest="/data/.review_hold/agno-orphaned-$stamp"
mkdir -p /data/.review_hold
sz=$(du -sh "$OLD" 2>/dev/null | cut -f1)
mv "$OLD" "$dest"
echo "$(hostname): moved $OLD ($sz) -> $dest"
find "$dest" -maxdepth 3 -type f 2>/dev/null | head -20
[ -e "$OLD" ] && echo "$(hostname): WARN $OLD exists again" || echo "$(hostname): $OLD gone"
