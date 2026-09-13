# Exact legacy TEST queue retirement — applied by root

Byline: Codex, 2026-09-12. Scope: `queue-*` files only; no implementation changes.

## Applied result

Root subsequently executed the reviewed exact `--apply` command successfully.
Root reported Temporal Running=`[]` before and after, and preserved-six-failure
fingerprint `4e0da7342096cfc162fe1b9ba54a1ac491871b40e3e4722c3bdfc1c1eea0f4c6`.
This lane independently re-queried the public API after root execution: **six original
failed rows + 13 failed/abort rows; zero running rows**. No new ingest was started.
The preparation/dry-run account below remains historical and is not an unexecuted
queue action. Do not rerun the script: it intentionally rejects the now-terminal set.

## Cause verified against live code and logs

`server/api/run_routes.py:755` imports the legacy stage map, commits a new
`ops.workflow_run` through `create_run`, then evaluates
`WORKFLOW_STAGE_NAMES[workflow]` at line 767 **before** reaching
`asyncio.create_task` at line 775. The deployed map has only `chat-transcript` and
`sms-xml`, not `framework-neutral-ingest`.

Live Platform API logs show repeated retry HTTP 500 responses, the exact failing
`seed_stages(new_run_id, WORKFLOW_STAGE_NAMES[workflow])` line and
`KeyError: 'framework-neutral-ingest'`. Therefore the 13 retry child ledger rows were
committed without ever scheduling their runners. The abort endpoint only sets a gate
and appends an owner review action; with no runner there is nobody to finish the run.
No parser/engine changes or new ingest run were made during this investigation.

Read-only portal and container queries agreed: 19 legacy rows, six failed parents/originals
and 13 running/abort children, all children zero stages. Exact TEST scope is
`source_context.matter_id=deadbeef-dead-beef-dead-beefdeadbeef` and
`source_context.source_identity.test_only=true` (not top-level test_only).
The 13 IDs are pinned in `queue-retire.py`, not dynamically expanded.

Live Temporal default-namespace Running query returned `[]` using endpoint
`192.168.176.3:7233` inside temporal-server. This supplements the code/log proof;
Temporal absence alone would not prove Python asyncio tasks absent.

## Safe retirement proof

Default script mode is read-only. `--dry-run` invokes the existing
`record_review_action` and `finish_run` APIs on one shared SQLAlchemy connection inside
an outer transaction, then explicitly rolls back. A bounded table lock blocks concurrent
run/stage writes during verification. All 19 original run+stage objects are compared
after rollback. `--apply` is the only commit mode.

Actual container results, exit 0:

```json
{"mode":"read-only","targets":13,"original_failed":6,"stages_in_targets":0,"preserved_failed_sha256":"4e0da7342096cfc162fe1b9ba54a1ac491871b40e3e4722c3bdfc1c1eea0f4c6"}
{"mode":"rolled_back","targets_retired":13,"preserved_failed":6,"preserved_failed_sha256":"4e0da7342096cfc162fe1b9ba54a1ac491871b40e3e4722c3bdfc1c1eea0f4c6","remaining_running":0}
```

The `remaining_running:0` value describes the in-transaction dry-run state only;
the script verified restoration of all original rows after rollback. No retirement
has been committed by this lane. Parent reviewed and approved exact retirement and
will execute the apply command separately.

`finish_run` changes only status/summary/error/updated_at for these empty orphan rows;
SHA-256 and artifact IDs are COALESCE-preserved. Script explicitly compares every other
field and the original six failed rows. One `abort` review action per target invokes
the canonical audit writer on that same transaction. No source file is read, moved,
or deleted; no parent failed result is overwritten. Rolled-back audit inserts may
consume sequence numbers, which PostgreSQL does not roll back; no rows persist.

## Execution commands

Working directory:
`E:\AI_Workspace\Projects\_worktrees\probata-duckdb-live-test`.

Recheck Temporal before applying; the trailing shell comment absorbs PowerShell CRLF:

```powershell
@'
sudo docker exec temporal-server-llv5zt8phx1xf4devwqugk3y-121445595884 temporal --address 192.168.176.3:7233 workflow list --namespace default --query "ExecutionStatus='Running'" --output json #
'@ | ssh ovh-files-ts sh
```

Read-only command verified through UV in the actual API container. The deployed
interpreter is `/usr/local/bin/python`; UV is `/usr/local/bin/uv`. No new environment,
dependency installation, credentials printing, or workstation runtime is needed.

```powershell
Get-Content docs/pending-review/2026-09-12-handler-schema-reconcile/queue-retire.py -Raw | ssh ovh-app "sudo docker exec -i platform-api-rz41wqhpjfh1rj796ixvjhfs-153307801540 uv run --no-project --python /usr/local/bin/python python -"
```

Parent-reviewed exact apply command:

```powershell
Get-Content docs/pending-review/2026-09-12-handler-schema-reconcile/queue-retire.py -Raw | ssh ovh-app "sudo docker exec -i platform-api-rz41wqhpjfh1rj796ixvjhfs-153307801540 uv run --no-project --python /usr/local/bin/python python - --apply"
if ($LASTEXITCODE -ne 0) { throw 'Retirement did not report success; inspect state before retry' }
```

After success verify `/api/runs?limit=500` has no running rows, 19 failed historical
rows, and unchanged six original failures. Expected script output includes mode
`committed`. This is not deletion of history: the queue becomes empty because its
orphan entries are truthfully terminal, with an audit explanation. It does not fix
the legacy retry route; that requires the independent caller/engine repair.
