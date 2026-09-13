"use client";

import { AlertTriangle, Check, CircleDot, Database, ExternalLink, Flag, RefreshCw, ShieldCheck, X } from "lucide-react";
import { useMemo, useState } from "react";

import { AtomicTools } from "@/components/tools/atomic-tools";
import { PlatformMessageViewer } from "@/components/sbv/platform-message-viewer";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { AppLink } from "@/lib/router-compat";
import { checkpointLabel } from "@/lib/proffer-context-checkpoints";
import type {
  ProfferOperatorAvailability,
  ProfferOperatorSnapshot,
  ProfferParserCandidate,
  ProfferPreviewEvent,
  ProfferPreviewMessage,
  ProfferPreviewParticipant,
  ProfferPreviewResponse,
  ProfferContentResponse,
  ProfferPotentialPromotionFlag,
  ProfferPotentialPromotionScope,
} from "@/lib/shared/types";
import { cn } from "@/lib/utils";

type ReviewTab = "overview" | "records" | "chunks" | "entities" | "relationships" | "graph" | "files" | "lineage" | "warnings" | "attempts";

const TABS: Array<{ id: ReviewTab; label: string }> = [
  { id: "overview", label: "Overview" },
  { id: "records", label: "Source records" },
  { id: "chunks", label: "Chunks" },
  { id: "entities", label: "Entities" },
  { id: "relationships", label: "Relationships" },
  { id: "graph", label: "Graph" },
  { id: "files", label: "Attachments / files" },
  { id: "lineage", label: "Lineage" },
  { id: "warnings", label: "Warnings" },
  { id: "attempts", label: "Attempts / runs" },
];

function Availability({ value, label }: { value: ProfferOperatorAvailability; label: string }) {
  return (
    <div className="border bg-card p-3 text-xs">
      <div className="flex items-center justify-between gap-3">
        <strong>{label}</strong>
        <Badge variant={value.status === "available" ? "default" : "outline"}>{value.status}</Badge>
      </div>
      {value.ref && <p className="mt-2 break-all font-mono text-[10px] text-muted-foreground">{value.ref}</p>}
      {value.count !== null && value.count !== undefined && <p className="mt-2">{value.count.toLocaleString()} reported</p>}
      {value.reason && <p className="mt-2 leading-5 text-muted-foreground">{value.reason}</p>}
    </div>
  );
}

function PotentialPromotionControl({
  scope,
  targetId,
  attemptId,
  flags,
  pending,
  onFlag,
}: {
  scope: ProfferPotentialPromotionScope;
  targetId: string;
  attemptId: string;
  flags: ProfferPotentialPromotionFlag[];
  pending: boolean;
  onFlag: (scope: ProfferPotentialPromotionScope, targetId: string, attemptId: string, reason: string) => void;
}) {
  const [reason, setReason] = useState("");
  const targetFlags = flags.filter((flag) => flag.scope === scope && flag.target_id === targetId);

  return (
    <section className="mt-3 border-l-4 border-l-[#c69027] bg-[#fff4dd] p-3 text-xs text-[#684b18] dark:bg-[#43351f] dark:text-[#ffe0a6]">
      <div className="flex flex-wrap items-start justify-between gap-2">
        <div>
          <strong>Potential future use</strong>
          <p className="mt-1 leading-5">This reversible Context annotation records why the item may need a later workflow. It does not publish or alter the source.</p>
        </div>
        <Badge variant="outline" className="border-current text-current">{targetFlags.length} flag{targetFlags.length === 1 ? "" : "s"}</Badge>
      </div>
      {targetFlags.length > 0 && <ol className="mt-3 space-y-2">{targetFlags.map((item) => <li key={item.flag_id} className="border border-current/30 bg-background/70 p-2"><p>{item.reason}</p><p className="mt-1 break-all font-mono text-[10px] opacity-75">{item.actor_username} · {item.flagged_at} · {item.status}<br />attempt {item.attempt_id} · flag {item.flag_id}</p></li>)}</ol>}
      <Label className="mt-3 block" htmlFor={`potential-promotion-${scope}-${targetId}`}>Reason</Label>
      <textarea
        id={`potential-promotion-${scope}-${targetId}`}
        className="mt-1 min-h-20 w-full border bg-background p-2 text-foreground"
        value={reason}
        onChange={(event) => setReason(event.target.value)}
        maxLength={2000}
        placeholder="Why should an operator consider this item later?"
      />
      <Button
        type="button"
        variant="outline"
        size="sm"
        className="mt-2 border-current"
        disabled={pending || !attemptId || !reason.trim()}
        onClick={() => onFlag(scope, targetId, attemptId, reason.trim())}
      >
        <Flag className="size-3.5" /> Mark for later review
      </Button>
    </section>
  );
}

export function ProfferOperatorPreview({
  snapshot,
  preview,
  messages,
  participants,
  events,
  content,
  contentLoading,
  contentError,
  potentialFlags,
  flagError,
  flagPendingTarget,
  messagesLoading,
  messageError,
  hasMore,
  onLoadMore,
  onLoadMoreContent,
  onFlagPotentialPromotion,
  onRefresh,
  onApprove,
  onReject,
  onRetainOriginal,
  onSelectHandler,
  actionPending,
  decisionReady,
}: {
  snapshot: ProfferOperatorSnapshot;
  preview: ProfferPreviewResponse;
  messages: ProfferPreviewMessage[];
  participants: ProfferPreviewParticipant[];
  events: ProfferPreviewEvent[];
  content: ProfferContentResponse | null;
  contentLoading: boolean;
  contentError: string | null;
  potentialFlags: ProfferPotentialPromotionFlag[];
  flagError: string | null;
  flagPendingTarget: string | null;
  messagesLoading: boolean;
  messageError: string | null;
  hasMore: boolean;
  onLoadMore: () => void;
  onLoadMoreContent: (recordCursor?: string, chunkCursor?: string) => void;
  onFlagPotentialPromotion: (scope: ProfferPotentialPromotionScope, targetId: string, attemptId: string, reason: string) => void;
  onRefresh: () => void;
  onApprove: () => void;
  onReject: (reason: string) => void;
  onRetainOriginal: () => void;
  onSelectHandler: (candidate: ProfferParserCandidate) => void;
  actionPending: boolean;
  decisionReady: boolean;
}) {
  const [tab, setTab] = useState<ReviewTab>("overview");
  const [reason, setReason] = useState("");
  const candidates = useMemo(() => preview.recommended_handler
    ? [preview.recommended_handler, ...(preview.alternative_handlers ?? [])]
    : [], [preview.alternative_handlers, preview.recommended_handler]);
  const [selectedHandlerKey, setSelectedHandlerKey] = useState("");
  const selectedHandler = candidates.find((candidate) => `${candidate.handler_id}:${candidate.handler_version}:${candidate.execution_path}:${candidate.compatibility_ref}` === selectedHandlerKey);
  const actionNames = new Set(snapshot.valid_actions.map((item) => item.action));
  const modeTone = snapshot.matter_mode === "REAL"
    ? "border-[#b5433b] bg-[#fbe9e7] text-[#7e2924] dark:bg-[#4d2522] dark:text-[#ffd3ce]"
    : "border-[#c69027] bg-[#fff4dd] text-[#6a480c] dark:bg-[#493719] dark:text-[#ffe0a6]";
  const attemptId = content?.attempt.attempt_ref || content?.attempt.projection_ref || "";
  const entityViewerAvailability: ProfferOperatorAvailability = {
    status: "unavailable",
    reason: snapshot.surfaces.entities.reason || "The Review API does not return attempt-bound entity rows yet.",
  };
  const graphViewerAvailability: ProfferOperatorAvailability = {
    status: "unavailable",
    reason: snapshot.surfaces.graph.reason || "The Review API does not return attempt-bound graph rows yet.",
  };

  return (
    <div className="space-y-4">
      <section className={cn("border-2 p-4", modeTone)} aria-label={`${snapshot.matter_mode} destination`}>
        <div className="flex flex-wrap items-start justify-between gap-4">
          <div>
            <p className="text-[10px] font-bold uppercase tracking-[0.18em]">{snapshot.matter_mode} operation destination</p>
            <h2 className="mt-1 text-lg font-semibold">{snapshot.matter_mode === "REAL" ? "Real matter" : "Development test matter"}</h2>
          </div>
          <Badge variant="outline" className="border-current text-current">{snapshot.lifecycle.replaceAll("_", " ")}</Badge>
        </div>
        <dl className="mt-4 grid gap-3 text-xs md:grid-cols-2 xl:grid-cols-4">
          <div><dt className="opacity-70">Matter</dt><dd className="mt-1 break-all font-mono text-[10px]">{snapshot.matter_id}</dd></div>
          <div><dt className="opacity-70">Court case</dt><dd className="mt-1 break-all font-mono text-[10px]">{snapshot.court_case_id}</dd></div>
          <div><dt className="opacity-70">Attempt resource</dt><dd className="mt-1 break-all font-mono text-[10px]">{snapshot.preview_handle}</dd></div>
          <div><dt className="opacity-70">Request</dt><dd className="mt-1 break-all font-mono text-[10px]">{snapshot.request_id}</dd></div>
        </dl>
      </section>

      <nav className="flex gap-1 overflow-x-auto border bg-card px-2 pt-2" role="tablist" aria-label="Context review views">
        {TABS.map(({ id, label }) => {
          const durableContentAvailable = Boolean(content && (
            id === "overview" || id === "records" || id === "files" || id === "lineage" || id === "warnings" || id === "attempts" ||
            (id === "chunks" && content.chunk_generation)
          ));
          const surfaceKey = id === "relationships" ? "graph" : id === "attempts" ? "workflow" : id;
          const projected = surfaceKey in snapshot.surfaces ? snapshot.surfaces[surfaceKey as keyof typeof snapshot.surfaces] : undefined;
          const state = durableContentAvailable ? { status: "available" as const } : projected ?? { status: "unavailable" as const };
          return (
            <button key={id} type="button" role="tab" aria-selected={tab === id} onClick={() => setTab(id)} className={cn("flex shrink-0 items-center gap-2 border-b-2 px-3 py-2 text-xs font-semibold", tab === id ? "border-primary text-primary" : "border-transparent text-muted-foreground hover:text-foreground")}>
              {label}<span className={cn("size-1.5 rounded-full", state.status === "available" ? "bg-[#2f9d67]" : state.status === "pending" ? "bg-[#c69027]" : "bg-muted-foreground/50")} />
            </button>
          );
        })}
      </nav>

      <section className="min-h-[31rem] border bg-card p-4" role="tabpanel">
        {tab === "overview" && <div className="space-y-5">
          <header><p className="platform-kicker">Context extraction package</p><h2 className="mt-1 text-xl font-semibold">Source, parser, package, and destination</h2></header>
          {content && <section className="border-l-4 border-l-primary bg-accent/30 p-4 text-xs">
            <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-4">
              <div><strong>Retained source version</strong><p className="mt-1 break-all font-mono text-[10px]">{content.package.source_version_ref}</p></div>
              <div><strong>Original object</strong><p className="mt-1 break-all font-mono text-[10px]">{content.package.original_ref ?? "Not retained yet"}</p></div>
              <div><strong>Original SHA-256</strong><p className="mt-1 break-all font-mono text-[10px]">{content.package.original_sha256 ?? "Not available"}</p></div>
              <div><strong>Declared format / state</strong><p className="mt-1">{content.package.declared_format} · {content.package.status}</p></div>
            </div>
            <p className="mt-3 text-muted-foreground">{content.package.metadata_count} metadata records · {content.package.attachment_count} retained attachments · {content.package.original_bytes?.toLocaleString() ?? "unknown"} bytes · {content.package.storage_class ?? "storage class unavailable"}</p>
          </section>}
          {contentError && <p className="border border-[#ead5a9] bg-[#fff4dd] p-3 text-xs text-[#684b18]" role="status">Package projection unavailable: {contentError}</p>}
          <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-4">
            <Availability label="Original source reference" value={snapshot.package.original} />
            <Availability label="Original fingerprint" value={snapshot.package.original_fingerprint} />
            <Availability label="Package identity" value={snapshot.package.package_identity} />
            <Availability label="Package hash" value={snapshot.package.package_hash} />
            <Availability label="Metadata" value={snapshot.package.metadata} />
            <Availability label="Attachments" value={snapshot.package.attachments} />
            <Availability label="Parsed / extracted products" value={snapshot.package.parsed_or_extracted_products} />
            <Availability label="Normalized products" value={snapshot.package.normalized_products} />
          </div>
          {preview.correlation && <dl className="grid gap-px border bg-border text-xs md:grid-cols-2">
            <div className="bg-card p-3"><dt className="text-muted-foreground">Raw generation</dt><dd className="mt-1 break-all font-mono text-[10px]">{preview.correlation.raw_generation_id}</dd></div>
            <div className="bg-card p-3"><dt className="text-muted-foreground">Normalized generation</dt><dd className="mt-1 break-all font-mono text-[10px]">{preview.correlation.normalized_generation_id}</dd></div>
          </dl>}
          <div className="grid gap-3 lg:grid-cols-2">
            <Availability label="Intake classification" value={snapshot.authority_state.intake_classification} />
            <Availability label="Context acceptance state" value={snapshot.authority_state.context_status} />
          </div>
          <section className="space-y-3">
            <header><p className="platform-rule-title">Source repair and preprocessing</p><p className="mt-1 text-xs leading-5 text-muted-foreground">Repair assessment belongs before signature routing and handler selection. A detector or tool failure is an operational error, not proof that the source is damaged.</p></header>
            <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-3">
              <Availability label="Assessment report" value={snapshot.repair_state.assessment_report} />
              <Availability label="Affected members / pages" value={snapshot.repair_state.affected_units} />
              <Availability label="Engine / profile / version / hash" value={snapshot.repair_state.engine_profile} />
              <Availability label="Proposed derived action" value={snapshot.repair_state.proposed_action} />
              <Availability label="Durable decision receipt" value={snapshot.repair_state.decision_receipt} />
            </div>
            <p className="border-l-4 border-l-[#c69027] bg-[#fff4dd] p-3 text-xs leading-5 text-[#684b18] dark:bg-[#43351f] dark:text-[#ffe0a6]">{snapshot.repair_state.reentry_rule}</p>
          </section>
          <section className="space-y-3">
            <header><p className="platform-rule-title">D-158 context storage destination</p><p className="mt-1 text-xs leading-5 text-muted-foreground">The destination depends on the package source type and must be visible before publication.</p></header>
            <div className="grid gap-3 md:grid-cols-2">
              <Availability label="Messaging / non-messaging classification" value={snapshot.storage_state.source_type} />
              <Availability label="Selected context target" value={snapshot.storage_state.context_target} />
              <Availability label="PostgreSQL control-plane state" value={snapshot.storage_state.postgres_control_state} />
              <Availability label="Governed searchable projection" value={snapshot.storage_state.searchable_projection} />
            </div>
            <p className="border p-3 text-xs leading-5 text-muted-foreground">{snapshot.storage_state.rule}</p>
          </section>
          <div className="border-l-4 border-l-primary bg-accent/40 p-4 text-sm"><ShieldCheck className="mr-2 inline size-4" />This workspace does not publish anything until the current attempt exposes an explicit valid action and the operator records that decision.</div>
          <section className="space-y-4">
            <div className="border-l-4 border-l-primary bg-accent/40 p-4"><div className="flex items-center gap-2"><Database className="size-4" /><strong>Go-managed structured extraction</strong></div><p className="mt-2 text-xs leading-5 text-muted-foreground">DuckDB is the primary ELT path for compatible structured sources. Go owns selection, bounded references, Temporal correlation, receipt validation, retries, and repair decisions. Only governed DuckDB tools from the monitored catalog appear here.</p>{snapshot.parser_execution_path && <p className="mt-2 text-xs">Selected path for this operation: <strong>{snapshot.parser_execution_path}</strong></p>}</div>
            <AtomicTools embedded initialSearch="duckdb" requiredToolTerm="duckdb" />
          </section>
        </div>}

        {tab === "records" && (content ? <div className="space-y-3">
          <header><p className="platform-kicker">Authoritative normalized projection</p><h2 className="mt-1 text-xl font-semibold">All record types</h2><p className="mt-1 text-xs text-muted-foreground">Payloads below are the exact persisted normalized_payload objects. Messages are one record type within this view.</p></header>
          {flagError && <p className="border border-destructive/40 bg-destructive/5 p-3 text-xs text-destructive" role="alert">Later-review annotations unavailable: {flagError}</p>}
          <ol className="divide-y border">{content.records.map((record) => <li key={record.record_id} className="p-4"><div className="flex flex-wrap justify-between gap-2"><strong>#{record.ordinal} · {record.record_type}</strong><span className="text-xs text-muted-foreground">{record.occurred_at ?? "No occurrence time"}</span></div><p className="mt-2 break-all font-mono text-[10px] text-muted-foreground">{record.record_id} · {record.source_locator_ref}</p><pre className="mt-3 max-h-96 overflow-auto whitespace-pre-wrap border bg-muted/30 p-3 text-xs">{JSON.stringify(record.payload, null, 2)}</pre><PotentialPromotionControl scope="record" targetId={record.record_id} attemptId={attemptId} flags={potentialFlags} pending={flagPendingTarget === `record:${record.record_id}`} onFlag={onFlagPotentialPromotion} /></li>)}</ol>
          {!content.records.length && <p className="border p-6 text-center text-sm text-muted-foreground">No normalized records are projected for this attempt.</p>}
          {content.next_record_cursor && <Button variant="outline" disabled={contentLoading} onClick={() => onLoadMoreContent(content.next_record_cursor ?? undefined, undefined)}>Load more records</Button>}
        </div> : <PlatformMessageViewer key={snapshot.preview_handle} messages={messages} participants={participants} loading={messagesLoading || contentLoading} error={contentError ?? messageError} previewHandle={snapshot.preview_handle} hasMore={hasMore} onLoadMore={onLoadMore} />)}

        {tab === "chunks" && (content?.chunk_generation ? <div className="space-y-4">
          <header><p className="platform-kicker">Exact pre-publication chunks</p><h2 className="mt-1 text-xl font-semibold">Sealed chunk generation {content.chunk_generation.generation_ordinal}</h2><p className="mt-1 text-xs text-muted-foreground">These chunks remain Context candidates until the exact attempt is approved for its configured destination.</p></header>
          {flagError && <p className="border border-destructive/40 bg-destructive/5 p-3 text-xs text-destructive" role="alert">Later-review annotations unavailable: {flagError}</p>}
          <dl className="grid gap-px border bg-border text-xs md:grid-cols-3"><div className="bg-card p-3"><dt>Generation / receipt</dt><dd className="mt-1 break-all font-mono text-[10px]">{content.chunk_generation.generation_ref}<br />{content.chunk_generation.receipt_ref}</dd></div><div className="bg-card p-3"><dt>Chunker / policy</dt><dd className="mt-1">{content.chunk_generation.chunker_id}@{content.chunk_generation.chunker_version}<br />{content.chunk_generation.policy_id}@{content.chunk_generation.policy_version}</dd></div><div className="bg-card p-3"><dt>Completeness</dt><dd className="mt-1">{content.chunk_generation.status} · {content.chunk_generation.reassembly_result ?? "not reported"}<br />{content.chunk_generation.chunk_count ?? content.chunks.length} chunks</dd></div></dl>
          <ol className="space-y-3">{content.chunks.map((piece) => <li key={piece.chunk_ref} className="border p-4"><div className="flex flex-wrap items-center justify-between gap-2"><strong>Chunk {piece.index}</strong><Badge variant="outline">{piece.derivation_mode}</Badge></div><p className="mt-2 break-all font-mono text-[10px] text-muted-foreground">Bytes [{piece.byte_start}, {piece.byte_end}) · {piece.locator_ref}<br />SHA-256 {piece.sha256}</p><pre className="mt-3 max-h-96 overflow-auto whitespace-pre-wrap border bg-muted/30 p-3 text-xs">{piece.content}</pre><PotentialPromotionControl scope="chunk" targetId={piece.chunk_ref} attemptId={attemptId} flags={potentialFlags} pending={flagPendingTarget === `chunk:${piece.chunk_ref}`} onFlag={onFlagPotentialPromotion} /></li>)}</ol>
          {content.next_chunk_cursor && <Button variant="outline" disabled={contentLoading} onClick={() => onLoadMoreContent(undefined, content.next_chunk_cursor ?? undefined)}>Load more chunks</Button>}
        </div> : <UnavailablePanel title="Chunks and context" availability={contentError ? { ...snapshot.surfaces.chunks, reason: contentError } : snapshot.surfaces.chunks} />)}
        {tab === "entities" && <UnavailablePanel title="Extracted entities" availability={entityViewerAvailability} action="Entity rows will appear here when the backend returns an attempt-bound entity projection." />}
        {tab === "relationships" && <UnavailablePanel title="Proposed relationships" availability={graphViewerAvailability} action="Relationship rows will appear here when the backend returns source and target references for this attempt." />}
        {tab === "graph" && <div className="space-y-4"><UnavailablePanel title="Context graph" availability={graphViewerAvailability} action="Neo4j is the primary approved graph destination. This view needs a read API that returns attempt-bound nodes, relationships, and write receipts." /><div className="border-l-4 border-l-[#c69027] bg-[#fff4dd] p-4 text-xs leading-5 text-[#684b18] dark:bg-[#43351f] dark:text-[#ffe0a6]"><strong>SurrealDB projection is separate.</strong> It is a later, manual projection and is not run or implied by this Context review.</div></div>}

        {tab === "files" && <div className="space-y-4">
          <header><p className="platform-kicker">Retained source package</p><h2 className="mt-1 text-xl font-semibold">Attachments and files</h2><p className="mt-1 text-xs text-muted-foreground">Every row below is returned by the current package projection.</p></header>
          {content?.attachments.length ? <ol className="divide-y border">{content.attachments.map((attachment) => <li key={attachment.object_ref} className="grid gap-2 p-4 text-xs md:grid-cols-[minmax(0,1fr)_12rem]"><div><strong className="break-all">{attachment.object_ref}</strong><pre className="mt-2 max-h-44 overflow-auto whitespace-pre-wrap text-[10px] text-muted-foreground">{JSON.stringify(attachment.member_locator, null, 2)}</pre></div><div className="space-y-1 text-muted-foreground"><p>{attachment.byte_length.toLocaleString()} bytes</p><p>{attachment.storage_class}</p><p className="break-all font-mono text-[10px]">SHA-256 {attachment.sha256}</p></div></li>)}</ol> : <UnavailablePanel title="Attachments and files" availability={contentError ? { status: "unavailable", reason: contentError } : snapshot.package.attachments} action="No attachment rows were returned for this attempt." />}
        </div>}

        {tab === "lineage" && <div className="space-y-4">
          <header><p className="platform-kicker">Trace every result</p><h2 className="mt-1 text-xl font-semibold">Source to record to chunk lineage</h2></header>
          {content ? <div className="space-y-4"><dl className="grid gap-px border bg-border text-xs md:grid-cols-3"><div className="bg-card p-3"><dt className="text-muted-foreground">Source version</dt><dd className="mt-1 break-all font-mono text-[10px]">{content.package.source_version_ref}</dd></div><div className="bg-card p-3"><dt className="text-muted-foreground">Attempt</dt><dd className="mt-1 break-all font-mono text-[10px]">{attemptId || "Unavailable"}</dd></div><div className="bg-card p-3"><dt className="text-muted-foreground">Chunk generation</dt><dd className="mt-1 break-all font-mono text-[10px]">{content.chunk_generation?.generation_ref ?? "Unavailable"}</dd></div></dl><ol className="divide-y border">{content.records.map((record) => <li key={record.record_id} className="grid gap-2 p-3 text-xs md:grid-cols-[minmax(0,1fr)_minmax(0,1fr)]"><span className="break-all"><strong>Record {record.ordinal}</strong><br />{record.record_id}</span><span className="break-all font-mono text-[10px] text-muted-foreground">{record.source_locator_ref}</span></li>)}</ol>{!content.records.length && <p className="border p-6 text-center text-sm text-muted-foreground">No source-record lineage rows were returned.</p>}</div> : <UnavailablePanel title="Lineage" availability={{ status: "unavailable", reason: contentError ?? "The backend has not returned a content projection for this attempt." }} />}
        </div>}

        {tab === "warnings" && <div className="space-y-4">
          <header><p className="platform-kicker">Operator attention</p><h2 className="mt-1 text-xl font-semibold">Warnings and unavailable controls</h2></header>
          {snapshot.reason && <p className="border border-destructive/40 bg-destructive/5 p-3 text-sm text-destructive" role="alert">{snapshot.reason}</p>}
          {contentError && <p className="border border-[#ead5a9] bg-[#fff4dd] p-3 text-sm text-[#684b18]" role="status">Content projection: {contentError}</p>}
          {messageError && <p className="border border-[#ead5a9] bg-[#fff4dd] p-3 text-sm text-[#684b18]" role="status">Message records: {messageError}</p>}
          {snapshot.stages.filter((stage) => stage.reason).length > 0 && <ol className="divide-y border">{snapshot.stages.filter((stage) => stage.reason).map((stage, index) => <li key={`${stage.stage}:${index}`} className="p-3 text-sm"><strong>{stage.stage.replaceAll("_", " ")}</strong><p className="mt-1 text-xs text-muted-foreground">{stage.reason}</p></li>)}</ol>}
          {!snapshot.reason && !contentError && !messageError && snapshot.stages.every((stage) => !stage.reason) && snapshot.unavailable_controls.length === 0 && <p className="border p-6 text-center text-sm text-muted-foreground">No warnings are reported for this attempt.</p>}
          {snapshot.unavailable_controls.length > 0 && <section className="border border-[#ead5a9] bg-[#fff4dd] p-4 text-[#684b18] dark:bg-[#43351f] dark:text-[#ffe0a6]"><h3 className="text-sm font-semibold">Controls waiting on backend contracts</h3><ul className="mt-2 space-y-2 text-xs">{snapshot.unavailable_controls.map((gap) => <li key={gap.control}><strong>{gap.control.replaceAll("_", " ")}:</strong> {gap.reason}</li>)}</ul></section>}
        </div>}

        {tab === "attempts" && <div className="space-y-5">
          {content && <section className="border p-4 text-xs"><div className="flex items-center justify-between gap-3"><h2 className="platform-rule-title">Projected extraction attempt</h2><Badge variant="outline">{content.attempts_complete ? "history complete" : "current projection only"}</Badge></div><div className="mt-3 grid gap-2 md:grid-cols-2"><p className="break-all"><strong>Attempt ref:</strong> {content.attempt.attempt_ref || "Unavailable"}</p><p className="break-all"><strong>Projection ref:</strong> {content.attempt.projection_ref}</p><p className="break-all"><strong>Selection:</strong> {content.attempt.selection_ref || "Unavailable"}</p><p className="break-all"><strong>Options:</strong> {content.attempt.parser_options_ref || "Unavailable"}</p><p><strong>Parser:</strong> {content.attempt.parser ? `${content.attempt.parser.parser_id}@${content.attempt.parser.parser_version}` : "Unavailable"}</p></div>{!content.attempts_complete && <p className="mt-3 border-l-4 border-l-[#c69027] bg-[#fff4dd] p-3 text-[#684b18]">Compare attempts and edit-template rerun remain unavailable: {content.attempts_reason}</p>}</section>}
          <div className="grid gap-3 lg:grid-cols-2">
            {snapshot.layers.map((layer) => <article key={layer.layer} className="border p-4">
              <div className="flex items-center justify-between"><h2 className="text-base font-semibold uppercase">{layer.layer}</h2><Badge variant="outline">{layer.status.replaceAll("_", " ")}</Badge></div>
              <p className="mt-2 text-xs leading-5 text-muted-foreground">{layer.detail}</p>
              <div className="mt-4 grid gap-2"><Availability label="Workflow ID" value={layer.workflow_id} /><Availability label={layer.layer === "n8n" ? "Execution ID" : "Run ID"} value={layer.run_or_execution_id} /><Availability label="Version / activation truth" value={layer.version} /></div>
            </article>)}
          </div>
          <section><div className="flex items-center justify-between"><h2 className="platform-rule-title">Stages, references, receipts, errors</h2><span className="text-xs text-muted-foreground">Retry count {snapshot.retry_count}</span></div>
            <ol className="mt-3 divide-y border">{snapshot.stages.length ? snapshot.stages.map((stage, index) => <li key={`${stage.stage}:${index}`} className="grid gap-2 p-3 text-xs md:grid-cols-[minmax(14rem,1fr)_8rem_minmax(12rem,1fr)]"><div><strong>{stage.stage.replaceAll("_", " ")}</strong>{stage.reason && <p className="mt-1 text-destructive">{stage.reason}</p>}</div><span>{stage.status}</span><div className="space-y-1 break-all font-mono text-[10px] text-muted-foreground">{stage.ref && <p>Output {stage.ref}</p>}{stage.receipt_ref && <p>Receipt {stage.receipt_ref}</p>}{!stage.ref && !stage.receipt_ref && <p>No output or receipt reference reported</p>}</div></li>) : <li className="p-5 text-sm text-muted-foreground">No stage receipt has been projected yet.</li>}</ol>
          </section>
          <section><h2 className="platform-rule-title">Context receipts</h2><ol className="mt-3 divide-y border">{preview.receipts?.length ? preview.receipts.map((receipt) => <li key={receipt.receipt_ref} className="grid gap-2 p-3 text-xs md:grid-cols-[minmax(12rem,1fr)_8rem_minmax(12rem,1fr)]"><strong>{checkpointLabel(receipt.receipt_type)}</strong><span>{receipt.status}</span><div className="break-all font-mono text-[10px] text-muted-foreground"><p>{receipt.receipt_ref}</p><p>{receipt.recorded_at}</p></div></li>) : <li className="p-5 text-sm text-muted-foreground">No context receipt has been returned.</li>}</ol></section>
          <section><h2 className="platform-rule-title">Replayable events</h2><ol className="mt-3 space-y-2">{events.length ? events.map((event) => <li key={event.event_id} className="border-l-2 pl-3 text-xs"><span className="font-mono">#{event.event_id}</span> · {event.event_type} · {event.phase}{event.detail && <p className="mt-1 text-muted-foreground">{event.detail}</p>}</li>) : <li className="text-sm text-muted-foreground">No events received in this browser session.</li>}</ol></section>
        </div>}
      </section>

      <section className="border bg-card p-4" aria-label="Next valid actions">
        <div className="flex flex-wrap items-start justify-between gap-3"><div><p className="platform-rule-title">Next valid actions</p><p className="mt-1 text-xs text-muted-foreground">Only actions backed by the current state and API contract appear here.</p></div><Button variant="outline" size="sm" onClick={onRefresh} disabled={actionPending}><RefreshCw className="size-3.5" /> Refresh</Button></div>
        {snapshot.reason && <p className="mt-3 border border-destructive/40 bg-destructive/5 p-3 text-sm text-destructive" role="alert"><AlertTriangle className="mr-2 inline size-4" />{snapshot.reason}</p>}
        {actionNames.has("select_handler") && <div className="mt-4 space-y-3"><Label htmlFor="operator-handler">Compatible handler</Label><select id="operator-handler" className="h-10 w-full border bg-background px-3 text-sm" value={selectedHandlerKey} onChange={(event) => setSelectedHandlerKey(event.target.value)}><option value="">Choose an exact registered handler</option>{candidates.map((candidate) => {const key = `${candidate.handler_id}:${candidate.handler_version}:${candidate.execution_path}:${candidate.compatibility_ref}`; return <option key={key} value={key}>{candidate.handler_id} · {candidate.handler_version} · {candidate.execution_path}</option>;})}</select><Button disabled={!selectedHandler || actionPending} onClick={() => selectedHandler && onSelectHandler(selectedHandler)}><Check className="size-4" /> Record handler and continue</Button></div>}
        {actionNames.has("retain_original") && <div className="mt-4"><Button disabled={actionPending} onClick={onRetainOriginal}><ShieldCheck className="size-4" /> Retain sealed original and continue</Button></div>}
        {(actionNames.has("approve_preview") || actionNames.has("reject_preview")) && <div className="mt-4 space-y-3"><Label htmlFor="operator-decision-reason">Reason for rejection</Label><Input id="operator-decision-reason" value={reason} onChange={(event) => setReason(event.target.value)} placeholder="Required only for rejection"/><div className="flex flex-wrap gap-2">{actionNames.has("approve_preview") && <Button disabled={actionPending || !decisionReady} onClick={onApprove}><Check className="size-4" /> Approve this attempt</Button>}{actionNames.has("reject_preview") && <Button variant="destructive" disabled={actionPending || !decisionReady || !reason.trim()} onClick={() => onReject(reason.trim())}><X className="size-4" /> Reject with reason</Button>}</div></div>}
        {actionNames.has("restart_new_operation") && <div className="mt-4"><Button asChild><AppLink href={`/intake?mode=${snapshot.matter_mode}`}><CircleDot className="size-4" /> Start a new import <ExternalLink className="size-3.5" /></AppLink></Button><p className="mt-2 text-xs text-muted-foreground">This creates a new request identity and does not misrepresent the failed operation as resumed.</p></div>}
      </section>
    </div>
  );
}

function UnavailablePanel({ title, availability, action }: { title: string; availability: ProfferOperatorAvailability; action?: string }) {
  return <div className="grid min-h-[18rem] place-content-center text-center"><CircleDot className="mx-auto size-7 text-muted-foreground"/><h2 className="mt-3 text-lg font-semibold">{title}</h2><Badge variant="outline" className="mx-auto mt-2">{availability.status}</Badge><p className="mx-auto mt-3 max-w-xl text-sm leading-6 text-muted-foreground">{availability.reason}</p>{action && <p className="mx-auto mt-2 max-w-xl text-xs leading-5 text-muted-foreground">{action}</p>}</div>;
}
