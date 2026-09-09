# awaiting-verification/ — Full Inventory & Recommended Dispositions

> _Byline: Claude Code · Fable 5 (orchestrator) + 5 Sonnet inventory subagents · 2026-09-01_
> Executes H-09 task 3 (report-only; owner rules on each). Method: every file's claims
> cross-checked against `docs/DECISION_LOG.md` (D-001–D-121), `docs/DEBT.md`, and `docs/adr/`.
> A document's own PASS/DONE claim was never trusted; only independent corroboration counts.

**Totals: 75 files → 13 verified→archive · ~37 stale→quarantine · ~25 still-pending→keep.**

**The dominant pattern:** almost everything written 2026-07-13 through 2026-08-18 was
overtaken by the owner-ruled reversals of 2026-08-23 → 08-31: AgentOS retired (D-101/D-107),
Graphiti retired (D-070/D-095), evidence-at-ingest reversed to context-first (D-069),
Next.js Workbench retired (D-108), and the schema reckoning (D-108–D-121, 58 tables deleted).
Any doc assuming AG2/OrchestrationPort, AgentOS Knowledge bases, Graphiti belief graphs, the
R0–R8/S1–S9 wave structure, or `visible_from = COALESCE(realized_at, occurred_at)` is stale.

**Tooling defect surfaced:** 5 of 11 `summaries/` files contain ZERO content — just repeated
"Summary field not found in hook payload" JSON from a broken PostCompact hook on Codex
(gpt-5.6-sol) sessions. ~45% of that quarantine lane was junk from one hook bug.

## verified→archive (13) — independently corroborated

| File | Corroboration |
|---|---|
| evaluations/DOC-PATCH-REPORT-2026-08-16-phase0-owner-rulings.md | D-064 (+D-065 narrowing) |
| evaluations/EVALUATION-2026-08-16-surreal-investigation-phase0.md | D-064 — caveat: spec acceptance only, harness never built/run |
| handoffs/HANDOFF-2026-08-02-sbv-chatminer-parser-gap-review.md | DECISION_LOG cites it by name; DEBT item 1 LANDED PR #18; D-040 |
| handoffs/HANDOFF-2026-08-09-S1-docs-registers-true-up.md | DEBT.md carries its exact dated stamp; S4 gate = D-042 |
| handoffs/HANDOFF-2026-08-09-S10-compose-consolidation.md | D-043 names this handoff, done 2026-08-10 |
| handoffs/HANDOFF-2026-08-09-S4-adr-package-owner-rulings.md | D-042; ADR-0045/46/47 Accepted headers |
| plans/CONTRACTS-2026-08-16-surreal-investigation-phase0.md | D-064/D-065 |
| plans/GOALS-2026-08-15-surreal-investigation-memory.md | D-061/D-062/D-063/D-064 |
| plans/PENDING-OWNER-DECISIONS-SURREAL-INVESTIGATION-2026-08-16.md | D-064 reproduces S1–S6 verdicts near-verbatim |
| plans/PHASE1-DISPOSABLE-SURREAL-D2-PHYSICAL-PROPOSAL-2026-08-16.md | DEBT "D1/D2 complete; execution held" — archive the approval, not a green light |
| plans/SURREAL-INVESTIGATION-BLUEPRINT-2026-08-15.md | D-061–D-065; self-annotates its ADR-0059 supersession |
| summaries/COMPACT-SUMMARY-2026-08-12.md | D-053, D-054 (ADR-0052 signed), D-056 — dates+content match |
| summaries/COMPACT-SUMMARY-2026-08-14.md | DEBT.md "Report re-verification corrections (2026-08-14)" — archive findings; built Wave-1 code superseded |

## stale→quarantine (~37) — falsified or superseded by later rulings

Root/inventories/evaluations: DOC_PATCH_REPORT-2026-08-15 (subject architecture replaced by
D-101/D-107/D-108) · Horizon Platform Audit R0–R12 (snapshot; most findings since resolved per
DEBT) · INVENTORY-2026-08-09 (DA-series superseded by D-101/D-107).

Handoffs: 2026-07-27-vector-graph-transition (Memgraph never adopted D-095; Weaviate cutover
abandoned D-104) · 2026-07-30-current-tasklist · 2026-07-30-memory-knowledge-audit ·
2026-08-01-agentos-repair (all: AgentOS retired D-107; D-069) · 2026-08-02-semantica-platform-review
(Surreal-exit reversed by ADR-0056/D-093; Semantica half became ADR-0043) ·
2026-08-09-S3-sql-bootstrap-hygiene (bootstrap model overturned D-108/D-109) ·
2026-08-09-S6-horizon-spine (built, then premises superseded D-069/D-107) ·
2026-08-09-S8-semantica-graph-lane (self-superseded in-document) ·
2026-08-09-S9-population-evals-backups (D-069; evals claim already wrong per DEBT) ·
2026-08-15-R0-wave1-audit + R2-horizon-engine (premise falsified — 0026–0030 were applied,
DEBT CH-15/16) · R4-graphiti-zep (Graphiti retired D-070/D-095) · R5-ag2-coordination ·
R6-provider-switching (D-101 "not needed") · R8-workbench (Next.js retired D-108) ·
R9-knowledge-to-case-mvp (AgentOS knowledge home gone D-101; Weaviate cutover abandoned D-104) ·
2026-08-17-R14-phase1-surreal-live-core-pass (self-superseded by own ADR-0059 addendum) ·
SESSION-HANDOFF-2026-07-13 (wholesale superseded).

Plans: ARCHITECTURE-BLUEPRINT-2026-08-15 · MIGRATION-DIAGRAMS-2026-08-15 ·
PLAN-2026-08-15-platform-runtime-migration · TASK-DISTRIBUTION-2026-08-15 (all: AG2/OrchestrationPort
model replaced by Temporal+n8n+ContextForge+Portkey, D-068/D-101/D-107) · OPEN-TASKS-2026-07-27 ·
PLAN-2026-08-09-completion-master (clock formula superseded by D-065/ADR-0059).

Summaries: COMPACT-SUMMARY-2026-08-01 (schema superseded D-069→D-121; its H3 finding already
captured in DECISION_LOG) · -02 (four-schema split superseded) · -13, -15, -16, -17, -18
(EMPTY — hook-failure exhaust, zero content).

## still-pending→keep (~25) — genuinely unverified, not contradicted

Root: AI-TO-PLATFORM-CONSOLIDATION-2026-08-29 (D-098 confirms unstarted) ·
MOVE-MANIFEST-2026-08-18 · PG18-MIGRATION-REHEARSAL-2026-08-29 (self-declared PASS, no
independent corroboration; tension with D-098 on 0049).

Inventories: INVENTORY-BASELINE-2026-08-14 (horizon-predicate finding still LIVE-CONFIRMED in DEBT).

Handoffs: 2026-08-02-pg18-migration-permission-allowlist (casebible-pg18 completion never
recorded) · 2026-08-03-universal-parser-repair-workbench (honest PARTIAL; SBV core verified via
PR #18/D-040, rest unconfirmed) · S2-build-and-test-green (task 4 confirmed via D-040, rest not) ·
S5-audit-ledger (0020 exists; acceptance gate unconfirmed) · S7-sbv-live-test (DEBT confirms open) ·
R1-go-ingestion · R3-semantica · R7-opencode-workspace · R10-surreal-investigation-design ·
R11/R12/R13 surreal phase-0/rulings/checkpoint (D-064 chain, no contradictions) ·
opencode-briefs 01/02/03 (task briefs, no completion claims; 03 flagged — targets Next.js paths
D-108 retired next day; 01's receipt has no D-### corroboration).

Plans: apply-0036-set-role-patch (concern real per D-094(d), exact patch not found in code —
needs a live-DB check) · PENDING-OWNER-DECISIONS-MATTER-MVP-2026-08-15 (P-series likely ruled
via D-060/ADR-0055 but exact rulings unrecorded) · PHASE0-PLANTED-FUTURE-FACT-THREAT-TESTS ·
PHASE1-D3-D4-AUTHORIZATION-PREFLIGHT (self-reported test counts unverified) ·
PHASE1-SLICE-DESIGN · PRODUCT-BLUEPRINT-2026-08-15 (light edit re Graphiti row, keep) ·
RELEASE-CUSTODY-2026-08-15 (**numbering-collision flag**: two different "0030" lanes —
matter_case_foundation vs evidence-vector — needs a human check before disposition).

Summaries: COMPACT-SUMMARY-2026-08-03, -07 (Case Bible/OneDrive ops — outside this repo's
registers; unverifiable here).

## Also noted

- `sql/bootstrap/schema_baseline.sql` (superseded Aug-10 baseline): deletion stays gated on the
  H-08 ledger-row correction (the `baseline` ledger row still names this superseded file).
- `docs/wiki/FUCKED.MD` (dictation transcript) removed from the tree per H-09; content remains
  recoverable from git history. A quarantine copy was placed in the workspace `_stale` archive,
  which the owner has since relocated during the 2026-09-01 workspace reorganization.
