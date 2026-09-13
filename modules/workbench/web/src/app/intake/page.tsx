// Byline: Claude Code · Sonnet (agent) · 2026-07-20
// Byline: Codex · GPT-5 · 2026-08-28 (production Proffer intake surface)
/**
 * Intake — the renamed Files page. Upload is folded in here (no more
 * standalone /upload route — see _stale/upload-page-pre-c1/ for the retired
 * route file) and the Promote buttons are gone (owner rejected the
 * upload->promote blind-box UX); each row's action is now "Start run ->",
 * which opens the New-run dialog prefilled with that staged file.
 */
import { UnifiedIntake } from "@/components/intake/unified-intake";
import { IntakeTable } from "@/components/intake/intake-table";
import { ProfferOperationsTable } from "@/components/intake/proffer-operations-table";

export default function IntakePage() {
  return (
    <div className="space-y-8 pb-10">
      <UnifiedIntake />
      <section className="space-y-4 px-5 lg:px-8" aria-labelledby="proffer-operations-heading">
        <div>
          <p className="platform-kicker mb-1">Process visibility</p>
          <h2 id="proffer-operations-heading" className="text-xl font-semibold tracking-tight">Proffer operations</h2>
          <p className="mt-1 text-sm text-muted-foreground">Running, waiting, failed, unavailable, and completed Proffer work remains visible across navigation and refresh.</p>
        </div>
        <ProfferOperationsTable />
      </section>
      <section className="space-y-4 px-5 lg:px-8" aria-labelledby="intake-inventory-heading">
        <div>
          <p className="platform-kicker mb-1">Legacy staging inventory</p>
          <h2 id="intake-inventory-heading" className="text-xl font-semibold tracking-tight">Workbench staged files</h2>
          <p className="mt-1 text-sm text-muted-foreground">This existing file list is not a Proffer operation history. Durable Proffer work is listed above.</p>
        </div>
        <IntakeTable />
      </section>
    </div>
  );
}
