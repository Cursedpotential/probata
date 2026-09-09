# Documentation reconciliation plan — consolidate to only-current

> _Byline: Claude Code subagent · Opus 5 · 2026-09-06_

STATUS: ITERATING — not executed; owner ratifies before any move

Owner directive, 2026-09-06 17:10: *"the docs need complete reconciling — consolidate and
replace with only current, the whole stack of them."*

This plan **moves nothing**. It names the target shape, classifies every file mechanically,
maps the merges, lists the contradictions between documents that both claim to be current,
and sequences an execution a later session can run on an explicit go.

**It builds on `docs/reviews/2026-09-05-docs-consolidation-audit.md`** (Opus 5, 2026-09-05)
and its two companions under `docs/consolidated/`. That pass classified 1,337 files, produced
a 71-command move manifest in four batches, and diagnosed the structural loop. None of it was
executed. Where its classification still holds, this plan cites it rather than re-deriving it.
What is new here: the 2026-09-06 artifacts that did not exist when it ran (the ingest-rulings
handoff, D-149, four review/planning docs, the rename follow-ups, two session digests), the
target-shape decision it deliberately did not make, and a measured drift list.

**Method.** Content facts come from a DuckDB `read_text('docs/**/*.md')` sweep with regex
extraction of byline dates, `STATUS:` lines, supersession markers and strike-through density;
last-change dates come from one `git log --name-only` pass over `docs/`; drift strings come
from `rg` with the archive, wiki and private trees excluded. Every classification cites the
marker or date it rests on. Nothing is proposed for deletion.

**Scope.** `docs/` holds **1,368 files** today. Out of scope: `docs/private/` (1 file, never
touched), `docs/adr/` (63, append-only, superseded in place), `docs/archive/` (1, the
destination). That leaves **1,303 files** classified below. `docs/wiki/` (580) is carried as a
single owner-gated cluster row and is excluded from every move batch until its P0 credential
item is ruled.

---

## 1. The target shape — "only current"

The rule that produces this list: **one document per role.** Where several documents compete
for one role, the newest owner-approved one wins and the others merge into it and then
archive. Registers are the exception — an append-only ledger is not competing with anything,
it *is* the record, and it stays.

### Entry — how an agent finds its way in

| Role | Target file | Note |
|---|---|---|
| Universal entry point | `AGENTS.md` (repo root) | Already correct; carries the drift rule and the atomicity rule |
| Memory router | `AGENT_MEMORY.md` (repo root) + `docs/AGENT_MEMORY.md` | Path-hierarchy routers, not authority |
| Memory format contract | `docs/agent-memory/README.md` | Named by both routers |
| Current-truth index | `docs/INDEX.md` | **Must be rewritten.** Today it routes to 08-18-era artifacts and names none of the current ones — drift finding D-10 |

### Canon — never archived, amended in place

| Role | Target file |
|---|---|
| Product invariant, locked decisions, the knowledge-horizon mechanism | `docs/PROJECT_CANON.md` |
| Naming canon | `docs/NAMING.md` |
| Coding style, tool contract, doc conventions | `docs/CONVENTIONS.md` |
| Where every kind of file goes | `docs/REPO_STRUCTURE.md` |
| Vocabulary | `docs/glossary.md` |
| Ruling ledger | `docs/DECISION_LOG.md` — append-only, rows never edited |
| Architecture decisions | `docs/adr/**` — append-only, superseded in place, never moved |
| Memory architecture | `docs/MEMORY_ARCHITECTURE.md` |
| Custody hash canon | `docs/reference/CUSTODY-HASH-CANON.md` + `docs/reference/HASH-TAXONOMY-2026-08-29.md` (cited by ten nested `AGENTS.md` files) |

### The ONE current ingest plan

**Winner: `docs/planning/2026-09-03-ingest-redesign-plan-and-sequential-guide.md`**
(61 KB, `STATUS: ITERATING`, amended through 2026-09-06, cited by name as *the plan* in
`docs/HANDOFF-2026-09-06-ingest-rulings-and-parser-fix.md:48`).

Losers, all MERGE-INTO it:

| Loser | Why it loses |
|---|---|
| `docs/planning/2026-09-03-ingest-simplification-plan.md` | Same date, same lane, not the one the 09-06 handoff advances; still asserts Google Voice as the first real ingest (struck 2026-09-06) and the tool gateway as undeployed (deployed 2026-09-05) |
| `docs/planning/2026-09-06-derived-layers-change-map.md` | Is the file:line execution annex *of* the winner — it belongs inside it, not beside it |
| `docs/planning/reingest-etl-pipeline.md` | `STATUS: DRAFT — PENDING OWNER APPROVAL`; same lane, older premise |
| `docs/plans/TEMPORAL-INTEGRATION-PLAN-2026-08-23.md` | Says "no decision recorded yet"; D-130 ruled it and Temporal is live |
| The three 2026-09-06 review passes (recall / thinking / chunks-in-Weaviate) | Analysis inputs to D-149; their conclusions belong in the plan, the passes archive as evidence |

### The ONE current handoff

**Winner: `docs/HANDOFF-2026-09-06-ingest-rulings-and-parser-fix.md`** (`STATUS: PARTIAL`,
2026-09-06 15:46; names itself the authoritative current state and is named as such by
`docs/reviews/2026-09-06-ingest-session-digest.md:3`).

Losers: `docs/COMPACT-SUMMARY-2026-09-06.md` · `docs/reviews/2026-09-06-ingest-session-digest.md` ·
`docs/reviews/2026-09-06-naming-and-rename-session-digest.md` ·
`docs/HANDOFF-2026-08-29-agno-role-dissection.md` ·
`docs/HANDOFF-2026-08-29-derived-document-ingest-wiring.md` ·
`docs/HANDOFF-2026-08-18-evidence-operations-desk-mvp.md` · and, outside `docs/`, the stale
`.remember/now.md`.

### The ONE current open-work register

**Winner: `docs/consolidated/OPEN-WORK-REGISTER-2026-09-05.md`** (101 open items + 21
done-but-never-closed; `STATUS: ITERATING`).

It must absorb, item by item and not by summary: the rename-followups rows 02–07, the
handoff's UNRESOLVED block, the session digest §6, and the open rows of every document
classified MERGE-INTO or ARCHIVE below. **That absorption is the archive gate** — per the
09-05 audit §8, nothing moves until its open items exist as rows here.

Contested: `docs/MASTER-TODO-2026-08-18.md` is called "authoritative production resume ledger"
by `docs/INDEX.md`, and the register's own scope note defers to it rather than superseding it.
Two ledgers, neither answering "what is open." Recommended winner: the register (newer, and
the only one that enumerates its own boundary). **Owner call — Q3 in §5.**

### Registers that are append-only ledgers — keep, do not merge, do not archive

`docs/DECISION_LOG.md` · `docs/COORDINATION.md` · `docs/URGENT-TODO.md` · `docs/DEBT.md` ·
`docs/DOC_DEBT.md` · `docs/CHANGE-ORDER.md` · `docs/GUARD-TRIGGER-DISPOSITION.md` ·
`docs/registers/SETTLED.md` · `docs/registers/RENAME-BLAST-RADIUS-2026-09-05.md` ·
`docs/registers/RENAME-LIVE-CHANGES-2026-09-06.md`

Each keeps its scope; the open-work register indexes them rather than replacing them. Two need
a one-line scope header so a reader can tell them apart at a glance (`URGENT-TODO` = loud
stubs and broken things; `DEBT` = activation holds and technical debt).

### Salvage and stable reference

`docs/consolidated/RETIRED-SYSTEMS-KNOWLEDGE.md` · `docs/reference/parsers.md` (needs a
freshness check against the live decoder set) · `docs/reference/sms-backup-restore-xml-fields.md` ·
`docs/reference/SAT-ACTION-CONTRADICTION-LABELS-2026-09-06.md` (untracked; **contains real
names — no-PII-in-git check before it is ever committed**) · `docs/recovered/**` (sole
surviving GraphRAG record) · `docs/schema/` + `docs/schemas/` (machine-consumed contracts) ·
`docs/planning/chat-sample-analysis/**` (irreplaceable discovery over the real corpus) ·
`docs/design/**` (includes the ADR-0061 spec) · `docs/runbooks/**`.

---

## 2. Inventory table

### Count summary

Measured 2026-09-06 by DuckDB `read_text` over `docs/**/*.md` plus `find` for non-markdown,
joined to one `git log --name-only` pass.

| | Files |
|---|---|
| `docs/` total | **1,368** |
| less `docs/private/` (never touched) | −1 |
| less `docs/adr/` (append-only, in place) | −63 |
| less `docs/archive/` (the destination; still holds only its own README) | −1 |
| **In scope, classified below** | **1,303** |

| Classification | Files | Dominated by |
|---|---|---|
| **CURRENT-KEEP** | **153** | canon + entry (15 at `docs/` root) · `chat-sample-analysis` 22 · `reports` working output 28 · `design` 14 · code-cited planning docs 5 · live pre-mortems 10 |
| **APPEND-ONLY-KEEP** | **10** | 7 root registers + 3 under `docs/registers/` |
| **MERGE-INTO** | **22** | 9 current reviews · 6 root handoff/manifest docs · 4 planning · 2 plans · 1 handoffs README |
| **ARCHIVE** | **432** | `reports/_stale` 123 · `planning/forensic-db-*` 85 · `reviews/` historical subtrees 91 · `plans/` superseded 14 · `docs/` root 29 |
| **OWNER-DECIDES** | **686** | `docs/wiki/` **580** and `docs/awaiting-verification/` **78** — two rulings carried forward from the 09-05 audit (OW-063, OW-004). **Excluding those two, 28 files across 14 questions** |
| **Total** | **1,303** | |

Coverage: **168 per-file rows** (every file at `docs/` root and in `handoffs/`, `registers/`,
`consolidated/`, `reference/`, `pending-review/`, `planning/` top level, `plans/`, the
`reviews/2026-09-*` lane, and `docs/.claude/`) plus **25 cluster rows** covering the remaining
1,135 files. Cluster rows adopt the 09-05 audit's per-file work rather than re-deriving it;
per-file rows override cluster rows. 168 + 1,135 = 1,303.

Two counts worth stating plainly: `docs/` grew from **1,337 files on 2026-09-05** (audit §0)
to **1,368 on 2026-09-06** — 31 files added in one day — and `docs/archive/` has received
**zero** files in the 19 days since it was created.

### 2.1 CURRENT-KEEP — per-file

| Path | Size | Last git change | Byline | Status marker found | Reason |
|---|---|---|---|---|---|
| `docs/PROJECT_CANON.md` | 53.7 KB | 2026-09-06 | 2026-09-05 | 32 strike-through corrections | The SSOT; §1 is the knowledge-horizon mechanism. Carries drift D-5/D-7/D-8 — corrections, not a move |
| `docs/INDEX.md` | 7.2 KB | 2026-09-06 | 2026-08-18 | — | Current-truth router; watched by `docs/AGENT_MEMORY.md`. **Needs rewriting** (D-10) |
| `docs/NAMING.md` | 11.8 KB | 2026-09-06 | 2026-09-05 | — | Naming canon D-137..D-141; the rename lane depends on it |
| `docs/CONVENTIONS.md` | 12.4 KB | 2026-09-06 | 2026-09-05 | — | `AGENTS.md` Further Reading. Line 34 carries drift D-5 |
| `docs/REPO_STRUCTURE.md` | 14.5 KB | 2026-09-06 | 2026-09-05 | — | `AGENTS.md` Further Reading; structural index |
| `docs/glossary.md` | 4.2 KB | 2026-06-13 | — | — | Canon vocabulary; oldest canon file, due a naming pass |
| `docs/AGENT_MEMORY.md` | 1.6 KB | 2026-08-29 | 2026-08-27 | `status: current` | The `docs/**` memory router |
| `docs/MEMORY_ARCHITECTURE.md` | 11.6 KB | 2026-08-27 | 2026-06-16 | — | Authority row in `docs/AGENT_MEMORY.md`. Line 54 carries drift D-6 |
| `docs/HANDOFF-2026-09-06-ingest-rulings-and-parser-fix.md` | 12.4 KB | UNTRACKED | 2026-09-06 | `STATUS: PARTIAL` | **THE current handoff.** Commit it (PII check first) |
| `docs/EVIDENCE_MERGE_MAP.md` | 47.6 KB | 2026-08-31 | 2026-06-13 | `Status: DRAFT for owner sign-off` | Capability inventory cited by `BUILD_PLAN.md`. Lines 7/16/52 carry drift D-5/D-6 |
| `docs/INFRASTRUCTURE.md` | 5.7 KB | UNTRACKED | 2026-06-13 | — | Predates Temporal, the n8n sandbox and D-122's secrets broker. Recompile in place; do not move |
| `docs/n8n-model-and-node-notes.md` | 11.1 KB | 2026-08-24 | — | — | Live n8n 2.36.6 working notes with measured model results |
| `docs/wiki.xxh3` | — | tracked | — | — | Checksum sidecar; `AGENTS.md` says ignore `*.xxh3` |
| `docs/semantica` | symlink | tracked | — | — | Git symlink (mode 120000) into `server/vendored/semantica/` — moving it breaks the alias |
| `docs/semantica-benchmarks` | symlink | tracked | — | — | Same |
| `docs/consolidated/OPEN-WORK-REGISTER-2026-09-05.md` | 49.5 KB | 2026-09-06 | 2026-09-05 | `STATUS: ITERATING — NOT DONE` | **THE open-work register.** The archive gate |
| `docs/consolidated/RETIRED-SYSTEMS-KNOWLEDGE.md` | 33.4 KB | 2026-09-06 | 2026-09-05 | `STATUS: ITERATING — NOT DONE` | Salvaged facts from retired systems; the reason those systems' docs can archive |
| `docs/reference/CUSTODY-HASH-CANON.md` | 5.3 KB | 2026-09-06 | 2026-09-05 | — | Custody canon |
| `docs/reference/HASH-TAXONOMY-2026-08-29.md` | 5.6 KB | 2026-09-02 | 2026-08-29 | — | Cited by ten nested `AGENTS.md` files |
| `docs/reference/parsers.md` | 48.7 KB | 2026-08-05 | 2026-07-11 | — | Parser reference; **needs a freshness check** against the live decoders (OW row) |
| `docs/reference/sms-backup-restore-xml-fields.md` | 6.9 KB | 2026-08-02 | 2026-07-02 | — | Field reference for the format of the first real ingest |
| `docs/handoffs/2026-09-06-rename-followups/02-restore-deny-list-and-gate.md` | 1.4 KB | 2026-09-06 | 2026-09-06 | — | Open task prompt; owner-gated (settings file) |
| `docs/handoffs/…/03-r2-dev-fixtures-copy.md` | 1.0 KB | 2026-09-06 | 2026-09-06 | — | Open; needs billable-transfer sign-off |
| `docs/handoffs/…/04-golden-clone-teardown.md` | 1.7 KB | 2026-09-06 | 2026-09-06 | — | Open; owner gate before touching `platform` |
| `docs/handoffs/…/05-identifier-rulings-needed.md` | 2.1 KB | 2026-09-06 | 2026-09-06 | — | Open; 18 identifier rulings owed (drift D-13) |
| `docs/handoffs/…/06-analysis-engine-split-indagatio.md` | 1.2 KB | 2026-09-06 | 2026-09-06 | — | Open; plan iterates until owner says done |
| `docs/handoffs/…/07-memory-tooling-repairs.md` | 2.1 KB | 2026-09-06 (modified) | 2026-09-06 | — | Open; memory lane |
| `docs/planning/2026-09-03-ingest-redesign-plan-and-sequential-guide.md` | 61.2 KB | 2026-09-06 (modified) | 2026-09-03 | `STATUS: ITERATING — NOT DONE`; 28 strike-throughs | **THE ingest plan.** Internally inconsistent at :400 — see D-2 |
| `docs/planning/operator-console-requirements.md` | 10.4 KB | 2026-08-02 | 2026-07-20 | `status open\|partial\|corroborated` | 8 live code/SQL/test citations — reference by use |
| `docs/planning/port-backlog.md` | 12.3 KB | 2026-07-04 | 2026-07-04 | `Status: INVENTORY for owner triage` | 4 live citations |
| `docs/planning/agno-chunking-strategy.md` | 28.3 KB | 2026-08-10 | 2026-07-10 | — | 4 live citations including ADR-0050 |
| `docs/planning/facade-collapse-plan.md` | 45.5 KB | 2026-08-02 | 2026-07-09 | `Status: PLAN ONLY — not executed` | Cited by `server/agents/AGENTS.md` |
| `docs/planning/gui-integration-spec.md` | 18.0 KB | 2026-09-02 | 2026-07-04 | `Status: DRAFT for owner brainstorm` | Cited by `scripts/annotate-plans.sh` |
| `docs/plans/COURT-READINESS-pre-mortem-2026-08-15.md` | 4.7 KB | 2026-08-15 | 2026-08-15 | `STATUS: COMPLETE LOCALLY` | Gating safety analysis for an undeployed feature (OW-037) |
| `docs/plans/EVIDENCE-CUSTODY-INSPECTION-pre-mortem-2026-08-15.md` | 3.6 KB | 2026-08-15 | 2026-08-15 | `BUILT LOCALLY; VERIFIED; UNDEPLOYED` | Same |
| `docs/plans/MATTER-ACTIVATION-PREFLIGHT-pre-mortem-2026-08-15.md` | 4.2 KB | 2026-08-30 | 2026-08-15 | `COMPLETE LOCALLY — read-only release gate` | Same |
| `docs/plans/MATTER-WORKBENCH-pre-mortem-2026-08-15.md` | 8.3 KB | 2026-08-15 | 2026-08-15 | `BUILT LOCALLY; VERIFIED; UNDEPLOYED` | Same |
| `docs/plans/MATTER-FOUNDATION-pre-mortem-2026-08-15.md` | 6.0 KB | 2026-08-15 | 2026-08-15 | `STATUS: BUILT; HELD; UNAPPLIED` | Status is **false** — 0026–0030 applied 2026-08-23 (OW-030). Dated correction before anything else |
| `docs/plans/MCP-GATEWAY-CHAIN-PHASE1-2026-08-16.md` | 4.5 KB | 2026-08-16 | 2026-08-16 | `LOCAL CONTRACT COMPLETE; ACTIVATION HELD` | Live activation gate (OW-035) |
| `docs/plans/SEMANTICA-SWIFT-SLICE4-2026-08-16.md` | 4.7 KB | 2026-08-16 | 2026-08-16 | `LOCAL DISPOSABLE SLICE IMPLEMENTED` | Activation gate (OW-033) |
| `docs/plans/WEAVIATE-NATIVE-EVIDENCE-CUTOVER-RUNBOOK-2026-08-18.md` | 8.8 KB | 2026-08-23 | 2026-08-18 | `clone to blue has executed…` | Activation gate (OW-015) |
| `docs/plans/N8N-BUILDER-AGENT-GUIDE.md` | 11.5 KB | 2026-08-24 | 2026-08-24 | — | The owner's own n8n methodology |
| `docs/plans/chat-ingest-pipeline.md` | 2.4 KB | 2026-08-13 | 2026-08-13 | — | Short current explainer for the chat lane |
| `docs/reviews/2026-09-05-docs-consolidation-audit.md` | 65.8 KB | 2026-09-06 | 2026-09-05 | `STATUS: ITERATING — NOT DONE` | The parent of this plan; the move manifest lives here |
| `docs/reviews/2026-09-05-ingest-day-live-chain.md` | 9.5 KB | 2026-09-06 | 2026-09-05 | — | Named by the open-work register as a living register |
| `docs/reviews/2026-09-05-tool-gateway-live-deploy.md` | 10.2 KB | 2026-09-06 | 2026-09-05 | — | The deploy receipt that settles drift D-3. Still carries old `uiw` names |
| `docs/reviews/2026-09-03-r2-messaging-inventory-and-export-shapes.md` | 5.7 KB | 2026-09-03 | 2026-09-03 | — | Source inventory cited by both ingest plans |
| `docs/reviews/2026-09-02-relitigation-pattern-and-fix.md` | 9.3 KB | 2026-09-06 | 2026-09-02 | — | The diagnosis this whole lane exists to fix; its F2/F3/F4 are OW-050/051/052 |
| `docs/reviews/2026-09-02-uiw-rehearsal-acquisition-seam.md` | 8.2 KB | 2026-09-06 | 2026-09-02 | — | **Cited by `modules/engine/AGENTS.md` — never archive** |
| `docs/reviews/2026-09-01-resolved-designs-recovery.md` | 6.6 KB | 2026-09-06 | 2026-09-01 | `Status: this is handoffs-v2 H-07` | Recovery of resolved designs; still the only record |
| `docs/reviews/2026-09-06-webbed-install.md` | 4.6 KB | UNTRACKED | 2026-09-06 | `STATUS: DONE; live-verified` | Live receipt for the pg_duckdb `webbed` install; the Dockerfile change depends on it |
| `docs/reviews/2026-09-06-memsearch-summarizer-fix.md` | 4.7 KB | UNTRACKED | 2026-09-06 | — | Memory-lane receipt, outside the ingest lane |
| `docs/agent-memory/README.md` | 4.3 KB | 2026-08-27 | 2026-08-27 | `status: current` | Memory format/precedence contract named by both routers |

### 2.2 APPEND-ONLY-KEEP — per-file

| Path | Size | Last git change | Byline | Status marker | Reason |
|---|---|---|---|---|---|
| `docs/DECISION_LOG.md` | 203.5 KB | 2026-09-06 | 2026-08-30 | 18 strike-throughs | D-001…D-149. Rows are never edited; supersession is a new row. Title line carries drift D-6 |
| `docs/COORDINATION.md` | 45.5 KB | 2026-09-06 | 2026-09-05 | 24 strike-throughs | Multi-chat lane ledger; header already correctly struck for the rename. Lines 168/219/223/296 carry drift D-7 |
| `docs/URGENT-TODO.md` | 25.5 KB | 2026-08-31 | 2026-08-20 | 15 strike-throughs | Loud stub/broken register, ~20 rows OPEN |
| `docs/DEBT.md` | 33.7 KB | 2026-09-06 | 2026-09-05 | 16 strike-throughs | Activation holds and technical debt |
| `docs/DOC_DEBT.md` | 3.5 KB | 2026-08-05 | 2026-07-11 | — | 9 open rows (OW-062). Oldest live register — needs a pass, not a move |
| `docs/CHANGE-ORDER.md` | 53.9 KB | 2026-08-29 | 2026-08-24 | 4 strike-throughs | Running change order, stalled at CH-21 (OW-060). Title line carries drift D-6 |
| `docs/GUARD-TRIGGER-DISPOSITION.md` | 6.3 KB | 2026-08-31 | — | — | 131 guard triggers in four buckets; makes the D-110 flag flip safe |
| `docs/registers/SETTLED.md` | 5.9 KB | 2026-09-06 | 2026-09-03 | — | The F1 anti-relitigation register. Row 26 is the Milvus ruling drift D-4 tests against |
| `docs/registers/RENAME-BLAST-RADIUS-2026-09-05.md` | 67.6 KB | 2026-09-06 | 2026-09-05 | — | Rename blast radius; still being consumed |
| `docs/registers/RENAME-LIVE-CHANGES-2026-09-06.md` | 16.3 KB | 2026-09-06 (modified) | 2026-09-06 | Status legend DONE/PENDING-OWNER/NOT DONE | The live-change ledger for everything changed outside git. **Append, never rewrite** |

### 2.3 MERGE-INTO — per-file

| Path | Size | Last git change | Byline | Status marker | Target | Reason |
|---|---|---|---|---|---|---|
| `docs/planning/2026-09-03-ingest-simplification-plan.md` | 32.2 KB | 2026-09-06 | 2026-09-05 | `STATUS: ITERATING — NOT DONE` | the ingest plan | Same lane, same date, not the plan the 09-06 handoff advances; two stale claims (D-1, D-3) |
| `docs/planning/2026-09-06-derived-layers-change-map.md` | 16.8 KB | UNTRACKED | 2026-09-06 | `STATUS: PROPOSED — owner has not ruled` | the ingest plan | It *is* the plan's file:line execution annex |
| `docs/planning/reingest-etl-pipeline.md` | 24.7 KB | 2026-08-31 | 2026-08-02 | `STATUS: DRAFT — PENDING OWNER APPROVAL` | the ingest plan | Same lane, older premise, never approved |
| `docs/planning/contextforge-adoption-list.md` | 5.4 KB | 2026-07-31 | 2026-07-31 | `Status: inventory + triage. Nothing adopted yet` | open-work register | It is a worklist; worklists belong in the register |
| `docs/plans/TEMPORAL-INTEGRATION-PLAN-2026-08-23.md` | 17.5 KB | 2026-08-23 | 2026-08-23 | — | the ingest plan | Says no decision recorded; D-130 ruled it and it is live (OW-122). Line 53 carries drift D-5 |
| `docs/plans/uiw-preview-contract.md` | 3.9 KB | 2026-09-06 | 2026-08-29 | `IMPLEMENTED LOCALLY; DEPLOYMENT AND LIVE PROOF REMAIN` | open-work register | OW-038; predates the rename and the 09-05 chain |
| `docs/DOC_CLEANUP_MANIFEST-2026-08-15.md` | 6.8 KB | 2026-08-15 | 2026-08-15 | `ENTRY-POINT REPAIR COMPLETE; QUARANTINE STILL PROPOSED` | open-work register | Its five UNRESOLVED questions are OW-003. Merge the questions, then archive the manifest |
| `docs/UNRESOLVED-QUESTIONS-2026-08-16-surreal-investigation-phase0.md` | 11.9 KB | 2026-08-16 | 2026-08-16 | `Status: ACTIVE INVENTORY — S1–S6 resolved by D-064` | open-work register | Self-declared inventory; the unresolved rows are register rows |
| `docs/HANDOFF-2026-08-18-evidence-operations-desk-mvp.md` | 1.9 KB | 2026-08-23 | 2026-08-18 | body: "NOT COMPLETE — resume at step 1" | open-work register | One-role rule: not the current handoff |
| `docs/HANDOFF-2026-08-29-agno-role-dissection.md` | 21.2 KB | 2026-09-06 | 2026-08-29 | `STATUS: IMPLEMENTING` | open-work register | AgentOS-cutover authority; its holds are register rows. **Item-level merge — it carries live release gates** |
| `docs/HANDOFF-2026-08-29-derived-document-ingest-wiring.md` | 126.6 KB | 2026-09-06 | 2026-08-29 | `STATUS: PARTIAL` | open-work register | WP-10/WP-11 = OW-017/018. Largest handoff in the tree; merge WP rows, archive the body. Line 505 carries drift D-7 |
| `docs/COMPACT-SUMMARY-2026-09-06.md` | 79.4 KB | UNTRACKED | hook-generated | — | current handoff | PostCompact exhaust. Its three blocks contain the sealing-at-ingest ruling and the two unquarantined seal files — extract those, then archive |
| `docs/handoffs/2026-09-06-rename-followups/README.md` | 2.3 KB | 2026-09-06 | 2026-09-06 | rows 01/08 DONE | open-work register | Rows 02–07 are open work; the README is a mini-register competing with the real one |
| `docs/reviews/2026-09-06-ingest-session-digest.md` | 69.7 KB | UNTRACKED | 2026-09-06 | `STATUS: digest of a closed session` | current handoff + register | §6 is 40+ open items that exist nowhere else; §1 failure patterns belong in `CONVENTIONS.md` or the relitigation review |
| `docs/reviews/2026-09-06-naming-and-rename-session-digest.md` | 414.7 KB | 2026-09-06 | 2026-09-06 | `Status — Wave 1 dispatched` | `RENAME-LIVE-CHANGES` + register | **Largest single file in `docs/`.** Its live-change facts belong in the ledger; the transcript is evidence |
| `docs/reviews/2026-09-06-storage-copies-recall-pass.md` | 10.2 KB | UNTRACKED | 2026-09-06 | `STATUS: RECALL — prior rulings located` | the ingest plan | Input to D-149; 3 of 7 morning proposals were restatements of settled rulings |
| `docs/reviews/2026-09-06-storage-copies-and-derived-layers-thinking-pass.md` | 13.9 KB | UNTRACKED | 2026-09-06 | `STATUS: ANALYSIS — owner has not ruled` | the ingest plan | Input to D-149; the "operator time is the bottleneck" claim was WITHDRAWN |
| `docs/reviews/2026-09-06-chunks-live-in-weaviate-systems-pass.md` | 2.6 KB | UNTRACKED | 2026-09-06 | `STATUS: RULED 12:2x. Amends D-149 items 7–8` | the ingest plan | It amends a ruling — the amendment must live in the plan, and a D-row records it. Do not edit D-149 |
| `docs/reviews/2026-09-06-ingest-to-surreal-thinking-pass.md` | 23.2 KB | 2026-09-06 | 2026-09-06 | `STATUS: ITERATING. Nothing here is ruled` | the ingest plan | Analysis with no ruling attached |
| `docs/reviews/2026-09-05-h04-bridge-and-weaviate-feed-rewire.md` | 13.4 KB | 2026-09-05 | 2026-09-05 | `STATUS: BUILT; NOT DEPLOYED` | open-work register | An undeployed build is a register row |
| `docs/reviews/2026-09-04-outbox-part1-build.md` | 12.1 KB | 2026-09-05 | 2026-09-04 | `built + live-validated under rollback; NOT committed; NOT applied` | open-work register | Same |
| `docs/reviews/2026-09-02-feature-flag-integrity-audit.md` | 33.1 KB | 2026-09-06 | 2026-09-02 | — | open-work register | `SBV_CUSTODY_ENABLED` default and the zero-test immutability gates are remediation rows |

### 2.4 ARCHIVE — per-file

Destination `docs/archive/2026-09/<category>/`. Every row leaves a pointer line in
`docs/archive/2026-09/INDEX.md` (old path → new path → one-line why). Nothing is deleted.

| Path | Size | Last git change | Byline | Status marker | Reason |
|---|---|---|---|---|---|
| `docs/ADR_RECONCILIATION.md` | 12.4 KB | 2026-08-15 | 2026-08-15 | `Superseded-in-part` codes | Self-bannered historical sweep; stops at ADR-0022. Paired edit: `BUILD_PLAN.md` |
| `docs/AGENT_CONTEXT_MERGE_PLAN.md` | 17.9 KB | 2026-07-04 | 2026-06-29 | `PLAN — discovery complete; no files rewritten yet` | Overtaken by the 08-27 and 09-01 restructures |
| `docs/RULINGS-SHEET-2026-08-09.md` | 1.4 KB | 2026-08-10 | — | "ALL RESOLVED" | Recorded as D-042; the artifact built once and never maintained |
| `docs/Codex Goal — Horizon Swift MVP.md` | 15.4 KB | UNTRACKED | 2026-08-16 | — | Framed around Agno retirement as future; ruled and executed (D-107) |
| `docs/INGESTION-READINESS-2026-08-23.md` | 5.9 KB | 2026-08-23 | 2026-08-23 | — | Explicitly "written for tonight". Paired edit: `INDEX.md` Start-here row |
| `docs/HANDOFF-2026-08-18-evidence-desk-backend.md` | 3.3 KB | 2026-08-23 | 2026-08-18 | `STATUS: PARTIAL` | Superseded by the 08-24/27/29 chain |
| `docs/HANDOFF-2026-08-24-ingest-testing.md` | 10.0 KB | 2026-08-25 | 2026-08-24 | `STATUS: PARTIAL` | Superseded hours later by the n8n go-live handoff. Line 25 carries drift D-4. Paired edit: `sql/AGENT_MEMORY.md` |
| `docs/HANDOFF-2026-08-24-n8n-pipeline-golive.md` | 10.5 KB | 2026-08-25 | 2026-08-24 | `STATUS: PARTIAL` | "One step from first run" is moot; n8n-as-Activities is live (OW-123) |
| `docs/HANDOFF-2026-08-27-platform-development-takeover.md` | 12.3 KB | 2026-08-27 | 2026-08-27 | `STATUS: PARTIAL` | Cold-start takeover superseded by the 08-29 pair |
| `docs/INFRASTRUCTURE.template.md` | 6.2 KB | 2026-06-14 | 2026-06-14 | — | Sanitized structural mirror of `INFRASTRUCTURE.md`, same staleness. Survivor: `INFRASTRUCTURE.md` |
| `docs/create-new-agent.md` | 10.6 KB | 2026-06-13 | — | — | Upstream AgentOS template residue; links `../app/config.yaml`, `../railway.json` — none exist |
| `docs/extend-agent.md` | 11.3 KB | 2026-06-13 | — | — | Same |
| `docs/improve-agent.md` | 9.5 KB | 2026-06-13 | — | — | Same |
| `docs/eval-and-improve.md` | 7.4 KB | 2026-06-13 | — | — | Same; eval contract already salvaged into `RETIRED-SYSTEMS-KNOWLEDGE.md` §5 |
| `docs/review-and-improve.md` | 9.3 KB | 2026-06-13 | — | — | Same |
| `docs/COMPACT-SUMMARY-2026-08-24.md` | 345.8 KB | UNTRACKED | hook | 22 strike-throughs | PostCompact exhaust; largest of the set. Plain `mv`, not `git mv` |
| `docs/COMPACT-SUMMARY-2026-08-29.md` | 18.9 KB | UNTRACKED | hook | — | Same |
| `docs/COMPACT-SUMMARY-2026-08-30.md` | 10.5 KB | UNTRACKED | hook | — | Same |
| `docs/COMPACT-SUMMARY-2026-09-02.md` | 68.0 KB | UNTRACKED | hook | — | Same |
| `docs/COMPACT-SUMMARY-2026-09-03.md` | 102.8 KB | UNTRACKED | hook | — | Same. **Move last** — it holds the verbatim Milvus/memsearch correction the SETTLED row was built from |
| `docs/TODO-SNAPSHOT-2026-08-02.json` … `-08-14.json` (5 files) | — | UNTRACKED | — | — | Point-in-time TODO dumps. Plain `mv` |
| `docs/URGENT-TODO.md.bak-20260824b/c/d` (3 files) | — | tracked | — | — | Mechanical editor backups, content-distinct but superseded. Never delete |
| `docs/n8n-model-and-node-notes.md.bak-20260824` | — | tracked | — | — | Same |
| `docs/planning/BUILD_TODO.md` | 12.5 KB | 2026-06-13 | — | — | v8.1-era; self-banners "Phases 1–9 DONE… retained as build history" |
| `docs/planning/EXECUTION_PLAN.md` | 29.5 KB | 2026-06-13 | — | — | Same |
| `docs/planning/MIGRATION_PLAN_v8.md` | 23.4 KB | 2026-06-13 | — | — | Same |
| `docs/planning/TOOL_SOURCES_INVENTORY.md` | 11.7 KB | 2026-06-13 | — | — | Same; line 117 carries drift D-5 |
| `docs/planning/VERIFIED_AGNO_API.md` | 3.5 KB | 2026-06-13 | — | — | Same; Agno retired as orchestrator (D-107) |
| `docs/planning/DEV_RESOURCES_INDEX.md` | 9.2 KB | 2026-06-13 | — | — | Same |
| `docs/planning/graphiti-image-rebuild-plan.md` | 14.0 KB | 2026-07-31 | 2026-08-01 | `Status: ~~research complete~~ →` | Graphiti retired (D-070) |
| `docs/planning/sbv-mcp-integration-plan.md` | 4.4 KB | 2026-08-02 | 2026-06-25 | — | Superseded by D-131 (donor, not fork) |
| `docs/planning/sbv-fork-plan.md` | 9.1 KB | 2026-07-09 | 2026-07-09 | `Status: DRAFT for owner sign-off` | Same. Paired edit: `COORDINATION.md`; ADR-0033 gets a dated footnote, never an edit |
| `docs/planning/repo-restructure-spec.md` | 15.9 KB | 2026-07-09 | 2026-07-08 | `Status: DRAFT for owner annotation` | Executed as ADR-0033 and the 09-01 restructure. ADR footnote only |
| `docs/planning/parser-iterations-inventory.md` | 31.6 KB | 2026-08-10 | 2026-07-10 | — | Superseded by the live decoder inventory. `DECISION_LOG` citation stays; path discoverable here |
| `docs/planning/ovh-data-to-ovh-files-cutover.md` | 4.9 KB | 2026-08-01 | 2026-08-01 | — | Cutover executed |
| `docs/planning/exec-tier-split-2026-07-19.md` | 2.8 KB | 2026-07-19 | 2026-07-19 | — | Split executed |
| `docs/planning/conversation_ingestion_system_design.md` | 25.1 KB | 2026-09-01 | — | — | Superseded by the ingest plan lane |
| `docs/planning/forensic-db-extension-and-reconciliation-addendum.md` | 7.0 KB | 2026-08-02 | 2026-06-30 | — | D-142 makes the 93-table schema history |
| `docs/planning/Claude - chat pipeline for PostgreSQL - Claude.md` | 132.9 KB | 2026-09-01 | — | — | Raw chat transcript in a planning tree |
| `docs/planning/agno-cookbook-adoptions.md` | 8.6 KB | 2026-08-02 | 2026-08-02 | — | Agno retired as orchestrator (D-107) |
| `docs/planning/transcript-mining-pipeline-spec.md` | 6.3 KB | 2026-07-01 | 2026-06-19 | `Status: DRAFT for review` | Lines 94/101 assert an Agno-agent architecture (drift D-5); superseded by the transcript-miner agent |
| `docs/planning/gui-build-plan.html` | — | tracked | — | — | Generated artifact |
| `docs/planning/restructure-report.html` | — | tracked | — | — | Generated artifact |
| `docs/plans/WAVE1-pre-mortem-2026-08-14.md` + `WAVE1-subplan` + `W1.2`–`W1.5` (6 files) | 113 KB | 2026-08-15/23 | 2026-08-14/15 | `BUILD COMPLETE — validated in rollback; NOT applied` | Doubly superseded: own R0 audit banner and ADR-0059's per-source-clock redesign. 9 unchecked items already registered |
| `docs/plans/R10-PHASE0-P0.1`…`P0.5`, `R11`, `R12` (7 files) | 33 KB | 2026-08-16/23 | 2026-08-16 | — | Surreal Phase-0 packet; rulings landed as D-064, then superseded by D-107/D-142 |
| `docs/plans/chat-ingest-before-after-visual.md` | 2.9 KB | 2026-08-13 | 2026-08-13 | — | One-shot explainer for a superseded migration |
| `docs/handoffs/2026-09-06-rename-followups/01-finish-directory-rename.md` | 2.6 KB | 2026-09-06 | 2026-09-06 | README: **DONE 2026-09-06** | Executed; defects fixed by hand, recorded in register §9 |
| `docs/reviews/2026-09-05-live-deploy-run.md` | 17.9 KB | 2026-09-06 | 2026-09-05 | `Status running` | A run log; the outcome lives in the live-chain review |
| `docs/reviews/2026-09-03-three-day-incident-reconciliation.md` | 10.0 KB | 2026-09-06 | 2026-09-03 | — | Incident photograph; lessons already in the relitigation review |
| `docs/reviews/2026-09-02-ingest-day-board.md` | 17.0 KB | 2026-09-06 | 2026-09-02 | — | Board snapshot superseded by the 09-05 chain and the desk artifact |
| `docs/reviews/2026-09-02-ingest-day-board-appendix-codex-state.md` | 27.9 KB | 2026-09-06 | 2026-09-02 | — | Appendix to the above |
| `docs/reviews/2026-09-02-n8n-uiw-binding.md` | 34.6 KB | 2026-09-06 | 2026-09-02 | — | Binding proven; superseded by the rehearsal and the live chain |
| `docs/reviews/2026-09-02-uiw-schema-admission-unblock.md` | 29.0 KB | 2026-09-06 | 2026-09-02 | — | Unblocked; migration 0066 applied |

### 2.5 OWNER-DECIDES — per-file

| Path | Size | Last git change | Byline | Status marker | Question |
|---|---|---|---|---|---|
| `docs/MASTER-TODO-2026-08-18.md` | 17.6 KB | 2026-09-06 | 2026-08-29 | `Status correction … owner-ordered reconciliation` | Q3 — does it or the open-work register own "what is open"? |
| `docs/OWNER-REVIEW-2026-08-18-verified-todo-audit.md` | 16.8 KB | 2026-08-29 | 2026-08-18 | — | Q3 — travels with MASTER-TODO either way |
| `docs/HANDOFFS.md` | 24.1 KB | 2026-08-29 | 2026-06-13 | "status is recorded in the newest R9 addendum" | Q4 — R0–R14 router into `awaiting-verification`; its fate follows Q2 |
| `docs/BUILD_PLAN.md` | 19.1 KB | 2026-08-29 | 2026-07-11 | 6 strike-throughs | Q5 — `INDEX.md` calls it the forward entry point; content frozen 2026-08-23 and contradicted by the ingest plan |
| `docs/COMPACT-SUMMARY-2026-08-18.md` | 0.9 KB | UNTRACKED | hook | — | Q6 — OW-146: diverged fragment of the same log stream as its `awaiting-verification/summaries/` twin |
| `docs/planning/2026-09-06-sftpgo-file-surface.md` | 11.4 KB | UNTRACKED | 2026-09-06 | `STATUS: PROPOSED — not deployed` | Q12 — competes with Filestash/FileBrowser; no app, no compose file |
| `docs/planning/forensic-staging-schema.sql` | — | tracked | — | — | Q9 — SQL in a docs tree |
| `docs/planning/forensic_staging_test.sqlite` | — | tracked | — | — | Q9 — a test database in a docs tree |
| `docs/pending-review/atomic-parse-driver-20260906/README.md` | 0.9 KB | UNTRACKED | 2026-09-06 | — | Q8 — the parse-proof receipt; promote the text, relocate the code |
| `docs/pending-review/atomic-parse-driver-20260906/main.go` | — | UNTRACKED | — | — | Q8 — Go source in a docs tree; `go.mod` line 23 still points at the pre-rename path |
| `docs/pending-review/atomic-parse-driver-20260906/go.mod` | — | UNTRACKED | — | — | Q8 |
| `docs/pending-review/atomic-parse-driver-20260906/go.sum` | — | UNTRACKED | — | — | Q8 |
| `docs/pending-review/atomic-parse-driver-20260906/build/atomicparse-linux-amd64` | binary | UNTRACKED | — | — | Q8 — a compiled binary must not live in `docs/` |
| `docs/.claude/memories/project_memory.json` | — | UNTRACKED | — | — | Q14 — a memory store inside `docs/`; belongs to the memory lane, not this sweep |

### 2.6 Cluster rows — 1,135 files

Adopted from `docs/reviews/2026-09-05-docs-consolidation-audit.md` §4.3/§4.4 with counts
re-measured 2026-09-06. Per-file rows above override any cluster row.

| Cluster | Files | Classification | Reason |
|---|---|---|---|
| `docs/wiki/**` | 580 | **OWNER-DECIDES** | OW-063. `docs/wiki/INDEX.md:1-3` documents *dial-stack*, a different product. **Blocked by OW-001** — `docs/wiki/archive/.planning/**` holds git-tracked credential literals; archiving does not remove them from history |
| `docs/awaiting-verification/**` | 78 | **OWNER-DECIDES** | OW-004. Purgatory since 2026-08-18; README declares every claim UNVERIFIED. Blocked by Q6 until `COMPACT-SUMMARY-2026-08-18` is merged |
| `docs/reports/_stale/recovery-run1-203756/**` | 123 | ARCHIVE | Recovery run #1 stubs; many carry `e3b0c44298fc` (SHA-256 of the empty string) = failed recoveries. Gitignored — plain `mv` |
| `docs/reports/recovery/**` + `docs/reports/*` | 28 | CURRENT-KEEP | Current recovery output + skill inventories; 1 of 151 files tracked by design |
| `docs/planning/forensic-db-reconciliation/**` | 50 | ARCHIVE | Records a real 2026-06-30 migration to a 93-table schema. **D-142 makes it pure history** — that database no longer exists. Grep and repoint `BEHAVIORAL_DETECTION_EXPLAINED.md` first |
| `docs/planning/forensic-db-architecture/**` | 35 | ARCHIVE | 91k-word SPEC-1 draft, never merged into canon, self-bannered DRAFT. **Precondition:** extract the unique court-safety rationale (owed since 2026-08-15) |
| `docs/planning/chat-sample-analysis/**` | 22 | CURRENT-KEEP | "Nothing decided here — this maps what's actually IN the chats." Completed discovery over the owner's real corpus; irreplaceable, non-iterating, gitignored |
| `docs/planning/architecture-directives/**` | 9 | **OWNER-DECIDES** | OW-107. Its `INDEX.md` says ACTIVE; every file inside says DRAFT / DESIGN-ONLY / not-deployed, three months and ~40 ADRs later |
| `docs/planning/goals-archive/**` | 9 | ARCHIVE | Self-declared archive |
| `docs/planning/ui-vision/constellation-mockup.html` | 1 | ARCHIVE | Static mockup; mockup history is never production truth |
| `docs/reviews/2026-08-*` top level | 27 | ARCHIVE ×23 · CURRENT-KEEP ×3 · OWNER-DECIDES ×1 | Point-in-time receipts. Six carry retired-architecture names (Authentik forward-auth, AgentOS, SBV-as-fork) and need a superseded banner appended before the move. The one owner row is `2026-08-29-nocodb-quarantine-receipt.md` — "OWNER DELETE PENDING", OW-026 |
| `docs/reviews/2026-08-25-schema-audit/**` | 54 | ARCHIVE ×51 · CURRENT-KEEP ×3 | GAP-001…034 against a database torn down twice since. The three TIMESKETCH/R09 files are cited by `server/timeline/AGENTS.md` — never archive those |
| `docs/reviews/2026-08-23-cross-repo-evidence-audit/**` | 34 | ARCHIVE ×33 · CURRENT-KEEP ×1 | `ISSUES-AND-TODO.md` (47+ ISS ids) is a live register with no disposition pass (OW-069) |
| `docs/reviews/2026-08-31-external-reviews/**` | 5 | ARCHIVE | Superseded by `repo-rereview-validation-and-dispatch-2026-09-01.md`, which is the verdict on them |
| `docs/reviews/agent-tooling/**` | 2 | ARCHIVE | Two closed one-off hook repairs |
| `docs/research/integration-audit-2026-08-24/**` | 30 | ARCHIVE ×28 · OWNER-DECIDES ×2 | Six `lane-*.md` analyses are durable and archive as evidence; the two raw npm catalogs (8.3 MB JSONL) are scrape dumps that do not belong in a doc tree — Q10. `.duckdb/AGENTS.md` references one |
| `docs/research/N8N-CAPABILITY-ASSESSMENT-2026-08-25.md` | 1 | CURRENT-KEEP | Live capability assessment; carries a stale Milvus claim (OW-057) — dated correction, not a move |
| `docs/design/**` | 14 | CURRENT-KEEP | 2026-08-29/09-01 design sessions plus `0061-unified-operator-surface/spec.md`, the accepted production composition. `classification-sentiment-test-system.md` has no byline (OW-066) |
| `docs/blueprint/**` | 4 | CURRENT-KEEP | The three-layer blueprint. **Carries drift D-4 and D-6** — fix `architecture.md:99` and `:23`, `index.md:22`; the `docs/blueprint` vs `.agents/blueprint` canonical question is OW-003 |
| `docs/recovered/**` | 6 | CURRENT-KEEP | Only surviving record of the retired GraphRAG comparison lane; the source `.py` files are gone |
| `docs/schema/**` + `docs/schemas/**` | 11 | CURRENT-KEEP | Machine-consumed contracts; `catalog.json` is generated from the live DB |
| `docs/runbooks/**` | 3 | CURRENT-KEEP | `go-live-case-registry.md` is 2026-09-02; `MIGRATION-0036-CONTEXT-IMPORT.md` has no byline (OW-066) |
| `docs/CLAIMED_COMPLETE_LIKELY_LIES/**` | 7 | CURRENT-KEEP ×4 · ARCHIVE ×1 · OWNER-DECIDES ×2 | Keep the folder and its name — it is honest and doing its job. `D-072-D-080-backfill.md` archives (verified merged, OW-125). The two 2026-08-30 Workbench "LIVE VERIFIED" claims are Q11 |
| `docs/visualizations/**` | 1 | ARCHIVE | Single generated artifact |
| `docs/agent-memory/README.md` | 1 | CURRENT-KEEP | Counted in the per-file table; listed here for cluster reconciliation only |

---

## 3. Merge map

For each MERGE-INTO row: what the source carries that the target lacks, and what happens to the
remainder. **The remainder always archives with a pointer — it is never deleted, and it is never
summarized away.** Where a source contains an owner ruling, the ruling's home is
`docs/DECISION_LOG.md` (a new row, never an edit to an old one) and its operational form is the
plan; the source document then archives as the evidence behind it.

### 3.1 The 2026-09-06 analysis chain → the ingest plan

Target: `docs/planning/2026-09-03-ingest-redesign-plan-and-sequential-guide.md`.

| Source | Carries that the plan lacks | Remainder |
|---|---|---|
| `docs/reviews/2026-09-06-storage-copies-recall-pass.md` | The finding that **3 of 7 morning proposals were restatements of already-settled rulings** (Q1=C, the 2026-09-03 DuckDB ruling, the 11:43 attachments ruling), and which 4 were genuinely open. This is the recall-gate evidence — it belongs as a short "already settled, do not re-open" block at the head of the plan's stage list | Archive as evidence for the relitigation lane (OW-050/051/052) |
| `docs/reviews/2026-09-06-storage-copies-and-derived-layers-thinking-pass.md` | The measured footprint split — **text-side savings ≈0.2%, attachments ≈99.8%, vectors ≈8 KB/chunk** — which is the quantitative basis for D-149 clauses 5–8. The plan asserts the clauses without the numbers. Also the explicit **withdrawal** of "operator time is the bottleneck" (owner, 12:12) | Archive |
| `docs/reviews/2026-09-06-chunks-live-in-weaviate-systems-pass.md` | The four owner answers that **amend D-149 items 7–8** (Weaviate holds the chunk search object with vector + member ids + PG coordinate, no text; hits return messages from PG; rebuild from PG id lists; write path = PG row + outbox). The amendment is currently only in this 2.6 KB review | The amendment goes into the plan **and** into a new `DECISION_LOG` row citing D-149. D-149's own row is not edited. Archive the review |
| `docs/planning/2026-09-06-derived-layers-change-map.md` | The entire file:line execution map — migrations 0073–0077, `profferworker/worker.go:49-60` (ELT activity registered on no worker), the `EvidenceChunkV2` consequence of Weaviate-no-text, the struck §3d attachment lines, the SMS-file-not-verified note | Becomes the plan's execution annex. Nothing archives |
| `docs/reviews/2026-09-06-ingest-to-surreal-thinking-pass.md` | Analysis of the context → Surreal → evidence lifecycle (D-145/D-146) with nothing ruled | Fold the parts that survive D-149; archive the rest |
| **D-149** (`docs/DECISION_LOG.md`) | Twelve clauses that are the current ingest contract | **Stays where it is, append-only.** The plan cites it clause by clause; the plan never restates it as if it were the source |

Ordering note: the change map is the only source whose content is wholly execution-shaped. Merge
it first; the three review passes then fill in the *why* behind clauses the map already implements.

### 3.2 The five handoff/compact artifacts → one handoff + one register

Targets: `docs/HANDOFF-2026-09-06-ingest-rulings-and-parser-fix.md` (state) and
`docs/consolidated/OPEN-WORK-REGISTER-2026-09-05.md` (open items).

| Source | To the handoff | To the register | Remainder |
|---|---|---|---|
| `docs/HANDOFF-2026-09-06-…` (the target) | — | Its UNRESOLVED block is 6 items that exist as prose, not rows: the real-workflow proof run, the uncommitted parser fix, the Postgres persistence redeploy, the PII check on the SAT labels file, the rename reconciliation, the owner-deletes cleanup list | Stays; the handoff keeps a one-line pointer per item into the register |
| `docs/COMPACT-SUMMARY-2026-09-06.md` (79 KB, 3 blocks) | The "sealing at ingest = the custody-at-ingest he told me to kill" ruling and its exact resolution ("a SHA attached on a table to the file; revalidate at promotion") — this is D-149 clause 1's provenance | The D-145..D-148 ruling list, and the record of the two seal files the guard refused to quarantine. **Note the supersession:** the summary says `sealfile.go` and `cmd/proffer-seal/main.go` are still in place; `docs/HANDOFF-2026-09-06-…:24` says the seal code is parked at `modules/engine/parked/seal/` with a `//go:build parked` tag. Newest wins — the handoff. Carry only the ruling, never the summary's file-state claim | Archive to `2026-09/summaries/` (plain `mv`, untracked) |
| `docs/reviews/2026-09-06-ingest-session-digest.md` (70 KB) | §7 one-paragraph resume brief — the most compact accurate statement of settled-vs-open in the tree | **§6 in full** — ~40 open items, most of which appear nowhere else: B2 backup automation broken since 2026-08-01; the Docker `default-address-pools` durable fix; the `sbv-forensic` repo reconciliation (+10,973 lines); `SBV_CUSTODY_ENABLED` defaulting to skip; zero tests on the immutability gates; 26–27 carried pytest failures; five open ADR-0049 gaps; OCR/VLM selection unbenchmarked; participant→`entity_resolution`→`id_xref` unimplemented; Google Photos comments shape unverified; Coolify watch-path re-scoping unconfirmed; the Lost and Found corpus never ingested | §1's 15 failure patterns are a durable teaching artifact — promote the pattern list into `docs/CONVENTIONS.md` or `docs/reviews/2026-09-02-relitigation-pattern-and-fix.md`, then archive the digest |
| `docs/reviews/2026-09-06-naming-and-rename-session-digest.md` (415 KB) | Nothing — the rename outcome is already in `NAMING.md` and the live-change register | Any live change in it **not already in `docs/registers/RENAME-LIVE-CHANGES-2026-09-06.md`** must be appended to that register before the digest moves. Also its "tool gateway not deployed" lines (3557, 3770) are stale and must not be carried forward | Archive to `2026-09/summaries/`. This single file is 8× the median doc |
| `docs/handoffs/2026-09-06-rename-followups/README.md` | Nothing | Rows 02–07 become register rows with their owner-gate flags intact: deny-list restore (owner's settings file), R2 dev-fixtures copy (billable sign-off), golden-clone teardown (before touching `platform`), 18 identifier rulings, the indagatio split plan, memory-tooling repairs | The README becomes a two-line pointer at the prompt files; the six prompt files stay CURRENT-KEEP until executed |
| `.remember/now.md` (outside `docs/`) | Nothing — it is three days stale and asserts a question D-149 clause 9 closed | Nothing | **Not a move.** Refresh or clear it in the same change that ratifies the handoff, so the two do not disagree (drift D-9) |

### 3.3 `docs/pending-review/**` — promote or archive, item by item

One directory, five files, all untracked: `atomic-parse-driver-20260906/`.

| Item | Disposition |
|---|---|
| `README.md` | **Promote** the parse-proof text into `docs/reviews/` as a dated receipt (it is the evidence for "SMS 11,676/11,676, calls 1,457/1,457, iMessage HTML 1,918, TXT 1,918") and reference it from the handoff |
| `main.go`, `go.mod`, `go.sum` | **Promote out of `docs/`** to `modules/engine/cmd/atomicparse/`. It is a real tool that produced a real proof and will be run again. `go.mod:23` still carries the pre-rename absolute path `…/Agno-MCP-Platform/modules/forks/sbv` — fix on the move |
| `build/atomicparse-linux-amd64` | **Do not keep a compiled binary in `docs/`.** Move to a build/scratch path or drop it (the source rebuilds it) — owner's call, Q8 |

### 3.4 Other MERGE-INTO rows

| Source | Target | What carries |
|---|---|---|
| `docs/planning/2026-09-03-ingest-simplification-plan.md` | the ingest plan | Its stage-by-stage table of the 26-stage workflow and the five hash stages with the "ALL FIVE STAY" ruling; the `custody.py:418-427` "leftover to remove" identification; the `elt_structured_repository.go:65` canon-deviation call. **Do not carry** its Google Voice or gateway-undeployed claims |
| `docs/plans/TEMPORAL-INTEGRATION-PLAN-2026-08-23.md` | the ingest plan | The phased-adoption reasoning and the versioning/`workflow.patched()` gap. **Do not carry** "Agno agents/teams/knowledge stay as they are" (line 53) |
| `docs/planning/reingest-etl-pipeline.md` | the ingest plan | Whatever of its ETL shape survives D-149 clause 12's four ELT strictness gates |
| `docs/planning/contextforge-adoption-list.md` | register | The un-adopted worklist items, one row each |
| `docs/plans/uiw-preview-contract.md` | register | OW-038: upstream Go surface, deployment, live proof |
| `docs/DOC_CLEANUP_MANIFEST-2026-08-15.md` | register | Its five UNRESOLVED questions (OW-003), including the `docs/blueprint` vs `.agents/blueprint` canonical question |
| `docs/UNRESOLVED-QUESTIONS-2026-08-16-surreal-…md` | register | The rows not resolved by D-064 |
| `docs/HANDOFF-2026-08-29-agno-role-dissection.md` | register | Every live release hold, as its own row. **Item-level merge** — this doc is the current AgentOS-cutover authority and losing a hold in a summary would be a live risk |
| `docs/HANDOFF-2026-08-29-derived-document-ingest-wiring.md` | register | WP-1…WP-11 rows, WP-10/WP-11 still open (OW-017/018) |
| `docs/HANDOFF-2026-08-18-evidence-operations-desk-mvp.md` | register | "NOT COMPLETE — resume at step 1" as one row |
| `docs/reviews/2026-09-05-h04-bridge-and-weaviate-feed-rewire.md` | register | Built-not-deployed row |
| `docs/reviews/2026-09-04-outbox-part1-build.md` | register | Built-not-committed-not-applied row |
| `docs/reviews/2026-09-02-feature-flag-integrity-audit.md` | register | The `SBV_CUSTODY_ENABLED` default and the untested immutability gates |

---

## 4. Drift findings

Contradictions between documents that **both** currently claim to be current. Each cites the
file and line. Rule applied: the newest owner-approved statement wins. Nothing below is fixed
by this plan.

**D-1 · Two current ingest plans disagree on the first real ingest.**
`docs/planning/2026-09-03-ingest-simplification-plan.md:299` — *"First real ingest: **Google
Voice** — ~29,300 HTML conversation files…"* — against
`docs/planning/2026-09-03-ingest-redesign-plan-and-sequential-guide.md:216` —
*"~~Google Voice as the first real ingest~~ STRUCK."* Both files carry
`STATUS: ITERATING — NOT DONE` and both were touched 2026-09-06.
Winner: STRUCK. Desk answer Q20 (2026-09-06 10:33): first real ingest = SMS Backup & Restore
XML and iMessage; *"Snapchat and Google Voice are the least significant."*

**D-2 · The winning plan contradicts itself on the same point.**
`…-redesign-plan-and-sequential-guide.md:400` still carries the heading
*"### Stage 3 — First real ingest: Google Voice (~29k HTML + 502 MP3)"* while line 216 of the
same file strikes exactly that claim. A reader who opens at Stage 3 gets the retired answer.

**D-3 · Tool gateway: deployed, or not.**
`docs/HANDOFF-2026-09-06-ingest-rulings-and-parser-fix.md:21` — *"Gateway / Stage 2 | DONE
2026-09-05: `svc:tool-gateway` live, worker repointed, rehearsal reached the HITL repair gate
(9 stages)"* — against three current statements:
`…-redesign-plan-and-sequential-guide.md:571` — *"Tool gateway is built + tested, NOT deployed.
Diagram must not draw it live."*;
`…-ingest-simplification-plan.md:174` — *"| Tool gateway | … | built, **undeployed** |"*;
`…-ingest-simplification-plan.md:297` — *"1. Deploy `deploy/tool-gateway.yaml` on ovh-app"* as
future work. Also stale at `docs/reviews/2026-09-06-naming-and-rename-session-digest.md:3557`
and `:3770`.
Winner: deployed. Receipt: `docs/reviews/2026-09-05-tool-gateway-live-deploy.md`.

**D-4 · "Milvus is down", unqualified, in a current document.**
`docs/blueprint/architecture.md:99` — `MV[("Milvus — DOWN, deliberate")]` — against
`docs/registers/SETTLED.md:26` — *"The Milvus service (`100.91.190.107:19530`…) is UP and IS
memsearch's backend… **NEVER say 'Milvus is down'**"* (owner correction 2026-09-03, repeated
angrily across multiple sessions). This is OW-057, raised 2026-09-05, still standing.
Three further hits are role-scoped and therefore inside the ruling, but none names memsearch and
each reads as an unqualified claim on a skim: `docs/PROJECT_CANON.md:222`, `docs/PROJECT_CANON.md:414`,
`docs/DEBT.md:189`. One archive-bound doc also carries the bare form:
`docs/HANDOFF-2026-08-24-ingest-testing.md:25`.

**D-5 · "Agno agents" as a live orchestration claim, after D-107 retired Agno as orchestrator.**
`docs/CONVENTIONS.md:34` — *"Agno agents inside the platform consume the same docs via the
knowledge engine"* (canon, last changed 2026-09-06).
`docs/PROJECT_CANON.md:433` — *"Agno agents use `graphiti-core` in-process"* — doubly stale:
Agno retired as orchestrator (D-107) **and** Graphiti retired (D-070).
`docs/EVIDENCE_MERGE_MAP.md:7` and `:16` — *"TS tools run as MCP services behind Agno; Agno
agents call them as tools"* / *"Agno agents are builders and consumers of that platform."*
`docs/plans/TEMPORAL-INTEGRATION-PLAN-2026-08-23.md:53`;
`docs/planning/transcript-mining-pipeline-spec.md:94` and `:101`;
`docs/planning/TOOL_SOURCES_INVENTORY.md:117`.
Known and explicitly unruled: **ADR-0041 still literally reads "Agno agents"** — recorded as
open at `docs/reviews/2026-09-06-ingest-session-digest.md:452`. ADRs are append-only; the fix is
an appended dated note, and whether to append is the owner's call (Q15).

**D-6 · The old product name asserted as current, unstruck, in living documents.**
Against `docs/NAMING.md` §3 (D-138: `Agno-MCP-Platform` → **Indicia Probata** / `probata`) and
the correctly-struck model at `docs/COORDINATION.md:1`:
`docs/CHANGE-ORDER.md:1` — *"# CHANGE-ORDER — Agno-MCP-Platform"*;
`docs/DECISION_LOG.md:1` — *"# DECISION LOG — Agno-MCP-Platform"* (title line only — rows are
append-only and are not touched; whether a title line may be amended is Q15b);
`docs/MEMORY_ARCHITECTURE.md:54` — *"`Agno-MCP-Platform/docs/`"*;
`docs/HANDOFFS.md:217`; `docs/blueprint/architecture.md:23` (`subgraph Platform["Agno-MCP-Platform"]`);
`docs/blueprint/index.md:22`; `docs/pending-review/atomic-parse-driver-20260906/go.mod:23`
(an absolute path that will break on a fresh checkout).
`docs/EVIDENCE_MERGE_MAP.md:53` and `:390` reference `Agno-MCP-Platform-alpha/` — that is a
literal workspace path for the donor parser core, **not** a product-name assertion; leave it.

**D-7 · SBV described as a fork, or as the platform's own surface.**
Against `docs/registers/SETTLED.md:15` (*"SBV is a DONOR (lowcarbdev, MIT), not a fork"*, D-131)
and D-149 clause 10 (*"SBV = decoder library → `modules/engine/decode/` subtree FIRST… Vite
viewer = client, ≠ HITL preview"*):
`docs/PROJECT_CANON.md:221` — *"`exec-platform-tools` (SBV forensic fork + tools-facade)"*;
`docs/COORDINATION.md:168`, `:219`, `:223`, `:296` — the subtree-split → fork → CI → tag-bump
contract that D-131 explicitly retires;
`docs/BUILD_PLAN.md:168` — *"SBV as Workflow A (custody-gated vertical + iframe + CLI + export)"*;
`docs/HANDOFF-2026-08-29-derived-document-ingest-wiring.md:505` — *"**SBV GUI** | inside
`platform-tools`, `:8085`"*.
`docs/AGENTS.md`'s own note that the SBV donor is credited to **lowcarbdev**, not danzek, is
already corrected — no action.

**D-8 · Custody hashing at ingest.**
Current rule: D-149 clause 1 —
`docs/HANDOFF-2026-09-06-ingest-rulings-and-parser-fix.md:30` — *"Custody sealing at PROMOTION
only; ingest retain = working copy + SHA row."*
Contradicted by:
`docs/PROJECT_CANON.md:324` — *"Tool architecture = polyglot orchestration mesh: universal
custody gate → named workflows A/B/C → atomic tools"* (custody at the entry gate);
`docs/PROJECT_CANON.md:259` — the TODO-207/TODO-101 line, *"custody hashing must first be
extracted into a standalone callable process"* before *"mandatory at capture"* is enforced —
capture-time custody, superseded;
`docs/DECISION_LOG.md:298` (D-123) — *"the client calls the … Activities ATOMICALLY (hash
first, always — the dedicated custody-hash Activity family)"*. D-123 is append-only and is
**not** to be edited; D-149 supersedes it, but nothing in the log cross-references the two, so a
reader arriving at D-123 gets the retired rule with no signal.
`docs/planning/2026-09-03-ingest-simplification-plan.md` is aligned — it names
`server/evidence/custody.py:418-427` as *"the leftover to remove."*

**D-9 · The session-memory pointer disagrees with the handoff.**
`.remember/now.md` (outside `docs/`, last written 2026-09-03 14:42) still describes the ingest
decision-desk artifact as incomplete with an *"unresolved Google Voice HTML routing rule
(extract-only via regex vs registered parser)"* — a question D-149 clause 9 closed and a source
D-1 struck. Three days stale, and it is what a resuming session reads first.

**D-10 · `docs/INDEX.md` routes to nothing current.**
Its Start-here table names `BUILD_PLAN.md` (content frozen 2026-08-23), `MASTER-TODO-2026-08-18.md`,
`INGESTION-READINESS-2026-08-23.md` ("written for tonight"), and three 08-18/08-29 handoffs. It
names **none** of: `docs/HANDOFF-2026-09-06-ingest-rulings-and-parser-fix.md`, either 2026-09-03
ingest plan, `docs/consolidated/OPEN-WORK-REGISTER-2026-09-05.md`, or
`docs/registers/RENAME-LIVE-CHANGES-2026-09-06.md`. An agent that follows `AGENTS.md` to
`INDEX.md` as instructed lands on 08-18-era truth. `INDEX.md` was last committed 2026-09-06 —
the naming row was added, the routing was not revisited.

**D-11 · The archive rule has never once been followed, and the corpus is still growing.**
`docs/archive/README.md` states the rule: *"When a task is completed or superseded, remove it
from the active TODO/current handoff and move it here **in the same completion change**."*
`docs/archive/` contains exactly 1 file — its own README — 19 days after it was created.
Meanwhile `docs/` went from **1,337 files** (measured in the 09-05 audit §0) to **1,368** on
2026-09-06: +31 files in one day, zero archived. This is the loop the 09-05 audit §2 diagnosed,
observed running one more turn.

**D-12 · Two documents both claim to be the authoritative open-work ledger.**
`docs/INDEX.md` — *"Entire application TODO | MASTER-TODO-2026-08-18.md | Authoritative
production resume ledger."*
`docs/consolidated/OPEN-WORK-REGISTER-2026-09-05.md` — 101 open items, newer, and its own scope
note *defers* to MASTER-TODO instead of superseding it. Neither answers "what is open" on its
own, and the archive gate in the 09-05 audit §8 depends on exactly one of them doing so.

**D-13 · "Naming is ruled" and "18 identifier rulings are owed" are both current.**
`docs/NAMING.md` opens with *"naming is RULED at the product and component tier"*;
`docs/handoffs/2026-09-06-rename-followups/README.md` row 05 —
*"`05-identifier-rulings-needed.md` | any agent, in conversation with the owner | yes (18
rulings)"*. Not a logical contradiction (product tier vs identifier tier) but they do not
reference each other, so a reader gets "done" from one and "18 outstanding" from the other. One
cross-reference line in `NAMING.md` §2 closes it.

**Count: 13 drift findings.**

---

## 5. Execution order — for a later session, on owner go

Every step is a move, never a delete. Destination `docs/archive/2026-09/<category>/`.
*"Leaves a pointer"* means one line appended to `docs/archive/2026-09/INDEX.md` reading
`old path → new path → one-line why`, plus the paired edit named in the step — **not** a stub
file per moved document.

**Convention conflict to settle first:** the 09-05 manifest writes
`docs/archive/2026/<category>/`; this plan writes `docs/archive/2026-09/<category>/`. One must
win before any move. Recommendation: `2026-09/` — dated buckets make each sweep auditable and
cap how large any one bucket gets.

### Phase 0 — gate (no moves)

1. **Owner ratifies §1 (the target shape) and answers Q1–Q15 below.** Nothing moves before this.
2. **Fix the 13 drift findings in place** (dated corrections, strike-through, never silent
   deletion — `AGENTS.md` doc-drift rule). Order: D-10 (`INDEX.md` rewrite) first, because every
   later step is verified against what `INDEX.md` claims; then D-1/D-2/D-3 (they mislead the
   ingest lane, which is the live work); then D-4…D-9, D-13.
   *A Sonnet agent can do all of these unattended* — each is a located line with a named winner.
   Exception: D-5's ADR-0041 note and D-6's `DECISION_LOG.md` title line need Q15/Q15b first.
3. **Refresh `.remember/now.md`** to match the handoff (D-9). *Sonnet, unattended.*
4. **Commit the untracked current docs** — the 09-06 handoff, the four review/planning docs, the
   change map — **after** the PII check on
   `docs/reference/SAT-ACTION-CONTRADICTION-LABELS-2026-09-06.md` (it contains real names;
   `git grep` the tracked tree before any commit that could sweep it in). *Owner-supervised;
   explicit path allowlist, never `git add -A` (shared-worktree rule).*

### Phase 1 — merges (no moves yet)

5. **Merge §3.1** — change map into the ingest plan first, then the three review passes.
   *Opus-class judgement; the amendment to D-149 items 7–8 must land as a new `DECISION_LOG`
   row, not an edit.*
6. **Merge §3.2** — every open item from the five handoff/compact artifacts into the open-work
   register, item by item. *Sonnet can do the mechanical extraction; a reviewer must confirm no
   item was lost, because this is the archive gate.*
7. **Merge §3.4** — the remaining eleven MERGE-INTO sources.
   *Sonnet, unattended, except the two 08-29 handoffs (they carry live release holds — read
   item-level, do not summarize).*
8. **Run the 09-05 audit §8 proof checklist** — six mechanical checks including "every archived
   file's open items are in the register" and "the broken-link count did not increase"
   (baseline: 152 broken intra-docs links). *Sonnet, unattended.*

### Phase 2 — moves that need no owner input

9. **Batch A of the 09-05 manifest, unchanged** — 46 `git mv` commands, 52 files, zero reference
   updates, verified by an inbound-reference scan. *Sonnet, unattended.* This alone removes 52
   files from the working set.
10. **This plan's additions to Batch A** — the ARCHIVE rows in §2.4 that the 09-05 manifest did
    not have: the six 2026-09-02/03/05 reviews, `01-finish-directory-rename.md`,
    `agno-cookbook-adoptions.md`, `transcript-mining-pipeline-spec.md`,
    `conversation_ingestion_system_design.md`, the two planning `.html` artifacts,
    `COMPACT-SUMMARY-2026-09-06.md`. *Sonnet, unattended, after step 6 proves their items are in
    the register.*
11. **Batch B — 9 moves, each with its paired edit** (`INDEX.md`, `BUILD_PLAN.md`,
    `sql/AGENT_MEMORY.md`, `COORDINATION.md`, `RENAME-BLAST-RADIUS`; ADR-0033 gets an appended
    dated footnote, never an edit). Preconditions: extract the court-safety rationale from
    `forensic-db-architecture/` and repoint `BEHAVIORAL_DETECTION_EXPLAINED.md`.
    *Sonnet for the moves; the rationale extraction is Opus-class.*
12. **Batch D — untracked/gitignored, plain `mv` not `git mv`**: the compact summaries, the TODO
    snapshots, `reports/_stale` (123 files). Hold `COMPACT-SUMMARY-2026-09-03.md` until last.
    *Sonnet, unattended.* `git mv` **will fail** on these — `docs/reports/**` is gitignored.
13. **Move the reviews/planning historical subtrees** — schema-audit (51 of 54),
    cross-repo-evidence-audit (33 of 34), external-reviews, agent-tooling,
    `forensic-db-architecture`, `forensic-db-reconciliation`, `goals-archive`, `ui-vision`,
    `visualizations`. *Sonnet, unattended, after the three `server/timeline/AGENTS.md`-cited
    files and `ISSUES-AND-TODO.md` are pinned as CURRENT-KEEP.*

### Phase 3 — owner-gated moves

14. Execute whichever of Q1–Q14 the owner ruled, in the order the answers allow. Q1 (`docs/wiki/`)
    is **blocked by OW-001** — the credential literals must be redacted and anything live rotated
    first; archiving does not remove them from git history.

### Phase 4 — close the loop (otherwise generation 7 arrives in three weeks)

15. Add to `docs/CONVENTIONS.md`: *a change that supersedes a document moves that document to
    `docs/archive/<yyyy-mm>/` in the same commit, after its open items are in a register.*
    (The 09-05 audit §11 intervention 1; also OW-052's F4 edit.)
16. Add a CI check: *no tracked file references a path that does not exist.* Converts the fear
    that blocks retirement into a build failure. (§11 intervention 2.)
17. Standing rule: compact summaries older than 14 days move to `docs/archive/<yyyy-mm>/summaries/`
    automatically. (§11 intervention 3 — this alone would have removed ~545 KB with no judgement
    calls.)

### Owner questions, with a recommended answer for each

| # | Question | Recommendation |
|---|---|---|
| **Q1** | `docs/wiki/` — 580 files (43% of `docs/`) of another product's wiki (dial-stack). Archive whole, or keep? | **Archive whole** to `docs/archive/2026-09/wiki-dial-stack-donor/` (09-05 KT score 83). It is genuine ADR-0022 donor material, so it must not be lost — but it must stop competing with real docs. **After OW-001 redaction + rotation.** |
| **Q2** | `docs/awaiting-verification/` — 78 files in purgatory since 2026-08-18. | **Archive whole, as-is**, README's UNVERIFIED banner intact (KT score 82). Archiving changes nothing epistemically and everything about attention. Blocked by Q6. |
| **Q3** | `MASTER-TODO-2026-08-18` or `OPEN-WORK-REGISTER-2026-09-05` — which owns "what is open"? | **The register.** Newest, and the only one that enumerates its own boundary. MASTER-TODO's open rows merge in; MASTER-TODO and its OWNER-REVIEW companion archive together; `INDEX.md`'s row repoints. |
| **Q4** | `docs/HANDOFFS.md` — the R0–R14 packet router into `awaiting-verification`. | **Follows Q2.** If the tree archives, the router archives with it and `INDEX.md` points at the register instead. |
| **Q5** | `docs/BUILD_PLAN.md` — `INDEX.md` calls it "the forward entry point"; its content froze 2026-08-23 and it is contradicted by the ingest plan (SBV-as-Workflow-A, drift D-7). | **Demote and archive.** The forward entry point becomes the ingest plan; BUILD_PLAN's still-live rows merge into the register. |
| **Q6** | `COMPACT-SUMMARY-2026-08-18.md` (OW-146) — diverged fragment of the same log stream as its `awaiting-verification/summaries/` twin. | **Merge the two, then archive both.** One mechanical diff; it unblocks Q2. |
| **Q7** | `docs/planning/architecture-directives/` (9 files) — `INDEX.md` says ACTIVE, every file says DRAFT/not-deployed, three months and ~40 ADRs later (OW-107). | **Archive**, unless the owner names a directive still in force. It cannot be both active and never-deployed. |
| **Q8** | `docs/pending-review/atomic-parse-driver-20260906/` — Go source plus a compiled Linux binary inside `docs/`. | **Promote source to `modules/engine/cmd/atomicparse/`** (fixing the pre-rename absolute path in `go.mod:23`), promote the README as a dated review receipt, **do not keep the binary in `docs/`**. |
| **Q9** | `docs/planning/forensic-staging-schema.sql` + `forensic_staging_test.sqlite`. | **Move out of `docs/`**: the `.sql` to `sql/parked/`, the `.sqlite` to a data or scratch path. Neither is documentation. |
| **Q10** | `docs/research/integration-audit-2026-08-24/` — two raw npm catalogs, 8.3 MB of JSONL. | **Move out of `docs/`** to a data/scratch path and repoint `.duckdb/AGENTS.md`. Scrape dumps are not documentation. |
| **Q11** | The two 2026-08-30 Workbench docs in `CLAIMED_COMPLETE_LIKELY_LIES/` claiming "LIVE VERIFIED". | **Re-verify or re-label.** Either promote with evidence or leave quarantined with a dated note saying why. Never silently promote a completion claim. |
| **Q12** | `docs/planning/2026-09-06-sftpgo-file-surface.md` — PROPOSED, not deployed; competes with Filestash (recommended) and FileBrowser (parked). | **Keep as a proposal under one register row** ("operator file surface — undecided"), not as plan-of-record. Do not archive; do not treat as ratified. |
| **Q13** | `docs/reviews/2026-08-29-nocodb-quarantine-receipt.md` — "OWNER DELETE PENDING" (OW-026). | **Rule it.** One line closes a hold that has stood since 2026-08-29. |
| **Q14** | `docs/.claude/memories/project_memory.json` — a memory store inside `docs/`. | **Memory lane owns it.** Leave in place or relocate under the memory tree; do not archive it with documentation. |
| **Q15** | ADR-0041 still literally reads "Agno agents" after D-107 (drift D-5). ADRs are append-only. | **Append a dated superseding note** citing D-107. Never edit the ADR body. |
| **Q15b** | `docs/DECISION_LOG.md:1` and `docs/CHANGE-ORDER.md:1` carry the old product name in their **title lines** (drift D-6). Rows are append-only; a title is not a row. | **Amend the title lines with a strike-through + dated correction**, exactly as `COORDINATION.md:1` already does. No row is touched. |
| **Q16** | Archive path convention: `docs/archive/2026/<category>/` (09-05 manifest) or `docs/archive/2026-09/<category>/` (this plan). | **`2026-09/`** — dated buckets keep each sweep auditable and bounded. |

---

## 6. What this plan does not cover

- **`docs/wiki/` credential literals (OW-001, P0).** `docs/wiki/archive/.planning/**` contains
  git-tracked credential-shaped literals. This plan flags them as a **separate owner item** and
  blocks Q1 on them. Archiving does not remove a value from git history; the disposition is
  redact-in-place with a dated correction plus rotation of anything still live, and that is the
  owner's call, not a documentation move.
- **`docs/private/` — 1 file.** Private data. Excluded from every count that classifies content,
  never read, never moved, never described.
- **Memory stores — a separate lane.** `.remember/**` (5.9 MB, gitignored), the cwd-keyed
  auto-memory store, memsearch/Milvus, Graphiti, and `docs/.claude/memories/` are not
  documentation and are not swept here. The one exception is a pointer refresh:
  `.remember/now.md` must stop contradicting the current handoff (drift D-9). The rename lane's
  `07-memory-tooling-repairs.md` owns the rest.
- **Code-side docstring and comment drift.** Module docstrings, `# STUB:` tags, `AGENTS.md`
  files nested under `server/`, `modules/`, `sql/`, `deploy/`, and Go package comments are
  outside `docs/` and outside this sweep. Known live examples that belong to that lane, recorded
  here only so they are not lost: the root `AGENTS.md` `deploy/docker` row, the
  `deploy/compose.yaml` platform-tools block, and the two leftover `universal_import`
  identifiers in `server/tools/parsers/messaging/sbv_sms.py` and `server/tools/_sbv_client.py`
  (all three named in the 09-06 handoff's "Owned drift" line).
- **`docs/adr/**` (63 files).** Counted, never moved, never edited. Supersession is an appended
  banner or a new ADR. Q15 is the only ADR-adjacent question here and it is an append.
- **`docs/DECISION_LOG.md` rows.** Counted, kept, never edited. Every correction this plan
  implies to a past ruling lands as a **new** row citing the old one.
- **Execution.** No file was moved, archived, edited, or deleted in producing this plan. The
  only new file is this one.
