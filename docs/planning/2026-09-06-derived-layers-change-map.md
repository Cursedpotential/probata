# Derived Layers — Change Map

> _Byline: Claude Code · Opus 5 · 2026-09-06._

STATUS: PROPOSED — owner has not ruled; executed in a separate session.

Scope: locate, do not change. Every path was verified to exist. New migrations start at
**0073** (0072 is highest; 0068/0070 absent by history). No applied migration is edited.

---

## 1. Custody hashing/sealing moves to promotion; ingest retains working copy + SHA-256 row

| File:line | What changes | Type | Owner ruling? | Size |
|---|---|---|---|---|
| `modules/engine/stagegraph/stage.go:39` `SealGeneration` | Seal leaves the ingest graph; becomes a promotion-lane stage | Go activity | **Y** (Q1) | M |
| `modules/engine/stagegraph/registry.go:215,221` | `DependsOn` edges into/out of seal removed; publish re-anchored to `PublishPreview` | Go activity | N | S |
| `modules/engine/parked/seal/` (`proffer_seal_main.go`, `sealfile.go`) | Already parked; annotate as the promotion-lane seed | doc | N | S |
| `modules/engine/activities/hashing.go:178` `FingerprintSource` | Stays — the ingest SHA-256 row (`context_source_fingerprint`, R02); confirm it is ingest's only hash | Go activity | N | S |
| `modules/engine/activities/hashing.go:234,256,381` `LegacyHash*` | Custody-named aliases retire with the seal move | Go activity | **Y** (Q2) | M |
| `sql/0036_context_import_foundation.sql:88` `context.retained_object`; `:640` `context.hash_receipt` | Unchanged — working-copy row and fingerprint receipt kind already exist | migration | N | — |
| **NEW `sql/0073_promotion_seal_boundary.sql`** | `context.promotion_event` (source_version → evidence + custody H1/H2/H3 receipt ids) | migration | **Y** (Q1) | M |

---

## 2. One cold copy; block storage is a TTL cache; one physical text table

| File:line | What changes | Type | Owner ruling? | Size |
|---|---|---|---|---|
| `modules/engine/acquisition/objectstorage.go:73` (R2), `:86` (B2) | Both resolvers already exist; B2 is config, not code | Go activity | N | S |
| `modules/engine/acquisition/dispatch.go:27` `NewSchemeRouter` | `permanent_home`-aware branch so a run cannot resolve bytes from a cache-only locator | Go activity | N | M |
| `sql/0036_...:89-91` `storage_class CHECK (immutable_object_store\|filesystem\|inline)` | `filesystem` becomes the cache class; needs an explicit cache/cold distinction | migration | **Y** (Q3) | M |
| **NEW `sql/0074_block_cache_ttl.sql`** | `context.retained_object_cache(object_id, cached_path, cached_at, expires_at, run_terminal, sha_matches_cold)` + sweep view | migration | **Y** (Q4) | M |
| `sql/0047_content_chunk_and_context_thread_foundation.sql:234` `content TEXT NOT NULL` | The only other physical text column outside `working.normalized_record`; removed in 3b | migration | N | — |

---

## 3a. Raw records store byte ranges, not bytes

| File:line | What changes | Type | Owner ruling? | Size |
|---|---|---|---|---|
| `sql/0036_...:219` `raw_record_identity.stored_bytes BYTEA` | Retired; the `:239-247` XOR CHECK collapses to locator-only | migration | N | M |
| **NEW `sql/0075_raw_locator_only.sql`** | Drop `stored_bytes`, replace the XOR CHECK, keep `h2-rawspan-v1` | migration | **Y** (Q5) | M |
| `sql/0036_...:281-400` `context.register_raw_format_subtype` | Subtype tables are JSONB-only — **already byte-free**, no change | migration | N | — |
| `modules/engine/parser/parser.go:252` `StoredBytes`, `:266` `RawRecordEnvelope`, `:291` the `(Locator==nil)==(StoredBytes==nil)` XOR | `StoredBytes` removed; `Locator` required | Go activity | N | M |
| `modules/engine/activities/raw_pipeline.go:167` `PersistRawGeneration` | Writes range only | Go activity | N | M |
| `modules/engine/activities/hashing.go:291` `hashRecordBytes` | Digest over a re-materialized range (DuckDB `read_text`), not an inline blob | Go activity | N | L |
| `modules/engine/postgres/hash_repository.go` | Range-read path for digest verification | Go activity | N | M |
| `modules/engine/activities/raw_pipeline.go:301` `ReconcileByteCoverage`, `:339` `VerifyRawCoverageAgainstSource` | Become the primary integrity gate | Go activity | N | M |

## 3b. Chunks are ids-only

| File:line | What changes | Type | Owner ruling? | Size |
|---|---|---|---|---|
| `sql/0047_...:234` `content TEXT NOT NULL CHECK (length>0)` and `:244` `CHECK (digest(convert_to(content,'UTF8'),'sha256') = content_sha256)` | Both dropped | migration | **Y** (Q6) | M |
| **NEW `sql/0076_content_chunk_ids_only.sql`** | Drop `content` + digest CHECK; add a reassembly view over `content_chunk_message` → `normalized_record` | migration | N | M |
| `sql/0072_content_chunk_message_bridge.sql:44` `working.content_chunk_message` | The only membership record — semantics promoted, no DDL change | migration | N | S |
| `sql/0072_...:127` `working.enqueue_evidence_vector_projection` | Already selects through the bridge; unchanged | migration | N | — |
| `modules/engine/activities/chunking.go:157` `ChunkDocument` | Emits generation + index + ordered member ids; no text | Go activity | N | L |
| `modules/engine/postgres/chunk_repository.go:172` `PersistChunkGeneration` | Stops writing `content`; writes bridge rows | Go activity | N | L |
| `sql/0047_...:255` `working.content_chunk_source_span` | Overlaps the bridge — reconcile or retire | migration | **Y** (Q7) | M |

## 3c. Weaviate holds vectors + coordinates + member ids, no text

| File:line | What changes | Type | Owner ruling? | Size |
|---|---|---|---|---|
| `server/core/evidence_vector_store.py:220` `Property(name="content", data_type=DataType.TEXT, index_searchable=True)` | Removed from `evidence_vector_properties()` | Python | N | S |
| `server/core/evidence_vector_store.py:85-87,111-113,147-149` | `content` dropped from the projection document; member ids added | Python | N | M |
| `server/core/evidence_vector_store.py:236` `ensure_evidence_vector_collection` | Property-set change forces **`EvidenceChunkV2`** — in-place V1 edits forbidden (`docs/plans/WEAVIATE-NATIVE-EVIDENCE-CUTOVER-RUNBOOK-2026-08-18.md:41`) | Python | **Y** (Q8) | L |
| `server/evidence/vector_projection.py:164` (`chunk.content` in the claim SQL), `:192` `self._embed(str(row["content"]))`, `:218` | Text fetched from `normalized_record` to embed, never stored | Python | N | M |
| `server/api/native_evidence_search_routes.py:252,257` | Retrieval hydrates text from PG via `normalized_record_id` + member ids | Python | N | M |
| Horizon filters added here | Must stay **dict** filters — agno drops FilterExpr on Weaviate (root `AGENTS.md`) | Python | N | S |

## 3d. Attachments as `source_version_object` rows

> **CORRECTED 12:10 (owner ruling 11:43):** attachments are EXTRACTED at parse, every run, into a subfolder beside the parsed object, with filenames, converted, indexed. `member_locator` byte range = provenance only. The two "decode-on-view / rows-not-files" lines below are STRUCK; the SBV `attachmentDir` materialization is the correct behavior and stays.

| File:line | What changes | Type | Owner ruling? | Size |
|---|---|---|---|---|
| `sql/0036_...:143-158` — `object_role` already has `attachment`/`container_member`, `member_locator JSONB` already exists | **No DDL change**; the byte-range shape inside `member_locator` needs a contract | migration | **Y** (Q9) | S |
| `modules/forks/sbv/internal/sms_xml_importer.go:308` `captureMMSDataAttribute`, `:469` `decodeMMSAttribute` | ~~becomes range-record, decode-on-view~~ **KEEP: materializes each attachment to `attachmentDir` (subfolder beside the object); add its own SHA row + `attachment` role row** | registry | N | S |
| `modules/engine/parser/parser.go:256` `AttachmentRef` | Already `Locator`-based — contract is correct | Go activity | N | — |
| `modules/engine/activities/source_observation.go` `InventoryContainer` | ~~rows, not extracted files~~ **members extracted to files AND recorded as rows** | Go activity | N | M |

## 3e. Vectors in exactly one store

| File:line | What changes | Type | Owner ruling? | Size |
|---|---|---|---|---|
| repo-wide `pgvector` / Surreal vector references | Assert no evidence-vector mirror; record in `docs/PROJECT_CANON.md` | doc | **Y** (Q13) | S |

---

## 4. DuckDB ELT primary for extract-only formats

| File:line | What changes | Type | Owner ruling? | Size |
|---|---|---|---|---|
| `modules/engine/activities/elt_structured.go:128` `ExecuteStructuredELT` | Must emit `RawRecordEnvelope` with a byte-range `Locator`, not land rows directly | Go activity | N | L |
| `modules/engine/postgres/elt_structured_repository.go:175` `INSERT INTO raw.raw_csv`, `:246` `duckDBReaderExpr` | Add `read_text`/XML/HTML readers; target the raw contract | Go activity | **Y** (Q10) | L |
| `modules/engine/profferworker/worker.go:49-60` `RegisterAll` | **ELT is registered on no worker today**; add `RegisterStructuredELTActivities` | Go activity | N | S |
| `modules/engine/activities/register.go:104` `RegisterParserActivities` | Add the ELT registration function beside it | Go activity | N | S |
| `modules/engine/stagegraph/stage.go:23` `SelectParser`; `registry.go:107-124` | Routes extract-only formats to ELT; fallback edge to `ExecuteParser` on logged failure | Go activity | **Y** (Q11) | M |
| `modules/engine/proffer/workflow.go:151,173` | Workflow branches on the selection result | Go activity | N | M |
| `modules/engine/parser/registry.go:63` `Select(format)` | Must be able to return "ELT" rather than an adapter | Go activity | N | M |

### Fallback-path fixes (not blockers for the ELT path)

| File:line | What changes | Type | Owner ruling? | Size |
|---|---|---|---|---|
| `modules/forks/sbv/internal/sms_xml_importer.go:156` `readXMLStartElement` (with `:129` `nextXMLRecordStart`) | Desyncs on an unescaped attribute quote; aborted 2,135/11,676 (test 2026-09-06) | registry | N | M |
| `modules/forks/sbv/internal/messaging_html_importers.go:100,131` (`current.depth == 0` flush guards) | Flushes only at depth 0; unclassed wrapper div yields 1/1,918 | registry | N | M |
| `server/tools/parsers/messaging/messaging_transcript.py:20` vs `server/tools/parsers/messaging/imessage_txt.py:459` `looks_like_imessage_txt` | Bracket-timestamp iMessage TXT must route to `messages_transcript` | registry | N | S |
| `docs/pending-review/atomic-parse-driver-20260906/` | Driver that produced these three findings — promote or archive | doc | N | S |

---

## 5. HITL destination gate + TTL sweep

| File:line | What changes | Type | Owner ruling? | Size |
|---|---|---|---|---|
| `modules/engine/stagegraph/stage.go:14-40` | New `SelectDestination StageID = "select_destination_activity"` | Go activity | **Y** (Q12) | S |
| `modules/engine/stagegraph/registry.go:65-71` | Gate sits after `FingerprintSource`, before `SelectParser` | Go activity | N | M |
| `modules/engine/proffer/workflow.go:77-151`; patterns at `:366` `awaitRepairDecision`, `:383` `awaitPreviewDecision` | Signal-await block modeled on the existing gates | Go activity | N | M |
| `modules/engine/stagegraph/stage.go:106` `ChunkDocument` | Precedent: the TTL sweep registers off-`Stages`, on the worker only | Go activity | N | S |
| `modules/engine/activities/source_lifecycle.go:132` `RetainOriginal` | Writes `permanent_home` on the source row | Go activity | N | M |
| **NEW `sql/0077_destination_gate.sql`** | `context.source_version.permanent_home TEXT CHECK (IN ('test','vault','discard'))` + decision receipt | migration | **Y** (Q12) | M |
| `modules/engine/profferworker/worker.go:49` | Register `SelectDestination` + `SweepBlockCache` | Go activity | N | S |

---

## 6. Atomicity (D-130)

Each new unit is one Activity: `select_destination`, `sweep_block_cache`,
`execute_structured_elt`, the range-reader used by hashing and chunking. No orchestration
inside units — the ELT-vs-parser fallback lives in `workflow.go`, never inside
`elt_structured.go`. All inputs are locators; no source bytes cross Temporal history.

---

## Docs needing same-turn drift fixes

| File | What changes | Type |
|---|---|---|
| `docs/reference/HASH-TAXONOMY-2026-08-29.md:24-39,101,106` | H1→H2→H3 restated as promotion-time; four lifecycle moments re-anchored; H2 over a byte range | doc |
| `modules/engine/AGENTS.md:27,88` | Cache/cold distinction; ELT lane; new stages | doc |
| `docs/planning/2026-09-03-ingest-redesign-plan-and-sequential-guide.md` | Stage-3 chunker becomes ids-only; ELT becomes primary | doc |
| `docs/adr/README.md` | Index a new ADR for the derived-layer boundary | doc |
| `docs/DECISION_LOG.md` | Next number is **D-149** | doc |
| `docs/consolidated/OPEN-WORK-REGISTER-2026-09-05.md:78,106,172` | OW-014 / OW-031 / OW-092 move if `EvidenceChunkV2` is cut | doc |

---

## Sequencing

**First:** `0073` promotion/seal boundary (until seal leaves ingest, ingest still claims
custody); `0075` raw locator-only (the Go `StoredBytes` removal cannot compile against the
old CHECK).

**Then, in order:** `parser.go` `StoredBytes` removal → `raw_pipeline.go` →
`hashing.go` + `hash_repository.go` (one commit; they break together) → `0076` →
`chunking.go` + `chunk_repository.go` → `EvidenceChunkV2` + `vector_projection.py` +
`native_evidence_search_routes.py` (last; the projection reads the bridge).

**Independent:** `0074` cache TTL and sweep; `0077` destination gate; ELT worker
registration (an unused registered Activity is inert); the three SBV/routing fixes; every
doc fix, same turn as its code change.

**Blocked on a ruling:** the `EvidenceChunkV2` cut, `raw.raw_csv` survival,
`content_chunk_source_span` vs the bridge, automatic-vs-HITL ELT fallback.

---

## Storage effect

Today one export can exist six times: cold object, block-storage copy, `stored_bytes` per
raw record, `content_chunk.content` per chunk, `content` in Weaviate, extracted MMS
attachment files.

After: **one** cold copy (R2 now, B2 later); a TTL'd block cache deletable when the run is
terminal and the SHA matches cold; **one** physical text table
(`working.normalized_record`). Raw records become offsets, chunks id lists, Weaviate
vectors plus coordinates. ~~Attachments byte ranges decoded on view~~ **attachments are extracted files, permanent, deduped by SHA (owner 11:43); they are ~99.8% of the footprint (thinking pass)**. For the 1.3 GB
smsbackuprestore XML: from roughly six multiples of 1.3 GB to
`1.3 GB cold + extracted attachments (~0.9 GB, deduped) + normalized text + index`.

> **Owner rulings 12:07–12:09 folded in:** (a) destination gate fires ONLY for one-offs (upload/drop/test); anything already in the Case Bible vault has its home and gets no gate. (b) No test bucket: tests live on block storage (`/data/test_data`). Tiers = vault (cold) · block (working + test) · `nexus` (workbench upload staging only). No second transfer of the nexus test copies.

---

## Not found

- No `byte_start`/`byte_end` columns exist. The as-built spelling is `byte_offset` +
  `byte_length` (`sql/0036_context_import_foundation.sql:217-218`). Q1=C is **partly
  already built** — the locator branch exists; only `stored_bytes` must go.
- No `RegisterStructuredELTActivities`; ELT is genuinely unregistered on every worker.
- No `sql/0068_*` or `sql/0070_*` — gaps in the applied series, not missing files.
- `/data/test_data/smsbackuprestore/export-20251206/sms-20251206203434.xml` lives on ovh-files and
  was **not** verified from this checkout.
- No `permanent_home`, `retained_object_cache`, `promotion_event`, or destination-gate
  stage exists anywhere in the tree yet.

---

## Open questions for the owner

1. Does `publish_generation` remain in the proffer graph once `seal_generation` moves to promotion?
2. Retire the `LegacyHash*` aliases now, or keep them for in-flight workflows?
3. Is the block cache a new `storage_class` value, or a separate `cache_state` column?
4. Confirm the 7-day default TTL and that "run terminal + SHA matches cold" is the whole deletion predicate.
5. Drop `raw_record_identity.stored_bytes` outright, or keep it nullable and forbidden by CHECK?
6. Once chunk text is derived, does `working.content_chunk.content_sha256` survive as an integrity digest?
7. Does `working.content_chunk_source_span` survive alongside the bridge, or retire into it?
8. Cut `EvidenceChunkV2` now, or hold the Weaviate change until the Go chunker writes real rows?
9. Pin the `source_version_object.member_locator` JSON shape in a `modules/contracts/` schema?
10. Does `raw.raw_csv` survive as ELT staging, or does ELT write the raw contract directly?
11. Is the ELT→parser fallback automatic on logged failure, or does it stop at a HITL gate?
12. Are the destination values exactly `test`/`vault`/`discard`, and is `discard` a tombstone or a no-retain?
13. May any pgvector column remain, or is the one-vector-store rule absolute?
14. Next decision number is **D-149** — is this map one decision or several?
