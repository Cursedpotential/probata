# Gotchas — Probata Intake and Owner Portal Recovery

Ranked by damage. **S** = data loss, security hole, false governance claim, or silent corruption. **A** = likely to cost a day or more or block a release. **B** = likely to cost an hour and create visible confusion.

This audit takes [STACK.md](STACK.md) and [SPLIT.md](SPLIT.md) as fixed. It does not reopen the owner’s package-first, shared-UI, Authentik, Tailscale, graph, or Coolify decisions. It incorporates the later owner-directed exact Glide alpha24 compatibility result as a bounded exception path; it does not mislabel that prerelease as stable.

## Cross-tier gotchas

### S-1. Authentik headers become an authentication bypass when the socket peer is not proven first

**Trigger:** FastAPI accepts `X-Authentik-*` headers merely because they are present, or trusts `X-Forwarded-For` to decide whether the sender is the proxy.

**Mechanism:** A direct client can manufacture those headers. The identity is trustworthy only after the actual socket peer is inside the exact Traefik proxy CIDR. Authentik 2026.8 also tightened forwarded-header trust around `AUTHENTIK_LISTEN__TRUSTED_PROXY_CIDRS`.

**Avoidance:** Fail closed in both Authentik and Workbench when the exact proxy CIDR is absent; validate the socket peer before reading identity headers; leave `/health` as the only minimal exception; add direct-header-spoof tests and a public unauthenticated denial probe. See [Workbench auth implementation](../../../modules/workbench/api/app/runtime/auth.py), [Authentik source contract](../../../deploy/authentik.yaml), [Authentik 2026.8 notes](https://docs.goauthentik.io/releases/2026.8/), and [Traefik ForwardAuth](https://doc.traefik.io/traefik/reference/routing-configuration/http/middlewares/forwardauth/).

### S-2. Missing detector flags fabricate “repair required”

**Trigger:** Detector output is otherwise parseable but omits a top-level field named exactly `review_required`, `needs_repair`, or `repair_required`, and adapter code defaults the result to `true`.

**Mechanism:** Schema absence is incorrectly converted into a positive defect finding. A valid photo becomes gated behind a repair decision even though no issue and no derived repair exist.

**Avoidance:** Validate detector output against a versioned schema. Derive `repair_required=true` only from concrete validated issues whose policy requires a choice. Invalid/missing detector data produces a visible detector error or degraded capability and otherwise keeps the original moving. Cover omitted, false, malformed, empty-issue, and positive-issue fixtures in Go, Python, TypeScript, and Storybook. See the [settled repair decision](../../decisions/2026-09-12-intake-workflow-visibility-and-repair-gate.md).

### S-3. Context processing is silently mislabeled as evidence custody

**Trigger:** A context/ELT source is inserted into evidence tables or given H1/H2/H3 semantics merely because PostgreSQL stores the operation or a hash.

**Mechanism:** Control metadata, package preservation, and evidence admission are different acts. A context fingerprint does not prove the later evidence owner gate or custody process occurred.

**Avoidance:** Always create the Intake Source Package and its deterministic membership/fingerprint record. Store operation/receipt authority in PostgreSQL, but let context/ELT read governed object references without evidence admission. Later evidence admission must reopen and rehash the packaged original before applying evidence-only gates. See [D-154](../../DECISION_LOG.md) and the [settled register](../../registers/SETTLED.md).

### S-4. Pydantic and TypeScript disagree during the exact repair state being fixed

**Trigger:** Python returns pre-parser/repair snapshots without correlation, preview digest, or receipts, while the handwritten TypeScript interface declares those fields mandatory.

**Mechanism:** The frontend compiles against a stronger contract than the server provides, so dereferencing a field can crash only during an early wait state. Separate frontend/backend tasks can deepen this drift without noticing.

**Avoidance:** Check in a generated OpenAPI snapshot and generate TypeScript types from it. Make optionality identical, add fixtures for every pre-parser state, and fail CI when the OpenAPI snapshot changes without regenerated types. Current evidence: [Pydantic Proffer types](../../../modules/workbench/api/app/types/proffer.py) and [handwritten browser types](../../../modules/workbench/web/src/lib/shared/types.ts).

### S-5. Retried clicks create duplicate packages, workflows, n8n runs, or decisions

**Trigger:** Start, override, repair decision, cancel, retry, hold, or resume can be submitted twice without an operation-bound idempotency key and expected revision.

**Mechanism:** Browser retries, double-clicks, reverse-proxy retries, or a timeout followed by retry can reach the backend more than once. Temporal and n8n IDs alone do not make the external mutation idempotent.

**Avoidance:** Require `Idempotency-Key` plus `expected_revision` on mutations; persist the request digest and immutable receipt before returning; replay identical requests to the same result; reject a different request under the same key with `409`; prove concurrent submission behavior. The command and mutation contract is in [SPLIT.md](SPLIT.md).

### S-6. Previewed bytes and ingested bytes can be different

**Trigger:** The UI inspects an object by name, then Start later rereads the mutable name without pinning its version/ETag/digest.

**Mechanism:** The source may be overwritten between preview and sealing. The operator approves one photo/document while the workflow packages another.

**Avoidance:** Inspection returns a `source_version_ref` and computed original-byte digest; Start requires both and fails on mismatch; content reads remain version/ETag-bound; the package receipt records the exact version and digest. Never treat an S3-compatible ETag as a universal content hash because multipart ETags are not plain MD5. See [source inspection service](../../../modules/workbench/api/app/service/source_inspection.py) and [AWS multipart ETag documentation](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity-upload.html).

### A-1. `phase` is mistaken for the durable lifecycle

**Trigger:** Frontend logic treats preview phase as operation status, or labels an early preview state as the final workflow lifecycle.

**Mechanism:** Preview phase and durable lifecycle are separate projections. Compatibility fallback code can hide this until a repair/decision wait or Temporal outage.

**Avoidance:** Make `lifecycle` authoritative, retain phase only as an explicitly labeled compatibility field, and add fixtures where phase and lifecycle differ. See [current Intake compatibility logic](../../../modules/workbench/web/src/components/intake/unified-intake.tsx) and [engine lifecycle model](../../../modules/engine/proffer/preview.go).

### A-2. SSE is treated as the receipt instead of an invalidation hint

**Trigger:** A `proffer.preview` event directly mutates final UI state or marks completion without reloading the authoritative snapshot.

**Mechanism:** SSE can reconnect, repeat, arrive after navigation, or coalesce. The current client already correlates by opaque handle and reloads REST state; weakening that makes stale events overwrite the selected operation.

**Avoidance:** Include handle and revision, ignore wrong/older revisions, abort obsolete REST requests, and reload snapshot/messages after an event. Completion comes only from the durable REST view. See [current preview client](../../../modules/workbench/web/src/components/sbv/proffer-preview-client.tsx).

### A-3. A client-side filter claims to search all operations but only searches one cursor page

**Trigger:** Source/service filters are applied only to loaded rows while the interface says “all” or yields a false empty state.

**Mechanism:** Cursor pagination means later rows are absent from memory. Client-only filtering cannot answer a global query.

**Avoidance:** Add server-side source/service/time/needs-decision filters to the versioned contract. Until implemented, label page-local refinements clearly and distinguish “no operations,” “no server matches,” and “no matches on this loaded page.” See [current operation table](../../../modules/workbench/web/src/components/intake/proffer-operations-table.tsx).

### A-4. A 15-second BFF timeout is reported as workflow failure even though Temporal keeps running

**Trigger:** FastAPI’s bounded private HTTP call times out and the UI converts the timeout to `failed` or retries Start blindly.

**Mechanism:** The HTTP request and durable Temporal execution have different lifetimes. The operation may have been accepted before the response path failed.

**Avoidance:** Use idempotency keys, return a safe `504` saying the durable state is unknown/may be running, and reconcile by operation/request ID before retrying. Never synthesize terminal state from the adapter timeout. See [current Proffer BFF client](../../../modules/workbench/api/app/service/proffer.py) and [Temporal Go guidance](https://docs.temporal.io/develop/go).

## React, TanStack, Storybook, Glide, and Tauri gotchas

### A-5. The tested Glide alpha exception silently expands beyond what passed

**Trigger:** An agent changes `6.0.4-alpha24` to a caret, `next`/`beta`, a later alpha, or direct grid imports throughout the product because the isolated React 19.2.3 test passed.

**Mechanism:** The evidence is exact-version and isolated-stack evidence. It does not make all prereleases equivalent, prove the current Workbench’s Storybook 10.5.10 integration, prove Tauri packaging, or guarantee stable support.

**Avoidance:** Exact-pin alpha24 without `--force` or legacy peer overrides; place it behind one shared grid adapter; rerun dependency deduplication, actual Workbench build/smoke/Storybook, 100,000-row real-browser navigation/edit/paste, URL/selection stability, and rollback. Keep React 18.3.1 + stable Glide 6.0.3 as the documented fallback. Reconcile the canonical decision record before merge/release. See the [isolated compatibility artifact](C:/Users/matts/.codex/visualizations/2026/09/12/01a09663-e9bb-72c2-bfce-c0714cba8d66/glide-alpha-compat), [Glide versions](https://www.npmjs.com/package/%40glideapps/glide-data-grid?activeTab=versions), and [STACK.md](STACK.md).

### A-6. Virtualized rows display the wrong operation after sorting, filtering, or pagination

**Trigger:** Glide row selection/detail lookup is keyed by visible row index rather than stable `operation_handle`.

**Mechanism:** Virtualization reuses cells and row indices change when filters, cursor pages, or polling updates arrive. An index-bound action can open or command a different operation than the one the user selected.

**Avoidance:** Key selection, URL state, details, and mutations by opaque handle; treat row index as render-only; reconcile a missing selected handle explicitly after refresh; test inserted/reordered rows while detail is open. See the [Glide project](https://github.com/glideapps/glide-data-grid) and [SPLIT operation contract](SPLIT.md).

### A-7. “Image supported” does not mean the browser can decode it

**Trigger:** Intake labels TIFF, BMP, AVIF, or another extension as image previewable and renders it directly in `<img>` on every browser.

**Mechanism:** Browser codec support varies, and extension/MIME classification is not successful decode. A blank tab then looks like missing preview data.

**Avoidance:** Separate `detected_media_type` from `preview.kind=renderable`; handle `img.onerror`; show metadata and an explicit “browser cannot render this format” state; create a governed thumbnail/derived preview only through a recorded capability; always retain original download/reference. See [current image classification](../../../modules/workbench/web/src/components/intake/unified-intake.tsx) and [MDN image format guidance](https://developer.mozilla.org/en-US/docs/Web/Media/Guides/Formats/Image_types).

### A-8. Storybook 10 configuration copied from CommonJS fails only in CI/build

**Trigger:** A fresh task adds `require`, `module.exports`, or a CommonJS-only addon/config to the existing ESM Storybook 10 setup.

**Mechanism:** Storybook 10 is ESM-only. The dev server can obscure configuration differences that the static build catches.

**Avoidance:** Preserve `type: module`, use ESM config/addons, and require both `storybook dev` review and `build-storybook` in the frontend exit gate. See the [Storybook migration guide](https://storybook.js.org/docs/releases/migration-guide) and [React/Vite setup](https://storybook.js.org/docs/get-started/frameworks/react-vite/?renderer=react).

### A-9. Tauri becomes a second application instead of a shell

**Trigger:** Desktop work copies the UI, stores workflow truth locally, or invents IPC alternatives to the REST contract.

**Mechanism:** The desktop host has privileged filesystem APIs and a separate release lifecycle, which makes a fork tempting. It immediately violates D-156 and creates divergent decisions/state.

**Avoidance:** Reuse the same built React application and generated contracts. Limit Tauri commands to explicit native capabilities; validate paths/permissions at the native boundary; return opaque staged-source references to the shared workflow. See [D-156](../../DECISION_LOG.md) and [Tauri frontend guidance](https://v2.tauri.app/start/frontend/).

### B-1. Back changes the page but loses source, tab, filters, or selected operation

**Trigger:** Intake keeps selection only in component state while TanStack Router changes routes.

**Mechanism:** Browser history can restore the route without the state, leaving the operator unable to return to the same in-flight process.

**Avoidance:** Put source/version, active tab, filters, and selected opaque handle in typed URL search state; keep file bytes/object URLs out of the URL; test Back/Forward after Start and after reopening a wait.

### B-2. A Vite SPA is moved under a subdirectory and asset/router paths break

**Trigger:** A deployment changes `/` to `/intake` or `/advocatio` without coordinating Vite `base`, TanStack router base, static fallback, Authentik redirect URI, cookies, and generated asset URLs.

**Mechanism:** Each layer resolves base paths independently. The HTML may load while chunks, callbacks, or deep links 404.

**Avoidance:** Use per-app hostnames by default. Permit subpaths only after a dedicated base-path matrix passes direct load, deep link, refresh, callback, SSE, static asset, and logout tests.

## FastAPI, Go, Temporal, and operation-model gotchas

### S-7. A Temporal workflow code change breaks replay

**Trigger:** Workflow code begins using nondeterministic I/O/time/randomness, changes command ordering, or removes/reorders already-recorded workflow behavior without versioning.

**Mechanism:** Temporal replays history to rebuild workflow state. Code that makes different decisions for the same history can fail nondeterministically and strand running Intake operations.

**Avoidance:** Keep I/O in Activities, use Temporal-safe time/random primitives, run replay tests against captured histories, and use supported workflow versioning/patching for incompatible changes. Never deploy a workflow change based only on unit tests. See [Temporal Go workflow guidance](https://docs.temporal.io/develop/go).

### S-8. A stale PostgreSQL projection invents a terminal result when Temporal is unavailable

**Trigger:** Operation detail falls back to the last database row and reports completed/failed because the Temporal query cannot be served.

**Mechanism:** The projection may lag the durable workflow. A temporary control-plane failure is not evidence of terminal state.

**Avoidance:** Preserve the current fail-closed `unavailable`, `terminal:false` behavior with a safe reason. Show last projection time separately and keep command availability empty until authoritative state returns. See [engine operation query](../../../modules/engine/runtimeapi/proffer_preview.go).

### S-9. An advertised Cancel/Retry/Hold/Resume button has no durable command receipt

**Trigger:** Frontend work adds controls before the Temporal command, transition policy, idempotency, and append-only receipt exist.

**Mechanism:** A request may appear accepted locally without changing the workflow, or may be repeated against the wrong revision. “Cancel” can also be confused with fully canceled cleanup.

**Avoidance:** Backend returns `allowed_commands`; frontend renders only those. Each command requires expected revision/idempotency and returns a receipt. Distinguish requested, canceling, and canceled. Current absence of controls is truthful and must not be “fixed” cosmetically. See [SPLIT durable command contract](SPLIT.md).

### S-10. Filename extension is mistaken for an executable parser capability

**Trigger:** `sms_export_xml` or “SMS XML route” is shown as a recorded parser decision because a filename ended in `.xml`.

**Mechanism:** Extension routing is descriptive preflight. It does not prove a handler is registered, healthy, compatible with the detected content, selected, versioned, or actually invoked.

**Avoidance:** Return registered capability offers with implementation version and availability; inspect content safely; show recommendation plus alternatives and override; record the selected capability in the operation receipt. Coordinate this with the D-149 DuckDB/XML cutover owner. Current static behavior is visible in [source inspection](../../../modules/workbench/api/app/service/source_inspection.py) and [Unified Intake](../../../modules/workbench/web/src/components/intake/unified-intake.tsx).

### S-11. A derived repair option points to bytes that do not exist or are not sealed

**Trigger:** The UI offers “use repaired version” from detector prose without a created, hashed, immutable derived source version.

**Mechanism:** The decision receipt can then name an unrepeatable transformation or a temporary file. Later package verification cannot reproduce what was accepted.

**Avoidance:** Emit a derived-repair option only after the derived object/version, digest, transformation/tool version, input binding, and receipt exist. Otherwise show detector details and permitted use-original/stop choices only. Never gate on a repair option the workflow did not actually supply. See [repair decision](../../decisions/2026-09-12-intake-workflow-visibility-and-repair-gate.md).

### A-10. `temporalio/auto-setup` hides production schema lifecycle

**Trigger:** The team upgrades the current `temporalio/auto-setup:1.29.7` tag or treats it as a permanent production deployment.

**Mechanism:** Upstream describes `auto-setup` as deprecated/development-oriented. Automatic setup couples server startup to schema creation/update and makes controlled backups, migrations, and rollback harder.

**Avoidance:** Separate two changes: first capture persistence/version/backups and move to explicit schema management with compatible admin tools; then test any server-minor upgrade. Do not combine this with workflow behavior changes. See [repository Temporal compose](../../../deploy/temporal/compose.temporal.yaml), [Temporal Docker builds](https://github.com/temporalio/docker-builds), and [production image guidance](https://github.com/temporalio/docker-compose#using-temporal-docker-images-in-production).

### A-11. Python dependencies change without a source diff

**Trigger:** Coolify rebuilds `python:3.12-slim` and installs broad `fastapi>=`, `uvicorn>=`, `pydantic>=`, and `httpx>=` requirements.

**Mechanism:** Both base tag and dependency resolution float. A rebuild can introduce incompatible behavior with the same Git commit.

**Avoidance:** Produce a hashed lock/constraints file after compatibility testing with Agno 2.8.7; pin the base image digest; make CI/container use the same resolver; record the resolved SBOM in the deployment receipt. See [requirements](../../../modules/workbench/api/requirements.txt) and [Workbench Dockerfile](../../../modules/workbench/Dockerfile).

### A-12. A command’s HTTP response races its durable state

**Trigger:** API returns an updated terminal-looking object immediately after signaling Temporal, even though the workflow has only accepted the signal.

**Mechanism:** Signal acceptance and workflow transition/cleanup are different events.

**Avoidance:** Return a command receipt and current observed lifecycle; use transitional statuses; let polling/SSE observe subsequent state; only mark terminal when the workflow query says terminal.

### A-13. n8n execution is duplicated when a Temporal Activity retries

**Trigger:** A timed-out Activity submits the same n8n workflow again without a stable external idempotency/binding key.

**Mechanism:** Temporal Activities are at-least-once. n8n may have accepted the first run even when its response was lost.

**Avoidance:** Bind `(operation, stage, attempt-policy)` to one recorded n8n idempotency key/execution lookup; reconcile before resubmit; return only reference-safe outputs; make duplicates visible and non-authoritative if the n8n API cannot enforce idempotency. See [Temporal Activity guidance](https://docs.temporal.io/develop/go) and the [repository flow-binding seam](../../../modules/engine/temporal/flowbinding.go).

## n8n gotchas

### S-12. Original evidence/context bytes are pushed through an n8n webhook

**Trigger:** A workflow upload or OCR node receives the original file body instead of a governed source/package locator.

**Mechanism:** n8n webhooks have a default 16 MB payload limit, execution data may retain payloads, and the workflow tier is not the custody store. This creates size failures and uncontrolled duplicate sensitive data.

**Avoidance:** Pass opaque locators, expected digests, and minimum metadata; let a bounded service read bytes under policy; disable/save only governed execution metadata; return output references and receipts. See [n8n Webhook documentation](https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-base.webhook/) and [D-154](../../DECISION_LOG.md).

### S-13. Git contains the workflow, but production has no executable n8n flow

**Trigger:** A checked-in JSON export or README is treated as active without import, credential binding, validation, publish/activation, and a runtime flow binding.

**Mechanism:** n8n production webhook URLs register only for published workflows. Repository exports do not create credentials or activate a workflow in the running Community instance.

**Avoidance:** Require an activation receipt that records export digest, target n8n version, imported workflow ID, credential placeholders resolved server-side, validator result, published/active state, production webhook or API invocation path, and `N8N_FLOW_BINDINGS_FILE` binding. See [Proffer n8n README](../../../deploy/docker/n8n/workflows/proffer/README.md) and [n8n webhook publication behavior](https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-base.webhook/).

### A-14. `n8n:latest` outruns the exported workflow contract

**Trigger:** Coolify redeploys the current floating image while checked-in exports target Community 2.36.6.

**Mechanism:** `latest` can advance without a meaningful source diff. Node schemas, credential behavior, validation, or defaults can change under the flow.

**Avoidance:** Test the export on the researched stable 2.38.7 release, pin the exact image/digest, record the validator output, and make upgrades their own task. See [n8n compose](../../../deploy/docker/n8n/compose.yaml) and [official releases](https://github.com/n8n-io/n8n/releases).

### A-15. The plan assumes Enterprise source-control or external-storage features on Community n8n

**Trigger:** A task treats Git exports as n8n’s built-in environments/source control or assumes binary external storage is available in the installed edition.

**Mechanism:** Those features have plan restrictions. The repository-based import/publish runbook is not the same capability.

**Avoidance:** Design for the actual Community deployment: repository export, explicit import, credentials, validate, publish, binding, smoke. Keep original bytes outside n8n rather than depending on gated external binary storage. See [n8n environments](https://docs.n8n.io/source-control-environments/create-environments/) and [external storage](https://docs.n8n.io/hosting/scaling/external-storage/).

### A-16. Credential IDs or secrets leak into workflow exports and handoff prompts

**Trigger:** An exported workflow, task prompt, log excerpt, screenshot, or README includes live credential values or tenant-specific credential IDs presented as reusable setup.

**Mechanism:** Fresh tasks and Git artifacts are durable and broadly visible. n8n credentials and Authentik/Coolify bootstrap material belong in server-side secret paths, not the build kit.

**Avoidance:** Export placeholders only, reference credential binding names, redact values from diagnostics, and prove secrets are read from the approved server-side store/file. Never print passwords into this handoff or a new-task prompt.

## Authentik, Traefik, Tailscale, Cloudflare, and Coolify gotchas

### S-14. Coolify is reachable from the Internet before Authentik

**Trigger:** `https://coolify.mitechconsult.com/` or a direct `:8000` port reaches the Coolify UI from a non-tailnet client without an Authentik challenge.

**Mechanism:** Coolify is a privileged control plane. Its own login page is still an exposed management surface, and a direct published port bypasses the intended ingress middleware.

**Avoidance:** Treat normal Coolify access as Tailscale-only. Close/unpublish direct public management ports at the network/application boundary. If outside browser access is intentionally admitted, Traefik must invoke Authentik before Coolify. Prove from a non-tailnet probe that unauthenticated traffic goes nowhere/reaches only Authentik, then separately prove the unchanged tailnet path. The canonical owner link is `https://coolify.mitechconsult.com/`, never a direct IP:port.

### S-15. Traefik routes the Authentik outpost request back through the application middleware

**Trigger:** `/outpost.goauthentik.io/` does not have the documented higher-priority router to Authentik, or the main application router wins the overlap.

**Mechanism:** Forward-auth then loops, returns 404, or produces a generic 500 before a login can complete. Traefik normally sorts rule length unless explicit priority overrides it.

**Avoidance:** Keep the application router at priority 10 and outpost router at 15, route the outpost path directly to Authentik, and test the exact `/outpost.goauthentik.io/auth/traefik` endpoint plus full redirect/callback. See [Authentik’s Traefik template](https://docs.goauthentik.io/add-secure-apps/providers/proxy/server_traefik/) and [Traefik priority](https://doc.traefik.io/traefik/reference/routing-configuration/http/routing/rules-and-priority/).

### S-16. A broad trusted-proxy range lets other containers assert owner identity

**Trigger:** `TRAEFIK_PROXY_CIDR` is set to a Docker supernet, entire tailnet, host LAN, or `0.0.0.0/0` for convenience.

**Mechanism:** Any peer in that range can send accepted Authentik headers. Network reachability becomes identity authority.

**Avoidance:** Resolve the actual Coolify Traefik peer address on the shared network and use the narrowest `/32` or `/128`; fail startup when missing; revalidate after proxy/network recreation; keep the tailnet bypass separate and explicitly scoped. See [Authentik deployment comments](../../../deploy/authentik.yaml) and [Workbench auth settings](../../../modules/workbench/api/app/config/settings.py).

### S-17. Cloudflare is accidentally used as a proxy after the owner limited it to DNS

**Trigger:** The DNS record is orange-cloud proxied, or a Tunnel/Access/Worker is added as a workaround for origin reachability.

**Mechanism:** TLS, source addresses, headers, caching, and access policy then gain a second control plane, contradicting the ruled path and complicating trusted-proxy validation.

**Avoidance:** Use DNS-only records for the ruled origin path; make public 80/443 reach the existing Coolify Traefik directly; document origin firewall/TLS; do not create a tunnel or Worker fallback. See [D-155 and owner correction](../../decisions/2026-09-12-authentik-owner-correction.md).

### S-18. Authentik bootstrap identity and secret become permanent owner credentials

**Trigger:** The bootstrap account remains `akadmin`, bootstrap values remain in Coolify environment state, or a task prints the password into chat/docs to “prove” it knows it.

**Mechanism:** Bootstrap inputs are recovery/setup mechanisms, not the governed owner identity. Persisting or redistributing them expands credential exposure and violates the required `msalem` owner naming contract.

**Avoidance:** Complete setup with the `msalem` owner identity and recovery factors through Authentik’s supported administrative flow. Verify login and break-glass recovery before removing bootstrap material from Coolify. Rotate exposed values. Record only secret locations/rotation receipts—never plaintext passwords—in docs, logs, task prompts, or screenshots.

### A-17. Authentik server/outpost patch mismatch creates proxy-only failures

**Trigger:** The custom server remains 2026.8.0 while an embedded/managed outpost or rebuilt image runs a different patch, or the relevant 2026.8.1/.2 fixes are absent.

**Mechanism:** Authentik requires matching server/outpost versions; the 2026.8 patch releases include proxy/outpost and security fixes.

**Avoidance:** Rebuild/digest-pin 2026.8.2 as one Coolify change, verify the embedded outpost reports the same version, retain an immediate rollback image, and set the base URL before the announced 2026.11 requirement. See [Authentik 2026.8 release notes](https://docs.goauthentik.io/releases/2026.8/) and [version policy](https://docs.goauthentik.io/security/policy/).

### A-18. Source labels are fixed but Coolify is still running the old rendered compose

**Trigger:** A repository review sees correct Authentik/Workbench labels and concludes the live HTTP 500 is fixed without checking the Coolify application’s deployed revision/rendered compose/provider objects.

**Mechanism:** Coolify application source, branch, compose path, watch paths, retained repository behavior, and last deployment are external state. A correct file does not update the running app by itself.

**Avoidance:** Read the exact application UUID and current record first; compare commit/compose path/rendered configuration; inspect build/runtime logs; deploy through Coolify; then probe the real hostname. Report “source fixed,” “deployed,” and “live verified” as three different states. See the [Coolify deployment overview](https://coolify.io/docs/applications/deployments/overview) and the [coolify-write contract](https://coolify.io/docs/applications/builds/docker-compose).

### A-19. A repository-relative file bind becomes an empty directory in Coolify 4.1.2

**Trigger:** Compose uses `./deploy/file.json:/container/file.json` assuming the repository exists beside Coolify’s rendered compose.

**Mechanism:** On the observed Coolify 4.1.2 layout, the application render directory may contain only generated compose/env material; Docker creates a directory where the missing source file was expected. The service then fails with confusing “is a directory,” permission, or parser errors.

**Avoidance:** In the owning deployment task, stage required runtime files to a verified absolute host path such as `/data/probata/config/<app>/...`, hash/read them back, and bind that exact path. Keep the repository copy as source/provenance. Do not assume Compose `content:` worked without a host read-back. This is a verified environment-specific rule from the explicitly requested coolify-write skill.

### A-20. A Coolify environment change is followed by Restart, so the container keeps the old value

**Trigger:** A task upserts an Authentik/Workbench/n8n environment value and invokes restart instead of deployment.

**Mechanism:** Coolify renders environment values into the deployment compose. Restarting the existing container does not necessarily render/recreate it.

**Avoidance:** After an approved environment mutation, dispatch a Coolify deployment for the exact application UUID, inspect the deployment, and verify the effective behavior without echoing secret values. This is a coolify-write 4.1.2 gotcha.

### A-21. “Deployment finished” is reported as “working”

**Trigger:** The Coolify deployment record reaches finished/success and the task closes without hostname, health, auth, and workflow probes.

**Mechanism:** The deployment record proves build/up orchestration, not that routing, Authentik, health checks, content, or downstream services work.

**Avoidance:** Keep the state “deployed, not verified” until the container is healthy and real user-facing probes pass: public unauthenticated denial/challenge, Authentik round-trip, authenticated app/portal content, direct Tailscale path, and relevant application behavior. This is an explicit coolify-write rule.

### A-22. Watch paths are blamed for a failed manual deployment

**Trigger:** A task sees a missed Git-triggered rollout and concludes Watch Paths also explain why a correctly targeted manual redeploy did not change the container.

**Mechanism:** Watch Paths filter Git-provider webhook deployments when changed-file data exists. A dashboard/manual deployment or deployment-webhook call is a separate trigger.

**Avoidance:** Diagnose trigger selection and deployment behavior separately; record application UUID, branch, base directory, compose location, and ordered watch patterns. Remember the last matching watch pattern wins. See [Coolify automatic deployments](https://coolify.io/docs/applications/deployments/automatic-deployments).

### A-23. Tailscale behavior changes while “adding” the public lane

**Trigger:** Authentik/Traefik work removes Tailscale Serve, changes private ports, narrows ACL behavior, or redirects enrolled systems through the public hostname.

**Mechanism:** The two lanes are independent. A public security change can accidentally become a private access migration.

**Avoidance:** Capture current private URLs and responses before public work; leave Tailscale manifests/routes untouched unless separately authorized; rerun the identical tailnet probes after rollout. See [D-155](../../DECISION_LOG.md) and the [Workbench Tailscale contract](../../../deploy/tailscale/workbench-serve.hujson).

## PostgreSQL, packages, graphs, and projections gotchas

### S-19. Later evidence admission trusts the old context hash without rereading the original

**Trigger:** The owner promotes context material to evidence by copying its stored digest/metadata into custody records.

**Mechanism:** The earlier hash is part of the Intake Source Package, not proof that the later admission read the retained original or that the package remained complete.

**Avoidance:** Reopen the retained package, verify deterministic manifest membership, reread/re-hash the byte-identical original, compare fingerprints, re-extract with recorded tool versions, then execute the evidence owner and H1/H2/H3 gates. Produce a distinct Evidence Release Package. See [D-154](../../DECISION_LOG.md).

### S-20. PostgreSQL is treated as the graph database or a graph projection becomes authority

**Trigger:** Relationship/temporal graph logic is implemented as ad hoc PostgreSQL edges while Neo4j/SurrealDB exist, or a graph/vector record is treated as the canonical source/custody record.

**Mechanism:** It erases the explicit authority/projection boundary and makes rebuilds, provenance, and disagreement handling ambiguous.

**Avoidance:** PostgreSQL stores source/package/decision/receipt authority and projection checkpoints. Neo4j owns the semantic relationship projection; SurrealDB owns the governed temporal graph role; Weaviate owns vector retrieval. Every projection row/edge points back to source/package receipts and remains rebuildable.

### S-21. The custom PG18/pg_duckdb image is silently replaced with official PostgreSQL

**Trigger:** A security/minor-version task changes `probata-postgres:18-duckdb` to `postgres:18` because official 18.6 is newer.

**Mechanism:** The custom image includes extension/build assumptions. Substitution can remove `pg_duckdb`, PostGIS, pgvector, or startup lifecycle behavior and make existing migrations/functions fail.

**Avoidance:** Inventory the Dockerfile/base digest/extensions and verify backups/restores before changing it. Rebuild the custom image on a tested base with an SBOM and compatibility suite; never substitute images by name alone. See [PostgreSQL Dockerfile](../../../deploy/docker/postgres/Dockerfile) and [data deployment](../../../deploy/data-pg.yaml).

### S-22. Package membership is called complete while a member is missing, unreadable, or unhashed

**Trigger:** A manifest digest is computed over only the members that happened to succeed, with missing members omitted.

**Mechanism:** The resulting digest proves a smaller set—not the intended package—and creates false future-evidence confidence.

**Avoidance:** Canonically enumerate expected membership; record each member state/digest; make any missing/unreadable/unhashed member visibly incomplete; compute the deterministic manifest digest over the explicit membership/state model; refuse equality/admission claims until complete. See [D-154](../../DECISION_LOG.md).

### A-24. Major-only PostgreSQL tags hide missing patch/security fixes

**Trigger:** `postgres:18-alpine`, `postgres:16-alpine`, or a custom major tag is documented as an exact running version.

**Mechanism:** Mutable tags can resolve to new patches on rebuild, while an old running container may remain behind. Repository text alone proves neither.

**Avoidance:** Query `SELECT version()` live, record image digest, track the supported patch (18.6/16.15 during research), test extensions/restore, then pin or establish an explicit patch-update process. See [PostgreSQL version policy](https://www.postgresql.org/support/versioning/) and [2026 patch release](https://www.postgresql.org/about/news/postgresql-186-1711-1615-1519-1424-and-19-beta-3-released-3365/).

### A-25. SurrealDB is upgraded and then rolled back against changed on-disk data

**Trigger:** A deployment changes the SurrealDB storage version and rollback simply restores the old container tag against the newer data directory.

**Mechanism:** Storage-format changes can make downgrade unsafe even when the container starts.

**Avoidance:** Export/backup and verify restore before upgrade, digest-pin 3.2.4 until a planned migration, and define rollback as data restore—not merely image rollback. See [SurrealDB upgrade constraints](https://surrealdb.com/docs/manage/instances/versions-and-upgrades) and [repository pins](../../../deploy/surreal-case.yaml).

### A-26. Official Neo4j release notes are used to claim a third-party DozerDB image is patched

**Trigger:** A task equates `graphstack/dozerdb:5.26.27.0` with official Neo4j 5.26.27/28 provenance and support.

**Mechanism:** The tag is a third-party distribution. Neo4j’s changelog does not prove the image contents, rebuild date, licenses, or included security fixes.

**Avoidance:** Capture image digest/SBOM/upstream Dockerfile and DozerDB release policy; test backup/restore and clients; do not silently substitute official Neo4j. Track the provenance gap as unresolved. See [repository deployment](../../../deploy/data-neo4j.yaml) and [Neo4j 5.26 changelog](https://github.com/neo4j/neo4j/wiki/Neo4j-5.26-changelog).

### A-27. Weaviate is made publicly reachable or downgraded below the fixed 1.38.7 floor

**Trigger:** A new portal/ingress task adds the vector service to the public catalog, enables anonymous access outside development, or selects 1.38.0–1.38.6.

**Mechanism:** The vector store is a private projection, not a user UI. Weaviate documents a read-repair issue in those earlier 1.38 patches that could produce partial object/vector loss.

**Avoidance:** Keep it private/authenticated, retain at least 1.38.7, digest-pin after client tests, and expose search only through governed app APIs. See [Weaviate known issues](https://docs.weaviate.io/weaviate/release-notes/known-issues) and [repository pin](../../../deploy/data-weaviate.yaml).

## Portal and release gotchas

### S-23. The portal auto-discovers listening ports and publishes infrastructure

**Trigger:** The launcher builds links from Coolify/Docker service discovery without a reviewed allowlist.

**Mechanism:** Tool runtimes, workers, databases, storage, raw webhooks, admin consoles, and private APIs can appear as clickable/public surfaces simply because they have health endpoints or ports.

**Avoidance:** Use the server-side `PortalSurface` allowlist from [SPLIT.md](SPLIT.md). Each entry must name exposure (`authentik_public` or `tailscale_only`), auth mode, role, canonical URL, and health source. Default is absent/private. Admission requires an explicit owner-facing reason and auth/routing proof.

### S-24. “One login” is implemented as “one application only”

**Trigger:** Authentik successfully protects Workbench, and the project declares the owner portal complete without inventorying/routing the other approved surfaces.

**Mechanism:** The required outcome is one owner session leading to a launcher and all explicitly admitted human-facing applications. A single Workbench redirect satisfies authentication plumbing but not the portal job.

**Avoidance:** Maintain the surface catalog, include Workbench/Intake, verified Advocatio legal workdesk, Docstore/knowledge, and approved operations surfaces, and test session continuity/policy per hostname. Keep non-human surfaces private.

### A-28. One domain-level forward-auth provider erases per-application policy

**Trigger:** Multiple applications share Authentik’s domain-level forward-auth mode even though they need different roles/policies.

**Mechanism:** Authentik documents that domain-level mode protects a parent domain but cannot apply separate application policies in the same way as per-application providers.

**Avoidance:** Use per-application providers/outpost assignments when authorization differs; rely on the shared Authentik session for single sign-on, not one undifferentiated policy. See [Authentik forward-auth modes](https://docs.goauthentik.io/add-secure-apps/providers/proxy/forward_auth/).

### A-29. Health checks show green while the operator workflow is broken

**Trigger:** Release verification stops at container `healthy` or `/health` 200.

**Mechanism:** Health does not prove source content, parser capability, photo preview, Temporal query, n8n binding, decision receipts, authentication redirect, or portal routes.

**Avoidance:** Use layered release proof: container health; public denial; login round-trip; tailnet non-regression; portal catalog; photo preview/metadata/options; no-issue bypass; real repair choice; parser override; background/reopen; all-operation filters/detail; n8n/Temporal correlation; package digest/read-back; and a controlled failure path.

### A-30. Fresh tasks mutate the same dirty files because ownership is described only by “frontend” and “backend”

**Trigger:** Multiple new tasks receive broad repository prompts without file allowlists, current dirty inventory, or dependency points.

**Mechanism:** The current tree already contains overlapping modified and untracked Intake/Proffer files. Git sees a shared working directory; one task can overwrite or broad-stage another’s work.

**Avoidance:** Give every new task a bounded lane, exact allowed paths, read-only dependencies, forbidden paths, current HEAD/status snapshot, and handoff target. Tasks must re-read `AGENTS.md`, coordination, current handoff, and `git status` before edits; never reset, clean, stash, broad-stage, or delete. The lane matrix and prompts in this build kit are the authority.

### B-3. `advocatio` is shown as a mysterious service name

**Trigger:** The portal uses a repository/container name without identifying its human job.

**Mechanism:** The owner cannot tell which surface is the legal workdesk or whether a similarly named service is safe to expose.

**Avoidance:** Verify repository, live application, hostname, and auth mode; label it “Advocatio — Legal Workdesk” in the catalog; keep the internal identifier secondary.

### B-4. Coolify’s correct URL is replaced by an IP address in a handoff

**Trigger:** A task copies an SSH/debug endpoint into “links to everything.”

**Mechanism:** Direct ports bypass canonical TLS/routing expectations and become stale or unsafe bookmarks.

**Avoidance:** Publish only `https://coolify.mitechconsult.com/` as the Coolify UI, label it Tailscale/private-by-default, and keep raw addresses in restricted operational diagnostics only.

## Release-blocking severe checks

No release may be called complete while any answer below is “no” or “unknown”:

1. Does a non-tailnet, unauthenticated request fail before every admitted app and before Coolify?
2. Does Authentik log in the `msalem` owner and preserve an independently proven recovery path without exposing a password?
3. Do enrolled owner systems retain their unchanged direct Tailscale access?
4. Does a normal photo bypass repair, render or explain preview capability, show metadata, and offer real OCR/vision/preserve/context alternatives?
5. Can a repair gate name a concrete issue, detector/version/evidence, actual derived option when one exists, and permitted original override?
6. Is parser selection a registered/versioned capability with visible alternatives and a recorded override—not an extension label?
7. Does every started source have one stable operation binding the package/version, decisions, Temporal state, n8n binding/execution, stages, outputs, errors, and receipts?
8. Can the operator leave, return, filter all in-flight/waiting/failed/completed work, and see what is running or blocking?
9. Are all visible commands backed by durable transition policy, idempotency, and append-only receipts?
10. Does context/ELT avoid false evidence custody while the Intake Source Package remains verifiable for later admission?
11. Are Neo4j/SurrealDB/Weaviate still explicit private projections with PostgreSQL/package provenance, not competing authorities?
12. Was production changed only through the correct Coolify application/compose source and proven at the actual hostnames—not merely built?
