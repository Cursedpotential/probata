// Byline: Codex · GPT-5.6-Sol · 2026-08-30
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const intake = readFileSync(new URL("../src/components/intake/unified-intake.tsx", import.meta.url), "utf8");
const client = readFileSync(new URL("../src/lib/api-client.ts", import.meta.url), "utf8");
const types = readFileSync(new URL("../src/lib/shared/types.ts", import.meta.url), "utf8");

test("repair review is an explicit gate inside the unified intake window", () => {
  assert.match(intake, /phase === "repair_review" && preview\?\.repair_assessment/);
  assert.match(intake, /aria-label="Repair review gate"/);
  assert.match(intake, /assessment_ref/);
  assert.match(intake, /source_version_ref/);
  assert.match(intake, /Override repair and use the original source/);
  assert.match(intake, /Confirm and continue/);
  assert.match(intake, /repairChoice === "original"/);
});

test("clean assessments continue without an operator decision", () => {
  assert.match(intake, /state\.phase === "awaiting_repair_decision" && state\.repair_assessment\?\.review_required/);
  assert.doesNotMatch(intake, /terminalPreviewPhases[^\n]+repair_approved/);
  assert.match(intake, /ignoredTerminalPhases\.has\(lastState\.phase\)/);
});

test("repair decision is typed, correlated, and carries no browser-authored tool payload", () => {
  assert.match(client, /\/api\/proffer\/previews\/\$\{encodeURIComponent\(previewHandle\)\}\/repair-decision/);
  assert.match(types, /interface ProfferRepairDecisionRequest/);
  assert.match(intake, /approved: true,\s*apply_repair: false/);
  assert.match(intake, /decision\.preview_handle !== run\.preview_handle/);
  assert.match(intake, /waitForPreview\(run\.preview_handle/);
  assert.doesNotMatch(intake, /tool_payload|tool_id|executeRepairTool|runAutomaticRepairAssessment|JSON\.stringify/);
});

test("the UI does not invent a derived repair choice absent from the assessment contract", () => {
  const assessment = types.slice(types.indexOf("interface ProfferRepairAssessmentView"), types.indexOf("interface ProfferRepairDecisionRequest"));
  assert.doesNotMatch(assessment, /tool|payload|option|choice/);
  assert.match(intake, /No compatible derived-repair action was supplied by the workflow/);
  assert.match(intake, /application will not invent or silently run one/);
});
