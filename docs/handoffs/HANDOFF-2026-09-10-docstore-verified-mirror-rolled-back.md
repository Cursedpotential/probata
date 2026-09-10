# HANDOFF — docstore rebuild verified; mirror --apply attempted, damaged one file, rolled back (2026-09-10)

> _Byline: Claude Code · Opus 5 (1M context) · 2026-09-10_
STATUS: PARTIAL
BUILD_STATUS: NOT RUN (no build touched this session; docs and docstore only)

## Read this first

- **The docstore rebuild from 2026-09-09 succeeded and is verified.** Ingest run 15
  (13:48) finished 494/494 files with 0 errors. The store holds **489 documents and
  11,436 chunks** — the same 11,436 that existed before the 10:40 crash.
- **The mirror `--apply` was attempted and rolled back.** It clobbered one file
  (`docs/blueprint/index.md`) because of a Windows case-collision. Everything was
  recovered and verified. **No work was lost.** Details below, because the cause is
  a live trap for the next run.
- The docs tree is back to exactly its pre-apply state: 567 `.md` files,
  git `28 M / 17 ?? / 8 D`, both index files correct.

## Verified-live state

| Thing | State | How it was verified |
|---|---|---|
| Docstore contents | 489 documents, 11,436 chunks, 11,436 `chunk_of` | direct query |
| Embeddings | 0 wrong-dimension, 0 null; sampled chunks 2048-dim | direct query |
| Doc content vs disk | **490/490 hash-match, 0 stale, 0 absent, 0 extra** | checker that hashes the way the pipeline hashes |
| Docs tree after rollback | 567 `.md`, `28 M / 17 ?? / 8 D`, 0 staged leftovers | `git status`, `find` |
| Content preserved | **0 real content differences**; 94 files differ from the store in line endings only | normalized comparison |
| Mirror plan | 496 moves, 225 rewrites, dead links **73 -> 73, delta +0**, 0 missing sources | `mirror_docs.py` plan into a scratch out-dir |
| Store transport | embedded SurrealKV at `.docstore/kv` (771 MB). No server, no port 8462 | health probe fails; embedded opens fine |

**Hash the way the pipeline hashes** or every check lies: `read_bytes().decode("utf-8")`
(no newline translation) -> `fold_non_bmp` -> `sha256` of the UTF-8 encoding. Hashing raw
file bytes is what made 97 correct rows look stale on 2026-09-09.

## What changed under the previous handoff

1. **The checkout moved**: `Projects/the-platform-workspace/probata` ->
   `Projects/Propria/Probata/probata`. Absolute paths baked into scripts silently died
   with it. This is why the store *looked* empty when it was intact.
2. **The docs tree was relocated** into `docs/docs (do not manually edit)/` and then
   **reverted by the owner**. It is back at `docs/`.

### Fixes applied (owner-approved)

- `.docstore/.env` — `SURREAL_URL` is now `surrealkv://{REPO_ROOT}/.docstore/kv`.
- `scripts/docstore/flow_docs.py` — expands `{REPO_ROOT}` to the real checkout root.
- `scripts/docstore/mirror_docs.py` — `REPO_ROOT` is derived from `__file__`, not a
  hard-coded absolute path. **This alone was fatal**: it made the plan report
  "503/503 missing sources", which reads as data loss and is not.

## The mirror failure, in full (do not repeat it)

`--apply` moved all 496 files, then crashed in the frontmatter pass.

**Cause.** Windows is case-insensitive. Mapping row 20 moves `docs/INDEX.md` ->
`docs/blueprint/INDEX.md`, but row 195's *source* is `docs/blueprint/index.md` — the
same path on this filesystem. `git mv` refused, correctly. A fallback that moved the
file anyway **overwrote** `blueprint/index.md` ("# Platform Blueprint") with
`INDEX.md`'s text; row 195 then carried the wrong content to `docs/reference/index.md`.

**This is exactly one row pair.** A sweep of the mapping finds **1** destination that
collides case-insensitively with another row's source, and **0** duplicate
destinations. It is not a systemic mapping problem.

**Now guarded.** `git_mv` refuses to move onto an existing destination and raises,
restoring the abort-before-damage behaviour. The fallback itself is still needed:
`docs/INFRASTRUCTURE.md` is gitignored by name (`.gitignore:95`, credential-shaped
lines, tracked counterpart is `INFRASTRUCTURE.template.md`), so `git mv` cannot move
it and it must **never** be force-added.

**Recovery, and what it proved.** 24 of 27 edited files were restored losslessly from a
backup and byte-verified against the docstore; the remaining 3 (`DECISION_LOG.md`,
`COORDINATION.md`, `Codex Goal — Horizon Swift MVP.md`) were restored from the store's
`body`. `docs/INDEX.md` had a 175-char uncommitted edit that only the store knew about.
**The docstore was the recovery source of record** — the first time it has paid for
itself.

## UNRESOLVED

- **The mirror has not run.** The tree is pre-apply. The plan is green apart from the
  one collision.
- **The collision needs a ruling** before any re-run — see below.
- **94 files have normalised line endings** (LF where they were CRLF) as a side effect
  of the `git restore` used to roll back. Content is identical, git reports them
  unmodified, but the docstore's content-hash change detection *will* re-embed those 94
  on the next ingest. Harmless, costs one embed pass.
- **Nothing is committed.** The four file edits above are uncommitted, alongside the
  other session's staged work (`.review_hold/`, `.agents/blueprint/`). Stage by explicit
  path only.
- **14 non-markdown mapping rows** still excluded by the `**/*.md` matcher — unruled,
  carried from the previous handoff.
- **6 store rows are not files**: `handoff://verify-*` and `verify/ADR-VERIFY-*.md`,
  written by the docstore MCP tooling. They are not on disk and the mirror ignores them.

## Pending owner decisions

- **How to resolve the one collision.** Three options, in order of preference:
  1. **Order the moves** so a row whose source is another row's destination runs first
     (here: run row 195 before row 20). Smallest change, fixes the general class.
  2. **Repoint row 20's `mirror_path`** away from `blueprint/INDEX.md`. Note `--apply`
     regenerates `docs/INDEX.md` from the mapping anyway, so the old index is being
     archived, not kept.
  3. **Two-phase moves** via unique temp names. Most robust, largest change.
- **Whether to commit** the four fixes, and whether this session should do it given the
  shared working tree.

## Next steps, in order

1. Owner rules on the collision fix.
2. Re-run the plan; confirm 0 missing sources and dead-link delta <= 0.
3. Re-run `--apply`. The `git_mv` guard now aborts before damage rather than after.
4. Re-verify with the content checker; expect 0 real content differences.
5. Commit, by explicit path.

## Owner working-style contract

- **Get approval before making a change.** Propose, wait, then act. The one unapproved
  judgement call this session — a fallback that moved a file when git refused — is the
  single thing that caused damage.
- Verify before claiming; never report success from a proxy signal.
- Never hard-delete; quarantine. Byline every artifact.
- Structured, answer-first replies: bullets, labelled blocks, white space.
