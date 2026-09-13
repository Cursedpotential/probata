// Byline: Claude Code · Sonnet (agent) · 2026-07-21 (C2: supervised-gate controls — continue/abort/retry; C2.6: louder failure banner + retry from_stage=knowledge)
// Byline: Codex · GPT-5 · 2026-08-13 (durable interactive report)
// Byline: Codex · GPT-5 · 2026-08-27 (bounded live run-event panel)
"use client";

/**
 * Run detail: the stage rail plus per-run metadata, opened as a Dialog from
 * a Runs-table row (mirrors the existing FileDetailDialog pattern rather
 * than a Next.js dynamic route — this app is a static export with
 * `output: 'export'`, so a `/runs/[id]` route would need
 * `generateStaticParams` enumerating every run id at BUILD time, which
 * can't work for runs created after deploy).
 *
 * Polls `GET /api/runs/{id}` every 2s while status is "running" OR "paused"
 * (a gate is a wait state, not a terminal one — something else could still
 * move the run along), stopping only on a terminal status or dialog close.
 *
 * C2 gate controls, per the console/c2-spine contract this frontend codes
 * against (a parallel branch): `status==='paused' && gate_state==='waiting'`
 * means the run is stopped at a gate and the NEXT pending stage is the
 * gated one — surfaced here as a prominent banner with Continue/Abort.
 * While running, Abort is still available but takes effect at the next
 * stage boundary, not instantly. A terminal-failed run gets a Retry button
 * that starts a new run and — since this dialog is controlled by the
 * parent's `runId` state, not its own — asks the parent (`onNavigateToRun`)
 * to swap over to the new run so the operator watches it land.
 *
 * C2.6 requirement 3 (louder failures): a failed run now gets a prominent
 * red banner at the TOP of the dialog with the failing stage name and its
 * full error text (monospace, copy button) — replaces the old small
 * failed-stage callout that used to sit below the stage rail. When the
 * failing stage is specifically "knowledge", a second "Retry from
 * knowledge" button (server/evidence/workflows.py's
 * `run_knowledge_from_store`, C2.6 requirement 1) sits next to the regular
 * full Retry — it skips straight to re-running the knowledge stage over
 * this run's already-stored records instead of a full rerun.
 */
import { useEffect, useRef, useState } from "react";
import { AlertTriangle, Pause, RotateCcw, Zap } from "lucide-react";
import { toast } from "sonner";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
} from "@/components/ui/dialog";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Separator } from "@/components/ui/separator";
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip";
import { StageRail } from "./stage-rail";
import { StageDrawer } from "./stage-drawer";
import { CopyButton } from "./stage-output-view";
import { ingestStageLabel } from "./stage-label";
import { RunReportPanel } from "./run-report-panel";
import { RunEventsPanel } from "./run-events-panel";
import { ApiError, abortRun, continueRun, getRun, getRunReport, retryRun } from "@/lib/api-client";
import { useRefresh } from "@/lib/refresh-context";
import { formatDate } from "@/lib/utils";
import type { RunDetail, RunReport, RunStageDetail } from "@/lib/shared/types";

const POLL_INTERVAL_MS = 2000;

interface RunDetailDialogProps {
  runId: string | null;
  open: boolean;
  onOpenChange: (open: boolean) => void;
  /** C2: called with a new run_id after a successful Retry, so the parent
   * can point this same dialog at the freshly created run instead of
   * closing it. Optional so existing callers keep working untouched. */
  onNavigateToRun?: (runId: string) => void;
}

function statusBadgeVariant(status: string): "default" | "secondary" | "destructive" | "outline" {
  switch (status) {
    case "completed":
      return "default";
    case "running":
      return "secondary";
    case "failed":
      return "destructive";
    default:
      return "outline";
  }
}

export function RunDetailDialog({ runId, open, onOpenChange, onNavigateToRun }: RunDetailDialogProps) {
  const [run, setRun] = useState<RunDetail | null>(null);
  const [report, setReport] = useState<RunReport | null>(null);
  const [selectedSeq, setSelectedSeq] = useState<number | null>(null);
  const [drawerOpen, setDrawerOpen] = useState(false);
  const [actionPending, setActionPending] = useState(false);
  const [abortConfirmOpen, setAbortConfirmOpen] = useState(false);
  const intervalRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const lastReportVersionRef = useRef<string | null>(null);
  const { triggerRefresh } = useRefresh();

  const stopPolling = () => {
    if (intervalRef.current) {
      clearInterval(intervalRef.current);
      intervalRef.current = null;
    }
  };

  useEffect(() => {
    if (!open || !runId) {
      stopPolling();
      lastReportVersionRef.current = null;
      queueMicrotask(() => setRun(null));
      queueMicrotask(() => setReport(null));
      return;
    }

    let cancelled = false;
    lastReportVersionRef.current = null;
    queueMicrotask(() => {
      if (!cancelled) setReport(null);
    });
    const fetchRun = async () => {
      try {
        const data = await getRun(runId);
        if (cancelled) return;
        setRun(data);
        const reportVersion = `${runId}:${data.status}:${data.updated_at}`;
        let reportSucceeded = lastReportVersionRef.current === reportVersion;
        if (!reportSucceeded) {
          try {
            const nextReport = await getRunReport(runId);
            if (cancelled) return;
            setReport(nextReport);
            lastReportVersionRef.current = reportVersion;
            reportSucceeded = true;
          } catch {
            // Report migration/API may lag during a rolling deploy; the
            // underlying run view remains available and polling retries.
          }
        }
        // Paused is a wait state, not terminal — keep polling in case a
        // gate action lands from elsewhere (another tab/session). A terminal
        // run stops only after its report was retrieved successfully.
        if (reportSucceeded && data.status !== "running" && data.status !== "paused") stopPolling();
      } catch {
        // Transient poll failure — keep the last-known state, try again next tick.
      }
    };

    fetchRun();
    intervalRef.current = setInterval(fetchRun, POLL_INTERVAL_MS);

    return () => {
      cancelled = true;
      stopPolling();
    };
  }, [open, runId]);

  const handleSelectStage = (seq: number) => {
    setSelectedSeq(seq);
    setDrawerOpen(true);
  };

  const selectedStage: RunStageDetail | null =
    run?.stages.find((s) => s.seq === selectedSeq) ?? null;
  const failedStage = run?.stages.find((s) => s.status === "failed");

  // C2: the gate always sits at the next pending stage of a paused run —
  // per the spine contract, `paused` + `gate_state==='waiting'` together
  // mean exactly this, so there is no separate "which stage" field to read.
  const isGated = run?.status === "paused" && run.gate_state === "waiting";
  const gatedStage = isGated ? run?.stages.find((s) => s.status === "pending") : undefined;

  const refetchNow = async () => {
    if (!runId) return;
    try {
      const data = await getRun(runId);
      setRun(data);
      setReport(await getRunReport(runId));
      lastReportVersionRef.current = `${runId}:${data.status}:${data.updated_at}`;
    } catch {
      // Swallow — the next poll tick (or the toast already shown) covers it.
    }
  };

  const handleContinue = async () => {
    if (!runId) return;
    setActionPending(true);
    try {
      await continueRun(runId);
      toast.success("Run released past the gate");
      await refetchNow();
      triggerRefresh();
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : "Failed to continue run");
    } finally {
      setActionPending(false);
    }
  };

  const handleAbort = async () => {
    if (!runId) return;
    setAbortConfirmOpen(false);
    setActionPending(true);
    try {
      await abortRun(runId);
      toast.success("Run aborted");
      await refetchNow();
      triggerRefresh();
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : "Failed to abort run");
    } finally {
      setActionPending(false);
    }
  };

  const handleRetry = async (fromKnowledge = false) => {
    if (!runId) return;
    setActionPending(true);
    try {
      const result = await retryRun(runId, fromKnowledge ? "knowledge" : undefined);
      toast.success(
        fromKnowledge ? `Retried from knowledge stage as ${result.run_id}` : `Retried as ${result.run_id}`,
      );
      triggerRefresh();
      onNavigateToRun?.(result.run_id);
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : "Failed to retry run");
    } finally {
      setActionPending(false);
    }
  };

  return (
    <>
      <Dialog open={open} onOpenChange={(next) => { if (!next) setAbortConfirmOpen(false); onOpenChange(next); }}>
        <DialogContent className="max-w-3xl">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2 truncate">
              {run?.source_name ?? runId}
              {run && <Badge variant={statusBadgeVariant(run.status)}>{run.status}</Badge>}
            </DialogTitle>
            {run && (
              <DialogDescription>
                {run.workflow} · {run.domain || "no domain"} · {run.mode}
              </DialogDescription>
            )}
          </DialogHeader>

          {!run ? (
            <p className="py-8 text-center text-sm text-muted-foreground">Loading…</p>
          ) : (
            <div className="space-y-4">
              {/* C2.6 requirement 3: prominent red banner at the TOP for a
                  failed run — the failing stage's full error text (or, if
                  no stage was individually marked failed, run.error — set
                  only when an exception escaped the runner itself, rare)
                  in a monospace block with a copy button. */}
              {run.status === "failed" && (
                <div className="space-y-2 rounded-md border-2 border-destructive bg-destructive/10 p-3">
                  <div className="flex items-center gap-2 text-sm font-semibold text-destructive">
                    <AlertTriangle className="size-4 shrink-0" />
                    {failedStage ? `Run failed at stage "${ingestStageLabel(failedStage.name)}"` : "Run failed"}
                  </div>
                  {failedStage?.content && (
                    <div className="relative">
                      <pre className="max-h-56 overflow-auto whitespace-pre-wrap rounded-md border border-destructive/30 bg-background p-2 pr-9 font-mono text-xs text-destructive">
                        {failedStage.content}
                      </pre>
                      <div className="absolute right-1 top-1">
                        <CopyButton text={failedStage.content} />
                      </div>
                    </div>
                  )}
                  {run.error && run.error !== failedStage?.content && (
                    <div className="relative">
                      <p className="text-xs font-medium uppercase tracking-wide text-destructive/80">Run error</p>
                      <pre className="max-h-56 overflow-auto whitespace-pre-wrap rounded-md border border-destructive/30 bg-background p-2 pr-9 font-mono text-xs text-destructive">
                        {run.error}
                      </pre>
                      <div className="absolute right-1 top-6">
                        <CopyButton text={run.error} />
                      </div>
                    </div>
                  )}
                </div>
              )}

              {abortConfirmOpen && (
                <div className="flex flex-wrap items-center justify-between gap-3 rounded-md border-2 border-destructive bg-destructive/10 p-3">
                  <div>
                    <p className="text-sm font-semibold text-destructive">Confirm run abort</p>
                    <p className="text-xs text-muted-foreground">This stops the run at its next safe stage boundary and cannot be undone.</p>
                  </div>
                  <div className="flex gap-2">
                    <Button size="sm" variant="outline" onClick={() => setAbortConfirmOpen(false)}>Cancel</Button>
                    <Button size="sm" variant="destructive" onClick={handleAbort} disabled={actionPending}>Confirm abort</Button>
                  </div>
                </div>
              )}

              {isGated && (
                <div className="flex flex-wrap items-center justify-between gap-3 rounded-md border border-amber-500/50 bg-amber-500/10 px-3 py-2">
                  <div className="flex items-center gap-2 text-sm">
                    <Pause className="size-4 shrink-0 text-amber-600 dark:text-amber-400" />
                    <span className="font-medium text-amber-700 dark:text-amber-400">
                      Paused at gate — next: {gatedStage ? ingestStageLabel(gatedStage.name) : "unknown stage"}
                    </span>
                  </div>
                  <div className="flex gap-2">
                    <Button size="sm" onClick={handleContinue} disabled={actionPending}>
                      Continue
                    </Button>
                    <Button size="sm" variant="destructive" onClick={() => setAbortConfirmOpen(true)} disabled={actionPending}>
                      Abort
                    </Button>
                  </div>
                </div>
              )}

              <StageRail
                stages={run.stages}
                variant="full"
                activeSeq={selectedSeq ?? undefined}
                onSelect={handleSelectStage}
                gatedSeq={gatedStage?.seq}
              />

              <RunEventsPanel runId={run.run_id} />

              {run.status === "running" && (
                <div className="flex justify-end">
                  <Tooltip>
                    <TooltipTrigger asChild>
                      <Button size="sm" variant="outline" onClick={() => setAbortConfirmOpen(true)} disabled={actionPending}>
                        Abort
                      </Button>
                    </TooltipTrigger>
                    <TooltipContent>Takes effect at the next stage boundary, not instantly</TooltipContent>
                  </Tooltip>
                </div>
              )}

              {run.status === "failed" && (
                <div className="flex flex-wrap justify-end gap-2">
                  {/* C2.6 requirement 1: when the knowledge stage is
                      specifically what failed, offer the targeted retry
                      that skips custody/parse/store and re-runs only
                      knowledge over this run's already-stored records
                      (server/evidence/workflows.py's run_knowledge_from_store) —
                      faster, and sidesteps the custody-dedupe/no-new-rows
                      trap a full rerun could otherwise hit. */}
                  {failedStage?.name === "knowledge" && (
                    <Tooltip>
                      <TooltipTrigger asChild>
                        <Button
                          size="sm"
                          variant="outline"
                          onClick={() => handleRetry(true)}
                          disabled={actionPending}
                        >
                          <Zap className="size-4" />
                          Retry from knowledge
                        </Button>
                      </TooltipTrigger>
                      <TooltipContent>
                        Uses this historical run&apos;s already-stored records
                      </TooltipContent>
                    </Tooltip>
                  )}
                  <Button size="sm" onClick={() => handleRetry()} disabled={actionPending}>
                    <RotateCcw className="size-4" />
                    Retry
                  </Button>
                </div>
              )}

              {report && (
                <RunReportPanel runId={run.run_id} report={report} onRecorded={refetchNow} />
              )}

              <Separator />
              <div className="grid grid-cols-2 gap-x-4 gap-y-1 text-sm">
                <div className="flex justify-between">
                  <span className="text-muted-foreground">Run ID</span>
                  <span className="truncate font-mono text-xs">{run.run_id}</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-muted-foreground">sha256</span>
                  <span className="truncate font-mono text-xs">{run.sha256}</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-muted-foreground">Created</span>
                  <span>{formatDate(run.created_at)}</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-muted-foreground">Updated</span>
                  <span>{formatDate(run.updated_at)}</span>
                </div>
                {run.parent_run_id && (
                  <div className="col-span-2 flex justify-between">
                    <span className="text-muted-foreground">Retried from</span>
                    <button
                      type="button"
                      className="truncate font-mono text-xs underline underline-offset-2 hover:text-foreground disabled:no-underline disabled:opacity-60"
                      onClick={() => onNavigateToRun?.(run.parent_run_id as string)}
                      disabled={!onNavigateToRun}
                      title={onNavigateToRun ? "Open the parent run" : run.parent_run_id}
                    >
                      {run.parent_run_id}
                    </button>
                  </div>
                )}
              </div>
            </div>
          )}
        </DialogContent>
      </Dialog>

      <StageDrawer
        stage={selectedStage}
        open={drawerOpen}
        onOpenChange={setDrawerOpen}
        sha256={run?.sha256}
      />
    </>
  );
}
