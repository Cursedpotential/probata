# Docstore operational run repair receipt — 2026-09-13

Scope: Probata-hosted Propria Docstore worker, API, control MCP, and deployment
contract. This receipt records source and test proof. It does not claim deployment.

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

## Verification

- Existing control suite plus new contract tests: 287 passed, 3 skipped.
- Worker HTTP API tests under the system FastAPI environment: 2 passed.
- Python compilation passed for worker API, worker, run primitives, CDC verifier,
  MCP server, and receipt reader.
- Static source snapshot completed over 504 currently eligible Probata Markdown
  files. No indexing or store write was triggered by that snapshot.
- Pre-change Tailnet proof: `/health` returned `ok=true`; `/stats` returned 511
  documents, 11,761 chunks, 11,761 chunk edges, and a ready vector index. Its OpenAPI
  exposed only the historical read routes, confirming the operational job API was not
  deployed at the time of this receipt.

## Deployment boundary

The current worker image copies only Probata `docs/` plus `scripts/docstore/`.
Production multi-root ingestion stays disabled until a Propria-root build context or
an immutable complete source projection contains every required registry root. A
successful source build or Coolify deployment is not live proof until the Tailnet URL
serves the new routes, the worker identity is verified, and one bounded run completes
with exact CDC attribution.
