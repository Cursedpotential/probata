# Docstore operational run repair receipt — 2026-09-13

Scope: Probata-hosted Propria Docstore worker, API, control MCP, and deployment
contract.

## Result

The read-only Docstore API was extended with a governed run interface:

- `POST /runs` registers an authenticated durable run ID.
- `GET /runs/current` and `GET /runs/{run_id}` return bounded status.
- `DELETE /runs/{run_id}` requests cancellation only for a process launched by the
  same API instance.
- `GET /pipeline` reports the live `ProbataDocStore@probata-docstore` identity from
  durable worker state.
- selected paths never become a partial CocoIndex source. They are exact verification
  targets while the worker reconciles the complete declared source.
- each run snapshots every managed Markdown path and normalized content hash before
  execution, rejects source changes during execution, and compares the complete
  managed projection with SurrealDB after indexing. Only an exact match can set
  `cdc_verified=true`.
- an explicit `full_reprocess=true` repair request invokes CocoIndex's supported
  full-reprocess mode when target drift exists despite unchanged tracking state. It
  is opt-in because it recomputes every document and may incur provider cost.
- run receipts and current status validate the CDC proof fields before accepting a
  true verification value.

The MCP capabilities now report indexing, write-run registration, live status, and
CDC attribution as implemented. Source-registry mutation remains governed by the
Propria monorepo manifest; the service does not edit that authority file.

First-class MCP operations are registered for pipeline identity; full and admitted
selected-source runs; current/exact/history status; cancellation; fresh attribution;
and graph schema, preview, query, and inline JSON, CSV node/edge, GraphML, or Mermaid
export. Graph queries are depth-one, relation-allowlisted, parameter-bound, and
bounded to 200 results per relation/direction. Arbitrary SurrealQL and mutations are
not exposed.

Every operational/graph request is fenced to `index_kind=docs`. Responses identify
`ProbataDocStore@probata-docstore`, the docs index kind, allowed documentation roots
and Markdown file class, and rejected source-code/configuration/test classes. The
separate codebase index is managed locally by CocoIndex Code (`ccc`); no stable
internal CocoIndex app/environment identity for it is declared in repository or
deployment configuration, so this receipt does not invent one or claim it is live.

## Verification

- Existing control suite before the final tool additions: 287 passed, 3 skipped.
- Focused final contracts: 51 MCP server tests, 35 worker/CLI tests, and 8 worker HTTP
  API tests passed.
- Python compilation passed for worker API, worker, run primitives, CDC verifier,
  MCP server, and receipt reader.
- Static source snapshot completed over 504 currently eligible Probata Markdown
  files. No indexing or store write was triggered by that snapshot.
- Pre-change Tailnet proof: `/health` returned `ok=true`; `/stats` returned 511
  documents, 11,761 chunks, 11,761 chunk edges, and a ready vector index. Its OpenAPI
  exposed only the historical read routes, confirming the operational job API was not
  deployed at the time of this receipt.

Deployment `u2qudf0q5yhk1xwmsa1qetxn` installed commit `154d395162348ca4184b15f5060a307ba70e89b4`.
Deployments `eh3avdgm97w5qrtapqapmv0v` and `sz7tlka1zhe1yxniu2v9i9y4` installed follow-up
commit `2d1e334ca69f5c52702d0825b0a701d82893210d`. Live OpenAPI then exposed all run,
attribution, graph-schema, and graph-query routes; pipeline identity verified true.
Fresh graph-schema proof counted 513 documents, 116 `links_to`, 1,146 `cites`, and 48
`supersedes` records.

The first ordinary run correctly failed closed: 488 declared documents, 508 managed
documents, zero missing, 20 unexpected, and 17 normalized-content hash mismatches.
Explicit full reprocess run `6fe6fd6e7f644ac7bf67df57ff546f3d` was then admitted
with the same 488-document stable source digest. Its terminal attribution is recorded
in the final section when available; a running receipt is not CDC proof.

The first uninterrupted `full_reprocess=true` proof was run
`1bcb3295187a4c22888ffeec81dd78ad`: it finished in 519 seconds but left the same
20 unexpected documents and 17 stale hashes. This proves transformation reprocessing
alone does not reconcile external Surreal target drift when CocoIndex's tracked
desired target already matches its recomputed desired target. The follow-up repair
therefore adds an explicit, full-source-only `tracking_rebuild` mode. It retains the
dedicated SQLite state and sidecars under the worker volume's `to_be_deleted`,
bootstraps a fresh declaration, retires only identities absent from the complete
source snapshot, and still requires the exact zero-drift attribution gate.

Tracking rebuild run `5d86d0419fdf423799e9546c69bad58e` then completed the
membership repair in 509 seconds: it retained the old tracking state, upserted the
complete 488-source declaration, retired the 20 unexpected projections, and reached
488 observed documents with no missing or unexpected paths. Its first verifier result
still reported 17 hash mismatches. End-to-end inspection proved every one of those 17
stored hashes matched the actual ingest transform. The verifier had replaced every
non-BMP character with U+FFFD while ingestion folds each such character to its Unicode
name. The verifier now mirrors the dependency-free ingest fold; all 17 previously
reported mismatches compare equal against the deployed commit's exact source bytes.
The run remains recorded as degraded because receipts are immutable evidence; a fresh
post-deploy run must produce the corrected terminal proof.

## User-facing workflow reasoning

The thinking-model router characterized this as a high-stakes, partly reversible
architecture and workflow repair: diagnose and decide under concurrent source drift.
It routed to branch thinking for competing execution paths and second-order reasoning
for the consequences of repair and retry. Those two methods have distinct jobs; no
additional reasoning model improved the decision.

The evaluated branches were:

1. Keep ordinary CocoIndex reconciliation only. This is the lowest-complexity path but
   scored 2/5 because it cannot correct target/tracking divergence and leaves users in
   a repeated failed-run dead end.
2. Run CocoIndex full reprocess only. This preserves the framework's normal lifecycle
   but scored 3/5 after live evidence showed it recomputes without repairing externally
   drifted target rows.
3. Use a bounded tracking rebuild plus exact attribution. This scored 5/5 because it is
   full-source-only, retains prior state in `to_be_deleted`, removes only paths proven
   absent from the complete snapshot, and must pass a zero-drift gate. The owner's
   existing requirement for a real operational repair selects this branch.

The workflow surface follows this path: discover a named MCP tool; invoke it directly;
read an identified queued/running/terminal state; cancel the exact process where the
worker supports it; retry ordinary failures; request explicit full reprocess/tracking
rebuild only for attribution drift; then read the result, attribution, document, graph,
or bounded export. Status returns `valid_next_actions`, evidence fields, an error type,
and `override_supported=false`, so an unsupported override cannot be inferred.

The consequence chain and guards are:

- A rebuild immediately restores source membership (high probability); on the next
  cycle, retained evidence and the exact source digest make the repair auditable; at
  scale, the 1,000-record retirement ceiling and full-source admission prevent a partial
  selection from becoming a mass retirement.
- Direct run registration creates operator visibility (high probability); repeated use
  could create concurrent-job pressure, so the API admits one live child process and
  reports 409 rather than queueing invisible work.
- Selected verification improves convenience (high probability); users could mistake it
  for partial ingestion, so every selected run still reconciles the full declaration and
  reports that selected paths are verification targets.
- Cross-store repair packets improve diagnosis (medium probability); an automated loop
  could cross ownership or ingest boundaries, so Docstore delegates to the canonical
  Search plugin, exposes per-store state, and never silently edits sources.
- Documentation and code retrieval become easy to combine (high probability); this
  raises the risk of identity conflation, so every Docstore run/status/attribution/graph
  response identifies `index_kind=docs` and rejects code/config/test classes. The CCC
  index retains its independent root/settings/index identity.

Final pre-deploy verification passed 292 control-plugin tests with 3 live-only
skips, including the first-class MCP catalog, execution/status/cancellation fences,
selected/full admission, graph previews/exports, source registration, revision-exact
writes, and worker attribution safety. Python compilation passed for the worker API,
worker, run primitives, verifier, graph module, MCP server, and CLI. The canonical
installed MCP path discovers 40 tools, including all four thin Search adapters. A
live invocation against Search commit `d50dbf57a687a2f2438b21e5773bbe8e0038e555`
returned the `propria-search-reconcile/v1` contract with explicit state for all eight
stores. The selected Docstore adapter was unavailable because
`PROPRIA_DOCSTORE_ADAPTER` is not configured in that Search branch; its result
reported requested=true, available=false, queried=false, skipped=unavailable, and
the exact configuration/retry next action. No ad-hoc search or silent fallback ran.

Deployment `vhp260pdcx7udkw60gi2e1wq` installed commit
`b97562ea6833b4ceeeb207504530096b8e600d8b`. Its ordinary startup reconciliation,
run `2e1193bc5013444bbbc3f4990e4302b4`, finished in 27 seconds with a stable source
digest, 488 expected documents, 488 observed documents, and zero missing,
unexpected, or hash-mismatched paths. The durable receipt and a separate fresh
`/attribution` call both returned `cdc_verified=true`.

The exact user-configured Codex stdio command then discovered 40 tools and invoked
pipeline identity, current run, fresh attribution, graph schema, graph preview, and
CSV node/edge export through MCP. Identity verified live; the same terminal run and
zero-drift attribution were returned. The catalog exposed full/selected run start,
current/get/list, cancellation, attribution, graph, DuckDB compact presentation, and
all four reconciliation adapter tools. A `codebase` index-kind invocation was rejected
by the MCP schema, and cancellation of a non-active run was rejected by the live API.
A final operational handoff was written through `docstore_handoff_write` and read back
as active `document:i5ygmg5kucat5wx0pmn3`; the write explicitly did not trigger
indexing.

## Deployment boundary

The current worker image copies only Probata `docs/` plus `scripts/docstore/`.
Production multi-root ingestion stays disabled until a Propria-root build context or
an immutable complete source projection contains every required registry root. A
successful source build or Coolify deployment is not live proof until the Tailnet URL
serves the new routes, the worker identity is verified, and one bounded run completes
with exact CDC attribution.
