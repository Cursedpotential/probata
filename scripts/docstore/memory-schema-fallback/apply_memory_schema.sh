#!/usr/bin/env bash
# apply_memory_schema.sh
# Applies the D-154 agent-memory schema (000/080/085/087) in order to a
# SurrealDB HTTP /sql endpoint via curl + basic auth, per-file, checking each
# response for "status":"ERR" before moving to the next file. Prints
# INFO FOR DB at the end. Credentials are read from an env file
# (SURREAL_USER / SURREAL_PASS) and are NEVER echoed.
#
# Usage:
#   ./apply_memory_schema.sh <env_file> <endpoint> <ns> <db> [schema_dir]
#
# Example (local scratch, already applied by this pass):
#   ./apply_memory_schema.sh \
#     "$REPO_ROOT/.docstore/.env" \
#     "http://127.0.0.1:8462" scratch_memory memory
#
# VPS example (NOT run by this task -- endpoint given for the record only):
#   ./apply_memory_schema.sh \
#     "$REPO_ROOT/.docstore/.env" \
#     "http://100.91.190.107:8471" probata_memory memory

set -euo pipefail

ENV_FILE="${1:?usage: apply_memory_schema.sh <env_file> <endpoint> <ns> <db> [schema_dir]}"
ENDPOINT="${2:?missing endpoint}"
NS="${3:?missing namespace}"
DB="${4:?missing database}"
SCHEMA_DIR="${5:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

FILES=(000_analyzers.surql 080_memory.surql 085_memory_functions.surql 087_memory_access.surql)

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: env file not found: $ENV_FILE" >&2
  exit 2
fi

# Tolerant KEY=value parser -- never `source`s the env file (a value with
# "KEY = value" spacing would otherwise be executed as a shell command).
SURREAL_USER="$(grep -E '^SURREAL_USER=' "$ENV_FILE" | head -1 | cut -d= -f2-)"
SURREAL_PASS="$(grep -E '^SURREAL_PASS=' "$ENV_FILE" | head -1 | cut -d= -f2-)"

if [[ -z "$SURREAL_USER" || -z "$SURREAL_PASS" ]]; then
  echo "ERROR: SURREAL_USER/SURREAL_PASS not found in $ENV_FILE" >&2
  exit 2
fi

echo "Applying D-154 memory schema to endpoint=$ENDPOINT ns=$NS db=$DB"
echo "Files (in order): ${FILES[*]}"
echo

for f in "${FILES[@]}"; do
  path="$SCHEMA_DIR/$f"
  if [[ ! -f "$path" ]]; then
    echo "ERROR: schema file not found: $path" >&2
    exit 2
  fi
  echo "=== Applying $f ==="
  resp="$(curl -sS -u "${SURREAL_USER}:${SURREAL_PASS}" \
    -H "surreal-ns: ${NS}" \
    -H "surreal-db: ${DB}" \
    -H "Accept: application/json" \
    -H "Content-Type: text/plain" \
    --data-binary @"$path" \
    "${ENDPOINT%/}/sql")"

  # Fail loudly on any statement whose status is "ERR".
  if echo "$resp" | grep -q '"status":"ERR"'; then
    echo "FAILED: $f produced at least one ERR result:" >&2
    echo "$resp" >&2
    exit 1
  fi
  # Fail loudly on a top-level HTTP-error-shaped JSON body (e.g. {"code":400,...}).
  if echo "$resp" | grep -q '"code":4'; then
    echo "FAILED: $f -- request-level error:" >&2
    echo "$resp" >&2
    exit 1
  fi
  echo "OK: $f applied cleanly."
  echo
done

echo "=== INFO FOR DB (post-apply) ==="
curl -sS -u "${SURREAL_USER}:${SURREAL_PASS}" \
  -H "surreal-ns: ${NS}" \
  -H "surreal-db: ${DB}" \
  -H "Accept: application/json" \
  -H "Content-Type: text/plain" \
  --data "INFO FOR DB;" \
  "${ENDPOINT%/}/sql"
echo
echo "Done."
