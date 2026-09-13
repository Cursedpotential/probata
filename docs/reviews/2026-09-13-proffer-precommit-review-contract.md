# Proffer precommit proposal and Review workspace contract

**Status:** owner-directed implementation contract  
**Date:** 2026-09-13  
**Scope:** Proffer intake-to-Context preparation, review, approval, and projection  
**Implementation proof:** this document defines the target and acceptance gates; it does not claim the current runtime satisfies them.

## Product purpose

Proffer turns retained source material into an inspectable, reproducible proposal. A person must be able to see what the system found, how it found it, what it plans to write, and what every target will receive before any proposed domain record is committed to a target database or searchable index.

The workflow begins with one or more source resources and ends with either:

1. a frozen proposal that remains available for review or revision;
2. an approved proposal committed and read back from its selected destinations; or
3. a stopped or failed attempt whose completed work, failure, and recovery actions remain visible.

Internal identifiers support deep links and API calls. The operator never has to discover, copy, or type an opaque handle to use the product.

## Binding storage order

1. **Source package:** retained originals, container members, attachments, hashes, and source metadata remain immutable and addressable.
2. **Proposal workspace:** one attempt writes its proposed records, chunks, entities, relationships, metadata, warnings, lineage, target deltas, and tool receipts into a per-attempt DuckDB artifact bundle.
3. **Human review:** the Review workspace reads the frozen proposal bundle and shows every proposed result before target commit.
4. **Exact approval:** approval binds the complete proposal digest and the selected destination plan.
5. **Context commit:** approved content is committed idempotently to the selected Context destinations.
6. **Neo4j graph:** the approved entity and relationship graph is written to Neo4j and read back there. Neo4j is the first durable graph destination.
7. **Manual SurrealDB projection:** SurrealDB receives nothing automatically. A later, separately initiated human action may project selected approved material into SurrealDB for whole-case consolidation and analysis.

No proposed source record, normalized record, chunk, entity, relationship, or index entry may be written to PostgreSQL, Weaviate, Neo4j, SurrealDB, or a searchable index before exact proposal approval. PostgreSQL may retain the minimum source/package identity, mode/matter coordinates, attempt/workflow correlation, artifact locators and hashes, and operational state needed to find and govern the proposal. Those control coordinates may not contain the proposed domain payload. Read-only destination queries are allowed during preparation so the proposal can show inserts, updates, no-ops, duplicates, and conflicts.

Temporal persists workflow history in Temporal's own service. That operational history is not a target-domain commit. The immutable source package and the per-attempt proposal bundle are also allowed to exist before approval because they are the material under review.

## Proposal bundle

Each attempt has a self-contained location such as:

```text
proposal/<operation-id>/<attempt-id>/
  proposal.duckdb
  manifest.json
  source-package.json
  tool-receipts/
  derived/
  warnings.json
```

`proposal.duckdb` contains at least:

| Relation | Required content |
|---|---|
| `proposed_source_records` | source object/member identity, native record, native locator, raw value and typed interpretation |
| `proposed_records` | normalized typed records with source lineage and per-field transformation details |
| `proposed_metadata` | filesystem, container, embedded, media, and record-native assertions with extractor identity |
| `proposed_attachments` | parent/member relationships, names, media type, byte size, hashes, metadata, and repair state |
| `proposed_entity_mentions` | exact source spans/cells/pages, extractor, confidence, and unresolved/resolved state |
| `proposed_entities` | entity candidates, aliases, attributes, merge/split state, and revision identity |
| `proposed_relationships` | endpoints, type, direction, temporal qualifiers, provenance, confidence, and revision identity |
| `proposed_temporal_expressions` | original text, normalized interpretation, precision, certainty, and alternatives |
| `proposed_chunks` | exact content, source span, policy/version, token count, chunk hash, and inherited source boundary |
| `proposed_lineage` | complete source → package → attempt → tool run → record → chunk/entity/relationship graph |
| `proposed_warnings` | severity, stage, affected resource, explanation, recovery choices, and resolution state |
| `proposed_sink_operations` | per-destination insert/update/no-op/conflict plan and expected post-write identity |
| `tool_receipts` | tool/version/config/input/output digests, Temporal activity identity, n8n execution/node identity when used |

Freeze uses two explicit digest layers so the DuckDB file never has to contain its own byte hash:

1. The **logical proposal digest** binds the source-package digest, canonical row-set digest and count for every required proposal relation, exact tool/template/policy configuration, and destination plan. Its freeze record may be stored inside DuckDB because it does not depend on the database file's serialized bytes.
2. After the freeze record is written and DuckDB is checkpointed and closed, an external **bundle manifest** records the finalized database byte length and SHA-256 plus every derived artifact's length and SHA-256. A bundle digest binds that external manifest. The external manifest is not written back into the database.

Exact approval binds the logical proposal digest and its bundle digest. A read must verify both layers before presenting the artifact as frozen. A mutable, partially written, logically mismatched, or byte-mismatched bundle cannot be approved.

## Operation and attempt model

An **operation** is the durable user-visible container for one source set. An **attempt** is one immutable execution configuration and its result. Rerunning a parser, changing an extraction template, refining entities, or changing a chunking policy creates a new attempt; it never overwrites a prior attempt.

Every operation exposes:

- mode and matter coordinates;
- source-set identity and source-package digest;
- current stage, current activity, activity attempt, retry/wait state, and last event time;
- all immutable attempts and which attempt is currently selected;
- parser, extractor, repair, entity, relationship, temporal, chunk, and path-selection configuration;
- proposal completeness and digest state;
- approvals and selected destination plan;
- destination receipts and read-back results;
- failures, warnings, and available recovery actions.

TEST and REAL are explicit coordinates on the operation. They never derive from whichever mode happens to be open in the browser.

## Review workspace

The current user-facing **Preview** destination becomes **Review**. Its landing state is a resource catalog, not a form requesting a context ID, preview handle, workflow ID, or other internal coordinate.

### Resource catalog

The catalog lists available operations/proposals in the selected matter and mode. Each row shows:

- source/resource title and source type;
- operation state and current stage;
- selected attempt and attempt count;
- record, attachment, chunk, entity, relationship, and warning counts;
- last activity time;
- proposal digest state: building, frozen, approved, committed, superseded, failed, or stopped;
- selected destinations and their commit/read-back status.

The catalog supports search, state/source-type filtering, warning-only filtering, sorting, and pagination. It remembers the last opened resource as a convenience, but the URL remains a complete deep link. If the URL lacks a resource coordinate, the first matching resource may be selected automatically; an empty catalog explains why and offers a direct path to Intake.

### Resource viewer

Opening a resource provides these views:

| View | Required behavior |
|---|---|
| Overview | source package, current configuration, progress, counts, warnings, proposal digest, and destination plan |
| Source records | typed table plus raw/native value, normalized interpretation, and exact source locator |
| Chunks | exact proposed or committed chunks, policy/version, boundaries, tokens, hash, inherited metadata, and source span |
| Entities | mention-to-entity resolution, aliases, attributes, confidence, revisions, look-again/refine/merge/split actions |
| Relationships | endpoints, type, direction, temporal qualifiers, provenance, confidence, and revision comparison |
| Graph | proposed graph rendered from the DuckDB bundle before approval; approved graph read back from Neo4j after commit |
| Files | originals, container members, attachments, derivative files, metadata, hashes, and parent lineage |
| Lineage | navigable source → package → attempt → record → chunk/entity/relationship chain with tool receipts |
| Warnings | every warning/failure, affected output, impact, recovery choices, and resolution state |
| Runs | attempt history, configuration diff, result-count diff, proposal digest, failure/retry history, and side-by-side comparison |

The viewer states whether it is showing a **proposed** bundle or **committed** read-back. It never blends those states. Empty views distinguish “none found,” “stage has not run,” “stage failed,” “resource is unavailable,” and “contract not implemented.”

### Review actions

From the selected resource the operator can:

- rerun from immutable input with the same configuration;
- choose a different compatible parser or extractor;
- edit or select an extraction template/profile;
- rerun entity extraction or resolution;
- add/edit aliases and link, unlink, merge, or split entity candidates;
- change chunk policy and preview the replacement chunks;
- run Custom, Semantica, or both paths independently;
- compare attempts and select one exact frozen proposal;
- approve or reject the exact proposal digest;
- select approved destinations individually;
- stop, resume a healthy wait, or start a replacement attempt after a terminal failure;
- export the proposal tables, graph, warnings, lineage, and receipts.

Every action shows what it will invalidate and creates a new attempt or revision where required. Approval cannot survive a configuration or content change.

## Destination roles

| System | Role | Earliest write | Operator control |
|---|---|---|---|
| DuckDB proposal bundle | complete frozen precommit proposal and local analytical review model | during preparation | every attempt is visible; freeze/digest required before approval |
| PostgreSQL | control coordinates, source/package provenance, approved canonical messaging where applicable, decisions, destination coordinates, and receipts | minimum source/control coordinates before approval; proposed domain content only after exact approval | selected domain writes are in the destination plan; read-back required |
| Weaviate | approved searchable Context chunks and their filter/provenance coordinates | after exact approval | independently selectable; chunk generation and counts shown before write |
| Neo4j | approved entity/relationship graph and graph provenance | after exact approval | independently selectable; proposed graph and graph delta shown before write |
| SurrealDB | later whole-case manual projection for consolidation and analysis | only after a separate manual projection action | never part of automatic Context commit; selection, scope, and receipt shown separately |
| Searchable indexes | approved, versioned index generations derived from the frozen proposal | after exact approval | each index is independently selectable and receipted |

The proposal records expected target identity and a precommit destination snapshot. Immediately before writing, the commit workflow checks for destination drift. If the target changed in a way that invalidates the proposed delta, the workflow returns to Review and requires a new proposal digest.

## Neo4j and SurrealDB graph behavior

Before approval, the Graph view reads nodes and edges from `proposal.duckdb`. It can also show a read-only comparison against the currently approved Neo4j graph:

- nodes to add, update, merge, leave unchanged, or flag as conflicts;
- edges to add, update, leave unchanged, or flag as conflicts;
- unresolved aliases and ambiguous endpoints;
- provenance and temporal qualifier completeness;
- expected Neo4j identifiers and constraint/index effects.

After approval, Neo4j receives only the graph slice named by the approved digest. The commit activity is idempotent and writes a receipt containing counts, target transaction/bookmark identity when available, and a read-back digest or reconciliation report.

SurrealDB is not a shadow write. Its manual projection starts from selected approved resources and shows its own preflight plan, scope, conflicts, and expected changes. It produces a separate projection digest, approval, execution, and read-back receipt.

## Dragonfly boundary

Dragonfly is a useful fit for the responsive operator experience because it is Redis-compatible and can provide fast, reconstructible live state. It may hold:

- operation-list cache entries with short TTLs;
- current progress snapshots derived from Temporal;
- pub/sub or stream events used to update the Review workspace;
- short-lived graph layout/query caches keyed by proposal digest;
- UI presence, filters, and resume cursors;
- idempotency acceleration that is also enforced by the durable workflow/store.

Dragonfly must not hold:

- the only copy of source bytes, a proposal bundle, an approval, a destination receipt, or a warning resolution;
- authoritative workflow state that conflicts with Temporal;
- mutable proposal content after the proposal digest is frozen;
- a graph that is presented as committed Neo4j state;
- a queue whose loss can silently skip required work.

Every Dragonfly key includes mode, matter, operation, attempt, and proposal digest as applicable. Cache loss must cause a rebuild from Temporal and durable artifacts, not data loss or a changed decision. The first integration should be a cache/event adapter behind an interface, with an in-process development implementation and contract tests. Dragonfly deployment is a separate operational gate.

## Temporal and n8n responsibilities

Temporal owns durable sequencing, retries, timeouts, compensation, waits, attempt identity, exact approval, commit order, and read-back reconciliation. Every unit remains one retry-safe activity with reference-only payloads.

n8n owns visible tool composition where branching and human-understandable media/document processing are valuable. A workflow/node is still invoked from a Temporal activity boundary, and each node returns artifact references and receipts. n8n does not own the operation's durable truth or approval state.

Minimum atomic stages are:

1. retain source object;
2. enumerate container members;
3. capture filesystem/container/embedded/media metadata;
4. assess damage and tool compatibility;
5. apply one approved repair operation when selected;
6. detect signature/format;
7. select one parser/extractor;
8. parse;
9. normalize;
10. extract temporal expressions;
11. extract entity mentions;
12. resolve/propose entities;
13. propose relationships;
14. chunk;
15. optionally run Semantica candidate extraction;
16. assemble DuckDB proposal;
17. validate proposal completeness;
18. freeze artifacts and compute proposal digest;
19. wait for exact human approval;
20. recheck target drift;
21. commit each selected destination independently;
22. read back and reconcile each selected destination;
23. complete or return a visible recovery decision.

PDF, image, OCR, archive, repair, and extraction flows may use n8n subworkflows, but every tool invocation stays visible as a named node with input/output artifact references, duration, version, warnings, and error.

## Failure behavior

Every stage must distinguish:

- unavailable capability;
- incompatible tool/template;
- source damage;
- detector or extractor failure;
- incomplete output;
- ambiguous output requiring review;
- retryable infrastructure failure;
- terminal integrity failure;
- stale proposal caused by a source/configuration/target change;
- optional-path failure that does not block the selected primary path.

The Review workspace shows the failed stage, exact attempt, completed artifacts, affected views, retry history, and valid recovery actions. It never converts a detector failure into a claim that the source is damaged, silently falls back to another tool, silently changes a template, silently commits a partial proposal, or traps the operator with no action.

## First implementation slice

The first reviewable vertical slice is complete only when all of these are true:

1. `/review` opens a resource catalog without a handle field.
2. The catalog is filtered by explicit mode and matter and never mixes them.
3. A resource deep link opens without requiring copied internal identifiers.
4. The viewer exposes the complete tab structure with truthful availability states.
5. A real retained ZIP containing the three current XLSX record sets is enumerated without losing the outer package or member identities.
6. XLSX extraction preserves workbook, sheet, row, column/cell, original value, interpreted value, and metadata.
7. The 69 actual extracted rows are visible as typed proposed records rather than being coerced into messages.
8. Entity mentions, candidate entities, relationships, and proposed chunks are visible from the same attempt.
9. The graph view renders the proposed graph from DuckDB and clearly identifies Neo4j as the first post-approval graph destination.
10. No target-domain rows or index entries exist before approval.
11. Approval binds the source-package, proposal, record, entity, relationship, chunk, and destination-plan digests.
12. A changed template/parser/entity/chunk choice invalidates approval and produces a new immutable attempt.
13. PostgreSQL, Weaviate, and Neo4j commits are independently selectable and read-back verified.
14. SurrealDB remains absent from automatic commit and appears only as a later manual projection action.
15. Temporal activity/attempt and n8n workflow/execution/node visibility is present from start through completion or failure.

## Current migration rule

The existing implementation's PostgreSQL-backed late preview cannot be relabeled and treated as compliant. Migration requires a real prepare/review/approve/commit split. During the transition, any view backed by already committed PostgreSQL rows must say **Committed read-back**. Only a frozen per-attempt artifact that has not written proposed domain data to a target may say **Precommit proposal**.
