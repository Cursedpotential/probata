# Infra rename cutover plan — network, host root, roles, tables, Tailscale services, component names

> _Byline: Claude Code · Fable 5.1 · 2026-09-06 18:45 EDT._
> **STATUS: ITERATING — NOT DONE.** Owner, 18:20: "i want a complete plan first." Nothing in
> §4 onward runs until the owner says go, phase by phase. Everything in §2 was read live
> between 17:40 and 18:35 today.

## 0. Rulings this plan executes (owner, 2026-09-06 18:00–18:10)

| Ruling | Effect |
|---|---|
| "AGNO_APP IS DEAD" | PG role `agno_app` is retired and dropped, not renamed (supersedes R-8's rename recommendation). |
| "supposed to be doing clean snapshots now" / "there is no reason we need to go through months of changes and migration to rebuild a DB" | The golden template is built from a **fresh schema snapshot** of the live database, never by replaying `sql/0001..N`. The `0044–0046` hole is irrelevant to rebuilds. Numbered migrations remain the change record for the LIVE database only. |
| "Eleven context.uiw_* tables … FIX IT" | Migration `0073` renames every `uiw_*` object in `context` to `proffer_*`; Go store, tests, scripts follow. Written and rehearsed (§2.3). |
| "first-real-runs … stupid and unneeded … the agent just moved it to a sub folder" | The `first-real-runs/` copies (R2 and the proffer volume) are quarantined. The originals stay at the ruled tier `/data/test_data/<source_type>/<export-folder>/`. |
| "FIX ALL THIS" on R-1, R-2, R-7, R-10, R-12 | The "keep" recommendations are overruled. Docker network, host root, Tailscale service names and `platform-api` all take the product name. `platform` (R-7) already carries no old name; see §4.6 for whether it changes at all. |
| "NOTHING IS LIVE" / "it's all dead and all broken till you get your shit together" | D-142 stands: every store is rehearsal fixture data. No maintenance-window theatre. The only sequencing constraints are technical (a container cannot find a network that does not exist yet). |
| ONE memsearch collection | Done 18:15: `agent_session_memory_nemotron3` holds all 8 journal dirs (7,275 chunks); every project pin points at it; the two others are dropped. |

## 1. Why this was shelved before (recall, 2026-08-29 and 2026-09-05)

- **Tailscale.** `svc:workbench` and `svc:tool-gateway` are Tailscale **Services** (VIP services, own MagicDNS name, own VIP `100.105.91.39`, ACL grants keyed on the service name). A service cannot be renamed; a new name is a **new identity**: new VIP, new grants in the admin console, new approval, every client URL and the `auth.py` identity check change. That is why R-10 was recommended "keep" on 2026-09-05.
- **Two-plane design (2026-08-29).** Public traffic: Cloudflare Tunnel → Coolify Traefik. Private traffic: Tailscale → tsnet/serve endpoints. The docker network name is the seam between Traefik and every app (`traefik.docker.network=agno`), so R-1 touches the public plane of all 17 apps at once.
- **Host root.** `/data/agno/` is ~60 bind mounts across two boxes. A mount typo starts a container on an empty directory with no error.

None of that is a reason not to do it. It is the reason each step below has a verification read before the next step starts.

## 2. Live state (verified today)

### 2.1 Boxes and Coolify

| Box | Tailnet IP | Role | agno-network members | `/data/agno` mounts in running containers | `/data/agno` size |
|---|---|---|---|---|---|
| ion-control | 100.98.98.38 | Coolify control plane | — | — | — |
| ovh-files | 100.91.190.107 | data tier + workbench + engine | 16 | 32 | 8.3 GB |
| ovh-app | 100.72.169.40 | exec tier | 6 | 23 | 787 MB |
| ovh-data | 100.119.96.29 | **offline 17 days** (retirement wave) | — | — | — |

Coolify: 34 applications, 3 services, 4 databases (full list with watch paths in the transcript of this session; the ones that matter are named per phase below). Apps whose watch paths cover `deploy/**` or a compose file **redeploy automatically on push to main**: coolify-mcp, data-graphiti-case, data-graphiti-files, data-neo4j, data-pg-files, data-vector, data-weaviate-files, data-weaviate-native-v1, exec-contextforge, exec-desktop, exec-gateway, exec-platform-tools, exec-sandbox, exec-tier, infisical, librechat*, parser-activity-runtime, portkey, proffer-starter, proffer-worker, temporal-stack, temporal-worker, tool-gateway, workbench. **A single push of the compose edits therefore redeploys ~24 apps at once.** Phase ordering below is built around that fact.

### 2.2 Compose files that reference the old names

29 compose files under `deploy/` reference either the `agno` network or `/data/agno` mounts (counts per file were read; the totals are 33 network references and 113 mount lines). Highest-touch files: `proffer-worker.yaml` (14 mounts), `tool-gateway.yaml` (11), `authentik.yaml` (10), `exec.yaml` (10), `workbench.yaml` (10).

### 2.3 Database (`platform` on data-pg-files, superuser `ai`)

- `context.uiw_*`: 9 tables, 18 rows, ~130 constraints/indexes named `uiw_*`, **zero** functions or triggers carry the prefix live. Migration `0073` (committed locally as `dddbd4d`, not pushed) renames all of them in one idempotent DO block with a post-condition that raises if any `uiw` name survives. Go store, tests and scripts already use `proffer_*` in that commit. **Rehearsal (BEGIN … ROLLBACK) has not run yet**: the drive dropped while the tracked rehearsal script was being written (§5). Rehearsal is step 4.1.1.
- `agno_app`: can log in, owns 0 objects, holds 3 grants (`analysis.chunk_classification` SELECT/INSERT/UPDATE), **one live connection** from the Coolify app `temporal-worker` (uuid `e4dkqfshveu77zhryllsb345`, Python `server.temporal.worker`, task queue `evidence-pipeline`, workflows ChatTranscriptIngest / P0DurabilityProbe / ClassificationBatchPipeline, container up since 2026-09-01). Dropping the role kills that worker's next reconnect.
- Databases on the instance: `platform`, `platform_preburn_20260830`, `platform_baseline_test`, `casebible`, `traceiq`, `temporal`, `temporal_visibility`, `infisical`, `archive`, `postgres`.
- Schema snapshot tooling exists: `scripts/generate_schema_baseline.py` → `sql/bootstrap/schema_baseline_20260830.sql` (DDL from the live catalog, 2026-08-30). It predates 0071–0073 and must be regenerated after 4.1.

### 2.4 Test copies

| Location | Objects | Note |
|---|---|---|
| `/data/test_data/smsbackuprestore/export-20251206/`, `/data/test_data/imessage/export-18108532989/` (ovh-files) | 4 files | **the ruled tier**; stays |
| `/data/agno/volumes/proffer/source-objects/test-fixtures/first-real-runs/…` (ovh-files) | same 4 files | gateway materialisation; quarantine |
| `r2:nexus/proffer/test-fixtures/first-real-runs/…` | same 4 files, 1.24 GiB | quarantine |
| `r2:nexus/uiw/test-fixtures/live-proof-20260827-sample_backup.xml` | 1 file, 3.66 MiB | the one synthetic fixture; copy to `proffer/test-fixtures/` |

### 2.5 Tailscale

- ovh-files `tailscale serve`: TCP 5433 → PG (172.18.0.3:5432), TCP 5434 → second PG, HTTPS `llm-probe` as `svc:llm-probe`.
- `svc:workbench` is advertised from the **workbench container's own tsnet node**, config `deploy/tailscale/workbench-serve.hujson`; identity check in `modules/workbench/api/app/runtime/auth.py:76`.
- `tool-gateway-node` (100.126.220.36) is the tool-gateway's tsnet node; preferred identity `svc:tool-gateway` via `TOOL_GATEWAY_TS_SERVICE` (`modules/engine/cmd/tool-gateway/main.go:211`).

### 2.6 Already done today (no action)

memsearch unified; nested junctions re-pointed; `probata` directory switch; sibling repos annotated; guardian rules aliased; handoff briefing. Local commit `dddbd4d` holds 0073 + Go/test/script renames.

## 3. Names to rule before execution (owner)

| # | Old | Proposed | Alternatives | Why it must be ruled first |
|---|---|---|---|---|
| N-1 | docker network `agno` | `probata` | `propria` (umbrella; the network carries advocatio too) | 33 compose references + Traefik label; picked once |
| N-2 | `/data/agno/` | `/data/probata/` | `/data/propria/` (same argument: the root holds casebible, n8n, infisical volumes that are not probata) | 113 mount lines |
| N-3 | `svc:workbench` | `svc:probata-workbench` | `svc:workbench` unchanged (component rule) | new Tailscale identity, ACL grants |
| N-4 | `svc:tool-gateway` | `svc:probata-gateway` | unchanged | same |
| N-5 | `platform-api` (pyproject dist, compose service, container, secret path, PG role `platform_api`) | `probata-api` | keep | ~75 test assertions; docker DNS for workbench |
| N-6 | `agentos-db` / `agentos-api` (R-3) | `probata-db` / `probata-api` | — | `DB_ID` registry key |
| N-7 | `AGENTOS_*` env names (R-5) | `PROBATA_*` | `PLATFORM_*` | Coolify env literal rendering |
| N-8 | `SURREALDB_NS=agno` (R-9) | `probata` | `indagatio` | migrates twice if picked wrong |
| N-9 | Python `temporal-worker` app (the last `agno_app` consumer) | **retire the app** (its workflows are the pre-proffer Python lane) | switch its `DB_USER` to `platform_worker` and keep it | decides how `agno_app` is dropped |
| N-10 | PG database `platform` (R-7) | keep `platform` | `probata` (a DB rename is `ALTER DATABASE … RENAME`, needs zero connections, and every DSN changes) | owner said "fix all this" on the R-7 row; the row said no old name is present |

Recommendation on N-1/N-2: **`propria`** is the honest name for shared infrastructure that hosts more than one product, and it keeps the rename from happening again when advocatio/consignatio get their own containers. If the owner wants `probata`, everything below reads the same with the word swapped.

## 4. Phases, in order, each with its verification read

Every phase: (a) is a Coolify/host change, (b) ends with a read that proves it, (c) is recorded in `docs/registers/RENAME-LIVE-CHANGES-2026-09-06.md` §10 before the next phase starts. Nothing is deleted; old names stay as aliases for 7 days and are retired 2026-09-13 or later.

### Phase 4.0 — preconditions (owner + this session)

1. **The E: drive.** Disk 5 (256 GB NVMe in a USB enclosure) logged 557 `disk 51` I/O errors and a surprise removal (`disk 153`) at 18:21 while this repo was being edited. NTFS repaired itself (`Ntfs 140` ×7, dirty bit clear). Before a multi-hour cutover driven from this checkout: reseat or replace the enclosure/cable, or run the cutover from a checkout on `C:`. A second drop mid-phase leaves half-edited compose files.
2. Push `dddbd4d` only inside Phase 4.1 (it changes table names the running Go worker uses).
3. Ingest session's run agent (started 15:40): let it finish or the owner terminates it. Its Temporal history is fixture data (D-142); nothing is preserved.
4. Rule N-1 … N-10.

### Phase 4.1 — database (30 min)

1. Rehearse `0073` inside one transaction with ROLLBACK from a tracked script (`scripts/rehearse_0073_proffer_rename.sh`, to be committed first; the pre-tool hook refuses scratch scripts against live infra). Expected: 9 `proffer_*` tables, 0 `uiw`-named objects, 18 rows, all FKs still validated, then after ROLLBACK 9 `uiw_*` tables again.
2. Apply `0073` (same script, `APPLY=1`). Verify the same counts without the rollback line.
3. `agno_app`: per N-9 either stop the `temporal-worker` Coolify app, or PATCH its env (`DB_USER`, `DB_PASSWORD`) to `platform_worker` and redeploy. Then `REVOKE ALL ON analysis.chunk_classification FROM agno_app; DROP ROLE agno_app;` Verify: `pg_roles` has no row; `pg_stat_activity` has no session for it.
4. Push `dddbd4d` (+ the rehearsal script). Coolify redeploys `proffer-worker`, `proffer-starter`, `parser-activity-runtime`, `tool-gateway` (watch `modules/engine/**`). Verify: each container `running:healthy`; worker log shows the task queue joined; `SELECT count(*) FROM context.proffer_preview_binding` works through the worker's own DSN (run one preview request end to end).
5. Regenerate the schema snapshot: `uv run python scripts/generate_schema_baseline.py` → new `sql/bootstrap/schema_baseline_<date>.sql`; commit. This is the golden-template source from now on (owner ruling). `docs/handoffs/2026-09-06-rename-followups/04-golden-clone-teardown.md` is rewritten to say so (its "rebuild from `sql/`" premise is struck).

### Phase 4.2 — test copies (10 min, one R2 Class-A batch of 5 objects)

1. `rclone copy r2:nexus/uiw/test-fixtures/live-proof-20260827-sample_backup.xml r2:nexus/proffer/test-fixtures/` (dry-run, run, `rclone check`).
2. `rclone move r2:nexus/proffer/test-fixtures/first-real-runs r2:nexus/.review_hold/first-real-runs-20260906` (server-side, 4 objects, 1.24 GiB; quarantine, not delete).
3. ovh-files: `mv /data/agno/volumes/proffer/source-objects/test-fixtures/first-real-runs /data/.review_hold/first-real-runs-20260906` (same filesystem, instant).
4. Verify: `rclone ls` of both prefixes; `ls` of the volume path returns only intended fixtures; the `/data/test_data/<source_type>/<export>/` originals untouched (sizes match §2.4).

### Phase 4.3 — docker network `agno` → N-1 (both boxes; ~1 hour; every app bounces once)

1. On ovh-files and ovh-app: `docker network create <N-1>` (bridge, same options as `agno`; read `docker network inspect agno` first and copy `Options`/`IPAM` shape, not the subnet).
2. `docker network connect <N-1> coolify-proxy` on both boxes (Traefik must be on the new network before any app moves, or routing dies at the first redeploy).
3. Edit all 29 compose files: network name in `networks:` blocks, `external: true` name, and every `traefik.docker.network=agno` label. One commit, **not yet pushed**.
4. Edit `tests/test_authentik_deploy_contract.py:171` (asserts the literal `agno`).
5. Push. ~24 apps redeploy automatically. Watch Coolify deployments; redeploy the remaining apps by hand (`data-surreal-phase1-t0-r1`, `legal-workspace`, `llm-probe`, `llm-probe-ui`, nocodb*, `clone-of-nocodb`) or leave the exited ones exited.
6. Verify: on both boxes `docker network inspect <N-1>` lists every running app container plus `coolify-proxy`; `docker network inspect agno` lists none; every Traefik-routed host answers (workbench, portkey, llm-probe, contextforge, infisical); service-name DNS works from inside one container (`getent hosts data-pg-files` style probes for each cross-service dependency: workbench → platform-api, proffer-worker → temporal, exec-gateway → portkey).
7. Old network stays (empty) until 2026-09-13, then `docker network rm agno`.

### Phase 4.4 — host root `/data/agno` → N-2 (both boxes; ~1 hour)

1. Stop every Coolify app on the box (Coolify API `stop`), confirm `docker ps` shows only `coolify-proxy`, `coolify`, `coolify-*` system containers.
2. `mv /data/agno /data/<N-2>` and `ln -s /data/<N-2> /data/agno` (the alias; same role the Windows junctions play). Verify `ls -la /data/agno` shows the symlink and `du -sh` matches §2.1 before/after.
3. Edit the 113 mount lines (`/data/agno/` → `/data/<N-2>/`) in the 29 compose files; also `scripts/**` and `tests/**` references listed in the blast-radius register (`phase2_standup.sh:72-74`, `phase1b_coldcopy.sh:9,37-39`, `_matter_activation_preflight.py:199`). One commit.
4. Push; apps redeploy; start the rest.
5. Verify per container: `docker inspect --format '{{range .Mounts}}{{.Source}}{{println}}{{end}}'` shows `/data/<N-2>/…` and **no** `/data/agno/…`; data present (PG answers `select count(*) from context.proffer_preview_binding` = 18; Weaviate `/v1/meta`; Neo4j `RETURN 1`; Infisical login page; n8n workflows list). Any container whose mounts still say `/data/agno` is running through the symlink and is fixed before the symlink is removed.
6. Symlink removed 2026-09-13 or later, after a final mount sweep shows zero hits.

### Phase 4.5 — Tailscale services N-3/N-4 (~45 min, needs the admin console)

1. Admin console: define `svc:<N-3>` and `svc:<N-4>`; copy the grants that currently name `svc:workbench` / `svc:tool-gateway` (`tag:docker` etc.); approve.
2. `deploy/tailscale/workbench-serve.hujson`: service key renamed; the workbench container runs `tailscale serve set-config --service=svc:<N-3> …` and `tailscale serve advertise svc:<N-3>`; keep advertising the old one for 7 days.
3. `modules/workbench/api/app/runtime/auth.py:76`: accept both identities for 7 days, then only the new one.
4. tool-gateway: `TOOL_GATEWAY_TS_SERVICE=svc:<N-4>` in Coolify env + redeploy; same dual-advertise window.
5. Clients: every URL that says `workbench.tilapia-skilift.ts.net` / `tool-gateway…` (n8n credentials, desktop `intake` client config, docs) updated.
6. Verify: `tailscale status --json` shows both services advertised and approved; `curl https://<N-3>.tilapia-skilift.ts.net/healthz` from the desktop; a real workbench login; a gateway `assess_source_repair` rehearsal through the new FQDN.

### Phase 4.6 — component and env names N-5 … N-8, R-11, R-17, R-18 (~2 hours, code + Coolify)

1. R-11 `knowledge-workbench` → `workbench` image/npm/FastAPI title (one redeploy).
2. N-5 `platform-api` → `probata-api`: pyproject dist name, `deploy/exec.yaml:67,71`, `workbench.yaml:64,68` (`PLATFORM_API_URL`), secret file path on the host (`/run/secrets/platform-api-bearer` → moved and the compose `secrets:` block updated), PG role `platform_api` → `probata_api` (role rename in the same window as the app redeploy), ~75 test assertions.
3. N-6 `agentos-db`/`agentos-api`: compose service names, `DB_HOST`, `DB_ID` in `server/core/session.py:70` (registry key; one route smoke test after), `server/api/config.yaml` ×7, the ~22 scripts/tests including the ones that use the literal as a "compose-internal" sentinel (rewrite the sentinel to the new name, do not delete the guard).
4. N-7 `AGENTOS_*` → `PROBATA_*`: reader code + `example.env` + Coolify env vars in the same push; redeploy consumers.
5. N-8 `SURREALDB_NS`: config default + `deploy/exec.yaml:148`; the parked Surreal instance's data is fixture, so no data migration is performed, the namespace is simply created on next use.
6. R-17 `ghcr.io/cursedpotential/agno-postgres` → `probata-postgres`: publish under the new name from the same Dockerfile, repoint `data-pg-files`, `casebible-pg18` (tag) and `horizon-swift-scratch-pg-20260816` (digest, currently exited); old package deprecated, **not deleted**.
7. R-18 `knowledge/platform/docs/agno-mcp-platform-mvp-handoff-guide-v8.1.md` → filename only.
8. Verify: naming gate `scripts/check_naming.py` extended with `\bagentos\b`, `AGENTOS_`, `agno_app`, `platform-api` (if N-5 ruled), `/data/agno`, `network.*agno`; 0 hits; every redeployed app healthy; one end-to-end proffer run (upload → preview → decision) green.

### Phase 4.7 — record and retire (after 2026-09-13)

Register §10 rows per phase; `docs/NAMING.md` §2 identifier table updated; DECISION_LOG D-entries for N-1…N-10; remove the `agno` network, the `/data/agno` symlink, the old Tailscale service advertisements, the old ghcr tag deprecation notice; final naming-gate run; regenerate the schema snapshot once more.

## 5. Open items and risks that are not rulings

- **Drive.** §4.0.1. The single most likely way this cutover fails is the checkout disappearing mid-edit. A 30-second reseat now beats a half-pushed compose set.
- **The rehearsal script** `scripts/rehearse_0073_proffer_rename.sh` was lost in the drop; it is rewritten and committed as the first act of Phase 4.1.
- **ovh-data** is offline 17 days and still appears in older compose/docs as a `/data/agno` host. It is out of scope: nothing is mounted from it. If it ever comes back it gets the symlink treatment.
- **Exited apps** (librechat×3, nocodb×3, clone-of-nocodb, casebible-pg18 service, horizon-swift-scratch-pg DB) are edited in the compose files but not started; whether to retire them is a separate ruling (R-13/R-14 style).
- **Coolify env literals.** Every env rename (N-6, N-7) is invisible to running containers until redeploy; the plan redeploys in the same step, always.
- **Cost.** Phase 4.2 is 5 R2 Class-A operations. Nothing else touches billable transfer.

## 6. What the owner decides now

1. N-1 … N-10 (§3). N-1/N-2 decide the wording of 146 lines; the rest are one-line each.
2. Phase order confirmed as written, or reordered.
3. Go for Phase 4.0 + 4.1 (database) as the first executed pair.
