#!/usr/bin/env bash
# Infra rename cutover plan §4.3 — final step: remove the old shared docker network `agno` from the box it runs on.
# Refuses while any container other than coolify-proxy is still attached (that container has not been redeployed
# onto `probata` yet). Detaches coolify-proxy itself, then removes the network. Idempotent.
# Byline: Claude Code · Fable 5.1 · 2026-09-07
set -euo pipefail
OLD=agno; NEW=probata
docker network inspect "$NEW" >/dev/null 2>&1 || { echo "$(hostname): REFUSING — $NEW network does not exist"; exit 2; }
docker inspect coolify-proxy -f '{{index .NetworkSettings.Networks "'"$NEW"'"}}' | grep -q . || { echo "$(hostname): REFUSING — coolify-proxy not on $NEW"; exit 3; }
if ! docker network inspect "$OLD" >/dev/null 2>&1; then echo "$(hostname): $OLD already gone"; exit 0; fi
members=$(docker network inspect "$OLD" -f '{{range .Containers}}{{.Name}} {{end}}')
others=$(for m in $members; do [ "$m" = coolify-proxy ] || printf '%s ' "$m"; done)
if [ -n "${others// /}" ]; then echo "$(hostname): REFUSING — still attached to $OLD: $others"; exit 4; fi
echo "$members" | grep -q coolify-proxy && docker network disconnect "$OLD" coolify-proxy && echo "$(hostname): coolify-proxy detached from $OLD"
docker network rm "$OLD" >/dev/null && echo "$(hostname): network $OLD removed"
docker network ls --format '{{.Name}}' | grep -E "^($OLD|$NEW)$" | sed "s/^/$(hostname): remaining: /"
