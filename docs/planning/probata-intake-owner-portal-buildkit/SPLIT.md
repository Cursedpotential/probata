# Frontend / Backend Split — Probata Intake and Owner Portal Recovery

## Applies?

**Yes.** The product has a separately built React browser/desktop presentation tier and persistent FastAPI, Go, Temporal, n8n, database, object-store, authentication, and deployment tiers that continue running after any browser closes.

This is a hard contract split inside the existing Probata monorepo. It is not permission to split Probata into new repositories or to create a second Intake implementation.

## Contract

### Contract authority

The frontend may know only the versioned browser contract below. It may not depend on Go structs, Temporal workflow internals, n8n node layouts, database tables, Coolify application details, object-store credentials, or private service addresses.

The implementation must establish these checked-in artifacts during the contract phase:

1. A versioned **Workbench browser OpenAPI snapshot** generated from FastAPI and checked for drift in CI.
2. Generated TypeScript types/client bindings from that snapshot; handwritten request/response copies are transitional only.
3. JSON fixtures for every lifecycle, wait, repair, capability, command, error, and empty/loading state used by Storybook and frontend smoke tests.
4. A separate private Go-runtime contract exercised by Python consumer tests and Go provider tests.
5. A reference-only n8n flow-binding schema. Workflow JSON, credential binding, validation, publish/activation, and runtime execution IDs are separate deployment facts.

The current endpoints remain the compatibility surface. D-149’s separate cutover lane owns the existing `/api/proffer/start` path and DuckDB/XML handler selection; this plan must extend that contract, never create a competing `/v1/ingest` implementation.

### Browser authentication contract

| Lane | Required behavior | Forbidden behavior |
|---|---|---|
| Public browser | Cloudflare DNS only → public HTTPS → Coolify-managed Traefik → Authentik login/policy/session → approved application. FastAPI trusts Authentik identity headers only from the exact configured proxy peer. | Anonymous application response, a browser-visible signing secret, accepting identity headers from arbitrary clients, whole-bearer comparison with a signing secret, Cloudflare Tunnel/Access/Worker, or a second ingress. |
| Trusted owner system | Existing Tailscale route remains direct and unfettered. The private route uses its explicitly configured tailnet identity/bypass contract and does not fabricate Authentik headers. | Narrowing Tailscale, routing it through Authentik, publishing direct host/port links as canonical, or making the public route a prerequisite for private access. |
| Coolify control plane | Canonical UI is `https://coolify.mitechconsult.com/`; normal owner access is by Tailscale. Any non-tailnet path must stop at Authentik before Coolify. | Listing `http://<tailnet-ip>:8000/` as the owner link or permitting an unauthenticated non-tailnet request to reach Coolify. |
| BFF to Go runtime | Private REST over the existing service boundary. Credential is read server-side from a mounted secret file and the engine verifies the allowed network peer. | Reusing the browser session token as the service secret or exposing the private runtime URL/token to JavaScript. |
| JWT-consuming service, if used | Validate signature against issuer keys plus issuer, audience, expiry, and required claims; enforce authorization separately. | Treating a signing secret as the expected bearer string. |

`GET /health` may remain the minimal unprivileged health exception if it discloses no operational data. Every other public application path is authenticated.

### Shared protocol rules

- Transport is same-origin HTTPS REST/JSON, plus the existing SSE preview-notification stream.
- Every mutation requires an `Idempotency-Key` header or an equivalent body field that is bound into the durable receipt. Replaying the same key and request returns the same accepted result; reusing it with different content returns `409`.
- Every operation and decision response carries an opaque public `operation_handle`/`preview_handle`, `request_id`, and monotonic `revision`. Temporal workflow/run IDs and raw internal service URLs remain server-side.
- List pagination uses an opaque cursor and `limit` in `1..100`. Clients never parse, increment, or synthesize cursors.
- Closing a tab, navigating Back, changing the selected source, or losing SSE does not cancel work. Only an accepted durable command changes workflow execution.
- SSE delivery is at-least-once and may be coalesced. An event tells the client which authoritative REST resource/revision to reload; it is not itself a receipt or final state.
- Dates are RFC 3339 UTC strings. Digests include their algorithm, for example `sha256:<hex>`.
- References are opaque strings. The browser must not infer storage buckets, filesystem paths, database keys, or Temporal IDs from them.
- No original evidence/context bytes travel through n8n. n8n receives locators plus the minimum typed metadata required by a published flow.

### Error envelope

All new or normalized browser endpoints return this shape for non-2xx responses:

```ts
type ApiError = {
  error: {
    code: string;
    message: string;
    retryable: boolean;
    request_id: string;
    operation_handle?: string;
    current_revision?: number;
    details?: Record<string, unknown> | Array<Record<string, unknown>>;
  };
};
```

The FastAPI BFF owns normalization while older routes still produce `detail`. It must preserve safe validation detail without exposing secrets, private paths, SQL, credentials, stack traces, or raw upstream responses.

| HTTP status | Meaning |
|---:|---|
| `400` | Malformed or semantically invalid request that is not a schema-validation failure. |
| `401` | No valid authenticated identity/session. |
| `403` | Authenticated identity lacks the action. |
| `404` | Opaque source/operation/reference is unknown or not visible to the actor. |
| `409` | Stale revision, duplicate idempotency key with different content, or command/decision invalid for current lifecycle. |
| `413` | Upload or request exceeds the governed size limit. |
| `422` | Typed request validation failed. |
| `429` | Rate or concurrency limit; include a retry hint when safe. |
| `502` | A bounded downstream adapter returned an invalid response. |
| `503` | Durable state or required service is temporarily unavailable; never infer success/failure from a stale projection. |
| `504` | Bounded downstream timeout; the response must say whether the durable operation may still be running. |

### Core types

```ts
type DeclaredPurpose =
  | "context_elt"
  | "metadata_only"
  | "ocr"
  | "vision"
  | "preserve_only"
  | "evidence_admission";

type CapabilityKind =
  | "parser"
  | "metadata"
  | "ocr"
  | "vision"
  | "preserve"
  | "context_elt"
  | "evidence_admission";

type CapabilityOffer = {
  capability_id: string;
  kind: CapabilityKind;
  label: string;
  service: string;
  implementation_version: string;
  availability: "available" | "unavailable" | "degraded";
  recommended: boolean;
  reason: string;
  inputs: Record<string, unknown>;
};

type DetectedIssue = {
  issue_code: string;
  severity: "warning" | "blocking";
  description: string;
  detector: string;
  detector_version: string;
  evidence: Record<string, unknown>;
};

type RepairOption = {
  option_id: string;
  kind: "use_original" | "use_derived_repair";
  label: string;
  description: string;
  derived_source_version_ref?: string;
  changes?: string[];
};

type RepairAssessment = {
  assessment_ref: string;
  source_version_ref: string;
  detector_completed: boolean;
  issues: DetectedIssue[];
  repair_required: boolean; // true only when validated issues require a choice
  options: RepairOption[];
  original_override_allowed: boolean;
};

type OperationLifecycle =
  | "queued"
  | "running"
  | "awaiting_capability_decision"
  | "awaiting_repair_decision"
  | "awaiting_preview_decision"
  | "held"
  | "completed"
  | "failed"
  | "canceled"
  | "unavailable";

type AllowedCommand = "hold" | "resume" | "cancel" | "retry";

type OperationStage = {
  stage_id: string;
  display_name: string;
  service: string;
  status: "pending" | "running" | "waiting" | "completed" | "failed" | "canceled";
  attempt: number;
  started_at?: string;
  updated_at?: string;
  completed_at?: string;
  progress?: { completed: number; total?: number; unit?: string };
  reason?: string;
  output_refs: string[];
  receipt_refs: string[];
};

type OperationBinding = {
  kind: "temporal" | "n8n" | "service" | "projection";
  label: string;
  public_ref: string;
  state: string;
  last_observed_at?: string;
};

type IntakeOperation = {
  operation_handle: string;
  request_id: string;
  revision: number;
  source_ref: string;
  source_version_ref: string;
  package_ref: string;
  declared_purpose: DeclaredPurpose;
  lifecycle: OperationLifecycle;
  terminal: boolean;
  current_stage?: string;
  active_stages: string[];
  blocked_by?: { kind: string; label: string; reason: string };
  allowed_commands: AllowedCommand[];
  stages: OperationStage[];
  bindings: OperationBinding[];
  decision_refs: string[];
  receipt_refs: string[];
  created_at: string;
  updated_at: string;
  completed_at?: string;
  reason?: string;
};
```

Compatibility note: the current API calls the public operation identifier `preview_handle` and currently exposes `running`, `awaiting_repair_decision`, `awaiting_preview_decision`, `completed`, `failed`, and `unavailable`. The target may preserve that field as an alias during migration, but there must be one stable operation identity—not a preview record, package record, Temporal run, and n8n run presented as unrelated processes.

### Source inspection and capability contract

Current compatibility routes remain:

```http
GET  /api/proffer/sources
POST /api/proffer/source-inspection
GET  /api/proffer/source-content
POST /api/proffer/source-contexts
POST /api/proffer/upload
```

`POST /api/proffer/source-inspection` must return a version-bound inspection, not merely an extension-derived label:

```ts
type SourceInspection = {
  source_ref: string;
  source_version_ref: string;
  display_name: string;
  byte_length: number;
  etag?: string;
  original_digest: string;
  declared_format: string;
  detected_media_type: string;
  preview: {
    kind: "image" | "pdf" | "text" | "metadata" | "unsupported";
    content_url?: string;
    message?: string;
  };
  metadata: Record<string, unknown>;
  capabilities: CapabilityOffer[];
  repair_assessment?: RepairAssessment;
};
```

Rules:

- A normal photo receives an image preview, metadata, and available OCR/vision/preserve/context choices. It is not sent to a repair gate merely because a detector omitted a Boolean.
- `repair_required` is false unless one or more concrete validated issues requires a choice. Missing, invalid, or ambiguous detector output becomes a visible detector failure/degraded capability—not a fabricated source defect.
- If repair is required, `issues`, detector identity/version, and every allowed choice are visible. “Use original” remains available whenever policy allows it. A derived-repair option appears only when an actual derived source version exists.
- Parser choice is a real capability decision. The UI shows the selected parser, viable alternatives, recommendation basis, version, and an override. It never pretends an extension-derived route label is a completed parser decision.

### Start contract

The existing endpoint remains authoritative:

```http
POST /api/proffer/start
Idempotency-Key: <opaque client-generated key>
Content-Type: application/json
```

```ts
type StartIntakeRequest = {
  source_ref: string;
  source_version_ref: string;
  inspection_ref: string;
  declared_purpose: DeclaredPurpose;
  selected_capability_ids: string[];
  selected_parser_capability_id?: string;
  parser_options: Record<string, unknown>;
  expected_source_digest: string;
};

type StartIntakeResponse = {
  operation: IntakeOperation;
  links: {
    self: string;
    preview: string;
    events: string;
  };
};
```

Starting intake seals the source version and creates/binds the Intake Source Package. A context/ELT purpose does not first admit the bytes into evidence PostgreSQL. Later evidence admission reopens the retained package, re-reads and rehashes the original, compares recorded fingerprints, re-extracts with recorded versions, and then performs the evidence-only owner/custody gate.

### Operation registry and detail contract

```http
GET /api/proffer/operations?status=<exact>&cursor=<opaque>&limit=<1..100>
GET /api/proffer/operations/{operation_handle}
```

The list supports all in-flight and historical lifecycle values, not only “runs.” Server-side filters must include lifecycle, source text/reference, service/capability, created-time range, and “needs my decision.” Client-only filtering of the current page is allowed only as a clearly labeled refinement, never as a claim that all operations were searched.

The detail view returns the complete `IntakeOperation`, stage attempts, waits, bindings, decisions, outputs, and receipts. For “What is repair doing?” it must show either the active detector/repair stage and elapsed/last-observed time, or the exact human decision it is waiting for. A tiny file is not allowed to spin invisibly.

When Temporal cannot answer authoritatively, return lifecycle `unavailable`, `terminal: false`, and a safe reason. Do not infer completion or failure from a stale PostgreSQL projection.

### Durable command contract

Do not render a control unless it is present in `allowed_commands`.

```http
POST /api/proffer/operations/{operation_handle}/commands
Idempotency-Key: <opaque key>
```

```ts
type OperationCommandRequest = {
  command: AllowedCommand;
  expected_revision: number;
  reason: string;
};

type OperationCommandResponse = {
  accepted: boolean;
  command_receipt_ref: string;
  operation: IntakeOperation;
};
```

`cancel` means a Temporal cancellation request was durably accepted; it does not mean cleanup has completed. `retry` creates a recorded retry/re-execution transition under policy and does not overwrite the failed attempt. `hold` and `resume` require actual workflow semantics and receipts. Until those commands exist, the UI supports safe backgrounding/reopening but labels control as unavailable instead of faking buttons.

### Decision contracts

Keep the current compatibility endpoints while normalizing their typed receipts:

```http
POST /api/proffer/previews/{operation_handle}/repair-decision
POST /api/proffer/previews/{operation_handle}/decision
```

Each request includes `expected_revision`, a selected option/decision, a non-empty human reason when overriding a recommendation, and an idempotency key. Each response returns the updated operation plus an immutable decision receipt reference. A parser/capability decision may be added under the same typed decision model only after D-149’s current endpoint contract is reconciled.

### SSE event catalog

Current compatibility stream:

```http
GET /api/proffer/previews/{operation_handle}/events
Accept: text/event-stream
```

| Event | Producer | Consumer | Payload and guarantee |
|---|---|---|---|
| `proffer.preview` | Workbench/engine adapter | Selected Intake detail | `{ operation_handle, revision, changed_resources: ("snapshot" | "messages")[] }`. At-least-once, may coalesce, opaque handle must match active selection. Client reloads REST state and ignores older revisions. |
| heartbeat/comment | Stream adapter | Browser connection health only | No state meaning and no receipt semantics. |

The all-operations registry may continue five-second REST polling in the first recovery release. If a registry SSE event is added later, it follows the same “reload authoritative REST data” rule.

### Owner portal surface catalog contract

The launcher must be driven by a server-side allowlist, not hard-coded assumptions or automatic discovery of every listening port:

```ts
type PortalSurface = {
  surface_id: string;
  label: string;
  description: string;
  canonical_url: string;
  category: "work" | "knowledge" | "operations";
  exposure: "authentik_public" | "tailscale_only";
  health: "available" | "degraded" | "unavailable" | "unknown";
  auth_mode: "authentik_forward_auth" | "oidc_pkce" | "tailscale";
  owner_role_required: string;
};
```

Initial inventory must distinguish at least:

- Workbench/Intake as one application destination.
- Advocatio as the legal workdesk, after its name and route are verified.
- Docstore/knowledge surfaces that are safe for a human browser.
- Approved operations surfaces. Coolify is private-by-default at `https://coolify.mitechconsult.com/`; normal access is Tailscale, and any outside route requires Authentik before Coolify.

Tool runtimes, gateways, service APIs, workers, Temporal internals, databases, storage, raw n8n webhooks, and native/Tauri bridges are never auto-promoted into the portal.

## Frontend workstream

- **Scope:** Shared React/TanStack/Storybook/Glide foundation; source chooser; preview/metadata/parser tabs; visible capabilities and overrides; package/current-purpose selection; all-operation registry; operation detail/stage visibility; truthful background/reopen and controls; repair decision UX; error/empty/loading states; authenticated portal/launcher; responsive and keyboard-accessible behavior; future Tauri host adapters.
- **Can be built independently against:** The checked-in OpenAPI snapshot and versioned JSON fixtures. Storybook supplies every meaningful state; a fixture-backed adapter supplies list/detail pagination, SSE invalidation, errors, stale revisions, command acceptance, and Authentik actor context. No developer needs live Temporal, n8n, object storage, or Authentik merely to render and test states.
- **Owns:** `modules/workbench/web/**` and any explicitly approved shared UI/contracts package created inside this monorepo. It does not own FastAPI models, Go workflows, SQL, n8n exports, Authentik/Traefik labels, or Coolify deployment state.
- **Independent exit criteria:** React/Glide compatibility is resolved without prerelease coercion; lint, TypeScript build, Vite production build, smoke contracts, and Storybook production build pass; all contract fixtures render; keyboard/Back/URL restoration works; there is no fake parser selection, repair condition, progress, cancellation, retry, hold, success, or public link.

## Backend workstream

- **Scope:** Versioned BFF OpenAPI and error normalization; source inspection/content; capability registry; package-first start; stable operation ledger and queries; Temporal lifecycle/stages/waits/commands; repair validation; parser/metadata/OCR/vision/preserve/context/evidence-routing adapters; reference-only n8n bindings; PostgreSQL receipts and projection boundaries; object/package integrity; graph/vector projection receipts; Authentik/Tailscale enforcement; portal surface allowlist; Coolify deployment contracts and live proof.
- **Can be built independently against:** Provider-side OpenAPI/JSON contract tests, Go `httptest` suites, FastAPI/Pydantic consumer/provider tests, Temporal workflow replay/unit tests, PostgreSQL migration/integrity fixtures, object-store fakes, n8n export schema/validator tests, and ingress/auth source-contract tests. The backend passes contract fixtures without any browser running.
- **Owns:** `modules/workbench/api/**`, the explicitly assigned `modules/engine/**` packages, governed migrations/bootstrap functions, `deploy/docker/n8n/**`, relevant `deploy/*.yaml`, and Coolify/Auth configuration through their owning operational lanes. Ownership is phase/file specific; a worker never broad-stages or overwrites concurrent dirty files.
- **Independent exit criteria:** OpenAPI and fixtures pass provider tests; invalid/missing detector flags cannot fabricate repair; capability offers are registered/available, not extension-only labels; package fingerprints and later-admission checks are proven; operation list/detail and every advertised command have durable receipts; n8n exports validate and are proven published/bound without original bytes; auth fails closed publicly while Tailscale remains unchanged; deployment remains unclaimed until Coolify and browser probes pass.

### Backend sub-lanes

The backend workstream is one contract, but implementation ownership must remain bounded:

| Sub-lane | Owns | Must not own |
|---|---|---|
| BFF contract | FastAPI routes/models/adapters, OpenAPI snapshot, safe error translation | Durable workflow truth, browser components, database schema authority |
| Durable runtime | Go operation/package/workflow APIs, Temporal queries/signals/commands, receipt creation | Browser state, Authentik browser configuration, n8n credentials |
| Data/package | PostgreSQL migrations/integrity functions, immutable object/package verification, projection receipts | UI decisions, arbitrary service orchestration, silent graph consolidation |
| n8n composition | Versioned exports, schemas, credential placeholders, validation/publish runbook, binding references | Durable lifecycle, custody authority, original evidence transport |
| Identity/ingress | Authentik provider/application/outpost, exact trusted proxy CIDR, Traefik routes, Tailscale non-regression | App business logic, Cloudflare Tunnel/Access, unauthenticated operational exposure |
| Deployment | Correct Coolify application UUID/source/branch/compose/watch paths, image digests, rollout and rollback receipts | Hand-run competing production containers, unrelated applications, claiming a commit is deployed |

## Synchronization points

1. **Contract freeze:** Backend publishes the OpenAPI snapshot, lifecycle/command matrix, error envelope, SSE catalog, and fixtures. Frontend proves every fixture before either side changes the contract independently.
2. **D-149 start/capability merge:** The DuckDB/XML cutover owner and this backend lane reconcile `/api/proffer/start`, capability IDs, package binding, and parser override semantics before the frontend replaces `parser-options://default-v1`.
3. **Durable controls:** Backend proves command availability plus append-only receipts before frontend exposes Hold, Resume, Cancel, or Retry. Background/reopen ships independently because navigation is not a command.
4. **Identity and portal admission:** Frontend consumes only the approved surface catalog after the identity lane proves Authentik denial/login/session behavior, canonical URLs, and unchanged Tailscale paths. No UI hard-codes unverified ports or auto-discovers services.
5. **Integrated release candidate:** Both workstreams meet independent tests, then one pinned Coolify candidate proves source preview, photo choices, parser override, repair/no-repair paths, all-operation visibility, n8n/Temporal correlation, public denial/login, authenticated launcher routes, and private Tailscale access.

## Repo layout decision

Keep both tiers in the **existing Probata monorepo**. The current deployment already builds the Vite SPA and copies it into the FastAPI image while the Go engine and deployment manifests remain sibling modules. A repository split would add release and schema coordination risk without providing an ownership benefit.

The split is enforced by contracts and scoped instructions, not by pretending the tiers are unrelated:

```text
modules/workbench/web/       frontend workstream
modules/workbench/api/       browser-facing backend adapter
modules/engine/              durable backend runtime and package/workflow logic
deploy/docker/n8n/           visual composition exports and activation material
deploy/                      identity, service, and Coolify compose contracts
docs/planning/...-buildkit/  this implementation handoff and fixtures/specification plan
```

Current dirty implementation work in those source paths belongs to its active contributors. This build kit does not stage, reset, overwrite, merge, deploy, or claim it.
