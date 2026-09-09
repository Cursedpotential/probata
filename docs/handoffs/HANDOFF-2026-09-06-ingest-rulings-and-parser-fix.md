# HANDOFF — ingest rulings, storage tiers, parser fix, webbed install (2026-09-06)

> _Byline: Claude Code · Fable 5.1 · 2026-09-06 15:21 EDT; updated 15:46_
STATUS: PARTIAL
BUILD_STATUS: PASS for Go (15:38: SBV `go vet`/`go test -tags fts5 ./...` green in a Linux container on ovh-files; `modules/engine` `go build ./...` OK after vendor resync). Python: one frozen-dataclass test failure `test_pinned_parser_rejection_is_loud_no_mesh_fallback` and unformatted `server/evidence/store.py` (sanity pass 2026-09-06, unfixed)

## READ FIRST

- Memory `what-this-is-for.md`: this is a custody case; 15 months since the owner saw his daughter; nothing is "live" until he can assemble messages, build the timeline, and prove the deception. Never call a component live.
- Every turn: recall (transcripts, DECISION_LOG, plan) → `/thinking-skills:thinking-model-router` → the models it names → question gate (what am I asking · what needs asking · is it real · already decided or superseded) → only the residue goes to the owner. Memory: `named-skill-is-non-negotiable.md`, `question-gate-before-asking.md`, `memory-notes-are-rules-not-quotes.md`.
- Work surface = `modules/workbench/` (probata Workbench). Never propose deploying SBV as a surface.

## Verified-live state (do not re-derive)

| Thing | State |
|---|---|
| Live platform DB | ovh-files `100.91.190.107:5432/platform`, Coolify app `agentos-db`, pg_duckdb 1.1.0 / DuckDB v1.4.3; all three proffer services connect to it (verified from container env) |
| `webbed` extension | installed, autoload on, `read_xml` proven with 2 typed rows (`scripts/pgduckdb_webbed_smoke.sql`, run over stdin). `duckdb.allow_community_extensions = on` via ALTER SYSTEM (data-volume only; image persistence in flight). `allow_unsigned_extensions` stays off. ~1-minute live outage of DuckDB queries during install, corrected. Record: `docs/reviews/2026-09-06-webbed-install.md` |
| Test data on block | ovh-files `/data/test_data/smsbackuprestore/export-20251206/{sms-20251206203434.xml 1,327,221,655 B, calls-20260609173028.xml}` and `/data/test_data/imessage/export-18108532989/{index.html, +18108532989.txt}`; `.sha256` sidecars (bare filenames) all verify; README.txt states the layout; empty `first-real-runs/` left for the owner to delete. Same files hardlinked at `/data/agno/volumes/proffer/source-objects/test-fixtures/first-real-runs/` = container path `/data/proffer/source-objects/test-fixtures/first-real-runs/` in `parser-activity-runtime` |
| Atomic parse test (morning) | calls XML 1,457/1,457 OK; iMessage TXT 1,918/1,918 under `messages_transcript` (0 under `imessage_txt`); iMessage HTML 1/1,918 (depth-0 flush bug); SMS XML aborted 2,135/11,676 (scanner desync on an unescaped attribute quote, fail-closed). Driver: `docs/pending-review/atomic-parse-driver-20260906/` (untracked) |
| Gateway / Stage 2 | DONE 2026-09-05: `svc:tool-gateway` live, worker repointed, rehearsal reached the HITL repair gate (9 stages). Plan + desk updated today |
| Decision Desk | https://claude.ai/code/artifact/efe3d190-dc46-43d3-8bfc-768cb023d60a — Stage 2 done, Stage 3 decode-subtree-first, Stage 4 reframed as analysis surface, Stage 6 SBV line removed |
| nexus bucket | 10 objects, 1.24 GiB: 4 first-real-run test copies (leftovers, owner deletes), 1 synthetic uiw fixture, 4 workbench `upload://` staging objects, deploy marker. Role = workbench upload staging only |
| Seal code | parked at `modules/engine/parked/seal/` (`//go:build parked`, README). Reused by the promote activity; never rewrite |
| Coolify MCP plugin | connection failure cached at session start (auto-retry 15 min); Coolify itself up on both URLs |
| Git | uncommitted: D-149 row, plan edits, today's four review/planning docs, `modules/engine/parked/`, `scripts/pgduckdb_webbed_smoke.sql`, this handoff, SBV fork changes (own repo, gitignored). Rename session's untracked leftovers: 3 hash CSVs at repo root, `.review_hold/*` |

## Rulings today (D-149, `docs/DECISION_LOG.md`, plus amendments in-row)

1. Custody sealing at PROMOTION only; ingest retain = working copy + SHA row (`context.retained_object`, `hash_receipt` context_source_fingerprint).
2. Tiers: vault `r2:casebible-sorted` (home of everything sorted) · block `/data/test_data/<source_type>/<export-folder>/` (working + test) · `nexus` (upload staging). No test bucket, no second transfer.
3. Block TTL: deletable once run terminal AND SHA validated vs vault; promotion re-reads from vault; sweep automatic, reports.
4. Destination gate (test/vault/discard) ONLY for one-offs; vault sources skip it.
5. Attachments EXTRACTED at parse into a subfolder beside the object, named, converted, indexed, own SHA; byte range = provenance only; permanent, deduped.
6. Raw records: locator + range already built (`raw_record_identity`, `source_range_locator`); drop `stored_bytes` branch. For `read_xml` templates offsets are NOT required (Q1=C slow lane: re-parse at promotion). Row digest on insert = integrity; file SHA at promotion = custody.
7. Chunks = ids only in PG (`content_chunk_message`); drop `content_chunk.content`; view for readers.
8. Weaviate holds the chunk search object (vector + member ids + PG coordinate), no text; hit returns messages from PG; rebuild from PG id lists; write path PG row + outbox. Confirmed by four explicit answers (`docs/reviews/2026-09-06-chunks-live-in-weaviate-systems-pass.md`).
9. Routing: lint/validate first (assess_source_repair → HITL → resolve) → select by file fingerprint/signature (Q18 matcher) → ONE registered handler per signature. Registry fill rule: DuckDB owns every signature it can process; Go decoders registered only where it cannot. Not a priority ladder. Go/SBV decoders KEPT, built, tested, callable atomically, backup on DuckDB failure, not in the workflow for DuckDB signatures.
10. SBV = decoder library → `modules/engine/decode/` subtree FIRST in Stage 3 (D-131), then in-tree fixes; Vite viewer = client, ≠ HITL preview; Go orchestrates everything including DuckDB.
11. Reading context, sending to Surreal, Surreal analysis = the platform in use, not build stages.
12. DuckDB ELT strictness = same four gates as parsers (template output schema, `RawRecordEnvelope`, raw-table constraints, count reconciliation + row digest); templates declare typed columns and TRY_CAST into reject rows.

## Findings / work done

- Recall pass (`docs/reviews/2026-09-06-storage-copies-recall-pass.md`): 3 of 7 morning proposals were restatements of settled rulings (Q1=C, 2026-09-03 DuckDB, 11:43 attachments); 4 open → ruled above.
- Thinking pass (`docs/reviews/2026-09-06-storage-copies-and-derived-layers-thinking-pass.md`): text-side savings ≈0.2% of footprint; attachments ≈99.8%; vectors ≈8 KB/chunk. "Operator time is the bottleneck" WITHDRAWN (owner 12:12).
- Change map (`docs/planning/2026-09-06-derived-layers-change-map.md`): file:line for every change; migrations 0073 seal boundary, 0074 block TTL, 0075 raw locator-only, 0076 chunk ids-only, 0077 destination gate; ELT activity registered on no worker (`profferworker/worker.go:49-60`); Weaviate no-text forces `EvidenceChunkV2`; §3d attachment lines struck to match ruling 5; SMS-file-not-verified note.
- Plan (`docs/planning/2026-09-03-ingest-redesign-plan-and-sequential-guide.md`): Stage 2 ☑; Stage 3 head = decode subtree; Stage 4 framing note; test-data block superseded; false "call-log decoder may not exist" line struck with proof (`sms_xml_importer.go:105,150`).
- Memory written today (canonical dir): `what-this-is-for`, `memory-notes-are-rules-not-quotes`, `question-gate-before-asking`, `attachments-extracted-at-parse`, `sbv-is-two-things-decoders-and-viewer`, `work-surface-is-probata-workbench`, `router-is-signature-based-not-priority`; `test-the-job-not-the-transport` and `lifecycle-order-…` rewritten as rules; `named-skill-is-non-negotiable` addenda (router every turn).

## UNRESOLVED (mandatory)

- **Parser fix DONE 15:38 (uncommitted, SBV fork working tree + engine vendor resync):** all four real files parse: SMS 11,676/11,676 (2 m 46 s), calls 1,457/1,457, iMessage HTML 1,918, iMessage TXT 1,918 (HTML and TXT cross-validate, same date range). Root cause of the SMS abort was NOT a malformed element: the MMS path rejected with a nil raw span and the driver had no attachment sink; no malformed element exists in the file. Also fixed: HTML flush at any depth; HTML detection accepts `class='…'`; `parseonly.DetectFormat` added so bracket-TXT routes to `messages_transcript`; scanner hardening (1 MiB start-tag bound, resync, complete bytes on every reject). 7 tests added on synthetic fixtures. Files: `modules/forks/sbv/internal/{sms_xml_importer.go, messaging_html_importers.go, importer.go, messaging_defect_repair_test.go}`, `pkg/parseonly/{parseonly.go, detect_format_test.go}`, `modules/engine/vendor/github.com/lowcarbdev/sbv/**` (4 files), driver `docs/pending-review/atomic-parse-driver-20260906/`. Not proven: >64 MiB malformed span path; HTML `overflow` reject still passes rawComplete=false. **Acceptance half met:** counts reconcile; "every field in the full raw tables" needs the real workflow (parse-only writes no rows).
- **Real-workflow run agent (Opus, running since 15:40):** runs the SMS export from its vault locator through the live proffer workflow with the fixed decoder (agent chooses: push sbv fork to its own remote → CI digest → local Dockerfile bump → redeploy parser runtime, or build on ovh-files), approves the HITL repair gate, then seven proof queries on `platform`: source_version SHA = sidecar; raw_generation; 11,676 raw rows + subtype rows; per-column NULL census (name any all-NULL column); attachment files + rows; hash_receipt rows; rejects. Result pending.
- **Postgres persistence DONE 15:43 (uncommitted):** `deploy/docker/postgres/Dockerfile:64` CMD now carries `-c duckdb.allow_community_extensions=on`; `deploy/data-pg.yaml` parses; `deploy/docker/AGENT_MEMORY.md` + webbed review doc updated. Takes effect only on a Coolify redeploy of `agentos-db` (bounces the live DB; owner triggers).
- `docs/private/SAT-ACTION-CONTRADICTION-LABELS-2026-09-06.md` (moved to docs/private/, 2026-09-06) (untracked) contains real names — no-PII-in-git check before any commit.
- Rename session (project rename) had unpushed live Coolify/host changes; my local commits are unpushed; reconcile with `docs/registers/RENAME-LIVE-CHANGES-2026-09-06.md` before pushing. R2 fixture prefix `nexus/uiw/test-fixtures` → `proffer/test-fixtures` in code still to fix.
- Owner deletes when convenient: `/data/test_data/first-real-runs/` (empty), 4 nexus test copies, `components_hashes.csv` / `skills_hashes.csv` / `tools_hashes.csv` at repo root (rename session's wiki manifests), `.review_hold/*` leftovers, probe file `/data/agno/volumes/tool-gateway/materialize/probe-fixture.xml` on ovh-app.
- Desk: Q2, Q5, Q8, Q11, Q12, Q16, Q17, Q20–Q25 still owed a read/discussion.
- Owned drift: root `AGENTS.md` deploy/docker row; `deploy/compose.yaml` platform-tools block; two leftover `universal_import` identifiers in `sbv_sms.py` / `_sbv_client.py`.

## Pending owner decisions

- None new. All storage/derived-layer questions ruled (D-149). The block-TTL grace period (7 days proposed) is a parameter, not a decision.

## Next steps (work in order)

1. Receive the real-workflow run report → present stage table + seven proofs; any all-NULL column or missing attachment file = defect, back to an agent.
2. Owner triggers `agentos-db` redeploy when acceptable (postgres setting persistence).
3. Execution session from the change map: decode subtree → `modules/engine/decode/` (drop go.mod `replace`) → register `execute_structured_elt_activity` on a worker → first `read_xml` template for smsbackuprestore, compared with the decoder on fields/counts/time on the 1.3 GB file → migrations 0073–0077.
4. Commit today's docs + parked seal + smoke script (explicit path allowlist; PII check first); push after reconciling with the rename session.

## Owner working-style contract

- Structured replies: bullets, labeled blocks, white space, answer-first. Concise.
- Rules not quotes in memory/docs. Recall → router → skills → question gate, every turn.
- Confirm before changes; never hard-delete (quarantine or park); byline every artifact; verify live before claiming done; "live" = messages assembled, timeline built, deception proven.
