# Selected CDC proof — 2026-09-12

Status: **synthetic SDK proof only; no Docstore pipeline integration or deployment**.
Canonical finding: `note:docstore_selected_components_proof_20260912` in Docstore.

## What was tested

Installed CocoIndex 1.0.21, its native SQLite connector with vector extension
disabled, explicit isolated environment/app/tracking paths, three synthetic
documents. No corpus access, model calls, network database, source files or
filesystem deletions. Each phase runs in a separate uv-managed process.

The retained proof script is `scripts/docstore/proofs/selected_components_proof.py`.
All proof directories are under `E:/AI_Workspace/.intake-dev/temp/`.

| Directory suffix | Experiment | Observed result |
| --- | --- | --- |
| docstore-selected-proof-20260912-01 | Static seed then incremental-only catch-up | Seed had three rows; selected run left target empty. Failed. |
| docstore-selected-proof-20260912-02 | Fresh incremental-only live component in catch-up | Empty target. Failed. |
| docstore-selected-proof-20260912-03 | Complete bootstrap, live readiness, then selected updates | Bootstrap, alpha, beta, failure retention and retry passed. |
| docstore-selected-proof-20260912-04 | Static seed followed by complete live-parent bootstrap | Three rows retained; not a scan-free migration. |
| docstore-selected-proof-20260912-05 | Instrumented fresh bootstrap and four later processes | Bootstrap ran once only; later processing touched only selected key. |
| docstore-selected-proof-20260912-06 | Same sequence with document and chunk tables | Stale selected-document chunk retired; siblings preserved; failure retained prior documents and chunks; retry passed. |

## Successful proof sequence

1. Read committed bootstrap marker inside `process_live`.
2. If absent, run a **complete synthetic** `process()` via `update_full()`.
3. Await `mark_ready()` with **App.update(live=True)**.
4. Persist bootstrap marker, then issue per-key `operator.update` and await readiness.
5. Let the finite live component return; check update statistics and independent
   read-only SQLite target rows before claiming success.

The initial failure was not proven to have a specific Rust GC cause. Do not
describe component-path equality alone as ownership proof. A fresh incremental-only
baseline failed too. The failed primitive remains explicitly experimental and is
not imported by the real flow.

## Error and statistics traps

A failed transform after live readiness logged an error but did **not** raise
from `UpdateHandle.result()`. Statistics reported `num_errors=1`; this must reject
success. A 30-second timeout is not accepted as an expected transform failure.

`num_deletes=0` was observed even when an obsolete synthetic chunk row disappeared.
It is therefore **not** a count/proof of unchanged target rows. Independent exact
target readback is necessary. Neither successful execution nor aggregate health
sets `cdc_verified=true`.

## Remaining gates

- Keep the existing static production flow unchanged until its current app,
  component paths, source membership, writer exclusivity and target ownership
  are verified. A migration bootstrap is a complete scan, not a selected run.
- Production selected execution must refuse missing/mismatched bootstrap instead
  of silently turning a selected request into a full scan.
- Add restart/cancellation and concurrent-writer proof, then bind execution to
  revision/source fingerprints and exact chunk/vector readback.
- Surreal target and remote provider behavior still require a separately scoped
  real-service proof. SQLite evidence does not establish Surreal deployment.
- No worker, scheduler or control tool currently exposes this experimental path.

## Guarded primitive follow-up

`CommittedSelectedComponentUpdates` now refuses missing or differently typed/valued
bootstrap markers before readiness/updates and never calls full reconciliation or
writes/upgrades markers. It snapshots selected membership and admits at most 20
unique keys before processing. It still requires caller-side canonical path/revision
validation, immutable values, identity binding and `live=True` execution.

On the populated `-06` fixture, a matching marker reused the existing live topology;
missing and mismatched markers each produced one error, zero transforms and exact
unchanged document/chunk tables. A matching retry then succeeded. These tests do
not establish all-or-nothing semantics for a multi-item selection; previously
completed items may remain committed when a later item fails.

The marker contract was subsequently tightened from the synthetic integer to a
lowercase SHA-256 digest of seven non-secret identity fields: app, environment,
component topology, source identity, tracking-state ownership, target ownership
and processing profile.
Every field is required and bounded. The `-10` fresh sequence passed bootstrap,
alpha-only and beta-only updates, missing/mismatched digest refusal, transform
failure retention and retry. Each later phase reported zero bootstrap calls and
only the selected key where a transform was admitted. `-08` is retained because
its harness expected beta to have been updated before that phase; exact output
instead showed the rejection preserved the actual alpha-only state. This was a
test expectation failure, not evidence of a target mutation.

Control regression suite after the final read-only admission/result-cleaning work:
**209 passed, 2 skipped** on 2026-09-12. The skips are explicitly gated live
revision tests, not synthetic CDC proof failures. The final test temporary files
remain at `E:/AI_Workspace/.intake-dev/temp/docstore-selected-full-20260912-04`.

## Interrupted-process proof

`scripts/docstore/proofs/interrupted_selected_proof.py` created a fresh `-07`
three-document/chunk baseline, launched only its own selected-update child, waited
for a synthetic pre-commit gate after target declarations, then terminated that
child. Independent SQLite readback matched the complete prior baseline. A fresh
selected retry converged correctly, retiring the stale alpha chunk and preserving
all siblings. The child attempt is recorded as interrupted, not successful.

Receipt retained at
`E:/AI_Workspace/.intake-dev/temp/docstore-selected-proof-20260912-07/interruption-receipt.json`.
This establishes the tested pre-commit interruption behavior only, not rollback of
an already committed write or whole-batch atomicity. Post-commit receipt loss must
remain indeterminate until independently reconciled. `cdc_verified` remains false.

The identity-bound interruption proof was repeated successfully in `-09`.

The pure identity contract was split into `scripts/docstore/selected_identity.py`
so control planning can share it without importing CocoIndex or `flow_docs.py`.
Fresh `-11` bootstrap and alpha-only update passed after that split. The control
plugin now exposes a read-only revision-bound `docstore_selected_update_plan`; it
reports candidate identity only, bootstrap unobserved and execution unavailable.
No execution tool exposes the experimental updater.

References: [live component operators](https://cocoindex.io/docs/advanced_topics/live_component/)
and installed `cocoindex/connectors/oci_object_storage/_source.py` bootstrap ordering.

To reproduce on a **new** E: directory, use the project uv environment and phases
`bootstrap --expect-bootstrap 1 --with-chunks`, then `boot-first`, `boot-second`,
`boot-failure`, `boot-retry`, each with `--with-chunks`. Never reuse a prior proof
directory for bootstrap; the script refuses an existing target.
