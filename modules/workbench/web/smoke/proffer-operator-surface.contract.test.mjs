// Byline: Codex · GPT-6 · 2026-09-13 (Context Review workspace contract)
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const surface = readFileSync(new URL("../src/components/sbv/proffer-operator-preview.tsx", import.meta.url), "utf8");
const review = readFileSync(new URL("../src/components/sbv/proffer-preview-client.tsx", import.meta.url), "utf8");
const viewer = readFileSync(new URL("../src/components/sbv/platform-message-viewer.tsx", import.meta.url), "utf8");
const flow = readFileSync(new URL("../src/components/intake/context-flow-rail.tsx", import.meta.url), "utf8");
const navigation = readFileSync(new URL("../src/surfaces/primary/navigation.ts", import.meta.url), "utf8");
const sidebar = readFileSync(new URL("../src/components/layout/app-sidebar.tsx", import.meta.url), "utf8");
const desk = readFileSync(new URL("../src/surfaces/primary/evidence-operations-desk.tsx", import.meta.url), "utf8");
const tools = readFileSync(new URL("../src/components/tools/atomic-tools.tsx", import.meta.url), "utf8");
const client = readFileSync(new URL("../src/lib/api-client.ts", import.meta.url), "utf8");

test("the primary surface consistently names this workspace Review", () => {
  assert.match(navigation, /title: "Review"/);
  assert.match(navigation, /pageTitle: "Review extracted context"/);
  assert.match(sidebar, /Intake and Review/);
  assert.match(desk, /Open Review workspace/);
  assert.match(review, /Context Review workspace/);
  assert.match(flow, /All Review views unlock/);
});

test("direct Review entry uses a resource list instead of manual opaque-handle plumbing", () => {
  assert.match(review, /Sources and proposals/);
  assert.match(review, /listProfferProposalResources\(mode, \{ limit: 50 \}/);
  assert.match(review, /selectResource\(response\.items\[0\]\.preview_handle\)/);
  assert.match(review, /query\.get\("resource"\)/);
  assert.match(review, /query\.get\("preview_handle"\)/);
  assert.match(review, /query\.get\("attempt"\)/);
  assert.match(review, /Start intake/);
  assert.match(review, /Committed readback/);
  assert.match(review, /resource\.representation_detail/);
  assert.match(client, /\/api\/proffer\/proposal-resources/);
  assert.match(client, /context_review_resources/);
  assert.doesNotMatch(review, /draftHandle|proffer-preview-handle|Attach to an import|Enter the preview handle/);
});

test("the Review workspace exposes every required operator view", () => {
  for (const label of [
    "Overview",
    "Source records",
    "Chunks",
    "Entities",
    "Relationships",
    "Graph",
    "Attachments / files",
    "Lineage",
    "Warnings",
    "Attempts / runs",
  ]) assert.match(surface, new RegExp(`label: "${label.replaceAll("/", "\\/")}"`));
  assert.match(surface, /aria-label="Context review views"/);
  assert.match(surface, /useState<ReviewTab>\("overview"\)/);
});

test("available source records, chunks, files, and lineage use returned API data", () => {
  assert.match(client, /getProfferPreviewContent/);
  assert.match(client, /record_cursor/);
  assert.match(client, /chunk_cursor/);
  assert.match(surface, /content\.records\.map/);
  assert.match(surface, /content\.chunks\.map/);
  assert.match(surface, /content\.attachments\.map/);
  assert.match(surface, /record\.source_locator_ref/);
  assert.match(surface, /content\.chunk_generation\?\.generation_ref/);
  assert.match(surface, /piece\.byte_start/);
  assert.match(surface, /piece\.sha256/);
});

test("pending entities, relationships, and graph stay truthful and do not fabricate rows", () => {
  assert.match(surface, /Entity rows will appear here when the backend returns/);
  assert.match(surface, /Relationship rows will appear here when the backend returns/);
  assert.match(surface, /This view needs a read API that returns attempt-bound nodes, relationships, and write receipts/);
  assert.doesNotMatch(surface, /demoEntit|sampleNode|mockRelationship|fakeGraph/i);
});

test("Neo4j is primary and SurrealDB is explicitly later and manual", () => {
  assert.match(surface, /Neo4j is the primary approved graph destination/);
  assert.match(surface, /SurrealDB projection is separate/);
  assert.match(surface, /later, manual projection/);
  assert.match(surface, /is not run or implied by this Context review/);
});

test("attempt history limitations, warnings, events, and receipts remain visible", () => {
  assert.match(surface, /attempts_complete/);
  assert.match(surface, /Compare attempts and edit-template rerun remain unavailable/);
  assert.match(surface, /snapshot\.unavailable_controls/);
  assert.match(surface, /snapshot\.stages\.filter/);
  assert.match(surface, /Replayable events/);
  assert.match(surface, /Context receipts/);
  assert.match(surface, /layer\.layer === "n8n"/);
});

test("operator controls are server projected and approval is attempt-bound", () => {
  assert.match(surface, /snapshot\.valid_actions/);
  assert.match(surface, /Approve this attempt/);
  assert.match(surface, /disabled=\{actionPending \|\| !decisionReady\}/);
  assert.match(review, /normalized records, source locators, and every required completed receipt/);
  assert.doesNotMatch(surface, /retryStage\(|cancelOperation\(|resumeCheckpoint\(|applyRepair\(/);
});

test("later-review annotations stay reversible and preserve actor and attempt provenance", () => {
  assert.match(surface, /Potential future use/);
  assert.match(surface, /reversible Context annotation/);
  assert.match(surface, /Mark for later review/);
  assert.match(surface, /item\.attempt_id/);
  assert.match(surface, /item\.actor_username/);
  assert.match(review, /createProfferPotentialPromotionFlag/);
  assert.match(review, /listProfferPotentialPromotionFlags/);
});

test("DuckDB tools remain governed under the Go-managed extraction overview", () => {
  assert.match(surface, /Go-managed structured extraction/);
  assert.match(surface, /DuckDB is the primary ELT path/);
  assert.match(surface, /requiredToolTerm="duckdb"/);
  assert.match(tools, /requiredToolTerm/);
  assert.doesNotMatch(surface, /textarea[^>]+sql|executeSql|runSql/i);
});

test("visible Review copy stays within Context scope", () => {
  const userFacingSources = [surface, review, viewer, flow, navigation, sidebar, desk];
  for (const source of userFacingSources) {
    assert.doesNotMatch(source, />[^<{]*(?:evidence|custody)[^<{]*</i);
  }
});
