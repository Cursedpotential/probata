# pg_duckdb `webbed` extension — installed live 2026-09-06

> _Byline: Claude Code · Fable 5.1 · 2026-09-06._
> STATUS: DONE, live-verified. Owner order 15:12 ("do it"). Serves D-149 item 9 (DuckDB ELT templates use `read_xml` / `read_html`).

## Target

| Item | Value |
|---|---|
| Host / container | ovh-files `100.91.190.107`, Coolify app `agentos-db` (image `agno-postgres:18-duckdb`), the only container publishing `:5432` on the tailnet |
| Database | `platform` (43 `context.*` tables); all three proffer services connect to `…:5432/platform` (verified from their env) |
| pg_duckdb / DuckDB | 1.1.0 / v1.4.3 |
| Extension | `webbed` from the DuckDB community repo (`read_xml`, `read_xml_objects`, `read_html`, XPath helpers) |

## What was changed

1. `select duckdb.install_extension('webbed', 'community')` → downloaded 12.3 MB to `/var/lib/postgresql/18/docker/pg_duckdb/extensions/v1.4.3/linux_amd64/`, row added to `duckdb.extensions` with `autoload = true`.
2. First load FAILED: `signature is either missing or invalid and unsigned extensions are disabled`. Root cause: `duckdb.allow_community_extensions = off` (community-signed extensions are rejected under that setting; the download was intact, sha `6f7a7481…`, community repo serves the v1.4.3 build).
3. **Incident, ~1 minute:** with the autoload row present and the setting off, EVERY `duckdb.raw_query` on `platform` errored. Corrected by `update duckdb.extensions set autoload=false where name='webbed'`, then `alter system set duckdb.allow_community_extensions = on; select pg_reload_conf();`, then autoload re-enabled. `duckdb.allow_unsigned_extensions` was NOT touched (stays off).
4. Proof: `scripts/pgduckdb_webbed_smoke.sql` run over stdin from the repo → pg_duckdb alive, setting `on`, `webbed installed=true loaded=true`, `read_xml` returned 2 typed rows from a 2-record SMS-shaped document, count = 2.

## Follow-ups

- The setting is persisted by ALTER SYSTEM in `postgresql.auto.conf` inside the container's data dir; it survives restarts but NOT a rebuild from image. Add `duckdb.allow_community_extensions = on` to the `agno-postgres:18-duckdb` image config or the Coolify env for the app so a redeploy keeps it. (`deploy/docker/postgres/`.)
- First real template: `read_xml` over the 1.3 GB smsbackuprestore export on block storage, compared to the SBV decoder on fields, counts, and time. Byte offsets are not required for `read_xml` templates (Q1=C slow lane: re-parse with the pinned template at promotion).
- Lint stage precedes selection (owner 15:04); `read_xml` is strict, so malformed input is a lint finding.

## Lesson

Installing an extension with autoload on, before confirming the loader accepts it, took the live DuckDB path down for the duration of the fix. Order next time: set `allow_community_extensions`, install with autoload off, load once by hand, then enable autoload.

## Persistence (closes the follow-up above)

> _Byline: Claude Code · Sonnet 5 · 2026-09-06._

- **File:line:** `deploy/docker/postgres/Dockerfile:64` (final `CMD` line). The
  image's only existing mechanism for pg_duckdb GUCs is the `postgres -c ...`
  argument list in the Dockerfile `CMD` (there is no `postgresql.conf.d`
  fragment or compose `command:` override for this service in
  `deploy/data-pg.yaml`) — the new setting was added there, alongside the
  existing `shared_preload_libraries` flag, as its own `-c`:
  `"duckdb.allow_community_extensions=on"`. `duckdb.allow_unsigned_extensions`
  was deliberately NOT added.
- **Extension row survives on its own:** the `webbed` row in `duckdb.extensions`
  (with `autoload = true`) lives in the data volume
  (`/data/agno/volumes/pgdata`), not the image, so it is untouched by this
  change and survives a redeploy regardless. The image does not pre-install
  any DuckDB extensions (no `INSTALL`/`duckdb.install_extension` step exists
  in the Dockerfile), so per scope no download step was added — only the GUC.
- **Validation performed:** `deploy/data-pg.yaml` (the compose file for this
  Coolify app) still parses with `python3 -c "import yaml,sys;
  yaml.safe_load(open(sys.argv[1]))"` (confirmed OK). A `docker build` of the
  Dockerfile is not possible on this desktop (no Docker CLI) — the actual
  image-build/boot check happens on the VPS at the next Coolify deploy of
  `agentos-db`.
- **Deploy action required (owner-triggered, not run here):** a Coolify
  redeploy of the `agentos-db` app (which rebuilds `agno-postgres:18-duckdb`
  from `deploy/docker/postgres/` and bounces the live container). This was
  NOT triggered as part of this change — no live service was restarted or
  redeployed.
