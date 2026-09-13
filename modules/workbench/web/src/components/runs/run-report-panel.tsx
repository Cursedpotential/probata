// Byline: Codex · GPT-5 · 2026-08-13
"use client";

import { useState } from "react";
import { ExternalLink } from "lucide-react";
import { toast } from "sonner";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { createRunReviewAction } from "@/lib/api-client";
import type { RunReport } from "@/lib/shared/types";
import { ingestStageLabel } from "./stage-label";

export function RunReportPanel({
  runId,
  report,
  onRecorded,
}: {
  runId: string;
  report: RunReport;
  onRecorded: () => Promise<void>;
}) {
  const [selectedSeq, setSelectedSeq] = useState<number | undefined>();
  const [reason, setReason] = useState("");
  const [pending, setPending] = useState(false);
  const reviewStages = report.data.stages.filter((stage) => stage.review.decision_required);
  const summary = report.data.summary;

  const record = async (actionType: "acknowledge" | "approve" | "override") => {
    if (!reason.trim()) {
      toast.error("A reason is mandatory for every review action");
      return;
    }
    setPending(true);
    try {
      await createRunReviewAction(runId, {
        action_type: actionType,
        reason: reason.trim(),
        stage_seq: selectedSeq,
        ...(actionType === "override" ? { replacement: { operator_instruction: reason.trim() } } : {}),
      });
      setReason("");
      toast.success(`${actionType} recorded in the append-only report`);
      await onRecorded();
    } catch (error) {
      toast.error(error instanceof Error ? error.message : "Could not record review action");
    } finally {
      setPending(false);
    }
  };

  return (
    <section className="space-y-3 rounded-md border p-3">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div>
          <p className="text-sm font-semibold">Durable run report</p>
          <p className="text-xs text-muted-foreground">Schema {report.schema_version} · original outcomes are never overwritten</p>
        </div>
        <div className="flex flex-wrap gap-1">
          <Badge variant="default">{summary.passed} ran successfully</Badge>
          <Badge variant={summary.skipped ? "secondary" : "outline"}>{summary.skipped} skipped</Badge>
          <Badge variant={summary.failed ? "destructive" : "outline"}>{summary.failed} failed</Badge>
        </div>
      </div>

      {reviewStages.length > 0 && (
        <div className="space-y-1.5">
          <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">Needs review</p>
          {reviewStages.map((stage) => (
            <button
              type="button"
              key={stage.seq}
              onClick={() => setSelectedSeq(stage.seq)}
              className={`block w-full rounded border p-2 text-left text-xs ${selectedSeq === stage.seq ? "border-primary bg-primary/5" : ""}`}
            >
              <span className="font-semibold">{stage.seq}. {ingestStageLabel(stage.name)} — {stage.status}</span>
              <span className="mt-0.5 block text-muted-foreground">
                {stage.reason.code || "unspecified"}: {stage.reason.detail || "No detail recorded"}
              </span>
            </button>
          ))}
        </div>
      )}

      {report.data.trace.url && (
        <a
          className="inline-flex items-center gap-1 text-xs underline underline-offset-2"
          href={report.data.trace.url}
          target="_blank"
          rel="noreferrer"
        >
          Open correlated Langfuse trace <ExternalLink className="size-3" />
        </a>
      )}

      <div className="space-y-2">
        <Textarea
          value={reason}
          onChange={(event) => setReason(event.target.value)}
          placeholder="Mandatory reason for approval, acknowledgement, or override"
          rows={2}
        />
        <div className="flex flex-wrap gap-2">
          <Button size="sm" variant="outline" disabled={pending} onClick={() => record("acknowledge")}>Acknowledge</Button>
          <Button size="sm" disabled={pending} onClick={() => record("approve")}>Approve</Button>
          <Button size="sm" variant="secondary" disabled={pending} onClick={() => record("override")}>Record override</Button>
        </div>
      </div>

      {report.data.review_actions.length > 0 && (
        <details>
          <summary className="cursor-pointer text-xs font-medium">Review history ({report.data.review_actions.length})</summary>
          <div className="mt-2 space-y-1">
            {report.data.review_actions.map((action) => (
              <div key={action.action_id} className="rounded border p-2 text-xs">
                <span className="font-semibold">{action.action_type}</span>
                {action.stage_seq ? ` · stage ${action.stage_seq}` : " · whole run"} — {action.reason}
              </div>
            ))}
          </div>
        </details>
      )}
    </section>
  );
}
