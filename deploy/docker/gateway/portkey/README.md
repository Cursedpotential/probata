> _Byline: Claude Code · Sonnet · 2026-07-19
> (drift-fix 2026-08-12 Claude Code · Kimi K3: doors-policy soak narrative annotated as pre-retirement history; LiteLLM disabled 2026-07-29 per ADR-0042)_

# Portkey gateway configs

Durable source of truth for the Portkey gateway's routing configs, in parity with how
`docker/gateway/litellm-config.yaml` is already git-tracked. Portkey itself
(`portkeyai/gateway:1.15.2`, Coolify app `portkey` / `z5787t1l7gl2zbrya8cxzapf`, port `8787` on
`ovh-app`) is a **stateless, no-DB, no-volume** deployment — it has no durable config of its own.
Every route is expressed as a JSON body sent per-request in the `x-portkey-config` header. These
files are that JSON, committed here so routing isn't only "whatever header a caller happened to
build" — see `probata (formerly Agno-MCP-Platform)/../PROPOSAL-portkey-changeover.md`-class research doc (OneDrive AI
Space) for the full as-built research this was built from.

## Files

| Config | Lane | Design |
|---|---|---|
| `configs/embed.json` | Graphiti's `embed-text` (dimension-locked, 4096-d) | NVIDIA `nv-embed-v1` ONLY — no cross-provider fallback. Gemini embeddings top out at 3072-d and can't match the Neo4j-locked index; a silent wrong-dimension fallback would corrupt vectors, not just error. |
| `configs/embed-general.json` | Future/not-yet-dimension-locked knowledge-core collections | Gemini 4-key loadbalance primary, NVIDIA `nv-embed-v1` fallback. **See the dimension-truncation warning inside the file** — do not trust it blind. |
| `configs/classify.json` | Cheap/fast triage calls | Gemini `gemini-flash-latest` 4-key loadbalance primary → Groq `llama-3.1-8b-instant` → Cerebras `gemma-4-31b` → OpenRouter `meta-llama/llama-3.1-8b-instruct` (valid-but-broke, see below) → NVIDIA `meta/llama-3.1-8b-instruct` → Mistral `mistral-small-latest` (paid, absolute-last fallback). Groq/Cerebras/OpenRouter/Mistral tiers added 2026-07-19 provider-key sweep. |
| `configs/chat.json` | rag+chat (mid-to-heavy reasoning) | glm-5.1 (Ollama Cloud) primary → Gemini `gemini-flash-latest` 4-key loadbalance → Groq `llama-3.3-70b-versatile` → Cerebras `gpt-oss-120b` → OpenRouter `meta-llama/llama-3.3-70b-instruct` (valid-but-broke, see below) → NVIDIA `nemotron-3-super-120b-a12b` → Mistral `mistral-medium-latest` (paid, absolute-last fallback). Collapsed from separate rag/chat drafts — they came out identical; split again later if they ever need independent tuning. Groq/Cerebras/OpenRouter/Mistral tiers added 2026-07-19 provider-key sweep. |
| `configs/rerank.json` | Rerank (`POST /v1/rerank`), added 2026-09-10 | Jina `jina-reranker-m0` primary (free tier, 10M tokens) → Voyage `rerank-2.5` fallback (free tier, ~3 requests/min). The NVIDIA `llama-nemotron-rerank-vl-1b-v2` reranker lives on a non-OpenAI retrieval endpoint and is not in this lane. **Send no `top_n`/`top_k`** — see below. |

### Rerank lane — verified live 2026-09-10

> _Byline: Claude Code · Opus 5 · 2026-09-10 — owner order "set it up in portkey" (Jina key), then the Voyage key._

- **Keys:** `JINA_API_KEY` (`~/.secrets/jina.env`) and `VOYAGE_API_KEY` (`~/.secrets/voyage.env`) upserted into this app's Coolify env on 2026-09-10; read back, both rows match the local values. `memsearch.env` holds a second, different, also-working Voyage key.
- **Primary:** the committed `rerank.json` (placeholders substituted) sent as `x-portkey-config` → HTTP 200 in 245 ms, `x-portkey-last-used-option-index: config.targets[0]`, model `jina-reranker-m0`, relevant passage ranked first (0.917 vs 0.282–0.345).
- **Fallback:** same file with a deliberately invalid Jina key → HTTP 200 in 376 ms, `config.targets[1]`, model `rerank-2.5`, same passage first (0.711 vs 0.229–0.248). The fallback really engages.
- **Gotcha — result count:** Jina takes `top_n`; Voyage takes `top_k` and answers **400 "Argument 'top_n' is not supported"**; gateway 1.15.2 does not translate between them. Callers send neither (both providers then return every document, sorted) and trim client-side. A `top_n` request fails exactly when the fallback is needed.
- **Direct provider checks the same day:** Jina `jina-reranker-v2-base-multilingual` 200 (same order, weaker spread), `jina-embeddings-v3` 1024-d; `/v1/embeddings` with `x-portkey-provider: jina` 200 through this gateway.

Each `$VAR` placeholder is substituted with a real secret value at request-construction time by
whatever consumer builds the outgoing `x-portkey-config` header — Portkey itself does **not** read
these from its own container env (confirmed: `Mounts: []`, and env-substitution inside an inline
header isn't a documented Portkey feature). The values live in `C:\Users\matts\.secrets\probata (formerly Agno-MCP-Platform).env`
locally and were also upserted into the Portkey Coolify app's stored env
(`NVIDIA_API_KEY`, `GEMINI_API_KEY`, `GEMINI_API_KEY_2`, `GEMINI_API_KEY_3`, `GEMINI_API_KEY_4` on
2026-07-19 Phase 1; `GROQ_API_KEY`, `OPENROUTER_API_KEY`, `CEREBRAS_API_KEY`, `MISTRAL_API_KEY`,
`OPENAI_API_KEY` added same day, Phase 4 provider-key sweep) so they're available server-side for
whatever future substitution mechanism picks them up (e.g. a small router/sidecar service, or a
wrapper script) — see the Coolify env upsert note below. `GOOGLE_API_KEY` is deliberately **not**
part of this rotation pool (owner: reserved, stays separate) even though as of 2026-07-19 it happens
to hold the same value as `GEMINI_API_KEY`.

## Verified live (2026-07-19, real API calls through `http://100.72.169.40:8787`)

- **Embed lane**: `POST /v1/embeddings` with `configs/embed.json` (NVIDIA `nv-embed-v1` via
  `custom_host`) → **HTTP 200, 4096-d vector**. Confirms the dimension-lock-safe path works
  end-to-end through Portkey.
- **Gemini provider slug**: `"google"` is correct (not `"google-ai-studio"` — that 400s with
  "Invalid 'provider' value"; the pinned image's valid list is `anthropic, anyscale, azure-openai,
  cohere, google, vertex-ai, mistral-ai, openai, palm, perplexity-ai, ...`). A real chat completion
  through `provider: "google"` returned real content.
- **Nested loadbalance-inside-fallback**: accepted by this pinned image — verified against the
  actual `classify.json` file (not a hand-rolled shape), got a real completion back.
- **3-tier fallback chain**: verified against the actual `chat.json` file, glm-5.1 primary tier
  answered directly (no fallthrough needed for a healthy primary).
- **Gemini key pool — per-key verification matrix** (this is why `classify.json`/`chat.json` pin
  `gemini-flash-latest` instead of the proposal's original `gemini-2.5-flash`/`gemini-2.5-pro`
  drafts):

  | Key | Format | `gemini-2.5-flash` | `gemini-2.5-pro` / `gemini-pro-latest` | `gemini-flash-latest` |
  |---|---|---|---|---|
  | `GEMINI_API_KEY` | `AIzaSy...` (standard AI Studio key) | 200 | 429 (quota, see note) | 200 |
  | `GEMINI_API_KEY_2` | `AQ.Ab8RN6...` (non-standard token format) | **404** "no longer available to new users" | 429 (quota) | 200 |
  | `GEMINI_API_KEY_3` | `AQ.Ab8RN6...` (non-standard token format) | **404** "no longer available to new users" | 429 (quota) | 200 |
  | `GEMINI_API_KEY_4` | `AIzaSy...` (standard AI Studio key) | 200 | not fully retested (timeout during test run) | 200 |

  The `gemini-2.5-pro`/`gemini-pro-latest` 429s hit **every** key including the two standard-format
  ones, under rapid repeated test traffic in a short window — this looks like it's most likely a
  free-tier RPM/quota ceiling triggered by the verification pass itself, not a standing "pro tier is
  broken" fact, but it was NOT re-verified at a slower request rate before this commit. Treat "is the
  pro tier actually usable at real traffic rates" as an open question, not a closed one.

  `GEMINI_API_KEY_2`/`_3` use a token format (`AQ.Ab8RN6...`) that doesn't look like a normal Google
  AI Studio API key (those are `AIzaSy...`, 39 chars). These two are longer (~70 chars incl. a `.`
  separator) and behave like they're tied to accounts Google has migrated off the pinned `2.5`
  model family onto `*-latest` aliases only. Flagging for the owner to double check these two
  accounts/keys are what was intended for the rotation pool — they work, but only on `*-latest`
  aliased models, not the pinned generation the other two keys can reach.

- **`embed-general.json`'s `gemini-embedding-001`**: all 4 keys returned 200, but **the
  `output_dimensionality`/`outputDimensionality`/top-level `dimensions` override was not honored by
  this pinned Portkey image** — every combination tried still returned the model's native 3072-d
  output, not the requested 1536-d. This is flagged inline in `embed-general.json` itself; treat the
  1536 figure in that file as aspirational until re-verified, and lock any real Milvus collection to
  the dimension actually observed at creation time, not the config's stated intent.

## Provider-key sweep (Phase 4, 2026-07-19) — new providers wired into chat.json/classify.json

Owner ordered a scan of every available provider key, live verification of each, and durable
config into Portkey. Full per-key verification matrix (real API calls; last4 only, never full
values):

| Provider | Key (last4) | Source | Direct API check | Through Portkey gateway | Decision |
|---|---|---|---|---|---|
| Groq | `9Nna` (canonical) | `.secrets` | HTTP 200, 15 models | HTTP 200, real completion (`GROQ_OK`) | **LIVE** — wired as single target (chat + classify) |
| Groq #2 | `wpCO` | donor `.env` (agno-agent-platform, prior-iteration project) | HTTP 401 invalid_api_key | not tested (dead at source) | **DEAD** — not added anywhere, not a working rotation partner |
| OpenRouter | `0fe6` (canonical) | `.secrets` | `/v1/auth/key` HTTP 200 (key valid, `is_free_tier=false`) but a real completion 402s "Insufficient credits" | HTTP 402 "Insufficient credits" | **valid-but-broke** — wired anyway per owner instruction; will no-op-fallthrough until topped up at openrouter.ai/settings/credits |
| OpenRouter #2 | `1ec9` | donor `.env` | HTTP 401 "User not found" | not tested (dead at source) | **DEAD** — not added |
| Cerebras | `8d5c` | donor `.env` (added to `.secrets` this pass) | HTTP 200, 3 models | HTTP 200, real completion | **LIVE** — wired as single target (chat + classify) |
| Mistral | `eXMA` (canonical) | `.secrets` | HTTP 200, 72 models | HTTP 200, real completion (`MISTRAL_OK`) | **LIVE** — wired as the absolute-last fallback tier per owner policy (paid, never primary) |
| Ollama Cloud | `kA8U` (canonical) | `.secrets` | `GET /api/tags` HTTP 200 (model list returned); `/api/whoami` 404 (wrong path, not the auth check) | already wired as chat.json's primary tier (unchanged) | **LIVE**, no change needed |
| OpenAI | `ELUA` (dashboard.env origin, added to `.secrets` this pass) | `Secrets/dashboard.env` | HTTP 200, 123 models | not wired into chat/classify (not requested — added to `.secrets`+Coolify for future use) | **LIVE**, held in reserve |
| Gemini #5 (`GOOGLE_API_KEY` donor variant) | `stmg` | donor `.env` | HTTP 400 `API_KEY_INVALID` | not tested (dead at source) | **DEAD** — not added as `GEMINI_API_KEY_5`, rotation pool stays at 4 keys |
| NVIDIA, Gemini 1-4 | — | already in Portkey Coolify env | unchanged | unchanged | out of scope this pass (already configured) |

A real bug was found and fixed in this same pass: the first Coolify bulk-upsert of `CEREBRAS_API_KEY`/
`OPENAI_API_KEY` accidentally captured this file's own inline `# account: ...` trailing comment as
part of the value (a naive `cut -d= -f2-` extraction doesn't strip trailing comments the way
`python-dotenv`-style parsers do) — caught because the Cerebras gateway proof-call 401'd with "Wrong
API Key" even though the same key worked fine directly against `api.cerebras.ai`. Fixed by moving the
`# account:` notes to their own line **above** the `KEY=value` line instead of trailing it (matches
how every entry in this file should be written going forward — trailing comments are parser-fragile,
leading comments are not) and re-upserting the corrected values; re-verified 200 end-to-end afterward.

## Coolify env durability (Phase 1 of the 2026-07-19 changeover)

As part of this same pass, the exec-tier (LiteLLM) Coolify app's stored env was found to have a
genuine drift: `GROQ_API_KEY` was present in the local `.secrets` file but empty in both the live
gateway container and Coolify's own rendered compose (i.e. never actually reached Coolify's env
store) — fixed via `coolify-write-upsert-application-envs`. `NVIDIA_API_KEY` was already correctly
synced (a prior redeploy had already fixed it) but was upserted again anyway to guarantee it, since
`upsert` is idempotent. See `C:\Users\matts\OneDrive\AI Space\portkey-standup-result.md` for the
full Phase 1 writeup.

While doing this, a real bug was found and fixed in the `coolify-write` MCP server itself
(`~/.claude/skills/coolify-write/server.py`, `upsert_application_envs`): its bulk-PATCH body shape
was `{"envs": [...]}` with `is_runtime`/`is_buildtime`/`is_literal` fields, but Coolify's actual API
(`PATCH /applications/{uuid}/envs/bulk`, verified live against v4.1.2) wants `{"data": [...]}` with
`is_preview`. The wrong shape 400'd, was swallowed silently (no exception raised on non-2xx), and
fell through to a per-key `POST` fallback that can only **create** — so it 409'd on every
already-existing key, meaning **this tool could never actually update an existing env var** before
this fix. Corrected in-place; verified against the live API (create → in-place update, confirmed by
matching `uuid` + changed `updated_at` → cleanup delete) before relying on it for the real upserts
in this pass.

## Graphiti cutover (Phase 3, 2026-07-19) — CUTOVER LIVE, LiteLLM untouched

Graphiti's embed-text + LLM calls now run through Portkey, not LiteLLM. See
`compose.data-graphiti.yaml` (`graphiti-portkeyfix` service) and the two dedicated configs,
`configs/embed.json` (reused as-is) and `configs/graphiti-llm.json` (new — Graphiti needs NIM
guided-JSON structured output, and `chat.json`'s glm-5.1 primary tier can't emit schema-conformant
JSON, so this is a dedicated NVIDIA-nemotron-only lane, not a reuse of `chat.json`).

**Why a sidecar and not a direct config.yaml repoint**: confirmed live (2026-07-19, reading the
running `zepai/knowledge-graph-mcp` image's own source) that `graphiti_core`'s `OpenAIClient`/
`OpenAIEmbedder` construct a bare `AsyncOpenAI(api_key=, base_url=)` with **no**
`default_headers`/`extra_headers` hook anywhere in the chain (`config.yaml` → `factories.py` →
`graphiti_core` client constructors) — so Graphiti structurally cannot send the `x-portkey-config`
header Portkey's stateless deployment needs. `graphiti-portkeyfix` (`nginx:alpine`, same pattern as
the existing `graphiti-hostfix` sidecar) sits between `graphiti-mcp` and Portkey, statically
injecting the right `x-portkey-config` per path (`/v1/embeddings` → `embed.json`, everything else
including `/v1/responses` → `graphiti-llm.json`, since `graphiti_core`'s structured-completion path
uses OpenAI's newer Responses API, not `/v1/chat/completions`).

**The static config file bakes the real `NVIDIA_API_KEY` as a literal**, staged at
`/data/probata/config/graphiti/portkeyfix.conf` on `ovh-data` — same convention as `hostfix.conf`
already uses for that host path. To regenerate after a key rotation: re-render
`docker/gateway/portkey/configs/{embed,graphiti-llm}.json` with the new key substituted for
`$NVIDIA_API_KEY` into the nginx `proxy_set_header x-portkey-config '...'` value (see the template
this was built from, or just hand-edit the two JSON blobs in the staged file), `scp` it back to
`/data/probata/config/graphiti/portkeyfix.conf`, then restart just the `graphiti-portkeyfix` container
(`docker compose ... restart graphiti-portkeyfix` or a Coolify redeploy of `data-graphiti`) — no
image rebuild needed.

**Verified end-to-end with real production traffic**, not a synthetic probe: added a live episode
via `graphiti-add-memory` with a random marker token, watched `graphiti-mcp`'s own logs show real
`POST http://graphiti-portkeyfix:8072/v1/embeddings` (4× `200 OK`) and
`POST http://graphiti-portkeyfix:8072/v1/responses` (2× `200 OK`) calls during that episode's actual
background processing, then confirmed via `graphiti-search-memory-facts` that the exact fact
(`HAS_MARKER_TOKEN: "Verification episode has marker token ...VERIFYTOKEN."`) was extracted,
indexed, and retrievable. Full round trip: real LLM extraction + real embedding + real Neo4j
write + real semantic search, all through Portkey.

**Rollback** (if ever needed): revert `compose.data-graphiti.yaml`'s `graphiti-mcp.environment`
block to `OPENAI_API_URL`/`OPENAI_BASE_URL: http://${OVH1_HOST:-100.72.169.40}:4000/v1` and
`OPENAI_API_KEY: ${LITELLM_MASTER_KEY:-changeme-dev-key}`, then redeploy `data-graphiti`. LiteLLM
was never stopped or reconfigured, so this is a config repoint, not a restore-from-backup.

## Doors policy

LiteLLM (`gateway:4000`, `docker/gateway/litellm-config.yaml`) is untouched and still running (live
health-checked `200 "I'm alive!"` at the end of this pass) — it stays live as the working fallback
path per the workspace's doors policy. Graphiti has been cut over to Portkey and verified end-to-end
as of 2026-07-19; the owner's stated soak-period recommendation before considering LiteLLM retirement
still applies (see `docker/gateway/litellm-config.yaml`'s own header and the "Retire LiteLLM" section
of the originating proposal doc).

> **Corrected 2026-08-12 (doc drift):** the soak-period framing above is pre-retirement HISTORY.
> LiteLLM was disabled/retired by owner ruling 2026-07-29 (ADR-0042): `docker/gateway/supervisord.conf`
> pins `autostart=false`, so nothing listens behind :4000 in the gateway container. The "live as of
> 2026-07-19" health-check line reflects that date only; the working fallback it describes no longer
> exists unless litellm is deliberately re-enabled. Portkey is THE model gateway.
