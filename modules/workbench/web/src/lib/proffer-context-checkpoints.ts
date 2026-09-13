import type { ProfferPreviewCheckpoint, ProfferPreviewEvent, ProfferPreviewReceipt } from "@/lib/shared/types";

export const PROFFER_CONTEXT_CHECKPOINTS = [
  { type: "raw_source_verification", label: "Raw source verification" },
  { type: "parser_selection", label: "Parser selection" },
  { type: "parser_execution", label: "Parser execution" },
  { type: "normalization", label: "Normalization" },
  { type: "storage", label: "Storage" },
  { type: "completeness", label: "Completeness" },
] as const;

export type ProfferContextCheckpointType = (typeof PROFFER_CONTEXT_CHECKPOINTS)[number]["type"];
export type ProfferContextCheckpointStatus = "waiting" | "running" | "completed" | "failed";

export const PROFFER_CHECKPOINT_WAITING_COPY = "Waiting for this checkpoint.";
export const PROFFER_CHECKPOINT_FAILED_COPY = "Stopped here. The full preview remains locked.";

export function checkpointLabel(type: ProfferContextCheckpointType) {
  return PROFFER_CONTEXT_CHECKPOINTS.find((checkpoint) => checkpoint.type === type)?.label ?? type;
}

export function profferCheckpointStatuses({
  started,
  phase,
  receipts = [],
  checkpoints = [],
  events = [],
}: {
  started: boolean;
  phase?: string;
  receipts?: ProfferPreviewReceipt[] | null;
  checkpoints?: ProfferPreviewCheckpoint[] | null;
  events?: ProfferPreviewEvent[];
}): Record<ProfferContextCheckpointType, ProfferContextCheckpointStatus> {
  const statuses = Object.fromEntries(
    PROFFER_CONTEXT_CHECKPOINTS.map(({ type }) => [type, "waiting"]),
  ) as Record<ProfferContextCheckpointType, ProfferContextCheckpointStatus>;

  for (const receipt of receipts ?? []) {
    statuses[receipt.receipt_type] = receipt.status === "completed" || receipt.status === "skipped"
      ? "completed"
      : receipt.status === "failed"
        ? "failed"
        : "running";
  }

  for (const checkpoint of checkpoints ?? []) {
    statuses[checkpoint.checkpoint] = checkpoint.status === "pending" ? "waiting" : checkpoint.status;
  }

  const firstUnfinished = PROFFER_CONTEXT_CHECKPOINTS.find(({ type }) => statuses[type] === "waiting");
  const workflowFailed = phase === "failed" || events.some((event) => event.event_type === "failed");
  if (firstUnfinished) {
    if (workflowFailed) statuses[firstUnfinished.type] = "failed";
    else if (started) statuses[firstUnfinished.type] = "running";
  }

  return statuses;
}

export function profferContextFlowComplete(
  receipts: ProfferPreviewReceipt[] | null | undefined,
  checkpoints?: ProfferPreviewCheckpoint[] | null,
) {
  return PROFFER_CONTEXT_CHECKPOINTS.every(({ type }) => {
    const durableReceiptComplete = receipts?.some(
      (receipt) => receipt.receipt_type === type && receipt.status === "completed",
    );
    const liveCheckpointComplete = !checkpoints?.length || checkpoints.some(
      (checkpoint) => checkpoint.checkpoint === type && checkpoint.status === "completed",
    );
    return Boolean(durableReceiptComplete && liveCheckpointComplete);
  });
}
