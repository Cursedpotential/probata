#!/usr/bin/env bash
# PHASE 1b — cold-copy the ovh-data volumes that have no consistent online
# export: data-neo4j, data-vector (milvus+attu), nocodb. One Coolify app at a
# time, so the data tier is never fully down — stop -> verify stopped -> tar
# -> start -> verify healthy -> pull the tarball back to local staging.
#
# Byline: Claude Code · Sonnet (agent) · 2026-08-01
#
# Deliberately excludes /data/probata/volumes/milvus.corrupt-* and *.bak-*
# (owner instruction: those die with the box, never copied, never rm'd).
#
# Run LOCALLY (dev box with tailnet + Coolify API access + the ~/.ssh/ovh key).
# Requires COOLIFY_API_TOKEN exported by the caller (see migration_lib.sh
# header for the safe parse — never `source` the secrets file).
#
# Usage:
#   ./scripts/phase1b_coldcopy.sh [app-name ...]
#   (defaults to all three; pass one or more names to redo just those)
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./migration_lib.sh
source "$HERE/migration_lib.sh"

SSH_KEY="${SSH_KEY:-$HOME/.ssh/ovh}"
OVHDATA_HOST="root@100.119.96.29"
SSH=(ssh -i "$SSH_KEY" -o ConnectTimeout=15)
SCP=(scp -i "$SSH_KEY")
STAGE_REMOTE="/data/backup-ovhdata-20260801/coldcopy"
STAGE_LOCAL="${STAGE_LOCAL:?set STAGE_LOCAL to a local staging directory}"

declare -A APP_UUID=(
  [data-neo4j]=jfvnf0i45mmccxonv1p570au
  [data-vector]=ujg3ko312xoh6xvkag8q2ina
  [nocodb]=a9z6r2b0p6ky2kpxhnc1xzh2
)
declare -A APP_PATHS=(
  [data-neo4j]="/data/probata/volumes/neo4j_data"
  [data-vector]="/data/probata/volumes/milvus /data/probata/volumes/attu"
  [nocodb]="/data/probata/volumes/nocodb"
)
declare -A APP_HEALTHCHECK=(
  [data-neo4j]="http://100.119.96.29:7474"
  [data-vector]="http://100.119.96.29:9091/healthz"
  [nocodb]="http://100.119.96.29:8570/api/v1/health"
)

APPS=("$@")
[ "${#APPS[@]}" -eq 0 ] && APPS=(data-neo4j data-vector nocodb)

mkdir -p "$STAGE_LOCAL"

for app in "${APPS[@]}"; do
  uuid="${APP_UUID[$app]:?unknown app: $app}"
  paths="${APP_PATHS[$app]}"
  hc="${APP_HEALTHCHECK[$app]}"
  echo "==================== $app ($uuid) ===================="
  t0=$(date +%s)

  echo "-- stopping --"
  cf_stop "$uuid"
  cf_wait_not_running "$uuid" 120
  # Belt-and-suspenders: confirm the container is actually gone on the host
  # (never trust the API status alone — verify the real end state).
  running=$("${SSH[@]}" "$OVHDATA_HOST" "docker ps --filter name=$uuid --format '{{.Names}}'")
  if [ -n "$running" ]; then
    echo "  WARNING: container still visible on host after stop: $running" >&2
  else
    echo "  confirmed: no container named *$uuid* running on ovh-data"
  fi

  echo "-- archiving on ovh-data --"
  "${SCP[@]}" "$HERE/coldcopy_volume.sh" "$OVHDATA_HOST:/root/coldcopy_volume.sh"
  # shellcheck disable=SC2029 — $paths is intentionally word-split remotely
  "${SSH[@]}" "$OVHDATA_HOST" "bash /root/coldcopy_volume.sh '$STAGE_REMOTE' '$app' $paths"

  echo "-- starting --"
  cf_start "$uuid"
  cf_wait_running "$uuid" 180

  echo "-- app-specific liveness probe --"
  code=$(curl -s -o /dev/null -m 15 -w '%{http_code}' "$hc" || echo 000)
  echo "  $hc -> HTTP $code"
  if [ "$code" != "200" ]; then
    echo "  WARNING: liveness probe did not return 200 — inspect before proceeding" >&2
  fi

  t1=$(date +%s)
  echo "-- downtime for $app: $((t1 - t0))s --"

  echo "-- pulling tarball to local staging --"
  "${SCP[@]}" "$OVHDATA_HOST:$STAGE_REMOTE/${app}.tar.gz" "$STAGE_LOCAL/"
  "${SCP[@]}" "$OVHDATA_HOST:$STAGE_REMOTE/${app}.tar.gz.sha256" "$STAGE_LOCAL/"
  echo "  local copy: $STAGE_LOCAL/${app}.tar.gz"
  ( cd "$STAGE_LOCAL" && sha256sum -c "${app}.tar.gz.sha256" )
  echo
done

echo "PHASE 1b complete for: ${APPS[*]}"
echo "Tarballs staged in: $STAGE_LOCAL"
