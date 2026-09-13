"use client";

import { AlertTriangle, Check, CircleDot, Database, ExternalLink, RefreshCw, ShieldCheck, X } from "lucide-react";
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
} from "@/lib/shared/types";
import { cn } from "@/lib/utils";

type PreviewTab = "source" | "records" | "chunks" | "entities" | "graph" | "workflow" | "duckdb";

const TABS: Array<{ id: PreviewTab; label: string }> = [
  { id: "source", label: "Source" },
  { id: "records", label: "Records" },
  { id: "chunks", label: "Chunks / Context" },
  { id: "entities", label: "Entities" },
  { id: "graph", label: "Graph candidates" },
  { id: "workflow", label: "Workflow / receipts / errors" },
  { id: "duckdb", label: "DuckDB workspace" },
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

export function ProfferOperatorPreview({
  snapshot,
  preview,
  messages,
  participants,
  events,
  messagesLoading,
  messageError,
  hasMore,
  onLoadMore,
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
  messagesLoading: boolean;
  messageError: string | null;
  hasMore: boolean;
  onLoadMore: () => void;
  onRefresh: () => void;
  onApprove: () => void;
  onReject: (reason: string) => void;
  onRetainOriginal: () => void;
  onSelectHandler: (candidate: ProfferParserCandidate) => void;
  actionPending: boolean;
  decisionReady: boolean;
}) {
  const [tab, setTab] = useState<PreviewTab>("source");
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
          <div><dt className="opacity-70">Preview</dt><dd className="mt-1 break-all font-mono text-[10px]">{snapshot.preview_handle}</dd></div>
          <div><dt className="opacity-70">Request</dt><dd className="mt-1 break-all font-mono text-[10px]">{snapshot.request_id}</dd></div>
        </dl>
      </section>

      <nav className="flex gap-1 overflow-x-auto border bg-card px-2 pt-2" role="tablist" aria-label="Proffer preview data">
        {TABS.map(({ id, label }) => {
          const state = snapshot.surfaces[id === "graph" ? "graph" : id];
          return (
            <button key={id} type="button" role="tab" aria-selected={tab === id} onClick={() => setTab(id)} className={cn("flex shrink-0 items-center gap-2 border-b-2 px-3 py-2 text-xs font-semibold", tab === id ? "border-primary text-primary" : "border-transparent text-muted-foreground hover:text-foreground")}>
              {label}<span className={cn("size-1.5 rounded-full", state.status === "available" ? "bg-[#2f9d67]" : state.status === "pending" ? "bg-[#c69027]" : "bg-muted-foreground/50")} />
            </button>
          );
        })}
      </nav>

      <section className="min-h-[31rem] border bg-card p-4" role="tabpanel">
        {tab === "source" && <div className="space-y-5">
          <header><p className="platform-kicker">Extraction package</p><h2 className="mt-1 text-xl font-semibold">Original, package, and authority boundary</h2></header>
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
            <Availability label="Evidence eligibility" value={snapshot.authority_state.evidence_eligibility} />
            <Availability label="Later promotion prerequisites" value={snapshot.authority_state.promotion_prerequisites} />
            <Availability label="Promotion rehash / re-extraction" value={snapshot.authority_state.promotion_rehash} />
            <Availability label="Custody state" value={snapshot.authority_state.custody_state} />
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
          <div className="border-l-4 border-l-primary bg-accent/40 p-4 text-sm"><ShieldCheck className="mr-2 inline size-4" />{snapshot.write_boundary}</div>
        </div>}

        {tab === "records" && <PlatformMessageViewer key={snapshot.preview_handle} messages={messages} participants={participants} loading={messagesLoading} error={messageError} previewHandle={snapshot.preview_handle} hasMore={hasMore} onLoadMore={onLoadMore} />}

        {tab === "chunks" && <UnavailablePanel title="Chunks and context" availability={snapshot.surfaces.chunks} />}
        {tab === "entities" && <UnavailablePanel title="Extracted entities" availability={snapshot.surfaces.entities} />}
        {tab === "graph" && <UnavailablePanel title="Governed graph candidates" availability={snapshot.surfaces.graph} />}

        {tab === "workflow" && <div className="space-y-5">
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
          {snapshot.unavailable_controls.length > 0 && <section className="border border-[#ead5a9] bg-[#fff4dd] p-4 text-[#684b18] dark:bg-[#43351f] dark:text-[#ffe0a6]"><h2 className="text-sm font-semibold">Controls omitted because the backend contract is missing</h2><ul className="mt-2 space-y-2 text-xs">{snapshot.unavailable_controls.map((gap) => <li key={gap.control}><strong>{gap.control.replaceAll("_", " ")}:</strong> {gap.reason}</li>)}</ul></section>}
        </div>}

        {tab === "duckdb" && <div className="space-y-4">
          <div className="border-l-4 border-l-primary bg-accent/40 p-4"><div className="flex items-center gap-2"><Database className="size-4" /><strong>Go-managed primary structured extraction</strong></div><p className="mt-2 text-xs leading-5 text-muted-foreground">DuckDB is the primary ELT path for compatible structured sources. Go owns selection, bounded references, Temporal correlation, receipt validation, retries, and repair decisions. This workspace discovers only governed DuckDB tools from the monitored catalog; it does not expose arbitrary SQL.</p>{snapshot.parser_execution_path && <p className="mt-2 text-xs">Selected path for this operation: <strong>{snapshot.parser_execution_path}</strong></p>}</div>
          <AtomicTools embedded initialSearch="duckdb" requiredToolTerm="duckdb" />
        </div>}
      </section>

      <section className="border bg-card p-4" aria-label="Next valid actions">
        <div className="flex flex-wrap items-start justify-between gap-3"><div><p className="platform-rule-title">Next valid actions</p><p className="mt-1 text-xs text-muted-foreground">Only actions backed by the current state and API contract appear here.</p></div><Button variant="outline" size="sm" onClick={onRefresh} disabled={actionPending}><RefreshCw className="size-3.5" /> Refresh</Button></div>
        {snapshot.reason && <p className="mt-3 border border-destructive/40 bg-destructive/5 p-3 text-sm text-destructive" role="alert"><AlertTriangle className="mr-2 inline size-4" />{snapshot.reason}</p>}
        {actionNames.has("select_handler") && <div className="mt-4 space-y-3"><Label htmlFor="operator-handler">Compatible handler</Label><select id="operator-handler" className="h-10 w-full border bg-background px-3 text-sm" value={selectedHandlerKey} onChange={(event) => setSelectedHandlerKey(event.target.value)}><option value="">Choose an exact registered handler</option>{candidates.map((candidate) => {const key = `${candidate.handler_id}:${candidate.handler_version}:${candidate.execution_path}:${candidate.compatibility_ref}`; return <option key={key} value={key}>{candidate.handler_id} · {candidate.handler_version} · {candidate.execution_path}</option>;})}</select><Button disabled={!selectedHandler || actionPending} onClick={() => selectedHandler && onSelectHandler(selectedHandler)}><Check className="size-4" /> Record handler and continue</Button></div>}
        {actionNames.has("retain_original") && <div className="mt-4"><Button disabled={actionPending} onClick={onRetainOriginal}><ShieldCheck className="size-4" /> Retain sealed original and continue</Button></div>}
        {(actionNames.has("approve_preview") || actionNames.has("reject_preview")) && <div className="mt-4 space-y-3"><Label htmlFor="operator-decision-reason">Reason for rejection</Label><Input id="operator-decision-reason" value={reason} onChange={(event) => setReason(event.target.value)} placeholder="Required only for rejection"/><div className="flex flex-wrap gap-2">{actionNames.has("approve_preview") && <Button disabled={actionPending || !decisionReady} onClick={onApprove}><Check className="size-4" /> Approve and continue</Button>}{actionNames.has("reject_preview") && <Button variant="destructive" disabled={actionPending || !decisionReady || !reason.trim()} onClick={() => onReject(reason.trim())}><X className="size-4" /> Reject with reason</Button>}</div></div>}
        {actionNames.has("restart_new_operation") && <div className="mt-4"><Button asChild><AppLink href={`/intake?mode=${snapshot.matter_mode}`}><CircleDot className="size-4" /> Start a new import <ExternalLink className="size-3.5" /></AppLink></Button><p className="mt-2 text-xs text-muted-foreground">This creates a new request identity and does not misrepresent the failed operation as resumed.</p></div>}
      </section>
    </div>
  );
}

function UnavailablePanel({ title, availability }: { title: string; availability: ProfferOperatorAvailability }) {
  return <div className="grid min-h-[27rem] place-content-center text-center"><CircleDot className="mx-auto size-7 text-muted-foreground"/><h2 className="mt-3 text-lg font-semibold">{title}</h2><Badge variant="outline" className="mx-auto mt-2">{availability.status}</Badge><p className="mx-auto mt-3 max-w-xl text-sm leading-6 text-muted-foreground">{availability.reason}</p></div>;
}
