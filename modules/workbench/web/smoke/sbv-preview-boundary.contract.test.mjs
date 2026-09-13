// Byline: Codex · GPT-5.6 · 2026-08-29
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const preview = readFileSync(new URL("../src/components/sbv/proffer-preview-client.tsx", import.meta.url), "utf8");
const operatorPreview = readFileSync(new URL("../src/components/sbv/proffer-operator-preview.tsx", import.meta.url), "utf8");
const viewer = readFileSync(new URL("../src/components/sbv/platform-message-viewer.tsx", import.meta.url), "utf8");
const page = readFileSync(new URL("../src/app/evidence/preview/page.tsx", import.meta.url), "utf8");
const client = readFileSync(new URL("../src/lib/api-client.ts", import.meta.url), "utf8");
const intake = readFileSync(new URL("../src/components/intake/unified-intake.tsx", import.meta.url), "utf8");

test("SBV preview is native to the Workbench shell and platform contracts", () => {
  assert.match(page, /ProfferPreviewClient/);
  assert.match(preview, /getProfferPreview/);
  assert.match(preview, /decideProffer/);
  assert.match(preview, /getProfferPreviewMessages/);
  assert.match(preview, /getProfferPreviewContent/);
  assert.match(preview, /createProfferPreviewEventSource/);
  assert.match(viewer, /PostgreSQL remains canonical/);
  assert.match(preview, /data-testid="back-to-proffer-intake" href="\/intake"/);
  assert.doesNotMatch(preview, /kimi|moonshot|href="https?:\/\//i);
});

test("SBV preview does not revive legacy storage, auth, or ingest APIs", () => {
  const source = `${preview}\n${operatorPreview}\n${viewer}`;
  assert.doesNotMatch(source, /DB_PATH_PREFIX|VITE_API_URL/i);
  assert.doesNotMatch(source, /\/api\/(auth|upload|conversations|messages|imports|settings)/);
  assert.doesNotMatch(source, /localhost:8085|platform-tools:8085/);
});

test("Proffer preview never reuses workflow or run identifiers at legacy boundaries", () => {
  const source = `${preview}\n${viewer}\n${client}`;
  assert.doesNotMatch(preview, /workflow_id|run_id|listRecords|RunEventsPanel|decider\s*:|owner\s*:/);
  assert.match(source, /preview_handle/);
  assert.match(client, /\/api\/proffer\/previews\//);
  assert.doesNotMatch(preview, /\/api\/runs|\/api\/records/);
});

test("decisions are centralized behind correlated generic-record provenance gates", () => {
  assert.doesNotMatch(intake, /\bdecideProffer\b|Approve and continue|Reject preview/);
  assert.match(intake, /Review messages and decide/);
  assert.match(preview, /result\.preview_handle !== handle/);
  assert.match(preview, /page\.preview_handle !== handle/);
  assert.match(preview, /generationRef/);
  assert.match(preview, /AbortController/);
  assert.match(preview, /decisionEligible/);
  assert.match(preview, /result\.preview_handle !== handle/);
  assert.match(preview, /provenanceLoaded/);
  assert.match(preview, /receiptsComplete/);
  assert.match(preview, /record\.source_locator_ref/);
  assert.match(preview, /contentError/);
});

test("the viewer renders modeled correlation, provenance, participant, attachment, and receipt fields", () => {
  const source = `${preview}\n${operatorPreview}\n${viewer}`;
  for (const field of [
    "raw_generation_id",
    "normalized_generation_id",
    "receipt_ref",
    "recorded_at",
    "canonical_address",
    "source_locator_ref",
    "attachment_id",
    "sha256",
    "byte_length",
    "participant_ids",
  ]) assert.match(source, new RegExp(field));
});
