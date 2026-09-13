#!/usr/bin/env bash
# Shared helper: resolve a python3 interpreter without depending on jq.
# Prefers PATH; falls back to the pinned uv-managed shim on this desktop
# (see CLAUDE.md: plain pip/python setups on this machine are PEP-668
# managed, and this shim is the one guaranteed to exist).
pybin() {
  if command -v python3 >/dev/null 2>&1; then
    echo "python3"
  elif command -v python >/dev/null 2>&1; then
    echo "python"
  else
    echo "C:/Users/matts/.local/bin/python3.exe"
  fi
}
