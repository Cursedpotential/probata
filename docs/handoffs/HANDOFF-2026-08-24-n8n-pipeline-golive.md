# HANDOFF — n8n classification pipeline: built, staged, one step from first run (2026-08-24)

> _Byline: Claude Code · Fable 5 · 2026-08-24 (late evening session)_
STATUS: PARTIAL
BUILD_STATUS: PASS (43/43 — temporal skeleton 38 + custody canon vectors 5, re-run at handoff; worker boot log verified listing ClassificationBatchPipeline)

Companions: `docs/plans/N8N-BUILDER-AGENT-GUIDE.md` (ALL owner rulings — read first),
`docs/runbooks/N8N-PIPELINE-GOLIVE-RUNBOOK.md` (the execution script for ANY model),
`docs/research/integration-audit-2026-08-24/` (6 audit lanes + discovery + extract + composed/),
`docs/CHANGE-ORDER.md` CH-20/CH-21, DECISION_LOG D-068.
Earlier same-day handoff `HANDOFF-2026-08-24-ingest-testing.md`: its "owner does first (Coolify)"
steps 1–3 are **DONE** (Temporal deployed, agno_app cutover executed) — see correction note there.

## Verified-live state (do not re-derive — all checked at handoff time)

| Thing | State |
|---|---|
| Temporal | server+UI live on ovh-files (7233/8233); namespace `default`, 30d retention; **P0 exit test PASSED** (worker killed mid-run, resumed from history) |
| temporal-worker | redeploy `jso4q5vg…` FINISHED; boot log verified: "worker running — workflows: ChatTranscriptIngest, P0DurabilityProbe, **ClassificationBatchPipeline**" on queue `evidence-pipeline`; envs staged: `N8N_BASE_URL`, `CLAUDE_OAUTH_TOKEN` (gated by `TOP_JUDGE_ENABLED=false`) |
| DB `ai` (PG18 ovh-files) | canonical, new shape. `analysis.chunk_classification` live (migration 0033, applied+verified). reference.* vocabulary intact (527/164/225/51/12/10/1). Stamps applied live: `working.context_record`=SUPERSEDED, `analysis.human_label_gold`=NON-CANONICAL ARCHIVE, database `ai_test_ingest`=OLD-SHAPE TEST CORPUS frozen |
| DB `casebible` | other session's consolidation DONE: 31 tables/117MB, 24 tables hash-verified copies (labels, reference vocab, context_record, old test evidence, June LLM run in `media.*`), provenance in `ops.migration_log`. **Copies only — nothing dropped from sources** |
| app role | exec-tier runs as `agno_app` (verified in-container); password in Coolify env `DB_PASS` (exec-tier + temporal-worker apps) — owner has it |
| n8n (2.36.6) | greenfield + credentials: `NVIDIA NIM`, `Weaviate (ovh2 :8081)`, `Claude OAuth (top judge — DISABLED…)` id `ipjJyMKYsZzqi6Vj`. Public API key in `~/.secrets/n8n-ovh2.env` (`N8N_API_URL`/`N8N_API_KEY`, **expires 2026-09-22**; MCP token ≠ API key). Reaches platform API/Temporal/Weaviate (probed) |
| Composed workflows | 5 validated JSONs + COMPOSE-REPORT + STAGE5-DEPLOY-CHECKLIST in `docs/research/integration-audit-2026-08-24/composed/` — **NOT yet imported into n8n** |
| Mounts | ovh-files: `/srv/ingest` + read-only rclone mount of `casebible-sorted` (systemd, AppArmor local override); temporal-worker container: `/data/ingest` rw + `/data/r2-sorted` ro VERIFIED. agentos (ovh-app): `/data/ingest` verified writable; `/data/r2-sorted` via rclone docker-volume plugin returned EMPTY listing — UNVERIFIED |
| npm catalog | 5,905 packages: JSONL+md committed; DuckDB at `.duckdb/npm-community-nodes.duckdb`; tools `scripts/npm-catalog {search,stats,fresh,rescan}`; rescan rule in `.duckdb/AGENTS.md` (30-day staleness) |
| Workspace agent | `repo-consolidator` skill+agent+ledger at `E:/AI_Workspace/.claude/` (NOT user scope; own-ledger memory only). Ancestor pickup from child repos NOT yet verified in a fresh session |

## Findings / work done (this session, compressed)

- **D-068 ruled and recorded** (DECISION_LOG): n8n = agent/integration layer; Temporal = durable spine; custody path stays in-code; THE WRAP IS THE ACTIVITY BOUNDARY; promotion stays behind the PG gate; strategic rationale = sister-project merge via thin adapters.
- **Owner-methodology builder pipeline executed S1→S5**: decompose → Interview A → discover (7 shapes, verified candidates; sourcing order native>npm>github; community-check standing rule born after owner's 300-tab npm sample out-discovered the agents) → Interview B (adds: Summarization Chain, Sentiment Analysis, **Auto-fixing Output Parser**, Sort node; roundrobin+claude-cli to verify) → extract (roundrobin = FALSE LEAD (persona storage); claude-cli REJECTED → **direct API/staged-token top judge**; semantic-splitter upstream dead → **chonkie-behind-platform-endpoint** wins chunking upgrade) → compose (5 small workflows; auto-fix wired via error-output retry chain since 2.36.6 can't nest it under Information Extractor) → Stage-5 injection: `server/temporal/n8n_activities.py` + `classification_workflow.py` (small batches; low-confidence→`unreviewed` NEVER flags; classifier_version on every draft; HITL Signal gate notify-forever; abort supported).
- **Key rulings tonight** (all in the guide): rate-limits-not-cost (Portkey caps; but FOR NOW "do it all in code inside n8n, copy the pattern to Portkey later"); model pool = NIM/Ollama≤3/Gemini×4/OpenRouter-free; classification EXPECTED TO SUCK AT FIRST (iterate on versioned drafts); temporal-awareness mandate (every query carries a time window; time assertions with relative anchors for extracted events); realization events attach at the EXTRACTED layer, third-party ingest is the dominant realization source; multi-query expansion joins the 4-mode search requirement (fusion + per-variant provenance).
- **June 2026 LLM run recovered** (other session): 15,252 enrichment + 3,113 screenshot classifications with per-row model/conf/latency in `casebible.media.*` — a real PRIOR for pool weights (granite-4.1-8b fast/0.741; gemini-3-flash 0.948; mistral-small 0.962). No accuracy ground truth exists (labels proven never-entered, 6 artifacts).

## UNRESOLVED (mandatory)

- **Workflows not imported into n8n** — the one substantive step between here and the first run. Runbook step 1–2 is the exact procedure; blocked only by minutes, not decisions (except the Postgres credential below).
- **Postgres n8n credential needs the password pasted** (owner has it; value lives in Coolify env only — correct).
- **First smoke batch not run** — `scripts/run_classification_batch.py --limit 10` after import; owner wants to SEE it.
- **agentos `/data/r2-sorted` empty listing** — rclone docker-volume plugin mount unverified on ovh-app; check `docker volume ls`/plugin config there. Worker-side mount works, so ingest testing is NOT blocked.
- **Intake workflow (wf-intake-dropdir) deliberately NOT imported** — needs n8n container bind-mount + Local File Trigger enablement (env) — owner-gated deploy change.
- **Epoch mirror fields** on native Weaviate collections before EvidenceChunkV1 backfill (URGENT-TODO; design already carries `source_available_from_epoch` — verify `occurred_at` twin).
- **Ancestor skill/agent pickup** (E:/AI_Workspace/.claude) unverified from a fresh child-repo session; fallback = thin per-repo shim, NEVER user scope (owner ruling).
- Housekeeping: 5 hook-protected `to_be_deleted/` deletions (human-only); stash `wf-registry-wip`; queue-name cosmetic (`evidence-ingest` unused constant) + duplicate `ChatTranscriptInput` class name.

## Pending owner decisions

- **Drops from `ai`/`ai_test_ingest` after consolidation** (other session's lane): copies verified, sources intact; `behavior_category.is_enabled` is a live kill-switch comment — reader check before ANY drop.
- **Fleet cleanup triage** (both OVH boxes — queued in URGENT-TODO, untouched tonight).
- **Tests/evals/build duplicate-folder consolidation** — seeded in the repo-consolidator agent's ledger; inventory-first.
- **Arming the top judge** — one env/credential flip; owner: "let's see how the agents do on their own" first.

## SAFE ITEMS — a master agent can start these WITHOUT owner input (all reversible, all in-guardrails)

1. **Import the 4 workflows** (classify/judge/persist/error — NOT intake) per runbook steps 1–2; skip the Postgres credential node config if the password isn't pasted yet; verify webhook paths `classify-batch`/`judge-gate`/`persist-results`; wire errorWorkflow settings.
2. **Verify the agentos r2-sorted mount** (read-only inspection on ovh-app: plugin volume state, one `ls` in-container) and record the finding.
3. **Dry-run the smoke script up to the Temporal submit** (`fetch_examples` + payload print without starting a workflow) to prove DB read path; full run once the Postgres credential exists.
4. **Doc-sync pass**: fold tonight's rulings into `docs/INDEX.md`/`CONVENTIONS.md` where stale; verify no doc still claims Temporal is pending-deploy (grep "not live"/"pending" against Temporal claims).
5. **npm-catalog maintenance**: `scripts/npm-catalog fresh`; sample-verify 5 shortlist packages' registry metadata; fix any loader schema drift.
6. **Read-only duplicate-folder INVENTORY** (tests/evals/build across workspace repos) into the repo-consolidator ledger — inventory only, zero moves.
7. **Compose-file reference sweep**: verify nothing else references the moved surreal compose root paths (grep configs + Coolify apps' compose locations via API, read-only).
8. **Write the promotion status-flip design note** (lane-4 finding: endpoint exists, nothing flips status) — design doc only, no code.

## Next steps (work in order)

1. Safe item 1 (import) → owner pastes Postgres password → smoke run (`--limit 10`) watched in Temporal UI (100.91.190.107:8233) with owner.
2. Review drafts together → purge by run_key → iterate prompts/threshold as `clf-v1` (small batches rule).
3. Intake trigger deploy change (owner-gated) → drop-dir → custody-door flow live.
4. Then the queued backlog: canon-registry migration, promotion quiet-columns, epoch fields, run-ledger fold (per `HANDOFF-2026-08-24-ingest-testing.md`).

## Owner working-style contract

- Answer-first, bullets, white space, plain English (never bare ID codes). Hyperfocus flow permanent.
- Sprint mode: ship smallest increment, verify LIVE; small batches with review between; stop only for destructive/outward/irreversible-spend.
- Never hard-delete (quarantine); byline every artifact; update EVERY stale doc same turn; community-check before finalizing anything; test data never becomes canonical (purge after review).

---

> _Note added 2026-08-25 by Claude Code · Fable 5: the LIVE-ONLY / grounded-mode testing policy referenced above was REMOVED by owner order ("you're grounded — remove it entirely"). Text above is historical record, left intact per the doc-drift rule; it no longer reflects active policy. Confirm-and-discuss-before-changing is back in force._
