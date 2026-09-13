# Stack Decision — Probata Intake and Owner Portal Recovery

**Research date:** 2026-09-12
**Planning boundary:** This is an incremental recovery and convergence plan for the existing Probata platform. It is not a second implementation and it does not authorize deployment from this planning artifact. A later owner-directed isolated test changed the React/Glide implementation route described in D-157: this kit plans a bounded exact-pinned Glide alpha24 integration on the existing React 19 client, with an explicit adoption/release gate and rollback.

## Application type

An existing full-stack platform with a browser-first operator application, an optional Tauri desktop host, a same-origin FastAPI boundary, a Go/Temporal durable workflow engine, n8n visual orchestration, governed PostgreSQL and object-storage records, and separate graph/vector projections.

## Chosen stack

Versions below are either the target selected by the owner’s settled decisions, an exact repository lock/pin, or a researched release target. “Repository pin” is deliberately not presented as “ecosystem latest.”

| Layer | Choice | Version (as of 2026-09-12) | Why |
|---|---|---:|---|
| Shared browser UI | React + React DOM | **19.2.3 repository lock and bounded-integration target** | Preserve the current client runtime. The owner chose to test the exact Glide alpha rather than make a React 18 downgrade the mandate; the isolated compatibility application passed dependency deduplication, a 100,000-row real-browser grid, editing/navigation/paste, TypeScript/Vite build, Storybook build, UI tests, and lint. Product integration still has its own gate. |
| UI language | TypeScript | **5.9.3 repository lock** | Keep the existing strict typed boundary and generated/shared contract types. Pin the exact resolved version across shared UI packages instead of leaving the current `^5` manifest range to drift. |
| Browser build/runtime | Vite | **8.2.2 repository lock** | The Workbench is already a browser SPA built by Vite and served by its same-origin FastAPI container. Vite 8 requires modern Node; the repository already declares Node >=22.13. |
| Routing and URL state | TanStack Router | **1.170.32 repository lock** | Typed routes and search parameters fit persistent operator views: selected source, operation filters, current tab, and reopened workflow state must be URL-addressable instead of component-local accidents. |
| Component contract | Storybook React/Vite | **10.5.10 repository lock** | Every important async state can be reviewed independently: loading, no preview, parser alternatives, repair detected, backgrounded, held, failed, retryable, and complete. Storybook 10 is ESM-only, which matches the existing ESM Vite application. |
| Data-heavy operator tables | `@glideapps/glide-data-grid` behind a shared adapter | **exact `6.0.4-alpha24` bounded-integration target** | One virtualized grid foundation for in-flight operations, packages, sources, receipts, and errors. Alpha24 passed the owner-directed isolated React 19.2.3 compatibility suite. It remains prerelease software, so the version must not float, direct imports stay behind the shared adapter, regression coverage and rollback remain mandatory, and final product adoption is a named gate. |
| Styling and primitives | Existing Tailwind/Radix/CVA component foundation | **repository-locked set; exact shared-package pins required in Phase 1** | Preserve the current visual language and consolidate it into shared packages. Do not create another design system while repairing Intake. |
| Desktop host | Tauri | **2.x target; exact pin at desktop phase** | Tauri is the native shell and bridge only. The shared React application remains the product UI. Native file selection and local filesystem capabilities cross explicit Tauri commands; business workflow truth does not move into the shell. |
| Browser/BFF boundary | FastAPI on Python | **Python 3.12 repository image; FastAPI 0.141.1 target** | The current Workbench already serves the Vite build and same-origin API from one service. Keep it as a browser-facing adapter and policy boundary, not a second durable workflow engine. Replace broad `>=` dependency ranges with a tested lock. |
| BFF runtime support | Uvicorn + Pydantic + HTTPX | **Uvicorn 0.52.4, Pydantic 2.13.5, HTTPX 0.28.1 targets** | These are the researched stable targets for the existing ASGI, schema-validation, and service-client roles. They must be compatibility-tested with the repository’s pinned Agno 2.8.7 before the lock changes. |
| Durable engine | Go | **1.26.6 repository directive** | Retain the existing strongly typed runtime, package, receipt, and workflow implementation. Do not reimplement these guarantees in the UI or n8n. |
| Durable orchestration | Temporal Server + Go SDK | **Server 1.29.7; UI 2.53.3; Go SDK 1.48.0 repository pins** | Temporal owns durable execution, retries, waiting, signals, cancellation semantics, and recovery. A user may leave Intake and later reopen the same operation without losing workflow identity. |
| Visual/service orchestration | n8n | **2.38.7 target; repository currently uses `latest` and exports describe 2.36.6** | n8n owns inspectable integration plans and bounded service composition. It is invoked from a governed Temporal activity/binding and receives references, not uncontrolled evidence payloads. Pin the image; `latest` is not a reproducible deployment contract. |
| Relational authority and receipts | PostgreSQL | **18.x; resolve and digest-pin a tested 18.6 image for standard images** | PostgreSQL remains authority for identities, operation indexes, typed decisions, package/receipt metadata, and custody records. Context/ELT bytes do not have to be copied through PostgreSQL first, and PostgreSQL is not the graph engine. Custom `probata-postgres:18-duckdb` images require their own immutable build provenance. |
| Original bytes and package members | Existing R2/B2-compatible object-store boundary | **service contract; no client-side version** | The Intake Source Package preserves an immutable object reference, original-byte fingerprint, extracted members, and deterministic manifest digest. Later evidence admission reopens and rehashes the retained package; it never relabels a context fingerprint as custody. |
| Tabular/file extraction | Existing governed DuckDB handler/package path | **exact runtime package pin to be captured by the separate D-149 cutover lane** | DuckDB is an extraction/query capability selected by declared format and validated content. It is not inferred merely from seeing “SMS XML route,” and it does not replace the durable operation ledger. |
| Graph projections | Existing Neo4j and SurrealDB services, with explicit projection ownership | **live deployed versions must be captured before mutation** | Relationship and temporal-graph views belong in actual graph databases. PostgreSQL keeps authoritative records and projection receipts; it does not pretend to be the graph store. No graph database is retired or consolidated by this build kit. |
| Vector projection | Existing Weaviate service | **1.38.7 repository pin** | Keep vector retrieval a rebuildable projection downstream of governed source/package records. It must not become the custody authority. |
| Public browser identity | Authentik behind existing Coolify Traefik | **Authentik 2026.8.2 target; repository image is 2026.8.0** | One real browser login/session protects each explicitly admitted human-facing hostname. Apps without suitable OIDC use the embedded-outpost forward-auth pattern; capable apps may use authorization code with PKCE. Identity headers are accepted only from the exact trusted proxy peer. The target is the latest researched patch of the already-selected supported train, not a major/minor redesign. |
| Private owner access | Existing Tailscale routes | **unchanged** | Trusted owner systems retain direct, unfettered private access. Tailscale is not replaced, narrowed, or forced through the public Authentik route. |
| Deployment control plane | Coolify + its existing Traefik proxy | **Coolify 4.1.2 stable; canonical UI `https://coolify.mitechconsult.com/`** | Production changes are made through the actual Coolify application/source/compose records. Coolify itself is an operational surface: the normal owner route is Tailscale, and any non-tailnet route must stop at Authentik before Coolify. A direct host/port URL is not a user-facing link. Cloudflare provides DNS only; no Tunnel, Access, Worker proxy, second ingress, or hand-run competing production deployment is added. |

## Rejected alternatives

| Layer | Runner-up | Why it lost |
|---|---|---|
| Shared UI | Immediate React 18.3.1 downgrade plus stable Glide 6.0.3 | This remains the stable fallback, but it lost as the first implementation route after the owner requested a direct alpha test and exact alpha24 passed the isolated React 19.2.3 browser/build suite. Avoiding a framework downgrade preserves the current client while the prerelease risk is contained behind an adapter, exact pin, regression suite, and rollback. |
| Grid release policy | Floating `next`/`beta`, caret range, or an untested later Glide alpha | The compatibility evidence applies only to `6.0.4-alpha24`. A different prerelease is a different stack and requires the same test matrix. |
| Browser application framework | New Next.js application or continued Next-only Advocatio conventions | The product is an authenticated, stateful operator SPA and gains no required server-component or SSR capability. Tauri’s recommended integration is a static SPA/SSG frontend, and D-156 requires one shared React/TanStack foundation. Existing Next code remains supported only as transitional compatibility work. |
| Grid/table layer | Per-page HTML tables or a second grid library | This recreates the existing fragmentation and makes filtering, keyboard behavior, virtualization, and state restoration inconsistent. Migrate one complete operational table at a time to Glide instead. |
| Browser integration | Direct browser calls to Go workers, Temporal, n8n, databases, or object stores | It exposes infrastructure and service credentials, splinters authorization, and bypasses the same-origin policy/receipt boundary. Browser code talks only to the Workbench BFF. |
| Durable workflow engine | n8n alone | n8n is valuable for visual service composition, but Temporal already owns workflow/run identity, durable waits, retry policy, cancellation, and replay-safe recovery. n8n execution IDs are correlated children of the stable Intake Operation, not its identity. |
| Orchestration visibility | Temporal alone | Temporal durability does not replace a human-readable integration plan or n8n’s visual service composition. The correct split is Temporal durability plus n8n bounded plans, joined by one operation ledger. |
| Public routing | One hostname with every application forced under subdirectories | Independent SPAs, cookies, redirects, generated assets, and WebSockets can break under an unproven base path. Default to per-application hostnames behind one Authentik session; allow a subpath only after explicit compatibility tests. |
| Public transport | Cloudflare Tunnel, Cloudflare Access, or a Worker proxy | The owner ruled Cloudflare’s role to DNS only. Existing public HTTPS terminates through the host’s Coolify Traefik. |
| Authentication | Whole-bearer comparison against a signing secret | That is neither JWT validation nor a browser login flow. JWT consumers validate signature, issuer, audience, expiry, and required claims against issuer keys; browsers use an Authentik session/OIDC flow. |
| Private access | Sending Tailscale traffic through Authentik or removing direct routes | This violates the settled two-lane access model. Tailscale remains unchanged and direct for enrolled owner systems. |
| Relational/graph boundary | PostgreSQL as the graph database | PostgreSQL owns authoritative records and projection receipts; Neo4j and SurrealDB own the graph projections. Conflating them would erase explicit projection and rebuild boundaries. |
| Source intake | “Evidence or never evidence” choice at initial upload | D-154 settled package-first preservation. The operator chooses what happens now—context/ELT, metadata, OCR, vision, preserve-only, or an eligible parser—without forfeiting later evidence admission. |
| Repair control | Defaulting `repair_required=true` when a detector omits an exact flag | Absence of a flag is not a detected defect. A repair gate is allowed only after a concrete, validated issue with detector details and an original-source override. |

## Integration mechanism

The primary browser integration is **same-origin REST/JSON**:

1. The React/TanStack UI calls only the Workbench FastAPI BFF under the same origin. OpenAPI schemas and generated/shared TypeScript types define the boundary.
2. FastAPI performs browser-session/actor enforcement, request validation, read-model composition, and reference-safe calls to the Go runtime. It does not own workflow truth.
3. The Go runtime creates one stable **Intake Operation** and binds its package/version IDs, current-purpose decision, parser/detector decisions, Temporal workflow/run IDs, n8n execution/binding IDs, outputs, errors, and receipts.
4. Temporal commands, signals, queries, and activities own durable lifecycle. REST endpoints expose truthful control capabilities; the UI must not render Cancel, Retry, Hold, Resume, or Override until the corresponding durable command and receipt exist.
5. n8n runs bounded visual subflows invoked through a recorded flow binding. Payloads carry opaque references and minimum necessary metadata; governed bytes and secrets remain behind service boundaries.
6. Operator progress retains the existing **REST plus Server-Sent Events** split. The operation registry uses bounded REST polling with opaque cursors/pagination; an opened preview uses the existing SSE notification stream to trigger authoritative REST snapshot/message reloads. SSE is a cache-invalidation signal rather than workflow truth. WebSockets are not required for this recovery.
7. Tauri uses an explicit **native command bridge** only for desktop capabilities such as local file selection/read staging. It then calls the same application contracts and never creates a parallel workflow/state model.

The access paths are intentionally separate:

```text
ordinary browser -> Cloudflare DNS -> public HTTPS -> Coolify Traefik
                 -> Authentik login/session -> approved human-facing app hostname

enrolled owner system -> existing Tailscale route -> direct private app/service access
```

The public portal is a launcher and session boundary for all explicitly admitted owner-facing UIs, not merely a redirect to Workbench. Infrastructure APIs, workers, databases, object stores, Temporal internals, n8n webhooks, tool-runtime services, and Tauri/native bridges remain private. The Coolify control plane is also private-by-default: its canonical UI is `https://coolify.mitechconsult.com/`, normal owner access is through Tailscale, and a non-tailnet request without Authentik must go nowhere rather than reaching either Coolify’s UI or a direct port.

## Time-sensitive flags

- **React/Glide evidence boundary:** exact Glide `6.0.4-alpha24` passed an isolated React 19.2.3 compatibility test: one deduplicated React tree, a lazy 100,000-row `DataEditor`, real-browser selection/ArrowDown/boolean and text editing/TSV paste, TypeScript+Vite build, Storybook static build, 14 passing UI tests, four jsdom canvas cases intentionally skipped and browser-verified, and lint with zero errors. This proves the isolated stack, not Probata product adoption or a stable-release guarantee.
- **Native limitation:** the isolated frontend built, but native Tauri/Rust linking could not resolve `kernel32.lib` in the current Windows SDK environment. No alpha runtime failure was observed, but desktop packaging remains unproven and cannot be included in a release claim.
- **Current Workbench integration gap:** `package-lock.json` resolves React 19.2.3, TypeScript 5.9.3, TanStack Router 1.170.32, Storybook 10.5.10, and Vite 8.2.2; Glide is absent. The isolated test used Storybook 10.6.0, so product integration must exact-pin alpha24 and rerun the actual Workbench lock/build/smoke/Storybook/browser matrix. Keep the grid behind a shared adapter and preserve a one-commit rollback to the pre-Glide table.
- **Canonical-decision reconciliation:** D-157 still records React 18.3.1 + stable Glide 6.0.3 as the settled baseline. Before product merge/release, the newer owner-directed alpha24 result and bounded exception must be amended/read back through the governed decision path. The requested dedicated `docstore_handoff_write` tool was not exposed to this planning task, so this file does not pretend that governed write occurred.
- **Current Intake work is concurrent and unmerged:** the operation registry, image preview, source tabs, filters, URL state, cursor pagination, and supporting engine/BFF contracts exist in the dirty working tree; the operations table and its smoke contract are untracked. Treat them as implementation input, not committed or deployed proof, and preserve their owners’ edits.
- **Parser/repair capabilities are not negotiated yet:** the current browser derives a descriptive route from the filename and sends `parser-options://default-v1`; it has no live capability inventory for OCR, vision, metadata-only, preserve-only, or alternate parsers. The current repair continuation is also one-sided and offers only the sealed original. Those are product gaps, not evidence that the source needs repair.
- **Schema optionality drift:** the Python preview contract permits correlation/digest/receipts to be absent before parsing, while the current TypeScript interface requires them. Generate or mechanically reconcile the client schema before relying on those fields in repair and pre-parser states.
- **Vite/Node floor:** Vite 8’s published migration material requires Node 20.19+ or 22.12+. The repository’s Node >=22.13 contract is compatible, but every build image and Coolify builder must match it.
- **Storybook 10:** Storybook 10 is ESM-only. Preserve `type: module` and audit addons/config instead of copying CommonJS examples.
- **Python dependency drift:** the API currently uses broad `>=` ranges. The exact FastAPI/Uvicorn/Pydantic/HTTPX target set must be locked and tested together with Agno 2.8.7; a successful local import is not enough without API tests and container build proof.
- **n8n image drift:** the checked-in compose uses `n8n:latest`, while checked-in workflow material targets Community 2.36.6 and the researched stable release is 2.38.7. Replace the floating tag with an exact tested image/digest through the owning Coolify application. Imported JSON, credentials, validation, flow bindings, and publish/activation are separate requirements; Git presence does not activate a workflow. n8n uses the Sustainable Use License rather than an OSI open-source license; this plan assumes internal platform use, not selling hosted n8n access.
- **Authentik patch level:** the repository image is 2026.8.0 and the researched supported-train patch is 2026.8.2. The 2026.8 release line changed proxy/outpost implementation and tightened trusted-proxy behavior, while 2026.8.1/.2 contain relevant proxy/outpost and security fixes. Rebuild and digest-pin 2026.8.2 through Coolify after backup/config preflight; keep server and embedded outpost versions aligned and set the base URL before the announced 2026.11 requirement.
- **Authentik source versus live behavior:** source labels and embedded-outpost routes do not prove the deployed provider/application/outpost assignment. The last observed public Workbench request returned HTTP 500. Inspect the live Coolify application, deployed labels, Authentik objects, and logs before changing source again.
- **Coolify-only production path:** watch paths and compose-file selection are application state. Confirm the actual application, branch, compose path, and deployment UUID before dispatch. A repository commit or local container is not production proof.
- **Coolify UI exposure:** inventory DNS and both public/private routes for `https://coolify.mitechconsult.com/`. Prove direct Tailscale owner access still works, an unauthenticated non-tailnet request cannot reach Coolify, and any intentionally enabled outside route completes Authentik before Coolify’s own surface. Never publish a direct `http://<tailnet-ip>:8000/` address as the canonical UI.
- **Temporal production packaging:** the repository pins Temporal Server 1.29.7 in `temporalio/auto-setup`, while upstream now describes `auto-setup` as deprecated for production and publishes Server 1.32.0. Do not combine a packaging migration with an untested server-minor jump. First capture schemas/backups and move to explicit schema management with a compatible server image; then consider the version upgrade as a separate gate. The Go SDK 1.48.0 is current and does not require numeric parity with the server.
- **PostgreSQL image provenance:** official PostgreSQL 18.6 was current during research, but Probata also uses a custom PG18/pg_duckdb image. Do not silently substitute an official image or minor-upgrade the custom build; capture its Dockerfile, extensions, digest, backup, and restore compatibility first.
- **Graph service state:** Neo4j and SurrealDB are active, separately governed stores. Capture their live deployed image versions, namespaces/databases, credentials path, health, and projection ownership before any integration mutation.
- **Parallel implementation:** another task owns the `/v1/ingest` to Go `/api/proffer/start` cutover and D-149 DuckDB XML handler selection. This build kit consumes that contract and must not create a competing endpoint or handler registry.

## Research limitations

This stage used current official project documentation/registries plus the checked-in repository locks and decisions. It did **not** mutate or redeploy any live service, and it did not treat locally modified concurrent work as merged. Live Coolify application state, deployed image digests, Authentik object configuration, graph-service versions, and end-to-end browser behavior must be captured in the implementation preflight before a production claim.

## Sources

### Owner decisions and repository truth

- [D-154 through D-157: package-first intake, public Authentik lane, shared UI, and the earlier stable React/Glide baseline](../../DECISION_LOG.md)
- [Settled decision register](../../registers/SETTLED.md)
- [Intake workflow visibility and repair-gate decision](../../decisions/2026-09-12-intake-workflow-visibility-and-repair-gate.md)
- [Authentik owner correction](../../decisions/2026-09-12-authentik-owner-correction.md)
- [Workbench web manifest](../../../modules/workbench/web/package.json) and [resolved npm lock](../../../modules/workbench/web/package-lock.json)
- [Owner-directed Glide alpha24 isolated compatibility artifact](C:/Users/matts/.codex/visualizations/2026/09/12/01a09663-e9bb-72c2-bfce-c0714cba8d66/glide-alpha-compat) (local, not a Probata product checkout)
- [Go module and Temporal SDK pins](../../../modules/engine/go.mod)
- [Workbench Python requirements](../../../modules/workbench/api/requirements.txt)
- [Temporal deployment pins](../../../deploy/temporal/compose.temporal.yaml)
- [n8n deployment currently using `latest`](../../../deploy/docker/n8n/compose.yaml) and [Proffer workflow activation contract](../../../deploy/docker/n8n/workflows/proffer/README.md)
- [Authentik source deployment](../../../deploy/authentik.yaml) and [Workbench ingress source](../../../deploy/workbench.yaml)
- [PostgreSQL/pg_duckdb deployment](../../../deploy/data-pg.yaml), [Neo4j deployment](../../../deploy/data-neo4j.yaml), [SurrealDB deployment](../../../deploy/compose.data-surreal.yaml), and [Weaviate deployment](../../../deploy/data-weaviate.yaml)

### Official current research

- React: [18.3/19 upgrade guide](https://react.dev/blog/2024/04/25/react-19-upgrade-guide), [React 18.3.1 registry record](https://registry.npmjs.org/react/18.3.1), and [current React versions](https://react.dev/versions)
- Glide Data Grid: [package versions and license](https://www.npmjs.com/package/%40glideapps/glide-data-grid?activeTab=versions), [project repository](https://github.com/glideapps/glide-data-grid), and [open compatibility issues](https://github.com/glideapps/glide-data-grid/issues). Upstream still identifies alpha24 as prerelease; the local compatibility artifact is the evidence for the exact bounded exception.
- TanStack Router: [official type-safety guide](https://tanstack.com/router/latest/docs/guide/type-safety) and [package record](https://www.npmjs.com/package/%40tanstack/react-router)
- Vite: [Vite 8 release and Node requirements](https://vite.dev/blog/announcing-vite8)
- Tauri: [frontend integration guidance](https://v2.tauri.app/start/frontend/) and [current Rust API documentation](https://docs.rs/tauri/latest/tauri/struct.Config.html)
- Storybook: [React/Vite framework documentation](https://storybook.js.org/docs/get-started/frameworks/react-vite/?renderer=react) and [Storybook 10 migration guide](https://storybook.js.org/docs/releases/migration-guide)
- FastAPI: [PyPI release record](https://pypi.org/project/fastapi/); Uvicorn: [PyPI release record](https://pypi.org/project/uvicorn/); Pydantic: [PyPI release record](https://pypi.org/project/pydantic/); HTTPX: [PyPI release record](https://pypi.org/project/httpx/)
- Temporal: [Go SDK development guide](https://docs.temporal.io/develop/go), [Go SDK releases](https://github.com/temporalio/sdk-go/releases), [Server releases](https://github.com/temporalio/temporal/releases), [UI Server releases](https://github.com/temporalio/ui-server/releases), and [Docker image/`auto-setup` guidance](https://github.com/temporalio/docker-builds)
- n8n: [official releases](https://github.com/n8n-io/n8n/releases), [release notes](https://github.com/n8n-io/n8n-docs/blob/main/docs/changelog/release-notes.md), and [Sustainable Use License](https://github.com/n8n-io/n8n/blob/master/LICENSE.md)
- Authentik: [2026.8 release notes](https://docs.goauthentik.io/releases/2026.8/), [version support policy](https://docs.goauthentik.io/security/policy/), [forward-auth modes](https://docs.goauthentik.io/add-secure-apps/providers/proxy/forward_auth/), and [official Traefik configuration](https://docs.goauthentik.io/add-secure-apps/providers/proxy/server_traefik/)
- Traefik: [router rules and priority](https://doc.traefik.io/traefik/reference/routing-configuration/http/routing/rules-and-priority/)
- Coolify: [4.1.x changelog](https://coolify.io/changelog), [Traefik proxy overview](https://coolify.io/docs/core/networking/proxy/traefik/overview), [Docker Compose deployments](https://coolify.io/docs/applications/builds/docker-compose), [domains](https://coolify.io/docs/core/networking/domains), and [automatic deployments/watch paths](https://coolify.io/docs/applications/deployments/automatic-deployments)
- PostgreSQL: [PostgreSQL 18 documentation](https://www.postgresql.org/docs/18/) and [release notes](https://www.postgresql.org/docs/release/)
