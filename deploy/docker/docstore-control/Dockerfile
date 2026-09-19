# docstore-control - the existing Docstore control MCP server (plugins/docstore/control), served
# over streamable HTTP on the VPS so the propria-docstore plugin's `ctl` reaches real control tools
# (index/run/health/verify/flags/handoff) instead of the raw SurrealDB gateway.
# Byline: Claude Code · Opus 5 · 2026-09-19
# Build context = repo root. Layout under /app mirrors the repo because admission.py loads
# scripts/docstore/selected_identity.py via parents[3] of the control package.
FROM python:3.12-slim

COPY --from=ghcr.io/astral-sh/uv:0.8.17 /uv /usr/local/bin/uv
ENV PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1 UV_LINK_MODE=copy UV_PROJECT_ENVIRONMENT=/opt/venv \
    FASTMCP_CHECK_FOR_UPDATES=off

WORKDIR /app/plugins/docstore/control
COPY plugins/docstore/control/pyproject.toml plugins/docstore/control/uv.lock ./
RUN uv sync --frozen --no-dev --no-install-project
COPY plugins/docstore/control/ ./
COPY scripts/docstore/selected_identity.py /app/scripts/docstore/selected_identity.py
COPY scripts/docstore/schema/ /app/scripts/docstore/schema/

EXPOSE 8084
CMD ["/opt/venv/bin/python", "cli.py", "serve"]
