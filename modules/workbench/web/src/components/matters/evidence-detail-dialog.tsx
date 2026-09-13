// Byline: Codex · GPT-5 · 2026-08-15 (Matter-scoped custody inspection)
// Byline: Codex · GPT-5 · 2026-08-18 (third-party acquisition and realization detail)
"use client";

import { useEffect, useRef, useState } from "react";
import type { ReactNode } from "react";
import { AlertTriangle, Eye, Fingerprint, Loader2, RefreshCw } from "lucide-react";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { getEvidenceConversationContext, getEvidenceDetail, getEvidenceSourceContent, listEvidenceReviews } from "@/lib/api-client";
import { useFixedCase } from "@/lib/fixed-case-context";
import type { EvidenceConversationContext, EvidenceDetail, EvidenceItem, EvidenceReviewRecord, EvidenceSourceContent, MatterMode } from "@/lib/shared/types";

function readableDate(value?: string | null) {
  if (!value) return "Not established";
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? value : date.toLocaleString();
}

function detailError(error: unknown) {
  return error instanceof Error ? error.message : "Evidence provenance could not be inspected";
}

function PaneState({ loading, error, children }: { loading: boolean; error: string | null; children: ReactNode }) {
  if (loading) return <p role="status" className="flex items-center gap-2 rounded-md border p-4 text-sm text-muted-foreground"><Loader2 className="h-4 w-4 animate-spin" aria-hidden="true" /> Loading verified evidence view</p>;
  if (error) return <p role="alert" className="rounded-md border border-destructive p-4 text-sm text-destructive">This view is unavailable: {error}</p>;
  return <>{children}</>;
}

function SourcePointer({ pointer }: { pointer?: Record<string, unknown> | null }) {
  if (!pointer) return <span className="text-muted-foreground">Not returned</span>;
  return <span className="break-all font-mono text-xs">{Object.entries(pointer).map(([key, value]) => `${key}=${String(value)}`).join(" · ")}</span>;
}

function OperationsViews({ detail }: { detail: EvidenceDetail }) {
  const { mode } = useFixedCase();
  const [view, setView] = useState<"source" | "normalized" | "context" | "review">("normalized");
  const [source, setSource] = useState<EvidenceSourceContent | null>(null);
  const [context, setContext] = useState<EvidenceConversationContext | null>(null);
  const [history, setHistory] = useState<EvidenceReviewRecord[] | null>(null);
  const [loading, setLoading] = useState({ source: false, context: false, review: false });
  const [errors, setErrors] = useState<{ source: string | null; context: string | null; review: string | null }>({ source: null, context: null, review: null });
  const requestRef = useRef(0);

  useEffect(() => {
    const request = ++requestRef.current;
    const load = async () => {
      setSource(null); setContext(null); setHistory(null);
      setLoading({ source: true, context: true, review: true });
      setErrors({ source: null, context: null, review: null });
      const results = await Promise.allSettled([
        getEvidenceSourceContent(detail.item.matter_id, detail.item.id, mode),
        getEvidenceConversationContext(detail.item.matter_id, detail.item.id, mode),
        listEvidenceReviews(detail.item.matter_id, detail.item.id, mode),
      ]);
      if (request !== requestRef.current) return;
      const [sourceResult, contextResult, reviewResult] = results;
      if (sourceResult.status === "fulfilled") setSource(sourceResult.value); else setErrors((old) => ({ ...old, source: detailError(sourceResult.reason) }));
      if (contextResult.status === "fulfilled") setContext(contextResult.value); else setErrors((old) => ({ ...old, context: detailError(contextResult.reason) }));
      if (reviewResult.status === "fulfilled") setHistory(reviewResult.value.data); else setErrors((old) => ({ ...old, review: detailError(reviewResult.reason) }));
      setLoading({ source: false, context: false, review: false });
    };
    void load();
    return () => { requestRef.current += 1; };
  }, [detail.item.id, detail.item.matter_id, mode]);

  const tabs = [["source", "Original Source"], ["normalized", "Normalized Message"], ["context", "Conversation Context"], ["review", "Human Review"]] as const;
  return <section aria-label="Evidence Operations Desk" className="space-y-3 rounded-md border bg-background p-3">
    <div role="tablist" aria-label="Evidence views" className="grid grid-cols-2 gap-1 sm:grid-cols-4">
      {tabs.map(([value, label]) => <button key={value} type="button" role="tab" aria-selected={view === value} className={`rounded-md px-2 py-2 text-xs font-medium ${view === value ? "bg-primary text-primary-foreground" : "border text-muted-foreground"}`} onClick={() => setView(value)}>{label}</button>)}
    </div>
    {view === "source" && <PaneState loading={loading.source} error={errors.source}><div className="space-y-3"><h3 className="font-semibold">Original Source</h3><pre className="max-h-80 overflow-auto whitespace-pre-wrap break-words rounded-md border bg-muted/30 p-3 text-sm">{source?.content}</pre><dl className="space-y-2 rounded-md border p-3 text-sm"><DetailRow label="Source pointer"><SourcePointer pointer={source?.source_pointer as Record<string, unknown> | null | undefined} /></DetailRow><DetailRow label="H1 / H2 / H3">{source?.h1 || "—"} / {source?.h2 || "—"} / {source?.h3 || "—"}</DetailRow><DetailRow label="Provenance"><SourcePointer pointer={source?.provenance} /></DetailRow></dl></div></PaneState>}
    {view === "normalized" && <div className="space-y-3"><h3 className="font-semibold">Normalized Message</h3><div className="flex flex-wrap gap-2"><Badge variant="outline">{detail.record.record_type}</Badge><Badge variant="outline">{detail.record.source_kind.replaceAll("_", " ")}</Badge><Badge variant="outline">{detail.record.disclosure_tier}</Badge><Badge variant="outline">{detail.record.projection_kind.replaceAll("_", " ")}</Badge></div><pre className="max-h-80 overflow-auto whitespace-pre-wrap break-words rounded-md border bg-muted/30 p-3 text-sm">{detail.record.content}</pre><dl className="space-y-2 rounded-md border p-3 text-sm"><DetailRow label="Sender / role">{detail.record.third_party_conversation?.actual_sender || detail.record.role || "Not established"}</DetailRow><DetailRow label="Recipients">{detail.record.third_party_conversation?.actual_recipients.join(", ") || "Not established"}</DetailRow><DetailRow label="Occurred"><time dateTime={detail.record.occurred_at || undefined}>{readableDate(detail.record.occurred_at)}</time></DetailRow><DetailRow label="Source available"><time dateTime={detail.record.source_available_from || undefined}>{readableDate(detail.record.source_available_from)}</time></DetailRow></dl></div>}
    {view === "context" && <PaneState loading={loading.context} error={errors.context}><div className="space-y-3"><h3 className="font-semibold">Conversation Context</h3><p className="text-xs text-muted-foreground">Showing the server-returned window (up to 25 messages before and after). Messages remain source evidence; agent notes are non-canonical.</p>{context?.messages.length ? <ol className="max-h-96 space-y-2 overflow-auto">{context.messages.map((message) => <li key={message.id} className={`rounded-md border p-3 text-sm ${message.id === detail.record.id ? "border-primary bg-primary/5" : ""}`}><div className="flex flex-wrap gap-2 text-xs text-muted-foreground"><span>{message.sender || "Sender not established"}</span><span>→ {message.recipients.length ? message.recipients.join(", ") : "Recipients not established"}</span><time dateTime={message.occurred_at || undefined}>{readableDate(message.occurred_at)}</time></div><p className="mt-2 whitespace-pre-wrap">{message.content}</p><p className="mt-2 text-xs text-muted-foreground">Source pointer: <SourcePointer pointer={message.source_pointer} /></p></li>)}</ol> : <p className="rounded-md border p-3 text-sm text-muted-foreground">No conversation context was returned.</p>}</div></PaneState>}
    {view === "review" && <PaneState loading={loading.review} error={errors.review}><div className="space-y-3"><h3 className="font-semibold">Human Review</h3><div className="flex flex-wrap gap-2"><Badge variant="outline">Status: {detail.item.review_status}</Badge><Badge variant={detail.item.safe_for_legal_use ? "secondary" : "destructive"}>{detail.item.safe_for_legal_use ? "Legal safety asserted" : "Unsafe for legal use"}</Badge><Badge variant="outline">{detail.item.is_authenticated ? "Authenticated" : "Unauthenticated"}</Badge></div><p className="rounded-md border border-amber-500/60 bg-amber-500/5 p-3 text-sm">Review decisions are append-only and do not authenticate the source or grant legal safety. Use the adjacent Review draft action to record a decision. Agent notes are non-canonical.</p>{history?.length ? <ol className="space-y-2">{history.map((record) => <li key={record.decision_id} className="rounded-md border p-3 text-sm"><div className="flex flex-wrap gap-2"><Badge variant="outline">{record.decision.replaceAll("_", " ")}</Badge><span className="text-xs text-muted-foreground">{readableDate(record.decided_at)} · {record.reviewer}</span></div><p className="mt-2">{record.rationale}</p></li>)}</ol> : <p className="rounded-md border p-3 text-sm text-muted-foreground">No reviewer decision has been recorded.</p>}</div></PaneState>}
  </section>;
}

export function validateEvidenceDetail(detail: EvidenceDetail, expected: EvidenceItem) {
  if (detail.item.id !== expected.id || detail.item.matter_id !== expected.matter_id) {
    return "Inspection returned a different Matter evidence item";
  }
  if (detail.record.id !== expected.normalized_record_id) {
    return "Canonical record identity does not match this evidence item";
  }
  if (detail.custody_hash.id !== expected.evidence_hash_id) {
    return "Custody hash identity does not match this evidence item";
  }
  if (detail.source.id !== expected.source_id) {
    return "Source identity does not match this evidence item";
  }
  if (
    expected.file_node_id &&
    (!detail.file_node || detail.file_node.id !== expected.file_node_id)
  ) {
    return "File-node provenance does not match this evidence item";
  }
  if (
    detail.custody_hash.level !== "H1" ||
    detail.custody_hash.algo.toLowerCase() !== "sha256" ||
    detail.custody_hash.canon_version !== "h1-rawbytes-v1"
  ) {
    return "Inspection did not return the required H1 SHA-256 raw-bytes custody contract";
  }
  if (detail.source.hash_canon_version !== "h1-rawbytes-v1") {
    return "Source did not return the required raw-bytes canon version";
  }
  if (detail.record.source_kind === "third_party_acquired") {
    if (!detail.record.third_party_conversation || !detail.record.source_available_from) {
      return "Third-party evidence is missing its approved conversation acquisition boundary";
    }
    if (detail.record.projection_kind !== "derived_third_party") {
      return "Third-party evidence returned an inconsistent projection kind";
    }
  }
  if (detail.record.third_party_conversation && detail.record.source_kind !== "third_party_acquired") {
    return "Conversation acquisition context was attached to a non-third-party record";
  }
  const pointer = detail.promotion.source_pointer;
  if (
    pointer.matter_id !== expected.matter_id ||
    pointer.court_case_id !== expected.court_case_id ||
    pointer.normalized_record_id !== detail.record.id ||
    pointer.evidence_hash_id !== detail.custody_hash.id ||
    pointer.source_id !== detail.source.id
  ) {
    return "Promotion pointer does not match this evidence item";
  }
  return null;
}

export async function loadValidatedEvidenceDetail(item: EvidenceItem, mode: MatterMode) {
  const detail = await getEvidenceDetail(item.matter_id, item.id, mode);
  const invalid = validateEvidenceDetail(detail, item);
  if (invalid) throw new Error(invalid);
  return detail;
}

function DetailRow({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div className="grid gap-1 sm:grid-cols-[10rem_1fr]">
      <dt className="text-xs font-medium uppercase tracking-wide text-muted-foreground">{label}</dt>
      <dd className="min-w-0 break-words text-sm">{children}</dd>
    </div>
  );
}

export function EvidenceDetailContent({ detail }: { detail: EvidenceDetail }) {
  const { item, promotion, record, custody_hash: custody, source, file_node: fileNode } = detail;
  const thirdParty = record.third_party_conversation;
  return (
    <div className="space-y-5">
      <div className="flex flex-wrap items-center gap-2 rounded-md border border-amber-500/60 bg-amber-500/5 p-3 text-sm">
        <AlertTriangle className="h-4 w-4 text-amber-600" aria-hidden="true" />
        <Badge variant="outline">{item.review_status}</Badge>
        {item.hitl_required && <Badge variant="outline">HITL required</Badge>}
        {!item.safe_for_legal_use && <Badge variant="destructive">Unsafe for legal use</Badge>}
        {!item.is_authenticated && <Badge variant="outline">Unauthenticated</Badge>}
        <span className="basis-full text-muted-foreground">
          Inspection confirms identity and custody coordinates. It does not authenticate the source or grant legal safety.
        </span>
      </div>

      <OperationsViews detail={detail} />

      <section aria-labelledby={`record-content-${item.id}`} className="space-y-2">
        <h3 id={`record-content-${item.id}`} className="font-semibold">Exact normalized source record</h3>
        <div className="flex flex-wrap gap-2">
          <Badge variant="outline">{record.record_type}</Badge>
          <Badge variant="secondary">{record.source_kind.replaceAll("_", " ")}</Badge>
          <Badge variant="outline">{record.projection_kind.replaceAll("_", " ")}</Badge>
          {!thirdParty && record.role && <Badge variant="outline">normalized role: {record.role}</Badge>}
          <Badge variant="outline">{record.disclosure_tier}</Badge>
        </div>
        <pre className="max-h-72 overflow-auto whitespace-pre-wrap break-words rounded-md border bg-muted/30 p-3 text-sm">
          {record.content}
        </pre>
        <dl className="space-y-2 rounded-md border p-3">
          <DetailRow label="Record ID"><span className="break-all font-mono text-xs">{record.id}</span></DetailRow>
          <DetailRow label="Occurred"><time dateTime={record.occurred_at || undefined}>{readableDate(record.occurred_at)}</time></DetailRow>
          <DetailRow label="Source available"><time dateTime={record.source_available_from || undefined}>{readableDate(record.source_available_from)}</time></DetailRow>
          <DetailRow label="Ingested"><time dateTime={record.ingested_at}>{readableDate(record.ingested_at)}</time></DetailRow>
          <DetailRow label="Record source">{record.source}</DetailRow>
        </dl>
      </section>

      {thirdParty && (
        <section aria-labelledby={`third-party-${item.id}`} className="space-y-2">
          <h3 id={`third-party-${item.id}`} className="font-semibold">Acquired third-party conversation</h3>
          <p className="text-sm text-muted-foreground">
            These are the source-recorded parties. Possession of the conversation does not make the owner a participant.
          </p>
          <dl className="space-y-2 rounded-md border p-3">
            <DetailRow label="Conversation">{thirdParty.title || thirdParty.external_thread_key}</DetailRow>
            <DetailRow label="Platform">{thirdParty.platform}</DetailRow>
            <DetailRow label="Actually sent by">{thirdParty.actual_sender || "Not established"}</DetailRow>
            <DetailRow label="Actual recipients">{thirdParty.actual_recipients.length ? thirdParty.actual_recipients.join(", ") : "Not established"}</DetailRow>
            <DetailRow label="Conversation acquired"><time dateTime={thirdParty.acquired_at}>{readableDate(thirdParty.acquired_at)}</time></DetailRow>
            <DetailRow label="Conversation ID"><span className="break-all font-mono text-xs">{thirdParty.id}</span></DetailRow>
          </dl>
        </section>
      )}

      <section aria-labelledby={`realizations-${item.id}`} className="space-y-2">
        <h3 id={`realizations-${item.id}`} className="font-semibold">Linked realization history</h3>
        {record.realization_events.length === 0 ? (
          <p className="rounded-md border p-3 text-sm text-muted-foreground">No linked realization events.</p>
        ) : (
          <ol className="space-y-2">
            {record.realization_events.map((event) => (
              <li key={event.id} className="rounded-md border p-3 text-sm">
                <div className="flex flex-wrap items-center gap-2">
                  <Badge variant="outline">{event.kind.replaceAll("_", " ")}</Badge>
                  <Badge variant={event.approval_state === "approved" ? "secondary" : "outline"}>{event.approval_state}</Badge>
                  <time dateTime={event.realized_at}>{readableDate(event.realized_at)}</time>
                </div>
                {event.notes && <p className="mt-2 text-muted-foreground">{event.notes}</p>}
              </li>
            ))}
          </ol>
        )}
      </section>

      <section aria-labelledby={`custody-${item.id}`} className="space-y-2">
        <h3 id={`custody-${item.id}`} className="flex items-center gap-2 font-semibold">
          <Fingerprint className="h-4 w-4" aria-hidden="true" /> H1 custody
        </h3>
        <dl className="space-y-2 rounded-md border p-3">
          <DetailRow label="Contract">{custody.level} · {custody.algo} · {custody.canon_version}</DetailRow>
          <DetailRow label="SHA-256"><span className="break-all font-mono text-xs">{custody.digest_sha256}</span></DetailRow>
          <DetailRow label="Hash ID"><span className="break-all font-mono text-xs">{custody.id}</span></DetailRow>
          <DetailRow label="Hashed"><time dateTime={custody.hashed_at}>{readableDate(custody.hashed_at)}</time></DetailRow>
          <DetailRow label="Computed by">{custody.computed_by || "Not recorded"}</DetailRow>
        </dl>
      </section>

      <section aria-labelledby={`source-${item.id}`} className="space-y-2">
        <h3 id={`source-${item.id}`} className="font-semibold">Canonical source</h3>
        <dl className="space-y-2 rounded-md border p-3">
          <DetailRow label="Filename">{source.original_filename || "Not recorded"}</DetailRow>
          <DetailRow label="Source type">{source.source_type}{source.source_platform ? ` · ${source.source_platform}` : ""}</DetailRow>
          <DetailRow label="Media">{source.mime_type || "Unknown"} · {source.byte_size.toLocaleString()} bytes</DetailRow>
          <DetailRow label="Custody acquisition">{source.acquisition_source}{source.acquisition_method ? ` · ${source.acquisition_method}` : ""}</DetailRow>
          <DetailRow label="Entered custody"><time dateTime={source.acquired_at_utc || undefined}>{readableDate(source.acquired_at_utc)}</time> · {source.acquired_certainty}</DetailRow>
          <DetailRow label="Custody status">{source.custody_status} · {source.provenance_tier}</DetailRow>
          <DetailRow label="Source ID"><span className="break-all font-mono text-xs">{source.id}</span></DetailRow>
          <DetailRow label="Verification">{source.verified_by ? `${source.verified_by} · ${readableDate(source.verified_at)}` : "Not separately verified"}</DetailRow>
        </dl>
      </section>

      {fileNode && (
        <section aria-labelledby={`file-node-${item.id}`} className="space-y-2">
          <h3 id={`file-node-${item.id}`} className="font-semibold">Structural file provenance</h3>
          <dl className="space-y-2 rounded-md border p-3">
            <DetailRow label="Node">{fileNode.node_kind} · <span className="break-all font-mono text-xs">{fileNode.id}</span></DetailRow>
            <DetailRow label="Media">{fileNode.mime_type || "Unknown"}</DetailRow>
            <DetailRow label="Byte span">{fileNode.byte_span_start ?? "?"}–{fileNode.byte_span_end ?? "?"}</DetailRow>
            {fileNode.sha256 && <DetailRow label="Node SHA-256"><span className="break-all font-mono text-xs">{fileNode.sha256}</span></DetailRow>}
          </dl>
        </section>
      )}

      <section aria-labelledby={`promotion-${item.id}`} className="space-y-2">
        <h3 id={`promotion-${item.id}`} className="font-semibold">Promotion audit</h3>
        <dl className="space-y-2 rounded-md border p-3">
          <DetailRow label="Partition / lane">{promotion.partition_key} / {promotion.knowledge_lane}</DetailRow>
          <DetailRow label="Retrieval ref"><span className="break-all font-mono text-xs">{promotion.retrieval_item_ref}</span></DetailRow>
          <DetailRow label="Content / chunk">{promotion.content_ref || "—"} / {promotion.chunk_ref || "—"}</DetailRow>
          <DetailRow label="Promoted">{promotion.promoted_by} · <time dateTime={promotion.promoted_at}>{readableDate(promotion.promoted_at)}</time></DetailRow>
        </dl>
      </section>
    </div>
  );
}

export function EvidenceDetailDialog({ item }: { item: EvidenceItem }) {
  const { mode } = useFixedCase();
  const [open, setOpen] = useState(false);
  const [loading, setLoading] = useState(false);
  const [detail, setDetail] = useState<EvidenceDetail | null>(null);
  const [error, setError] = useState<string | null>(null);
  const requestRef = useRef(0);

  async function loadDetail() {
    const request = ++requestRef.current;
    setLoading(true);
    setDetail(null);
    setError(null);
    try {
      const result = await loadValidatedEvidenceDetail(item, mode);
      if (request !== requestRef.current) return;
      setDetail(result);
    } catch (requestError) {
      if (request !== requestRef.current) return;
      setDetail(null);
      setError(detailError(requestError));
    } finally {
      if (request === requestRef.current) setLoading(false);
    }
  }

  function changeOpen(next: boolean) {
    setOpen(next);
    if (next) {
      void loadDetail();
    } else {
      requestRef.current += 1;
      setDetail(null);
      setError(null);
      setLoading(false);
    }
  }

  return (
    <>
      <Button type="button" size="sm" variant="outline" onClick={() => changeOpen(true)}>
        <Eye aria-hidden="true" /> Inspect provenance
      </Button>
      <Dialog open={open} onOpenChange={changeOpen}>
        <DialogContent className="max-h-[90vh] max-w-4xl overflow-y-auto" aria-busy={loading}>
          <DialogHeader>
            <DialogTitle>Evidence provenance inspection</DialogTitle>
            <DialogDescription>
              Matter-scoped canonical record, H1 custody, source, and promotion details. Private storage paths are not exposed.
            </DialogDescription>
          </DialogHeader>
          {loading ? (
            <p className="flex items-center gap-2 py-8 text-sm text-muted-foreground" role="status">
              <Loader2 className="h-4 w-4 animate-spin" aria-hidden="true" /> Loading exact evidence provenance
            </p>
          ) : error ? (
            <div role="alert" className="space-y-3 rounded-md border border-destructive p-3 text-sm text-destructive">
              <p>{error}</p>
              <Button type="button" size="sm" variant="outline" onClick={() => void loadDetail()}>
                <RefreshCw aria-hidden="true" /> Retry inspection
              </Button>
            </div>
          ) : detail ? (
            <EvidenceDetailContent detail={detail} />
          ) : null}
        </DialogContent>
      </Dialog>
    </>
  );
}
