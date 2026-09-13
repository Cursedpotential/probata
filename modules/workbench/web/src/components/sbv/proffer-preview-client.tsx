// Byline: Codex · GPT-5.6 · 2026-09-12 (hydrate deep-linked preview mode and handle atomically)
"use client";

import { ChevronLeft, CircleDot, FileText, Loader2, RefreshCw } from "lucide-react";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { toast } from "sonner";

import { ProfferOperatorPreview } from "@/components/sbv/proffer-operator-preview";
import { ContextFlowRail } from "@/components/intake/context-flow-rail";
import { MatterModeSelector } from "@/components/intake/matter-mode-selector";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  createProfferPreviewEventSource,
  createProfferPotentialPromotionFlag,
  decideProffer,
  decideProfferHandler,
  decideProfferRepair,
  getProfferOperatorSnapshot,
  getProfferPreviewContent,
  getProfferPreview,
  getProfferPreviewMessages,
  listProfferProposalResources,
  listProfferPotentialPromotionFlags,
} from "@/lib/api-client";
import { PROFFER_CONTEXT_CHECKPOINTS, profferContextFlowComplete } from "@/lib/proffer-context-checkpoints";
import { useFixedCase } from "@/lib/fixed-case-context";
import { AppLink } from "@/lib/router-compat";
import type {
  ProfferPreviewEvent,
  ProfferPreviewMessage,
  ProfferPreviewParticipant,
  ProfferPreviewResponse,
  ProfferOperatorSnapshot,
  ProfferParserCandidate,
  ProfferContentResponse,
  ProfferPotentialPromotionFlag,
  ProfferPotentialPromotionScope,
  ProfferProposalResource,
} from "@/lib/shared/types";

function initialHandle(mode: "TEST" | "REAL") {
  if (typeof window === "undefined") return "";
  const query = new URLSearchParams(window.location.search);
  if (query.get("mode") !== mode) return "";
  return (query.get("resource") ?? query.get("preview_handle") ?? query.get("attempt"))?.trim() ?? "";
}

function createdAt(value: string) {
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? value : parsed.toLocaleString();
}

export function ProfferPreviewClient() {
  const { mode } = useFixedCase();
  return <ModeScopedPreviewClient key={mode} mode={mode} />;
}

function ModeScopedPreviewClient({ mode }: { mode: "TEST" | "REAL" }) {
  const [initialUrlHandle] = useState(() => initialHandle(mode));
  const [previewHandle, setPreviewHandle] = useState(initialUrlHandle);
  const [resources, setResources] = useState<ProfferProposalResource[]>([]);
  const [resourcesLoading, setResourcesLoading] = useState(true);
  const [resourcesError, setResourcesError] = useState<string | null>(null);
  const [preview, setPreview] = useState<ProfferPreviewResponse | null>(null);
  const [operatorSnapshot, setOperatorSnapshot] = useState<ProfferOperatorSnapshot | null>(null);
  const [messages, setMessages] = useState<ProfferPreviewMessage[]>([]);
  const [participants, setParticipants] = useState<ProfferPreviewParticipant[]>([]);
  const [content, setContent] = useState<ProfferContentResponse | null>(null);
  const [contentError, setContentError] = useState<string | null>(null);
  const [contentLoading, setContentLoading] = useState(false);
  const [potentialFlags, setPotentialFlags] = useState<ProfferPotentialPromotionFlag[]>([]);
  const [flagError, setFlagError] = useState<string | null>(null);
  const [flagPendingTarget, setFlagPendingTarget] = useState<string | null>(null);
  const [nextCursor, setNextCursor] = useState<string | null>(null);
  const [events, setEvents] = useState<ProfferPreviewEvent[]>([]);
  const [snapshotError, setSnapshotError] = useState<string | null>(null);
  const [messageError, setMessageError] = useState<string | null>(null);
  const [eventError, setEventError] = useState<string | null>(null);
  const [messagesLoading, setMessagesLoading] = useState(false);
  const [decisionPending, setDecisionPending] = useState(false);
  const [rejectionReason, setRejectionReason] = useState("");
  const generationRef = useRef(initialUrlHandle ? 1 : 0);
  const activeHandleRef = useRef(initialUrlHandle);
  const snapshotControllerRef = useRef<AbortController | null>(null);
  const messageControllersRef = useRef(new Map<string, AbortController>());
  const contentControllerRef = useRef<AbortController | null>(null);
  const flagControllerRef = useRef<AbortController | null>(null);
  const requestedCursorsRef = useRef(new Set<string>());
  const resourcesControllerRef = useRef<AbortController | null>(null);

  const activateHandle = useCallback((handle: string) => {
    generationRef.current += 1;
    activeHandleRef.current = handle;
    snapshotControllerRef.current?.abort();
    messageControllersRef.current.forEach((controller) => controller.abort());
    contentControllerRef.current?.abort();
    flagControllerRef.current?.abort();
    messageControllersRef.current.clear();
    requestedCursorsRef.current.clear();
    setPreview(null);
    setOperatorSnapshot(null);
    setMessages([]);
    setParticipants([]);
    setContent(null);
    setContentError(null);
    setContentLoading(false);
    setPotentialFlags([]);
    setFlagError(null);
    setFlagPendingTarget(null);
    setNextCursor(null);
    setEvents([]);
    setSnapshotError(null);
    setMessageError(null);
    setEventError(null);
    setMessagesLoading(false);
    setDecisionPending(false);
    setRejectionReason("");
    setPreviewHandle(handle);
  }, []);

  const selectResource = useCallback((handle: string) => {
    activateHandle(handle);
    const url = new URL(window.location.href);
    url.search = "";
    url.searchParams.set("mode", mode);
    if (handle) url.searchParams.set("resource", handle);
    window.history.replaceState({}, "", url);
  }, [activateHandle, mode]);

  useEffect(() => {
    const timer = window.setTimeout(() => {
      const handle = initialHandle(mode);
      const url = new URL(window.location.href);
      url.search = "";
      url.searchParams.set("mode", mode);
      if (handle) url.searchParams.set("resource", handle);
      window.history.replaceState({}, "", url);
    }, 0);
    return () => window.clearTimeout(timer);
  }, [mode]);

  const loadResources = useCallback(async () => {
    resourcesControllerRef.current?.abort();
    const controller = new AbortController();
    resourcesControllerRef.current = controller;
    setResourcesLoading(true);
    try {
      const response = await listProfferProposalResources(mode, { limit: 50 }, controller.signal);
      if (controller.signal.aborted) return;
      setResources(response.items);
      setResourcesError(null);
      if (!activeHandleRef.current && response.items.length > 0) {
        selectResource(response.items[0].preview_handle);
      }
    } catch (error) {
      if (!controller.signal.aborted) {
        setResourcesError(error instanceof Error ? error.message : "Review resources are unavailable");
      }
    } finally {
      if (resourcesControllerRef.current === controller) {
        resourcesControllerRef.current = null;
        setResourcesLoading(false);
      }
    }
  }, [mode, selectResource]);

  useEffect(() => {
    queueMicrotask(() => void loadResources());
    return () => resourcesControllerRef.current?.abort();
  }, [loadResources]);

  const loadSnapshot = useCallback(async () => {
    const handle = previewHandle;
    if (!handle) return;
    const generation = generationRef.current;
    snapshotControllerRef.current?.abort();
    const controller = new AbortController();
    snapshotControllerRef.current = controller;
    try {
      const [result, operator] = await Promise.all([
        getProfferPreview(handle, mode, controller.signal),
        getProfferOperatorSnapshot(handle, mode, controller.signal),
      ]);
      if (generation !== generationRef.current || activeHandleRef.current !== handle) return;
      if (result.preview_handle !== handle) throw new Error("Preview snapshot correlation failed");
      setPreview(result);
      setOperatorSnapshot(operator);
      setSnapshotError(null);
    } catch (error) {
      if (generation !== generationRef.current || activeHandleRef.current !== handle) return;
      setSnapshotError(error instanceof Error ? error.message : "Preview snapshot is unavailable");
    } finally {
      if (snapshotControllerRef.current === controller) snapshotControllerRef.current = null;
    }
  }, [previewHandle, mode]);

  const loadMessages = useCallback(async (cursor?: string) => {
    const handle = previewHandle;
    if (!handle) return;
    const generation = generationRef.current;
    const cursorKey = cursor ?? "__first__";
    if (requestedCursorsRef.current.has(cursorKey)) return;
    requestedCursorsRef.current.add(cursorKey);
    const controller = new AbortController();
    messageControllersRef.current.set(cursorKey, controller);
    setMessagesLoading(true);
    try {
      const page = await getProfferPreviewMessages(handle, mode, cursor, 100, controller.signal);
      if (generation !== generationRef.current || activeHandleRef.current !== handle) return;
      if (page.preview_handle !== handle) throw new Error("Preview message correlation failed");
      setParticipants((current) => {
        const merged = new Map((cursor ? current : []).map((item) => [item.participant_id, item]));
        page.participants.forEach((item) => merged.set(item.participant_id, item));
        return [...merged.values()];
      });
      setMessages((current) => {
        const merged = new Map((cursor ? current : []).map((item) => [item.message_id, item]));
        page.messages.forEach((item) => merged.set(item.message_id, item));
        return [...merged.values()].sort((left, right) => left.ordinal - right.ordinal);
      });
      setNextCursor(page.next_cursor ?? null);
      setMessageError(null);
    } catch (error) {
      if (generation !== generationRef.current || activeHandleRef.current !== handle) return;
      setMessageError(error instanceof Error ? error.message : "Preview messages are unavailable");
    } finally {
      if (messageControllersRef.current.get(cursorKey) === controller) {
        requestedCursorsRef.current.delete(cursorKey);
        messageControllersRef.current.delete(cursorKey);
      }
      if (generation === generationRef.current && activeHandleRef.current === handle) {
        setMessagesLoading(messageControllersRef.current.size > 0);
      }
    }
  }, [previewHandle, mode]);

  const loadContent = useCallback(async (recordCursor?: string, chunkCursor?: string) => {
    const handle = previewHandle;
    if (!handle) return;
    const generation = generationRef.current;
    contentControllerRef.current?.abort();
    const controller = new AbortController();
    contentControllerRef.current = controller;
    setContentLoading(true);
    try {
      const page = await getProfferPreviewContent(handle, mode, recordCursor, chunkCursor, 100, controller.signal);
      if (generation !== generationRef.current || activeHandleRef.current !== handle) return;
      setContent((current) => {
        const append = Boolean(recordCursor || chunkCursor);
        const records = new Map((append && current ? current.records : []).map((item) => [item.record_id, item]));
        page.records.forEach((item) => records.set(item.record_id, item));
        const chunks = new Map((append && current ? current.chunks : []).map((item) => [item.chunk_ref, item]));
        page.chunks.forEach((item) => chunks.set(item.chunk_ref, item));
        return {
          ...page,
          records: [...records.values()].sort((left, right) => left.ordinal - right.ordinal),
          chunks: [...chunks.values()].sort((left, right) => left.index - right.index),
        };
      });
      setContentError(null);
    } catch (error) {
      if (generation !== generationRef.current || activeHandleRef.current !== handle) return;
      setContentError(error instanceof Error ? error.message : "Package, record, and chunk preview is unavailable");
    } finally {
      if (contentControllerRef.current === controller) contentControllerRef.current = null;
      if (generation === generationRef.current && activeHandleRef.current === handle) setContentLoading(false);
    }
  }, [previewHandle, mode]);

  const loadPotentialFlags = useCallback(async () => {
    const handle = previewHandle;
    if (!handle) return;
    const generation = generationRef.current;
    flagControllerRef.current?.abort();
    const controller = new AbortController();
    flagControllerRef.current = controller;
    try {
      const result = await listProfferPotentialPromotionFlags(handle, mode, controller.signal);
      if (generation !== generationRef.current || activeHandleRef.current !== handle) return;
      setPotentialFlags(result.flags);
      setFlagError(null);
    } catch (error) {
      if (generation !== generationRef.current || activeHandleRef.current !== handle) return;
      setFlagError(error instanceof Error ? error.message : "Potential-promotion flags are unavailable");
    } finally {
      if (flagControllerRef.current === controller) flagControllerRef.current = null;
    }
  }, [previewHandle, mode]);

  useEffect(() => {
    if (!previewHandle) return;
    const generation = generationRef.current;
    const initialLoad = window.setTimeout(() => {
      void loadSnapshot();
    }, 0);
    const source = createProfferPreviewEventSource(previewHandle, mode);
    const onEvent = (raw: MessageEvent<string>) => {
      try {
        if (generation !== generationRef.current || activeHandleRef.current !== previewHandle) return;
        const event = JSON.parse(raw.data) as ProfferPreviewEvent;
        if (event.preview_handle !== previewHandle) throw new Error("Preview event correlation failed");
        if (event.matter_mode !== mode) throw new Error("Preview event crossed the active TEST/REAL boundary");
        setEvents((current) => [...current.filter((item) => item.event_id !== event.event_id), event]
          .sort((left, right) => left.event_id - right.event_id)
          .slice(-100));
        setEventError(null);
        void loadSnapshot();
      } catch (error) {
        setEventError(error instanceof Error ? error.message : "Malformed preview event");
        source.close();
      }
    };
    source.addEventListener("proffer.preview", onEvent as EventListener);
    source.onerror = () => {
      if (generation === generationRef.current && activeHandleRef.current === previewHandle) {
        setEventError("The Proffer preview event stream is unavailable");
      }
    };
    const messageControllers = messageControllersRef.current;
    const requestedCursors = requestedCursorsRef.current;
    return () => {
      window.clearTimeout(initialLoad);
      source.close();
      snapshotControllerRef.current?.abort();
      contentControllerRef.current?.abort();
      flagControllerRef.current?.abort();
      messageControllers.forEach((controller) => controller.abort());
      messageControllers.clear();
      requestedCursors.clear();
    };
  }, [loadSnapshot, mode, previewHandle]);

  const contextFlowComplete = profferContextFlowComplete(preview?.receipts, preview?.checkpoints);

  useEffect(() => {
    if (!previewHandle || !contextFlowComplete) return;
    const timer = window.setTimeout(() => {
      void loadMessages();
      void loadContent();
      void loadPotentialFlags();
    }, 0);
    return () => window.clearTimeout(timer);
  }, [contextFlowComplete, loadContent, loadMessages, loadPotentialFlags, previewHandle]);

  async function flagPotentialPromotion(
    scope: ProfferPotentialPromotionScope,
    targetId: string,
    attemptId: string,
    reason: string,
  ) {
    const handle = previewHandle;
    const generation = generationRef.current;
    if (!handle || !reason.trim()) return;
    const pendingKey = `${scope}:${targetId}`;
    setFlagPendingTarget(pendingKey);
    try {
      const created = await createProfferPotentialPromotionFlag(handle, mode, {
        scope,
        target_id: targetId,
        attempt_id: attemptId,
        reason: reason.trim(),
      });
      if (generation !== generationRef.current || activeHandleRef.current !== handle) return;
      setPotentialFlags((current) => [
        ...current.filter((flag) => flag.flag_id !== created.flag_id),
        created,
      ]);
      setFlagError(null);
      toast.success("Potential-promotion classification recorded");
    } catch (error) {
      if (generation !== generationRef.current || activeHandleRef.current !== handle) return;
      const detail = error instanceof Error ? error.message : "Potential-promotion flag failed";
      setFlagError(detail);
      toast.error(detail);
    } finally {
      if (generation === generationRef.current && activeHandleRef.current === handle) {
        setFlagPendingTarget(null);
      }
    }
  }

  async function decide(approved: boolean, explicitReason = rejectionReason.trim()) {
    const handle = previewHandle;
    const generation = generationRef.current;
    if (!handle || !decisionEligible) {
      toast.error("Load the correlated messages, provenance, and completed receipts before deciding");
      return;
    }
    if (!approved && !explicitReason) {
      toast.error("A rejection requires a reason");
      return;
    }
    setDecisionPending(true);
    try {
      const result = await decideProffer(handle, mode, { approved, reason: approved ? "" : explicitReason });
      if (generation !== generationRef.current || activeHandleRef.current !== handle) return;
      if (result.preview_handle !== handle) throw new Error("Decision response correlation failed");
      toast.success(approved ? "Review approved" : "Review rejected");
      await loadSnapshot();
    } catch (error) {
      toast.error(error instanceof Error ? error.message : "Decision failed");
    } finally {
      if (generation === generationRef.current && activeHandleRef.current === handle) {
        setDecisionPending(false);
      }
    }
  }

  async function retainOriginal() {
    if (!previewHandle || preview?.phase !== "awaiting_repair_decision") return;
    setDecisionPending(true);
    try {
      await decideProfferRepair(previewHandle, mode, { approved: true, apply_repair: false });
      toast.success("Original-source override recorded");
      await loadSnapshot();
    } catch (error) {
      toast.error(error instanceof Error ? error.message : "The repair decision failed");
    } finally {
      setDecisionPending(false);
    }
  }

  async function selectHandler(candidate: ProfferParserCandidate) {
    if (!previewHandle || preview?.phase !== "awaiting_handler_selection" || !preview.handler_recommendation_ref) return;
    setDecisionPending(true);
    try {
      await decideProfferHandler(previewHandle, mode, {
        recommendation_ref: preview.handler_recommendation_ref,
        handler_id: candidate.handler_id,
        handler_version: candidate.handler_version,
        execution_path: candidate.execution_path,
        compatibility_ref: candidate.compatibility_ref,
      });
      toast.success("Handler selection recorded");
      await loadSnapshot();
    } catch (error) {
      toast.error(error instanceof Error ? error.message : "The handler selection failed");
    } finally {
      setDecisionPending(false);
    }
  }

  const awaitingDecision = preview?.phase === "awaiting_decision";
  const requiredReceiptTypes = useMemo(
    () => PROFFER_CONTEXT_CHECKPOINTS.map(({ type }) => type),
    [],
  );
  const provenanceLoaded = Boolean(content && content.records.length > 0 && content.records.every((record) =>
    Boolean(record.source_locator_ref),
  ));
  const receiptsComplete = requiredReceiptTypes.every((receiptType) =>
    preview?.receipts?.some((receipt) => receipt.receipt_type === receiptType && receipt.status === "completed"),
  );
  const decisionEligible = Boolean(
    awaitingDecision &&
    preview?.preview_handle === previewHandle &&
    content &&
    !snapshotError &&
    !contentError &&
    provenanceLoaded &&
    receiptsComplete,
  );

  return (
    <div className="mx-auto w-full max-w-[1680px] space-y-4 p-4 md:p-6">
      <header className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <Button asChild variant="outline" size="sm" className="mb-4"><AppLink data-testid="back-to-proffer-intake" href="/intake"><ChevronLeft className="size-4" /> Back to intake</AppLink></Button>
          <p className="platform-kicker">Unified operator surface · bounded client</p>
          <h1 className="mt-1 text-2xl font-semibold tracking-tight">Context Review workspace</h1>
          <p className="mt-1 max-w-3xl text-sm text-muted-foreground">
            Select a source proposal, inspect every available context artifact, and control the exact processing attempt.
          </p>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <MatterModeSelector />
          <Badge variant={previewHandle ? "default" : "outline"}>{previewHandle ? `${mode} resource selected` : `${mode} · no resource selected`}</Badge>
        </div>
      </header>

      <section className="platform-panel overflow-hidden" aria-labelledby="review-resources-heading">
        <header className="flex flex-wrap items-center justify-between gap-3 border-b px-4 py-3">
          <div>
            <h2 id="review-resources-heading" className="text-sm font-semibold">Sources and proposals</h2>
            <p className="mt-1 text-xs text-muted-foreground">The current URL resource is selected automatically; otherwise the newest available proposal opens.</p>
          </div>
          <div className="flex items-center gap-2">
            <Button asChild variant="outline" size="sm"><AppLink href={`/intake?mode=${mode}`}>Start intake</AppLink></Button>
            <Button variant="ghost" size="sm" onClick={() => void loadResources()} disabled={resourcesLoading}>
              {resourcesLoading ? <Loader2 className="size-4 animate-spin motion-reduce:animate-none" /> : <RefreshCw className="size-4" />} Refresh list
            </Button>
          </div>
        </header>
        {resourcesError && <div className="border-b border-destructive/40 bg-destructive/5 px-4 py-3 text-sm text-destructive" role="alert"><strong>Resource list unavailable.</strong> {resourcesError}</div>}
        {resourcesLoading && resources.length === 0 ? (
          <div className="flex items-center gap-2 px-4 py-6 text-sm text-muted-foreground"><Loader2 className="size-4 animate-spin motion-reduce:animate-none" /> Loading available sources and proposals…</div>
        ) : resources.length ? (
          <div className="grid max-h-64 divide-y overflow-y-auto lg:grid-cols-2 lg:divide-x lg:divide-y-0 xl:grid-cols-3">
            {resources.map((resource) => (
              <button
                key={resource.preview_handle}
                type="button"
                aria-pressed={previewHandle === resource.preview_handle}
                onClick={() => selectResource(resource.preview_handle)}
                className={`grid min-h-24 grid-cols-[auto_minmax(0,1fr)] gap-3 p-4 text-left focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-ring ${previewHandle === resource.preview_handle ? "bg-accent" : "bg-card hover:bg-accent/40"}`}
              >
                <FileText className="mt-0.5 size-4 text-primary" />
                <span className="min-w-0">
                  <strong className="block truncate text-sm" title={resource.source_ref}>{resource.source_ref}</strong>
                  <span className="mt-1 block text-xs capitalize text-muted-foreground">{resource.lifecycle.replaceAll("_", " ")} · {resource.completed_stage_count} stages</span>
                  <span className="mt-1 block text-[11px] font-semibold text-foreground">{resource.representation_state === "committed_readback" ? "Committed readback" : "Precommit proposal"}</span>
                  <span className="mt-1 block text-[11px] capitalize text-muted-foreground">Content {resource.content_status}{resource.chunk_count !== null && resource.chunk_count !== undefined ? ` · ${resource.chunk_count} chunks` : ""}</span>
                  <span className="mt-1 block text-[11px] leading-4 text-muted-foreground">{resource.representation_detail}</span>
                  <span className="mt-1 block text-[11px] text-muted-foreground">{createdAt(resource.created_at)}</span>
                </span>
              </button>
            ))}
          </div>
        ) : (
          <div className="px-5 py-10 text-center">
            <CircleDot className="mx-auto size-5 text-muted-foreground" />
            <p className="mt-3 text-sm font-semibold">No context proposals are available</p>
            <p className="mt-1 text-xs text-muted-foreground">Start intake to select source material and create the first reviewable attempt.</p>
          </div>
        )}
      </section>

      {previewHandle && <ContextFlowRail
        started
        phase={preview?.phase}
        receipts={preview?.receipts}
        checkpoints={preview?.checkpoints}
        events={events}
      />}

      {!previewHandle ? (
        <div className="platform-panel rounded-md px-5 py-14 text-center">
          <CircleDot className="mx-auto size-9 text-muted-foreground" />
          <p className="mt-3 text-sm font-medium">Choose a source proposal above or start intake.</p>
        </div>
      ) : snapshotError ? (
        <div className="platform-panel border-destructive/50 p-5 text-sm text-destructive" role="alert">{snapshotError}</div>
      ) : !preview || !operatorSnapshot ? (
        <section className="platform-panel flex min-h-[34rem] items-center justify-center p-6 text-sm text-muted-foreground" aria-label="Review loading"><Loader2 className="mr-2 size-4 animate-spin motion-reduce:animate-none" /> Loading the {mode} review workspace…</section>
      ) : (
        <>
          {eventError && <p className="border border-[#ead5a9] bg-[#fff4dd] p-3 text-sm text-[#684b18]" role="status">{eventError}</p>}
          {!decisionEligible && awaitingDecision && <p className="border border-[#ead5a9] bg-[#fff4dd] p-3 text-xs text-[#684b18]" role="status">Approval remains locked until this exact attempt has normalized records, source locators, and every required completed receipt.</p>}
          <ProfferOperatorPreview
            key={`${mode}:${previewHandle}`}
            snapshot={operatorSnapshot}
            preview={preview}
            messages={messages}
            participants={participants}
            events={events}
            content={content}
            contentLoading={contentLoading}
            contentError={contentError}
            potentialFlags={potentialFlags}
            flagError={flagError}
            flagPendingTarget={flagPendingTarget}
            messagesLoading={messagesLoading}
            messageError={messageError}
            hasMore={Boolean(nextCursor)}
            onLoadMore={() => void loadMessages(nextCursor ?? undefined)}
            onLoadMoreContent={(recordCursor, chunkCursor) => void loadContent(recordCursor, chunkCursor)}
            onFlagPotentialPromotion={(scope, targetId, attemptId, reason) => void flagPotentialPromotion(scope, targetId, attemptId, reason)}
            onRefresh={() => void loadSnapshot()}
            onApprove={() => decisionEligible && void decide(true)}
            onReject={(reason) => decisionEligible && void decide(false, reason)}
            onRetainOriginal={() => void retainOriginal()}
            onSelectHandler={(candidate) => void selectHandler(candidate)}
            actionPending={decisionPending}
            decisionReady={decisionEligible}
          />
        </>
      )}
    </div>
  );
}
