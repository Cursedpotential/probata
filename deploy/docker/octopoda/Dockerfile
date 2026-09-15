# octopoda MCP server (agent memory: memory/search/loop-detection/goals/
# messaging/decisions/snapshots) — streamable-HTTP container on ovh-app,
# behind ContextForge. Federated per owner order 2026-09-15: "every movable
# MCP server is hosted on the VPS behind ContextForge".
# octopoda==3.3.4 only ships a stdio entrypoint; run_http.py imports its
# FastMCP object directly and runs it over streamable-HTTP (see that file's
# docstring for why). Byline: Claude Code · Sonnet 5 · 2026-09-15
FROM python:3.13-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY run_http.py .

ENV PYTHONUNBUFFERED=1 \
    PORT=8095 \
    OCTOPODA_API_KEY=local \
    OCTOPODA_DATA_DIR=/data

EXPOSE 8095

CMD ["python", "run_http.py"]
