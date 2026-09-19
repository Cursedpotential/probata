"""Live test of every top-level Docstore tool through the public single endpoint.

Byline: Claude Code · Opus 5 · 2026-09-19 — owner order: "TEST EVERY CALL, FUNCTION, SKILL AND
FEATURE". Runs against the real endpoint with the real client token (env CF_MCP_CLIENT_TOKEN).
Test rows carry the marker `zz-live-test-20260919`; every row created here is purged at the end
through admin_call, which also exercises the two-step confirm gate. Prints one line per check.

Usage: python live_surface_test.py [--endpoint URL]
"""
from __future__ import annotations

import json
import os
import sys
import urllib.request

URL = (sys.argv[sys.argv.index("--endpoint") + 1] if "--endpoint" in sys.argv
       else "https://mcp.mitechconsult.com/servers/0745d76aa25d4712b545e5dc12e1a4bb/mcp")
MARK = "zz-live-test-20260919"
HEADERS = {"Content-Type": "application/json", "Accept": "application/json, text/event-stream",
           "Authorization": "Bearer " + os.environ["CF_MCP_CLIENT_TOKEN"]}
results: list[tuple[str, bool, str]] = []
session: dict = {}


def rpc(body: dict) -> dict:
    headers = dict(HEADERS)
    if session.get("id"):
        headers["mcp-session-id"] = session["id"]
    with urllib.request.urlopen(urllib.request.Request(URL, data=json.dumps(body).encode(), headers=headers),
                                timeout=300) as response:
        text = response.read().decode()
        session["id"] = response.headers.get("mcp-session-id") or session.get("id")
    for line in text.splitlines():
        if line.startswith("data:"):
            text = line[5:]
    return json.loads(text) if text.strip() else {}


def call(tool: str, args: dict) -> tuple[bool, object]:
    reply = rpc({"jsonrpc": "2.0", "id": 9, "method": "tools/call", "params": {"name": "ctl-" + tool, "arguments": args}})
    result = reply.get("result", reply)
    if result.get("isError"):
        return False, " ".join(c.get("text", "") for c in result.get("content", []))
    if result.get("structuredContent") is not None:
        value = result["structuredContent"]
        return True, value.get("result", value) if isinstance(value, dict) and set(value) == {"result"} else value
    texts = [c.get("text", "") for c in result.get("content", [])]
    try:
        return True, json.loads(texts[0]) if len(texts) == 1 else texts
    except (json.JSONDecodeError, IndexError):
        return True, texts


def check(name: str, ok: bool, detail: object = "") -> None:
    results.append((name, ok, json.dumps(detail, default=str)[:220] if not isinstance(detail, str) else detail[:220]))
    print(("PASS " if ok else "FAIL ") + name + " | " + results[-1][2], flush=True)


def admin(target: str, operation: str, args: dict) -> tuple[bool, object]:
    ok, preview = call("admin-call", {"target": target, "operation": operation, "args": args})
    if not ok or not isinstance(preview, dict) or preview.get("gate") != "confirm_required":
        return False, preview
    return call("admin-call", {"target": target, "operation": operation, "args": args,
                               "confirm": preview["confirm_code"]})


def main() -> int:
    rpc({"jsonrpc": "2.0", "id": 1, "method": "initialize",
         "params": {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "live-test", "version": "1"}}})
    listed = [t["name"] for t in rpc({"jsonrpc": "2.0", "id": 2, "method": "tools/list"})["result"]["tools"]]
    check("endpoint lists exactly the 13 top-level tools", len(listed) == 13, listed)

    # ---- read
    ok, r = call("read-search", {"query": "pipeline history receipt 2026-09-18"})
    hits = json.dumps(r)
    check("read-search project-wide finds a new Consignatio doc", ok and "consignatio/docs" in hits, r if not ok else r.get("scope"))
    ok, r = call("read-search", {"query": "timeline validation schema", "module": "vestigia"})
    check("read-search module=vestigia returns vestigia docs", ok and "vestigia/" in json.dumps(r), r if not ok else r.get("scope"))
    rid = "document:consignatio_docs_receipts_pipeline_history_2026_09_18_md"
    ok, r = call("read-get", {"record_id": rid})
    check("read-get returns document + history", ok and "history" in r and "document" in r, r if not ok else list(r))
    ok, r = call("read-health", {})
    check("read-health returns health + stats", ok and "health" in r and "stats" in r, r if not ok else r["health"].get("ok"))
    ok, r = call("read-discover", {})
    check("read-discover lists read/write/run/admin with disclaimer",
          ok and all(k in r for k in ("read", "write", "run", "admin")) and "bypass" in json.dumps(r["admin"]), list(r) if ok else r)
    ok, r = call("read-discover", {"area": "graph"})
    check("read-discover area=graph narrows", ok and "graph" in r.get("read", {}) and "write" not in r, list(r.get("read", {})) if ok else r)
    ok, r = call("read-call", {"tool": "docstore_run_list", "args": {"limit": 2}})
    check("read-call runs a read tool", ok, r if not ok else "runs listed")
    ok, r = call("read-call", {"tool": "docstore_set_flags", "args": {}})
    check("read-call refuses a write tool", not ok and "not a read tool" in str(r), r)
    ok, r = call("read-memory", {"action": "recall", "query": "Propria is the project"})
    check("read-memory recall (scope propria)", ok and "propria" in json.dumps(r), r)
    ok, r = call("read-memory", {"action": "stats"})
    check("read-memory stats (scope propria)", ok, r)

    # ---- write: memory
    ok, r = call("write-memory", {"action": "remember", "fields": {
        "kind": "observation", "claim": f"{MARK} live surface test memory, safe to purge",
        "agent": "live-test", "scope": "propria/test"}})
    mem_id = r.get("written") if ok and isinstance(r, dict) else None
    check("write-memory remember", bool(mem_id), r)
    ok, r = call("write-memory", {"action": "remember", "fields": {
        "kind": "observation", "claim": f"{MARK} live surface test memory, safe to purge",
        "agent": "live-test", "scope": "propria/test"}})
    check("write-memory remember refuses a duplicate", ok and isinstance(r, dict) and not r.get("written") and r.get("conflicts"), r)
    ok, r = call("write-memory", {"action": "correct", "fields": {"old": mem_id, "new_payload": {
        "kind": "observation", "claim": f"{MARK} corrected live surface test memory", "agent": "live-test", "scope": "propria/test"}}})
    check("write-memory correct (supersede)", ok, r)
    ok, r = call("write-memory", {"action": "forget", "fields": {"id": mem_id, "reason": MARK}})
    check("write-memory forget (retract, not delete)", ok, r)
    ok, r = call("write-memory", {"action": "remember", "fields": {"kind": "observation", "claim": f"{MARK} wrong root", "scope": "probata/test"}})
    check("memory rejects the old probata root", not ok or (isinstance(r, dict) and not r.get("written")), r)

    # ---- write: notes and updates on a throwaway document (created through the admin gate)
    ok, r = admin("docs", "run", {"function": "fn::docs_register", "args": [
        f"propria/test/{MARK}.md", f"{MARK} throwaway", "reference", ["docs"], "unverified", f"{MARK} body v1", None]})
    doc = json.dumps(r)
    check("admin-call two-step gate executes after confirm", ok and "document:" in doc, r)
    ok, r = call("admin-call", {"target": "docs", "operation": "select", "args": {"target": "document", "limit_clause": 1}})
    check("admin-call without confirm only previews", ok and isinstance(r, dict) and r.get("gate") == "confirm_required", list(r) if isinstance(r, dict) else r)
    ok, r = admin("docs", "query", {"query": "SELECT VALUE id FROM document WHERE source_path = $p;",
                                     "parameters": {"p": f"propria/test/{MARK}.md"}})
    test_doc = None
    try:
        test_doc = str(json.loads(json.dumps(r))["result"]["value"][0]) if ok else None
    except Exception:
        test_doc = next((w.strip('"') for w in json.dumps(r).split() if "document:" in w), None)
    check("throwaway document id resolved", bool(test_doc), test_doc or r)
    if test_doc:
        ok, r = call("write-update", {"action": "tags", "fields": {"id": test_doc, "tags": [MARK], "actor": "live-test"}})
        check("write-update tags", ok, r)
        ok, r = call("write-update", {"action": "new_version", "fields": {"old": test_doc, "body": f"{MARK} body v2"}})
        check("write-update new_version (old kept, superseded)", ok, r)
        ok, r = call("write-update", {"action": "retract", "fields": {"id": test_doc, "reason": MARK}})
        check("write-update retract (history kept)", ok, r)
        ok, r = call("write-note", {"type": "decision", "fields": {"subject": test_doc, "banner": f"{MARK} decision", "closes": None}})
        check("write-note decision (append-only log)", ok, r)
    ok, r = call("write-note", {"type": "todo", "fields": {"item": f"{MARK} todo", "priority": 3, "domains": ["docs"]}})
    todo_id = next((w.strip('",{}[]') for w in json.dumps(r).split() if "todo:" in w), None) if ok else None
    check("write-note todo", ok and bool(todo_id), r)
    if todo_id:
        ok, r = call("write-update", {"action": "close_todo", "fields": {"id": todo_id, "evidence": MARK}})
        check("write-update close_todo", ok, r)
    ok, r = call("write-call", {"tool": "docstore_health", "args": {}})
    check("write-call refuses a read tool", not ok and "not a write tool" in str(r), r)

    # ---- run
    ok, r = call("run-index", {"action": "status"})
    check("run-index status", ok, r if not ok else r.get("sync"))
    ok, r = call("run-index", {"action": "verify", "paths": ["docs/consignatio/receipts/PIPELINE-HISTORY-2026-09-18.md"]})
    check("run-index verify (paths)", ok, r)
    ok, r = call("run-call", {"tool": "docstore_health", "args": {}})
    check("run-call refuses a read tool", not ok and "not a run tool" in str(r), r)

    # ---- purge every row this test created
    purge = [("mem", "UPDATE memory SET scope = scope WHERE false;"),  # no-op keeps the gate honest
             ("mem", f"DELETE memory WHERE string::contains(claim, '{MARK}');"),
             ("mem", f"DELETE decision_log WHERE string::contains(<string> reason ?? '', '{MARK}') OR string::contains(<string> subject, 'zz_live_test');"),
             ("docs", f"DELETE todo WHERE string::contains(item ?? '', '{MARK}') OR string::contains(detail ?? '', '{MARK}');"),
             ("docs", f"DELETE decision_log WHERE string::contains(<string> rationale ?? '', '{MARK}') OR string::contains(<string> banner ?? '', '{MARK}');"),
             ("docs", f"DELETE supersedes WHERE string::contains(<string> in.source_path ?? '', '{MARK}') OR string::contains(<string> out.source_path ?? '', '{MARK}');"),
             ("docs", f"DELETE document WHERE string::contains(source_path, '{MARK}');")]
    for target, sql in purge:
        ok, r = admin(target, "query", {"query": sql})
        check("purge " + target + ": " + sql.split(" WHERE")[0], ok, r if not ok else "done")
    ok, r = admin("docs", "query", {"query": f"SELECT count() FROM document WHERE string::contains(source_path, '{MARK}') GROUP ALL;"})
    check("purge verified: no test documents left", ok and '"count"' not in json.dumps(r).replace('"count": 0', ''), r)

    failed = [n for n, ok, _ in results if not ok]
    print(f"\n{len(results) - len(failed)}/{len(results)} passed" + (f"; FAILED: {failed}" if failed else ""))
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
