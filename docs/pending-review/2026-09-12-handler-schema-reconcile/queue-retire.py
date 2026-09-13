"""Reviewed orphan TEST queue retirement; default is an entirely read-only check.

Run inside the existing Platform API container. No sources are ingested or deleted.
--apply requires a fresh external Temporal Running=[] check and parent approval.
"""
from contextlib import contextmanager
import hashlib
import inspect
import json
import sys

from sqlalchemy import text
from server.api import run_routes
from server.evidence import run_ledger as ledger
from server.evidence.workflows import WORKFLOW_STAGE_NAMES

TARGETS = {
    "01a0978c-dae4-788e-ba66-cdc4f0346beb",
    "01a0978c-d9b5-7d92-9e21-a6f3c679e57a",
    "01a0978c-d903-75ec-9480-1fc6ab47ba24",
    "01a0978c-d856-7b29-9a62-4e91338a7a02",
    "01a0978c-d7be-72e7-9104-d3b9e3fc0705",
    "01a0978c-d709-77d2-b74e-d9fed0a29d40",
    "01a0978c-d658-79b5-9b23-6cf67cd6f977",
    "01a0978c-d5b5-73d4-84e4-fc3129fc72f5",
    "01a0978c-d504-7a07-9c9c-fdbbb7536b0b",
    "01a0978c-d449-75c1-8b23-90a3afb168bc",
    "01a0978c-d336-73c1-adb9-47fba9888eef",
    "01a0978c-cec7-738a-80d9-57418afaf219",
    "01a0977a-a418-744e-beef-bf41ecf171c1",
}
PARENTS = {"01a096c3-12a6-72ca-bfc5-85ad20db112f", "01a096c1-f9fd-7040-833e-daeeeae7ca5a"}
MATTER = "deadbeef-dead-beef-dead-beefdeadbeef"
REASON = (
    "Owner requested clear queue/start over. This TEST retry committed its ledger row "
    "then failed at WORKFLOW_STAGE_NAMES['framework-neutral-ingest'] before scheduling "
    "the runner. Zero stages, abort requested, and no running Temporal workflow were "
    "verified. Retired as failed/owner-aborted without retrying or changing parent receipts."
)


def fingerprint(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, default=str).encode()).hexdigest()


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def check_runs():
    rows = ledger.list_runs(500)
    require(len(rows) == 19, "Expected exactly 19 legacy ledger rows; scope drift")
    require({r['run_id'] for r in rows if r['status'] == 'running'} == TARGETS,
            "Running target set changed")
    full = {r['run_id']: ledger.get_run(r['run_id']) for r in rows}
    require(len([r for r in full.values() if r['status'] == 'failed']) == 6,
            "Original failed count changed")
    for rid in TARGETS:
        r = full[rid]
        c = r.get('source_context') or {}
        require(r['workflow'] == 'framework-neutral-ingest' and r['gate_state'] == 'abort',
                f"Workflow/gate drift: {rid}")
        require(r.get('parent_run_id') in PARENTS and full[r['parent_run_id']]['status'] == 'failed',
                f"Parent drift: {rid}")
        require(c.get('matter_id') == MATTER and c.get('source_identity', {}).get('test_only') is True,
                f"Not exact TEST scope: {rid}")
        require(not r['stages'] and not r.get('summary') and not r.get('error'),
                f"Execution/results appeared: {rid}")
    return full


def check_code():
    require('framework-neutral-ingest' not in WORKFLOW_STAGE_NAMES, "Registry changed; re-investigate orphan proof")
    source = inspect.getsource(run_routes)
    retry = source[source.index('async def retry_run('):]
    create = retry.index('new_run_id = create_run(')
    lookup = retry.index('seed_stages(new_run_id, WORKFLOW_STAGE_NAMES[workflow])')
    schedule = retry.index('asyncio.create_task(')
    require(create < lookup < schedule, "Retry scheduling code changed; re-investigate")


check_code()
if '--apply' not in sys.argv and '--dry-run' not in sys.argv:
    state = check_runs()
    print(json.dumps({'mode': 'read-only', 'targets': len(TARGETS), 'original_failed': 6,
                      'stages_in_targets': 0,
                      'preserved_failed_sha256': fingerprint({k:v for k,v in state.items() if k not in TARGETS})}))
    sys.exit(0)

# Reuse the existing ledger APIs, but bind their begin/connect scopes to one outer
# transaction. record_review_action's audit record already accepts that connection.
original_engine = ledger._get_engine()
with original_engine.begin() as connection:
    connection.execute(text("SET LOCAL lock_timeout='5s'"))
    connection.execute(text("SET LOCAL statement_timeout='30s'"))
    connection.execute(text("LOCK TABLE ops.workflow_run, ops.workflow_run_stage IN SHARE ROW EXCLUSIVE MODE"))

    class BoundEngine:
        @contextmanager
        def begin(self):
            yield connection

        @contextmanager
        def connect(self):
            yield connection

    ledger._engine = BoundEngine()
    try:
        before = check_runs()
        preserved = {k:v for k,v in before.items() if k not in TARGETS}
        for rid in sorted(TARGETS):
            ledger.record_review_action(rid, 'abort', REASON, actor='owner-authorized:queue-retirement',
                                        replacement={'status': 'failed', 'reason_code': 'orphaned_retry_owner_abort'})
            ledger.finish_run(rid, 'failed', summary={'retirement': 'orphaned_retry_owner_abort',
                              'no_runner_scheduled': True}, error=REASON)
        after = {rid:ledger.get_run(rid) for rid in before}
        require(preserved == {k:v for k,v in after.items() if k not in TARGETS},
                'Original failed receipts changed')
        for rid in TARGETS:
            require(after[rid]['status'] == 'failed' and not after[rid]['stages'], 'Retirement failed')
            unchanged = set(before[rid]) - {'status', 'summary', 'error', 'updated_at'}
            require(all(before[rid][k] == after[rid][k] for k in unchanged), 'Unexpected row mutation')
        result = {'targets_retired': len(TARGETS), 'preserved_failed': 6,
                  'preserved_failed_sha256': fingerprint(preserved), 'remaining_running': 0}
        if '--apply' not in sys.argv:
            connection.rollback()
    finally:
        ledger._engine = original_engine
if '--apply' not in sys.argv:
    require(check_runs() == before, 'Rollback did not restore the original run state')
print(json.dumps({'mode': 'committed' if '--apply' in sys.argv else 'rolled_back', **result}))
