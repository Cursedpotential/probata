// Byline: Codex · GPT-5 · 2026-08-29.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const intake = readFileSync(new URL("../src/components/intake/unified-intake.tsx", import.meta.url), "utf8");
const client = readFileSync(new URL("../src/lib/api-client.ts", import.meta.url), "utf8");
const types = readFileSync(new URL("../src/lib/shared/types.ts", import.meta.url), "utf8");
const explorer = readFileSync(new URL("../src/components/intake/source-explorer.tsx", import.meta.url), "utf8");

test("OpenList-backed R2 browser is the default and local upload is secondary", () => {
  assert.match(explorer, /Default ingestion point/);
  assert.match(explorer, /OpenList-backed R2 locations/);
  assert.match(intake, /Or add a source from this device/);
  assert.ok(intake.indexOf("SourceExplorer") < intake.indexOf("Choose local file"));
});

test("browser API selects only server-allowlisted roots and never accepts bucket input", () => {
  assert.match(client, /\/api\/proffer\/sources/);
  assert.match(client, /rootId\?: string/);
  assert.doesNotMatch(client, /listProfferSources[\s\S]{0,600}(provider|bucket)\??:/);
  assert.match(types, /source: "casebible-raw" \| "casebible-sorted" \| "casebible-quarantine"/);
  assert.match(types, /available_roots: ProfferSourceRoot\[\]/);
});

test("backing-source search and type filtering are server-scoped, not current-page filtering", () => {
  assert.match(client, /query\.set\("filter_scope", "root"\)/);
  assert.match(client, /query\.append\("file_type", fileType\)/);
  assert.match(client, /response\.filter_scope !== "root"/);
  assert.match(explorer, /manualFiltering: true/);
  assert.match(explorer, /aria-label="Source directory tree and files"/);
  assert.doesNotMatch(intake, /visibleObjects|visiblePrefixes/);
  assert.match(explorer, /search_complete/);
  assert.match(explorer, /scan_limit_reached/);
});

test("remote listings carry server-authored source identity and inspection never constructs it", () => {
  const remoteType = types.slice(types.indexOf("interface ProfferSourceObject"), types.indexOf("interface ProfferSourcePrefix"));
  assert.doesNotMatch(remoteType, /sha256/i);
  assert.match(remoteType, /source_ref: string/);
  assert.match(remoteType, /archive_format\?: string \| null/);
  assert.match(client, /inspectProfferSource/);
  assert.match(client, /\/api\/proffer\/source-inspection/);
  assert.match(types, /digest_status: "preview_only"/);
  assert.doesNotMatch(intake, /r2:\/\/casebible-sorted/);
  assert.match(intake, /remote\?\.source_ref/);
  assert.match(explorer, /activeRootRecord\.root_ref/);
});
