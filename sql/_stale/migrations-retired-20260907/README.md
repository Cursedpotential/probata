# Retired numbered migrations (parked 2026-09-07)

> _Byline: Claude Code · Fable 5.1 · 2026-09-07. Owner rulings 2026-09-06 18:51 ("the snapshot is the database"), D-142 §3, D-152, and 2026-09-07 07:24 ("create the rest in their final form")._

These files are HISTORY. They are never replayed, never edited, never referenced by code or tests. The database is
`sql/bootstrap/schema_snapshot_<date>.sql`; a schema change is made by editing the snapshot and running
`scripts/rebuild_platform_from_snapshot.sh` (dump -> verify-keep -> edit -> rebuild). Reference and state tables (the keep set)
survive every rebuild; everything else is created in its final form.
