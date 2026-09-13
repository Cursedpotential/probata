# Compact result adapter receipt

Derived from the existing `scripts/docstore/sq.py` normalization plus DuckDB rendering pattern. The original helper was not changed; its temporary-file creation/removal, embedded-store fallback and arbitrary SQL path were not copied.

Added `compact.py`, `docstore_compact` (search/flags/graph/document), and CLI `--compact` before a command. Catalog now exposes 12 tools. `uv.lock` pins DuckDB 1.5.5 in the existing E-drive environment.

Rendering uses bound JSON Pointer projections and JSON rows in a short-lived in-memory DuckDB connection, one thread, 64 MB buffer limit, no spill directory, external access or automatic extension downloads. The buffer limit is not a process RSS ceiling. Input is capped at 2 MiB and tabular schemas at 128 columns. All source rows and order are preserved; duplicates are not silently removed. Body/content/text beyond 600 characters becomes a labeled excerpt. Embedding/vector arrays become dimension labels. Every such omission has a path and original size; other numeric lists are preserved.

Diagnostics, hashes, flags and approval fields are not abbreviated. The upstream response is not mutated; compact output must never be used for write verification or source hashing. Existing structured tools/resources remain compatible; the skill recommends compact retrieval first. CLI output is opt-in to avoid silently breaking scripts. Existing hosted APIs and the native Surreal MCP are not modified.

Validation: 103 local tests passed in 5.58 seconds after initial implementation, including real in-memory DuckDB execution, literal/escaped field keys, row order, preserved duplicate rows, flags, diagnostics, excerpts, size limits and catalog discovery. Synthetic large-body/vector fixture shrank to less than one quarter of its original JSON character size. This is not a measured model-token or production-corpus savings claim.

Shared cross-application requirements and approved revision lifecycle are in `../../../../../RESULT-PRESENTATION-CONTRACT.md`. Existing Case Bible/Intake surface rollout, host activation and document revision pipeline remain pending. No workers or background schedules started; no corpus writes, deletes, commits or deployments performed for this adapter.

Final regression run: **104 tests passed in 4.94 seconds**, including MCP compact-document retrieval through intercepted HTTP and verification that the full document tool still returns the complete body. No live hosted recall proof is claimed.

Documentation: https://duckdb.org/docs/lts/data/json/json_functions and https://duckdb.org/docs/current/operations_manual/securing_duckdb/overview. The installed DuckDB documentation-search skill was inspected but its remote-index download path was not used for this bounded implementation; official pages were consulted directly. MCP skill connector export was unavailable through the browser, so the existing validated FastMCP architecture was retained.
