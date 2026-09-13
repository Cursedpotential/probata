// Byline: Codex · GPT-5 · 2026-08-15 (reviewer-of-record evidence gate)
"use client";

import { useRef, useState } from "react";
import { AlertTriangle, ClipboardCheck, History, Loader2, RefreshCw } from "lucide-react";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { listEvidenceReviews, reviewEvidenceItem } from "@/lib/api-client";
import { useFixedCase } from "@/lib/fixed-case-context";
import type {
  EvidenceDetail,
  EvidenceItem,
  EvidenceReviewDecision,
  EvidenceReviewRecord,
  EvidenceReviewResult,
} from "@/lib/shared/types";
import {
  EvidenceDetailContent,
  loadValidatedEvidenceDetail,
} from "./evidence-detail-dialog";

interface EvidenceReviewDialogProps {
  item: EvidenceItem;
  onReviewed: (result: EvidenceReviewResult) => void;
}

const DECISIONS: Array<{ value: EvidenceReviewDecision; label: string }> = [
  { value: "approved", label: "Approve record-level draft" },
  { value: "rejected", label: "Reject draft" },
  { value: "needs_changes", label: "Needs changes" },
  { value: "needs_context", label: "Needs more context" },
  { value: "hold", label: "Place on hold" },
  { value: "escalated", label: "Escalate review" },
];

function errorMessage(error: unknown) {
  return error instanceof Error ? error.message : "The review decision could not be recorded";
}

export function EvidenceReviewDialog({ item, onReviewed }: EvidenceReviewDialogProps) {
  const { mode } = useFixedCase();
  const [open, setOpen] = useState(false);
  const [saving, setSaving] = useState(false);
  const [decision, setDecision] = useState<EvidenceReviewDecision>("needs_context");
  const [rationale, setRationale] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [detail, setDetail] = useState<EvidenceDetail | null>(null);
  const [detailLoading, setDetailLoading] = useState(false);
  const [detailError, setDetailError] = useState<string | null>(null);
  const submittingRef = useRef(false);
  const detailRequestRef = useRef(0);

  function reset() {
    setDecision("needs_context");
    setRationale("");
    setError(null);
    detailRequestRef.current += 1;
    setDetail(null);
    setDetailLoading(false);
    setDetailError(null);
  }

  async function loadDetail() {
    const request = ++detailRequestRef.current;
    setDetailLoading(true);
    setDetail(null);
    setDetailError(null);
    try {
      const result = await loadValidatedEvidenceDetail(item, mode);
      if (request !== detailRequestRef.current) return;
      if (result.item.safe_for_legal_use || result.item.is_authenticated) {
        throw new Error("This review gate only accepts unauthenticated, legally unsafe evidence");
      }
      setDetail(result);
    } catch (requestError) {
      if (request !== detailRequestRef.current) return;
      setDetail(null);
      setDetailError(errorMessage(requestError));
    } finally {
      if (request === detailRequestRef.current) setDetailLoading(false);
    }
  }

  function changeOpen(next: boolean) {
    setOpen(next);
    if (next) {
      reset();
      void loadDetail();
    } else {
      reset();
    }
  }

  async function submit() {
    if (submittingRef.current || !detail || !rationale.trim()) return;
    submittingRef.current = true;
    setSaving(true);
    setError(null);
    try {
      const result = await reviewEvidenceItem(item.matter_id, item.id, {
        decision,
        rationale: rationale.trim(),
      }, mode);
      if (result.item.safe_for_legal_use || result.item.is_authenticated) {
        throw new Error("Review unexpectedly granted authentication or legal safety");
      }
      onReviewed(result);
      setOpen(false);
      reset();
    } catch (requestError) {
      setError(errorMessage(requestError));
    } finally {
      submittingRef.current = false;
      setSaving(false);
    }
  }

  return (
    <>
      <Button type="button" size="sm" variant="outline" onClick={() => changeOpen(true)}>
        <ClipboardCheck aria-hidden="true" /> Review draft
      </Button>
      <Dialog open={open} onOpenChange={changeOpen}>
        <DialogContent className="max-h-[90vh] max-w-4xl overflow-y-auto" aria-busy={saving || detailLoading}>
          <DialogHeader>
            <DialogTitle>Record reviewer decision</DialogTitle>
            <DialogDescription>
              This records an append-only human decision for the exact promoted record. Approval does not authenticate the source or make it safe for legal use.
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-4">
            {detailLoading ? (
              <p className="flex items-center gap-2 py-8 text-sm text-muted-foreground" role="status">
                <Loader2 className="h-4 w-4 animate-spin" aria-hidden="true" /> Loading exact evidence provenance before review
              </p>
            ) : detailError ? (
              <div role="alert" className="space-y-3 rounded-md border border-destructive p-3 text-sm text-destructive">
                <p>Review is locked: {detailError}</p>
                <Button type="button" size="sm" variant="outline" onClick={() => void loadDetail()}>
                  <RefreshCw aria-hidden="true" /> Retry provenance inspection
                </Button>
              </div>
            ) : detail ? (
              <EvidenceDetailContent detail={detail} />
            ) : null}
            {error && <p role="alert" className="rounded-md border border-destructive p-3 text-sm text-destructive">{error}</p>}
            <div className="flex flex-wrap gap-2">
              <Badge variant="outline">{item.review_status}</Badge>
              <Badge variant="destructive">Unsafe for legal use</Badge>
              <Badge variant="outline">Unauthenticated</Badge>
            </div>
            <div className="space-y-1">
              <Label htmlFor={`review-decision-${item.id}`}>Decision</Label>
              <select
                id={`review-decision-${item.id}`}
                className="h-9 w-full rounded-md border border-input bg-transparent px-3 text-sm"
                value={decision}
                disabled={saving || detailLoading || !detail}
                onChange={(event) => setDecision(event.target.value as EvidenceReviewDecision)}
              >
                {DECISIONS.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}
              </select>
            </div>
            <div className="space-y-1">
              <Label htmlFor={`review-rationale-${item.id}`}>Reviewer rationale</Label>
              <Textarea
                id={`review-rationale-${item.id}`}
                maxLength={20000}
                value={rationale}
                disabled={saving || detailLoading || !detail}
                onChange={(event) => setRationale(event.target.value)}
                placeholder="State what was reviewed and why this decision is appropriate."
              />
            </div>
            <div className="flex gap-2 rounded-md border border-amber-500 bg-amber-500/5 p-3 text-sm">
              <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0 text-amber-600" aria-hidden="true" />
              <p>Even an approved review remains unauthenticated and unsafe for legal use until a separate authentication gate is completed.</p>
            </div>
          </div>
          <DialogFooter>
            <Button type="button" variant="outline" onClick={() => changeOpen(false)}>Cancel</Button>
            <Button type="button" disabled={saving || detailLoading || !detail || !rationale.trim()} onClick={() => void submit()}>
              {saving && <Loader2 className="animate-spin" aria-hidden="true" />} Record decision
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}

interface EvidenceReviewHistoryDialogProps {
  item: EvidenceItem;
}

export function EvidenceReviewHistoryDialog({ item }: EvidenceReviewHistoryDialogProps) {
  const { mode } = useFixedCase();
  const [open, setOpen] = useState(false);
  const [loading, setLoading] = useState(false);
  const [history, setHistory] = useState<EvidenceReviewRecord[]>([]);
  const [error, setError] = useState<string | null>(null);
  const requestRef = useRef(0);

  async function loadHistory() {
    const request = ++requestRef.current;
    setLoading(true);
    setHistory([]);
    setError(null);
    try {
      const response = await listEvidenceReviews(item.matter_id, item.id, mode);
      if (request !== requestRef.current) return;
      setHistory(response.data);
    } catch (requestError) {
      if (request !== requestRef.current) return;
      setHistory([]);
      setError(errorMessage(requestError));
    } finally {
      if (request === requestRef.current) setLoading(false);
    }
  }

  function changeOpen(next: boolean) {
    setOpen(next);
    if (next) {
      void loadHistory();
    } else {
      requestRef.current += 1;
      setHistory([]);
      setError(null);
    }
  }

  return (
    <>
      <Button type="button" size="sm" variant="ghost" onClick={() => changeOpen(true)}>
        <History aria-hidden="true" /> Review history
      </Button>
      <Dialog open={open} onOpenChange={changeOpen}>
        <DialogContent aria-busy={loading}>
          <DialogHeader>
            <DialogTitle>Review history</DialogTitle>
            <DialogDescription>
              Append-only reviewer decisions for this exact evidence item. These decisions do not authenticate the source or grant legal safety.
            </DialogDescription>
          </DialogHeader>
          {loading ? (
            <div className="flex items-center gap-2 py-6 text-sm text-muted-foreground" role="status">
              <Loader2 className="animate-spin" aria-hidden="true" /> Loading review history
            </div>
          ) : error ? (
            <p role="alert" className="rounded-md border border-destructive p-3 text-sm text-destructive">{error}</p>
          ) : history.length === 0 ? (
            <p className="py-6 text-sm text-muted-foreground">No reviewer decision has been recorded.</p>
          ) : (
            <ol className="max-h-[60vh] space-y-3 overflow-y-auto">
              {history.map((record) => (
                <li key={record.decision_id} className="rounded-md border p-3">
                  <div className="flex flex-wrap items-center gap-2">
                    <Badge variant="outline">{record.decision.replaceAll("_", " ")}</Badge>
                    <Badge variant="outline">{record.court_readiness.replaceAll("_", " ")}</Badge>
                    <span className="text-xs text-muted-foreground">
                      {new Date(record.decided_at).toLocaleString()}
                    </span>
                  </div>
                  <p className="mt-2 text-sm">{record.rationale}</p>
                  <p className="mt-2 text-xs text-muted-foreground">Reviewer: {record.reviewer}</p>
                </li>
              ))}
            </ol>
          )}
        </DialogContent>
      </Dialog>
    </>
  );
}
