# Briefing — the five open rename follow-ups, with live state

> _Byline: Claude Code · Fable 5.1 · 2026-09-06 17:45 EDT. Owner asked for "way more context and details" on handoffs 02, 03, 04, 05, 07. Every "live state" line below was read directly this hour, not from the prompt files._

---

## 02 — Restore the permission deny list

**What it is.** On 2026-09-04 you ruled: docs/plans/memory free, git writes ask, code/SQL/deploy/AGENTS **denied** until a named build lifts a path. For the rename build (2026-09-06 morning) the denies were lifted so the routers, `deploy/**`, `modules/**` could be edited.

**Live state (read `.claude/settings.local.json` 17:40).**

| Field | Now |
|---|---|
| `permissions.deny` | **empty** `[]` |
| `permissions.ask` | git writes + `Edit/Write` on `**/AGENTS.md`, `**/AGENT_MEMORY.md`, `compose.yaml`, `deploy/**`, `modules/**`, `server/**`, `sql/**` |
| `permissions.allow` | 220 one-shot entries (many with the old scratchpad path — inert) |
| `_build_lift.restored` | still the **2026-09-05** entry; the 2026-09-06 lift was never closed |

So the protected paths are at **ask**, not **deny**. Every agent session gets a prompt instead of a wall. Three entries from the ruling are missing entirely: `Edit(pyproject.toml)`, `Edit(requirements.txt)`, `Write(sql/**)`.

**Why still open.** It is your file, local, never pushed. The prompt file says only you or an explicitly authorized agent edits it.

**Risk if left.** An agent in a hurry answers "yes" to an ask prompt on `server/**` and the gate is gone. The deny wall is what made the 2026-09-04 ruling bite.

**Recommendation.** Move the 16 `Edit/Write` entries from `ask` to `deny`, add the three missing ones, keep git under `ask`, stamp `_build_lift.restored` with today. Five-minute edit. Naming gate stays at 0 hits either way.

**Needs from you:** one word — "restore" — and I do it, or you do it yourself.

---

## 03 — R2 dev fixtures at the proffer prefix

**What it is.** The Go runtime API (`modules/engine/runtimeapi/source_ref.go:23`) allows exactly one non-canonical R2 location for dev bypass: `r2://nexus/proffer/test-fixtures/`. The handoff assumed the objects were still under the old `uiw/` prefix and needed a server-side copy.

**Live state (rclone listing 17:41, read-only).**

| Prefix | Objects | Size | Contents |
|---|---|---|---|
| `nexus/uiw/test-fixtures/` | 1 | 3.66 MiB | `live-proof-20260827-sample_backup.xml` |
| `nexus/proffer/test-fixtures/` | 4 | 1.24 GiB | `first-real-runs/smsbackup/sms-20251206203434.xml` (1.33 GB), `calls-20260609173028.xml`, `imessage-18108532989/index.html`, `+18108532989.txt` |

The **code already points at proffer** and the **ingest session already put its four real-run files there**. Those four are your actual SMS, calls and iMessage exports — real PII, in a dev-fixture prefix, and the ingest handoff lists them as "4 nexus test copies, owner deletes when convenient".

**What actually remains.** One 3.66 MiB sample file to copy from `uiw/` to `proffer/`. Cost: one Class-A operation, fractions of a cent.

**Risk.** None on the copy. The real question is the 1.24 GiB of real exports sitting under a "test-fixtures" key: they are fixtures for the first-real-run proof, but they are also the first objects in `nexus` that carry your data. D-142 says fixture data is disposable, so the answer is either delete them after the run report lands, or accept the prefix as their home for now.

**Recommendation.** Copy the one sample file now (dry-run shown, then run, then `rclone check`). Leave the four real-run files alone until the ingest session's run report is in and you say delete. Do not delete the `uiw/` copy; that stays your call.

**Needs from you:** "copy the sample" (or not), and later a delete ruling on the four real-run files.

---

## 04 — Golden template database + teardown (D-142 §3)

**What it is.** Your proposal, accepted in D-142: stop purging rows; keep a template database (`probata_golden`) that holds schema + `reference.*` + `analysis.human_label*` + the Case Bible catalog, and re-create the working `platform` database FROM it whenever a design pass needs a clean slate. You assigned it to the ingest session because its full ingest test (hundreds of errors) was on hold pending the rename.

**Live state (read this hour).**

- Ingest handoff (`docs/HANDOFF-2026-09-06-ingest-rulings-and-parser-fix.md`): STATUS PARTIAL. Parser fix done 15:38 (uncommitted, SBV fork). A real-workflow run agent has been running since 15:40 on the 1.3 GB SMS export. Its next steps are the run report, an `agentos-db` redeploy you trigger, then the decode-subtree execution. **Golden clone is not on its list.**
- `sql/` has a hole: `0044`, `0045`, `0046` are missing (present: 0042, 0043, 0047…). The live role `agno_app` was created by hand with no migration file. A template rebuilt from `sql/` will not have it.
- Ten `context.uiw_preview_*` tables plus `context.uiw_source_context_revision` still carry the old lane name in their DDL; they rename to `proffer_*` only via a new migration.
- D-127 governs the feature flag: the flag skips our own gates, never the build. The teardown must be fully built and tested behind it.

**Why still open.** Nobody owns it yet. The ingest session is consumed by the first real run, and the golden template depends on the migration hole being ruled first (restore 0044–0046 as real files, or renumber and record the gap).

**Risk.** Two directions. Doing it without the migration fix produces a template missing a live role, so the first re-clone breaks every connection using `agno_app`. Not doing it means the next "clean slate" is another row purge, which is the exact thing D-142 called two weeks of bullshit.

**Recommendation.** Sequence: (1) rule the migration hole (this also closes round-5 #3 in the plan); (2) add the `uiw_* → proffer_*` rename migration; (3) build the template script and prove `CREATE DATABASE platform_scratch TEMPLATE probata_golden` on the live server; (4) teardown behind a flag, smoke suite after; (5) only then touch `platform`, with your explicit go. Give it to a fresh session, not the ingest one.

**Needs from you:** who owns it (new session or ingest session after its run report), and the migration-hole ruling: restore or renumber.

---

## 05 — The 18 identifier rulings (R-1..R-18)

**What it is.** The product rename settled names in docs and code identifiers that were cheap. Eighteen infrastructure identifiers were deliberately left for you because each one is a live change with its own failure mode. Two are already done (R-15 task queue, R-16 checkout directory). Sixteen remain. Grouped by what I recommend:

**Keep (no action, just a ruling so nobody re-opens it)**

| # | Identifier | Why keep |
|---|---|---|
| R-1 | docker network `agno` | 17 compose files, `traefik.docker.network=agno`. Recreating a network means re-attaching and redeploying every app; one missed app loses DNS to its peers. Highest blast radius on the list. Infrastructure, not a product surface. |
| R-2 | `/data/agno/` host root | ~60 bind mounts on two boxes. A `mv` with one mismatched mount starts a container on an empty volume and silently loses state. Invisible to users. |
| R-7 | PG database name | It is already `platform`. Nothing to do. |
| R-10 | `svc:workbench`, `svc:tool-gateway` | Component names, correct under the component rule. A Tailscale Service rename is a new identity: new VIP, ACLs, MagicDNS, every client URL. |
| R-12 | `platform-api` | Component name. Renaming breaks docker DNS for workbench until both redeploy, moves a secret path on the host, changes ~75 test assertions. |

**Retire (delete, do not rename)**

| # | Identifier | Live state | Risk |
|---|---|---|---|
| R-4 | `agentos.mitechconsult.com` | DNS resolves to `40.160.5.19`, returns 503; no Coolify app behind it. | Near zero. Confirm nothing external bookmarks it. |
| R-6 | `OS_SECURITY_KEY` | Zero occurrences in `server/**`; one comment in `compose.yaml:72`; two docs. | Near zero. Check no Coolify app still sets it. |
| R-13 | `unified-operator-surface` | Design mockup; no live Coolify app found. | Confirm nothing depends on host port 8020. |
| R-14 | `graphiti*`, `phase1-surreal*` | Three Coolify apps still `running` on ovh-files: `data-graphiti-case`, `data-graphiti-files`, `data-surreal-phase1-t0-r1`. Graphiti retired D-070. | `server/analysis/graphiti_case_client.py:32` still has a live default URL; retire the client default in the same change. Frees resources on ovh-files. |

**Rename, each as its own deliberate step**

| # | Identifier | Target | The failure mode to plan around |
|---|---|---|---|
| R-3 | `agentos-db` / `agentos-api` | `probata-db` / `probata-api` | `DB_ID="agentos-db"` at `server/core/session.py:70` is a **live agno registry key** injected into every route by `db_id_middleware.py`. Not cosmetic. Several scripts also assert on the literal string as a "compose-internal, unreachable from desktop" sentinel; renaming silently disables those guards. Change with a route smoke test. |
| R-5 | `AGENTOS_*` env names | `PROBATA_*` (or `PLATFORM_*` to match the majority prefix) | Coolify renders env values as literals at deploy. Reader code, writer, and the Coolify variable must change together, then every consuming app redeploys. |
| R-8 | PG role `agno_app` | `probata_app`; leave `platform_*` | `ALTER ROLE … RENAME` invalidates the password and breaks live connections. Maintenance window + coordinated redeploy. Ties to 04: the role has no migration file. |
| R-9 | `SURREALDB_NS="agno"` | `probata` **or** `indagatio` | A namespace rename is a data migration. Legacy Surreal is parked so risk is low today, but if the analysis engine splits out as indagatio (D-139) after you pick `probata`, it migrates twice. **Decide the target before the split.** |
| R-11 | `knowledge-workbench` (image, npm name, FastAPI title, container) | `workbench` | Coolify app already renamed; Traefik router already `workbench`. Container rename = one redeploy. Low risk. |
| R-17 | `ghcr.io/cursedpotential/agno-postgres` | `probata-postgres` | Two live Coolify databases pull it (`casebible-pg18`, `horizon-swift-scratch-pg`), one by digest. Publish under the new name, repoint, verify, deprecate. **Never delete the old package while a digest-pinned DB references it.** |
| R-18 | `knowledge/…/agno-mcp-platform-mvp-handoff-guide-v8.1.md` | rename the filename only | Zero infra risk. Pure question of whether a historical artifact's filename is part of the record. |

**Why still open.** Each one is a ruling, and half of them are live-infra changes I am not allowed to make without your explicit yes per item.

**Recommendation.** Rule the five keeps and four retires in one sitting (nine D-entries, no infra risk on the keeps, low on the retires). Then take the renames in this order: R-11 (trivial), R-18 (trivial), R-9 (decide the target only), R-5 + R-3 together in one Coolify redeploy window, R-8 with 04's maintenance window, R-17 last.

**Needs from you:** rulings. I will present them one screen at a time if you prefer, or take this table as the screen.

---

## 07 — Memory tooling: the one remaining decision

**What was fixed today (verified 17:35).** Recall skill reports hits from all eight sources (SETTLED, DECISION_LOG, .remember, native memory, cnf, sessions, ccc, memsearch). memsearch project collection is `ms_probata_4ac6a58f`, 3,421 chunks, pinned in `.memsearch/collection`; the old collection is dropped. ccc healthy.

**Live collection inventory (memsearch stats 17:43).**

| Collection | Chunks | What it is |
|---|---|---|
| `ms_probata_4ac6a58f` | 3,421 | **this repo's journals** (`.memsearch/memory`, 58 files) — the pin |
| `agent_session_memory_nemotron3` | 506 | **the global journal** (`~/.memsearch/memory`, 17 files); `~/.memsearch/config.toml` points here |
| `ms_agno_mcp_platform_9e350219_nemotron3_d2048` | 3,082 | stray: a 2026-09-03 rebuild attempt of the old project collection that crashed mid-way; superseded twice now |

**The decision.** memsearch has one default collection (global config) and one project collection (the pin). Today, `memsearch search` with no `-c` hits the global 506-chunk journal; the recall skill reads the pin and hits the project one. Question: should the global default BE the project collection?

- **Yes** means: every tool that calls bare `memsearch` (hooks, OpenCode, Codex) searches this repo's journals by default. Simpler, one place. But the global journal covers every project on this machine, not just probata, and other repos' pins would still diverge.
- **No** (keep two) means: the pin does the project routing, the global stays cross-project. This is what works right now.

**Recommendation.** Keep two. The pin mechanism is already what makes recall work, and it generalizes to advocatio and vestigia when they get their own journals. Drop the stray `…_nemotron3_d2048` (3,082 chunks; its sources are the same 58 files now indexed in the new collection, so nothing is lost). Do not touch `agent_session_memory_nemotron3`.

**Needs from you:** "keep two" or "make global = project", and a yes/no on dropping the stray.

---

## Summary of what I need from you

| # | One-line decision |
|---|---|
| 02 | "restore" the deny list (I do it, or you do) |
| 03 | copy the one 3.66 MiB sample to `proffer/`? and, later, delete the four real-run files? |
| 04 | who owns golden clone; migration hole 0044–0046: restore or renumber |
| 05 | rule the 5 keeps + 4 retires now; then the 7 renames in the order above |
| 07 | keep two collections (recommended) or merge; drop the stray `…_d2048`? |
