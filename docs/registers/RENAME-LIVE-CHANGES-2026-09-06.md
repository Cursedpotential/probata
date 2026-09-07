# Rename — every LIVE change made outside git (register)

> _Byline: Claude Code · Fable 5.1 · 2026-09-06. Companion to `RENAME-BLAST-RADIUS-2026-09-05.md`
> and `docs/NAMING.md` (D-137..D-142). Written for the ingest session's reconciliation:
> reconcile against THIS list, not guesses. Updated as each live step lands._

Status legend: **DONE** (verified live) · **PENDING-OWNER** (classifier refused my write; owner runs it) ·
**NOT DONE** (deliberately left) · **AFTER PUSH** (sequenced behind the git push).

## 1. Git / GitHub

| Item | Old | New | Status |
|---|---|---|---|
| GitHub repository | `Cursedpotential/mcp-platform-agno-mvp` | `Cursedpotential/probata` (GitHub redirect from old name active) | DONE 2026-09-05 |
| Local `origin` remote | old URL | `https://github.com/Cursedpotential/probata.git` | DONE |
| Commits on `main` | — | `d7e8f81`, `34f8d8d`, `b50d828`, `01dfaa2`, `48ff9f3`, `4fed839` + the ingest session's `9c00b46`, `35e5092` | PUSHED 2026-09-06 10:25 EDT after the Coolify repoint |

## 2. Coolify (control plane on IONOS) — DONE 2026-09-06 10:24 EDT (owner exited auto mode; verified with `show`/`envs`)

Caveat found during the env rename: Coolify keeps a preview-environment twin of every key; the first pass deleted the preview twins and created the new keys as preview rows. Corrected by deleting the remaining old production rows and promoting the new keys to production (values verbatim). `N8N_PROFFER_BASE_URL` production value was re-set to the tailnet URL (`http://100.91.190.107:5678/webhook`, 34 chars) because the preview twin carried the docker-internal hostname. `TEMPORAL_TASK_QUEUE=proffer-v1` set explicitly on worker and starter.

| App uuid | Field | Old | New |
|---|---|---|---|
| `d24bb9eoo47qtw9eq1xc6u64` | name | `universal-import-worker` | `proffer-worker` |
| 〃 | docker_compose_location | `/deploy/universal-import-worker.yaml` | `/deploy/proffer-worker.yaml` |
| 〃 | watch_paths | `modules/engine/**`, `deploy/docker/universal-import-worker/**`, `deploy/universal-import-worker.yaml` | `modules/engine/**`, `deploy/docker/proffer-worker/**`, `deploy/proffer-worker.yaml` |
| 〃 | env keys | `N8N_UNIVERSAL_IMPORT_BASE_URL/_AUTH_HEADER/_AUTH_VALUE`, `UIW_SOURCE_OBJECT_DIR`, `UIW_PARSER_BUNDLE_DIR`, `UIW_NORMALIZED_BUNDLE_DIR`, `UIW_INVENTORY_MANIFEST_DIR` | `N8N_PROFFER_BASE_URL/_AUTH_HEADER/_AUTH_VALUE`, `PROFFER_SOURCE_OBJECT_DIR`, `PROFFER_PARSER_BUNDLE_DIR`, `PROFFER_NORMALIZED_BUNDLE_DIR`, `PROFFER_INVENTORY_MANIFEST_DIR` (values copied verbatim) |
| `r1084s1lsm80fsv4ol9ocij0` | name | `universal-import-starter` | `proffer-starter` |
| 〃 | docker_compose_location | `/deploy/universal-import-starter.yaml` | `/deploy/proffer-starter.yaml` |
| 〃 | watch_paths | …`universal-import-starter`… | `modules/engine/**`, `deploy/docker/proffer-starter/**`, `deploy/proffer-starter.yaml` |
| 〃 | env keys | `N8N_UNIVERSAL_IMPORT_*` (3), `UNIVERSAL_IMPORT_UPLOAD_TOKEN`, `UNIVERSAL_IMPORT_UPLOAD_MAX_BYTES` | `N8N_PROFFER_*`, `PROFFER_UPLOAD_TOKEN`, `PROFFER_UPLOAD_MAX_BYTES` |
| `o11nxvzqwskxrqmtbvup7iet` (parser-activity-runtime) | git_repository only | old repo | `Cursedpotential/probata` (compose path unchanged; its bind mounts changed in git, see §3) |
| `xjbuo6drbwjfby75lalk8bk7` | name | `knowledge-workbench` | `workbench` (R-11) |
| 〃 | watch_paths | `workbench/**`, `deploy/workbench.yaml` (stale since the 2026-09-01 move) | `modules/workbench/**`, `deploy/workbench.yaml` |
| 〃 | env keys | `UIW_STARTER_URL`, `UIW_STARTER_TOKEN`, `UIW_UPLOAD_TOKEN` | `PROFFER_STARTER_URL`, `PROFFER_STARTER_TOKEN`, `PROFFER_UPLOAD_TOKEN` |
| all other 30 apps | git_repository | old repo (works via GitHub redirect) | `Cursedpotential/probata` — NOT DONE; cosmetic, redirect covers it |

Coolify renders env VALUES into the materialized compose at deploy — none of the above reaches a container
until each app is redeployed (§6).

## 3. Host directories — DONE 2026-09-06 13:48 UTC (running containers unaffected; bind mounts follow the inode)

| Host | Old absolute path | New absolute path |
|---|---|---|
| ovh-files (`100.91.190.107`, ubuntu) | `/data/agno/volumes/universal-import/` (source-objects, parser-bundles, normalized-bundles, inventory-manifests, parser-artifacts) | `/data/agno/volumes/proffer/` (same five subdirs, same uid 10001) |
| ovh-files | `/data/agno/secrets/uiw/{preview-cursor-key,service-token}` | `/data/agno/secrets/proffer/{preview-cursor-key,service-token}` |
| ovh-files | `/data/agno/secrets/n8n/universal-import-auth` | `/data/agno/secrets/n8n/proffer-auth` |
| ovh-app (`100.72.169.40`, debian) | `/data/agno/secrets/uiw/service-token` | `/data/agno/secrets/proffer/service-token` |
| ovh-app | `/data/agno/volumes/universal-import/` | did not exist on this host (nothing moved) |
| both | `/data/agno/` root, `/data/agno/secrets/{casebible-r2.json,platform/,tool-gateway/}` | **unchanged** (R-2: plumbing root, not a product name) |

Container-side paths changed in git: `/data/uiw/*` → `/data/proffer/*`; `/run/secrets/uiw-*` → `/run/secrets/proffer-*`;
`/run/secrets/n8n-universal-import-auth` → `/run/secrets/n8n-proffer-auth`.

## 4. Temporal — DONE 2026-09-06 10:28 EDT: worker log `Started Worker Namespace default TaskQueue proffer-v1`, 26 activities; starter `/healthz` 200

| Item | Old | New | Note |
|---|---|---|---|
| Task queue | `universal-import-v1` | `proffer-v1` | compose defaults changed in git; BUT Coolify sets `TEMPORAL_TASK_QUEUE` explicitly on both apps and the value is 19 chars = `universal-import-v1`, which overrides the default. PENDING-OWNER: set `TEMPORAL_TASK_QUEUE=proffer-v1` on `d24bb9eoo47qtw9eq1xc6u64` and `r1084s1lsm80fsv4ol9ocij0` in Coolify before redeploy, or the new worker/starter keep polling the old queue |
| Workflow type | `UniversalImportWorkflow` | `ProfferWorkflow` | in-flight runs are rehearsals (D-142); they are orphaned, not drained — terminate them in Temporal UI after the new worker is up |
| Old worker drained? | — | no | D-142: nothing live to preserve |

## 5. n8n — DONE 2026-09-06 10:24 EDT via the REST API (`X-N8N-API-KEY`, the same path the agents used to create them); all seven renamed `Proffer - …`, webhook paths `proffer/*`, all still active

| Live workflow (id) | Old webhook path | New path | Rename name to |
|---|---|---|---|
| Universal Import - start (`7HDcx0GPDELB56J0`) | `universal-import/start` | `proffer/start` | Proffer - start |
| Universal Import - preview (`nobMh2uO8eIBuH2p`) | `universal-import/preview` | `proffer/preview` | Proffer - preview |
| Universal Import - decision (`abOE3dzoZo3yw26x`) | `universal-import/decision` | `proffer/decision` | Proffer - decision |
| Universal Import - select_parser_activity (`fvKS2gcsRUdEKUun`) | `universal-import/select-parser-activity` | `proffer/select-parser-activity` | Proffer - select_parser_activity |
| Universal Import - execute_parser_activity (`YQoFBykpZoDrU0n6`) | `universal-import/execute-parser-activity` | `proffer/execute-parser-activity` | Proffer - execute_parser_activity |
| Universal Import - assess_source_repair_activity (`6TMn03Jq8WSxt9iY`) | `universal-import/assess-source-repair-activity` | `proffer/assess-source-repair-activity` | Proffer - assess_source_repair_activity |
| Universal Import - resolve_source_repair_activity (`cu7y91jsOVfBBWJC`) | `universal-import/resolve-source-repair-activity` | `proffer/resolve-source-repair-activity` | Proffer - resolve_source_repair_activity |

The checked-in definitions under `deploy/docker/n8n/workflows/proffer/*.json` already carry the new paths. The
`headerAuth` credential named `N8N_UNIVERSAL_IMPORT_WEBHOOK` is a credential NAME inside n8n — unchanged.
Sequencing: change the live paths at the same time as the worker/starter redeploy; until both sides match,
parser select/execute calls 404.

## 6. Redeploys — DONE 2026-09-06 10:26–10:29 EDT (all four queued via API; worker Up, starter healthy, parser-runtime healthy, workbench healthy; worker mounts verified on `/data/agno/volumes/proffer/*` and `/run/secrets/n8n-proffer-auth`)

1. `proffer-worker` and `proffer-starter` together (queue + workflow type + env names + mounts all change at once).
2. `parser-activity-runtime` (new bind-mount paths).
3. `workbench` (new env names, `/api/proffer` routes).
Proof: worker log shows polling `proffer-v1`; starter `/healthz` 200 on `100.91.190.107:8091`; Temporal UI lists
pollers on `proffer-v1`; a Workbench preview call reaches `/api/proffer/...`.

## 7. R2 dev fixtures — NOT DONE (flagged)

Code now expects `r2://nexus/proffer/test-fixtures/…` (`runtimeapi.devFixturePrefix`, dev-bypass only). The
objects sit at `nexus/uiw/test-fixtures/`. Server-side copy required (`rclone copy` within the bucket, dry-run
first per the transfer rule); old prefix stays until the copy is verified. Not done in this pass.

## 8. Deliberately left on the old name

| Identifier | Why |
|---|---|
| PG tables `uiw_preview_*`, `uiw_source_context_revision`; migration filenames `0066_uiw_*`, `0067_uiw_*` | `sql/` is immutable applied history; a rename migration belongs to the golden-clone lane (D-142 §3) |
| docker network `agno`, `/data/agno/` host root, PG roles `agno_app`/`platform_*`, `SURREALDB_NS=agno`, `agentos-*` compose services, `OS_SECURITY_KEY` | need owner rulings R-1..R-9 (blast-radius register) |
| `agentos.mitechconsult.com` DNS (live, 503) | R-4: retire, not rename — owner action in Cloudflare |
| `ghcr.io/cursedpotential/agno-postgres` image | R-17: two live DBs pull it by digest; republish-then-deprecate, separate change |
| `svc:workbench`, `svc:tool-gateway`, `platform-api` | component names, correct under the rule |
| SBV's own "universal import" API term in `sbv_sms.py` / `_sbv_client.py` | donor vocabulary, not our lane |
| Case Bible identifiers (`casebible-*` buckets, `casebible` database/table prefix, `cb-*` commands) | D-141 KEEP |
| sibling repos `Legal-Workspace` → advocatio, `traceIQ` → vestigia (GitHub names) | directory renames are the last step of this pass; GitHub repo renames need their own decision |
| ~~Checkout directory `Agno-MCP-Platform` → `probata` + memory dir + parent gitlink + memsearch collection~~ **DONE 2026-09-06, see §9** | ~~BLOCKED by open handles (this session, the ingest session, a pwsh window): Windows refuses the rename while any process has the dir as cwd. `modules/Legal-Workspace` → `modules/advocatio` DONE (junction at old name). `modules/traceIQ` → `vestigia` and the repo dir + memory dir are done by `finish_rename_dirs.ps1` (scratchpad) once all sessions are closed; it also aliases the parent routers, commits both repos, and reindexes memsearch under the new collection name~~ |

## 9. Directory rename — DONE 2026-09-06 ~15:45 EDT (owner ran `finish_rename_dirs.ps1` three times; the script left defects that were then fixed by hand, one read at a time)

> _Byline: Claude Code · Fable 5.1 · 2026-09-06._

Verified directly with `Get-Item` / `git ls-files -s` / `git log` / `memsearch search` after the runs (no script):

| Item | State |
|---|---|
| `E:\AI_Workspace\Projects\the-platform-workspace\probata` | real directory (was `Agno-MCP-Platform`) |
| `…\the-platform-workspace\Agno-MCP-Platform` | junction → `probata` |
| `probata\modules\vestigia` / `probata\modules\advocatio` | real directories |
| `probata\modules\traceIQ` / `probata\modules\Legal-Workspace` | junctions → the new dirs (targets spelled through the old outer path; resolve via the outer junction) |
| `%USERPROFILE%\.claude\projects\E--…-probata` | real dir; the `…-Agno-MCP-Platform` name is a junction to it |
| probata `main` | `25f1ce3` pushed to `Cursedpotential/probata` |
| workspace `master` | commits `8514f089` + `08f98a66` from the script runs, plus the fix commit below; pushed to `origin/master` (the script pushed `main`, which does not exist on that repo) |
| memsearch | ~~pin `.memsearch/collection` = `ms_agno_mcp_platform_9e350219`~~ **replaced 2026-09-06 ~16:55 by `ms_probata_4ac6a58f`, see the follow-up sweep below**; `memsearch search "proffer rename probata"` returns the D-137..D-142 journal entry; result paths still show the old directory (index not rebuilt; junction resolves them) |

Defects the script produced, and the fixes:

1. **Workspace lost its product-repo gitlink.** Run 2 un-staged the old `Agno-MCP-Platform` gitlink, but the `git add …/probata` was refused because the parent `.gitignore` still carried the `probata/` alias-ignore line the router script had added on 2026-09-06 morning. Fix: took that ignore block out (and a duplicated `Agno-MCP-Platform/` line), staged `Projects/the-platform-workspace/probata` → mode `160000` pinned at `25f1ce3`.
2. **Router text applied twice.** Runs 2 and 3 both ran the text substitutions, yielding `probata/ (formerly probata/ (formerly Agno-MCP-Platform/))` in five router files and a second, garbled byline note in all seven. Fix: collapsed to `probata/ (formerly Agno-MCP-Platform/)`, dropped the garbled byline, and replaced the "junction until the directory rename lands" phrasing with "directory rename landed 2026-09-06".
3. **Ignore lines tripled.** `the-platform-workspace/.gitignore` (`probata/data|tmp|.data`) and `probata/.gitignore` (`modules/advocatio/`, `modules/vestigia/`) got one copy per run. Deduplicated.
4. **Push to the wrong branch.** Workspace repo's branch is `master`; the script pushed `main`. Pushed `master` by hand.

~~Still open from this section: the memsearch collection name still encodes the old directory (renaming the Milvus collection is handoff 07's call); the two nested junction targets are spelled through `…\Agno-MCP-Platform\modules\…` and will break if the outer junction is retired after 2026-09-13 — re-point them to `…\probata\modules\…` before that.~~

**Follow-up sweep 2026-09-06 ~16:10 EDT (Claude Code · Fable 5.1), all by hand:**

| Item | Done |
|---|---|
| Nested junctions `modules/Legal-Workspace` and `modules/traceIQ` | re-pointed to `…\probata\modules\advocatio` / `…\probata\modules\vestigia` (verified with `dir /al`); the outer `Agno-MCP-Platform` junction can now be retired without breaking them |
| `AGENTS.md` vestigia row | "lands with the directory-rename step" → "rename landed 2026-09-06" |
| `scripts/rename_routers_2026_09_06.py`, `scripts/rename_siblings_2026_09_06.py` | marked PROVENANCE ONLY / already run; `REPO` and vestigia `dir` now name the real `probata` / `vestigia` directories; the sibling note text updated to "landed 2026-09-06" |
| vestigia repo (`modules/vestigia`) | the same stale sentence in its naming note fixed in 248 annotated files (32 tracked); commit `e1a4acd` pushed to `Cursedpotential/TraceIQ` main |
| Claude memory index `MEMORY.md` (probata store) | project pointer aliased: **Indicia Probata / probata** (formerly Agno MCP Platform); old path noted as the junction |
| Guardian rule `guardian-naming-Agno-MCP-Platform-scripts.md` (repo `.claude/rules/` and `~/.claude/rules/`, untracked) | replaced by `guardian-naming-probata-scripts.md` with the old path kept as "(formerly …)"; old file kept beside it with a `.superseded-20260906` suffix |

~~Still open: the memsearch collection name (`ms_agno_mcp_platform_9e350219`) still encodes the old directory — handoff 07's call, not changed here.~~ **Owner ruling 2026-09-06 16:49: the "never drop a collection before proving the replacement" rule is for platform knowledge, not memsearch journals — do it.** Done ~16:55: new collection `ms_probata_4ac6a58f` (name = `ms_probata_` + first 8 hex of sha256 of the lower-cased checkout path) indexed from `.memsearch/memory` (58 files, 3,421 chunks; the old collection's 4,106 included stale chunks from files re-edited since), same embedder `nvidia/nemotron-3-embed-1b`; search for "proffer rename probata D-137" returns the D-137..D-142 journal entry with `…\probata\…` source paths; `.memsearch/collection` pin switched; old collection dropped with `memsearch reset` and confirmed gone (stats → collection not found). The two stray collections named in handoff 07 (`…_nemotron3_d2048`, `agent_session_memory_nemotron3` = the live global journal) were NOT touched. **Superseded 18:15 by the owner's ONE-collection ruling:** `agent_session_memory_nemotron3` now holds all 8 journal directories on this machine (7,275 chunks), every project's `.memsearch/collection` pins it, and `ms_probata_4ac6a58f` + `…_d2048` were dropped after cross-project search was verified.

## 10. Primary data extracted into `platform` — 2026-09-06 18:57 EDT (Claude Code · Fable 5.1)

Owner rulings 18:51–18:57: no migration and no rehearsal for a database that holds no evidence (rebuild from the snapshot instead); "reference stays. period."; the ontology / best-interest-factor / reference set is primary data and must be extracted and written into `platform`; reference tables are never foreign-key-bound to operational tables ("that's why the migrations become needed"); "it's all primary data. EXPORT IT AS SUCH."

| Step | Result (verified by count after each step) |
|---|---|
| Located the precious set | NOT in `platform` (its `reference.*` was an empty shell, no ontology table). It is in the `casebible` database on the same instance, column-identical tables. |
| Removed the one FK from `reference.*` to an operational table | `reference.detection_pattern_set → ops.processing_run` gone; FKs leaving `reference.*` now 0 |
| Loaded into `platform` in one transaction (from `pg_dump` of casebible) | `reference.custody_factor` 12 · `behavior_category` 164 · `behavior_category_mcl` 225 · `detection_pattern` 527 · `detection_pattern_set` 1 · `pattern_lexicon` 51 · `topic_code` 10 · `claim_type` 11 (already there) · `analysis.human_label` 1,918 · `human_label_gold` 1,918 · `media.photos` 7,121 · `faces` 6,911 · `faces_scanned` 7,121 · `screenshots` 3,113 · `enrichment` 15,252 · `knowledge.*` 28. New schemas `media`, `knowledge` created in `platform`. |
| Exported as primary data | `/data/agno/backups/primary-data-20260906/` on ovh-files: 26 per-table CSVs (header row), per-schema schema+data SQL for `reference`, `media`, `knowledge`, `analysis.human_label*`, `SHA256SUMS`, README. Contains real names/lexicon values: vault tier only, never git. The raw load file is beside it as `precious-20260906.sql` (117 MB). |
| `casebible` database | untouched; remains the source of record until its role is ruled (consignatio, D-141) |

Not done here: an R2 copy of the export (billable; dry-run + owner sign-off first).

## 11. Simplest wins — 2026-09-06 19:03–19:20 EDT (Claude Code · Fable 5.1)

Owner 19:04–19:14: no dual execution until really live; simplest/fastest approach wins; "why not just delete the table and recreate it"; "you're in bypass mode so get rid of it" (the hook).

| Step | Result |
|---|---|
| Snapshot rebuild attempt 19:08 | FAILED at line 5151: my edit step dropped `CREATE TABLE ai.agno_approvals` (substring match on `agno_app`). `platform` was left half-built. |
| Recovery 19:13 | Restored the 19:03 safety dump (`platform-pre-rebuild-20260906.dump`) into `platform_restore`, swapped database names, dropped the half-built one. 276 tables, reference data intact (custody_factor 12, media.photos 7,121). |
| `uiw_*` → `proffer_*` | 9 `ALTER TABLE … RENAME`; 0 `uiw_*` tables remain (constraint/index names keep the old prefix; cosmetic). |
| `analysis.human_label*` → `reference.*` | 2 `ALTER TABLE … SET SCHEMA`; 1,918 + 1,918 rows. |
| `agno_app` | `DROP OWNED BY` in every database on the instance, then `DROP ROLE`; 0 rows in `pg_roles`. Its last consumer, Coolify app `temporal-worker` (Python `evidence-pipeline` worker), stopped. |
| Hook | `.claude/hooks/db_write_gate.py` (local, gitignored; registered in `.claude/settings.json`) no longer denies DROP DATABASE / DROP SCHEMA / TRUNCATE CASCADE. |
| Code | probata `main` pushed at `5f1c4f9`: Go store/tests/scripts use `proffer_*`; 0073 parked under `sql/parked/` as superseded; snapshot + rebuild script kept as provenance. Coolify redeploys `proffer-worker`, `proffer-starter`, `parser-activity-runtime`, `tool-gateway` on that push. |
| Directory junctions | all four removed 19:16 (`Agno-MCP-Platform`, `modules/traceIQ`, `modules/Legal-Workspace`, the Claude memory dir alias). Workspace `.gitignore` alias line removed; `master` at `36b6807c`. |

Left on the instance, owner's call: `platform_preburn_20260830`, `platform_baseline_test` (old rehearsal DBs), `uiw-pg18-rehearsal-20260830` Coolify database.

**Post-deploy fixes 19:25–19:40 (same session).** The rebuilt `proffer-worker` crash-looped on its schema-admission gate (`modules/engine/postgres/proffer_schema_probe.go:274`): (1) the restored database was owned by `ai`, the gate requires `platform_admin` → `ALTER DATABASE platform OWNER TO platform_admin`; (2) the gate also checks constraint names by their new `proffer_*` spelling → every `uiw_*` constraint and index renamed in one DO block; 0 `uiw`-named objects remain anywhere in `platform`. Worker started on `proffer-v1` at 00:17 UTC; `parser-activity-runtime` and `tool-gateway` redeployed healthy; `proffer-starter` still on the 14:35 build (its redeploy was queued, not yet run). The push did trigger webhook deploys; my API trigger doubled them, harmless. `.claude/settings.local.json` still carries historical one-shot permission entries with the old scratchpad path; they are inert allow-list lines and belong to handoff 02 (owner's settings file).