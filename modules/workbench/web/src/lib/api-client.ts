// Byline: Claude Code · Sonnet (agent) · 2026-07-22 (C3: records, schemas, verify, parse-dryrun, flags; C4: knowledge search/browse + Graphiti pane added 2026-07-23)
// Byline: Codex · GPT-5 · 2026-08-15 (run reports, review actions, and court readiness)
// Byline: Codex · GPT-5 · 2026-08-18 (conversation intake and governed entities)
// Byline amendment: Codex · GPT-5 · 2026-08-18 (third-party review client)
// Byline: Codex · GPT-5 · 2026-08-18 (native evidence horizon search parameter)
// Byline: Codex · GPT-5 · 2026-08-28 (proffer workflow (formerly Universal Import Workflow) client)
/**
 * API client for the Knowledge Workbench.
 *
 * The static export (`output: "export"`) is served same-origin by the
 * platform's FastAPI backend, so the base URL is empty by default — every
 * call resolves relative to the page's own origin. `VITE_API_URL` remains a
 * supported build-time override for browser development against a backend on
 * a different port.
 */
import type {
  CustodyTier,
  CourtCase,
  CourtCaseStatus,
  EvidenceDetail,
  EvidenceSourceContent,
  EvidenceConversationContext,
  CourtReadiness,
  EvidenceItemListResponse,
  EvidencePromotionResult,
  EvidenceReviewDecision,
  EvidenceReviewListResponse,
  EvidenceReviewResult,
  FileAnalysis,
  FileTextResponse,
  Flag,
  FlagCreateRequest,
  FlagStatus,
  FlagTargetKind,
  FlagUpdateRequest,
  GraphitiEpisodesResponse,
  GraphitiFactsResponse,
  GraphitiNodesResponse,
  HealthDepsResponse,
  KnowledgeContentsResponse,
  KnowledgeItemDetail,
  KnowledgeSourceRef,
  KnowledgeSourceResolution,
  KnowledgeSearchResponse,
  Matter,
  MatterDetail,
  MatterListResponse,
  ParseDryrunResponse,
  PgSchemaName,
  RecordMetaPatch,
  RecordRow,
  RecordsListResponse,
  RetryFromStage,
  RunAbortResponse,
  RunContinueResponse,
  RunCreateResponse,
  RunDetail,
  RunMode,
  RunReport,
  RunReviewAction,
  RunReviewActionRequest,
  RunRetryResponse,
  RunSummary,
  SchemasResponse,
  TableDetail,
  ThirdPartyApprovalRequest,
  ThirdPartyApprovalResponse,
  AcquisitionAssertionInput,
  GovernedEntitiesResponse,
  GovernedEntity,
  MessageCorpus,
  StagedFile,
  StagedFileMeta,
  ToolServerGroup,
  MonitoredActionCapability,
  MonitoredActionRun,
  StartAtomicToolActionRequest,
  UploadResponse,
  VerifyResponse,
  WeaviateDetail,
  Workflow,
  ProfferOperationDetail,
  ProfferOperationLifecycle,
  ProfferOperationListResponse,
  ProfferDecisionResponse,
  ProfferPreviewResponse,
  ProfferRepairDecisionRequest,
  ProfferRepairDecisionResponse,
  ProfferPreviewMessagesResponse,
  ProfferStartRequest,
  ProfferStartResponse,
  ProfferUploadResponse,
  ProfferSourceBrowserResponse,
  ProfferSourceInspection,
  ProfferSourceObject,
  ProfferHumanSourceAssertions,
  ProfferSourceContextReceipt,
} from "./shared/types";

const API_BASE = import.meta.env.VITE_API_URL || "";

/** Typed API error with HTTP status code for caller-side branching. */
export class ApiError extends Error {
  constructor(
    message: string,
    public readonly status: number,
  ) {
    super(message);
    this.name = "ApiError";
  }

  /** True for 408, 429, 500, 502, 503, 504 — worth retrying. */
  get isRetryable(): boolean {
    return [408, 429, 500, 502, 503, 504].includes(this.status);
  }

  get isNotFound(): boolean {
    return this.status === 404;
  }

  get isConflict(): boolean {
    return this.status === 409;
  }

  /** 410 — the spine has retired the resource (e.g. a stale gate action
   * racing a run that moved on). Distinct from isConflict(409): a 409
   * means "not in the right state right now", a 410 means "gone for good". */
  get isGone(): boolean {
    return this.status === 410;
  }
}

async function apiFetch<T>(path: string, init?: RequestInit): Promise<T> {
  let res: Response;
  try {
    res = await fetch(`${API_BASE}${path}`, init);
  } catch {
    // Network failure (offline, DNS, CORS, etc.)
    throw new ApiError("Network error — check your connection", 0);
  }
  if (!res.ok) {
    const body = await res.json().catch(() => ({}));
    throw new ApiError(
      body.detail || `API error: ${res.status}`,
      res.status,
    );
  }
  return res.json();
}

export async function getHealth() {
  return apiFetch<{ status: string }>("/health");
}

/** Console header's dependency status chips (C2.6 requirement 4) —
 * `{lancedb, object_store, pg, milvus, checked_at}`. */
export async function getHealthDeps() {
  return apiFetch<HealthDepsResponse>("/api/health/deps");
}

export interface ListFilesParams {
  status?: string;
  detected_type?: string;
}

export async function listFiles(params: ListFilesParams = {}) {
  const qs = new URLSearchParams();
  if (params.status) qs.set("status", params.status);
  if (params.detected_type) qs.set("detected_type", params.detected_type);
  const suffix = qs.toString() ? `?${qs.toString()}` : "";
  return apiFetch<StagedFile[]>(`/api/files${suffix}`);
}

export async function getFile(id: string) {
  return apiFetch<StagedFile>(`/api/files/${encodeURIComponent(id)}`);
}

export async function updateFileMeta(id: string, patch: Partial<StagedFileMeta>) {
  return apiFetch<StagedFile>(`/api/files/${encodeURIComponent(id)}`, {
    method: "PATCH",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(patch),
  });
}

/** Full, untruncated extracted text for the Preview modal (C2.7). */
export async function getFileText(id: string) {
  return apiFetch<FileTextResponse>(`/api/files/${encodeURIComponent(id)}/text`);
}

/** Re-run the server's detect.py sniffing + basic shape stats (C2.7). */
export async function analyzeFile(id: string) {
  return apiFetch<FileAnalysis>(`/api/files/${encodeURIComponent(id)}/analyze`, {
    method: "POST",
  });
}

// ---------------------------------------------------------------------------
// Repair control surface
// ---------------------------------------------------------------------------

export interface RepairToolCard {
  id: string;
  category: string;
  description: string;
  execution_policy: "manual_or_auto" | "manual_approval_required" | string;
  side_effect: string;
}

export async function listRepairTools() {
  return apiFetch<RepairToolCard[]>("/api/repairs/tools");
}

export async function runAutomaticRepairAssessment(path: string, format?: string) {
  return apiFetch<Record<string, unknown>>("/api/repairs/automatic-assessment", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ path, format: format || null, sample_limit: 25 }),
  });
}

export async function executeRepairTool(
  toolId: string,
  payload: Record<string, unknown>,
  approved = false,
) {
  return apiFetch<Record<string, unknown>>("/api/repairs/execute", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ tool_id: toolId, payload, approved }),
  });
}

// ---------------------------------------------------------------------------
// Runs (C1 Operator Console)
// ---------------------------------------------------------------------------

export interface ListRunsParams {
  status?: string;
  limit?: number;
}

export async function listRuns(params: ListRunsParams = {}) {
  const qs = new URLSearchParams();
  if (params.status) qs.set("status", params.status);
  if (params.limit) qs.set("limit", String(params.limit));
  const suffix = qs.toString() ? `?${qs.toString()}` : "";
  return apiFetch<RunSummary[]>(`/api/runs${suffix}`);
}

export async function getRun(runId: string) {
  return apiFetch<RunDetail>(`/api/runs/${encodeURIComponent(runId)}`);
}

/** Start a run from an already-staged file (JSON body — no re-upload). */
export async function createRunFromStaged(params: {
  stagedId: string;
  workflow: Workflow | string;
  domain: string;
  mode: RunMode;
  custodyTier?: CustodyTier;
  sourceMeta?: Record<string, unknown>;
  messageCorpus: MessageCorpus;
  sourcePrincipal: string;
  callerOwnsConversation: boolean;
  acquisition?: AcquisitionAssertionInput;
}) {
  return apiFetch<RunCreateResponse>("/api/runs", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      staged_id: params.stagedId,
      workflow: params.workflow,
      domain: params.domain,
      mode: params.mode,
      custody_tier: params.custodyTier ?? null,
      source_meta: params.sourceMeta ?? null,
      message_corpus: params.messageCorpus,
      source_principal: params.sourcePrincipal,
      caller_owns_conversation: params.callerOwnsConversation,
      acquisition: params.acquisition ?? null,
    }),
  });
}

/** Start a run from a freshly dropped file (multipart — never lands in staging). */
export async function createRunFromFile(params: {
  file: File;
  workflow: Workflow | string;
  domain: string;
  mode: RunMode;
  custodyTier?: CustodyTier;
  sourceMeta?: Record<string, unknown>;
  messageCorpus: MessageCorpus;
  sourcePrincipal: string;
  callerOwnsConversation: boolean;
  acquisition?: AcquisitionAssertionInput;
}) {
  const formData = new FormData();
  formData.append("file", params.file);
  formData.append("workflow", params.workflow);
  formData.append("domain", params.domain);
  formData.append("mode", params.mode);
  if (params.custodyTier) formData.append("custody_tier", params.custodyTier);
  if (params.sourceMeta) formData.append("source_meta", JSON.stringify(params.sourceMeta));
  formData.append("message_corpus", params.messageCorpus);
  formData.append("source_principal", params.sourcePrincipal);
  formData.append("caller_owns_conversation", String(params.callerOwnsConversation));
  if (params.acquisition) formData.append("acquisition", JSON.stringify(params.acquisition));
  return apiFetch<RunCreateResponse>("/api/runs", { method: "POST", body: formData });
}

// ---------------------------------------------------------------------------
// Run gate controls (C2)
// ---------------------------------------------------------------------------

/** Release a gated (paused) run past its current stage boundary. Throws
 * ApiError(409) if the run isn't paused. */
export async function continueRun(runId: string) {
  return apiFetch<RunContinueResponse>(`/api/runs/${encodeURIComponent(runId)}/continue`, {
    method: "POST",
  });
}

/** Abort a running or gated run. While `running`, this takes effect at the
 * next stage boundary rather than instantly. Throws ApiError(409) if the
 * run is already terminal. */
export async function abortRun(runId: string) {
  return apiFetch<RunAbortResponse>(`/api/runs/${encodeURIComponent(runId)}/abort`, {
    method: "POST",
  });
}

/** Start a fresh run from a terminal-failed one. The returned `run_id` is
 * the NEW run (not the one passed in) — open that run to watch it.
 * Throws ApiError(409) if the source run isn't terminal-failed.
 *
 * `fromStage` (C2.6, optional): pass `"knowledge"` to skip straight to
 * re-running the knowledge stage over the parent's already-stored records
 * instead of a full custody->parse->store->knowledge rerun — see
 * `RetryFromStage`'s doc comment. Omit for the pre-C2.6 full-rerun. */
export async function retryRun(runId: string, fromStage?: RetryFromStage) {
  return apiFetch<RunRetryResponse>(`/api/runs/${encodeURIComponent(runId)}/retry`, {
    method: "POST",
    ...(fromStage
      ? { headers: { "Content-Type": "application/json" }, body: JSON.stringify({ from_stage: fromStage }) }
      : {}),
  });
}

export async function getRunReport(runId: string) {
  return apiFetch<RunReport>(`/api/runs/${encodeURIComponent(runId)}/report`);
}

export async function createRunReviewAction(runId: string, payload: RunReviewActionRequest) {
  return apiFetch<RunReviewAction>(`/api/runs/${encodeURIComponent(runId)}/review-actions`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
}

// ---------------------------------------------------------------------------
// Records (C3 — parse-quality review + curation)
// ---------------------------------------------------------------------------

export interface ListRecordsParams {
  artifactId?: string;
  runId?: string;
  q?: string;
  limit?: number;
  offset?: number;
}

export async function listRecords(params: ListRecordsParams = {}) {
  const qs = new URLSearchParams();
  if (params.artifactId) qs.set("artifact_id", params.artifactId);
  if (params.runId) qs.set("run_id", params.runId);
  if (params.q) qs.set("q", params.q);
  if (params.limit) qs.set("limit", String(params.limit));
  if (params.offset) qs.set("offset", String(params.offset));
  const suffix = qs.toString() ? `?${qs.toString()}` : "";
  return apiFetch<RecordsListResponse>(`/api/records${suffix}`);
}

/** Curation-only edit (title/labels/attrs_patch) — never touches evidence
 * blobs/hashes. Returns the updated record row. */
export async function patchRecordMeta(recordId: string, patch: RecordMetaPatch) {
  return apiFetch<RecordRow>(`/api/records/${encodeURIComponent(recordId)}/meta`, {
    method: "PATCH",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(patch),
  });
}

// ---------------------------------------------------------------------------
// Data Explorer (read-only PostgreSQL + Weaviate inspection views)
// ---------------------------------------------------------------------------

export async function getSchemas() {
  return apiFetch<SchemasResponse>("/api/schemas");
}

export async function approveThirdPartyConversation(
  conversationId: string,
  review: ThirdPartyApprovalRequest,
) {
  return apiFetch<ThirdPartyApprovalResponse>(
    `/api/third-party-conversations/${encodeURIComponent(conversationId)}/approve`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(review),
    },
  );
}

export async function listGovernedEntities(query = "", limit = 20) {
  const qs = new URLSearchParams({ limit: String(limit) });
  if (query.trim()) qs.set("q", query.trim());
  return apiFetch<GovernedEntitiesResponse>(`/api/entities?${qs.toString()}`);
}

export async function createGovernedEntity(payload: { display_name: string; entity_type?: string }) {
  return apiFetch<GovernedEntity>("/api/entities", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
}

export async function getTableDetail(schema: PgSchemaName, table: string, limit = 5) {
  const qs = new URLSearchParams({ limit: String(limit) });
  return apiFetch<TableDetail>(
    `/api/schemas/postgresql/${encodeURIComponent(schema)}/${encodeURIComponent(table)}?${qs.toString()}`,
  );
}

export async function getWeaviateDetail(collection: string, limit = 5) {
  const qs = new URLSearchParams({ limit: String(limit) });
  return apiFetch<WeaviateDetail>(
    `/api/schemas/weaviate/${encodeURIComponent(collection)}?${qs.toString()}`,
  );
}

// ---------------------------------------------------------------------------
// Verify (C3 — active hash verification)
// ---------------------------------------------------------------------------

export async function verifySha256(sha256: string) {
  return apiFetch<VerifyResponse>(`/api/verify/${encodeURIComponent(sha256)}`, {
    method: "POST",
  });
}

// ---------------------------------------------------------------------------
// Parse dry-run (C3 — "the real parser candidates")
// ---------------------------------------------------------------------------

/** Dry-run parse an already-staged file by sha256 — no run is created. */
export async function parseDryrunSha(sha256: string) {
  return apiFetch<ParseDryrunResponse>("/api/runs/parse-dryrun", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ sha256 }),
  });
}

/** Dry-run parse a fresh, not-yet-staged file — no run is created. */
export async function parseDryrunFile(file: File) {
  const formData = new FormData();
  formData.append("file", file);
  return apiFetch<ParseDryrunResponse>("/api/runs/parse-dryrun", { method: "POST", body: formData });
}

// ---------------------------------------------------------------------------
// Corroboration flags (C3 — requirements addendum 6)
// ---------------------------------------------------------------------------

export interface ListFlagsParams {
  status?: FlagStatus;
  targetKind?: FlagTargetKind;
}

export async function listFlags(params: ListFlagsParams = {}) {
  const qs = new URLSearchParams();
  if (params.status) qs.set("status", params.status);
  if (params.targetKind) qs.set("target_kind", params.targetKind);
  const suffix = qs.toString() ? `?${qs.toString()}` : "";
  return apiFetch<Flag[]>(`/api/flags${suffix}`);
}

export async function createFlag(payload: FlagCreateRequest) {
  return apiFetch<Flag>("/api/flags", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
}

export async function updateFlag(flagId: string, patch: FlagUpdateRequest) {
  return apiFetch<Flag>(`/api/flags/${encodeURIComponent(flagId)}`, {
    method: "PATCH",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(patch),
  });
}

// ---------------------------------------------------------------------------
// Knowledge (Weaviate projection search + canonical PostgreSQL browse/detail)
// ---------------------------------------------------------------------------

export interface SearchKnowledgeParams {
  caseId?: string;
  lane?: string;
  limit?: number;
  /** Optional as-lived ceiling. The evidence service clamps omitted searches
   * to the current instant and never accepts disclosure tiers from callers. */
  horizon?: string;
}

export async function searchKnowledge(query: string, params: SearchKnowledgeParams = {}) {
  const qs = new URLSearchParams({ q: query });
  qs.set("case_id", params.caseId || "primary");
  if (params.lane) qs.set("lane", params.lane);
  if (params.limit) qs.set("limit", String(params.limit));
  if (params.horizon) qs.set("horizon", params.horizon);
  return apiFetch<KnowledgeSearchResponse>(`/api/knowledge/search?${qs.toString()}`);
}

export interface ListKnowledgeContentsParams {
  caseId: string;
  lane: string;
  limit?: number;
  offset?: number;
}

export async function listKnowledgeContents(params: ListKnowledgeContentsParams) {
  const qs = new URLSearchParams();
  qs.set("case_id", params.caseId);
  qs.set("lane", params.lane);
  if (params.limit) qs.set("limit", String(params.limit));
  if (params.offset) qs.set("offset", String(params.offset));
  const suffix = qs.toString() ? `?${qs.toString()}` : "";
  return apiFetch<KnowledgeContentsResponse>(`/api/knowledge/contents${suffix}`);
}

export async function getKnowledgeContent(artifactId: string, caseId: string) {
  const qs = new URLSearchParams({ case_id: caseId });
  return apiFetch<KnowledgeItemDetail>(
    `/api/knowledge/contents/${encodeURIComponent(artifactId)}?${qs.toString()}`,
  );
}

// ---------------------------------------------------------------------------
// Matter workspace (framework-neutral spine API, via Workbench proxy)
// ---------------------------------------------------------------------------

export async function listMatters(limit = 50, offset = 0) {
  const qs = new URLSearchParams({ limit: String(limit), offset: String(offset) });
  return apiFetch<MatterListResponse>(`/api/matters?${qs.toString()}`);
}

export async function createMatter(payload: {
  title: string;
  description?: string;
  partition_key?: string;
  created_by?: "owner";
}) {
  return apiFetch<Matter>("/api/matters", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
}

export async function getMatter(matterId: string) {
  return apiFetch<MatterDetail>(`/api/matters/${encodeURIComponent(matterId)}`);
}

export interface CaseManagementCapabilities {
  registry_available: boolean;
  advanced_evidence_available: boolean;
  advanced_evidence_reason: string;
}

export async function getCaseManagementCapabilities() {
  return apiFetch<CaseManagementCapabilities>("/api/case-management/capabilities");
}

// ---------------------------------------------------------------------------
// proffer workflow (formerly Universal Import Workflow) — production acquisition and decision boundary
// ---------------------------------------------------------------------------

export async function uploadProfferSource(file: File) {
  const response = await fetch(`${API_BASE}/api/proffer/upload`, {
    method: "POST",
    headers: {
      "Content-Type": file.type || "application/octet-stream",
      "X-Source-Filename": file.name,
    },
    body: file,
    credentials: "same-origin",
  });
  if (!response.ok) {
    let detail = `Upload failed (${response.status})`;
    try {
      const body = await response.json();
      if (typeof body?.detail === "string") detail = body.detail;
    } catch {
      // Preserve the status-based message when the upstream body is not JSON.
    }
    throw new ApiError(detail, response.status);
  }
  return (await response.json()) as ProfferUploadResponse;
}

export function listProfferSources(params: {
  prefix?: string;
  continuationToken?: string;
  filter?: string;
  pageSize?: number;
} = {}) {
  const query = new URLSearchParams();
  if (params.prefix) query.set("prefix", params.prefix);
  if (params.continuationToken) query.set("continuation_token", params.continuationToken);
  if (params.filter) query.set("filter", params.filter);
  if (params.pageSize) query.set("page_size", String(params.pageSize));
  const suffix = query.size ? `?${query.toString()}` : "";
  return apiFetch<ProfferSourceBrowserResponse>(`/api/proffer/sources${suffix}`);
}

export function inspectProfferSource(source: ProfferSourceObject) {
  return apiFetch<ProfferSourceInspection>("/api/proffer/source-inspection", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      key: source.key,
      expected_byte_length: source.byte_length,
      expected_etag: source.etag ?? null,
    }),
  });
}

export function createProfferSourceContext(payload: {
  request_id: string;
  matter_id: string;
  court_case_id: string;
  source_ref: string;
  observed_source: {
    key: string;
    name: string;
    byte_length: number;
    etag: string;
    preview_sha256: string;
    verification_state: "preview_only";
  };
  supersedes_ref?: string | null;
  assertions: ProfferHumanSourceAssertions;
  change_reason: string;
}) {
  return apiFetch<ProfferSourceContextReceipt>("/api/proffer/source-contexts", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
}

export function startProffer(payload: ProfferStartRequest) {
  return apiFetch<ProfferStartResponse>("/api/proffer/start", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
}

export function getProfferPreview(previewHandle: string, signal?: AbortSignal) {
  return apiFetch<ProfferPreviewResponse>(`/api/proffer/previews/${encodeURIComponent(previewHandle)}`, { signal });
}

export function listProfferOperations(params: {
  status?: ProfferOperationLifecycle;
  cursor?: string;
  limit?: number;
} = {}, signal?: AbortSignal) {
  const query = new URLSearchParams();
  if (params.status) query.set("status", params.status);
  if (params.cursor) query.set("cursor", params.cursor);
  if (params.limit) query.set("limit", String(params.limit));
  const suffix = query.size ? `?${query.toString()}` : "";
  return apiFetch<ProfferOperationListResponse>(`/api/proffer/operations${suffix}`, { signal });
}

export function getProfferOperation(previewHandle: string, signal?: AbortSignal) {
  return apiFetch<ProfferOperationDetail>(
    `/api/proffer/operations/${encodeURIComponent(previewHandle)}`,
    { signal },
  );
}

export function decideProfferRepair(previewHandle: string, payload: ProfferRepairDecisionRequest) {
  return apiFetch<ProfferRepairDecisionResponse>(
    `/api/proffer/previews/${encodeURIComponent(previewHandle)}/repair-decision`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    },
  );
}

export function decideProffer(
  previewHandle: string,
  payload: { approved: boolean; reason: string },
) {
  return apiFetch<ProfferDecisionResponse>(`/api/proffer/previews/${encodeURIComponent(previewHandle)}/decision`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
}

export function getProfferPreviewMessages(
  previewHandle: string,
  cursor?: string,
  limit = 100,
  signal?: AbortSignal,
) {
  const query = new URLSearchParams({ limit: String(limit) });
  if (cursor) query.set("cursor", cursor);
  return apiFetch<ProfferPreviewMessagesResponse>(
    `/api/proffer/previews/${encodeURIComponent(previewHandle)}/messages?${query.toString()}`,
    { signal },
  );
}

export function createProfferPreviewEventSource(previewHandle: string) {
  return new EventSource(
    `${API_BASE}/api/proffer/previews/${encodeURIComponent(previewHandle)}/events`,
    { withCredentials: true },
  );
}

export async function createCourtCase(
  matterId: string,
  payload: {
    caption: string;
    court_name?: string;
    docket_number?: string;
    jurisdiction?: string;
    case_type?: string;
    status?: CourtCaseStatus;
    filed_on?: string;
    closed_on?: string;
    is_primary?: boolean;
    created_by?: "owner";
  },
) {
  return apiFetch<CourtCase>(`/api/matters/${encodeURIComponent(matterId)}/court-cases`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
}

export async function resolveKnowledgeSource(matterId: string, source: KnowledgeSourceRef) {
  return apiFetch<KnowledgeSourceResolution>(
    `/api/matters/${encodeURIComponent(matterId)}/knowledge/resolve`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(source),
    },
  );
}

export async function createEvidenceItem(
  matterId: string,
  payload: {
    court_case_id: string;
    source: KnowledgeSourceRef & { normalized_record_id: string };
    title: string;
    description?: string;
    quote?: string;
    evidence_type?: string;
    created_by?: "owner";
  },
) {
  return apiFetch<EvidencePromotionResult>(
    `/api/matters/${encodeURIComponent(matterId)}/evidence-items`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    },
  );
}

export async function listEvidenceItems(matterId: string, limit = 50, offset = 0) {
  const qs = new URLSearchParams({ limit: String(limit), offset: String(offset) });
  return apiFetch<EvidenceItemListResponse>(
    `/api/matters/${encodeURIComponent(matterId)}/evidence-items?${qs.toString()}`,
  );
}

export async function getEvidenceDetail(matterId: string, evidenceItemId: string) {
  return apiFetch<EvidenceDetail>(
    `/api/matters/${encodeURIComponent(matterId)}/evidence-items/${encodeURIComponent(evidenceItemId)}`,
  );
}

export async function getEvidenceSourceContent(matterId: string, evidenceItemId: string) {
  return apiFetch<EvidenceSourceContent>(
    `/api/matters/${encodeURIComponent(matterId)}/evidence-items/${encodeURIComponent(evidenceItemId)}/source-content`,
  );
}

export async function getEvidenceConversationContext(matterId: string, evidenceItemId: string) {
  return apiFetch<EvidenceConversationContext>(
    `/api/matters/${encodeURIComponent(matterId)}/evidence-items/${encodeURIComponent(evidenceItemId)}/conversation-context?before=25&after=25`,
  );
}

export async function getCourtReadiness(matterId: string, evidenceItemId: string) {
  return apiFetch<CourtReadiness>(
    `/api/matters/${encodeURIComponent(matterId)}/evidence-items/${encodeURIComponent(evidenceItemId)}/court-readiness`,
  );
}

export async function reviewEvidenceItem(
  matterId: string,
  evidenceItemId: string,
  payload: {
    decision: EvidenceReviewDecision;
    rationale: string;
    reviewer?: "owner";
  },
) {
  return apiFetch<EvidenceReviewResult>(
    `/api/matters/${encodeURIComponent(matterId)}/evidence-items/${encodeURIComponent(evidenceItemId)}/reviews`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    },
  );
}

export async function listEvidenceReviews(matterId: string, evidenceItemId: string) {
  return apiFetch<EvidenceReviewListResponse>(
    `/api/matters/${encodeURIComponent(matterId)}/evidence-items/${encodeURIComponent(evidenceItemId)}/reviews`,
  );
}

// ---------------------------------------------------------------------------
// Graphiti (C4 — Graph memory pane, read-only)
// ---------------------------------------------------------------------------

export async function searchGraphitiFacts(query: string, limit?: number, groupId = "platform") {
  const qs = new URLSearchParams({ q: query, kind: "facts" });
  qs.set("group_id", groupId);
  if (limit) qs.set("limit", String(limit));
  return apiFetch<GraphitiFactsResponse>(`/api/graphiti/search?${qs.toString()}`);
}

export async function searchGraphitiNodes(query: string, limit?: number, groupId = "platform") {
  const qs = new URLSearchParams({ q: query, kind: "nodes" });
  qs.set("group_id", groupId);
  if (limit) qs.set("limit", String(limit));
  return apiFetch<GraphitiNodesResponse>(`/api/graphiti/search?${qs.toString()}`);
}

export async function listGraphitiEpisodes(last?: number, groupId = "platform") {
  const qs = new URLSearchParams();
  qs.set("group_id", groupId);
  if (last) qs.set("last", String(last));
  const suffix = qs.toString() ? `?${qs.toString()}` : "";
  return apiFetch<GraphitiEpisodesResponse>(`/api/graphiti/episodes${suffix}`);
}

// ---------------------------------------------------------------------------
// Tool Explorer (MCP servers)
// ---------------------------------------------------------------------------

export async function listTools() {
  return apiFetch<ToolServerGroup[]>("/api/tools");
}

/**
 * Capability handshake for the only browser-supported atomic-tool path.
 * A missing route is intentionally reported by callers as unavailable; the
 * browser must never fall back to a legacy direct-call route for execution.
 */
export async function getMonitoredActionCapability() {
  return apiFetch<MonitoredActionCapability>("/api/monitored-actions/capabilities");
}

export async function startAtomicToolAction(request: StartAtomicToolActionRequest) {
  return apiFetch<MonitoredActionRun>("/api/monitored-actions", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(request),
  });
}

export async function getMonitoredAction(actionId: string) {
  return apiFetch<MonitoredActionRun>(`/api/monitored-actions/${encodeURIComponent(actionId)}`);
}

export async function cancelMonitoredAction(actionId: string) {
  return apiFetch<MonitoredActionRun>(`/api/monitored-actions/${encodeURIComponent(actionId)}/cancel`, {
    method: "POST",
  });
}

/** Upload a file with progress reporting (non-streaming — one JSON response). */
export function uploadFile(
  file: File,
  onProgress?: (percent: number) => void,
): Promise<UploadResponse> {
  return new Promise((resolve, reject) => {
    const xhr = new XMLHttpRequest();
    const formData = new FormData();
    formData.append("file", file);

    xhr.upload.addEventListener("progress", (e) => {
      if (e.lengthComputable && onProgress) {
        onProgress(Math.round((e.loaded / e.total) * 100));
      }
    });

    xhr.addEventListener("load", () => {
      if (xhr.status >= 200 && xhr.status < 300) {
        try {
          resolve(JSON.parse(xhr.responseText));
        } catch {
          reject(new ApiError("Malformed response from server", xhr.status));
        }
      } else {
        try {
          const body = JSON.parse(xhr.responseText);
          reject(new ApiError(body.detail || `Upload failed: ${xhr.status}`, xhr.status));
        } catch {
          reject(new ApiError(`Upload failed: ${xhr.status}`, xhr.status));
        }
      }
    });

    xhr.addEventListener("error", () =>
      reject(new ApiError("Network error — check your connection", 0)),
    );
    xhr.addEventListener("abort", () =>
      reject(new ApiError("Upload aborted", 0)),
    );

    xhr.open("POST", `${API_BASE}/api/upload`);
    xhr.send(formData);
  });
}
