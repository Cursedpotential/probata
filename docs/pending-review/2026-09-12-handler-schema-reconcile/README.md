# Handler schema reconciliation — applied by root

Byline: Codex, 2026-09-12.

## Applied schema receipt

Root executed the reviewed recovery-adjusted SQL and observed COMMIT with
PRESERVATION OK: 43 existing context tables, 208 rows and matching fingerprints.
This lane independently queried the live catalog after that commit: **six PKs,
18 FKs, seven UNIQUE constraints**, and preview receipt CHECK includes both
`custody` and `raw_source_verification`. Tested/applied snapshot hash is
`6CFBE90CB19920AA1584F526BAF7369A9E96FD4AF5572E0CB0D6B09C4B9D2674`.
Do not rerun reconciliation: its absent-table preflight will intentionally reject
the now-applied target. Earlier preparation/dry-run sections below are historical.

## Dedicated n8n wrapper read-only inspection after schema apply

Used n8n tooling guidance for inspection only; no workflows activated, edited, or run.
Worker `proffer-worker-d24bb9eoo47qtw9eq1xc6u64-202026998416` has
`N8N_PROFFER_BASE_URL=http://100.91.190.107:5678/webhook`.
Read-only n8n Public API requests succeeded, with secrets parsed locally and never
printed. Actual dedicated wrappers are active, with versionId=activeVersionId:

| Wrapper | Workflow ID | Active version | Webhook suffix |
|---|---|---|---|
| Select parser | fvKS2gcsRUdEKUun | 3870c5fc-d036-4868-887f-8f2fe90cd7a0 | proffer/select-parser-activity |
| Execute parser | YQoFBykpZoDrU0n6 | a839c59b-a0ad-4504-b412-538c925db703 | proffer/execute-parser-activity |
| Assess repair | 6TMn03Jq8WSxt9iY | c7a832fc-c81f-4eb9-8c9d-e8103f065e2e | proffer/assess-source-repair-activity |
| Resolve repair | cu7y91jsOVfBBWJC | 53ae56c7-0ba5-488e-91b3-6fc19c6330ba | proffer/resolve-source-repair-activity |

All target `http://100.91.190.107:8090/activities/<activity_name>` through their
HTTP nodes. Thus missing generic Flow bindings does not mean the dedicated seam
is absent. This inspection does not assert generic bindings exist.

**Deployment blocker:** live select/execute request validators still require exactly
three refs. Select requires filesystem_metadata/container_manifest/metadata_manifest;
execute requires parser_selection/original/parser_options. Both reject any additional
keys. Neither accepts the six content-backed handler refs:
handler_recommendation, handler_decision, handler_validation, detected_format,
content_signature, handler_compatibility.

Local wrapper JSON and Go client support exactly base-three OR base-three plus all six.
Therefore targeted validator-code updates on the existing two workflow IDs are needed
before new engine requests will pass. Select does not require original in its base set;
that is consistent with the current client and not a defect. Preserve existing credentials,
URLs, IDs, and unrelated workflow settings. Root was informed; no update executed here.

## Scope and authority

Parent-task instruction authorizes an additive reconciliation only, explicitly forbidding
rebuild, truncate, erasure, and mutation of current context/run data. This one-off reviewed
reconciliation is not a numbered migration. Current `sql/bootstrap/README.md` and that
instruction override stale numbered-migration instructions in SQL memory and the
platform-postgres-migrations skill. Canonical snapshot editing belongs to the engine agent;
this lane did not edit it. Engine agent confirmed the existing six handler tables and
expanded detected-format CHECK are the required schema.

Recovery adjustment: remove the canonical `handler_recommendation_signature_key`
UNIQUE constraint from the **new table definition**, permitting a separate immutable
recommendation after a failed attempt for the same signature. Activity-receipt uniqueness
and compatibility identity uniqueness remain. The reconciliation now expects exactly
31 ALTER statements and seven UNIQUE constraints. Since live target tables are absent,
no live constraint removal or row rewrite is needed for this adjustment.

`reconcile.ps1` emits SQL without connecting or writing files. Default output ends in
ROLLBACK. Explicit `-Apply` changes only the terminator to COMMIT. No COMMIT has been run
by this lane, and no Git commit was made.

## Recovery-adjusted repeat — ready for root apply

After engine-owned removal of signature uniqueness, all **13 static assertions passed**.
Repeat live dry-run exited 0 and explicitly ROLLED BACK. Verified exactly six PKs,
18 validated FKs, **seven UNIQUE constraints**, and absence of the recovery-blocking
signature constraint. All 43 existing context tables / 208 rows retained the exact
counts and fingerprints recorded below. Independent post-rollback catalog check again
showed zero handler tables and the original custody receipt CHECK.

Recovery-adjusted tested snapshot SHA-256:
`6CFBE90CB19920AA1584F526BAF7369A9E96FD4AF5572E0CB0D6B09C4B9D2674`.

No COMMIT was executed by this lane. The apply command below is unchanged. New ingest
remains frozen pending the parent's deployment and verification decision.

## Initial verified live dry-run (before recovery adjustment)

Target: `ovh-files-ts`, container
`probata-db-w10gg3an43jvry4y79n6sxi1-122959880896`, database `platform`, role `ai`.

Snapshot SHA-256:
`82B718730D25FFFE26CB4761CA80FFF113298CE4A8C5B869D446475B2BF4A478`.

Observed successful SQL execution, exit 0, ending in ROLLBACK:

- Initial dry-run: six snapshot-derived handler tables, six PKs, 18 validated FKs,
  eight UNIQUE constraints. The recovery-adjusted repeat is recorded below separately.
- All inline CHECK/NOT NULL/default definitions extracted with the table definitions.
- Eighteen canonical table grants plus two canonical function grants.
- Existing `context.forbid_mutation()` body matches canonical after whitespace removal;
  existing function is not replaced. If absent, the canonical definition is created.
- Existing receipt CHECK expanded to allow `raw_source_verification` **and retain
  `custody`**, preserving old failed-run history rather than rewriting it.
- Every preexisting context table locked in SHARE mode, counted and SHA-256 fingerprinted
  before and after DDL: **PRESERVATION OK, 43 tables, 208 rows**.
- All 12 local script contract assertions passed (`test-reconcile.ps1`).
- Follow-up live query after rollback: **zero handler tables**, original six-value
  custody receipt CHECK unchanged, **11 source versions**, **53 activity receipts**.

The parent initially observed 10/50 source-version/receipt rows. They were 11/53 by this
dry-run, so the script correctly used the newest live rows rather than hardcoding stale
counts. Other schemas are not altered. This does not prove application deployment or
successful ingestion; it proves this DDL can be applied without changing existing context
rows at the tested catalog state.

## Preservation fingerprints from dry-run

Algorithm: each row is `SHA256(UTF8(to_jsonb(row)::text))`, represented as hex; sort those
hashes, concatenate, SHA-256 the UTF-8 concatenation. Multiplicity is preserved. This is
an operational preservation check, **not an evidence/custody hash**. No row contents were
printed or moved off-server. All tables below use schema `context`.

| Relation | Rows | SHA-256 |
|---|---:|---|
| activity_execution | 53 | 99f3e1eaf36af2aabd7f82a725e13f97b56a0ff63239e0c02fc1184a7af19508 |
| activity_receipt | 53 | 78db07882b2d3b09096b4d515e4ac54eef39510f240b157fe719d71d3c08eb3c |
| hash_batch | 4 | 57afb1d54f8508710ca8d916c41dc68940ede9f404b7617838005e8d0ef6a368 |
| hash_batch_member | 4 | 1b04d91a9cc56a799af5e0c7ae2ef28efb8f1a81db12eb4ea8f56baf48ce6337 |
| hash_receipt | 4 | 979c576a82ad0768739b3be5cbbc92aa1c68fb987e15b544855449f2e50401a3 |
| proffer_preview_binding | 11 | 997e8c0018fee8521f7ff84a508241bdc310a1a171aaca2c86f9f86fc3196f51 |
| proffer_preview_event | 11 | f1e646f2163816984167cf0749ba548f18493d349c425c27648e4ab84c94a35e |
| proffer_source_context_revision | 5 | 4c72497ee5620cd88b4345f02c1a16986ffab49c3d24637938f9665baf56f57e |
| repair_assessment | 6 | 44f0d7050dab72440dfe8701a646cb330dcea7eeaf7b6c61b304422702cf95ae |
| repair_decision | 4 | 7d441fc4a8b4d122a433887cde2ef96b53518155091f0c7f821507ea8cafaae5 |
| repair_resolution | 4 | de26a2162bd5e92825dc92ac34cbc8ec4d0a0990e2d863af7715e5794d548a57 |
| retained_object | 10 | 923e062640671e56003b2719cbc277bbbbcf5946be505f17407aa463529c3bb6 |
| source | 11 | 32d011c5cdddc6c16a92fae1a9b91cbfc94cb4ad2cdfdcb07858fb7774a682fb |
| source_metadata | 4 | 59209d0be2e835e9b3a513c56ab59aa51e429612241fda103714fb16d3004714 |
| source_version | 11 | c06b7f35e41ae7566cfbec87842408307efe1db44c3e85e933cc941a05af7871 |
| source_version_object | 13 | 3578938507c48bad516d64605492a84102129559b60f0fe292c3eb44485df271 |

The remaining 27 context tables were empty; all had SHA-256
`e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`.

## Exact commands

Run from the surviving worktree in PowerShell with no profile. Recheck the live container
identity if a deployment has replaced it. Review emitted SQL and re-run dry-run if the
snapshot changes. The script stops before output if extraction coverage differs.

```powershell
& ./docs/pending-review/2026-09-12-handler-schema-reconcile/test-reconcile.ps1
$schemaSql = & ./docs/pending-review/2026-09-12-handler-schema-reconcile/reconcile.ps1
if (!$?) { throw 'Schema SQL generation failed' }
$schemaSql | ssh ovh-files-ts "sudo docker exec -i probata-db-w10gg3an43jvry4y79n6sxi1-122959880896 psql -X -U ai -d platform -v ON_ERROR_STOP=1"
if ($LASTEXITCODE -ne 0) { throw 'Schema dry-run failed' }
```

**Only after parent review**, exact apply command:

```powershell
$schemaSql = & ./docs/pending-review/2026-09-12-handler-schema-reconcile/reconcile.ps1 -Apply
if (!$?) { throw 'Schema SQL generation failed' }
$schemaSql | ssh ovh-files-ts "sudo docker exec -i probata-db-w10gg3an43jvry4y79n6sxi1-122959880896 psql -X -U ai -d platform -v ON_ERROR_STOP=1"
if ($LASTEXITCODE -ne 0) { throw 'Schema application failed; inspect catalog before any retry' }
```

Expected output: `PRESERVATION OK` with current counts, catalog constraint counts,
then `COMMIT`. The script deliberately fails if any target table already exists,
including after a successful apply. This prevents overwriting unseen partial deployments;
it is **not silently idempotent**. Transactional errors rollback automatically when psql
exits. A network ambiguity requires read-only catalog verification, never a blind retry.

Locks are bounded by 5 seconds and statements by 90 seconds; concurrent ingestion may
briefly wait or cause a fail-closed timeout. The only removed schema object is the receipt
CHECK, recreated in the same transaction as a strict superset. No tables, files, or rows
are deleted. No rebuild or host/service restart is involved.
