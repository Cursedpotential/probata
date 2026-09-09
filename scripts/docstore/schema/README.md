# Local document store schema (D-155, D-156)

> _Byline: Claude Code · Fable 5.1 · 2026-09-09_

Bound copies of the docstore kit schema, applied to the local SurrealDB 3.2.0 store at `127.0.0.1:8462` (`probata`/`docs`) on 2026-09-09. Order is numeric. `EMBED_DIM` is fixed at 2048 (`nvidia/nemotron-3-embed-1b`). `010` carries the ruled seven `doc_type` values, five `status` values, and the `domains` tag field; `090` is the domain API the plugin skills call through the native MCP `run` tool.

Apply by POSTing each whole file to `/sql` with basic auth and `surreal-ns`/`surreal-db` headers (the `surreal sql` shell reads stdin line by line and breaks multi-line statements; `surreal import` needs `OPTION IMPORT` and disables events). Verification receipt: `docs/reviews/2026-09-09-docstore-api-verification.md`.
