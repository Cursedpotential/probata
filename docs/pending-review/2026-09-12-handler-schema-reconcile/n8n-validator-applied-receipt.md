# Dedicated parser validators — updated and published

Byline: Codex, 2026-09-13 UTC (2026-09-12 America/New_York).

Root explicitly authorized the exact two validator code changes and publication.
Executed reviewed `n8n-validator-update.ps1 -Apply` after fresh local contract tests:
**20 passed**, durable report `tests/_reports/pytest-20260913T032303145118Z-1fa21d58.json`.
Shell exit **0**; both workflows reported `updated-and-published`.

| Workflow ID | Changed node ID | Prior active version | Verified new draft = active version |
|---|---|---|---|
| fvKS2gcsRUdEKUun | 7a5ab1a0-1c9c-4c0e-8ae6-000000000103 | 3870c5fc-d036-4868-887f-8f2fe90cd7a0 | cedd6a11-244b-4d12-a320-1e3645fd9394 |
| YQoFBykpZoDrU0n6 | 7a5ab1a0-1c9c-4c0e-8ae6-000000000203 | a839c59b-a0ad-4504-b412-538c925db703 | acc0a46a-9467-4ce0-b586-98d90e834e93 |

Only each `Validate + Shape StageRequest` node's `parameters.jsCode` changed,
copied exactly from its local wrapper JSON. Existing base-three refs remain accepted;
the alternative is base-three plus all six handler refs. Partial handler sets remain
rejected. No handler decision, parsing, or evidence promotion logic moved into n8n.

Immediately before each PUT the complete fetched workflow fingerprint matched its
original read. After PUT and publication, exact editable-payload fingerprints matched
the intended payload: workflow names, every other node parameter, node IDs, credential
references, HTTP URLs, connections, settings and staticData were preserved. Both remained
active=true, and each activeVersionId exactly equaled its newly returned versionId.
There were no ambiguous responses or retry attempts.

## Before/after provenance

Hashes below use SHA-256 of UTF-8 compressed PowerShell JSON serialization. Code hashes
therefore hash the JSON string representation, not unquoted raw JavaScript bytes.

| Item | SHA-256 |
|---|---|
| Select prior full workflow | 26067C5DF3B425F7718580189FC8FE6CFC7FD8BE309E8D1A49A1C68F9C1A74FA |
| Select prior validator | 651D0C752B0EBF3B1B5B17D469C2E8A1B32BD1336EA44B422CD7CDDDEC658B04 |
| Select published validator | FF10F43DAE8D80ADD97E26BD98DBA39565DAD288C448E057FB0559A13202E146 |
| Execute prior full workflow | 00CDB456381BFE7794F7B501854C05CF31126F76BF2FE76C5B1DB20AFFF50BA5 |
| Execute prior validator | 30EFF3975BCD8726EB89BB0BC148BEC8581C71C49DEE86729A4686CD00B6470A |
| Execute published validator | AF32457642C8D24DF48536328A33E3D712A952137610075BC5728E038D6362FB |

Rollback provenance is the prior native workflow version ID in the table above. Any
rollback requires fresh read/fingerprint and approval, and must restore only this code
field from that version while preserving subsequent unrelated edits; do not blindly
restore the whole old workflow. Prepared script intentionally rejects re-execution
against the now-new versions.

## Verification boundary

This proves successful live validator publication and exact read-back, not successful
parser/ingest execution. No webhook or workflow was triggered; no ingestion, database
mutation, generic-flow activation, or application deployment was performed by this lane.
Repair wrappers were not modified. Secrets were neither printed nor persisted.

This receipt supersedes the earlier read-only finding that the two validators were
still old; that earlier receipt remains accurate for its inspection time.
