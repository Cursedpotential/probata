# docstore-worker - sync (CocoIndex change detection -> cloud docstore -> graph) + HTTP API.
# Byline: Claude Code · Opus 5 · 2026-09-10
# Build context = repo root (Coolify resolves contexts from base_directory). The repo .dockerignore
# excludes docs/, so this image uses its own Dockerfile.dockerignore allowlist (BuildKit).
FROM python:3.13-slim

ENV PYTHONUNBUFFERED=1 PIP_NO_CACHE_DIR=1 PIP_DISABLE_PIP_VERSION_CHECK=1

RUN pip install \
      "cocoindex==1.0.21" "surrealdb==3.0.0b8" "litellm==1.100.0" "ftfy==6.3.1" \
      "numpy==2.5.3" "psutil==7.2.2" "duckdb==1.5.4" \
      "fastapi>=0.110,<1" "uvicorn[standard]>=0.29,<1"

WORKDIR /app
COPY scripts/docstore/ /app/scripts/docstore/
COPY docs/ /app/docs/

EXPOSE 8000
# The PID-1 supervisor exposes the API while one bounded startup sync runs and
# preserves a failed sync as observable health state instead of losing a shell
# background-process exit. It does not retry or schedule additional runs.
CMD ["python", "scripts/docstore/container_entrypoint.py"]
