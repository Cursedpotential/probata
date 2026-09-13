// Byline: Codex · GPT-5 · 2026-09-12 (TEST/REAL fail-closed UI isolation and deep-link hydration contract)
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

function source(path) {
  return readFileSync(new URL(path, import.meta.url), "utf8");
}

const context = source("../src/lib/fixed-case-context.tsx");
const intake = source("../src/components/intake/unified-intake.tsx");
const preview = source("../src/components/sbv/proffer-preview-client.tsx");
const client = source("../src/lib/api-client.ts");
const selector = source("../src/components/intake/matter-mode-selector.tsx");
const header = source("../src/components/layout/header.tsx");
const matterWorkspace = source("../src/components/matters/matter-workspace.tsx");
const types = source("../src/lib/shared/types.ts");

test("TEST and REAL are explicit global modes", () => {
  assert.match(types, /type MatterMode = "TEST" \| "REAL"/);
  assert.match(selector, /const MODES: MatterMode\[\] = \["TEST", "REAL"\]/);
  assert.match(selector, /\{mode\} mode active/);
  assert.match(header, /<MatterModeSelector compact/);
});

test("mode switching clears matter scope and remounts every import or preview cache", () => {
  assert.match(context, /setMatter\(null\)/);
  assert.match(context, /setLoading\(true\)/);
  assert.match(intake, /<UnifiedIntakeMode key=\{mode\} mode=\{mode\}/);
  assert.match(preview, /<ModeScopedPreviewClient key=\{mode\} mode=\{mode\}/);
  assert.match(matterWorkspace, /<ModeScopedMatterWorkspace key=\{mode\} mode=\{mode\}/);
  assert.match(matterWorkspace, /getMatter\(matterId, mode\)/);
  assert.match(matterWorkspace, /listMatters\(50, 0, mode\)/);
  assert.match(preview, /key=\{`\$\{mode\}:\$\{previewHandle\}`\}/);
});

test("all import and preview boundaries carry and verify the active mode", () => {
  for (const phrase of [
    "Staged acquisition did not confirm TEST/REAL mode",
    "source browser did not confirm",
    "source inspection did not confirm",
    "source-context receipt did not confirm",
    "started preview did not confirm",
    "preview did not confirm",
    "preview messages did not confirm",
    "decision response did not confirm",
  ]) assert.match(client, new RegExp(phrase));
  assert.match(client, /new URLSearchParams\(\{ mode \}\)/);
  assert.match(preview, /event\.matter_mode !== mode/);
  assert.match(intake, /event\.matter_mode !== mode/);
});

test("a URL preview handle is accepted only for its matching mode", () => {
  assert.match(preview, /query\.get\("mode"\) === mode/);
  assert.match(preview, /url\.searchParams\.set\("mode", mode\)/);
});

test("a direct REAL preview deep link hydrates mode before resolving its handle", () => {
  assert.match(context, /function initialMatterMode\(\): MatterMode/);
  assert.match(context, /requestedMode === "REAL" \? "REAL" : "TEST"/);
  assert.match(context, /useState<MatterMode>\(initialMatterMode\)/);
  assert.doesNotMatch(context, /useState<MatterMode>\("TEST"\)/);

  const handleInitializer = preview.indexOf("useState(() => initialHandle(mode))");
  const activeHandleInitializer = preview.indexOf("useRef(initialUrlHandle)");
  const locationCanonicalizer = preview.indexOf("window.history.replaceState");
  assert.ok(handleInitializer >= 0, "the URL handle must initialize synchronously for the validated mode");
  assert.ok(activeHandleInitializer > handleInitializer, "the active correlation ref must start with the URL handle");
  assert.ok(locationCanonicalizer > activeHandleInitializer, "URL canonicalization must run after initial correlation state exists");
  assert.doesNotMatch(preview, /setDraftHandle\(handle\);\s*activateHandle\(handle\)/);
});
