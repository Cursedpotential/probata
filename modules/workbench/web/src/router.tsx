// Byline: Codex · GPT-5.6-Sol · 2026-08-30
import {
  createRootRoute,
  createRoute,
  createRouter,
  lazyRouteComponent,
} from "@tanstack/react-router";

import { AppShell } from "@/app-shell";
import HomePage from "@/app/page";

const rootRoute = createRootRoute({
  component: AppShell,
  notFoundComponent: () => (
    <section className="mx-auto grid min-h-full max-w-3xl place-content-center px-6 py-16 text-center">
      <p className="platform-kicker">Unknown destination</p>
      <h1 className="mt-3 text-3xl font-semibold tracking-tight">This Workbench route does not exist.</h1>
      <a className="mt-6 text-sm font-semibold text-primary underline underline-offset-4" href="/">
        Return to the Context Intake Desk
      </a>
    </section>
  ),
});

function applicationRoute(path: string, importer: () => Promise<{ default: React.ComponentType }>) {
  return createRoute({
    getParentRoute: () => rootRoute,
    path,
    component: lazyRouteComponent(importer),
  });
}

const routeTree = rootRoute.addChildren([
  createRoute({ getParentRoute: () => rootRoute, path: "/", component: HomePage }),
  applicationRoute("classification-test", () => import("@/app/classification-test/page")),
  applicationRoute("copilot", () => import("@/app/copilot/page")),
  applicationRoute("evidence-queue", () => import("@/app/evidence-queue/page")),
  applicationRoute("review", () => import("@/app/evidence/preview/page")),
  // Preserve old deep links while Review becomes the canonical destination.
  applicationRoute("evidence/preview", () => import("@/app/evidence/preview/page")),
  applicationRoute("intake", () => import("@/app/intake/page")),
  applicationRoute("knowledge", () => import("@/app/knowledge/page")),
  applicationRoute("matter", () => import("@/app/matter/page")),
  applicationRoute("records", () => import("@/app/records/page")),
  applicationRoute("repairs", () => import("@/app/repairs/page")),
  applicationRoute("runs", () => import("@/app/runs/page")),
  applicationRoute("schemas", () => import("@/app/schemas/page")),
  applicationRoute("surreal", () => import("@/app/surreal/page")),
  applicationRoute("tools", () => import("@/app/tools/page")),
]);

export const router = createRouter({
  routeTree,
  defaultPreload: "intent",
  scrollRestoration: true,
});

declare module "@tanstack/react-router" {
  interface Register {
    router: typeof router;
  }
}
