import { useFixedCase } from "@/lib/fixed-case-context";
import type { MatterMode } from "@/lib/shared/types";
import { cn } from "@/lib/utils";

const MODES: MatterMode[] = ["TEST", "REAL"];

export function MatterModeSelector({ compact = false }: { compact?: boolean }) {
  const { mode, setMode, loading } = useFixedCase();

  return (
    <div className={cn("border p-1", mode === "TEST" ? "border-[#c58214] bg-[#fff4dd] text-[#4d3711] dark:bg-[#43351f] dark:text-[#ffe0a6]" : "border-[#b5433b] bg-[#fbe9e7] text-[#762b26] dark:bg-[#3a2422] dark:text-[#ffb5ae]")}>
      <div className="flex items-center gap-1" role="group" aria-label="Matter data mode">
        {MODES.map((candidate) => (
          <button
            key={candidate}
            type="button"
            aria-pressed={mode === candidate}
            disabled={loading}
            onClick={() => setMode(candidate)}
            className={cn(
              "min-h-8 px-3 text-xs font-semibold tracking-wide focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring",
              mode === candidate ? "bg-foreground text-background" : "hover:bg-background/70",
              compact && "min-h-7 px-2 text-[11px]",
            )}
          >
            {candidate}
          </button>
        ))}
        <span className={cn("px-2 text-xs font-semibold", compact && "text-[11px]")} aria-live="polite">
          {mode} mode active
        </span>
      </div>
    </div>
  );
}
