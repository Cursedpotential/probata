#!/usr/bin/env bash
# PHASE 2 — stand up data-neo4j, data-vector (milvus+attu), and nocodb on
# ovh-files: push the phase1b tarballs, restore the volumes, create (or
# reuse) a Coolify app pointed at ovh-files for each, start, and probe
# liveness. Mirrors the deploy/data-graphiti-case.yaml precedent (S10 path, 2026-08-10) (own
# Coolify app per store on ovh-files, same repo/compose file, tailnet-only
# ports) — see that file's header for the pattern this follows.
#
# Byline: Claude Code · Sonnet (agent) · 2026-08-01
#
# Does NOT touch DNS/env of any application that currently points at
# ovh-data — that cutover belongs to the main session. This script only
# stands the stores up on ovh-files and proves they're alive.
#
# Requires COOLIFY_API_TOKEN exported (see migration_lib.sh header). Run
# LOCALLY (dev box with tailnet + Coolify API + ~/.ssh/ovh access).
#
# Usage:
#   STAGE_LOCAL=<phase1b staging dir> MILVUS_CONFIG_SRC=<dir with
#   embedEtcd.yaml/user.yaml> ./scripts/phase2_standup.sh [app-name ...]
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./migration_lib.sh
source "$HERE/migration_lib.sh"

SSH_KEY="${SSH_KEY:-$HOME/.ssh/ovh}"
OVHFILES_HOST="root@100.91.190.107"
OVHDATA_UUID_NEO4J=jfvnf0i45mmccxonv1p570au
SSH=(ssh -i "$SSH_KEY" -o ConnectTimeout=15)
SCP=(scp -i "$SSH_KEY")
STAGE_LOCAL="${STAGE_LOCAL:?set STAGE_LOCAL to the phase1b staging dir}"
MILVUS_CONFIG_SRC="${MILVUS_CONFIG_SRC:?set MILVUS_CONFIG_SRC to the dir with embedEtcd.yaml/user.yaml from phase1a}"

PROJECT_UUID=nbg0ocqqrf91xag492yjqf5i
ENV_NAME=production
GITHUB_APP_UUID=r4mhpblr8cnxk3481r07xxz0
GIT_REPO=Cursedpotential/probata
SERVER_UUID=cn89l8801u8gsginw1rxq5qt   # ovh-files

declare -A APP_TARBALL=([data-neo4j]=data-neo4j [data-vector]=data-vector [nocodb]=nocodb)
declare -A APP_COMPOSE=(
  [data-neo4j]=/deploy/data-neo4j.yaml
  [data-vector]=/deploy/data-vector.yaml
  [nocodb]=/deploy/nocodb.yaml
)
declare -A APP_BRANCH=([data-neo4j]=main [data-vector]=main [nocodb]=infra/nocodb)
declare -A APP_HEALTHCHECK=(
  [data-neo4j]="http://100.91.190.107:7474"
  [data-vector]="http://100.91.190.107:9091/healthz"
  [nocodb]="http://100.91.190.107:8570/api/v1/health"
)

APPS=("$@")
[ "${#APPS[@]}" -eq 0 ] && APPS=(data-neo4j data-vector nocodb)

: > "$STAGE_LOCAL/phase2_app_uuids.txt" 2>/dev/null || true

for app in "${APPS[@]}"; do
  echo "==================== $app ===================="
  tb="$STAGE_LOCAL/${APP_TARBALL[$app]}.tar.gz"
  sha="$STAGE_LOCAL/${APP_TARBALL[$app]}.tar.gz.sha256"
  [ -f "$tb" ] || { echo "missing tarball: $tb (run phase1b_coldcopy.sh first)" >&2; exit 1; }
  expected=$(awk '{print $1}' "$sha")

  echo "-- pushing tarball + restore script to ovh-files --"
  "${SCP[@]}" "$tb" "$OVHFILES_HOST:/root/${app}.tar.gz"
  "${SCP[@]}" "$HERE/restore_volume.sh" "$OVHFILES_HOST:/root/restore_volume.sh"
  "${SSH[@]}" "$OVHFILES_HOST" "bash /root/restore_volume.sh /root/${app}.tar.gz $expected"

  if [ "$app" = "data-vector" ]; then
    echo "-- carrying Milvus config (embedEtcd.yaml, user.yaml — the boot-race fix) --"
    "${SSH[@]}" "$OVHFILES_HOST" "mkdir -p /data/probata/config/milvus"
    "${SCP[@]}" "$MILVUS_CONFIG_SRC/embedEtcd.yaml" "$OVHFILES_HOST:/data/probata/config/milvus/embedEtcd.yaml"
    "${SCP[@]}" "$MILVUS_CONFIG_SRC/user.yaml" "$OVHFILES_HOST:/data/probata/config/milvus/user.yaml"
  fi

  echo "-- checking for an existing Coolify app named $app on ovh-files --"
  existing=$(curl -s -H "$(_cf_auth_header)" "$COOLIFY_API/applications" \
    | python3 -c "
import json, sys
data = json.load(sys.stdin)
for a in data:
    if a.get('name') == '$app':
        dest = a.get('destination') or {}
        srv = (dest.get('server') or {}).get('name')
        print(a['uuid'], srv)
")
  uuid=""
  if [ -n "$existing" ]; then
    while read -r u srv; do
      [ "$srv" = "ovh-files" ] && uuid="$u"
    done <<< "$existing"
  fi

  if [ -z "$uuid" ]; then
    echo "-- creating Coolify app $app on ovh-files --"
    resp=$(cf_create_dockercompose_app "$PROJECT_UUID" "$SERVER_UUID" "$ENV_NAME" \
      "$GITHUB_APP_UUID" "$GIT_REPO" "${APP_BRANCH[$app]}" "${APP_COMPOSE[$app]}" "$app")
    uuid=$(echo "$resp" | python3 -c "import json,sys; print(json.load(sys.stdin).get('uuid',''))")
    [ -n "$uuid" ] || { echo "app creation failed: $resp" >&2; exit 1; }
    echo "  created: $uuid"
  else
    echo "  found existing app on ovh-files: $uuid"
  fi

  echo "-- setting env (BIND_IP + app-specific; values never echoed) --"
  case "$app" in
    data-neo4j)
      pw=$(cf_get_env_value "$OVHDATA_UUID_NEO4J" NEO4J_PASSWORD)
      [ -n "$pw" ] || { echo "could not read source NEO4J_PASSWORD" >&2; exit 1; }
      # NEO4J_server_config_strict__validation_enabled=false is REQUIRED
      # alongside NEO4J_PASSWORD: the official neo4j image auto-maps any
      # unrecognized NEO4J_xxx env into a neo4j.conf setting, so the raw
      # NEO4J_PASSWORD var (present for compose-level ${NEO4J_PASSWORD}
      # substitution, but also leaked into the container env by Coolify)
      # becomes a bogus "PASSWORD" setting. Source tolerates this by
      # disabling strict validation; skipping this env crashes the
      # container in a restart loop with "Unrecognized setting... PASSWORD"
      # (hit live 2026-08-01 standing up data-neo4j on ovh-files).
      strict=$(cf_get_env_value "$OVHDATA_UUID_NEO4J" NEO4J_server_config_strict__validation_enabled)
      cf_upsert_envs "$uuid" "BIND_IP=100.91.190.107" "NEO4J_PASSWORD=$pw" \
        "NEO4J_server_config_strict__validation_enabled=${strict:-false}" ;;
    data-vector)
      cf_upsert_envs "$uuid" "BIND_IP=100.91.190.107" ;;
    nocodb)
      cf_upsert_envs "$uuid" "BIND_IP=100.91.190.107" "NC_PUBLIC_URL=http://100.91.190.107:8570" ;;
  esac

  echo "-- deploying/starting --"
  cf_start "$uuid"
  cf_wait_running "$uuid" 300

  echo "-- liveness probe --"
  hc="${APP_HEALTHCHECK[$app]}"
  sleep 5
  code=$(curl -s -o /dev/null -m 20 -w '%{http_code}' "$hc" || echo 000)
  echo "  $hc -> HTTP $code"
  if [ "$code" != "200" ]; then
    echo "  WARNING: liveness probe did not return 200 — inspect logs before trusting this store" >&2
  fi

  echo "$app uuid=$uuid" >> "$STAGE_LOCAL/phase2_app_uuids.txt"
  echo
done

echo "PHASE 2 stand-up complete for: ${APPS[*]}"
echo "App uuids recorded in: $STAGE_LOCAL/phase2_app_uuids.txt"
