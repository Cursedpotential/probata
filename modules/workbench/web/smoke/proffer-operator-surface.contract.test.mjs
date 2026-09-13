// Byline: Codex · GPT-6 · 2026-09-13 (truthful Proffer operator surface contract)
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const surface = readFileSync(new URL("../src/components/sbv/proffer-operator-preview.tsx", import.meta.url), "utf8");
const preview = readFileSync(new URL("../src/components/sbv/proffer-preview-client.tsx", import.meta.url), "utf8");
const tools = readFileSync(new URL("../src/components/tools/atomic-tools.tsx", import.meta.url), "utf8");
const client = readFileSync(new URL("../src/lib/api-client.ts", import.meta.url), "utf8");
const types = readFileSync(new URL("../src/lib/shared/types.ts", import.meta.url), "utf8");

test("the Proffer preview exposes the complete operator tab contract", () => {
  for (const label of [
    "Source",
    "Records",
    "Chunks / Context",
    "Entities",
    "Graph candidates",
    "Workflow / receipts / errors",
    "DuckDB workspace",
  ]) assert.match(surface, new RegExp(label.replaceAll("/", "\\/")));
  assert.match(preview, /ProfferOperatorPreview/);
  assert.match(preview, /getProfferOperatorSnapshot/);
  assert.match(client, /\/operator\?\$\{query\.toString\(\)\}/);
});

test("package integrity and later promotion remain visibly separate from context intake", () => {
  for (const field of [
    "original_fingerprint",
    "package_identity",
    "package_hash",
    "context_status",
    "evidence_eligibility",
    "promotion_prerequisites",
    "promotion_rehash",
    "custody_state",
  ]) assert.match(`${surface}\n${types}`, new RegExp(field));
  assert.match(surface, /Context acceptance state/);
  assert.match(surface, /Later promotion prerequisites/);
  assert.match(surface, /Promotion rehash \/ re-extraction/);
});

test("source repair is a visible pre-routing lane and cannot overwrite the original", () => {
  assert.match(surface, /Source repair and preprocessing/);
  assert.match(surface, /before signature routing and handler selection/);
  assert.match(surface, /not proof that the source is damaged/);
  assert.match(surface, /Affected members \/ pages/);
  assert.match(surface, /Engine \/ profile \/ version \/ hash/);
  assert.match(surface, /snapshot\.repair_state\.reentry_rule/);
});

test("D-158 storage routing is visible and does not force non-messaging content into PostgreSQL", () => {
  assert.match(surface, /D-158 context storage destination/);
  assert.match(surface, /Messaging \/ non-messaging classification/);
  assert.match(surface, /snapshot\.storage_state\.rule/);
  assert.match(types, /storage_state:/);
});

test("TEST and REAL identities stay in every preview and restart link", () => {
  assert.match(surface, /\{snapshot\.matter_mode\} operation destination/);
  assert.match(surface, /Development test matter/);
  assert.match(surface, /matter_id/);
  assert.match(surface, /court_case_id/);
  assert.match(surface, /\/intake\?mode=\$\{snapshot\.matter_mode\}/);
  assert.match(preview, /key=\{`\$\{mode\}:\$\{previewHandle\}`\}/);
  assert.match(preview, /getProfferOperatorSnapshot\(handle, mode/);
});

test("only server-projected actions render and unsupported recovery stays explicit", () => {
  assert.match(surface, /snapshot\.valid_actions/);
  assert.match(surface, /snapshot\.unavailable_controls/);
  assert.match(surface, /Controls omitted because the backend contract is missing/);
  assert.doesNotMatch(surface, /retryStage\(|cancelOperation\(|resumeCheckpoint\(|applyRepair\(/);
  assert.match(surface, /disabled=\{actionPending \|\| !decisionReady\}/);
  assert.match(preview, /actionPending=\{decisionPending\}/);
});

test("DuckDB workspace is catalog-bounded and remains under Go and Temporal control", () => {
  assert.match(surface, /Go-managed primary structured extraction/);
  assert.match(surface, /Go owns selection, bounded references, Temporal correlation, receipt validation, retries, and repair decisions/);
  assert.match(surface, /requiredToolTerm="duckdb"/);
  assert.match(tools, /requiredToolTerm/);
  assert.match(tools, /`\$\{serverLabel\} \$\{tool\.name\} \$\{tool\.description \?\? ""\}`\.toLowerCase\(\)\.includes\(requiredToolTerm\.toLowerCase\(\)\)/);
  assert.doesNotMatch(surface, /textarea[^>]+sql|executeSql|runSql/i);
});

test("n8n visibility is explicit without inventing execution or activation identity", () => {
  assert.match(surface, /layer\.layer === "n8n"/);
  assert.match(surface, /Version \/ activation truth/);
  assert.match(surface, /run_or_execution_id/);
  assert.doesNotMatch(surface, /n8n\.io|\/executions\//);
});

test("generic records and exact chunks use the durable content projection", () => {
  assert.match(client, /getProfferPreviewContent/);
  assert.match(client, /record_cursor/);
  assert.match(client, /chunk_cursor/);
  assert.match(preview, /content\.records\.every/);
  assert.match(surface, /exact persisted normalized_payload objects/);
  assert.match(surface, /Exact pre-publication chunks/);
  assert.match(surface, /piece\.byte_start/);
  assert.match(surface, /piece\.sha256/);
  assert.match(surface, /does not publish to Weaviate, promote evidence, or establish custody/);
  assert.match(surface, /Compare attempts and edit-template rerun remain unavailable/);
});
