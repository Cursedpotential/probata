---
name: docstore
description: THE entry point for the Propria Docstore. Use whenever an agent must read, search, cite, submit, update, tag, hand off, decide, retract or verify project documentation, decisions, todos or handoffs — or is unsure which Docstore tool/skill applies. It orients, then routes to the exact function, tool or sub-skill. Triggers on "docstore", "docs store", "where is that documented", "record this decision", "write a handoff", "register this doc", "tag this", "is the index fresh", "what did we decide about".
allowed-tools: mcp__plugin_probata-docstore_docs__run mcp__plugin_probata-docstore_docs__query mcp__plugin_probata-docstore_docs__list mcp__plugin_probata-docstore_control__coco_docstore_search mcp__plugin_probata-docstore_control__docstore_search mcp__plugin_probata-docstore_control__docstore_get mcp__plugin_probata-docstore_control__docstore_health mcp__plugin_probata-docstore_control__docstore_index_full mcp__plugin_probata-docstore_control__docstore_verify_index mcp__plugin_probata-docstore_control__docstore_flags mcp__plugin_probata-docstore_control__docstore_set_flags mcp__plugin_probata-docstore_control__docstore_handoff_write mcp__plugin_probata-docstore_control__docstore_project_sources Read
---

# Docstore — use the system, this is the process

> _Byline: Claude Code · Fable 5.1 · 2026-09-14 — owner 21:16 EDT: "I need something that informs and guides it: hey, this is the plugin process you need to use, use it."_

Docstore is the universal Propria documentation plane (owner decision 2026-09-12).
Every project's docs, decisions, todos and handoffs live here. Before you answer
about docs or decisions, query it. Before you write, know which lane you are in.

## 1. Orient in 30 seconds

| You are trying to… | Do this | Never |
|---|---|---|
| **Find** what was decided / documented | `fn::docs_search(query, NONE, doc_type|NONE, domain|NONE, status|NONE, k)` — status NONE = every status; then `fn::docs_get(id)` for the full row. Agent-grade hybrid search with critical-flag context: control tool `coco_docstore_search(query, domain, status="all")`. Decisions: `fn::current_decisions(project)` (adr table) **and** `docs_search(..., "decision", ...)` — an empty result is a finding, not an answer. | Answer from memory; stop at the first hit (owner: "NEVER STOP AT THE FIRST RESULT"). |
| **Find by tag** ("everything about UI components") | `fn::docs_tagged(tag, query|NONE, domain|NONE, k|NONE)` | Guess a tag; check `docs_tagged` returns rows and read `tags` on results. |
| **Add a doc that lives in a repo** (any file under a registry root: Probata `docs/**`, Consignatio, Legal-desktop, family-court, vestigia, Propria root docs) | **Write the file with tags** (front matter `tags: [..]` or `<!-- tags: a, b -->`). The CocoIndex pipeline indexes it on the next run (control tool `docstore_index_full`; verify with `docstore_health` → `cdc_attribution.status = verified`). | **Hand-register it** with `fn::docs_register` / `docs_new_version` — the UNIQUE `content_hash` index makes the hand row collide with the pipeline's row and fail the run. |
| **Add a file-less note or record** | skill `docs-write`: `fn::docs_register(...)` then `fn::docs_set_tags(id, tags, actor)`; read back with `docs_get`. | Register without tags; register a file the pipeline owns. |
| **Write a handoff** (end of session, before compact) | skill `handoff`: body starts with `<!-- tags: ... -->`; control tool `docstore_handoff_write{title, body, domains}`; then `fn::docs_set_tags`. It supersedes the previous ACTIVE handoff with any overlapping domain — choose domains narrowly. | Drop a HANDOFF-*.md file as the record. |
| **Record a decision / ADR** | Write the decision file in the owning repo `docs/decisions/` or `docs/adr/` **with tags**, let the pipeline index it, then `fn::decision_amend(source_path, banner, closes|NONE)` for the log row and supersedes edges. Skill `decisions`. | Hand-write `decision_log`; hand-register the file. |
| **Update an existing file-less record** | `fn::docs_new_version(old_id, body, title|NONE)` (inherits type/domains, supersedes old). For files: edit the file; pipeline re-indexes. | Edit rows directly. |
| **Retire a duplicate / wrong row** | `fn::docs_retract(id, reason)` — keeps body + history, releases the hash, logs `document_retracted`. | DELETE anything. |
| **Todos** | skill `todo`: `fn::todo_open(item, priority, domains, source|NONE)`, `fn::open_work(project)`, `fn::todo_close(id, evidence)`. | Track work only in chat. |
| **Flag a critical decision so it surfaces in every search of a domain** | control tool `docstore_set_flags` (priority/authority/status); read with `docstore_flags(domain)`. | Use flags as tags (tags are topical; flags are priority/authority). |
| **Check freshness / prove the index** | `docstore_health` (latest run + CDC attribution), `docstore_verify_index(paths)` for specific files, `docstore_project_sources` for the six roots. | Claim "indexed" from a file write. |
| **Provenance** | `fn::provenance(record)` — history + sources. | — |

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
