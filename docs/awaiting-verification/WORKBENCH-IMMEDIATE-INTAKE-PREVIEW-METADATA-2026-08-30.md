# Workbench immediate intake preview and metadata release receipt

> _Byline: Codex · GPT-5.6-Sol · 2026-08-30._
> _Naming: written before the 2026-09-05 rename (D-137..D-141); see docs/NAMING.md for the old->new glossary._

## Delivered contract

- Selecting a fixed `casebible-sorted` object immediately streams it through the authenticated
  Workbench BFF, computes a read-only SHA-256, and renders PDF, image, or bounded text preview
  without claiming custody or evidentiary promotion.
- The parser panel displays an explicitly non-authoritative filename-extension preflight until the
  durable UIW parser receipt replaces it.
- One-item and small-batch intake can capture source relationship, parties, acquisition method and
  authority, known dates and certainty, device/custodian, context, and notes before start.
- Source observations remain `preview_only`; custody acquisition recomputes the authoritative
  checksum. Human assertions are separate, actor-bound, append-only revisions with idempotency and
  correction receipts.
- The starter validates every `source_context_ref` against the exact request, matter, court case,
  and authorized source before Temporal starts. Source registration binds that exact reference to
  the canonical source version.
- The shared Case Bible contract is versioned at
  `docs/schemas/platform-intake-job-contract-v1.openapi.yaml`; the compatibility mapping is beside it.

## Validation receipt

- Engine: `go test ./...` passed.
- Workbench API: 254 tests passed; the only full-suite failure is the pre-existing
  `app/types/case_management.py` 315-line structure violation. All intake/UIW source tests pass.
- Browser: Vite/TypeScript production build and all 26 smoke tests passed.
- Storybook: production build passed.
- PostgreSQL: migrations 0036, 0050, 0051, and 0053 were exercised together in a rollback-only
  production connection before release. The live database had none of those UIW tables beforehand,
  so deployment requires the full ordered chain rather than forcing migration 0053 alone.
- The first live apply attempt stopped before UIW DDL because the empty legacy migration ledger used
  `schema_version_id` while the tracked rich-ledger contract and apply scripts require `id`. The
  guarded, empty-ledger-only forward true-up is persisted at
  `sql/bootstrap/schema_version_ledger_trueup.sql`; it must run before 0036.

## Release state

Production deployment IDs, exact commit, migration ledger receipts, and live browser proof are
appended here after the Coolify release completes.
