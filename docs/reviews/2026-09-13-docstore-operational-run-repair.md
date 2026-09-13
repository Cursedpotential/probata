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

## Deployment boundary

The current worker image copies only Probata `docs/` plus `scripts/docstore/`.
Production multi-root ingestion stays disabled until a Propria-root build context or
an immutable complete source projection contains every required registry root. A
successful source build or Coolify deployment is not live proof until the Tailnet URL
serves the new routes, the worker identity is verified, and one bounded run completes
with exact CDC attribution.
