// Byline: Codex · GPT-5 · 2026-09-12
/** Presentation-only compatibility for historical ingest stage identifiers.
 * Never edits persisted receipts or applies to promotion/court-readiness views.
 */
export function ingestStageLabel(name: string): string {
  switch (name.toLowerCase()) {
    case "custody":
    case "raw_source_verification":
      return "Raw-source verification";
    default:
      return name.replaceAll("_", " ");
  }
}
