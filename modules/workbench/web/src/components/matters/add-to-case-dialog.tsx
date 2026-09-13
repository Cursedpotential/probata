// Byline: Codex · GPT-5 · 2026-08-15 (custody-safe Knowledge-to-Evidence flow)
"use client";

import { useRef, useState } from "react";
import { AlertTriangle, Loader2, SearchCheck } from "lucide-react";

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
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import {
  createEvidenceItem,
  getCaseManagementCapabilities,
  getMatter,
  listMatters,
  resolveKnowledgeSource,
} from "@/lib/api-client";
import { useFixedCase } from "@/lib/fixed-case-context";
import type {
  EvidencePromotionResult,
  KnowledgeSourceRef,
  Matter,
  MatterDetail,
  SourceCandidate,
} from "@/lib/shared/types";

interface AddToCaseDialogProps {
  source: KnowledgeSourceRef;
  defaultTitle: string;
  boundMatter?: MatterDetail;
  defaultCourtCaseId?: string;
  onPromoted?: (result: EvidencePromotionResult) => void;
}

function message(error: unknown) {
  return error instanceof Error ? error.message : "The source could not be resolved";
}

export function AddToCaseDialog({
  source,
  defaultTitle,
  boundMatter,
  defaultCourtCaseId,
  onPromoted,
}: AddToCaseDialogProps) {
  const { mode } = useFixedCase();
  const [open, setOpen] = useState(false);
  const [loading, setLoading] = useState(false);
  const [matters, setMatters] = useState<Matter[]>([]);
  const [selectedMatterId, setSelectedMatterId] = useState("");
  const [matter, setMatter] = useState<MatterDetail | null>(null);
  const [candidates, setCandidates] = useState<SourceCandidate[]>([]);
  const [selectedRecordId, setSelectedRecordId] = useState("");
  const [courtCaseId, setCourtCaseId] = useState("");
  const [title, setTitle] = useState(defaultTitle.slice(0, 500));
  const [description, setDescription] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [result, setResult] = useState<EvidencePromotionResult | null>(null);
  const operationRef = useRef(0);
  const promotingRef = useRef(false);

  function reset() {
    operationRef.current += 1;
    promotingRef.current = false;
    setMatters([]);
    setSelectedMatterId("");
    setMatter(null);
    setCandidates([]);
    setSelectedRecordId("");
    setCourtCaseId("");
    setTitle(defaultTitle.slice(0, 500));
    setDescription("");
    setError(null);
    setResult(null);
  }

  async function openFlow() {
    reset();
    const operation = operationRef.current;
    setOpen(true);
    setLoading(true);
    try {
      const capabilities = await getCaseManagementCapabilities();
      if (operation !== operationRef.current) return;
      if (!capabilities.advanced_evidence_available) {
        setError(capabilities.advanced_evidence_reason);
        setLoading(false);
        return;
      }
    } catch (requestError) {
      if (operation !== operationRef.current) return;
      setError(message(requestError));
      setLoading(false);
      return;
    }
    if (boundMatter) {
      setSelectedMatterId(boundMatter.id);
      setMatter(boundMatter);
      setCourtCaseId(defaultCourtCaseId || "");
      try {
        const resolution = await resolveKnowledgeSource(boundMatter.id, source, mode);
        if (operation !== operationRef.current) return;
        setCandidates(resolution.candidates);
        if (resolution.candidates.length === 0) {
          setError("No canonical normalized record with matching custody metadata was found. This hit is not promotable.");
        } else if (!defaultCourtCaseId) {
          setError("This Matter has no primary court proceeding. Source resolution is visible, but promotion is disabled.");
        }
      } catch (requestError) {
        if (operation !== operationRef.current) return;
        setError(message(requestError));
      } finally {
        if (operation === operationRef.current) setLoading(false);
      }
      return;
    }
    try {
      const response = await listMatters(50, 0, mode);
      if (operation !== operationRef.current) return;
      setMatters(response.data.filter((item) => item.status === "active"));
      if (response.data.length === 0) setError("No active Matter is available.");
    } catch (requestError) {
      if (operation !== operationRef.current) return;
      setError(message(requestError));
    } finally {
      if (operation === operationRef.current) setLoading(false);
    }
  }

  async function resolveSource() {
    if (!selectedMatterId) return;
    const requestedMatterId = selectedMatterId;
    const operation = ++operationRef.current;
    setLoading(true);
    setCandidates([]);
    setSelectedRecordId("");
    setMatter(null);
    setError(null);
    try {
      const [detail, resolution] = await Promise.all([
        getMatter(requestedMatterId, mode),
        resolveKnowledgeSource(requestedMatterId, source, mode),
      ]);
      if (operation !== operationRef.current) return;
      setMatter(detail);
      setCandidates(resolution.candidates);
      const primaryCase = detail.court_cases.find((item) => item.is_primary);
      setCourtCaseId(primaryCase?.id || detail.court_cases[0]?.id || "");
      if (resolution.candidates.length === 0) {
        setError("No canonical normalized record with matching custody metadata was found. This hit is not promotable.");
      }
    } catch (requestError) {
      if (operation !== operationRef.current) return;
      setError(message(requestError));
    } finally {
      if (operation === operationRef.current) setLoading(false);
    }
  }

  async function promoteSelected() {
    if (promotingRef.current) return;
    const candidate = candidates.find((item) => item.normalized_record_id === selectedRecordId);
    if (!candidate || !courtCaseId || !selectedMatterId || !title.trim()) return;
    promotingRef.current = true;
    const operation = ++operationRef.current;
    setLoading(true);
    setError(null);
    try {
      const exactQuote = candidate.content.slice(0, 50_000);
      const promotion = await createEvidenceItem(selectedMatterId, {
        court_case_id: courtCaseId,
        source: {
          ...source,
          normalized_record_id: candidate.normalized_record_id,
          quote: exactQuote,
        },
        title: title.trim(),
        description: description.trim() || undefined,
        quote: exactQuote,
        evidence_type: "communication",
      }, mode);
      if (operation !== operationRef.current) return;
      if (
        promotion.created &&
        (promotion.item.review_status !== "unreviewed" ||
          !promotion.item.hitl_required ||
          promotion.item.safe_for_legal_use ||
          promotion.item.is_authenticated)
      ) {
        throw new Error("The spine did not return the required unsafe human-review draft state");
      }
      setResult(promotion);
      onPromoted?.(promotion);
    } catch (requestError) {
      if (operation !== operationRef.current) return;
      setError(message(requestError));
    } finally {
      promotingRef.current = false;
      if (operation === operationRef.current) setLoading(false);
    }
  }

  return (
    <>
      <Button type="button" variant="outline" size="sm" onClick={() => void openFlow()}>
        {boundMatter ? "Add to Matter" : "Add to case"}
      </Button>
      <Dialog
        open={open}
        onOpenChange={(next) => {
          setOpen(next);
          if (!next) reset();
        }}
      >
        <DialogContent className="max-h-[90vh] max-w-3xl overflow-y-auto" aria-busy={loading}>
          <DialogHeader>
            <DialogTitle>{boundMatter ? `Add Knowledge to ${boundMatter.title}` : "Add Knowledge to a Matter"}</DialogTitle>
            <DialogDescription>
              {boundMatter
                ? "The Matter and primary court proceeding are fixed from this workspace. Choose one exact canonical record; retrieval text alone cannot become evidence."
                : "Select a Matter, resolve this retrieval hit to an exact canonical record, then choose that record explicitly. Retrieval text alone cannot become evidence."}
            </DialogDescription>
          </DialogHeader>

          {loading && <p className="flex items-center text-sm" role="status"><Loader2 className="mr-2 h-4 w-4 animate-spin" aria-hidden="true" />Checking canonical provenance…</p>}
          {error && <div role="alert" className="rounded-md border border-destructive bg-destructive/5 p-3 text-sm text-destructive">{error}</div>}

          {result ? (
            <div className="space-y-3 rounded-lg border border-amber-500 bg-amber-500/5 p-4" role="status" aria-live="polite">
              <div className="flex flex-wrap items-center gap-2">
                <AlertTriangle className="h-5 w-5 text-amber-600" aria-hidden="true" />
                <span className="font-semibold">Evidence {result.created ? "draft created" : "already existed"}</span>
                <Badge variant="outline">{result.item.review_status}</Badge>
                {result.item.hitl_required && <Badge variant="outline">HITL required</Badge>}
                {!result.item.safe_for_legal_use && <Badge variant="destructive">Unsafe for legal use</Badge>}
                <Badge variant="outline">{result.item.is_authenticated ? "Authenticated" : "Unauthenticated"}</Badge>
              </div>
              <p className="text-sm">
                {result.created
                  ? "This is an unauthenticated, legally unsafe draft. Human content review is required, and separate authentication/legal-release gates still remain."
                  : "This canonical source was promoted previously. Its current review and safety state is shown above; retrying did not create a duplicate."}
              </p>
              <p className="font-mono text-xs text-muted-foreground">Evidence {result.item.id}</p>
            </div>
          ) : (
            <div className="space-y-5">
              {boundMatter ? (
                <div className="rounded-md border bg-muted/40 p-3 text-sm">
                  <span className="font-medium">Fixed scope:</span> {boundMatter.title}
                  <span className="mx-2 text-muted-foreground" aria-hidden="true">/</span>
                  {boundMatter.court_cases.find((item) => item.id === defaultCourtCaseId)?.caption || "No primary court proceeding"}
                  <div className="mt-1 font-mono text-xs text-muted-foreground">Partition {source.partition_key}</div>
                </div>
              ) : (
                <div className="grid gap-3 sm:grid-cols-[1fr_auto] sm:items-end">
                <div className="space-y-1">
                  <Label htmlFor="promotion-matter">Matter</Label>
                  <select
                    id="promotion-matter"
                    className="h-9 w-full rounded-md border border-input bg-transparent px-3 text-sm"
                    value={selectedMatterId}
                    disabled={loading}
                    onChange={(event) => {
                      setSelectedMatterId(event.target.value);
                      setMatter(null);
                      setCandidates([]);
                      setSelectedRecordId("");
                      setCourtCaseId("");
                    }}
                  >
                    <option value="">Select a Matter</option>
                    {matters.map((item) => <option key={item.id} value={item.id}>{item.title}</option>)}
                  </select>
                </div>
                <Button type="button" disabled={loading || !selectedMatterId} onClick={() => void resolveSource()}>
                  <SearchCheck aria-hidden="true" /> Resolve exact source
                </Button>
                </div>
              )}

              {candidates.length > 0 && (
                <fieldset className="space-y-2">
                  <legend className="text-sm font-medium">Choose one exact normalized record</legend>
                  {candidates.map((candidate) => (
                    <label key={candidate.normalized_record_id} className="flex cursor-pointer gap-3 rounded-lg border p-3 has-[:checked]:border-primary">
                      <input
                        type="radio"
                        name="normalized-record"
                        value={candidate.normalized_record_id}
                        checked={selectedRecordId === candidate.normalized_record_id}
                        onChange={(event) => setSelectedRecordId(event.target.value)}
                        className="mt-1"
                      />
                      <span className="min-w-0 space-y-1">
                        <span className="flex flex-wrap gap-2 text-xs">
                          <Badge variant="outline">{candidate.record_type}</Badge>
                          <Badge variant="outline">{candidate.disclosure_tier}</Badge>
                          <Badge variant="outline">{candidate.review_status}</Badge>
                        </span>
                        <span className="block whitespace-pre-wrap text-sm">{candidate.content}</span>
                        <span className="block break-all font-mono text-xs text-muted-foreground">Record {candidate.normalized_record_id}</span>
                      </span>
                    </label>
                  ))}
                </fieldset>
              )}

              {selectedRecordId && matter && (
                <div className="grid gap-3">
                  {boundMatter ? (
                    <div className="space-y-1">
                      <Label>Court proceeding</Label>
                      <div className="rounded-md border bg-muted/40 px-3 py-2 text-sm">
                        {matter.court_cases.find((item) => item.id === courtCaseId)?.caption || "No primary court proceeding"}
                      </div>
                    </div>
                  ) : (
                    <div className="space-y-1">
                      <Label htmlFor="promotion-court-case">Court proceeding</Label>
                      <select
                        id="promotion-court-case"
                        className="h-9 w-full rounded-md border border-input bg-transparent px-3 text-sm"
                        value={courtCaseId}
                        onChange={(event) => setCourtCaseId(event.target.value)}
                      >
                        <option value="">Select a court proceeding</option>
                        {matter.court_cases.map((item) => <option key={item.id} value={item.id}>{item.caption}</option>)}
                      </select>
                    </div>
                  )}
                  <div className="space-y-1">
                    <Label htmlFor="promotion-title">Draft evidence title</Label>
                    <Input id="promotion-title" maxLength={500} value={title} onChange={(event) => setTitle(event.target.value)} />
                  </div>
                  <div className="space-y-1">
                    <Label htmlFor="promotion-description">Operator note (optional)</Label>
                    <Textarea id="promotion-description" maxLength={20000} value={description} onChange={(event) => setDescription(event.target.value)} />
                  </div>
                  <div className="rounded-md border border-amber-500 bg-amber-500/5 p-3 text-sm">
                    <strong>Human review gate:</strong> creation produces an unreviewed, HITL-required, unauthenticated draft that is unsafe for legal use.
                  </div>
                </div>
              )}
            </div>
          )}

          <DialogFooter>
            <Button type="button" variant="outline" onClick={() => setOpen(false)}>Close</Button>
            {!result && (
              <Button
                type="button"
                variant="destructive"
                disabled={loading || !selectedRecordId || !courtCaseId || !title.trim()}
                onClick={() => void promoteSelected()}
              >
                Create unsafe draft for review
              </Button>
            )}
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}
