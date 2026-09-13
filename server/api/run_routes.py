# Byline amendment: Codex · GPT-5 · 2026-08-18 (combined-change hygiene)
"""server/api/run_routes.py — REST surface for the C0/C2 operator-console run ledger.

Modeled on server/api/evidence_routes.py's multipart pattern (same base_app
registration convention as register_knowledge_routes / register_evidence_routes
— see server/api/main.py), but "fire-and-watch" instead of request/response:

  POST /v1/runs                   — save the upload, seed the run + its stage
                                     rows, kick the workflow off in the
                                     background, return 202 {run_id, workflow,
                                     mode} immediately.
  GET  /v1/runs                   — list recent runs (+ per-stage pairs).
  GET  /v1/runs/{run_id}          — full run detail (run row + ordered stages).
  POST /v1/runs/{run_id}/continue — release a supervised-mode gate (C2).
  POST /v1/runs/{run_id}/abort    — abort a paused or running run (C2).
  POST /v1/runs/{run_id}/retry    — re-run a terminal-failed run from its
                                     original custody blob, linked via
                                     parent_run_id (C2). Optional JSON body
                                     {"from_stage": "knowledge"} (C2.6) skips
                                     straight to re-running the knowledge
                                     stage over the parent's already-stored
                                     records instead of a full rerun.
  GET  /v1/health/deps            — cheap parallel pg + Milvus connectivity
                                     check, 3s timeout each (C2.6 requirement 4).

The caller polls GET /v1/runs/{run_id} to watch ops.workflow_run_stage
rows fill in as server/evidence/workflows.py executes (server/evidence/
run_ledger.py is the write side; this module never touches the DB directly).

C2 supervised gates (server/evidence/workflows.py's
`_wrap_step_for_run_control`): when mode="supervised", the run pauses after
every non-final stage and waits on POST .../continue or .../abort. The
run's own background asyncio task (`_execute_run` below, still alive for as
long as the process is) is the ONLY thing that ever calls finish_run() —
these control endpoints only flip ops.workflow_run.gate_state (and, for
/continue and a /abort-while-paused, also flip status directly so the HTTP
response is truthful immediately); single-writer discipline for run
termination is preserved exactly the way custody.py is the sole writer of
the evidence schema.

C2.6 retry `from_stage` (requirement 1 — the real prod bug this fixes): a
plain retry re-ingests from the custody blob, custody dedupes (same bytes,
duplicate=True), parse/store re-run but store sees 0 NEW rows to insert
(the records are already there) — under the OLD behavior, the knowledge
step then saw an empty `ctx['records']` and reported a false success with
docs_ingested=0. `{"from_stage": "knowledge"}` sidesteps that trap entirely:
it creates a child run that skips custody/parse/store (recorded 'skipped',
content "inherited from parent") and re-runs ONLY the knowledge stage over
the parent's already-stored working.normalized_record rows
(server/evidence/workflows.py's `run_knowledge_from_store`). A plain retry
(no body / from_stage omitted) ALSO got safer this task: if its custody
step dedupes AND the parent's knowledge stage had failed, `_store_step_impl`
auto-routes into the same reload-and-reingest path instead of silently
reporting 0 records, logging it loudly on the store stage's content.
"""
# Byline: Claude Code · Sonnet (agent) · 2026-07-22 (C2 gates+retry+custody_tier 2026-07-20; C2.6 retry from_stage + health/deps 2026-07-21; C3 KnowledgeHandle live-resolve + retry-gap for completed parents 2026-07-22)
# Byline: Codex · GPT-5 · 2026-08-13 (ADR-0053 five-lane alignment)
# Byline: Codex · GPT-5 · 2026-09-12 (reject unsupported retry before creating an orphan child)

from __future__ import annotations

import asyncio
import hashlib
import json
import logging
import os
import shutil
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Annotated, Any

from fastapi import FastAPI, File, Form, HTTPException, Query, Request, UploadFile
from pydantic import BaseModel, ConfigDict, Field, StringConstraints

from server.core.knowledge_handle import resolve_knowledge
from server.api.uploads import safe_upload_name
from server.evidence.custody import blob_root
from server.evidence.run_ledger import (
    create_run,
    get_run,
    list_review_actions,
    list_runs,
    ping,
    record_review_action,
    seed_stages,
    set_gate,
)
from server.evidence.run_report import build_run_report

logger = logging.getLogger("evidence.runs")  # same logger name workflows.py/store.py use

# ADR-0053 (2026-08-13): five-lane vocabulary; relationship history is part
# of personal_history. AI-chat routing still cannot produce evidence.
_ALLOWED_DOMAINS = {
    "platform",
    "legal",
    "personal_history",
    "context",
    "evidence",
}
_ALLOWED_WORKFLOWS = {"chat-transcript", "sms-xml"}
_ALLOWED_MODES = {"auto", "supervised"}
_ALLOWED_CUSTODY_TIERS = {"full", "light"}
# C2.6 requirement 1: only "knowledge" is supported today — the retry-stage
# fix only exists for the knowledge stage's dedupe/no-new-rows trap. Any
# other value 422s rather than silently falling back to a full rerun.
_ALLOWED_RETRY_FROM_STAGES = {"knowledge"}
# C2.6 requirement 4: per-check timeout for GET /v1/health/deps.
_HEALTH_DEPS_TIMEOUT_S = 3.0

# ADR-0050 lane defaults: AI chats are CONTEXT (ADR-0044 §1); SMS/MMS custody
# imports are EVIDENCE (they vector into evidence_knowledge via
# `_knowledge_for` above — the lane tag and the destination handle agree).
_DEFAULT_DOMAIN: dict[str, str] = {
    "chat-transcript": "context",
    "sms-xml": "evidence",
}

# Two-tier custody (operator-console-requirements.md addendum 2): the
# knowledge-lane AI-chat vertical defaults to 'light' (whole-file sha256 +
# blob + dedupe only — this is the owner's STORY, not evidence); the
# evidence vertical (sms-xml) keeps the historical 'full' default.
_DEFAULT_CUSTODY_TIER: dict[str, str] = {
    "chat-transcript": "light",
    "sms-xml": "full",
}

_TERMINAL_STATUSES = {"completed", "failed"}


class RunReviewActionRequest(BaseModel):
    """Append-only operator decision attached to a run or stage."""

    model_config = ConfigDict(extra="forbid")

    action_type: str = Field(pattern="^(acknowledge|approve|override)$")
    reason: Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=4000)]
    stage_seq: int | None = Field(default=None, ge=1)
    replacement: dict[str, Any] | None = None


def _trace_url(trace_id: str | None) -> str | None:
    template = os.getenv("LANGFUSE_TRACE_URL_TEMPLATE")
    if not trace_id or not template:
        return None
    try:
        return template.format(trace_id=trace_id)
    except (IndexError, KeyError, ValueError):
        logger.warning("LANGFUSE_TRACE_URL_TEMPLATE must contain a valid {trace_id} placeholder")
        return None


def _audit_report_read(run_id: str, report: dict[str, Any]) -> None:
    """Audit every report read with a content hash, never report contents."""
    from server.core.audit import record_read

    canonical = json.dumps(report, sort_keys=True, separators=(",", ":"), default=str)
    record_read(
        run_id,
        actor="workbench",
        ctx={},
        object_schema="ops.workflow_run_report",
        payload_hash=hashlib.sha256(canonical.encode("utf-8")).hexdigest(),
    )


def register_run_routes(
    app: FastAPI,
    knowledge: Any,
    evidence_knowledge: Any | None = None,
    native_projector: Any | None = None,
) -> None:
    """Register the C0 run-ledger REST surface on the FastAPI app.

    Parameters
    ----------
    app:
        The FastAPI application instance (base app, pre-AgentOS wrap).
    knowledge:
        Agno Knowledge instance handed through to the workflow's knowledge step
        (same handle register_evidence_routes uses). C3 (spine boot resilience,
        server/core/knowledge_handle.py): may ALSO be a `KnowledgeHandle` —
        every usage site below resolves it via `resolve_knowledge()` freshly
        at call time (not once at registration), so a run started AFTER a
        background reconnect succeeds sees the real knowledge engine even
        though this module was only ever registered once. A raw Knowledge
        instance or None (every pre-C3 caller/test) passes through unchanged.
    evidence_knowledge:
        Deprecated compatibility input. It is never selected for evidence.
    native_projector:
        Native PostgreSQL-outbox projector selected for every SMS/evidence run.
        None leaves projection pending; it never falls back to Agno.
    """

    def _knowledge_for(workflow: str) -> Any:
        # Evidence writes are native-only. The Agno evidence handle remains a
        # deprecated parameter solely so older callers do not break at import.
        if workflow == "sms-xml":
            return native_projector
        return resolve_knowledge(knowledge)

    async def _execute_run(
        run_id: str,
        workflow: str,
        tmp_path: Path,
        tmpdir: Path,
        meta: dict[str, Any],
        domain: str,
        mode: str = "auto",
        custody_tier: str = "full",
        parent_run_id: str | None = None,
    ) -> None:
        """Background task body: run the workflow with the ledger wired in,
        then clean up the private temp dir regardless of outcome. The runner's
        own finally-block (workflows.py) calls finish_run — this task doesn't
        need to (and must not swallow/re-report status; the ledger IS the
        result surface for a fire-and-watch run).

        This same task is what stays alive to service a supervised-mode run's
        gate poll loop (server/evidence/workflows.py's
        `_wrap_step_for_run_control`) — POST .../continue and .../abort below
        only flip ops.workflow_run.gate_state; THIS coroutine is what
        actually observes it and resumes/halts the workflow.

        parent_run_id (C2.6, optional): only set for a FULL rerun kicked off
        by POST .../retry (not a from_stage='knowledge' retry, which never
        calls this function — see `_retry_from_knowledge`) — threaded to the
        runner so its store step can auto-route a custody-dedupe no-op into
        knowledge-from-store when the parent's knowledge stage had failed."""
        from opentelemetry import trace

        from server.evidence.run_ledger import set_trace_id
        from server.evidence.workflows import run_chat_transcript, run_sms_xml

        runner = run_chat_transcript if workflow == "chat-transcript" else run_sms_xml
        tracer = trace.get_tracer("server.evidence.workflow")
        with tracer.start_as_current_span("evidence.workflow.run") as span:
            span.set_attribute("platform.run_id", run_id)
            span.set_attribute("platform.workflow", workflow)
            span.set_attribute("platform.domain", domain)
            span.set_attribute("platform.mode", mode)
            span_context = span.get_span_context()
            if span_context.is_valid:
                set_trace_id(run_id, format(span_context.trace_id, "032x"))
            try:
                await runner(
                    str(tmp_path),
                    source_meta=meta,
                    domain=domain,
                    knowledge=_knowledge_for(workflow),
                    run_id=run_id,
                    mode=mode,
                    custody_tier=custody_tier,
                    parent_run_id=parent_run_id,
                )
            except Exception as exc:
                span.record_exception(exc)
                # workflows.py's own finally-block already recorded this failure
                # into the ledger; this background task has no caller left.
            finally:
                shutil.rmtree(tmpdir, ignore_errors=True)

    async def _retry_from_knowledge(run_id: str, run: dict[str, Any]) -> dict[str, Any]:
        """C2.6 requirement 1 — the explicit `{"from_stage": "knowledge"}`
        retry path. Validates the parent run actually has something to
        re-ingest (custody/parse/store all succeeded, artifact_id/sha256
        recorded), then starts `run_knowledge_from_store` as a background
        task exactly like a normal retry starts `_execute_run`."""
        if run.get("artifact_id") is None or run.get("sha256") is None:
            raise HTTPException(
                409,
                f"run {run_id!r} has no artifact_id/sha256 recorded — cannot retry "
                "from_stage='knowledge' (nothing to reload from working.normalized_record)",
            )
        stage_by_name = {s["name"]: s for s in run["stages"]}
        for name in ("custody", "parse", "store"):
            stage = stage_by_name.get(name)
            if stage is None or stage["status"] != "success":
                got = stage["status"] if stage else "missing"
                raise HTTPException(
                    409,
                    f"run {run_id!r}: retry from_stage='knowledge' requires custody/parse/store to "
                    f"have succeeded on the parent run — stage {name!r} is {got!r}",
                )

        from server.evidence.workflows import WORKFLOW_STAGE_NAMES, run_knowledge_from_store

        workflow = run["workflow"]
        domain = run["domain"]
        custody_tier = run.get("custody_tier") or _DEFAULT_CUSTODY_TIER.get(workflow, "full")
        custody_stage = stage_by_name.get("custody") or {}
        blob_key = (custody_stage.get("output") or {}).get("blob_key")

        new_run_id = create_run(
            workflow=workflow,
            mode=run["mode"],
            source_name=run.get("source_name"),
            source_path=None,
            domain=domain,
            parent_run_id=run_id,
            custody_tier=custody_tier,
            source_context=run.get("source_context") or {},
        )
        seed_stages(new_run_id, WORKFLOW_STAGE_NAMES[workflow])

        async def _traced_retry() -> None:
            from opentelemetry import trace

            from server.evidence.run_ledger import set_trace_id

            tracer = trace.get_tracer("server.evidence.workflow")
            with tracer.start_as_current_span("evidence.workflow.retry_from_knowledge") as span:
                span.set_attribute("platform.run_id", new_run_id)
                span.set_attribute("platform.parent_run_id", run_id)
                span.set_attribute("platform.workflow", workflow)
                span_context = span.get_span_context()
                if span_context.is_valid:
                    set_trace_id(new_run_id, format(span_context.trace_id, "032x"))
                await run_knowledge_from_store(
                    parent_run_id=run_id,
                    run_id=new_run_id,
                    workflow=workflow,
                    domain=domain,
                    knowledge=_knowledge_for(workflow),
                    artifact_id=run["artifact_id"],
                    sha256=run["sha256"],
                    blob_key=blob_key,
                    custody_tier=custody_tier,
                )

        asyncio.create_task(_traced_retry())

        return {"run_id": new_run_id, "parent_run_id": run_id}

    async def _knowledge_doc_exists_for_artifact(workflow: str, knowledge_instance: Any, sha256: str) -> bool | None:
        """C3 retry-gap ("closes the reingest-after-collection-loss hole"):
        cheap, GUARDED Milvus existence check — does the knowledge collection
        still have at least one doc for this artifact? Filters on
        ``metadata['sha256']`` (every doc `ingest_into_knowledge` inserts
        carries this — server/evidence/store.py's `_do_insert`), which is a
        more robust "artifact-derived" check than reconstructing a doc's
        exact name (the name also encodes a per-conversation slug this
        endpoint has no cheap way to reconstruct without first loading the
        artifact's stored records — see `ingest_into_knowledge`'s
        `doc_path = out_dir / f"{artifact.sha256[:12]}-{safe}.md"`).

        Returns True (doc verifiably exists — caller should keep the 409),
        False (query succeeded, zero hits — the collection genuinely lacks
        the doc, e.g. after a collection recreate), or None (the query
        itself failed, or there's no knowledge instance to query — UNKNOWN).
        The task spec is explicit that a 409 is only warranted when the doc
        VERIFIABLY exists, so callers must treat None the same as False
        (allow the retry), never as an implicit True.
        """
        if workflow == "sms-xml":
            if native_projector is None:
                return None
            try:
                return await asyncio.wait_for(
                    asyncio.to_thread(native_projector.source_projection_exists, sha256),
                    timeout=_HEALTH_DEPS_TIMEOUT_S,
                )
            except Exception as exc:
                logger.warning("retry-gap: native source lookup failed (%s) — treating as unknown/allow", exc)
                return None
        if knowledge_instance is None:
            return None

        def _do() -> bool:
            vector_db = getattr(knowledge_instance, "vector_db", None)
            if vector_db is None:
                raise RuntimeError("no vector_db available on this knowledge instance")
            client = vector_db.get_client()
            # agno's Weaviate stores meta_data as a JSON STRING property, so the
            # sha256 can't be filtered as a structured key — LIKE-match the hex
            # token inside the serialized JSON (a sha256 hex string is a single
            # token; false positives would need a 64-hex-char collision in other
            # metadata, which "verifiably exists" tolerates for a 409 gate).
            from weaviate.classes.query import Filter

            result = client.collections.get(vector_db.collection).query.fetch_objects(
                limit=1,
                filters=Filter.by_property("meta_data").like(f"*{sha256}*"),
            )
            return bool(result.objects)

        try:
            return await asyncio.wait_for(asyncio.to_thread(_do), timeout=_HEALTH_DEPS_TIMEOUT_S)
        except Exception as exc:
            logger.warning("retry-gap: knowledge doc-existence check failed (%s) — treating as unknown/allow", exc)
            return None

    async def _check_pg() -> dict[str, Any]:
        """GET /v1/health/deps' pg check — SELECT 1 via run_ledger's engine,
        time-boxed to `_HEALTH_DEPS_TIMEOUT_S` (a slow/blocked DB should not
        hang the health endpoint itself)."""
        try:
            await asyncio.wait_for(asyncio.to_thread(ping), timeout=_HEALTH_DEPS_TIMEOUT_S)
            return {"status": "ok"}
        except Exception as exc:
            return {"status": "error", "error": str(exc)[:300]}

    async def _check_weaviate() -> dict[str, Any]:
        """GET /v1/health/deps' vector-store check — reuses the already-connected
        Knowledge instance's Weaviate client when available (agno's
        `Weaviate.get_client()`, a lazily-created v4 client) so this doesn't
        open a second connection; falls back to a fresh client
        (server.core.session.get_weaviate_client) when `knowledge` is None
        (e.g. this route registered without a live knowledge handle, as in
        tests)."""

        def _do() -> None:
            client = None
            live_knowledge = resolve_knowledge(knowledge)
            vector_db = getattr(live_knowledge, "vector_db", None) if live_knowledge is not None else None
            if vector_db is not None and getattr(vector_db, "get_client", None) is not None:
                client = vector_db.get_client()
            if client is None:
                from server.core.session import get_weaviate_client

                client = get_weaviate_client()
            if not client.is_ready():
                raise RuntimeError("weaviate not ready")

        try:
            await asyncio.wait_for(asyncio.to_thread(_do), timeout=_HEALTH_DEPS_TIMEOUT_S)
            return {"status": "ok"}
        except Exception as exc:
            return {"status": "error", "error": str(exc)[:300]}

    @app.get("/v1/health/deps")
    async def health_deps() -> dict[str, Any]:
        """C2.6 requirement 4 — cheap, parallel dependency health check.

        Returns ``{"pg": {"status": "ok"|"error", "error"?: str},
        "weaviate": {...}, "milvus": <deprecated alias of weaviate>,
        "checked_at": <iso8601>}``. The ``milvus`` key is a TRANSITIONAL alias
        (ADR-0040 cutover 2026-07-29) kept only until the workbench health proxy
        (workbench/api/app/runtime/health.py) and its UI read ``weaviate``; it
        now reports the Weaviate check, not Milvus. Object-store health is
        workbench-side only (this spine doesn't touch R2 directly) — the
        workbench's own GET /api/health/deps merges its lancedb/object_store
        checks with a proxy of THIS endpoint.
        """
        pg_result, vector_result = await asyncio.gather(_check_pg(), _check_weaviate())
        return {
            "pg": pg_result,
            "weaviate": vector_result,
            "milvus": vector_result,  # deprecated alias — see docstring
            "checked_at": datetime.now(timezone.utc).isoformat(),
        }

    @app.post("/v1/runs", status_code=202)
    async def start_run(
        file: UploadFile = File(...),
        workflow: str = Form("chat-transcript"),
        domain: str | None = Form(None),
        mode: str = Form("auto"),
        custody_tier: str | None = Form(None),
        source_meta: str = Form("{}"),
    ) -> dict[str, Any]:
        """Start a workflow run in the background; return its run_id immediately.

        Returns
        -------
        dict
            ``{"run_id": ..., "workflow": ..., "mode": ...}`` — poll
            GET /v1/runs/{run_id} for progress.
        """
        if workflow not in _ALLOWED_WORKFLOWS:
            raise HTTPException(422, f"unknown workflow {workflow!r}; allowed: {sorted(_ALLOWED_WORKFLOWS)}")
        if mode not in _ALLOWED_MODES:
            raise HTTPException(422, f"unknown mode {mode!r}; allowed: {sorted(_ALLOWED_MODES)}")
        resolved_domain = domain or _DEFAULT_DOMAIN[workflow]
        if resolved_domain not in _ALLOWED_DOMAINS:
            raise HTTPException(422, f"unknown domain {resolved_domain!r}; allowed: {sorted(_ALLOWED_DOMAINS)}")
        # Two-tier custody (addendum 2): 'light' for chat-transcript, 'full'
        # for sms-xml, unless the caller explicitly overrides.
        resolved_tier = custody_tier or _DEFAULT_CUSTODY_TIER[workflow]
        if resolved_tier not in _ALLOWED_CUSTODY_TIERS:
            raise HTTPException(
                422, f"unknown custody_tier {resolved_tier!r}; allowed: {sorted(_ALLOWED_CUSTODY_TIERS)}"
            )
        try:
            meta = json.loads(source_meta) if source_meta else {}
        except json.JSONDecodeError as exc:
            raise HTTPException(422, f"source_meta is not valid JSON: {exc}") from exc

        from server.evidence.workflows import WORKFLOW_STAGE_NAMES

        # Persist the upload to a private temp dir that OUTLIVES this request
        # (deliberately not `with TemporaryDirectory()` — the background task
        # reads it after we return 202, and removes it itself when done).
        tmpdir = Path(tempfile.mkdtemp(prefix="run-ledger-"))
        suffix_name = safe_upload_name(file.filename)
        tmp_path = tmpdir / suffix_name
        tmp_path.write_bytes(await file.read())

        run_id = create_run(
            workflow=workflow,
            mode=mode,
            source_name=suffix_name,
            source_path=str(tmp_path),
            domain=resolved_domain,
            custody_tier=resolved_tier,
            source_context=meta,
        )
        seed_stages(run_id, WORKFLOW_STAGE_NAMES[workflow])

        asyncio.create_task(
            _execute_run(
                run_id, workflow, tmp_path, tmpdir, meta, resolved_domain, mode=mode, custody_tier=resolved_tier
            )
        )

        return {"run_id": run_id, "workflow": workflow, "mode": mode}

    @app.get("/v1/runs")
    async def get_runs(
        status: str | None = Query(None),
        limit: int = Query(50, ge=1, le=500),
    ) -> list[dict[str, Any]]:
        """List recent runs (most recent first), each with its per-stage
        name/status pairs. Each run dict now also carries gate_state,
        parent_run_id, and custody_tier (C2)."""
        return list_runs(limit=limit, status=status)

    @app.get("/v1/runs/{run_id}")
    async def get_run_detail(run_id: str) -> dict[str, Any]:
        """Full run detail: the run row + its ordered stages (typed output
        included), or 404 if run_id is unknown. Now also carries gate_state,
        parent_run_id, and custody_tier (C2)."""
        run = get_run(run_id)
        if run is None:
            raise HTTPException(404, f"run {run_id!r} not found")
        return run

    @app.get("/v1/runs/{run_id}/report")
    async def get_run_report(run_id: str) -> dict[str, Any]:
        """Versioned report: every stage, disposition, reason, and review action."""
        run = get_run(run_id)
        if run is None:
            raise HTTPException(404, f"run {run_id!r} not found")
        report = build_run_report(run, list_review_actions(run_id), trace_url=_trace_url(run.get("trace_id")))
        _audit_report_read(run_id, report)
        return report

    @app.post("/v1/runs/{run_id}/review-actions", status_code=201)
    async def create_run_review_action(run_id: str, body: RunReviewActionRequest) -> dict[str, Any]:
        """Record a human decision without rewriting the underlying outcome."""
        run = get_run(run_id)
        if run is None:
            raise HTTPException(404, f"run {run_id!r} not found")
        if body.stage_seq is not None and not any(s["seq"] == body.stage_seq for s in run["stages"]):
            raise HTTPException(422, f"run {run_id!r} has no stage seq={body.stage_seq}")
        action = record_review_action(
            run_id,
            body.action_type,
            body.reason,
            actor="owner",
            stage_seq=body.stage_seq,
            replacement=body.replacement,
        )
        return action

    @app.post("/v1/runs/{run_id}/continue")
    async def continue_run(run_id: str) -> dict[str, Any]:
        """Release a supervised-mode gate: 200 {run_id, status:'running'}.

        409 if the run is not currently paused (nothing to release) — includes
        runs that were never gated (mode='auto') and terminal runs."""
        run = get_run(run_id)
        if run is None:
            raise HTTPException(404, f"run {run_id!r} not found")
        if run["status"] != "paused":
            raise HTTPException(409, f"run {run_id!r} is {run['status']!r}, not paused — nothing to continue")
        # Write BOTH columns now so the response is truthful the instant it
        # returns; the run's own background poll loop (workflows.py's
        # `_wrap_step_for_run_control`) will independently notice
        # gate_state='released' within ~2s and clear it back to None as it
        # resumes — a harmless, idempotent second write.
        set_gate(run_id, "released", status="running")
        record_review_action(run_id, "continue", "Owner released the supervised workflow gate.")
        return {"run_id": run_id, "status": "running"}

    @app.post("/v1/runs/{run_id}/abort")
    async def abort_run(run_id: str) -> dict[str, Any]:
        """Abort a paused or running run: 200 {run_id, status:'failed'}.

        409 on a terminal run (completed/failed already — nothing to abort).

        LIMITATION (by design, matches the C2 task spec): this endpoint only
        ever sets gate_state='abort' — it never calls finish_run itself. For
        a PAUSED run, the run's own background gate-poll loop is already
        awake roughly every 2s and will observe the flag almost immediately.
        For a RUNNING run, the abort is honored at "the next gate/stage
        boundary" (server/evidence/workflows.py's
        `_wrap_step_for_run_control`) — i.e. once the in-flight stage's
        executor returns, NOT preemptively mid-stage. If that run is in
        'auto' mode and its currently-executing stage happens to be the
        workflow's LAST stage, the abort can still race a run that finishes
        on its own in the meantime (the abort flag would then sit unused on
        an already-terminal row). The 200 response below reports the
        *intended* outcome of this call, not a synchronously-verified one —
        poll GET /v1/runs/{run_id} to observe the actual terminal state."""
        run = get_run(run_id)
        if run is None:
            raise HTTPException(404, f"run {run_id!r} not found")
        status = run["status"]
        if status in _TERMINAL_STATUSES:
            raise HTTPException(409, f"run {run_id!r} is {status!r} (terminal) — cannot abort")
        set_gate(run_id, "abort")
        record_review_action(run_id, "abort", "Owner requested abort at the next safe stage boundary.")
        return {"run_id": run_id, "status": "failed"}

    @app.post("/v1/runs/{run_id}/retry", status_code=202)
    async def retry_run(run_id: str, request: Request) -> dict[str, Any]:
        """Re-run a terminal-failed run.

        Optional JSON body ``{"from_stage": "knowledge"}`` (C2.6 requirement
        1): skips custody/parse/store entirely and re-runs ONLY the
        knowledge stage over the parent's already-stored records — see
        `_retry_from_knowledge` and server/evidence/workflows.py's
        `run_knowledge_from_store`. No body (or a body without `from_stage`,
        or `from_stage: null`) keeps the pre-C2.6 full-rerun behavior below,
        UNCHANGED except that a custody-dedupe no-op now auto-routes into
        knowledge-from-store when the parent's knowledge stage had failed
        (server/evidence/workflows.py's `_store_step_impl`).

        409 if the parent run is not status='failed'. 422 for an unknown
        `from_stage` value or a non-JSON/non-object body. 410 Gone (full
        rerun only) if neither the custody blob (preferred) nor the original
        source_path (fallback) is still readable.

        Returns 202 {"run_id": <NEW run_id>, "parent_run_id": <this run_id>}
        — poll the new run_id like any other fire-and-watch run.
        """
        from_stage: str | None = None
        body_bytes = await request.body()
        if body_bytes:
            try:
                payload = json.loads(body_bytes)
            except json.JSONDecodeError as exc:
                raise HTTPException(422, f"retry body is not valid JSON: {exc}") from exc
            if payload is not None:
                if not isinstance(payload, dict):
                    raise HTTPException(422, 'retry body must be a JSON object, e.g. {"from_stage": "knowledge"}')
                from_stage = payload.get("from_stage")
                if from_stage is not None and from_stage not in _ALLOWED_RETRY_FROM_STAGES:
                    raise HTTPException(
                        422, f"unknown from_stage {from_stage!r}; allowed: {sorted(_ALLOWED_RETRY_FROM_STAGES)}"
                    )

        run = get_run(run_id)
        if run is None:
            raise HTTPException(404, f"run {run_id!r} not found")

        # Validate before any retry path can create a child or read/copy source
        # bytes. Framework-neutral context runs belong to Go Proffer, not this
        # historical Python stage registry. The old late lookup orphaned rows.
        from server.evidence.workflows import WORKFLOW_STAGE_NAMES

        retry_stages = WORKFLOW_STAGE_NAMES.get(run["workflow"])
        if not retry_stages:
            raise HTTPException(
                410,
                "This historical run cannot be retried by the legacy executor. "
                "Start a fresh context import through Go Proffer; the original run remains unchanged.",
            )

        if from_stage == "knowledge":
            # C3 retry-gap: from_stage='knowledge' is now ALSO allowed on a
            # COMPLETED parent (not only 'failed') when the knowledge
            # collection can be shown to LACK the parent's doc — e.g. Milvus
            # collection was recreated after a completed run already landed
            # its rows in working.normalized_record. This closes the
            # "reingest after collection loss" hole: before this, the ONLY
            # way to re-ingest into knowledge was a full custody/parse/store
            # rerun even though the source rows were already safely stored.
            # A plain (no from_stage) retry is UNCHANGED — still 'failed'-only.
            if run["status"] not in ("failed", "completed"):
                raise HTTPException(
                    409,
                    f"run {run_id!r} is {run['status']!r} — retry from_stage='knowledge' only allowed on a "
                    "terminal 'failed' or 'completed' run",
                )
            if run["status"] == "completed":
                sha256 = run.get("sha256")
                if sha256 is None:
                    raise HTTPException(
                        409,
                        f"run {run_id!r} is completed but has no sha256 recorded — cannot verify whether "
                        "the knowledge collection already has this artifact's doc",
                    )
                exists = await _knowledge_doc_exists_for_artifact(
                    str(run["workflow"]), resolve_knowledge(knowledge), sha256
                )
                if exists:
                    raise HTTPException(
                        409,
                        f"run {run_id!r}: a knowledge doc for sha256={sha256[:12]}... VERIFIABLY EXISTS in the "
                        "collection already — refusing from_stage='knowledge' on a completed run to avoid "
                        "inserting a duplicate. This path only reruns the knowledge stage when the doc is "
                        "provably missing (e.g. after a Milvus collection recreate); a query failure/unknown "
                        "result is treated as 'missing' (allow), never as 'exists' (block).",
                    )
            result = await _retry_from_knowledge(run_id, run)
            record_review_action(
                run_id,
                "retry",
                "Owner started a targeted retry from the knowledge stage.",
                replacement={"child_run_id": result["run_id"], "from_stage": "knowledge"},
            )
            return result

        if run["status"] != "failed":
            raise HTTPException(
                409,
                f"run {run_id!r} is {run['status']!r}, not failed — a full rerun is only allowed on a "
                'terminal-failed run (use {"from_stage": "knowledge"} to retry a completed run\'s '
                "knowledge stage instead)",
            )

        workflow = run["workflow"]
        domain = run["domain"]
        mode = run["mode"]
        custody_tier = run.get("custody_tier") or _DEFAULT_CUSTODY_TIER.get(workflow, "full")

        # PREFERRED path: read the pristine write-once blob back the same way
        # custody.py's ingest_artifact() wrote it (blob_root() / blob_key) —
        # the custody stage's typed output (ops.workflow_run_stage.output,
        # server/evidence/workflows.py's `_ledger_stage_output`) carries
        # blob_key for exactly this reason. FALLBACK (only if the blob isn't
        # there): the original upload's source_path, if that private temp
        # file still happens to exist (it's normally deleted by
        # `_execute_run`'s finally-block right after the parent run finishes,
        # so this fallback will rarely succeed in practice — it exists per
        # the task spec as a documented, less-preferred second attempt before
        # giving up with 410).
        custody_stage = next((s for s in run["stages"] if s["name"] == "custody"), None)
        blob_key = (custody_stage or {}).get("output", {}).get("blob_key") if custody_stage else None
        original_name = Path(run.get("source_name") or "retry-upload.bin").name

        tmpdir = Path(tempfile.mkdtemp(prefix="run-retry-"))
        tmp_path = tmpdir / original_name
        source_used: str | None = None

        if blob_key:
            blob_path = blob_root() / blob_key
            if blob_path.is_file():
                shutil.copyfile(blob_path, tmp_path)
                source_used = "blob"

        if source_used is None and run.get("source_path"):
            legacy_path = Path(run["source_path"])
            if legacy_path.is_file():
                shutil.copyfile(legacy_path, tmp_path)
                source_used = "source_path"

        if source_used is None:
            shutil.rmtree(tmpdir, ignore_errors=True)
            raise HTTPException(
                410,
                f"run {run_id!r}: neither the custody blob ({blob_key!r}) nor the original "
                f"source_path ({run.get('source_path')!r}) is still readable — cannot retry",
            )

        from server.evidence.workflows import WORKFLOW_STAGE_NAMES

        new_run_id = create_run(
            workflow=workflow,
            mode=mode,
            source_name=run.get("source_name"),
            source_path=str(tmp_path),
            domain=domain,
            parent_run_id=run_id,
            custody_tier=custody_tier,
            source_context=run.get("source_context") or {},
        )
        seed_stages(new_run_id, retry_stages)

        # Source identity/acquisition context is durable. A retry must replay it
        # exactly; dropping it can reclassify an acquired third-party export as
        # first-party and move the horizon boundary backwards.
        #
        # parent_run_id=run_id (C2.6): lets this new run's store step detect
        # "I just deduped AND my parent's knowledge stage failed" and
        # auto-route into knowledge-from-store instead of a silent no-op.
        asyncio.create_task(
            _execute_run(
                new_run_id,
                workflow,
                tmp_path,
                tmpdir,
                run.get("source_context") or {},
                domain,
                mode=mode,
                custody_tier=custody_tier,
                parent_run_id=run_id,
            )
        )

        record_review_action(
            run_id,
            "retry",
            "Owner started a full workflow retry.",
            replacement={"child_run_id": new_run_id, "from_stage": None},
        )
        return {"run_id": new_run_id, "parent_run_id": run_id}
