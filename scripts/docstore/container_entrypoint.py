"""PID-1 supervisor for the Docstore API and one startup synchronization pass.

The API stays available for diagnosis when the sync fails.  The durable current
status and append-only receipts make that failure observable; this supervisor
does not retry, schedule, or start any additional indexing pass.
"""
from __future__ import annotations

import os
import pathlib
import signal
import subprocess
import sys
import time

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from run_support import read_current_status, write_current_status

STATUS = pathlib.Path(os.environ.get('DOCSTORE_RUN_STATUS', '/data/state/latest-run.json'))


def _stop(child: subprocess.Popen | None) -> None:
    if child is not None and child.poll() is None:
        child.terminate()


def main() -> int:
    api: subprocess.Popen | None = None
    worker: subprocess.Popen | None = None
    stopping = False

    def request_stop(_signum, _frame):
        nonlocal stopping
        stopping = True
        _stop(worker)
        _stop(api)

    signal.signal(signal.SIGTERM, request_stop)
    signal.signal(signal.SIGINT, request_stop)
    api = subprocess.Popen([
        sys.executable, '-m', 'uvicorn', '--app-dir', str(HERE), 'api:app',
        '--host', '0.0.0.0', '--port', '8000',
    ])
    try:
        write_current_status(STATUS, {
            'sync': 'running', 'run_id': 'startup-pending',
            'reason': 'Startup worker launch pending',
        })
        try:
            worker = subprocess.Popen([sys.executable, str(HERE / 'worker_sync.py')])
        except OSError as exc:
            write_current_status(STATUS, {
                'sync': 'failed', 'error_type': type(exc).__name__,
                'reason': 'Startup worker could not be launched',
            })

        while api.poll() is None and not stopping:
            if worker is not None and worker.poll() is None:
                time.sleep(0.25)
                continue
            if worker is not None and worker.returncode:
                try:
                    current = read_current_status(STATUS)
                except (OSError, ValueError, TypeError):
                    current = {'sync': 'invalid'}
                if current.get('sync') == 'running':
                    write_current_status(STATUS, {
                        'sync': 'failed', 'error_type': 'WorkerExit',
                        'reason': 'Startup worker exited without a terminal status',
                        'worker_exit_code': worker.returncode,
                    })
            worker = None
            return api.wait()
        return api.returncode if api.returncode is not None else 0
    finally:
        _stop(worker)
        _stop(api)
        for child in (worker, api):
            if child is not None and child.poll() is None:
                try:
                    child.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    child.kill()
                    child.wait(timeout=10)


if __name__ == '__main__':
    raise SystemExit(main())
