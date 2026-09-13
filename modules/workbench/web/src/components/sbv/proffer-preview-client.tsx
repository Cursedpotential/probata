// Byline: Codex · GPT-5.6 · 2026-09-12 (hydrate deep-linked preview mode and handle atomically)
"use client";

import { Activity, ChevronLeft, Link2, ShieldCheck } from "lucide-react";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { toast } from "sonner";

import { ProfferOperatorPreview } from "@/components/sbv/proffer-operator-preview";
import { ContextFlowRail } from "@/components/intake/context-flow-rail";
import { MatterModeSelector } from "@/components/intake/matter-mode-selector";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  createProfferPreviewEventSource,
  decideProffer,
  decideProfferHandler,
  decideProfferRepair,
  getProfferOperatorSnapshot,
  getProfferPreview,
  getProfferPreviewMessages,
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
} from "@/lib/shared/types";

function initialHandle(mode: "TEST" | "REAL") {
  if (typeof window === "undefined") return "";
  const query = new URLSearchParams(window.location.search);
  return query.get("mode") === mode ? query.get("preview_handle")?.trim() ?? "" : "";
}

export function ProfferPreviewClient() {
  const { mode } = useFixedCase();
  return <ModeScopedPreviewClient key={mode} mode={mode} />;
}

function ModeScopedPreviewClient({ mode }: { mode: "TEST" | "REAL" }) {
  const [initialUrlHandle] = useState(() => initialHandle(mode));
  const [draftHandle, setDraftHandle] = useState(initialUrlHandle);
  const [previewHandle, setPreviewHandle] = useState(initialUrlHandle);
  const [preview, setPreview] = useState<ProfferPreviewResponse | null>(null);
  const [operatorSnapshot, setOperatorSnapshot] = useState<ProfferOperatorSnapshot | null>(null);
  const [messages, setMessages] = useState<ProfferPreviewMessage[]>([]);
  const [participants, setParticipants] = useState<ProfferPreviewParticipant[]>([]);
  const [nextCursor, setNextCursor] = useState<string | null>(null);
  const [events, setEvents] = useState<ProfferPreviewEvent[]>([]);
  const [snapshotError, setSnapshotError] = useState<string | null>(null);
  const [messageError, setMessageError] = useState<string | null>(null);
  const [eventError, setEventError] = useState<string | null>(null);
  const [messagesLoading, setMessagesLoading] = useState(false);
  const [messagesLoaded, setMessagesLoaded] = useState(false);
  const [decisionPending, setDecisionPending] = useState(false);
  const [rejectionReason, setRejectionReason] = useState("");
  const generationRef = useRef(initialUrlHandle ? 1 : 0);
  const activeHandleRef = useRef(initialUrlHandle);
  const snapshotControllerRef = useRef<AbortController | null>(null);
  const messageControllersRef = useRef(new Map<string, AbortController>());
  const requestedCursorsRef = useRef(new Set<string>());

  const activateHandle = useCallback((handle: string) => {
    generationRef.current += 1;
    activeHandleRef.current = handle;
    snapshotControllerRef.current?.abort();
    messageControllersRef.current.forEach((controller) => controller.abort());
    messageControllersRef.current.clear();
    requestedCursorsRef.current.clear();
    setPreview(null);
    setOperatorSnapshot(null);
    setMessages([]);
    setParticipants([]);
    setNextCursor(null);
    setEvents([]);
    setSnapshotError(null);
    setMessageError(null);
    setEventError(null);
    setMessagesLoaded(false);
    setMessagesLoading(false);
    setDecisionPending(false);
    setRejectionReason("");
    setPreviewHandle(handle);
  }, []);

  useEffect(() => {
    const timer = window.setTimeout(() => {
      const handle = initialHandle(mode);
      const url = new URL(window.location.href);
      url.search = "";
      url.searchParams.set("mode", mode);
      if (handle) url.searchParams.set("preview_handle", handle);
      window.history.replaceState({}, "", url);
    }, 0);
    return () => window.clearTimeout(timer);
  }, [mode]);

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
      if (!cursor) setMessagesLoaded(true);
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
      messageControllers.forEach((controller) => controller.abort());
      messageControllers.clear();
      requestedCursors.clear();
    };
  }, [loadSnapshot, mode, previewHandle]);

  const contextFlowComplete = profferContextFlowComplete(preview?.receipts, preview?.checkpoints);

  useEffect(() => {
    if (!previewHandle || !contextFlowComplete) return;
    const timer = window.setTimeout(() => void loadMessages(), 0);
    return () => window.clearTimeout(timer);
  }, [contextFlowComplete, loadMessages, previewHandle]);

  function attach() {
    const handle = draftHandle.trim();
    if (!handle) {
      toast.error("Enter the preview handle returned by intake");
      return;
    }
    activateHandle(handle);
    const url = new URL(window.location.href);
    url.search = "";
    url.searchParams.set("mode", mode);
    url.searchParams.set("preview_handle", handle);
    window.history.replaceState({}, "", url);
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
      toast.success(approved ? "Preview approved" : "Preview rejected");
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
  const participantIds = useMemo(
    () => new Set(participants.map((participant) => participant.participant_id)),
    [participants],
  );
  const provenanceLoaded = messages.length > 0 && messages.every((message) =>
    Boolean(message.source_locator_ref) &&
    message.participant_ids.every((id) => participantIds.has(id)) &&
    (!message.sender_participant_id || participantIds.has(message.sender_participant_id)) &&
    message.attachments.every((attachment) => Boolean(attachment.source_locator_ref)),
  );
  const receiptsComplete = requiredReceiptTypes.every((receiptType) =>
    preview?.receipts?.some((receipt) => receipt.receipt_type === receiptType && receipt.status === "completed"),
  );
  const decisionEligible = Boolean(
    awaitingDecision &&
    preview?.preview_handle === previewHandle &&
    messagesLoaded &&
    !snapshotError &&
    !messageError &&
    provenanceLoaded &&
    receiptsComplete,
  );

  return (
    <div className="mx-auto w-full max-w-[1680px] space-y-4 p-4 md:p-6">
      <header className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <Button asChild variant="outline" size="sm" className="mb-4"><AppLink data-testid="back-to-proffer-intake" href="/intake"><ChevronLeft className="size-4" /> Back to intake</AppLink></Button>
          <p className="platform-kicker">Unified operator surface · bounded client</p>
          <h1 className="mt-1 text-2xl font-semibold tracking-tight">Pipeline preview</h1>
          <p className="mt-1 max-w-3xl text-sm text-muted-foreground">
            Watch the durable import workflow and platform messages through one opaque preview boundary.
          </p>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <MatterModeSelector />
          <Badge variant={previewHandle ? "default" : "outline"} className="gap-1.5"><Link2 className="size-3" /> {previewHandle ? `${mode} attached` : `${mode} not attached`}</Badge>
        </div>
      </header>

      <ContextFlowRail
        started={Boolean(previewHandle)}
        phase={preview?.phase}
        receipts={preview?.receipts}
        checkpoints={preview?.checkpoints}
        events={events}
      />

      <Card className="platform-panel">
        <CardHeader className="pb-3"><CardTitle className="text-sm">Attach to an import preview</CardTitle></CardHeader>
        <CardContent className="grid gap-3 md:grid-cols-[1fr_auto] md:items-end">
          <div className="space-y-1.5">
            <Label htmlFor="proffer-preview-handle">Preview handle</Label>
            <Input id="proffer-preview-handle" value={draftHandle} onChange={(event) => setDraftHandle(event.target.value)} autoComplete="off" />
          </div>
          <Button onClick={attach} className="gap-2"><Activity className="size-4" /> Open preview</Button>
        </CardContent>
      </Card>

      {!previewHandle ? (
        <div className="platform-panel rounded-md px-5 py-14 text-center">
          <ShieldCheck className="mx-auto size-9 text-muted-foreground" />
          <p className="mt-3 text-sm font-medium">Attach the preview handle returned by intake.</p>
        </div>
      ) : snapshotError ? (
        <div className="platform-panel border-destructive/50 p-5 text-sm text-destructive" role="alert">{snapshotError}</div>
      ) : !preview || !operatorSnapshot ? (
        <section className="platform-panel flex min-h-[34rem] items-center justify-center p-6 text-sm text-muted-foreground" aria-label="Preview loading">Loading the {mode} operator snapshot…</section>
      ) : (
        <>
          {eventError && <p className="border border-[#ead5a9] bg-[#fff4dd] p-3 text-sm text-[#684b18]" role="status">{eventError}</p>}
          {!decisionEligible && awaitingDecision && <p className="border border-[#ead5a9] bg-[#fff4dd] p-3 text-xs text-[#684b18]" role="status">Approval remains locked until this exact preview has normalized records, participant and attachment provenance, and every required completed receipt.</p>}
          <ProfferOperatorPreview
            key={`${mode}:${previewHandle}`}
            snapshot={operatorSnapshot}
            preview={preview}
            messages={messages}
            participants={participants}
            events={events}
            messagesLoading={messagesLoading}
            messageError={messageError}
            hasMore={Boolean(nextCursor)}
            onLoadMore={() => void loadMessages(nextCursor ?? undefined)}
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
