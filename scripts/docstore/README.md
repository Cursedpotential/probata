> ## ⚠️ SUPERSEDED IN PART — 2026-09-09 (Claude Code · Opus 5)
>
> The docstore now runs **fully embedded, in-process**. No server, no port, nothing
> resident. Everything below describing a server, a custom writer, or SurrealKit is
> **historical** — kept because the findings behind it are still true, but it no
> longer describes how this runs. Corrections, in order of importance:
>
> | Statement below | Now |
> |---|---|
> | Store reached over `ws://127.0.0.1:8462` (`SURREAL_BIND`) | `SURREAL_URL=surrealkv://.docstore/kv`, opened in-process. The 2.1 GB always-on RocksDB server and its Startup-folder launcher are quarantined in `to_be_deleted/2026-09-09-docstore-server-mode/`. |
> | A **custom `TargetHandler`** writes rows because the built-in target "cannot express `chunk.document`" | Uses the **built-in connector**. The link is a `chunk_of` RELATION written by `mount_relation_target`/`declare_relation`; `chunk.document` no longer exists. Typed arrays need `SurrealType("array<string>")` — a bare `list[str]` is sent as the JSON *string* `'["docs"]'` and rejected. |
> | Custom `/sql` batching by byte budget (`DOCSTORE_SQL_BATCH_BYTES`) | Gone. The connector owns writing. |
> | `COCOINDEX_DB` pinned at import; "an explicit `coco.Environment` would bypass the `@coco.lifespan`" | Explicit `coco.Environment(Settings.from_env(db_path=...), name="probata-docstore")` bound via `AppConfig(environment=...)`, per the docs' own table ("apps needing separate databases → explicit environments"). The lifespan *does* only register against the default environment, so context keys are provided through `DOCSTORE_ENV.context_provider` instead. The global env var is no longer mutated. |
> | `asyncio.Semaphore` around writes / concurrency worry | `LiteLLMEmbedder` batches natively (`@coco.fn.as_async(batching=True, max_batch_size=64)`); a semaphore only starves the batcher. Measured: bounding it changed peak RSS by 4 MB. |
> | RSS ceiling default 1024 MB | **2048 MB.** Measured 2026-09-09: ~225 MB is fixed import cost (litellm ~170 MB) and a 489-document run peaks near 1350 MB, so 1024 sat below the floor. |
> | SurrealKit applies the schema | SurrealKit, `surreal sql` and `surreal import` all need a **remote endpoint** and cannot reach an embedded store. `apply_schema.py` applies it in-process. |
> | Verify by hashing `read_text()` | `FileLike.read_text` does **not** translate newlines. Hash `read_bytes().decode("utf-8")`; `Path.read_text()` folds CRLF→LF and falsely reported 98 documents stale. |
>
> Also fixed 2026-09-09: `confidence` must be written explicitly and `observed_at`
> moved to `VALUE $value ?? time::now()`, because `UPSERT ... CONTENT` is a full
> replace and `DEFAULT` fires only on create — otherwise every re-ingest fails.
> Requires `surrealdb[embedded]==3.0.0b8` (pre-release) in `.docstore/venv`; the
> 3.2.0 CLI cannot read its store (storage format v3 vs v1).
>
> Verified after the rebuild: 489 documents, 11,436 chunks, 11,436 `chunk_of`
> edges, 0 stale, 0 absent, 0 unlinked, 0 wrong-dimension.

# probata docstore — CocoIndex → SurrealDB ingest

> _Byline: Claude Code · Sonnet 5 · 2026-09-09; Writer v2 amendment Claude Code · Fable 5.1 · 2026-09-09 08:01 EDT_

Ingests `docs/**/*.md` (excluding `docs/private/**` and `**/to_be_deleted/**`)
into the live SurrealDB `probata`/`docs` store: one `document` row per file,
heading-aware `chunk` rows with NVIDIA NIM embeddings, linked by SurrealDB
record references.

## Writer v4 (2026-09-09 09:15 EDT) — the documented CocoIndex mechanisms

Owner, 08:39–09:00: "how many hacks and shortcuts did you take without checking the documentation", "none of that is supposed to be the way it works", "make sure you have the change detection right so it automatically updates". Every piece below replaced something hand-rolled with the mechanism CocoIndex already documents.

| Was hand-rolled | Now |
|---|---|
| `asyncio.Semaphore` around writes | `AppConfig(max_inflight_components=8)` / `COCOINDEX_MAX_INFLIGHT_COMPONENTS` (default is 1024, which is why 489 documents ran at once) |
| per-document `print()` progress | `await coco.show_progress(handle)` (`report_to_stdout=` is the `update_blocking()` spelling; `update()` does not take it) |
| my own error list and stats summary | `handle.stats().total.num_errors` — note the installed 1.0.21 field is `num_errors`, the docs page says `num_errored` |
| declared-vs-present verify pass | reconciliation: CocoIndex removes records no longer declared |
| stale-row retract pass | same reconciliation, via `NON_EXISTENCE` |
| bypassing the target to write chunks | a **custom target connector**: `_DocHandler(coco.TargetHandler)` + `TargetActionSink.from_async_fn`, registered with `register_root_target_states_provider` |

The custom connector is the important one. The built-in SurrealDB target cannot express `chunk.document` (`record<document>`, required, no DEFAULT) because it inlines `json.dumps` text and documents no bound-parameter path — and all its tables share one transaction sink, so 489 documents' bodies committed together, which is what parked runs 5 and 6 with client and server both idle. Putting our own bound `/rpc` write inside `TargetHandler` keeps reconciliation, fingerprint-based change skipping, and interrupted-run recovery (`prev_possible_records` / `prev_may_be_missing`) instead of discarding all three.

One target state per document (`DocBundle` = the document row plus its chunk rows), so the pair is written in one transaction and removed together.

### Change detection (this was broken)

v3 memoized `process_doc(meta)` on the **mapping-CSV row**. Editing a document's text without touching the CSV left the memo key unchanged, so the file was skipped and the store kept the stale copy — while this README claimed it was "keyed by the file's content". It was not. The file is now an argument and a memo-key function is registered for `pathlib.Path` (`register_memo_key_function`, advanced_topics/memoization_keys) returning size, mtime and a SHA-256 of the content.

Proven live 2026-09-09 09:15 EDT on a three-file scoped run: fresh state → 3 documents / 31 chunks / 0 errors; re-run with no changes → `adds 0, unchanged 3`; append one line to one file's text, mapping row untouched → `reprocesses 2`, and the store's `content_hash` equals the edited file's SHA with the probe string present in both the body and a chunk. The file was then restored byte-identical.

### `MERGE`, not `CONTENT` — a silent data-loss bug this surfaced

`UPSERT … CONTENT` is a full replace, and a field's `DEFAULT` only fires on CREATE. So a `CONTENT` upsert over an **existing** row wipes the engine-owned fields and fails with `Couldn't coerce value for field 'confidence' … found NONE`. Measured live:

| Operation | Result |
|---|---|
| `UPSERT … CONTENT` on a new record | OK, `confidence` defaults to 0.5 |
| `UPSERT … CONTENT` on an existing record | **ERR**, `confidence` is NONE |
| `UPSERT … MERGE` on an existing record | OK, `confidence` preserved |

Every document could therefore be written exactly once; any re-ingest of an existing document was guaranteed to fail, and under the old silent write path that failure was invisible and the stale row stayed. Combined with the memo-key bug, updates could never have worked. The writer now uses `MERGE`.

### `age_days` blocked every genuinely new document (found 2026-09-09 09:45 EDT)

The 10 documents that did not already exist could not be created at all, while all 479 existing ones updated cleanly. Inside a transaction, `RETURN VALUE id` on a newly created row makes SurrealDB materialise the output record, which evaluates the `age_days` COMPUTED field before `observed_at`'s DEFAULT is visible. Two failures followed, in order:

| Attempt | Error |
|---|---|
| `time::now() - (authored_at OR observed_at)` | `Cannot perform subtraction with 'datetime' and 'none'` |
| adding `OR time::now()` as a fallback | `the operation results in a negative duration` — `time::now()` is re-read per occurrence, so the fallback lands microseconds after the left operand |

Isolated live: fails for a NEW record inside a transaction, succeeds for an existing record, succeeds with `RETURN NONE`. The field is now guarded on both conditions and returns `0s` rather than throwing:

```surql
DEFINE FIELD OVERWRITE age_days ON document
  COMPUTED (IF (authored_at OR observed_at) = NONE
              OR (authored_at OR observed_at) > time::now() { 0s }
            ELSE { time::now() - (authored_at OR observed_at) });
```

Real ages still report correctly afterwards (a fresh row reads `50ms`, an existing one `1h56m`). Only this one field definition was re-applied — re-applying the whole file would rebuild the BM25 fulltext indexes over 489 bodies.

### `body` is newline-normalized, not byte-exact (correction, 2026-09-09 09:45 EDT)

Earlier notes here and in `flow_docs.py` claimed the stored `body` is "byte-exact from disk". ~~byte-exact~~ That is **wrong for any CRLF file**: `path.read_text()` performs universal-newline translation, so the stored body uses LF and `content_hash = sha256(body.encode())` is the digest of the normalized text, not of the file's bytes. This is self-consistent — the hash always matches what is stored — and change detection is unaffected because the memo key hashes the RAW bytes and so still catches a newline-only change.

It did, however, break my own verification: hashing raw bytes made 97 correctly-written documents look stale. Any checker must hash the same way the pipeline does. This is the same mistake in a different costume as the 08:51 ruling — a check that does not mirror the operation it is verifying reports nonsense.

### Failure model

Success is proven by the write's own result in the same transaction, never by a follow-up `SELECT` or a row count taken afterwards (owner, 08:51: "the means of checking what is successful is wrong" — a later read shows the state, possibly set by someone else, not the effect of this statement). Each bundle's transaction binds `UPSERT … RETURN VALUE id` and `INSERT … RETURN VALUE id` and `THROW`s from inside SurrealDB when the affected-row counts are wrong, aborting the write. On the client, `_run_checked` uses `query_raw` and raises on the RPC error and on any statement with `status: ERR`, because the SDK's `query()` inspects only the first statement and returns `None` for an aborted transaction.

### State isolation

`ccc` runs its own CocoIndex pipeline on this machine. `COCOINDEX_DB` is pinned at import to `.docstore/cocoindex_state.db` (override with `DOCSTORE_COCOINDEX_DB`) so an ambient value from another pipeline cannot share tracking records. The default environment is kept deliberately: an explicit `coco.Environment` would bypass the `@coco.lifespan` that provides the SurrealDB and embedder context keys.

## Writer v2 (superseded by v4 above; kept for the record) — bound parameters over `/rpc`, lossless text pass
2026-09-09 08:01 EDT) — bound parameters over `/rpc`, lossless text pass

Owner question 07:45: "why are we using sql instead of its native query lang". `/sql` was only ever the HTTP endpoint name for SurrealQL, but the real point stood: v1 inlined JSON text into statements, and that is where two of the three ingest crashes lived. Owner approved (07:48) the rewrite plus a lossless text pass. Both are in `flow_docs.py`:

- **Chunk rows are bound, never inlined.** `write_chunks()` sends `UPSERT $i CONTENT $d` over the SDK's WebSocket `/rpc` connection with `RecordID("document", id)` for the link, Python `None` for a missing heading (arrives as NONE), and raw UTF-8 text. The v1 gotchas 1–4 below (record/datetime literal splicing, JSON null vs NONE, surrogate-pair escapes, the 1 MiB `/sql` body cap) are historical; none applies to the bound path.
- **Errors are loud.** The SDK's `query()` inspects only the first statement and returns `None`, no exception, for an aborted `BEGIN…COMMIT` block (confirmed live 07:50). `_run_checked()` uses `query_raw()` and raises on the RPC error and on any statement with `status: ERR`.
- **Batches of `DOCSTORE_CHUNK_BATCH_ROWS` (100) rows**, one transaction each; the 401-chunk digest went in as six batches (proof run 07:58).
- **End-of-run verify.** The official `document` target has the same `query()` blind spot (one transaction per batch, abort swallowed, CocoIndex records it as applied); 15 markdown files went missing that way in runs 2–4. `app_main` now compares declared `source_path`s against the store and exits 1 with the list if any is absent. A fresh `COCOINDEX_DB` forces re-declaration.
- **Text pass.** `body` on `document` stays byte-exact (hash verified); the chunk/embedding/BM25 text goes through `ftfy.fix_text` (mojibake, stray control characters, CRLF→LF) with NFC, `uncurl_quotes`/`unescape_html`/ligature/width folding OFF. Emoji, curly quotes and entities verified untouched. ASCII folding stays in the `doc_text` analyzer.
- The `_Utf8Json` shim on the official target stays until upstream stops ASCII-escaping (cocoindex 1.0.21 `_target.py:499`).

## Connector decision (v1 rationale, retained for the record; see Writer v2 above)

**CocoIndex ships an official SurrealDB target and it IS used here.**

- Package: `cocoindex[surrealdb]` (extra `surrealdb`, requires `surrealdb>=1.0.0`).
  Installed with:
  ```
  uv pip install --python "C:\Users\matts\.local\bin\python3.exe" --break-system-packages "surrealdb>=1.0.0"
  ```
  `python -c "import cocoindex.connectors"` shows no attributes because
  `cocoindex.connectors` is a lazy namespace package with no submodules
  imported yet — that is NOT evidence the SurrealDB connector is missing.
  `python -c "import cocoindex.connectors.surrealdb"` fails only until the
  `surrealdb` SDK dependency above is installed; after that it imports
  cleanly and exposes `ConnectionFactory`, `TableTarget`, `RelationTarget`,
  `TableSchema`, `SurrealType`, `mount_table_target`, `mount_relation_target`.
- SurrealDB's own docs confirm the same package name and install command:
  https://surrealdb.com/docs/build/integrations/ai-frameworks/cocoindex
- `document` is written entirely through the official connector:
  `surrealdb.mount_table_target(SURREAL_DB, "document", TableSchema.from_class(DocumentRow), managed_by="user")`
  → `doc_table.declare_record(row=...)`.

**`chunk`'s row *content* is written with one small raw SurrealQL helper
instead — not a hand-declared `connectorkits` target, and not because the
connector is unused, but because of two coercion gaps in this exact
SurrealDB build, found only by testing live (not assumed from docs):**

1. `TableTarget.declare_record()` always serializes row content through
   `json.dumps()`. SurrealQL's literal syntax is a superset of JSON: a
   record link needs the `r"table:id"` prefix and a strict `datetime` field
   needs `d"..."` (or a `<datetime>` cast) — `json.dumps` can only ever
   produce a plain quoted string, never one of those prefixed tokens.
2. This SurrealDB 3.2.0 instance does **not** implicitly coerce a plain
   string into either type. Verified against the live store:
   ```
   UPSERT zz_dt:a CONTENT { t: "2026-09-09T00:00:00Z" };    -- ERR: Couldn't coerce value ... Expected `datetime` but found '2026-09-09T00:00:00Z'
   UPSERT zz_dt:b CONTENT { t: d"2026-09-09T00:00:00Z" };   -- OK
   UPSERT chunk:x CONTENT { ...no document field... };      -- ERR: Couldn't coerce value ... Expected `record<document>` but found NONE
   UPSERT chunk:x CONTENT { ..., document: r"document:y" }; -- OK
   UPSERT chunk:x CONTENT { heading: null, ... };            -- ERR: Expected `none | string` but found NULL (JSON null ≠ SurrealQL NONE)
   ```
3. _(v1 text writer, historical; resolved by Writer v2)_ `json.dumps` must run with `ensure_ascii=False`. The default ASCII escaping turns any character outside the BMP (emoji such as 🤖) into a `\ud83e\udd16` surrogate pair, and the SurrealQL string parser rejects that with HTTP 400 "unicode escape character is not a valid unicode character" (verified live 2026-09-09 07:22 EDT; it killed full run 1 at document 333 of 503, the first file with an emoji; 0 of the 332 landed files contained one, 17 of the 171 missing did). Raw UTF-8 passes; BMP `\uXXXX` and `\n \t \f \b \" \\` escapes are accepted; `\/` is not, but `json.dumps` never emits it.
   The **official connector has the same defect**: `cocoindex/connectors/surrealdb/_target.py` lines 499 and 517 inline `json.dumps(content, default=str)` into `UPSERT ... CONTENT`, so full run 2 (chunk writer already fixed) died on the `document` row of the first emoji-bearing file (2026-09-09 07:36 EDT). `flow_docs.py` therefore installs a module-local shim (`_Utf8Json`) that makes that module's `json.dumps` default to `ensure_ascii=False`; remove it when upstream fixes the target (worth an upstream issue: cocoindex 1.0.21, surrealdb target, astral characters).
4. _(v1 text writer, historical; resolved by Writer v2)_ The `/sql` request body is capped (`SURREAL_HTTP_MAX_SQL_BODY_SIZE`, 1 MiB default; this server runs the default). A chunk row is ~40 KB as text because of the 2048-float embedding, so one request per document overflows at ~25 chunks (HTTP 413 Payload Too Large; killed full run 3 at 2026-09-09 07:46 EDT; the largest pending file is ~400 chunks). The writer therefore batches UPSERTs by byte budget (`DOCSTORE_SQL_BATCH_BYTES`, default 600 KiB), one transaction per batch, and sends the trailing-ordinal DELETE last. Atomicity is per batch, not per document; UPSERT by id makes a re-run complete a partial document.

`document.observed_at` sidesteps gap 2 for free: it's declared
`TYPE datetime DEFAULT time::now()` on the live schema, so `DocumentRow`
simply omits the field and the schema's own `DEFAULT` fires — no
literal-prefix problem, no custom code needed.

`chunk.document` (`TYPE record<document>`, no `option<>`, **no default**)
has no such escape — it's a required field only a raw `r"..."` literal can
satisfy — and `chunk.heading` needs the key *omitted* rather than sent as
JSON `null`. So `chunk` rows are written with one hand-rolled
`UPSERT chunk:<id> CONTENT {...}` per file, over the **HTTP `/sql`
endpoint** (both HTTP `/sql` and the official SDK are explicitly permitted
by the brief for this; `/sql` was chosen deliberately because it returns a
per-statement `status`/error — the async `surrealdb` SDK's `query()` was
tested side-by-side and **silently returned `None` with no exception** for
a whole `BEGIN...COMMIT` transaction SurrealDB itself had aborted, which
would make a failed ingest look like a successful one).

This mirrors CocoIndex's own reference example
(`examples/conversation_to_knowledge/conv_knowledge/app.py`, read from
GitHub): it never writes a plain `record<table>` field either — every
record link there goes through `RelationTarget.declare_relation()` against
a `TYPE RELATION` table. Our `chunk` is `TYPE NORMAL`, not a relation table,
and `managed_by="user"` forbids CocoIndex from ever redefining it into one
— so that mechanism doesn't apply to this schema, confirming the gap is
real rather than a design fumble on our part.

**Net effect:** the officially-shipped connector owns every table/column it
can actually express (all of `document`, and every `chunk` column except
`document`/`heading`'s literal-typing quirks). The one raw helper
(`write_chunks_raw()` in `flow_docs.py`) is the "connectorkits-style custom
code for a documented gap" fallback the task brief explicitly allows —
scoped to exactly the fields that need it, not a parallel hand-rolled
target.

## Schema (already applied, `managed_by="user"`)

`document` and `chunk` are defined by
`scripts/docstore/schema/010_documents.surql` and `020_chunks.surql`
(SurrealKit-managed). Every `mount_table_target(..., managed_by="user")`
call skips ALL of CocoIndex's own `DEFINE TABLE`/`DEFINE FIELD` DDL — this
was verified by reading `cocoindex/connectorkits/statediff.py`:
`resolve_system_transition()` returns `None` whenever
`desired.managed_by == "user"`, which short-circuits `_TableHandler`'s DDL
path entirely, every run, regardless of prior state. CocoIndex only ever
issues `UPSERT`/`DELETE` against the pre-existing table.

`DocumentRow`/`ChunkRow` in `flow_docs.py` are deliberately a **subset** of
each table's real columns — only the fields listed are written; every
omitted column keeps its live `DEFAULT` or existing value. Do not add a
field the SCHEMAFULL table doesn't define (it will reject the write); do
not add a table `DEFINE FIELD` yourself expecting CocoIndex to pick it up —
`managed_by="user"` means it never will.

## Setup

1. Python: `C:/Users/matts/.local/bin/python3.exe` (cocoindex 1.0.21, duckdb 1.5.4 already present).
2. Install the SurrealDB extra + litellm (OpenAI-compatible embedding op):
   ```
   uv pip install --python "C:\Users\matts\.local\bin\python3.exe" --break-system-packages "surrealdb>=1.0.0" litellm ftfy
   ```
   (`requests` arrives transitively via `surrealdb`; it backs the raw
   `/sql` chunk writer above.)
3. Confirm `NVIDIA_API_KEY` is set (used for the embedding calls).
4. Confirm `E:/AI_Workspace/Projects/the-platform-workspace/probata/.docstore/.env`
   has `SURREAL_USER`, `SURREAL_PASS`, `SURREAL_NS=probata`, `SURREAL_DB=docs`,
   `SURREAL_BIND=<host:port>`. **The flow reads `SURREAL_BIND` from this file
   at lifespan start and derives `ws://<bind>/rpc` and `http://<bind>` from
   it — the port is never hardcoded in code.** This matters because it has
   already moved once (8000 → 8462, owner ruling 2026-09-09) with zero code
   change required. Set `SURREAL_URL` explicitly only
   to override `.env`'s `SURREAL_BIND` for one run (see env vars below). The
   flow loads `.env` itself (`os.environ.setdefault`, so real env vars still
   win) — its contents are never printed.
5. CocoIndex needs its own local change-tracking state file (separate from
   the SurrealDB target): set `COCOINDEX_DB` to a path outside the repo,
   e.g. `C:/Users/matts/.claude/jobs/<job>/tmp/cocoindex_state/state.db`, or
   let it use its default location if you want persistent incrementality
   across sessions.

## Run

Full run (every eligible file in the mapping CSV):
```
cd E:/AI_Workspace/Projects/the-platform-workspace/probata/scripts/docstore
COCOINDEX_DB="<path-to-state.db>" "C:/Users/matts/.local/bin/python3.exe" flow_docs.py
```

Dry run / scoped run (only the named files — comma-separated `source_path`
values exactly as they appear in the mapping CSV's `source_path` column):
```
DOCSTORE_ONLY_FILES="docs/a.md,docs/b.md" \
    COCOINDEX_DB="<path-to-state.db>" "C:/Users/matts/.local/bin/python3.exe" flow_docs.py
```

Update (re-run any time): unchanged files are skipped automatically.
~~keyed by the file's content via CocoIndex's own memoization~~ — that was
FALSE until 2026-09-09 09:15 EDT: `process_doc` was memoized on the mapping-CSV row, so a
text edit was skipped. It now takes the file as an argument with a
content-derived memo key (see Writer v4), so only a changed file
re-chunks/re-embeds/re-writes. Every run's chunk write also `DELETE`s trailing chunk ordinals
past the current chunk count for that document, so a file that got shorter
doesn't leave orphaned old chunks behind.

## Environment variables

| Var | Default | Purpose |
|---|---|---|
| `DOCSTORE_REPO_ROOT` | `E:/AI_Workspace/Projects/the-platform-workspace/probata` | repo root; `docs/` is resolved under it |
| `DOCSTORE_MAPPING_CSV` | `C:\Users\matts\.claude\jobs\68afe1c5\tmp\out\docs-ingest-mapping.csv` | per-file metadata source |
| `DOCSTORE_STALENESS_INVENTORY` | `docs/reviews/2026-09-09-docs-staleness-inventory.md` | fallback metadata source, dry-run only, only if the CSV is missing |
| `DOCSTORE_ONLY_FILES` | unset (= full run) | comma-separated `source_path` allow-list |
| `DOCSTORE_ENV_FILE` | `<repo>/.docstore/.env` | where `SURREAL_*`/`NVIDIA_API_KEY` are loaded from if not already in the environment |
| `SURREAL_BIND` | (read from `.env`, currently `127.0.0.1:8462`) | `host:port` — the single source of truth for where the store listens; `SURREAL_URL` is derived from this and never hardcoded |
| `SURREAL_URL` | `ws://<SURREAL_BIND>/rpc` | override to bypass `SURREAL_BIND` for one run; official connector's websocket URL |
| ~~`SURREAL_HTTP_URL`~~ | — | unused since Writer v2 (chunk rows go over `/rpc`); kept here only so old notes resolve |
| `SURREAL_NS` | `probata` | namespace |
| `SURREAL_DB_NAME` (falls back to `SURREAL_DB`) | `docs` | database |
| `SURREAL_USER` / `SURREAL_PASS` | — (required, from `.env`) | credentials |
| `NVIDIA_API_KEY` | — (required) | NIM API key |
| `NVIDIA_API_BASE` | `https://integrate.api.nvidia.com/v1` | NIM OpenAI-compatible endpoint |
| `EMBED_MODEL` | `nvidia/nemotron-3-embed-1b` | NIM embedding model (2048-dim, symmetric — no `input_type` is ever sent) |
| `EMBED_DIM` | `2048` | must match the model and `chunk.embedding`'s `array<float,2048>` |
| `DOCSTORE_CHUNK_SIZE` / `_OVERLAP` / `_MIN_SIZE` | `1200` / `150` / `200` | chunking (chars) |
| `COCOINDEX_DB` | pinned to `.docstore/cocoindex_state.db` at import | CocoIndex's local change-tracking store (a directory, not the target store); pinned so ccc's pipeline cannot share it |
| `DOCSTORE_COCOINDEX_DB` | `.docstore/cocoindex_state.db` | override for the above |
| `COCOINDEX_MAX_INFLIGHT_COMPONENTS` | `8` | documented concurrency control; CocoIndex's own default is 1024 |
| `DOCSTORE_CHUNK_BATCH_ROWS` | `100` | chunk rows per bound `BEGIN…COMMIT` batch over `/rpc` (~1.7 MB CBOR); sized for the WebSocket frame limit, not the `/sql` body cap |
| `COCOINDEX_LOG_LEVEL` | `WARNING` | only honored by the `cocoindex` CLI's own logging setup, not by `python flow_docs.py` directly |

## Chunking

Heading-aware: `cocoindex.ops.text.RecursiveSplitter` splits with
`language="markdown"` (so splits respect markdown structure) at
`chunk_size=1200`, `chunk_overlap=150`, `min_chunk_size=200`. The splitter's
`Chunk` type doesn't carry a heading field in this CocoIndex version, so
`heading_for_offset()` builds a `(char_offset, heading_text)` index over the
document's `#`..`######` lines once per file and looks up the nearest
preceding heading for each chunk's start offset — kept per chunk in
`chunk.heading`.

`strip_data_uris()` removes any `data:image/...;base64,...` payload before
chunking/embedding (NIM 503s on those — see project CLAUDE.md).

## Embeddings

`cocoindex.ops.litellm.LiteLLMEmbedder` — CocoIndex's own OpenAI-compatible
embedding op, wired to NIM:
```python
LiteLLMEmbedder(f"openai/{EMBED_MODEL}", api_base=NVIDIA_API_BASE, api_key=...)
```
`input_type` is never passed (the model is symmetric — passing it would be
wrong for this model per project CLAUDE.md). Verified live: single embed
returns `(2048,) float32`; 5 concurrent `embed()` calls batch through NIM
correctly (`LiteLLMEmbedder` auto-batches concurrent same-`input_type`
calls via `@coco.fn.as_async(batching=True)`).

**Embeddings are API calls only — owner ruling: never run a local
embedding model on this desktop.** `flow_docs.py` never imports
`SentenceTransformerEmbedder`, FastEmbed, or any ONNX/local-inference path;
the only embedder wired in is `LiteLLMEmbedder` against NIM's hosted
endpoint. Do not add a local embedder as a fallback if the NIM call fails —
surface the error instead.

## Known limitations

- **Chunk-level incremental diffing is coarser than the official connector
  gives you for `document`.** File-level memoization (`@coco.fn(memo=True)`
  on `process_doc`) still means an unchanged file never re-embeds or
  re-writes. But within a changed file, chunk rows are UPSERTed
  unconditionally (not diffed field-by-field against prior state), and
  stale trailing ordinals are cleaned up with one `DELETE ... WHERE ordinal
  >= N` rather than CocoIndex's own per-record reconciliation. For this
  ingest's scale (docs, not a high-churn stream) that trade-off is fine;
  a future iteration could build a proper `connectorkits.target.TargetHandler`
  for `chunk` if finer-grained tracking becomes valuable.
- `document.tags` is always written as `[]` — the mapping CSV has no tags
  column. `document.confidence`/`retracted_reason`/`authored_at` are left
  at their schema defaults (unset/`0.5`) since no source of truth for them
  exists in the CSV yet.
- `token_est` is a cheap heuristic (`len(text)//4`), not a real tokenizer.

## Dry run (already performed, do not repeat as part of a "full run")

5 files (one per doc_type where a same-status active `.md` candidate
existed): `blueprint`, `decision`, `handoff`, `reference`, `review`. Full
command log, verification queries, and results are in
`C:/Users/matts/.claude/jobs/68afe1c5/tmp/out/2026-09-09-ingest-dry-run.md`.

## Full runs (executed 2026-09-09; v1 history, then v2)

| Run | Writer | Outcome |
|---|---|---|
| 1 (07:06) | v1 `/sql` text | crashed at 332/503: `json.dumps` surrogate-pair escapes for emoji rejected by the parser (HTTP 400) |
| 2 (07:26) | v1 + `ensure_ascii=False` | same escape bug one layer down, inside the official `document` target; `_Utf8Json` shim added |
| 3 (07:36) | v1 + shim | HTTP 413: one `/sql` request per document overflowed the 1 MiB body cap at ~25 chunks |
| 4 (07:46) | v1 + byte batching | exit 0, 474 documents, 11,430 chunks; 15 declared markdown rows silently missing (aborted connector batch swallowed by `query()`), 14 non-markdown mapping rows never eligible |
| 5 (08:00) | **v2 bound parameters** | fresh `COCOINDEX_DB` (`.docstore/cocoindex_state_v2.db`); result recorded in `docs/MASTER-TODO-2026-09-09.md` |

Run logs are kept under `.docstore/ingest-run<N>-*.log`. Current command:

```
cd E:/AI_Workspace/Projects/the-platform-workspace/probata/scripts/docstore
COCOINDEX_DB="E:/AI_Workspace/Projects/the-platform-workspace/probata/.docstore/cocoindex_state_v2.db" \
DOCSTORE_MAPPING_CSV="E:/AI_Workspace/Projects/the-platform-workspace/probata/scripts/docstore/mapping/docs-ingest-mapping.csv" \
    "C:/Users/matts/.local/bin/python3.exe" flow_docs.py
```

Eligibility: the flow declares only `.md` rows of the mapping (`load_doc_metas`). 14 mapping rows are non-markdown (3 Go sources, 9 `.txt`/`.err` introspection dumps, 1 OpenAPI `.yaml`, 1 recovered `.txt`) and are therefore never ingested; they are listed in `mapping/mapping-exceptions.md` pending the owner's ruling.
