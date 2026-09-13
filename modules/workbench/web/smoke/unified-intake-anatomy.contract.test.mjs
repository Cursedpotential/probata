// Byline: Codex · GPT-5 · 2026-08-29 (production intake anatomy contract)
// Byline: Codex · GPT-5.6-Sol · 2026-08-30 (opaque UIW preview contract)
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const intake = readFileSync(
  new URL("../src/components/intake/unified-intake.tsx", import.meta.url),
  "utf8",
);

function between(source, startMarker, endMarker) {
  const start = source.indexOf(startMarker);
  const end = source.indexOf(endMarker, start + startMarker.length);
  assert.notEqual(start, -1, `missing start marker: ${startMarker}`);
  assert.notEqual(end, -1, `missing end marker: ${endMarker}`);
  assert.ok(end > start, `expected ${endMarker} after ${startMarker}`);
  return source.slice(start, end);
}

test("source inspection exposes the Source preview, Metadata, and Parser tabs", () => {
  assert.match(intake, /type PreviewTab = "source" \| "metadata" \| "parser";/);
  assert.match(intake, /\(\["source", "metadata", "parser"\] as const\)\.map/);
  assert.match(intake, /tab === "source" \? "Source preview" : tab/);
  assert.match(intake, /aria-label="Source preview"/);
  assert.match(intake, /aria-label="Source metadata"/);
  assert.match(intake, /aria-label="Parser selection"/);
});

test("local intake selects supported document extensions and declares them truthfully", () => {
  assert.match(intake, /const LOCAL_FILE_ACCEPT = "\.md,\.json,\.docx,\.html,\.htm,\.pdf,\.png,\.jpg,\.jpeg,\.gif,\.webp,\.avif,\.tif,\.tiff,\.bmp";/);
  assert.match(intake, /<input accept=\{LOCAL_FILE_ACCEPT\} className="sr-only" type="file"/);
  assert.match(intake, /md: "markdown"/);
  assert.match(intake, /json: "message_export_json"/);
  assert.match(intake, /docx: "docx"/);
  assert.match(intake, /html: "html"/);
  assert.match(intake, /htm: "html"/);
  assert.match(intake, /pdf: "pdf"/);
  for (const extension of ["png", "jpg", "jpeg", "gif", "webp", "avif", "tif", "tiff", "bmp"]) {
    assert.match(intake, new RegExp(`${extension}: "image"`));
  }
  assert.match(intake, /\/\\\.\(md\|json\|html\?\|txt\|csv\|xml\)\$\/i/);
});

test("local images receive a bounded object URL preview that is always revoked", () => {
  assert.match(intake, /URL\.createObjectURL\(selected\)/);
  assert.match(intake, /URL\.revokeObjectURL\(localImagePreviewUrlRef\.current\)/);
  assert.match(intake, /replaceLocalImagePreview\(selected\)/);
  assert.match(intake, /replaceLocalImagePreview\(null\)/);
  assert.match(intake, /file && localImagePreviewUrl/);
  assert.match(intake, /src=\{localImagePreviewUrl\}/);
  assert.match(intake, /alt=\{`Local preview of \$\{file\.name\}`\}/);
  assert.match(intake, /onError=\{\(\) => setLocalImagePreviewError\(true\)\}/);
  assert.match(intake, /This browser could not render the selected image format inline/);
});

test("remote sources are immediately previewed and hashed without claiming custody", () => {
  assert.match(intake, /inspectProfferSource\(selected\)/);
  assert.match(intake, /Reading and hashing/);
  assert.match(intake, /Preview checksum/);
  assert.match(intake, /Read-only preview identity/);
  assert.match(intake, /Acquisition recomputes and receipts the custody checksum before promotion/);
  assert.match(intake, /iframe[\s\S]*inspection\.preview_url/);
  assert.doesNotMatch(intake, /Remote content is fetched and sealed/);
});

test("parser details are rendered only from backend workflow preview state", () => {
  const parserPanel = between(
    intake,
    '{previewTab === "parser"',
    '<div className="flex flex-col gap-3 border-t',
  );

  assert.match(parserPanel, /\{preview \? \(/);
  assert.match(parserPanel, /preview\.phase/);
  assert.match(parserPanel, /preview\.parser/);
  assert.match(parserPanel, /preview\.parser\.parser_id/);
  assert.match(parserPanel, /preview\.parser\.parser_version/);
  assert.match(parserPanel, /preview\.parser\.config_digest/);
  assert.match(parserPanel, /preview\.reason/);
  assert.match(parserPanel, /Temporal read-back/);
  assert.match(parserPanel, /inspection\.parser_preflight\.route_label/);
  assert.match(parserPanel, /Filename extension; the durable workflow records the final parser identity and version/);
  assert.doesNotMatch(parserPanel, /setParser|parserOptions/);
});

test("execution receipt uses the opaque preview identity and preserves the context boundary", () => {
  const receipt = between(
    intake,
    'aria-label="Intake execution receipt"',
    "</main>",
  );

  assert.match(receipt, /Server-returned preview identity and latest durable workflow phase\./);
  assert.match(receipt, /\{run\.preview_handle\}/);
  assert.match(receipt, /\{preview\?\.phase/);
  assert.doesNotMatch(receipt, /run\.workflow_id|run\.run_id/);
  assert.match(receipt, /Authority boundary/);
  assert.match(receipt, /Context only; not evidence/);
});

test("intake exposes no model or provider selector and no Timeline or Legal destination", () => {
  assert.doesNotMatch(intake, /model(_id|Id|Selector)?\b|setModel|Model selector/i);
  assert.doesNotMatch(
    intake,
    /provider(_id|Id|Selector)\b|setProvider|Provider selector|<label[^>]*>[^<]*Provider/i,
  );
  assert.doesNotMatch(intake, />\s*(Timeline|Legal)\s*</);
});
