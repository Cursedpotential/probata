# Byline: Claude Code · Sonnet (agent) · 2026-07-23 (C4: knowledge router — Knowledge browser + Graphiti pane)
# Byline: Codex · GPT-5 · 2026-08-16 (neutral Portkey streaming chat)
# Byline: Codex · GPT-5 · 2026-08-27 (durable run-event SSE proxy)
"""Knowledge Workbench API entrypoint — the C1-C4 Operator Console backend.

Stages uploaded files locally (LanceDB whole-file store + object-store copy),
starts/lists/inspects spine runs (custody -> parse -> store -> knowledge, via
the Platform API's /v1/runs), proxies MCP tool servers for the Tool Explorer,
(C3) proxies the spine's record browser, PG/Milvus schema views, active hash
verification, and corroboration flags, and (C4) proxies the spine's own
Milvus-backed knowledge search/browse routes plus read-only Graphiti
(knowledge-graph memory) search/episodes. Never chunks, embeds, or writes
Milvus/Postgres/Neo4j itself — see workbench/api/README.md.
"""

from __future__ import annotations

import logging
from pathlib import Path

from app.config import settings
from app.runtime import (
    case_management,
    chat,
    classification,
    compare,
    copilot,
    documents,
    files,
    health,
    inspect,
    knowledge,
    metrics,
    proffer,
    proffer_resources,
    promote,
    repairs,
    run_events,
    runs,
    sentiment,
    source_inspection,
    tools,
    upload,
)
from app.runtime.auth import authentication_middleware
from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles
from starlette.exceptions import HTTPException as StarletteHTTPException
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.responses import FileResponse

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("workbench")

app = FastAPI(
    title="Knowledge Workbench API",
    description="""
Staging + promote surface over the existing platform ingestion API.

## Classification & Sentiment Analysis Test System

This API includes a comprehensive test system for running conversation chunks and AI chat chunks through classification and sentiment analysis via LLM.

### Features
- **Multi-provider support**: Ollama, NVIDIA NIM, Portkey, OpenRouter, Anthropic, OpenAI, Google, Groq
- **Classification**: Categorize texts into custom categories with confidence scores
- **Sentiment Analysis**: Detect sentiment (positive/negative/neutral/mixed) with emotion breakdown
- **Comparison**: Run same texts across multiple providers simultaneously
- **Export**: JSON/CSV export of results
- **Portkey Integration**: Unified gateway with tracing, fallbacks, cost tracking

### Authentication
Traefik + Authentik ingress only. Socket peer must be inside explicitly
configured trusted proxy CIDRs (fail-closed). Authentik identity headers
`X-authentik-uid` and `X-authentik-username` required on all protected routes.
Forwarded headers, passwords, HTTP Basic, cookies, and bearer tokens parsed by
Workbench are not accepted. Only `/health` is public.

### Documentation
- Swagger UI: `/docs`
- ReDoc: `/redoc`
- OpenAPI JSON: `/openapi.json`
    """,
    version="0.1.0",
    openapi_tags=[
        {"name": "health", "description": "Health checks"},
        {"name": "upload", "description": "File upload and staging"},
        {"name": "files", "description": "Staged file management"},
        {"name": "promote", "description": "Promote staged files to platform"},
        {"name": "documents", "description": "Document management"},
        {"name": "runs", "description": "Spine run management"},
        {"name": "inspect", "description": "Record inspection and flagging"},
        {"name": "knowledge", "description": "Knowledge search and browse"},
        {"name": "matters", "description": "Matter workspaces and draft evidence"},
        {"name": "tools", "description": "MCP tool proxy"},
        {"name": "repairs", "description": "Automated repair agents"},
        {"name": "copilot", "description": "Copilot chat interface"},
        {"name": "chat", "description": "Framework-neutral Portkey streaming chat"},
        {"name": "metrics", "description": "API metrics"},
        {"name": "classification", "description": "Text classification (single/batch)"},
        {"name": "sentiment", "description": "Sentiment analysis (single/batch)"},
        {"name": "comparison", "description": "Multi-provider comparison and export"},
    ],
)

# Request timing + in-process metrics counters (app.runtime.metrics)
app.add_middleware(BaseHTTPMiddleware, dispatch=metrics.timing_middleware)
# Added after timing so authentication is the outermost boundary around API,
# documentation, and the static frontend alike.
app.add_middleware(BaseHTTPMiddleware, dispatch=authentication_middleware)

app.include_router(health.router)
app.include_router(upload.router)
app.include_router(proffer.router)
app.include_router(proffer_resources.router)
app.include_router(source_inspection.router)
app.include_router(files.router)
app.include_router(promote.router)
app.include_router(documents.router)
app.include_router(runs.router)
app.include_router(run_events.router)
app.include_router(inspect.router)
app.include_router(knowledge.router)
app.include_router(case_management.router)
app.include_router(chat.router)
app.include_router(tools.router)
app.include_router(repairs.router)
app.include_router(copilot.router)
app.include_router(metrics.router)
app.include_router(classification.router)
app.include_router(sentiment.router)
app.include_router(compare.router)

# Static frontend (built separately) mounted LAST so /api + /health always win.
_static_dir = Path(settings.static_dir)
_SPA_RESERVED_PREFIXES = frozenset({"api", "docs", "health", "openapi.json", "redoc"})


def _allows_spa_fallback(path: str) -> bool:
    """Return whether an unknown path may be a client-side Workbench route."""

    normalized = path.lstrip("/")
    first_segment = normalized.split("/", 1)[0]
    final_segment = normalized.rsplit("/", 1)[-1]
    return first_segment not in _SPA_RESERVED_PREFIXES and "." not in final_segment


class _WorkbenchStaticFiles(StaticFiles):
    """Serve real assets normally and fall back to Vite's SPA entry document.

    API routers are mounted before this catch-all. Extensionless browser routes
    resolve to ``index.html`` so TanStack Router can restore deep links, while a
    missing asset-like path remains a real 404 instead of receiving HTML.
    """

    async def get_response(self, path: str, scope):  # type: ignore[override]
        request_path = str(scope.get("path") or path)
        try:
            response = await super().get_response(path, scope)
        except StarletteHTTPException as error:
            if error.status_code == 404 and _allows_spa_fallback(request_path):
                return FileResponse(Path(self.directory) / "index.html")  # type: ignore[arg-type]
            raise
        if response.status_code == 404 and _allows_spa_fallback(request_path):
            return FileResponse(Path(self.directory) / "index.html")  # type: ignore[arg-type]
        return response


if _static_dir.is_dir():
    app.mount("/", _WorkbenchStaticFiles(directory=str(_static_dir), html=True), name="static")
    logger.info("Serving static frontend from %s", _static_dir)
else:
    logger.info("STATIC_DIR %s not found — no frontend mounted", _static_dir)


if __name__ == "__main__":
    import uvicorn

    uvicorn.run("main:app", host="0.0.0.0", port=settings.app_port)
