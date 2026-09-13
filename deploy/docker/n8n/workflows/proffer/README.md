# Universal import Activity bodies + Temporal integration

Five deliberately small n8n 2.36.6 workflow exports implement the HTTP body
of the two n8n-backed parser Activities plus the "start / decide / preview"
surface a human operator uses to run one end-to-end import through
`engine/proffer.ProfferWorkflow` — the real 23-stage workflow, not a
substitute. Temporal remains the durable owner of sequencing, timeouts,
retry policy, and the human preview hold's Signal/Query/Timer state; n8n
only validates envelopes, calls the authenticated Go HTTP endpoint it owns,
validates the response, and sends it back to the caller.

```
n8n "start" webhook --> engine/temporal starter HTTP --> Temporal client
  --> engine/proffer.ProfferWorkflow
        --> register_source_activity ... the observation fan-out (stages 1-6)
        --> select_parser_activity  --> n8n "select" webhook --> engine/runtimeapi (Go parser)
        --> [human preview hold: a real Signal + Query + Timer, entirely
             inside ProfferWorkflow — engine/proffer/preview.go]
        --> n8n "decision" webhook --> engine/temporal starter HTTP --> Signal
        --> execute_parser_activity --> n8n "execute" webhook --> engine/runtimeapi (Go parser)
        --> persist/hash/reconcile/normalize/seal/publish (stages 9-22)
```

The preview hold lives **inside** ProfferWorkflow itself, as a
genuine Temporal Signal + Query + Timer, not as a trick at the Activity
boundary in `engine/temporal`. That is a deliberate, load-bearing choice: only
a workflow-level hold survives a worker restart or a replica change, because
Temporal replays the workflow's own durable history to resume it, independent
of any one worker process. An earlier design that tried to implement the hold
via Activity async-completion (with an in-process hold store bridging a
worker and a starter process) could not give that guarantee and was rejected
— see `engine/to_be_deleted/temporal-holds.go.obsolete`, kept for history.

## Workflows and stable webhook paths

| File | Purpose | Webhook path | Calls |
|---|---|---|---|
| `wf-select-parser-activity.json` | `select_parser_activity` body | `proffer/select-parser-activity` | `engine/runtimeapi` `/activities/select_parser_activity` |
| `wf-execute-parser-activity.json` | `execute_parser_activity` body | `proffer/execute-parser-activity` | `engine/runtimeapi` `/activities/execute_parser_activity` |
| `wf-start-import.json` | begin one `ProfferWorkflow` run | `proffer/start` | `engine/temporal` starter `POST /reference-import/start` |
| `wf-preview-decision.json` | approve/reject a held run | `proffer/decision` | `engine/temporal` starter `POST /reference-import/{workflow_id}/decision` |
| `wf-preview-status.json` | read a run's current preview state | `proffer/preview` (GET, `?workflow_id=`) | `engine/temporal` starter `GET /reference-import/{workflow_id}/preview` |

The runtime URLs are explicit, non-secret configuration in each HTTP Request
node. Checked-in exports use the fail-closed hosts
`https://import-runtime.example.invalid` and
`https://reference-import-starter.example.invalid`; deployment must replace
those literals with the two stable service endpoints before activation. Keep
the authentication values in the existing n8n credentials, never in the URL
or export.

This split is deliberate for n8n Community 2.36.6. n8n 2.x blocks `$env`
access from node expressions by default, Custom Variables (`$vars`) are not a
Community feature, and HTTP Header/Custom Auth credentials can add request
headers, query parameters, or body fields but do not own the request URL.
Disabling `N8N_BLOCK_ENV_ACCESS_IN_NODE` would relax the entire instance, so
these workflows do not use `$env` at all. The HTTP node's own URL field is the
smallest supported, workflow-scoped home for a non-secret endpoint. All five
workflows remain inactive on import until the URL literals and credential IDs
have both been bound and re-read.

**Corrected 2026-08-27:** the select/execute workflows previously called
`.../v1/activities/<name>` — a path `engine/runtimeapi/parser_activities.go`
(`SelectParserPath`/`ExecuteParserPath`) has never actually served; the real
mount point is `/activities/<name>` with no version prefix. Both JSON exports
now call the correct path.

**Added 2026-08-27:** the two existing Webhook trigger nodes previously had
no `authentication` set at all, so anyone who discovered the webhook URL
could invoke a real parser Activity. All five Webhook nodes now require the
`headerAuth` credential `N8N_PROFFER_WEBHOOK (placeholder)` — set a
real header/value pair on it before activating any of these workflows in a
live instance.

## Generic flow Activity registry

The Proffer worker also registers one generic Temporal Activity named
`run_n8n_flow_activity`. Its body resolves a named n8n flow from the optional
JSON file named by `N8N_FLOW_BINDINGS_FILE`, validates the flow's declared
reference and scalar-input requirements, and then calls the bound webhook.
Temporal still owns retries and durability; the request carries locators and
bounded inputs, never source bytes.

`N8N_FLOW_BINDINGS_FILE` is optional. With no file configured, the worker
starts with zero extra flow bindings and the two dedicated parser Activities
continue to work. When the variable is set, it must point to an absolute,
read-only mounted regular file. A missing, unreadable, malformed, duplicate,
or unsafe binding stops worker startup instead of silently producing an empty
registry. Startup logs include `n8n_flow_binding_count` only; they do not log
URLs or credentials.

The deployed compose file does **not** currently mount or select a production
binding document, and none of the checked-in inactive `.example.invalid`
workflow exports is activated by this registration. A deployable binding must
name a real active webhook that implements the `FlowRequest` / `FlowResult`
contract in `engine/temporal/flowactivity.go`. A Temporal workflow or operator
plan must also explicitly schedule `run_n8n_flow_activity`; merely declaring a
binding does not insert it into `ProfferWorkflow`.

For Coolify 4.1.2, do not add a repository-relative bind such as
`./deploy/.../bindings.json:/run/config/...`: Coolify renders the compose in an
application directory that does not contain the repository checkout, and
Docker creates an empty directory at the missing source path. Provision the
reviewed JSON as an absolute host file (for example under
`/data/probata/config/proffer-worker/`), mount that absolute file read-only,
and set `N8N_FLOW_BINDINGS_FILE` to its absolute container path. An environment
change requires a Coolify deploy, not only a container restart, followed by an
actual webhook/worker health check before calling the binding active.

**Corrected 2026-08-27:** `wf-start-import.json` and `engine/temporal`
previously started a smaller, package-local substitute workflow instead of
the real `ProfferWorkflow`, and implemented the preview hold as
in-process Activity async-completion rather than a workflow-level Signal.
Both are now the real workflow and a real Signal/Query/Timer — see the note
above.

## Compact contracts: select / execute

The Webhook body must contain exactly these fields:

```json
{
  "request_id": "temporal-activity-request-id",
  "source_version_ref": "custody-or-source-version-ref",
  "declared_format": "pdf",
  "refs": {
    "filesystem_metadata": "filesystem-metadata-ref",
    "container_manifest": "container-manifest-ref",
    "metadata_manifest": "metadata-manifest-ref"
  }
}
```

For `select_parser_activity`, `refs` is a non-empty object with exactly the
named compact references `filesystem_metadata`, `container_manifest`, and
`metadata_manifest`. For `execute_parser_activity`, it must instead contain
exactly `parser_selection`, `original`, and `parser_options`, each as a
non-empty string reference. Arrays, unknown names, empty values, files, binary
input, raw records, normalized records, and content are rejected before the
HTTP call. The same `request_id` is sent in both `X-Request-ID` and
`Idempotency-Key`; n8n does not generate, hash, persist, or otherwise transform
that identity.

An execute request therefore has this shape:

```json
{
  "request_id": "temporal-activity-request-id",
  "source_version_ref": "custody-or-source-version-ref",
  "declared_format": "pdf",
  "refs": {
    "parser_selection": "parser-selection-ref",
    "original": "retained-original-ref",
    "parser_options": "parser-options-ref"
  }
}
```

The import-runtime response must contain exactly:

```json
{
  "stage": "select_parser_activity",
  "status": "success",
  "ref": "runtime-result-ref",
  "receipt_ref": "runtime-receipt-ref"
}
```

The execute workflow requires `stage: "execute_parser_activity"`; both flows
require `status: "success"`. An HTTP error or malformed StageResult fails the
execution and does not reach the Respond node.

## Compact contracts: start / decision / preview

`wf-start-import.json` mirrors `engine/proffer.WorkflowInput` exactly — this
starts the real workflow from its actual root input, not a partially-observed
mid-pipeline state:

```json
{
  "request_id": "temporal-workflow-id",
  "source_ref": "not-yet-retained-acquisition-ref",
  "declared_format": "pdf",
  "parser_options_ref": "parser-options-ref"
}
```

and the starter responds `{"workflow_id": "...", "run_id": "..."}` (the
`request_id` you sent, echoed back as the Temporal workflow ID — using it
again for the same source joins the existing run instead of starting a
second one). `wf-preview-decision.json` accepts
`{"workflow_id": "...", "approved": true|false, "reason": "...", "decider": "..."}`
(`reason` is required when `approved` is `false`) and the starter responds
`{"status": "signaled"}` once the Signal is delivered — delivery, not the
workflow having acted on it yet, since Signals are asynchronous.
`wf-preview-status.json` is a `GET` with `?workflow_id=...` and returns the
current `{"phase": "...", "select_ref": "...", "reason": "..."}` (`reason`
only present once the run has left `awaiting_decision`). `phase` is one of
`awaiting_decision`, `approved`, `rejected`, `timed_out` — see
`engine/proffer/preview.go`'s `PreviewPhase` constants. The hold itself sits
between `select_parser_activity` and `execute_parser_activity`
(`engine/proffer/workflow.go`) and times out after 24 hours
(`engine/proffer/preview.go`'s `previewDecisionTimeout`) if never decided — a
real Temporal Timer, not bounded by any Activity's own timeout.

## Node inventory

All five exports use the same five-node shape and no branches: Webhook
(POST or GET, `responseMode: responseNode`) -> a `Code` node that enforces
the exact request contract above (named fields only, unknown fields rejected)
-> an authenticated `httpRequest` node -> a `Code` node that enforces the
exact response contract -> `respondToWebhook`.

The select/execute HTTP nodes use the placeholder credential
`PLATFORM_IMPORT_RUNTIME (placeholder)`; the start/decision/preview HTTP
nodes use `REFERENCE_IMPORT_STARTER (placeholder)`. Both are `httpHeaderAuth`
type — replace their credential ID/name in the n8n instance; no token or
secret is present in these exports. There is no `retryOnFail`, retry counter,
wait, batch, persistence, hashing, classification, or enrichment node
anywhere in this directory. Temporal owns retries, the hold, and idempotent
Activity execution; the platform runtime owns parsing, persistence, receipts,
and the PostgreSQL timeline contract; `engine/temporal`'s starter owns only
relaying start/Signal/Query calls to Temporal. The select call uses a
30-second HTTP timeout to stay within its Activity budget; execute uses
1,800,000 ms (30 minutes); start/decision/preview each use 10,000 ms.

## The `engine/temporal` side

`engine/cmd/proffer-worker` is the sole production Temporal worker:
it registers the real `engine/proffer.ProfferWorkflow` and all 23 canon
Activity names on one dedicated UIW task queue. The two parser Activities are
thin, heartbeating HTTP proxies to the n8n webhooks above; the other 21 use
their concrete PostgreSQL/runtime implementations. The old
`engine/temporal/cmd/worker` partial-worker entry point is retired and fails
closed instead of polling a queue with only two registered bodies.
`engine/temporal/cmd/starter` is the small authenticated HTTP service the
three other n8n workflows call, since n8n has no native Temporal client: it
starts a run, sends the preview_decision Signal, and answers the preview
Query. Both binaries can run as **separate processes** (or many replicas of
either) — Decide/Preview go through the Temporal server as a real
Signal/Query against the workflow's own durable history, not any in-process
state shared between them.

The existing Python worker continues polling `evidence-pipeline` unchanged.
The Go UIW worker rejects that queue name at startup: disjoint partial workers
must not compete for Activity tasks on one queue.

Shared starter/worker environment:

| Variable | Purpose |
|---|---|
| `TEMPORAL_HOST_PORT` | Temporal frontend address |
| `TEMPORAL_NAMESPACE` | Temporal namespace |
| `TEMPORAL_TASK_QUEUE` | dedicated UIW task queue shared by the all-23 worker and starter; never `evidence-pipeline` |
| `N8N_PROFFER_BASE_URL` | n8n webhook base (worker only) |
| `N8N_PROFFER_AUTH_HEADER` / `N8N_PROFFER_AUTH_VALUE` | header the worker sends on every call to the n8n webhooks — must match the `headerAuth` credential on the select/execute Webhook nodes (worker only) |
| `N8N_FLOW_BINDINGS_FILE` | optional absolute, read-only mounted JSON registry for extra flows invoked through `run_n8n_flow_activity`; an explicitly configured missing or invalid file stops worker startup |
| `REFERENCE_STARTER_TOKEN` | bearer token the starter HTTP service requires — must match the `headerAuth` credential on the start/decision/preview Webhook nodes |
| `REFERENCE_STARTER_ADDR` | starter listen address (default `:8091`) |
| `SELECT_PARSER_HTTP_TIMEOUT` / `EXECUTE_PARSER_HTTP_TIMEOUT` | optional overrides (Go duration strings) |

The worker additionally requires `PLATFORM_DATABASE_URL` and four absolute
shared roots: `SOURCE_OBJECT_DIR`, `PARSER_BUNDLE_DIR`,
`NORMALIZED_BUNDLE_DIR`, and `INVENTORY_MANIFEST_DIR`. See
`deploy/proffer-worker.yaml`. The parser runtime must mount its
parser-bundle host directory at the same container path the worker sees;
otherwise retained `file://` locators correctly fail closed.

## Deployment checklist

1. Import all five JSON files into the n8n 2.36.6 instance.
2. Replace `https://import-runtime.example.invalid` in select/execute and
   `https://reference-import-starter.example.invalid` in
   start/decision/preview with the stable, non-secret live service endpoints.
   Bind the `PLATFORM_IMPORT_RUNTIME` and `REFERENCE_IMPORT_STARTER` header
   credentials separately; do not put tokens in the URL or workflow export.
3. Attach a real `N8N_PROFFER_WEBHOOK` `headerAuth` credential to
   all five Webhook trigger nodes, and configure `engine/temporal`'s worker
   and starter with the matching header/value via
   `N8N_PROFFER_AUTH_HEADER`/`_VALUE` and `REFERENCE_STARTER_TOKEN`.
4. Confirm the production/test webhook base URL and the five paths above.
5. Deploy `deploy/proffer-worker.yaml`, confirm its startup schema
   gate passes, and deploy the starter against the identical dedicated queue.
6. Keep the workflows inactive while reviewing endpoints and credentials;
   activate only once the all-23 worker and starter are both running.
7. Start a run, poll preview, send a decision, and verify the approved run
   reaches publication or a rejected/timed-out run fails closed before parser
   execution.

No local containers or live n8n deployment are part of this packet.
