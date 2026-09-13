// Byline: Codex · GPT-5.6-Sol · 2026-09-12 (Proffer operation visibility contract)
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const table = readFileSync(
  new URL("../src/components/intake/proffer-operations-table.tsx", import.meta.url),
  "utf8",
);
const page = readFileSync(new URL("../src/app/intake/page.tsx", import.meta.url), "utf8");
const client = readFileSync(new URL("../src/lib/api-client.ts", import.meta.url), "utf8");
const types = readFileSync(new URL("../src/lib/shared/types.ts", import.meta.url), "utf8");
const intake = readFileSync(
  new URL("../src/components/intake/unified-intake.tsx", import.meta.url),
  "utf8",
);

test("the Intake page uses a dedicated Proffer ledger instead of relabeling legacy runs", () => {
  assert.match(page, /<ProfferOperationsTable \/>/);
  assert.doesNotMatch(page, /RunsTable/);
  assert.match(page, /This existing file list is not a Proffer operation history/);
  assert.match(table, /They are separate from legacy Workbench runs/);
  assert.doesNotMatch(table, /listRuns|\/api\/runs/);
});

test("operation list and detail use only the engine-backed BFF contract", () => {
  assert.match(client, /apiFetch<ProfferOperationListResponse>\(`\/api\/proffer\/operations\$\{suffix\}`/);
  assert.match(client, /apiFetch<ProfferOperationDetail>/);
  assert.match(client, /`\/api\/proffer\/operations\/\$\{encodeURIComponent\(previewHandle\)\}`/);
  for (const lifecycle of [
    "running",
    "awaiting_repair_decision",
    "awaiting_preview_decision",
    "completed",
    "failed",
    "unavailable",
  ]) {
    assert.match(types, new RegExp(`\\| "${lifecycle}"|= "${lifecycle}"`));
  }
  assert.match(types, /service: "proffer"/);
  assert.match(types, /active_stages: string\[\]/);
  assert.match(types, /stages: ProfferOperationStage\[\]/);
});

test("status source service and reopened handle survive refresh in the URL", () => {
  assert.match(table, /searchParams\.get\("operation_status"\)/);
  assert.match(table, /searchParams\.get\("operation_source"\)/);
  assert.match(table, /searchParams\.get\("operation_service"\)/);
  assert.match(table, /searchParams\.get\("preview_handle"\)/);
  assert.match(table, /navigate\.replace\(`\/intake\$\{query/);
  assert.match(table, /Reopen/);
  assert.match(table, /Reopened by preview handle/);
  assert.match(table, /getProfferOperation\(selectedHandle/);
});

test("the ledger distinguishes loading error empty and filtered-empty states", () => {
  assert.match(table, /Loading Proffer operations/);
  assert.match(table, /Operation list could not be refreshed/);
  assert.match(table, /No Proffer operations found/);
  assert.match(table, /No loaded operation matches the source and service filters/);
  assert.match(table, /Status is filtered by the engine; source and service refine the rows loaded here/);
  assert.match(table, /Cancel and retry controls are not exposed here/);
});

test("selected source tabs remain mounted while the intake phase changes", () => {
  assert.match(intake, /const selectedSource = file \?\? remote/);
  assert.match(intake, /\{\(\["source", "metadata", "parser"\] as const\)\.map/);
  assert.doesNotMatch(intake, /phase === "starting"[^\n]*\?[^\n]*Source preview/);
});
