# docstore — complete setup, operation, and gotcha reference

> _Byline: Claude Code · Opus 5 · 2026-09-09_
>
> **Purpose:** everything needed to stand up, run, verify, and debug the probata document
> store **without re-deriving any of it**. Every claim below was verified live on
> 2026-09-09 against the real store; where something is unverified or broken it says so
> explicitly. Build history and the upstream-defect narrative stay in `README.md`; this
> file is the operational truth.
>
> Rulings: D-155 (docs local, embedded), D-156 (seven-type taxonomy), D-157/D-158 (memory +
> NIM providers). Design: `docs/design/2026-09-09-docstore-memory-plugin-design.md`.

---

## 0 · The 60-second model

Three moving parts, routinely confused for each other:

| Part | Where | What it is |
|---|---|---|
| **The store** | `.docstore/` (gitignored) | Embedded SurrealDB (**SurrealKV**, not RocksDB). `kv/` is the data. Also `.env`, `venv/`, ingest logs, CocoIndex state dirs. |
| **The pipeline** | `scripts/docstore/` | `flow_docs.py` (CocoIndex flow), `apply_schema.py`, `mirror_docs.py`, `schema/*.surql`, `mapping/`. |
| **The plugin** | `plugins/docstore/` | Claude Code plugin — 7 skills, 3 agents, 5 hooks, `.mcp.json`. **Config only**: no binary, no data. |

Not in the repo: the `surreal` CLI binary (winget), used only for out-of-band inspection.
The pipeline never shells out to it — it opens the store **in-process** via
`surrealdb[embedded]`.

```
docs/**/*.md ──> mapping CSV ──> flow_docs.py (CocoIndex) ──> SurrealDB
                  (per-file        chunk + embed via NIM        document + chunk
                   type/domain/    (LiteLLM, 2048-dim)          + chunk_of edges
                   status)
                                                                     |
                                     agents <── MCP `run` on fn:: ───┘
```

---

## 1 · Prerequisites

| Requirement | Value | Notes |
|---|---|---|
| Python | `C:/Users/matts/.local/bin/python3.exe` (3.14) | uv-managed shim; has `cocoindex 1.0.21` |
| `surrealdb` | **`3.0.0b8`** | version is load-bearing — see GOTCHA 1 |
| `surrealdb-embedded` | **`3.0.0b8`** | separate wheel from the `[embedded]` extra |
| `NVIDIA_API_KEY` | in shell env | embeddings; no local embedder (D-158) |

```bash
uv pip install --python "C:/Users/matts/.local/bin/python3.exe" --break-system-packages \
    "surrealdb[embedded]==3.0.0b8"
```

### GOTCHA 1 — the SDK version is not optional, and `[embedded]` is a separate wheel

The schema is written for **SurrealDB 3.2** syntax. `surrealdb 2.0.0` — the current *stable*
release on PyPI — ships a 2.x engine that **cannot parse it**. Symptom: `apply_schema.py`
reports `5 file(s) FAILED` with

```
Parse error: Unexpected token `an identifier`, expected Eof
```

on `010_documents`, `020_chunks`, `030_records`, `040_graph`, `060_functions`. The 3.x-only
constructs that trip it are `COMPUTED` fields and `FULLTEXT ANALYZER … BM25 HIGHLIGHTS`
(2.x spelled the latter `SEARCH ANALYZER`).

**Only 3.x betas exist** — `3.0.0a1`…`3.0.0b8`. Use `3.0.0b8`. Installing plain
`surrealdb==3.0.0b8` is *not enough*; embedded URLs then fail with

```
UnsupportedEngineError: Unsupported protocol in URL: surrealkv://...
```

You must install the `[embedded]` extra, which pulls the separate `surrealdb-embedded`
wheel. Verify both:

```bash
python3.exe -c "import importlib.metadata as m; print(m.version('surrealdb'), m.version('surrealdb-embedded'))"
```

---

## 2 · Standing it up from zero

```bash
cd E:/AI_Workspace/Projects/Propria/Probata/probata

# 1. schema (URL arg optional since 2026-09-09; falls back to SURREAL_URL in .docstore/.env)
python3.exe scripts/docstore/apply_schema.py

# 2. ingest
cd scripts/docstore
DOCSTORE_COCOINDEX_DB="<repo>/.docstore/cocoindex_state_v5.db" \
DOCSTORE_MAPPING_CSV="<repo>/scripts/docstore/mapping/docs-ingest-mapping.csv" \
DOCSTORE_MAX_RSS_MB=2048 \
  python3.exe flow_docs.py
```

Expect **all 9 schema files `ok`** and a full ingest in roughly **7 minutes**.

### GOTCHA 2 — `COCOINDEX_DB` is ignored; the variable is `DOCSTORE_COCOINDEX_DB`

`flow_docs.py:127` pins CocoIndex's state directory from `DOCSTORE_COCOINDEX_DB`, defaulting
to `.docstore/cocoindex_state.db`. Setting the upstream `COCOINDEX_DB` does **nothing**.

This is the most dangerous failure mode in the system: pointing at a *stale* state directory
makes CocoIndex believe every file is already processed. The run reports

```
process_file: 495 total | 1 added, 494 reprocessed        exit 0
```

…and writes **nothing**. The store stays empty while the log says success.

**To force a full re-ingest, point `DOCSTORE_COCOINDEX_DB` at a fresh path** (or use
`--full-reprocess`, §7).

### GOTCHA 3 — exit code 0 means nothing

CocoIndex's `mount()` / `mount_each()` **log errors at ERROR level and do not propagate
them**. A run can fail 455 of 495 files and still exit 0 — observed live on the VPS attempt:
`40 added, 455 ⚠️ errors`, exit 0.

**Never accept exit status as evidence.** Always:

```bash
grep -cE "ERROR|Traceback" .docstore/ingest-run<N>.log      # must be 0
grep -E "process_file: .* total \|" .docstore/ingest-run<N>.log | tail -1
```

…then count rows in the store.

---

## 3 · Verified state (2026-09-09)

| Metric | Value |
|---|---|
| documents | **493** |
| chunks / `chunk_of` edges | **11,436** each |
| chunks with embeddings | **11,436** (100%) |
| full ingest wall time | ~7 min (~500 NIM calls) |
| incremental ingest (1 new file) | **37 s** |
| ingest errors | 0 |

Document types (the D-156 seven):

```
review 167 · blueprint 142 · decision 65 · handoff 63 · reference 37 · todo 12 · infrastructure 3
```

### GOTCHA 4 — the ingest populates only 3 tables

The biggest structural surprise. Live counts:

| Table | Rows | Populated by |
|---|---|---|
| `document` | 493 | the ingest |
| `chunk`, `chunk_of` | 11,436 | the ingest |
| **`adr`** | **0** | **nothing** |
| `entity`, `mentions`, `blocks`, `derived_from` | 0 | nothing |
| `retrieval` | written by `fn::recall` | audit trail |
| `decision_log`, `todo`, `supersedes` | only what `fn::` calls create | — |

The 63 ADR files **were** ingested — as `document` rows with `doc_type='decision'`. But the
`adr` **table** is empty, and `fn::current_decisions()` queries that table, so it returns
**0 rows on a fully-populated store**. Same for `entity`/`mentions`: the graph layer in
`030_records.surql` / `040_graph.surql` has no writer at all.

Do not read "0 rows" from those functions as a broken store.

---

## 4 · The API surface — 16 `fn::` functions

```
fn::docs_search($query: string, $vec: option<array<float>>, $doc_type: option<string>,
                $domain: option<string>, $status: option<string>, $k: option<int>)
fn::docs_get($id: record<document>)
fn::docs_register($source_path, $title, $doc_type, $domains: array<string>,
                  $status, $body, $authored_at: option<datetime>)
fn::docs_new_version($old: record<document>, $body: string, $title: option<string>)
fn::docs_supersede($new: record<document>, $old: record<document>)
fn::search_vec($q: array<float>, $project: option<string>, $doc_type: option<string>)
fn::search_text($terms: string, $project: option<string>, $doc_type: option<string>)
fn::recall($query: string, $q: array<float>, $project, $doc_type, $agent: string)
fn::provenance($subject: record)
fn::open_work($project: string)
fn::current_decisions($project: string)
fn::stale_candidates($older_than: duration)
fn::todo_open($item: string, $priority: int, $domains: array<string>, $source: option<string>)
fn::todo_close($id: record<todo>, $evidence: string)
fn::decision_amend($subject: string, $banner: string, $closes: option<array<record<document>>>)
fn::handoff_write($title: string, $body: string, $domains: array<string>)
```

### GOTCHA 5 — `fn::recall` was broken; the fix is a 3.x syntax change

`fn::recall` writes an audit row into `retrieval`, whose `scope` field is `TYPE object` on a
**SCHEMAFULL** table. Schemafull object fields reject undeclared nested keys, so every call
failed with:

```
Found field 'scope.doc_type', but no such field exists for table 'retrieval'
```

The fix is `FLEXIBLE` — but **the syntax moved in SurrealDB 3.x**:

```surql
-- 1.x / 2.x  → 3.x rejects: "Parse error: FLEXIBLE must be specified after TYPE"
DEFINE FIELD scope ON retrieval FLEXIBLE TYPE object DEFAULT {};

-- 3.x  ✔  now in 040_graph.surql
DEFINE FIELD OVERWRITE scope ON retrieval TYPE object FLEXIBLE DEFAULT {};
```

Fixed and verified 2026-09-09: `fn::recall` returns hits and `retrieval` records.

### GOTCHA 6 — `content_hash` is UNIQUE, and that is deliberate

Registering a document whose body is byte-identical to an existing one fails:

```
Database index `document_hash` already contains '<sha256>', with record `document:…`
```

**Correct behaviour, not a bug** — exact-duplicate suppression enforced at write time (the
`reconcile` skill depends on it). It surprises test harnesses that register the same body
twice under different paths. Vary the body, not just the path.

### GOTCHA 7 — there is no DELETE, by design

No `fn::` deletes anything. Retirement is `docs_new_version` / `docs_supersede` /
`decision_amend` moving a record to `superseded` / `retracted`. Preserve this in any API
built on top — do not add a delete verb.

---

## 5 · Change detection — verified working

Memoizes on the **file content fingerprint** plus the mapping-CSV fingerprint (v5 fixed an
earlier bug that keyed on the CSV row only, so editing a document never re-ingested it).

Verified 2026-09-09: added one new document + one mapping row, re-ran the ingest against the
**same** state directory:

```
496 total | 1 added, 495 reprocessed     37 s, 0 errors
documents 492 → 493, new doc present with correct doc_type/status
```

37 s versus ~7 min for a full run confirms embeddings are not recomputed for unchanged files.

### GOTCHA 8 — a file with no mapping row is silently skipped

`flow_docs.py` ingests only `.md` files that have a row in the mapping CSV. Everything else
logs one line and is dropped:

```
docstore: SKIP (no mapping row) docs/<path>.md
```

**Adding a document to `docs/` is not enough.** You must add a mapping row
(`source_path,doc_type,domains,status,supersedes_path,title,bytes,sha256,mirror_path,notes`)
or it is never indexed. 14 non-markdown rows in the CSV are typed but permanently ineligible
(3 Go, 9 `.txt`/`.err`, 1 `.yaml`, 1 recovered `.txt`) and await a ruling.

### GOTCHA 9 — CocoIndex deletes by omission

From the CocoIndex docs: *"if you stop declaring a target state, CocoIndex will remove it
from the target."* A run declaring a **subset** **deletes every document it did not declare**.
`DOCSTORE_ONLY_FILES` and any partial-scope reindex are therefore destructive. Any API or UI
exposing "reindex" must guard this at the API layer, not the UI.

---

## 6 · Operating the store

### GOTCHA 10 — embedded SurrealKV is single-process exclusive

Only one process may hold `.docstore/kv` at a time. While an ingest runs, other connections
fail with:

```
IO error: The process cannot access the file because another process has locked
a portion of the file. (os error 33)
```

Consequence: **the docs MCP server and the ingest can never run simultaneously.** An
always-on MCP server holding the store blocks every ingest.

### GOTCHA 11 — an unclean shutdown corrupts the store

The ingest tears down uncleanly (`asyncio.InvalidStateError`, "Task was destroyed but it is
pending"); a crash mid-run leaves a truncated WAL and the store refuses to open:

```
Failed to create datastore: ... Log error: IO error: kind=unexpected end of file
```

This happened twice on 2026-09-09, costing a 770 MB store each time. **The store is derived
data — rebuild, don't repair.** Quarantine `kv/`, re-apply schema, re-ingest (~7 min). Never
attempt WAL surgery.

### GOTCHA 12 — absolute paths break on any directory rename

`SURREAL_URL` is an absolute path (`surrealkv://E:/…/.docstore/kv`). After the
`the-platform-workspace` → `Propria/Probata` rename it still pointed at the old location, so
SurrealKV **silently created a brand-new empty store there** — no error, zero documents, and
it recreated the dead directory tree on disk.

After ANY move, re-check `.docstore/.env`. The same class of breakage hits
`.docstore/venv/Scripts/*.exe` — uv trampolines embed absolute paths, so `cocoindex.exe`
fails with `uv trampoline failed to canonicalize script path`. Work around it by invoking
the module:

```bash
python3.exe -c "from cocoindex.cli import cli; cli()" --help
```

### GOTCHA 13 — re-applying the schema to a populated store is slow

Seconds on an empty store; **minutes** against 11,436 chunks, because `DEFINE TABLE OVERWRITE`
rebuilds the BM25 fulltext and HNSW vector indexes. It does **not** destroy rows (verified:
492/11,436 survived intact). Budget the time; don't assume it hung.

---

## 7 · CocoIndex facts worth knowing (from the docs, not folklore)

| Fact | Why it matters |
|---|---|
| `max_inflight_components` default is **1024** | Let 489 files run at once and consume 17 GB, crashing the desktop. `flow_docs.py` pins 4 plus an RSS guard (`DOCSTORE_MAX_RSS_MB`). |
| `--full-reprocess` | Bypasses memoization — the documented way to force a rebuild, cleaner than swapping state dirs. |
| `--reset`, `--preview` | `--reset` drops setup first; `--preview` shows planned actions without applying — a real dry run against the delete-by-omission risk. |
| `handle.stats()` / `handle.watch()` | Snapshot and async-iterator progress: `num_adds`, `num_unchanged`, `num_deletes`, `num_reprocesses`, `num_errors`. The right basis for a progress API. |
| Environments isolate state | `flow_docs.py` correctly uses `coco.Environment(name="probata-docstore")` via `AppConfig(environment=…)`, so the `ccc` pipeline cannot share tracking records. (`README.md`'s claim that "the default environment is kept deliberately" is **stale** — the code does the opposite, correctly.) |

---

## 8 · Verifying it works

`verify_docstore.py` (in this directory) exercises all 16 functions, retrieval, and the write
paths, printing PASS/FAIL per check. It is **re-runnable** — every body it writes is stamped so
`content_hash` stays unique (GOTCHA 6).

```bash
cd <repo root>            # must run from the repo root: it reads .docstore/.env
python3.exe scripts/docstore/verify_docstore.py
```

Last run, 2026-09-09 — **17/18 PASS**:

```
[PASS] store populated            494 documents, 11437 chunks
[PASS] fn::search_text            20 hits
[PASS] NIM embedding reachable    dim=2048
[PASS] fn::search_vec             6909 hits   (see GOTCHA 14)
[PASS] fn::docs_search (hybrid)   5 hits
[PASS] fn::recall                 (after the FLEXIBLE fix)
[PASS] fn::docs_get               [PASS] fn::provenance
[PASS] fn::docs_register          [PASS] fn::docs_new_version
[PASS] fn::todo_open              [PASS] fn::todo_close
[PASS] fn::handoff_write          [PASS] fn::decision_amend
[PASS] fn::open_work / fn::current_decisions / fn::stale_candidates   (0 rows - GOTCHA 4)
[FAIL] DB-created ADR materializes as a FILE                          (SS 9 item 1 - not built)
```

The single FAIL is the known gap, not a regression: an ADR written through the database does
**not** appear on disk. Everything else is green.

The harness writes records under a `verify/` `source_path` prefix and prints the stamp so they
can be superseded later. It never deletes (GOTCHA 7).

### GOTCHA 14 — `fn::search_vec` returns everything

One call returned **6,908 hits** — no meaningful LIMIT or distance threshold. It "works" but
is not a usable search primitive alone. Prefer `fn::docs_search`, which takes `$k` and
returned a sane 5. Treat `search_vec` as a building block that must be bounded before any
API exposes it.

---

## 9 · Known gaps — NOT built

1. **No DB → filesystem writer.** A document created via `fn::docs_register` exists only in
   the store; **no markdown file is produced**. `mirror_docs.py` moves *existing* files via
   `git mv` from the mapping CSV — it does not emit files from database rows. So "add an ADR
   through the database and see it in `docs/`" **does not work today**. Highest-value missing
   piece.
2. **ADR consolidation.** There are **63 separate ADR files**, and the mapping currently
   mirrors all 63 into `docs/decision/` individually. Owner ruling 2026-09-09: this must
   become **one clean consolidated ADR document**, not 63. The mapping CSV must change to
   match. ADRs are otherwise append-only records, so consolidation must preserve every entry
   verbatim.
3. **No HTTP API.** The store is reachable only through MCP `run` on the 16 functions.
   Nothing in `server/`, `modules/workbench/`, or `modules/engine/` calls it, so a front end
   cannot use it. Everything *else* in the platform is API-first: `server/` is a versioned
   `/v1` spine (55 routes) with a BFF (`modules/workbench/api`, 100 routes) that proxies it.
4. **The `adr`/`entity`/graph tables have no writer** (GOTCHA 4).
5. **`mirror --apply` never run** — 496 moves / 225 link rewrites pending; the seven-folder
   D-156 tree does not exist on disk yet.
6. **Compact hooks not repointed** — D-156 requires it in the same change. The hooks writing
   `TODO-SNAPSHOT-*.json` and empty `COMPACT-SUMMARY-*.md` belong to the **`FlineDev/recall`
   plugin**, not to probata.
7. **The write gate only warns.** `flag-doc-write.sh` is `PostToolUse` — it fires *after* the
   write and prints a reminder. Real read-only enforcement needs a `PreToolUse` deny hook.
   `DOCSTORE_DOCS_ROOT` defaults to `docs`, so nesting the tree under a differently named
   folder silently disables the gate entirely.

---

## 10 · The plugin

`plugins/docstore/` — passes `claude plugin validate --strict`.

| Skill | Purpose |
|---|---|
| `docs` | search / get / provenance |
| `docs-write` | register, new version, supersede |
| `decisions` | ADR banners, D-rows |
| `todo` | open / close |
| `handoff` | write and mirror |
| `memory` | remember / recall / supersede / forget |
| `reconcile` | stale candidates, dedupe, ingest mapping |

Agents: `docstore-librarian` (Sonnet, the only writer), `docstore-reconciler` (Opus,
interactive, never batch-writes), `memory-curator` (Sonnet).

Hooks: `SessionStart`→`preflight.sh`, `UserPromptSubmit`→`read-gate.sh`,
`PostToolUse`→`flag-doc-write.sh` + `track-tool-use.sh`, `PreCompact`→`precompact-marker.sh`.

**Codex side is a stub**: `.codex/docstore/` has `config.toml` and `AGENTS.md`, but
`prompts/` is **empty** — the seven prompts the README promises were never written.

---

## 11 · Troubleshooting quick table

| Symptom | Cause | Fix |
|---|---|---|
| `5 file(s) FAILED`, `expected Eof` | SDK 2.x engine vs 3.2 schema | install `surrealdb[embedded]==3.0.0b8` |
| `UnsupportedEngineError: surrealkv://` | missing `[embedded]` extra | install the extra |
| "N reprocessed", store empty | stale `DOCSTORE_COCOINDEX_DB` | fresh state dir, or `--full-reprocess` |
| exit 0 but few rows | `mount_each` swallows errors | grep the log for `ERROR` |
| `os error 33` / file locked | embedded store is single-process | stop the other holder |
| `unexpected end of file` on open | truncated WAL from a crash | quarantine `kv/`, re-apply schema, re-ingest |
| Store silently empty after a move | absolute `SURREAL_URL` in `.env` | repoint `.docstore/.env` |
| `uv trampoline failed to canonicalize` | venv shim holds an old absolute path | `python -c "from cocoindex.cli import cli; cli()"` |
| `document_hash already contains` | identical body already registered | intended dedupe — vary the body |
| `fn::current_decisions` returns 0 | `adr` table has no writer | expected; GOTCHA 4 |
| `FLEXIBLE must be specified after TYPE` | 1.x/2.x syntax on a 3.x engine | `TYPE object FLEXIBLE` |

---

## 12 · The VPS option (attempted, currently NOT viable)

Moving the store to the VPS SurrealDB (`ws://100.91.190.107:8471`, SurrealDB 3.2.4,
namespace `probata`, database `docs`, NS-scoped user `probata`) **failed**: `40 added,
455 errors` over 31 minutes, and it **deadlocked the container**, which also serves the
family-court case store (`fct` namespace).

Isolation itself was proven — the `probata` user is DENIED on both the `fct` namespace and
`INFO FOR ROOT` — so the namespace split is sound. The failure was capacity.

Root cause: the container was capped at `mem_limit: 2g` / `cpus: 1.5` in
`deploy/surreal-case.yaml`, so SurrealDB reported `available_parallelism: 1` while four
concurrent writers pushed 11,436 vector inserts at it. It wedged at **0% CPU** (deadlock, not
saturation) with 59 consecutive failed health checks, and required a container restart.

Both caps were removed on owner order (2026-09-09) — live via the rendered compose on the
host, and in `deploy/surreal-case.yaml`. **That repo change must be committed**, or the next
Coolify redeploy pulls from git and re-applies the caps, reproducing the deadlock.

`flow_docs.py` also gained `_server_credentials()` so a **namespace-scoped** user can
authenticate: the connector's `{username, password}` shape fails for such users; `namespace`
must be included. Opt in with `SURREAL_SIGNIN_NS`. Verified: user+pass alone → FAIL,
user+pass+namespace → OK.

Retrying the VPS ingest is reasonable now the caps are gone, but it is **unverified**.
