# Probata integration branch receipt — 2026-09-13

This receipt covers `codex/propria-reconcile-20260913`. The branch combines the
chunk-backed Proffer review gate, the generic package/record/chunk browser, the
canonical Search runtime relocation, and the current operator-surface
corrections. It does not claim a live deployment.

The consolidated current state, owner-directed workflow, complete gap list,
ordered implementation plan, acceptance gates, storage roles, and do-not-claim
boundary are recorded in
[`2026-09-13-proffer-current-state-plan-and-gap-ledger.md`](2026-09-13-proffer-current-state-plan-and-gap-ledger.md).
The binding target behavior is recorded in
[`2026-09-13-proffer-precommit-review-contract.md`](2026-09-13-proffer-precommit-review-contract.md).

The consolidated current state, owner-directed workflow, complete gap list,
ordered implementation plan, acceptance gates, storage roles, and do-not-claim
boundary are recorded in
[`2026-09-13-proffer-current-state-plan-and-gap-ledger.md`](2026-09-13-proffer-current-state-plan-and-gap-ledger.md).
The binding target behavior is recorded in
[`2026-09-13-proffer-precommit-review-contract.md`](2026-09-13-proffer-precommit-review-contract.md).

## Operator contract implemented in this integration

- Non-messaging review uses generic normalized records and exact source
  locators. An empty or unavailable message-only projection cannot block a
  valid generic record set.
- The browser shows retained source/package fields, attachments and hashes,
  exact normalized record payloads, exact sealed chunks, span coordinates,
  chunk hashes, generation/receipt identity, the current extraction attempt,
  and context receipts.
- New Temporal histories execute normalization verification, optional
  non-messaging chunking, then preview publication before the final operator
  hold. Viewing or approving this intake/context preview does not create
  evidence or custody state.
- A record or chunk can be flagged as a **potential promotion** candidate. The
  flag is a reversible annotation in the existing durable flag spine. Its
  governed metadata records preview handle, TEST/REAL mode, scope, target ID,
  exact attempt ID, reason, authenticated actor and timestamp. It has no
  evidence-wanted links and does not perform evidence admission, custody,
  database projection or promotion. The same flag is returned beside the
  stable record/chunk identity when the preview browser is reopened.
- The API rejects a stale attempt ID or a target outside the current bounded
  preview projection before it writes the annotation. Entity flags remain
  fail-closed because no entity projection exists yet.

## Binding gaps that remain visible

The current generic content browser reads normalized records and sealed chunks
that already exist in PostgreSQL. It therefore does **not** yet satisfy the
owner's stronger gate requiring proposed records, chunks, entities,
relationships, metadata, attachments, hashes, warnings and full lineage to be
reviewable before any PostgreSQL, Weaviate, SurrealDB or index write.

The authoritative engine still needs an immutable pre-write proposal model and
authenticated commands for parser/extractor/profile override, editable and
versioned templates/options, a new rerun attempt, complete attempt history,
side-by-side diff, exact-attempt approval, destination projection, destination
IDs, write receipts and index status. Current content selects the newest sealed
chunk generation for a source version instead of binding the query directly to
the attempt. Potential-promotion classification is preserved with its attempt
provenance, but downstream projection receipts do not yet include that flag.

n8n workflow/version/activation/execution/node identities remain absent from
the browser-safe projection. The UI reports those values as unavailable. No
live n8n or Temporal deployment was inferred from source code.

## Full-web smoke failure and correction

The first full `npm run smoke` run reported exactly four failures:

1. `Matter-bound Knowledge promotes and reviews one exact custody record`
2. `New Run submits staged SMS through Proffer and renders guided recovery`
3. `New Run submits fresh SMS through Proffer and renders guided recovery`
4. `Matter registry stays usable without issuing advanced evidence calls`

All four failed before application launch with `ENOENT` while creating a
Chromium profile under `modules/to_be_deleted`. They shared one pre-existing
fixture path bug and were not caused by the Proffer or Search runtime changes.
The fixture now resolves the repository-root `to_be_deleted`, creates it if
needed, and closes browser/server handles deterministically. The four tests
then passed, and the complete smoke suite passed **58/58**. Browser profiles are
left in the repository-root quarantine for owner-only deletion, consistent
with the repository safety contract.

The final integration rerun, after adding the complete Review-contract checks,
passed **60/60** smoke tests and rebuilt 2,081 frontend modules successfully.

## Proposal schema and bundle groundwork

The branch now includes a Go proposal package with the canonical fourteen-table
DuckDB schema, lifecycle validation, deterministic `proffer-table-json-v1`
logical digests, and separate logical-proposal and external-bundle digest
layers. The `proposal-bundle` command freezes logical manifests, creates a
closed-database bundle manifest, and verifies database/artifact tampering.

The Python API includes proposal-detail DTO groundwork and a configurable
`PROFFER_PROPOSAL_ROOT`, but the generic bundle discovery/validation adapter and
detail route are unfinished. No valid canonical v3 proposal exists, and the 69
actual workbook records have not yet been frozen, bundled, verified, or served.

## Proposal schema and bundle groundwork

The branch now includes a Go proposal package with the canonical fourteen-table
DuckDB schema, lifecycle validation, deterministic `proffer-table-json-v1`
logical digests, and separate logical-proposal and external-bundle digest
layers. The `proposal-bundle` command freezes logical manifests, creates a
closed-database bundle manifest, and verifies database/artifact tampering.

The Python API includes proposal-detail DTO groundwork and a configurable
`PROFFER_PROPOSAL_ROOT`, but the generic bundle discovery/validation adapter and
detail route are unfinished. No valid canonical v3 proposal exists, and the 69
actual workbook records have not yet been frozen, bundled, verified, or served.

## Canonical commit reconciliation

Canonical checkout commit `2a26edf` (`fix(docstore): register canonical Codex
plugin`) and this integration branch diverge after merge-base `0369db8`.
Integration already contained the exact `.no-skill-scan` boundary and newer
Docstore package/readme work, but the source marketplace file from `2a26edf`
was absent. Cherry-picking the old commit would downgrade the current
`propria-docstore` 0.6.2 manifest to `probata-docstore` 0.5.2, so this branch
reconciles its intent instead:

- restores `plugins/.agents/plugins/marketplace.json`;
- registers `propria-docstore` in the `propria` source marketplace;
- aligns package documentation and the plugin-local agent instruction with the
  current `propria-docstore@propria` identity;
- preserves the separately configured `probata-docstore` MCP server name as a
  runtime compatibility identity rather than treating it as the package name.

The canonical checkout must not be reset, cleaned, stashed or broadly staged.
After this branch is pushed, update `main` through a clean reconciliation
worktree with a merge commit whose parents include canonical `2a26edf` and the
integration tip. First compare the canonical dirty file hashes against the
integration tip and explicitly preserve any non-identical file. Files already
identical to the integration tip will naturally become clean after the merge;
unique canonical content must be committed on a separate preservation branch
or moved to Propria `to_be_deleted` only when it is truly a removal candidate.

## Validation boundary

Final targeted validation before commit and publication:

- frontend build plus complete smoke suite: **60/60 passed**;
- focused Proffer API mode, resource-catalog, and potential-promotion tests:
  **54 passed**;
- Go proposal and proposal-bundle package tests: **passed**;
- Go vet for proposal and proposal-bundle packages: **passed**;
- Git whitespace validation: **passed** (line-ending conversion warnings only).

The final validation commands and exact branch/remote commit are recorded in
the integration commit and push report. Tests here use local/static fixtures.
They prove contracts, types, builds, and browser flow behavior; they do not
prove live PostgreSQL, Weaviate, SurrealDB, n8n, Temporal or deployment state.
