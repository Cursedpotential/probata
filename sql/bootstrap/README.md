# THE DATABASE

> _Byline: Claude Code · Fable 5.1 · 2026-09-07. Owner rulings: D-142 §3, 2026-09-06 18:51, D-152, 2026-09-07 07:24._

`schema_snapshot_20260907.sql` **is** the `platform` database. It is a `pg_dump --schema-only` of live, passed through
`scripts/rebuild_platform_from_snapshot.sh edit` (uiw->proffer, no `agno_app`, human labels under `reference`, no FK leaving
`reference`, `raw.*.content_canon` default = context-fingerprint family).

## Rules

- **There are no migrations.** Numbered `sql/NNNN_*.sql` files are retired to `sql/_stale/migrations-retired-20260907/`
  and are never replayed. Do not create new ones. Do not propose them in plans.
- **A schema change = edit this snapshot in its final form, then rebuild.**
  `STAMP=<date> bash scripts/rebuild_platform_from_snapshot.sh dump`, `verify-keep`, `edit`, `rebuild`. The dump step
  refreshes the snapshot from live first, so hand edits go into the edit step (step 5 style) or directly into the new
  dated snapshot before `rebuild`.
- **Reference and state tables never change or delete across rebuilds**: the keep set (`reference.*`, `media.*`,
  `knowledge.*`, `canon.*`, `registry.*`, `ops.*`, `public.canon_registry`, `public.schema_version`) is exported, proven
  against live (`verify-keep` must print `KEEP-SET OK`) and reloaded. Everything else is fixture until first real ingest (D-142).
- Fresh-container bootstrap (`docker-entrypoint-initdb.d`) applies this same file (see `deploy/compose.yaml`, `deploy/data-pg.yaml`).
- `sql/parked/geo_lane_parked_20260831.sql` is the owner-ruled parked geo lane (D-121), not a migration.
