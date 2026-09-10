# HANDOFF — cloud services: Tailscale Services, OpenList drives, devbox v2 (2026-09-10)

> _Byline: Claude Code · Opus 5 (1M) · 2026-09-10 — covers session 42902756 work of 2026-09-08 (written by Fable 5.1 turns), state re-verified live 2026-09-10 06:40 EDT; memory section added 06:55 EDT_

STATUS: PARTIAL
BUILD_STATUS: FAIL — devbox v2 image has never built successfully (6 failed Coolify builds); the running devbox is the 2026-09-08 morning image.

## Verified-live state (do not re-derive)

Re-checked 2026-09-10 06:40 EDT unless marked otherwise.

| Thing | State |
|---|---|
| Repo | Moved to `E:\AI_Workspace\Projects\Propria\Probata\probata` (git root). HEAD `b560f2e`. |
| Tailscale Services | 10 on ovh-files, 10 on ovh-app, all `https://<name>.tilapia-skilift.ts.net`, tailnet-only. Sample re-probed today: files 200, opencode 401, contextforge 303, portkey 200, workbench 200, desk 401. Full 20/20 probe passed 2026-09-08 14:05. |
| Services list | ovh-files: files, opencode, surreal, neo4j, temporal, weaviate, infisical, n8n, llm-probe, llm-probe-ui. ovh-app: contextforge, portkey, coolify-mcp, homepage, legal, legal-api, platform-api, platform-tools, desk, workbench. |
| Tailscale sidecars | Removed from opencode-server + openlist (commit `8cb06d1`); machines `files`/`opencode` deleted from the tailnet. Devbox sidecar still running (its compose change is staged, not deployed). |
| opencode-server | Runs `opencode web` (UI + API) with inline entrypoint. 401 without auth, 200 with password, `/doc` 200 (verified 2026-09-08 13:29). |
| OpenList | 14 storages incl. desktop over SMB (`/desktop/platform-workspace`), 4 Google Drives, 1 OneDrive. `msalem` full-permission user. Old WebDAV storage disabled, not deleted. |
| Google Drive | Tokens minted with the owner's custom OAuth client for matt.salemnet, matt.salem85, salemnma, caminstaller85. OpenList `/gdrive/<acct>` + rclone remotes `gd_salemnet`, `gd_salem85`, `gd_salemnma`, `gd_caminstaller85`. Old `gd_net_rw` removed (backup `rclone.conf.bak-20260908-130736`). |
| OneDrive | Personal mattsalem85, rclone default client, OpenList `/onedrive/mattsalem85` (online refresh API off). |
| Desktop WebDAV | Scheduled task `desktop-webdav` disabled, processes stopped, port 8087 closed. |
| Devbox container | `devbox-pd3xc78ahqkfswq12bpfqgy1-…` up 44 h, image built 2026-09-08 14:47Z, runs as kasm-user, persist-subset mount. Kasm :6901 answers 401. |
| Devbox fixes | `deploy/devbox.yaml` + `deploy/docker/devbox/Dockerfile` modified in the working tree, NOT COMMITTED, NOT DEPLOYED. (Staged at 06:40; by 07:00 the shared index had been reset by another session, so re-stage by explicit path before committing.) |
| Auto-memory store | MOVED 2026-09-10 06:50: `~/.claude/projects/E--AI-Workspace-Projects-the-platform-workspace-probata/memory` (191 memories, old path no longer on disk) → `E--AI-Workspace-Projects-Propria-Probata/memory`, the store sessions started in `Propria\Probata` load. Manifest 193 files / 633,355 bytes, copy verified path+size identical; original kept at the old slug's `stale/memory-moved-to-Propria-Probata-20260910`, pointer `MOVED.md` beside it. Sessions started inside `Probata\probata` would use slug `…-Propria-Probata-probata`, which has no store. |
| Superpowers hooks | Off. All 6 superpowers plugins `false` in enabledPlugins; no settings or project settings wire a superpowers hook; `superpowers-chrome` not enabled and has no hooks.json; `~/.claude/hooks/polyglot-wrapper/run-hook.cmd` only borrows superpowers' cmd/bash trick. Resume SessionStart 2026-09-10 injected no superpowers text. Owner order 06:31 satisfied, no change needed. |

## Findings / work done

1. **Tailscale Services need three steps, not one.** Register the service (`PUT /api/v2/tailnet/-/vip-services/svc:<name>`), advertise from the host (`tailscale serve --service=svc:<name> --https=443 http://<BIND_IP>:<port>`), then approve the host (`POST /api/v2/tailnet/-/services/svc:<name>/device/<deviceId>/approved {"approved":true}`). Advertising alone shows nothing in the admin panel. autoApprovers did not approve hosts that advertised before the service existed. Recorded in memory `look-up-the-feature-before-building`.
2. **Coolify keeps no repo checkout beside the rendered compose.** Relative binds of repo files (`./deploy/x.json:/x`) become empty directories. Coolify's `content:` bind also did not write the file on 4.1.2. Use absolute host paths. Added to the coolify-write skill gotchas and `deploy_application` docstring; memory `coolify-no-repo-checkout-relative-binds-are-empty-dirs`.
3. **Devbox build failures, root causes.** Builds 1 to 6 failed on: missing `claude-rc.sh` copy; SurrealDB install path twice; `pinta` has no Noble package (dropped, GIMP kept); Homebrew under `su -` ran in dash. The real cause behind the path failures is that the Kasm base image bakes `ENV HOME=/home/kasm-user`, so every root installer wrote into the user home.
4. **Staged devbox fix (untested as a full build).** Dockerfile: `ENV HOME=/root` during build and back to `/home/kasm-user` before `USER 1000`; `zstd` added to the first apt layer; ollama step strict again (was `|| true`, which hid a zstd failure); Homebrew fetched then run as `sudo -u kasm-user -H env NONINTERACTIVE=1 HOME=/home/kasm-user /bin/bash`. The ollama and Homebrew steps passed in a scratch `kasmweb/core-ubuntu-noble:1.17.0` container on ovh-files (Homebrew 6.0.22). devbox.yaml: tailscale sidecar service removed.
5. **Planning docs committed** (`288591e`): `docs/planning/2026-09-08-TODO.md` (living list), `2026-09-08-cloud-services-phase-2-plan.md` (NOT approved), `2026-09-08-contextforge-federation-inventory.md` (ContextForge is empty despite ADR-0046; 40 MCP definitions → ~24 targets, 10 move / 8 stay / 6 drop; ingress recommendation Cloudflare Tunnel + Access).
6. **Rules added** to global `~/.claude/CLAUDE.md` and memory: every turn runs model router, then sequential thinking, lists always, running TODO file; owner `msalem` admin on every service; look up a named feature before building; no curling non-doc sites; verify the user-facing URL, never deployment status.
7. **case-bible `cc_guard.py` hook** was removed by the owner on 2026-09-08 13:21 as too strict.

## Memory locations (read before resuming)

- **Canonical auto-memory:** `~/.claude/projects/E--AI-Workspace-Projects-Propria-Probata/memory/` (moved today, see table). Newest entries from this session: `look-up-the-feature-before-building` (Tailscale Services 3-step procedure), `coolify-no-repo-checkout-relative-binds-are-empty-dirs`, `running-todo-file-always-current`, `owner-admin-user-on-every-service`, `gateway-auth-and-subscriptions-next`, `discuss-before-building-not-after`.
- **Casebible store, newer rulings 2026-09-09:** `~/.claude/projects/e--AI-Workspace-casebible/memory/`. Binding for this work:
  - Fable never runs as a subagent; Opus is the ceiling; every Agent dispatch passes an explicit model (sonnet default, haiku for Smart Explore).
  - Search via `ccc` and DuckDB, grep sweeps are the fallback.
  - D-154/D-157/D-158: one shared agent memory for ALL agents on the VPS = SurrealDB Agent Memory `spectrond` (free self-hostable) in front of `surreal-case`; NIM for LLM+embeddings, Gemini allowed where spectrond fixes the embed model; all provider traffic through Portkey; never run local embedders on the desktop. Docs store stays local, embedded SurrealKV, no Docker. Never shut down Neo4j.
  - Budget 2026-09-09 07:03: owner at 10% weekly usage left; no new agents without need.
- **Parent-level plugin capture:** `E:\AI_Workspace\Projects\Propria\Probata\.claude\memories\project_memory.json` (claude-never-forgets realtime capture; held the 06:31 superpowers order).
- **`.remember`:** `Propria\Probata\.remember\today-2026-09-10.md` (session digest) and repo-level `probata\.remember\recent.md`.

## UNRESOLVED (mandatory)

- **Devbox v2 build 7 never started.** WHY: session ended right after the scratch-container test passed. APPROACH: commit the two staged files, deploy Coolify app `pd3xc78ahqkfswq12bpfqgy1` once, poll. SHORTCOMINGS: only the two failing steps were tested in isolation; later steps (launchers, chown, USER switch with the new HOME handling) are untested. A seventh failure is possible.
- **Devbox host prep for v2 not done.** Whole-home bind needs `/data/probata/volumes/devbox/home` seeded with `cp -an` from the new image, and `/data/probata/volumes/devbox/linuxbrew` seeded from the BUILT image before first boot, or `/home/linuxbrew` mounts empty and brew disappears.
- **svc:kasm and svc:syncthing** not advertised. They are in autoApprovers already. Do after the devbox redeploy; Kasm upstream is `https+insecure://100.91.190.107:6901`, Syncthing `http://100.91.190.107:8384`. Delete the `kasm` sidecar machine from the tailnet first if it exists.
- **Host `tailscale serve` config persistence across reboots** not verified. Serve config normally persists in tailscaled state, but no reboot test was done.
- **Devbox verification table** (root, whole-home mount, apt install survives restart, tool versions, Kasm/xrdp/Syncthing/glances, `claude --remote-control` flag) has not been run.
- **Relative-bind audit:** `deploy/compose.yaml` still binds `./sql/bootstrap/schema_snapshot_20260907.sql` and `./docker/graphiti/config.yaml`. Not checked whether that stack is Coolify-rendered.
- **Phase-2 plan not approved** by the owner. Nothing from P1–P8 has started.
- **Memory for sessions started inside `Probata\probata`:** that cwd maps to slug `E--AI-Workspace-Projects-Propria-Probata-probata`, which has no store. WHY open: aliasing is ruled out (no-dual-execution 2026-09-06). Owner to decide the one working directory sessions start from; today that is `Propria\Probata`.
- **Coolify status drift:** Coolify reported opencode-server exited / openlist restarting while containers were healthy. Not investigated.

## Pending owner decisions

- **Approve the phase-2 plan (per phase is fine).** WHAT: say go per phase. WHY: Filestash, Grafana stack, Portkey key front, ContextForge upgrade/auth, federation and cloud ingress all wait on it. Recommendation: approve P1 (Filestash) and P2 (Grafana + Loki + Mimir + Tempo + OTel on ovh-files, Coolify Log Drains per app) first; they are independent of the gateway work.
- **Portkey tokens: per-consumer vs one shared.** WHY: sets the shape of the nginx front in P3. Options: per-consumer tokens (revocable per client, a little more config) or one token (simplest, no isolation). Recommendation: per-consumer.
- **Aperture vs Portkey.** WHAT: decide whether to evaluate Tailscale Aperture as the gateway. WHY: it covers identity-based access, key vault, quotas, request logs and MCP connectors in one product, overlapping P3/P5/P6. SHORTCOMINGS: beta; hosting model and pricing not stated in the docs read; if hosted, keys leave our box (owner ruled against that for Portkey cloud). Portkey is canon under ADR-0042, so switching is a ruling. Recommendation: stay on Portkey unless the owner wants the hosting/price answered first.
- **Cloud MCP ingress:** Cloudflare Tunnel + Access recommended by the inventory; needs two hands-on checks (ContextForge 1.0.10 inbound auth; how an Access token satisfies ContextForge's bearer check).

## Next steps (work in order)

1. From the repo root, review `git diff -- deploy/devbox.yaml deploy/docker/devbox/Dockerfile`, then stage and commit `deploy/devbox.yaml` and `deploy/docker/devbox/Dockerfile` by explicit path and push.
2. Seed `/data/probata/volumes/devbox/home` on ovh-files with `cp -an` from `kasmweb/core-ubuntu-noble:1.17.0`'s `/home/kasm-user`, chown 1000:1000.
3. Deploy devbox once; poll `get_deployment` to finished or failed. On failure, read the last log lines and fix only that step.
4. After a green build, seed `/data/probata/volumes/devbox/linuxbrew` from `probata-devbox:latest` `/home/linuxbrew`, chown 1000:1000, restart the devbox container through Coolify.
5. Run the devbox verification table from the plan file `C:\Users\matts\.claude\plans\rosy-wibbling-cosmos.md` and record PASS/FAIL per row in the TODO.
6. Register/advertise/approve `svc:kasm` and `svc:syncthing` on ovh-files; load both hostnames from the desktop.
7. Update `docs/planning/2026-09-08-TODO.md` items 17/18 and the devbox line in the same turn.
8. Ask the owner for the phase-2 approvals listed above.

## Owner working-style contract

- Every turn: model router, sequential thinking, lists, running TODO file updated the same turn.
- Answer questions directly before proposing or doing anything; do not act while the owner is still asking.
- Look up a named feature (its skill, its docs, the repo) before building; never hand-roll a replacement.
- Verify by loading the user-facing URL; say "deployed, not yet verified" until then.
- Confirm before changes; never hard-delete (quarantine); byline every artifact; `msalem` admin on every service.
