#!/usr/bin/env bash
# opencode-server entrypoint — `opencode web` instead of the image's hard-coded `opencode serve`.
# Byline: Claude Code · Fable 5.1 · 2026-09-08 (owner 12:23 "do the web thing").
# Copy of sprisa/opencode-server entrypoint.sh (MPL-2.0) with ONE change: the final exec runs
# `opencode web`, which is the same headless server plus the browser UI at /. OPENCODE_SERVER_PASSWORD
# basic auth applies to both (opencode.ai/docs/server). Bind-mounted read-only by deploy/opencode-server.yaml.
set -euo pipefail

mkdir -p "${HOME}/.config/opencode" "${HOME}/workspace"
cd "${HOME}/workspace"

# Opt-in mise home tools (same semantics as upstream; runs in the background after 3 s).
if [ "${OPENCODE_INSTALL_HOME_TOOLS:-false}" = "true" ] && [ -f "${HOME}/.config/mise/config.toml" ]; then
  (
    sleep 3
    if ! MISE_SYSTEM_CONFIG_FILE=/dev/null MISE_CEILING_PATHS="${HOME}" \
      mise -C "${HOME}" install --yes; then
      printf '%s\n' 'opencode: home tool installation failed' >&2
    fi
  ) &
fi

args=(web --hostname 0.0.0.0 --port "${OPENCODE_PORT:-4096}")
if [ "${OPENCODE_PRINT_LOGS:-false}" = "true" ]; then
  args+=(--print-logs)
fi
if [ -n "${OPENCODE_LOG_LEVEL:-}" ]; then
  args+=(--log-level "${OPENCODE_LOG_LEVEL}")
fi
if [ -n "${OPENCODE_CORS_ORIGIN:-}" ]; then
  args+=(--cors "${OPENCODE_CORS_ORIGIN}")
fi
# No browser in a container: BROWSER=true makes any xdg-open/open attempt a harmless no-op.
export BROWSER=true
exec opencode "${args[@]}"
