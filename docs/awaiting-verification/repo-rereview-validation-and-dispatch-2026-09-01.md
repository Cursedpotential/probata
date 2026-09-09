# Repo Re-Review Validation — Claim Verdicts + Corrected Dispatch Plan

> _Byline: Claude Code · Fable 5 · 2026-09-01._
> Validates the external Perplexity re-review ("Repo Re-Review — Consistency, Gap Closure, and Doc",
> Downloads, 2026-09-01) against the live repo, live GitHub Actions, the live `platform` database
> (read-only probes at 100.91.190.107), and conversational history (`.remember/`, session transcripts,
> DECISION_LOG). **Report-only — no fixes executed.** Owner rules on the decision queue in Part 3.

## Part 0 — Bottom line

The report is **substantially accurate on code and schema claims** (every named file, function, and
line-level claim verified) but **stale or wrong on operational state** (CI, role cutover, row counts)
and **imprecise on aggregates** (docs sizes/counts, content_hash count). Three of its recommendations
rest on false premises. Validation also surfaced **six new defects the report missed** (Part 4).

Verdict totals across ~70 checked claims: **~45 VERIFIED · ~15 PARTIAL · ~10 REFUTED/stale.**

## Part 1 — Verdicts on the report's load-bearing claims

### Gap register (Part 2 of the report)

| Gap | Claim | Verdict | Evidence |
|---|---|---|---|
| G-01 | CI red because SUBMODULE_TOKEN missing | **REFUTED (stale)** | Secret set 2026-09-01 18:56Z (`gh secret list`); Go engine job GREEN on run 33546664265. CI is still red — but from `scripts/validate.sh` traceability: stale `vendored/sbv`/`compose.yaml` citations in AGENTS.md + **unresolved D-072–D-080** + mypy `route.app` (fix uncommitted in worktree) |
| G-02 | 7 GAP-021 secrets unprovisioned | **VERIFIED** | Names confirmed in validate.yml L123-140; job fail-not-skip verified; never provisioned per GAP-021-IMPLEMENTATION-STATUS.md |
| G-03 | 27 pre-existing pytest failures | **VERIFIED (already triaged)** | Session log 2026-09-01 11:35; handoffs-v2 plan classifies them (ingest_port ×14, opencode_ops ×6, …) and already rules "H-02 must not gate on these initially" |
| G-04 | 0045 hole needs owner ruling | **VERIFIED — genuinely open** | Only `.broken-historical`/`.incoming-conflict` variants ever existed, quarantined out in `82258c6`; no ledger row (live-verified); test_0048 module-skips (`tests/test_0048_context_fingerprint_uiw_repair.py:12-22`); no prior owner ruling found in history |
| G-05 | `enqueue_evidence_vector_projection` targets dropped table | **VERIFIED live** | `pg_get_functiondef` shows `FROM working.normalized_record_chunk`; table absent live; will raise UndefinedTable; explicitly deferred to H-04 in `sql/0065` header |
| G-06 | agno_app cutover never switched; "cheapest integrity win" | **REFUTED — overtaken by events** | Cutover EXECUTED 2026-08-24 (CHANGE-ORDER CH-21), then **superseded by D-091/D-094**: fresh `platform` DB + `platform_runtime` as canonical runtime login. Live: `ai` **database no longer exists**; `platform` DB live; a live `agno_app` connection was observed; `ai` role still superuser owning 252 tables. The real open item is **verify/complete the D-094 `platform_runtime` cutover**, not the G-06 framing |
| G-07/G-08 | Two-runtime parser/chunker/hash duplication | **VERIFIED** | 26 Python parser modules / 25 `@register`; `server/tools/repair/chunkers.py` exactly 705 lines vs `modules/engine/chunk`; `PostgresReceiptJournal` at `server/ingest/service.py:64` |
| G-09 | Two H3 chains share tag; "fix before further writes" | **PARTIAL — already ruled closed** | HASH-TAXONOMY-2026-08-29:41-49: tag question CLOSED (`h3-chain-sbv-genesisempty-v1` vs read-only legacy, disambiguated by writer; "any statement that this collision is still open is stale"). Residual real work: `AGENTS.md:272` still carries the pre-resolution framing, and `public.canon_registry` (live) has **no** `h3-chain-sbv-genesisempty-v1` row — doc + registry reconciliation, not a re-decision |
| G-10 | SMS-XML parser memory-bound, `iter_records()` unused | **VERIFIED** | `sms_xml.py`: `parse()`→`_collect()` (list-append), fallback `ET.fromstring(read_text())`; `iter_records` has zero callers |
| G-11 | ADR-0044 blob ban unenforced | **PARTIAL — guard exists** | `server/ingest/service.py:34` `_EVIDENCE_FORBIDDEN_PARSERS = {"transcripts.markdown","documents.text-v1"}` raises for evidence lane (:286). It is a parse-lane guard; no store-boundary guard and no reachability test — residual gap is narrower than claimed |
| G-12 | No `raw_rejected` writer | **VERIFIED, schema corrected** | Zero INSERTs repo-wide; table live as **`raw.raw_rejected`** (0 rows), not `evidence.raw_rejected` (older baseline). Fix must target `raw.` |
| G-13 | Horizon predicate inert/superseded | **VERIFIED live** | `working.horizon_visible` filters `row_knowledge_time <= p_horizon` (+ actor + disclosure conjuncts; NULL horizon = hindsight passthrough) — pre-ADR-0059 predicate |
| G-14 | ADR-0045§B/0059 derivation contracts unbuilt | Not independently re-validated (design-layer; no counter-evidence found) |
| G-15 | ADR-0053 tables empty; 1,741 context rows to migrate | **REFUTED as of now** | chat_conversation/chat_message = 0 ✓, but `chat_chunk` doesn't exist as an object, and `working.context_record` = **0** — wiped by `0060_test_reset` (applied 08-31 17:47, per ledger + owner disposable-test-data rule). The "migrate 1,741 rows" work item is moot; re-ingest from originals instead |
| G-16 | Promotion→evidence writer doesn't exist | **PARTIAL** | `server/case_management/repository.py:902` already writes `analysis.evidence_item` promotions + review_task rows. Missing leg = custody-backed `evidence.source`/`evidence_hash`/`custody_event` writer from the 08-25 schema-audit sequence |
| G-17 | Evals: 8 cases, no grounding/retrieval cases | **VERIFIED** | `evals/cases.py` 145 lines, exactly 8 cases, all classification/sentiment/provider-comparison |
| G-18 | No recurring backup lane | **VERIFIED** | `scripts/backup_ovhdata_hot.sh` is the one-time snapshot (PG/Surreal/Weaviate; Neo4j/Milvus cold-copied) |
| G-20 | Unversioned custody digest; 105-offset readiness grid | **VERIFIED** | Trigger hashes session-TZ-rendered timestamp; `repository.py:1739` `generate_series(-720, 840, 15)` = 105 candidates |
| G-21 | Baseline drifts on current image; lacks audit_ledger | **PARTIAL — largely fixed already** | In `sql/bootstrap/schema_baseline_20260830.sql` pg_duckdb is **commented out** (ordering hazard fixed) and `ops.audit_ledger` **is present** (:2095). The stale statements live in `sql/README.md`, which documents only the OLD `schema_baseline.sql` and never mentions the 20260830 file. Real residuals: README true-up, no empty-DB CI regression test, functions duplicated twice in the dump (capture artifact?) |
| G-23 | No status single source (H-08) | **VERIFIED** | DEBT.md self-corrections confirmed (see 4e verdicts) |
| G-24 | Docs mass: 46 MB / 700+ (or 842) files | **REFUTED on numbers, VERIFIED on substance** | Actual: **55.5 MB / 1,279 files** — worse than claimed. wiki = 580 files / 23.3 MiB exact. Markdown line count (131,489) does not reproduce under any scoping |
| G-25 | Evidence bundling never scoped | **VERIFIED** | Zero hits for court_export_draft/human_review_packet in ADRs/DECISION_LOG/DEBT; only `analysis.vw_court_export` view exists; genuinely neither built nor deferred |

### CI/naming/tests (report "Gaps That Remain Open")

| Claim | Verdict |
|---|---|
| No CI job builds baseline against empty DB | **VERIFIED** — no workflow references schema_baseline/postgres service; `generate_schema_baseline.py` + `_wave0_fresh_restore.py` exist, uninvoked. (Path correction: baseline is `sql/bootstrap/schema_baseline_20260830.sql`.) |
| content_hash: 309 occurrences / 20+ files, ban unenforced | **PARTIAL — undercounted** — **387 occurrences / 43 code files** (704/100 incl. docs); no gate anywhere ✓. Nuance: the "ban" exists only as the D-116 comment on `working.content_chunk` ("content_hash is banned") — scoped to the chunk model, **not** a repo-wide naming ruling. Many hits are legitimate distinct concepts (context_record dedup keys per D-048/D-052). A blanket grep gate needs an owner scoping ruling first |
| test_0043/test_0054 assert pre-move schema, no pin markers | **VERIFIED** — live text-assertions against migration files, zero frozen-pin comments; will pass forever regardless of drift |
| Wave 3+ untouched (H-01/H-03/H-04/H-05/H-07) | **VERIFIED** (no contrary evidence) |

### Documentation disposition (report Part 4) — spot verdicts

- 4a delete list: **all six items VERIFIED** (4 `.bak` files, `_TO_BE_DELETED/repair-2026-03-31/`, `wiki.xxh3` 98 KiB).
- 4b/4c: inventory-20260901 exists at `docs/pending-review/` with exactly the 13/37/25 triage; "5 of 11 empty summaries" **exactly verified** (broken PostCompact hook stubs); moves NOT executed; `docs/archive/` empty except README ✓.
- 4d: schema vs schemas dirs ✓ (sizes exact); dial-stack wiki INDEX ✓ (stamped 2026-03-12); 127 KB handoff ✓ (WP-0..11); 137 KB chat transcript ✓; planning dir + sqlite binary ✓; symlinks are real git symlinks but point **inside the repo** (`../server/vendored/semantica/...`), rendered as text stubs on Windows checkouts.
- **URGENT-TODO "pure infra punch list" — REFUTED**: items 17–19 are OPEN ingest/evidence defects (DOCX/PPTX/XLSX/HTML ingest fails; no OCR; evidence lane can't ingest PDFs/DOCX), separated in the file's own prose. Do NOT rename to INFRA-PUNCHLIST as recommended.
- 4e drift table: mostly VERIFIED, except — README sbv/compose rows **ALREADY-FIXED today (uncommitted)**; agno 2.8.0-vs-2.8.7 **REFUTED** (reconciled 08-12/08-14; DEBT.md:196 complaint is itself the stale part); INDEX.md 8 bylines + DIRTY strikethrough ✓; ADR-0044/sql-0009 missing D-069 strike-through ✓; ADR-0050 status line additionally stale (advertises the D-057 merge that **D-105 reversed** — code is right, ADR status wrong).

## Part 2 — New findings the report missed

1. **DECISION_LOG D-number integrity is broken** — D-108 and D-109 each denote TWO unrelated rulings; D-121 double-appended; **D-072–D-080 have no rows at all** while AGENTS.md, ADR-0062, and D-093 cite D-073/D-080 as SurrealDB authority (nearest real ruling: D-061). This is also **the active CI failure** (validate.sh unresolved-D checks).
2. **`~/.secrets` + PLATFORM_REFERENCE point at a dead database** — `DB_DATABASE=ai` everywhere, but the `ai` database no longer exists on 100.91.190.107; live DB is `platform`. (D-091/D-094 cutover doc drift.)
3. **`sql/README.md` describes the wrong baseline** — all caveats (pg_duckdb ordering, missing audit_ledger, regeneration via `capture_bootstrap_ddl.py`) are about the old `schema_baseline.sql`; the canonical 20260830 file is never mentioned and fixes two of the three caveats.
4. **`h3-chain-sbv-genesisempty-v1` missing from live `public.canon_registry`** despite being canon per HASH-TAXONOMY; registry has h1-rawbytes-v1 / h3-chain-v1 / h2-filebound-v1(lost) / h2-canonical-v2 only.
5. **Second engine digest site**: `modules/engine/runtimeapi/bundle_store.go:288` `hashFile` — needs classification alongside the artifact_sink finding (Registry-owned finalization is plausibly legitimate; record the ruling either way).
6. **CI nits**: setup-go cache expects root `go.sum` (engine's is at `modules/engine/go.sum`); checkout@v4/setup-go@v5 Node 20 deprecation warnings; test_0048 silently dead since 08-29.

## Part 3 — Corrected dispatch plan (hand-off ready)

### Wave 0 — Owner decision queue (nothing below starts until ruled)

| # | Decision | Notes |
|---|---|---|
| O-1 | ~~SUBMODULE_TOKEN~~ — **DONE 2026-09-01**, drop from queue | Go job green |
| O-2 | Provision the 7 GAP-021 integration secrets | Names in validate.yml L125-131; job red-by-design until then |
| O-3 | Rule on sql/0045: restore canonical file vs renumber supersession chain | Un-skips test_0048; genuinely never ruled |
| O-4 | Approve execution of the 75-file awaiting-verification dispositions (13 archive / 37 quarantine / 25 keep) + delete the 5 empty COMPACT-SUMMARY stubs | Inventory already persisted 2026-09-01; report-only until approved |
| O-5 | Rule on evidence bundling: ADR now vs formal deferral | Confirmed neither built nor deferred |
| O-6 | Rule content_hash gate SCOPE before any grep gate lands | Ban is currently chunk-model-scoped (D-116), not repo-wide; 387 code occurrences include legitimate distinct concepts |
| O-7 | Rule on docs/wiki dial-stack tree (580 files / 23 MiB): archive wholesale? | No prior ruling exists; never-delete → archive/quarantine only |
| O-8 | Confirm D-094 runtime cutover state: is everything now `platform` DB + `platform_runtime`? Retire `ai` superuser from any remaining app path | Replaces the report's G-06 item; live evidence mixed (agno_app connection seen; ai role still superuser/owner) |

### Owner rulings received 2026-09-01 evening (chat)

| # | Ruling | Consequence |
|---|---|---|
| O-2 | "If I can run a command you can run a command" — agent provisions the secrets | Done so far: `INTEGRATION_SBV_BASE_URL` (= `http://100.72.169.40:8085`, SBV service on ovh-app, health 200). Remaining 4 (`INTEGRATION_DB_USER/PASS`, `INTEGRATION_SBV_SERVICE_USER/PASS`, sourced from Coolify app `exec-tier` env) + Tailscale `tag:ci` — agent's push was blocked by the permission classifier; owner runs the two scratchpad scripts (`set_gh_secrets.py`, `ts_ci_setup.py`). **No Tailscale OAuth client exists**; plan = tagOwners `tag:ci` + 90-day ephemeral pre-authorized auth key → secret `TS_AUTHKEY`, workflow switched to `authkey:`. **Even with all secrets the job cannot pass yet**: it targets `DB_DATABASE=horizon_scratch` + Coolify target `yrhzg9ksyr8sjko1yg44qvgc`, neither of which exists any more (pre-D-091 scratch env), and `tests/test_schema_docs_current.py` hardcodes database `ai` (gone). Integration suite retarget to `platform` = H-02 lane item |
| O-3 | **Renumber** — hole stays documented; **0066 must recreate 0045's full intent** (context-fingerprint supersession semantics), not merely note the gap | Un-skips test_0048 against 0066 |
| O-4 | **Approved** — execute the 75-file dispositions (13 archive / 37 quarantine / 25 keep) + remove the 5 zero-content COMPACT-SUMMARY stubs | Lane C unblocked |
| O-5 | Evidence bundling / exhibit assembly **ownership moves to the Legal Workspace module subproject**; not tracked here | Pointer only in this repo; no ADR/DEBT row here |
| O-6 | Owner: "evaluate once more, pick what's best" → **Agent pick: repo-wide RATCHET gate, no mass rename.** CI fails only on *new* `content_hash` occurrences vs an allowlisted baseline (387/43 files inventoried into HASH-TAXONOMY as legacy); rationale = owner's standing rule that hash names must name their construction (`content_sha256` does, `content_hash` doesn't) applies everywhere, but live-column renames (`raw.raw_rejected.content_hash`, `context_record` dedup keys) are migrations with blast radius — fold them into the Wave-5 `normalized_record` trim where those columns are touched anyway | Stops regrowth now; rename debt scheduled, not sprayed |
| O-7 | **Archive `docs/wiki/` wholesale; salvage what is still alive/useful; restart the wiki later** | Lane C: `git mv` to `docs/archive/wiki-dial-stack-2026-03/`; parser pages reconciled against `docs/reference/parsers.md`; cookbook + `.plannotator` quarantined outside docs/ |
| O-8 | **Finding (live, Coolify env):** `exec-tier` still runs `DB_USER=ai` (superuser) on `platform`, **password is 2 characters**; `DB_HOST` unset. D-094 `platform_runtime` cutover is NOT done. Owner ruling still needed on executing it (create `platform_runtime`, rotate to a real password, redeploy exec-tier + temporal-worker) | Cheapest real integrity win in the register. **Owner direction 2026-09-01 20:06:** Agno keeps minimal tooling — usable as an atomic-agent framework for specific purposes, but it **owns nothing and is not a primary surface**; it is one tool/agent among others. Owner believes the Agno tables from the old `ai` database were reduced to a single set — **to be verified**. Superuser password must change; owner asked for a recommendation and a full reconciliation of whether the cutover completed (reconciliation lane dispatched; results to be appended below) |

### Wave 1 — Parallel, no shared files (dispatch after O-rulings where noted)

| Lane | Task | Source | Model tier |
|---|---|---|---|
| A | **Repair DECISION_LOG integrity**: renumber/disambiguate duplicate D-108/D-109, dedupe D-121, add the missing D-072–D-080 rows (or re-point citations at D-061 etc.) — this also un-reds CI validate | New finding 1 | Sonnet |
| B | **AGENTS.md/README true-up sweep**: commit today's uncommitted README/mypy fixes; fix AGENTS.md `vendored/sbv` ⚠ note + :272 stale H3 framing + `_stale/` export pointer + "on Agno AgentOS" project line + README Graphiti/AgentOS rows; add D-069 dated strike-throughs to ADR-0044 §4 and sql/0009 header; fix ADR-0050 status (D-105); DEBT.md evals row + :196 agno-version note; sql/README.md re-pointed at the 20260830 baseline | 4e verdicts + new findings 3 | Luna free / GLM |
| C | **Docs cleanup pass 1 (mechanical)**: delete 4 `.bak` files + wiki.xxh3 + `_TO_BE_DELETED/`; execute the 75-file dispositions per O-4; move generated artifacts (schema HTML/JSON, sqlite binary, PNGs, receipts) out of docs/ | 4a/4b/4c, gated on O-4 | Luna free |
| D | **Triage remains valid**: 27 pytest failures already classified — execute stale-expectation fixes vs regression fixes per the handoffs-v2 classification | G-03 | GLM-5.2 |
| E | **Baseline CI gate**: add empty-Postgres job restoring `sql/bootstrap/schema_baseline_20260830.sql` + post-baseline migrations; fixes setup-go cache path in same file | Discovery-delay gap (verified real) | Sonnet |

### Wave 2+ — unchanged from the report EXCEPT:

- **H-04** (vector cutover) now also owns: `enqueue_evidence_vector_projection` retarget (verified live-broken), `chat_chunk` non-existence, and the G-15 correction (re-ingest, no 1,741-row migration).
- **H-01 split** stays (G-10 streaming rewrite, G-11 store-boundary guard + reachability test — narrower now, G-12 writer targeting **`raw.raw_rejected`**), K3 barred per standing rule.
- **G-09** demotes from "fix before further chain writes" to: update AGENTS.md:272 + insert `h3-chain-sbv-genesisempty-v1` into `public.canon_registry` (needs a write-window; owner sign-off).
- **H-08 status single-source** proceeds as designed; add a CI check for duplicate/dangling D-numbers (prevents new finding 1 from recurring).
- Add: classify `bundle_store.go` hashFile (new finding 5) inside the H-01/Assertion-1 lane; update `~/.secrets`/PLATFORM_REFERENCE to `platform` DB (new finding 2, owner touches secrets).

### Completion gate (unchanged)

Independent Sonnet verification of each handoff's "Done when" block — live probes, real runs, no self-reported completion.

## Part 4 — Assertion verdicts (report's final section) — confirmed

1. **Parser hashing**: contract clean ✓, `sbv.go` clean ✓, `artifact_sink.go` computes + branches on SHA-256 ✓ (all six sub-claims file:line verified). Add `bundle_store.go:288` to the same review.
2. **Temporal hashing**: verified — `hashing.go` bodies + `register.go` registration (report attributed registration to the wrong file; facts otherwise exact), Fingerprint* vocabulary, legacy aliases with do-not-use warnings.
3. **Python-under-Go**: verified — `LanguagePython` declared, one test usage, zero production adapters; HTTP-only export via `parser-activity-runtime` (5 context.* relations probe, 31-min timeout, bearer auth).
