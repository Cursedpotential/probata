---
name: docstore
description: THE entry point for the Propria Docstore. Use whenever an agent must read, search, cite, submit, update, tag, hand off, decide, retract or verify project documentation, decisions, todos or handoffs — or is unsure which Docstore tool/skill applies. It orients, then routes to the exact function, tool or sub-skill. Triggers on "docstore", "docs store", "where is that documented", "record this decision", "write a handoff", "register this doc", "tag this", "is the index fresh", "what did we decide about".
allowed-tools: mcp__plugin_propria-docstore_docs__run mcp__plugin_propria-docstore_docs__query mcp__plugin_propria-docstore_docs__list mcp__plugin_propria-docstore_control__coco_docstore_search mcp__plugin_propria-docstore_control__docstore_search mcp__plugin_propria-docstore_control__docstore_get mcp__plugin_propria-docstore_control__docstore_health mcp__plugin_propria-docstore_control__docstore_index_full mcp__plugin_propria-docstore_control__docstore_verify_index mcp__plugin_propria-docstore_control__docstore_flags mcp__plugin_propria-docstore_control__docstore_set_flags mcp__plugin_propria-docstore_control__docstore_handoff_write mcp__plugin_propria-docstore_control__docstore_project_sources Read
---

# Docstore — use the system, this is the process

> _Byline: Claude Code · Fable 5.1 · 2026-09-14 — owner 21:16 EDT: "I need something that informs and guides it: hey, this is the plugin process you need to use, use it."_

Docstore is the universal Propria documentation plane (owner decision 2026-09-12).
Every project's docs, decisions, todos and handoffs live here. Before you answer
about docs or decisions, query it. Before you write, know which lane you are in.

## 1. Orient in 30 seconds

| You are trying to… | Do this | Never |
|---|---|---|
| **Find** what was decided / documented | `fn::docs_search(query, vec, doc_type, domain, status, k)` — every optional accepts JSON `null` **or** `NONE` (see §1a); status unset = every status. Returns a compact projection (id, title, source_path, status, doc_type, domains, tags, score, `snippet` ≤300 chars); then `fn::docs_get(id)` for the full body. Agent-grade hybrid search with critical-flag context: control tool `coco_docstore_search(query, domain, status="all")`. Decisions: `fn::current_decisions(project)` (adr table) **and** `docs_search(..., "decision", ...)` — an empty result is a finding, not an answer. | Answer from memory; stop at the first hit (owner: "NEVER STOP AT THE FIRST RESULT"). |
| **Find by tag** ("everything about UI components") | `fn::docs_tagged(tag, query|NONE, domain|NONE, k|NONE)` | Guess a tag; check `docs_tagged` returns rows and read `tags` on results. |
| **Add a doc that lives in a repo** (any file under a registry root: Probata `docs/**`, Consignatio, Legal-desktop, family-court, vestigia, Propria root docs) | **Write the file with tags** (front matter `tags: [..]` or `<!-- tags: a, b -->`), then **one command**: `python3 scripts/docstore/index_now.py --path <projected/source/path.md>`. It pushes the projection, runs one governed full run, waits, asserts `cdc_attribution.status = verified`, and prints the stored record id. See §1b — a file OUTSIDE Probata does **not** reach the worker just by being written. | **Hand-register it** with `fn::docs_register` / `docs_new_version` — the UNIQUE `content_hash` index makes the hand row collide with the pipeline's row and fail the run. Call `docstore_index_full` alone for a non-Probata file — that indexes the OLD projection and your file silently never appears. |
| **Add a file-less note or record** | skill `docs-write`: `fn::docs_register(...)` then `fn::docs_set_tags(id, tags, actor)`; read back with `docs_get`. | Register without tags; register a file the pipeline owns. |
| **Write a handoff** (end of session, before compact) | skill `handoff`: body starts with `<!-- tags: ... -->`; control tool `docstore_handoff_write{title, body, domains}`; then `fn::docs_set_tags`. **Supersede rule (fixed 2026-09-16):** it supersedes every ACTIVE handoff whose domain SET equals `domains` EXACTLY; a merely overlapping handoff is left alone. Pass a 4th arg `supersedes` (array of document ids) to name the targets explicitly. | Drop a HANDOFF-*.md file as the record. Assume an overlapping-domain handoff will be superseded — until 2026-09-16 it superseded ONE arbitrary overlapping handoff (`LIMIT 1`) and clobbered other lanes. |
| **Record a decision / ADR** | Write the decision file in the owning repo `docs/decisions/` or `docs/adr/` **with tags**, let the pipeline index it, then `fn::decision_amend(source_path, banner, closes|NONE)` for the log row and supersedes edges. Skill `decisions`. | Hand-write `decision_log`; hand-register the file. |
| **Update an existing file-less record** | `fn::docs_new_version(old_id, body, title|NONE)` (inherits type/domains, supersedes old). For files: edit the file; pipeline re-indexes. | Edit rows directly. |
| **Retire a duplicate / wrong row** | `fn::docs_retract(id, reason)` — keeps body + history, releases the hash, logs `document_retracted`. | DELETE anything. |
| **Todos** | skill `todo`: `fn::todo_open(item, priority, domains, source|NONE)`, `fn::open_work(project)`, `fn::todo_close(id, evidence)`. | Track work only in chat. |
| **Flag a critical decision so it surfaces in every search of a domain** | control tool `docstore_set_flags` (priority/authority/status); read with `docstore_flags(domain)`. | Use flags as tags (tags are topical; flags are priority/authority). |
| **Check freshness / prove the index** | `docstore_health` (latest run + CDC attribution), `docstore_verify_index(paths)` for specific files, `docstore_project_sources` for the six roots. | Claim "indexed" from a file write. |
| **Provenance** | `fn::provenance(record)` — history + sources. | — |

## 1a. Exact call forms — every row below was proven live by `scripts/docstore/test_plugin.py`

Run the harness after any change to these functions: it enumerates every `fn::`
in the store, calls each in every documented argument form, replays every
statement embedded in these skills, exercises all three MCP servers, and prints
a pass/fail matrix (zero FAILs is the bar).

| Argument | Send | Also accepted | Notes |
|---|---|---|---|
| unset optional (`vec`, `doc_type`, `domain`, `status`, `k`, `closes`, `title`, `source`, `authored_at`, `supersedes`) | JSON `null` | `NONE`, or `{"$ql": "NONE"}` | Fixed 2026-09-16. Before that, `null` failed with ``Failed to coerce argument `$vec`: Expected `none | array<float>` but found `NULL` `` and the MCP `run` tool could not call `fn::docs_search` at all. |
| a document/todo id | `"document:abc123"` (plain string) | `{"$ql": "document:abc123"}`, or a native record id | Fixed 2026-09-16 for `docs_get`, `docs_retract`, `docs_set_tags`, `docs_new_version`, `docs_supersede`, `todo_close`. Before that a string failed with ``Expected `record<document>` but found 'document:xyz'``. |
| a duration (`stale_candidates`) | `"90d"` (plain string) | `{"$ql": "90d"}`, or native `90d` | Fixed 2026-09-16; JSON has no duration literal. |
| `k` | any int; omit/`null` → 10 | — | `k > 20` switches the KNN branch to 50/256. |
| `status` | `"active"`, `"proposed"`, `"unverified"`, `"superseded"`, `"retracted"` | `null`/`NONE` = **every** status | Status is a classification field, not a visibility gate. |
| `domains` | only `probata`, `proffer`, `consignatio`, `advocatio`, `vestigia`, `indagatio`, `intake`, `workbench`, `knowledge`, `memory`, `infra`, `docs` | — | `document.domains` is ASSERTed against this closed set; anything else is rejected on write. |

Rule of thumb: **an omitted optional is `null`, an id is a plain string.** The
`{"$ql": ...}` sentinel still works everywhere and is the only way to pass a
value whose type JSON cannot express at all (datetimes, decimals, uuids).

## 1b. Getting a file outside Probata indexed (the projection)

The worker container reads its corpus from `/exchange/sources` on ovh-files,
which is a **pushed projection** of the monorepo — not the repos themselves.
So a new Consignatio / Legal-desktop / family-court / vestigia file is invisible
to the worker until the projection is rebuilt and pushed.

```
python3 scripts/docstore/index_now.py --path consignatio/docs/decisions/2026-09-16-catalog-source-of-truth.md
```

That is the whole procedure: build+push projection → `POST /runs` (full scope) →
poll → assert `cdc_attribution.status = verified` → read the record id back. It
refuses to start if another run is in flight. The stored `source_path` is the
**projected** path: the registry's `canonical_prefix` replaces the project's
`source_root`, so `Consignatio/docs/x.md` is stored as `consignatio/docs/x.md`.
Use `build_projection.py` directly (dry run by default) to inspect what would be
pushed; `index_now.py --no-push` re-runs the index without re-pushing.

## 2. Rules that are not optional

1. **Pipeline-only for repo files.** docs → CocoIndex worker → SurrealDB. Never hand-register a file under a registry root.
2. **Tags on every submission** (owner 2026-09-14 21:06). Lower-kebab; vocabulary in use: `ui-components`, `shadcn`, `design-system`, `search`, `intake`, `docstore`, `owner-directive`, `handoff`, `decision`. Add project/surface/system tags.
3. **Status is a classification field, not a visibility gate** (owner 2026-09-14 17:11). Ingest leaves `unverified`; search every status; a flag is set after classification/verification.
4. **Read before you write.** Query for related current decisions, then write through governed functions, then read the result back and report the record id.
5. **Preflight for decisions** (`E:\AI_Workspace\AGENTS.md`): Codex week, /read-memories, memsearch, CNF, .remember, Docstore. Codex is the design lead.
6. **No deletes.** Retract or supersede; nothing is removed.

## 3. Where things are

- Worker: Coolify app `probata-docstore-worker` (ovh-files); source `Probata/probata/scripts/docstore/` (`flow_docs.py`, `cdc_verify.py`, `tags_backfill.py`, `schema/*.surql`). Deploy branch `codex/docstore-operational-repair-20260913`; pushes to `scripts/docstore/**` or `docs/**` auto-redeploy and cancel a run in flight.
- Registry of the six roots: `Propria/docs/docstore-source-registry.json` (also carries the top-level `blocked_patterns` list, merged into every root by `source_registry.py`); the worker reads a pushed projection at `/exchange/sources` (rebuild + re-push after doc changes outside Probata until automated).
- `scripts/docstore/build_projection.py` — normalization: builds that `/exchange/sources` projection from the registry (decode/fold/dedupe/omit-empty, same logic the flow uses); dry run by default, `--push` to scp+swap it in. See `docs/docstore/LINT-AND-PROJECTION.md`.
- `scripts/docstore/docs_lint.py` — the linter: ENC001/EMPTY001/DUP001/PATH001/BLOCK001 (errors), TAGS001/BYLINE001/NBMP001/JUNK001/DATAURI001 (warnings), SIZE001 (dual). Runs standalone (`--registry` or `--paths`) and inside the worker's pre-run snapshot, recorded as `lint: {errors, warnings, findings[:200], largest_files}` in the run receipt. See `docs/docstore/LINT-AND-PROJECTION.md`.
- Store: SurrealDB `probata/docs` (`document`, `chunk`, `chunk_of`, `decision_log`, `todo`, `adr`, `docstore_flag`). Functions: `list functions` on the docs server.
- Sub-skills: `docs` (read), `docs-write`, `decisions`, `handoff`, `todo`, `query`, `reconcile`, `memory`.

## 4. Definition of done for any Docstore task

A record id or a verified CDC attribution, read back — never a file write alone. Say which lane you used.
