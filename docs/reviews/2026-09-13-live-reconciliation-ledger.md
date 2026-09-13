# Live reconciliation ledger — 2026-09-13

Status: active integration checkpoint  
Branch: `codex/propria-reconcile-20260913`  
Repository: `E:\AI_Workspace\Projects\Propria\_worktrees\probata-integration-20260913`

This file persists the current owner corrections, recovered archived-task
contracts, implementation ownership, and verification boundary so that a
conversation compaction cannot erase the operating state.

## Product and index boundaries

- App 1 is Probata/Proffer: intake, extraction, repair, context preview,
  operator override, Temporal durability, and n8n visual composition.
- App 2 is the single combined Xplorer + Case Bible + Consignatio tool:
  permissioned ACP/file operations, agent HITL, vault organization and
  deduplication, review, and legal-data workflows.
- The two applications may share interaction principles and typed contracts.
  They remain separate runtimes and authority boundaries.
- The docs index is Docstore + CocoIndex + SurrealDB and excludes source code.
- The code index is Search + Smart Explore + CCC + tree-sitter + DuckDB and
  excludes documentation.
- Reconciliation may call either or both indexes and selected memory stores,
  but must label provenance and must never silently turn an inference into an
  owner decision.

## Recovered archived-task corrections

The following Codex tasks were read through the task API, not inferred from
their titles:

- `01a050b5-e03b-7950-9d9b-3a3ab66b14df`: DuckDB is the primary extraction
  route for extractable inputs; registered Go/Python decoders are a logged
  fallback. The old `StructuredELT` direct writer cannot bypass Proffer's raw
  envelope, generation, fingerprint, reconciliation, normalization, lineage,
  verification, and preview receipts. The first visible checkpoint is raw
  source verification, never evidence custody. Real source objects must move
  server-to-server from R2/B2 and must not hop through the user's workstation.
- `01a09620-155b-7b01-8ab3-da15cfd419a9`: recovered Intake/Xplorer surface
  history and repository-boundary mistakes. Any statement that split Xplorer
  from Case Bible/Consignatio is superseded by the current explicit owner
  correction above.
- `01a0960d-eb7a-7d91-a28b-338f88e2d5ae`: recovered the tool-runtime rename,
  deployment, and source-ownership lane for collision avoidance.
- `01a09659-4c99-7aa1-819b-fb0e19ba49a4`: recovered the Smart Explore
  availability and index/runtime repair lane.
- `01a09338-1c1a-7212-beda-5ebe94fb3099`: recovered the Consignatio repair-tool
  location correction, DuckDB lake-catalog use, immutable source and derived
  repair requirements, bounded streaming, and provider-neutral object identity.
- `01a08483-6953-7302-952d-5d9c4180f74e`: recovered the Probata research prompt
  reconciliation and the warning that exploratory extractions are diagnostic
  probes, not canonical schemas.

## Current implementation lanes

- Root integration owns the n8n checked-in preview exports, their contract
  tests, this reconciliation record, integration, Git repair, and final proof.
- Surface lane owns generic package/record/chunk read projection and the
  Probata Workbench operator surface.
- Temporal lane owns the bounded workflow/activity wiring required to produce
  durable context chunks before preview and preserve handler decisions.
- Search lane owns Smart Explore/CCC/tree-sitter/Docstore adapter and optional
  memory-store reconciliation behavior.

Agents share the filesystem. Each lane must commit only its owned paths and
must not revert or broadly stage another lane's work.

## Completion gates still open

- Persist generic non-messaging package, attempt, record, attachment, and chunk
  preview projections without creating evidence or custody.
- Expose compatible parser/extractor/template/options override, rerun, attempt
  comparison, exact chunk preview, approval against preview digest, retry,
  cancel, and durable receipt visibility.
- Prove n8n exports match the current opaque preview-handle API; checked-in
  inactive sanitized exports do not count as live activation proof.
- Prove Temporal schedules the atomic units and owns retry, wait, signal,
  checkpoint, cancellation, and package-scoped durability.
- Prove Docstore and code search are separate indexes, both index-management
  surfaces are user-callable, and selected memory stores fail visibly when
  unavailable.
- Reconcile every owned branch into the integration branch, run proportional
  unit/build checks and required live checks, push the repaired Probata branch,
  then repair the canonical checkout without discarding its preserved dirty
  history.
- After every project and module is reconciled and clean, create the authorized
  private umbrella snapshot with Git metadata, secrets, caches, and
  `to_be_deleted` material excluded.

## Preservation and safety

The original dirty Probata checkout has not been reset, cleaned, stashed, or
broad-staged. Its preservation bundle is at
`E:\AI_Workspace\Projects\Propria\to_be_deleted\probata-primary-preservation-20260913`.
No file is permanently deleted; material selected for removal is moved into a
project `to_be_deleted` directory for owner review.
