// Byline: Codex · GPT-5 · 2026-08-15 (Matter workspace MVP and readiness inspection)
"use client";

import { useEffect, useState } from "react";
import { AppLink as Link, useBrowserSearchParams } from "@/lib/router-compat";
import { AlertTriangle, BriefcaseBusiness, Loader2, Scale } from "lucide-react";

import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { KnowledgeBrowser } from "@/components/knowledge/knowledge-browser";
import { useFixedCase } from "@/lib/fixed-case-context";
import {
  ApiError,
  getCaseManagementCapabilities,
  getMatter,
  listEvidenceItems,
  listMatters,
} from "@/lib/api-client";
import type { CaseManagementCapabilities } from "@/lib/api-client";
import type { EvidenceItem, Matter, MatterDetail } from "@/lib/shared/types";
import { EvidenceDetailDialog } from "./evidence-detail-dialog";
import { CourtReadinessDialog } from "./court-readiness-dialog";
import { EvidenceReviewDialog, EvidenceReviewHistoryDialog } from "./evidence-review-dialog";
import { CreateCourtCaseDialog } from "./matter-creation-dialogs";

function errorText(error: unknown) {
  return error instanceof ApiError ? error.message : "Unable to load the Matter workspace";
}

export function MatterWorkspace() {
  const { mode } = useFixedCase();
  return <ModeScopedMatterWorkspace key={mode} mode={mode} />;
}

function ModeScopedMatterWorkspace({ mode }: { mode: "TEST" | "REAL" }) {
  const searchParams = useBrowserSearchParams();
  const matterId = searchParams.get("matter_id")?.trim() || null;
  const [matters, setMatters] = useState<Matter[]>([]);
  const [matter, setMatter] = useState<MatterDetail | null>(null);
  const [evidence, setEvidence] = useState<EvidenceItem[]>([]);
  const [capabilities, setCapabilities] = useState<CaseManagementCapabilities | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loadedScope, setLoadedScope] = useState<string | null | undefined>(undefined);
  const loading = loadedScope !== matterId;

  useEffect(() => {
    let cancelled = false;
    const request = matterId
      ? Promise.all([getMatter(matterId, mode), getCaseManagementCapabilities()]).then(async ([detail, capability]) => ({
          detail,
          capability,
          items: capability.advanced_evidence_available
            ? (await listEvidenceItems(matterId, mode)).data
            : [],
          matters: [] as Matter[],
        }))
      : listMatters(50, 0, mode).then((response) => ({
          detail: null,
          capability: null,
          items: [] as EvidenceItem[],
          matters: response.data,
        }));

    request
      .then((result) => {
        if (cancelled) return;
        setMatter(result.detail);
        setEvidence(result.items);
        setCapabilities(result.capability);
        setMatters(result.matters);
        setError(null);
      })
      .catch((requestError: unknown) => {
        if (cancelled) return;
        setMatter(null);
        setEvidence([]);
        setCapabilities(null);
        setMatters([]);
        setError(errorText(requestError));
      })
      .finally(() => {
        if (!cancelled) setLoadedScope(matterId);
      });

    return () => {
      cancelled = true;
    };
  }, [matterId, mode]);

  if (loading) {
    return (
      <div className="flex min-h-48 items-center justify-center" role="status">
        <Loader2 className="mr-2 animate-spin" aria-hidden="true" /> Loading Matter workspace
      </div>
    );
  }

  if (error) {
    return (
      <Card className="border-destructive">
        <CardHeader><CardTitle>Workspace unavailable</CardTitle></CardHeader>
        <CardContent className="text-sm text-destructive">{error}</CardContent>
      </Card>
    );
  }

  if (!matterId) {
    return (
      <div className="space-y-4">
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div>
            <h1 className="text-3xl font-bold tracking-tight">Matters</h1>
            <p className="mt-1 text-sm text-muted-foreground">
              Choose an enduring Matter workspace. Court proceedings remain separate within it.
            </p>
          </div>
        </div>
        {matters.length === 0 ? (
          <Card><CardContent className="py-10 text-center text-sm text-muted-foreground">No Matter workspace is available.</CardContent></Card>
        ) : (
          <div className="grid gap-3 md:grid-cols-2">
            {matters.map((item) => (
              <Link key={item.id} href={`/matter?matter_id=${encodeURIComponent(item.id)}`}>
                <Card className="h-full transition-colors hover:border-primary">
                  <CardHeader>
                    <CardTitle className="flex items-center gap-2"><BriefcaseBusiness className="h-5 w-5" />{item.title}</CardTitle>
                    <CardDescription>{item.description || "No description"}</CardDescription>
                  </CardHeader>
                  <CardContent className="flex flex-wrap gap-2">
                    <Badge>{item.status}</Badge>
                    {item.partition_keys.map((key) => <Badge key={key} variant="outline">Partition: {key}</Badge>)}
                  </CardContent>
                </Card>
              </Link>
            ))}
          </div>
        )}
      </div>
    );
  }

  if (!matter) return null;

  const partitionKey = matter.partition_keys.length === 1 ? matter.partition_keys[0] : undefined;
  const primaryCourtCase = matter.court_cases.find((courtCase) => courtCase.is_primary);
  const advancedEvidenceAvailable = capabilities?.advanced_evidence_available === true;

  return (
    <div className="space-y-6">
      <div>
        <div className="flex flex-wrap items-center gap-2">
          <h1 className="text-3xl font-bold tracking-tight">{matter.title}</h1>
          <Badge>{matter.status}</Badge>
        </div>
        <p className="mt-1 text-sm text-muted-foreground">{matter.description || "Matter workspace"}</p>
      </div>

      <div className="grid gap-4 lg:grid-cols-3">
        <Card>
          <CardHeader><CardTitle className="text-base">Knowledge partitions</CardTitle></CardHeader>
          <CardContent className="flex flex-wrap gap-2">
            {matter.partition_keys.map((key) => <Badge key={key} variant="outline">{key}</Badge>)}
          </CardContent>
        </Card>
        <Card className="lg:col-span-2">
          <CardHeader className="flex-row items-start justify-between gap-3">
            <div className="space-y-1.5">
              <CardTitle className="text-base">Court proceedings</CardTitle>
              <CardDescription>Proceedings are scoped within this Matter; they are not Knowledge partition keys.</CardDescription>
            </div>
            <CreateCourtCaseDialog
              matterId={matter.id}
              onCreated={(created) => setMatter((current) => current ? {
                ...current,
                court_cases: [
                  ...current.court_cases.map((item) => created.is_primary ? { ...item, is_primary: false } : item),
                  created,
                ],
              } : current)}
            />
          </CardHeader>
          <CardContent className="space-y-2">
            {matter.court_cases.length === 0 ? (
              <p className="text-sm text-muted-foreground">No court proceeding is configured.</p>
            ) : matter.court_cases.map((courtCase) => (
              <div key={courtCase.id} className="flex flex-wrap items-center gap-2 rounded-md border p-3">
                <Scale className="h-4 w-4" aria-hidden="true" />
                <span className="font-medium">{courtCase.caption}</span>
                {courtCase.is_primary && <Badge>Primary</Badge>}
                <Badge variant="outline">{courtCase.status}</Badge>
                {courtCase.docket_number && <span className="text-xs text-muted-foreground">Docket {courtCase.docket_number}</span>}
              </div>
            ))}
          </CardContent>
        </Card>
      </div>

      {advancedEvidenceAvailable && partitionKey ? (
        <section aria-labelledby="matter-knowledge-heading" className="space-y-3">
          <div>
            <h2 id="matter-knowledge-heading" className="text-xl font-semibold tracking-tight">
              Find canonical Knowledge
            </h2>
            <p className="mt-1 text-sm text-muted-foreground">
              Search this Matter&apos;s bound partition and promote only an exact, custody-backed normalized record.
            </p>
          </div>
          <KnowledgeBrowser
            key={`${matter.id}:${partitionKey}:${primaryCourtCase?.id ?? "no-primary"}`}
            matterContext={{
              matter,
              partitionKey,
              defaultCourtCaseId: primaryCourtCase?.id,
              onEvidencePromoted: (promotion) => setEvidence((current) => [
                promotion.item,
                ...current.filter((item) => item.id !== promotion.item.id),
              ]),
            }}
          />
        </section>
      ) : advancedEvidenceAvailable ? (
        <Card className="border-amber-500/60" role="status">
          <CardHeader>
            <CardTitle className="flex items-center gap-2 text-base">
              <AlertTriangle className="h-4 w-4 text-amber-600" aria-hidden="true" />
              Knowledge search unavailable
            </CardTitle>
            <CardDescription>
              {matter.partition_keys.length === 0
                ? "This Matter has no explicit Knowledge partition. Search and promotion stay disabled until one is bound."
                : "This Matter has multiple Knowledge partitions. Search and promotion stay disabled until the operator explicitly selects a partition."}
            </CardDescription>
          </CardHeader>
        </Card>
      ) : (
        <Card className="border-amber-500/60" role="status">
          <CardHeader>
            <CardTitle className="flex items-center gap-2 text-base">
              <AlertTriangle className="h-4 w-4 text-amber-600" aria-hidden="true" />
              Evidence operations not yet available
            </CardTitle>
            <CardDescription>
              {capabilities?.advanced_evidence_reason || "The platform-native evidence substrate is unavailable."}
            </CardDescription>
          </CardHeader>
        </Card>
      )}

      {advancedEvidenceAvailable && <Card>
        <CardHeader>
          <CardTitle>Draft evidence</CardTitle>
          <CardDescription>Knowledge-derived items enter a human review queue; they are never legal-ready on creation.</CardDescription>
        </CardHeader>
        <CardContent className="space-y-3">
          {evidence.length === 0 ? (
            <p className="py-8 text-center text-sm text-muted-foreground">No draft evidence has been added.</p>
          ) : evidence.map((item) => (
            <article key={item.id} className="rounded-lg border border-amber-500/60 bg-amber-500/5 p-4">
              <div className="mb-2 flex flex-wrap items-center gap-2">
                <AlertTriangle className="h-4 w-4 text-amber-600" aria-hidden="true" />
                <span className="font-medium">{item.title}</span>
                <Badge variant="outline">{item.review_status}</Badge>
                {item.hitl_required && <Badge variant="outline">HITL required</Badge>}
                {!item.safe_for_legal_use && <Badge variant="destructive">Unsafe for legal use</Badge>}
                <EvidenceDetailDialog item={item} />
                <CourtReadinessDialog item={item} />
                {item.hitl_required && (
                  <EvidenceReviewDialog
                    item={item}
                    onReviewed={(result) => setEvidence((current) => current.map((candidate) => (
                      candidate.id === result.item.id ? result.item : candidate
                    )))}
                  />
                )}
                <EvidenceReviewHistoryDialog item={item} />
              </div>
              {item.quote && <blockquote className="border-l-2 pl-3 text-sm text-muted-foreground">{item.quote}</blockquote>}
              <p className="mt-2 font-mono text-xs text-muted-foreground">Record {item.normalized_record_id}</p>
            </article>
          ))}
        </CardContent>
      </Card>}
    </div>
  );
}
