# Engine recovery handoff — 2026-09-12

Owner: delegated engine SMS recovery lane. Changes are local; this document does not claim deployment or a live ingest result.

## Implemented

- Content signature registers one initial handler. DuckDB-supported signatures do not require a declared-format decoder lookup and do not advertise pre-failure decoder alternatives.
- Engine persists its default routing decision. `operator-handler-selection/v1` parser options requests an initial inspection hold using the existing authenticated handler-decision API.
- After a selected-unit failure, the recovery Activity appends a failed activity receipt and a distinct recovery recommendation. The workflow requires that durable failure receipt before exposing options.
- Operator may retry the selected unit or choose an actually registered compatible decoder after DuckDB failure. Three operator-directed recovery cycles are bounded; there is no silent fallback. Previous failed stage results remain in the durable workflow result.
- Decoder execution uses the detected signature for coverage while preserving the original canonical intake declaration in the persisted bundle. Arbitrary/hyphenated declarations remain invalid under the canonical raw FormatID contract; preserve external labels in source observations.
- Parser selection idempotency includes exact parser ID/version, permitting a distinct fallback selection without overwriting the original selection receipt.
- R2 source admission includes exactly `nexus/workbench/staging/<SHA-256>/<filename>` in addition to existing roots. Upload bridging must return a server-authored reference. No local-host relay is introduced.
- DuckDB resolves a retained R2/S3 object URI when present. A worker-local upload or repaired object with no verified PG-visible locator remains rejected, not silently replaced with original bytes.
- Stage registry comments now describe context fingerprints rather than ingest custody hashes.

## Schema coordination

The six handler tables are required. The detected-format CHECK includes every detector output. With root authorization, only `handler_recommendation_signature_key UNIQUE(content_signature_id)` was removed, permitting append-only recovery recommendations for one signature. Unique recommendation receipt and execution idempotency remain. The separate schema lane owns additive live reconciliation.

## Verification and limits

Full `go test ./...` and `go vet ./...` passed during this lane; re-run after integration. Focused Temporal test proves failed DuckDB -> logged-recovery Activity -> actor-selected decoder -> continuation, retaining one failed and one successful ExecuteParser result. This is mocked Temporal/unit proof, not live PostgreSQL/Temporal/n8n proof.

Current real template set is pinned CSV, NDJSON, SMS XML, ChatGPT JSON-array, and message-transcript SQL. There is no arbitrary SQL template or schema preset registry. Recovery does not yet return to repair assessment/apply a new repair; existing pre-parse repair gate remains. No dead repair/schema controls should be advertised.

Existing raw persistence still supports stored-byte envelopes; full D-149 locator-only convergence requires coordinated raw persistence/hash-reader work, not an isolated schema drop. R2 extraction reads shared object storage; live source immutability and normalization/preview completeness still require actual run proof after deployment. No source was ingested, deleted, promoted, or modified by this lane.
