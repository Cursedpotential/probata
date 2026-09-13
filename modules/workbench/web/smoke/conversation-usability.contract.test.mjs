// Byline: Codex · GPT-5 · 2026-08-18 (conversation usability contract)
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const dialog = readFileSync(new URL("../src/components/runs/new-run-dialog.tsx", import.meta.url), "utf8");
const drawer = readFileSync(new URL("../src/components/records/record-detail-drawer.tsx", import.meta.url), "utf8");
const picker = readFileSync(new URL("../src/components/records/entity-picker.tsx", import.meta.url), "utf8");
const client = readFileSync(new URL("../src/lib/api-client.ts", import.meta.url), "utf8");
const intake = readFileSync(new URL("../src/components/intake/unified-intake.tsx", import.meta.url), "utf8");

test("new-run collects both conversation source contracts", () => {
  assert.match(dialog, /<UnifiedIntake/);
  assert.doesNotMatch(dialog, /createRunFromFile|createRunFromStaged|custodyTier/);
  assert.match(intake, /value="first_party"/);
  assert.match(intake, /value="acquired_third_party"/);
  assert.match(intake, /acquired_at/);
  assert.match(client, /createProfferSourceContext/);
  assert.match(client, /source_principal/);
});

test("third-party approval uses governed entities and no reviewer text field", () => {
  assert.match(drawer, /<EntityPicker/);
  assert.doesNotMatch(drawer, /Reviewer identity \(required\)/);
  assert.match(drawer, /authenticated owner \(set by the server\)/);
  assert.match(picker, /listGovernedEntities/);
  assert.match(picker, /createGovernedEntity/);
});
