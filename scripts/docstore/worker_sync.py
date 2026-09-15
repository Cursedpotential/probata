"""worker_sync - one sync pass for the cloud docstore: incremental ingest -> graph rebuild -> health.

Byline: Claude Code - Opus 5 - 2026-09-10

Owner orders 2026-09-10: run on the server on a cron; use CocoIndex change detection ("the whole point
of ccc") so only changed files re-index; every re-index updates the database.

Runs at container start (each deploy of a docs change is the change event) and from the Coolify
scheduled task. Always FULL scope: CocoIndex deletes whatever a run does not declare, so a partial
run would wipe documents (SETUP.md GOTCHA 9). Change detection keeps a full run cheap.
A lock file prevents overlapping runs. Prints one compact summary line; non-zero exit on failure.
"""
from __future__ import annotations

import asyncio
import json
import os
import pathlib
import signal
import sys
import time
import uuid

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from run_support import WorkerBusy, worker_lock, write_current_status, write_receipt, run_child
from cdc_verify import retire_unexpected_projection, snapshot_sources, verify_projection
from docs_lint import lint_summary_from_env


class WorkerCancelled(RuntimeError):
    pass

LOCK = pathlib.Path(os.environ.get("DOCSTORE_SYNC_LOCK",
    str(HERE.parents[1] / '.docstore/sync.lock') if os.name == 'nt' else "/data/state/sync.lock"))
RECEIPTS = pathlib.Path(os.environ.get('DOCSTORE_RUN_RECEIPTS', str(LOCK.parent / 'runs')))
STATUS = pathlib.Path(os.environ.get('DOCSTORE_RUN_STATUS', str(LOCK.parent / 'latest-run.json')))


def _rows(r):
    while isinstance(r, list) and len(r) == 1 and isinstance(r[0], list):
        r = r[0]
    return r if isinstance(r, list) else ([r] if r else [])


def _status_payload(summary: dict, run_id: str) -> dict:
    """write_receipt() has no size limit (one JSON file per sequence step), but
    write_current_status() enforces a hard 64 KiB ceiling on the whole payload --
    and lint's own findings[:200] alone serialises to ~38 KB on this corpus
    (measured 2026-09-14 against the live 6-root registry). Left uncapped here,
    a busy summary (ingest log path, health stats, cdc_attribution samples) could
    push the combined status over 64 KiB and make write_current_status() raise
    from inside _sync()'s `finally` block, replacing the real sync outcome with a
    cryptic size error. The receipt keeps the full findings[:200]; the live
    status gets a small, safely-bounded view of the same lint result."""
    payload = {**summary, 'run_id': run_id}
    lint = payload.get('lint')
    if isinstance(lint, dict):
        trimmed = dict(lint)
        full_findings = lint.get('findings') or []
        trimmed['findings'] = full_findings[:20]
        trimmed['findings_truncated'] = bool(lint.get('findings_truncated')) or len(full_findings) > 20
        trimmed['largest_files'] = (lint.get('largest_files') or [])[:5]
        payload['lint'] = trimmed
    return payload


def _run(script: str, timeout: int, log_path: pathlib.Path) -> dict:
    return run_child([sys.executable, str(HERE / script)], dict(os.environ), timeout, log_path)


async def _health() -> dict:
    import sq
    db = await sq.connect("docs", "probata", "docs")
    try:
        out = {}
        for table in ("document", "chunk", "links_to", "cites"):
            r = _rows(await db.query(f"SELECT count() AS n FROM {table} GROUP ALL;"))
            out[table] = r[0]["n"] if r and isinstance(r[0], dict) else 0
        idx = _rows(await db.query("INFO FOR INDEX chunk_embedding ON chunk;"))
        out["hnsw"] = (idx[0] if idx else {}).get("building", {}).get("status")
        orphans = _rows(await db.query("SELECT count() AS n FROM chunk WHERE array::len(->chunk_of->document) = 0 GROUP ALL;"))
        out["orphan_chunks"] = orphans[0]["n"] if orphans and isinstance(orphans[0], dict) else 0
        return out
    finally:
        await db.close()


def main() -> int:
    if os.environ.get('DOCSTORE_ONLY_FILES', '').strip():
        print(json.dumps({'sync':'rejected','reason':'Partial source filters can retire unselected documents; no worker started'}))
        return 2
    try:
        def cancel(_signum, _frame):
            raise WorkerCancelled("Cancellation requested")
        signal.signal(signal.SIGTERM, cancel)
        signal.signal(signal.SIGINT, cancel)
        with worker_lock(LOCK):
            return _sync()
    except WorkerBusy as exc:
        print(json.dumps({'sync':'skipped','reason':str(exc)}))
        return 2
    except WorkerCancelled:
        print(json.dumps({'sync':'cancelled','reason':'Cancellation requested'}))
        return 3
    except Exception as exc:
        print(json.dumps({'sync':'failed','error_type':type(exc).__name__,
                          'reason':'Worker/receipt failure; inspect retained run events'}))
        return 1


def _sync() -> int:
    t0 = time.time()
    requested_run_id = os.environ.get('DOCSTORE_RUN_ID', '').strip()
    if requested_run_id and (len(requested_run_id) != 32 or any(c not in '0123456789abcdef' for c in requested_run_id)):
        raise ValueError('DOCSTORE_RUN_ID must be 32 lowercase hexadecimal characters')
    run_id = requested_run_id or uuid.uuid4().hex
    requested_paths = tuple(filter(None, os.environ.get('DOCSTORE_REQUESTED_PATHS', '').split('\n')))
    full_reprocess = os.environ.get('DOCSTORE_FULL_REPROCESS', '').strip() == '1'
    rebuild_tracking = os.environ.get('DOCSTORE_REBUILD_TRACKING', '').strip() == '1'
    source_snapshot, source_digest = snapshot_sources()
    source_paths = {row.source_path for row in source_snapshot}
    if requested_paths and (len(requested_paths) > 20 or len(set(requested_paths)) != len(requested_paths)
                            or any(path not in source_paths for path in requested_paths)):
        raise ValueError('Selected paths are not a bounded subset of the complete source snapshot')
    summary: dict = {'sync':'running', 'app':'ProbataDocStore',
                     'environment':'probata-docstore', 'source_scope':'full',
                     'worker_pid':os.getpid(),
                     'requested_scope':'selected' if requested_paths else 'full',
                     'requested_paths':list(requested_paths),
                     'full_reprocess':full_reprocess,
                     'tracking_rebuild':rebuild_tracking,
                     'source_count':len(source_snapshot), 'source_digest_before':source_digest,
                     'cdc_verified':False}
    # Lint findings are recorded, never fatal: the flow already skips empties and
    # fails closed on hash collisions on its own. This is so a degraded/failed run's
    # receipt can explain WHY (e.g. an ENC001/DUP001 the flow's own guards then hit)
    # without a second pass over the source tree.
    summary['lint'] = lint_summary_from_env()
    sequence = 0
    def record():
        nonlocal sequence
        path = write_receipt(RECEIPTS, run_id, sequence, summary)
        sequence += 1
        return path
    record()  # A durable start is required before any child is launched.
    try:
        # The current status must also be durable before expensive work begins.
        write_current_status(STATUS, _status_payload(summary, run_id))
        if rebuild_tracking:
            state_db = pathlib.Path(os.environ.get('DOCSTORE_COCOINDEX_DB', '')).resolve(strict=False)
            if not state_db.is_absolute() or state_db.parent != STATUS.parent.resolve(strict=False):
                raise RuntimeError('Tracking rebuild requires the dedicated worker state directory')
            quarantine = state_db.parent / 'to_be_deleted' / f'cocoindex-tracking-{run_id}'
            quarantine.mkdir(parents=True, exist_ok=False)
            moved = []
            for candidate in (state_db, pathlib.Path(str(state_db) + '-wal'), pathlib.Path(str(state_db) + '-shm')):
                if candidate.exists():
                    destination = quarantine / candidate.name
                    os.replace(candidate, destination)
                    moved.append(str(destination))
            summary['tracking_state_quarantined'] = bool(moved)
            summary['tracking_quarantine_path'] = str(quarantine)
            record()
        # Ingest ceiling is env-configurable (Claude Code · Fable 5.1 · 2026-09-14): the first
        # multi-root run embeds ~470 new documents at ~4/min on NVIDIA NIM and cannot finish
        # inside the old fixed 3600 s. Default unchanged.
        ingest_timeout = int(os.environ.get('DOCSTORE_INGEST_TIMEOUT_S', '3600'))
        for stage, script, timeout in [('ingest','flow_docs.py',ingest_timeout)]:
            result = _run(script, timeout, RECEIPTS / f'{run_id}-{stage}.log')
            summary[stage] = result
            if result['exit_code'] != 0 or result['timed_out'] or result['diagnostic_errors']:
                summary['sync'] = 'failed'
                return 1
            record()
        if rebuild_tracking:
            summary['projection_retirement'] = asyncio.run(retire_unexpected_projection(source_snapshot))
            record()
        for stage, script, timeout in [('graph','graph_build.py',900)]:
            result = _run(script, timeout, RECEIPTS / f'{run_id}-{stage}.log')
            summary[stage] = result
            if result['exit_code'] != 0 or result['timed_out'] or result['diagnostic_errors']:
                summary['sync'] = 'failed'
                return 1
            record()
        after_snapshot, after_digest = snapshot_sources()
        summary['source_digest_after'] = after_digest
        if after_digest != source_digest:
            summary['sync'] = 'degraded'
            summary['error_type'] = 'SourceChangedDuringRun'
            return 1
        summary["health"] = asyncio.run(_bounded_health())
        if summary["health"].get("hnsw") != "ready" or summary["health"].get("orphan_chunks"):
            summary["sync"] = "degraded"
            return 1
        summary['cdc_attribution'] = asyncio.run(verify_projection(after_snapshot))
        if summary['cdc_attribution'].get('status') != 'verified':
            summary['sync'] = 'degraded'
            return 1
        summary['sync'] = 'execution_finished'
        return 0
    except BaseException as exc:
        summary['sync'] = 'cancelled' if isinstance(exc, WorkerCancelled) else 'failed'
        summary['error_type'] = type(exc).__name__
        raise
    finally:
        summary["seconds"] = round(time.time() - t0)
        summary['receipt_path'] = str(record())
        write_current_status(STATUS, _status_payload(summary, run_id))
        print(json.dumps(summary, default=str))


async def _bounded_health() -> dict:
    return await asyncio.wait_for(_health(), timeout=60)


if __name__ == "__main__":
    raise SystemExit(main())
