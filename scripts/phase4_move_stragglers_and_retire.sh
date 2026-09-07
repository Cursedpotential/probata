#!/usr/bin/env bash
# Infra rename §4.3 tail: move the last containers off `agno` onto `probata` WITHOUT a rebuild,
# then remove the `agno` network. Two kinds of straggler:
#   - live apps whose source can't rebuild from this repo (llm-probe, llm-probe-ui live in the
#     gitignored modules/custom repo) -> connect probata, disconnect agno (keep the running container).
#   - orphaned one-off containers (e.g. temporalio/admin-tools jobs that never exited) -> just
#     disconnect from agno; the owner removes them later. Never stopped or deleted here.
# Idempotent and safe: only touches the `agno` and `probata` networks, never a volume or image.
# Byline: Claude Code · Fable 5.1 · 2026-09-07
set -euo pipefail
OLD=agno; NEW=probata
docker network inspect "$NEW" >/dev/null 2>&1 || { echo "$(hostname): REFUSING — $NEW missing"; exit 2; }
docker network inspect "$OLD" >/dev/null 2>&1 || { echo "$(hostname): $OLD already gone"; exit 0; }
members=$(docker network inspect "$OLD" -f '{{range .Containers}}{{.Name}} {{end}}')
for c in $members; do
  [ "$c" = coolify-proxy ] && continue
  img=$(docker inspect "$c" -f '{{.Config.Image}}' 2>/dev/null || echo "?")
  case "$img" in
    *admin-tools*)  # orphaned one-off job — just take it off the old net
      docker network disconnect "$OLD" "$c" 2>/dev/null && echo "$(hostname): disconnected orphan $c ($img) from $OLD (left running for owner)";;
    *)              # live app — put it on the new net, then off the old one (no rebuild)
      docker network inspect "$NEW" -f '{{range .Containers}}{{.Name}} {{end}}' | grep -qw "$c" || docker network connect "$NEW" "$c"
      docker network disconnect "$OLD" "$c" 2>/dev/null && echo "$(hostname): moved $c ($img) $OLD -> $NEW live";;
  esac
done
left=$(docker network inspect "$OLD" -f '{{range .Containers}}{{.Name}} {{end}}')
others=$(for m in $left; do [ "$m" = coolify-proxy ] || printf '%s ' "$m"; done)
[ -n "${others// /}" ] && { echo "$(hostname): STILL on $OLD, not removing: $others"; exit 3; }
echo "$left" | grep -qw coolify-proxy && docker network disconnect "$OLD" coolify-proxy && echo "$(hostname): coolify-proxy detached from $OLD"
docker network rm "$OLD" >/dev/null && echo "$(hostname): removed network $OLD"
docker network ls --format '{{.Name}}' | grep -qxE "$OLD" && echo "$(hostname): WARN $OLD still present" || echo "$(hostname): $OLD gone; $NEW remains"
