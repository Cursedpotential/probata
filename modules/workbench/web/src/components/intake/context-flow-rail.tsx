import { AlertTriangle, Check, Loader2 } from "lucide-react";

import {
  PROFFER_CHECKPOINT_FAILED_COPY,
  PROFFER_CHECKPOINT_WAITING_COPY,
  PROFFER_CONTEXT_CHECKPOINTS,
  profferCheckpointStatuses,
} from "@/lib/proffer-context-checkpoints";
import type { ProfferPreviewCheckpoint, ProfferPreviewEvent, ProfferPreviewReceipt } from "@/lib/shared/types";
import { cn } from "@/lib/utils";

export function ContextFlowRail({
  started,
  phase,
  receipts,
  checkpoints,
  events,
}: {
  started: boolean;
  phase?: string;
  receipts?: ProfferPreviewReceipt[] | null;
  checkpoints?: ProfferPreviewCheckpoint[] | null;
  events?: ProfferPreviewEvent[];
}) {
  const statuses = profferCheckpointStatuses({ started, phase, receipts, checkpoints, events });

  return (
    <section className="border-b bg-card px-6 py-4" aria-labelledby="context-flow-heading">
      <div className="mb-3 flex flex-wrap items-baseline justify-between gap-2">
        <h2 id="context-flow-heading" className="text-sm font-semibold">Context processing</h2>
        <p className="text-xs text-muted-foreground">Full preview unlocks after all six checkpoints complete.</p>
      </div>
      <ol className="grid gap-2 sm:grid-cols-2 xl:grid-cols-6" aria-label="Context processing checkpoints">
        {PROFFER_CONTEXT_CHECKPOINTS.map((checkpoint, index) => {
          const status = statuses[checkpoint.type];
          const statusCopy = status === "completed"
            ? "Completed."
            : status === "running"
              ? "In progress."
              : status === "failed"
                ? PROFFER_CHECKPOINT_FAILED_COPY
                : PROFFER_CHECKPOINT_WAITING_COPY;
          return (
            <li
              key={checkpoint.type}
              data-checkpoint={checkpoint.type}
              data-status={status}
              className="relative grid grid-cols-[1.75rem_1fr] gap-x-2 gap-y-0.5 sm:min-h-20 xl:grid-cols-1 xl:grid-rows-[1.75rem_auto_auto] xl:pr-3 xl:after:absolute xl:after:left-7 xl:after:right-0 xl:after:top-3.5 xl:after:h-px xl:after:bg-border xl:last:after:hidden"
            >
              <span
                className={cn(
                  "relative z-10 grid h-7 w-7 place-items-center rounded-full border bg-card text-xs font-semibold",
                  status === "completed" && "border-[#2f9d67] bg-[#2f9d67] text-white",
                  status === "running" && "border-primary text-primary",
                  status === "failed" && "border-destructive bg-destructive text-destructive-foreground",
                )}
                aria-hidden="true"
              >
                {status === "completed" ? <Check className="h-3.5 w-3.5" /> : status === "running" ? <Loader2 className="h-3.5 w-3.5 animate-spin motion-reduce:animate-none" /> : status === "failed" ? <AlertTriangle className="h-3.5 w-3.5" /> : index + 1}
              </span>
              <strong className="self-center text-xs leading-5 xl:mt-1">{checkpoint.label}</strong>
              <span className={cn("col-start-2 text-[11px] leading-4 text-muted-foreground xl:col-start-1", status === "failed" && "text-destructive")} role={status === "failed" ? "alert" : "status"}>
                {statusCopy}
              </span>
            </li>
          );
        })}
      </ol>
    </section>
  );
}
