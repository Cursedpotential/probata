"""Small worker primitives: persistent OS lock, bounded logs, append-only receipts.

No CocoIndex, model, database or source imports. Receipts describe worker execution,
not independently verified per-document CDC or embedding freshness.
"""
from __future__ import annotations

import json
import os
import pathlib
import subprocess
import threading
import uuid
from contextlib import contextmanager
from datetime import datetime, timezone

LOCK_MARKER = b'docstore-os-lock-v1\n'
MAX_LOG_BYTES = 4 * 1024 * 1024
STATUS_KIND = 'worker-current-status-v1'
MAX_STATUS_BYTES = 65536


class WorkerBusy(RuntimeError):
    pass


def _cdc_proven(payload: dict) -> bool:
    attribution = payload.get('cdc_attribution')
    return (payload.get('sync') == 'execution_finished'
            and isinstance(attribution, dict)
            and attribution.get('status') == 'verified'
            and attribution.get('missing_count') == 0
            and attribution.get('unexpected_count') == 0
            and attribution.get('hash_mismatch_count') == 0)


@contextmanager
def worker_lock(path: pathlib.Path):
    """Never steal an age-expired lock or unlink a lock another worker may own.

Legacy empty sentinel files require explicit reconciliation before activation.
All concurrently deployed writers must use this same locking protocol.
"""
    path.parent.mkdir(parents=True, exist_ok=True)
    try:
        with path.open('xb') as new:
            new.write(LOCK_MARKER)
            new.flush()
            os.fsync(new.fileno())
    except FileExistsError:
        pass
    with path.open('r+b') as handle:
        try:
            if os.name == 'nt':
                import msvcrt
                msvcrt.locking(handle.fileno(), msvcrt.LK_NBLCK, 1)
            else:
                import fcntl
                fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            raise WorkerBusy('Another worker owns the OS lock') from None
        try:
            if handle.read(len(LOCK_MARKER) + 1) != LOCK_MARKER:
                raise WorkerBusy('Legacy or unknown lock: explicit reconciliation required')
            yield
        finally:
            handle.seek(0)
            if os.name == 'nt':
                msvcrt.locking(handle.fileno(), msvcrt.LK_UNLCK, 1)
            else:
                fcntl.flock(handle.fileno(), fcntl.LOCK_UN)


def write_receipt(directory: pathlib.Path, run_id: str, sequence: int, payload: dict) -> pathlib.Path:
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / f'{run_id}-{sequence:03d}.json'
    record = {**payload, 'run_id':run_id, 'sequence':sequence,
              'at':datetime.now(timezone.utc).isoformat(), 'cdc_verified':_cdc_proven(payload),
              'receipt_kind':'worker-execution-v1'}
    with path.open('x', encoding='utf-8') as handle:
        json.dump(record, handle, ensure_ascii=False, sort_keys=True)
        handle.flush()
        os.fsync(handle.fileno())
    return path


def write_current_status(path: pathlib.Path, payload: dict) -> pathlib.Path:
    """Atomically replace the bounded operational status snapshot.

    Append-only receipts remain the audit trail.  This single file exists so a
    health probe does not have to enumerate an ever-growing receipt directory.
    """
    path.parent.mkdir(parents=True, exist_ok=True)
    record = {
        **payload,
        'status_kind': STATUS_KIND,
        'at': datetime.now(timezone.utc).isoformat(),
        'cdc_verified': _cdc_proven(payload),
    }
    encoded = json.dumps(record, ensure_ascii=False, sort_keys=True).encode('utf-8')
    if len(encoded) > MAX_STATUS_BYTES:
        raise ValueError('Worker status exceeds 64 KiB')
    temporary = path.with_name(f'.{path.name}.{uuid.uuid4().hex}.tmp')
    with temporary.open('xb') as handle:
        handle.write(encoded)
        handle.flush()
        os.fsync(handle.fileno())
    # A failed replace deliberately retains the uniquely named temporary file
    # for diagnosis; repository policy forbids this process from deleting it.
    os.replace(temporary, path)
    return path


def read_current_status(path: pathlib.Path) -> dict:
    """Read and validate the bounded current status without trusting its path."""
    info = path.stat()
    if path.is_symlink() or not path.is_file() or info.st_size > MAX_STATUS_BYTES:
        raise ValueError('Worker status path or size invalid')
    with path.open('rb') as handle:
        raw = handle.read(MAX_STATUS_BYTES + 1)
    if len(raw) > MAX_STATUS_BYTES:
        raise ValueError('Worker status grew beyond limit')
    value = json.loads(raw)
    if (not isinstance(value, dict) or value.get('status_kind') != STATUS_KIND
            or type(value.get('cdc_verified')) is not bool
            or value.get('sync') not in {'running', 'failed', 'degraded', 'cancelled', 'execution_finished'}
            or value.get('cdc_verified') != _cdc_proven(value)):
        raise ValueError('Worker status schema invalid')
    return value


def run_child(command: list[str], env: dict, timeout: int, log_path: pathlib.Path) -> dict:
    """Drain child output continuously with a bounded retained log, no RAM capture.

On timeout terminate only the child created here; never discover/kill other workers.
The caller receives diagnostics, not a claim that index writes were successful.
"""
    log_path.parent.mkdir(parents=True, exist_ok=True)
    counters = {'output_bytes':0, 'retained_bytes':0}
    failures = []
    with log_path.open('xb') as log:
        options = {'creationflags':subprocess.CREATE_NO_WINDOW} if os.name == 'nt' else {}
        process = subprocess.Popen(command, env=env, stdout=subprocess.PIPE,
                                   stderr=subprocess.STDOUT, **options)
        def drain():
            try:
                while block := process.stdout.read(65536):
                    counters['output_bytes'] += len(block)
                    keep = block[:max(0, MAX_LOG_BYTES-counters['retained_bytes'])]
                    log.write(keep)
                    counters['retained_bytes'] += len(keep)
            except Exception:
                failures.append('log_capture_failed')
        reader = threading.Thread(target=drain, daemon=True, name='docstore-log-drain')
        reader.start()
        timed_out = False
        try:
            process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            process.kill()
            process.wait(timeout=10)
        except BaseException:
            # Cancellation must not leave this invocation's child running.
            if process.poll() is None:
                process.kill()
                process.wait(timeout=10)
            raise
        finally:
            reader.join(timeout=10)
        if reader.is_alive():
            failures.append('log_capture_incomplete')
        else:
            process.stdout.close()
        log.flush()
        os.fsync(log.fileno())
    return {'exit_code':process.returncode,'timed_out':timed_out,'log_path':str(log_path),
            **counters,'log_truncated':counters['output_bytes']>MAX_LOG_BYTES,
            'diagnostic_errors':failures}
