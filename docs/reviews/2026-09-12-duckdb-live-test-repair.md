# DuckDB live-test repair receipt

> Byline: Codex · GPT-5 · 2026-09-12
> Status: implementation and local integration verification complete on `codex/duckdb-live-test-20260912`; deployment and end-to-end post-deploy proof pending
> Scope: observed synthetic failures plus the verified real-source rehearsal manifest below. Nothing in this receipt is an evidence promotion or an approval to promote.

## Result

The canonical schema snapshot now defines `context.forbid_mutation()` before the trigger-creating helper that references it, and grants execution to `context_import_writer` and `platform_app`. The omission had blocked raw-generation persistence in the observed ChatGPT test run even though the function was already restored on the live database during incident response.

This file records the observed 2026-09-12 test checkpoint. It does not supersede later run receipts or claim the state of workflows after a subsequent repair or replay.

## Controlling DuckDB rule and implementation boundary

- DuckDB is the primary extraction path for every registered signature it can process. A Go decoder is registered only for signatures DuckDB cannot process, or is selected after a logged DuckDB failure. Exactly one selected handler lands a source; a source must never land raw through both paths.
- DuckDB output must enter the same raw contract and then traverse the same normalize, lineage, digest, verification, preview, and publication gates as parser output.
- The repaired structured-ELT path now supports content-confirmed SMS Backup & Restore XML, official ChatGPT conversation JSON, iMessage transcript text, CSV, and newline-delimited JSON. Each DuckDB template emits the standard immutable parser-bundle contract; none inserts directly into a canonical raw table. SMS XML loads and verifies Webbed on the same leased PostgreSQL session used for `read_xml`.
- Under the current governed stage graph, DuckDB replaces only `execute_parser_activity` and must emit the same durable raw-bundle reference and successful stage receipt. `persist_raw_generation_activity` remains the sole canonical writer of `context.raw_generation` and its raw-record identities. Direct DuckDB creation of a canonical raw generation would bypass the persistence receipt required by downstream hashing/reconciliation and by the preview publication contract.

Source anchors:

- `docs/planning/2026-09-03-ingest-redesign-plan-and-sequential-guide.md:53-90`
- `docs/handoffs/HANDOFF-2026-09-06-ingest-rulings-and-parser-fix.md:35-41`
- `docs/reviews/2026-09-06-webbed-install.md:13-26`
- `modules/engine/activities/elt_structured.go:18-68`
- `modules/engine/postgres/elt_structured_repository.go:1-18,101-198,234-248`

## Observed synthetic live-test inputs and workflow checkpoints

All three sources were uploaded under the sanctioned synthetic test prefix:

| Test source | R2 locator | Temporal run | Observed checkpoint |
|---|---|---|---|
| SMS Backup & Restore XML | `r2://nexus/proffer/test-fixtures/probata-test-20260912/sms-backup.xml` | `01a096da-94ed-7819-86dd-583d440ff68d` | Source registration and retention succeeded; after the repair decision, `execute_parser_activity` exhausted retries with `temporal: decode n8n "execute_parser_activity" StageResult: EOF`. |
| iMessage transcript text | `r2://nexus/proffer/test-fixtures/probata-test-20260912/imessage-thread.txt` | `01a096da-959a-7ed6-9a54-e9510b80dd7f` | Workflow failed at `repair.preview` with HTTP 422 because the repair engine did not accept the detected structural-text format. |
| ChatGPT conversations JSON | `r2://nexus/proffer/test-fixtures/probata-test-20260912/chatgpt-conversations.json` | `01a096da-9600-7bd7-95da-bc073cee79b5` | Parser execution succeeded; raw-generation persistence then exhausted the observed retry window because `context.forbid_mutation()` was absent. The function was restored live after that checkpoint. |

The SMS and ChatGPT repair decisions selected the original source (`apply_repair=false`). They were repair-gate decisions only; they did not approve content, publish a generation, or promote anything to evidence.

The untracked `scripts/live_test_recovery_20260912.py` in the dirty main checkout is not part of the repaired branch or the real-data proof. It directly invokes Python parsers and stores, bypassing Temporal and DuckDB. Its staged SMS, iMessage, and ChatGPT inputs exactly match the tiny synthetic fixture hashes (`698`, `328`, and `955` bytes); its `510`-byte Claude input matches the synthetic demo receipt. It must not be cited as an engine or real-source result.

## Verified real-source rehearsal manifest

The intended real inputs were resolved and hashed entirely on `ovh-files` through the existing OpenList WebDAV mount over R2. No source bytes were copied through the workstation and no source was modified.

| Format | OpenList-backed R2 object | Bytes | SHA-256 | Intended first pass |
|---|---|---:|---|---|
| SMS Backup & Restore XML | `/r2/casebible-raw/Evidence/Call data/SMS/sms-20221104021809.xml` | 3,852,202 | `e14a793e81dd5c73ee2419561346a140296a00d546b323ae07ac31fe6d378cba` | Yes; bounded real SMS source. Multi-gigabyte siblings remain untouched for later scale proof. |
| iMessage transcript | `/r2/casebible-raw/Evidence/Phone Records/Messages with Katrina/+18108532989.txt` | 143,806 | `90653967f03ed7386a09531e9bdad3a58fc796628dcda41f58566e83eaa77cad` | Yes. |
| ChatGPT conversations JSON | `/r2/casebible-raw/data-2025-12-08-01-38-39-batch-0000/conversations.json` | 61,724,767 | `638b458b8e0e243901af9a8b13c54374fe6c972c2ae4576d03597a907ef77ef5` | Yes, with provenance retained to the atomic export package. |
| ChatGPT atomic export | `/r2/casebible-raw/AI_Chats/data-2025-12-08-batch-0001.zip` | 14,794,205 | Not recomputed in this pass | Provenance container; companion `projects.json`, `memories.json`, and `users.json` remain grouped with the extracted conversation member. |

These are source candidates, not successful ingest claims. The live receipt must later record the exact object locator, observed handler identity, source hash, raw/normalized counts, all six completed context checkpoints, and the visible preview handle.

The runtime source-reference gate now admits `casebible-raw` and
`casebible-quarantine` only while `PLATFORM_DEV_AUTH_BYPASS` is active. This is
the TEST-mode bridge for the real source candidates above; it does not make
either bucket canonical and it does not widen REAL-mode authority.

## Context checkpoint naming and progressive import view

The six preview checkpoints are `raw_source_verification`, `parser_selection`, `parser_execution`, `normalization`, `storage`, and `completeness`. The retired preview label `custody` was only an alias for `verify_raw_coverage_against_source`; it is not evidence custody, sealing, admission, or promotion. The Import Source view exposes these six live statuses while the full normalized-message Preview remains gated until all required work completes.

## Workbench preview contract after normalization

The Workbench preview does **not** read `working.message`, a downstream evidence table, or Docstore. The current path is:

1. The normalizer persists a correlated `context.normalized_generation` and message rows in `context.normalized_record_identity` (`record_type='message'`), with `context.normalization_lineage` pointing back to `context.raw_record_identity`.
2. After normalized-lineage, digest, and completeness verification, the Temporal workflow schedules `publish_preview_activity` before the human preview hold (`modules/engine/proffer/workflow.go:305-340`).
3. `PreviewProjectionActivity` passes compact references to `ProfferPreviewStore.PublishWorkflowPreview`; source or normalized payload bytes do not enter Temporal history.
4. The store reads:
   - `context.normalized_generation` for source/raw correlation;
   - successful `context.activity_receipt` rows for parser identity and the six required receipts;
   - `context.normalized_record_identity` for message body, occurrence time, and participants;
   - `context.normalization_lineage` joined to `context.raw_record_identity` for attachment metadata.
5. `PublishProjection` atomically appends the browser projection to:
   - `context.proffer_preview_snapshot`
   - `context.proffer_preview_receipt`
   - `context.proffer_preview_participant`
   - `context.proffer_preview_message`
   - `context.proffer_preview_attachment`
   - `context.proffer_preview_event`
   The opaque request/run binding already exists in `context.proffer_preview_binding` from the starter.
6. The Workbench BFF serves `GET /api/proffer/previews/{preview_handle}` and `GET /api/proffer/previews/{preview_handle}/messages`, and streams `GET /api/proffer/previews/{preview_handle}/events`. It proxies those calls to the Proffer starter routes under `/reference-import/previews/{preview_handle}`.

Therefore, the supported way to make normalized test messages appear in the live preview is to complete the governed raw-to-normalized gates and let `publish_preview_activity` materialize the `context.proffer_preview_*` projection. Direct ad-hoc insertion into `working.message` or the preview tables is outside this contract.

## Validation boundary

- Snapshot source repair: applied locally to `sql/bootstrap/schema_snapshot_20260907.sql`, the repository's owner-ruled current database image. This repository has no active migration chain; `sql/bootstrap/README.md` requires final-form snapshot edits followed by a controlled rebuild.
- SQL static validation: `git diff --check` passed; focused inspection proved exactly one `context.forbid_mutation()` definition positioned before its first trigger reference, all six handler-selection tables with primary/unique/foreign-key constraints, the six-checkpoint receipt constraint, and expected writer/reader/application grants. No isolated snapshot rebuild was performed in this pass, so this is not PostgreSQL execution proof.
- Engine verification: `go test ./...` and `go vet ./...` passed. Focused live, read-only Webbed rehearsal loaded the extension twice on one leased PostgreSQL session and counted 225 SMS plus 6 MMS elements (231 total) from the bounded real R2 source without copying source bytes through the workstation.
- Workbench API verification: 270 tests passed using the repository virtual environment. The suite includes required mode propagation, TEST/REAL separation, source-root scope, preview-handle binding, and exact handler recommendation/decision tuple validation.
- Workbench web verification: lint completed with zero errors and 12 pre-existing Fast Refresh warnings; the production build passed; all 36 smoke/contract tests passed, including two headless browser matter flows and the same-origin `/evidence/preview` route contract. `@tanstack/react-table` is the only added runtime package.
- n8n verification: all 20 parser-activity workflow contract tests passed; both edited workflow documents also parsed as valid JSON. The workflows accept either the legacy three-reference result or that base set plus exactly the six governed handler-selection references, and reject arbitrary extras.
- Synthetic fixtures: the three committed regression inputs are tiny synthetic samples only (`698`, `328`, and `955` bytes). They are not the real R2 sources and are not ingest receipts.
- Commit/push: pending at the time this receipt text was updated.
- Coolify deployment: pending.
- Live workflow replay and visible Workbench preview proof: pending.

The Webbed session boundary is now implemented and locally tested. SMS XML
extraction leases one PostgreSQL connection, explicitly loads Webbed, verifies
its DuckDB-side loaded state, executes `read_xml` on that same connection, and
releases the lease on completion or failure. A live same-session probe loaded
Webbed idempotently and counted 225 SMS elements from the real R2 SMS source.

## Browser-side Kimi redirect finding

The reported navigation from **Inspect pipeline preview** to
`https://kimi.moonshot.cn/extension/login` is not authored by the Workbench
route or its deployed static bundle:

- The Workbench control targets the same-origin `/evidence/preview` route, and
  that route is registered in the TanStack application router.
- A search of the deployed Workbench JavaScript bundle found no `kimi`,
  `moonshot`, or `extension/login` reference.
- Chrome profile `Default` has the Kimi extension
  `fldmhceldgbpfpkbgopacenieobmligc` installed. Its manifest injects content
  scripts on `<all_urls>` and grants broad tab, navigation, request, debugger,
  and scripting permissions. An Edge profile also contains a Kimi-related
  extension.

The evidenced failure boundary is therefore browser-extension interception or
the extension's authentication gate, not a Probata/Workbench redirect. The
operator should not authenticate to Kimi in order to inspect a local pipeline.
Use a browser profile without Kimi, or disable Kimi for the Workbench origin,
while keeping `/` and `/evidence/preview` separately and accurately labeled.
No extension was disabled or removed during this investigation.
