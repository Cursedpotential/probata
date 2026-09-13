# Verification receipt — 2026-09-12

## Superseding semantic-search and activation check — 2026-09-12

The earlier baseline below is retained as history. The current package is **0.4.0**
and its catalog contains **19 tools**. `coco_docstore_search` is the primary
agent-facing path: the existing Docstore API embeds the query through NVIDIA NIM,
searches CocoIndex-maintained chunk embeddings in the dedicated SurrealDB service
(`probata` / `docs`) with BM25+KNN reciprocal-rank fusion, and uses bounded in-memory
DuckDB compact-column presentation by default. No Weaviate or second vector store was
added. `docstore_search` remains as a compatibility/full-result name.

The canonical `propria-search` skill now routes Propria documentation questions to Docstore,
code questions to the separate project-local CCC application, and mixed questions to
both with distinct citations/freshness. It does not merge their application identity,
database, tracking state, lock, credentials or write path.

Observed checks for this increment:

| Check | Result |
|---|---|
| Protocol/unit suite | **233 passed, 2 skipped in 8.74 seconds** with package root on `PYTHONPATH` |
| Skill validation | `propria-search` passed the skill validator; canonical plugin validation passed |
| Live API/store | Health `ok=true`; 500 documents, 11,688 chunks and 11,688 `chunk_of` edges |
| Surreal vector index | Ready, zero pending at the instant queried |
| Live semantic search | Passed through `coco_docstore_search`; returned `kw+vec` results and explicit backend identity |
| Windows compact output | Fixed JSON console output to escape non-ASCII instead of raising `UnicodeEncodeError` |
| Claude plugin registration | `propria-docstore@probata` 0.6.1 is installed and enabled at user scope. `docstore@probata` 0.4.0 and `probata-docstore@probata` 0.5.1 are disabled; their caches were retained. |
| Claude MCP trust | Both new plugin connections are pending the one-time interactive project approval; current sessions must be restarted after approval |

The database binding is the intended dedicated service, but the current 500-document
corpus is mostly historical Probata documentation and contains stale/noisy records.
The owner has clarified that Probata hosts a universal Propria documentation plane.
Expanding project registration and controlled CocoIndex CDC remains separate work; this
read-path change did not launch a corpus run or claim universal source freshness.

## Delivered source

All changes for this task are under `plugins/docstore/control/`: FastMCP adapter, terminal entrypoint, PowerShell launcher, Claude plugin/connection manifests, Codex configuration example, shared skill/references, locked dependencies and tests. Existing `plugins/docstore/claude`, existing worker, app identity, databases, codebase CCC, and host settings were not modified. No commit/push or deployment performed.

## Observed checks

| Check | Result |
|---|---|
| uv dependency resolution | FastMCP 3.2.4; package-local E-drive environment and source lockfile generated (not yet Git committed) |
| Protocol/unit suite | **43 passed in 5.13 seconds**; intercepted HTTP and synthetic files, not live DB tests |
| Stdio MCP startup/discovery | Passed: eight tools, four resources, two resource templates, one prompt |
| Skill validator | Passed |
| Source secret scan | Passed for the Git-visible plugin source; an initial directory-wide scan also traversed third-party .venv files and reported 31 findings there, so it was not used as the source-package result |
| Native SurrealDB MCP discovery | Passed at `https://surreal-docs.tilapia-skilift.ts.net/mcp`: 14 tools |
| Anonymous native document read | Rejected with NotAllowed, as expected |
| Authenticated native document read | Passed: `select`, target document, fields id, limit 1; returned `document:docs_adr_0001_fresh_build_from_skeleton_md` |
| Document API health | Failed from this host for the declared HTTPS API and prior direct port 8473 probe |
| Viewer UI rendering | Not run; connection-guide tool/resource tested, not graphical login/rendering |
| Index execution | Not run; not implemented as a tool because the current worker lacks a safe job interface |
| Revision-bound selected plan | Passed locally and with a read-only live rejection probe; execution/bootstrap remain unavailable |

The authenticated read used the existing dedicated credential file in a transient process environment. Credentials were not changed, printed, placed in command arguments, persisted in this package, or installed into a host configuration. Native permission isolation beyond the successful scoped read is not established by this test. Header scoping alone is not an authorization boundary.

Native MCP client teardown emitted `Session termination failed: 202` after successful requests. This is an observed server/client close-status compatibility warning, not an indexing job or database-write failure. It remains to be checked before activation; do not suppress it to imply a cleaner proof.

## Tested invariants

- Tool discovery does not import the CocoIndex worker, index sources, write control state or contact the documentation API.
- No automatic update checks on stdio startup; no local embedding/model packages added.
- Search types/status/limits are schema validated; remote costs are disclosed.
- API errors, redirects, malformed JSON and oversized responses fail explicitly without alternate-store fallback.
- Index plans reject traversal, oversized/count-exceeding inputs, and Windows cloud placeholders; source bytes remain unchanged.
- Config rejects relative/shared/nested tracking paths and non-Docstore instance names; ambient COCOINDEX_DB is ignored; credential repr is hidden.
- Plugin and CLI entrypoints are real, with shared tooling implementations rather than separate command behavior.

## Remaining work before calling the entire system complete

1. Restore/verify the existing document API route and prove search/get/graph against it. Do not create an unrelated replacement service silently.
2. Verify the native credential's actual namespace/database permissions; preserve the independent memory/evidence/code indexing systems.
3. Add safe CocoIndex job control to the existing worker: full-source manifest ownership, nondeleting scoped reconciliation, shared admission/locking, bounded execution/logs, durable status and cancellation. Preserve current App/environment tracking identity.
4. Verify Surrealist/Studio connection and graph rendering on the installed version.
5. Activate the reviewed replacement in the chosen host and federate through the real ContextForge deployment. Neither activation nor federation has been performed.

This receipt is a local implementation/verification artifact. It has **not** been registered or indexed into the authoritative documentation store.
