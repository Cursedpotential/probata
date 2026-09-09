# DECISION_LOG.md backfill — D-072 through D-080

> _Byline: Claude Code · Sonnet (recovery subagent) · 2026-09-01_

## What this is

`docs/DECISION_LOG.md` currently jumps directly from **D-071** to **D-082** — decisions D-072
through D-081 are missing (verified live 2026-09-01: `grep -n "| D-07" docs/DECISION_LOG.md` returns
only D-071; `grep -n "| D-08"` starts at D-082). These rows were written during a 2026-08-25 Codex
CLI session (`rollout-2026-08-25T08-52-26-01a038fa-a77a-79e1-b66a-99bdb0af6771.jsonl`) but the
session's edits to `docs/DECISION_LOG.md` were never committed to git, so the rows were lost.

This document recovers **D-072 through D-080** verbatim from the Codex rollout transcript, per the
owner's task scope. **D-081 was also found in the same rollout** (recovered incidentally while
tracing the sequence) but is **out of this task's requested range (D-072–D-080)** — it is noted at
the bottom for completeness/owner awareness, not as a formal deliverable of this backfill.

Each row below is the **exact final text** as it was written and applied successfully in that
session (verified against the tool's own `custom_tool_call_output` — i.e. these `apply_patch` calls
returned success, not the "Script failed" error some nearby attempts in the same session produced).
Where a row was touched more than once within the session, the text below is the **last** (final)
version. No paraphrase; nothing invented.

**This document does NOT edit `docs/DECISION_LOG.md`** — another session has that file active per
the task instructions. The owner (or a future session once the file is free) should append these
nine rows to the decision table, immediately after the current D-071 row and before D-082, preserving
the table's `| # | Decision | Lane | Status | Rationale / notes |` column order.

## Recovery provenance (per row)

| Row | Recovered from (rollout file) | Timestamp (row's final write) |
|---|---|---|
| D-072 | `2026/08/25/rollout-2026-08-25T08-52-26-01a038fa-a77a-79e1-b66a-99bdb0af6771.jsonl` | 2026-08-25T13:34:09.386Z |
| D-073 | same | 2026-08-25T13:34:09.386Z |
| D-074 | same | 2026-08-25T13:34:09.386Z |
| D-075 | same | 2026-08-25T13:37:54.505Z |
| D-076 | same | 2026-08-25T13:43:36.633Z |
| D-077 | same | 2026-08-25T13:52:51.631Z |
| D-078 | same | 2026-08-25T13:59:58.505Z |
| D-079 | same | 2026-08-25T14:01:38.215Z |
| D-080 | same | 2026-08-25T14:03:59.367Z |

All nine rows were authored once each, sequentially, in the order shown, as part of one continuous
architecture-ruling session on 2026-08-25 (~13:34–14:04 UTC). Cross-checked against every later
patch call in the 08-25/08-26/08-27 rollout window that touches `docs/DECISION_LOG.md`: none of
D-072–D-080 was revised again after the timestamps above.

## Recovered rows (verbatim, ready to append)

| # | Decision | Lane | Status | Rationale / notes |
|---|---|---|---|---|
| D-072 | **The platform is permanently one owner and one personal case. Do not build multi-Matter tenancy, Matter-to-CourtCase hierarchies, cross-Matter isolation, or evidence scope-binding machinery.** Existing Matter/CourtCase IDs and `case_id='primary'` are compatibility scaffolding only and must not proliferate into new domain architecture. | A/B | **owner-ruled 2026-08-25** | Reasserts D-041 and supersedes D-060 / ADR-0055's multi-proceeding identity consequence. Any later flattening is a separate migration; no destructive change is authorized here. |
| D-073 | **SurrealDB is the final temporal-graph aggregation, walk, and analysis engine.** Evidence modalities remain in their proper authoritative/specialist homes; governed, established facts and typed provenance references are projected into Surreal, where the complete cross-source temporal graph is assembled and the final as-lived/hindsight walks and delta analysis execute. | B/C | **owner-ruled 2026-08-25** | Refines D-070 and supersedes ADR-0056's description of Surreal as merely experimental. PostgreSQL remains custody/governance authority; Surreal does not own original bytes or silently promote candidates. The final analytical product is computed in Surreal from governed cross-modal facts. |
| D-074 | **Semantica (awksite) is the governed semantic extraction layer.** It extracts entity, relation, event, temporal, claim, and conflict candidates with exact source provenance; it supports entity resolution and conflict-resolution proposals, but it does not declare canonical truth or write final walk beliefs. Governed review/promotion establishes facts before they enter the final Surreal analytical graph. | B | **owner-ruled 2026-08-25** | Incorporates Semantica as a first-class stage rather than an optional side worker. Preserves ADR-0043's candidate boundary while broadening the required production role to provenance, entity resolution, and conflict proposal. |
| D-075 | **H2 is computed during normalization for each individual message/normalized record, verified at evidence promotion, and may be independently reverified during evidence processing.** The normalization-time H2 is a provisional content fingerprint, not yet a custody assertion. Successful promotion recomputes/verifies H2 against the selected normalized content and its original-source/H1 lineage, then records the accepted custody H2. Later evidence reverification appends a verification event/result; it never replaces the accepted hash or rewrites history. | B | **owner-ruled 2026-08-25** | Refines D-069's "hashes at ingest are fingerprints" boundary: H1 identifies the original source; H2 is the per-message/per-record normalization process. Computation, promotion verification, and later evidence reverification are distinct lifecycle events. H3 timing is not changed by this ruling. |
| D-076 | **H3 is the ordered completeness seal for one normalized source generation.** For the platform evidence chain: `chain_0 = H1`; for every `h2-canonical-v2` in deterministic source sequence, `chain_i = sha256(utf8(chain_{i-1}_hex \|\| H2_i_hex))`; the final value is H3. Normalization may compute a provisional head. Promotion independently verifies H1, the complete ordered H2 membership/count, and H3 before accepting the H2/H3 assertions into custody. H3 covers the complete normalized source generation even when only selected records are promoted as evidence; it proves integrity/completeness, not blanket evidence approval. Later reverification appends results. New writes use the precise tag `h3-chain-h1genesis-hexconcat-v1`; legacy `h3-chain-v1` rows remain read-only and are disambiguated by writer. SBV's `h3-chain-sbv-genesisempty-v1` remains a separate raw-import integrity receipt and is never conflated with evidence H3. | B | **owner-directed resolution 2026-08-25** | Reconciles D-069/D-075 with the two test-proven constructions. The H1-genesis chain matches `h2-canonical-v2` and the Case Bible 1,918-link proof. H3 is per source/parser-canonicalization generation, not global across unrelated sources and not based on promotion order. Any parser/canonicalization change creates a new generation and chain; history is never rewritten. |
| D-077 | **n8n owns the visual business/agent flow; Temporal owns durable Workflow execution and schedules every independently tracked Activity. Hashing is a standalone callable capability exposed through separate Temporal Activities for H1 computation, normalized H2/H3 computation, promotion verification, and later evidence reverification.** Hashing must not be embedded inside parsing, normalization, storage, promotion, or evidence code. n8n starts/signals Temporal and may itself be called as an Activity body; it must not bypass Temporal for load-bearing work. Activities exchange immutable references/manifests, not files or full record batches. | B/C | **owner-ruled 2026-08-25** | Refines D-068 into concrete boundaries. Temporal/n8n entered the architecture only days ago, so incomplete workflow coverage is expected integration work, not a failed rollout. The legacy `ChatTranscriptIngest` boundary is nevertheless wrong after D-069: its `custody_activity` performs ingest-time evidence writes and `store_activity` combines normalization/storage. Target workflow and gap map: `docs/reviews/2026-08-25-schema-audit/TEMPORAL-N8N-WORKFLOW-AND-GAPS.md`. Deferred SBV/ChatMiner consolidation remains behind one parser Activity contract. |
| D-078 | **PostgreSQL is the canonical source-and-control plane for the entire lifecycle. All downstream processing starts from PostgreSQL change detection/outbox events. Weaviate, Neo4j, geo, and other sister databases are specialized derived processors/projections; every projection/result writes its receipt, provenance, status, and source linkage back to PostgreSQL. Weaviate is the search surface and every object/hit resolves to exact PostgreSQL source/chunk/version authority. Neo4j is primarily Semantica's semantic candidate/relationship graph and every node/edge resolves to exact source provenance. SurrealDB receives only a PostgreSQL-authorized, version-pinned, cross-store reconciled manifest of promoted/governed material for final temporal-graph analysis and walks.** | B/C | **owner-ruled 2026-08-25** | No sister database may become an independent truth store or feed Surreal directly without PG reconciliation. Ingest, normalized representations, candidates/facts, governance, projection jobs/receipts, and aggregate readiness remain in PG. Specialist payloads stay in their proper engines; PG retains their identities, metadata, authority, and lineage. |
| D-079 | **Raw geodata and normalized geospatial representations live in PostgreSQL/PostGIS.** Geo ingest, provenance, coordinates/geometries, source versions, and relevant derived geo events/features remain PG-authoritative. PG change detection triggers geo processing; governed/relevant temporal-geospatial facts and typed source references are then included in the PG-reconciled Surreal aggregation so they can be analyzed against communications, claims, realizations, and other events. | B/C | **owner-ruled 2026-08-25** | Corrects D-078 only where its shorthand grouped geo with sister databases. PostGIS is the geo home inside PG; Surreal receives relevant governed geo facts/projections, not a competing raw-geo truth store. |
| D-080 | **The canonical engine is PostgreSQL 18 augmented by `pg_duckdb`, PostGIS, and pgvector.** PG therefore handles canonical relational/JSON state, change/outbox control, analytical and object-store scans through DuckDB, raw/normalized geospatial data through PostGIS, and canonical/local vector representations plus reconciliation through pgvector. External databases are workload-optimized rebuildable serving/analysis projections—not compensations for missing PG authority: Weaviate serves search, Neo4j serves the Semantica-originated semantic graph, and Surreal serves the final reconciled cross-domain temporal graph and walks. | B/C | **owner-ruled 2026-08-25** | Clarifies D-078/D-079. Metadata, lineage, governance, projection jobs/receipts, and normalized truth always return to/stay in PG. `pg_duckdb` is inside PG, not a separate truth database; pgvector does not displace the ruled Weaviate search surface. |

## Bonus find, outside requested range (D-081)

Also recovered from the same rollout (last write 2026-08-25T14:07:04.134Z), immediately following
D-080 in the same session — flagged for owner awareness only, not formally in scope for this task,
but reproduced verbatim since it was already in hand:

| # | Decision | Lane | Status | Rationale / notes |
|---|---|---|---|---|
| D-081 | **Whole-platform reconciliation is divided by semantic authority transition into R0-R14 bounded workstreams, each with a mandatory authority/input/output/source-path/clock/idempotency/CDC/census/migration/test/handoff contract. R9 independently reconciles every sister-store receipt before Surreal; R14 independently verifies migration and live end-to-end completeness.** | A/B/C | **owner-directed 2026-08-25** | Prevents agents from dropping cross-domain requirements or declaring a database slice complete in isolation. Master dependency map and assignment rules: `docs/reviews/2026-08-25-schema-audit/RECONCILIATION-DOMAIN-WORKSTREAMS.md`. |

Note: `docs/DECISION_LOG.md` already resumes at **D-082** today, so if the owner backfills D-081 too,
the append range becomes D-072 through D-081 (ten rows), immediately before the existing D-082 row.

## How to apply

Once `docs/DECISION_LOG.md` is free for editing, append the nine rows above to its decision table in
numeric order, directly after the current D-071 row and before D-082. Do not renumber or alter
wording — this is a verbatim backfill of lost content, not a re-authoring.
