// Byline: Codex · GPT-5 · 2026-08-15 (Matter promotion, custody, readiness, and review smoke)
// Byline: Codex · GPT-5 · 2026-08-18 (third-party projection detail coverage)
// Byline: Codex · GPT-5.6-Sol · 2026-08-30 (Vite SPA harness and fixed-case shell)
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { createServer } from "node:http";
import { mkdtemp, readFile, stat } from "node:fs/promises";
import { extname, join, normalize, resolve } from "node:path";
import test from "node:test";

const MATTER_A = "11111111-1111-4111-8111-111111111111";
const MATTER_B = "11111111-1111-4111-8111-222222222222";
const CASE_PRIMARY = "22222222-2222-4222-8222-222222222222";
const CASE_SECONDARY = "22222222-2222-4222-8222-333333333333";
const RECORD_A = "33333333-3333-4333-8333-333333333333";
const ARTIFACT_A = "44444444-4444-4444-8444-444444444444";
const HASH_A = "55555555-5555-4555-8555-555555555555";
const SOURCE_A = "66666666-6666-4666-8666-666666666666";
const EVIDENCE_A = "77777777-7777-4777-8777-777777777777";
const PROMOTION_A = "88888888-8888-4888-8888-888888888888";
const TASK_A = "99999999-9999-4999-8999-999999999999";
const DECISION_A = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const SHA_A = "ab".repeat(32);
const NOW = "2026-08-15T12:00:00Z";
const OUT = resolve("dist");

function json(response, statusCode, body) {
  const data = Buffer.from(JSON.stringify(body));
  response.writeHead(statusCode, {
    "content-type": "application/json",
    "content-length": data.length,
  });
  response.end(data);
}

async function bodyJson(request) {
  const chunks = [];
  for await (const chunk of request) chunks.push(chunk);
  return JSON.parse(Buffer.concat(chunks).toString("utf8") || "{}");
}

function evidenceItem(overrides = {}) {
  return {
    id: EVIDENCE_A,
    matter_id: MATTER_A,
    court_case_id: CASE_PRIMARY,
    title: "Custody-backed message",
    description: null,
    quote: "Exact normalized record text",
    evidence_type: "communication",
    evidence_date: null,
    normalized_record_id: RECORD_A,
    evidence_hash_id: HASH_A,
    source_id: SOURCE_A,
    file_node_id: null,
    source_run_id: null,
    review_status: "unreviewed",
    hitl_required: true,
    safe_for_legal_use: false,
    is_authenticated: false,
    created_by: "owner",
    created_at: NOW,
    ...overrides,
  };
}

function evidenceDetail() {
  return {
    item: evidenceItem(),
    promotion: {
      id: PROMOTION_A,
      partition_key: "primary",
      knowledge_lane: "evidence",
      retrieval_item_ref: "knowledge-hit-a",
      content_ref: "content-a",
      chunk_ref: "chunk-a",
      source_pointer: {
        matter_id: MATTER_A,
        court_case_id: CASE_PRIMARY,
        partition_key: "primary",
        lane: "evidence",
        normalized_record_id: RECORD_A,
        evidence_hash_id: HASH_A,
        source_id: SOURCE_A,
        sha256: SHA_A,
        conversation_id: "thread-a",
        retrieval_ref: "knowledge-hit-a",
        content_ref: "content-a",
        chunk_ref: "chunk-a",
      },
      promoted_by: "owner",
      promoted_at: NOW,
    },
    record: {
      id: RECORD_A,
      record_type: "message",
      source: "sms",
      conversation_id: "thread-a",
      role: "sender",
      content: "Exact normalized record text",
      occurred_at: NOW,
      source_kind: "unclassified",
      projection_kind: "authored_normalized",
      source_available_from: null,
      third_party_conversation: null,
      realization_events: [],
      acquired_at: NOW,
      ingested_at: NOW,
      realized_at: null,
      disclosure_tier: "contemporaneous",
      review_status: "unreviewed",
      case_id: "primary",
    },
    custody_hash: {
      id: HASH_A,
      source_ref: "fixture-export.json",
      algo: "sha256",
      digest_sha256: SHA_A,
      level: "H1",
      canon_version: "h1-rawbytes-v1",
      hashed_at: NOW,
      computed_by: "custody.go",
    },
    source: {
      id: SOURCE_A,
      sha256: SHA_A,
      byte_size: 1024,
      mime_type: "application/json",
      original_filename: "fixture-export.json",
      source_type: "chat_export",
      source_platform: "fixture",
      acquisition_source: "manual_export",
      acquisition_method: "manual_export",
      acquired_at_utc: NOW,
      acquired_certainty: "exact",
      provenance_tier: "r2_canonical",
      hash_canon_version: "h1-rawbytes-v1",
      custody_status: "verified",
      review_status: "reviewed",
      verified_by: "owner",
      verified_at: NOW,
    },
    file_node: null,
  };
}

function courtReadiness() {
  return {
    evidence_item_id: EVIDENCE_A,
    matter_id: MATTER_A,
    readiness_passed: false,
    blockers: ["CONTENT_REVIEW_REQUIRED", "CUSTODY_NOT_VERIFIED"],
    gates: {
      content_review: { approved: false, decision_id: null },
      provenance: { exact: true },
      custody: {
        h1_valid: true,
        event_chain_valid: true,
        verified_event_present: true,
        source_status: "pending",
        source_reviewed: false,
        verified_by: null,
        verified_at: null,
      },
      authentication: { authenticated: true, method: "hash_chain_of_custody" },
      confidence: { value: 0.8, tier: "medium", export_band: true },
      assertion: { not_hypothesis: true },
      redaction: { privacy_sensitivity: "none", source_privacy_sensitivity: "none", status: "none", clear_for_export: true },
      sensitivity: { evidence_tier: "restricted", source_tier: "restricted", sealed: false },
      court_export: { view_member: true },
    },
  };
}

function matterDetail() {
  return {
    id: MATTER_A,
    matter_mode: "TEST",
    title: "Matter Alpha",
    description: "Fixture Matter",
    status: "active",
    partition_keys: ["primary"],
    created_at: NOW,
    updated_at: NOW,
    court_cases: [
      {
        id: CASE_SECONDARY,
        matter_id: MATTER_A,
        caption: "Secondary proceeding",
        status: "active",
        is_primary: false,
        created_at: NOW,
        updated_at: NOW,
      },
      {
        id: CASE_PRIMARY,
        matter_id: MATTER_A,
        caption: "Primary proceeding",
        status: "active",
        is_primary: true,
        created_at: NOW,
        updated_at: NOW,
      },
    ],
  };
}

function createFixtureServer({ advancedEvidenceAvailable = true, newRunFixture = false } = {}) {
  const requests = [];
  const failures = [];
  let handlerDecisions = 0;
  const server = createServer(async (request, response) => {
    try {
      const url = new URL(request.url, "http://fixture.local");
      let body = null;
      if (newRunFixture && url.pathname === "/api/upload") {
        for await (const chunk of request) { void chunk; }
      } else if (["POST", "PUT", "PATCH"].includes(request.method)) body = await bodyJson(request);
      requests.push({ method: request.method, path: url.pathname, search: url.search, body });

      if (newRunFixture && url.pathname === "/api/upload") return json(response, 200, { id: SHA_A, name: "sms.xml", size: 42 });

      if (newRunFixture && url.pathname === "/api/files") {
        return json(response, 200, [{ id: SHA_A, name: "sms-real-route-test.xml", size: 42,
          mime: "application/xml", detected_type: "sms", status: "staged", r2_key: `workbench/staging/${SHA_A}/sms.xml` }]);
      }
      if (newRunFixture && url.pathname === "/api/proffer/sources") {
        return json(response, 200, { matter_mode: "TEST", active_root_id: "r2-sorted", objects: [], prefixes: [],
          available_roots: [], available_file_types: [], selected_file_types: [], page_size: 100, is_truncated: false });
      }
      if (newRunFixture && url.pathname === `/api/proffer/staged/${SHA_A}/acquisition`) {
        assert.equal(url.searchParams.get("mode"), "TEST");
        return json(response, 201, { acquisition_ref: `r2://nexus/workbench/staging/${SHA_A}/sms.xml`,
          sha256: SHA_A, byte_length: 42, matter_mode: "TEST" });
      }
      if (newRunFixture && url.pathname === "/api/proffer/source-contexts") {
        assert.equal(body.matter_id, MATTER_A);
        assert.equal(body.court_case_id, CASE_PRIMARY);
        assert.equal(body.assertions.source_class, "unknown");
        return json(response, 201, { source_context_ref: SOURCE_A, matter_mode: "TEST" });
      }
      if (newRunFixture && url.pathname === "/api/proffer/start") {
        assert.equal(body.source_ref, `r2://nexus/workbench/staging/${SHA_A}/sms.xml`);
        assert.equal(body.parser_options_ref, "pending-handler-selection/v1");
        assert.equal(body.source_context_ref, SOURCE_A);
        assert.equal(body.engine, undefined);
        assert.equal(body.custody_tier, undefined);
        return json(response, 201, { preview_handle: "new_run_preview_abcdefghijklmnopqrstuvwxyz", matter_mode: "TEST" });
      }
      if (newRunFixture && url.pathname === "/api/proffer/previews/new_run_preview_abcdefghijklmnopqrstuvwxyz") {
        if (handlerDecisions < 2) return json(response, 200, {
          preview_handle: "new_run_preview_abcdefghijklmnopqrstuvwxyz", matter_mode: "TEST",
          phase: "awaiting_handler_selection", detected_format: "smsbackuprestore_xml",
          detected_format_ref: "detected-ref", signature_ref: "signature-ref",
          handler_recommendation_ref: `recommendation-${handlerDecisions}`,
          recommended_handler: { handler_id: "duckdb_structured_elt", handler_version: "1.0.0", execution_path: "duckdb",
            compatibility_ref: `compatibility-${handlerDecisions}`, reason: handlerDecisions ? "Retry after second logged failure" : "Retry after logged automatic execution failure" },
          alternative_handlers: [], receipts: [], checkpoints: [],
        });
        return json(response, 200, { preview_handle: "new_run_preview_abcdefghijklmnopqrstuvwxyz", matter_mode: "TEST",
          phase: "failed", reason: "Fixture stop: execution is deliberately mocked", receipts: [], checkpoints: [] });
      }
      if (newRunFixture && url.pathname === "/api/proffer/previews/new_run_preview_abcdefghijklmnopqrstuvwxyz/handler-selection") {
        assert.equal(body.recommendation_ref, `recommendation-${handlerDecisions}`);
        assert.equal(body.compatibility_ref, `compatibility-${handlerDecisions}`);
        handlerDecisions += 1;
        return json(response, 200, { preview_handle: "new_run_preview_abcdefghijklmnopqrstuvwxyz", matter_mode: "TEST", decision_ref: `decision-${handlerDecisions}` });
      }
      if (newRunFixture && url.pathname.endsWith("/events")) {
        response.writeHead(200, { "content-type": "text/event-stream" });
        return response.end(": fixture\n\n");
      }
      if (newRunFixture && url.pathname === "/api/runs") {
        assert.equal(request.method, "GET", "NewRun must never POST the legacy route");
        return json(response, 200, []);
      }

      if (request.method === "GET" && url.pathname === "/api/matters") {
        assert.equal(url.searchParams.get("limit"), "50");
        assert.equal(url.searchParams.get("offset"), "0");
        assert.equal(url.searchParams.get("mode"), "TEST");
        return json(response, 200, { data: [matterDetail()], total: 1, limit: 50, offset: 0 });
      }
      if (request.method === "GET" && url.pathname === `/api/matters/${MATTER_A}`) {
        assert.equal(url.searchParams.get("mode"), "TEST");
        return json(response, 200, matterDetail());
      }
      if (request.method === "GET" && url.pathname === "/api/case-management/capabilities") {
        return json(response, 200, {
          registry_available: true,
          advanced_evidence_available: advancedEvidenceAvailable,
          advanced_evidence_reason: advancedEvidenceAvailable
            ? ""
            : "Advanced Matter evidence operations are unavailable until the platform-native evidence substrate is implemented and activated; legacy ai and Case Bible stores are not fallback sources.",
        });
      }
      if (request.method === "GET" && url.pathname === "/api/health/deps") {
        return json(response, 200, {
          pg: { status: "ok" },
          milvus: { status: "ok" },
          lancedb: { status: "ok" },
          object_store: { status: "ok" },
          checked_at: NOW,
        });
      }
      if (request.method === "GET" && url.pathname === "/api/flags") {
        return json(response, 200, []);
      }
      if (request.method === "GET" && url.pathname === "/api/runs") {
        return json(response, 200, []);
      }
      if (request.method === "GET" && url.pathname === `/api/matters/${MATTER_A}/evidence-items`) {
        return json(response, 200, { data: [], total: 0, limit: 50, offset: 0 });
      }
      if (request.method === "GET" && url.pathname === "/api/knowledge/search") {
        assert.equal(url.searchParams.get("case_id"), "primary");
        assert.equal(url.searchParams.get("lane"), "evidence");
        assert.equal(url.searchParams.get("limit"), "20");
        return json(response, 200, {
          data: [{
            id: "knowledge-hit-a",
            name: "Custody-backed message",
            content: "Ranked chunk context",
            content_id: "content-a",
            content_origin: "fixture-export.json",
            reranking_score: 0.98,
            meta_data: {
              knowledge_lane: "evidence",
              case_id: "primary",
              artifact_id: ARTIFACT_A,
              sha256: SHA_A,
              chunk_ref: "chunk-a",
            },
          }],
          meta: { total_count: 1 },
        });
      }
      if (request.method === "POST" && url.pathname === `/api/matters/${MATTER_A}/knowledge/resolve`) {
        assert.deepEqual(
          {
            lane: body.lane,
            partition_key: body.partition_key,
            artifact_id: body.artifact_id,
            sha256: body.sha256,
            retrieval_ref: body.retrieval_ref,
            content_ref: body.content_ref,
            chunk_ref: body.chunk_ref,
          },
          {
            lane: "evidence",
            partition_key: "primary",
            artifact_id: ARTIFACT_A,
            sha256: SHA_A,
            retrieval_ref: "knowledge-hit-a",
            content_ref: "content-a",
            chunk_ref: "chunk-a",
          },
        );
        return json(response, 200, {
          matter_id: MATTER_A,
          candidates: [{
            normalized_record_id: RECORD_A,
            artifact_id: ARTIFACT_A,
            evidence_hash_id: HASH_A,
            source_id: SOURCE_A,
            file_node_id: null,
            source_run_id: null,
            sha256: SHA_A,
            record_type: "message",
            role: "sender",
            content: "Exact normalized record text",
            occurred_at: NOW,
            disclosure_tier: "contemporaneous",
            review_status: "unreviewed",
          }],
        });
      }
      if (request.method === "POST" && url.pathname === `/api/matters/${MATTER_A}/evidence-items`) {
        assert.equal(body.court_case_id, CASE_PRIMARY);
        assert.equal(body.source.partition_key, "primary");
        assert.equal(body.source.normalized_record_id, RECORD_A);
        assert.equal(body.source.artifact_id, ARTIFACT_A);
        assert.equal(body.source.sha256, SHA_A);
        return json(response, 201, { item: evidenceItem(), promotion_id: PROMOTION_A, created: true });
      }
      if (request.method === "GET" && url.pathname === `/api/matters/${MATTER_A}/evidence-items/${EVIDENCE_A}`) {
        return json(response, 200, evidenceDetail());
      }
      if (request.method === "GET" && url.pathname === `/api/matters/${MATTER_A}/evidence-items/${EVIDENCE_A}/source-content`) {
        return json(response, 200, {
          content: "Original source message text",
          mime_type: "application/json",
          source_pointer: evidenceDetail().promotion.source_pointer,
          provenance: { h1: HASH_A, h2: "fixture-h2", h3: "fixture-h3" },
          h1: HASH_A,
          h2: "fixture-h2",
          h3: "fixture-h3",
        });
      }
      if (request.method === "GET" && url.pathname === `/api/matters/${MATTER_A}/evidence-items/${EVIDENCE_A}/conversation-context`) {
        assert.equal(url.searchParams.get("before"), "25");
        assert.equal(url.searchParams.get("after"), "25");
        return json(response, 200, {
          before: 25,
          after: 25,
          total: 1,
          messages: [{ id: RECORD_A, content: "Exact normalized record text", sender: "sender", recipients: ["recipient"], occurred_at: NOW, source_pointer: { normalized_record_id: RECORD_A } }],
        });
      }
      if (request.method === "GET" && url.pathname === `/api/matters/${MATTER_A}/evidence-items/${EVIDENCE_A}/court-readiness`) {
        return json(response, 200, courtReadiness());
      }
      if (request.method === "POST" && url.pathname === `/api/matters/${MATTER_A}/evidence-items/${EVIDENCE_A}/reviews`) {
        assert.equal(body.decision, "approved");
        assert.equal(body.rationale, "Exact record and custody pointer reviewed.");
        return json(response, 200, {
          item: evidenceItem({ review_status: "approved", hitl_required: false }),
          task_id: TASK_A,
          decision_id: DECISION_A,
          decision: "approved",
          court_readiness: "review_passed",
        });
      }
      if (request.method === "GET" && url.pathname === `/api/matters/${MATTER_A}/evidence-items/${EVIDENCE_A}/reviews`) {
        return json(response, 200, {
          data: [{
            decision_id: DECISION_A,
            task_id: TASK_A,
            evidence_item_id: EVIDENCE_A,
            reviewer: "owner",
            decision: "approved",
            court_readiness: "review_passed",
            rationale: "Exact record and custody pointer reviewed.",
            decided_at: NOW,
          }],
          total: 1,
        });
      }

      if (url.pathname.startsWith("/api/")) {
        failures.push(`unexpected API request: ${request.method} ${url.pathname}${url.search}`);
        return json(response, 500, { detail: "MATTER-B-CANARY" });
      }

      const relative = normalize(decodeURIComponent(url.pathname)).replace(/^([/\\])+/, "");
      const requestedFile = join(OUT, relative || "index.html");
      const requestedStat = await stat(requestedFile).catch(() => null);
      const file = requestedStat?.isFile() ? requestedFile : join(OUT, "index.html");
      if (!requestedFile.startsWith(OUT) || !(await stat(file).catch(() => null))?.isFile()) {
        response.writeHead(404);
        return response.end("not found");
      }
      const types = {
        ".html": "text/html; charset=utf-8",
        ".js": "text/javascript; charset=utf-8",
        ".css": "text/css; charset=utf-8",
        ".svg": "image/svg+xml",
        ".ico": "image/x-icon",
        ".txt": "text/plain; charset=utf-8",
      };
      const data = await readFile(file);
      response.writeHead(200, { "content-type": types[extname(file)] || "application/octet-stream" });
      response.end(data);
    } catch (error) {
      failures.push(error.stack || String(error));
      json(response, 500, { detail: "fixture assertion failed" });
    }
  });
  return { server, requests, failures };
}

class CdpPipe {
  constructor(process) {
    this.process = process;
    this.nextId = 1;
    this.pending = new Map();
    this.events = [];
    this.buffer = Buffer.alloc(0);
    process.stdio[4].on("data", (chunk) => this.consume(chunk));
  }

  consume(chunk) {
    this.buffer = Buffer.concat([this.buffer, chunk]);
    let delimiter;
    while ((delimiter = this.buffer.indexOf(0)) !== -1) {
      const payload = this.buffer.subarray(0, delimiter).toString("utf8");
      this.buffer = this.buffer.subarray(delimiter + 1);
      if (!payload) continue;
      const message = JSON.parse(payload);
      if (message.id && this.pending.has(message.id)) {
        const { resolve: accept, reject, timer } = this.pending.get(message.id);
        this.pending.delete(message.id);
        clearTimeout(timer);
        if (message.error) reject(new Error(`${message.error.message} (${message.error.code})`));
        else accept(message.result || {});
      } else {
        this.events.push(message);
      }
    }
  }

  command(method, params = {}, sessionId) {
    const id = this.nextId++;
    return new Promise((accept, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error(`CDP timeout: ${method}`));
      }, 10_000);
      this.pending.set(id, { resolve: accept, reject, timer });
      this.process.stdio[3].write(`${JSON.stringify({ id, method, params, ...(sessionId ? { sessionId } : {}) })}\0`);
    });
  }
}

function browserPath() {
  const candidates = [
    process.env.SMOKE_BROWSER,
    "C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe",
    "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe",
  ].filter(Boolean);
  return candidates[0];
}

async function evaluate(cdp, sessionId, expression) {
  const result = await cdp.command(
    "Runtime.evaluate",
    { expression, awaitPromise: true, returnByValue: true },
    sessionId,
  );
  if (result.exceptionDetails) throw new Error(result.exceptionDetails.text || "browser evaluation failed");
  return result.result?.value;
}

async function waitFor(cdp, sessionId, expression, label, timeout = 10_000) {
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) {
    if (await evaluate(cdp, sessionId, expression)) return;
    await new Promise((accept) => setTimeout(accept, 75));
  }
  throw new Error(`Timed out waiting for ${label}`);
}

function clickText(text) {
  return `(() => { const node = [...document.querySelectorAll('button')].find((item) => item.textContent.trim().includes(${JSON.stringify(text)})); if (!node) return false; node.click(); return true; })()`;
}

function setValue(selector, value) {
  return `(() => { const node = document.querySelector(${JSON.stringify(selector)}); if (!node) return false; const setter = Object.getOwnPropertyDescriptor(node instanceof HTMLTextAreaElement ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype, 'value').set; setter.call(node, ${JSON.stringify(value)}); node.dispatchEvent(new Event('input', { bubbles: true })); node.dispatchEvent(new Event('change', { bubbles: true })); return true; })()`;
}

test("Matter-bound Knowledge promotes and reviews one exact custody record", { timeout: 60_000 }, async () => {
  await stat(join(OUT, "index.html"));
  const fixture = createFixtureServer();
  await new Promise((accept) => fixture.server.listen(0, "127.0.0.1", accept));
  const address = fixture.server.address();
  const profile = await mkdtemp(join(resolve("../..", "to_be_deleted"), "matter-flow-browser-profile-"));
  const browser = spawn(browserPath(), [
    "--headless=new",
    "--disable-gpu",
    "--no-first-run",
    "--no-default-browser-check",
    "--remote-debugging-pipe",
    `--user-data-dir=${profile}`,
    "about:blank",
  ], { stdio: ["ignore", "ignore", "pipe", "pipe", "pipe"] });
  const stderr = [];
  browser.stderr.on("data", (chunk) => stderr.push(chunk.toString("utf8")));
  const cdp = new CdpPipe(browser);

  try {
    const target = await cdp.command("Target.createTarget", {
      url: `http://127.0.0.1:${address.port}/matter?matter_id=${MATTER_A}`,
    });
    const attached = await cdp.command("Target.attachToTarget", { targetId: target.targetId, flatten: true });
    const session = attached.sessionId;
    await cdp.command("Page.enable", {}, session);
    await cdp.command("Runtime.enable", {}, session);

    await waitFor(cdp, session, `document.body?.innerText.includes('Matter Alpha')`, "Matter workspace");
    assert.equal(await evaluate(cdp, session, `document.querySelector('#knowledge-case') === null`), true);
    assert.equal(await evaluate(cdp, session, `document.querySelector('#knowledge-memory-tab') === null`), true);
    assert.equal(await evaluate(cdp, session, `document.querySelector('#knowledge-lane')?.value`), "evidence");

    assert.equal(await evaluate(cdp, session, setValue("#knowledge-query", "custody message")), true);
    assert.equal(await evaluate(cdp, session, clickText("Search")), true);
    await waitFor(cdp, session, `document.body.innerText.includes('Custody-backed message') && document.body.innerText.includes('Add to Matter')`, "Knowledge result");

    assert.equal(await evaluate(cdp, session, clickText("Add to Matter")), true);
    await waitFor(cdp, session, `document.body.innerText.includes('Choose one exact normalized record')`, "resolved record");
    assert.equal(await evaluate(cdp, session, `document.querySelector('#promotion-matter') === null`), true);
    assert.equal(await evaluate(cdp, session, `document.querySelector('#promotion-court-case') === null`), true);
    assert.equal(await evaluate(cdp, session, `document.body.innerText.includes('Primary proceeding') && document.body.innerText.includes('Partition primary')`), true);

    assert.equal(await evaluate(cdp, session, `(() => { const node = document.querySelector('input[name="normalized-record"][value="${RECORD_A}"]'); if (!node) return false; node.click(); return true; })()`), true);
    assert.equal(await evaluate(cdp, session, clickText("Create unsafe draft for review")), true);
    await waitFor(cdp, session, `document.body.innerText.includes('Evidence draft created')`, "unsafe draft result");
    assert.equal(await evaluate(cdp, session, `document.body.innerText.includes('HITL required') && document.body.innerText.includes('Unsafe for legal use')`), true);

    assert.equal(await evaluate(cdp, session, clickText("Close")), true);
    await waitFor(cdp, session, `document.body.innerText.includes('Review draft')`, "new Matter evidence row");

    // Evidence Operations Desk click-path contract: each tab must expose the
    // returned evidence body, not only metadata or an endpoint call.
    assert.equal(await evaluate(cdp, session, clickText("Inspect provenance")), true);
    await waitFor(cdp, session, `document.body.innerText.includes('Evidence provenance inspection') && document.body.innerText.includes('Exact normalized source record')`, "evidence operations desk");
    assert.equal(await evaluate(cdp, session, clickText("Original Source")), true);
    await waitFor(cdp, session, `document.body.innerText.includes('Original source message text')`, "original source content");
    assert.equal(await evaluate(cdp, session, clickText("Normalized Message")), true);
    assert.equal(await evaluate(cdp, session, `document.body.innerText.includes('Exact normalized record text')`), true);
    assert.equal(await evaluate(cdp, session, clickText("Conversation Context")), true);
    await waitFor(cdp, session, `document.body.innerText.includes('Conversation Context') && document.body.innerText.includes('Exact normalized record text')`, "conversation context message body");
    assert.equal(await evaluate(cdp, session, `document.body.innerText.includes('sender') && document.body.innerText.includes('recipient') && document.body.innerText.includes('8/15/2026')`), true);
    assert.equal(await evaluate(cdp, session, `document.querySelector('ol.max-h-96') !== null`), true);
    assert.equal(await evaluate(cdp, session, clickText("Close")), true);
    assert.equal(await evaluate(cdp, session, clickText("Court readiness")), true);
    await waitFor(cdp, session, `document.body.innerText.includes('Court-export readiness checklist')`, "court readiness checklist");
    assert.equal(await evaluate(cdp, session, `document.body.innerText.includes('database gate status only') && document.body.innerText.includes('does not determine admissibility')`), true);
    assert.equal(await evaluate(cdp, session, `document.body.innerText.includes('In database export view') && document.body.innerText.includes('Supplemental readiness checks blocked')`), true);
    assert.equal(await evaluate(cdp, session, `document.body.innerText.includes('Content review: Blocked') && document.body.innerText.includes('Custody: Blocked')`), true);
    assert.equal(await evaluate(cdp, session, `document.body.innerText.includes('Not in database export view')`), false);
    assert.equal(await evaluate(cdp, session, clickText("Close")), true);
    assert.equal(await evaluate(cdp, session, clickText("Review draft")), true);
    await waitFor(
      cdp,
      session,
      `document.querySelector('#review-decision-${EVIDENCE_A}') !== null && document.body.innerText.includes('Exact normalized source record') && document.body.innerText.includes('Linked realization history') && document.body.innerText.includes('H1 custody')`,
      "review provenance inspection",
    );
    await evaluate(cdp, session, `(() => { const node = document.querySelector('#review-decision-${EVIDENCE_A}'); node.value='approved'; node.dispatchEvent(new Event('change', {bubbles:true})); return true; })()`);
    assert.equal(await evaluate(cdp, session, setValue(`#review-rationale-${EVIDENCE_A}`, "Exact record and custody pointer reviewed.")), true);
    assert.equal(await evaluate(cdp, session, clickText("Record decision")), true);
    await waitFor(cdp, session, `document.body.innerText.includes('approved') && !document.body.innerText.includes('Review draft')`, "terminal review state");
    assert.equal(await evaluate(cdp, session, `document.body.innerText.includes('Unsafe for legal use')`), true);

    assert.equal(await evaluate(cdp, session, clickText("Review history")), true);
    await waitFor(cdp, session, `document.body.innerText.includes('Exact record and custody pointer reviewed.')`, "persisted review history");
    assert.equal(await evaluate(cdp, session, `document.body.innerText.includes('Reviewer: owner')`), true);

    assert.deepEqual(fixture.failures, []);
    assert.equal(
      fixture.requests.filter((item) => item.method === "GET" && item.path === "/api/matters").length,
      1,
    );
    assert.equal(fixture.requests.some((item) => item.path.startsWith("/api/graphiti/")), false);
    assert.equal(fixture.requests.some((item) => item.path.includes(MATTER_B)), false);
    assert.equal(JSON.stringify(fixture.requests).includes("MATTER-B-CANARY"), false);
    assert.equal(
      fixture.requests.filter((item) => item.method === "GET" && item.path === `/api/matters/${MATTER_A}/evidence-items/${EVIDENCE_A}`).length,
      2,
    );
    assert.equal(
      fixture.requests.filter((item) => item.method === "GET" && item.path === `/api/matters/${MATTER_A}/evidence-items/${EVIDENCE_A}/court-readiness`).length,
      1,
    );
    assert.equal(
      fixture.requests.filter((item) => item.method === "GET" && item.path === `/api/matters/${MATTER_A}/evidence-items/${EVIDENCE_A}/source-content`).length,
      2,
    );
    assert.equal(
      fixture.requests.filter((item) => item.method === "GET" && item.path === `/api/matters/${MATTER_A}/evidence-items/${EVIDENCE_A}/conversation-context`).length,
      2,
    );
  } catch (error) {
    error.message += `\nBrowser stderr:\n${stderr.join("").slice(-4000)}\nRequests:\n${JSON.stringify(fixture.requests, null, 2)}`;
    throw error;
  } finally {
    browser.kill();
    await new Promise((accept) => fixture.server.close(accept));
    // Project safety contract: never hard-delete. The isolated browser profile
    // remains quarantined under to_be_deleted for owner-only cleanup.
  }
});

for (const inputKind of ["staged", "fresh"]) test(`New Run submits ${inputKind} SMS through Proffer and renders guided recovery`, { timeout: 60_000 }, async () => {
  const fixture = createFixtureServer({ newRunFixture: true });
  await new Promise((accept) => fixture.server.listen(0, "127.0.0.1", accept));
  const profile = await mkdtemp(join(resolve("../..", "to_be_deleted"), "new-run-browser-profile-"));
  const browser = spawn(browserPath(), ["--headless=new", "--disable-gpu", "--no-first-run",
    "--no-default-browser-check", "--remote-debugging-pipe", `--user-data-dir=${profile}`, "about:blank"],
    { stdio: ["ignore", "ignore", "pipe", "pipe", "pipe"] });
  const cdp = new CdpPipe(browser);
  try {
    const target = await cdp.command("Target.createTarget", { url: `http://127.0.0.1:${fixture.server.address().port}/runs` });
    const { sessionId: session } = await cdp.command("Target.attachToTarget", { targetId: target.targetId, flatten: true });
    await cdp.command("Runtime.enable", {}, session);
    await waitFor(cdp, session, `document.body?.innerText.includes('New run')`, "Runs page");
    assert.equal(await evaluate(cdp, session, clickText("New run")), true);
    await waitFor(cdp, session, `document.querySelector('select[aria-label="Staged source"] option[value="${SHA_A}"]') !== null`, "staged source list");
    if (inputKind === "staged") {
      await evaluate(cdp, session, `(() => { const select = document.querySelector('select[aria-label="Staged source"]'); select.value = '${SHA_A}'; select.dispatchEvent(new Event('change', { bubbles: true })); })()`);
    } else {
      await waitFor(cdp, session, `document.querySelector('input[type="file"]') !== null`, "fresh file input");
      await evaluate(cdp, session, `(() => { const input = document.querySelector('input[type="file"]'); const transfer = new DataTransfer(); transfer.items.add(new File(['<smses><sms body="fixture" /></smses>'], 'sms.xml', { type: 'application/xml' })); input.files = transfer.files; input.dispatchEvent(new Event('change', { bubbles: true })); })()`);
    }
    await waitFor(cdp, session, `Array.from(document.querySelectorAll('button')).some((button) => button.textContent.includes('Start TEST context intake') && !button.disabled)`, "context start enabled");
    assert.equal(await evaluate(cdp, session, clickText("Start TEST context intake")), true);
    for (let attempt = 0; attempt < 2; attempt += 1) {
      await waitFor(cdp, session, `document.body.innerText.includes('${attempt ? "Retry after second logged failure" : "Retry after logged automatic execution failure"}')`, "runtime handler guidance");
      await evaluate(cdp, session, `document.querySelector('input[name="parser-handler"]').click()`);
      await waitFor(cdp, session, `Array.from(document.querySelectorAll('button')).some((button) => button.textContent.includes('Record selection and continue') && !button.disabled)`, "handler decision enabled");
      assert.equal(await evaluate(cdp, session, clickText("Record selection and continue")), true);
    }
    await waitFor(cdp, session, `document.body.innerText.includes('Fixture stop: execution is deliberately mocked')`, "Go preview result");
    assert.equal(fixture.requests.some((request) => request.method === "POST" && request.path === "/api/proffer/start"), true);
    assert.equal(fixture.requests.some((request) => request.method === "POST" && request.path === "/api/runs"), false);
    assert.equal(fixture.requests.some((request) => request.method === "POST" && request.path === "/api/upload"), inputKind === "fresh");
    assert.equal(await evaluate(cdp, session, `document.querySelector('#run-custody-tier-select') === null`), true);
    assert.deepEqual(fixture.failures, []);
  } finally {
    browser.kill();
    await new Promise((accept) => fixture.server.close(accept));
  }
});

test("Matter registry stays usable without issuing advanced evidence calls", { timeout: 60_000 }, async () => {
  await stat(join(OUT, "index.html"));
  const fixture = createFixtureServer({ advancedEvidenceAvailable: false });
  await new Promise((accept) => fixture.server.listen(0, "127.0.0.1", accept));
  const address = fixture.server.address();
  const profile = await mkdtemp(join(resolve("../..", "to_be_deleted"), "matter-gate-browser-profile-"));
  const browser = spawn(browserPath(), [
    "--headless=new",
    "--disable-gpu",
    "--no-first-run",
    "--no-default-browser-check",
    "--remote-debugging-pipe",
    `--user-data-dir=${profile}`,
    "about:blank",
  ], { stdio: ["ignore", "ignore", "pipe", "pipe", "pipe"] });
  const cdp = new CdpPipe(browser);

  try {
    const target = await cdp.command("Target.createTarget", {
      url: `http://127.0.0.1:${address.port}/matter?matter_id=${MATTER_A}`,
    });
    const attached = await cdp.command("Target.attachToTarget", { targetId: target.targetId, flatten: true });
    const session = attached.sessionId;
    await cdp.command("Page.enable", {}, session);
    await cdp.command("Runtime.enable", {}, session);
    await waitFor(cdp, session, `document.body?.innerText.includes('Matter Alpha')`, "Matter registry");
    await waitFor(cdp, session, `document.body?.innerText.includes('Evidence operations not yet available')`, "capability hold");

    assert.equal(fixture.failures.length, 0);
    assert.equal(fixture.requests.some((item) => item.path.includes("/evidence-items")), false);
    assert.equal(fixture.requests.some((item) => item.path === "/api/knowledge/search"), false);
    assert.equal(fixture.requests.some((item) => item.path.includes("/knowledge/resolve")), false);
    assert.equal(await evaluate(cdp, session, `document.body.innerText.includes('Court proceedings')`), true);
  } finally {
    browser.kill();
    await new Promise((accept) => fixture.server.close(accept));
  }
});
