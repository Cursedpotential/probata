// Byline: Claude Code · Sonnet (agent) · 2026-07-22 (C3: records, schemas, verify, parse-dryrun, flags; C4: knowledge search/browse + Graphiti pane types added 2026-07-23)
// Byline: Codex · GPT-5 · 2026-08-18 (conversation intake and governed entities)
// Byline: Codex · GPT-5 · 2026-08-15 (durable reports and Matter court-readiness contracts)
// Byline: Codex · GPT-5 · 2026-08-18 (message projection, realization, and chunk lineage contracts)
// Byline amendment: Codex · GPT-5 · 2026-08-18 (third-party human review contracts)
// Byline amendment: Codex · GPT-5 · 2026-08-18 (Evidence Operations Desk source/context contracts)
// Byline: Codex · GPT-5 · 2026-08-18 (native evidence search compatibility envelope)
// Byline: Codex · GPT-5 · 2026-08-28 (proffer workflow (formerly Universal Import Workflow) contracts)
/**
 * Types for the Knowledge Workbench staged-file record.
 *
 * Inlined from the donor kit's `packages/shared` (this app is no longer part
 * of a pnpm workspace, so there is no `@vibe-coding-starter-kit/shared` to
 * depend on) and rewritten to match the workbench FastAPI backend's contract
 * — see `workbench/api/app/types/documents.py::StagedFile` for the source of
 * truth this mirrors.
 */

/** Lifecycle of a staged file record. */
export type StagedStatus = "staged" | "promoting" | "promoted" | "failed";

/** Which promote path a staged file should take. */
export type DetectedType = "doc" | "chat_export";

/** The only four domains the workbench classifies staged files into. */
export const DOMAIN_OPTIONS = [
  "timeline_relationship",
  "personal_history",
  "platform_design",
  "legal_strategy",
] as const;

export type Domain = (typeof DOMAIN_OPTIONS)[number];

/** User-editable classification metadata for a staged file. */
export interface StagedFileMeta {
  domain?: string | null;
  category?: string | null;
  source_platform?: string | null;
}

/** A row in the backend's `staged_files` table. */
export interface StagedFile {
  id: string;
  name: string;
  size: number;
  mime: string;
  detected_type: DetectedType;
  /** Extracted text preview, capped server-side; "" for binary formats. */
  text?: string;
  /** True when `text` above was cut short of the full extracted text by the
   * detail endpoint's TEXT_PREVIEW_CHARS cap — only set on the `GET
   * /api/files/{id}` detail response, not on list rows (C2.7). Use
   * `getFileText()` / the Preview dialog for the untruncated text. */
  text_truncated?: boolean;
  meta: StagedFileMeta;
  r2_key: string;
  status: StagedStatus;
  promote_result?: Record<string, unknown> | null;
  created_at: string;
  updated_at: string;
}

/** Response body from `POST /api/upload` — a staged file plus a duplicate flag. */
export interface UploadResponse extends StagedFile {
  duplicate?: boolean;
}

// ---------------------------------------------------------------------------
// Intake Preview + Analyze (C2.7 owner scope addition, 2026-07-21)
// ---------------------------------------------------------------------------

/** `GET /api/files/{id}/text` — the full, untruncated extracted text (unlike
 * `StagedFile.text`, which the detail endpoint caps for the summary view). */
export interface FileTextResponse {
  id: string;
  text: string;
  length: number;
}

/** `POST /api/files/{id}/analyze` — re-runs the server's detect.py sniffing
 * and reports basic shape stats. Mirrors `app/service/files.py::analyze_file`. */
export interface FileAnalysis {
  id: string;
  detected_type: DetectedType;
  /** The type currently recorded on the staged-file row, for comparison
   * against a freshly re-sniffed `detected_type` (they can drift if the
   * operator manually overrode detected_type via metadata edit). */
  current_detected_type: DetectedType | null;
  /** Human-readable reason the sniffer landed on `detected_type`. */
  evidence: string;
  shape: {
    size: number;
    mime: string;
    text_length: number;
    line_count: number;
    is_json_parseable: boolean;
    has_text: boolean;
  };
}

/** Local upload-widget progress state — not part of the API contract. */
export type UploadItemStatus = "uploading" | "complete" | "error";

// ---------------------------------------------------------------------------
// Runs (C1 Operator Console) — mirrors the spine's C0 run ledger
// (server/evidence/run_ledger.py, server/api/run_routes.py,
// sql/bootstrap/schema_snapshot (ops.workflow_run; migrations retired 2026-09-07)), a parallel build that landed in this
// same working tree while this frontend was in progress. Field shapes below
// were cross-checked against that actual code (not just the build brief's
// prose), which is how the run/stage status-vocabulary mismatch below was
// caught before it shipped.
// ---------------------------------------------------------------------------

/** Lifecycle of a spine run — matches the `analysis.workflow_run.status`
 * CHECK constraint (sql/bootstrap/schema_snapshot (ops.workflow_run; migrations retired 2026-09-07)) exactly. */
export type RunStatus = "running" | "paused" | "completed" | "failed";

/** Lifecycle of a single STAGE within a run — matches the
 * `analysis.workflow_run_stage.status` CHECK constraint exactly. NOTE this
 * is a different vocabulary than RunStatus ("success"/"skipped", not
 * "completed") — a real gotcha found while cross-checking the spine's
 * actual implementation (server/evidence/run_ledger.py) against the build
 * brief, which only documented run-level status. */
export type StageStatus = "pending" | "running" | "success" | "failed" | "skipped";

/** The only two workflows the spine currently documents. */
export const WORKFLOW_OPTIONS = ["chat-transcript", "sms-xml"] as const;
export type Workflow = (typeof WORKFLOW_OPTIONS)[number];

export type RunMode = "auto" | "supervised";

/** Supervised-gate state on a run (C2). Set only for supervised-mode runs;
 * `null` for auto-mode runs and non-gated states. Per the C2 spine contract
 * (console/c2-spine, a parallel branch this frontend codes against):
 * `status==='paused' && gate_state==='waiting'` means the run is stopped at
 * a gate, and the NEXT pending stage (lowest seq with status 'pending') is
 * the gated one. */
export type GateState = "waiting" | "released" | "abort" | null;

/** Evidence-chain depth for a run's source file (C2). `light` = whole-file
 * hash only; `full` = every intermediate hashed into the custody chain. The
 * spine defaults this per-workflow when omitted at run-creation time
 * (chat-transcript -> light, sms-xml -> full). */
export type CustodyTier = "full" | "light";

/** One row of a run's stage list, as embedded in `GET /v1/runs` list items.
 *
 * `content` (C2.6 requirement 3, optional): the spine's `list_runs()` now
 * includes each stage's `content` text (truncated server-side to 500 chars)
 * so a failed run's table row can show a truncated error snippet without a
 * second round-trip to `GET /v1/runs/{id}`. */
export interface RunStageSummary {
  seq: number;
  name: string;
  status: StageStatus;
  content?: string | null;
}

/** Historical ingest output shapes; the old first-stage wire name remains
 * readable but is displayed as raw-source verification. Field names verified
 * against the real implementation (server/evidence/workflows.py's
 * `_ledger_stage_output`), not just the build brief's prose description. */
export interface RawSourceVerificationOutput {
  sha256?: string | null;
  artifact_id?: string | null;
  duplicate?: boolean;
  /** The build brief called this "blob path"; the actual ledger key is `blob_key`. */
  blob_key?: string | null;
  [key: string]: unknown;
}

export interface ParseOutput {
  parser_id?: string | null;
  attempts?: unknown[];
  schema_recognized?: boolean;
  record_count?: number;
  /** Already JSON-stringified + truncated to 500 chars server-side
   * (`json.dumps(r, default=str)[:500]`) — render as text, not re-parse. */
  sample_records?: string[];
  parse_stats?: Record<string, unknown>;
  /** sms-xml only (fallback-parser substitution occurred); chat-transcript never sets this. */
  alt_parse?: boolean;
  [key: string]: unknown;
}

export interface StoreOutput {
  rows_stored?: number;
  table?: string;
  [key: string]: unknown;
}

export interface KnowledgeOutput {
  docs_ingested?: number;
  domain?: string | null;
  skipped?: boolean;
  [key: string]: unknown;
}

export type StageOutput = RawSourceVerificationOutput | ParseOutput | StoreOutput | KnowledgeOutput | Record<string, unknown>;

/** A stage as returned by `GET /v1/runs/{run_id}` (the detail view) —
 * `SELECT *` off `analysis.workflow_run_stage`, so `stage_id`/`run_id` also
 * ride along; only the fields the console renders are declared here. */
export interface RunStageDetail {
  seq: number;
  name: string;
  status: StageStatus;
  content?: string | null;
  output?: StageOutput | null;
  started_at?: string | null;
  finished_at?: string | null;
  outcome_reason_code?: string | null;
  outcome_reason_detail?: string | null;
}

/** Fields common to both `GET /v1/runs` list rows and the `GET /v1/runs/{id}`
 * detail's top level (both are `SELECT *` off `analysis.workflow_run`). */
export interface RunFields {
  run_id: string;
  workflow: string;
  mode: RunMode;
  source_name: string | null;
  source_path?: string | null;
  sha256: string | null;
  artifact_id?: string | null;
  domain: string | null;
  status: RunStatus;
  /** The runner's own end-of-run summary dict (run_chat_transcript/run_sms_xml's return value). */
  summary?: Record<string, unknown> | null;
  /** Set only if an exception escaped the workflow runner itself (rare — most
   * failures surface as a failed STAGE with `content`, not this). */
  error?: string | null;
  created_at: string;
  updated_at: string;
  /** C2: supervised-gate state — see `GateState` doc comment. */
  gate_state: GateState;
  /** C2: the run this one was created from via POST /v1/runs/{id}/retry,
   * or null for a run that wasn't a retry. */
  parent_run_id: string | null;
  /** C2: evidence-chain depth — see `CustodyTier` doc comment. */
  custody_tier: CustodyTier;
  trace_id?: string | null;
  report_schema_version?: string;
}

/** One row of `GET /v1/runs`. */
export interface RunSummary extends RunFields {
  stages: RunStageSummary[];
}

/** `GET /v1/runs/{run_id}` — the summary fields plus full stage detail. */
export interface RunDetail extends RunFields {
  stages: RunStageDetail[];
}

/** `POST /api/runs` 202 response. */
export interface RunCreateResponse {
  run_id: string;
  workflow: string;
  mode: string;
}

/** `POST /api/runs/{id}/continue` 200 response (C2). 409 if not paused. */
export interface RunContinueResponse {
  run_id: string;
  status: RunStatus;
}

/** `POST /api/runs/{id}/abort` 200 response (C2) — `status` is always
 * 'failed'. 409 if the run is already terminal. */
export interface RunAbortResponse {
  run_id: string;
  status: RunStatus;
}

/** `POST /api/runs/{id}/retry` 202 response (C2) — `run_id` is the NEW run;
 * `parent_run_id` is the failed run that was retried. 409 if the source run
 * isn't terminal-failed. */
export interface RunRetryResponse {
  run_id: string;
  parent_run_id: string;
}

/** `POST /api/runs/{id}/retry` optional JSON body (C2.6). Omit entirely for
 * the full-rerun behavior; `"knowledge"` re-runs ONLY the knowledge stage
 * over the parent's already-stored records (server/evidence/workflows.py's
 * `run_knowledge_from_store`) — the fix for the custody-dedupe/no-new-rows
 * trap where a plain retry could report docs_ingested=0 without actually
 * re-ingesting anything. */
export type RetryFromStage = "knowledge";

export interface RunReviewAction {
  action_id: string;
  run_id: string;
  stage_seq?: number | null;
  action_type: "acknowledge" | "approve" | "override" | "continue" | "abort" | "retry";
  actor: string;
  reason: string;
  replacement?: Record<string, unknown> | null;
  created_at: string;
}

export interface RunReportStage {
  seq: number;
  name: string;
  status: StageStatus;
  disposition: string;
  reason: { code?: string | null; detail?: string | null };
  duration_ms?: number | null;
  output?: StageOutput | null;
  review: { decision_required: boolean; allowed_actions: string[] };
}

export interface RunReport {
  schema_version: string;
  pass: { number: number; name: string; status: "COMPLETE" | "PARTIAL" | "BLOCKED" };
  metadata: { timestamp?: string | null; platform: string; byline_revision: string; duration_ms?: number | null };
  input: Record<string, unknown>;
  output?: Record<string, unknown> | null;
  errors: Array<{ code: string; message: string; stage_seq?: number; recoverable?: boolean }>;
  warnings: Array<{ code: string; message: string; stage_seq?: number }>;
  handoff: { status: string; next_action: string };
  data: {
    summary: { total: number; passed: number; failed: number; skipped: number; pending: number; running: number };
    stages: RunReportStage[];
    review_actions: RunReviewAction[];
    trace: { trace_id?: string | null; url?: string | null; authority: "diagnostic_only" };
  };
}

export interface RunReviewActionRequest {
  action_type: "acknowledge" | "approve" | "override";
  reason: string;
  stage_seq?: number;
  replacement?: Record<string, unknown>;
}

// ---------------------------------------------------------------------------
// Dependency health strip (C2.6 requirement 4)
// ---------------------------------------------------------------------------

/** One dependency's health, as returned by both the spine's
 * `GET /v1/health/deps` and the workbench's `GET /api/health/deps`. */
export interface DepStatus {
  status: "ok" | "error";
  error?: string;
}

/** `GET /api/health/deps` response — the workbench's own lancedb/object_store
 * checks merged with a proxy of the spine's pg/milvus checks. */
export interface HealthDepsResponse {
  pg: DepStatus;
  milvus: DepStatus;
  lancedb: DepStatus;
  object_store: DepStatus;
  checked_at: string;
}

// ---------------------------------------------------------------------------
// MCP Tool Explorer
// ---------------------------------------------------------------------------

/** A (subset of) JSON Schema, as carried on an MCP tool's `inputSchema`. */
export interface JsonSchema {
  type?: string;
  properties?: Record<string, JsonSchema>;
  required?: string[];
  enum?: (string | number)[];
  items?: JsonSchema;
  description?: string;
  default?: unknown;
  [key: string]: unknown;
}

/** One tool as returned by an MCP server's `tools/list`. */
export interface McpTool {
  name: string;
  description?: string;
  inputSchema?: JsonSchema;
  /** Optional MCP tool-hints object (e.g. readOnlyHint/destructiveHint) —
   * present only when the source server sends it (C2.7). */
  annotations?: Record<string, unknown>;
}

/** One entry of `GET /api/tools` — a configured server, its tools, or an error. */
export interface ToolServerGroup {
  key: string;
  label: string;
  tools?: McpTool[];
  error?: string;
}

// Monitored actions
// ---------------------------------------------------------------------------

export type MonitoredActionStatus =
  | "accepted"
  | "scheduled"
  | "running"
  | "waiting"
  | "completed"
  | "failed"
  | "cancelled";

export interface MonitoredActionCapability {
  available: boolean;
  reason?: string;
  supports_cancel?: boolean;
  supports_live_status?: boolean;
}

export interface MonitoredActionWait {
  kind: string;
  detail?: string;
  since?: string;
}

export interface MonitoredActionReceipt {
  label?: string;
  ref: string;
}

export interface MonitoredActionRun {
  action_id: string;
  workflow_id: string;
  run_id: string;
  status: MonitoredActionStatus;
  retry_count?: number;
  waits?: MonitoredActionWait[];
  receipts?: MonitoredActionReceipt[];
  output?: unknown;
  output_ref?: string;
  error?: string;
  created_at?: string;
  updated_at?: string;
}

export interface StartAtomicToolActionRequest {
  kind: "atomic_tool";
  intent: string;
  matter_id: string;
  court_case_id: string;
  horizon: "as_lived" | "hindsight" | "paired";
  authority_scope: "read_only" | "derived_output" | "governed_write";
  tool: {
    server: string;
    name: string;
    arguments: Record<string, unknown>;
  };
}

// ---------------------------------------------------------------------------
// Records (C3 — parse-quality review + curation, requirements addenda 1, 3)
// mirrors console/c3-spine's GET /v1/records, a parallel branch this
// frontend codes against per the C3 build brief's contract (not
// independently verified — same posture as the Runs types above).
// ---------------------------------------------------------------------------

/** One row of `GET /api/records` — authored normalized lineage plus projection context. */
export interface RecordRow {
  id: string;
  /** Position within its artifact — the split-boundary/turn-order signal. */
  idx: number;
  record_type: string;
  role: string | null;
  ts: string | null;
  /** Truncated preview text; see `full_len` for whether it was cut. */
  text: string;
  /** Untruncated character length of the full record text. */
  full_len: number;
  attrs: Record<string, unknown>;
  source_kind: RecordSourceKind;
  projection_kind: RecordProjectionKind;
  source_available_from?: string | null;
  normalized_lineage: {
    normalized_record_id: string;
    artifact_id: string;
  };
  third_party_conversation?: ThirdPartyConversationContext | null;
  third_party_review?: ThirdPartyPendingReview | null;
  realization_events: RealizationEventDetail[];
}

/** `GET /api/records` response. */
export interface RecordsListResponse {
  records: RecordRow[];
  total?: number;
}

/** `PATCH /api/records/{id}/meta` body — curation-only edits (never touches
 * evidence blobs/hashes). All fields optional; omit a field to leave it
 * alone (mirrors app/types/inspect.py::RecordMetaPatchRequest). */
export interface RecordMetaPatch {
  title?: string;
  labels?: string[];
  attrs_patch?: Record<string, unknown>;
}

// ---------------------------------------------------------------------------
// Data Explorer (read-only PostgreSQL + Weaviate inspection views)
// ---------------------------------------------------------------------------

export interface SchemaColumn {
  name: string;
  type: string;
}

export type TableAuthority = "authored" | "derived" | "audit-control";

export interface SchemaTable {
  table: string;
  authority: TableAuthority;
  row_count: number;
  row_count_is_estimate: boolean;
  columns: SchemaColumn[];
}

export type PgSchemaName = "evidence" | "working" | "analysis" | "reference" | "ops";

export type PgSchemas = Partial<Record<PgSchemaName, SchemaTable[]>> & {
  error?: string;
};

export interface WeaviateField {
  name: string;
  type: string;
  index_filterable?: boolean | null;
  index_searchable?: boolean | null;
}

export interface WeaviateCollection {
  name: string;
  description?: string | null;
  num_entities?: number | null;
  fields: WeaviateField[];
  vectorizer?: unknown;
  vector_index_type?: string | null;
  vector_index_config?: Record<string, unknown> | null;
  named_vectors?: Record<string, unknown> | null;
}

export interface InspectorError {
  error: string;
}

/** `GET /api/schemas` response — either section may independently carry
 * `{error}` instead of its normal shape; a down Weaviate projection never
 * blocks PostgreSQL's canonical schema view. */
export interface SchemasResponse {
  pg: PgSchemas;
  weaviate: WeaviateCollection[] | InspectorError;
}

export interface TableDetailColumn extends SchemaColumn {
  database_type: string;
  nullable: boolean;
  default?: string | null;
  position: number;
}

export interface TableDetailIndex {
  name: string;
  definition: string;
}

export interface TableDetail {
  schema: PgSchemaName;
  table: string;
  authority: TableAuthority;
  limit: number;
  columns: TableDetailColumn[];
  indexes: TableDetailIndex[];
  rows: Array<Record<string, unknown>>;
}

export interface VectorPreview {
  name: string;
  dimensions: number;
  preview: number[];
  truncated: boolean;
}

export interface VectorObjectPreview {
  uuid: string;
  properties: unknown;
  vectors: VectorPreview[];
}

export interface WeaviateDetail {
  collection: string;
  limit: number;
  objects: VectorObjectPreview[];
}

// ---------------------------------------------------------------------------
// Verify (C3 — active hash verification, requirements addendum 2)
// ---------------------------------------------------------------------------

export type VerifyVerdict = "intact" | "broken" | "hash-only-ok";

export interface VerifyChainLink {
  seq: number;
  ok: boolean;
}

/** `POST /api/verify/{sha256}` response — the verdict panel payload.
 * `chain` is `null` for light-tier custody (whole-file hash only, no H1/H2/H3
 * chain rows) — the panel must label that honestly as 'hash-only-ok', not
 * imply a full chain was walked. */
export interface VerifyResponse {
  sha256_match: boolean;
  computed: string;
  recorded: string;
  custody_tier: CustodyTier;
  chain: VerifyChainLink[] | null;
  verdict: VerifyVerdict;
}

// ---------------------------------------------------------------------------
// Parse dry-run (C3 — requirements addendum 1: "the real parser candidates")
// ---------------------------------------------------------------------------

export interface ParseDryrunAttempt {
  tool: string;
  ok: boolean;
  confidence?: number;
  error?: string;
}

/** `POST /api/runs/parse-dryrun` response. */
export interface ParseDryrunResponse {
  attempts: ParseDryrunAttempt[];
  parser_id: string | null;
  record_count: number;
  sample_records: string[];
}

// ---------------------------------------------------------------------------
// Corroboration flags (C3 — requirements addendum 6)
// ---------------------------------------------------------------------------

export type FlagStatus = "open" | "partial" | "corroborated" | "unobtainable";

/** The evidence types the owner asked the multiselect to cover verbatim. */
export const EVIDENCE_WANTED_OPTIONS = [
  "sms",
  "photo",
  "call-log",
  "financial",
  "witness",
  "other",
] as const;
export type EvidenceWantedType = (typeof EVIDENCE_WANTED_OPTIONS)[number];

/** The kinds of things a flag can target — a record (a specific turn) or a
 * run (the whole artifact). Kept as `string` rather than a closed union
 * since the spine is the source of truth for what target_kind values exist
 * (a parallel build — see module-level note above). */
export type FlagTargetKind = "record" | "run" | string;

export interface FlagLinkArtifact {
  id: string;
  sha256: string;
}

/** A corroboration flag, as returned by `GET /api/flags` / `POST /api/flags`. */
export interface Flag {
  id: string;
  target_kind: FlagTargetKind;
  target_id: string;
  claim: string;
  claim_date_start?: string | null;
  claim_date_end?: string | null;
  evidence_wanted?: EvidenceWantedType[] | null;
  status: FlagStatus;
  notes?: string | null;
  link_artifact?: FlagLinkArtifact | null;
  created_at?: string;
  updated_at?: string;
  [key: string]: unknown;
}

/** `POST /api/flags` body. */
export interface FlagCreateRequest {
  target_kind: FlagTargetKind;
  target_id: string;
  claim: string;
  claim_date_start?: string | null;
  claim_date_end?: string | null;
  evidence_wanted?: EvidenceWantedType[] | null;
  notes?: string | null;
}

/** `PATCH /api/flags/{id}` body. */
export interface FlagUpdateRequest {
  status?: FlagStatus;
  notes?: string | null;
  link_artifact?: FlagLinkArtifact | null;
}

// ---------------------------------------------------------------------------
// Knowledge: Weaviate projection search plus canonical PostgreSQL source,
// chunk, metadata, and custody-provenance inspection.
// ---------------------------------------------------------------------------

/** One hit from `GET /api/knowledge/search`. Evidence hits are normalized from
 * the native horizon-prefiltered store; other lanes retain Agno compatibility. */
export interface KnowledgeSearchHit {
  id: string;
  content: string;
  name?: string | null;
  /** Arbitrary metadata the knowledge doc was ingested with — includes
   * "domain" for conversation docs (server/evidence/workflows.py sets it). */
  meta_data?: Record<string, unknown> | null;
  usage?: Record<string, unknown> | null;
  reranking_score?: number | null;
  content_id?: string | null;
  content_origin?: string | null;
  size?: number | null;
}

/** Shared pagination envelope used by knowledge search and content browse. */
export interface KnowledgePageMeta {
  page: number;
  limit: number;
  total_pages: number;
  total_count: number;
  search_time_ms?: number;
  knowledge_lane?: string;
  case_id?: string;
  truncated?: boolean;
}

/** `GET /api/knowledge/search` response. */
export interface KnowledgeSearchResponse {
  data: KnowledgeSearchHit[];
  meta: KnowledgePageMeta;
}

/** One canonical source row from `GET /api/knowledge/contents`. */
export interface KnowledgeContentRow {
  id: string;
  name?: string | null;
  description?: string | null;
  type?: string | null;
  size?: string | null;
  metadata?: Record<string, unknown> | null;
  access_count?: number | null;
  status?: string | null;
  status_message?: string | null;
  created_at?: string | null;
  updated_at?: string | null;
}

/** `GET /api/knowledge/contents` response. */
export interface KnowledgeContentsResponse {
  data: KnowledgeContentRow[];
  meta: KnowledgePageMeta;
}

/** One normalized PostgreSQL record/chunk belonging to a canonical source. */
export interface KnowledgeRecord {
  record_id: string;
  artifact_id: string;
  source_sha256: string;
  source_ref: string;
  blob_key?: string | null;
  record_type: string;
  source: string;
  conversation_id?: string | null;
  role?: string | null;
  participants?: unknown;
  content: string;
  occurred_at?: string | null;
  knowledge_time?: string | null;
  disclosure_tier: string;
  attrs?: Record<string, unknown> | null;
  matter_id: string;
  domain: string;
  created_at: string;
  source_kind: RecordSourceKind;
  projection_kind: RecordProjectionKind;
  source_available_from?: string | null;
  normalized_lineage: { normalized_record_id: string; artifact_id: string };
  third_party_conversation?: ThirdPartyConversationContext | null;
  realization_events: RealizationEventDetail[];
}

export interface ThirdPartyPendingParticipant {
  id: string;
  participant_raw: string | null;
  role: "from" | "to" | "cc" | "bcc" | "group";
  entity_id: string | null;
}

export interface ThirdPartyPendingMessage {
  id: string;
  normalized_record_id: string;
  sender_raw: string | null;
  sender_entity_id: string | null;
  participants: ThirdPartyPendingParticipant[];
}

export interface ThirdPartyPendingReview {
  conversation_id: string;
  review_status: "pending" | "approved" | "rejected";
  decision_state: "proposed" | "approved";
  messages: ThirdPartyPendingMessage[];
}

export interface ThirdPartyApprovalRequest {
  sender_entity_ids: Record<string, string>;
  participant_entity_ids: Record<string, string>;
  reason: string;
}

export type MessageCorpus = "first_party" | "acquired_third_party";

export interface AcquisitionAssertionInput {
  acquired_at: string;
  method: "own_device" | "household_device" | "voluntary_third_party" | "legal_process" | "public_source" | "unknown";
  authority: "device_owner" | "parent_guardian" | "account_holder" | "consent_given" | "court_order" | "unclear";
  source_device?: string | null;
  device_custodian?: string | null;
  notes?: string | null;
}

export interface GovernedEntity {
  id: string;
  display_name: string;
  entity_type: string;
  review_status: string;
  safe_for_legal_use: boolean;
}

export interface GovernedEntitiesResponse {
  entities: GovernedEntity[];
}

export interface ThirdPartyApprovalResponse {
  approval: {
    conversation_id: string;
    approved_record_count: number;
    audit_ledger_id: number;
    vector_reprojection: {
      artifact_id: string;
      normalized_record_ids: string[];
      source_available_from: Record<string, string>;
    };
  };
  reprojection:
    | { status: "completed"; record_count: number }
    | { status: "replay_pending"; reason: string };
}

/** Rebuildable derived chunk; never an authored record or editing target. */
export interface KnowledgeChunk {
  chunk_id: string;
  normalized_record_id: string;
  chunker_id: string;
  chunk_index: number;
  content: string;
  content_sha256: string;
  source_content_sha256: string;
  char_start?: number | null;
  char_end?: number | null;
  token_count?: number | null;
  attrs?: Record<string, unknown> | null;
  derived_at: string;
}

/** Canonical item detail from `GET /api/knowledge/contents/{artifactId}`. */
export interface KnowledgeItemDetail {
  artifact_id: string;
  source_sha256: string;
  source_ref: string;
  source_name?: string | null;
  source_path?: string | null;
  blob_key?: string | null;
  matter_id: string;
  lane?: string | null;
  parser_id?: string | null;
  chunker_id?: string | null;
  record_count: number;
  chunk_count: number;
  records: KnowledgeRecord[];
  chunks: KnowledgeChunk[];
}

// ---------------------------------------------------------------------------
// Matter workspace — framework-neutral case-management API
// ---------------------------------------------------------------------------

export type MatterStatus = "active" | "closed" | "archived";
export type CourtCaseStatus =
  | "pre_filing"
  | "active"
  | "stayed"
  | "closed"
  | "appealed"
  | "archived";
export type ReviewState = "unreviewed" | "in_review" | "approved" | "rejected" | "needs_more_evidence";
export type EvidenceReviewDecision =
  | "approved"
  | "rejected"
  | "needs_changes"
  | "needs_context"
  | "escalated"
  | "hold";
export type KnowledgeLane = "platform" | "legal" | "personal_history" | "context" | "evidence";
export type RecordSourceKind = "first_party" | "third_party_acquired" | "unclassified";
export type RecordProjectionKind = "authored_normalized" | "derived_third_party";
export type MatterMode = "TEST" | "REAL";

export interface Matter {
  id: string;
  title: string;
  description?: string | null;
  status: MatterStatus;
  partition_keys: string[];
  created_at: string;
  updated_at: string;
  matter_mode: MatterMode;
}

export interface MatterListResponse {
  data: Matter[];
  total: number;
  limit: number;
  offset: number;
}

export interface CourtCase {
  id: string;
  matter_id: string;
  caption: string;
  court_name?: string | null;
  docket_number?: string | null;
  jurisdiction?: string | null;
  case_type?: string | null;
  status: CourtCaseStatus;
  filed_on?: string | null;
  closed_on?: string | null;
  is_primary: boolean;
  created_at: string;
  updated_at: string;
}

export interface MatterDetail extends Matter {
  court_cases: CourtCase[];
}

export interface ProfferUploadResponse {
  acquisition_ref: string;
  matter_mode: MatterMode;
  sha256: string;
  byte_length: number;
}

export interface ProfferSourceObject {
  kind: "object";
  key: string;
  name: string;
  byte_length: number;
  last_modified?: string | null;
  etag?: string | null;
  source_ref: string;
  source_location: "r2";
  bucket: string;
  relative_parent: string;
  extension: string;
  file_kind: string;
  media_type?: string | null;
  archive_format?: string | null;
  intake_note?: string | null;
}

export interface ProfferSourcePrefix {
  kind: "prefix";
  prefix: string;
  name: string;
}

export interface ProfferSourceRoot {
  root_id: string;
  label: string;
  source_location: "r2";
  bucket: string;
  root_ref: string;
  temporary: boolean;
}

export interface ProfferSourceBrowserResponse {
  source: "casebible-raw" | "casebible-sorted" | "casebible-quarantine";
  prefix: string;
  delimiter: "/";
  filter: string;
  filter_applied: boolean;
  filter_scope: "root";
  search_complete: boolean;
  scanned_count: number;
  scan_limit_reached: boolean;
  active_root_id: string;
  available_roots: ProfferSourceRoot[];
  available_file_types: string[];
  page_size: number;
  is_truncated: boolean;
  continuation_token?: string | null;
  prefixes: ProfferSourcePrefix[];
  objects: ProfferSourceObject[];
  matter_mode: MatterMode;
}

export interface ProfferParserCandidate {
  handler_id: string;
  handler_version: string;
  execution_path: "decoder" | "duckdb";
  compatibility_ref: string;
  reason: string;
}

export interface ProfferSourceInspection {
  source: "casebible-raw" | "casebible-sorted" | "casebible-quarantine";
  root_id: string;
  key: string;
  source_ref: string;
  active_root_id: string;
  source_location: "r2";
  bucket: string;
  name: string;
  byte_length: number;
  etag: string;
  last_modified?: string | null;
  content_type: string;
  sha256: string;
  digest_status: "preview_only";
  preview_kind: "pdf" | "text" | "image" | "unsupported";
  preview_text: string;
  preview_url?: string | null;
  parser_preflight: {
    declared_format: string;
    route_label: string;
    basis: "filename_extension";
    authoritative: false;
  };
  matter_mode: MatterMode;
}

export interface ProfferHumanSourceAssertions {
  source_class: "first_party" | "acquired_third_party" | "unknown";
  source_principal: string;
  other_party: string;
  acquired_at: string | null;
  acquisition_method: "" | "own_device" | "household_device" | "voluntary_third_party" | "legal_process" | "public_source" | "unknown";
  acquisition_authority: "" | "device_owner" | "parent_guardian" | "account_holder" | "consent_given" | "court_order" | "unclear";
  source_device: string;
  device_custodian: string;
  occurred_start: string;
  occurred_end: string;
  date_certainty: "" | "exact" | "approximate" | "range" | "unknown";
  context: string;
  notes: string;
}

export interface ProfferSourceContextReceipt {
  source_context_ref: string;
  receipt_ref: string;
  content_digest: string;
  revision: number;
  recorded_at: string;
  matter_mode: MatterMode;
}

export interface ProfferStartRequest {
  request_id: string;
  source_ref: string;
  declared_format: string;
  parser_options_ref: string;
  matter_id: string;
  court_case_id: string;
  source_context_ref?: string | null;
  matter_mode: MatterMode;
}

export interface ProfferStartResponse {
  preview_handle: string;
  matter_mode: MatterMode;
}

export interface ProfferHandlerSelectionDecisionRequest {
  recommendation_ref: string;
  handler_id: string;
  handler_version: string;
  execution_path: "decoder" | "duckdb";
  compatibility_ref: string;
}

export interface ProfferHandlerSelectionDecisionResponse {
  preview_handle: string;
  matter_mode: MatterMode;
  decision_ref: string;
  status: string;
}

export type ProfferOperationLifecycle =
  | "running"
  | "awaiting_repair_decision"
  | "awaiting_preview_decision"
  | "completed"
  | "failed"
  | "unavailable";

export type ProfferOperationWait = "repair_decision" | "preview_decision";

export interface ProfferOperationSummary {
  preview_handle: string;
  request_id: string;
  source_ref: string;
  service: "proffer";
  created_at: string;
  lifecycle: ProfferOperationLifecycle;
  current_stage?: string | null;
  active_stages: string[];
  wait?: ProfferOperationWait | null;
  terminal: boolean;
  reason?: string;
  source_version_ref?: string | null;
  completed_stage_count: number;
}

export interface ProfferOperationStage {
  stage: string;
  status: string;
  ref?: string | null;
  receipt_ref?: string | null;
  reason?: string;
  attempt?: number | null;
  started_at?: string | null;
  completed_at?: string | null;
}

export interface ProfferOperationDetail extends ProfferOperationSummary {
  stages: ProfferOperationStage[];
}

export interface ProfferOperationListResponse {
  items: ProfferOperationSummary[];
  next_cursor?: string | null;
}

export interface ProfferPreviewReceipt {
  receipt_type: "raw_source_verification" | "parser_selection" | "parser_execution" | "normalization" | "storage" | "completeness";
  receipt_ref: string;
  status: "pending" | "running" | "completed" | "failed" | "skipped";
  digest?: string | null;
  recorded_at: string;
}

export interface ProfferPreviewCheckpoint {
  checkpoint: ProfferPreviewReceipt["receipt_type"];
  status: "pending" | "running" | "completed" | "failed";
  receipt_ref?: string | null;
  reason?: string;
}

export interface ProfferRepairAssessmentView {
  assessment_ref: string;
  source_version_ref: string;
  review_required: boolean;
}

export interface ProfferRepairDecisionRequest {
  approved: boolean;
  apply_repair: boolean;
  tool_id?: string;
  tool_payload?: Record<string, unknown>;
}

export interface ProfferRepairDecisionResponse {
  preview_handle: string;
  matter_mode: MatterMode;
  decision_ref: string;
  status: string;
}

export interface ProfferPreviewResponse {
  preview_handle: string;
  matter_mode: MatterMode;
  phase: "awaiting_decision" | "approved" | "rejected" | "timed_out" | string;
  correlation?: {
    request_id: string;
    source_version_id: string;
    raw_generation_id: string;
    normalized_generation_id: string;
  };
  parser?: {
    parser_id: string;
    parser_version: string;
    config_digest: string;
  } | null;
  preview_digest?: string | null;
  receipts?: ProfferPreviewReceipt[] | null;
  reason?: string;
  repair_assessment?: ProfferRepairAssessmentView | null;
  checkpoints?: ProfferPreviewCheckpoint[] | null;
  handler_recommendation_ref?: string | null;
  handler_decision_ref?: string | null;
  detected_format?: string | null;
  detected_format_ref?: string | null;
  signature_ref?: string | null;
  recommended_handler?: ProfferParserCandidate | null;
  alternative_handlers?: ProfferParserCandidate[] | null;
  lifecycle?: ProfferOperationLifecycle | null;
  current_stage?: string | null;
  active_stages?: string[];
  wait?: ProfferOperationWait | null;
  terminal?: boolean | null;
  completed_stage_count?: number | null;
}

export interface ProfferPreviewParticipant {
  participant_id: string;
  display_name: string;
  canonical_address?: string | null;
}

export interface ProfferPreviewAttachment {
  attachment_id: string;
  filename?: string | null;
  media_type?: string | null;
  byte_length?: number | null;
  sha256?: string | null;
  source_locator_ref: string;
}

export interface ProfferPreviewMessage {
  message_id: string;
  ordinal: number;
  sent_at?: string | null;
  sender_participant_id?: string | null;
  body: string;
  participant_ids: string[];
  attachments: ProfferPreviewAttachment[];
  source_locator_ref: string;
}

export interface ProfferPreviewMessagesResponse {
  preview_handle: string;
  matter_mode: MatterMode;
  participants: ProfferPreviewParticipant[];
  messages: ProfferPreviewMessage[];
  next_cursor?: string | null;
}

export interface ProfferPreviewEvent {
  event_id: number;
  event_type: "phase_changed" | "receipt_recorded" | "messages_available" | "decision_requested" | "decision_recorded" | "completed" | "failed";
  occurred_at: string;
  preview_handle: string;
  matter_mode: MatterMode;
  phase: string;
  receipt_ref?: string | null;
  message_count?: number | null;
  detail?: string;
}

export interface ProfferDecisionResponse {
  preview_handle: string;
  matter_mode: MatterMode;
  status: string;
}

export interface KnowledgeSourceRef {
  lane: KnowledgeLane;
  partition_key: string;
  artifact_id: string;
  sha256: string;
  conversation_id?: string;
  quote?: string;
  retrieval_ref: string;
  content_ref?: string;
  chunk_ref?: string;
}

export interface SourceCandidate {
  normalized_record_id: string;
  artifact_id: string;
  evidence_hash_id: string;
  source_id: string;
  file_node_id?: string | null;
  source_run_id?: string | null;
  sha256: string;
  conversation_id?: string | null;
  record_type: string;
  role?: string | null;
  content: string;
  occurred_at?: string | null;
  source_kind: RecordSourceKind;
  projection_kind: RecordProjectionKind;
  source_available_from?: string | null;
  disclosure_tier: string;
  review_status: ReviewState;
}

export interface KnowledgeSourceResolution {
  matter_id: string;
  candidates: SourceCandidate[];
}

export interface EvidenceItem {
  id: string;
  matter_id: string;
  court_case_id: string;
  title: string;
  description?: string | null;
  quote?: string | null;
  evidence_type: string;
  evidence_date?: string | null;
  normalized_record_id: string;
  evidence_hash_id: string;
  source_id: string;
  file_node_id?: string | null;
  source_run_id?: string | null;
  review_status: ReviewState;
  hitl_required: boolean;
  safe_for_legal_use: boolean;
  is_authenticated: boolean;
  created_by: string;
  created_at: string;
}

export interface EvidencePromotionResult {
  item: EvidenceItem;
  promotion_id: string;
  created: boolean;
}

export interface EvidenceSourcePointerDetail {
  matter_id: string;
  court_case_id: string;
  partition_key: string;
  lane: KnowledgeLane;
  normalized_record_id: string;
  evidence_hash_id: string;
  source_id: string;
  sha256: string;
  conversation_id?: string | null;
  retrieval_ref: string;
  content_ref?: string | null;
  chunk_ref?: string | null;
}

export interface EvidencePromotionDetail {
  id: string;
  partition_key: string;
  knowledge_lane: KnowledgeLane;
  retrieval_item_ref: string;
  content_ref?: string | null;
  chunk_ref?: string | null;
  source_pointer: EvidenceSourcePointerDetail;
  promoted_by: string;
  promoted_at: string;
}

export interface ThirdPartyConversationContext {
  id: string;
  external_thread_key: string;
  platform: string;
  title?: string | null;
  acquisition_id?: string | null;
  acquired_at: string;
  actual_sender?: string | null;
  actual_recipients: string[];
  actual_participants: string[];
}

export interface RealizationEventDetail {
  id: string;
  kind: string;
  realized_at: string;
  approval_state: "proposed" | "approved" | "superseded";
  trigger_record_id?: string | null;
  evidence_pointer: Record<string, unknown>;
  proposer: "algorithm" | "owner";
  proposed_at: string;
  approved_at?: string | null;
  approved_by?: string | null;
  notes?: string | null;
}

export interface CanonicalRecordDetail {
  id: string;
  record_type: string;
  source: string;
  conversation_id?: string | null;
  role?: string | null;
  content: string;
  occurred_at?: string | null;
  source_kind: RecordSourceKind;
  projection_kind: RecordProjectionKind;
  source_available_from?: string | null;
  third_party_conversation?: ThirdPartyConversationContext | null;
  realization_events: RealizationEventDetail[];
  /** @deprecated Use third_party_conversation.acquired_at. */
  acquired_at?: string | null;
  ingested_at: string;
  /** @deprecated Use realization_events. */
  realized_at?: string | null;
  disclosure_tier: string;
  review_status: ReviewState;
  case_id: string;
}

export interface CustodyHashDetail {
  id: string;
  source_ref: string;
  algo: string;
  digest_sha256: string;
  level: string;
  canon_version: string;
  hashed_at: string;
  computed_by?: string | null;
}

export interface EvidenceSourceDetail {
  id: string;
  sha256: string;
  byte_size: number;
  mime_type?: string | null;
  original_filename?: string | null;
  source_type: string;
  source_platform?: string | null;
  acquisition_source: string;
  acquisition_method?: string | null;
  acquired_at_utc?: string | null;
  acquired_certainty: string;
  provenance_tier: string;
  hash_canon_version: string;
  custody_status: string;
  review_status: string;
  verified_by?: string | null;
  verified_at?: string | null;
}

export interface EvidenceFileNodeDetail {
  id: string;
  node_kind: string;
  node_path?: string | null;
  ordinal?: number | null;
  sha256?: string | null;
  byte_span_start?: number | null;
  byte_span_end?: number | null;
  locator: Record<string, unknown>;
  mime_type?: string | null;
}

export interface EvidenceDetail {
  item: EvidenceItem;
  promotion: EvidencePromotionDetail;
  record: CanonicalRecordDetail;
  custody_hash: CustodyHashDetail;
  source: EvidenceSourceDetail;
  file_node?: EvidenceFileNodeDetail | null;
}

/** Read-only source bytes/text projection for the Evidence Operations Desk. */
export interface EvidenceSourceContent {
  content: string;
  mime_type?: string | null;
  source_pointer?: EvidenceSourcePointerDetail | null;
  provenance?: Record<string, unknown> | null;
  h1?: string | null;
  h2?: string | null;
  h3?: string | null;
}

export interface EvidenceConversationMessage {
  id: string;
  content: string;
  sender?: string | null;
  recipients: string[];
  occurred_at?: string | null;
  source_pointer?: Record<string, unknown> | null;
}

/** Context window around the selected normalized message. */
export interface EvidenceConversationContext {
  messages: EvidenceConversationMessage[];
  before: number;
  after: number;
  total?: number | null;
}

export type CourtReadinessBlocker =
  | "CONTENT_REVIEW_REQUIRED"
  | "PROVENANCE_INVALID"
  | "CUSTODY_NOT_VERIFIED"
  | "CUSTODY_CHAIN_INVALID"
  | "AUTHENTICATION_REQUIRED"
  | "CONFIDENCE_NOT_EXPORTABLE"
  | "HYPOTHESIS_NOT_EXPORTABLE"
  | "REDACTION_REQUIRED"
  | "SENSITIVITY_SEALED"
  | "NOT_RELEASED";

export interface CourtReadiness {
  evidence_item_id: string;
  matter_id: string;
  readiness_passed: boolean;
  blockers: CourtReadinessBlocker[];
  gates: {
    content_review: { approved: boolean; decision_id?: string | null };
    provenance: { exact: boolean };
    custody: {
      h1_valid: boolean;
      event_chain_valid: boolean;
      verified_event_present: boolean;
      source_status: string;
      source_reviewed: boolean;
      verified_by?: string | null;
      verified_at?: string | null;
    };
    authentication: { authenticated: boolean; method?: string | null };
    confidence: { value?: number | null; tier: string; export_band: boolean };
    assertion: { not_hypothesis: boolean };
    redaction: { privacy_sensitivity: string; source_privacy_sensitivity: string; status: string; clear_for_export: boolean };
    sensitivity: { evidence_tier: string; source_tier: string; sealed: boolean };
    court_export: { view_member: boolean };
  };
}

export interface EvidenceReviewResult {
  item: EvidenceItem;
  task_id: string;
  decision_id: string;
  decision: EvidenceReviewDecision;
  court_readiness: "review_passed" | "excluded" | "draft";
}

export interface EvidenceReviewRecord {
  decision_id: string;
  task_id?: string | null;
  evidence_item_id: string;
  reviewer: string;
  decision: EvidenceReviewDecision;
  court_readiness: string;
  rationale: string;
  decided_at: string;
}

export interface EvidenceReviewListResponse {
  data: EvidenceReviewRecord[];
  total: number;
}

export interface EvidenceItemListResponse {
  data: EvidenceItem[];
  total: number;
  limit: number;
  offset: number;
}

// ---------------------------------------------------------------------------
// Graphiti (C4 — Graph memory pane, read-only knowledge-graph search)
// mirrors the same three read tools the `grc` CLI (graphiti-client skill)
// exposes over MCP (search_memory_facts / search_nodes / get_episodes),
// proxied through app/service/graphiti.py + app/runtime/knowledge.py. This
// is a parallel-verified contract (grc.py + its failure-modes.md were read
// directly, not guessed) rather than an independently-built spine — same
// posture as the Records types above re: "not independently verified" only
// applies to spine-side contracts, NOT this one (Graphiti's tool shapes were
// confirmed live 2026-07-19 per the graphiti-client skill).
// ---------------------------------------------------------------------------

/** One fact from `GET /api/graphiti/search?kind=facts`. */
export interface GraphitiFact {
  uuid: string;
  fact: string;
  valid_at?: string | null;
  invalid_at?: string | null;
  group_id?: string | null;
  [key: string]: unknown;
}

/** `GET /api/graphiti/search?kind=facts` response. */
export interface GraphitiFactsResponse {
  facts: GraphitiFact[];
  message?: string;
}

/** One entity node from `GET /api/graphiti/search?kind=nodes`. */
export interface GraphitiNode {
  uuid: string;
  name: string;
  labels?: string[];
  summary?: string | null;
  group_id?: string | null;
  [key: string]: unknown;
}

/** `GET /api/graphiti/search?kind=nodes` response. */
export interface GraphitiNodesResponse {
  nodes: GraphitiNode[];
  message?: string;
}

/** One episode from `GET /api/graphiti/episodes`. */
export interface GraphitiEpisode {
  uuid: string;
  name?: string | null;
  content?: string | null;
  created_at?: string | null;
  group_id?: string | null;
  [key: string]: unknown;
}

/** `GET /api/graphiti/episodes` response. */
export interface GraphitiEpisodesResponse {
  episodes: GraphitiEpisode[];
  message?: string;
}
