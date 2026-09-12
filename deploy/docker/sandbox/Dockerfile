# =============================================================================
# agent-sandbox — isolated code-execution space for agents (2026-06-10)
# =============================================================================
# Deliberately SEPARATE from tool-runtime: untrusted code runs here.
#   - non-root user, NO secrets in env, no volume mounts to repo/data
#   - resource-capped in compose (cpus/mem), network confined to the
#     agentos network (no published ports)
#   - exec API on :8070 — POST /run {language, code, timeout} -> stdout/stderr
# Agents call it via a sandboxed-exec tool; nothing here can reach .env or R2.

FROM python:3.12-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
        nodejs npm \
    && rm -rf /var/lib/apt/lists/* \
    && pip install --no-cache-dir fastapi uvicorn \
    && useradd -m -u 10001 runner && mkdir -p /workspace && chown runner /workspace

COPY exec_api.py /srv/exec_api.py
USER runner
WORKDIR /workspace
EXPOSE 8070
CMD ["python", "/srv/exec_api.py"]
