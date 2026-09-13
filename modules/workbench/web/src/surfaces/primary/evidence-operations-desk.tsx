// Byline: Codex · GPT-5.6-Sol · 2026-08-30
import { useEffect, useState } from "react";
import {
  ArrowRight,
  CircleDot,
  FileSearch,
  Inbox,
  Loader2,
  ReceiptText,
  ScanSearch,
  ShieldCheck,
} from "lucide-react";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { AppLink } from "@/lib/router-compat";
import { getHealth, listFiles, listFlags, listRuns } from "@/lib/api-client";
import { useFixedCase } from "@/lib/fixed-case-context";
import type { RunSummary } from "@/lib/shared/types";

interface DeskSnapshot {
  staged: number;
  openFlags: number;
  runs: RunSummary[];
  healthy: boolean;
}

const workflowSteps = [
  { label: "Stage source", detail: "Upload or select original source bytes for context intake." },
  { label: "Inspect preview", detail: "Read parser identity, structure, and message boundaries." },
  { label: "Confirm decision", detail: "Accept or reject the exact previewed material." },
  { label: "Follow receipt", detail: "Track the durable workflow without guessing completion." },
] as const;

function statusTone(status: RunSummary["status"]) {
  if (status === "completed") return "border-[#b8ddc7] bg-[#e2f3e9] text-[#17794b]";
  if (status === "failed") return "border-[#efc7c3] bg-[#fbe9e7] text-[#8e2f29]";
  if (status === "paused") return "border-[#ead5a9] bg-[#fff4dd] text-[#7d520d]";
  return "border-[#cdd3f1] bg-[#e9ecfb] text-[#2f3d9c]";
}

export function EvidenceOperationsDesk() {
  const { matter, primaryCourtCase, loading: caseLoading, error: caseError } = useFixedCase();
  const [snapshot, setSnapshot] = useState<DeskSnapshot | null>(null);
  const [snapshotError, setSnapshotError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    Promise.all([getHealth(), listFiles(), listFlags({ status: "open" }), listRuns({ limit: 6 })])
      .then(([health, files, flags, runs]) => {
        if (cancelled) return;
        setSnapshot({ staged: files.length, openFlags: flags.length, runs, healthy: health.status === "ok" });
        setSnapshotError(null);
      })
      .catch((error: unknown) => {
        if (cancelled) return;
        setSnapshotError(error instanceof Error ? error.message : "Live operational counts are unavailable");
      });
    return () => { cancelled = true; };
  }, []);

  return (
    <div className="mx-auto flex w-full max-w-[1480px] flex-col gap-6 px-5 py-6 lg:px-8 lg:py-8">
      <section className="grid gap-6 border-b border-border pb-7 xl:grid-cols-[minmax(0,1fr)_390px]">
        <div className="max-w-4xl">
          <p className="platform-kicker">Primary surface · browser preview</p>
          <h1 className="mt-3 max-w-3xl text-4xl font-semibold tracking-[-0.035em] text-foreground md:text-5xl">
            Evidence Operations Desk
          </h1>
          <p className="mt-4 max-w-2xl text-base leading-7 text-muted-foreground">
            Bring source material into the governed pipeline, inspect what the parser actually produced,
            and follow the durable receipt. This desk does not silently promote or rewrite evidence.
          </p>
          <div className="mt-6 flex flex-wrap gap-3">
            <Button asChild size="lg" className="rounded-sm">
              <AppLink href="/intake">Open intake <ArrowRight className="h-4 w-4" /></AppLink>
            </Button>
            <Button asChild size="lg" variant="outline" className="rounded-sm bg-card">
              <AppLink href="/evidence/preview">Inspect pipeline preview</AppLink>
            </Button>
          </div>
        </div>

        <aside className="border border-border bg-card p-5 shadow-[0_12px_28px_rgb(29_34_40_/_0.06)]" aria-label="Current case scope">
          <div className="flex items-center justify-between gap-4 border-b border-border pb-3">
            <p className="platform-rule-title">Current case scope</p>
            <ShieldCheck className="h-4 w-4 text-[#2f9d67]" />
          </div>
          {caseLoading ? (
            <p className="mt-5 flex items-center gap-2 text-sm text-muted-foreground"><Loader2 className="h-4 w-4 animate-spin" /> Loading canonical case</p>
          ) : matter ? (
            <div className="mt-5">
              <h2 className="text-xl font-semibold tracking-tight">{matter.title}</h2>
              <p className="mt-2 text-sm leading-6 text-muted-foreground">
                {primaryCourtCase?.caption || primaryCourtCase?.court_name || "Primary proceeding unavailable"}
              </p>
              <div className="mt-5 flex flex-wrap gap-2">
                <Badge variant="outline">{matter.status}</Badge>
                <Badge variant="outline">{matter.partition_keys.length} knowledge partition{matter.partition_keys.length === 1 ? "" : "s"}</Badge>
              </div>
            </div>
          ) : (
            <p className="mt-5 text-sm leading-6 text-destructive">{caseError || "Canonical case scope is unavailable."}</p>
          )}
        </aside>
      </section>

      <section className="grid gap-5 xl:grid-cols-[minmax(0,1.55fr)_minmax(360px,0.85fr)]">
        <article className="border border-border bg-card">
          <header className="flex items-center justify-between gap-4 border-b border-border px-5 py-4">
            <div>
              <p className="platform-rule-title">Governed intake path</p>
              <h2 className="mt-1 text-lg font-semibold">One visible chain from source to receipt</h2>
            </div>
            <ScanSearch className="h-5 w-5 text-primary" />
          </header>
          <ol className="grid md:grid-cols-2">
            {workflowSteps.map((step, index) => (
              <li key={step.label} className="relative border-b border-border p-5 odd:md:border-r last:border-b-0 md:[&:nth-last-child(-n+2)]:border-b-0">
                <div className="flex gap-4">
                  <span className="grid h-8 w-8 shrink-0 place-items-center border border-[#aeb6e8] bg-[#e9ecfb] font-mono text-xs font-semibold text-[#2f3d9c]">
                    {String(index + 1).padStart(2, "0")}
                  </span>
                  <div>
                    <h3 className="font-semibold">{step.label}</h3>
                    <p className="mt-1 text-sm leading-6 text-muted-foreground">{step.detail}</p>
                  </div>
                </div>
              </li>
            ))}
          </ol>
        </article>

        <article className="border border-border bg-[#202b33] text-[#f7f8f7]">
          <header className="border-b border-[#3d4952] px-5 py-4">
            <p className="text-[10px] font-semibold uppercase tracking-[0.12em] text-[#aeb7bc]">Live operational snapshot</p>
            <h2 className="mt-1 text-lg font-semibold">What needs attention now</h2>
          </header>
          {snapshot ? (
            <div className="grid grid-cols-3 divide-x divide-[#3d4952] border-b border-[#3d4952]">
              <div className="p-4"><strong className="block font-mono text-2xl">{snapshot.staged}</strong><span className="text-xs text-[#b8c0c5]">staged sources</span></div>
              <div className="p-4"><strong className="block font-mono text-2xl">{snapshot.openFlags}</strong><span className="text-xs text-[#b8c0c5]">open flags</span></div>
              <div className="p-4"><strong className="block font-mono text-2xl">{snapshot.runs.length}</strong><span className="text-xs text-[#b8c0c5]">recent runs</span></div>
            </div>
          ) : (
            <div className="border-b border-[#3d4952] p-5 text-sm text-[#c4cbd0]">
              {snapshotError || <span className="flex items-center gap-2"><Loader2 className="h-4 w-4 animate-spin" /> Loading live counts</span>}
            </div>
          )}
          <div className="p-5">
            <div className="flex items-center justify-between gap-3">
              <p className="text-xs font-semibold uppercase tracking-wide text-[#c9d0d4]">Recent durable runs</p>
              <span className="flex items-center gap-1 text-[11px] text-[#9fe0b9]"><CircleDot className="h-3 w-3" /> {snapshot?.healthy ? "API healthy" : "API status pending"}</span>
            </div>
            <div className="mt-4 space-y-2">
              {snapshot?.runs.length ? snapshot.runs.slice(0, 4).map((run) => (
                <div key={run.run_id} className="grid grid-cols-[minmax(0,1fr)_auto] items-center gap-3 border border-[#3d4952] bg-[#172129] px-3 py-2.5">
                  <div className="min-w-0">
                    <p className="truncate text-sm font-medium">{run.source_name || run.workflow}</p>
                    <p className="truncate font-mono text-[10px] text-[#9da8ae]">{run.run_id}</p>
                  </div>
                  <span className={`border px-2 py-1 text-[10px] font-semibold uppercase tracking-wide ${statusTone(run.status)}`}>{run.status}</span>
                </div>
              )) : (
                <p className="py-6 text-sm text-[#aeb7bc]">{snapshot ? "No durable runs are available." : "Run history is loading."}</p>
              )}
            </div>
          </div>
        </article>
      </section>

      <section className="grid gap-4 border-t border-border pt-5 md:grid-cols-3" aria-label="Primary desk capabilities">
        <div className="flex gap-3"><Inbox className="mt-0.5 h-4 w-4 text-primary" /><div><h2 className="text-sm font-semibold">Intake</h2><p className="mt-1 text-xs leading-5 text-muted-foreground">Stage sources without treating upload as evidence promotion.</p></div></div>
        <div className="flex gap-3"><FileSearch className="mt-0.5 h-4 w-4 text-primary" /><div><h2 className="text-sm font-semibold">Preview</h2><p className="mt-1 text-xs leading-5 text-muted-foreground">Inspect parser identity, messages, and provenance before deciding.</p></div></div>
        <div className="flex gap-3"><ReceiptText className="mt-0.5 h-4 w-4 text-primary" /><div><h2 className="text-sm font-semibold">Receipt</h2><p className="mt-1 text-xs leading-5 text-muted-foreground">Follow durable state instead of inferring completion from the screen.</p></div></div>
      </section>
    </div>
  );
}
