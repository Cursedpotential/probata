// Byline: Claude Code · Sonnet (agent) · 2026-07-20 (C2: gatedSeq pulsing-ring indicator)
"use client";

/**
 * Historical ingest stage rail, in whatever order
 * and under whatever names the API actually returned for THIS run (per
 * workflow, per the build brief) — `FALLBACK_STAGE_NAMES` only fills in a
 * label when a run genuinely has no stages yet (e.g. still queued).
 *
 * Two variants: "mini" (a row of small dots for the Runs table) and "full"
 * (a labeled, clickable stepper for the run-detail dialog).
 *
 * C2: an optional `gatedSeq` marks the stage a paused run is stopped at
 * (the caller computes this as the lowest-seq 'pending' stage when
 * `status==='paused' && gate_state==='waiting'`) with a pulsing amber ring,
 * so operators can see where a gate is without opening the drawer.
 */
import { Check, X, Loader2, Circle, Minus } from "lucide-react";
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip";
import { cn } from "@/lib/utils";
import type { StageStatus } from "@/lib/shared/types";
import { ingestStageLabel } from "./stage-label";

/** Only used when a run has zero stages reported yet — never overrides real API data. */
const FALLBACK_STAGE_NAMES = ["raw_source_verification", "parse", "store", "knowledge"];

interface StageLike {
  seq: number;
  name: string;
  status: StageStatus;
}

interface StageRailProps {
  stages: StageLike[];
  variant?: "mini" | "full";
  activeSeq?: number;
  onSelect?: (seq: number) => void;
  /** C2: seq of the stage a paused run is gated at — rendered with a
   * pulsing amber ring in both variants. */
  gatedSeq?: number;
}

function statusColorClasses(status: StageStatus): string {
  switch (status) {
    case "success":
      return "bg-green-600 border-green-600 text-white";
    case "running":
      return "bg-blue-600 border-blue-600 text-white";
    case "failed":
      return "bg-destructive border-destructive text-white";
    case "skipped":
      return "bg-muted border-muted-foreground/50 text-muted-foreground";
    default:
      return "bg-muted border-muted-foreground/30 text-muted-foreground";
  }
}

function StatusIcon({ status }: { status: StageStatus }) {
  switch (status) {
    case "success":
      return <Check className="size-3" />;
    case "running":
      return <Loader2 className="size-3 animate-spin" />;
    case "failed":
      return <X className="size-3" />;
    case "skipped":
      return <Minus className="size-3" />;
    default:
      return <Circle className="size-2 fill-current" />;
  }
}

export function StageRail({ stages, variant = "full", activeSeq, onSelect, gatedSeq }: StageRailProps) {
  const items: StageLike[] =
    stages.length > 0
      ? stages
      : FALLBACK_STAGE_NAMES.map((name, i) => ({ seq: i, name, status: "pending" }));

  if (variant === "mini") {
    return (
      <div className="flex items-center gap-1">
        {items.map((stage) => (
          <Tooltip key={stage.seq}>
            <TooltipTrigger asChild>
              <span
                className={cn(
                  "inline-flex size-2.5 shrink-0 rounded-full border",
                  statusColorClasses(stage.status).split(" ").slice(0, 2).join(" "),
                  stage.seq === gatedSeq &&
                    "ring-2 ring-amber-500 ring-offset-1 ring-offset-background animate-pulse",
                )}
              />
            </TooltipTrigger>
            <TooltipContent>
              {ingestStageLabel(stage.name)}: {stage.status}
              {stage.seq === gatedSeq ? " (gated)" : ""}
            </TooltipContent>
          </Tooltip>
        ))}
      </div>
    );
  }

  return (
    <div className="flex items-start">
      {items.map((stage, i) => (
        <div key={stage.seq} className="flex flex-1 items-center last:flex-none">
          <button
            type="button"
            onClick={() => onSelect?.(stage.seq)}
            disabled={!onSelect}
            className={cn(
              "flex flex-col items-center gap-1.5 px-1 text-center",
              onSelect && "cursor-pointer",
            )}
          >
            <span
              className={cn(
                "flex size-8 items-center justify-center rounded-full border-2 transition-colors",
                statusColorClasses(stage.status),
                activeSeq === stage.seq && "ring-2 ring-ring ring-offset-2 ring-offset-background",
                stage.seq === gatedSeq &&
                  "ring-2 ring-amber-500 ring-offset-2 ring-offset-background animate-pulse",
              )}
            >
              <StatusIcon status={stage.status} />
            </span>
            <span className="max-w-28 text-xs font-medium capitalize">{ingestStageLabel(stage.name)}</span>
          </button>
          {i < items.length - 1 && (
            <div
              className={cn(
                "mt-4 h-0.5 flex-1",
                stage.status === "success" ? "bg-green-600" : "bg-muted-foreground/20",
              )}
            />
          )}
        </div>
      ))}
    </div>
  );
}
