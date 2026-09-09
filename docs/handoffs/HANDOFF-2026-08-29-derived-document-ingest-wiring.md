# HANDOFF — Derived-document ingest wiring (AI work products → context → timeline/vectors/graphs) (2026-08-29)

> _Byline: Claude Code · Opus 5 · 2026-08-29_
> _Byline amendment: Claude Code · Opus 5 · 2026-08-29_
> _Byline implementation-state amendment: Codex · GPT-5 · 2026-08-29_
> _Byline ADR-0061/SBV-boundary correction: Codex · GPT-5 · 2026-08-29_
> _Naming: written before the 2026-09-05 rename (D-137..D-141); see docs/NAMING.md for the old->new glossary._
STATUS: PARTIAL — audit decisions are reconciled; schema, auth, Workbench shell, and SBV-preview
implementation lanes are local/in review; nothing in this document is yet production-complete.
BUILD_STATUS: PARTIAL PASS — focused migration/contract/auth tests and Workbench lint/build pass locally;
PostgreSQL 18 execution, the complete suite, clean integration branch, Coolify deployment, and live
operator proof remain mandatory.

## HANDOFF v2 — current continuation state (supersedes stale status statements below)

- **Accepted architecture:** ADR-0061 is accepted. Workbench is the single shell/context/auth boundary;
  SBV is the storage-free pipeline-preview client composed inside it. The Vite mockup is a design donor,
  not a third production application.
- **SBV retirement contract:** no target-state SBV SQLite/cache, local auth, bespoke ingest, parser
  selection, or custody authority. SMS joins the common Go-selected parser contract. UIW computes
  separately named **context fingerprints** before parsing; these are not evidence custody. Evidence
  H1/H2/H3 begins only at governed promotion and dispatches by the precise canon tuple. Retained XML
  remains the MMS migration authority because historical SQLite is lossy, but the current streaming
  decoder iterates every part. ~~The active blocker is the missing immutable platform attachment
  sink/locator in `pkg/parseonly`, reflected by `SupportsAttachments: false` in the adapter.~~
  **CLOSED 2026-08-29 — see the reconciliation block below.** Quarantine
  only after complete re-ingest and live platform read proof.
- **Schema foundation:** migration `0047` and its import-light contracts are implemented locally after
  independent review remediation. Focused static tests report 21 pass; ~~the PostgreSQL 18 rollback-only
  behavior harness is ready but skipped until a disposable `PLATFORM_0047_TEST_SERVICE` is bound.~~
  **The PG18 lifecycle proof has since run — commit `860e925` "test(context): prove 0047 lifecycle on
  PostgreSQL 18".** It is not applied live.
- **Fingerprint/UIW repair:** migration `0048`, contract vectors, and Go activity/replay changes are
  implemented locally. The first independent read-only review returned **REQUEST CHANGES**; remediation,
  executable PostgreSQL proof, and re-review remain required. ~~Do not commit or deploy this lane yet.~~
  **Superseded by events 2026-08-29: `sql/0048` is committed and git-tracked (`0f30d33`). The
  do-not-deploy half of this instruction stands — it is not applied and not deployed.**

> ### RECONCILIATION BLOCK — Claude · Opus 5 · 2026-08-29, owner-ordered
>
> This header was accurate when written and drifted within hours. Verified against the repo, not the
> docs:
>
> | Header claim | Verified state |
> |---|---|
> | HEAD `312d302` @ 11:34 | **`aeb8f4b` @ 16:10.** `origin/main` is `ddd258d` @ 13:46 — local `main` is **36 commits ahead and unpushed** |
> | "Migrations on disk through `sql/0046`" | **`0001`–`0051`.** Git-tracked through `0048`; **`0049`, `0050`, `0051` exist on disk but are not committed** |
> | SBV `SupportsAttachments: false` | `engine/adapters/sbv/sbv.go:113` → `SupportsAttachments: a != nil && a.artifacts != nil`, adapter `1.3.0`, sink `FilesystemArtifactSink`. False only for legacy `New` / `NewAll` |
> | `context_thread_id` "does not exist anywhere in the schema" (body, later in this file) | **Built in `sql/0047`** — first-party and third-party thread tables, versions, messages, sources. Contradicts this file's own schema-foundation bullet above |
>
> **Standing rule for anyone reading this document:** it is a point-in-time audit of a repository that
> was moving while it was written, and it says so. Re-verify HEAD, the highest migration number, and any
> adapter capability flag against source before acting on them. Prefer the dated receipts in
> `docs/reviews/` over this header where they disagree — they are narrower and newer.
- **Workbench shell:** fixed-case provider plus approved graphite shell/intake integration builds and
  lints locally. The bounded SBV client/API implementation is still in progress. Local build proof is
  not a preview URL or production proof.
- **Preview identity/API boundary:** the SBV composition must read preview, records, decisions, and events
  through UIW-native APIs that carry the UIW workflow/source/run correlation explicitly. Never pass a UIW
  workflow or run ID to legacy `/v1/records` or legacy run-event SSE and assume the namespaces correlate;
  the BFF must resolve and verify the mapping or fail closed.
- **Authentication:** Authentik 2026.8/Traefik source contracts are implemented locally with no Basic
  Auth/password env and no direct `:8020` bypass. Focused tests report 18 provider/consumer + 43
  Workbench auth pass. Exact Traefik address, secret files, Authentik objects, DNS/TLS, deployment, and
  live login/denial/identity proof remain open.
- **Integration rule:** the current local `main` contains divergent history and a shared dirty tree.
  Stage only explicit owned paths. Produce scoped commits, rebuild from current `origin/main`, cherry-pick
  only verified net changes, run mandatory unit/integration/build checks, then push non-force and deploy.

## Scope

Owner supplied four markdown files (AI-assistant outputs containing case chronologies, events,
entities, legal strategy, and a long-form research guide) and asked: **is there a parser that
will handle them, where should they land, and are they searchable?** Then: write the handoff +
TODO to get documents of this class through the Temporal/n8n path, into the right tables, so
change detection can drive them to timeline, vectors, and graphs.

Answer up front (**corrected same-day, see "Ingest taxonomy" below**): **these files need no
parser at all — they are already text, so parsing (decoding a structured export format) is a
category error for them.** The real gaps are a structure-aware **chunker** and a **producer** for
the timeline table; once chunked they are not yet semantically searchable, and the downstream
timeline/graph machinery is built but has no producer. Nearly every missing piece already exists
in-tree and is unwired.

## The four files (content class)

They are **not chat transcripts** — zero role markers in any of them. They are *derived
analytical work products*: a NotebookLM case chronology ("FULL CASE EXTRACTION — ALL
TIMELINES, EVENTS, STRA", 17.6KB), a courtroom-framing strategy memo (3.8KB), a long-form
Michigan digital-evidence practitioner guide (56.4KB), and statute analysis with NotebookLM
`[span_N](start_span)` citation markers still embedded (5.0KB).

This class has no representation in the parser registry or the format router — **because there
is nothing for a parser to decode.** They need chunk + ingest, not parse + ingest. See "Ingest
taxonomy" below.

## Verified-live state (do not re-derive)

> **⚠ LINE NUMBERS ARE VOLATILE.** Codex is running ~6 concurrent subagents against this repo
> (owner, 2026-08-29); HEAD moved twice during the audit that produced this document. Every
> `file:line` below was verified at the HEAD named in the first row — **anchor on the symbol
> name, not the line number**, and re-locate before acting. Findings are about *symbols and
> behavior*, which are stable; line numbers are not.

| Thing | State |
|---|---|
| Repo / HEAD | `Agno-MCP-Platform` `main` @ **`312d302`** "PHASE-0.2-SECURITY: Critical security fixes for STOP gates" (2026-08-29 11:34). Audit was performed at `54de3f0` "PHASE-0-FREEZE" (11:10); re-verified against `312d302` where noted |
| Working tree at time of writing | Dirty and moving — `engine/activities/hashing.go`, `engine/stagegraph/`, `engine/uiw/`, `workbench/api/app/runtime/auth.py`, `server/ingest/service.py` modified; `deploy/authentik.yaml` untracked. **Codex in-flight — do not touch.** |
| In-flight change to an audited file | `server/ingest/service.py` has **+130 uncommitted lines** adding `recover_incomplete_ingests()` — startup recovery scanning `ops.workflow_run` for stuck `framework-neutral-ingest` runs, replacing the `_INGEST_TASKS` asyncio-only path lost on restart. **Orthogonal to this handoff** (touches durability, not parser routing / lane / chunking) — the work packages below are not redundant with it, but expect line drift in that file |
| Migrations on disk | through `sql/0046_agno_app_role.sql`; `0041`–`0046` all post-date the 2026-08-23 audit |
| Parser registry | 25 `@register` parsers; **16 accept `.md`/`.txt`** |
| Format router | `server/analysis/format_router.py` — `SIGNATURES` has **3 entries, all JSON marker matches** (`chatgpt-official`, `perplexity-contexts`, `claude-ai-export`). **Zero markdown signatures.** |
| Router wiring | `detect_format()` IS wired — `server/analysis/chat_parse.py:68`. Returns `format_id=None` for all `.md` → falls to `_parse_via_registry` with no preferred tool (`chat_parse.py:84`) |
| Detection is advisory | On a hit, `preferred_tool_id` only **sorts** the candidate first (`chat_parse.py:99`); on exception it still walks every other candidate |
| Parser precedence | **Only `sbv_sms.py:393` declares `priority=100`.** Every `.md` parser is priority 0, so order is decided by `pkgutil.walk_packages` alphabetical traversal (`registry.py:140`) — `ai_chat/` < `generic/` is load-bearing by accident |
| `.md` terminal fallback | `transcripts.markdown` (`generic/whole_file_fallback.py:25`) — one flat whole-file record |
| Evidence-lane guard | `_EVIDENCE_FORBIDDEN_PARSERS = {transcripts.markdown, documents.text-v1}` (`service.py:29`); enforced at `service.py:131`. The guard at `:232` is **dead** — it raises inside a `try` whose `except` reroutes into `:131` |
| Temporal parse path | `server/temporal/activities.py:196 parse_activity` resolves via `registry.resolve()` directly and has **no lane guard at all** — its docstring states it is deliberately not the ingest facade's path |
| Ingest lane default | **`platform`** (`server/contracts/ingest.py:75`, `server/api/ingest_routes.py:138`). No auto-classifier on the canonical path |
| Lane semantics | **ADR-0053** governs (supersedes ADR-0050): `legal` = law/procedure/strategy/created legal work; `personal_history` = personal/relationship history (absorbed retired `relationship_timeline`); `context` = general/ambiguous; `evidence` = custody-approved only |
| Canonical chunker | `server/ingest/chunking.py::chunk_records()` (`service.py:321-323`) — Chonkie `RecursiveChunker(tokenizer="character", chunk_size=1500)`, **no overlap, lane-blind**. `chunking_policy.lane_chunker()` is NOT on this path (only caller `server/core/session.py:426`) |
| Chonkie | **1.7.0 installed, `requirements.txt:23-24`** — in production. Chunkers available: Recursive, Semantic, Sentence, Token, Fast, Code, Table, Late, Neural, Slumber |
| Chonkie markdown recipe | **`RecursiveRules.from_recipe("markdown")` FAILS live** — root cause verified: `from_recipe()` → `chonkie.utils.hub.get_recipe(name, lang, path)` → `huggingface_hub` download → raises `huggingface_hub.errors.LocalEntryNotFoundError`, because this machine sets `HF_HUB_OFFLINE=1` / `TRANSFORMERS_OFFLINE=1` (owner's "no local models, ever" enforcement guard) — **not a Chonkie bug, not a network outage, not a reason to reject Chonkie.** Ranked Hub-free options: (a) hand-specify `RecursiveLevel(delimiters=['\n# ','\n## ','\n### '])` inline — **preferred**, no vendored asset, no Hub call; (b) Semantica `StructuralChunker` (candidate A); (c) vendor the recipe JSON and call `from_recipe(..., path=<local>)` — **last resort only** (owner correction: not the recommended fix). Default `RecursiveRules` levels are `['\n\n','\r\n','\n','\r']` → sentences → punctuation, no heading delimiters — a 56KB record → ~37 chunks with section structure destroyed |
| Docling | Declared `pyproject.toml:87` (`document-ai` extra). **NOT in `requirements.txt`; NOT installed by the root `Dockerfile` (`RUN uv pip sync requirements.txt --system`) nor `docker/tools/Dockerfile`.** Not present in any deployed image |
| Docling failure mode | `.pdf` degrades to `documents.extract-text`; **`.docx/.pptx/.xlsx/.html/.htm` have no fallback and hard-fail** (`docling_extract.py:6-17`, their URGENT-TODO #17) |
| Tesseract OCR | `ocr` extra (`pyproject.toml:80-83`); absent from `requirements.txt` and both Dockerfiles — **not functional at runtime** |
| Not present at all | LlamaIndex, LlamaParse, unstructured, pandoc, markitdown, tika, textract — absent from `pyproject.toml`, `uv.lock`, `requirements.txt`, and every import |
| Semantica `parse/` | **17 working format modules** (pdf/docx/pptx/xlsx/html/docling/email/image-OCR/csv/json/xml/yaml/code/media/mcp/web) using pdfplumber, python-docx, python-pptx, openpyxl, BeautifulSoup, pytesseract. **Zero callers outside the vendored subtree** |
| `StructuralChunker` | `server/vendored/semantica/semantica/split/structural_chunker.py` — structure-aware, has vendored tests, **zero callers** |
| Semantica platform wiring | `semantica_wiring.py:133-149` — `"deploy": "APPROVALS-gated; fixture/in-process adapter only"`. Callers: `scripts/run_semantica_fixture.py`, a config-printing smoke script, 3 test files |
| Semantica candidate sink | Writes `working.candidate_entity` / `candidate_fact` / **`candidate_event`** (`semantica_candidates.py:32-63`) |
| Timeline sink | Timeline reads **`timeline.event_candidate`** (`sql/0035_timeline_projection.sql:62`) — a **different table**. **No bridge exists between them** |
| `timeline.event_candidate` | Purpose-built for this class: `source_system` examples include `'ai_chat'`; table comment records **D-082 — "an AI-chat-derived row is a lead, never evidence"**; append-only via `forbid_mutation()` trigger; corrections are new rows with a new `extraction_run_id`; deliberately **not FK-constrained** so "any producer that can name its own system/record/version may write here" |
| Timeline module | `40ef4b2` **IS on `main`** (verified `git merge-base --is-ancestor`). `server/timeline/` = generation.py (382 lines), projector, receipts, hashing, models, cli + `sql/0035` (504 lines) + 392 lines of tests. **CLI-only, no HTTP route, zero production callers** (only importer is `tests/test_timeline_projection.py`). Its docs say upstream extraction (WP-B01) is "blocked upstream" |
| `working.investigation_event*` | Schema only (`sql/0024:224-291`) — **zero Python writers anywhere** |
| Searchability | Content ingested via `/v1/ingest` **never reaches the collections `/knowledge/search` queries**. Only reachable paths: `GET /v1/knowledge/items` (exact match) and `GET /v1/records?q=` (plain `ILIKE`, not the existing FTS/trigram indexes) |
| Evidence search | `/v1/evidence/search` and `/v1/operator/evidence/search` hardcode `"knowledge_lane": "evidence"` — cannot see non-evidence lanes |
| Dual-lane comparison | `GraphRagLane` = `semantica` \| `sat_temporal` (`graphrag_contracts.py:14-18`, "callers cannot supply graph database names"). `GraphRagExtractionComparisonWorkflow` **IS registered on the worker** (`server/temporal/worker.py:71`). Output documented as "Two independent lane receipts plus their **no-fusion** reconciliation state" |
| Temporal worker registry | Workflows: `ChatTranscriptIngest`, `ClassificationBatchPipeline`, `GraphRagExtractionComparisonWorkflow`. Activities: `custody_activity`, `parse_activity`, `store_activity`, `knowledge_activity`, `n8n_webhook_activity` (`worker.py:33-78`) |
| Feature flags | **Decided: Unleash.** Queued in `docs/MASTER-TODO-2026-08-18.md` (added 2026-08-29 from owner directive), behind the Workbench/UIW release slice. Standing rule: side-by-side deploys / swappable implementations use named flags |
| NvidiaReranker | `server/core/reranker.py:36` — complete client, **zero callers**; no `Knowledge(...)` passes `reranker=` |
| PII / git safety | Ingested content lands in Postgres + `/r2/evidence` blob root + `/tmp` staging — **outside git**. Owner ruling 2026-08-29: no redaction or PII modification until export time; everything stays in |
| Production database | **`platform` is the new production database** (owner, 2026-08-29). The `ai` database referenced in the `PHASE-0-FREEZE` STOP items (`STOP-R13-2`, `STOP-R14-2`) is **no longer production** — that freeze line is stale. See `sql/0043_platform_single_case_foundation.sql`, `sql/0046_agno_app_role.sql` |
| n8n integration pattern | **Owner, 2026-08-29: n8n exists to utilize the tools. To date every custom tool is wrapped in an n8n code node.** New capability should be exposed as a callable tool and wrapped that way, not as a bespoke route. `n8n_webhook_activity` (`server/temporal/n8n_activities.py:45`) is the Temporal↔n8n bridge and is registered on the worker |
| Chonkie semantic tier | `SemanticChunker`/`NeuralChunker`/`LateChunker`/`SlumberChunker` require model or embedding inference. Owner hard rule: no local models on this box — model-backed work routes through **Portkey** (the model gateway; `docker/gateway/portkey/`, `x-portkey-config` header at `server/core/session.py:210`) to a remote provider (NVIDIA NIM, Ollama Cloud, or a free-tier API) as the normal path, keeping the provider swappable. **Colab (via the Colab MCP) is only for the narrow case of a local-model-only application with no API equivalent**, and — like every other MCP server — would be reached through **ContextForge** (`CF_GATEWAY_URL`/`CF_GATEWAY_TOKEN`, `deploy/exec.yaml:24-26,109`), never as a direct client; unverified reachable this session (a tool search for it returned no Colab tools). `NimEmbedder` (`server/core/embedder.py:26`) already exists for NIM-backed embeddings via this Portkey path. Chonkie's own remote executor is still a stub (`chonkie_chunkers.py:186-228`, line 192 "the remote executor is not wired yet", D-046) — a blocker independent of which remote path is used |
| Gateways | **Portkey = the model gateway** (`docker/gateway/portkey/`, `portkey/configs/embed.json` NVIDIA `nv-embed-v1` 4096-d dimension-locked, `x-portkey-config` header at `server/core/session.py:210`, `graphiti-portkeyfix` sidecar injecting `custom_host=integrate.api.nvidia.com` at `deploy/compose.yaml:207-208`, `deploy/portkey.yaml`). **ContextForge = the MCP gateway** (`CF_GATEWAY_URL`/`CF_GATEWAY_TOKEN`, docker-DNS name `contextforge` on the shared `agno` network, `deploy/exec.yaml:24-26,109`, `deploy/contextforge.yaml`) — standing rule: MCP servers are reached ONLY through ContextForge, never as direct clients. Model/embedding calls route through Portkey; MCP calls (including a hypothetical Colab MCP) route through ContextForge |

## Identifier taxonomy (owner flag, 2026-08-29 — context every later section depends on)

> Owner: *"There's chat IDs which is for AI chats, and then there's the chunks, and then we also
> have conversation IDs which can actually spread across different mediums and files because of
> platform hopping, and those are separate entirely."*

| Concept | Column / table | Exists? | Note |
|---|---|---|---|
| AI chat session | `working.chat_conversation.id`, referenced as `chat_chunk.conversation_id` | **YES** | One ChatGPT/Claude/Gemini conversation export. **Read "conversation" here as "AI chat session"** — see the name-trap warning below |
| Chunk | `working.chat_chunk.id` | **YES** | `UNIQUE(conversation_id, chunk_index)` + `UNIQUE(content_hash)` |
| AI chat message | `working.chat_message.id`, `chat_chunk_message.message_id` | **YES** | One message inside an **AI chat** — not human messaging |
| **Human messaging — first party** | `working.message` | **YES** | `projection_kind` CHECK-constrained to `'first_party'` (`sql/0026:131,154`). This is where SMS/Messenger/iMessage first-party content lives — **NOT** in `chat_*` |
| **Human messaging — acquired third party** | `working.third_party_conversation` / `third_party_message` / `third_party_message_participant` / `third_party_conversation_acquisition` | **YES** | `sql/0026:172-238`. `third_party_message.conversation_id` FKs `third_party_conversation`; CHECK `projection_kind='acquired_third_party'`. Carries its own **acquisition + approval** record |
| Party discriminator | `projection_kind`, `message_corpus` | **YES** | Both `IN ('first_party','acquired_third_party')` (`sql/0026:80,114`). Acquisition kinds in `sql/0008:61`, `sql/0016:185`: `voluntary_third_party`, `legal_process`, `public_source`, `unknown` |
| Source artifact / file | `source_id`, `source_version_id` | **YES** | One ingested file/version — the most common id in the schema |
| **Cross-medium human thread** (SMS → Messenger → iMessage → email, spanning multiple files, "platform hopping") | — | **NO — DOES NOT EXIST** | See below |
| Case | `matter_id`, `case_id` | YES | |
| Normalized record | `normalized_record_id`, `record_id` | YES | |
| Run / extraction | `run_id`, `extraction_run_id`, `raw_generation_id`, `normalized_generation_id`, `manifest_id` | YES | |

**Problem 1 — the cross-medium thread concept is ABSENT, and it's a documented requirement that
was never implemented.** Grepping `sql/*.sql`, `server/evidence/*.py`, `server/contracts/*.py`
for `context_thread`, `thread_id`, and cross-medium/platform-hopping language: **zero matches.**
But the August requirements register already specifies it: **R09** — extraction output must be
dual-granularity, a flat structured record PLUS a contextual embedding chunk carrying a
**parent-thread ID**; **R15** — the exported chronology matrix must include a
**`context_thread_id`** column. This closes the loop: the requirement predates the gap.

**Problem 2 — `conversation_id` is a name trap, and the collision is THREE-WAY.**
_(Corrected 2026-08-29 — an earlier revision of this section described a two-way ambiguity. It is
three-way; the third-party messaging tables were not accounted for.)_ `conversation_id` is a live
column in two different tables meaning two different things, with a third concept still to come:

| `conversation_id` in… | actually means |
|---|---|
| `working.chat_chunk` → `working.chat_conversation` | an **AI chat session** |
| `working.third_party_message` → `working.third_party_conversation` | a **human third-party conversation** |
| *(does not exist yet)* | the **cross-platform human thread** — must NOT reuse this name |

This is a demonstrated live ambiguity, not a hypothetical one. **Naming rule,
going forward:** the cross-medium thread, when it lands, **MUST NOT be called `conversation_id`**
— use **`context_thread_id`**, already the owner's own vocabulary (R09/R15), so this adopts
existing terminology rather than inventing new. Renaming the existing column is **NOT proposed**
— it's a live FK with a UNIQUE constraint depending on it; the mitigation is unambiguous naming
for the NEW concept plus this glossary entry.

**Structural consequence:** a cross-medium thread is **many-to-many with sources** — one thread
draws messages from multiple files across multiple mediums, and one file can contain messages
belonging to several threads. It cannot be a column on a source or a chat; it needs its own table
plus a join (thread ↔ message), the same shape as the existing `chat_chunk_message` join —
modelling it as an FK column on either side is the obvious wrong turn. It is also the **only**
identifier in this list that is **inferred, not observed** — a thread is a judgment about which
messages belong together across platforms, not something any source file declares — so it needs
provenance and a review state, exactly like `chat_chunk_lane` already carries
`classifier_id`/`confidence`/`review_status`. Reuse that established pattern rather than
inventing one. Tracked as a distinct UNRESOLVED gap below — it is broader than, and not part of,
the document-ingest work packages (WP-0..WP-11).

**Problem 3 — two thread populations, same shape, never mixed.**

> ~~Earlier revision (2026-08-29, superseded same day): "threads cross an AUTHORIZATION boundary…
> a cross-platform human conversation can legitimately contain **both** first-party messages and
> acquired third-party messages… thread membership records each member's `projection_kind`, and
> every thread read filters by approval state."~~
>
> **Superseded by owner ruling, 2026-08-29:** *"Cross-platform is only going to be first-party.
> Third party is Katrina and her friends, or Katrina and somebody else, that came from a
> third-party device. First party will platform hop."* The mixed-authorization design above was
> built on an assumption that was never confirmed and is wrong. Recorded rather than deleted so
> the reasoning is not re-derived later.

**Refined same day by the owner:** *"The third party will also platform hop, but it will not
include myself. So it needs to have the same format and the same shape. But likely different
tables."* So the first-party-only scoping immediately above is itself superseded — **both**
populations platform-hop.

**Settled model — two populations, same shape, never mixed:**

| | Members | Owner a party? | Platform-hops? |
|---|---|---|---|
| **First-party thread** | `working.message` | yes | **yes** |
| **Third-party thread** | `working.third_party_message` | no | **yes** |

A single thread is **always one population or the other**, because the defining property of each
is who is party to it. There is no mixed thread, so there is no mixed-authorization thread.

**Recommendation — separate tables, shared logic.** Follow the precedent the schema already set
one layer down: first- and third-party *messages* were NOT modelled as one table with a
discriminator. They are separate tables, each with a CHECK pinning `projection_kind`
(`working.message` → `'first_party'`; `working.third_party_message` → `'acquired_third_party'`,
`sql/0026:154,196`). Threads should mirror that:

- **Consistency.** One shared thread table would be inconsistent with the message layer directly
  beneath it, and inconsistency between adjacent layers is what produces join mistakes.
- **Safety by construction.** A query against the first-party thread table *cannot* return
  third-party rows — stronger than a `WHERE projection_kind = …` a caller can forget, and it
  matters because third-party content carries an acquisition/approval gate
  (`working.third_party_conversation_acquisition`, `docs/adr/0059-*`, tracked in `MASTER-TODO`).
- **Divergence is likely.** A third-party thread will plausibly need linkage to its acquisition
  record; a first-party thread will not. Separate tables absorb that without a nullable column
  that is meaningless for half the rows.

**Same shape means the LOGIC is shared even though the tables are not.** Threading operates on
(participant identity, normalized timestamp, medium) and is party-agnostic — one implementation
over two tables, not two implementations. The duplication is in the schema, deliberately, and
must not spread into the code.

**Authorization, correctly scoped:** a third-party thread inherits the acquisition/approval
posture of its members, so third-party thread reads are filtered by approval state. First-party
threads carry no such gate. This is a property of *which thread table is being read* — not a
per-member check inside a mixed thread.

**Identity-resolution asymmetry — size the work accordingly.** In a first-party thread one
participant is always known (the owner), which anchors cross-platform matching. In a third-party
thread every participant is someone else, so identity resolution (**R17**) is strictly harder and
has no anchor. Expect third-party threading to need materially more human review.

## CRITICAL GAP — cross-medium conversation threads (`context_thread_id`)

> Owner, 2026-08-29, elevating this above the document-ingest work below: *"That's going to need
> to be a gap that's resolved. That's actually one of the most critical things for this entire
> platform."* **This is the highest-severity finding in this document — higher priority than
> the WP-0..WP-11 document-ingest work packages below, which are comparatively narrow.**

**Why it is critical, not cosmetic.** This is a custody matter whose evidence is largely
messaging. When a conversation moves SMS → Messenger → iMessage → email, **the pattern across
platforms is the evidence.** Fragmenting that thread by source file destroys exactly what the
record is meant to show. This is register requirement **R58** verbatim: preserve full
conversational nuance rather than over-summarizing when the pattern itself is the evidence
("nuance IS the abuse") — a per-file view cannot express a cross-platform pattern no matter how
good the chunking is. It concretely blocks: **R09** (dual-granularity extraction needs a
parent-thread ID on the contextual chunk), **R15** (the exported chronology matrix needs a
`context_thread_id` column), and any chronology/exhibit that must show a conversation continuing
across platforms. Two recorded output requirements cannot be satisfied at all today.

**Design sketch (a sketch, not a decision — flagged as such):**
- **`context_thread`** — its own table. A thread is INFERRED, never declared by any source file,
  so it must carry provenance and review state: `classifier_id`, `classifier_version`,
  `confidence`, `review_status`. Reuse the exact vocabulary `working.chat_chunk_lane` already
  established (`auto_accepted` / `pending_review` / `human_approved` / `human_corrected` /
  `classification_failed`) rather than inventing a parallel scheme.
- **`context_thread_member`** — the join, many-to-many (mandatory): one thread draws messages
  from multiple files and mediums; one file can contain messages from several threads. Carries
  `thread_id`, the message/record reference, `ordinal`, `source_id`, and medium — same shape as
  the existing `chat_chunk_message` join.
- **Corrections are new rows, not edits** — the owner must be able to re-thread, and prior
  threading must survive. Reuse the append-only pattern from `timeline.event_candidate`
  (`forbid_mutation()` trigger; "a correction is a NEW row, never an edit"). This also satisfies
  **R48** (reviewer corrections persist and downstream outputs reuse the corrected version).

**Two independent linkage axes per chunk (owner follow-up, 2026-08-29) — orthogonal, not variants
of each other:**

1. **DOWN to its original source (reassembly axis).** chunk → source file, `chunk_index` for
   order, `char_start`/`char_end` for range. Scoped to ONE source file — this is what makes the
   completeness check above possible. Already exists on `working.chat_chunk`.
2. **UP to the cross-platform conversation (thread axis).** chunk → the `context_thread` that
   hops platforms. Spans MANY source files and mediums. Does not exist yet (this section).

**These cannot share an ordinal — the critical consequence an implementer will get wrong.**
Reassembly order is *within one source file* (contiguous, gap-free ranges, ordered by
`chunk_index`). Thread order is *across source files* (interleaved chronologically by normalized
timestamp). `chat_chunk.chunk_index` serves reassembly and must keep serving only that; the
thread needs its own ordering — either its own ordinal on `context_thread_member`, or ordering by
normalized timestamp (why the R05 clock-normalization dependency below is load-bearing, not
incidental). A single "position" column trying to serve both silently corrupts one of them.

**How the thread link should attach — recommend the derived path, do not add a column.** A chunk
is a slice of text; a thread is composed of MESSAGES. The natural chain is chunk → message(s) →
thread, via the existing `working.chat_chunk_message` join (`chunk_id`, `message_id`, `ordinal`)
plus the new `context_thread_member` join (`thread_id`, `message_id`, ...). **Recommendation: do
NOT add a `context_thread_id` column to the chunk table.** Thread membership is a property of
messages, not of text slices, and a chunk may span messages — deriving membership through the
message join keeps one source of truth and avoids a denormalized column that can disagree with
the join. If query performance later demands it, a materialized view or maintained
denormalization is the fix, not a hand-set column.

**Scope boundary, narrowed by owner follow-up: the thread axis applies to HUMAN-TO-HUMAN
messaging ONLY** (SMS, Facebook Messenger, iMessage, and similar) — **explicitly excluding**:
**AI chats** (ChatGPT/Claude/Gemini/Perplexity sessions — a session with an assistant, not a
conversation hopping platforms between people; no thread membership), and **document-class work
products** (the four sample files — reassembly axis only, as already stated). If a document needs
to point at a thread, that's a citation/reference, not membership — don't blur the two as
document ingest and thread work proceed in parallel.

### Glossary — naming reconciliation (owner directive, 2026-08-29: "don't conflate AI chats and
human-to-human interactions")

The parser layer already separates them correctly (`server/tools/parsers/ai_chat/` vs.
`server/tools/parsers/messaging/`) — preserve and extend that split. Storage and capability
naming do not: `working.chat_conversation`/`chat_message`/`chat_chunk` hold **AI chats only**
(migration `0024_chat_conversation_and_message.sql`), but the bare word "chat" reads as generic
conversation. Worse: **"transcript" is used on both sides** — capability `parse.transcript`
covers AI-chat parsers *and* generic markdown fallbacks, while `messages.transcript-marker`
(`parse.messages-transcript`) covers human messaging — the same word denoting two different
things, live in the registry today.

| Term | Means | Applies to |
|---|---|---|
| **AI chat** | a session with an AI assistant | `parsers/ai_chat/`, `working.chat_*` tables |
| **Message / messaging** | human-to-human communication | `parsers/messaging/`; storage is `working.message` (first party) and `working.third_party_*` (acquired) — **never** `chat_*` |
| **Context thread** (`context_thread_id`) | one human conversation spanning platforms and files | messaging ONLY, never AI chats |
| **Document / work product** | derived analytical material about the case | the four sample files |
| **Chunk** (`chunk_id`) | a retrievable slice of text | all of the above |
| **"Transcript"** | **AMBIGUOUS — avoid in new names** | currently used for both; see rules below |

**Rules:** do not use bare "transcript" in any NEW capability, table, or column name — qualify it
(`ai_chat` or `messages`) where a distinction is needed. `chat_*` is henceforth documented as
**AI-chat-only** — that's what it already means; the fix is making it explicit, not renaming a
live table.

_(Corrected 2026-08-29 — an earlier revision of this section recommended `message_*`/`messaging_*`
as a **new** convention for human-messaging storage. That was wrong: **the separation is already
built.** `working.message` (first party) and `working.third_party_*` (acquired) already exist and
already hold human messaging, discriminated by `projection_kind`. Extend what exists; do not
introduce a parallel naming scheme.)_

So the AI-chat vs human-messaging split the owner asked for is **already correct at the storage
layer**. The naming debt is narrower than it first appeared, and confined to two things: the bare
word `chat` being unqualified, and `transcript` being used on both sides of the divide.

**Migration posture — same realism as "Ingest taxonomy" above:** `parse.transcript` is a live
registry capability used by ~16 parsers; `working.chat_*` are live tables with FKs. Renaming
either is **NOT a same-turn change** and must not happen during the freeze. Adopt the glossary
for everything NEW immediately; document the existing ambiguous names with their true meanings so
no one is misled; treat any rename of `parse.transcript` or `chat_*` as a separate, later,
explicitly-scheduled change — tracked as known naming debt, not silently forgotten.

**Naming resolved:** keep `chunk_id` — it already exists (`working.chat_chunk.id`), is already
used in `chat_chunk_message`, `chat_chunk_lane`, `chat_chunk_embedding`, `chat_chunk_projection`,
and is unambiguous. The ambiguity is with `conversation_id` (see "Identifier taxonomy" above),
not with `chunk_id` — no rename needed.

**Hard dependencies — name them, they decide feasibility.** Threading across mediums is not
primarily a schema problem:
1. **Party identity resolution across platforms (R17)** — normalize people so the same human is
   recognized despite differing representations (a phone number in SMS, a Facebook user id in
   Messenger, an address in email). Without this, threads cannot be assembled correctly.
   `server/tools/parsers/messaging/_source_parties.py` exists and is the natural place to check
   what identity handling already exists — start there rather than assume nothing exists.
2. **Timestamp normalization to a single timezone at ingest (R05)** — interleaving messages from
   different mediums into one ordered thread is wrong if their clocks aren't normalized; the
   register separately warns that source clocks must be verified.

**Attempting the thread table before identity resolution and clock normalization will produce
confidently-wrong threads — in an evidence context, worse than no threads at all.**

**Recommendation (for the owner to decide, not an action taken here):** this likely warrants its
own ADR or a dedicated handoff, rather than living permanently inside a document-ingest handoff.
Also queued separately (not nested under document-ingest) in `docs/MASTER-TODO-2026-08-18.md`.

## HARD CONSTRAINT — Semantica atomic tool vs Semantica lane

> _Owner ruling, 2026-08-29._

Two different things share the name "Semantica" and they have **opposite authorizations**:

| | Authorization |
|---|---|
| **Semantica as an ATOMIC TOOL** — calling `StructuralChunker` or a single `parse/` module directly to parse/chunk one document | **ALLOWED NOW.** Use it this way. Owner: *"if one of the bundled semantica tools will work, we can call on those… we're going to utilize that tool atomically."* |
| **Semantica as an EXTRACTION LANE** — content flowing through the Semantica pipeline for entity/fact/event extraction | **BLOCKED until change detection is ordered.** Semantica is downstream of context creation and is triggered by change detection; it must not run ahead of that ordering |

Why this matters: Semantica is one half of the `no-fusion` dual-lane comparison
(`GraphRagLane.semantica` vs `GraphRagLane.sat_temporal`). Running its extraction lane before
change detection is ordered breaks D-069 context-first ingest and invalidates the comparison —
the two lanes must observe the same ordered context state to be comparable at all.

**Do not read WP-5 as authorization to wire the Semantica lane.** WP-5 is an atomic call for
document structure only. Lane activation is WP-6+, gated on WP-1.

## HARD CONSTRAINT — Local-model routing (Portkey first, Colab only as narrow exception)

> _Owner directive, 2026-08-29 (addendum, corrected twice same day — Colab is the exception, not
> the default; gateway routing added)._

**Model-backed work routes through Portkey — the established model gateway**
(`docker/gateway/portkey/`, `portkey/configs/embed.json` for NVIDIA `nv-embed-v1`,
`x-portkey-config` header wiring at `server/core/session.py:210`, `graphiti-portkeyfix` sidecar
injecting `custom_host=integrate.api.nvidia.com` at `deploy/compose.yaml:207-208`,
`deploy/portkey.yaml`) — **to a remote provider** (NVIDIA NIM, Ollama Cloud, or any free-tier
API) **as the normal path.** This is the general form of the same no-local-models policy that
sets `HF_HUB_OFFLINE=1` / `TRANSFORMERS_OFFLINE=1` on this machine. Never write code that calls
a provider (NIM, Ollama Cloud, etc.) directly — route it through Portkey, which is also what
keeps the provider swappable.

**Colab (via the Colab MCP) is ONLY for the specific applications that require a local model
with no API equivalent.** Owner: *"It's only specific applications that require local models
that are not available on an API that have to be used that way."* Do not default model-backed
work to Colab — check for a Portkey-routed remote-API equivalent first. If that narrow case is
ever hit, the Colab MCP is an MCP server like any other and must be reached through
**ContextForge** (`CF_GATEWAY_URL`/`CF_GATEWAY_TOKEN`, resolved via docker-DNS name
`contextforge` on the shared `agno` network, `deploy/exec.yaml:24-26,109`;
`deploy/contextforge.yaml`) — never wired as a direct client.

Applies to Chonkie `SemanticChunker` / `NeuralChunker` / `LateChunker` / `SlumberChunker`, any
embedding-backed chunking (`NimEmbedder`, `server/core/embedder.py:26`, subclasses
`OpenAIEmbedder`, already routes NIM calls this way), and the extraction-quality scorer discussed
in WP-5d below if that scorer turns out to be model-backed.

**Verified caveat:** the Colab MCP was NOT connected in the session that produced this handoff —
a tool search for it returned no Colab tools — and it would additionally need to be exposed
through ContextForge. If a genuine local-model-only application is ever identified, confirm both
before relying on it; do not assume it is callable.

## Tool colocation — a Go tool does NOT need to live with the Go engine

> _Owner question, 2026-08-29: everything together as far as tools go — does the Go tool have to
> reside with the Go engine, or can it move to platform-tools?_

**Answer: it can move, and the precedent is already in production.** `platform-tools` is ALREADY a
polyglot container. From `docker/tools/Dockerfile`:

- `:34` — `FROM ghcr.io/cursedpotential/sbv-forensic@sha256:18a2a21c… AS sbv` (a **Go** binary,
  pinned by digest)
- `:37` — its own comment: *"Final image: python facade + the SBV binary/assets lifted from the
  sbv stage."*
- `:43` — `FROM python:3.12-slim`
- `:48-50` — `COPY --from=sbv /app /opt/sbv`, plus the musl loader and libs
- `:66` — `COPY server/ /opt/tools/server/` (the Python tool registry)
- `:71` — `CMD ["supervisord", …]` running both

So Go and Python tools already share one container, one image, one supervisor. **A Go chunker
joins the same way SBV did:** a Go build stage, a `COPY --from`, a third supervisord program, and
an entry in the registry manifest. No new pattern, no new infrastructure.

### The SBV GUI is unaffected — verified

`docker/tools/supervisord.conf` defines two **fully independent** programs:

    [program:sbv]           command=/opt/sbv/sbv                       # port 8085, autorestart
    [program:tools-facade]  command=python -m uvicorn facade:app … 8090

Separate processes, separate ports, independent `autorestart`. Adding a third program touches
neither. **The SBV GUI on `:8085` is preserved as-is.**

### OPEN QUESTION — what is the SBV GUI FOR? (owner intent vs. current deployment)

> _Owner, 2026-08-29: "The SBV GUI is supposed to be the front end — the preview window, the
> client — that sits above and can call on the Go agent and the different workflows, and view
> things as they go through the pipeline."_

**That intent does not match where it currently sits, and it overlaps a surface already in
flight.** Flagging rather than encoding, because it is an owner call with deployment consequences.

**Current reality (verified):**
- SBV GUI runs as a supervisord program **inside** `platform-tools` on `:8085` — i.e. colocated
  with the tools, not above them.
- It is essentially the **upstream** viewer. Per the 2026-08-23 audit of `sbv-forensic`, its React
  frontend has **zero references** to hash, custody, or automation — the forensic layer added by
  the fork is wired end-to-end at the HTTP/DB level and **never surfaced in the UI**.

**Surfaces that already exist or are in flight:**

| Surface | Deployment | What it is |
|---|---|---|
| **Workbench / UIW** | own Coolify app, ovh-app `100.72.169.40` | `deploy/workbench.yaml` byline (2026-08-28): *"unified UIW production surface"*. **Codex's #1 active priority** — "finish and live-prove the Workbench/UIW release" |
| **unified-operator-surface** | own app, `:8020` | `deploy/unified-operator-surface.yaml`: *"Approved unified-operator-surface **Vite prototype**"*, built from `workbench/design-mockups/` |
| **SBV GUI** | inside `platform-tools`, `:8085` | upstream SMS viewer; no custody/automation UI |

**The fork:**
- **(a) SBV GUI becomes the pipeline preview.** Then it must move OUT of `platform-tools` — a
  client that calls the coordinator should not live inside the tool container it calls. That
  contradicts the colocation described above, changes the deployment, and means building the
  custody/automation/workflow views that its frontend does not currently have.
- **(b) Workbench/UIW is the pipeline preview**, and SBV GUI stays a specialised **message
  viewer**. The preview deep-links *into* it ("open this conversation at this message") rather
  than reimplementing message rendering.

**RECOMMENDATION: (b).** Workbench/UIW is being built for exactly this role, is the active
critical path, and forking a second operator surface duplicates in-flight work. SBV GUI's real
near-term value is as the thing that renders a conversation well — which the pipeline preview
should link to, not rebuild.

> **SUPERSEDED by the owner, 2026-08-29.** The binary choice and recommendation above were
> framed incorrectly. Workbench and SBV are not competing preview products, and SBV is not merely
> a deep-link target. Workbench owns the unified shell, fixed case context, navigation, and access
> boundary. The refactored SBV client is the bounded preview application composed inside that shell:
> it renders messages and the live Go/Temporal/n8n pipeline state. The Vite
> `unified-operator-surface` remains a design donor/prototype, not a third production application.

### RESOLVED by owner, 2026-08-29 — SBV becomes a pure VIEWING CLIENT

> _Owner: "The SQLite-backed stuff is all supposed to be separated out and refactored so that SBV
> is just a viewing client. All of the processes in the ingestion — including SMS — follow the
> same contract."_

This **supersedes the fork above rather than selecting either branch**: SBV stops being a
self-contained application and becomes the **pipeline-preview client inside the Workbench shell**,
reading the platform's canonical store and workflow receipts through bounded APIs.

Those APIs must be UIW-native and correlation-aware. The preview client may hold a UIW workflow ID,
source-version reference, and correlated platform run ID only after the BFF has verified their mapping.
It must not send a UIW identifier to legacy `/v1/records` or legacy run-event SSE as if an equal string
proved identity; absent a verified mapping, records/events are unavailable and the client fails closed.

**Three separations follow:**

| SBV layer today | Destination |
|---|---|
| **Storage** — per-user `sbv_<uuid>.db`, shared auth `sbv.db`, `messages`, `messages_fts`, `imports` | **Retired.** Platform tables own this — `working.message` / `working.third_party_message` and the content-chunk spine |
| **Parsing** — `internal/parser.go` | **The Go engine adapter.** `engine/adapters/sbv/` already exists as the coordinator-side seat for it |
| **Hash implementation** — `internal/custody.go` / `pkg/custodyhash` | **Decoupled deterministic capability, never parser authority.** UIW uses separately named context fingerprints; promotion-time custody dispatches the exact evidence canon tuple. See the correction below |
| **Frontend** — the React viewer | **Stays as the embedded pipeline-preview client inside Workbench**; it reads platform data and run events, renders messages, and owns no canonical state |

### DATED CORRECTION — hashing was separate, but the custody boundary below is superseded

> **Preserved history; not current architecture.** This 2026-08-29 correction correctly separated
> hashing from parsing, but it still described the old intake-time evidence-custody workflow. D-069,
> the R04 reviewed boundary, and ADR-0061 supersede that part: UIW's pre-parse hashes are context
> fingerprints, while evidence H1/H2/H3 begins only at governed promotion.

> _Owner, 2026-08-29: hashing is always a separate activity in n8n/Temporal — already discussed
> and resolved. (Caching may follow the same pattern.)_

_An earlier revision of the table above listed "Parsing **+ custody hashing**" as a single
destination. **That was wrong and is corrected.** They are deliberately separate activities._

**Verified in code:** `custody_activity` is its own Temporal activity
(`server/temporal/activities.py:149`), and it runs **first** in the chain —
`workflows.py:174` documents the order as **`custody -> parse -> store -> knowledge`**, with the
stages set at `:223` (custody), `:242` (parse), `:256` (store). Hashing has never been inside
parsing; the separation is already the shipped contract.

**So for the SBV port:** its parser goes to the Go adapter under the *parse* activity, while
H1/H2/H3 belong to the *custody* activity that already precedes it. Porting them as one unit
would collapse an existing, deliberate boundary — and would put hashing downstream of parsing,
which inverts the order the platform relies on (hash the bytes as received, then parse).

**Inherit this trap while you are in there.** `custody_activity`'s own docstring records a real
production false-success:

> *"`duplicate=True` is also what produced the real prod false-success documented at
> `workflows.py:36-44` (knowledge fails → operator retries → custody dedupes → store sees 0 new
> rows → the run reports completed with `docs_ingested=0`)."*

Document ingest travels the same path, so it inherits the same failure: a retry after a downstream
failure can report **completed with zero documents ingested**. `store_activity` reuses
`_store_step_impl`'s guard rather than re-deriving it — keep any new document-ingest path on that
same guard rather than writing a parallel dedupe branch.

### CURRENT CORRECTION — context fingerprints first; evidence custody only at promotion

The common UIW runs separate context-source, raw-record, and raw-generation fingerprint activities
before parser execution. They protect intake integrity and reproducibility but create no evidence
authority and must never be labeled custody H1/H2/H3. The parser remains separately selected by the Go
coordinator and emits through the common contract.

Only the governed evidence-promotion workflow may establish custody. It re-opens the retained original,
recomputes H1, verifies every H2 over the pinned canonical normalized bytes in the frozen generation
order, and constructs/verifies H3. Verification dispatch is by the full canon tuple — algorithm, hash
level, canonical byte recipe/serializer version, ordered membership definition, construction tag, and
writer/version — never by the bare name "H3." The platform promotion construction is
`h3-chain-h1genesis-hexconcat-v1`; the SBV empty-genesis/newline construction remains a separate import
receipt and cannot satisfy promotion.

**SMS stops being special-cased.** Today SMS enters through a bespoke arrangement — `sbv_sms.py`
registers `parse.sms-xml` at `priority=100` and its `accept` predicate additionally requires
`_sbv_enabled()`, so ingest depends on a *separate running service*. Under the same-contract rule
SMS becomes an ordinary parser emitting the same normalized records as every other format, and the
"SBV is down, so the non-hashing fallback silently takes over" hazard recorded earlier disappears
with it.

### What this does to previously-reported SBV defects — re-triage

Several defects I recorded on 2026-08-23 live in the layer being retired, and several do not. The
distinction matters, because the second group **carries over into the adapter** unless fixed
deliberately.

**Evaporate with SBV's storage layer (no action needed):**
- Re-ingest dedup keyed on `(record_type, address, date, type, body, …)` **excluding**
  `content_hash` — dedup on normalized equality rather than raw-byte identity. A property of
  SBV's own `messages` table.
- `messages_fts` indexing `body` only, leaving call logs unsearchable. Platform search replaces it.
- `InsertCallLogBatch` omitting `content_hash` — dead code in a retired store.

**CARRY OVER into the engine adapter — these are PARSING behaviour, not storage:**
- ~~**Multi-attachment MMS keeps only the first part.** `convertMMSEntry` guards with
  `if msg.MediaType == "" { // Only store first media item }`. That is a decode-time decision, so
  porting the parser ports the data loss. **Fix during the port, not after.**~~
  **Superseded 2026-08-29:** current `streamMMSRecord` iterates every `<part>`. The current blocker is
  the parse-only boundary: attachment artifacts have no immutable platform sink/locator, and the SBV
  adapter advertises `SupportsAttachments: false` and fails closed rather than silently dropping them.
- **`extractGroupNameFromTrID` is a live no-op** returning `""` — RCS group-chat names silently
  dropped at parse time.
- ~~**H3 chains do not span import batches** — `ChainH3(recordHashes, "")` at the only production
  call site. This is a custody-stage defect. **Do not move that hashing call into the parser
  adapter**; reconcile it inside the separately versioned custody activity/canon.~~
  **Superseded boundary:** the SBV empty-genesis chain is a generation-scoped context/import receipt,
  not evidence H3. Promotion independently builds/verifies the complete platform custody generation
  under `h3-chain-h1genesis-hexconcat-v1`; readers dispatch by the full canon tuple.

**Remains a frontend gap:** SBV's React frontend has *zero* references to
hash/custody/automation. Because SBV is the preview client composed inside Workbench, it must
surface the platform's custody receipts and workflow state without computing or owning either.

### DO NOT MIGRATE SBV's SQLite MEDIA — RE-INGEST FROM THE RETAINED SOURCES

Two verified facts collide here, and the collision is the whole point:

1. SBV's historical per-user SQLite stores MMS attachments as `media_data` BLOBs and may be lossy.
   The old `convertMMSEntry` first-media behavior explains affected historical rows, but it is not the
   current decoder: `streamMMSRecord` now walks every part. Current platform re-ingest is blocked until
   `pkg/parseonly` can hand every artifact/reference to an immutable platform attachment locator and the
   adapter can truthfully set `SupportsAttachments: true`.
2. SBV **never deletes its source files.** Auto-import moves the source to
   `data/<uuid>/complete/` and retains it; the headless extract path opens the source read-only
   and explicitly keeps it as evidence.

**Therefore: SQLite remains the wrong migration authority. Re-ingest from retained source XML after the
immutable attachment sink/locator exists, then prove every part through the platform read path.**

This inverts the usual migration instinct — the old store is *lossier than its own inputs*, so the
inputs are the better migration source. Any "caller and data migration proof" for the retired
storage paths must therefore compare against the **source files**, not against the SQLite it is
replacing; a SQLite-to-Postgres row-count match would prove the migration faithful and the corpus
still incomplete.

Practical consequence for the quarantine gate: retain `data/<uuid>/complete/` until re-ingest is
proven, and treat it — not the SQLite — as the authority for what *should* be present.

### CARRY-OVER DEFECTS — "move SMS decoding behind the contract" ports these unless fixed

Three of the defects re-triaged above are **parse-time**, so porting the decoder ports them. They
are easy to miss because they read as storage bugs and are not:

- ~~**Multi-attachment MMS keeps only the first part** (`convertMMSEntry`) — decode-time.~~
  **Superseded:** current `streamMMSRecord` iterates every part; the carry-over defect is the missing
  immutable parse-only attachment sink/locator plus adapter `SupportsAttachments: false`.
- **`extractGroupNameFromTrID` is a live no-op** returning `""` — RCS group names dropped at parse.
- ~~**H3 chains do not span import batches** — `ChainH3(recordHashes, "")` at the sole production
  call site; fix this within the separately versioned custody activity/canon, not the parser
  adapter.~~ **Superseded:** this is an SBV context/import construction, not platform evidence H3;
  the promotion verifier owns the distinct full-generation custody construction.

Fix them **during** the port. Porting first and fixing later means a second pass over every record
already ingested under the ported decoder.

**Sequencing:** this refactor is **not** derived-document work and must not be started inside this
lane. It belongs with the Workbench/UIW and Go-adapter lanes, and it has a hard prerequisite —
`engine/adapters/` currently holds exactly one adapter, so the SBV port is also the proof case for
adapter coverage generally.

### INHERIT THIS GOTCHA when adding the Go chunker

The SBV program block carries a hard-won note in-line:

> *"Multi-stage COPY does not inherit the source image's `DB_PATH_PREFIX`. Pin it to the deployed
> bind mount so auth, per-user databases, and import artifacts survive container replacement."*

That is the trap for any Go binary brought in by `COPY --from`: **the source image's `ENV`
defaults do not come with the binary.** SBV needed both `LD_LIBRARY_PATH="/opt/sbv-libs"` (because
its musl libs were copied to a non-default path) and `DB_PATH_PREFIX` re-pinned explicitly, or
state would not survive a container replacement.

So when the Go chunker lands: enumerate every `ENV` its own image sets, and re-declare each one in
its supervisord `environment=` line. A chunker is more stateless than SBV so the blast radius is
smaller — but the failure mode is silent (it runs, then loses or misplaces state on replacement),
which is exactly the kind that reaches production.

### But draw one line: TOOLS colocate, the COORDINATOR does not

- **Go chunker (a TOOL)** → belongs in `platform-tools` beside the Python tools. It is selected
  and invoked like any other tool.
- **Go coordinator (`engine/parser/registry.go`, the SELECTOR)** → must stay ABOVE the tool hosts.
  It decides *which* tool runs, and it needs to select across more than one host — `platform-tools`
  (Python tools + Go tools) and `parser-activity-runtime` (Go SBV) are different Coolify apps on
  different machines. Putting the selector inside one of the things it selects from creates a
  circular shape and caps it at whatever that container happens to hold.

Short form: **everything callable in one space; the thing that chooses among them sits one level
up.** That is the same split already recorded as "platform-tools provides EXECUTION, `engine/parser`
provides SELECTION."

### Consolidation opportunity worth deciding

There are currently **two Go-hosting tool services on two hosts** — `platform-tools` (OVH-1, the
facade on `:8090` plus SBV on `:8085`) and `parser-activity-runtime` (ovh-files, a Go binary on
`:8090`). Both exist to run parser tools. Folding `parser-activity-runtime`'s binary into
`platform-tools` the way SBV was folded in would genuinely deliver "everything together," remove a
duplicate deployment, and end the `:8090`-on-two-hosts ambiguity flagged earlier.

Not recommended unilaterally — `parser-activity-runtime` has its own bind mount
(`/data/agno/volumes/universal-import/parser-bundles`) and watch paths, so consolidation is a
deployment decision with a data-locality question attached, not a refactor. Flagged for the owner.

## Where this gets installed

> _Verified 2026-08-29 (addendum, updated same day once the bridge substrate was confirmed)._
> Answers "where does a new parser dependency actually land" and "how does the Go coordinator
> reach a Python parser" — see "Orchestration and the quality gate" below for how selection and
> execution divide.

- **The callable-tool space is `server/tools/`, by design (D-026).** `server/tools/AGENTS.md`:
  *"The atomic-tool capability layer (D-026): a **polyglot registry** consumed by `evidence/`,
  `analysis/`, `agents/`, workflows, and the CLI — not owned by any one domain."* **Polyglot is
  the operative word** — the registry was designed from the start to front non-Python tools, and
  `@register` appears ONLY under `server/tools/` today (verified: zero strays elsewhere in
  `server/`). Precedent for fronting an out-of-process engine from inside the registry already
  exists: `server/tools/_sbv_client.py` is an SBV REST client shared by `sbv_sms.py` and the
  `docker/tools` facade. WP-6a's Go-adapter-fronting-`platform-tools` design is the mirror image
  of a pattern this repo already runs — see WP-0 for the consolidation gap this implies.
- **`platform-tools`** (Coolify app `exec-platform-tools` on **OVH-1**, `deploy/platform-tools.yaml`)
  runs the Python FastAPI facade `docker/tools/tools/facade.py`, which **volume-mounts the
  `server.tools` package** so its inventory and execution surface stay in sync with the registry
  (D-026). Port **`:8090`** (`"${BIND_IP:-127.0.0.1}:8090:8090"` — parsers/extractors facade,
  tailnet-only; port `8085` on the same container is the SBV GUI). Reachable cross-app over the
  shared external `agno` docker network by DNS name `platform-tools` — this is already how
  `agentos-api`/`agentos-mcp` reach it (`SBV_BASE_URL=http://platform-tools:8085`).
- **Verified routes:** `GET /health` → `registry_ok`/`registry_error` + the sorted tool-id list;
  `GET /tools` → full manifest (id, capability, description, provenance); `GET
  /tools/resolve/{capability}?hint=&size=` → ordered substitution candidates for a
  capability+input; `POST /tools/{tool_id}/run` with a contract payload (e.g. `{"path":
  "/r2/..."}`) → executes one atomic tool and returns its result. Errors: `422` = contract
  rejection/wrong format ("caller should try resolve() alternatives"), `404` = unknown tool or
  file not found, `503` = registry load failure (degrades, never crashes).
- **This IS the Go→Python bridge for parser execution** (see MIGRATION CONSTRAINT above for the
  dated correction). **Authority split, stated explicitly:** `platform-tools` provides
  **execution**; the Go coordinator (`engine/parser`) retains **selection**. A Go adapter fronting
  this facade must use `GET /tools` for discovery and apply its OWN `Capability`/
  `QualityFor(format)` to choose — it must **not** trust `GET /tools/resolve`'s ordering, which is
  exactly the Python priority-0/alphabetical mesh flagged for removal. Getting this backwards
  re-imports the rejected behavior into Go. See WP-6a for the adapter and its capability/quality
  mapping design.
- **Separately, `deploy/parser-activity-runtime.yaml`** is a **different** Coolify application on
  **ovh-files** — also HTTP, coincidentally also on `:8090` (different host, different app, not a
  conflict today — do not wire the wrong `:8090`), token-auth (`PARSER_ACTIVITY_TOKEN`), a
  parser-bundle volume at `/data/agno/volumes/universal-import/parser-bundles`, watch paths
  `engine/**`, `vendored/sbv/**`. Its `docker/parser-activity-runtime/Dockerfile` is **Go-only**
  (`FROM golang:1.25-bookworm AS builder` → `debian:bookworm-slim`, one static binary,
  `ENTRYPOINT ["/usr/local/bin/parser-activity-runtime"]`) — it does not run Python and is not
  the bridge; `platform-tools` is.
- **Python parsers ship in the MAIN image**, built by the root `Dockerfile` via
  `RUN uv pip sync requirements.txt --system`. Consequence: **any new Python dependency must be
  added to `requirements.txt` and the main image rebuilt/redeployed** — a `pyproject.toml` extra
  alone (e.g. `document-ai`) never reaches production. This is exactly why Docling and the OCR
  tier are declared but absent at runtime today (see the Docling/Tesseract rows above and Pending
  owner decision #3).
- **Consolidation gap (WP-0):** Semantica's 17 `parse/` modules and `StructuralChunker`, plus
  `server/analysis/chonkie_chunkers.py`, are real working code that is **not** `@register`ed
  under `server/tools/` today — so none of it is yet reachable via `GET /tools` /
  `POST /tools/{id}/run`, and therefore not yet reachable from the Go coordinator either.
  Registering them is not extra work on top of the bridge — **it delivers the bridge** for those
  modules, with no Go-native rewrite required.

## Orchestration and the quality gate

> _Owner directive, 2026-08-29 (amended by a same-day addendum: parser SELECTION lives in the Go
> coordinator, not in n8n, Unleash flags, or Python)._

> **Caveat:** `engine/` is in Codex's active dirty set this session (`engine/activities/`,
> `engine/stagegraph/`, `engine/uiw/` all modified) — the `engine/parser/*.go` symbols cited below
> are especially volatile even by this document's usual standard; anchor on symbol names
> (`Registry.Select`, `Capability.QualityFor`, `ExecuteSelected`), not the line numbers given.

- ~~**n8n orchestrates.** It is the orchestrator; the whole point of n8n here is to utilize the
  tools. Every custom tool to date is wrapped in an n8n code node — follow that pattern.~~
  **Superseded boundary:** n8n owns visual integration/agent workflow bodies, notifications, and
  human-facing signals. Temporal is the durable spine and the only scheduler of load-bearing
  activities. n8n starts/signals Temporal or is invoked by a bounded Temporal activity; it does not
  replace durable sequencing.
- **The Go coordinator selects and executes the parser.** `engine/parser/registry.go:63`
  `Registry.Select(format)` already implements quality-ranked, declared-coverage adapter
  selection — documented "Quality breaks [ties]" — using `QualityPrimary` / `QualityFallback` /
  `QualityExperimental` (`engine/parser/parser.go:69-95`), where each adapter declares its own
  `Capability.QualityFor(format)` (`parser.go:151`). This IS the multi-approach mechanism the
  owner asked for: alternates are registered adapters with a declared quality, not
  exception-chained fallbacks. n8n calls into this selection+execution; it does not reimplement
  it.
- **Temporal executes durably.** n8n runs the extraction as a Temporal **activity** (bridge
  already exists: `n8n_webhook_activity`, `server/temporal/n8n_activities.py`, registered on the
  worker in `server/temporal/worker.py`); that activity is what invokes the Go coordinator's
  `Select` + `ExecuteSelected` (`registry.go:158`), which pins the exact `parserID`/
  `parserVersion` used, giving deterministic replay.
- **For Python-implemented adapters, execution routes through `platform-tools`**
  (`deploy/platform-tools.yaml`, port `:8090`, `POST /tools/{id}/run`) — but selection stays with
  the Go coordinator's `Capability`/`QualityFor(format)`, never `platform-tools`' own `GET
  /tools/resolve` ordering. See "Where this gets installed" and WP-6a.
- **A model or worker then scores the extraction QUALITY / confidence** — this is a distinct
  evaluation step after the activity returns, not part of the parser (atomicity constraint, see
  "PARSE vs CHUNK" and WP-5d).
- **If quality/confidence is low, OR the extraction failed, the workflow calls `Select` again for
  the next-best declared quality and executes that DIFFERENT adapter — before the workflow moves
  on.** The retry is quality-ranked adapter substitution inside the Go coordinator, not a re-run
  of the same activity and not a Python-side exception catch.

**This is quality-gated method substitution using the Go coordinator's existing declared-quality
registry, NOT the exception-chained fallback mesh the owner rejected, and NOT a parallel
selection scheme invented in Python or n8n.** The discriminator is an extraction-quality score,
not a caught exception. Each candidate method is its own registered `Adapter` with its own
declared `Quality`, so the substitution is explicit, durable (both attempts are recorded via
`ExecuteSelected`'s immutable capability snapshot, `registry.go:74`), observable in workflow
history, and individually retryable.

This supersedes the purely static "flag-selected alternates" framing in the Parser strategy
section below: **selection is the Go coordinator's job** (`engine/parser`), not a Python
`format_router` priority list or a bare Unleash flag pick. Named flags still gate which adapters
are *registered* as eligible; the Go registry's declared `Quality` decides ranking among them,
and the runtime choice on a failing score is made by the quality gate calling `Select` again. See
WP-5d.

## MIGRATION CONSTRAINT — Python router removal, sequenced on Go adapter coverage

> _Owner directive, 2026-08-29: "That Python router needs to just be flagged for removal."_
>
> **Dated correction (2026-08-29, same session).** An earlier draft of this section stated "no
> Go→Python bridge adapter exists" and called that the single biggest open blocker on this
> migration. **That was wrong and is superseded here** — the bridge substrate already exists in
> the repo. See "Where this gets installed" below for `platform-tools`. Do not act on the earlier
> "no bridge" framing; the corrected picture follows.
>
> **Second correction (2026-08-29, from Codex reconciliation).** The phrase "and is already
> deployed" appeared here and is an **overclaim, now withdrawn**. What was verified is that
> `deploy/platform-tools.yaml` and `docker/tools/tools/facade.py` exist in the repo, with routes
> and a documented cross-app DNS contract. **Nothing in this audit confirmed a running container.**
> Manifest present ≠ service live — the same distinction the platform already learned the hard way
> with migrations (R68: "design complete" and "deployed to the live database" are two separately
> verified states). **Before building the Go bridge adapter, curl `platform-tools:8090/health` and
> confirm `registry_ok: true`.** The same caveat applies to any statement in this document that the
> timeline machinery is "tested" — 392 lines of tests exist; this audit did not run them.

**Still true and still load-bearing:** `engine/adapters/` currently contains exactly **ONE**
adapter — `sbv/`. There are no document, markdown, or AI-chat adapters yet. Meanwhile the
**Python registry holds 25 registered parsers, 16 of which accept `.md`/`.txt`.**

**Corrected:** the Go coordinator is not missing a way to reach Python parsers. `platform-tools`
(`deploy/platform-tools.yaml`, Coolify app on OVH-1) already fronts the Python tool registry over
HTTP on `:8090` (`GET /tools`, `POST /tools/{id}/run` — see "Where this gets installed"). The
vendored Semantica `parse/` modules, `StructuralChunker`, and Chonkie remain usable from the Go
coordinator once registered as Python tools with `@register` — **this migration does not force a
Go-native rewrite of every parser.** What remains open is narrower: the `capability`→`FormatID`
mapping, and who declares `QualityFor(format)` on behalf of each Python-fronted tool — design
work, tracked as **WP-6a**, not a missing mechanism.

So `format_router.py` and the Python parser-selection mesh around it
(`chat_parse.py::_parse_via_registry`, `registry.resolve` priority ordering,
`service.py::_parse`'s try-next-candidate loop) are **flagged for removal — not extended** — but
removal is still **sequenced on Go coordinator adapter coverage existing for the formats those
parsers serve.** The required order:

1. Prove a candidate parser standalone on the four sample files (**WP-5c — safe to run now, not
   blocked on anything below**).
2. Register it as a Go `Adapter` with a declared `Capability` / `QualityFor(format)`, fronting it
   through `platform-tools` where the implementation is Python (**WP-5b** / **WP-6a**).
3. **Only once Go coverage exists for a given format** does the Python path for that format get
   removed.
4. `format_router.py` is deleted **last**, when nothing routes through it any more.

Do not read this as authorization to delete `format_router.py` or the registry mesh now — an
unqualified removal would break every currently-working ingest path. See WP-2 (inverted) and
WP-4 (downgraded) below.

## Parser strategy — multiple approaches, deliberately selected (selection lives in the Go coordinator)

> _Owner directive, 2026-08-29: "I would like to have multiple approaches for parsing these
> things out, in case one of them doesn't work the way that we expect." Amended same day: "Parsing
> should all be coordinated through the GO coordinator. The Go parsing coordinator can call on
> whichever parser is best for that particular document. So for testing, validate that any one of
> the parsers work and then it gets written into the Go orchestrator."_

This is **not** a return to the exception-chained fallback mesh (owner rejected that: routing
must be by analysis, not by retry-until-something-doesn't-raise) — and, per the same-day
amendment, it is **not a Python `format_router` priority scheme either.** The contract is:

- **The Go coordinator (`engine/parser`) owns selection**, via `Registry.Select(format)`
  (`registry.go:63`) and each adapter's declared `Capability.QualityFor(format)`
  (`parser.go:151`, `QualityPrimary`/`QualityFallback`/`QualityExperimental`, `priority()` at
  `parser.go:69-95`). `format_router.SIGNATURES` in Python still does upstream format
  DETECTION (what kind of file is this); it is not where selection among competing parser
  implementations belongs going forward. For Python-implemented adapters, execution is fronted
  by `platform-tools` (`:8090`); selection never defers to that facade's own `/tools/resolve`
  ordering — see WP-6a.
- **Alternates are registered adapters with an EXPLICIT declared quality** — `QualityPrimary` /
  `QualityFallback` / `QualityExperimental` — never left to `pkgutil` alphabetical order or an
  undeclared Python priority.
- **Named Unleash flags gate which adapters are registered/eligible at all**; the Go registry's
  declared quality decides ranking among eligible adapters, and the runtime choice on a failing
  score is made by the quality gate ("Orchestration and the quality gate" above, WP-5d), not by a
  static flag pick or an operator hint alone.
- **A failure or a low-confidence score on the selected adapter triggers `Select` again for the
  next-best declared quality (WP-5d)** — never a silent slide into a lesser parser outside that
  mechanism. `ExecuteSelected` (`registry.go:158`) pins the exact `parserID`/`parserVersion` used
  each time, so both attempts are recorded for deterministic replay. Only exhausting every
  registered adapter without a passing score is a hard, logged error naming the file.

### PARSE vs CHUNK — a strict contract (owner invariant, 2026-08-29)

> Owner: *"Every single parser has the same contract and the same destinations. And they're
> entirely atomic. And they do one thing, they parse, they do nothing more."*

- **Uniform contract.** Every registered parser takes the same payload shape (`{"path": ...,
  "source_meta": ...}`) and returns the same shape (`{"records": [...], "stats": {...}}`) — this
  is what lets `POST /tools/{id}/run` front any of them generically and what lets
  `_parse_via_registry` swap candidates. The Go side mirrors it: `ParserInput` →
  `RawRecordEnvelope` via `BundleWriter`.
- **Same destinations.** Parsers do not choose where output goes. They emit normalized records;
  the pipeline decides storage, lane, and projection. Lane assignment is a pipeline/caller
  decision (Pending owner decision #1 below) — no work package here proposes a parser that picks
  its own lane.
- **Atomic, single-purpose.** A parser parses. It does **not** chunk, embed, classify, score,
  route, or assign lanes.

**Correction this forces, applied throughout this document:** `StructuralChunker` and the
Chonkie chunkers (candidates A/C/D/E below) are **CHUNKERS, not parsers.** If registered under
`server/tools/` (WP-0), they must carry a DISTINCT capability — e.g. `chunk.text` /
`chunk.structural` — never `parse.transcript` or any `parse.*` id. Anywhere earlier text in this
document calls `StructuralChunker` a "parser" or implies the `.md` **parse** stage itself must
preserve `##` boundaries, read that as superseded here: boundary preservation is a **chunk-stage**
concern (WP-5/WP-5c below), not a parse-stage one. The **parse** stage for this content class is
comparatively simple: does a document parser emit ONE record per document, or one record PER
SECTION? Both are contract-legal (chat parsers already emit one record per message — multi-record
output is normal) — **recommendation: one record per document at the parse stage**, keeping the
parser dumb and uniform, and let a structure-aware chunker (chunk stage) own section granularity,
since heading-based segmentation is a semantic/retrieval-tuning judgment that should be changeable
without touching the parser.

### Ingest taxonomy — parse vs extract vs chunk (owner reframing, 2026-08-29)

> Owner: *"Chunking can be separate... If it doesn't need to be parsed and it really needs to be
> chunked and ingested, then so be it."*

**The insight:** parsing means decoding a *structured export format* into records — a ChatGPT
JSON export, an SMS Backup XML, a Facebook HTML dump each have a format to decode. **A markdown
document has no format to decode. It is already text.** This reframes a finding this document
otherwise presents as a defect: 16 registered parsers accept `.md`/`.txt` and every one fails on
document-class markdown. That is not primarily a missing-signature bug — **it is a category
error.** These four files were never parse-stage inputs; `transcripts.markdown` (the whole-file
fallback) exists precisely to paper over that mismatch, and it is doing **document ingest under a
transcript id** — misnamed, not merely a weak fallback.

**Taxonomy, using vocabulary the repo already has** (`server/ingest/`, `ingest_file()`,
`IngestLane`, `IngestReceipt` all exist — "ingest" is the established stage name; do not invent
"processing" as a competing term):

- **Stage: `ingest`** — the umbrella pipeline every input goes through.
- **`parse.*`** — decode a structured export format into records. Only applies when there IS a
  format to decode (chat exports, SMS XML, messaging CSV).
- **`extract.*`** — get text out of an opaque/binary container (PDF, DOCX, PPTX, images). Already
  exists: `extract.text` → `documents.extract-docling` / `documents.extract-text`.
- **`chunk.*`** — segment text into retrievable units. NEW capability; `StructuralChunker` and the
  Chonkie chunkers register here (see the correction above).
- Optionally **`normalize.*`** for a cleaning step (e.g. stripping the NotebookLM
  `[span_N](start_span)` markers still embedded in one of the four sample files).

**Plainly: an ingest run does not require a parse step.** For already-text inputs the path is
ingest → (optional normalize) → chunk → store — the parse stage is **skipped, not failed-through.**
The four sample files take exactly this path: chunk + ingest, no parser.

**The pipeline shape is broadly right; one suffix is misrouted.** `service.py` already
distinguishes `_extract_document()` (documents) from `_parse()` (transcripts) — the actual defect
is narrower than "no parser exists": `.md` sits in `_TEXT_SUFFIXES` and is therefore misfiled into
the TRANSCRIPT branch, when document-class markdown should take a document/text path instead
(chunk, not parse).

**Naming migration cost — do not start it now.** The existing pipeline names the stage "parse"
throughout: `parse_activity`, `_parse()`, `parse.transcript`, `parse_chat_export`,
`ParseParams`/`ParseResult`. Adopting the parse/extract/chunk split under the `ingest` umbrella
does **not** require renaming any of that today. Recommendation: use the new taxonomy for NEW
capabilities immediately (`chunk.*`), leave existing `parse.*` ids alone, and treat any rename as
a separate, later change — not something to start inside the current freeze.

### Candidate set — chunker bake-off (verified availability as of this HEAD)

> Per the contract above, candidates **A, C, D, E are CHUNK-stage** (they operate on already-parsed
> records/text and must register, if at all, under a `chunk.*` capability, never `parse.*`).
> Candidates **B, F, G are PARSE/CONVERT-stage** (format converters for office documents) — not
> applicable to the four already-markdown sample files, kept here for the separate office-format
> decision (Pending owner decision #3).

| # | Approach | Installed? | Needs | Risk / unknown |
|---|---|---|---|---|
| A | **[CHUNK] Semantica `StructuralChunker`** (`vendored/semantica/semantica/split/structural_chunker.py`) | **Yes — vendored** | Nothing. No network, no model | Zero callers today; behavior on these files unproven |
| B | **[PARSE/CONVERT] Semantica `parse/` document modules** (17 modules incl. `document_parser`, `docling_parser`) | **Yes — vendored** | Nothing for the pure-python ones | `docling_parser` inherits the missing-Docling problem; others use pdfplumber/python-docx/BeautifulSoup which ARE base deps. Not needed for the four (already-markdown) sample files |
| C | **[CHUNK] Chonkie `RecursiveChunker` + hand-specified heading delimiters** (`RecursiveLevel(delimiters=['\n# ','\n## ','\n### '])`) — the **preferred** Hub-free fix | **Yes — `requirements.txt:23`** | Explicit rules config (inline; no vendored asset, no Hub call) | Root cause of the live `from_recipe("markdown")` failure: `chonkie.utils.hub.get_recipe()` → `huggingface_hub` download → `LocalEntryNotFoundError`, because this machine sets `HF_HUB_OFFLINE=1`/`TRANSFORMERS_OFFLINE=1` (owner's no-local-models guard) — not a Chonkie defect. That guard would block the Hub call in any container inheriting these env vars, which this inline-delimiter approach sidesteps entirely (no Hub touch at all). Vendoring the recipe JSON + `from_recipe(..., path=<local>)` is also Hub-free but is a **last resort only** — owner correction: do not treat vendoring as the recommended fix |
| D | **[CHUNK] Chonkie `TableChunker`** for the tabular passages | **Yes** | Nothing | Narrow; complements rather than replaces |
| E | **[CHUNK] Chonkie `SemanticChunker`** | **Yes (lib)** | **Remote inference through Portkey** — a thin `BaseEmbeddings` shim fronting the existing `NimEmbedder` (`server/core/embedder.py:26`, NVIDIA NIM through Portkey) | **VERIFIED: accepts a custom embedder — Colab blocker removed.** `SemanticChunker.__init__(embedding_model: Union[str, BaseEmbeddings] = "minishlab/potion-base-32M", ...)`: a string goes through `AutoEmbeddings.get_embeddings()` (HF Hub, hits the offline guard); a `BaseEmbeddings` instance is used directly, bypassing the Hub entirely. Candidate E does **not** require Colab — it requires writing the `BaseEmbeddings` shim. **Remaining unverified sub-question:** immediately after, `__init__` calls `self.embedding_model.get_tokenizer()` — the shim must also supply a tokenizer, and a naive one could pull an HF tokenizer and re-trip the offline guard. Chonkie's own remote executor is a stub either way (`chonkie_chunkers.py:192`, D-046). **WP-5e:** compare this remote-embedder path against running native `potion-base-32M` on Colab (chunk quality, latency, cost) — owner wants both measured, do not pre-judge |
| F | **[PARSE/CONVERT] Docling** | **NO — not in any deploy image** | `document-ai` extra + image rebuild | Converter; for *already-markdown* input the conversion is a no-op, so low value for THIS class. Real value is the office formats that hard-fail today |
| G | **[PARSE/CONVERT] LlamaParse** | **NO — not present at all** | API key; transmits case content externally | Escalation tier for hard scanned PDFs only. Not needed for markdown |

### Recommended order to try (and prove)

**A → C → E → D** among the chunk-stage candidates (B/F/G are the separate office-format
decision, not this bake-off). A and C are both zero-install and zero-network, so they can be
bake-offed immediately. E is now unblocked (a `BaseEmbeddings`/`NimEmbedder` shim, not Colab) but
needs that shim written first and compared per WP-5e. D complements rather than replaces the
others for tabular passages.

### WP-5c — Chunker bake-off — **PARTIALLY RUN 2026-08-29. Results below overturn the recommendation.**

> **Run against two of the four real sample files** with the repo's own venv, read-only, no repo
> changes. Metric `starts_at_heading` = how many chunks begin at a markdown heading, out of the
> headings present. `reassembles_exactly` = `sha256(concat(chunks)) == sha256(source)`.

**56KB Michigan guide — 56,341 chars, 26 headings**

| Candidate | chunks | starts_at_heading | reassembles exactly |
|---|---|---|---|
| **A** RecursiveChunker default *(current production)* | 46 | **1 / 26** | **yes** |
| **B** RecursiveChunker + hand-specified heading delimiters | 65 | **1 / 26** | **yes** |
| **C** Semantica `StructuralChunker` | 35 | **13 / 26** | **NO** |

**Chronology — 17,553 chars, 8 headings**

| Candidate | chunks | starts_at_heading | reassembles exactly |
|---|---|---|---|
| **A** RecursiveChunker default | 13 | 0 / 8 | yes |
| **B** RecursiveChunker + heading delimiters | 18 | 0 / 8 | yes |
| **C** Semantica `StructuralChunker` | 11 | 1 / 8 | **NO** |

**Two findings, both of which change the plan:**

1. **Candidate B does not work.** Hand-specified heading delimiters produced *identical*
   heading alignment to the default (1/26) while creating **more** chunks (65 vs 46). It
   subdivides more, it does not align better — `chunk_size=1500` still dominates, so heading
   boundaries get recursively split anyway. **The earlier recommendation of "(a) hand-specified
   `RecursiveLevel` delimiters inline" as the preferred Hub-free fix is empirically WRONG and is
   withdrawn.**
2. **Candidate C preserves structure but FAILS the reassembly invariant.** `StructuralChunker` is
   the only candidate that meaningfully respects headings (13/26 vs 1/26) — and it does not
   reassemble losslessly. Per the completeness gate, a chunker that cannot reassemble **fails
   outright**, regardless of how good its boundaries look.

**So the current candidate set has no winner:** the structure-preserving option violates the
reassembly requirement, and the reassembly-safe options do not preserve structure. This tension
was not visible from reading the code and is exactly what the bake-off existed to find.

**Next steps for whoever picks this up** (do not treat the above as final):
- Determine *why* `StructuralChunker` is lossy — it was invoked with default settings via a
  guessed method name; the loss may be whitespace normalization or a configurable behaviour, in
  which case it may be recoverable. Check before discarding the only structure-aware candidate.
- If it is inherently lossy, the fix is likely **byte-range locators rather than concatenation**
  (already recommended above): `StructuralChunker` may be usable if chunks record `char_start`/
  `char_end` into the source and completeness is checked as full range coverage rather than
  string equality.
- Test the remaining two sample files and add candidate D (`TableChunker`) for the guide's
  tabular passages.

**Caveats on these numbers:** `starts_at_heading` is a coarse proxy — a chunk can contain a whole
section without beginning at its heading line. Only 2 of 4 files were run. `StructuralChunker`
was called with defaults. Treat this as a directional result that disqualifies B and flags a real
problem with C, not as a final ranking.

#### Reproducibility (supplied on Codex's challenge — do not treat the above as evidence without it)

**Environment:** Python 3.13.12 AMD64, `chonkie==1.7.0`, run with the repo's own
`.venv/Scripts/python.exe`. Read-only; no repo file was written by the experiment.

**Input fingerprints** (bytes and UTF-8 hash identical — files are pure ASCII/UTF-8, no BOM):

| File | bytes | chars | sha256 |
|---|---|---|---|
| `Copy of Michigan Custody_ Digital Evidence Standards.md` | 56,371 | 56,341 | `18618992f24e492c19b7bf3be27188385df19efc6f133107495b6d8a78406914` |
| `FULL CASE EXTRACTION — ALL TIMELINES, EVENTS, STRA.md` | 17,601 | 17,553 | `8d766277b73baf69b7afbdccfc9056f630ce056af6280a21b7abb67b2fe586c6` |

**Reassembly proof, 56KB guide** — `sha256` of `"".join(chunk_texts)` versus the source hash:

| Candidate | reassembled sha256 | chars | match |
|---|---|---|---|
| source | `18618992…406914` | 56,341 | — |
| **A** RecursiveChunker default | `18618992…406914` | 56,341 | **True** |
| **C** `StructuralChunker` | `5afef976f177fede7eedda9c5145cadb098d5884fad6222914fbac4a6b7aabb0` | 56,165 | **False** |

**Why C fails — and it is worse than "lossy".** Diagnosis run on the same input:

- **176 characters missing** from the concatenation (56,165 vs 56,341).
- **Not whitespace normalization** — whitespace-normalised equality is also `False`.
- **24 of 35 chunks do not appear verbatim anywhere in the source.**

That last line is the disqualifying one. `StructuralChunker` is **not a pure splitter — it
transforms content.** For a forensic platform this is categorically unusable in its default
configuration regardless of boundary quality: a chunk that does not match the original cannot be
cited, cannot be hash-verified against the source, and breaks the chunk → `source_locator` →
original-document path that the evidence promotion flow depends on.

**Revised next step for C:** the question is no longer "is it lossy, and can byte-range locators
work around it" — locators cannot rescue text that has been altered. It is: **what transformation
is it applying, and can it be disabled?** If it cannot be configured into a verbatim-preserving
mode, it is out, and the search moves to a different structure-aware splitter. Do not adopt it on
boundary quality alone.

**Scripts:** `scratchpad/bakeoff.py` (the table above) and `scratchpad/proof.py` (the hashes and
diagnosis), both session-scratchpad, read-only, re-runnable against the fingerprints above.

### WP-5c — original brief

Run the **chunk-stage** candidates A, C, and E (D as a complement for tables) over the **four
real sample files** (the two NotebookLM outputs, the strategy memo, and the 56KB Michigan guide)
and record, per approach: chunk count, whether `##` section boundaries survive, whether the
chronology's dated entries stay intact as units, and whether a known phrase ("MRE 901
authentication") retrieves as one coherent section. Pick the primary on evidence; register the
runners-up behind flags. This is the only way "in case one doesn't work as expected" is actually
answered rather than assumed. This bake-off measures the **chunk stage only** — the parse stage
for this content class is the simpler one-record-per-document question addressed above.

### WP-5d — Quality gate + method substitution

> _Owner directive, 2026-08-29. See "Orchestration and the quality gate" above._

Define the extraction-quality score and wire it around the Go coordinator's `Select` /
`ExecuteSelected` mechanism (`engine/parser/registry.go:63,158`). **Atomicity constraint (per
"PARSE vs CHUNK" above): the scorer is its OWN step — a separate Temporal activity or its own
registered capability — and must NOT be implemented inside a parser or a chunker.** A parser or
chunker that scores its own output is doing two things.

**The gate splits in two (owner requirement, 2026-08-29): completeness is a correctness gate,
quality is a judgment gate.** A chunk set that fails completeness is broken regardless of how
good the model says the boundaries are.

1. **Completeness check — DETERMINISTIC, no model, always runs, hard gate.** **Invariant:
   chunking must be lossless and reversible — the ordered set of chunks for a source must
   reassemble to the original.** This is the same discipline the platform already applies to
   custody (H1/H2/H3 exist to prove nothing changed), applied to the chunk stage. Define
   reassembly over **byte-range locators, not naive concatenation** — `engine/parser/parser.go`
   already defines `LocatorType`, `ByteRange`, and `Locator` (with `Validate()`); each chunk
   carries its range into the source so reconstruction is verifiable rather than assumed. The
   check is "do the ranges cover `[0, len(source))` with no gaps" (dedupe overlapping ranges),
   compared by hash (`sha256(reassembled) == sha256(original)`) or against an explicitly declared
   and bounded normalization applied identically to both sides — never left implicit. **This
   catches dropped content, duplicated content, boundary corruption, and silent truncation** —
   exactly what a model-based scorer is worst at noticing, since a plausible-looking chunk set
   with a missing section still reads fine. Cheap, exact, needs no API call; gates every chunk
   run. **Tension to record, not gloss over:** the current canonical chunker runs with NO overlap
   (`RecursiveChunker(tokenizer="character", chunk_size=1500)`), which is what makes naive
   concatenation look viable today, but several retrieval strategies want overlap for context
   continuity — locator-based reassembly (above) resolves this, since overlapping chunks still
   reassemble correctly by range coverage. Adopt the locator-based definition from the start so
   overlap remains available later without breaking the invariant. Byte-range locators also
   independently serve R33 (material findings must open to the exact source page/location plus
   surrounding context) — they pay for themselves twice: reassembly proof AND source-opening for
   the reviewer.
**Correction (owner follow-up, 2026-08-29): most of this reassembly/back-reference machinery
already exists at the PG layer — do not design it from scratch, generalize and tighten it.**
`working.chat_chunk` (`sql/0024_chat_conversation_and_message.sql:103-118`) already has
`chunk_index`, `content_hash` (64-char), `chunker_id`+`chunker_version` (the chunk-stage replay
pin from the receipt paragraph above already exists at chunk level, not just as a proposed
addition), and `char_start`/`char_end`. Given those columns, the completeness check above is
implementable **today** — order by `chunk_index`, assert char ranges are contiguous and cover
`[0, len(source))` with no gaps/overlaps, hash-compare the reconstruction — this is "use the
columns that exist," not "add reassembly support." **One real, small gap:** `char_start`/
`char_end` are nullable (`CHECK (char_start IS NULL OR ...)`) and nothing enforces a chunker
populates them; they must be **NOT NULL for document chunks**, and the chunker must always emit
them — a constraint, not a redesign. **The actual gap: the parent link is chat-specific** —
`conversation_id` is `NOT NULL REFERENCES working.chat_conversation(id)`, so document-class
content can't use this table as-is. Two options: (a) a sibling `working.document_chunk`
duplicating the column set with `document_id`, or (b) generalize the parent reference so one
canonical chunk store serves both. **Recommend (b) in principle** (matches the "one space"
principle; `chat_chunk` is already effectively the canonical chunk store) **but it is a migration
against a live table with an existing NOT NULL FK and `UNIQUE(conversation_id, chunk_index)`** —
not a same-turn change, and must not happen during the freeze. If (a) is chosen for speed, it
creates exactly the kind of parallel implementation the zero-tech-debt discipline warns about;
timebox it with a merge plan. **Vectoring, connected explicitly:** `working.chat_chunk_embedding`
is an idempotency ledger (the vector itself lives in Weaviate) — **chunk id is the join key
between PG and the vector store**, which is why stable chunk identity matters beyond bookkeeping:
without it a vector hit can't resolve back to its text or source. `working.chat_chunk_projection`
(sink CHECK `weaviate|graphiti`) tracks where a chunk has been projected. **Evidence
back-reference, closing a loop already in this document:** `char_start`/`char_end` + parent id
IS the source-opening pointer for R33 ("material findings must open to the exact source
page/location plus enough surrounding material to judge meaning"), and it feeds
`timeline.event_candidate.source_locator` (`sql/0035`, documented example
`{"schema":"context","table":"chat_message","pk":"..."}`) directly — a chunk locator populates
that field when a lead is promoted. Chain: chunk id + char range → `source_locator` on the event
candidate → owner opens the original when classifying it toward evidence — one populated field
away from working, not a new mechanism.

2. **Quality check — JUDGMENT, model-backed, advisory or substitution-triggering.** Are the
   boundaries semantically sensible (does a section hold together, is a dated chronology entry
   intact) — candidate signals: section-boundary survival (`##`/`#` boundaries survive into
   distinct chunks), chunk-count sanity (not 1, not absurdly many for the input size), and
   empty/degenerate-output detection (blank or near-duplicate chunks). **This non-model heuristic
   is the cheaper first cut** — no model, no gateway call, no API at all.
- If a model-backed scorer is ever needed instead, it routes through **Portkey** to a remote
  provider (NVIDIA NIM, Ollama Cloud, or a free-tier API) like any other model-backed work here.
  Colab is reserved only for the narrow local-model-only case in the HARD CONSTRAINT above and
  does not apply to a scorer.
- **The flow is `Select(format)` → `ExecuteSelected` → score.** On a failing score, a raised
  error, or a `422` from a Python-fronted tool via `platform-tools` (WP-6a), call `Select` again
  — the registry's declared `Quality` ranking (`QualityPrimary` → `QualityFallback` →
  `QualityExperimental`) hands back the next-best registered `Adapter` — and run
  `ExecuteSelected` for that adapter, before the workflow proceeds to WP-6. Both invocations pin
  their own `parserID`/`parserVersion`, so both attempts are individually replayable and show up
  distinctly in workflow history.
- Each candidate proven in WP-5c is registered per WP-5b/WP-6a as its own `Adapter` with its own
  declared quality — not as branches inside one activity — so substitution is explicit and
  durable by construction, not something this work package has to separately implement.

**Verifiable outcome:** feeding a file that defeats the primary adapter causes the workflow
history to show `Select` returning a second, different adapter, `ExecuteSelected` running and
succeeding on it, without a human in the loop.

### WP-5e — Remote-embedder vs Colab-native comparison for candidate E

> _Owner directive, 2026-08-29: measure both, do not pre-judge._

Compare (a) the `BaseEmbeddings` shim fronting `NimEmbedder` through Portkey against (b) running
the native `potion-base-32M` model on Colab (via the Colab MCP, narrow-exception path, HARD
CONSTRAINT above) on chunk quality, latency, and cost. Resolve the tokenizer sub-question from
candidate E's row as part of building the shim.

### WP-5f — Model-discovered schema, deterministic chunk application

> _Owner proposal, 2026-08-29: "use a model to discover the structure and properly chunk based on
> the markdown structure and a created schema?" **Endorsed, with one hard guard.** Run this AFTER
> WP-5c, not before — a deterministic chunker's section-boundary result is the baseline the model
> approach must beat; without it there is no control to compare against._

**Not a new idea — already a recorded requirement.** `conversation_ingestion_system_design.md`'s
distilled register (2026-08-23) already specifies this pattern: R03 (check ingested samples
against a library of known schemas — fingerprint + similarity score, >85% threshold — before full
discovery), R04 (interactive field-mapping with reusable mapping templates), R06
(preview-before-commit on ~10 records before a full run), R67 (save/version transformation and
mapping configs for reuse). The four sample files are genuinely heterogeneous (a dated
chronology, a nested research guide, a framing memo, statute text with residual citation
markers) — one fixed chunking rule serves none of them well, which is exactly the case R03/R67
are for.

**HARD GUARD — determinism, non-negotiable:** the model must **NOT** chunk. The model discovers
a **schema**, once; a deterministic chunker **applies** that schema on every run, including
replays. This is a forensic/evidence platform — chunk boundaries that vary between runs break
replay and undermine custody, and `ExecuteSelected` exists specifically to re-run "precisely the
parser named by an immutable persisted" record (`registry.go:158`) — a model-in-the-loop chunker
defeats that guarantee. Correct shape: model runs **once per document-type** → emits a
**versioned schema artifact** → a deterministic chunker applies that schema on every run.
**Acceptance test: re-ingesting the same document against the same schema version MUST produce
byte-identical chunk boundaries.** Cost/latency follows for free — one model call per
document-type, not per document and never per chunk; R03's fingerprint matching lets repeat
document types skip discovery entirely.

**Capability shape (per the atomicity rule):** three separate capabilities, not one blended step
— `schema.discover` (model-backed, routes through **Portkey**, emits a versioned schema
artifact; its own capability, its own tool), `chunk.*` (deterministic, consumes the schema, no
model), and schema storage (the schema library from R03 needs a home — PG table vs. versioned
config is an open question, connects to R67).

**Register it as a manifest, per owner follow-up — using the pattern that already exists, not a
new one.** Two distinct artifacts, kept separate:

1. **Schema manifest (the library).** Lists discovered schemas: schema id, version,
   document-type fingerprint (R03's >85% similarity match key), created-by/run id, and the
   chunking rules it encodes — what a new document is fingerprinted against to skip
   re-discovery. This is the same shape of thing as `registry.manifest()` (served at
   `GET /tools`) and `SelectCapability`'s "immutable capability snapshot" (`registry.go`) —
   reuse the pattern, don't invent a new one.
2. **Receipt pin (the replay record).** Which schema was actually applied to THIS ingest. **This
   is nearly free:** `IngestReceipt` (`server/contracts/ingest.py`) already carries `receipt_id`,
   `parser_id` + engine, **`chunker_id`**, record/chunk counts, `rejections[]`, `attempts[]`,
   `projections[]`. Adding `schema_id`/`schema_version` alongside the existing `chunker_id` is
   purely additive and completes the replay triple: **parser id+version, chunker id, schema
   id+version.** That triple is what makes the byte-identical-boundaries acceptance test above
   actually checkable after the fact. Symmetry: the platform already pins WHICH PARSER ran for
   replay (`ExecuteSelected` takes `parserID`+`parserVersion`); pinning WHICH SCHEMA ran is the
   same discipline applied to the chunk stage — without it, a model-discovered schema would be
   the one un-replayable step in an otherwise replayable pipeline. **Extend the receipt further
   (per the completeness gate in WP-5d):** also record the completeness-check result and the
   source hash it was checked against, so a past ingest can be shown to have been complete
   without re-running it.

**DECIDED (owner, 2026-08-29): the schema manifest lives in PostgreSQL, not versioned config
files or the parser-bundle volume.** Consistent with the single system of record — matches R18
(store extracted artifacts in the existing bitemporal Postgres schema rather than a parallel
tool, so the custody trail isn't fragmented) and avoids re-opening the four-store split
(Contradiction 2). PG is the right answer, not just a convenient one: R03 requires fingerprint +
similarity matching (>85% threshold) against the schema library at ingest time — an indexed
lookup, which a table supports and versioned config files do not. **Schema rows must be
IMMUTABLE once referenced** — a receipt that pins `schema_id`/`schema_version` for replay is
meaningless if that row can later be edited, and replay would silently diverge. Reuse the
platform's existing pattern rather than inventing a new one: append-only, a correction is a NEW
row/version, never an edit — exactly `timeline.event_candidate`'s `forbid_mutation()` trigger
(`sql/0035_timeline_projection.sql`, "a correction is a NEW row... never an edit to this one").
**Migration numbering:** `sql/0046_agno_app_role.sql` was highest as of this audit (next free was
`0047`) — Codex is committing rapidly, so re-check the highest number immediately before creating
the file, don't trust this document. **Do not apply during the freeze** — draft only, held like
`sql/0030`, until the Workbench/UIW critical path clears; per R68, "migration written" and
"migration applied to the live database" are two separately-verified states, never conflate them.

**Check off-the-shelf first (owner rule: wire what we own).** Chonkie already ships model-backed
chunkers — `SlumberChunker` (LLM-driven), `NeuralChunker`, `LateChunker`. **Verified caveat: in
this repo's wrapper they are stubs** (`server/analysis/chonkie_chunkers.py:186-228`, line 192
"the remote executor is not wired yet", D-046) — the capability exists off-the-shelf, the wiring
does not. The determinism guard applies to `SlumberChunker` too: an LLM chunker that re-decides
boundaries per run has the same replay problem, so it needs the same schema-then-apply treatment
or must be confined to the one-time discovery step, never per-run chunking.

## Findings (ranked)

1. **The router is correct as far as it goes, but the deeper issue is a category error, not a
   missing signature.** `detect_format` runs on every ingest and works as designed — it just has
   three JSON signatures and none for markdown, so 100% of `.md` input skips routing and lands in
   the try-until-one-doesn't-raise mesh. For real markdown **chat exports** (which do have role
   markers), adding `FormatSig` rows is the right, narrow fix — see WP-2. But for **document-class**
   markdown like the four sample files, no signature should route to a parser at all: per "Ingest
   taxonomy" above, these files need no parse step, only chunk + ingest. The narrower underlying
   defect is that `.md` sits in `service.py`'s `_TEXT_SUFFIXES` and is misfiled into the
   `_parse()`/transcript branch instead of a document/chunk path. Per the owner's same-day
   amendment ("MIGRATION CONSTRAINT" above), selection among competing parser *implementations*
   durably belongs to the Go coordinator (`engine/parser`), not more Python `FormatSig` rows;
   `format_router.py` is superseded and scheduled for removal once Go coverage exists.

2. **The destination table was purpose-built for this content class and has no producer.**
   `timeline.event_candidate` already names `'ai_chat'` as a source system and already encodes
   D-082 (AI-derived = lead, never evidence) in its table comment, with an append-only trigger
   and no FK requirement. Everything downstream of it is built and tested. Nothing writes to it.

3. **Two parallel, both-half-installed document stacks.** `docling_extract.py` +
   `extract_text.py` are wired in code but their libraries aren't installed in any image;
   Semantica's `parse/` has 17 working format modules with zero callers. The platform is
   maintaining two document layers and running neither.

4. **`StructuralChunker` is the closest thing to the right tool for this class — as a CHUNKER, not
   a parser** (see "PARSE vs CHUNK" above) — and is vendored, tested, and uncalled. For
   already-markdown input it needs no converter at all — Docling and LlamaParse are converters,
   and conversion is a no-op here; the four files skip both the parse and extract/convert stages
   entirely and go straight to chunk + ingest.

5. **Ingest defaults to the `platform` lane.** Forgetting `lane=` silently routes custody-case
   material into `platform`. The "nothing reaches evidence without promotion" invariant holds,
   but the default lands in the wrong non-evidence lane.

6. **Guard asymmetry across two parse paths.** ADR-0044's evidence-lane prohibition is enforced
   on the HTTP ingest facade only. The production Temporal `parse_activity` has no lane guard.
   Not currently exploitable (nothing routes straight to evidence), but the protection is not
   structural.

7. **Parser precedence is decided by alphabetical filesystem order — a Python-side risk now
   scheduled for retirement, not a permanent fix target.** Only `sbv_sms` declares a priority.
   `ai_chat/` sorting before `generic/` is what currently keeps the whole-file fallback last.
   Renaming a package would silently promote the fallback above every real parser, and no test
   would catch it because whole-file always succeeds. Per the owner's same-day amendment
   ("MIGRATION CONSTRAINT" above), the durable fix is Go coordinator adapter coverage
   (`engine/parser/registry.go:63`), not a Python priority scheme — WP-4 is at most a throwaway
   interim mitigation while that migration is in flight.

8. **Ingested content is effectively unsearchable.** Substring `ILIKE` only; semantically
   invisible; and the FTS/trigram indexes that already exist are not used by that route.

## UNRESOLVED (mandatory)

- ~~**`context_thread_id` (cross-medium human thread) does not exist anywhere in the schema.**~~
  **RESOLVED 2026-08-29 — schema built in `sql/0047` (commit `06702d9`), PG18 lifecycle proof in
  `860e925`.** Owner-elevated to the highest-severity finding in this document — see "CRITICAL GAP"
  near the top, not a normal document-ingest work package. Broader than WP-0..WP-11; tracked here
  only as a pointer. **The open items are now application of `0047` and a producer, not design.**
- **Do not remove `format_router.py` / the Python parser-selection mesh yet.** It is flagged for
  removal (owner 2026-08-29), sequenced on Go adapter coverage per format — see "MIGRATION
  CONSTRAINT" and WP-2/WP-3/WP-4 (shrunk/inverted/downgraded below). An unqualified removal now
  would break every currently-working ingest path.
- **Design work remaining for the Go↔platform-tools bridge, tracked as WP-6a (not a missing
  mechanism).** The bridge itself exists and is deployed (`platform-tools`, `:8090` — see "Where
  this gets installed"); what's still open is the `capability`→`FormatID` mapping and who
  declares `QualityFor(format)` for each Python-fronted tool. RECOMMENDED design (not just an
  option): declare `formats=(...)` and `quality={format: "primary"|"fallback"|"experimental"}`
  as optional `@register` kwargs, surface both via `GET /tools`, and have the Go bridge adapter
  build its `Capability`/`QualityFor(format)` directly from that manifest — see WP-6a. This keeps
  declaration (Python, next to the implementation) and selection (Go, `Registry.Select`) separate,
  the same split `sbv_sms.py`'s `priority=100` already runs today. Until the new `@register`
  fields exist, a hand-maintained Go-side override list is acceptable as **throwaway scaffolding
  only** — not the destination.
- **Consolidation gap tracked as WP-0.** `engine/adapters/` currently holds only `sbv/`; the
  vendored Semantica `parse/` modules, `StructuralChunker`, and `server/analysis/chonkie_chunkers.py`
  are real working code not yet `@register`ed under `server/tools/` (D-026's polyglot registry),
  so none of it is reachable via `platform-tools` yet either. This is design/registration work,
  not a blocked or unsolved mechanism.
- **No bridge `working.candidate_event` → `timeline.event_candidate`.** Semantica's existing
  extractor writes the former; the timeline reads the latter. Not attempted — the correct
  direction (bridge vs. write `event_candidate` directly) is an owner/architecture call, and
  `event_candidate` takes free-text `extraction_run_id` with no FK, so direct write is viable.
- **`sql/0045_context_fingerprint_semantics.sql` not reviewed.** It is untracked and in Codex's
  live working tree; auditing a file changing underneath produces false findings. It is very
  likely the change-detection substrate this handoff depends on — reconcile before building.
- **Chunk-stage heading-aware chunking has a diagnosed root cause but no verified fix yet** (this
  is chunk-stage, not parse-stage — see "PARSE vs CHUNK"). `from_recipe("markdown")` fails
  because `chonkie.utils.hub.get_recipe()` calls `huggingface_hub`, and this machine has
  `HF_HUB_OFFLINE=1`/`TRANSFORMERS_OFFLINE=1` set (the owner's no-local-models guard) — not a
  Chonkie bug or network outage. Preferred fix order: (a) hand-specify
  `RecursiveLevel(delimiters=['\n# ','\n## ','\n### '])` inline; (b) Semantica `StructuralChunker`;
  (c) vendor the recipe JSON and call `from_recipe(..., path=<local>)` — **last resort only**.
  `SemanticChunker` (candidate E) is now verified to accept a custom `BaseEmbeddings` and no
  longer needs Colab, but its tokenizer sub-question is still open. **None of A/C/E has been
  executed and verified yet** — one must be proven before relying on any of them (WP-5c).
- **Local-model routing: Colab is a narrow exception, not the default.** Model-backed work
  routes through **Portkey** to a remote provider (NIM/Ollama Cloud/free-tier) as the normal
  path; Colab via the Colab MCP (reached through ContextForge like any other MCP server) is only
  for an application that requires a local model with no API equivalent. The Colab MCP was not
  reachable from the audit session — keep that caveat, but it no longer blocks the current work
  packages (WP-5d's scorer doesn't need it; candidate E doesn't either, per WP-5e).
- **BUILD_STATUS UNKNOWN.** No tests run; repo is frozen and dirty. Do not claim PASS.
- **Nothing verified against a live database or deployed service.** All findings are from source
  reading plus one local read-only parser probe. Migration/deploy state is read from file headers.

## Pending owner decisions

1. **Lane assignment for derived AI work products.** WHAT: decide whether these land in `context`
   uniformly, or route per ADR-0053. WHY: owner stated "everything goes to context" (×3), but
   ADR-0053 would place the research guide + strategy memo in `legal` and the chronology in
   `personal_history`. Options: (a) uniform `context`, simplest, contradicts ADR-0053 — the ADR
   must then be amended, not silently ignored; (b) per-ADR routing, needs a classifier or an
   explicit `lane=` at submit. RECOMMENDATION: (b) with explicit `lane=`, since the promotion
   path to evidence is owner-gated either way and ADR-0053 already encodes the taxonomy.
2. **Is `platform` the intended ingest LANE default?** STILL OPEN. Owner confirmed 2026-08-29
   that `platform` is the new production **database** — that is recorded above and is a
   different question from `IngestLane.platform` being the default lane on
   `contracts/ingest.py:75`. WHY it matters: forgetting `lane=` silently files case material
   under the platform-design domain (`_DB_DOMAIN`, `service.py:33`). RECOMMENDATION: make
   `lane` required so nothing lands by accident. Do not treat the database ruling as having
   settled this.
3. **One document stack or two?** WHAT: install the `document-ai` + `ocr` extras into the deploy
   images, or standardize on Semantica's `parse/` layer and retire the parallel extractors.
   WHY: both are currently half-installed; office formats hard-fail today. Owner 2026-08-29:
   *"If one of the bundled semantica tools will work, we can call on those."* RECOMMENDATION:
   Semantica for parse/structure (already vendored, no new deps, no network, nothing to
   install), Docling installed only if binary-format fidelity proves insufficient.
4. **LlamaParse tier.** WHAT: whether to add it as an escalation tier for hard scanned PDFs.
   WHY: it is API-based and transmits case content externally — a different question from local
   storage, which the owner has ruled stays unredacted. RECOMMENDATION: defer; not needed for
   markdown, and Tesseract is the cheaper first fix.

## Next steps (work in order)

Each item is a bounded work package. Nothing here is authorized to run during the
Workbench/UIW critical path or against Codex's in-flight files.

0. **WP-0 — Register the already-owned, currently-unregistered callable modules into
   `server/tools/` per D-026.** Semantica `StructuralChunker` first (leading chunk-stage
   candidate), then the Semantica `parse/`/`extract/` modules needed for the office formats that
   currently hard-fail, then the Chonkie chunkers (`server/analysis/chonkie_chunkers.py`). Each
   gets an `@register` id, a **capability under `chunk.*` or `extract.*` (never `parse.*` for a
   chunker)**, and an `accept` predicate. Confirm which of Semantica's `parse/` dependencies
   (pdfplumber, python-docx, python-pptx, openpyxl, BeautifulSoup, pytesseract) are already in
   `requirements.txt` before registering — anything missing there is absent at runtime, the same
   trap that leaves Docling and the OCR tier non-functional today. Verifiable: each module appears
   in `GET /tools` and executes via `POST /tools/{id}/run`. Unblocks the WP-5c bake-off (uniform
   interface to compare candidates under) and WP-6a (delivers the Go↔Python bridge for these
   modules with no Go-native rewrite).
1. **WP-1 — Reconcile with `0045`.** Read `sql/0045_context_fingerprint_semantics.sql` once
   committed; confirm whether it provides the change-detection trigger this chain assumes.
   Blocks WP-6.
2. **WP-2 — Add markdown signatures to `format_router.SIGNATURES`, SHRUNK to real chat exports
   only.** Per "Ingest taxonomy" above, this is only needed to route markdown **chat exports**
   (which do have role markers) to their correct parser — lift the existing role regexes into
   `FormatSig` rows: `gemini_md._ROLE_RE` (`**You:**`/`**Gemini:**`),
   `chatgpt_custom_gpt_md._ROLE_RE` (`You asked:`/`ChatGPT Replied:`), plus claude/perplexity
   markdown markers. **Document-class markdown (the four sample files) does NOT need a signature
   that selects a parser** — it needs the routing fix in WP-3 instead. Per "MIGRATION CONSTRAINT"
   above, `format_router.py` itself is flagged for removal, so treat this as maintenance on a
   superseded module, sequenced per that constraint, not a destination. Verifiable: a real
   Gemini `.md` export routes first-try with `attempts == 1`.
3. **WP-3 — Route document-class markdown PAST the parse stage entirely, not into a new parser
   signature.** The four sample files need no parser (see "Ingest taxonomy"). The narrower
   defect: `.md` sits in `service.py`'s `_TEXT_SUFFIXES` and is misfiled into the `_parse()`/
   transcript branch. Fix the routing so headings-present/role-markers-absent `.md` takes the
   document/chunk path (`_extract_document()`'s sibling, or a new document-text path) instead of
   `_parse_via_registry`. Do not add this as a new Python `FormatSig` row selecting a parser —
   there is no parser to select. Verifiable: one of the four sample files ingests with zero
   `_parse()` calls and lands as chunked records via the winning WP-5c chunker.
4. **WP-4 — OPTIONAL interim mitigation only (throwaway), not a goal in its own right.** The Go
   coordinator's `Quality` ranking (`QualityPrimary`/`QualityFallback`/`QualityExperimental`,
   `engine/parser`) already provides ranking durably for parser selection. **Only if the Python
   path must keep running during migration** (MIGRATION CONSTRAINT ordering above), set
   `priority=-100` on `transcripts.markdown` (and `transcripts.generic-md` above it) as a stopgap
   so precedence stops depending on `pkgutil` alphabetical order in the interim. Explicitly
   throwaway: delete this mitigation along with `format_router.py`/the registry mesh once Go
   coverage lets that format's Python path retire.
5. **WP-5 — Confirm the chunk-only path for document-class markdown; no parser to wire.**
   Per "Ingest taxonomy," the four sample files skip parse and go straight to chunk + ingest.
   This work package is: (a) make WP-3's routing land already-text `.md` on a chunk-only path,
   and (b) prove the winning chunker from WP-5c (`StructuralChunker`, or Chonkie
   `RecursiveChunker` with inline heading delimiters — `from_recipe("markdown")` fails here
   because `HF_HUB_OFFLINE=1`/`TRANSFORMERS_OFFLINE=1` are set, the owner's no-local-models guard,
   not a Chonkie defect; vendoring the recipe JSON is Hub-free too but last-resort only) actually
   preserves `##` boundaries end-to-end through that path. If `SemanticChunker` (candidate E) is
   chosen instead, it fronts `NimEmbedder` through **Portkey** via a `BaseEmbeddings` shim — not
   Colab, not a local model (see WP-5e). Register the winning chunker behind a named Unleash
   flag. **This step is standalone validation only (WP-5c) — it does not decide runtime
   selection; that belongs to the Go coordinator (WP-5b / WP-6a).** Verifiable: the 56KB guide
   chunks on `##` boundaries with no parse-stage call in between, and "MRE 901 authentication"
   retrieves as one coherent section.
5b. **WP-5b — Register the proven chunker as a Go coordinator `Adapter` under a `chunk.*`
   capability** (never `parse.*` — see "PARSE vs CHUNK"). Once WP-5c has proven a candidate
   against the four real sample files, implement it as an `engine/parser`-family `Adapter`
   declaring a `Capability` with `QualityFor(format)` — `QualityPrimary` for the winner,
   `QualityFallback`/`QualityExperimental` for registered runners-up (`parser.go:69-151`). n8n
   still orchestrates the workflow (every custom tool to date is wrapped in an n8n code node —
   follow that pattern) and Temporal still executes durably via `n8n_webhook_activity`
   (`server/temporal/n8n_activities.py:45`); the activity invoked calls into the Go coordinator's
   `Select`/`ExecuteSelected`, which for a Python-implemented winner executes through the
   `platform-tools` facade (`:8090`, `POST /tools/{id}/run` — see "Where this gets installed" and
   WP-6a) rather than a bespoke HTTP route or a Python-side priority pick. Verifiable: the n8n
   workflow triggers the Go coordinator's `Select` for the sample file's format,
   `ExecuteSelected` runs the registered chunk adapter (via `platform-tools` if Python-backed),
   and chunk counts come back through the same n8n/Temporal path.
6. **WP-6 — Build the `timeline.event_candidate` producer.** Write rows with
   `source_system='ai_chat'`, a real `extraction_run_id`, and `source_locator` pointing back at
   the context row. Decide bridge-vs-direct per UNRESOLVED. Verifiable: an event from the FULL
   CASE EXTRACTION chronology appears as a candidate with a working source-open pointer.
6a. **WP-6a — Build the platform-tools bridge `Adapter` in `engine/adapters/`, and the
   capability/quality declaration it reads.** The execution substrate already exists —
   `platform-tools` (`deploy/platform-tools.yaml`, port `:8090`) — see "Where this gets
   installed." Build one Go `Adapter` that: (a) calls `GET /tools` for the manifest (id,
   capability, description, provenance) — discovery only; (b) applies the Go side's OWN
   `Capability`/`QualityFor(format)` to choose among them — **do NOT trust `GET
   /tools/resolve/{capability}`'s ordering**, that is exactly the Python priority-0/alphabetical
   mesh flagged for removal (MIGRATION CONSTRAINT above); (c) executes via `POST
   /tools/{tool_id}/run` and maps the result into a `RawRecordEnvelope`. Pair it with the
   **recommended declaration design**: add optional `@register` kwargs `formats=(...)` and
   `quality={format: "primary"|"fallback"|"experimental"}`, surface both via `GET /tools`, and
   have this adapter build its `Capability`/`QualityFor(format)` directly from that manifest —
   declaration (Python, next to the implementation) and selection (Go, `Registry.Select`) stay
   separate, mirroring `sbv_sms.py`'s existing `priority=100` split. Until those `@register`
   fields exist, a hand-maintained Go-side override list is acceptable as throwaway scaffolding
   only. Treat a `422` (contract rejection/wrong format) from the facade as a hard substitution
   trigger, distinct from a low quality score on a successful parse (WP-5d) — both feed the same
   `Select`-again flow but are different signals. **Caution:** port `:8090` is also used by the
   unrelated `parser-activity-runtime` app on `ovh-files` — different host, different Coolify app,
   not a conflict today, but do not wire the wrong `:8090`. Verifiable: the adapter resolves a
   registered capability to a Go-declared `QualityPrimary` choice, executes it through
   `platform-tools`, and a `422` from the facade correctly triggers substitution to the
   next-declared-quality adapter.
7. **WP-7 — Give the timeline an HTTP/Temporal surface.** It is CLI-only today. Expose
   generation/projection as a Temporal activity so n8n can drive it.
8. **WP-8 — Close the searchability gap.** Make non-evidence lanes reachable from a real
   retrieval path (`/knowledge/search` collections, or FTS/trigram on `/v1/records`). Currently
   `ILIKE`-only. Verifiable: semantic query returns a section of the guide.
9. **WP-9 — Make the evidence invariant structural.** Remove `lane` from the ingest surface or
   assert `context`-only at all three Temporal activity entry points, so evidence is
   unreachable by ingest rather than merely guarded.
10. **WP-10 — Install `ocr` extra + system `tesseract-ocr`/`poppler`,** or formally retire the
    OCR tier. Today it is wired in code and absent at runtime.
11. **WP-11 — Resolve the office-format hard-fail** (URGENT-TODO #17) per decision 3.

## Owner working-style contract

- Structured replies: bullets, labeled blocks, white space, answer-first.
- Confirm before changes; never hard-delete (quarantine); byline every artifact; verify before
  claiming done.
- No redaction or PII modification until export time — owner ruling 2026-08-29.
- Nothing is ingested directly to evidence under any circumstances; promotion from context is
  the only path.
- Shared worktree: stage only your own files by explicit path; never `git add -A`.
