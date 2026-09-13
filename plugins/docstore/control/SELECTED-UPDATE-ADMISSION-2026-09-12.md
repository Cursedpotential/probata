# Revision-bound selected-update admission — 2026-09-12

Status: **implemented and locally/live-read verified as a plan; execution unavailable**.
Canonical finding: `note:docstore_selected_update_admission_20260912`.

## Capability

`docstore_selected_update_plan` accepts 1–20 explicit entries containing a logical
document key, canonical repository-relative `docs/*.md` path, expected generation,
expected revision number and raw SHA-256. The matching terminal command is
`selected-update-plan REQUEST.json` with a 64 KiB request-file ceiling.

For each entry it:

- rejects `private/**`, any `to_be_deleted` segment, non-Markdown/noncanonical
  paths, placeholders, files larger than 1 MiB and a changed stat snapshot;
- calculates original-byte SHA-256 and the worker-equivalent
  `docstore-fold-non-bmp-v1` projection SHA-256;
- compares exact head path/generation/current revision/raw hash and immutable
  current-revision metadata through one reused native Docstore session;
- rejects duplicate logical keys, source paths and colliding selected-set worker
  document IDs before source reads;
- returns a deterministic body-free request and manifest digest plus concise
  per-entry eligibility/issues. Missing head state yields only the root issue
  `logical_document_missing`, not derivative mismatch noise.

Approval status is returned for context but approval is not required merely to
index. A plan is a point-in-time source/revision check, not a lease or authority to
mutate either source or projection.

## Bootstrap identity boundary

The shared no-CocoIndex `SelectedBootstrapIdentity` hashes seven required bounded,
non-secret fields: app, environment, topology, source identity, tracking-state
ownership, target ownership and processing profile. The control planner reports a
candidate identity only. It does not import `flow_docs.py`, start CocoIndex or read
a committed live-component marker.

Every result deliberately reports:

```text
bootstrap_observed=false
execution_available=false
indexing_triggered=false
worker_started=false
```

The existing production flow remains static complete-source reconciliation and
continues to reject `DOCSTORE_ONLY_FILES`. A caller-supplied or locally calculated
digest must never be promoted into observed bootstrap proof.

## Verification

- Focused admission/identity/protocol/CLI suite: 87 passed.
- Complete control suite after result-noise correction: **209 passed, 2 skipped**.
  The skips are explicitly gated live revision tests.
- Read-only live control-tool probe used local `docs/NAMING.md` bytes and a
  deliberately nonexistent logical key. It returned `rejected` with exactly
  `logical_document_missing`; all four execution/bootstrap booleans remained false.
- No source modification, corpus scan, embedding/model call, worker launch,
  production projection write or deployment occurred.

## Remaining gate

A separate approved migration/bootstrap must bind the exact deployed worker,
tracking state, source membership, target ownership and processing configuration;
finish without errors; and pass exact target verification before persisting its
committed marker. Selected execution must revalidate the manifest under the shared
exclusive writer lock and record per-item outcomes. Multiple selected items are not
assumed atomic. A post-commit interruption remains indeterminate until readback.

See [synthetic CocoIndex proof](SELECTED-CDC-PROOF-2026-09-12.md) and
[worker safety receipt](CDC-WORKER-SAFETY-2026-09-12.md).
