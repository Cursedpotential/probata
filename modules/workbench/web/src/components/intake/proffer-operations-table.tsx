// Byline: Codex · GPT-5.6-Sol · 2026-09-12 (durable Proffer operation visibility)
"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
  AlertTriangle,
  ChevronRight,
  CircleDot,
  ExternalLink,
  Loader2,
  RefreshCw,
  RotateCcw,
  X,
} from "lucide-react";

import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import {
  ApiError,
  getProfferOperation,
  listProfferOperations,
} from "@/lib/api-client";
import {
  AppLink,
  useAppNavigate,
  useBrowserSearchParams,
} from "@/lib/router-compat";
import type {
  ProfferOperationDetail,
  ProfferOperationLifecycle,
  ProfferOperationSummary,
} from "@/lib/shared/types";
import { cn } from "@/lib/utils";

const LIST_POLL_MS = 5_000;
const PAGE_SIZE = 50;
const PREVIEW_HANDLE_PATTERN = /^[A-Za-z0-9_-]{32,128}$/;
const OPERATION_STATUSES: readonly ProfferOperationLifecycle[] = [
  "running",
  "awaiting_repair_decision",
  "awaiting_preview_decision",
  "completed",
  "failed",
  "unavailable",
];

function errorText(error: unknown) {
  return error instanceof ApiError
    ? error.message
    : error instanceof Error
      ? error.message
      : "The Proffer operation request failed";
}

function operationStatus(value: string | null): ProfferOperationLifecycle | "all" {
  return OPERATION_STATUSES.includes(value as ProfferOperationLifecycle)
    ? (value as ProfferOperationLifecycle)
    : "all";
}

function lifecycleLabel(lifecycle: ProfferOperationLifecycle) {
  return lifecycle.replaceAll("_", " ");
}

function lifecycleClass(lifecycle: ProfferOperationLifecycle) {
  if (lifecycle === "completed") return "border-[#2f9d67] bg-[#e2f3e9] text-[#17794b] dark:bg-[#203d31] dark:text-[#72d9a1]";
  if (lifecycle === "failed") return "border-[#b5433b] bg-[#fbe9e7] text-[#8f302a] dark:bg-[#442723] dark:text-[#ff9f96]";
  if (lifecycle.startsWith("awaiting_")) return "border-[#c58214] bg-[#fff4dd] text-[#684b18] dark:bg-[#43351f] dark:text-[#ffe0a6]";
  if (lifecycle === "unavailable") return "border-border bg-muted text-muted-foreground";
  return "border-primary/40 bg-primary/10 text-primary";
}

function operationWork(operation: ProfferOperationSummary) {
  if (operation.wait === "repair_decision") return "Waiting for repair decision";
  if (operation.wait === "preview_decision") return "Waiting for preview decision";
  if (operation.current_stage) return operation.current_stage.replaceAll("_", " ");
  if (operation.terminal) return `${operation.completed_stage_count} stages completed`;
  return operation.active_stages.length
    ? operation.active_stages.map((stage) => stage.replaceAll("_", " ")).join(", ")
    : "Registering operation";
}

function createdAt(value: string) {
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? value : parsed.toLocaleString();
}

export function ProfferOperationsTable() {
  const searchParams = useBrowserSearchParams();
  const navigate = useAppNavigate();
  const statusFilter = operationStatus(searchParams.get("operation_status"));
  const sourceFilter = searchParams.get("operation_source") ?? "";
  const serviceFilter = searchParams.get("operation_service") === "proffer" ? "proffer" : "all";
  const selectedHandle = searchParams.get("preview_handle");

  const [operations, setOperations] = useState<ProfferOperationSummary[]>([]);
  const [nextCursor, setNextCursor] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [listError, setListError] = useState<string | null>(null);
  const [detail, setDetail] = useState<ProfferOperationDetail | null>(null);
  const [detailLoading, setDetailLoading] = useState(false);
  const [detailError, setDetailError] = useState<string | null>(null);
  const listBusyRef = useRef(false);
  const listAbortRef = useRef<AbortController | null>(null);

  function replaceSearch(changes: Record<string, string | null>) {
    const next = new URLSearchParams(searchParams);
    for (const [key, value] of Object.entries(changes)) {
      if (value) next.set(key, value);
      else next.delete(key);
    }
    const query = next.toString();
    void navigate.replace(`/intake${query ? `?${query}` : ""}`);
  }

  const refresh = useCallback(async (quiet = false) => {
    if (listBusyRef.current) return;
    listBusyRef.current = true;
    const controller = new AbortController();
    listAbortRef.current = controller;
    if (!quiet) setLoading(true);
    try {
      const response = await listProfferOperations(
        {
          status: statusFilter === "all" ? undefined : statusFilter,
          limit: PAGE_SIZE,
        },
        controller.signal,
      );
      setOperations(response.items);
      setNextCursor(response.next_cursor ?? null);
      setListError(null);
    } catch (requestError) {
      if (!controller.signal.aborted) setListError(errorText(requestError));
    } finally {
      if (listAbortRef.current === controller) {
        listAbortRef.current = null;
        listBusyRef.current = false;
        if (!quiet) setLoading(false);
      }
    }
  }, [statusFilter]);

  useEffect(() => {
    queueMicrotask(() => void refresh());
    const poll = window.setInterval(() => void refresh(true), LIST_POLL_MS);
    return () => {
      window.clearInterval(poll);
      const activeRequest = listAbortRef.current;
      listAbortRef.current = null;
      activeRequest?.abort();
      listBusyRef.current = false;
    };
  }, [refresh]);

  useEffect(() => {
    if (!selectedHandle || !PREVIEW_HANDLE_PATTERN.test(selectedHandle)) return;
    let activeController: AbortController | null = null;
    let stopped = false;
    const loadDetail = async (quiet = false) => {
      if (activeController || stopped) return;
      const controller = new AbortController();
      activeController = controller;
      if (!quiet) {
        setDetail(null);
        setDetailError(null);
        setDetailLoading(true);
      }
      try {
        const response = await getProfferOperation(selectedHandle, controller.signal);
        if (!stopped) {
          setDetail(response);
          setDetailError(null);
        }
      } catch (requestError) {
        if (!controller.signal.aborted && !stopped) setDetailError(errorText(requestError));
      } finally {
        if (activeController === controller) activeController = null;
        if (!stopped && !quiet) setDetailLoading(false);
      }
    };
    queueMicrotask(() => void loadDetail());
    const poll = window.setInterval(() => void loadDetail(true), LIST_POLL_MS);
    return () => {
      stopped = true;
      window.clearInterval(poll);
      activeController?.abort();
    };
  }, [selectedHandle]);

  const filteredOperations = useMemo(() => {
    const sourceNeedle = sourceFilter.trim().toLocaleLowerCase();
    return operations.filter((operation) => {
      const sourceMatches = !sourceNeedle || [
        operation.source_ref,
        operation.request_id,
      ].some((value) => value.toLocaleLowerCase().includes(sourceNeedle));
      const serviceMatches = serviceFilter === "all" || operation.service === serviceFilter;
      return sourceMatches && serviceMatches;
    });
  }, [operations, serviceFilter, sourceFilter]);

  async function loadMore() {
    if (!nextCursor || listBusyRef.current) return;
    listBusyRef.current = true;
    setLoadingMore(true);
    try {
      const response = await listProfferOperations({
        status: statusFilter === "all" ? undefined : statusFilter,
        cursor: nextCursor,
        limit: PAGE_SIZE,
      });
      setOperations((current) => {
        const rows = new Map(current.map((operation) => [operation.preview_handle, operation]));
        for (const operation of response.items) rows.set(operation.preview_handle, operation);
        return Array.from(rows.values());
      });
      setNextCursor(response.next_cursor ?? null);
      setListError(null);
    } catch (requestError) {
      setListError(errorText(requestError));
    } finally {
      listBusyRef.current = false;
      setLoadingMore(false);
    }
  }

  const filtersActive = statusFilter !== "all" || Boolean(sourceFilter) || serviceFilter !== "all";
  const selectedHandleInvalid = Boolean(selectedHandle && !PREVIEW_HANDLE_PATTERN.test(selectedHandle));
  const selectedDetail = detail?.preview_handle === selectedHandle ? detail : null;

  return (
    <div className="platform-panel overflow-hidden">
      <header className="flex flex-wrap items-start justify-between gap-4 border-b px-5 py-4">
        <div>
          <p className="platform-rule-title">Durable operation ledger</p>
          <p className="mt-1 max-w-2xl text-xs leading-5 text-muted-foreground">
            These rows come from Proffer's lifecycle projection. They are separate from legacy Workbench runs.
          </p>
        </div>
        <Button variant="outline" size="sm" onClick={() => void refresh()} disabled={loading}>
          {loading ? <Loader2 className="h-4 w-4 animate-spin" /> : <RefreshCw className="h-4 w-4" />}
          Refresh
        </Button>
      </header>

      <div className="grid gap-3 border-b bg-accent/20 p-4 md:grid-cols-[190px_minmax(220px,1fr)_190px_auto]">
        <label className="grid gap-1.5 text-[11px] font-semibold uppercase tracking-wide text-muted-foreground">
          Status
          <select
            className="h-10 border bg-background px-3 text-sm font-normal normal-case tracking-normal text-foreground"
            value={statusFilter}
            onChange={(event) => replaceSearch({ operation_status: event.target.value === "all" ? null : event.target.value })}
          >
            <option value="all">All statuses</option>
            {OPERATION_STATUSES.map((status) => <option key={status} value={status}>{lifecycleLabel(status)}</option>)}
          </select>
        </label>
        <label className="grid gap-1.5 text-[11px] font-semibold uppercase tracking-wide text-muted-foreground">
          Source or request
          <input
            className="h-10 border bg-background px-3 text-sm font-normal normal-case tracking-normal text-foreground"
            value={sourceFilter}
            onChange={(event) => replaceSearch({ operation_source: event.target.value || null })}
            placeholder="Filter loaded source references"
          />
        </label>
        <label className="grid gap-1.5 text-[11px] font-semibold uppercase tracking-wide text-muted-foreground">
          Service
          <select
            className="h-10 border bg-background px-3 text-sm font-normal normal-case tracking-normal text-foreground"
            value={serviceFilter}
            onChange={(event) => replaceSearch({ operation_service: event.target.value === "all" ? null : event.target.value })}
          >
            <option value="all">All listed services</option>
            <option value="proffer">Proffer</option>
          </select>
        </label>
        <div className="flex items-end">
          <Button
            variant="ghost"
            size="sm"
            disabled={!filtersActive}
            onClick={() => replaceSearch({ operation_status: null, operation_source: null, operation_service: null })}
          >
            <RotateCcw className="h-4 w-4" /> Clear filters
          </Button>
        </div>
      </div>

      {selectedHandle && (
        <section className="border-b bg-card" aria-label="Reopened Proffer operation" aria-live="polite">
          <header className="flex items-center justify-between gap-4 border-b px-5 py-3">
            <div>
              <p className="platform-rule-title">Reopened by preview handle</p>
              <p className="mt-1 break-all font-mono text-[10px] text-muted-foreground">{selectedHandle}</p>
            </div>
            <Button variant="ghost" size="icon" aria-label="Close reopened operation" onClick={() => replaceSearch({ preview_handle: null })}>
              <X className="h-4 w-4" />
            </Button>
          </header>
          {selectedHandleInvalid ? (
            <div className="flex items-start gap-2 p-5 text-sm text-[#8f302a]" role="alert">
              <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" />
              <div><strong className="block">Operation detail unavailable</strong><p className="mt-1 text-xs">The preview handle in this URL is invalid.</p></div>
            </div>
          ) : detailError ? (
            <div className="flex items-start gap-2 p-5 text-sm text-[#8f302a]" role="alert">
              <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" />
              <div><strong className="block">Operation detail unavailable</strong><p className="mt-1 text-xs">{detailError}</p></div>
            </div>
          ) : detailLoading || !selectedDetail ? (
            <div className="space-y-2 p-5"><Skeleton className="h-12 w-full" /><Skeleton className="h-24 w-full" /></div>
          ) : selectedDetail ? (
            <div className="grid gap-5 p-5 lg:grid-cols-[minmax(0,1fr)_minmax(360px,1.4fr)]">
              <dl className="grid gap-px border bg-border text-xs sm:grid-cols-2 lg:grid-cols-1">
                <div className="bg-card p-3"><dt className="text-muted-foreground">Source reference</dt><dd className="mt-1 break-all font-mono text-[10px]">{selectedDetail.source_ref}</dd></div>
                <div className="bg-card p-3"><dt className="text-muted-foreground">Lifecycle</dt><dd className="mt-1 capitalize">{lifecycleLabel(selectedDetail.lifecycle)}</dd></div>
                <div className="bg-card p-3"><dt className="text-muted-foreground">Started</dt><dd className="mt-1">{createdAt(selectedDetail.created_at)}</dd></div>
                <div className="bg-card p-3"><dt className="text-muted-foreground">Service</dt><dd className="mt-1 capitalize">{selectedDetail.service}</dd></div>
              </dl>
              <div>
                <p className="platform-rule-title mb-2">Recorded stages</p>
                {selectedDetail.stages.length ? (
                  <ol className="divide-y border">
                    {selectedDetail.stages.map((stage, index) => (
                      <li key={`${stage.stage}-${index}`} className="grid gap-1 px-3 py-2 text-xs sm:grid-cols-[minmax(0,1fr)_120px]">
                        <div><strong className="capitalize">{stage.stage.replaceAll("_", " ")}</strong>{stage.reason && <p className="mt-1 text-muted-foreground">{stage.reason}</p>}</div>
                        <span className="capitalize text-muted-foreground">{stage.status.replaceAll("_", " ")}</span>
                      </li>
                    ))}
                  </ol>
                ) : (
                  <p className="border p-4 text-xs text-muted-foreground">No stage completion has been recorded yet.</p>
                )}
                <div className="mt-4 flex flex-wrap items-center justify-between gap-3">
                  <p className="max-w-xl text-[11px] leading-5 text-muted-foreground">Cancel and retry controls are not exposed here because the engine has no append-only control-receipt contract for those actions yet.</p>
                  <Button asChild size="sm"><AppLink href={`/evidence/preview?preview_handle=${encodeURIComponent(selectedDetail.preview_handle)}`}>Open pipeline preview <ExternalLink className="h-4 w-4" /></AppLink></Button>
                </div>
              </div>
            </div>
          ) : null}
        </section>
      )}

      {listError && (
        <div className="flex items-start justify-between gap-4 border-b border-[#b5433b] bg-[#fbe9e7] px-5 py-3 text-sm text-[#8f302a]" role="alert">
          <div className="flex items-start gap-2"><AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" /><div><strong className="block">Operation list could not be refreshed</strong><p className="mt-1 text-xs">{listError}</p></div></div>
          <Button variant="outline" size="sm" onClick={() => void refresh()}>Try again</Button>
        </div>
      )}

      {loading && operations.length === 0 ? (
        <div className="space-y-2 p-5" aria-label="Loading Proffer operations">
          {Array.from({ length: 5 }, (_, index) => <Skeleton key={index} className="h-12 w-full" />)}
        </div>
      ) : operations.length === 0 && !listError ? (
        <div className="px-5 py-14 text-center">
          <CircleDot className="mx-auto h-5 w-5 text-muted-foreground" />
          <p className="mt-3 text-sm font-semibold">No Proffer operations found</p>
          <p className="mt-1 text-xs text-muted-foreground">{statusFilter === "all" ? "No durable Proffer operation has been recorded yet." : `No operation currently has status “${lifecycleLabel(statusFilter)}”.`}</p>
        </div>
      ) : filteredOperations.length === 0 ? (
        <div className="px-5 py-14 text-center">
          <p className="text-sm font-semibold">No loaded operation matches the source and service filters</p>
          <p className="mt-1 text-xs text-muted-foreground">Clear the filters or load another engine page. Status is filtered by the engine; source and service refine the rows loaded here.</p>
        </div>
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full min-w-[880px] text-left text-sm">
            <thead className="border-b bg-muted/40 text-[10px] uppercase tracking-wide text-muted-foreground">
              <tr><th className="px-4 py-3 font-semibold">Source</th><th className="px-4 py-3 font-semibold">Service</th><th className="px-4 py-3 font-semibold">Lifecycle</th><th className="px-4 py-3 font-semibold">Current work</th><th className="px-4 py-3 font-semibold">Started</th><th className="px-4 py-3 text-right font-semibold">Action</th></tr>
            </thead>
            <tbody className="divide-y">
              {filteredOperations.map((operation) => (
                <tr key={operation.preview_handle} className={cn("bg-card hover:bg-accent/30", selectedHandle === operation.preview_handle && "bg-accent/50")}>
                  <td className="max-w-[300px] px-4 py-3"><strong className="block truncate font-mono text-[11px]" title={operation.source_ref}>{operation.source_ref}</strong><span className="mt-1 block truncate font-mono text-[10px] text-muted-foreground" title={operation.request_id}>{operation.request_id}</span></td>
                  <td className="px-4 py-3 capitalize">{operation.service}</td>
                  <td className="px-4 py-3"><span className={cn("inline-flex border px-2 py-1 text-[10px] font-semibold uppercase", lifecycleClass(operation.lifecycle))}>{lifecycleLabel(operation.lifecycle)}</span></td>
                  <td className="max-w-[280px] px-4 py-3"><span className="block truncate capitalize" title={operationWork(operation)}>{operationWork(operation)}</span>{operation.reason && <span className="mt-1 block truncate text-xs text-muted-foreground" title={operation.reason}>{operation.reason}</span>}</td>
                  <td className="whitespace-nowrap px-4 py-3 text-xs text-muted-foreground">{createdAt(operation.created_at)}</td>
                  <td className="px-4 py-3 text-right"><Button variant="ghost" size="sm" onClick={() => replaceSearch({ preview_handle: operation.preview_handle })}>Reopen <ChevronRight className="h-4 w-4" /></Button></td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      <footer className="flex flex-wrap items-center justify-between gap-3 border-t bg-muted/20 px-5 py-3 text-xs text-muted-foreground">
        <span>{filteredOperations.length} of {operations.length} loaded operations shown</span>
        {nextCursor ? <Button variant="outline" size="sm" disabled={loadingMore} onClick={() => void loadMore()}>{loadingMore && <Loader2 className="h-4 w-4 animate-spin" />} Load more</Button> : <span>End of engine results</span>}
      </footer>
    </div>
  );
}
