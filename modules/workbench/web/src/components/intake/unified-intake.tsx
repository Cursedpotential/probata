// Byline: Codex · GPT-5 · 2026-08-28 (production unified intake vertical slice)
// Byline: Codex · GPT-5 · 2026-08-29 (truthful Matter baseline failure state)
// Byline: Codex · GPT-5 · 2026-08-29 (single-case automatic scope binding)
// Byline: Codex · GPT-5 · 2026-08-29 (Case Bible Sorted default source browser)
// Byline: Codex · GPT-5 · 2026-08-29 (approved inspector and receipt anatomy)
// Byline: Codex · GPT-5 · 2026-08-29 (shared fixed-case shell context)
"use client";

import { AppLink as Link } from "@/lib/router-compat";
import { useEffect, useMemo, useRef, useState } from "react";
import {
  AlertTriangle,
  Check,
  ChevronRight,
  ArrowLeft,
  FileText,
  Loader2,
  Scale,
  ShieldCheck,
  Upload,
} from "lucide-react";

import { AtomicTools } from "@/components/tools/atomic-tools";
import { ContextFlowRail } from "@/components/intake/context-flow-rail";
import { MatterModeSelector } from "@/components/intake/matter-mode-selector";
import { ParserSelectionPanel } from "@/components/intake/parser-selection-panel";
import { SourceExplorer } from "@/components/intake/source-explorer";
import { Button } from "@/components/ui/button";
import {
  ApiError,
  createProfferPreviewEventSource,
  createProfferSourceContext,
  decideProfferHandler,
  decideProfferRepair,
  getProfferPreview,
  inspectProfferSource,
  listProfferSources,
  startProffer,
  uploadProfferSource,
} from "@/lib/api-client";
import type {
  ProfferPreviewEvent,
  ProfferPreviewResponse,
  ProfferParserCandidate,
  ProfferHumanSourceAssertions,
  ProfferSourceContextReceipt,
  ProfferStartResponse,
  ProfferUploadResponse,
  ProfferSourceBrowserResponse,
  ProfferSourceInspection,
  ProfferSourceObject,
} from "@/lib/shared/types";
import { useFixedCase } from "@/lib/fixed-case-context";
import { profferContextFlowComplete } from "@/lib/proffer-context-checkpoints";
import { cn } from "@/lib/utils";

type IntakePhase = "choose" | "ready" | "starting" | "handler_review" | "repair_review" | "review" | "complete" | "error";
type PreviewTab = "source" | "metadata" | "parser";
type OperatorTab = "intake" | "atomic_tools";

const LOCAL_FILE_ACCEPT = ".xml,.json,.txt,.csv,.md,.html,.htm,.pdf,.docx,.zip,.tar,.tgz,.gz,.7z,.rar,.png,.jpg,.jpeg,.gif,.tif,.tiff,.bmp";

const EMPTY_ASSERTIONS: ProfferHumanSourceAssertions = {
  source_class: "unknown",
  source_principal: "",
  other_party: "",
  acquired_at: null,
  acquisition_method: "",
  acquisition_authority: "",
  source_device: "",
  device_custodian: "",
  occurred_start: "",
  occurred_end: "",
  date_certainty: "",
  context: "",
  notes: "",
};

function errorText(error: unknown) {
  return error instanceof ApiError ? error.message : error instanceof Error ? error.message : "The intake request failed";
}

function declaredFormat(source: { name: string }) {
  const extension = source.name.split(".").pop()?.toLowerCase();
  const formats: Record<string, string> = {
    xml: "sms_export_xml",
    json: "message_export_json",
    md: "markdown",
    txt: "delimited_text",
    csv: "delimited_text",
    pdf: "pdf",
    png: "image",
    jpg: "image",
    jpeg: "image",
    gif: "image",
    tif: "image",
    tiff: "image",
    bmp: "image",
    docx: "docx",
    html: "html",
    htm: "html",
    zip: "archive",
    tar: "archive",
    tgz: "archive",
    gz: "archive",
    "7z": "archive",
    rar: "archive",
  };
  return formats[extension ?? ""] ?? "unknown_binary";
}

function bytes(value: number) {
  if (value < 1024) return `${value} bytes`;
  if (value < 1024 * 1024) return `${(value / 1024).toFixed(1)} KB`;
  return `${(value / (1024 * 1024)).toFixed(1)} MB`;
}

const terminalPreviewPhases = new Set(["awaiting_handler_selection", "awaiting_repair_decision", "awaiting_decision", "approved", "rejected", "timed_out", "failed"]);

async function waitForPreview(
  previewHandle: string,
  mode: "TEST" | "REAL",
  attempts = 80,
  ignoredTerminalPhases: ReadonlySet<string> = new Set(),
  onState?: (state: ProfferPreviewResponse) => void,
) {
  let lastState: ProfferPreviewResponse | null = null;
  let lastError: unknown = null;
  for (let attempt = 0; attempt < attempts; attempt += 1) {
    try {
      lastState = await getProfferPreview(previewHandle, mode);
      onState?.(lastState);
      lastError = null;
      if (terminalPreviewPhases.has(lastState.phase) && !ignoredTerminalPhases.has(lastState.phase)) return lastState;
    } catch (requestError) {
      lastError = requestError;
      const transient =
        requestError instanceof ApiError &&
        (requestError.isRetryable || requestError.isNotFound || requestError.isConflict || requestError.status === 422);
      if (!transient) throw requestError;
    }
    await new Promise((resolve) => setTimeout(resolve, 1500));
  }
  if (lastError) throw lastError;
  throw new Error(`The workflow is still processing${lastState ? ` (${lastState.phase})` : ""}. Try again shortly.`);
}

async function fileDigest(file: File) {
  const digest = await crypto.subtle.digest("SHA-256", await file.arrayBuffer());
  return Array.from(new Uint8Array(digest), (value) => value.toString(16).padStart(2, "0")).join("");
}

export function UnifiedIntake() {
  const { mode } = useFixedCase();
  return <UnifiedIntakeMode key={mode} mode={mode} />;
}

function parserCandidateKey(candidate: ProfferParserCandidate) {
  return [candidate.handler_id, candidate.handler_version, candidate.execution_path, candidate.compatibility_ref].join("\u0000");
}

function UnifiedIntakeMode({ mode }: { mode: "TEST" | "REAL" }) {
  const { matter, primaryCourtCase, loading: scopeLoading, error: scopeError } = useFixedCase();
  const [file, setFile] = useState<File | null>(null);
  const [remote, setRemote] = useState<ProfferSourceObject | null>(null);
  const [inspection, setInspection] = useState<ProfferSourceInspection | null>(null);
  const [inspectionLoading, setInspectionLoading] = useState(false);
  const [inspectionError, setInspectionError] = useState<string | null>(null);
  const [sources, setSources] = useState<ProfferSourceBrowserResponse | null>(null);
  const [sourceRootId, setSourceRootId] = useState("");
  const [sourcePrefix, setSourcePrefix] = useState("");
  const [sourceFilter, setSourceFilter] = useState("");
  const [sourceFileTypes, setSourceFileTypes] = useState<string[]>([]);
  const [sourcesLoading, setSourcesLoading] = useState(true);
  const [sourcesError, setSourcesError] = useState<string | null>(null);
  const [digest, setDigest] = useState("");
  const [textPreview, setTextPreview] = useState("");
  const [phase, setPhase] = useState<IntakePhase>("choose");
  const [upload, setUpload] = useState<ProfferUploadResponse | null>(null);
  const [run, setRun] = useState<ProfferStartResponse | null>(null);
  const [preview, setPreview] = useState<ProfferPreviewResponse | null>(null);
  const [workflowEvents, setWorkflowEvents] = useState<ProfferPreviewEvent[]>([]);
  const [checkpointStreamError, setCheckpointStreamError] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [previewTab, setPreviewTab] = useState<PreviewTab>("source");
  const [operatorTab, setOperatorTab] = useState<OperatorTab>("intake");
  const [repairChoice, setRepairChoice] = useState<"original" | null>(null);
  const [repairSubmitting, setRepairSubmitting] = useState(false);
  const [repairDecisionRef, setRepairDecisionRef] = useState<string | null>(null);
  const [assertions, setAssertions] = useState<ProfferHumanSourceAssertions>(EMPTY_ASSERTIONS);
  const [sourceContextReceipt, setSourceContextReceipt] = useState<ProfferSourceContextReceipt | null>(null);
  const [intakeRequestId, setIntakeRequestId] = useState<string | null>(null);
  const [selectedHandlerKey, setSelectedHandlerKey] = useState("");
  const [handlerDecisionRef, setHandlerDecisionRef] = useState<string | null>(null);
  const [handlerSubmitting, setHandlerSubmitting] = useState(false);
  const intakeGenerationRef = useRef(0);

  function updateAssertion<K extends keyof ProfferHumanSourceAssertions>(key: K, value: ProfferHumanSourceAssertions[K]) {
    setAssertions((current) => ({ ...current, [key]: value }));
    setSourceContextReceipt(null);
    setIntakeRequestId(null);
  }

  useEffect(() => {
    intakeGenerationRef.current += 1;
    let cancelled = false;
    const timer = setTimeout(() => {
      setSourcesLoading(true);
      setSourcesError(null);
      listProfferSources({ mode, rootId: sourceRootId || undefined, prefix: sourcePrefix, filter: sourceFilter, fileTypes: sourceFileTypes, pageSize: 100 })
        .then((response) => {
          if (!cancelled) {
            setSources(response);
            setSourcesError(null);
          }
        })
        .catch((requestError) => {
          if (!cancelled) setSourcesError(errorText(requestError));
        })
        .finally(() => {
          if (!cancelled) setSourcesLoading(false);
        });
    }, sourceFilter ? 250 : 0);
    return () => {
      cancelled = true;
      clearTimeout(timer);
    };
  }, [sourcePrefix, sourceFilter, sourceFileTypes, sourceRootId, mode]);

  useEffect(() => {
    if (!run?.preview_handle) return;
    const source = createProfferPreviewEventSource(run.preview_handle, mode);
    const onEvent = (raw: MessageEvent<string>) => {
      try {
        const event = JSON.parse(raw.data) as ProfferPreviewEvent;
        if (event.preview_handle !== run.preview_handle) throw new Error("Checkpoint event did not match this import.");
        if (event.matter_mode !== mode) throw new Error("Checkpoint event crossed the active TEST/REAL boundary.");
        setWorkflowEvents((current) => [...current.filter((item) => item.event_id !== event.event_id), event]
          .sort((left, right) => left.event_id - right.event_id)
          .slice(-100));
        setCheckpointStreamError(null);
      } catch {
        setCheckpointStreamError("Live checkpoint updates are unavailable. Snapshot polling continues.");
      }
    };
    source.addEventListener("proffer.preview", onEvent as EventListener);
    source.onerror = () => setCheckpointStreamError("Live checkpoint updates are unavailable. Snapshot polling continues.");
    return () => {
      source.removeEventListener("proffer.preview", onEvent as EventListener);
      source.close();
    };
  }, [run?.preview_handle, mode]);

  const lines = useMemo(() => textPreview.split(/\r?\n/).filter(Boolean).slice(0, 12), [textPreview]);
  const runtimeParserCandidates = preview?.phase === "awaiting_handler_selection" && preview.recommended_handler
    ? [preview.recommended_handler, ...(preview.alternative_handlers ?? [])]
    : [];
  const selectedParser = runtimeParserCandidates.find((candidate) => parserCandidateKey(candidate) === selectedHandlerKey) ?? null;

  function changeSourcePrefix(nextPrefix: string) {
    setSourcesLoading(true);
    setSourcePrefix(nextPrefix);
  }

  function changeSourceRoot(nextRootId: string) {
    setSourceRootId(nextRootId);
    setSourcePrefix("");
    setSourceFilter("");
    setSourceFileTypes([]);
    setSources(null);
    setSourcesLoading(true);
  }

  function changeSourceFilter(nextFilter: string) {
    setSourcesLoading(true);
    setSourceFilter(nextFilter);
  }

  async function selectFile(selected: File | null) {
    intakeGenerationRef.current += 1;
    const generation = intakeGenerationRef.current;
    setFile(selected);
    setRemote(null);
    setInspection(null);
    setInspectionError(null);
    setAssertions(EMPTY_ASSERTIONS);
    setSourceContextReceipt(null);
    setIntakeRequestId(null);
    setUpload(null);
    setRun(null);
    setPreview(null);
    setWorkflowEvents([]);
    setCheckpointStreamError(null);
    setError(null);
    setPreviewTab("source");
    setRepairChoice(null);
    setRepairDecisionRef(null);
    setSelectedHandlerKey("");
    setHandlerDecisionRef(null);
    if (!selected) {
      setDigest("");
      setTextPreview("");
      setPhase("choose");
      return;
    }
    setPhase("ready");
    const [nextDigest, nextText] = await Promise.all([
      fileDigest(selected),
      selected.type.startsWith("text/") || /\.(md|json|html?|txt|csv|xml)$/i.test(selected.name)
        ? selected.text()
        : Promise.resolve(""),
    ]);
    if (generation !== intakeGenerationRef.current) return;
    setDigest(nextDigest);
    setTextPreview(nextText.slice(0, 250_000));
  }

  async function selectRemote(selected: ProfferSourceObject) {
    intakeGenerationRef.current += 1;
    const generation = intakeGenerationRef.current;
    const sameSelection = remote?.key === selected.key;
    setRemote(selected);
    setFile(null);
    setInspection(null);
    setInspectionError(null);
    setInspectionLoading(true);
    if (!sameSelection) {
      setAssertions(EMPTY_ASSERTIONS);
      setSourceContextReceipt(null);
      setIntakeRequestId(null);
    }
    setDigest("");
    setTextPreview("");
    setUpload(null);
    setRun(null);
    setPreview(null);
    setWorkflowEvents([]);
    setCheckpointStreamError(null);
    setError(null);
    setPreviewTab("source");
    setRepairChoice(null);
    setRepairDecisionRef(null);
    setSelectedHandlerKey("");
    setHandlerDecisionRef(null);
    setPhase("ready");
    try {
      const activeRootId = sourceRootId || sources?.active_root_id;
      if (!activeRootId) throw new Error("The selected source has no confirmed R2 source location.");
      const inspected = await inspectProfferSource(selected, mode, activeRootId);
      if (generation !== intakeGenerationRef.current) return;
      if (inspected.key !== selected.key) throw new Error("The inspected source did not match the selection.");
      setInspection(inspected);
      setDigest(inspected.sha256);
      setTextPreview(inspected.preview_text);
    } catch (requestError) {
      if (generation !== intakeGenerationRef.current) return;
      setInspectionError(errorText(requestError));
    } finally {
      if (generation === intakeGenerationRef.current) setInspectionLoading(false);
    }
  }

  async function loadMoreSources() {
    if (!sources?.continuation_token) return;
    const generation = intakeGenerationRef.current;
    setSourcesLoading(true);
    try {
      const next = await listProfferSources({
        mode,
        rootId: sourceRootId || undefined,
        prefix: sourcePrefix,
        filter: sourceFilter,
        fileTypes: sourceFileTypes,
        continuationToken: sources.continuation_token,
        pageSize: sources.page_size,
      });
      if (generation !== intakeGenerationRef.current) return;
      setSources({ ...next, prefixes: [...sources.prefixes, ...next.prefixes], objects: [...sources.objects, ...next.objects] });
    } catch (requestError) {
      if (generation !== intakeGenerationRef.current) return;
      setSourcesError(errorText(requestError));
    } finally {
      if (generation === intakeGenerationRef.current) setSourcesLoading(false);
    }
  }

  async function start() {
    if ((!file && !remote) || !matter || !primaryCourtCase) return;
    const generation = intakeGenerationRef.current;
    setPhase("starting");
    setError(null);
    setRepairChoice(null);
    setRepairDecisionRef(null);
    try {
      const sealed = file ? await uploadProfferSource(file, mode) : null;
      if (generation !== intakeGenerationRef.current) return;
      setUpload(sealed);
      const selected = file ?? remote;
      if (!selected) return;
      const requestId = intakeRequestId ?? `proffer-${matter.id}-${crypto.randomUUID()}`;
      setIntakeRequestId(requestId);
      const sourceRef = sealed?.acquisition_ref ?? inspection?.source_ref;
      if (!sourceRef) throw new Error("The selected source has no inspected acquisition reference.");
      const sourceContext = sourceContextReceipt ?? await createProfferSourceContext({
        request_id: requestId,
        source_ref: sourceRef,
        matter_id: matter.id,
        court_case_id: primaryCourtCase.id,
        observed_source: inspection ? {
          key: inspection.key,
          name: inspection.name,
          byte_length: inspection.byte_length,
          etag: inspection.etag,
          preview_sha256: inspection.sha256,
          verification_state: "preview_only",
        } : {
          key: file?.name ?? "local-source",
          name: file?.name ?? "local-source",
          byte_length: sealed?.byte_length ?? file?.size ?? 0,
          etag: `sha256:${sealed?.sha256 ?? digest}`,
          preview_sha256: sealed?.sha256 ?? digest,
          verification_state: "preview_only",
        },
        assertions: {
          ...assertions,
          acquired_at: assertions.acquired_at ? new Date(assertions.acquired_at).toISOString() : null,
        },
        change_reason: "Operator supplied source context during intake",
        matter_mode: mode,
      });
      if (generation !== intakeGenerationRef.current) return;
      setSourceContextReceipt(sourceContext);
      const started = await startProffer({
        request_id: requestId,
        source_ref: sourceRef,
        declared_format: declaredFormat(selected),
        parser_options_ref: "pending-handler-selection/v1",
        matter_id: matter.id,
        court_case_id: primaryCourtCase.id,
        source_context_ref: sourceContext.source_context_ref,
        matter_mode: mode,
      });
      if (generation !== intakeGenerationRef.current) return;
      setRun(started);
      setWorkflowEvents([]);
      setCheckpointStreamError(null);

      const state = await waitForPreview(started.preview_handle, mode, 80, new Set(), (next) => {
        if (generation === intakeGenerationRef.current) setPreview(next);
      });
      if (generation !== intakeGenerationRef.current) return;
      setPreview(state);
      setPhase(phaseForPreview(state));
      if (state.phase === "failed") setError(state.reason || "The context import stopped before the full preview was ready.");
    } catch (requestError) {
      if (generation !== intakeGenerationRef.current) return;
      setError(errorText(requestError));
      setPhase("error");
    }
  }

  async function confirmRepairDecision() {
    if (!run || !preview?.repair_assessment?.review_required || repairChoice !== "original") return;
    setRepairSubmitting(true);
    const generation = intakeGenerationRef.current;
    setError(null);
    try {
      const decision = await decideProfferRepair(run.preview_handle, mode, {
        approved: true,
        apply_repair: false,
      });
      if (generation !== intakeGenerationRef.current) return;
      if (decision.preview_handle !== run.preview_handle) {
        throw new Error("The repair decision response did not match this preview.");
      }
      setRepairDecisionRef(decision.decision_ref);
      setPhase("starting");
      const state = await waitForPreview(run.preview_handle, mode, 80, new Set(["awaiting_repair_decision"]), (next) => {
        if (generation === intakeGenerationRef.current) setPreview(next);
      });
      if (generation !== intakeGenerationRef.current) return;
      setPreview(state);
      setPhase(phaseForPreview(state));
      if (state.phase === "failed") setError(state.reason || "The context import stopped before the full preview was ready.");
    } catch (requestError) {
      if (generation !== intakeGenerationRef.current) return;
      setError(errorText(requestError));
      setPhase("repair_review");
    } finally {
      if (generation === intakeGenerationRef.current) setRepairSubmitting(false);
    }
  }

  async function confirmHandlerSelection() {
    if (!run || preview?.phase !== "awaiting_handler_selection" || !preview.handler_recommendation_ref || !selectedParser) return;
    const generation = intakeGenerationRef.current;
    setHandlerSubmitting(true);
    setError(null);
    try {
      const decision = await decideProfferHandler(run.preview_handle, mode, {
        recommendation_ref: preview.handler_recommendation_ref,
        handler_id: selectedParser.handler_id,
        handler_version: selectedParser.handler_version,
        execution_path: selectedParser.execution_path,
        compatibility_ref: selectedParser.compatibility_ref,
      });
      if (generation !== intakeGenerationRef.current) return;
      setHandlerDecisionRef(decision.decision_ref);
      setPhase("starting");
      const state = await waitForPreview(run.preview_handle, mode, 80, new Set(["awaiting_handler_selection"]), (next) => {
        if (generation === intakeGenerationRef.current) setPreview(next);
      });
      if (generation !== intakeGenerationRef.current) return;
      setPreview(state);
      setPhase(phaseForPreview(state));
      if (state.phase === "failed") setError(state.reason || "The context import stopped before the full preview was ready.");
    } catch (requestError) {
      if (generation !== intakeGenerationRef.current) return;
      setError(errorText(requestError));
      setPhase("handler_review");
    } finally {
      if (generation === intakeGenerationRef.current) setHandlerSubmitting(false);
    }
  }

  function reset() {
    intakeGenerationRef.current += 1;
    setFile(null);
    setRemote(null);
    setInspection(null);
    setInspectionLoading(false);
    setInspectionError(null);
    setDigest("");
    setTextPreview("");
    setUpload(null);
    setRun(null);
    setPreview(null);
    setWorkflowEvents([]);
    setCheckpointStreamError(null);
    setError(null);
    setPreviewTab("source");
    setRepairChoice(null);
    setRepairDecisionRef(null);
    setAssertions(EMPTY_ASSERTIONS);
    setSourceContextReceipt(null);
    setIntakeRequestId(null);
    setSelectedHandlerKey("");
    setHandlerDecisionRef(null);
    setPhase("choose");
  }

  const selectedSource = file ?? remote;
  const selectedSize = file?.size ?? remote?.byte_length ?? 0;
  const selectedSourceRef = upload?.acquisition_ref ?? inspection?.source_ref ?? remote?.source_ref ?? null;
  const contextFlowComplete = profferContextFlowComplete(preview?.receipts, preview?.checkpoints);

  return (
    <div className="min-h-full">
      <nav className="flex min-h-12 items-end gap-6 border-b bg-card px-6" aria-label="Operator execution tabs" role="tablist">
        <button type="button" role="tab" aria-selected={operatorTab === "intake"} onClick={() => setOperatorTab("intake")} className={cn("h-12 border-b-2 px-1 text-xs font-semibold", operatorTab === "intake" ? "border-primary text-primary" : "border-transparent text-muted-foreground hover:text-foreground")}>Intake workflow</button>
        <button type="button" role="tab" aria-selected={operatorTab === "atomic_tools"} onClick={() => setOperatorTab("atomic_tools")} className={cn("h-12 border-b-2 px-1 text-xs font-semibold", operatorTab === "atomic_tools" ? "border-primary text-primary" : "border-transparent text-muted-foreground hover:text-foreground")}>Atomic Tools</button>
      </nav>
      {operatorTab === "atomic_tools" ? (
        <div className="px-5 py-5 lg:px-8"><AtomicTools embedded /></div>
      ) : (
      <div>
      <section className="border-b bg-card px-6 py-5">
        <div className="flex flex-wrap items-start justify-between gap-4">
          <div>
            <p className="platform-kicker mb-1">Context operations desk</p>
            <h1 className="text-xl font-semibold tracking-tight">Import source context</h1>
            <p className="mt-1 text-sm text-muted-foreground">Choose a source, inspect it, then start the context-only workflow for the fixed case.</p>
          </div>
          <div className="flex flex-wrap items-center justify-end gap-2">
            <MatterModeSelector />
            <div className="flex items-center gap-2 border bg-background px-3 py-2 text-xs text-muted-foreground">
              <ShieldCheck className="h-4 w-4" /> PostgreSQL authority preserved
            </div>
          </div>
        </div>
      </section>

      <ContextFlowRail
        started={Boolean(run)}
        phase={preview?.phase ?? (phase === "error" ? "failed" : undefined)}
        receipts={preview?.receipts}
        checkpoints={preview?.checkpoints}
        events={workflowEvents}
      />
      {checkpointStreamError && run && <p className="border-b bg-card px-6 py-2 text-xs text-muted-foreground" role="status">{checkpointStreamError}</p>}

      {(scopeError || error) && (
        <div className="flex items-center gap-2 border-b border-[#b5433b] bg-[#fbe9e7] px-6 py-3 text-sm text-[#8f302a]" role="alert">
          <AlertTriangle className="h-4 w-4" /> {scopeError || error}
        </div>
      )}

      <div className="grid min-h-[620px] lg:grid-cols-[minmax(0,1fr)_330px]">
        <main className="min-w-0 space-y-5 p-6">
          {phase === "repair_review" && preview?.repair_assessment && (
            <section className="platform-panel overflow-hidden" aria-label="Repair review gate">
              <header className="flex flex-wrap items-start justify-between gap-4 border-b px-5 py-4">
                <div>
                  <p className="platform-kicker mb-1">Repair review required</p>
                  <h2 className="text-xl font-semibold">Choose how this source continues</h2>
                  <p className="mt-1 max-w-2xl text-sm leading-6 text-muted-foreground">The durable workflow paused before parsing. The source preview remains available below. Nothing is repaired or replaced until you confirm an allowed choice.</p>
                </div>
                <span className="border border-[#c58214] bg-[#fff4dd] px-2 py-1 text-[10px] font-semibold uppercase text-[#684b18] dark:bg-[#43351f] dark:text-[#ffe0a6]">Review required</span>
              </header>

              <dl className="grid gap-px border-b bg-border text-xs sm:grid-cols-3">
                <div className="bg-card p-4"><dt className="text-muted-foreground">Why it stopped</dt><dd className="mt-1 text-sm font-semibold">{preview.reason || "The detector requested human review before parsing."}</dd></div>
                <div className="bg-card p-4"><dt className="text-muted-foreground">Assessment</dt><dd className="mt-1 break-all font-mono text-[10px]">{preview.repair_assessment.assessment_ref}</dd></div>
                <div className="bg-card p-4"><dt className="text-muted-foreground">Source version</dt><dd className="mt-1 break-all font-mono text-[10px]">{preview.repair_assessment.source_version_ref}</dd></div>
              </dl>

              <div className="space-y-4 p-5">
                <div>
                  <p className="platform-rule-title mb-2">Owner decision</p>
                  <button type="button" onClick={() => setRepairChoice("original")} aria-pressed={repairChoice === "original"} className={cn("w-full border p-4 text-left hover:bg-accent", repairChoice === "original" && "border-primary bg-accent ring-1 ring-primary")}>
                    <strong className="block text-sm">Override repair and use the original source</strong>
                    <span className="mt-1 block text-xs leading-5 text-muted-foreground">Continue with the sealed original bytes. No derived repair is applied, and the override is recorded against this assessment.</span>
                  </button>
                  <p className="mt-2 text-xs leading-5 text-muted-foreground">No compatible derived-repair action was supplied by the workflow. The application will not invent or silently run one.</p>
                </div>

                {repairChoice === "original" && (
                  <div className="flex flex-wrap items-center justify-between gap-4 border-l-4 border-l-primary bg-accent/40 p-4">
                    <div><strong className="block text-sm">Confirm use of the original</strong><p className="mt-1 text-xs leading-5 text-muted-foreground">This records a typed decision against the same opaque preview handle and resumes its durable workflow.</p></div>
                    <Button onClick={() => void confirmRepairDecision()} disabled={repairSubmitting}>{repairSubmitting ? <Loader2 className="h-4 w-4 animate-spin" /> : <Check className="h-4 w-4" />} Confirm and continue</Button>
                  </div>
                )}
              </div>
            </section>
          )}

          {!file && !remote ? (
            <div className="space-y-4">
              <SourceExplorer
                response={sources}
                loading={sourcesLoading}
                error={sourcesError}
                rootId={sourceRootId}
                prefix={sourcePrefix}
                query={sourceFilter}
                fileTypes={sourceFileTypes}
                onRootChange={changeSourceRoot}
                onPrefixChange={changeSourcePrefix}
                onQueryChange={changeSourceFilter}
                onFileTypesChange={setSourceFileTypes}
                onSelect={(source) => void selectRemote(source)}
                onLoadMore={() => void loadMoreSources()}
              />
              <div className="platform-panel mx-auto max-w-[1180px] px-5 py-4 text-sm">
                <span className="text-muted-foreground">Or add a source from this device: </span>
                <label className="cursor-pointer font-semibold text-primary hover:underline"><Upload className="mr-1 inline h-4 w-4" />Choose local file<input accept={LOCAL_FILE_ACCEPT} className="sr-only" type="file" onChange={(event) => void selectFile(event.target.files?.[0] ?? null)} /></label>
                <span className="ml-2 text-xs text-muted-foreground">XML, JSON, text, CSV, Markdown, HTML, PDF, Word, or ZIP/archive</span>
              </div>
            </div>
          ) : (
            <div className="platform-panel overflow-hidden">
              <div className="flex flex-wrap items-center gap-3 border-b px-5 py-4">
                <div className="grid h-10 w-10 place-items-center border bg-accent text-accent-foreground"><FileText className="h-5 w-5" /></div>
                <div className="min-w-0 flex-1">
                  <p className="platform-rule-title">Selected source</p>
                  <strong className="block truncate text-sm">{file?.name ?? remote?.name}</strong>
                  <span className="text-xs text-muted-foreground">{declaredFormat(file ?? remote!)} · {bytes(file?.size ?? remote?.byte_length ?? 0)}</span>
                </div>
                <Button variant="outline" onClick={reset}><ArrowLeft className="h-4 w-4" /> Back to sources</Button>
              </div>

              <div className="flex min-h-11 gap-5 border-b px-5" role="tablist" aria-label="Source inspection">
                {(["source", "metadata", "parser"] as const).map((tab) => (
                  <button
                    key={tab}
                    type="button"
                    role="tab"
                    aria-selected={previewTab === tab}
                    onClick={() => setPreviewTab(tab)}
                    className={`border-b-2 px-1 text-xs font-semibold capitalize ${previewTab === tab ? "border-primary text-primary" : "border-transparent text-muted-foreground hover:text-foreground"}`}
                  >
                    {tab === "source" ? "Source preview" : tab}
                  </button>
                ))}
              </div>

              <div className="min-h-[330px] border-b px-5 py-4">
                {previewTab === "source" && (
                  <section aria-label="Source preview">
                    <p className="platform-rule-title mb-3">Source preview</p>
                    {remote && inspectionLoading ? (
                      <div className="flex min-h-[270px] items-center justify-center gap-2 border bg-background text-sm text-muted-foreground"><Loader2 className="h-4 w-4 animate-spin" /> Reading and hashing {bytes(remote.byte_length)}</div>
                    ) : remote && inspectionError ? (
                      <div className="border border-[#a84039] bg-[#fff0ee] px-5 py-8 text-sm text-[#8f302a] dark:bg-[#3a2422] dark:text-[#ffb5ae]"><strong className="block">Preview could not be opened</strong><p className="mt-2">{inspectionError}</p><Button className="mt-4" variant="outline" onClick={() => void selectRemote(remote)}>Try inspection again</Button></div>
                    ) : remote && inspection?.preview_kind === "pdf" && inspection.preview_url ? (
                      <iframe className="h-[560px] w-full border bg-white" src={inspection.preview_url} title={`Read-only preview of ${inspection.name}`} />
                    ) : remote && inspection?.preview_kind === "image" && inspection.preview_url ? (
                      <div className="grid min-h-[270px] place-items-center border bg-background p-3"><img className="max-h-[520px] max-w-full object-contain" src={inspection.preview_url} alt={`Read-only preview of ${inspection.name}`} /></div>
                    ) : lines.length ? (
                      <div className="max-h-[270px] overflow-auto border bg-background font-mono text-[11px] leading-5" role="region" aria-label="Selected source content" tabIndex={0}>
                        {lines.map((line, index) => <div key={`${index}-${line.slice(0, 24)}`} className="grid grid-cols-[42px_1fr] border-b px-3 py-2 last:border-b-0"><span className="text-muted-foreground">{String(index + 1).padStart(2, "0")}</span><span className="break-words">{line}</span></div>)}
                      </div>
                    ) : (
                      <div className="border bg-background px-4 py-12 text-center text-sm text-muted-foreground">This format does not have an inline renderer. Its preview checksum and source metadata are still available.</div>
                    )}
                  </section>
                )}

                {previewTab === "metadata" && selectedSource && (
                  <section aria-label="Source metadata">
                    <p className="platform-rule-title mb-3">Observed source metadata</p>
                    <dl className="grid gap-px border bg-border sm:grid-cols-2">
                      <div className="bg-card p-4"><dt className="text-[10px] uppercase text-muted-foreground">Name</dt><dd className="mt-1 break-words text-sm font-semibold">{selectedSource.name}</dd></div>
                      <div className="bg-card p-4"><dt className="text-[10px] uppercase text-muted-foreground">Declared format</dt><dd className="mt-1 font-mono text-xs">{declaredFormat(selectedSource)}</dd></div>
                      <div className="bg-card p-4"><dt className="text-[10px] uppercase text-muted-foreground">Source location</dt><dd className="mt-1 text-sm">{remote ? `${remote.source_location.toUpperCase()} · ${remote.bucket}` : "This device"}</dd></div>
                      <div className="bg-card p-4"><dt className="text-[10px] uppercase text-muted-foreground">Declared size</dt><dd className="mt-1 text-sm">{bytes(selectedSize)}</dd></div>
                      {remote && <div className="bg-card p-4"><dt className="text-[10px] uppercase text-muted-foreground">File kind</dt><dd className="mt-1 text-sm">{remote.file_kind}{remote.archive_format ? ` · ${remote.archive_format}` : ""}</dd></div>}
                      {remote && <div className="bg-card p-4"><dt className="text-[10px] uppercase text-muted-foreground">Media type</dt><dd className="mt-1 text-sm">{remote.media_type || "Not reported"}</dd></div>}
                      <div className="bg-card p-4 sm:col-span-2"><dt className="text-[10px] uppercase text-muted-foreground">Preview checksum</dt><dd className="mt-1 break-all font-mono text-[11px]">{inspectionLoading ? "Reading and hashing now" : upload?.sha256 || digest || "Computing preview"}</dd><p className="mt-2 text-[11px] leading-5 text-muted-foreground">Read-only preview identity. The context workflow verifies the source bytes independently before processing.</p></div>
                      {remote?.last_modified && <div className="bg-card p-4"><dt className="text-[10px] uppercase text-muted-foreground">Object modified</dt><dd className="mt-1 text-sm">{new Date(remote.last_modified).toLocaleString()}</dd></div>}
                      {selectedSourceRef && <div className="bg-card p-4 sm:col-span-2"><dt className="text-[10px] uppercase text-muted-foreground">Acquisition reference</dt><dd className="mt-1 break-all font-mono text-[11px]">{selectedSourceRef}</dd></div>}
                    </dl>

                    <div className="mt-5 border bg-card p-5">
                      <div className="flex flex-wrap items-start justify-between gap-3">
                        <div><p className="platform-rule-title">Add what you already know</p><p className="mt-1 text-xs leading-5 text-muted-foreground">These are your assertions, kept separate from observed source facts. Starting intake records them with your authenticated identity and a durable receipt.</p></div>
                        {sourceContextReceipt && <span className="border border-[#2f9d67] bg-[#e2f3e9] px-2 py-1 text-[10px] font-semibold uppercase text-[#17794b]">Recorded · revision {sourceContextReceipt.revision}</span>}
                      </div>
                      <div className="mt-5 grid gap-4 sm:grid-cols-2">
                        <label className="grid gap-1.5 text-xs font-semibold">Source relationship
                          <select className="h-10 border bg-background px-3 font-normal" value={assertions.source_class} onChange={(event) => updateAssertion("source_class", event.target.value as ProfferHumanSourceAssertions["source_class"])}>
                            <option value="unknown">Unknown / not sure</option><option value="first_party">First party / mine</option><option value="acquired_third_party">Acquired third party</option>
                          </select>
                        </label>
                        <label className="grid gap-1.5 text-xs font-semibold">Other party
                          <input className="h-10 border bg-background px-3 font-normal" value={assertions.other_party} onChange={(event) => updateAssertion("other_party", event.target.value)} placeholder="Person, account, organization, or opposing party" />
                        </label>
                        <label className="grid gap-1.5 text-xs font-semibold">Source principal
                          <input className="h-10 border bg-background px-3 font-normal" value={assertions.source_principal} onChange={(event) => updateAssertion("source_principal", event.target.value)} placeholder="Account, phone, device, or person this came from" />
                        </label>
                        <label className="grid gap-1.5 text-xs font-semibold">How acquired
                          <select className="h-10 border bg-background px-3 font-normal" value={assertions.acquisition_method} onChange={(event) => updateAssertion("acquisition_method", event.target.value as ProfferHumanSourceAssertions["acquisition_method"])}>
                            <option value="">Not entered</option><option value="own_device">Own device</option><option value="household_device">Household device</option><option value="voluntary_third_party">Provided voluntarily</option><option value="legal_process">Legal process</option><option value="public_source">Public source</option><option value="unknown">Unknown</option>
                          </select>
                        </label>
                        <label className="grid gap-1.5 text-xs font-semibold">When acquired
                          <input type="datetime-local" className="h-10 border bg-background px-3 font-normal" value={assertions.acquired_at ?? ""} onChange={(event) => updateAssertion("acquired_at", event.target.value || null)} />
                        </label>
                        <label className="grid gap-1.5 text-xs font-semibold">Acquisition authority
                          <select className="h-10 border bg-background px-3 font-normal" value={assertions.acquisition_authority} onChange={(event) => updateAssertion("acquisition_authority", event.target.value as ProfferHumanSourceAssertions["acquisition_authority"])}>
                            <option value="">Not entered</option><option value="device_owner">Device owner</option><option value="parent_guardian">Parent / guardian</option><option value="account_holder">Account holder</option><option value="consent_given">Consent given</option><option value="court_order">Court order</option><option value="unclear">Unclear</option>
                          </select>
                        </label>
                        <label className="grid gap-1.5 text-xs font-semibold">Known date — start
                          <input type="date" className="h-10 border bg-background px-3 font-normal" value={assertions.occurred_start} onChange={(event) => updateAssertion("occurred_start", event.target.value)} />
                        </label>
                        <label className="grid gap-1.5 text-xs font-semibold">Known date — end
                          <input type="date" className="h-10 border bg-background px-3 font-normal" value={assertions.occurred_end} onChange={(event) => updateAssertion("occurred_end", event.target.value)} />
                        </label>
                        <label className="grid gap-1.5 text-xs font-semibold">Date certainty
                          <select className="h-10 border bg-background px-3 font-normal" value={assertions.date_certainty} onChange={(event) => updateAssertion("date_certainty", event.target.value as ProfferHumanSourceAssertions["date_certainty"])}>
                            <option value="">Not entered</option><option value="exact">Exact</option><option value="approximate">Approximate</option><option value="range">Date range</option><option value="unknown">Unknown</option>
                          </select>
                        </label>
                        <label className="grid gap-1.5 text-xs font-semibold">Source device
                          <input className="h-10 border bg-background px-3 font-normal" value={assertions.source_device} onChange={(event) => updateAssertion("source_device", event.target.value)} placeholder="Device or storage source" />
                        </label>
                        <label className="grid gap-1.5 text-xs font-semibold">Device custodian
                          <input className="h-10 border bg-background px-3 font-normal" value={assertions.device_custodian} onChange={(event) => updateAssertion("device_custodian", event.target.value)} placeholder="Who controlled the device" />
                        </label>
                        <label className="grid gap-1.5 text-xs font-semibold sm:col-span-2">Context
                          <textarea className="min-h-24 border bg-background p-3 font-normal" value={assertions.context} onChange={(event) => updateAssertion("context", event.target.value)} placeholder="What this source is, why it matters, and anything the parser cannot know" />
                        </label>
                        <label className="grid gap-1.5 text-xs font-semibold sm:col-span-2">Notes
                          <textarea className="min-h-20 border bg-background p-3 font-normal" value={assertions.notes} onChange={(event) => updateAssertion("notes", event.target.value)} placeholder="Collection notes, limitations, or follow-up needed" />
                        </label>
                      </div>
                    </div>
                  </section>
                )}

                {previewTab === "parser" && (
                  <ParserSelectionPanel
                    inspection={inspection}
                    preview={preview}
                    selectedCandidateKey={selectedHandlerKey}
                    handlerDecisionRef={handlerDecisionRef}
                    submitting={handlerSubmitting}
                    onSelect={(candidate) => setSelectedHandlerKey(parserCandidateKey(candidate))}
                    onRecordDecision={() => void confirmHandlerSelection()}
                  />
                )}
              </div>

              <div className="flex flex-col gap-3 border-t bg-card px-5 py-4 sm:flex-row sm:items-center">
                {phase === "starting" && run ? (
                  <><div className="flex-1 text-xs leading-5 text-muted-foreground" role="status">The workflow is processing the source and updating the six context checkpoints. It will pause here if an explicit handler or repair decision is needed.</div><Button disabled><Loader2 className="h-4 w-4 animate-spin" /> Processing context</Button></>
                ) : phase === "handler_review" && run ? (
                  <><div className="flex-1 text-xs leading-5 text-muted-foreground">The durable workflow is waiting for the confirmed parser decision. Review and record it in the Parser tab.</div><Button type="button" onClick={() => setPreviewTab("parser")}>Open parser decision</Button></>
                ) : phase === "review" && run && contextFlowComplete ? (
                  <>
                    <div className="flex-1 text-xs leading-5 text-muted-foreground">Review the normalized messages, provenance locators, and required receipts before deciding. Decisions are available only in the correlated pipeline preview.</div>
                    <Button asChild><Link data-testid="open-proffer-preview" href={`/evidence/preview?mode=${mode}&preview_handle=${encodeURIComponent(run.preview_handle)}`}>Review messages and decide <ChevronRight className="h-4 w-4" /></Link></Button>
                  </>
                ) : phase === "review" && run ? (
                  <><div className="flex-1 text-xs leading-5 text-muted-foreground" role="status">The full preview is locked until all six context-processing checkpoints are complete.</div><Button disabled>Full preview locked</Button></>
                ) : phase === "complete" ? (
                  <><div className="flex-1 text-sm"><strong className="capitalize">{preview?.phase ?? "Decision signaled"}</strong><p className="text-xs text-muted-foreground">The result below was read back from the durable workflow.</p></div><Button variant="outline" onClick={reset}>Start another intake</Button></>
                ) : (
                  <><div className="flex-1 text-xs text-muted-foreground">{matter && !primaryCourtCase ? "The fixed case needs its primary proceeding restored before context intake can start." : !file && !remote ? "Choose a local file or an R2 source to begin." : remote && !inspection ? "The selected R2 source must finish inspection before intake can start." : `Ready to start in ${mode} mode. The workflow will inspect content and pause for explicit handler selection.`}</div><Button disabled={!matter || !primaryCourtCase || (!file && !remote) || phase === "starting" || inspectionLoading || Boolean(remote && !inspection)} onClick={() => void start()} className="min-w-56">{phase === "starting" ? <Loader2 className="h-4 w-4 animate-spin" /> : <Upload className="h-4 w-4" />} Start {mode} context intake <ChevronRight className="h-4 w-4" /></Button></>
                )}
              </div>

              {phase === "complete" && run && (
                <section className="border-l-4 border-l-[#2f9d67] bg-card p-5" aria-label="Intake execution receipt">
                  <div className="flex flex-wrap items-start justify-between gap-3">
                    <div><p className="platform-kicker mb-1">Execution receipt</p><h2 className="text-lg font-semibold capitalize">{preview?.phase.replaceAll("_", " ") ?? "Decision recorded"}</h2><p className="mt-1 text-xs text-muted-foreground">Server-returned preview identity and latest durable workflow phase.</p></div>
                    <span className="border border-[#2f9d67] bg-[#e2f3e9] px-2 py-1 text-[10px] font-semibold uppercase text-[#17794b] dark:bg-[#203d31] dark:text-[#72d9a1]">Live workflow read-back</span>
                  </div>
                  <dl className="mt-5 grid gap-px border bg-border sm:grid-cols-2">
                    <div className="bg-card p-4 sm:col-span-2"><dt className="text-[10px] uppercase text-muted-foreground">Preview handle</dt><dd className="mt-1 break-all font-mono text-[11px]">{run.preview_handle}</dd></div>
                    <div className="bg-card p-4"><dt className="text-[10px] uppercase text-muted-foreground">Source</dt><dd className="mt-1 break-words text-xs">{selectedSource?.name}</dd></div>
                    <div className="bg-card p-4"><dt className="text-[10px] uppercase text-muted-foreground">Authority boundary</dt><dd className="mt-1 text-xs">Context only; not evidence</dd></div>
                  </dl>
                  {contextFlowComplete ? (
                    <Button asChild variant="outline" className="mt-4">
                      <Link href={`/evidence/preview?mode=${mode}&preview_handle=${encodeURIComponent(run.preview_handle)}`}>Open pipeline preview</Link>
                    </Button>
                  ) : <p className="mt-4 text-xs text-muted-foreground" role="status">The full preview remains locked until all six context-processing checkpoints are complete.</p>}
                </section>
              )}
            </div>
          )}
        </main>

        <aside className="border-l bg-card p-5">
          <section className="border-b pb-5">
            <p className="platform-rule-title mb-3">Fixed case</p>
            {scopeLoading ? (
              <div className="flex items-center gap-2 text-xs text-muted-foreground"><Loader2 className="h-3.5 w-3.5 animate-spin" /> Loading case identity</div>
            ) : matter ? (
              <div className="space-y-1 text-xs"><strong className="block text-sm">{matter.title}</strong><span className="block text-muted-foreground">{matter.partition_keys.join(", ") || "No partition configured"}</span>{primaryCourtCase && <span className="flex items-center gap-1 text-muted-foreground"><Scale className="h-3.5 w-3.5" /> {primaryCourtCase.caption}</span>}</div>
            ) : (
              <div className="flex items-start gap-2 text-xs text-[#8f302a]"><AlertTriangle className="mt-0.5 h-3.5 w-3.5 shrink-0" /> Case identity unavailable. Intake remains blocked.</div>
            )}
          </section>

          <section className="border-b py-5">
            <p className="platform-rule-title mb-3">Integrity preview</p>
            <dl className="space-y-3 text-xs">
              <div><dt className="text-muted-foreground">Preview SHA-256</dt><dd className="mt-1 break-all font-mono text-[10px]">{inspectionLoading ? "Hashing now" : upload?.sha256 || digest || "Choose a source"}</dd></div>
              <div className="grid grid-cols-2 gap-3"><div><dt className="text-muted-foreground">Source size</dt><dd>{file ? bytes(file.size) : remote ? bytes(remote.byte_length) : "—"}</dd></div><div><dt className="text-muted-foreground">Inspected size</dt><dd>{inspection ? bytes(inspection.byte_length) : upload ? bytes(upload.byte_length) : inspectionLoading ? "Reading" : "—"}</dd></div></div>
              {upload && <div><dt className="text-muted-foreground">Acquisition reference</dt><dd className="mt-1 break-all font-mono text-[10px]">{upload.acquisition_ref}</dd></div>}
            </dl>
          </section>

          <section className="border-b py-5">
            <p className="platform-rule-title mb-3">Workflow receipt</p>
            {run ? <dl className="space-y-3 text-xs"><div><dt className="text-muted-foreground">Preview handle</dt><dd className="break-all font-mono text-[10px]">{run.preview_handle}</dd></div><div><dt className="text-muted-foreground">Phase</dt><dd className="capitalize">{preview?.phase.replaceAll("_", " ") ?? phase}</dd></div>{repairDecisionRef && <div><dt className="text-muted-foreground">Repair decision</dt><dd className="break-all font-mono text-[10px]">{repairDecisionRef}</dd></div>}</dl> : <p className="text-xs leading-5 text-muted-foreground">A receipt appears after the server accepts the context import and starts its durable workflow.</p>}
          </section>

          <section className="pt-5">
            <div className="flex gap-2 border border-[#c58214] bg-[#fff4dd] p-3 text-[#684b18] dark:border-[#d9aa52] dark:bg-[#2f281d] dark:text-[#ffe0a6]">
              <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" />
              <div><strong className="block text-xs">This preview is not evidence.</strong><p className="mt-1 text-[11px] leading-5">Approval resumes the governed workflow. It does not independently establish a fact or alter an approved evidence record.</p></div>
            </div>
          </section>
        </aside>
      </div>
      </div>
      )}
    </div>
  );
}

function phaseForPreview(state: ProfferPreviewResponse): IntakePhase {
  if (state.phase === "awaiting_handler_selection") return "handler_review";
  if (state.phase === "awaiting_repair_decision" && state.repair_assessment?.review_required) return "repair_review";
  if (state.phase === "awaiting_decision") return "review";
  if (state.phase === "failed") return "error";
  return "complete";
}
