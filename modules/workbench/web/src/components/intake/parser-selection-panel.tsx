"use client";

import { AlertTriangle, Database, ShieldCheck } from "lucide-react";

import { Button } from "@/components/ui/button";
import type { ProfferParserCandidate, ProfferPreviewReceipt, ProfferPreviewResponse, ProfferSourceInspection } from "@/lib/shared/types";
import { cn } from "@/lib/utils";

function parserCandidateKey(candidate: ProfferParserCandidate) {
  return [candidate.handler_id, candidate.handler_version, candidate.execution_path, candidate.compatibility_ref].join("\u0000");
}

export function ParserSelectionPanel({
  inspection,
  preview,
  selectedCandidateKey,
  handlerDecisionRef,
  submitting,
  onSelect,
  onRecordDecision,
}: {
  inspection: ProfferSourceInspection | null;
  preview: ProfferPreviewResponse | null;
  selectedCandidateKey: string;
  handlerDecisionRef: string | null;
  submitting: boolean;
  onSelect: (candidate: ProfferParserCandidate) => void;
  onRecordDecision: () => void;
}) {
  const hasRecommendation = Boolean(
    preview?.handler_recommendation_ref &&
    preview.detected_format &&
    preview.detected_format_ref &&
    preview.signature_ref &&
    preview.recommended_handler,
  ) && (preview?.alternative_handlers?.length ?? 0) <= 3;
  const recommendationReady = preview?.phase === "awaiting_handler_selection" && hasRecommendation;
  const candidates = hasRecommendation && preview?.recommended_handler
    ? [preview.recommended_handler, ...(preview.alternative_handlers ?? [])]
    : [];
  const selected = candidates.find((candidate) => parserCandidateKey(candidate) === selectedCandidateKey) ?? null;
  const selectionReceipt = preview?.receipts?.find((receipt) => receipt.receipt_type === "parser_selection") ?? null;

  return (
    <section aria-label="Parser selection">
      <div className="mb-3 flex flex-wrap items-baseline justify-between gap-2">
        <p className="platform-rule-title">Parser decision</p>
        <span className="text-xs text-muted-foreground">Runtime content/signature route only</span>
      </div>

      {preview && preview.phase !== "awaiting_handler_selection" ? (
        <DurableReadBack preview={preview} receipt={selectionReceipt} selected={selected} localDecisionRef={handlerDecisionRef} />
      ) : !preview ? (
        <div className="border bg-background p-5">
          <strong className="block text-sm">Parser selection occurs after intake starts</strong>
          <p className="mt-2 text-xs leading-5 text-muted-foreground">
            Source inspection can show a filename preflight, but it is not authoritative. The workflow must read the content, persist its signature recommendation, and pause before this screen can offer registered handlers.
          </p>
          {inspection?.parser_preflight && (
            <dl className="mt-4 grid gap-3 border bg-accent/20 p-4 text-xs sm:grid-cols-2">
              <div><dt className="text-muted-foreground">Filename preflight</dt><dd className="mt-1 font-mono text-[11px]">{inspection.parser_preflight.declared_format}</dd></div>
              <div><dt className="text-muted-foreground">Authority</dt><dd className="mt-1 font-semibold">Diagnostic only</dd></div>
            </dl>
          )}
        </div>
      ) : !recommendationReady ? (
        <div className="border border-destructive/50 bg-destructive/5 p-5 text-destructive" role="alert">
          <div className="flex gap-3">
            <AlertTriangle className="mt-0.5 h-5 w-5 shrink-0" />
            <div>
              <strong className="block text-sm">Runtime parser recommendation is incomplete</strong>
              <p className="mt-1 text-xs leading-5">The workflow is paused for handler selection, but its snapshot did not include the durable recommendation, detected-format reference, content signature, and recommended registered handler. No choice can be submitted.</p>
            </div>
          </div>
        </div>
      ) : (
        <div className="space-y-4">
          <div className="border bg-accent/30 p-4 text-xs">
            <strong className="block text-sm">Detected format: {preview.detected_format}</strong>
            <dl className="mt-3 grid gap-2 sm:grid-cols-3">
              <div><dt className="text-muted-foreground">Format reference</dt><dd className="mt-1 break-all font-mono text-[10px]">{preview.detected_format_ref}</dd></div>
              <div><dt className="text-muted-foreground">Signature</dt><dd className="mt-1 break-all font-mono text-[10px]">{preview.signature_ref}</dd></div>
              <div><dt className="text-muted-foreground">Recommendation</dt><dd className="mt-1 break-all font-mono text-[10px]">{preview.handler_recommendation_ref}</dd></div>
            </dl>
            <p className="mt-3 text-muted-foreground">The recommended handler and bounded alternatives come from the workflow’s persisted content/signature match.</p>
          </div>

          <fieldset className="space-y-2">
            <legend className="text-xs font-semibold">Choose one compatible registered handler</legend>
            {candidates.map((candidate, index) => {
              const checked = parserCandidateKey(candidate) === selectedCandidateKey;
              return (
                <label key={parserCandidateKey(candidate)} className={cn("grid cursor-pointer grid-cols-[auto_1fr] gap-3 border p-4", checked && "border-primary bg-accent/40 ring-1 ring-primary")}>
                  <input type="radio" name="parser-handler" checked={checked} onChange={() => onSelect(candidate)} className="mt-1" />
                  <span>
                    <span className="flex flex-wrap items-center gap-2">
                      <strong className="text-sm">{candidate.handler_id}</strong>
                      {candidate.execution_path === "duckdb" && <span className="inline-flex items-center gap-1 border bg-card px-2 py-0.5 text-[10px] font-semibold"><Database className="h-3 w-3" /> DuckDB</span>}
                      {index === 0 && <span className="border border-[#2f9d67] bg-[#e2f3e9] px-2 py-0.5 text-[10px] font-semibold text-[#17794b]">Recommended</span>}
                    </span>
                    <span className="mt-1 block font-mono text-[10px] text-muted-foreground">Version {candidate.handler_version} · {candidate.execution_path}</span>
                    <span className="mt-2 block text-xs leading-5 text-muted-foreground">{candidate.reason}</span>
                    <span className="mt-2 block break-all font-mono text-[10px] text-muted-foreground">Compatibility {candidate.compatibility_ref}</span>
                  </span>
                </label>
              );
            })}
          </fieldset>

          <div className="flex flex-wrap items-center justify-between gap-3 border-l-4 border-l-primary bg-accent/40 p-4">
            <div>
              <strong className="block text-sm">Explicit selection required</strong>
              <p className="mt-1 text-xs text-muted-foreground">{selected ? `${selected.handler_id} will be recorded against this exact runtime recommendation.` : "Choose a handler before recording the durable actor-bound decision."}</p>
            </div>
            <Button type="button" onClick={onRecordDecision} disabled={!selected || submitting}>
              <ShieldCheck className="h-4 w-4" /> {submitting ? "Recording decision" : "Record selection and continue"}
            </Button>
          </div>
          <div className="border bg-card p-4 text-xs">
            <strong className="block">Durable decision gate</strong>
            <p className="mt-1 text-muted-foreground">The workflow is paused. The selected exact candidate becomes durable only after the authenticated server records the decision and returns its reference.</p>
            {(preview.handler_decision_ref || handlerDecisionRef) && <p className="mt-2 break-all font-mono text-[10px]">Decision {preview.handler_decision_ref ?? handlerDecisionRef}</p>}
          </div>
        </div>
      )}
    </section>
  );
}

function DurableReadBack({ preview, receipt, selected, localDecisionRef }: { preview: ProfferPreviewResponse; receipt: ProfferPreviewReceipt | null; selected: ProfferParserCandidate | null; localDecisionRef: string | null }) {
  const matchesChoice = Boolean(preview.parser && selected && preview.parser.parser_id === selected.handler_id && preview.parser.parser_version === selected.handler_version);
  return (
    <div className="border bg-accent/30 p-5">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <strong className="capitalize">{preview.phase.replaceAll("_", " ")}</strong>
        <span className="border bg-card px-2 py-1 text-[10px] font-semibold text-muted-foreground">Durable workflow read-back</span>
      </div>
      <dl className="mt-5 grid gap-4 text-xs sm:grid-cols-2">
        <div><dt className="text-muted-foreground">Selected handler</dt><dd className="mt-1 break-all font-mono text-[11px]">{preview.parser ? `${preview.parser.parser_id} · ${preview.parser.parser_version}` : "Selection has not been recorded yet"}</dd></div>
        <div><dt className="text-muted-foreground">Handler decision</dt><dd className="mt-1 break-all font-mono text-[11px]">{preview.handler_decision_ref ?? localDecisionRef ?? "Pending"}</dd></div>
        <div><dt className="text-muted-foreground">Parser-selection receipt</dt><dd className="mt-1 break-all font-mono text-[11px]">{receipt?.receipt_ref ?? "Pending"}</dd></div>
        {preview.parser && <div><dt className="text-muted-foreground">Parser config digest</dt><dd className="mt-1 break-all font-mono text-[11px]">{preview.parser.config_digest}</dd></div>}
        {selected && preview.parser && <div className="sm:col-span-2"><dt className="text-muted-foreground">Recorded choice correlation</dt><dd className={cn("mt-1 font-semibold", matchesChoice ? "text-[#17794b]" : "text-destructive")}>{matchesChoice ? "Matches selected runtime candidate" : "Server parser read-back differs from the selected runtime candidate"}</dd></div>}
        {preview.reason && <div className="sm:col-span-2"><dt className="text-muted-foreground">Runtime reason</dt><dd className="mt-1">{preview.reason}</dd></div>}
      </dl>
    </div>
  );
}
