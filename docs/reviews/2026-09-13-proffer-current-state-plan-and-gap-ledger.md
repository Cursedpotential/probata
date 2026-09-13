# Proffer current state, plan, and gap ledger

**Date:** 2026-09-13  
**Branch:** `codex/propria-reconcile-20260913`  
**Repository:** Probata child repository under the Propria umbrella  
**Status:** active integration; source changes are reviewable locally; deployment and canonical-checkout reconciliation remain open

This is the consolidated operating record for the Proffer intake-to-Context repair. It records what exists, what has been proved, what is still missing, and the order in which the remaining work must proceed. It supplements the binding [precommit Review contract](2026-09-13-proffer-precommit-review-contract.md) and the [integration branch receipt](2026-09-13-integration-branch-receipt.md). It does not create evidence, custody, or promotion state.

## Owner-directed product boundary

Proffer begins with retained source resources and ends this phase with an inspectable, frozen proposal or an approved Context commit with destination read-back. The operator must be able to select actual resources, see every stage and failure, inspect records, chunks, entities, relationships, metadata, attachments, hashes, warnings, lineage, and tool receipts, change compatible processing choices, rerun into a new immutable attempt, compare attempts, and approve one exact proposal and destination plan.

The current phase is **Context preparation and projection**. Evidence work happens later. Existing names in legacy code do not broaden the current product contract. A potential-promotion flag is only a reversible annotation for later consideration and performs no admission, custody, projection, or promotion.

There are two processing paths:

1. **Custom path:** retained package, format/signature routing, DuckDB-led extraction and normalization under the Go orchestrator, entity and relationship proposals, chunk proposal, and selected Context destinations.
2. **Semantica path:** an independently selectable semantic extraction path whose results can be inspected and compared. It is not the only path and cannot silently replace the Custom path.

The Go engine orchestrates the workflow. DuckDB performs supported extraction and analytical proposal work. Go decoders remain selectable and provide explicit recovery paths. Parser, extractor, repair tool, template, entity pass, relationship pass, chunk policy, and path selection must be visible and overridable. Every material change creates a new attempt and invalidates any approval bound to the prior proposal.

## Human workflow

1. Open Intake in an explicit TEST or REAL mode and select a real matter and source resources.
2. Retain or identify the immutable source package, including originals, container members, attachments, native metadata, filesystem metadata, embedded metadata, and hashes.
3. Create an operation and a first immutable attempt with visible processing choices.
4. Run signature detection, damage assessment, optional repair, parsing, normalization, temporal extraction, entity mention extraction, entity resolution, relationship proposal, and chunk proposal as independent, receipted stages.
5. Assemble a per-attempt DuckDB proposal containing all proposal tables and tool receipts.
6. Validate the proposal, freeze its logical content, close the database, hash the database and external artifacts, and publish the resource to Review.
7. Open Review from a resource catalog. No opaque handle or context ID is required from the user.
8. Inspect source records, proposed records, chunks, entities, relationships, graph, files, lineage, warnings, runs, configuration, and target deltas.
9. Resolve warnings or refine processing. Each rerun creates another immutable attempt with a side-by-side diff.
10. Select one frozen attempt and selected Context destinations. Exact approval binds both the logical proposal digest and external bundle digest.
11. Recheck destination drift, commit each selected destination idempotently, and read it back.
12. Keep Neo4j as the first approved graph destination. A later, separate manual action may project selected approved material into SurrealDB for whole-case consolidation.

At every step, the product must show current stage, current activity, activity attempt, completed artifacts, warnings, retry state, terminal failures, available recovery actions, and the effect of each operator choice. A failure cannot leave a blank page or an unresolvable handle field.

## What exists on this integration branch

### Review workspace

- `/review` is the canonical Review route. The legacy `/evidence/preview` route remains as a compatibility entry point.
- The primary navigation and Context flow rail use **Review** and **Context** language.
- Review opens a resource catalog and can select the URL resource, legacy attempt/handle, or the first available resource automatically.
- No manual context-ID or preview-handle field is required.
- The viewer distinguishes **Precommit proposal** from **Committed read-back**.
- The viewer exposes Overview, Source records, Chunks, Entities, Relationships, Graph, Files, Lineage, Warnings, and Attempts/runs.
- Empty and unavailable projections are labeled truthfully. Missing entity, relationship, or graph data is not presented as an empty successful extraction.
- The UI names Neo4j as the first post-approval graph destination and SurrealDB as a later manual projection.
- Potential-promotion flags are reversible annotations scoped to an exact mode, matter/resource, attempt, target, actor, reason, and time.

### Proposal contract and tools

- `modules/engine/proposal/schema.sql` defines fourteen required proposal relations: proposal control, source records, normalized records, metadata, attachments, entity mentions, entities, relationships, temporal expressions, chunks, lineage, warnings, sink operations, and tool receipts.
- The Go contract validates required relations, lifecycle transitions, immutable freeze behavior, destination rules, table counts, and digest identities.
- `proffer-table-json-v1` defines a deterministic logical table digest over canonical JSON.
- The logical proposal digest binds source identity, canonical table content, configuration, and destination plan.
- The external bundle digest binds the finalized DuckDB byte hash and external artifact hashes without creating a self-hash cycle.
- `proposal-bundle freeze`, `bundle`, and `verify` provide create-only artifact operations and tamper verification.

### API groundwork

- The API has a typed resource catalog for existing committed-readback Proffer operations.
- The API has durable, attempt-scoped potential-promotion flag commands and mode-isolation tests.
- `PROFFER_PROPOSAL_ROOT` is documented as the intended local proposal discovery root.
- DTO groundwork exists for proposal resource details and all fourteen proposal-table projections.
- The DuckDB bundle discovery, validation, read-only adapter, and proposal-detail route are **not implemented**. This groundwork must not be described as a working adapter.

### Development routing

- The local Vite portal routes `/api/proffer` to the integration API on `127.0.0.1:8021` with a fixed development-only authenticated actor.
- Other `/api` calls route to the deployed Workbench service so the full portal and its matter registry remain available during integration testing.
- This is a local development composition. It is not a deployed production topology.

## Verified local and live boundary

- The complete current workbook package is `Merged_Output-20260908T233006Z-1-001.zip` with SHA-256 `9006009A45AACB5F06CE6C3E871B18806D64A5BD3E763269643688E9287F88FC`.
- It contains three actual XLSX record sets: People (12 rows), Timeline (25 rows), and Narrative (32 rows), for 69 actual records.
- DuckDB 1.5.5 with its Excel extension read those workbook members directly in the investigation environment.
- The local portal at `http://127.0.0.1:5173/` returned a healthy application and the deployed matter API returned the available TEST matter.
- The R2-sorted Proffer source listing returned actual object metadata. This query did not hydrate OneDrive.
- The deployed service does not currently expose the new proposal-resource operation route. A local Review catalog therefore cannot yet show a verified canonical DuckDB proposal.
- No valid canonical v3 proposal bundle exists. No 69-record proposal has been frozen, bundled, verified, or served.
- Earlier v1/v2 experiments were invalid and were moved under `E:\AI_Workspace\Projects\Propria\to_be_deleted`; they are not discoverable proposal resources and must not be used as proof.

Invalid prototype quarantine entries include:

- `partial-proposal-attempt-duckdb-v1-20260913-060332`
- `partial-proposal-attempt-duckdb-v1-20260913-060411`
- `invalid-freeze-proposal-attempt-duckdb-v1-20260913-060637`
- `partial-proposal-attempt-duckdb-v2-20260913-060758`
- `invalid-schema-proposal-attempt-duckdb-v2-20260913-061531`
- `build_proposal-invalid-schema-20260913-061935270.py`
- `build_proposal_v3-invalid-schema-20260913-061935288.py`

## Required storage roles

| System | Current contract |
|---|---|
| Source package/object storage | Retains originals, members, attachments, native metadata, and hashes before proposal review. |
| DuckDB proposal | Complete per-attempt precommit proposal and analytical review model. |
| PostgreSQL | Minimum source/package/control/workflow/artifact coordinates before approval; selected approved canonical payload and receipts after approval. |
| Weaviate | Selected approved searchable Context chunks after exact approval and read-back. |
| Neo4j | Selected approved entity/relationship graph after exact approval and read-back. |
| SurrealDB | Separate later manual projection of selected approved resources for whole-case consolidation. |
| Temporal | Durable operation/attempt sequencing, retries, waits, exact approval, idempotent commits, and reconciliation. |
| n8n | Visible tool composition for document, image, OCR, archive, repair, and extraction subflows invoked from Temporal activity boundaries. |
| Dragonfly | Reconstructible catalog/progress/event/layout caches and live UI coordination only. |

Dragonfly cannot be the only copy of a source, proposal, warning resolution, approval, destination receipt, or workflow state. Its keys must be scoped by mode, matter, operation, attempt, and digest. Cache loss must rebuild from Temporal and durable artifacts. The existing private Infisical Dragonfly is unrelated and cannot be reused as the Review cache by assumption.

## Product and search boundaries that must remain intact

- **Proffer/Workbench** is the intake-to-Context preparation and Review portal.
- **Xplorer + Case Bible/Consignatio review** is one separate agent/HITL tool and legal-data review surface. Its ACP file operations and legal review workflow must not be merged into Proffer. Its visibility and approval patterns may inform shared interaction design.
- **Documentation index:** CocoIndex prepares the governed documentation corpus and SurrealDB provides its document/vector/BM25 store. Natural-language Docstore search and index-management tools remain exposed.
- **Code index:** Smart Explore uses tree-sitter structure and its own DuckDB state for code navigation and conflict/decision discovery. Documentation content is excluded from this codebase index.
- The documentation and code indexes can be queried together by an agent for conflict resolution, but they remain independently selectable sources with separate freshness, receipts, and management actions.

## Current gaps

### G1 — no valid proposal artifact

The 69 actual workbook records have not been transformed into the canonical fourteen-table DuckDB schema, logically frozen, externally bundled, and verified. This blocks a truthful precommit proposal preview.

### G2 — no generic DuckDB Review adapter

The API cannot yet discover canonical bundles, enforce root/path/symlink boundaries, validate logical and byte digests, open DuckDB read-only with external access disabled, validate the exact schema and frozen control row, or serve proposal tables through a detail route.

### G3 — intake cannot yet create a complete operation

The operator cannot yet select arbitrary files/resources in the full portal and create a visible operation with explicit TEST/REAL, matter, source set, Custom/Semantica path, parser, extractor, repair, template, entity, relationship, and chunk choices.

### G4 — entity workspace is incomplete

Entity mentions, candidate entities, aliases, resolution, refine/look-again, link/unlink, merge/split, relationship proposals, temporal qualifiers, and comparison across attempts need a first-class early-stage workspace and backend commands.

### G5 — override and rerun contracts are incomplete

The UI and API do not yet provide authenticated, versioned override commands, attempt creation, invalidation impact, run comparison, or exact digest approval for parser/extractor/template/entity/chunk changes.

### G6 — Temporal/n8n visibility is incomplete

The Review API does not yet expose Temporal workflow/run/activity/attempt/wait/retry coordinates or n8n workflow/version/activation/execution/node receipts. The required atomic stages have not been proved end to end in live orchestration.

### G7 — destination commit is not implemented for this proposal model

There is no proved prepare/review/approve/commit split with destination-drift checks, independently selectable PostgreSQL/Weaviate/Neo4j writes, idempotency, receipts, and read-back. SurrealDB must remain outside automatic commit.

### G8 — Semantica integration remains a capability lane

Semantica is installed and has extraction, ontology, temporal, provenance, visualization, and export capabilities, but the dual-path attempt model, comparison surface, and receipts are not integrated or live-proved.

### G9 — entity-model capacity is undecided

The first-pass NLP/NER reduction strategy, optional local GPU models, and inexpensive hosted classification/embedding/reranking path remain capability decisions. A missing model must appear as an unavailable optional capability, never a silent degraded result.

### G10 — Dragonfly service is not deployed

The cache/event interface, namespace, persistence boundary, contract tests, and separate deployment have not been implemented. The portal must remain correct without it.

### G11 — canonical Git reconciliation is unfinished

This integration branch is isolated from a severely dirty, diverged canonical Probata checkout. The canonical checkout must be preserved and reconciled through a clean worktree. It must not be reset, cleaned, stashed, or broadly staged.

### G12 — production publication is incomplete

Local/static validation is not deployment proof. The Review UI, proposal API, Temporal/n8n workflows, proposal bundle, destination commits, and read-back must be deployed and verified independently.

## Ordered implementation plan

1. Commit and push this integration branch with its exact validation receipt.
2. Publish this ledger, the product contract, and the integration receipt to the governed Docstore and verify read-back/index status.
3. Build one canonical v3 proposal from the retained ZIP and its three XLSX members, preserving package/member/workbook/sheet/row/cell lineage and all available metadata.
4. Freeze, bundle, and verify that proposal with the Go CLI. Reject any schema, logical digest, byte digest, or artifact mismatch.
5. Complete the generic API adapter and detail route with root containment, regular-file and symlink checks, exact schema validation, read-only DuckDB settings, mode/matter isolation, and upstream-failure notices.
6. Add focused real-DuckDB tests for a valid bundle and for path, symlink, mutable-state, schema, table-digest, database-byte, artifact, mode, duplicate-attempt, and upstream-failure rejection.
7. Point the local Review catalog at the verified v3 proposal and visually prove all ten views with the 69 actual records.
8. Implement the first-class operation creator and source selector. Preserve explicit TEST/REAL and matter selection through every screen and API call.
9. Implement early entity extraction/review and relationship/temporal refinement with immutable revisions and rerun comparison.
10. Implement visible Custom, Semantica, and dual-path selection with independent receipts and no silent fallback.
11. Implement operator overrides and immutable attempt reruns for repair/parser/extractor/template/entity/chunk choices.
12. Wire atomic stages through Temporal and visible n8n subworkflows. Surface every workflow, activity, node, retry, wait, artifact, warning, and recovery choice.
13. Implement exact approval over logical and bundle digests plus the selected destination plan.
14. Implement destination-drift checks and independent, idempotent PostgreSQL, Weaviate, and Neo4j commits with read-back. Keep SurrealDB as a later manual projection.
15. Add the reconstructible Dragonfly adapter and separate service after durable truth and replay behavior are proved.
16. Run the complete complaint audit against the finished human workflow, then pre-mortem and red-team every stage and recovery path before adoption.
17. Reconcile canonical Probata history and dirty paths from a clean worktree, merge this branch without losing unique work, and retire obsolete worktrees only after owner-reviewable proof.
18. Deploy each surface and run live end-to-end proof. Record exact versions, routes, workflow identities, target receipts, read-back results, and unresolved failures.

## Acceptance gates

- A user can begin from an explicit matter/mode and real source selection without knowing an internal ID.
- Every screen has a forward action, a back path, visible state, and a recovery path for each failure class.
- The actual 69-row package produces one valid, immutable proposal whose records, chunks, entities, relationships, graph, metadata, files, warnings, lineage, and runs are inspectable before target-domain commit.
- Every processing choice is visible, overridable, versioned, rerunnable, and compared as a new immutable attempt.
- An exact proposal cannot be approved until both digest layers and the selected destination plan validate.
- No proposed domain payload or searchable index entry is committed before exact approval.
- PostgreSQL, Weaviate, and Neo4j are independently selectable and read-back verified; SurrealDB remains a separate later manual action.
- Temporal and n8n coordinates are visible from start through completion or failure.
- TEST and REAL, first-party and third-party message sources, Custom and Semantica paths, the two applications, and the two indexes cannot silently cross boundaries.

## Do not claim

- Do not claim the canonical Probata checkout is clean or reconciled.
- Do not claim a canonical v3 proposal or a 69-record precommit preview exists.
- Do not claim the partial Python DTOs constitute a DuckDB adapter.
- Do not claim the Review/Context changes are deployed because they build or run locally.
- Do not claim live n8n, Temporal, Dragonfly, PostgreSQL, Weaviate, Neo4j, or SurrealDB proof without a current receipt and read-back.
- Do not describe current Context preparation as evidence or custody work.
- Do not describe a potential-promotion flag as a promotion.
- Do not merge the Xplorer + Case Bible/Consignatio agent/HITL tool into Proffer.
- Do not let Smart Explore index the governed documentation corpus or replace the natural-language CocoIndex/Docstore tools.
- Do not expose invalid v1/v2 proposal experiments as resources.

## Immediate operator/developer coordinates

- Full local portal: `http://127.0.0.1:5173/`
- Review route: `http://127.0.0.1:5173/review?mode=TEST`
- Integration API: `http://127.0.0.1:8021/`
- Branch: `codex/propria-reconcile-20260913`
- Worktree: `E:\AI_Workspace\Projects\Propria\_worktrees\probata-integration-20260913`
- Canonical Probata checkout requiring later reconciliation: `E:\AI_Workspace\Projects\Propria\Probata\probata`
- Propria umbrella root: `E:\AI_Workspace\Projects\Propria`

The running local services are development aids and may stop with their owning terminal/session. Their existence is not a deployment receipt.

## Docstore publication receipt

The complete text of this ledger, the binding precommit Review contract, and
the integration branch receipt was written as one governed Docstore handoff:

- document ID: `document:6wetw58ao8tr6dxhxx9d`;
- status: `active`;
- exact read-back: verified;
- indexing triggered by the handoff write: no;
- domains: `docs`, `infra`, `intake`, `knowledge`, `probata`, `proffer`, and
  `workbench`.

The handoff write makes the complete analysis immediately available through
structured Docstore retrieval. CocoIndex source indexing is a separate
operation and requires its own run receipt.
