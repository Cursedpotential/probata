# =============================================================================
# temporal-worker — first P0 build artifact (plan §5 review amendment,
# "the Temporal worker is its own Coolify app whose image carries the full
# server/ dependency stack ... building that image is the first concrete P0
# task, before any workflow code"). Byline: Claude Code · Opus 5 · 2026-08-23
# Full plan: docs/plans/TEMPORAL-INTEGRATION-PLAN-2026-08-23.md (D-067)
#
# Joins Temporal task queue `evidence-pipeline`. Connects to the Temporal
# frontend via TEMPORAL_ADDRESS (default temporal-server:7233 on the shared
# `probata` docker network — see deploy/temporal/compose.temporal.yaml).
#
# Needs the SAME application env as agentos-api (DB_*, WEAVIATE_*, PORTKEY_*,
# etc.) because Activities call the EXISTING pipeline code unchanged
# (custody.py, store.py, workflows.py's Step logic wrapped as Activities) —
# see plan §1: custody hashing and walk derivation stay platform-side,
# invoked FROM Activities, never reimplemented as workflow code.
#
# Base image matches every other docker/*/Dockerfile in this repo
# (python:3.12-slim — checked docker/coolify-mcp, docker/sandbox,
# docker/surreal-phase1-runner; the repo-ROOT Dockerfile uses agnohq/python:3.12
# for the AgentOS app itself, which is a different base for a different app).
#
# Multi-stage is unnecessary here — no compiled frontend/build step, just the
# existing pure-Python server/ package plus the temporalio SDK.
#
# NOTE: `python -m server.temporal.worker` is the P1 entrypoint module (not
# yet written — P0 ships infra only, per plan §2). Until that module exists
# this image builds but the CMD will fail at runtime; that is expected for a
# P0 scaffold and is tracked as the first P1 task, not a defect in this file.
# =============================================================================
FROM python:3.12-slim

WORKDIR /app
ENV PYTHONPATH=/app

COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt \
    && pip install --no-cache-dir temporalio

# Activities call into the existing pipeline code, so the worker needs the
# same application surface as agentos-api, not just an SDK stub.
COPY server/ ./server/
COPY scripts/ ./scripts/
COPY sql/ ./sql/

CMD ["python", "-m", "server.temporal.worker"]
