# Workbench Storybook and two-surface refactor

> _Byline: Codex · GPT-5.6-Sol · 2026-08-30._
> _Naming: written before the 2026-09-05 rename (D-137..D-141); see docs/NAMING.md for the old->new glossary._

STATUS: BROWSER VITE IMPLEMENTED / DEPLOYED / LIVE VERIFIED

## Owner direction captured

- The Workbench remains two related product surfaces, expressed as separate source directories:
  - `workbench/web/src/surfaces/primary/` — the everyday **Evidence Operations Desk**.
  - `workbench/web/src/surfaces/advanced/` — the **Modular Service Cockpit**.
- Shared visual and behavioral contracts live under `workbench/web/src/platform-ui/` rather than
  inside either surface.
- Storybook is the shared component workshop and visual contract. It is not a canonical data,
  workflow, or authority layer.
- This Platform Workbench is browser-first for continuous preview. A Tauri desktop host may be
  added after the browser product is complete; the separate Case Bible local-first sorter lane is
  not copied or modified here.
- The separate agent's Storybook/Glide document sorting work belongs to the primary surface when
  its implementation is ready for integration. This slice deliberately does not duplicate it.
- `react-calendar-timeline` and `vis-timeline` remain available as development-only visualization
  options. There is no artificial bake-off and no ruling that one must replace the other.
- Timesketch moves to the advanced surface. It remains a standalone governed projection and is not
  replaced by a lightweight primary-surface timeline.

## Implemented locally

- Converted the production browser build from Next.js static export to Vite 8 while retaining the
  existing React application and FastAPI/API/storage boundaries.
- Added code-split TanStack Router routes for every current Workbench destination and a FastAPI SPA
  fallback for direct browser deep links.
- Reserved `/api`, `/health`, `/docs`, `/redoc`, and `/openapi.json` namespaces from SPA fallback;
  unknown API paths and missing asset paths remain real 404 responses.
- Replaced every browser `process.env.NEXT_PUBLIC_*` access with typed `import.meta.env.VITE_*`
  access. Same-origin remains the production default.
- Replaced the broken root shell with the live Evidence Operations Desk. It reads the canonical
  fixed case, health, staged sources, open flags, and durable runs from real APIs and exposes only
  the complete Desk → Intake → Preview primary path.
- Added Storybook 10.5 on the React/Vite adapter with Docs, accessibility, approved light/dark
  palettes, both surface boundaries, and an actual operational-desk story backed by bounded API
  fixtures.
- Kept advanced navigation empty and fail-closed. No Timesketch, graph, map, workflow, or legal
  destination is exposed before its live-proof gate passes.
- Updated the subtree README and agent instructions to the Vite/browser contract. The superseded
  Next README was preserved under `to_be_deleted/workbench-next-shell-20260830/`; only the owner
  deletes it.
- Added one command for the complete 19-test browser/contract smoke suite and migrated the browser
  journey itself from the stale ignored `out/*.html` tree to the real `dist/index.html` SPA.

## Timesketch sharing boundary

The local fork audit found that Timesketch's default frontend is Vue 2/Vuetify 2, with an optional
Vue 3/Vuetify 3 frontend, while Workbench is React. Therefore:

- share generated CSS variables/design-token JSON, vocabulary, and launch/deep-link schemas;
- do not import Workbench React components into the Timesketch fork;
- reserve web components for small framework-neutral leaf controls if later justified;
- do not make an iframe the target architecture;
- enter the advanced Timesketch surface through a future short-lived, scoped server-side launch
  exchange, not by exposing an internal sketch identifier as the Workbench contract.

No launch exchange or Timesketch UI route was implemented in this slice.

## Verification

| Check | Result |
|---|---|
| `npm run build` | PASS — Vite 8.2.2, TypeScript, 2,072 modules, code-split `dist/` bundle |
| `npm run build-storybook` | PASS — actual operational desk plus palette and two-surface boundaries |
| `npm run lint` | PASS with zero errors and 14 warnings; 12 Fast Refresh warnings plus two pre-existing UIW ref-cleanup warnings |
| `npm audit --audit-level=high` | PASS — zero vulnerabilities |
| `git diff --check -- workbench/web` | PASS |
| `npm run smoke` contracts | PASS — 19/19 against the real Vite output and current opaque UIW contract |
| Focused FastAPI Vite/static suite | PASS — 4/4, including deep-link and reserved-API negative cases |
| Full Workbench API suite | 232 PASS / 1 pre-existing structure-policy failure: `app/service/uiw.py` is 301 lines and `app/types/case_management.py` is 315 lines |
| Root integration marker | BLOCKED during collection by the pre-existing missing tracked file `sql/0045_context_fingerprint_semantics.sql` referenced by `tests/test_0048_context_fingerprint_uiw_repair.py` |
| Local browser render | PASS — real Desk DOM rendered, navigation present, zero console errors; isolated preview correctly showed unavailable API state because it was not attached to the production backend |
| Exact production container build | PASS — Coolify built the release Dockerfile with Node 22 and copied the Vite `dist/` bundle into the FastAPI image |

## Production deployment receipt

The prior Storybook-foundation deployment was commit `2952250`, Coolify deployment
`vis21loq504r6spk6krpwyg9`. It proved only the former Next shell and is not acceptance evidence for
this Vite/browser release.

- Browser/Vite implementation commit: `22e488be6f43a982ac301cc82628bba6f7db4ddd`.
- Final production release commit: `9437f4a586b1740227033f1354d6e392bc6ff5fb`.
- Coolify resource: `knowledge-workbench` / `xjbuo6drbwjfby75lalk8bk7`.
- Final deployment: `cqalhd223bkghikhr6qet1ao`, status `finished`; the application reported
  `running:healthy` after replacement.
- Exact builder proof: `node:22-alpine`, clean `npm ci`, Vite 8.2.2, 2,072 modules transformed,
  and the production `dist/` bundle copied into the FastAPI image. The earlier deployment
  `moib81wylgarn9uy359j76wj` was superseded after its Node 20 builder exposed package-engine
  warnings; the final Node 22 build emitted none.
- Stable probes: `/`, `/intake`, and `/evidence/preview` returned HTTP 200 with title
  `The Platform — Evidence & Legal Operations`; `/health` returned HTTP 200 with
  `status=ok`, `lancedb=true`, and `object_store=true`; `/api/missing` returned a JSON HTTP 404
  rather than SPA HTML.
- Live browser proof: the root rendered the Evidence Operations Desk for `Primary matter` and
  `Primary proceeding`, with one knowledge partition, zero staged sources, zero open flags, two
  recent durable runs, and `API healthy`. Intake loaded real objects from `Case Bible Sorted`.
  Preview rendered its bounded opaque-handle boundary. The final route walk recorded zero browser
  console errors, and a full-page production screenshot was captured from the live root.
- Stable browser URL: `https://workbench.tilapia-skilift.ts.net/`.

## Still open

- Migrate data-heavy tables to Glide Data Grid one complete workflow at a time. This release does
  not claim that migration, and it does not duplicate the other agent's Case Bible sorter.
- Quarantine retained `next.config.ts` and `next-env.d.ts` in a separately scoped cleanup now that
  Vite production parity is live-proven; no destructive cleanup is authorized.
- Select a lightweight timeline engine per concrete visualization. Both retained engines may be
  used when their interaction models serve different jobs.
- Add the Timesketch advanced launch/deep-link contract only after its deployment, authority, and
  PostgreSQL round-trip gates pass.
