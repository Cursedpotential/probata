# Intake workflow visibility and repair-gate correction

Date: 2026-09-12

Owner requirement: Intake is an operations surface, not a browser-owned wizard. Every submitted source must remain visible across navigation and refresh, including in-process work, repair waits, parser-decision waits, completed work, and failures. A durable wait must not be rendered as active processing. Operators need explicit Open, Resume decision, Hold/Cancel, and Back controls.

## Confirmed regression

Commit `b1f3df5` changed `/intake` to mount only `UnifiedIntake`, disconnecting the existing filterable `IntakeTable` and `RunsTable`. The repair-review branch inside `UnifiedIntake` then replaced the selected-source panel, hiding Source preview, Metadata, and Parser tabs.

## Confirmed false repair gate

The tool contract does not emit top-level `review_required`, `needs_repair`, or `repair_required` flags. `repair.detect` reports bounded format/encoding/engine identification. `repair.preview` reports actual structural health under `report.clean` with failure, repair, loss, truncation, and event details.

The engine incorrectly treated absence of the nonexistent top-level flags as requiring review. This stranded clean inputs, including an ordinary JPG, behind an empty repair gate.

The governing rule is:

- Validate damage from the actual repair preview report.
- If the report is clean, continue the sealed original automatically.
- If a concrete issue is found, show the exact issue and compatible derived-repair proposal before pausing.
- Preserve an explicit owner override to use the sealed original, with actor, reason, assessment, source version, and durable decision receipt.
- Never alter the custody original. Any approved repair writes a separately hashed derived artifact.
- A malformed or unavailable detector is an operational detector failure; it must not be mislabeled as proof that the source itself needs repair.

## Current delivery boundary

The Intake route again mounts the filterable source inventory and Runs table. The selected-source tabs remain mounted during repair review, the original-source choice is labeled as an owner override, and common image extensions are classified as `image` rather than `unknown_binary`.

A complete Proffer queue remains required so every preview handle and durable wait can be reopened after navigation or refresh. Browser component state is not an acceptable registry.

## Unified ingest operation

The product-level unit is an **Ingest Operation**, not an isolated source row, browser wizard, Temporal handle, n8n execution, or service call. One stable operation identity must join:

`source version -> ingest plan -> workflow/run -> service executions -> human decisions -> derived outputs -> receipts`

### Settled package-first preservation rule

Every accepted source is represented by an **Intake Source Package** before its current processing route can make it disposable. The package preserves the byte-identical original through its immutable object reference, records the original-byte fingerprint, retains extraction/metadata/blob references, and binds complete package membership through a deterministic manifest digest. A package with missing, unreadable, or unhashed members is visibly incomplete and cannot claim whole-package equality.

This package is a preservation and reproducibility boundary. It is **not** an evidence-custody claim and it is not the later **Evidence Release Package**. The two package concepts must never be collapsed again:

- **Intake Source Package:** always retained; supports exploration, context processing, repeatable extraction, and possible later evidence admission.
- **Evidence Release Package:** created only after the owner decides that reviewed material is important and relevant; carries the evidence projection and custody receipts.

Consequently, the intake choice is **what should happen next**, not **whether this can ever become evidence**. Choosing context, ELT, OCR, vision, metadata-only, preserve-only, or another current route never surrenders future evidence eligibility. If the owner later promotes material, the evidence-admission operation reopens the retained package, re-reads and rehashes the packaged original, compares it with the recorded original and complete-manifest fingerprints, re-extracts under recorded tool/parser versions, and then applies the evidence-only validation, owner gate, and H1/H2/H3 custody process. A context fingerprint may match a later custody hash because both cover the same bytes, but it may never be relabeled as custody without that fresh read and verification.

The route is still lane-specific. A source selected for context/ELT **now** does not hit PostgreSQL first and must not receive evidence-custody semantics. The retained object remains in R2/object storage as the source-package original; inspection and routing produce an n8n ingest plan; an eligible direct tool or pg_duckdb/httpfs path reads the object in place; only the bounded decoded context/raw result, execution identity, reproducibility fingerprints, decisions, and receipts land in PostgreSQL. Future evidence admission remains available through the retained package.

PostgreSQL is authoritative for transactional records that actually land there; it is not the universal first hop and not a replacement graph engine. SurrealDB receives the governed temporal/source-lineage projection, and Neo4j may receive the traversal-heavy operational/dependency projection within its assigned domain. Those projections are rebuilt through an outbox/projection boundary; owner decisions are never dual-written independently into multiple databases. n8n composes the visible ingest plan and its eligible branches. Temporal owns durable execution and waits. Workbench projects the operation and sends authenticated owner decisions. Tool/runtime services execute only the selected bounded steps and return provenance-bearing results.

For an image, the plan must distinguish integrity assessment from extraction. A clean image continues past repair assessment, then exposes only capabilities that are registered and ready, such as preserve plus metadata, OCR, vision analysis, or OCR plus vision. The recommended route is explicit, alternatives are visible, and owner selection or override is durably receipted.

Every operation must remain reopenable and show source identity, current stage, responsible service, eligible and selected routes, waits, errors, decisions, outputs, and receipts. Submission returns control to the operator; backgrounding is normal. Hold/cancel/retry are authenticated durable commands, not browser-only state changes.

The queue must display both package identity and the selected physical route. For a context/ELT operation that route is `R2 source-package original -> verify package identity -> inspect/route -> n8n plan -> direct tool or pg_duckdb ELT -> context/raw result and reproducibility receipts -> governed projections`; it must never imply a PostgreSQL-first custody path or a permanent loss of evidence eligibility.

## Existing proof and remaining wiring

This ruling composes already-established mechanisms rather than inventing another storage path:

- `retain_original_activity` binds a source version to exactly one immutable retained original object.
- `context-source-fingerprint-v1` fingerprints the source bytes at intake without making a custody claim.
- Consignatio Intake derives a deterministic package-manifest SHA-256 from normalized member paths, sizes, and full-content SHA-256 values only when every package member was hashed; its package-duplicate test exercises the complete-manifest path.
- The fidelity digest independently verifies that a later re-extraction did not change a message's content, source timestamp, source handle, or direction across the raw-to-normalized boundary.

The missing work is integration and operator visibility: the current Proffer workflow does not yet expose the source package, current-purpose choice, live capability alternatives, package-verification state, and later-admission action as one persistent operation. That is an implementation gap. It is not permission to reopen the package-first rule.

## Do-not-relitigate instruction

Future audits must ask **whether the implementation satisfies this rule**, never whether a context-routed source should lose future evidence eligibility. Reopening this decision requires an explicit owner statement that identifies what changed. Absent that statement, build the missing wiring and keep the package invariant intact.
