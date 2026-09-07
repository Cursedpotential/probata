# Ingest simplification plan — custody only at promotion, one activity per file

> _Byline: Claude Code · Opus 5 · 2026-09-03. Orchestrator plan per `/make-plan`._
> _Byline amendment: Claude Code · Fable 5.1 · 2026-09-05 — naming canon sweep D-137..D-141. This repository is now **Indicia Probata** / `probata`; the import lane (`uiw` in the code paths referenced below, not yet renamed in `modules/engine/`) is named **proffer** going forward (D-140). Code path literals below (`modules/engine/proffer/ (formerly uiw/)...`) reflect the actual current tree and are left as-is until the owning lane executes the rename; see `docs/NAMING.md`._
>
> **STATUS: ITERATING — NOT DONE.** This plan is done only when the owner says it
> is done (owner, 2026-09-03: "You don't decide when the plan is done… We iterate
> until I say the plan is done"). Every phase below is a proposal until ratified.
>
> Owner direction, 2026-09-03 (verbatim fragments): "at the point that it becomes
> evidence we are going to re-extract it from the original binary… store that
> immutably… add all of our metadata and our tables away from the file… once it
> gets promoted to evidence it will get re-extracted and run through the entire
> hashing process… we can completely split the evidence process from the
> normalized ingestion process… one activity for the entire workflow" — refined
> to "one activity per file, so if the workflow is calling a batch it will call
> multiple activities… large files broken into chunks early… processed in
> parallel." And: "H1 still happens… likely the chunks also… it's more
> verification than anything." And on identity (corrected same day): promotion
> writes **new rows into `evidence.*` tables linked by FK to the working rows** —
> "create new tables for the evidence that has everything included and then it
> can just link to that particular foreign key for its provenance… just like it
> does through the change detection and into the graph and the vectors." An
> earlier verify-in-place variant was rejected because the D-128 immutability
> guards attach to `evidence.*` tables, so a flagged working row would be
> unguarded evidence.
>
> Each phase is self-contained for a fresh session. Every task is framed as
> COPY-FROM-A-CITED-LOCATION, not "migrate". Every phase ends with a proof
> checklist and anti-pattern guards. Nothing here is done until its checklist
> passes on the live stack.

## The model in one table

| Moment | Before (D-124) | After (this plan) | Hash family |
|---|---|---|---|
| Intake — whole file | context fingerprint | **keep** | `context-source-fingerprint-v1` |
| Intake — chunking | (chunker orphaned) | **wire in, hash each chunk** | `content_sha256` + byte range (D-116) |
| Normalization | normalized digests | **keep — reclassified as INTEGRITY VERIFICATION, never custody** (owner-ruled 2026-09-03) | `normalized-record-postgresql18-jsonb-text-utf8-sha256-v1`, `normalized-generation-ordered-digests-lengthframed-sha256-v1` — already non-custody tags |
| Promotion | custody H1/H2/H3 (never built) | **BUILD — project into `evidence.*`, FK to working rows** | `h1-rawbytes-v1`, `h2-rawelement-v1`, `h3-chain-sbv-genesisempty-v1` |
| Later | reverification | keep | — |

**Why this is safe:** `context-source-fingerprint-v1` and `h1-rawbytes-v1` are the
same computation over the same bytes (`modules/engine/activities/hashing.go:212`
and `modules/forks/sbv/internal/custody.go:35`). Same value, different claim.
Promotion recomputes over the sealed original, compares to the intake
fingerprint, and if equal records the number under its custody tag. The naming
discipline (D-088/D-089) is what stops a fingerprint from ever being presented
as custody. Chunk hashes are **not** promotable to H2 (different bytes, post-
chunking) — they prove chunking was lossless and re-extraction deterministic,
which is exactly the verification job the owner named.

## The hub-and-mirror model (owner ruling, 2026-09-03 12:51)

Owner: "we're going to split what we were trying to do in one set into two sets,
but essentially everything remains the same… we're still going to chunk
everything… we may not have to ingest the evidence into the vectors a second
time… once we link the original working tables and the evidence tables,
everything that was linked to the one should be linked to the other."

**The working row is the hub. Evidence is a linked mirror. Every projection stays
pointed at the hub and reaches evidence through the link.**

| Thing | Where it lives | At promotion |
|---|---|---|
| Working record / chunk | `working.*` | untouched |
| Evidence record / chunk | `evidence.*` — **mirrors** of the working tables (reuse the 7 existing `evidence.*` tables where they fit; add mirrors only where no fit) | new rows written |
| The link | **link table** `working_evidence_link(working_id, evidence_id, promotion_receipt_ref, linked_at)` — append-only, never a column added onto the working row | one row per promoted record |
| Vector index | points at the hub (working row) | **NOT re-embedded** — a search hit resolves to the working row, then to its evidence twin via the link |
| Entities, graph edges, timeline | attached to the hub | **NOT re-linked** — transitively reach evidence through the link |
| Horizon walks / delta analysis | **SurrealDB, analysis phase, exclusively** (D-073, D-080) | not an ingest or promotion concern at all; Surreal handles its own searching and temporal awareness |
| Chunking | **always**, everything, parse-then-chunk | chunks are what get mirrored and what the FK points at |

Why a link table and not a column: the plan's standing rule is that promotion
never mutates a working row. Appending `evidence_id` onto `working.content_chunk`
would be a mutation. A separate append-only link table keeps that rule intact
and also carries the promotion receipt, which a column could not.

Why chunk everything: it is the most efficient unit, and it guarantees messages
are properly split BEFORE anything reaches evidence — a message that was never
chunked correctly never gets promoted incorrectly.

## The hierarchy — Case Bible level down to chunk (owner ruling, 2026-09-03 13:06)

Owner: "Even when it's separated down to per-platform folders, there are still
going to be multiple file types within the platform, because the same
conversation may have happened, or been extracted, or live in several different
file types or export types."

The R2 inventory bears this out: `casebible-sorted/…/snapchat/` alone holds
**8 file types** (jpg, jpeg, png, html, json, mp4, xlsx, docx) that are all
artifacts of a small number of conversations. Routing is per FILE CLASS; grouping
and corroboration are per CONVERSATION. Both levels must exist or the
corroboration graph has nothing to hang edges on.

```
Case Bible domain        (v4 taxonomy, NO numbers — e.g. Messaging)
 └ platform              (Snapchat, WhatsApp, SMS, Messenger, Google Voice …)
    └ conversation group (the logical thread: "Snapchat — Katrina")
       └ artifact        (JSON export | HTML export | screenshot set | audio | summary docx)
          └ package      (an export zip, a screenshot folder — THE CUSTODY UNIT, never split)
             └ file      (routed by class per the table below)
                └ record / chunk
```

Consequences, binding on every phase below:

- **Conversation grouping is OUR classification act inside ingest — NOT assigned
  by the Case Bible sort** (owner correction, 2026-09-03 13:08: "this isn't
  gonna happen at the organizational level"). The folder is one signal; it does
  not decide. It runs in TWO passes because the real signal is parsed content:
  1. **Tentative group** at classify, per file, pre-parse — from Case Bible path,
     filename, platform, and any thread id visible in the container listing.
     Cheap; its only job is to fan packages out together.
  2. **Real group** after parse, ACROSS files — a `group_conversations` activity:
     parsed counterparty handles → `registry.id_xref` → canonical entity, evaluated
     as-of each message's date (numbers change); platform; date-range overlap;
     export thread ids (`thread_id`, `thread_path`); for screenshots the OCR'd
     counterparty and visible dates. This is entity resolution applied to
     counterparties, not a new classifier, and it is what makes cross-platform
     hopping one group (`5551234567` and `fb:1000…` → same person).
  The hard classify cases — an `.md` that may be an AI transcript or the owner's
  own notes; which conversation a screenshot depicts — are where agents READ
  content. Cheap sniffing covers A/D/E/F; agents cover the ambiguous middle.
  Both live in ingest+classify, never in sorting.
- **The manifest carries the whole path.** Every row has `case_bible_domain`,
  `platform`, `tentative_group`, `artifact_kind`, `package_id`, then the
  file-level fields; `conversation_group` is written by pass 2.
- **Fan-out is per package** (custody unit), and each package carries its
  `conversation_group` so the corroboration stage can find its siblings after
  ingest without re-discovery.
- **Corroboration edges are built WITHIN a conversation group** — native export
  ↔ screenshot ↔ audio ↔ summary — with independence class on every edge
  (same device / same party / cross-party). This is where "a screenshot shows a
  message the export lacks" becomes a recorded deletion finding.
- **Promotion is conversation-aware.** The operator promotes a conversation
  group — all its artifacts together with their corroboration verdicts — not one
  file in isolation. The evidence package then presents native + screenshots +
  verdicts as one exhibit set, which is what the owner described: "normalized
  data that's easy to read… along with it the original source data… validated as
  unchanged… slide in the hash validations… and the reassembly of cross-platform
  hopping."
- **A conversation may span platforms.** The group is keyed by counterparty and
  thread, not by platform; platform is an attribute of the artifact. A thread
  that hopped SMS → Messenger → WhatsApp is ONE conversation group with artifacts
  on three platforms, and the composition manifest (ordered by each source's own
  clock, ambiguity flagged) is how it is reassembled.

---

## Phase 0 — Discovery (DONE; consolidated here so later phases need not repeat it)

Source: Explore subagent report 2026-09-03, all claims file:line-cited. Read
these before any phase; do not re-derive them.

### Allowed APIs and existing patterns (cite these; do not invent)

| Need | Exists at | Notes |
|---|---|---|
| File-level fingerprint | `modules/engine/activities/hashing.go:182-228` (`fingerprintSource`) | uses `custodyhash.HashReaderH1` under tag `context-source-fingerprint-v1` (`:43`) |
| Per-record fingerprint | `hashing.go:291-365` (`hashRecordBytes`) | tags at `:44-45` |
| Generation fold | `hashing.go:421-508` | `custodyhash.NewChain("")` at `:377` |
| Custody-kind constants (reserved) | `hashing.go:28-31` | `HashKindH1Source`, `HashKindRawRecordDigest`, `HashKindH3RawGeneration` — declared, **unused**, comment: "R04 owner promotion only" |
| Custody primitives | `modules/forks/sbv/internal/custody.go:65` `HashFileH1`; `HashRecordH2`; `ChainH3` | vendored at `modules/engine/vendor/github.com/lowcarbdev/sbv/internal/` |
| Canon tags | `custody.go:35` `h1-rawbytes-v1`; `CUSTODY.md:137` `h2-rawelement-v1`, `h3-chain-sbv-genesisempty-v1` | |
| Chunker | `modules/engine/chunk/chunk.go` — `digest()` at `:167`; lossless validator `:150-165` | proves every chunk is an original-source slice with full coverage |
| Chunk activity | `modules/engine/activities/chunking.go:13` `chunk_document_activity` | registered, **NOT in `Stages`**, not workflow-invoked (`stagegraph/stage.go:79-106` explains why) |
| Chunk table | `working.content_chunk` (`sql/bootstrap/schema_baseline_20260830.sql:3415`) | `id uuid DEFAULT uuidv7()`, `content_sha256`, byte ranges |
| Stage list (26) | `modules/engine/stagegraph/stage.go:14-41`; DAG `registry.go:55-223` | 5 hash stages asserted by `graph_test.go:160-185` (`TestFiveHashComputationStagesAreDistinct`) |
| Hash stages | `FingerprintSource`, `FingerprintRawRecords`, `FingerprintRawGeneration`, `HashNormalizedRecords`, `HashNormalizedGeneration` | ALL FIVE STAY. The last two are hash moment 2 — integrity verification of a normalized generation, never custody |
| Workflow | `modules/engine/proffer/ (formerly uiw/)workflow.go` | version gates via `workflow.GetVersion` (`:13-41`) |
| Fidelity digest | `modules/engine/fidelity/fidelity.go` | 4-field seal; **KEEP (owner-ruled)** — guards the record where chunk hashes guard the file; used at promotion (step 7) and post-promotion reverification (moment 4) |
| n8n flow → Activity | `modules/engine/temporal/flowbinding.go`, `flowactivity.go` | declare a flow, get an Activity |
| Tool gateway | `modules/engine/toolgateway/`, `cmd/tool-gateway/` | built, **undeployed** |
| Python H1 custody write on ingest | `server/evidence/custody.py:418-427` | writes `level='H1'`, `canon_version='h1-rawbytes-v1'` on EVERY `ingest_artifact` — **the leftover to remove** |
| Python H2/H3 | `custody.py:582-658` `reconcile_sbv_import` | SBV-only path; digests received from SBV, not computed |
| ELT canon deviation | `modules/engine/postgres/elt_structured_repository.go:65` `h2-rawelement-duckdb-json-v1`; open question at `:33-49` | must be resolved as a **fingerprint**, not custody |

### Facts that shape the plan

- **Go ingest already computes zero custody hashes.** Only context fingerprints under distinct tags. The custody symbols are declared-unused. (Agent: repo-wide grep excluding `vendor/` returned only the declaration lines.)
- **No promotion code exists anywhere** — not in `modules/engine`, not in `server/evidence/`. Only comments saying R04 will do it. Phase 4 is greenfield.
- **The chunker is orphaned.** Built, tested, registered, never scheduled by the workflow.
- **`content_chunk.id` is `uuidv7()`** — random, and it stays put: promotion never touches working rows. Evidence rows get their own `uuidv7` plus a FK back — the standard provenance link, same as every CDC projection.
- **Python still writes custody H1 at ingest** (`custody.py:418`). This is the only real "custody at ingest" left, and it's the one to cut.

### Anti-patterns (global, every phase)

- Writing `h1-rawbytes-v1`, `h2-rawelement-v1`, or any `h3-chain-*` tag anywhere except the promotion activity.
- Promotion MUTATING working rows (tier flips, content edits, id changes). It writes new `evidence.*` rows and links back by FK; working rows keep evolving.
- Evidence living anywhere other than `evidence.*` — that is the D-128 guard boundary, and a flagged working row is unguarded evidence.
- Writing a CUSTODY tag against `analysis.normalized_record` / normalized generations. Integrity-verification digests there are correct and required; custody there is not.
- A parser or chunker computing a hash it then persists as custody (D-130 rule 1/2).
- Regenerating `uuidv7` for a record that already exists.
- Returning an empty record set on an unrecognized shape (the 516-MMS failure). Raise.
- Inventing a Temporal API — copy the `workflow.GetVersion` gate shape from `proffer/workflow.go (formerly uiw/):13-41`.

---

## Phase 1 — Canon first (docs + decision log), so nothing below can drift

**Goal:** record the ruling before touching code, per the doc-drift rule.

**Implement:**
1. Append to `docs/DECISION_LOG.md` (copy the row shape of D-136 exactly):
   - **D-137** — Custody only at promotion; promotion verifies existing rows in place; one activity per file; chunks early and parallel. Quote the owner fragments in the header of this plan.
   - **D-124 amendment** — all four hash moments STAND. Moment 2 (normalized digests) is reclassified as **integrity verification, never custody**: it proves a normalized generation is complete, contiguous and reproducible, which cross-platform conversation reassembly depends on (owner, 2026-09-03: reassembling from multiple normalized tables across platform hops needs each one provably intact). AI-chat rows receive it too — harmless, because it is not custody, so no D-082 conflict. An earlier draft of this plan proposed deleting moment 2; record that as struck, not silently removed.
   - **D-130 amendment** — "one unit does one thing" is satisfied by *ingest a file*; a per-file activity is compliant. Atomic sub-units remain the shape *inside* Go for parallelism, not the Temporal boundary.
2. Update `docs/reference/HASH-TAXONOMY-2026-08-29.md` "The recurring shape" table: remove the Normalized row from *custody-relevant* families; add a sentence that chunk hashes are verification-only and not promotable to H2.
3. Update `modules/engine/fidelity/fidelity.go` package comment: its job is the **comparison check at promotion** (stored row vs fresh parse), not a join key. Keep the construction and canon tag unchanged — changing the tag would invalidate nothing yet, but don't.
4. Update `modules/engine/AGENTS.md` "Boundaries that are rulings" with the promotion-only custody rule and the verify-in-place rule.

**Verification:**
- `grep -n "D-137" docs/DECISION_LOG.md` → 1 hit
- `grep -n "moment 2\|normalized digest" docs/reference/HASH-TAXONOMY-2026-08-29.md` shows the struck-through correction, not a deletion
- `git diff --stat` touches only docs + the fidelity doc comment (no logic)

**Guards:** no code behavior changes in this phase.

---

## Phase 2 — Cut custody out of ingest

**Goal:** after this phase, NOTHING on the ingest path writes a custody tag.

**Implement:**
1. `server/evidence/custody.py:418-427` — the `INSERT INTO evidence.evidence_hash … level='H1', canon_version='h1-rawbytes-v1'` on every `ingest_artifact`. Change it to write the **context fingerprint** under `context-source-fingerprint-v1` into the context receipt table used by `hashing.go:217` (copy the write shape from `modules/engine/postgres/hash_repository.go:427-435` ref-kind mapping). Keep the SHA-256 computation (`_sha256_file`, `:228`) — it's the same number. Only the tag and destination change.
2. `verify_artifact` (`custody.py:458-462`) must keep working against the fingerprint row — update its lookup, don't delete it.
3. **Hash moment 2 STAYS — owner-ruled 2026-09-03.** `HashNormalizedRecords`, `HashNormalizedGeneration`, and `verify_normalized_generation_activity` (`normalized_pipeline.go:341-418`) remain in the DAG unchanged, as do the `sql/0036` seal-trigger preconditions that require their receipts. Their role is integrity verification of each normalized generation (contiguous ordinals, canon check, reproducible fold, refuse-on-zero), which cross-platform reassembly depends on. `TestFiveHashComputationStagesAreDistinct` continues to assert **five**. Only their DOCUMENTATION changes: the activity/package comments must say verification-not-custody explicitly, citing this ruling, so no future session re-derives the deletion. **One structural requirement (owner, 2026-09-03): the same verification shape will be reused on the evidence side once material is promoted.** `VerifyNormalizedGeneration` already reads through a store interface (`a.Store.OpenNormalizedGenerationRecords`, `normalized_pipeline.go:360`); keep it generic over a generation source so the evidence mirror satisfies the same interface — do NOT fork a second verifier.
4. Confirm by grep that the two normalized tags never appear anywhere a custody tag is expected (`grep -rn "normalized-record-postgresql18\|normalized-generation-ordered" server/evidence/` → 0).
5. **DONE 2026-09-07 (Claude Code · Fable 5.1): constant renamed to `eltContextFingerprintCanon` = `context-rawrecord-fingerprint-duckdb-json-v1`; `raw.*` `content_canon` defaults moved to `context-rawrecord-fingerprint-v1` in `schema_snapshot_20260907.sql`, applied live by the 2026-09-07 rebuild; test `TestEltCanonIsAContextFingerprintNotCustodyH2` guards both.** Original item: Resolve the ELT open question at `elt_structured_repository.go:33-49`: `raw.<format>.content_hash` is a **context fingerprint**. Rename the constant at `:65` from `h2-rawelement-duckdb-json-v1` to `context-rawrecord-duckdb-json-fingerprint-v1` and update the SQL defaults at `sql/0009_raw_layer_and_derivation.sql:111` and `schema_baseline.sql:4678,4710,4742,4774,4830,4889` via a NEW migration (never edit an applied one). Strike the open-question comment with the resolution.

**Verification:**
- `grep -rn "h1-rawbytes-v1\|h2-rawelement-v1\|h3-chain" server/ modules/engine --include=*.py --include=*.go | grep -v vendor | grep -v _test | grep -v promotion` → **zero hits outside the (not-yet-built) promotion package** and the constant declarations at `hashing.go:28-31`
- `go test ./stagegraph/` passes with the hash-stage count still = 5
- `uv run pytest tests/ -k custody` passes; `verify_artifact` test still green
- Replay test: an in-flight workflow history recorded before the gate still replays (copy the pattern from `proffer/workflow_test.go`)

**Guards:** never edit an applied migration; the `GetVersion` gate is mandatory or live runs break on redeploy; keep the SHA-256 computation, only retag.

---

## Phase 3 — Wire chunking in early; one activity per file; parallel chunks

**Goal:** the workflow shape the owner described.

**Implement:**
1. Add `chunk_document_activity` to `stagegraph.Stages` and the DAG in `registry.go`. **Owner ruling: chunk EVERYTHING, always, parse-then-chunk.** Already-normalized text (markdown, plain text) still passes through the parse stage as a whole-file record (`generic/whole_file_fallback.py` exists for exactly this) and then chunks — so there is ONE entry point, not two, and the OR-branch concern in `stage.go:79-106` dissolves. Read that comment anyway before editing so its original reasoning is recorded as superseded, not deleted.
2. Chunk hashing: the chunker already emits `ContentHash` and byte ranges (`chunk.go:150-167`). Persist them to `working.content_chunk.content_sha256` — copy the repository write shape from `modules/engine/postgres/chunk_repository.go` (built in C1, 2026-09-02).
3. Per-file activity: introduce a `IngestFileWorkflow` (child workflow) in `modules/engine/proffer/ (formerly uiw/)` that runs the existing stage sequence for ONE source. The batch entry point fans out one child per file — copy the child-workflow shape from the Temporal Go SDK vendored at `modules/engine/vendor/go.temporal.io/sdk/workflow/` (`ExecuteChildWorkflow`). Do not invent a fan-out helper; the SDK has one.
4. Parallel chunks: inside the per-file activity, chunk processing (fingerprint/persist) fans out with a bounded `errgroup` — copy the concurrency pattern already used in `hashing.go:291-365` if present, else the standard `golang.org/x/sync/errgroup` (check `go.mod` before adding).
5. Heartbeat: any activity that processes a multi-GB file must call `activity.RecordHeartbeat` — copy from wherever the vendored SDK examples do it; the 86 GB SMS/MMS bucket has single files that need it.

**Verification:**
- `go test ./stagegraph/` — chunk stage present, DAG acyclic, dependency test passes
- `go test ./proffer/` — child-workflow fan-out test: 3 fixtures → 3 child runs
- Live: start a batch of 3 fixtures via the starter; Temporal UI shows 3 child workflows
- Chunk rows carry `content_sha256` and the validator's lossless-coverage check is exercised in a test

**Guards:** the chunker never hashes for custody; chunk hashes are verification only. No activity may exceed Temporal's default start-to-close without heartbeating.

---

## Phase 4 — Build promotion (greenfield): project into `evidence.*`, FK to working rows

**Goal:** R04. The only place custody tags are ever written. Evidence is a
**projection** of working data into the guarded schema — the same shape as the
ADR-0052 CDC fan-out into graph and vectors — never a mutation of working rows.

**Implement** — new package `modules/engine/promotion/`, new activity `promote_source_version_activity`:
1. Input: `source_version_ref` + the operator's decision receipt (copy the request/receipt shape from `activities/repair.go:100-140`, which already models an operator-gated activity).
2. Re-read the sealed original via the acquisition resolver (`acquisition.NewSchemeRouter` — same one the gateway uses). Recompute SHA-256; assert equal to the intake `context_source_fingerprint`. **Mismatch → fail closed, no promotion.**
3. Re-parse through the SAME parser id+version recorded on the source version (`postgres/parser_activity_store.go` persists it). Re-chunk.
4. **Verify against working rows:** for every produced chunk, look up the existing `working.content_chunk` row by `(source_version, byte_start, byte_end)`; assert `content_sha256` equal. Any mismatch → surface the diff as a receipt and **stop** — the exhibit must be the thing that was reviewed. Never mutate the working row.
5. On full match, **write the evidence projection**: new rows in `evidence.*`. The 7 existing tables are `acquisition`, `artifact_metadata`, `custody_event`, `evidence_hash`, `evidence_item`, `ingest_run`, `source` — reuse `evidence_item` if its shape fits a chunk/message row; otherwise a NEW migration adds **mirror** tables (`evidence.message`, `evidence.chunk`) whose columns mirror `working.*`. Then write one `working_evidence_link` row per promoted record (`working_id`, `evidence_id`, `promotion_receipt_ref`, `linked_at`). The link table is the ONLY join, it is append-only, and it never touches the working row.
6. Write custody on the evidence rows — H1 (`HashFileH1`, tag `h1-rawbytes-v1`), H2 per raw record span (`HashRecordH2`, `h2-rawelement-v1`), H3 fold (`ChainH3`, `h3-chain-sbv-genesisempty-v1`) — into `evidence.evidence_hash` using the column contract at `server/evidence/custody.py:415-432`.
6b. **Evidence-generation integrity verification (owner, 2026-09-03: "reuse that same shape and process… on the other side")**: run the SAME verifier used for normalized generations against the evidence projection — contiguous ordinals, canon check, reproducible fold, refuse-on-zero, verification receipt — by having the `evidence.*` mirror implement the generation-store interface the verifier already consumes. Its receipt sits beside the custody receipts. On the evidence side this is verification AND it is paired with custody, which is the only place the two families meet.
7. Message-level check (**owner-ruled KEEP, 2026-09-03**): for each promoted message, compute `fidelity.Digest` from the fresh re-parse and from the working row; assert equal. This is the mechanical proof the row's D-136-protected fields (content, timestamp, handle, direction) were not edited during the working period — chunk hashes cannot provide it because operators edit rows, not the file. **Store the digest on the evidence row** (`evidence.<mirror>.fidelity_digest`, with canon tag `fidelity-content-ts-handle-dir-v1`). That stored value is what hash moment 4 recomputes later: reverification of an evidence row = recompute `fidelity.Digest` from its own fields and compare, proving no post-promotion tampering. Honest scope: this does NOT catch a consistent parser bug (same wrong answer both times); only human review does.
8. Working rows are untouched and keep evolving — investigation continues after promotion; the evidence rows are the frozen snapshot under the D-128 guards. **Promotion writes NOTHING to Weaviate, Neo4j, or Surreal** — every projection points at the hub and reaches evidence through the link table. There is no metadata patch to the search surface: Weaviate is a search projection only (D-080), and the horizon walks that need evidence-awareness run in the ANALYSIS phase, exclusively in SurrealDB (D-073). A draft of this plan invented a Weaviate pre-filter tension from the superseded §1 retrieval design; that was a recall defect and is struck here so it is not re-derived.
9. Register under `stagegraph` as its own stage; it is NOT part of the ingest DAG. It is invoked by the operator's decision, not by ingest completion.

**Verification:**
- Unit: byte-identical re-parse → promotes; one altered byte in the original → refuses at step 2; one altered stored chunk → refuses at step 4 with a diff receipt; a swapped-direction message → refuses at step 7
- `grep -rn "h1-rawbytes-v1\|h2-rawelement-v1\|h3-chain" modules/engine server --include=*.go --include=*.py | grep -v vendor | grep -v _test` → hits ONLY in `modules/engine/promotion/` and the constant declarations
- `grep -n "UPDATE working\.\|DELETE FROM working\." modules/engine/promotion/` → **0** (promotion never mutates working)
- Live: promote the synthetic fixture (`upload://72640c6c…`, 95 messages, 555-numbers); `evidence.evidence_hash` gains H1 + 95 H2 + 1 H3; `evidence.*` gains 95 message rows each with a valid FK; `working.content_chunk` row count and every `id` are unchanged (snapshot ids before/after)
- The evidence generation passes the same verifier as the normalized one: one `verify` receipt per promoted generation, refuse-on-zero exercised
- Every evidence row's FK resolves: `SELECT count(*) FROM evidence.message e LEFT JOIN working.content_chunk w ON w.id = e.working_chunk_id WHERE w.id IS NULL` → 0

**Guards:** never mutate working rows; evidence only in `evidence.*`; never promote on any mismatch; custody tags nowhere else; reuse existing `evidence.*` tables before adding new ones.

## Phase 5 — Deploy and rehearse on real data

**Blocked on the owner for two actions** (unchanged since 2026-09-02): mint a tagged (`tag:docker`) Tailscale auth key for the gateway, and add the shared materialize mount to platform-tools.

**Implement:**
1. Deploy `deploy/tool-gateway.yaml` on ovh-app (host dirs already prepped at `/data/agno/volumes/tool-gateway/`). Confirm `svc:tool-gateway` appears in `tailscale serve status`.
2. Rehearsal on the synthetic fixture through the full new shape: batch → per-file child → chunk → fingerprint → preview → operator approve → **promotion**.
3. First real ingest: **Google Voice** — ~29,300 HTML conversation files across `r2:casebible-raw` and `r2:casebible-sorted` (inventory `docs/reviews/2026-09-03-r2-messaging-inventory-and-export-shapes.md`), parser `google_voice_html` already registered, zero new code. Run as a batch; do not promote anything real without the owner present.

**Verification:**
- Gateway `GET /healthz` 200 over its Service FQDN; `POST /tools/repair.detect/run` with an `upload://` locator returns 200 (the 2026-09-02 404 is gone)
- Temporal UI: one child workflow per file; no activity exceeds heartbeat timeout
- A Google Voice batch of 50 files completes with 0 silent-empty results (`stats.record_count > 0` or a raised error, never 0 without error)

---

## Phase 6 — Verification sweep

1. Anti-pattern grep (run all, expect the stated results):
   - custody tags outside promotion → 0
   - `uuidv7()` regeneration in promotion → 0 (`grep -n "uuidv7\|NewString" modules/engine/promotion/`)
   - `return None` / empty-set on unrecognized shape in any parser → review each hit
2. `go build ./... && go vet ./... && go test ./...` in `modules/engine/` — green
3. `uv run ruff check server tests && uv run mypy server && uv run pytest -q` — green, and the pre-existing 26 failures (deploy-contract drift, `FrozenInstanceError`, opencode-ops) are either fixed or explicitly listed as out of scope with their cause
4. Doc drift: `grep -rn "hash moment 2\|normalized digest at normalization" docs/` shows only struck-through, dated corrections
5. Live proof, not inferred: Temporal UI screenshot of a completed promotion; `SELECT count(*) FROM evidence.evidence_hash WHERE level IN ('H1','H2','H3')` matches the fixture's 1 + 95 + 1

---

## What this plan deliberately does NOT do

- It does not touch AI-chat ingest (`transcripts.*`, D-082). Those never promote and never get custody.
- ~~It does not rename the repo or the Go module (parked; see D-131/naming thread).~~ **Corrected 2026-09-05 (D-137..D-141):** naming is no longer parked — the product/component naming canon is ruled (this repo is **Indicia Probata** / `probata`; the import lane is **proffer**; see `docs/NAMING.md`). This plan still does not execute the mechanical GitHub repo rename, Go module path rewrite (97+ imports), parent gitlink update, or Coolify remote rename — that is its own plan, per D-138's execution note.
- It does not build the screenshot→message OCR inference lane (separate; ADR-0053 rung 3 provider is still unselected).
- It does not stand up Authentik (D-133; separate).
