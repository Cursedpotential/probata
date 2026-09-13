// Byline: Codex · GPT-5 · 2026-08-15 (read-only court-export gate inspection)
"use client";

import { useRef, useState } from "react";
import { AlertTriangle, CheckCircle2, CircleX, Loader2, RefreshCw, ShieldCheck } from "lucide-react";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { getCourtReadiness } from "@/lib/api-client";
import { useFixedCase } from "@/lib/fixed-case-context";
import type { CourtReadiness, CourtReadinessBlocker, EvidenceItem } from "@/lib/shared/types";

const BLOCKER_LABELS: Record<CourtReadinessBlocker, string> = {
  CONTENT_REVIEW_REQUIRED: "Approved content review is required",
  PROVENANCE_INVALID: "Exact canonical provenance is not established",
  CUSTODY_NOT_VERIFIED: "H1 custody or source review is not verified",
  CUSTODY_CHAIN_INVALID: "Custody event-chain validation failed",
  AUTHENTICATION_REQUIRED: "Source authentication is required",
  CONFIDENCE_NOT_EXPORTABLE: "Confidence tier is outside the export band",
  HYPOTHESIS_NOT_EXPORTABLE: "Hypothesis material is excluded from court export",
  REDACTION_REQUIRED: "Required redaction has not been completed",
  SENSITIVITY_SEALED: "Sealed sensitivity prevents export",
  NOT_RELEASED: "The database court-export view has not released this item",
};

function errorText(error: unknown) {
  return error instanceof Error ? error.message : "Court-export readiness could not be loaded";
}

function GateRow({ label, passed, detail }: { label: string; passed: boolean; detail: string }) {
  const Icon = passed ? CheckCircle2 : CircleX;
  return (
    <li className="flex gap-3 rounded-md border p-3">
      <Icon
        className={passed ? "mt-0.5 h-4 w-4 shrink-0 text-emerald-600" : "mt-0.5 h-4 w-4 shrink-0 text-destructive"}
        aria-hidden="true"
      />
      <div className="min-w-0">
        <p className="text-sm font-medium">{label}: {passed ? "Pass" : "Blocked"}</p>
        <p className="break-words text-xs text-muted-foreground">{detail}</p>
      </div>
    </li>
  );
}

function ReadinessContent({ readiness }: { readiness: CourtReadiness }) {
  const { gates } = readiness;
  const redactionClear = gates.redaction.clear_for_export;
  const sensitivityExportable = !gates.sensitivity.sealed;
  const custodyValid = gates.custody.h1_valid
    && gates.custody.event_chain_valid
    && gates.custody.verified_event_present
    && gates.custody.source_status.toLowerCase() === "verified"
    && gates.custody.source_reviewed
    && Boolean(gates.custody.verified_by)
    && Boolean(gates.custody.verified_at);
  const contentReviewValid = gates.content_review.approved && Boolean(gates.content_review.decision_id);
  const authenticationValid = gates.authentication.authenticated && Boolean(gates.authentication.method);

  return (
    <div className="space-y-4">
      <div className="rounded-md border border-amber-500/60 bg-amber-500/5 p-3 text-sm">
        <div className="flex flex-wrap items-center gap-2">
          <AlertTriangle className="h-4 w-4 text-amber-600" aria-hidden="true" />
          <Badge variant={gates.court_export.view_member ? "outline" : "destructive"}>
            {gates.court_export.view_member ? "In database export view" : "Not in database export view"}
          </Badge>
          <Badge variant={readiness.readiness_passed ? "outline" : "destructive"}>
            {readiness.readiness_passed ? "Supplemental readiness checks pass" : "Supplemental readiness checks blocked"}
          </Badge>
        </div>
        <p className="mt-2 text-muted-foreground">
          This is database gate status only. It does not determine admissibility, satisfy court rules, or provide legal advice.
        </p>
      </div>

      <section aria-labelledby={`readiness-checklist-${readiness.evidence_item_id}`}>
        <h3 id={`readiness-checklist-${readiness.evidence_item_id}`} className="mb-2 font-semibold">Court-export readiness checklist</h3>
        <ul className="grid gap-2 sm:grid-cols-2">
          <GateRow label="Content review" passed={contentReviewValid} detail={gates.content_review.decision_id ? `Decision ${gates.content_review.decision_id}` : "No approved decision"} />
          <GateRow label="Exact provenance" passed={gates.provenance.exact} detail={gates.provenance.exact ? "Canonical record pointer agrees" : "Canonical pointer validation failed"} />
          <GateRow label="Custody" passed={custodyValid} detail={`H1 ${gates.custody.h1_valid ? "valid" : "invalid"}; chain ${gates.custody.event_chain_valid ? "valid" : "invalid"}; verified event ${gates.custody.verified_event_present ? "present" : "missing"}; source ${gates.custody.source_status}`} />
          <GateRow label="Authentication" passed={authenticationValid} detail={gates.authentication.method || "No authentication method recorded"} />
          <GateRow label="Confidence" passed={gates.confidence.export_band} detail={`${gates.confidence.tier} tier${gates.confidence.value === null || gates.confidence.value === undefined ? "" : ` · ${gates.confidence.value}`}`} />
          <GateRow label="Assertion status" passed={gates.assertion.not_hypothesis} detail={gates.assertion.not_hypothesis ? "Item is not marked as a hypothesis" : "Item is marked as a hypothesis"} />
          <GateRow label="Redaction" passed={redactionClear} detail={`${gates.redaction.status} · item ${gates.redaction.privacy_sensitivity} · source ${gates.redaction.source_privacy_sensitivity}`} />
          <GateRow label="Sensitivity" passed={sensitivityExportable} detail={`evidence ${gates.sensitivity.evidence_tier} · source ${gates.sensitivity.source_tier}`} />
          <GateRow label="Court-export view" passed={gates.court_export.view_member} detail={gates.court_export.view_member ? "Item is a current view member" : "Item is not a current view member"} />
        </ul>
      </section>

      {readiness.blockers.length > 0 && (
        <section aria-labelledby={`readiness-blockers-${readiness.evidence_item_id}`} className="rounded-md border border-destructive/60 p-3">
          <h3 id={`readiness-blockers-${readiness.evidence_item_id}`} className="font-semibold text-destructive">Database blockers</h3>
          <ul className="mt-2 list-disc space-y-1 pl-5 text-sm">
            {readiness.blockers.map((blocker) => <li key={blocker}>{BLOCKER_LABELS[blocker]} <span className="font-mono text-xs text-muted-foreground">({blocker})</span></li>)}
          </ul>
        </section>
      )}
    </div>
  );
}

export function CourtReadinessDialog({ item }: { item: EvidenceItem }) {
  const { mode } = useFixedCase();
  const [open, setOpen] = useState(false);
  const [loading, setLoading] = useState(false);
  const [readiness, setReadiness] = useState<CourtReadiness | null>(null);
  const [error, setError] = useState<string | null>(null);
  const requestRef = useRef(0);

  async function loadReadiness() {
    const request = ++requestRef.current;
    setLoading(true);
    setReadiness(null);
    setError(null);
    try {
      const result = await getCourtReadiness(item.matter_id, item.id, mode);
      if (request !== requestRef.current) return;
      if (result.matter_id !== item.matter_id || result.evidence_item_id !== item.id) {
        throw new Error("Readiness returned a different Matter evidence item");
      }
      setReadiness(result);
    } catch (requestError) {
      if (request !== requestRef.current) return;
      setReadiness(null);
      setError(errorText(requestError));
    } finally {
      if (request === requestRef.current) setLoading(false);
    }
  }

  function changeOpen(next: boolean) {
    setOpen(next);
    if (next) void loadReadiness();
    else {
      requestRef.current += 1;
      setReadiness(null);
      setError(null);
      setLoading(false);
    }
  }

  return (
    <>
      <Button type="button" size="sm" variant="outline" onClick={() => changeOpen(true)}>
        <ShieldCheck aria-hidden="true" /> Court readiness
      </Button>
      <Dialog open={open} onOpenChange={changeOpen}>
        <DialogContent className="max-h-[90vh] max-w-4xl overflow-y-auto" aria-busy={loading}>
          <DialogHeader>
            <DialogTitle>Court-export readiness</DialogTitle>
            <DialogDescription>Read-only database gates for this exact Matter evidence item.</DialogDescription>
          </DialogHeader>
          {loading ? (
            <p className="flex items-center gap-2 py-8 text-sm text-muted-foreground" role="status">
              <Loader2 className="h-4 w-4 animate-spin" aria-hidden="true" /> Loading database gate status
            </p>
          ) : error ? (
            <div role="alert" className="space-y-3 rounded-md border border-destructive p-3 text-sm text-destructive">
              <p>{error}</p>
              <Button type="button" size="sm" variant="outline" onClick={() => void loadReadiness()}>
                <RefreshCw aria-hidden="true" /> Retry readiness check
              </Button>
            </div>
          ) : readiness ? <ReadinessContent readiness={readiness} /> : null}
        </DialogContent>
      </Dialog>
    </>
  );
}
