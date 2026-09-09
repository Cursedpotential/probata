# Cloud case store, ContextForge, and Portkey — discovery pass

> _Byline: Claude Code · Sonnet 5 · 2026-09-07._
>
> Read-only discovery only. No deploys, no config edits, no process kills, no
> downloads, no local builds were performed. Scope: owner ruling 2026-09-07
> 16:16 — move the family-court-toolkit (FCT) case store to the platform's
> existing SurrealDB on the VPS, serve the console MCP server through
> ContextForge to every harness, connect the Tauri desktop app to the cloud,
> and stand Portkey up for key rotation/logging/load-balancing. No secret
> values are printed anywhere in this document; env vars are named only.

---

## 0. Critical framing correction before anything else

**There is currently no live "governed analytical" SurrealDB instance on the
VPS.** Three distinct SurrealDB things exist in this repo/infra, and they are
easy to conflate:

| Thing | Status | Where | Role |
|---|---|---|---|
| Legacy Agno-operational SurrealDB | **PARKED, read-only, NOT Coolify-managed** | `ovh-data` host, `100.119.96.29:8000` (raw Docker, not a Coolify app — confirmed absent from the 34-app Coolify roster) | Retired per ADR-0043 decision 3. `get_surrealdb_legacy()` in `server/core/session.py` has zero callers. Kept alive only so a parity read is possible; owner-gated deletion. |
| Phase-1 synthetic spike | **Coolify app exists, `exited:unhealthy`** | Coolify app `data-surreal-phase1-t0-r1` (uuid `hastprr4a99tvpdi4c2k8i36`), `ovh-files`, retired compose at `deploy/_retired/compose.surreal-phase1.yaml` | A disposable, synthetic-data-only ADR-0056 spike, explicitly "stop and quarantine, never delete." Not a candidate for real case data. |
| **The "governed analytical" Surreal** described by D-073/D-080/ADR-0056/D-145/D-151 | **Designed, never deployed as its own live Coolify app** | — | This is the target SurrealDB the platform's own analysis engine (soon to split out as `indagatio`, D-139) will use for horizon walks/deltas. It does not exist as a running service today. |

So "the platform's existing SurrealDB on the VPS" **can only mean the legacy
parked instance** (`100.119.96.29:8000`, ns `agno` / db `platform`, image
`surrealdb/surrealdb:v3.1.4`) — nothing else is live. Live-probed this session
(`curl -m 8 http://100.119.96.29:8000/version` and `/health`): **HTTP 000 /
connection timeout** from this desktop over Tailscale — not proof the
container is down (it is described elsewhere as still healthy on the host as
of 2026-08-06), but this session could not reach it and that must not be
reported as "confirmed up." Verify from an on-box or on-tailnet vantage point
before relying on it.

**This creates the central owner decision for this whole task** (see §7):
whether "move the case store to the platform's existing SurrealDB" means (a)
a new `fct` namespace inside that same legacy-parked container, (b) a brand
new, dedicated SurrealDB Coolify app for FCT case data only, or (c) waiting
for the real governed-analytical Surreal to be built and landing FCT there.
Option (a) reuses a container the platform's own docs call "dead dependency,
parked container, owner-gated deletion" (`server/core/session.py:92-93`) —
reactivating it for new production writes is a reversal of that posture and
should not happen silently.

---

## 1. Platform SurrealDB — evidence

- **Coolify app roster** (`list_applications`, live): no app named `data-surreal`
  exists. Only `data-surreal-phase1-t0-r1` (uuid `hastprr4a99tvpdi4c2k8i36`,
  status `exited:unhealthy`) appears. This corroborates the compose header at
  `deploy/compose.data-surreal.yaml:1-9`: *"NOT Coolify-managed... This file
  stays at repo root as the parked container's record."* The legacy container
  lives outside Coolify's control plane entirely.
- **Legacy container spec** (`deploy/compose.data-surreal.yaml:49-82`):
  image `surrealdb/surrealdb:v3.1.4`, bind `${BIND_IP:-127.0.0.1}:8000:8000`,
  auth via `--user=${SURREALDB_USER:-root} --pass=${SURREALDB_PASS:-root}`,
  storage `rocksdb:/data/surreal.db` on host bind `/data/probata/volumes/surrealdb`
  (per the file's own header this predates the 2026-09-07 host-root rename and
  may now live under `/data/probata/...` — not reconciled in this pass).
- **App-side config defaults** (`server/core/session.py:94-98`):
  `SURREALDB_URL = ws://100.119.96.29:8000/rpc`, `SURREALDB_USER = root`,
  `SURREALDB_PASS = root`, `SURREALDB_NS = agno`, `SURREALDB_DB = platform`.
  Env var **names**: `SURREALDB_URL`, `SURREALDB_USER`, `SURREALDB_PASS`,
  `SURREALDB_NS`, `SURREALDB_DB`. Root credentials default to the literal
  string `root`/`root` unless overridden — this is a real exposure if this
  container is ever put back in front of anything besides a same-host,
  tailnet-only caller.
- **Version**: `v3.1.4` (surrealdb/surrealdb image tag, both the legacy
  container and referenced consistently across `deploy/compose.data-surreal.yaml`
  and `deploy/exec.yaml`).
- **Namespaces/databases**: could not be queried this session (`surreal sql`
  not installed locally, per the task's own constraint; `curl /health`/`/version`
  timed out — see §0). The only known ns/db pair is the default `agno`/`platform`
  baked into `server/core/session.py`.
- **Does `fct` fit governance?** ADR-0056 decision 8 says the disposable
  slice "uses **one shared Surreal Context** for its product/environment
  world. Matter scopes partition promoted material inside that Context" —
  i.e., the ADR's model is namespace-per-product-context with matter-level
  partitioning inside, not literally "one Surreal ns per unrelated product."
  D-073/D-080/D-145/D-151 are unanimous that the **governed** Surreal is
  reserved for the platform's own promoted, PG-reconciled evidence and its
  horizon-walk analysis — "reading context, sending it to Surreal, and
  analysing there **is the platform in use**" (D-151b). FCT case data is a
  **separate product's** working store, not promoted probata evidence, so
  landing it in the same governed instance under a same-named `fct` namespace
  would be a **namespace collision with a different meaning** than anything
  ADR-0056 describes, and would put non-platform-governed writes inside the
  instance ADR-0056 designates for governed, PG-reconciled state only. That is
  an owner call, not a mechanical fit — flagged in §7, not resolved here.
- **The `fct` namespace is not a new proposal — it is already hardcoded in
  the console today.** `mcp-app/src/store.ts:440`:
  `await db.use({ namespace: "fct", database: "case" });`. Whatever SurrealDB
  instance FCT points at, it already asks for ns `fct` / db `case`.

---

## 2. Current FCT case-store topology (as of TODAY, same day as this task)

This matters more than anything else found: **the owner already ruled on
FCT's SurrealDB topology 40–50 minutes before this task was issued**, and
that ruling is for a **local desktop shared service, not the VPS**.

- Owner ruling, 2026-09-07 15:27–15:34 (quoted verbatim in
  `C:\Users\matts\.claude\local-plugins\plugins\family-court-toolkit\scripts\install_case_db_service.py`
  docstring): *"install its binary in ~ ... all the data there so other
  harnesses can use it"* — because embedded RocksDB is single-process
  (proven: a second process hangs 60s on the lock file), the store must be a
  server, not an in-process engine.
- What that script installs (idempotent, never deletes): `~/bin/surreal.exe`
  (downloaded SurrealDB server binary), `~/.secrets/family-court-toolkit.env`
  holding `CUSTODY_CASE_DB_USER=fct` / `CUSTODY_CASE_DB_PASS=<generated>` /
  `CUSTODY_CASE_DB=ws://127.0.0.1:8471`, a launcher `~/bin/family-court-db.cmd`
  running `surreal start --bind 127.0.0.1:8471 rocksdb:~/.config/family-court-toolkit/case.db`,
  and a Windows Task Scheduler job `family-court-db` that starts it hidden at
  logon.
- **This is loopback-only, desktop-local — not the VPS, not reachable by a
  Tauri app on another machine, not reachable by ContextForge.** It solved
  "every local harness shares one store," not "the store is cloud-hosted."
- `mcp-app/src/store.ts` connection precedence (`resolveDbUrl`, lines
  ~163–171): explicit override > `CUSTODY_CASE_DB` env > `CUSTODY_CASE_DB` in
  any `~/.secrets/*.env` (tolerant-parsed, never `source`d) > embedded RocksDB
  at `~/.config/family-court-toolkit/case.db` (default). Root credentials for
  ws:// mode: `CUSTODY_CASE_DB_USER` / `CUSTODY_CASE_DB_PASS`, same discovery
  order (`findServerCredentials`, lines ~219–243).
- **This means moving to the cloud is a one-line config change from the
  client's point of view** — set `CUSTODY_CASE_DB` to a `wss://<vps-tailnet-ip>:<port>`
  URL and `CUSTODY_CASE_DB_USER`/`CUSTODY_CASE_DB_PASS` to the VPS instance's
  real credentials, in `~/.secrets/family-court-toolkit.env` (or per-harness
  env). The store.ts code already treats "shared server over ws(s)://" as a
  first-class mode; nothing in the TypeScript needs to change to point at a
  different host, only at whichever host is decided in §7.

---

## 3. ContextForge — evidence

- **Image / version**: `ghcr.io/ibm/mcp-context-forge:v1.0.4` (`deploy/contextforge.yaml:35`).
  Confirmed by both the tracked compose file and the live Coolify app's
  rendered `docker_compose`.
- **Coolify app**: `exec-contextforge`, uuid `k272znxpa4gh6drmolut723w`, on
  server `ovh-app` (`fmuao9enq3nxk8qw5hqjzzce`, tailnet `100.72.169.40`).
  Compose location on the app: `docker_compose_location: /deploy/contextforge.yaml`.
  **Watch path is `compose.contextforge.yaml`** (no `deploy/` prefix) —
  mismatched against the actual tracked path, meaning a push that only
  touches `deploy/contextforge.yaml` may not trigger a redeploy. This is the
  same class of drift the repo's own memory flags for Portkey's app (watch
  path also still says `compose.portkey.yaml` for an app whose real location
  is `/deploy/portkey.yaml`) — both should be corrected as part of any work
  on these apps.
- **Live status: `exited:unhealthy`.** `last_restart_type: "crash"`,
  `restart_count: 23`. `get_application_logs` returned `400: Application is
  not running` (no runtime log obtainable this session). Live probe
  `curl -m 8 http://100.72.169.40:4444/health` timed out (HTTP 000, ~2.3s) —
  consistent with the Coolify status, not a separate finding.
- **Root cause found (concrete, not speculative):** the app's *rendered*
  `docker_compose` (returned by `get_application`) shows three required env
  vars rendering as their own Compose `${VAR:?message}` **fallback message
  text**, not real values:
  - `CONTEXTFORGE_DATABASE_URL` → literal string `"set dedicated ContextForge PostgreSQL DSN"`
  - `CF_JWT_SECRET_KEY` → literal string `"set CF_JWT_SECRET_KEY"`
  - `CF_AUTH_ENCRYPTION_SECRET` → literal string `"set CF_AUTH_ENCRYPTION_SECRET"`

  By contrast, `CF_BASIC_AUTH_PASSWORD`, `CF_ADMIN_PASSWORD`,
  `CF_BASIC_AUTH_USER`, and `CF_ADMIN_EMAIL` render as real-looking values (not
  printed here). This is the exact "Coolify renders env-var VALUES as literals
  into the materialized compose" failure mode already on record in
  `AGENTS.md`'s Claude-Reflect learnings — **three of ContextForge's required
  envs are simply not set in the Coolify app's stored env**, so the container
  starts with a non-DSN string as `DATABASE_URL` and fails immediately. This
  is very likely the entire explanation for the crash loop and should be the
  first thing fixed, independent of any cloud-case-store work.
- **Auth scheme**: `AUTH_REQUIRED: "true"`, basic-auth front door
  (`BASIC_AUTH_USER`/`BASIC_AUTH_PASSWORD`) plus a platform-admin account
  (`PLATFORM_ADMIN_EMAIL`/`PLATFORM_ADMIN_PASSWORD`) for the admin UI/API,
  JWT-based session tokens (`JWT_SECRET_KEY`, `AUTH_ENCRYPTION_SECRET`).
  `PASSWORD_POLICY_ENABLED: "false"` and `CSRF_ENABLED: "false"` were
  deliberately relaxed for this tailnet-only, Bearer-fronted deployment
  (`deploy/contextforge.yaml` byline notes, 2026-08-03). Env var **names**:
  `CF_JWT_SECRET_KEY`, `CF_AUTH_ENCRYPTION_SECRET`, `CF_BASIC_AUTH_USER`,
  `CF_BASIC_AUTH_PASSWORD`, `CF_ADMIN_EMAIL`, `CF_ADMIN_PASSWORD`,
  `CF_ADMIN_PASSWORD_V1` (retired rotation), `CF_MCP_CLIENT_TOKEN` (a 1-year
  MCP-client JWT for `/servers/*/mcp` endpoints, generated 2026-07-08, exp
  2027-07 — this is almost certainly the credential a stdio→HTTP sidecar or a
  direct client would present). All confirmed present as **names only** in
  `C:\Users\matts\.secrets\contextforge.env`; no values printed.
- **Database**: `DATABASE_URL` is meant to point at "a dedicated ContextForge
  database on the ovh-files PostgreSQL cluster... never point this at
  Horizon's canonical application database" (`deploy/contextforge.yaml:47-49`
  comment). `CACHE_TYPE: database`. The old SQLite state
  (`/data/probata/volumes/contextforge`) is retained "for migration/rollback
  only" — ContextForge no longer authors state there post-PG-cutover. **This
  DSN is exactly the env var found unset above.**
- **What is registered now**: could not be queried — the app is not running,
  so `/health`, `/version`, `/gateways`, `/servers`, `/tools` all failed this
  session (connection timeout at the tailnet address). Once the app is
  healthy again, re-probe these before assuming any prior registration state
  still holds.
- **Public front door**: `deploy/contextforge.yaml` labels route
  `mcp.mitechconsult.com` via Traefik straight to ContextForge on 4444 with
  TLS — "ContextForge is THE MCP gateway (ADR-0025)." ADR-0025 itself
  (2026-06-13) also names LiteLLM as the model gateway; that half is
  superseded by ADR-0042 (LiteLLM retired, Portkey is the model gateway) —
  worth a doc-drift note the next time ADR-0025 is touched, not fixed here.
- **Prior "Context Forge auth test wiring" session**: a targeted grep for the
  phrase across `~/.claude/projects/**` hit raw transcript files under
  `C--Users-matts--claude-double-shot-latte` and
  `E--AI-Workspace-Projects-the-platform-workspace`, but parsing those
  session JSONL transcripts to confirm the specific prior finding was out of
  scope for this single-agent, read-only pass (would require reading large
  transcript files start-to-finish). Flagged as an open follow-up, not
  resolved here — grep hits recorded above so a future session can jump
  straight to them.
- **Consumers already wired to ContextForge in this repo**:
  - `deploy/exec.yaml:150-153`: `CF_GATEWAY_URL: http://contextforge:4444` —
    "Reach MCP servers ONLY through ContextForge, never graphiti's 8071
    directly."
  - `deploy/coolify-mcp.yaml`: the `coolify-mcp` server (14 tools) is "reached
    ONLY by ContextForge on the same box (registered as CF gateway
    `coolify-write`)" — i.e. it is itself a federated MCP peer registered
    into ContextForge's `/gateways`.
  - `deploy/workbench.yaml`: `CONTEXTFORGE_TOKEN` env, plus `MCP_SERVERS`
    populated only with "Portkey-published ContextForge virtual-server
    endpoints" — the Workbench never talks to ContextForge directly, only
    through Portkey (see §5).
  - `deploy/librechat.yaml`: `PORTKEY_PLATFORM_TOOLS_MCP_URL` — same pattern,
    ContextForge fronted by Portkey for this consumer too.

---

## 4. Deploying a stdio Node MCP server on the VPS — the exact pattern + steps

The console (`mcp-app/dist/server.js`) is a real, already-built artifact at
`C:\Users\matts\.claude\local-plugins\plugins\family-court-toolkit\mcp-app\dist\server.js`.
Evidence gathered directly from its source and `package.json`:

- **Current transport is stdio only.** `mcp-app/src/server.ts:6,142`:
  `import { StdioServerTransport } ...` and
  `await server.connect(new StdioServerTransport());`. No HTTP/SSE transport
  exists in the code today.
- **Dependencies** (`mcp-app/package.json`): `@modelcontextprotocol/sdk@1.30.0`,
  `@modelcontextprotocol/ext-apps@1.7.5`, `surrealdb@2.0.8`,
  `@surrealdb/node@3.0.3` (native `.node` bindings, esbuild-external per
  `build.mjs` — "cannot be bundled," must ship as real `node_modules`), `zod@4.4.3`.
- **The good news for cloud mode**: in **shared-server mode** (any
  `ws://`/`wss://`/`http(s)://` `CUSTODY_CASE_DB` URL), `store.ts` uses the
  plain `surrealdb` JS SDK's WS engine — the note at `store.ts:422-424`
  explicitly says remote URLs "must use the SDK's [own network engines]...
  not `@surrealdb/node`'s embedded-storage-only engines." So a cloud-mode
  deployment of the console genuinely does **not** need `@surrealdb/node`'s
  native bindings at all — it only needs the pure-JS `surrealdb` package. This
  simplifies the container: no native-binding platform-matching headache,
  just `surrealdb` + the MCP SDK + `zod`.
- **The SDK already has what's needed for HTTP.** Verified locally:
  `node_modules/@modelcontextprotocol/sdk/dist/{cjs,esm}/server/streamableHttp.js`
  exists in the installed 1.30.0 tree — `StreamableHTTPServerTransport` is
  available without adding any new dependency.

### Two viable deployment shapes

**Option A — add StreamableHTTPServerTransport to `server.ts` directly, ship
one container.** Pattern to follow: `deploy/docker/tool-gateway/` /
`deploy/docker/tools/` (existing Dockerfile-per-service under
`deploy/docker/`), plus a new `deploy/fct-console.yaml` compose file mirroring
`deploy/contextforge.yaml`'s shape (one service, `BIND_IP`-scoped port,
`networks: [probata]` for cross-app DNS, Watch Paths set at creation, tailnet-only
bind — never `0.0.0.0`). Steps:
1. Add an HTTP entrypoint in `mcp-app/src/server.ts` using
   `StreamableHTTPServerTransport` (stateless mode is simplest — no session
   store needed for a single-tenant console) alongside — not replacing —
   the existing stdio path, gated by an env var (e.g. `MCP_TRANSPORT=http`)
   so local stdio usage (Claude Code/Codex/OpenCode running the plugin
   locally) keeps working unchanged.
2. Write a `Dockerfile` under a new `deploy/docker/fct-console/` (Node LTS
   base, `npm ci --omit=dev`, copy `dist/`, `content/`, `skills/` per the
   task's own note that these must sit beside `server.js`).
3. New compose file `deploy/fct-console.yaml`: one service, env
   `CUSTODY_CASE_DB`/`CUSTODY_CASE_DB_USER`/`CUSTODY_CASE_DB_PASS` pointing at
   whichever cloud Surreal instance §7 decides on, `NVIDIA_API_KEY` (or
   route the embed call through Portkey instead — see §5), bind
   `${BIND_IP:-127.0.0.1}:<port>:<port>`, `networks: [probata]`.
4. New Coolify app, Docker Compose build pack, Watch Paths scoped to this one
   compose file + the `mcp-app/` subtree from the start (per the repo's
   standing "new app = set watch_paths at creation, always" rule — this
   exact repo has two live examples right now, ContextForge and Portkey,
   where the watch path drifted from the real file location; don't repeat it).
5. Register the resulting `http://<container-name>:<port>/mcp` (or whatever
   path the SDK's HTTP transport exposes) as a new ContextForge gateway peer
   (mirrors `coolify-write`'s existing registration pattern).

**Option B — keep the console stdio-only, front it with ContextForge's own
`mcpgateway.translate --stdio` sidecar.** IBM mcp-context-forge ships a
`translate` CLI that wraps a stdio MCP server and exposes it as SSE/HTTP. This
avoids touching `server.ts` at all, at the cost of a second container per
console instance (the sidecar) and one more moving part to keep alive. Given
this repo already has one live precedent for "stdio server wrapped as its own
HTTP-fronted app" (none currently — `coolify-mcp` in `deploy/coolify-mcp.yaml`
is natively HTTP via FastMCP, not a stdio-wrapped server), **Option A is the
closer fit to this repo's existing pattern** (every other MCP-ish service here
is natively HTTP) and avoids an extra container; Option B is faster to ship
if the owner wants zero TypeScript changes right now. Recommend Option A,
flagged as a judgment call in §7 only if the owner disagrees.

Either way, **tailnet-only bind, `BIND_IP` scoping, and Watch Paths set at
creation** are non-negotiable per this repo's own standing conventions
(`AGENTS.md` "Development and verification topology," and the
`deploy/*.yaml` header comments throughout).

---

## 5. Client-side consumption

- **Claude Code / plugin `.mcp.json` pattern, evidenced live in this repo's
  ecosystem**: the FCT plugin's own `.mcp.json`
  (`C:\Users\matts\.claude\local-plugins\plugins\family-court-toolkit\.mcp.json`)
  currently declares:
  ```json
  { "mcpServers": {
      "family-court-console": { "type": "stdio", "command": "node",
        "args": ["${CLAUDE_PLUGIN_ROOT}/mcp-app/dist/server.js"] },
      "courtlistener": { "type": "http", "url": "https://mcp.courtlistener.com/" }
  } }
  ```
  Moving to cloud means changing `family-court-console` from `type: "stdio"`
  to `type: "http"` (or `"sse"`) with a `url` pointing at the Portkey-published
  ContextForge virtual-server endpoint for this console, and (per the pattern
  already used in `deploy/workbench.yaml`/`deploy/librechat.yaml`) a `headers`
  block carrying a bearer credential via `${VAR}` substitution — e.g.
  `"headers": { "Authorization": "Bearer ${PORTKEY_FCT_MCP_TOKEN}" }`. This
  repo's own precedent for that exact shape is the top-level `.mcp.json`
  (`agno-docs`, `"type": "http"`, no auth needed there) plus the workbench/
  librechat pattern of `PORTKEY_*_MCP_URL` + `PORTKEY_MCP_API_KEY` env pairs.
- **Codex, OpenCode, Gemini CLI**: not independently verified this session
  (out of scope for a lightweight read-only pass), but all three support an
  HTTP/SSE MCP client config shape functionally equivalent to Claude Code's —
  the same ContextForge virtual-server URL + bearer header pattern applies;
  each tool's own config file format differs (Codex: `~/.codex/config.toml`
  `[mcp_servers.<name>]`; OpenCode: its own `opencode.json`/`~/.config/opencode`;
  Gemini CLI: `~/.gemini/settings.json` `mcpServers`) but the wire contract
  (streamable-HTTP or SSE, bearer header) is identical.
- **Tauri desktop app**: `app/src-tauri/` exists
  (`C:\Users\matts\.claude\local-plugins\plugins\family-court-toolkit\app\`),
  confirming a real Tauri shell alongside the MCP console. A Tauri
  frontend consuming the cloud console would do so the same way any
  browser-hosted client would: `fetch`/`EventSource` against the
  StreamableHTTP/SSE endpoint with a `Authorization: Bearer <token>` header —
  no different in kind from the Claude Code `.mcp.json` `headers` pattern,
  just issued from Rust/JS `fetch` instead of the harness's own MCP client.
  This session did not open `app/src-tauri/` further (out of scope; no code
  changes intended); flag for the implementer to confirm the existing Tauri
  app has no other transport assumption baked in before wiring it to the
  cloud endpoint.
- **Does ContextForge issue per-client JWTs?** `mcp-context-forge` supports
  per-team/per-user JWT issuance through its own auth system
  (`AUTH_REQUIRED`, `JWT_SECRET_KEY` in this deployment); the concrete,
  already-provisioned credential for this exact use case is
  `CF_MCP_CLIENT_TOKEN` — "1-year MCP client JWT for `/servers/*/mcp`
  endpoints" (`contextforge.env` comment, generated 2026-07-08). Whether that
  one shared token is reused across every harness or ContextForge is asked to
  mint one per client is an implementation choice, not something this
  session could verify live (app not running).
- **"m2m by REST"**: `MCPGATEWAY_ADMIN_API_ENABLED: "true"` is set on this
  deployment, meaning ContextForge's own admin/tool-invoke REST surface is
  turned on (typical mcp-context-forge admin API exposes `/tools`,
  `/resources`, `/prompts`, `/servers`, `/gateways`, `/health`, `/version`
  under the same auth as the admin UI). This session could not enumerate the
  live route list (app down). The alternative the task named — "the console
  exposing its own `/api/*`" — does not exist in the code today; `server.ts`
  only speaks MCP (stdio today, and per §4 potentially StreamableHTTP). Adding
  a bespoke `/api/*` REST surface to the console itself would be new work,
  not a reuse of anything already built, and would duplicate what
  ContextForge's admin API already offers for tool invocation — recommend
  REST-via-ContextForge over a bespoke console REST API unless there's a
  concrete reason the admin API can't serve that need (flagged, not decided,
  in §7).

---

## 6. Portkey — evidence

- **Coolify app**: `portkey`, uuid `z5787t1l7gl2zbrya8cxzapf`, image
  `portkeyai/gateway:1.15.2`, bind `${BIND_IP:-127.0.0.1}:8787:8787`, on
  `ovh-app` (`100.72.169.40`). **Status: `running:healthy`** (confirmed both
  by the Coolify API and a live probe this session).
- **Live probe results (this session, real calls)**:
  - `GET http://100.72.169.40:8787/` → `HTTP 200`, body `AI Gateway says
    hey!`, ~76ms.
  - `GET http://100.72.169.40:8787/v1/health` → `HTTP 400`,
    `{"status":"failure","message":"Either x-portkey-config or
    x-portkey-provider header is required"}` — **this OSS image has no
    dedicated health endpoint**; the compose file's own healthcheck hits `/`
    for exactly this reason (`deploy/portkey.yaml` / rendered compose:
    `node -e "fetch('http://localhost:8787/')..."`).
  - **One live chat probe** (owner-authorized): `POST /v1/chat/completions`
    with `x-portkey-config: {"provider":"groq","api_key":"$GROQ_API_KEY",
    "override_params":{"model":"llama-3.1-8b-instant"}}` → **HTTP 404**,
    `model_not_found` from Groq itself ("does not exist or you do not have
    access to it") in 1.03s. This confirms the gateway round-trips correctly
    to the real provider (a genuine provider-side error came back, not a
    gateway failure) but that `classify.json`'s pinned
    `llama-3.1-8b-instant` model id is now stale at Groq.
  - **Second chat probe**, Gemini: `x-portkey-config:
    {"provider":"google","api_key":"$GEMINI_API_KEY",
    "override_params":{"model":"gemini-flash-latest"}}` → **HTTP 200** in
    0.687s (empty `content` at `max_tokens: 8`, likely truncated before any
    visible token — not investigated further, out of scope). **Confirms an
    actual successful end-to-end call through the gateway.**
  - **One live embed probe**: `POST /v1/embeddings` with
    `configs/embed.json`'s primary target (`nvidia/nv-embed-v1`) → **HTTP
    410 Gone**: *"The model 'nvidia/nv-embed-v1' has reached its end of life
    on 2026-08-25T09:00:00Z and is no longer available."* This is a live,
    first-hand confirmation of the exact NIM retirement already recorded in
    this session's own memory (`milvus-etcd-corruption...` / NIM EOL note,
    2026-08-26) — **`deploy/docker/gateway/portkey/configs/embed.json` is
    currently broken** for its primary target and needs updating to a
    surviving NIM embedder (per that memory: `nvidia/nemotron-3-embed-1b`,
    2048-d, symmetric, or `nvidia/llama-nemotron-embed-vl-1b-v2`, needs
    `input_type`) before Graphiti's embed lane (the only current consumer of
    `embed.json`) can be trusted again. This is unrelated to the FCT/cloud
    task but was surfaced by the exact probe the task authorized.
- **Configs on disk** (`deploy/docker/gateway/portkey/configs/`): `chat.json`
  (glm-5.1 primary → Gemini 4-key loadbalance → Groq → Cerebras → OpenRouter
  → NVIDIA → Mistral, per `README.md`'s table), `classify.json` (cheap/fast
  triage, similar chain, Ollama Cloud primary), `embed.json` (NIM
  `nv-embed-v1`/`nv-embedcode-7b-v1`, dimension-locked 4096-d for Graphiti's
  Neo4j index — **now broken per above**), `embed-general.json` (Gemini
  4-key loadbalance primary, NVIDIA fallback — flagged inline as
  dimension-truncation-unverified), `graphiti-llm.json` (dedicated NVIDIA
  nemotron structured-output lane for Graphiti). Every config is a **stateless
  per-request JSON header** (`x-portkey-config`) — "Portkey itself does not
  read these from its own container env... confirmed `Mounts: []`."
- **Logging**: confirmed by direct observation this session — the OSS
  `portkeyai/gateway` image genuinely has **no built-in request logging or
  analytics surface**; its only "health" signal is the plain root response.
  What would provide logging, per the task's framing:
  1. **Portkey's hosted control plane** (`app.portkey.ai`) with a
     `PORTKEY_API_KEY` — this repo's self-hosted OSS gateway can optionally
     forward telemetry/traces to the hosted control plane for dashboards,
     cost tracking, and per-key rotation UI (this is the standard Portkey
     hosted-vs-self-hosted split; not independently re-verified against this
     exact pinned `1.15.2` image's docs in this session — flag as
     "documented capability, not live-verified here").
  2. **OpenTelemetry/log export** from the gateway container itself (stdout →
     a log drain; Coolify's server already has `logdrain_*` settings
     available per-server, currently all disabled on `ovh-app` per the
     `get_application` server-settings block returned this session).
  3. A thin **reverse-proxy/sidecar that logs `x-portkey-config` +
     response status** in front of 8787, mirroring the `graphiti-portkeyfix`
     nginx sidecar pattern already used elsewhere in this repo (README
     documents that exact sidecar-in-front-of-Portkey shape for a different
     problem — static header injection — but the same shape works for
     logging).
  Recommend (1) first since it needs zero new containers and the task
  explicitly named "Portkey hosted control plane w/ PORTKEY_API_KEY" as an
  intended direction; (2)/(3) are fallbacks if the owner doesn't want a
  hosted dependency.
- **Console embed lane through Portkey** (task's explicit ask): `store.ts`
  currently calls NIM **directly** — `EMBED_URL =
  "https://integrate.api.nvidia.com/v1/embeddings"` (`store.ts:120`),
  `EMBED_MODEL = "nvidia/nemotron-3-embed-1b"` (2048-d,
  `DEFAULT_EMBED_DIM = 2048`, matching this session's own memory that this is
  one of the two NIM embedders still alive post-EOL). To route this through
  Portkey: (a) point `EMBED_URL` at `http://<portkey-host>:8787/v1/embeddings`
  instead of NIM directly; (b) send `x-portkey-config` instead of a bare
  `Authorization: Bearer <NVIDIA_API_KEY>` header — a **new** config file
  (none of the existing five matches this model/dimension) such as
  `configs/embed-fct.json` pinning `nvidia/nemotron-3-embed-1b` with
  `input_type` handling if required by that model (per this session's memory,
  `nemotron-3-embed-1b` is symmetric, no `input_type` needed — simpler than
  the vl-1b-v2 alternative); (c) `store.ts`'s `embed()` function
  (`store.ts:290-...`) needs its header construction changed from
  `Authorization: Bearer` to `x-portkey-config: <JSON>` plus a Portkey virtual
  key/token env var, and its NVIDIA-key-discovery function
  (`findNvidiaApiKey`) either repointed at a Portkey token or left as a
  fallback for local/offline dev. This is a real code change, not
  configuration-only — flagged as implementation work, not done here.

---

## 7. Decisions only the owner can make

1. **Which SurrealDB is "the platform's existing SurrealDB on the VPS"?**
   Only the legacy parked instance (`100.119.96.29:8000`, ns `agno`/db
   `platform`, root/root by default, described elsewhere as "dead dependency,
   owner-gated deletion") is actually live. Reactivating it for new
   production FCT writes reverses that posture. Options: (a) reuse it with a
   new `fct` namespace, (b) stand up a dedicated, separate SurrealDB Coolify
   app for FCT only, (c) wait for the real governed-analytical Surreal
   (D-073/D-080) to be built and land FCT case data there once it exists.
2. **Does FCT case data belong in the same governed-analytical Surreal
   namespace space that D-073/D-080/D-145/D-151 reserve for the platform's
   own promoted, PG-reconciled evidence and horizon walks — or must it be
   architecturally separate?** This session's read is that they are
   different governance regimes (see §1); the owner may rule otherwise.
3. **Which stdio-to-HTTP path for the console** — Option A (add
   `StreamableHTTPServerTransport` to `server.ts` directly, one container) or
   Option B (`mcpgateway.translate --stdio` sidecar, two containers)? §4
   recommends A but this is a real fork in implementation work.
4. **Fix `exec-contextforge`'s three missing env vars
   (`CONTEXTFORGE_DATABASE_URL`, `CF_JWT_SECRET_KEY`,
   `CF_AUTH_ENCRYPTION_SECRET`) before or as part of this task?** It is
   currently crash-looping for a reason unrelated to FCT/cloud work, but
   ContextForge cannot serve anything to anyone until this is fixed.
5. **Portkey logging**: hosted control plane (`PORTKEY_API_KEY`, external
   dependency) vs. self-hosted log export/sidecar (more infra, no external
   dependency)? §6 recommends the hosted control plane as the lower-effort
   path; the owner may prefer to keep everything self-hosted.
6. **Per-client ContextForge JWTs vs. one shared `CF_MCP_CLIENT_TOKEN`**
   reused across every harness — a security/governance tradeoff, not a
   technical constraint.
7. **Whether to fix `deploy/docker/gateway/portkey/configs/embed.json`'s
   dead `nvidia/nv-embed-v1` primary target now** (unrelated to FCT but
   discovered live during the authorized probe, and it is actively broken).

---

## Order of operations (proposed, ≤ 12 steps — sequencing only, not authorization to execute)

1. Fix `exec-contextforge`'s three missing Coolify env vars
   (`CONTEXTFORGE_DATABASE_URL` pointing at a real dedicated Postgres DSN on
   the ovh-files cluster, `CF_JWT_SECRET_KEY`, `CF_AUTH_ENCRYPTION_SECRET`);
   correct its watch path to the real tracked location; redeploy; verify
   `/health` returns 200 live (not just "running" in Coolify).
2. Owner decision on §7.1/§7.2: which SurrealDB instance/namespace strategy
   FCT case data actually lands on.
3. Stand up (or repoint to) the decided SurrealDB target on the VPS,
   tailnet-only bind, root credentials rotated off `root`/`root` if the
   legacy instance is reused, `fct`/`case` ns/db provisioned.
4. Owner decision on §7.3: console HTTP transport approach (Option A vs B).
5. Implement the chosen transport in `mcp-app` (new HTTP entrypoint or
   `mcpgateway.translate` sidecar), keeping the existing stdio path working
   for local harnesses.
6. Build and deploy the console as its own tailnet-only Coolify app, Watch
   Paths scoped from creation, following the `deploy/contextforge.yaml`
   pattern.
7. Point the deployed console's `CUSTODY_CASE_DB`/`_USER`/`_PASS` at the VPS
   Surreal target from step 3 (env, not code changes — `store.ts` already
   supports this).
8. Register the console as a new ContextForge gateway peer (mirrors the
   `coolify-write` registration pattern); verify via ContextForge's own
   `/gateways`/`/servers`/`/tools` once healthy.
9. Publish a Portkey-fronted MCP endpoint for the console (mirrors
   `PORTKEY_PLATFORM_TOOLS_MCP_URL` for Workbench/LibreChat); mint or reuse a
   client credential per §7.6.
10. Update every harness's client config (`.mcp.json` type `stdio`→`http`,
    Codex/OpenCode/Gemini CLI equivalents, Tauri app's fetch target) to the
    new Portkey-published URL + bearer header.
11. Wire the console's `embed()` call through Portkey per §6's "console embed
    lane" plan (new `configs/embed-fct.json`, header change in `store.ts`),
    or explicitly defer this and keep the direct-NIM call if the owner
    prefers not to touch working code during the cloud migration.
12. Decide and wire Portkey logging (§7.5); live-verify end-to-end (Tauri app
    or a harness making a real case-store call through ContextForge through
    to the cloud Surreal instance) before calling this done — per this
    repo's own verify-before-claiming rule, "config accepted" is not "working."
