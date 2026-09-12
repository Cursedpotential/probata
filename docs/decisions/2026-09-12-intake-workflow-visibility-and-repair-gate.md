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
