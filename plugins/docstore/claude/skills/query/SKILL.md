---
name: query
description: "Inspect Probata SurrealDB stores with bounded SurrealQL and clean DuckDB output. Use for raw rows, counts, schema, index status, or verification without printing vectors or document bodies."
allowed-tools: "Bash Read"
---

# Query — one inspection format for every agent

> _Byline: Claude Code · Opus 5 · 2026-09-10 — owner order: "make sure the skill is updated so that everybody is able to run that same query format."_

Every ad-hoc look at a SurrealDB store goes through `scripts/docstore/sq.py`.
It runs the SurrealQL, normalises SDK objects (`RecordID` → `table:id`,
datetimes → `2026-09-10 11:03:38`, embeddings → `<vec 2048>`, bodies →
`<N chars>`), loads the rows into an in-memory DuckDB table `r`, and prints
DuckDB's typed, width-capped table. One-off scripts that print raw SDK
objects are not allowed: they flood context and hide the numbers.

## Run it (from the repo root)

Interpreter: `C:/Users/matts/.local/bin/python3.exe` (has `surrealdb[embedded]` and `duckdb`).

```bash
PY=C:/Users/matts/.local/bin/python3.exe
$PY scripts/docstore/sq.py "SELECT * FROM todo LIMIT 5;"
$PY scripts/docstore/sq.py "SELECT * FROM decision_log LIMIT 3; SELECT * FROM supersedes LIMIT 3;"
$PY scripts/docstore/sq.py "SELECT doc_type, status FROM document;" --sql "SELECT doc_type, status, count(*) n FROM r GROUP BY ALL ORDER BY n DESC"
$PY scripts/docstore/sq.py "INFO FOR INDEX chunk_embedding ON chunk;"        # cloud is the default target
```

## Options

| Flag | Meaning |
|---|---|
| `--target` | `docs` (**default** since 2026-09-10) = the cloud instance `surreal-docs`, creds from `~/.secrets/probata-docstore.env`. `local` = the retired embedded store `.docstore/kv`, kept as a backup (single process: stop other holders) |
| `--ns`, `--db` | default `probata`, `docs` |
| `--sql` | DuckDB SQL over the result table `r` (single-statement queries) |
| `--max-rows` | default 20 |
| `--width`, `--cell` | table width (160) and max characters per column (36). DuckDB hides middle columns when too wide; raise `--width` |
| `--show-hidden` | include embedding and body values (rarely right) |

## Rules

1. Retrieval still goes through the named `fn::` functions (`docs`, `todo`, `decisions` skills). Use `sq.py` to inspect, count, and verify.
2. Always bound the output: `LIMIT` in the query or `--max-rows`.
3. Read the numbers, not just "rows came back". A PASS on 0 rows is a failure.
4. Writes (`CREATE`, `UPDATE`, `DELETE`, `REBUILD INDEX`) through `sq.py` need owner approval first.
