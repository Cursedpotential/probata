---
tags: [docstore, lint, normalization, projection]
---

# Docstore normalization, validation and linting

> _Byline: Claude Code · Sonnet 5 · 2026-09-14_

Owner order 2026-09-14: "we need some kind of a normalization script, a validation
script, and a linter, somewhere in the mix, in some part of the process." This
document is the map of where those three landed.

| Role | Tool | What it does |
|---|---|---|
| Normalization | `scripts/docstore/build_projection.py` | Builds the multi-root projection the worker reads from `/exchange/sources`: decodes every source file exactly as `flow_docs.py` will, folds non-BMP characters, drops empty files, drops byte-identical duplicates, and re-encodes everything as clean UTF-8. |
| Linting | `scripts/docstore/docs_lint.py` | Standalone checker over the same registry roots (or explicit `--paths`), with one code per failure mode. Runs on the desktop and inside the worker's pre-run snapshot. |
| Validation | `scripts/docstore/cdc_verify.py` (existing) + `docs_lint.py`'s error-severity codes + the worker's lint stage | `cdc_verify.verify_projection()` proves the store matches the declared source after a run; `docs_lint.py` proves the source itself is well-formed before a run; the lint stage records both in the run receipt so a degraded/failed run is self-explaining. |

None of these three import CocoIndex. `build_projection.py` and `docs_lint.py` both
run on the desktop (no worker, no server) and inside the worker container without
a CocoIndex environment configured.

## 1. `build_projection.py` — normalization

```
python3 scripts/docstore/build_projection.py --registry <path> \
    [--out-dir <dir>] [--container-root /exchange/sources] [--push]
```

For every ACTIVE, non-`excluded` root in the registry (all six Propria roots, not
just the one currently flagged `current-full-source` — the projection is the
complete multi-root corpus the worker will eventually read):

1. Walk the root with the registry's `included_patterns` / `excluded_patterns`
   (merged with the registry's top-level `blocked_patterns`, see §4), using the
   same `**`-aware glob semantics as the flow (`cdc_verify._glob_re`).
2. Decode each `*.md` file's raw bytes with `cdc_verify.decode_markdown` — strict
   UTF-8 first, Windows-1252 fallback, no newline translation (CRLF survives
   verbatim, exactly like `FileLike.read()` in `flow_docs.py`).
3. Fold non-BMP characters with `cdc_verify._fold_non_bmp` (mirrors
   `flow_docs.fold_non_bmp`).
4. Omit the file if it is empty after that fold + strip (the flow silently skips
   empty files; a copy that is not skipped would be a permanent phantom document).
5. Omit the file if its folded content is byte-identical (sha256) to a file
   already kept anywhere in the projection — `document.content_hash` is UNIQUE
   across the whole store, so this dedup is global, not per-root. Every omission
   is recorded in `docstore-projection-duplicates.json` beside the container
   registry copy, with `{skipped, kept, sha256_folded}`.
6. Otherwise, write the folded text — re-encoded as UTF-8 — at the file's path
   relative to the registry's `monorepo_root`, so the container registry copy
   (same JSON, `monorepo_root` replaced by `--container-root`) resolves every
   project's `source_root` to exactly where this script put it.

Default is a **dry run**: it builds the projection under `--out-dir` (a fresh
temp directory if omitted) and prints a per-root table (files / kept /
omitted-empty / omitted-dup). `--push` additionally `scp`s the built projection
to the worker host (`root@100.91.190.107`, key `~/.ssh/ovh`) and swaps it in —
archive to `/data/probata/exchange/docstore-worker/projection-<ts>.tgz`, unpack
to `sources.new`, move the current `sources` to `sources.prev-<ts>`, move
`sources.new` to `sources`. `--push` is never invoked automatically by this
script or by any other tool in this repo.

On Windows Git-Bash, run a `--push` invocation with `MSYS_NO_PATHCONV=1` so the
`/unix/paths` in the `ssh`/`scp` commands are not mangled into Windows paths.

## 2. `docs_lint.py` — linting

```
python3 scripts/docstore/docs_lint.py --registry <path> [--json] [--strict] \
    [--fix-encoding] [--max-warn-bytes N] [--max-error-bytes N]
python3 scripts/docstore/docs_lint.py --paths file1.md file2.md ... [--json] [--strict]
```

Every check reuses the flow's own decode/fold/hash/glob logic (via `cdc_verify.py`),
so a finding here predicts a flow outcome exactly: an `ENC001` file decodes the
same way the flow will decode it, a `DUP001` pair collides on the same
`content_hash`, a `PATH001` file gets the same digest slug `flow_docs.slug()`
would produce.

| Code | Severity | Meaning |
|---|---|---|
| `ENC001` | error | File is not valid UTF-8 (decodes via the cp1252 fallback). |
| `EMPTY001` | error | Empty after decode + fold + strip — the flow silently **skips** it. |
| `DUP001` | error | Byte-identical content (post decode+fold, sha256) at more than one path. |
| `PATH001` | error | The record-id slug for this `source_path` would exceed 120 chars (the digest-suffixed slug is reported). |
| `BLOCK001` | error | Path matches a registry `blocked_patterns` entry. Defense-in-depth — see §4. |
| `TAGS001` | warning | No tags: neither front-matter `tags:` nor `<!-- tags: ... -->`. |
| `BYLINE001` | warning | No `Byline:` marker found in the body. |
| `NBMP001` | warning | A non-BMP character in the path or the body. |
| `JUNK001` | warning | Path passes through a memory/junk folder (`.remember`, `node_modules`, …). |
| `DATAURI001` | warning | A `data:...;base64,` payload in the body. |
| `SIZE001` | **dual** | `>= --max-warn-bytes` (default 1 MiB) is a warning; `>= --max-error-bytes` (default 4 MiB) is an error. Message carries the raw byte count and an estimated chunk count at `flow_docs.py`'s chunk size (`DOCSTORE_CHUNK_SIZE`, default 1200). |

`--strict` promotes every warning to error severity **for the exit-code decision
only** — findings keep their inherent severity in the output either way. Exit
code is 1 if any error-severity finding exists (or, under `--strict`, any
warning). `--fix-encoding` is the only thing in this module that writes
anything, and only when passed explicitly: it rewrites a non-UTF-8 file to UTF-8
in place (no other transformation — newline bytes are untouched, same as
`decode_markdown`).

`--registry` mode always includes every active, non-excluded registry root
(equivalent to `DOCSTORE_MULTI_ROOT_ENABLED=1`), independent of which single root
the live flow currently treats as `current-full-source` — the point of the CLI
is "check the whole declared registry". The worker's own lint stage
(`lint_summary_from_env()`, §3) instead mirrors that run's actual
`DOCSTORE_MULTI_ROOT_ENABLED` setting, because it must lint what will really be
ingested this run. Both are correct for what they are used for.

### `BLOCK001` is defense-in-depth, not the primary mechanism

`source_registry.py`'s `blocked_patterns` (§4) is merged into every registry
root's `excluded_patterns` at load time, so a registry-driven lint run never
even sees a blocked file — it is filtered out of `iter_registry_files()` before
`lint_files()` runs, and `BLOCK001` will not fire. `BLOCK001` exists for
`--paths` mode (which bypasses per-root `excluded_patterns` entirely, since each
path is its own one-file ad-hoc root) and to catch a future bug in that merge.

## 3. The worker's lint stage

`worker_sync.py` calls `docs_lint.lint_summary_from_env()` right after
`snapshot_sources()` and before the `ingest` stage, and stores the result under
`summary['lint']` — which flows into every receipt (`write_receipt`) for the
rest of the run, including the very first one written before `flow_docs.py`
even starts. The durable current-status file (`write_current_status`) carries
the same `lint` block but with its `findings`/`largest_files` trimmed further
(20 / 5) by `_status_payload()` — see the size note below.

```json
"lint": {
  "files_scanned": 1118,
  "errors": 48,
  "warnings": 1749,
  "findings": [ {"code": "...", "severity": "...", "path": "...", "message": "..."}, ... ],
  "findings_truncated": false,
  "largest_files": [ {"path": "...", "bytes": 123456, "estimated_chunks": 103}, ... ],
  "chunk_size_bytes": 1200
}
```

**Lint findings never abort the run.** The flow already skips empty files and
fails closed on hash collisions on its own; the lint stage exists so a
degraded/failed run's receipt can explain *why* (an `ENC001`/`DUP001` the flow's
own guards then hit) without a second pass over the source tree.

`lint_summary_from_env()`'s own `findings` list is capped at 200 entries
(`findings_truncated` says whether more exist) and `largest_files` at the 20
largest files by raw byte size — that shape goes into every **receipt** file
(`write_receipt`, one JSON file per sequence step, no size limit). Measured
against the live 6-root registry (2026-09-14), that 200-finding lint payload
alone serialises to ~38 KB. `write_current_status()` (the durable
`latest-run.json` the API probes) enforces a hard 64 KiB ceiling on the *whole*
status payload, and a busy summary (ingest log path, health stats,
`cdc_attribution` samples) stacked on top of an uncapped lint block could push
it over that ceiling and make `write_current_status()` raise from inside
`_sync()`'s `finally` block — replacing the real sync outcome with a cryptic
size error instead of reporting it. `worker_sync._status_payload()` guards
against this: it trims the *live status*'s copy of `lint` to 20 findings and 5
largest-files (~4.6 KB measured) while the append-only receipt keeps the full
200/20. Both copies come from the same `lint_summary_from_env()` call — nothing
is computed twice.

## 4. `blocked_patterns` — one blocklist, every root

Owner directive 2026-09-14 ("institute a pattern that blocks certain paths"): the
registry (`Propria/docs/docstore-source-registry.json`) carries a top-level
`blocked_patterns` array. `source_registry.load_sources()` merges it into
**every** root's `excluded_patterns` at load time, so the flow, `cdc_verify.py`,
`build_projection.py` and `docs_lint.py` all block the same paths from one list,
in addition to whatever a project's own `excluded_patterns` adds.

The key is optional and backward compatible: absent, it contributes nothing
(`()`). Present but malformed (not a bounded list of non-empty strings) makes
`load_sources()` raise — it fails closed rather than silently under-blocking.

Current seed list: `**/node_modules/**`, `**/dist/**`, `**/to_be_deleted/**`,
`**/.claude/**`, `**/.memsearch/**`, `**/.remember/**`, `**/.cnf/**`,
`**/.codex/**`, `**/.agents/**`, `**/.venv/**`, `**/.pytest_cache/**`,
`**/vendor/**`, `**/_stale/**`, `**/_v1-superseded/**`, `**/runtime-codex/**`,
`**/go-mod/**`, `**/cache/**`, `**/_intake/**`, `**/samples/**`,
`**/exports/**`, `**/COMPACT-SUMMARY-*.md`.

`source_registry.load_blocked_patterns(registry_path)` reads just this array
(without a full `load_sources()` call) for callers that only need it, such as
`docs_lint.py`'s `BLOCK001` check and the worker's `lint_summary_from_env()`.

## 5. Commands

```bash
# Lint the whole declared registry (all six roots), human table:
python3 scripts/docstore/docs_lint.py --registry "E:/AI_Workspace/Projects/Propria/docs/docstore-source-registry.json"

# Same, machine-readable:
python3 scripts/docstore/docs_lint.py --registry "E:/AI_Workspace/Projects/Propria/docs/docstore-source-registry.json" --json

# Fix a specific file's encoding in place:
python3 scripts/docstore/docs_lint.py --paths path/to/file.md --fix-encoding

# Build the projection (dry run, prints per-root counts):
python3 scripts/docstore/build_projection.py --registry "E:/AI_Workspace/Projects/Propria/docs/docstore-source-registry.json" --out-dir /tmp/projection

# Push it to the worker host (never automatic):
MSYS_NO_PATHCONV=1 python3 scripts/docstore/build_projection.py \
    --registry "E:/AI_Workspace/Projects/Propria/docs/docstore-source-registry.json" --push

# Run the test suite:
python3 -m pytest scripts/docstore/tests -q
```
