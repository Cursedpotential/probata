# Cloud services — phase 2 plan (files · logs · gateway auth · federation)

> _Byline: Claude Code · Fable 5.1 · 2026-09-08 12:46 EDT. STATUS: ITERATING — NOT approved (Fable wrongly marked it approved 12:54; owner corrected 12:55). Nothing executes until the owner approves each phase._

## Context
Phase 1 (2026-09-07/08) stood up devbox, opencode-server, OpenList, surreal-case, ContextForge, Portkey, Tailscale sidecars, SMB link. Owner orders 2026-09-08 12:28–12:44 define phase 2: Portkey + ContextForge fully set up with auth (m2m **and** user), all provider keys behind the gateway, Claude via the **Agent SDK** (decided 12:32), Codex via OpenCode's ChatGPT login, **federate our own tools into grouped virtual servers**, register every local MCP that can move, **secure ingress for cloud MCP clients (claude.ai + Case Bible plugin)**, **one log-aggregation stack for all logs** (decided 12:34), Filestash UI over OpenList, Google Drive + OneDrive in OpenList, newest versions everywhere, and an `msalem` admin on every service (rule saved 12:40). Devbox v2 is deploying now and is not part of this plan.

## Standing constraints
- Tailnet-only on both hosts; nothing public without an explicit design (2026-09-07 firewall rule). Bind-mounted volumes only, one concern per Coolify app, Watch Paths scoped per app, no secrets in git, byline every file, never delete (quarantine), verify live before claiming.
- Root session stays lean: each phase is executed by one Sonnet agent with a written brief; Fable reviews outputs.

## Phases (order = dependency + value)

### P0 — Finish in flight (no new decisions)
- devbox v2 deploy + verification table (agent running). opencode-server on `opencode web` (deployed 12:25; verify UI behind password). Federation inventory doc (agent running) → feeds P5/P6.

### P1 — Files lane
| step | detail |
|---|---|
| Filestash | New Coolify app `filestash` on ovh-files, image `machines/filestash:latest` pinned by **digest** at deploy (project publishes no version tags), `${BIND_IP}:8334:8334`, state volume `/data/probata/volumes/filestash`, tailscale sidecar `files-ui`. Backend = OpenList WebDAV `http://openlist:5244/dav` (probata network) as the default connection; admin password = generated (secrets), `msalem` via the same WebDAV creds. |
| Google Drive + OneDrive | Two OpenList storages (native drivers `GoogleDrive`, `Onedrive`). Needs owner: one browser OAuth each (Google Cloud project client or OpenList helper; Azure app registration for OneDrive). Mount paths `/gdrive/<account>`, `/onedrive/<account>`. Verify: list + 1 KB round-trip copy to `/exchange` and back, then quarantine the test file. |
| Verify | Filestash lists all OpenList roots incl. the two new ones; move a file R2 → desktop share from Filestash; owner opens it. |

### P2 — Observability stack (Grafana · Loki · Mimir · Tempo · Fluent Bit · OTel Collector)
_Owner 12:51: "I want the stack" (Grafana + Loki + Fluent Bit + Mimir + OpenTelemetry, per the Medium write-up), "Grafana should only have to run on one server." OpenObserve dropped. Article deltas (12:52): MinIO → a dedicated R2 bucket (Loki/Mimir S3-native), MySQL → Grafana SQLite, Loki read/write split → monolithic (flag change later), + Tempo for traces (article has none)._

| piece | where | detail |
|---|---|---|
| Grafana | **ovh-files only** (one instance) | Coolify app `grafana`, `grafana/grafana:<newest at deploy>`, `${BIND_IP}:3000:3000`, volume `/data/probata/volumes/grafana`, admin = generated + `msalem` admin, tailscale sidecar `grafana`. Datasources provisioned from repo files: Loki, Mimir, Tempo. |
| Loki (logs) | ovh-files | same compose, monolithic `-target=all`, **S3 store = R2 bucket `probata-observability`** (WAL/index cache on `/data/probata/volumes/loki`), 30-day retention via compactor + R2 lifecycle; OTLP ingest with `service.name`/`project.name`/`deployment.environment` as index labels. |
| Mimir (metrics) | ovh-files | monolithic mode, blocks in the same R2 bucket (prefix `mimir/`), local cache `/data/probata/volumes/mimir`; receives Prometheus remote-write + OTLP metrics. |
| Tempo (traces) | ovh-files | monolithic, local blocks `/data/probata/volumes/tempo`; Portkey + ContextForge + workbench OTLP traces land here (the article routes traces through the OTel Collector; Tempo is the store it needs). |
| OTel Collector | ovh-files | `otel/opentelemetry-collector-contrib`, OTLP :4317/:4318 in; exporters → Tempo (traces), Mimir (metrics), Loki (logs from OTLP-native apps). Host metrics + docker stats via receivers. |
| Shipping (Coolify Log Drains) | **both hosts**, run by Coolify | Owner 12:53: forward from Coolify. Coolify → Server → Log Drains → **Custom** (Coolify runs its own Fluent Bit container per server and attaches the fluentd log driver to every resource with "include in log drain" ticked). Custom output = Fluent Bit `opentelemetry` output → OTel Collector `100.91.190.107:4318` (tailnet) with `X-Scope-OrgID`. Coolify labels (`coolify.applicationId`, project/service names) → resource attributes → Loki labels. No daemon.json change, no compose edits, no Alloy. Confirm the Custom drain config shape in Coolify 4.1.2 at build time; tick every app on both servers. |
| Feeds day one | | every container on both hosts (logs), Portkey OTLP traces (verify 1.15.2 env vars), host CPU/RAM/disk both hosts, Docker container stats, PG exporter later. |
| Verify | | Grafana Explore: `{host="ovh-app"}` and `{host="ovh-files"}` both return lines within 5 min; one Portkey request visible in Tempo with model + token attrs; Mimir shows both hosts' node metrics; a query for `error` across all apps returns rows; one dashboard "fleet" saved and linked from tonight's navigation page. |
| Footprint | | ~1.5–2 GB RAM total on ovh-files (Loki/Mimir/Tempo monolithic + Grafana + collector); Fluent Bit ~30 MB per host. Check `free -m` on ovh-files before deploy; caps set per service. |

### P3 — Portkey: keys behind the gateway, self-hosted
| step | detail |
|---|---|
| Version | 1.15.2 is newest (verified 12:35). No bump. |
| Key store | Keys leave every client config. An nginx front `portkey-front` (same compose as Portkey, ovh-app) terminates one **internal bearer** per consumer class (`PK_TOKEN_DEVBOX`, `PK_TOKEN_OPENCODE`, `PK_TOKEN_WORKBENCH`, `PK_TOKEN_N8N`, …) and injects `x-portkey-config` from the lane JSONs (`deploy/docker/gateway/portkey/configs/*.json`, provider keys substituted at container start from Coolify env, never in git). Paths = lanes: `/chat`, `/classify`, `/embed`, `/embed-general`, `/graphiti-llm`, plus new `/code` (NIM nemotron → Ollama Cloud glm → OpenRouter free) and `/cheap`. |
| Consumers | opencode-server providers → one `portkey` provider entry per lane; devbox opencode/claude configs same; memsearch + ccc embedders → `/embed`; n8n credentials → front URL; agno/agents stay direct where they already pass through Portkey. |
| Verify | `curl` each lane with its token → 200 with the expected model in the response; a request with a wrong token → 401; provider keys grep-absent from every client config file on desktop + devbox home; OpenObserve shows the trace. |

### P4 — ContextForge: upgrade + auth (user + m2m) + msalem
| step | detail |
|---|---|
| Upgrade | `ghcr.io/ibm/mcp-context-forge:v1.0.4` → **v1.0.10**; read release notes 1.0.5–1.0.10 for env/migration changes first; PG schema migrations run on boot (backup the `contextforge` DB with `pg_dump` before). |
| User auth | `EMAIL_AUTH_ENABLED=true`, `PLATFORM_ADMIN_EMAIL=<owner>`, generated admin password in secrets, then create user `msalem` (admin role) via the admin API; `AUTO_CREATE_PERSONAL_TEAMS=true`. |
| M2M | Personal API tokens (long-lived, scoped per consumer) minted for: Claude Code desktop, devbox, opencode-server, Workbench Ops Copilot, n8n. JWT secret stays; `SSO_API_TOKEN_AUTH_ENABLED=true` only if a token type needs it. |
| Verify | login as `msalem` in the admin UI; each token lists `/tools` with 200; an expired/wrong token → 401; `/health` 200 after upgrade; existing registrations intact (count before = after). |

### P5 — Federation into virtual servers
- Input: `docs/planning/2026-09-08-contextforge-federation-inventory.md` (agent, in progress). Execute its MOVE list in its migration order: hosted transports first (console `MCP_TRANSPORT=http` — deploy `deploy/family-court-console.yaml`, code-only image; content loads into surreal-case via `load-content-to-store.mjs`), then stdio-only servers via `mcpgateway.translate` sidecars, then third-party HTTP MCPs. Virtual servers per the inventory's grouping (target 4–8, small tool counts). Client repoint: plugin `.mcp.json`s → virtual-server URLs + bearer, stdio fallback kept.
- Verify per server: tool list from ContextForge = tool list from the origin; one real call through the virtual server per group.

### P6 — Secure ingress for cloud MCP clients (claude.ai + Case Bible plugin)
- Design decided by the inventory doc's ingress section (Cloudflare Tunnel + Access vs Traefik public + ContextForge OAuth). Constraint: no inbound port on either host. Worked example end-to-end: claude.ai connector → ingress → ContextForge `case-work` virtual server → console. Verify from claude.ai itself (owner clicks), not from curl alone.

### P7 — Agent-side providers
- **Claude via Agent SDK:** `claude setup-token` once on the desktop (owner), token into secrets; devbox + opencode-server get it as `CLAUDE_CODE_OAUTH_TOKEN`; a small Agent-SDK runner (`scripts/claude_sdk_task.py`, mirrors `oc_task.py`) so the root session can delegate to Claude on subscription without a proxy. **Codex:** `opencode auth login` → OpenAI → ChatGPT Plus/Pro on opencode-server (owner does the device-code step once). Verify: one delegated task each, output file produced, no API key consumed.

### P8 — Tonight: monitoring + navigation dashboard
- Separate build (memory `dashboard-monitoring-navigation-next`); links to everything above (Grafana, Filestash, OpenList, Kasm, opencode web, ContextForge, Portkey health, Coolify).

## Owner decisions still open
1. ~~P1 OAuth~~ DECIDED 12:55: reuse the rclone OAuth process/tokens (desktop rclone remotes `od`, `od1` = OneDrive, `gd_net_rw` = Google Drive; VPS rclone has only `r2`). Owner: Google side may be broken, 4 Google accounts, **deferred — owner will fix later**; Drive/OneDrive step in P1 waits on that.
2. ~~P2: OpenObserve RC vs GA~~ — superseded 12:51: Grafana stack chosen; all images pinned to the newest release at deploy time.
3. P3: per-consumer tokens vs one shared token — OPEN.
4. P6: inventory recommends Cloudflare Tunnel + Access; two hands-on checks remain (1.0.10 inbound auth; Access token vs ContextForge bearer).

## Files this plan will touch
`deploy/filestash.yaml` (new), `deploy/openlist.yaml` (no change; storages via API), `deploy/observability.yaml` (Grafana/Loki/Mimir/Tempo/OTel on ovh-files) + `deploy/log-shipper.yaml` (Fluent Bit, one app per host) + `deploy/docker/observability/*` provisioning files (new), `deploy/portkey.yaml` (+ nginx front, configs), `deploy/contextforge.yaml` (image + env), `deploy/family-court-console.yaml`, plugin `.mcp.json`s, `scripts/claude_sdk_task.py` (new), `E:\AI_Workspace\TOOLING-REPAIRS.md`, memory notes.
