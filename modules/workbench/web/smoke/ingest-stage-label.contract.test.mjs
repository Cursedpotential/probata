// Byline: Codex · GPT-5 · 2026-09-12
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import ts from "typescript";

const base = new URL("../src/components/runs/", import.meta.url);
const read = (name) => readFileSync(new URL(name, base), "utf8");
const compiled = ts.transpileModule(read("stage-label.ts"), {
  compilerOptions: { module: ts.ModuleKind.ES2022, target: ts.ScriptTarget.ES2022 },
}).outputText;
const { ingestStageLabel } = await import(`data:text/javascript;base64,${Buffer.from(compiled).toString("base64")}`);

test("legacy first-stage display is context verification without rewriting wire records", () => {
  const historic = Object.freeze({ name: "custody", status: "failed" });
  assert.equal(ingestStageLabel(historic.name), "Raw-source verification");
  assert.equal(historic.name, "custody");
  assert.equal(historic.status, "failed");
  assert.equal(ingestStageLabel("raw_source_verification"), "Raw-source verification");
  assert.equal(ingestStageLabel("parse"), "parse");
  assert.equal(ingestStageLabel("fingerprint_source"), "fingerprint source");
});

test("every historical ingest stage heading uses the shared display translation", () => {
  for (const file of ["stage-rail.tsx", "stage-drawer.tsx", "run-detail-dialog.tsx", "run-report-panel.tsx"]) {
    assert.match(read(file), /ingestStageLabel\(/, file);
  }
  assert.doesNotMatch(read("stage-rail.tsx"), /FALLBACK_STAGE_NAMES = \["custody"/);
  assert.doesNotMatch(read("run-detail-dialog.tsx"), />Custody tier</);
});

test("ingest drawer does not invoke evidence-chain verification or claim a new check", () => {
  assert.doesNotMatch(read("stage-drawer.tsx"), /<VerifyPanel|from .*verify-panel/);
  assert.match(read("stage-drawer.tsx"), /not a custody seal or a new verification result/);
  assert.match(read("stage-output-view.tsx"), /Source fingerprint \(SHA-256\)/);
});
