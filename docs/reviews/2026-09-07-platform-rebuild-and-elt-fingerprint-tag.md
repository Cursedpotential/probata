# Platform rebuild 2026-09-07 + ELT fingerprint re-tag

> _Byline: Claude Code · Fable 5.1 · 2026-09-07 03:15 EDT. Rulings applied: D-124, D-149, D-152._

## Outcome

- Live `platform` rebuilt from `sql/bootstrap/schema_snapshot_20260907.sql` (fresh pg_dump of live, edit steps 1-5) with the keep set.
- Keep set proven before the drop (`verify-keep`): 49 COPY blocks; all 26 live tables with rows matched exactly; identical after reload.
- Shape after: 276 tables · 9 `context.proffer_*` · 0 `uiw` objects · 0 FKs leaving `reference` · `analysis.human_label*` gone (under `reference`) ·
  `raw.*.content_canon` DEFAULT `context-rawrecord-fingerprint-v1` · `agno_app` role absent · 14 extensions incl. pg_duckdb/postgis/vector.
- `ai.agno_approvals` (created live by the Agno runtime after 09-06) survived because the snapshot is a fresh dump.
- Services were disconnected by `pg_terminate_backend` during the rebuild; pools reconnect lazily. Not re-verified from this desktop.

## Near-miss (why the classifier block was the right thing)

- The 09-06 rebuild never ran (live still held every keep schema).
- `pg_dump --schema=... -t ...` ignores `-n` when `-t` is given: the keep set held 4 COPY blocks (2 labels tables + 2 public) on 09-06 and
  2 on the first 09-07 attempt - a rebuild would have dropped media (15,252 enrichment rows, 7,121 photos), reference (527 detection patterns...),
  knowledge, canon, registry and ops. Fixed: `-t "schema.*"` patterns + `verify-keep` gate that `rebuild` requires.

## ELT hash

- The lane's `content_hash` is a post-decode context fingerprint, not custody H2; tag renamed to `context-rawrecord-fingerprint-duckdb-json-v1`
  (`modules/engine/postgres/elt_structured_repository.go`), registered in `docs/reference/HASH-TAXONOMY-2026-08-29.md`, guarded by
  `TestEltCanonIsAContextFingerprintNotCustodyH2`; `go build/vet/test` green for `postgres` + `activities`.
- Custody H1/H2/H3 remain a promotion-time concern (D-149); no further hash work now (D-152).

## Backups on the host (`/data/agno/backups`)

- `platform-pre-rebuild-20260907.dump` (42 MB, pg_dump -Fc of live before the drop) · `keep_data_20260907.sql` (122 MB) · `schema_snapshot_20260907.sql`.
- 09-06 files untouched.

## Not committed

All of the above is in the working tree only (owner decides; PII check on `docs/private` first per the 09-06 handoff).
