# Docstore control plugin 0.5.0

## Operational indexing API — 2026-09-13

Source version 0.6.2 adds authenticated worker-run registration, exact run status,
cancellation, live pipeline identity, and source-to-store CDC attribution. A
selected request still runs the complete declared CocoIndex source; selected paths
are verification targets and can never become a partial source declaration. The
worker marks `cdc_verified=true` only after a stable before/after source snapshot
matches every managed SurrealDB document path and normalized content hash exactly.

The control catalog now exposes 26 tools. The production Tailnet API observed before
this change remains the older read-only deployment; this source capability is not a
live deployment claim. Multi-root remains disabled until the production build context
contains every required registered source.

<!-- Updated by: Codex | Date: 2026-09-12 | Rev: 2 | Platform: Codex / win32 | Changes: add universal project registry tools/resources | Context: explicit owner decision -->

**Owner decision — 2026-09-12:** CCC means project-local CocoIndex Code indexes only. Intake is the multifaceted CocoIndex-based filesystem workstation, using Weaviate for advanced search and SurrealDB for relationships, with multimodal tools/libraries (OCR, STT, video transcription/processing, advanced SLM extraction/classification). Docstore is CocoIndex + SurrealDB for project documentation. Keep their apps, tracking state, locks, configuration and target ownership isolated; shared technology is not a shared runtime. This defines scope, not proof every feature is implemented.

See [CCC / Intake / Docstore boundaries](../../../../../SYSTEM-BOUNDARIES.md) for indexing eligibility, duplicate provenance and the human-agent organizing workflow.

The combined documentation tool package: **CocoIndex + SurrealDB + document/graph retrieval + Surrealist guidance**. It does not replace the existing database or change the codebase CCC instance. Existing `../claude` plugin and live configuration remain intact; this is the reviewable replacement candidate, not a silently enabled second plugin.

Probata hosts the implementation, but the service is the universal Propria
documentation plane. The governed source list lives in the Propria root
`docs/docstore-source-registry.json`. `docstore_project_sources` and
`docstore://projects` expose the complete registration without walking or hydrating
documents; project detail is available through `docstore_project_source` and
`docstore://project/{project_id}`. Registration status is not ingestion proof.

### Semantic retrieval and project search routing — 2026-09-12

`coco_docstore_search` is the primary agent-facing documentation search tool. It
embeds the query through the existing Docstore API, runs hybrid BM25 plus KNN
retrieval over CocoIndex-maintained vectors in the dedicated SurrealDB Docstore,
and returns bounded DuckDB compact-column presentation by default. Set
`presentation=full` only when the original result shape is needed. This adds no
Weaviate instance or second vector projection.

The canonical `propria-docstore` plugin bundles the `propria-search` skill, which routes documentation questions to that tool,
code/symbol questions to the separately installed project-local CCC skill, and mixed
questions to both with explicitly labeled evidence. It unifies discovery, not state:
Docstore and CCC retain separate application identities, databases, tracking state,
locks, credentials, freshness checks, citations and write paths. Neither silently
falls back to the other.

Live proof on 2026-09-12: the dedicated API reported 500 documents, 11,688 chunks,
11,688 `chunk_of` edges, and a ready vector index with zero pending entries. A bounded
semantic query returned results marked `kw+vec` through the new tool. This proves the
read path at that instant, not full-corpus source freshness or CDC attribution.

## What is implemented

### CDC worker safety — 2026-09-12

[Source-hardening receipt](CDC-WORKER-SAFETY-2026-09-12.md): the existing worker now
rejects unsafe partial-source requests, propagates component errors, retains bounded
logs and append-only execution receipts, and uses a persistent OS lock without age
stealing. This increment is **not deployed**, and no corpus run was performed.
Execution receipts do not certify per-document CDC. Selective update execution and
remote run-status integration remain unavailable pending the documented migration.

[Crash-visibility receipt](CDC-WORKER-SUPERVISION-2026-09-12.md): the existing
Docstore worker/API is live at port 8474; 8473 is Intake SurrealDB, 8472 is
Docstore SurrealDB and 8471 is Case Bible/Probata SurrealDB. The compose
definition already persists state and receipts under `/data/state`, but the image
previously hid startup-sync failure behind a live Uvicorn process and a status-code-
only healthcheck. Source now uses a PID-1 Python supervisor, a bounded atomic current
run status and a healthcheck that evaluates the response body. This is locally
verified source only: this change is not deployed, and no corpus run or service restart was
performed. Latest remote state and historical remote receipt access remain distinct;
`docstore_cdc_runs` is still local-receipt-only.

### Revision history and exact approvals — 2026-09-12

The current catalog has **19 tools**. `docstore_capture_revision` appends bounded
content snapshots under a stable logical key; `docstore_approve_revision` records
explicit approval of an exact numbered revision and raw SHA-256; and
`docstore_revision_state` reads bounded revision, approval, alias and metadata-event
history. CLI equivalents are `capture-revision <json_file>`,
`approve-revision <json_file>` and `revision-state <document_key>`.

These operations use additive schema `096_revision_history.surql`, outside the
CocoIndex-owned document/chunk projection and the existing human flag overlay.
They do **not** execute indexing or imply CDC freshness. Historical catalog counts
below describe earlier increments. See [revision contract](REVISION-LIFECYCLE.md)
for concurrency, approval, path and verification boundaries.

`docstore_selected_update_plan` is the newest read-only admission surface. It
checks 1–20 explicit Markdown paths against current logical revision, generation,
raw hash and worker-equivalent projection hash; rejects worker exclusions,
duplicates and selected-set document-ID collisions; and returns a deterministic,
body-free manifest. It deliberately reports `bootstrap_observed=false` and
`execution_available=false`. A candidate identity digest is not evidence that the
production worker committed that topology. See the
[synthetic selected-CDC receipt](SELECTED-CDC-PROOF-2026-09-12.md).

### Query before recording — 2026-09-12

The catalog now has **13 tools**. `docstore_related_updates(term, limit)` queries indexed documents, human notes/flags, structured ADRs and decision-log entries before updates. It preserves inactive/superseded matches, returns compact results and reports source-specific errors/truncation. Literal keyword coverage is not proof that every external note was captured. Use `docstore_set_flags` to persist bounded notes/decisions and verify them through a read tool; local documentation alone is not completion. Note persistence does not claim CocoIndex content freshness. Cross-task coordination is a separate deferred concern.

### Shared compact results — 2026-09-12

The catalog now has **12 tools**. Prefer `docstore_compact` for routine search, flags, graph and document previews. It reuses the existing `sq.py` cleaning pattern through a bounded in-memory DuckDB adapter; original tools remain available for full content and specialized parameters. No corpus mutation or arbitrary SQL is exposed. See [adapter receipt](COMPACT-RESULTS-2026-09-12.md) and the cross-application [shared contract](../../../../../RESULT-PRESENTATION-CONTRACT.md).

```powershell
cd "E:\AI_Workspace\Projects\Propria\Probata\probata\plugins\docstore\control" && .\docstore.ps1 --compact flags --domain docs
```

CLI `--compact` is optional and precedes the subcommand; existing scripts keep their original structured output. App-wide rollout to existing Case Bible/Intake surfaces remains tracked in the shared contract, not claimed complete here.

### Critical note/decision flags and indexing verification — 2026-09-12

The extension adds `docstore_set_flags`, `docstore_flags`, `docstore_verify_index`, and `docstore://critical/{domain}`: **11 control tools, four static resources, three templates, one prompt**. The original eight-tool table below describes the base surface.

Flags carry separate priority (`critical/high/normal`), authority (`owner_decision/verified_finding/proposal`), status (`active/superseded/retracted`), domain scope, source reference, rationale, actor and revision. They live in `docstore_flag` with transactional `docstore_flag_audit` history in the same dedicated documentation database, outside CocoIndex-owned rows. Replaying identical metadata is idempotent; changed metadata must use the expected revision. No source row replacement, reindex or model call is involved.

The owner-approved three-system boundary is stored as `note:ccc_intake_docstore_boundaries`, critical/owner_decision/active. The HTML snapshot command renders real stored flags with separate badges, escaping content and loading no external scripts. It is a read-only snapshot, not a live-editing frontend.

`docstore_search` now retrieves active critical domain context before ordinary similarity results when native credentials are configured, and reports unconfigured/unavailable flag context explicitly. The standalone flag tool/resource works independently of the currently unavailable recall API. The skill instructs agents to consult relevant flags at decision points, not inject every note into every turn.

Use the existing dedicated credential through `DOCSTORE_BASIC_AUTH` (or an explicit `DOCSTORE_CONTROL_ENV_FILE`); never put credential values in commands or URLs. Commands from this directory:

```powershell
.\docstore.ps1 flags --domain docs
.\docstore.ps1 flags-view --domain docs
.\docstore.ps1 set-flags owner-system-boundary.flag.json
.\docstore.ps1 verify-index NAMING.md
```

`verify-index` is an on-demand/batch-completion check, not a per-turn watcher. It uses the current worker's UTF-8/non-BMP-folded fingerprint, not raw byte hashes from `plan`; records lifecycle/search eligibility separately; and inspects chunk count, vector dimension and document links. **CDC attribution and exact projection freshness remain unproven** because the existing worker does not persist a correlated per-document completion receipt. A mismatch can reflect stale indexing, different deployed source, or line-ending differences; it is not proof that CDC never ran. No verification call starts indexing.

Only `scripts/docstore/schema/095_flags.surql` installs the additive extension (`install-flags-schema`); do not replay all legacy schemas. Live results and known native protocol/planner gotchas are recorded in `FLAGS-AND-CDC-VERIFICATION-2026-09-12.md`.

| Connection | Tooling |
|---|---|
| `propria-docstore:control` | Twenty-one fixed-purpose MCP tools, five static resources, four resource templates, one reconciliation prompt; matching terminal commands |
| `docstore-surreal` | Existing native SurrealDB MCP endpoint, dedicated documentation namespace/database and credential reference; live tool schemas are discovered from that server |

| Control tool | Terminal command | Operation |
|---|---|---|
| `docstore_capabilities` | `capabilities` | Isolation settings and explicit capability gaps |
| `docstore_health` | `health` | Actual API/store health; unhealthy body returns nonzero in CLI |
| `docstore_stats` | `stats` | Documents, chunks, edges, vector-index build status |
| `coco_docstore_search` | `semantic-search QUERY --domain DOMAIN` | Primary CocoIndex/NIM to Surreal vector search; bounded DuckDB presentation by default |
| `docstore_search` | `search QUERY --domain DOMAIN` | Hybrid retrieval across nine document kinds; optional remote reranking |
| `docstore_get` | `get document:ID` | Document body, path, metadata and status |
| `docstore_graph` | `graph document:ID` | Incoming/outgoing links, citations and supersession |
| `docstore_index_plan` | `plan FILE.md ...` | Original-byte hashes for selected local Markdown; no ingestion |
| `docstore_selected_update_plan` | `selected-update-plan REQUEST.json` | Revision-bound selected-source admission manifest; no ingestion or bootstrap claim |
| `docstore_cdc_runs` | `runs [--run-id ID]` | Validated bounded worker execution receipts; never CDC proof |
| `docstore_surrealist` | `surrealist` | Credential-free visual viewer link and connection guide |
| `docstore_project_sources` | `projects` | Governed Propria documentation roots and declared ingestion state; no file scan |
| `docstore_project_source` | `project PROJECT_ID` | One registered project's ownership, prefix, patterns and state |

`catalog` lists complete tool schemas/resources/prompts. `verify-stdio` starts a temporary MCP subprocess and validates protocol discovery without upstream calls. `native-catalog` performs live discovery on the native SurrealDB MCP endpoint without executing its tools.

Live-discovered native tools (2026-09-12): `create`, `delete`, `gql`, `graphql`, `info`, `insert`, `list`, `query`, `relate`, `run`, `select`, `update`, `upsert`, `use`. These are the existing server's capabilities, not newly implemented database functions. `native-probe` selects only one document ID to verify authentication/read access. Destructive tools were not invoked. Do not use `use` to cross the dedicated Docstore namespace/database boundary.

### Important unfinished backend capability

**Actual CocoIndex indexing execution is not exposed yet.** The existing worker is full-source reconciliation and has no jobs API. Its subset option can retire omitted documents; graph rebuilding is whole-source and non-atomic. Wiring these behind a friendly button would not make them safe. The plugin explicitly reports execution unavailable. Native database mutation tools, if the server exposes them, do not substitute for CocoIndex ingestion.

## Run now

Dependencies were installed with uv into this package's E-drive `.venv`; `uv.lock` pins them. Nothing was installed into Claude/Codex settings.

PowerShell 7, offline capability inspection:

```powershell
cd "E:\AI_Workspace\Projects\Propria\Probata\probata\plugins\docstore\control" && .\docstore.ps1 capabilities
```

Full tooling inventory:

```powershell
cd "E:\AI_Workspace\Projects\Propria\Probata\probata\plugins\docstore\control" && .\docstore.ps1 catalog
```

Remote health, then search (search incurs query-embedding cost):

```powershell
cd "E:\AI_Workspace\Projects\Propria\Probata\probata\plugins\docstore\control" && .\docstore.ps1 health
cd "E:\AI_Workspace\Projects\Propria\Probata\probata\plugins\docstore\control" && .\docstore.ps1 search "CocoIndex isolation" --domain docs --limit 5
```

Claude Code can load the source package for a session with `claude --plugin-dir <absolute control directory>` after its environment credentials are set. Do not enable the old and replacement native docs connection together. `.mcp.json` contains references, never credential values. `codex.config.example.toml` is a reviewed source example to merge deliberately, not an automatic installer. The shared `skills/docstore` works for either host. Host activation and native tool permissions still require verification.

## Configuration and isolation

`DOCSTORE_API_URL`, `DOCSTORE_SOURCE_ROOT`, `DOCSTORE_CONTROL_STATE_DIR`, `DOCSTORE_INSTANCE_ID`, `DOCSTORE_PROJECT_REGISTRY`, optional `DOCSTORE_API_TOKEN`. The CLI supplies repo-specific defaults, including the Propria root registry; standalone `server.py` requires them explicitly. `DOCSTORE_CONTROL_ENV_FILE` optionally loads only DOCSTORE-prefixed keys without changing process-global environment; existing process values win. Optional `DOCSTORE_WORKER_RECEIPTS_DIR` exposes bounded read-only worker status only when the worker's actual receipt directory is deliberately mounted/provided. No secrets are printed.

The native connector separately uses `DOCSTORE_MCP_URL` and `DOCSTORE_BASIC_AUTH` (Base64 Basic credential). For the Codex example, `DOCSTORE_AUTHORIZATION` holds the full `Basic ...` header. The CLI env file is not automatically loaded by the native host connector; supply its credentials through the host environment.

Control state path is reserved configuration: this read-only adapter does not create a database or lock there. It must be on E on Windows, outside the source root and outside codebase state directories. The existing pipeline identity remains `ProbataDocStore@probata-docstore`; its state and worker lock are not changed by this package. Multiple read clients can coexist; index writer isolation must be enforced by the worker, not claimed from a client label.

No corpus enumeration at startup, flow imports, local models, model downloads, background workers, browser auto-opening, credential-bearing URLs, or automatic update checks. API responses are capped at 2 MiB with network timeouts; plan files are capped at 20 × 1 MiB. No request automatically retries or silently falls back to another store. Native MCP permissions are determined by its dedicated credential; the native server is not declared universally read-only.

## Validation and next integration

See [VERIFICATION.md](VERIFICATION.md) for observed results and limitations.

- [x] Control tools, MCP resources and prompt implemented.
- [x] Native SurrealDB connection packaged separately with dedicated target.
- [x] Scoped skill and operating references included.
- [x] Original CCC and existing Docstore app identity preserved.
- [x] Live native tool discovery and authenticated one-document-ID retrieval.
- [ ] Live API document/search/graph retrieval and credential permission-boundary verification.
- [ ] Viewer connection and graph rendering against the live target.
- [ ] Safe indexing job admission/status/cancellation and nondeleting scoped reconciliation.
- [ ] Explicit host activation after live verification.
- [ ] ContextForge registration: use the actual MCP catalog; no guessed gateway API or claimed federation. Stdio requires an approved gateway-side adapter/deployment before remote federation.

Upstream references used: [FastMCP 3.2.4 transports](https://github.com/prefecthq/fastmcp/blob/v3.2.4/docs/clients/transports.mdx), [SurrealDB Studio](https://surrealdb.com/docs/explore/studio), and the installed CocoIndex v1 skill. Anthropic's full documentation export was unavailable through the browser during this run; installed MCP skill references and local SDK source were used instead.
