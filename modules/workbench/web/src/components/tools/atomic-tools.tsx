// Byline: Codex · GPT-5.6-Sol · 2026-08-30
"use client";

import { useEffect, useMemo, useState } from "react";
import {
  AlertTriangle,
  Ban,
  CheckCircle2,
  ChevronDown,
  CircleDot,
  Clock3,
  Loader2,
  ReceiptText,
  RefreshCw,
  Search,
  ShieldCheck,
  Wrench,
} from "lucide-react";

import { ToolForm } from "@/components/tools/tool-form";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import {
  ApiError,
  cancelMonitoredAction,
  getMonitoredAction,
  getMonitoredActionCapability,
  listTools,
  startAtomicToolAction,
} from "@/lib/api-client";
import { useFixedCase } from "@/lib/fixed-case-context";
import { AppLink } from "@/lib/router-compat";
import type {
  McpTool,
  MonitoredActionCapability,
  MonitoredActionRun,
  StartAtomicToolActionRequest,
  ToolServerGroup,
} from "@/lib/shared/types";
import { cn } from "@/lib/utils";

interface CatalogTool {
  serverKey: string;
  serverLabel: string;
  tool: McpTool;
}

const activeStatuses = new Set(["accepted", "scheduled", "running", "waiting"]);

function errorMessage(error: unknown) {
  return error instanceof ApiError
    ? error.status === 404
      ? "The monitored-action service is not available in this deployment. Atomic execution stays disabled."
      : error.message
    : error instanceof Error
      ? error.message
      : "The monitored-action service is unavailable";
}

function intentFrom(name: string) {
  return name.replaceAll("_", " ").replaceAll("-", " ").replace(/\b\w/g, (letter) => letter.toUpperCase());
}

function statusTone(status: MonitoredActionRun["status"]) {
  if (status === "completed") return "border-[#b8ddc7] bg-[#e2f3e9] text-[#17794b]";
  if (status === "failed" || status === "cancelled") return "border-[#efc7c3] bg-[#fbe9e7] text-[#8e2f29]";
  if (status === "waiting") return "border-[#ead5a9] bg-[#fff4dd] text-[#7d520d]";
  return "border-[#cdd3f1] bg-[#e9ecfb] text-[#2f3d9c]";
}

export function AtomicTools({ embedded = false, initialSearch = "", requiredToolTerm = "" }: { embedded?: boolean; initialSearch?: string; requiredToolTerm?: string }) {
  const { matter, primaryCourtCase, loading: scopeLoading, error: scopeError } = useFixedCase();
  const [servers, setServers] = useState<ToolServerGroup[]>([]);
  const [catalogLoading, setCatalogLoading] = useState(true);
  const [catalogError, setCatalogError] = useState<string | null>(null);
  const [capability, setCapability] = useState<MonitoredActionCapability | null>(null);
  const [capabilityError, setCapabilityError] = useState<string | null>(null);
  const [search, setSearch] = useState(initialSearch);
  const [selected, setSelected] = useState<CatalogTool | null>(null);
  const [intent, setIntent] = useState("");
  const [horizon, setHorizon] = useState<StartAtomicToolActionRequest["horizon"]>("as_lived");
  const [authority, setAuthority] = useState<StartAtomicToolActionRequest["authority_scope"]>("read_only");
  const [run, setRun] = useState<MonitoredActionRun | null>(null);
  const [runError, setRunError] = useState<string | null>(null);
  const [cancelling, setCancelling] = useState(false);

  function loadSurface() {
    void listTools()
      .then(setServers)
      .catch((error) => {
        setServers([]);
        setCatalogError(errorMessage(error));
      })
      .finally(() => setCatalogLoading(false));
    void getMonitoredActionCapability()
      .then((nextCapability) => {
        setCapability(nextCapability);
        if (!nextCapability.available) {
          setCapabilityError(nextCapability.reason || "The monitored-action service has disabled atomic execution.");
        }
      })
      .catch((error) => {
        setCapability(null);
        setCapabilityError(errorMessage(error));
      });
  }

  useEffect(loadSurface, []);

  function recheckSurface() {
    setCatalogLoading(true);
    setCatalogError(null);
    setCapabilityError(null);
    loadSurface();
  }

  useEffect(() => {
    if (!run || !activeStatuses.has(run.status) || !capability?.supports_live_status) return;
    const timer = window.setInterval(() => {
      void getMonitoredAction(run.action_id)
        .then((nextRun) => {
          setRun(nextRun);
          setRunError(null);
        })
        .catch((error) => setRunError(errorMessage(error)));
    }, 2000);
    return () => window.clearInterval(timer);
  }, [capability?.supports_live_status, run]);

  const tools = useMemo<CatalogTool[]>(
    () => servers
      .flatMap((server) => (server.tools ?? []).map((tool) => ({ serverKey: server.key, serverLabel: server.label, tool })))
      .filter(({ serverLabel, tool }) => !requiredToolTerm || `${serverLabel} ${tool.name} ${tool.description ?? ""}`.toLowerCase().includes(requiredToolTerm.toLowerCase())),
    [requiredToolTerm, servers],
  );
  const visibleTools = useMemo(() => {
    const query = search.trim().toLowerCase();
    if (!query) return tools;
    return tools.filter(({ serverLabel, tool }) => `${serverLabel} ${tool.name} ${tool.description ?? ""}`.toLowerCase().includes(query));
  }, [search, tools]);

  function chooseTool(next: CatalogTool) {
    setSelected(next);
    setIntent(intentFrom(next.tool.name));
    setRun(null);
    setRunError(null);
  }

  const startDisabledReason = scopeLoading
    ? "Loading the fixed case scope."
    : scopeError
      ? scopeError
      : !matter || !primaryCourtCase
        ? "A canonical Matter and primary CourtCase are required."
        : capabilityError
          ? capabilityError
          : !capability?.available
            ? "Monitored execution is not available."
            : !intent.trim()
              ? "Describe the operator intent before starting."
              : undefined;

  async function start(arguments_: Record<string, unknown>) {
    if (!selected || !matter || !primaryCourtCase || startDisabledReason) return;
    setRunError(null);
    try {
      setRun(await startAtomicToolAction({
        kind: "atomic_tool",
        intent: intent.trim(),
        matter_id: matter.id,
        court_case_id: primaryCourtCase.id,
        horizon,
        authority_scope: authority,
        tool: { server: selected.serverKey, name: selected.tool.name, arguments: arguments_ },
      }));
    } catch (error) {
      setRunError(errorMessage(error));
      throw error;
    }
  }

  async function cancel() {
    if (!run) return;
    setCancelling(true);
    try {
      setRun(await cancelMonitoredAction(run.action_id));
      setRunError(null);
    } catch (error) {
      setRunError(errorMessage(error));
    } finally {
      setCancelling(false);
    }
  }

  return (
    <div className="space-y-5">
      {!embedded && <nav className="flex flex-wrap border bg-card" aria-label="Monitored action types">
        <AppLink className="border-r px-4 py-3 text-xs font-semibold text-muted-foreground hover:bg-accent" href="/intake">Process workflow</AppLink>
        <span className="border-r border-b-2 border-b-primary bg-accent px-4 py-3 text-xs font-semibold" aria-current="page">Atomic tool</span>
        <AppLink className="px-4 py-3 text-xs font-semibold text-muted-foreground hover:bg-accent" href="/runs">Run history</AppLink>
      </nav>}

      {capabilityError && (
        <div className="flex items-start justify-between gap-4 border border-[#ead5a9] bg-[#fff4dd] px-4 py-3 text-sm text-[#684b18] dark:bg-[#43351f] dark:text-[#ffe0a6]" role="status">
          <span className="flex items-start gap-2"><AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" /> <span><strong className="block">Execution unavailable</strong>{capabilityError}</span></span>
          <Button variant="outline" size="sm" onClick={recheckSurface}><RefreshCw className="h-3.5 w-3.5" /> Recheck</Button>
        </div>
      )}

      <div className="grid min-h-[670px] overflow-hidden border bg-card xl:grid-cols-[330px_minmax(460px,1fr)_390px]">
        <aside className="border-b xl:border-b-0 xl:border-r" aria-label="Atomic tool catalog">
          <div className="border-b p-4">
            <p className="platform-rule-title">Tool catalog</p>
            <div className="relative mt-3">
              <Search className="absolute left-3 top-2.5 h-4 w-4 text-muted-foreground" />
              <Input value={search} onChange={(event) => setSearch(event.target.value)} className="pl-9" placeholder="Search capabilities" aria-label="Search atomic tools" />
            </div>
          </div>
          <div className="max-h-[610px] overflow-auto">
            {catalogLoading ? <p className="flex items-center gap-2 p-5 text-sm text-muted-foreground"><Loader2 className="h-4 w-4 animate-spin" /> Loading governed catalog</p>
              : catalogError ? <p className="p-5 text-sm text-destructive">{catalogError}</p>
                : visibleTools.length ? <ul className="divide-y">{visibleTools.map((item) => (
                  <li key={`${item.serverKey}:${item.tool.name}`}>
                    <button type="button" onClick={() => chooseTool(item)} className={cn("w-full px-4 py-3 text-left hover:bg-accent", selected?.serverKey === item.serverKey && selected.tool.name === item.tool.name && "border-l-2 border-primary bg-accent")}>
                      <span className="flex items-center justify-between gap-3"><strong className="truncate text-sm">{intentFrom(item.tool.name)}</strong><Badge variant="outline" className="shrink-0 text-[9px]">{item.serverLabel}</Badge></span>
                      <span className="mt-1 line-clamp-2 block text-xs leading-5 text-muted-foreground">{item.tool.description || "No catalog description supplied."}</span>
                    </button>
                  </li>
                ))}</ul> : <p className="p-5 text-sm text-muted-foreground">No catalog tools match this search.</p>}
          </div>
        </aside>

        <main className="min-w-0 border-b xl:border-b-0 xl:border-r">
          {!selected ? (
            <div className="grid min-h-[500px] place-content-center p-8 text-center text-muted-foreground"><Wrench className="mx-auto h-8 w-8" /><p className="mt-3 text-sm">Select an atomic capability to define a monitored action.</p></div>
          ) : (
            <div>
              <header className="border-b px-5 py-4">
                <p className="platform-kicker">Operator intent</p>
                <h2 className="mt-1 text-xl font-semibold">{intentFrom(selected.tool.name)}</h2>
                <p className="mt-2 text-sm leading-6 text-muted-foreground">{selected.tool.description || "No catalog description supplied."}</p>
              </header>
              <div className="space-y-6 p-5">
                <section>
                  <label className="platform-rule-title" htmlFor="atomic-intent">What should this action accomplish?</label>
                  <Input id="atomic-intent" className="mt-2" value={intent} onChange={(event) => setIntent(event.target.value)} />
                </section>
                <section className="grid gap-4 sm:grid-cols-2">
                  <label className="text-xs font-semibold">Knowledge horizon
                    <select className="mt-2 h-10 w-full border bg-background px-3 text-sm font-normal" value={horizon} onChange={(event) => setHorizon(event.target.value as StartAtomicToolActionRequest["horizon"])}>
                      <option value="as_lived">As lived at the selected horizon</option><option value="hindsight">Full hindsight</option><option value="paired">Paired comparison</option>
                    </select>
                  </label>
                  <label className="text-xs font-semibold">Authority scope
                    <select className="mt-2 h-10 w-full border bg-background px-3 text-sm font-normal" value={authority} onChange={(event) => setAuthority(event.target.value as StartAtomicToolActionRequest["authority_scope"])}>
                      <option value="read_only">Read only</option><option value="derived_output">Create derived output</option><option value="governed_write">Governed write</option>
                    </select>
                  </label>
                </section>
                <section className="border bg-accent/30 p-4">
                  <div className="flex items-center gap-2"><ShieldCheck className="h-4 w-4 text-[#2f9d67]" /><p className="platform-rule-title">Fixed case scope</p></div>
                  <dl className="mt-3 grid gap-3 text-xs sm:grid-cols-2"><div><dt className="text-muted-foreground">Matter</dt><dd className="mt-1 font-semibold">{matter?.title || (scopeLoading ? "Loading…" : "Unavailable")}</dd></div><div><dt className="text-muted-foreground">Court case</dt><dd className="mt-1 font-semibold">{primaryCourtCase?.caption || primaryCourtCase?.court_name || "Unavailable"}</dd></div></dl>
                </section>
                <section>
                  <p className="platform-rule-title mb-3">Typed inputs</p>
                  <ToolForm serverKey={selected.serverKey} tool={selected.tool} onStart={start} disabled={Boolean(startDisabledReason)} disabledReason={startDisabledReason} />
                </section>
                <details className="border bg-background">
                  <summary className="flex cursor-pointer list-none items-center justify-between px-4 py-3 text-xs font-semibold"><span>Technical details</span><ChevronDown className="h-4 w-4" /></summary>
                  <dl className="grid gap-px border-t bg-border text-xs sm:grid-cols-2"><div className="bg-card p-3"><dt className="text-muted-foreground">Catalog server</dt><dd className="mt-1 font-mono">{selected.serverKey}</dd></div><div className="bg-card p-3"><dt className="text-muted-foreground">Tool identity</dt><dd className="mt-1 break-all font-mono">{selected.tool.name}</dd></div><div className="bg-card p-3 sm:col-span-2"><dt className="text-muted-foreground">Execution boundary</dt><dd className="mt-1">Platform monitored-action API; direct browser invocation is disabled.</dd></div></dl>
                </details>
              </div>
            </div>
          )}
        </main>

        <aside className="bg-accent/20" aria-label="Monitored run">
          <div className="flex items-center justify-between border-b bg-card px-4 py-4"><div><p className="platform-rule-title">Monitored run</p><p className="mt-1 text-xs text-muted-foreground">Status, waits, receipts, and output</p></div>{run && <span className={cn("border px-2 py-1 text-[10px] font-semibold uppercase", statusTone(run.status))}>{run.status}</span>}</div>
          {!run ? <div className="p-6 text-sm leading-6 text-muted-foreground"><Clock3 className="mb-3 h-6 w-6" />A workflow identity appears only after the monitored-action service accepts the request. No placeholder run is created in the browser.</div> : (
            <div className="space-y-5 p-4">
              {runError && <p className="border border-destructive/40 bg-destructive/10 p-3 text-xs text-destructive">{runError}</p>}
              <dl className="space-y-3 border bg-card p-3 text-xs"><div><dt className="text-muted-foreground">Workflow ID</dt><dd className="mt-1 break-all font-mono">{run.workflow_id}</dd></div><div><dt className="text-muted-foreground">Run ID</dt><dd className="mt-1 break-all font-mono">{run.run_id}</dd></div><div className="flex justify-between"><dt className="text-muted-foreground">Retries</dt><dd>{run.retry_count ?? 0}</dd></div></dl>
              {run.waits?.length ? <section><p className="platform-rule-title mb-2">Current waits</p><ul className="space-y-2">{run.waits.map((wait, index) => <li key={`${wait.kind}-${index}`} className="border border-[#ead5a9] bg-[#fff4dd] p-3 text-xs text-[#684b18]"><strong>{wait.kind}</strong>{wait.detail && <p className="mt-1">{wait.detail}</p>}</li>)}</ul></section> : <p className="flex items-center gap-2 text-xs text-muted-foreground"><CircleDot className="h-3.5 w-3.5" /> No reported wait state</p>}
              <section><p className="platform-rule-title mb-2">Receipts</p>{run.receipts?.length ? <ul className="space-y-2">{run.receipts.map((receipt) => <li key={receipt.ref} className="flex gap-2 border bg-card p-3 text-xs"><ReceiptText className="h-4 w-4 shrink-0" /><span><strong className="block">{receipt.label || "Execution receipt"}</strong><span className="break-all font-mono text-[10px] text-muted-foreground">{receipt.ref}</span></span></li>)}</ul> : <p className="text-xs text-muted-foreground">No receipt has been returned yet.</p>}</section>
              {(run.output !== undefined || run.output_ref) && <section><p className="platform-rule-title mb-2">Output</p><pre className="max-h-52 overflow-auto whitespace-pre-wrap border bg-card p-3 text-[10px]">{run.output !== undefined ? JSON.stringify(run.output, null, 2) : run.output_ref}</pre></section>}
              {run.error && <p className="border border-destructive/40 bg-destructive/10 p-3 text-xs text-destructive">{run.error}</p>}
              <div className="flex flex-wrap gap-2">
                {capability?.supports_live_status && <Button variant="outline" size="sm" onClick={() => void getMonitoredAction(run.action_id).then(setRun).catch((error) => setRunError(errorMessage(error)))}><RefreshCw className="h-3.5 w-3.5" /> Refresh</Button>}
                {capability?.supports_cancel && activeStatuses.has(run.status) && <Button variant="destructive" size="sm" onClick={() => void cancel()} disabled={cancelling}>{cancelling ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Ban className="h-3.5 w-3.5" />} Cancel</Button>}
                {run.status === "completed" && <span className="flex items-center gap-1 text-xs font-semibold text-[#17794b]"><CheckCircle2 className="h-4 w-4" /> Completed with server receipt</span>}
              </div>
            </div>
          )}
        </aside>
      </div>
    </div>
  );
}
