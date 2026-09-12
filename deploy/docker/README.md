# docker/ — Progressive Disclosure Map

> _Byline: Claude Code · Kimi K3 (drift-fix) · 2026-08-12 — gateway/graphiti labels corrected: LiteLLM retired (ADR-0042), Portkey is THE model gateway._
> _Byline amendment: Codex · GPT-5 · 2026-09-12 (`tool-runtime` owner ruling)._

> Dockerfiles for each service container.

## Directory Map

```
docker/
  postgres/            <- Custom PG18 image: pg_duckdb + PostGIS + pgvector.
  tool-runtime/        <- Consolidated tool runtime (SBV + registry facade).
  gateway/             <- OpenCode server (+ LiteLLM binary baked but DISABLED — RETIRED
                          per ADR-0042, supervisord autostart=false; the live model gateway
                          is Portkey — see docker/gateway/portkey/ and deploy/portkey.yaml).
  sandbox/             <- Isolated agent execution (no secrets, no published ports).
  graphiti/            <- Graphiti MCP config (Neo4j + Portkey LLM/embeddings — was LiteLLM;
                          corrected 2026-08-12, cutover live since 2026-07-19, ADR-0042).
  agent-ui/            <- Agent UI container (if present).
```

## Service Topology (compose.yaml)

| Service | Image | Profile | Ports |
|---|---|---|---|
| agentos-db | agno-postgres:18-duckdb | default | 5432 |
| agentos-api | agentos:latest | default | 8000 |
| tool-runtime | probata-tool-runtime:latest | tools | 8080, 8090 |
| sandbox | agno-sandbox:latest | tools | (internal only) |
| desktop | kasmweb/desktop:1.16.0 | desktop | 6901 |
| gateway | agno-gateway:latest | tools | 4000, 4096 |
| neo4j | neo4j:5-community | graph | 7474, 7687 |
| graphiti-mcp | zepai/knowledge-graph-mcp:latest | graph | 8071 |
