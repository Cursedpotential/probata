# ContextForge federation — desktop MCP inventory + grouping/migration proposal

> _Byline: Claude Code · Sonnet 5 · 2026-09-08 — read-only inventory for owner review; nothing changed._

**Scope:** owner request 2026-09-08 12:30 — inventory every MCP server configured on this
desktop, classify MOVE / STAY LOCAL / DROP, propose small purpose-grouped ContextForge virtual
servers, and give a migration order. Owner additions mid-task (12:36): add a secure-ingress
section for cloud-side consumers, and check whether ContextForge can serve as an OAuth 2.1
authorization server for claude.ai's custom-connector flow. **Everything below is read-only —
no config, deploy, or ContextForge state was changed.** Secret values were never printed; only
key names, lengths, and shapes.

Related prior art: `docs/planning/contextforge-adoption-list.md` (2026-07-31) already triaged
**claude.ai's built-in account-level cloud connectors** (Figma, LlamaParse, CourtListener,
Google Drive, etc.) against ContextForge adoption. That triage recommended several adoptions
(CourtListener named "strong CF adoption candidate") but **zero of it has been executed** — see
"ContextForge current state" below. This document inventories a different, overlapping layer:
the MCP servers configured in this desktop's own harness config files (Claude Code, OpenCode,
Codex, Gemini) plus the one custom remote connector we operate ourselves
(family-court-console).

---

## 1. ContextForge current state (live-probed)

- Container: `contextforge-k272znxpa4gh6drmolut723w-012816862914`, image
  `ghcr.io/ibm/mcp-context-forge:v1.0.4`, reachable at `http://100.72.169.40:4444` (tailnet).
- Minted a 30-minute admin JWT inside the container (`mcpgateway.utils.create_jwt_token`,
  `--username $PLATFORM_ADMIN_EMAIL --secret $JWT_SECRET_KEY`) — succeeded, 336-char token,
  valid 3-part JWT shape. Env var names read (values never printed): `PLATFORM_ADMIN_EMAIL`,
  `PLATFORM_ADMIN_PASSWORD`, `PLATFORM_ADMIN_FULL_NAME`, `JWT_SECRET_KEY`, `CF_JWT_SECRET_KEY`,
  `AUTH_ENCRYPTION_SECRET`, `CF_AUTH_ENCRYPTION_SECRET`, `BASIC_AUTH_USER/PASSWORD`,
  `CF_BASIC_AUTH_USER/PASSWORD`, `CF_ADMIN_EMAIL/PASSWORD`, `AUTH_REQUIRED`,
  `MCPGATEWAY_ADMIN_API_ENABLED`, `MCPGATEWAY_UI_ENABLED`.
- `GET /gateways`, `/servers`, `/tools`, `/resources`, `/prompts` all returned **HTTP 200 with
  an empty array (`[]`)**.

**Finding — doc drift:** ADR-0046 (accepted 2026-08-09, D-042) describes ContextForge as
already holding "14 SBV facade tools, Graphiti virtual server per ADR-0037." The live instance
has **zero gateways, zero servers, zero tools registered**. Either that registration was lost
(container restart, image upgrade, or the DB volume for ContextForge's own state was reset) or
it was never actually done and the ADR text describes an intended state that was never carried
out. This is exactly the class of drift the owner's doc-drift rule flags — recommend a follow-up
that either re-registers those 14 SBV tools + the Graphiti virtual server, or corrects ADR-0046
to say "designed, not yet registered." Not fixed here (read-only scope).

- Version: v1.0.4 now; owner is upgrading to v1.0.10. Could not find v1.0.10-specific changelog
  detail confirming or denying new inbound-auth capabilities (see §5 ingress section) — flagged
  as an open item to check at upgrade time, not resolved here.

---

## 2. Inventory — every MCP server configured on this desktop

### 2a. Claude Code (`C:\Users\matts\.claude.json`)

| Name | Scope | Transport | Target | Runtime | Env vars (names) | Ours/3rd-party | Talks to |
|---|---|---|---|---|---|---|---|
| `n8n-docs` | top-level (global) | http | `https://docs.n8n.io/~gitbook/mcp` | — | none | 3rd-party | n8n's own docs SaaS |
| `n8n-mcp` | top-level (global) | http | `https://n8n.mitechconsult.com/mcp-server/http` | — | none (auth via header, not in this file) | **Ours** (self-hosted n8n) | ovh-files VPS, tailnet-fronted, public TLS |
| `agno-docs` | project: `…/Agno-MCP-Platform` (junction to probata) | http | `https://docs.agno.com/mcp` | — | none | 3rd-party | Agno's docs SaaS |
| `surrealdb` | project: `…/Agno-MCP-Platform` | http | `https://mcp.surrealdb.com` | — | none | 3rd-party | SurrealDB Inc.'s hosted docs MCP (**not** our own SurrealDB instance) |
| `cocoindex-code` | project: `…/Agno-MCP-Platform` | stdio | `ccc mcp` | binary (`ccc`) | none | Ours (private dev tool) | local CocoIndex v1 index of this desktop's checkout |
| `tavily` | project: `C:/Users/matts` | http | `https://mcp.tavily.com/mcp` | — | none | 3rd-party | Tavily search SaaS |

Live health: **`n8n-mcp` is currently failing to connect** (`CONNECT_TIMEOUT` — "Version
negotiation probe timed out after 5000ms", reported this session). That is a live incident
independent of this migration proposal and should be checked before anything is repointed
through it.

### 2b. Claude Code plugins (only `enabledPlugins: true` in `settings.json`, 31 enabled)

Of the 31 enabled plugins, only four ship a `.mcp.json`:

| Plugin (marketplace) | Server name(s) | Transport | Target | Runtime | Env vars | Ours/3rd-party | Tool count (observed) |
|---|---|---|---|---|---|---|---|
| `context7@claude-plugins-official` | `context7` | http | `https://mcp.context7.com/mcp` | — | `CONTEXT7_API_KEY` (header) | 3rd-party | 2 (`resolve-library-id`, `query-docs`) |
| `cf@casebible-local` | `cloudflare-api`, `cloudflare-docs`, `cloudflare-bindings`, `cloudflare-builds`, `cloudflare-observability` | http ×5 | `mcp.cloudflare.com`, `docs.mcp.cloudflare.com`, `bindings.mcp.cloudflare.com`, `builds.mcp.cloudflare.com`, `observability.mcp.cloudflare.com` | — | none in file (OAuth per-connector) | 3rd-party (Cloudflare's own hosted MCPs) | `cloudflare-docs` exposes 2 unauth'd tools; the other four gate everything behind `authenticate`/`complete_authentication` until OAuth completes |
| `coolify-write@casebible-local` | `coolify` | stdio | `${CLAUDE_PLUGIN_ROOT}/.venv/Scripts/python.exe scripts/server.py` | python/venv | `PYTHONUTF8`, `COOLIFY_ENV_FILE` (points at `C:\Users\matts\.secrets\coolify-ionos-api.env`, which itself defines `COOLIFY_BASE_URL`, `COOLIFY_BASE_URL_PUBLIC_FIREWALLED`, `COOLIFY_FQDN`, `COOLIFY_API`, `COOLIFY_API_TOKEN`, `COOLIFY_VERSION`) | **Ours** | **39 tools** (observed this session: create/delete/start/stop/restart application/database/service, deployments, envs, infra overview, port-collision check, raw `coolify_api` escapee) — full write access to the Coolify control plane |
| `family-court-toolkit@casebible-local` | `family-court-console` | stdio | `node ${CLAUDE_PLUGIN_ROOT}/mcp-app/dist/server.js` | node | none in stdio mode | **Ours** | **27 tools** (observed: case_docket, case_eval, case_evidence_log, case_export, case_factor_map, case_facts, case_graph, case_import, case_memo, case_put, case_query, case_reference, case_search, case_source, case_status, case_summary, case_timeline, build_chronology, audit_sources, calculate_planning_date, court_language_review, get_checklist, get_packet_plan, open_dashboard, route_issue, search_guide, survival_guide, plus healthcheck) |
| `family-court-toolkit@casebible-local` | `courtlistener` | http | `https://mcp.courtlistener.com/` | — | OAuth | 3rd-party | 2 visible pre-auth (`authenticate`, `complete_authentication`); real search tools unlock post-OAuth |

**Same source, two transports:** `family-court-console` already has an **HTTP mode**
(`MCP_TRANSPORT=http`) deployed as its own Coolify app — `deploy/family-court-console.yaml` and
`deploy/docker/family-court-console/` — running tailnet-only at `100.91.190.107:8765/mcp`,
bearer-token gated, talking to `surreal-case` over the `probata` docker network. The stdio
form above is what a desktop Claude Code session launches locally; the HTTP form is what
already exists for cloud/remote consumption. **This is the strongest MOVE candidate in the
whole inventory** — the work to make it remotely reachable is already done; only ingress (§5)
is missing.

**`case-bible@casebible-local` is enabled but ships no `.mcp.json` at all** — it is
commands/skills/hooks/local Python tools (`cb_*` scripts) only, no MCP server. It is not a
federation candidate; nothing to move. (Relevant to the owner's mid-task question about a
"second candidate" — case-bible turns out not to be one.)

The other 26 enabled plugins (`claude-reflect`, `superpowers`, `remember`, `duckdb-skills`,
`memsearch`, `typescript-lsp`, `mcp-server-dev`, `session-report`, `code-review`,
`agent-sdk-dev`, `pyright-lsp`, `recall-skill`, `hyperfocus`, `plugin-dev`, `frontend-design`,
`context-mode`, `capability-discovery`, `semantic-skill-router`, `crewai`, `tanstack`,
`llm-probes`, `portkey`, `codebase`, `ops`, `n8n`, `think`) have no `.mcp.json` — skills/agents
only.

### 2c. OpenCode (`C:\Users\matts\.config\opencode\opencode.json`, global — no project-level
`opencode.json` files found)

| Name | Transport | Target | Runtime | Env vars | Enabled | Ours/3rd-party | Talks to |
|---|---|---|---|---|---|---|---|
| `@zilliz/claude-context-mcp` | local | `npx @zilliz/claude-context-mcp@latest` | node/npx | none seen | true | 3rd-party client, Ours' data | Zilliz Cloud (memsearch's live backend, free tier `in03-834f340cad0f74d`) |
| `chrome-devtools` | local (built-in) | — | — | — | true | 3rd-party | local Chrome instance |
| `context-mode` | local | `context-mode` binary | npm global | none | true | 3rd-party (npm pkg) | desktop-local |
| `midpage` | remote | `https://app.midpage.ai/mcp` | — | — | **false** | 3rd-party | Midpage legal-research SaaS |
| `morph-mcp` | local | `npx @morphllm/morphmcp` | node/npx | `ENABLED_TOOLS`, `MORPH_API_KEY` | true | 3rd-party | Morph LLM API, edits local files |
| `n8n-mcp` | remote | `https://traceiq.app.n8n.cloud/mcp-server/http` | — | — | **false** | 3rd-party SaaS (**n8n Cloud**, not our self-hosted n8n) | n8n Cloud |
| `sequential-thinking` | local | `cmd /c npx -y @modelcontextprotocol/server-sequential-thinking` | node/npx | none | true | 3rd-party | desktop-local |
| `browsermcp` | local | `npx @browsermcp/mcp@0.1.3` | node/npx | none | true | 3rd-party | local browser |
| `agno-gateway` | remote | `http://ovh-app:4444/servers/2c60f39fad3c494a9353970d9bf0573a/mcp` | — | — | true | **Ours (intended)** | **Broken from this desktop** — `ovh-app` is a Docker-network-internal hostname, not tailnet/DNS-resolvable from the desktop; and the referenced virtual-server UUID does not exist in ContextForge's current (empty) `/servers` list. This entry almost certainly belongs to the VPS-side OpenCode instance (`opencode-server` on NIM, per memory), not this desktop's OpenCode. |
| `graphiti` | remote | `http://100.119.96.29:8071/mcp` | — | — | true | **Dead** | `100.119.96.29` is a retired host IP (PG moved off it 2026-08-02 per memory) **and** Graphiti itself is retired platform-wide (D-070, AGENTS.md). This entry cannot work and should be removed. |

### 2d. Codex (`C:\Users\matts\.codex\config.toml`, `[mcp_servers.*]`)

| Name | Transport | Target | Runtime | Env vars | Enabled | Ours/3rd-party |
|---|---|---|---|---|---|---|
| `context7` | http | `mcp.context7.com/mcp` | — | — | true | 3rd-party (dup of Claude Code plugin) |
| `mcp-sequentialthinking-tools` | stdio | `npx mcp-sequentialthinking-tools` | node | — | true | 3rd-party (variant, not identical to OpenCode's) |
| `mcp-structured-memory` | stdio | `npx @nmeierpolys/mcp-structured-memory` | node | — | true | 3rd-party, desktop-local |
| `morph-mcp` | stdio | `npx @morphllm/morphmcp` | node | `ENABLED_TOOLS`, `MORPH_API_KEY` | true | 3rd-party (dup of OpenCode's) |
| `osgrep` | stdio | `osgrep mcp` | binary | — | **false (disabled)** | desktop tool |
| `context-mode` | stdio | `node .../context-mode/cli.bundle.mjs` | node | — | true | 3rd-party (dup) |
| `agentos` | http (bearer) | `http://100.72.169.40:8000/mcp` | — | `bearer_token_env_var = OS_SECURITY_KEY` | true | **Ours** — the AgentOS MCP door (`server/api/mcp_main.py`, ADR-0046's horizon-bound universal exposure contract) |
| `node_repl` | stdio | Codex's own bundled node runtime | node | several `NODE_REPL_*`/`SKY_CUA_*`/`BROWSER_USE_*` (Codex's own computer-use sandbox) | true | Codex-internal, not a platform MCP |
| `n8n-docs` | http | `docs.n8n.io/~gitbook/mcp` | — | — | true | 3rd-party (dup) |
| `n8n-mcp` | http | `n8n.mitechconsult.com/mcp-server/http` | — | `http_headers.Authorization` (a **literal JWT is written directly into `config.toml`**, not referenced via an env var) | true | **Ours** (dup of Claude Code top-level entry) |
| `tavily` | http | `mcp.tavily.com/mcp` | — | — | true | 3rd-party (dup) |
| `cloudflare`, `cloudflare-docs`, `cloudflare-bindings`, `cloudflare-builds`, `cloudflare-observability` | http ×5 | same CF-hosted URLs as the `cf` plugin | — | — | true | 3rd-party (dup ×5 of the `cf` plugin's servers) |
| `n8n-mcp-stdio` | stdio | `cmd /c npx -y n8n-mcp` | node | `DISABLE_CONSOLE_OUTPUT`, `LOG_LEVEL`, `MCP_MODE` | true | 3rd-party npm package (generic n8n knowledge tool — no `N8N_API_URL`/key seen, so likely not wired to our instance; overlaps `n8n-docs`) |
| `glide-data-grid` | http | `docs.grid.glideapps.com/~gitbook/mcp` | — | — | true | 3rd-party, unrelated to this platform — looks like leftover clutter |

**Security note (not printed further, no value shown):** the `n8n-mcp` entry in
`config.toml` stores its bearer credential as a **literal JWT string in the config file**
rather than an env-var reference (`${VAR}`), unlike every other credentialed entry in the same
file (which all use `${VAR}` or `*_env_var` indirection). Per the owner's 2026-08-12 amendment,
transcript exposure isn't itself an incident, but a plaintext-on-disk token in a config file is
worth tightening to the same `${N8N_MCP_TOKEN}` pattern used elsewhere — flagged, not fixed.

### 2e. Gemini (`C:\Users\matts\.gemini\settings.json`)

| Name | Transport | Target | Env vars | Ours/3rd-party |
|---|---|---|---|---|
| `sequential-thinking` | stdio | `cmd /c npx @modelcontextprotocol/server-sequential-thinking` | — | 3rd-party (dup) |
| `morph-mcp` | stdio | `npx @morphllm/morphmcp` | `ENABLED_TOOLS`, `MORPH_API_KEY` | 3rd-party (dup) |

### 2f. `.mcp.json` files under `E:\AI_Workspace` (Glob, excluding node_modules/.git/to_be_deleted/_stale)

Outside `dev-resources/Archives/` (donor/reference material, explicitly out of scope per
`AGENTS.md` — "reference-only… never revive an archived iteration wholesale") the live ones are:

| Path | Content | Note |
|---|---|---|
| `probata/.mcp.json` | `agno-docs` (http, dup of Claude Code project entry) | live, minimal |
| `probata/.claude/worktrees/affectionate-carson-fccaa9/.mcp.json` | copy of the above | worktree artifact, not a distinct config |
| `probata/.claude/worktrees/suspicious-satoshi-73d069/.mcp.json` | copy of the above | worktree artifact |
| `probata/modules/vestigia/traceiq-rebuild/.mcp.json` | malformed/placeholder (`{"servers": ...}` — not a `mcpServers` map, parsed as a single stray key named "servers") | not a working config; not investigated further (out of scope — vestigia has its own AGENTS.md) |
| `probata/modules/advocatio/docs/planning/original-context/.../toolkit-package/plugin/.mcp.json` (×2) | donor content from a prior toolkit package, nested under "original-context" | archival/reference only, not live config |

---

## 3. Classification

### MOVE (already HTTP, or cleanly wrappable, and only needs tailnet/cloud reach)

| Server | Why it moves cleanly |
|---|---|
| **`family-court-console`** | Already has an HTTP mode and a deployed Coolify app (`deploy/family-court-console.yaml`, tailnet `100.91.190.107:8765/mcp`, bearer-gated). Only needs a ContextForge peer-gateway registration + virtual server. **This is the flagship migration** — do this first. |
| **`n8n-mcp` (self-hosted, `n8n.mitechconsult.com`)** | Already HTTP, already public-TLS via Traefik/Coolify. Fix the live `CONNECT_TIMEOUT` first, then register as a ContextForge peer gateway so every harness stops duplicating its own copy (currently duplicated in Claude Code top-level + Codex). |
| **`agentos`** (AgentOS MCP door, `100.72.169.40:8000/mcp`) | Already HTTP + bearer (`OS_SECURITY_KEY`). Horizon-binding (ADR-0046 rule 6) is enforced server-side regardless of transport, so proxying it through ContextForge doesn't weaken the invariant. |
| **`coolify-write`** | stdio today, but it's a thin Python wrapper around the Coolify REST API — trivially rehostable as an HTTP service on the VPS (or wrapped with `mcpgateway.translate` stdio→SSE) since its only local dependency is the `.env` file path, which can move to a VPS-side secret. **Caveat:** 39 tools include full create/delete/stop on every Coolify app/database/service — this is the single most destructive tool surface in the whole inventory. Recommend a dedicated, narrowly-scoped virtual server + its own bearer token/audience, not bundled into a general "infra" group with looser access. |
| **`context7`, `cloudflare-*` (5), `tavily`, `courtlistener`** | All already HTTP, all third-party, all duplicated 2-4× across harnesses today. Federating them through ContextForge as peer gateways doesn't change what they are (we're not "moving" someone else's SaaS), but it collapses N duplicated per-harness configs into one virtual-server URL per group — the actual efficiency win the owner asked about ("grouping the tools efficiently"). |
| **`n8n-docs`** | Third-party, HTTP, low-risk, worth folding into the same `dev`/`docs` group as context7 for the same de-dup reason. |

### STAY LOCAL (desktop-file/process-bound; explain why)

| Server | Why it stays |
|---|---|
| `cocoindex-code` (`ccc mcp`) | Indexes this desktop's local checkout via a persistent local DuckDB index; also explicitly a private dev-assistance tool never to be surfaced in product architecture (AGENTS.md). Moving it means running `ccc` against a remote checkout, which is a different project, not a migration. |
| `chrome-devtools`, `browsermcp` | Automate the local Chrome browser on this machine. No remote equivalent target. |
| `context-mode` | Desktop CLI tool operating on local project state. |
| `morph-mcp` | Edits files on the local filesystem (`edit_file`); the API call is cloud (Morph), but the effect is local-file-bound. Federating the API call doesn't help since the tool still needs local filesystem access from wherever it runs. |
| `mcp-structured-memory`, `sequential-thinking` | Small, stateless-ish reasoning/memory utilities with no evident multi-consumer value; low migration ROI, and `sequential-thinking` in particular benefits from low round-trip latency as a thinking scratchpad. |
| `node_repl` (Codex) | Codex's own bundled computer-use/browser sandbox — not a platform MCP server at all. |
| `@zilliz/claude-context-mcp` | Indexes local repo code for OpenCode's code-search; backend is Zilliz Cloud but the indexing target is this desktop's checkout. |
| `case-bible` plugin | Not an MCP server (no `.mcp.json`) — commands/skills/hooks/local Python tools bound to local filesystem paths and `.secrets/` files. Nothing to move. |

### DROP / DEDUP

| Server | Reason |
|---|---|
| `graphiti` (OpenCode, `100.119.96.29:8071/mcp`) | Points at a retired host IP for a platform-retired service (D-070). Dead config, remove. |
| `agno-gateway` (OpenCode) | Points at a Docker-internal hostname unreachable from this desktop and a ContextForge virtual-server UUID that does not currently exist. Either fix once real virtual servers are registered, or remove until then. |
| `n8n-mcp` (OpenCode, `traceiq.app.n8n.cloud`) | Legacy reference to n8n **Cloud** (disabled) — superseded by the self-hosted `n8n.mitechconsult.com` instance already configured elsewhere. Remove to avoid confusion with the real one. |
| `n8n-mcp-stdio` (Codex) | Generic third-party npm n8n-knowledge tool, not wired to our instance (no API URL/key env seen), overlapping `n8n-docs`. Low value, redundant. |
| `glide-data-grid` (Codex) | Unrelated third-party docs MCP with no evident tie to this platform. Clutter. |
| Duplicated third-party entries (`context7` ×2, `tavily` ×2, `cloudflare-*` ×2 sets, `sequential-thinking` ×3, `morph-mcp` ×3, `n8n-docs` ×2, `n8n-mcp` self-hosted ×2) | Not wrong individually, but each is configured separately in 2-4 harnesses. Federating through ContextForge (see §4) removes the duplication — each harness config shrinks to one gateway URL. |
| `.mcp.json` copies inside `.claude/worktrees/*` | Artifacts of `git worktree` copying the repo root; not distinct configuration, no action needed beyond normal worktree cleanup per the existing stale-worktree hygiene rule. |

---

## 4. Proposed virtual servers

ContextForge virtual servers are "MCP Servers composed of Tools, Resources, and Prompts from
multiple [registered peer] servers" (`docs/faq`) — you register each real MCP server under
**Gateways**, then hand-pick tools into a **Server** (the virtual bundle) by tool ID. No
published hard cap on tools-per-virtual-server was found in the docs pulled via Context7;
treat "small, purpose-grouped" as an operational choice (context-window and blast-radius
hygiene), not a platform limit. Six groups, sized from what's actually in this inventory:

| Group | Purpose | Member servers | Tool count (approx.) | Consumers |
|---|---|---|---|---|
| **`case-work`** | Family-court case operations + legal research | `family-court-console` (27), `courtlistener` (unlocks post-OAuth; CourtListener plugin currently shows 16 tools once authenticated per the 2026-07-31 triage) | ~27-43 | Claude Code desktop, **claude.ai custom connector** (the owner's named worked example — see §5), Workbench Ops Copilot |
| **`infra-ops`** | Platform infrastructure control | `coolify-write` (39, isolate its own bearer/audience per §3 caveat) | 39 | Claude Code desktop/devbox only — **not** claude.ai (too destructive for a browser-reachable connector without very tight Access policy) |
| **`platform-mcp`** | The platform's own evidence/agent surface | `agentos` (AgentOS MCP door, tool count not enumerated — ADR-0046's progressive-disclosure quad means it may expose only 4 meta-tools: `search_tools/describe_tool/invoke_tool/get_ref`, not a flat catalog) | 4 (if the progressive-disclosure contract holds) or more | OpenCode server, Workbench Ops Copilot, n8n, crewai |
| **`dev-docs`** | Documentation/reference lookups | `context7` (2), `n8n-docs` (3), `agno-docs` (3, if federated) | ~8 | Claude Code, OpenCode, Codex, Gemini — collapses 4 separate per-harness configs into one |
| **`cloud-infra`** | Cloudflare account operations | `cloudflare-api`, `cloudflare-docs`, `cloudflare-bindings`, `cloudflare-builds`, `cloudflare-observability` | ~10 unauth'd + more post-OAuth | Claude Code, Codex — same de-dup logic as `dev-docs`, kept separate because these need their own Cloudflare OAuth, not bundled with generic docs |
| **`automation`** | Workflow orchestration | `n8n-mcp` (self-hosted, tool count unknown — currently failing to connect, must be fixed first) | unknown | n8n itself (self-referential ops), Workbench, crewai |

Not grouped yet (kept out until a decision is made): `graphiti`/`agno-gateway` (dead, §3),
`tavily` (could join `dev-docs` as a 7th light member, or get its own `search` group if usage
grows), `memory-recall`-shaped group (memsearch/Graphiti — skipped because memsearch has no
MCP server of its own and Graphiti is retired platform-wide, so there is currently nothing real
to put in a "memory" group despite it being a natural-sounding bucket).

---

## 5. Secure ingress for cloud-side MCP consumers

### 5a. Cloud-side vs tailnet-side consumers

| Consumer | Cloud or tailnet? | Notes |
|---|---|---|
| **claude.ai (web/desktop app) custom connector** | **Cloud** — Anthropic's infrastructure calls the connector URL directly; it is never on the tailnet | The concrete, named use case (owner 12:36): reach `family-court-console` via a custom connector |
| claude.ai's own built-in account connectors (Figma, LlamaParse, CourtListener, etc.) | Cloud | Separate mechanism — Anthropic-hosted, not ours to front; see the 2026-07-31 adoption-list doc |
| Codex CLI, Claude Code desktop, Gemini CLI (this machine) | Tailnet-side | Reach VPS services directly over Tailscale; no public ingress needed |
| OpenCode (this machine) | Tailnet-side | Same |
| `opencode-server` on NIM (VPS-hosted, per memory) | Tailnet-side | Runs on-box; the `agno-gateway` entry in this desktop's OpenCode config appears to actually belong here (§2c/§3) |
| n8n self-hosted (`n8n.mitechconsult.com`) | Tailnet-side, already public-TLS via existing Traefik/Coolify route | Not "cloud" in the sense of a third party — it's our own VPS app, just already internet-facing by design |
| n8n **Cloud** (`traceiq.app.n8n.cloud`) | Cloud, but currently **disabled** in config | If ever re-enabled, it would be a cloud consumer needing the same ingress treatment |
| ChatGPT/Codex cloud (hosted, not the local Codex CLI) | Cloud | Not currently configured anywhere found on this desktop — no evidence of an active cloud-hosted Codex/ChatGPT connector into our infra |
| Portkey | Cloud (SaaS gateway, per AGENTS.md stack line) | Portkey is an **outbound** model-gateway call from our services, not an inbound MCP consumer — doesn't need MCP ingress, mentioned for completeness only |

### 5b. The standing constraint

Owner ruling 2026-09-07 (commit `7d4583d`): tailnet-only `DOCKER-USER` forwarding on both VPS
hosts — **"nothing reachable from the public internet on the hosts."** Any ingress design that
opens an inbound host port (a public Traefik route with its own TLS cert bound to a host IP)
conflicts with that ruling outright and would need an explicit, separate owner carve-out. That
disqualifies "Traefik public route on the host" as the default answer here — it's technically
possible but requires re-opening a settled decision, so it is listed for completeness but not
recommended.

### 5c. What ContextForge itself supports (verified via Context7 docs, `/ibm/mcp-context-forge`)

- ContextForge's OAuth 2.0 support — including **Dynamic Client Registration (RFC 7591)** and
  **PKCE (RFC 7636)** — is all **client-side**: it's how ContextForge itself authenticates
  *outbound* to upstream MCP servers/gateways that require OAuth (e.g., the Box example in its
  docs, or GitHub's MCP server). The admin UI's "Add New MCP Server or Gateway" auth-type field
  (Basic / Bearer / OAuth2 / Custom Headers) governs that same outbound relationship.
- For **inbound** auth — i.e., how *callers of ContextForge itself* (including a
  `mcpgateway.wrapper` stdio bridge documented for "Claude Desktop") authenticate — every
  example in the docs uses a **static bearer JWT** (`MCPGATEWAY_BEARER_TOKEN`) or Basic Auth.
  No evidence was found, in the pulled docs or in a search for the v1.0.10 changelog, that
  ContextForge exposes itself as an **OAuth 2.1 authorization server** with protected-resource
  metadata (RFC 9728) or dynamic client registration for its *own* inbound clients. **This is
  the load-bearing finding for the whole ingress design:** ContextForge alone cannot hand
  claude.ai a working Authorization URL/Token URL — something else has to sit in front of it to
  play that role, or the connector has to use static-header auth instead of OAuth.
- Re-check this specifically after the v1.0.10 upgrade — I could not confirm or rule out a
  change here from the changelog search alone.

### 5d. What claude.ai's custom connector flow actually requires (verified via WebSearch,
current as of Sep 2026)

- Must be reachable over **Streamable HTTP or SSE** at a **public HTTPS URL** — Claude's
  connector calls originate from Anthropic's cloud, never from the user's machine, so
  tailnet-only reachability is not sufficient by itself.
- The connector UI (Settings → Connectors → Add custom connector, or Org settings for
  Team/Enterprise) has long supported **OAuth 2.0 fields**: Authorization URL, Token URL,
  Client ID, Client Secret — this is the universally-available, documented path.
- **Static header auth (`Authorization`/`x-api-key`) exists in beta** ("static_headers") but
  multiple open GitHub issues against `anthropics/claude-ai-mcp` (#112, #411, #644, #155)
  describe it as inconsistent — some orgs' UI only shows the OAuth fields, and one reported bug
  has the OAuth flow firing even when a static header was configured, using the header name as
  a bogus `client_id`. **Treat static-header auth as not reliably available; design for OAuth
  as the primary path**, with static-header as an opportunistic fallback to re-test once this
  org's UI is checked directly.
- Authless remote MCP servers are explicitly supported by claude.ai, but that is not
  appropriate for family-court case data.

### 5e. Recommendation

**Cloudflare Tunnel (outbound-only `cloudflared`) + Cloudflare Access, not a public Traefik
route.**

- `cloudflared` makes only outbound connections from the VPS to Cloudflare's edge — it opens no
  inbound port on the host, so it fully satisfies the 2026-09-07 DOCKER-USER firewall rule
  without needing a carve-out. (Confirmed no `cloudflared` container currently exists on
  `100.72.169.40`; this would be new infra. Separately, the new untracked `deploy/docker/
  tsnet-front/` work in this repo is a **tailnet-only** identity helper — no `EXPOSE`, tsnet
  listener only — it does not provide public reachability and is not a substitute for this.)
- Domain: `mitechconsult.com` is already the live zone (`n8n.mitechconsult.com`,
  `family-court.int.mitechconsult.com` already exist) — propose a new subdomain, e.g.
  `mcp.mitechconsult.com`, routed through the tunnel to ContextForge's specific virtual-server
  path (`/servers/<case-work-uuid>/mcp`), **not** the whole gateway or its admin UI.
- Because ContextForge is not itself an OAuth authorization server (§5c), the OAuth
  Authorization URL/Token URL claude.ai's UI wants should be served by **Cloudflare Access in
  its "SaaS application / OIDC provider" mode** — Access already fronts other apps in this
  stack conceptually (Authentik plays that forwardauth role for `family-court-console`'s
  *prepared-but-unopened* Traefik route today) and a CF account with the wrangler/CF plugin
  already present on this desktop means no new account is needed. Register one SaaS
  application in Access for the `case-work` connector; Access issues the Client ID/Secret and
  the Authorization/Token endpoints claude.ai's UI asks for. **DCR is not required** — claude.ai
  takes a manually-registered static Client ID/Secret, which is exactly what Access's SaaS-app
  mode produces.
- **Open item, not resolved by documentation alone:** how the token Access issues to claude.ai
  gets accepted as valid by ContextForge's own `AUTH_REQUIRED` bearer check is a real
  integration detail — Access's SaaS-OIDC mode is designed for a browser handoff into a
  third-party app's own session system, not automatically as a bearer ContextForge will
  recognize. Two ways to close that gap, both needing hands-on validation before build:
  (a) treat Access as a pure network/identity perimeter (nothing unauthenticated ever reaches
  the tunnel) and pair it with a long-lived per-connector ContextForge bearer token issued once
  and pinned into claude.ai's connector as a static header, if this org's UI actually offers
  that option (re-test §5d); or (b) put a minimal token-exchange shim behind the tunnel that
  validates Access's JWT and mints a ContextForge bearer on success. **Recommend (a) first** —
  it needs no new code — and fall back to (b) only if the static-header UI path proves
  unavailable on this account.
- What it needs to build: the `mitechconsult.com` zone (exists), a Cloudflare account (exists —
  CF plugin/`wrangler` already on this desktop), secrets to create (names only, not values):
  `CLOUDFLARE_TUNNEL_TOKEN`, a Cloudflare Access "SaaS app" Client ID/Secret pair for the
  `case-work` connector, and a dedicated ContextForge bearer JWT scoped to that one virtual
  server (mint it the same way this session minted its own admin token, with a narrower
  username/claim if ContextForge supports per-token scoping — **not confirmed either way in
  the docs pulled; check at build time**).
- **Worked example, end to end:** `claude.ai custom connector` → Cloudflare Tunnel
  (`cloudflared`, outbound-only, running on ovh-files) → Cloudflare Access (OIDC gate, issues
  the OAuth fields claude.ai's UI wants) → ContextForge `case-work` virtual server
  (`/servers/<uuid>/mcp`) → `family-court-console` (`100.91.190.107:8765/mcp`, already
  bearer-gated, already talking to `surreal-case`).
- `case-bible` was checked as the owner-suggested "second candidate" and **is not an MCP
  server** (§2b/§3) — nothing to route through this design for it today.

---

## 6. Migration order (cheapest + highest-value first)

1. **Fix `n8n-mcp`'s live `CONNECT_TIMEOUT`** before touching anything else that depends on it
   being reachable. (Prerequisite: none beyond diagnosing the self-hosted n8n's `/mcp-server/
   http` endpoint.)
2. **Register `family-court-console` as a ContextForge peer gateway, build the `case-work`
   virtual server.** Prerequisites: ContextForge admin token (already proven mintable this
   session), the app's existing bearer token (`MCP_BEARER_TOKEN` — already set per its Coolify
   env). Client-side change: none yet for existing Claude Code stdio users (they keep the
   fallback in `family-court-toolkit`'s `.mcp.json`); this step alone doesn't touch any client
   config, it just makes the virtual server exist.
3. **Stand up the Cloudflare Tunnel + Access ingress (§5e)** so `case-work` is reachable from
   claude.ai. Prerequisites: `CLOUDFLARE_TUNNEL_TOKEN`, an Access SaaS app registration, the
   `mcp.mitechconsult.com` DNS record. Client-side change: add `case-work` as a claude.ai custom
   connector (Settings → Connectors → Add custom connector) pointing at the new public URL with
   the OAuth fields Access issues.
4. **Register the third-party HTTP servers as ContextForge peer gateways and build `dev-docs` +
   `cloud-infra`** (`context7`, `n8n-docs`, `agno-docs`, the five `cloudflare-*` targets,
   `tavily`). Prerequisites: none beyond each service's own existing API key (`CONTEXT7_API_KEY`
   already exists; Cloudflare's five servers use per-connector OAuth already). Client-side
   change: repoint Claude Code's plugin `.mcp.json` blocks, Codex's `[mcp_servers.*]` entries,
   OpenCode's `mcp` block, and Gemini's `mcpServers` block to the two new ContextForge URLs
   instead of each harness's own copy — this is the actual de-dup payoff (4 configs → 1 each).
5. **Register `agentos`** (the AgentOS MCP door) as a peer gateway into `platform-mcp`.
   Prerequisite: confirm ADR-0046's progressive-disclosure quad is what actually gets exposed
   (4 meta-tools) rather than a flat tool catalog, since that changes what "grouping" even means
   for this one. Client-side change: Codex's `agentos` entry could repoint here, or stay direct
   — low urgency since it's already HTTP+bearer and single-harness today.
6. **Decide on `coolify-write`** (`infra-ops`) last and separately from the rest, given its
   39-tool destructive surface. Prerequisites beyond the mechanical (move the `.env` file's
   contents to a VPS-side secret, stdio→HTTP wrapper or native rehost): an explicit owner
   decision on which credential/audience is allowed to reach it once it's off a single desktop's
   local filesystem gate. Do not fold this into a Cloudflare/claude.ai-reachable connector
   without a much narrower Access policy than `case-work`'s.
7. **Cleanup pass**: remove the dead `graphiti` and stale `agno-gateway`/`n8n-mcp`
   (traceiq.app.n8n.cloud) entries from OpenCode's config, and the redundant `n8n-mcp-stdio`/
   `glide-data-grid` entries from Codex's config, once their replacements (steps 2-4) are live —
   don't remove them first, in case the migration stalls and the direct configs are still
   needed as fallback.

Fallback note: `family-court-console`'s stdio mode in `family-court-toolkit@casebible-local`'s
`.mcp.json` should stay in place through step 3 and beyond as a working local fallback for
Claude Code desktop sessions, per the plugin's own design (owner ruling referenced in
`deploy/family-court-console.yaml`'s header comment — "no client downloads anything," the
console is federated, not replaced).

---

## 7. Counts and what could not be determined

- **Total MCP server *definitions* found across all harness config files (including
  duplicates and the two dead/broken entries):** 40 (6 Claude Code top-level/project + 6 plugin
  + 9 OpenCode + 14 Codex + 2 Gemini + 3 live `.mcp.json` outside harness configs, one of which
  is malformed).
- **Unique logical targets after collapsing duplicates:** ~24.
- **MOVE:** 10 (`family-court-console`, `n8n-mcp` self-hosted, `agentos`, `coolify-write`,
  `context7`, 5×`cloudflare-*` counted as one federation unit, `tavily`, `courtlistener`,
  `n8n-docs`).
- **STAY LOCAL:** 8 (`cocoindex-code`, `chrome-devtools`, `browsermcp`, `context-mode`,
  `morph-mcp`, `mcp-structured-memory`, `sequential-thinking`, `node_repl`,
  `@zilliz/claude-context-mcp` — plus `case-bible` which isn't an MCP server at all).
- **DROP/DEDUP:** 6 distinct issues (`graphiti`, `agno-gateway`, `n8n-mcp`
  traceiq.app.n8n.cloud, `n8n-mcp-stdio`, `glide-data-grid`, plus the general duplicate-config
  pattern affecting 7 more entries).
- **Could not determine:**
  - Exact tool counts for `agentos` (AgentOS MCP door) and `n8n-mcp` (self-hosted) — neither
    was queried live (the former to stay strictly read-only/no extra load on a production
    door, the latter because it's currently failing to connect).
  - Whether ContextForge v1.0.10 changes anything about inbound OAuth/authorization-server
    behavior — the changelog search did not surface v1.0.10-specific detail.
  - Whether ContextForge supports per-virtual-server-scoped bearer tokens (vs. one global
    `MCPGATEWAY_BEARER_TOKEN` covering everything) — relevant to isolating `coolify-write`'s
    blast radius; not confirmed in the docs pulled.
  - The actual mechanism by which a Cloudflare Access-issued OAuth token would be accepted by
    ContextForge's own bearer check (§5e) — flagged explicitly as needing hands-on validation,
    not something documentation alone resolves.
  - Whether this specific claude.ai account/org's connector UI currently offers the
    static-header auth option or only the OAuth fields — the GitHub issues found describe
    inconsistent rollout; would need to be checked directly in the claude.ai settings UI.
  - `probata/modules/vestigia/traceiq-rebuild/.mcp.json`'s actual intended shape — it parsed as
    a single malformed key, not a real server map; out of scope for this task (vestigia has its
    own AGENTS.md) but worth a note to whoever owns that nested repo.
