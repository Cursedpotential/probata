# HANDOFF — Gap-report remainder + start of ingest testing (2026-08-24)

> _Byline: Claude Code · Fable 5 · 2026-08-24_
STATUS: PARTIAL
BUILD_STATUS: PASS (custody canon vectors 5/5 + Temporal skeleton 38/38 = 43/43, re-run at handoff time; full suite not re-run tonight)

Companion docs (this handoff supersedes neither — it indexes what's LEFT):
- The gap report itself: `docs/reviews/2026-08-23-cross-repo-evidence-audit/ISSUES-AND-TODO.md`
- The ingest runbook (how to actually run it): `docs/INGESTION-READINESS-2026-08-23.md`
- Tonight's change ledger: `docs/CHANGE-ORDER.md` CH-15 through CH-18

---

## Verified-live state (do not re-derive)

| Thing | State |
|---|---|
| Migrations 0026–0031 | ALL applied to prod (`100.91.190.107:5432` db `ai`), headers stamped. 0031 = dev-mode immutability gate. |
| Immutability | OFF everywhere until go-live. One switch arms it all: `ALTER DATABASE ai SET app.evidence_live = 'on';` |
| Evidence schema | TRUE ZERO — 28 test-residue rows purged 2026-08-24 (evidence.source / evidence_hash / custody_event / spine all empty, verified). |
| Prompt-example set | ~~1,918 labeled rows~~ **Corrected 2026-08-24 (later the same night):** 1,918 rows in `analysis.human_label`, message TEXT present on every row, label fields currently EMPTY (labeling pass still to be done — "golden example later"). Table is deliberately UNLINKED from live tables (linking broke every test) and was STRIPPED to message+label essentials by migration 0032 (applied+verified). Full-fidelity pre-strip archive: `analysis.human_label_gold`. Second durable copy: `OneDrive/AI Space/exports/human-label-examples-2026-08-24.jsonl` (kept out of git — real message content). **This table is DONE — no re-linking, ever.** |
| Hash recipes for ALL future ingest | Persisted in triplicate: `docs/reference/CUSTODY-HASH-CANON.md` + `tests/test_custody_canon_vectors.py` (5/5) + live `public.canon_registry`. Pushed at `1a30f51`. |
| DB roles | `agno_app` (non-superuser app role) and `temporal` created live. Databases `temporal` + `temporal_visibility` created. Passwords printed ONCE to owner's terminal — in NO file. |
| Temporal code | ~~P0/P1 scaffolds committed & INERT … Nothing deployed.~~ **Corrected later 2026-08-24: DEPLOYED AND LIVE** — server+UI+worker on ovh-files, P0 exit test passed; see `HANDOFF-2026-08-24-n8n-pipeline-golive.md`. |
| Services (probed 08-23) | AgentOS API UP · Weaviate UP · Neo4j UP · workbench 401 + stale build. Milvus deliberately DOWN (owner order, do not restart). |
| Repos | All three clean & pushed. Worktree PR: https://github.com/Cursedpotential/ai-workspace/pull/3 (CodeRabbit reviewing). |
| Context lane code path | Chat ingest writes `working.chat_conversation/chat_message/chat_chunk` (since commit `5ea3ede`, 08-13). The old `context_record` table (1,741 rows) is STRANDED — ruled: re-ingest from originals, don't migrate. |

---

## What "begin ingest testing" needs — in order

Everything below is from the runbook (`docs/INGESTION-READINESS-2026-08-23.md`); this is the sequence.

**Owner does first (Coolify, out-of-band — nothing else is blocked on it except step 4+):**
~~(steps 1–3 below)~~ **DONE 2026-08-24 evening session** — Temporal stack deployed (P0 exit test
passed), agno_app cutover executed and verified. See `HANDOFF-2026-08-24-n8n-pipeline-golive.md`.

1. Paste the two role passwords (agno_app, temporal) from terminal scrollback into Coolify env storage.
2. Deploy the Temporal stack (server + UI + worker) from `deploy/temporal/compose.temporal.yaml`.
3. App-role cutover: set `DB_USER`/`DB_PASS` to agno_app in Coolify + redeploy — stops the app running as superuser.

**Then the actual first ingest (agent-runnable, no Temporal required):**

4. Path A (preferred): `docker exec` into the AgentOS container, run `scripts/ingest_context_chat.py` against ONE chat export ZIP → lands in the CONTEXT lane (knowledge, not evidence — safe by design).
5. Verify with the runbook's SQL — it targets the chat model tables (`working.chat_*`), corrected at `024cd05`. Do NOT check `context_record`; nothing writes there anymore.
6. On success: purge the test rows (standing rule — test data never becomes canonical). The dev gate makes deletion possible; the purge script pattern is proven (CH-18).
7. Temporal P0 exit test (after step 2): start a workflow, kill the worker mid-run, watch it resume. That's the entire point of Temporal — prove it.

**Then the real corpus:**

8. Re-ingest the 1,741 stranded context conversations from their ORIGINAL export ZIPs through the new lane (owner ruling: originals, not table migration). Every message gets recomputable hashes under the current canon.
9. Stamp the old `context_record` table superseded; fix the two drain scripts whose docstrings still describe the old lane (`context_drain.py`, `drain_context.py`).
10. ~~Re-link the 1,918 human labels to the re-ingested messages~~ **STRUCK 2026-08-24 (owner ruling, same night):** the label table is UNLINKED by design — linking it caused problems in every test. It is a self-contained example set (message text + label in the same row) for few-shot prompting; stripped to essentials by 0032 and DONE. No re-linking task exists. The remaining work on it is the labeling pass itself, owner-driven, later.

---

## UNRESOLVED — gap-report items still open (plain English, codes in parens)

**Queued behind ingest (do after step 10):**

- **Make the canon registry reproducible by migration** — the recipe table exists live but no numbered migration creates it; write migration 0032 capturing it (CH-18 follow-up).
- **Default the quiet promotion columns** — matter/court-case columns on the promotion table should auto-fill from the single existing partition row instead of demanding input (owner ruled "quiet", conformance Q1).
- **Fold the two run ledgers into one** — `ops.processing_run` (empty, 35 foreign keys) folds into `ops.workflow_run*` at the Temporal cutover (conformance Q2 ruling).
- **Standalone custody hasher** (TODO-207) — a subcommand of the existing SBV engine, callable by either the ingest OR the backup process, so hashing survives either one failing (owner's design). After it exists: make hashing mandatory-at-capture for the evidence lane.
- **Search must offer all four modes** (TODO-201) — full-text + fuzzy + semantic + hybrid (owner requirement 08-24). Postgres FTS switch needs a live verify + a "not court-safe" marker on fuzzy/semantic results.
- **Framework bake-off** — PydanticAI vs Agno-as-library, two identical implementations of the knowledge activity in `server/temporal/knowledge_harness/` (owner: "ok start"; harnesses committed, bake runs at Temporal P1).
- **Agent memory bake-off** (TODO-211) — graph-based + temporal + hybrid search, "all the features"; Cognee is the frontrunner (has the SQLite fast-index the owner remembered). Post-ingest, fleet-only deployment.
- **Bitemporal graph in Neo4j** (TODO-210) — apply occurred-at/learned-at edges to the Semantica-built graph. Post-ingest.

**Deferred by explicit owner order (do NOT start):**

- SMS behavioral analysis rework — over-flags everything; whole process reworked later.
- Change detection / walk rebuild (TODO-208) — "on a to-do list for later, not important right now".
- Google Takeout / Timeline integration — PARKED, owner emphatic ×2; never propose it.
- JWT rotation — owner: "no!".

**Owner-gated decisions still pending (see section below).**

**Housekeeping remainders:**

- 5 files staged as deletions under the quarantine folder are hook-protected — a HUMAN must run that commit (any Bash text naming that folder is blocked).
- Stash `wf-registry-wip` (10 lines in `server/api/main.py`) — land or discard.
- Legal-Workspace `Source zips/` is gitignored (98 MB file exceeded GitHub limits) — originals live on disk/R2 only.

## Pending owner decisions

- **Two naming systems for disclosure tiers** (TODO-213) — WHAT: consolidate the enum (`contemporaneous/hindsight/discovered` = WHEN knowable) vs the text column (`public/restricted/sealed` = WHO may see). WHY: an agent already misread one for the other in a published doc. Options: rename the access column (recommended) or document-only. Blocked on owner because it renames a live column.
- **Fleet-wide open-port audit** (gap report B9) — WHAT: sweep every box for services bound to 0.0.0.0 like Weaviate was. WHY: the Weaviate exposure was found by accident, not audit. Owner call on when.
- **AG2 multi-agent plan reconciliation** — the 08-15 research packet (R5) predates the Temporal ruling; needs a pass to mark what Temporal now owns (durability) vs what AG2 still owns (deliberation).

## Next steps (work in order)

1. Owner: Coolify passwords + Temporal stack deploy + app-role cutover (steps 1–3 above).
2. Agent: first chat-ZIP ingest via docker exec + SQL verify + purge (steps 4–6).
3. Agent: Temporal durability exit test (step 7).
4. Agent: re-ingest the 1,741-conversation context corpus from originals; supersede the old table (steps 8–9; step 10 struck — no label re-linking, ever).
5. Then work the "queued behind ingest" list top-to-bottom.

## Owner working-style contract

- Structured replies: bullets, labeled blocks, white space, answer-first. Plain English — never bare ID codes as subjects.
- Sprint mode: ship + verify live; still stop for destructive/outward-facing/irreversible-spend actions.
- Never hard-delete (quarantine); byline every artifact; verify before claiming done; update ALL stale docs in the same turn.

---

> _Note added 2026-08-25 by Claude Code · Fable 5: the LIVE-ONLY / grounded-mode testing policy referenced above was REMOVED by owner order ("you're grounded — remove it entirely"). Text above is historical record, left intact per the doc-drift rule; it no longer reflects active policy. Confirm-and-discuss-before-changing is back in force._
