// Byline: Codex · GPT-5 · 2026-09-12 (context-only live checkpoint rail contract)
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

function source(path) {
  return readFileSync(new URL(path, import.meta.url), "utf8");
}

const checkpoints = source("../src/lib/proffer-context-checkpoints.ts");
const rail = source("../src/components/intake/context-flow-rail.tsx");
const intake = source("../src/components/intake/unified-intake.tsx");
const preview = source("../src/components/sbv/proffer-preview-client.tsx");
const types = source("../src/lib/shared/types.ts");

test("the import source surface has one ordered six-checkpoint context rail", () => {
  const orderedLabels = [
    "Raw source verification",
    "Parser selection",
    "Parser execution",
    "Normalization",
    "Storage",
    "Completeness",
  ];
  let previous = -1;
  for (const label of orderedLabels) {
    const index = checkpoints.indexOf(`label: "${label}"`);
    assert.ok(index > previous, `${label} must appear once in the requested sequence`);
    previous = index;
  }
  assert.match(rail, /aria-label="Context processing checkpoints"/);
  assert.match(intake, /<ContextFlowRail/);
  assert.doesNotMatch(intake, /aria-label="Intake progress"/);
});

test("checkpoint copy is literal and the full preview remains gated", () => {
  assert.match(checkpoints, /Waiting for this checkpoint\./);
  assert.match(checkpoints, /Stopped here\. The full preview remains locked\./);
  assert.match(intake, /profferContextFlowComplete\(preview\?\.receipts, preview\?\.checkpoints\)/);
  assert.match(intake, /phase === "review" && run && contextFlowComplete/);
  assert.match(intake, /Full preview locked/);
  assert.match(checkpoints, /durableReceiptComplete && liveCheckpointComplete/);
});

test("the UI receipt contract uses raw source verification and never labels it custody", () => {
  assert.match(types, /receipt_type: "raw_source_verification"/);
  assert.match(preview, /PROFFER_CONTEXT_CHECKPOINTS\.map/);
  assert.match(preview, /checkpointLabel\(receipt\.receipt_type\)/);
  assert.doesNotMatch(checkpoints, /custody/i);
  assert.doesNotMatch(rail, /custody/i);
  assert.doesNotMatch(preview, /custody/i);
});

test("live checkpoint status consumes partial snapshots and the event stream refreshes them", () => {
  assert.match(intake, /createProfferPreviewEventSource\(run\.preview_handle, mode\)/);
  assert.match(intake, /addEventListener\("proffer\.preview"/);
  assert.match(types, /interface ProfferPreviewCheckpoint/);
  assert.match(types, /checkpoints\?: ProfferPreviewCheckpoint\[\] \| null/);
  assert.match(checkpoints, /checkpoint\.checkpoint/);
  assert.doesNotMatch(types, /receipt_type\?: ProfferPreviewReceipt/);
});
