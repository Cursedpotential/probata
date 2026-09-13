// Byline: Codex · GPT-5 · 2026-08-29 (production intake anatomy contract)
// Byline: Codex · GPT-5.6-Sol · 2026-08-30 (opaque UIW preview contract)
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const intake = readFileSync(
  new URL("../src/components/intake/unified-intake.tsx", import.meta.url),
  "utf8",
);
const parserPanel = readFileSync(new URL("../src/components/intake/parser-selection-panel.tsx", import.meta.url), "utf8");
const explorer = readFileSync(new URL("../src/components/intake/source-explorer.tsx", import.meta.url), "utf8");
const client = readFileSync(new URL("../src/lib/api-client.ts", import.meta.url), "utf8");

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
  assert.match(parserPanel, /aria-label="Parser selection"/);
});

test("local intake selects supported document extensions and declares them truthfully", () => {
  assert.match(intake, /const LOCAL_FILE_ACCEPT = "\.xml,\.json,\.txt,\.csv,\.md,\.html,\.htm,\.pdf,\.docx,\.zip,\.tar,\.tgz,\.gz,\.7z,\.rar,\.png,\.jpg,\.jpeg,\.gif,\.tif,\.tiff,\.bmp";/);
  assert.match(intake, /<input accept=\{LOCAL_FILE_ACCEPT\} className="sr-only" type="file"/);
  assert.match(intake, /md: "markdown"/);
  assert.match(intake, /json: "message_export_json"/);
  assert.match(intake, /docx: "docx"/);
  assert.match(intake, /html: "html"/);
  assert.match(intake, /htm: "html"/);
  assert.match(intake, /pdf: "pdf"/);
  assert.match(intake, /zip: "archive"/);
  assert.match(intake, /"7z": "archive"/);
  assert.match(intake, /\/\\\.\(md\|json\|html\?\|txt\|csv\|xml\)\$\/i/);
});

test("remote sources are immediately previewed and hashed without claiming custody", () => {
  assert.match(intake, /inspectProfferSource\(selected, mode, activeRootId\)/);
  assert.match(intake, /Reading and hashing/);
  assert.match(intake, /Preview checksum/);
  assert.match(intake, /Read-only preview identity/);
  assert.match(intake, /context workflow verifies the source bytes independently before processing/);
  assert.match(intake, /iframe[\s\S]*inspection\.preview_url/);
  assert.doesNotMatch(intake, /Remote content is fetched and sealed/);
});

test("parser decision is content-signature-derived, explicit, bounded, and durably read back", () => {
  assert.match(parserPanel, /preview && preview\.phase !== "awaiting_handler_selection"/);
  assert.match(parserPanel, /preview\.phase/);
  assert.match(parserPanel, /preview\.parser/);
  assert.match(parserPanel, /preview\.parser\.parser_id/);
  assert.match(parserPanel, /preview\.parser\.parser_version/);
  assert.match(parserPanel, /preview\.parser\.config_digest/);
  assert.match(parserPanel, /preview\.reason/);
  assert.match(parserPanel, /Durable workflow read-back/);
  assert.match(parserPanel, /preview\.handler_recommendation_ref/);
  assert.match(parserPanel, /preview\.detected_format_ref/);
  assert.match(parserPanel, /preview\.recommended_handler/);
  assert.match(parserPanel, /preview\.alternative_handlers/);
  assert.match(parserPanel, /candidate\.execution_path === "duckdb"/);
  assert.match(parserPanel, /Explicit selection required/);
  assert.match(parserPanel, /receipt\.receipt_type === "parser_selection"/);
  assert.match(parserPanel, /filename preflight, but it is not authoritative/);
  assert.match(intake, /parser_options_ref: "pending-handler-selection\/v1"/);
  assert.doesNotMatch(intake, /inspection\.parser_selection/);
  assert.match(intake, /state\.phase === "awaiting_handler_selection"/);
  assert.match(intake, /decideProfferHandler\(run\.preview_handle, mode/);
  assert.match(parserPanel, /Record selection and continue/);
  assert.match(parserPanel, /becomes durable only after the authenticated server records the decision/);
  assert.match(intake, /recommendation_ref: preview\.handler_recommendation_ref/);
  assert.match(intake, /compatibility_ref: selectedParser\.compatibility_ref/);
  assert.match(intake, /execution_path: selectedParser\.execution_path/);
  assert.match(client, /\/handler-selection\?/);
  assert.match(intake, /data-testid="open-proffer-preview"[\s\S]*href=\{`\/evidence\/preview\?mode=/);
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
