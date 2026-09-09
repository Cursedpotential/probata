# FCT bundle → platform context-layer import mapping

> _Byline: Claude Code · Sonnet 5 · 2026-09-07 (owner order 2026-09-07 13:16: "create an
> adapter or import/export mechanism to export to the platform")._

STATUS: ITERATING — the family-court-toolkit (FCT) plugin's export bundle shape is being
built concurrently with this importer; several field-name assumptions below are inferred
from `E:\AI_Workspace\casebible\_intake\extracted-json-20260907\_SCHEMA-case-extract-v1.md`
(the closest documented field vocabulary at the time this was written) and will need a
one-line reconciliation pass once the plugin ships its first real bundle — the importer's
own `--dry-run` validation-error output is the mechanism for catching drift, by design.

## What this importer does and does not do

- Reads a bundle directory (`manifest.json` + one `<table>.ndjson` per table +
  `edges.ndjson`) written by the FCT plugin.
- Maps bundle records onto EXISTING platform tables only. **No schema change is
  proposed or applied anywhere in this pass** (owner instruction).
- Writes only into tables the schema already designed to receive exactly this shape of
  externally-produced, pending-review data: `working.candidate_entity`,
  `working.candidate_event`, `working.candidate_fact`, `timeline.event_candidate`, and
  `context.source`. Every one of these is a **candidate** landing zone — per the live
  comment on `timeline.event_candidate` (D-082): *"CANDIDATE authority only — an
  AI-chat-derived row is a lead, never evidence. A correction is a NEW row, never an edit
  to this one."* That is exactly the posture an externally-authored plugin bundle should
  land at.
- **Never** writes to `registry.*` (identity registry — a case is the coordinate system
  analysis happens in, not something bulk-imported into) or `evidence.*` (the
  evidence-tier promotion gate is a deliberate human action per D-145's ingest lifecycle
  — "owner reads context, sends to Surreal, analyzes, THEN promotes to evidence"; never a
  bare "promote"). It never touches `reference.*` either — per the standing rule that
  "reference data is the ruler, not the subject" (curated taxonomy only, never
  bulk-loaded case data).
- Where no clean, schema-change-free home exists, the bundle table is counted and
  reported as **UNMAPPED**; the importer never force-fits a record into a table whose
  constraints don't actually describe it.

## Schema source

`sql/bootstrap/schema_snapshot_20260907.sql` (newest snapshot; per D-142/D-152 this file
**is** the database — no migrations, the snapshot in its final form is applied via
`scripts/rebuild_platform_from_snapshot.sh`).

## Mapping table

| Bundle table | Target table | Column map (bundle → target) | Notes |
|---|---|---|---|
| `person` | `working.candidate_entity` | `name`→`name`/`normalized_name`; `role`,`aliases`,`relationship`,`contact`,`notes`→`attrs`; `confidence`(high/medium/low or 0..1)→`confidence`; whole record→`content_sha256`; the bundle's per-record `source` provenance block→`attrs.provenance` | `entity_type='person'`. `extraction_run_id` FK'd to one `working.extraction_run` row created per import (see below). |
| `child` | `working.candidate_entity` | same as `person`, plus **defensive redaction**: `dob`/`ssn`/`address`/`school`/`birthdate`/`date_of_birth` keys are stripped from the record before it ever reaches `attrs`, even if present — the bundle's own `manifest.redaction.children = "initials+age"` contract is the floor, not something this importer will accidentally widen. `contact` is also dropped for children. | `entity_type='person'`, `attrs.role='child'` (from the bundle's own `role` field if set). |
| `court` | `working.candidate_entity` | `court`/`name`/`title`→`name`; `jurisdiction`,`judge_or_referee`→`attrs` | `entity_type='organization'` (candidate_entity's `entity_type` CHECK has no `'court'` value; `attrs.entity_subtype='court'` carries the distinction without a schema change). |
| `event` (master-timeline narrative) | `working.candidate_event` | `description`→`summary`; `occurred_at`→`occurred_at`; `known_at`,`location`,`participants`,`evidence_refs`,`factors`,`tags`,`quote`,`source_locator`,`occurred_text`→`attrs`; `confidence`→`confidence` | `event_type='narrative_event'`. **Validation error, not a crash**, if `occurred_at` is missing/`"unknown"` — `working.candidate_event` has a `CHECK` requiring `occurred_at` or a `validity` range, and this importer has no validity-range source yet. |
| `note` | `working.candidate_fact` | `text`→`statement`; `kind`→`predicate` (default `'note'`); `about`,`author`→`attrs` | `subject_entity_id`/`object_entity_id` left NULL — no entity-resolution/linking pass exists yet (documented as future work, not attempted here). |
| `order` | `timeline.event_candidate` | `title`/`description`→`display_summary`; `date`→`occurred_at`; everything else→`source_locator.extra` | `event_type='court_order'`. `source_record_version` = the record's own content-hash hex (see idempotency below). |
| `hearing` | `timeline.event_candidate` | same shape as `order` | `event_type='hearing'`. |
| `deadline` | `timeline.event_candidate` | same shape as `order` | `event_type='deadline'`. |
| `court_event` | `timeline.event_candidate` | same shape as `order`; `kind`→`event_type` directly (falls back to `'court_event'`) | Preserves the case-extract-v1 `kind` enum (hearing/order/filing/service/deadline/referee-recommendation/objection/conference/foc-appointment/evaluation-appointment) as free text — `event_type` here is `text`, not an enum, so no value is rejected. |
| `filing` (event dimension only) | `timeline.event_candidate` | `title`→`display_summary`; `date`→`occurred_at`; `filed_or_planned` (a status enum, NOT a date — see the code comment) →`source_locator.extra` | `event_type='filing'`. Only the "something happened/will happen on a date" half of a filing is mapped this way — see **UNMAPPED** below for the document half. |
| `source` | `context.source` | `path`/`source_key`/`id`→`source_key`; `authored_by`→`provenance_class` (`owner`→`first_party_authored`, `court`/`third-party`→`acquired_third_party`, `ai:*`→`system_generated`, else `unknown`) | No `extraction_run_id` — `context.source` has no such column and needs none; it is the intake-file registration table, not a candidate-fact table. |
| `edges.ndjson` (`{from,to,edge}`) | — | — | **UNMAPPED.** No generic typed-edge table exists at the context tier; the only typed links available (`candidate_event.primary_entity_id`, `candidate_fact.subject_entity_id`/`object_entity_id`) require entity resolution this importer does not attempt. Counted and reported, never dropped silently. |

## UNMAPPED bundle tables (no clean, schema-change-free home)

| Bundle table | Why unmapped |
|---|---|
| `message` | `working.chat_message`/`chat_conversation` are explicitly scoped to **AI-chat exports** (live comment: *"PER-SOURCE conversation: one AI-chat export's conversation"*), and `chat_message.role` is `CHECK`-constrained to `user\|assistant\|system\|tool\|unknown` — forcing a real person's name into that enum would be a lossy, incorrect mapping. `working.third_party_message`/`third_party_conversation` are the semantically-correct acquired-communications tables, but both carry hard `NOT NULL` FKs into `working.artifact_registry` (`source_artifact_id`) and `working.normalized_record` (`normalized_record_id`) — landing a bundle message there would require this importer to *first* synthesize artifact-registry and normalized-record rows with their own required fields (`sha256`, `created_by`, `content_hash`, `deriver_version`, …), which is a design decision the owner has not made yet, not a column-mapping exercise. |
| `exhibit` | `working.context_asset` is explicitly scoped to *"generated docs/code/images from a chat-export archive"* — not general case exhibits. `working.artifact_registry` is the platform's "created works" vocabulary (owner ruling: *"artifact" = created WORKS (AI chats, generated documents/code)*), which an evidence photo/PDF is not. `evidence.*` requires the deliberate human promotion gate (D-145) this importer must never bypass. No clean landing zone exists without a design decision. |
| `factor` (MCL 722.23 tagging) | `analysis.factor_citation` exists and is shaped for this, but it is an **analysis-tier** (interpretive/conclusory) table, out of the context-layer scope this task defined. Left for a future analysis-layer importer. |
| `draft`, `memo` | Same "created work" gap as `exhibit` — `working.artifact_registry` is vocabulary-adjacent but its `assertion_type` column (`raw_evidence\|extracted_fact\|inferred_fact\|analytical_finding\|legal_conclusion`) describes a *claim*, not "here is a drafted motion." Forcing a value in would misrepresent what the row is. |
| `reference` (legal authorities/rules cited) | Hard standing rule: *"Reference data is the ruler, not the subject … reference stays. period."* `reference.*` tables are curated taxonomy, never bulk-loaded from an external source, however well the columns happen to fit. |
| `evidence_log` | Ambiguous target (custody-event replay vs. a work log) genuinely requires an owner decision; `evidence.custody_event`/`ops.audit_ledger` are both infra tables with their own invariants, not a content-import target. |
| `eval` (custody-evaluation appointments/reports) | Same document/exhibit-shaped gap as `exhibit` — this is evaluator-report content, not a timeline event. |
| `case_status` | Would either (a) risk creating a **duplicate** `registry.matter`/`registry.court_case` row for a case that should already exist exactly once in the identity registry, or (b) require a lookup-only reconciliation this importer does not attempt. Registry rows are identity truth, never re-created per import. |

## Idempotency

Every mapped target table already has a real unique index — no pre-check branch was
needed:

| Target | Unique key | Behavior on re-import |
|---|---|---|
| `working.candidate_entity` | `(source_raw_table, source_raw_id, content_sha256)` | Same content → `ON CONFLICT DO NOTHING`. Corrected content → new row (claims accumulate, never rewritten — matches the platform's `claim_candidate` doctrine). |
| `working.candidate_event` | same shape | same behavior |
| `working.candidate_fact` | same shape | same behavior |
| `timeline.event_candidate` | `(source_system, source_record_id, source_record_version)` | `source_record_version` is set to the record's own content-hash hex (not left NULL — Postgres unique indexes treat NULL as distinct every time, which would silently defeat dedup) so a corrected record lands as a new, distinguishable row (D-082: "a correction is a new row, never an edit"). |
| `context.source` | `(source_key)` | `ON CONFLICT DO NOTHING`. |

## Extraction-run bookkeeping

One `working.extraction_run` row is created per invocation (`extractor='fct_bundle_importer'`,
`extractor_version=<script version>`, `source_summary=<bundle path>`, `status='completed'`,
`stats={"planned_inserts": N}`). This is the FK every `candidate_*` row already requires
(`working.extraction_run` comment: *"Every candidate FKs here so a bad model version can
be traced and its output re-reviewed or discarded wholesale"*) — creating it is a normal
insert into an existing operational table the pipeline was designed to receive, not a
schema change.

## Live verification

Ran 2026-09-07 against the live tailnet database (`100.91.190.107`, database
`platform`) with a 9-record synthetic bundle (`person`, `child`, `event`,
`hearing`, `filing`, `source`, plus one each of the two UNMAPPED types
`message`/`exhibit` and one `edges.ndjson` row, to prove they are correctly
reported rather than silently imported).

**Live gotcha found and fixed during this verification:** the shared
`~/.secrets/probata.env` file's own `DB_DATABASE` value resolves to the legacy
`ai` database (connecting with it 500s `FATAL: database "ai" does not exist"`
— that database has since been dropped/never existed on this host under that
name). Every table this importer writes to lives in `platform`, the platform's
actual current database (D-142). `resolve_db_settings()` therefore
deliberately does NOT consult the secrets file for `dbname` — only an explicit
`DB_DATABASE` env var overrides its hardcoded `"platform"` default. Host/port/
user/password still come from the secrets file as usual.

```
$ DB_DATABASE=platform uv run python scripts/import_fct_bundle.py --bundle <synthetic bundle> --apply
FCT bundle import — APPLY - ROLLBACK MODE (pass --commit to persist)
database: reachable (100.91.190.107)
table          target                         rows  planned  errors
person         working.candidate_entity          1        1       0
child          working.candidate_entity          1        1       0
hearing        timeline.event_candidate          1        1       0
event          working.candidate_event           1        1       0
message        UNMAPPED                          1        0       0
exhibit        UNMAPPED                          1        0       0
source         context.source                    1        1       0
filing         timeline.event_candidate          1        1       0
edges          UNMAPPED (out of scope)           1        0       0
insert-vs-already-present (from the database round trip):
  working.candidate_entity     inserted=    2  already-present=    0
  timeline.event_candidate     inserted=    2  already-present=    0
  working.candidate_event      inserted=    1  already-present=    0
  context.source               inserted=    1  already-present=    0
validation errors: none
```

Post-run verification query (separate connection, after the rollback) confirmed
**zero residue** — `working.candidate_entity`/`timeline.event_candidate`/
`context.source`/`working.extraction_run` all returned 0 rows matching the
synthetic bundle's ids, proving the rollback-by-default behavior actually holds
against the live database and not just in the script's own bookkeeping.

`--dry-run` (no `--apply`) was also run against the same bundle and produced
identical counts via its own always-rolled-back round trip, confirming dry-run
and apply-without-commit agree exactly, as designed.
