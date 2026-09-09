# `case-extract/v1` — framework-fit review and schema map

> _Byline: Claude Code subagent · Opus 5 · 2026-09-07_

STATUS: REVIEW — owner ratifies; nothing applied

Scope: a read-only review of the 2026-09-07 extraction set at
`E:\AI_Workspace\casebible\_intake\extracted-json-20260907\` against this repository's canon
and against the live schema of record, `sql/bootstrap/schema_snapshot_20260907.sql`
(D-152/D-153: the snapshot **is** the database). No repository file other than this one was
written; no extract file was modified; nothing was applied to any database.

**No real names appear in this document.** Records are cited by id (`C4-114`), people by role
(`owner`, `other-parent`, `child`, `attorney`, `judge`, `FOC`).

## Corpus shape (measured)

> ⚠ **The extraction job was still running during this review.** Row E4 grew from 1,455 to 2,476
> records between the profiling load (~15:05) and the final recount (~16:40); the tree grew from
> 447 to 550 JSON files. Two number sets appear below and are labelled: **(final)** = a full
> recount at 16:40; **(profile)** = the DuckDB load used for the field-union and vocabulary
> analysis in §2, a 429-envelope / 885,433-record snapshot. Profile-derived per-field counts are
> therefore **lower bounds**, not stale — nothing was removed, only added.

| Measure | Value |
|---|---|
| JSON files under the set **(final)** | 550 |
| Valid `case-extract/v1` envelopes **(final)** | **521** (6 non-envelope; the rest are `_INDEX*.json`) |
| Records across all envelopes **(final)** | **886,769** |
| Record `id` values — distinct / duplicated **(profile)** | 885,433 / **0** |
| Record types observed | **14** (13 documented + 1 undocumented `property`) |
| Distinct `type`→field pairs (the real field union) **(profile)** | **213** |
| Envelope `authored_by`: AI-authored **(profile)** | 184 (43%) across 6 vendor spellings |
| Envelope `authored_by`: `unknown` **(profile)** | 203 (47%) |
| Envelope `authored_by`: `owner` / `third-party` **(profile)** | 37 (8.6%) / 5 (1.2%) |
| Envelope `confidence`: high / medium / low **(profile)** | 225 / 193 / 11 |
| `source.sha256` that is **not** a 64-hex digest **(final)** | **176 envelopes** (`"n/a-slice-of-larger-export"`, `"n/a (multi-file)"`) |

**The single most important number here is the record split.** Of 886,769 records,
**879,452 (99.17%) are bulk inventory or bulk export rows** that do not belong in a case-extract
lane at all:

| Bulk block | Records (final) | What it actually is |
|---|---|---|
| D3 `exhibit` | 590,560 | The R2 object catalog (`md5` + `path` only) — a Case Bible catalog table |
| B4 `exhibit` | 154,575 | A filesystem inventory listing |
| C3 `event` + `note` | 121,503 | GPS waypoints / stay-points from the location lane (99.99% carry `tags:["geo"]`) |
| B1 `message` | 12,814 | One SMS export, already a first-class ingest lane |
| **Bulk subtotal** | **879,452** | |
| **Case-narrative / analytic remainder** | **7,317** | The material this review is actually about |

The 7,317 remainder **(final)**: `note` 2,642 · `source_authority` 1,602 · `event` 831 ·
`person` 574 · `entity_rule` 386 · `issue` 379 · `message` 252 · `draft` 149 · `goal` 132 ·
`exhibit` 123 · `court_event` 113 · `filing` 67 · `risk` 66 · `property` 1.
By row: A2 2,711 · E4 2,476 · C4 665 · C6 284 · A3 205 · C5 192 · C1 156 · A4 141 · E3 111 ·
D1 107 · E1 92 · D2 66 · A1 49 · E5 37 · E2 25.

---

## 1. What the extracts are, in framework terms

### 1.1 Source classification under canon

The extract sources are, by the envelopes' own `authored_by` field: AI-authored strategy memos and
AI chat exports (184 envelopes, 43%), owner-authored documents and prompts (37, 8.6%), material of
unrecorded authorship (203, 47%), and third-party documents (5). Cross-tabulating record type
against envelope authorship shows the case-narrative types are overwhelmingly AI-authored —
`ai:perplexity` alone produced 407 `source_authority`, 292 `person`, 264 `event`, 160 `issue`,
82 `draft`, 45 `court_event`, 25 `filing`, 24 `risk` records.

**D-082 governs the whole set.** "AI chats are permanently context-only and are never promoted to
evidence… the AI chat itself is never an evidence anchor, corroborating source, or proof that the
event occurred." The canonical flow D-082 names is
`AI chat → extracted event/claim/lead → claim chart/list → evidence search → custody-backed
evidence → governed fact`. The extracts sit at step two of that chain, permanently.

Therefore, in framework vocabulary:

> **Every `case-extract/v1` record is a claim_candidate-class assertion *about* the case, made by
> a named author on a named date, carrying a provenance locator. It is never a fact, never
> evidence, and never a second authored spine.**

This is reinforced by three further rows. **D-142**: zero committed live evidence exists; the
precious set is `reference.*`, `analysis.human_label*`, the Case Bible catalog, and human-curated
docs — the extracts are none of those. **D-151(c)**: nothing ingested is evidence and the evidence
lane is out of scope; the only lane in play is ingest-through-to-context. **D-145/D-146**: the
lifecycle is context → owner reads → *send to Surreal* (an owner click) → *promote to evidence* (a
second owner click); an import can reach the first stage and no further.

### 1.2 What that implies per record type

| Extract type | What it actually asserts | Framework class | Never |
|---|---|---|---|
| `event` | *An author asserts that an event occurred at a stated time.* The record is the assertion, not the event. | Event candidate + (where it names a human act) a candidate **Action** (D-147) | Never a timeline fact; never an authored spine row |
| `court_event` | *An author asserts a docket/institutional event occurred or is scheduled.* 33 of 75 carry `date:"unknown"`; the C4 worked example `C4-114` asserts a filing with `date:"unknown"` and a `case_no`. | Court-event candidate | Never a docket of record. D1's own summary states every court form in that row has a blank case number and blank signature date — filing status with the court is **not** established by these files |
| `filing` | *An author asserts a document was filed / is planned / is draft-only.* 34 of 37 carry `filed_or_planned`; 12 say `filed`, none of them independently verified. | Filing candidate + a created-work pointer | Never proof of filing or service |
| `person` | *An author asserts a person exists in this case with a role.* | Entity candidate → resolution (never auto-merge) | Never a `registry.*` identity row |
| `message` | 12,814 first-party SMS rows (B1) are a real export; 19 (E4) are **messages reconstructed inside an AI chat**, and 191 (C6) are catalog rows. | TextUnit (D-147) for the real export; assertion-about-a-message for the reconstructed ones | The 19 reconstructed rows are never message evidence |
| `exhibit` | *An author asserts an object exists and would prove something.* 87 case-relevant rows; 76 of them have **no** `path`, `r2_path` or `sha256` at all. | Exhibit-candidate assertion (a pointer + a relevance claim) | Never an `evidence.*` row; never a custody anchor |
| `source_authority` | *An author cites a legal authority.* 1,393 rows, 543 distinct citations. Verification status: **493 `PROVISIONAL`, 88 `VERIFIED`, 22 `UNSUPPORTED`**, 790 with no status at all. 9 citations carry literal `<ungrounded-authority probable-jurisdiction="US-MI">` markup inside the citation string. | **Provisional citation register — reference-*like* but not reference** | **MUST NOT be written into `reference.*`.** See §1.3 |
| `issue` / `risk` / `goal` | Analytical assertions about the case (an argument, a risk, an objective). | `claim_assertion`-shaped, but the assertion tier is currently **unreachable** — see §4 gap 5 | Never findings; `analysis.finding` is analysis tier and out of scope (D-151c) |
| `note` | 2,380 case-relevant rows, `kind` ∈ todo(1,804)/finding(278)/strategy(135)/pattern(81)/definition(44)/advice(30)/question(12). Heterogeneous; mostly working notes. | Candidate fact / working note | Never a finding |
| `draft` | A created work — a drafted motion, letter, outline, memo. Owner vocabulary: "artifact" = created WORKS. | Artifact-registry candidate | Never evidence, never a filing |
| `entity_rule` | 343 AI-proposed detection patterns with 70+ distinct free-text `category` values and `severity` values like `"8-10 (strong indicator of coercive control)"`. | Proposed pattern candidates | **MUST NOT be written into `reference.detection_pattern` / `reference.behavior_category`** — see §1.3 |
| `property` (1 row, `E4-65-3`) | Out-of-vocabulary type invented mid-run. | — | Fails the schema; must be re-typed or the vocabulary extended deliberately |

### 1.3 `source_authority` and `entity_rule`: reference-like, but not reference

The standing rule is that **reference data is the ruler, not the subject** — `reference.*` is what
evidence is *compared against* and *classified into*, curated by hand, loaded whole, never
FK-bound to operational tables. D-152's rebuild verified the keep set (`reference.detection_pattern`
527 rows, labels 1,918) row-for-row.

`source_authority` rows fail every test for reference material: they are AI-proposed, 35% carry
`PROVISIONAL` and 1.6% carry `UNSUPPORTED`, some carry hallucination-guard markup verbatim in the
citation string, and one is a `citation` for a statute the extractor itself flagged as unverified.
`entity_rule` rows fail equally: the `category` vocabulary is unnormalised free text (70+ values,
mixing `AUTONOMY`, `alcohol_risk_child`, `Narcissistic Entitlement and Rage`, `mcl-factor`), and
`severity` is prose in 16 of 53 populated cases.

**Where they go instead:** a new working-tier candidate table (§4 gaps 1 and 3). They may be
*promoted into* `reference.*` later by a human curation pass, one at a time, never in bulk.

### 1.4 The knowledge-horizon rule applied

AGENTS.md §WHY and ADR-0059 require three concepts kept separate. Mapped onto the extracts:

| Concept | Extract field(s) | State today |
|---|---|---|
| `occurred_at` — event/valid time | `event.occurred_at`, `court_event.date`, `filing.date`, `message.sent_at`, `draft.date` | Present, but heterogeneous: 121,499 ISO-offset (geo), 306 literal `"unknown"`, 138 `YYYY-MM-DD`, 85 `YYYY-MM`, 29 `YYYY`, 24 naive datetimes |
| `source_available_from` — earliest horizon at which the source may be retrieved | **Absent.** The nearest proxy is envelope `source.source_date` (populated in 175 of 429 envelopes; `null` in 254) | **Critical gap** |
| Realization links — zero-to-many, "when the owner learned it" | `event.known_at` | Present in **21 of 122,081 event records (0.017%)** |
| `knowledge_time` — row-write audit | (platform-side only) | Correctly absent from the extracts |

**What a horizon-filtered walk must see and not see.** These documents are hindsight artifacts by
construction: an AI memo authored in late 2025 or 2026 narrating events from 2018–2025. Its
`source_available_from` is the memo's own authoring date — *never* the `occurred_at` of the events it
narrates. Consequences:

1. An ignorant-agent walk positioned before a memo's authoring date **must not retrieve any record
   from that memo**, however contemporaneous the event it describes. Retrieval gates on
   `source_available_from` **before** ranking (ADR-0059 §3).
2. Because 254 envelopes have `source_date: null`, there is currently **no defensible horizon value
   for 59% of the set**. Defaulting them to `extracted_at` (2026-09-07) is the safe, correct
   fallback — it makes them invisible to every historical horizon, which is the right failure mode.
   Defaulting them to `occurred_at` would be the contamination AGENTS.md warns about: "one leaked
   future fact makes the ignorant agent merely *smarter*; nothing fails and the delta is quietly
   worthless."
3. Any projection of these records into Weaviate must carry `source_available_from` as a typed
   date and apply it as a **dict filter** — agno's Weaviate adapter silently drops `FilterExpr`
   lists (AGENTS.md, re-verified at `weaviate.py:414-416`).
4. On any normalized projection these records are `disclosure_tier='hindsight'`
   (`working.normalized_record.disclosure_tier` CHECK ∈ `contemporaneous|hindsight|discovered`),
   never `contemporaneous`.

### 1.5 D-147 / D-148 applied: Actions, TextUnits, and where the contradiction label lives

| Extract material | SAT-lane class |
|---|---|
| `event` records whose `description` asserts a **human act** (refused, blocked, withheld, terminated a call, moved in with, drove to) | **Candidate Action.** `assertion_type` ∈ `said_did` / `observed`; `action_kind` ∈ `claimed_act` / `observed_act` per the label doc §A1 |
| `event` records describing a **state or period** ("the status quo period", "pre-birth relationship and cohabitation", every geo waypoint) | Not an Action. Interval facts |
| `message.body` (the 12,814 real SMS rows) | **TextUnit** — the carrier from which Actions are extracted, with a PG source coordinate |
| `draft.text`, `note.text`, `issue.summary`, `risk.mitigation`, `goal.title` | Neither. These are analytical assertions about the case |
| `court_event` | A docket/record event, explicitly **not** an Action under D-147 ("deletion/edit/unsend of a message is a record event… NOT an Action"). The *human act of filing* is separately an Action; the docket entry is not |

**Where the contradiction label lives: on the edge, not on the record.** D-148 requires two Action
nodes joined by a `CONTRADICTS` / `CHANGED_TO` edge carrying both PG source coordinates, both
timestamps, who asserted each, and who each was told to.

`case-extract/v1` has **no slot for this anywhere**. Yet the extraction job found at least two
textbook D-148 contradictions and recorded them **only as English prose in a job summary**:

- an FOC form question answered `YES` in an early draft (citing a specific May-2025 incident) and
  `NO` in the finalised version of the same document — a `commitment_vs_reversal` / self-correction
  pair with two distinct source coordinates in one file;
- an attorney surname spelled two different ways across three sources, "likely the same person, not
  reconciled" — an entity-resolution conflict, not a D-148 contradiction, but equally machine-invisible.

Both are unrecoverable by any downstream process. This is the single highest-value loss in the set:
the contradiction is the deliverable (AGENTS.md §WHY), and the extractor is finding them and
throwing them away into prose.

### 1.6 D-136 applied: immutable content vs custodian-asserted metadata

D-136's whole rule is three clauses: extract everything; never modify message content or
timestamps; everything else is operator discretion.

| Immutable (clause 2 — enforce mechanically) | Custodian-asserted (clause 3 — freely editable, no gate) |
|---|---|
| `message.body`, `message.sent_at` | `event.occurred_at` — this is an **asserted** event time, not a message timestamp |
| `draft.text` and any verbatim `quote` / `source_quote` span | `role`, `kind`, `status`, `priority`, `tier`, `strength`, `likelihood`, `impact` |
| `exhibit.sha256` / `exhibit.md5` | `factors`, `tags`, `confidence`, `description`, `summary`, `notes` |
| `source.sha256`, `source.bytes` | `court_event.date`, `filing.date`, `draft.date` (all asserted) |

The distinction matters concretely: correcting an event's `occurred_at` from `"unknown"` to a real
date is ordinary operator work requiring no ceremony; changing a message's `sent_at` is forbidden.
Do not build permission gates on the right-hand column (D-136 explicitly forbids that).

---

## 2. Field-by-field mapping, per record type

Conventions used below. **Target** columns are from `sql/bootstrap/schema_snapshot_20260907.sql`.
**Gap** is one of: `none` · `column missing` · `vocabulary mismatch` · `needs new table` ·
`type collision`. Where `scripts/import_fct_bundle.py` already chose a target, it is cited by line
and marked **agree** / **disagree**.

> **Counts in this section are from the DuckDB profile snapshot (429 envelopes / 885,433
> records, ~15:05) and are lower bounds** — the extractor was still writing row E4. Nothing
> was removed from the tree during the review; every count only grows. The failure counts in
> §6 Run B are against the final tree.

### 2.0 Envelope, identity, and dedup

| Extract field | Target | Transform | Gap |
|---|---|---|---|
| `schema` | — | validate `== "case-extract/v1"`, reject otherwise | none |
| `source.path` | `context.source.source_key` | verbatim path string | none — importer L486-488, `ON CONFLICT (source_key) DO NOTHING`. **agree** |
| `source.authored_by` | `context.source.provenance_class` | `owner`→`first_party_authored`; `court`/`third-party`→`acquired_third_party`; `ai:*`→`system_generated`; else `unknown` | none. **agree** with the importer's map. Note the CHECK vocabulary is exactly these 4 values |
| `source.sha256` | `context.hash_receipt` (`hash_kind='context_source_fingerprint'`, `construction='context-source-fingerprint-v1'`) | hex→`bytea`; **176 envelopes carry sentinel prose instead of a digest** and cannot produce a receipt | `column missing` — no. **data defect**: fix extractor-side (§3.14) |
| `source.bytes`, `source.kind`, `source.source_date` | `context.source_metadata.metadata` (`metadata_class='record_native'`) | jsonb passthrough | none |
| `extracted_at`, `extractor` | `working.extraction_run.started_at` / `.extractor` | one run row per import | none — importer L614. But that INSERT has **no `ON CONFLICT`**: every re-run creates a fresh `extraction_run` row even when all candidates conflict. Cosmetic, not a correctness bug |
| `confidence` (`high`/`medium`/`low`) | `working.candidate_*.confidence` (double 0..1) | importer maps `high→0.9, medium→0.6, low→0.3` (L~270) | **disagree.** This invents a probability from a 3-level label. Keep the word in `attrs.confidence_label` as well, so the original is recoverable; a 0.9 that was never a 0.9 will be treated as one downstream |
| **`id`** (`C4-12`) | `working.candidate_*.source_raw_id`, with `source_raw_table = 'case_extract:<row>'` | verbatim | none — but see the identity strategy below |

**Stable identity strategy.** The envelope `sha256` is not usable as an identity root (176 envelopes
lack one). The record `id` alone is not stable either — the C4 merge note records that ids
`C4-1..C4-347` were **renumbered** after a duplicate-run collision, so the same assertion has
carried two different ids. Recommended composite:

```
source_raw_table = "case_extract:" || source.row                 -- e.g. "case_extract:C4"
source_raw_id    = record.id                                     -- e.g. "C4-114"
content_sha256   = sha256(canonical_json(record MINUS "id"))     -- id excluded on purpose
```

Excluding `id` from the content hash is the change that makes the C4 renumber survivable: the
platform's unique key is `(source_raw_table, source_raw_id, content_sha256)`, so an id change alone
still lands a second row, but a **content**-identical record re-imported under its original id
correctly no-ops. The importer today hashes the whole record including `id`
(`content_sha256()`, L~262) — **disagree**, exclude `id`.

**Dedup across the six text-identical duplicates C4 skipped.** `C4/_INDEX.json` lists 10 skipped
files, of which six are text-identical exports of one document (five `.docx` variants differing only
in resave metadata, one `.md` export). That equivalence exists **only in `_INDEX.json`** — it is not
in any envelope and would not survive an import. Recommended landing with zero schema change:
register each skipped file as its own `context.source` row (its path is a distinct `source_key`)
and record the equivalence as a `context.source_metadata` row on the *surviving* source, e.g.
`{"metadata_class":"record_native","metadata":{"text_identical_duplicates":[<paths>],
"method":"docx-rendered-text-equal"}}`. Extractor-side, emit `source.duplicate_of` (§3.8).

### 2.1 `person` (405 records)

| Extract field | Target | Transform | Gap |
|---|---|---|---|
| `name` | `working.candidate_entity.name` + `.normalized_name` | `lower(trim())` for normalized | none — importer L334, `entity_type='person'`. **agree** |
| `role` | `working.candidate_entity.attrs.role` | verbatim code | **vocabulary mismatch** — see below |
| `aliases[]`, `relationship`, `contact`, `notes`, `details` | `.attrs` | jsonb | none. **agree** |
| `dob` (14 records) | **dropped for children** | importer strips `dob`/`ssn`/`address`/`school`/`birthdate`/`date_of_birth` for `child` (L~285, `CHILD_STRIP_KEYS`) | none. **strong agree** — this is defence in depth and should stay |
| `name_text` (10) | `.attrs.name_text` | jsonb | none |
| `evidence_refs[]` (3) | `.attrs` | jsonb | none |
| (mention → identity) | `working.entity_mention` + `working.entity_resolution` | see below | `column missing` on the import path |

**`role` vocabulary.** The extract's 15-value vocabulary (`owner`, `other-parent`, `child`, `judge`,
`referee`, `foc`, `gal`, `attorney`, `witness`, `family`, `police`, `cps`, `school`, `medical`,
`other`) has **no lossless target**. `registry.person.role_in_case` CHECK allows only
`user|partner|child|witness|evaluator|attorney|third_party|neutral|unknown` — it has no `judge`,
`referee`, `foc`, `gal`, `police`, `cps`, `school`, `medical`, or `family`. `registry.person.connection_to`
CHECK allows `petitioner|respondent|child|mutual|third_party|unknown`. Neither covers the set.
Additionally, **19 of 405 `role` values are free prose**, not vocabulary — `"attorney for Defendant"`,
`"Plaintiff / pro se father"`, `"third-party / alleged DV offender"`, `"Friend of the Court / county
employee (alleged conflict)"`, `"minor child"`, `"Judge"` (capitalised). See §4 gap 4.

**`participants` → `entity_mention` / `entity_resolution`.** `working.entity_mention` takes
`surface_text` (citext), `mention_kind` (`name|phone|handle|email|pronoun|partial|address|device|other`),
`extraction_method`, `confidence`, `data_tier` (default `extracted`); `working.entity_resolution`
carries `mention_id → canonical_entity_id`, `match_method`, `requires_human_review` (default **true**),
`safe_for_legal_use` (default **false**). That is exactly the right shape for the extract's
`event.participants[]` (562 mentions over 259 events) and `person.name`. **The importer writes
neither table** — it leaves `subject_entity_id`/`object_entity_id` NULL and notes "no
entity-resolution/linking pass exists yet." **agree that resolution is out of scope; disagree that
mentions are** — writing `entity_mention` rows costs nothing, requires no resolution decision, and
is the only way the resolution pass later has something to resolve.

**Owner-as-invented-participant check (ADR-0059 §2).** I checked this directly. Seven distinct names
carry `role:"owner"`. Across 562 `event.participants[]` mentions, 168 name an owner-role person, and
**107 of those appear in envelopes not authored by the owner**. Those 107 are *legitimate*: an
AI-authored memo narrating the owner's own case correctly names him as a participant in events he
was in. The ADR-0059 prohibition is narrower — the owner must not be inserted into an **acquired
third-party conversation**'s participant set. Checking that surface: `message` records come from
exactly three envelopes — B1 (12,814, `authored_by: owner`, the owner's own SMS export,
first-party), C6 (191, catalog), and E4 (19, `authored_by: ai:perplexity`, a chat-export). **No
acquired-third-party conversation exists in this set**, so the specific ADR-0059 violation is
absent. It becomes live the moment a third-party export is extracted, and there is no field in
`case-extract/v1` that would express the boundary — see §3.13.

### 2.2 `event` (122,081 records; 582 case-narrative)

| Extract field | Target | Transform | Gap |
|---|---|---|---|
| `description` | `working.candidate_event.summary` (NOT NULL, len>0) | verbatim | none — importer L375, `event_type='narrative_event'`. **agree** |
| `occurred_at` (ISO) | `.occurred_at timestamptz` | ISO parse | none |
| `occurred_at:"unknown"` + `occurred_text` (264 records) | **`.validity tstzrange`** | resolve the prose to a range: `"Fall 2022"` → `["2022-09-01","2022-12-01")`; `"c. 1993 (Age ~8)"` → `["1993-01-01","1994-01-01")` | **The importer rejects these** as a validation error, reasoning it "has no validity-range source yet" (mapping doc, `event` row). **disagree.** `candidate_event`'s CHECK is `occurred_at IS NOT NULL OR validity IS NOT NULL` — `validity` is precisely the column for month/season/era-level assertions, and the extractor already preserved the raw text verbatim so the resolution is auditable. Rejecting them discards the *highest-value* case events (the biography and relationship-timeline rows) while importing 121,499 GPS waypoints |
| `occurred_at:"unknown"` with **no** text (41 records) | reject with a named error | — | correct to reject; these are unrecoverable |
| `known_at` (21 records) | `working.source_provenance.realized_at` + `.realized_at_state='proposed'` | keyed `(source_raw_table, source_raw_id)` — the same key the candidate row uses | **The importer writes no `source_provenance` row at all.** `disagree` — this is the realization clock ADR-0059 §3 requires, and the table already exists and already keys correctly |
| `location` — object (108,409, geo) / string (32) | `.attrs.location` | jsonb passthrough | **type collision** — same field name, two incompatible types |
| `participants[]` | `.attrs` + `working.entity_mention` | see §2.1 | as above |
| `evidence_refs[]` (71), `document_refs[]` (2) | `.attrs` | jsonb | none |
| `factors[]` — array of `a`–`l` (153) / **object** (121,499, geo waypoint metadata) | link by code to `reference.custody_factor.factor` (`ai.mcl_factor`) | letters verbatim; **never an FK** | **type collision** (see below) + **vocabulary mismatch**: 20 array values are `"MCL722.23(j)"`, `"MCL 722.23(a)-(l)"`, `"MCL400.1501"` rather than a bare letter |
| `tags[]` | `working.candidate_event.topic_tags text[]`, or `.attrs.tags` | `reference.knowledge_tag.slug` CHECK is `^[a-z0-9]+(?:-[a-z0-9]+)*$` — underscore tags (`substance_alcohol`, `love_bombing`) fail it | **vocabulary mismatch**: normalise `_`→`-` at import; do **not** widen the reference CHECK |
| `quote` (143) | `working.candidate_fact.evidence_quote` on a companion row, or `.attrs.quote` | verbatim, immutable (D-136) | none |
| `source_locator` | `timeline.event_candidate.source_locator jsonb` for timeline rows; `.attrs.source_locator` for candidate rows | see §2.13 | `column missing` on `working.candidate_event` |
| `confidence` (82) | `.confidence` | word→float | see §2.0 caveat |

**`factors` type collision is a hard defect.** In 121,499 C3 geo events, `factors` is an *object*
carrying `{"waypoint_id":…,"parent_id":…,"sequence":…,"accuracy_meters":…}` — waypoint metadata
reusing the name of the MCL 722.23 best-interest-factor field. Any consumer that types `factors` as
`string[]` (including a DuckDB cast, as I hit while profiling) errors on the whole column. This is
the clearest single argument for excluding the geo lane from `case-extract/v1` entirely (§3.15).

**`reference.custody_factor` linkage.** `reference.custody_factor` is keyed by
`factor ai.mcl_factor` (enum `a`–`l`) and carries `code_display`, `name`, `statutory_text`,
`is_key_factor`. Candidate rows store the **letter** in `topic_tags`/`attrs` and join by value.
**No FK from any operational table into `reference.*`** — D-152's rebuild explicitly verified
"0 FKs leaving reference" and that property must be preserved.

### 2.3 `court_event` (75 records)

| Extract field | Target | Transform | Gap |
|---|---|---|---|
| `kind` (10-value enum, clean in all 74 populated rows) | `timeline.event_candidate.event_type text` | verbatim (column is free text, no enum) | none — importer maps `court_event.kind → event_type` directly. **agree** |
| `date` (ISO 37 / `"unknown"` 33 / `YYYY-MM` 4 / null 1) | `.occurred_at` + `.temporal_precision` (CHECK `point|interval|uncertain`, NOT NULL) | ISO→`occurred_at`+`point`; `YYYY-MM`→`valid_from`/`valid_to`+`interval`; `"unknown"`→`uncertain` with both null | none — `timeline.event_candidate` already has the precision slot `working.candidate_event` lacks |
| `date_text` (9) / `occurred_text` (13) | `.source_locator.extra` | jsonb | none. **Two field names for one concept** — see §3.3 |
| `title` | `.display_summary` (NOT NULL) | verbatim | none. **agree** |
| `court`, `judge_or_referee`, `case_no`, `outcome`, `deadline_rule`, `document_refs[]` | `.source_locator.extra` jsonb | passthrough | `column missing` — none of these have a typed home at the candidate tier. `analysis.legal_timeline_event` has `case_id`/`event_type`/`participants` but is analysis tier with `case_id uuid NOT NULL` and a `safe_for_legal_use` gate, and is out of scope under D-151(c). Correct to keep them in jsonb for now |
| `status` (`past`/`upcoming`/`unknown`) | `.source_locator.extra.status` | verbatim | **vocabulary mismatch**: one of 75 carries a 130-character prose sentence in `status` |
| `judge_or_referee` (27) | also a `working.entity_mention` row (`mention_kind='name'`) | — | as §2.1 |

`analysis.time_assertion` (`valid_earliest`/`valid_latest`/`certainty ai.precision_class`/
`disclosure_horizon`/`author`/`superseded_by`) is the *correct eventual* home for a contested court
date — it is append-only and supersession-aware, which matches "a correction is a NEW row." But it
requires an `analysis.timeline_event.event_id`, which requires the analysis tier. **Out of scope
today; the right target after D-151(c) lifts.**

### 2.4 `filing` (37 records)

| Extract field | Target | Transform | Gap |
|---|---|---|---|
| `title` | `timeline.event_candidate.display_summary` (event half) **and** `working.artifact_registry.title` (document half) | one record produces two rows | none |
| `filed_or_planned` (`filed`/`planned`/`draft-only`/`unknown`) | `.source_locator.extra` | verbatim | none — importer notes correctly that this is a status enum, **not a date**. **agree** |
| `date` (14 ISO / 21 null / 2 `"unknown"`) | `.occurred_at` + `temporal_precision` | as §2.3 | none |
| `court`, `served_on`, `service_method`, `document_refs[]`, `related_court_event` | `.source_locator.extra` | jsonb | `column missing` (acceptable) |
| `status` | `.source_locator.extra.status` | verbatim | **vocabulary mismatch — worst case in the set.** 13 of 24 populated `status` values are full prose sentences up to 300 characters, e.g. one describes an unsigned template with a blank case number and full identifying data captured verbatim |
| `filed_by` (1), `legal_authority` (1) | `.source_locator.extra` | jsonb | none |

### 2.5 `draft` (104 records)

| Extract field | Target | Transform | Gap |
|---|---|---|---|
| `title` | `working.artifact_registry.title` | verbatim | none |
| `doc_type` (9-value enum, clean in all 104) | `.artifact_kind text` (free) | verbatim | none |
| `text` / the drafted body | `.content_inline`, and `.sha256 bytea` = `sha256(text)` | `sha256` is **NOT NULL** — must be computed from the extracted text | none once computed |
| `status` (`working`/`final`/`abandoned`) | `.status` (CHECK `draft|needs_review|active|approved|promoted|rejected|superseded|archived`) | `working→draft`, `final→active`, `abandoned→archived` (+ `archive_reason`, required by CHECK) | **vocabulary mismatch** (mappable). 3 of 97 `status` values are prose |
| `date`, `path`, `version`, `notes` | `.metadata_json` | jsonb | none |
| `authorities[]` (2), `factors[]` (2) | `.metadata_json` | jsonb | none |
| — | `.assertion_type ai.assertion_type` **NOT NULL** | `analytical_finding` for AI-authored drafts | **disagree with the mapping doc**, which lists `draft` as UNMAPPED because `assertion_type` "describes a *claim*, not 'here is a drafted motion.'" That is over-cautious. Every hard requirement is satisfiable with zero schema change: `sha256` from the text, `created_by` from `source.authored_by`, `artifact_kind='draft_document'`, `assertion_type='analytical_finding'` (never `extracted_fact`). The type is imprecise, not wrong, and `artifact_kind` carries the real distinction. `working.artifact_registry` is the "created works" table and a drafted motion is a created work by the owner's own vocabulary |
| — | `.created_by text` **NOT NULL** | `source.authored_by` verbatim (`ai:perplexity`, `owner`, …) | none |

### 2.6 `message` (13,024 records)

| Extract field | Target (first-party, B1) | Transform | Gap |
|---|---|---|---|
| `sent_at` | `working.normalized_record.occurred_at` | naive ISO — **12,815 of 13,024 carry no timezone**; 207 are `"unknown"` | `column missing` — no. **Data gap**: no tz. `working.normalized_record` has no tz column either; `working.third_party_message.tz`/`.raw_ts` do. Record the raw string |
| `from`, `to[]` | `.sender`, `.recipients jsonb` | verbatim | none |
| `body` | `.content` | **verbatim, immutable (D-136 clause 2)** | none |
| `platform` | `.source` / `.attrs.platform` | `sms` (12,819) / `other` (14) | none. The B1 summary correctly records that the export has no SMS/MMS distinguishing column, so MMS fidelity is unrecoverable |
| `thread_id`, `attachments[]` | `.attrs` | jsonb | none |
| — | `.message_corpus` (CHECK `first_party|acquired_third_party`) | `first_party` for B1 | **the extract has no field to derive this from** — §3.13 |
| `pattern_category`/`pattern_name`/`pattern_description`/`severity` (191 C6 rows) | `analysis.chunk_classification` (`labels text[]`, `severity int 0-10`, `review_state`) | — | analysis tier, out of scope today |

**The importer lists `message` as UNMAPPED** because `working.chat_message.role` is CHECK-constrained
to `user|assistant|system|tool|unknown` (forcing a person's name into it would be wrong) and
`working.third_party_message` carries hard NOT NULL FKs to `working.artifact_registry` and
`working.normalized_record`. **agree on the reasoning, disagree on the conclusion for B1**: an SMS
export is not a bundle record at all — it is a first-class ingest-lane source that belongs in
`raw.raw_sms` → normalize → `working.normalized_record`, not in a case-extract bundle. See §3.15.

The 19 E4 `message` records are different in kind: they are messages *reconstructed inside an AI
chat*. Under D-082 they are assertions that a message existed, not messages. They must land as
`working.candidate_fact` (`predicate='asserted_message'`) and **must never** reach
`working.normalized_record` or `third_party_message`, where they would become indistinguishable
from a real export.

### 2.7 `exhibit` (745,218 records; 87 case-relevant)

| Extract field | Target | Transform | Gap |
|---|---|---|---|
| `label_or_name` | `working.candidate_fact.statement` prefix, `.attrs.label_or_name` | verbatim | see below |
| `description` | `.statement` | verbatim | none |
| `tier` | `.attrs.tier` | 9 distinct values, of which `high/medium/low/critical/public/sealed` are code-like and `"not yet gathered — pre-hearing checklist item"` (11 rows) and `"hybrid public/sealed"` are prose | **vocabulary mismatch** |
| `path`, `r2_path`, `mime`, `size` | `.attrs` | jsonb. `size` is a **type collision**: NULL 590,560 / string 154,571 / integer 9 | `type collision` |
| `sha256` (9 rows) | `context.retained_object.content_sha256 bytea(32)` | hex→bytea, only when bytes are actually retained | none |
| `md5` (590,560 rows, all D3) | **no home** — no md5 column exists anywhere in the snapshot | — | non-gap: these rows should not enter the platform (§3.15) |
| `related_events[]` (8) | `.attrs.related_events` | jsonb; the real target is §3.7 `related_ids` | `column missing` |

**A context-lane "exhibit candidate" row looks like this** (`working.candidate_fact`, zero schema
change):

```
extraction_run_id  = <this import's run>
source_raw_table   = 'case_extract:C4'
source_raw_id      = 'C4-137'
predicate          = 'exhibit_candidate'
statement          = '<label_or_name> — <description>'
evidence_quote     = <the `quote` field if present, else NULL>
subject_entity_id  = NULL          -- no resolution pass has run
object_entity_id   = NULL
confidence         = <envelope/record confidence>
domain             = 'evidence'    -- CHECK allows evidence|legal|behavioral|platform_design|context
attrs              = { "label_or_name":…, "path":…, "tier":…, "tier_note":…,
                       "related_ids":[…], "source_locator":…, "fct_type":"exhibit" }
content_sha256     = sha256(canonical_json(record minus id))
review_state       = 'pending'
```

That row asserts *"an author says an object exists and would prove X."* It is not the object, it
carries no custody, and it can never be mistaken for one. **The evidence lane is out of scope
(D-151c) and this row does not touch it.** The mapping doc lists `exhibit` as UNMAPPED because
`working.context_asset` is scoped to chat-export archive members and `artifact_registry` is for
created works — **agree on both**, and `working.candidate_fact` is the third option it did not
consider.

### 2.8 `source_authority` (1,393 records, 543 distinct citations)

| Extract field | Target | Transform | Gap |
|---|---|---|---|
| `citation` | **`working.candidate_authority.citation` — table does not exist** | verbatim; strip the `<ungrounded-authority …>` markup into a flag, do not silently delete it | **needs new table** (§4 gap 1) |
| `title`, `kind` (8-value enum, clean), `url`, `pin`, `context` | same new table | verbatim | as above |
| `status` (`VERIFIED` 88 / `PROVISIONAL` 493 / `UNSUPPORTED` 22 / absent 790) | `.verification_status` | verbatim | as above |
| — | — | — | **`reference.legal_issue` / `reference.claim_type` are NOT the target.** Both are curated. Writing 493 PROVISIONAL AI citations into the ruler would invalidate every classification made against it |

Interim landing with zero schema change: `working.candidate_fact` with
`predicate='cites_authority'`, `statement=citation`, `attrs={kind,status,url,pin,context}`. This
works and loses nothing, but it makes the citation register unqueryable as a register (no unique
key on citation, no verification workflow). The new table is the right answer; the candidate_fact
form is the acceptable stopgap.

### 2.9 `issue` (256 records)

| Extract field | Target | Transform | Gap |
|---|---|---|---|
| `title` | `working.candidate_fact.statement` | verbatim | none |
| `summary` | `.attrs.summary` (or `statement` when `title` is a stub) | verbatim | none |
| `factors[]` (134) | `.attrs.factors` — letter codes, joined to `reference.custody_factor.factor` by value | verbatim, **no FK** | none |
| `authorities[]` (161) | `.attrs.authorities` + a `cites_authority` companion row per citation | split | none |
| `evidence_refs[]` (51) | `.attrs` | jsonb | none |
| `strength` (63) | `.attrs.strength` | **only 4 of 63 are code-like** (`unverified-ai-generated` 11, `unknown` 6, `weak` 1); the rest are 100+ char prose including full "anticipated defence" paragraphs | **vocabulary mismatch (severe)** |
| `status` (160) | `.attrs.status` | 8 code-like values (`open`, `active`, `alleged`, `documented`, `argued`, `framed`, `PROVISIONAL`, `filed`) + 9 prose | **vocabulary mismatch** |

**`analysis.finding` is the eventual home and is not reachable today.** `analysis.finding` has
exactly the right shape (`finding_type`, `title`, `statement`, `mcl_factors ai.mcl_factor[]`,
`evidence_strength ai.strength_class`, `is_hypothesis` default **true**, `bias_caution` default
**true**, `safe_for_legal_use` gated on approval + `is_hypothesis=false`). But it is analysis tier,
out of scope under D-151(c), and importing 256 AI-authored arguments as `finding` rows would create
the "second authored spine" ADR-0045 forbids. **`working.candidate_fact` now; `analysis.finding`
after an owner review pass, one at a time.**

`analysis.claim_assertion` looks even closer (`assertion_kind` ∈
`connection|significance|decision|exposure|gap|correction`, `asserted_by_kind` ∈ `owner|model`,
`owner_disposition` ∈ `unreviewed|accepted|rejected|parked|superseded`) — but it is **structurally
unreachable** for this material. See §4 gap 5.

### 2.10 `risk` (39 records)

| Extract field | Target | Transform | Gap |
|---|---|---|---|
| `title` | `working.candidate_fact.statement`, `predicate='risk'` | verbatim | none |
| `likelihood` (36) | `.attrs.likelihood` | 25 of 36 are `low`/`medium`/`high`/`unknown`; 11 are prose | **vocabulary mismatch** |
| `impact` (36) | `.attrs.impact` | 24 of 36 code-like across **two overlapping scales** (`minor/moderate/major/severe` and `low/medium/high`); 12 prose | **vocabulary mismatch** — pick one scale |
| `mitigation` (38) | `.attrs.mitigation` | verbatim | none |
| `source_quote` (21) | `.evidence_quote` | verbatim, immutable | none |
| `authorities[]` (2) | companion `cites_authority` rows | split | none |

There is **no risk-register table** in the snapshot. `analysis.evidence_task` has `risk` (CHECK
`none|low|medium|high`), `risk_kind text[]`, `risk_note` — but a litigation risk ("the other side
will argue X") is not an evidence-collection risk, and `evidence_task` requires `case_id uuid NOT
NULL` and `evidence_needed NOT NULL`. Forcing it there is a category error. `working.candidate_fact`
with `predicate='risk'` is the honest landing; a real risk register is an analysis-tier design
decision, not a column mapping.

### 2.11 `goal` (73 records)

| Extract field | Target | Transform | Gap |
|---|---|---|---|
| `title` (72) | `working.candidate_fact.statement`, `predicate='goal'` | verbatim | none |
| `priority` (48) | `.attrs.priority` | 8 distinct values mixing urgency (`immediate`, `high`, `medium`, `low`) with horizon (`mid-term`, `long-term`, `ongoing`) and rank (`primary`) | **vocabulary mismatch — two orthogonal axes in one field** |
| `notes` (36) | `.attrs.notes` | verbatim | none |

**`analysis.evidence_task` is the wrong target** — the mapping brief asked the question and the
answer is no. `evidence_task.evidence_needed` is NOT NULL and means "what evidence must be
obtained"; `evidence_need_kind` CHECK is `corroboration|original_source|authentication|metadata|
completeness|chain_of_custody|rebuttal|foundation|impeachment`. A goal such as "force an immediate
evidentiary hearing" (`C4-129`) is a **litigation objective**, not an evidence need. Two of the 73
goals could be re-expressed as evidence needs; 71 could not. Do not force the mapping.

The closer relative is `note(kind='todo')` — 1,804 records, of which 1,782 come from one row (A2).
Those *are* task-shaped. They still are not evidence needs.

### 2.12 `note` (2,384 records) and `entity_rule` (343 records)

| Extract field | Target | Transform | Gap |
|---|---|---|---|
| `note.text` | `working.candidate_fact.statement` (NOT NULL, len>0) | verbatim; 5 of 2,384 have no `text` and would be rejected | none — importer L403, `predicate` from `kind` default `'note'`. **agree** |
| `note.kind` (7-value enum, clean in all 2,384) | `.predicate` | verbatim | none. **agree** |
| `note.about[]` (241) | `.attrs.about` | jsonb — **these are free-text name strings, not record ids**, so they cannot populate `subject_entity_id`. 2 of 241 are objects, not arrays (`type collision`) | see §3.7 |
| `note.author` (84) | `.attrs.author` | verbatim — this is the closest thing the format has to `asserted_by`, and it is present on 3.5% of notes | see §3.2 |
| `note.label_id`/`cluster_name`/`primary_attack_dimension`/`member_count` (13 each) | `.attrs` | jsonb — undocumented fields | none |
| `entity_rule.pattern`, `.regex` (6) | **`working.candidate_fact`**, `predicate='proposed_detection_pattern'` | verbatim | see below |
| `entity_rule.category` | `.attrs.category` | 70+ distinct free-text values | **vocabulary mismatch** |
| `entity_rule.severity` | `.attrs.severity` | mixed integers (`0`, `10`), ranges (`7-9`), words (`HIGH`, `SEVERE`), and prose | **vocabulary mismatch (severe)** |
| `entity_rule.factors[]` (27) | `.attrs.factors` | letter codes | none |

**`entity_rule` must not touch `reference.detection_pattern` or `reference.behavior_category`.**
Those are the ruler (D-152 verified `reference.detection_pattern` at 527 rows through the rebuild).
`reference.behavior_category.default_severity` is a `smallint 0..10` with a CHECK — the extract's
`"8-10 (strong indicator of coercive control)"` cannot be written there without inventing a number,
and inventing it would silently change how every future classification scores. Land them as
candidates; promote by hand.

### 2.13 `source_locator` (123,000+ occurrences, all record types)

| Observed shape | Count | Machine-usable? |
|---|---|---|
| Free prose (`"## Action Items item[0]"`, `"Pillar 1 timeline"`, `"S I.A"`, `"caption"`, `"¶3"`, `"Section 21.1"`) | 123,318 | **No** |
| Filename-prefixed (`"<file>.pdf, pages 1-2"`) | 420 | Partially |
| Section/pillar prose (`"<file>.docx § Pillar 3.2"`) | 252 | Partially |
| Line ranges (`"lines 27-44"`, `"line 132"`) | 45 | **Yes** |

`timeline.event_candidate.source_locator` is a `jsonb` column and accepts any shape, so nothing
rejects. But a prose locator cannot be resolved to a byte or character range, which means:

- no `content_chunk_source_span` / `source_range_locator` row can be created;
- the SAT-lane requirement that every Action carry `{normalized_record_id, content_chunk_id,
  chat_message_id, span_start, span_end}` (label doc §A1, `stated_in`, "**unrecoverable if not
  written at extraction time**") cannot be met;
- the GROUNDING doc's Option-A harvest cannot point at the quoted passage.

This is a extractor-side fix (§3.9), not a schema gap.

---

## 3. What is missing to fit the framework (extract side)

Numbered; each one line plus its reason.

1. **`source.source_available_from` (per envelope) and `record.asserted_at` (per record)** — the
   horizon clock ADR-0059 §3 requires; `extracted_at` is the *import* time, not the time the
   assertion became available to the owner, and `source.source_date` is null in 254 of 429 envelopes.
2. **`record.asserted_by`** — distinguishing the AI author of the memo from the owner's own words
   quoted inside it; today only `note.author` carries anything (84 of 2,384 notes) and the envelope
   `authored_by` cannot express a per-record difference.
3. **`occurred_at_precision` ∈ `exact|day|month|year|era|range|unknown`** — replacing the
   `"unknown"` sentinel; 264 events already carry the raw prose in `occurred_text`, so the precision
   is known and simply not recorded. Also **collapse `occurred_text` / `occurred_at_text` /
   `date_text` into one field name** — all three exist today for one concept.
4. **`record.confidence` per record, not per envelope** — present on only 343 of 885,433 records (profile)
   (0.04%); a single envelope-level `high` currently applies to a verbatim quote and to an inferred
   date equally.
5. **A `contradiction` slot on Action-shaped records** (`{contradicts_id, contradiction_kind,
   detected_by, basis[]}`) — D-148 makes the contradiction first-class, and the extraction job
   found at least two and recorded them only as English prose in a job summary.
6. **`source.provenance_depth` ∈ `original|quoted_in_derived` plus `derived_source_ref`** — the
   exact schema requirement `docs/design/GROUNDING-VS-UNAVAILABLE-SOURCES-2026-08-29.md` names as
   blocking the first harvest: "cheap now; unrecoverable later, since claims are append-only."
   Every quote inside these memos is `quoted_in_derived`.
7. **`related_ids[]` for within-file links** — an `exhibit` that evidences an `event`, an `issue`
   that rests on a `source_authority`. Today `note.about[]` holds free-text names (2 of 241 are
   objects, not arrays) and `exhibit.related_events[]` holds date strings such as `"2024-05"`, not
   record ids. Ids are globally unique across all 885,433 profiled records, so this is free to add — but see §6 finding 1: row E4 has since diverged to a three-part `E4-<file>-<seq>` scheme.
8. **`duplicate_of` (envelope) and `record.duplicate_of`** — the six text-identical C4 sources and
   the near-identical re-scrapes in E5 are recorded only in `_INDEX.json.skipped[]`, which no
   consumer reads and no envelope references.
9. **A machine `source_locator`**: `{kind, section_path[], start, end}` with character offsets
   into the extracted text, keeping the prose in `.text`. 99.7% of locators are prose today, which
   makes the SAT-lane `stated_in` coordinate impossible to produce later.
10. **`participant_roles[]` (`{name, role_in_event}`) and `is_owner_statement`** — 562 participant
    mentions carry no role, so "who did it / who was told / who merely appears" is unrecoverable,
    and D-147's Action shape requires `actor` vs `stated_to` to be distinguishable.
11. **Split every enum from its prose.** Add `*_note` companions and keep the enum clean:
    `status_note` (`filing.status` — 13 of 24 are prose sentences; `issue.status` 9; `court_event.status`
    1; `draft.status` 3), `strength_note` (`issue.strength` — 59 of 63 are prose), `impact_note` /
    `likelihood_note` (`risk` — 12 and 11), `tier_note` (`exhibit` — 13 of 32), `severity_note`
    (`entity_rule` — 16 of 53), `role_note` (`person.role` — 19 of 405). This is the single largest
    machine-usability loss in the set.
12. **Envelope `extractor_version`, `prompt_version`, `model_id`, `run_id`** — the platform's own
    `working.extraction_run` and `analysis.graph_node_projection` require all four ("prompt changes
    *are* extractor changes", label doc §A1); today `extractor` is one free-text string mixing agent
    id and merge history.
13. **`message.message_corpus` ∈ `first_party|acquired_third_party`** — matching
    `working.normalized_record.message_corpus`; without it the ADR-0059 rule that the owner is never
    invented as a participant in an acquired conversation has nothing to check against. No acquired
    third-party conversation is in this set yet, so this is free to add now.
14. **Make `source.sha256` mean one thing.** 176 envelopes carry `"n/a-slice-of-larger-export"` /
    `"n/a (multi-file)"` in a field typed as a digest. Add `source.slice_of` (parent path + ordinal)
    and require `sha256` to be either a real 64-hex digest of the bytes read or absent.
15. **Stop routing bulk catalogs and bulk exports through `case-extract/v1`.** 879,452 of 886,769
    records (99.17%) are an R2 object catalog, a filesystem inventory, a GPS waypoint set, and one
    SMS export — each of which has its own first-class lane (Case Bible catalog; `raw.file_node`;
    the parked geo lane, D-121; `raw.raw_sms`). Routing them here caused the `factors`
    object-vs-array and `location` object-vs-string type collisions and buries 7,317 genuine
    case records in a 380 MB tree.
16. **Retire the `property` type or adopt it.** One record (`E4-65-3`) uses a 14th type that the
    schema doc does not define, with fields `notes` + `type_note`.
17. **Settle one record-`id` scheme across all rows.** The documented form is `<row>-<seq>` with
    `seq` unique across the whole row (clarified 13:55 after row C6 collided per-file); row E4
    instead uses a three-part `E4-<file-ordinal>-<seq>` with inconsistent zero-padding
    (`E4-1-1` and `E4-073-1` both occur). That is 2,472 records — the single largest validation
    failure class (§6 finding 1) — and it breaks any consumer that parses the id, including the
    proposed `related_ids` / `duplicate_of` / `contradicts_id` references, which are all typed as
    record ids.
18. **Fix three field-name/meaning collisions.** `entity_rule.regex` carries a **boolean** ("is
    this a regex?") in 6 records where a pattern string is expected; `entity_rule.sequence` is a
    scalar in some rows and a nested `{description, steps[]}` state machine in others;
    `person.contact` is a string in 36 records and an **object** with address/phone/email keys in
    5. Each makes the field untypeable, and the `contact` object form puts live PII into a field
    downstream code will treat as an opaque label.

---

## 4. What is missing on the platform side (schema gaps)

Under **D-153 there are no migrations**: a schema change means editing
`sql/bootstrap/schema_snapshot_20260907.sql` in its final form and running
`scripts/rebuild_platform_from_snapshot.sh` with the keep set preserved. Every item below is
written as a snapshot edit. Nothing here is proposed for application — this is a review.

1. **No home for a provisional legal citation. → one new table `working.candidate_authority`.**
   Columns: `id`, `extraction_run_id` (FK `working.extraction_run`), `source_raw_table`,
   `source_raw_id`, `citation text NOT NULL`, `title`, `authority_kind text` (CHECK
   `statute|rule|case|form|benchbook|policy|secondary|other`), `url`, `pin`, `context`,
   `verification_status text` (CHECK `VERIFIED|PROVISIONAL|CONFLICTED|UNSUPPORTED|UNSET`),
   `grounding_flags jsonb`, `content_sha256 bytea(32)`, `review_state`, `created_at`, plus
   `UNIQUE(source_raw_table, source_raw_id, content_sha256)` to match the candidate family.
   Attaches beside `working.candidate_fact`. **This is the table that keeps 493 PROVISIONAL and 22
   UNSUPPORTED AI citations out of `reference.*`.**
2. **No precision class on `working.candidate_event`. → one column.**
   `occurred_at_precision ai.precision_class` (existing enum: `exact|approximate|inferred|uncertain`).
   `timeline.event_candidate` already has `temporal_precision` (CHECK `point|interval|uncertain`,
   NOT NULL); `working.candidate_event` has only `temporal_confidence`. Adding the column lets the
   264 `"unknown"`+`occurred_text` events land in `validity` with their precision recorded rather
   than being rejected.
3. **No contradiction candidate at the context tier. → one new table + two reference vocabularies.**
   `working.candidate_contradiction` (`from_candidate_kind`/`from_candidate_id`,
   `to_candidate_kind`/`to_candidate_id`, `contradiction_kind text`, `detected_by text` CHECK
   `rule|extractor|owner`, `basis jsonb NOT NULL`, `confidence`, `review_state`,
   `owner_verdict text` CHECK `NULL|confirmed|rejected`) attaching to `working.candidate_event` /
   `working.candidate_fact`. Today the only contradiction surfaces are `analysis.finding.contradicts_finding_id`
   (analysis tier), `analysis.location_contradiction` (geo-specific) and
   `analysis.graph_edge_projection` — which is a *projection receipt* requiring graph node ids, not
   a candidate store. Separately, `docs/private/SAT-ACTION-CONTRADICTION-LABELS-2026-09-06.md` §E
   names `reference.sat_action_kind` and `reference.sat_contradiction_kind` as vocabulary tables;
   **neither exists in the snapshot** (17 `reference.*` tables, no `sat_*`). Create them as curated
   vocabularies and have the operational table carry the **code as text**, never an FK.
4. **No party-role vocabulary covering the case. → one new reference table `reference.party_role`.**
   `registry.person.role_in_case` CHECK omits `judge`, `referee`, `foc`, `gal`, `police`, `cps`,
   `school`, `medical`, `family`; `connection_to` omits them too. The alternative — widening the
   `registry.person` CHECK — is worse: registry is identity truth and never bulk-imported, and the
   role vocabulary is a *ruler* (it is what people are classified into). `reference.party_role
   (code, label, description, is_court_officer, notes)`; candidate rows carry `attrs.role` as the
   code and join by value.
5. **The assertion tier is structurally unreachable for document-sourced material. → no schema
   change; an ingest-path decision the owner must make.** `analysis.claim_assertion` requires
   `analysis.claim_assertion_member.claim_candidate_id → working.claim_candidate`, and
   `working.claim_candidate` has `chat_conversation_id`, `chat_message_id`, `window_id` and
   `message_ordinal` all **NOT NULL**, plus `verbatim` CHECK `length ≤ 300` and the
   `speaker_role='assistant' ⇔ claim_class='AI_PROPOSAL'` biconditional. The extracts come from
   `.docx` / `.md` / `.rtf` documents, not from ingested chat conversations, so **no `issue`,
   `risk`, `goal` or `note` in this set can become a grounded assertion today.** This is exactly the
   conflict `GROUNDING-VS-UNAVAILABLE-SOURCES-2026-08-29.md` recorded as *"Undecided. Blocks the
   first harvest."* Its recommended Option C — harvest now, mark second-hand provenance, supersede
   later — requires items 6 and 7 below.
6. **No `provenance_depth` column. → two columns on three tables.**
   `provenance_depth text` (CHECK `original|quoted_in_derived`) and `derived_source_ref text` on
   `working.claim_candidate`, `working.candidate_fact`, and `working.candidate_event`. The grounding
   doc is explicit that this must be a column, not a convention, and that it is "cheap now;
   unrecoverable later, since claims are append-only and cannot be retro-annotated."
7. **`source_available_from` has no candidate-tier home — but this is a *mapping* gap, not a schema
   gap.** `working.source_provenance` already carries `occurred_at`, `export_created_at`,
   `acquired_at`, `ingested_at`, `realized_at`, `realized_at_state`, `acquisition_method`,
   `acquisition_authority` and `asserted_by`, and is keyed on
   `(source_raw_table, source_raw_id, revision)` — the same key candidate rows use. Its
   `asserted_by_kind` CHECK is `'human'` only, which is *correct* here: the custodian (the owner)
   asserts the provenance of an AI-authored document. **No change needed; the importer simply never
   writes it.**
8. **No md5 column anywhere.** 590,560 D3 exhibit rows carry `md5` only.
   `context.retained_object.content_sha256` is `NOT NULL bytea(32)`. **Not a gap to fix** — those
   rows belong in the Case Bible catalog, not the platform (§3.15). Recorded so it is not
   re-discovered.
9. **`reference.knowledge_tag.slug` CHECK rejects underscore tags.** Pattern is
   `^[a-z0-9]+(?:-[a-z0-9]+)*$`; the extracts use `substance_alcohol`, `love_bombing`,
   `parental_alienation`. **Do not widen the CHECK** — normalise `_`→`-` at import. Recorded as a
   deliberate non-change.

### Rule checks on the above

- **"Reference is the ruler."** Items 3 and 4 add *new curated vocabularies* to `reference.*` and
  are consistent with the rule. **No item adds an FK from an operational table into `reference.*`** —
  D-152's rebuild verified "0 FKs leaving reference" and every proposal here links by code value.
  Items 1 and the `entity_rule` handling exist specifically to keep AI-proposed material **out** of
  `reference.*`.
- **ADR-0045 (one authored spine).** No item creates a parallel authored store. Every landing is a
  `*_candidate` row or a derived projection; the authored spine remains
  `working.normalized_record`. The `case-extract` records are assertions *about* the spine, not a
  second copy of it.
- **D-151(c) (evidence lane out of scope).** No item touches `evidence.*`.
- **D-153 (no migrations).** Every item is phrased as a snapshot edit plus rebuild. Any proposal
  numbered `sql/NNNN` would be a defect.

---

## 5. Draft JSON Schema for `case-extract/v1`

Draft 2020-12. Written against the **measured** field union (213 `type`→field pairs) and the
**documented** enums, so that the vocabulary pollution catalogued in §3.11 shows up as validation
failures rather than being silently blessed. Fields carrying `"$comment": "proposed …"` are the
§3 additions and are all optional — JSON has no comment syntax, so `$comment` (a first-class JSON
Schema keyword, ignored by validators) carries the `// proposed` marker.

Two deliberate strictness choices, both of which produce findings in §6:
`source.authored_by` requires a lowercase vendor tag (`ai:gemini`, not `ai:Gemini`), and
`source.sha256` requires 64 hex characters.

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://probata.dev/schemas/case-extract/v1.schema.json",
  "title": "case-extract/v1",
  "description": "Case Bible extraction envelope. One document per source file (or logical source). Draft for review 2026-09-07. Fields carrying $comment 'proposed' are NOT present in the 2026-09-07 corpus and are optional.",
  "type": "object",
  "required": ["schema", "source", "extracted_at", "extractor", "confidence", "records"],
  "additionalProperties": false,
  "properties": {
    "schema": { "const": "case-extract/v1" },
    "source": { "$ref": "#/$defs/source" },
    "extracted_at": { "$ref": "#/$defs/isoDateTimeZ" },
    "extractor": { "type": "string", "minLength": 1 },
    "confidence": { "$ref": "#/$defs/confidenceWord" },
    "records": { "type": "array", "items": { "$ref": "#/$defs/record" } },
    "extractor_version": { "type": "string", "$comment": "proposed - section 3 item 12" },
    "prompt_version": { "type": "string", "$comment": "proposed - section 3 item 12" },
    "model_id": { "type": "string", "$comment": "proposed - section 3 item 12" },
    "run_id": { "type": "string", "$comment": "proposed - section 3 item 12" },
    "duplicate_of": { "type": "string", "$comment": "proposed - section 3 item 8" }
  },
  "$defs": {
    "isoDateTimeZ": {
      "type": "string",
      "pattern": "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?(Z|[+-][0-9]{2}:?[0-9]{2})$"
    },
    "isoDate": { "type": "string", "pattern": "^[0-9]{4}-[0-9]{2}-[0-9]{2}$" },
    "isoDateOrDateTime": {
      "type": "string",
      "pattern": "^[0-9]{4}-[0-9]{2}-[0-9]{2}([T ][0-9]{2}:[0-9]{2}(:[0-9]{2})?(\\.[0-9]+)?(Z|[+-][0-9]{2}:?[0-9]{2})?)?$"
    },
    "dateOrUnknown": {
      "anyOf": [{ "$ref": "#/$defs/isoDateOrDateTime" }, { "const": "unknown" }]
    },
    "confidenceWord": { "enum": ["high", "medium", "low"] },
    "recordId": { "type": "string", "pattern": "^[A-E][0-9]-[0-9]+$" },
    "mclFactor": { "enum": ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l"] },
    "factorList": { "type": "array", "items": { "$ref": "#/$defs/mclFactor" } },
    "stringList": { "type": "array", "items": { "type": "string" } },
    "precision": {
      "enum": ["exact", "day", "month", "year", "era", "range", "unknown"],
      "$comment": "proposed - section 3 item 3"
    },
    "source": {
      "type": "object",
      "required": ["row", "path", "sha256", "bytes", "kind", "authored_by", "source_date"],
      "additionalProperties": false,
      "properties": {
        "row": { "type": "string", "pattern": "^[A-E][0-9]$" },
        "path": { "type": "string", "minLength": 1 },
        "sha256": { "type": "string", "pattern": "^[0-9a-f]{64}$" },
        "bytes": { "type": "integer", "minimum": 0 },
        "kind": {
          "enum": ["timeline", "chat-export", "court-paper", "extraction-json", "rules", "memo", "assignment", "transcript", "catalog", "other"]
        },
        "authored_by": {
          "type": "string",
          "pattern": "^(owner|court|third-party|unknown|ai:[a-z0-9][a-z0-9._-]*)$"
        },
        "source_date": { "anyOf": [{ "$ref": "#/$defs/isoDate" }, { "type": "null" }] },
        "source_available_from": { "$ref": "#/$defs/isoDateOrDateTime", "$comment": "proposed - section 3 item 1" },
        "acquisition_method": {
          "enum": ["own_device", "household_device", "voluntary_third_party", "legal_process", "public_source", "unknown"],
          "$comment": "proposed - section 3 item 1"
        },
        "provenance_depth": {
          "enum": ["original", "quoted_in_derived"],
          "$comment": "proposed - section 3 item 6 (GROUNDING-VS-UNAVAILABLE-SOURCES-2026-08-29)"
        },
        "duplicate_of": { "type": "string", "$comment": "proposed - section 3 item 8" }
      }
    },
    "record": {
      "type": "object",
      "required": ["id", "type"],
      "properties": {
        "id": { "$ref": "#/$defs/recordId" },
        "type": {
          "enum": ["person", "event", "court_event", "filing", "draft", "message", "exhibit", "source_authority", "issue", "risk", "goal", "note", "entity_rule"]
        },
        "confidence": { "$ref": "#/$defs/confidenceWord" },
        "source_locator": { "$ref": "#/$defs/sourceLocator" },
        "quote": { "type": "string" },
        "notes": { "type": "string" },
        "asserted_by": { "type": "string", "$comment": "proposed - section 3 item 2" },
        "asserted_at": { "$ref": "#/$defs/isoDateOrDateTime", "$comment": "proposed - section 3 item 1" },
        "is_owner_statement": { "type": "boolean", "$comment": "proposed - section 3 item 10" },
        "related_ids": { "type": "array", "items": { "$ref": "#/$defs/recordId" }, "$comment": "proposed - section 3 item 7" },
        "duplicate_of": { "$ref": "#/$defs/recordId", "$comment": "proposed - section 3 item 8" },
        "contradiction": { "$ref": "#/$defs/contradiction", "$comment": "proposed - section 3 item 5" }
      },
      "allOf": [
        { "if": { "properties": { "type": { "const": "person" } }, "required": ["type"] }, "then": { "$ref": "#/$defs/person" } },
        { "if": { "properties": { "type": { "const": "event" } }, "required": ["type"] }, "then": { "$ref": "#/$defs/event" } },
        { "if": { "properties": { "type": { "const": "court_event" } }, "required": ["type"] }, "then": { "$ref": "#/$defs/courtEvent" } },
        { "if": { "properties": { "type": { "const": "filing" } }, "required": ["type"] }, "then": { "$ref": "#/$defs/filing" } },
        { "if": { "properties": { "type": { "const": "draft" } }, "required": ["type"] }, "then": { "$ref": "#/$defs/draft" } },
        { "if": { "properties": { "type": { "const": "message" } }, "required": ["type"] }, "then": { "$ref": "#/$defs/message" } },
        { "if": { "properties": { "type": { "const": "exhibit" } }, "required": ["type"] }, "then": { "$ref": "#/$defs/exhibit" } },
        { "if": { "properties": { "type": { "const": "source_authority" } }, "required": ["type"] }, "then": { "$ref": "#/$defs/sourceAuthority" } },
        { "if": { "properties": { "type": { "const": "issue" } }, "required": ["type"] }, "then": { "$ref": "#/$defs/issue" } },
        { "if": { "properties": { "type": { "const": "risk" } }, "required": ["type"] }, "then": { "$ref": "#/$defs/risk" } },
        { "if": { "properties": { "type": { "const": "goal" } }, "required": ["type"] }, "then": { "$ref": "#/$defs/goal" } },
        { "if": { "properties": { "type": { "const": "note" } }, "required": ["type"] }, "then": { "$ref": "#/$defs/note" } },
        { "if": { "properties": { "type": { "const": "entity_rule" } }, "required": ["type"] }, "then": { "$ref": "#/$defs/entityRule" } }
      ]
    },
    "sourceLocator": {
      "anyOf": [
        { "type": "string", "minLength": 1 },
        {
          "type": "object",
          "$comment": "proposed - section 3 item 9 (machine form)",
          "required": ["kind"],
          "properties": {
            "kind": { "enum": ["char_range", "line_range", "page", "section_path", "turn", "row"] },
            "section_path": { "type": "array", "items": { "type": "string" } },
            "start": { "type": "integer", "minimum": 0 },
            "end": { "type": "integer", "minimum": 0 },
            "text": { "type": "string" }
          }
        }
      ]
    },
    "contradiction": {
      "type": "object",
      "$comment": "proposed - section 3 item 5 (D-148 / SAT-ACTION-CONTRADICTION-LABELS A2)",
      "required": ["contradicts_id", "contradiction_kind"],
      "properties": {
        "contradicts_id": { "$ref": "#/$defs/recordId" },
        "contradiction_kind": {
          "enum": ["promise_vs_contrary_act", "stated_plan_vs_different_act", "commitment_vs_reversal", "stated_location_vs_gps", "stated_errand_vs_gps_stop", "told_me_vs_told_other"]
        },
        "detected_by": { "enum": ["rule", "extractor", "owner"] },
        "basis": { "type": "array", "items": { "type": "object" } }
      }
    },
    "person": {
      "required": ["name", "role"],
      "properties": {
        "name": { "type": "string", "minLength": 1 },
        "role": {
          "enum": ["owner", "other-parent", "child", "judge", "referee", "foc", "gal", "attorney", "witness", "family", "police", "cps", "school", "medical", "other"]
        },
        "aliases": { "$ref": "#/$defs/stringList" },
        "relationship": { "type": "string" },
        "contact": { "type": "string" },
        "dob": { "anyOf": [{ "$ref": "#/$defs/isoDate" }, { "const": "unknown" }] },
        "name_text": { "type": "string" },
        "details": { "type": "string" },
        "evidence_refs": { "$ref": "#/$defs/stringList" },
        "role_note": { "type": "string", "$comment": "proposed - carries the free prose that today pollutes role" }
      }
    },
    "event": {
      "required": ["occurred_at", "description"],
      "properties": {
        "occurred_at": { "$ref": "#/$defs/dateOrUnknown" },
        "occurred_text": { "type": "string" },
        "description": { "type": "string", "minLength": 1 },
        "known_at": { "$ref": "#/$defs/dateOrUnknown" },
        "location": { "anyOf": [{ "type": "string" }, { "type": "object" }] },
        "participants": { "$ref": "#/$defs/stringList" },
        "evidence_refs": { "$ref": "#/$defs/stringList" },
        "document_refs": { "$ref": "#/$defs/stringList" },
        "factors": { "$ref": "#/$defs/factorList" },
        "tags": { "$ref": "#/$defs/stringList" },
        "case_no_ref": { "type": "string" },
        "occurred_at_precision": { "$ref": "#/$defs/precision", "$comment": "proposed - section 3 item 3" },
        "participant_roles": {
          "type": "array",
          "$comment": "proposed - section 3 item 10",
          "items": {
            "type": "object",
            "required": ["name", "role_in_event"],
            "properties": {
              "name": { "type": "string" },
              "role_in_event": { "enum": ["actor", "recipient", "witness", "subject", "mentioned"] }
            }
          }
        }
      },
      "if": { "properties": { "occurred_at": { "const": "unknown" } }, "required": ["occurred_at"] },
      "then": { "required": ["occurred_text"] }
    },
    "courtEvent": {
      "required": ["kind", "date", "title"],
      "properties": {
        "kind": {
          "enum": ["hearing", "order", "filing", "service", "deadline", "referee-recommendation", "objection", "conference", "foc-appointment", "evaluation-appointment"]
        },
        "date": { "$ref": "#/$defs/dateOrUnknown" },
        "date_text": { "type": "string" },
        "occurred_text": { "type": "string" },
        "title": { "type": "string", "minLength": 1 },
        "court": { "type": "string" },
        "judge_or_referee": { "type": "string" },
        "case_no": { "type": "string" },
        "outcome": { "type": "string" },
        "document_refs": { "$ref": "#/$defs/stringList" },
        "deadline_rule": { "type": "string" },
        "status": { "enum": ["past", "upcoming", "unknown"] },
        "status_note": { "type": "string", "$comment": "proposed - carries the free prose that today pollutes status" },
        "date_precision": { "$ref": "#/$defs/precision", "$comment": "proposed - section 3 item 3" }
      }
    },
    "filing": {
      "required": ["title", "filed_or_planned"],
      "properties": {
        "title": { "type": "string", "minLength": 1 },
        "filed_or_planned": { "enum": ["filed", "planned", "draft-only", "unknown"] },
        "date": { "anyOf": [{ "$ref": "#/$defs/dateOrUnknown" }, { "type": "null" }] },
        "date_text": { "type": "string" },
        "occurred_text": { "type": "string" },
        "court": { "type": "string" },
        "served_on": { "anyOf": [{ "type": "string" }, { "$ref": "#/$defs/stringList" }] },
        "service_method": { "type": "string" },
        "document_refs": { "$ref": "#/$defs/stringList" },
        "status": { "enum": ["draft", "pending", "filed", "denied", "granted", "withdrawn", "working", "unknown"] },
        "status_note": { "type": "string", "$comment": "proposed - carries the free prose that today pollutes status" },
        "related_court_event": { "type": "string" },
        "filed_by": { "type": "string" },
        "legal_authority": { "type": "string" }
      }
    },
    "draft": {
      "required": ["title", "doc_type"],
      "properties": {
        "title": { "type": "string", "minLength": 1 },
        "doc_type": { "enum": ["motion", "response", "objection", "affidavit", "letter", "message", "outline", "memo", "other"] },
        "date": { "anyOf": [{ "$ref": "#/$defs/dateOrUnknown" }, { "type": "null" }] },
        "date_text": { "type": "string" },
        "path": { "type": "string" },
        "version": { "anyOf": [{ "type": "string" }, { "type": "integer" }] },
        "status": { "enum": ["working", "final", "abandoned"] },
        "status_note": { "type": "string", "$comment": "proposed - carries the free prose that today pollutes status" },
        "text": { "type": "string" },
        "authorities": { "$ref": "#/$defs/stringList" },
        "factors": { "$ref": "#/$defs/factorList" }
      }
    },
    "message": {
      "required": ["sent_at", "from", "to", "body"],
      "properties": {
        "sent_at": { "$ref": "#/$defs/dateOrUnknown" },
        "occurred_text": { "type": "string" },
        "from": { "type": "string" },
        "to": { "$ref": "#/$defs/stringList" },
        "body": { "type": "string" },
        "platform": { "enum": ["sms", "mms", "email", "facebook", "snapchat", "whatsapp", "imessage", "other"] },
        "thread_id": { "anyOf": [{ "type": "string" }, { "type": "null" }] },
        "attachments": { "type": "array" },
        "tags": { "$ref": "#/$defs/stringList" },
        "factors": { "$ref": "#/$defs/factorList" },
        "pattern_category": { "type": "string" },
        "pattern_name": { "type": "string" },
        "pattern_description": { "type": "string" },
        "severity": { "anyOf": [{ "type": "string" }, { "type": "integer" }] },
        "message_corpus": {
          "enum": ["first_party", "acquired_third_party"],
          "$comment": "proposed - section 3 item 13 (ADR-0059 / working.normalized_record.message_corpus)"
        }
      }
    },
    "exhibit": {
      "required": ["label_or_name"],
      "properties": {
        "label_or_name": { "type": "string", "minLength": 1 },
        "path": { "type": "string" },
        "sha256": { "anyOf": [{ "type": "string", "pattern": "^[0-9a-f]{64}$" }, { "type": "null" }] },
        "md5": { "anyOf": [{ "type": "string", "pattern": "^[0-9a-f]{32}$" }, { "type": "null" }] },
        "r2_path": { "anyOf": [{ "type": "string" }, { "type": "null" }] },
        "mime": { "anyOf": [{ "type": "string" }, { "type": "null" }] },
        "size": { "anyOf": [{ "type": "integer", "minimum": 0 }, { "type": "null" }] },
        "description": { "anyOf": [{ "type": "string" }, { "type": "null" }] },
        "tier": { "anyOf": [{ "enum": ["high", "medium", "low", "critical", "public", "sealed"] }, { "type": "null" }] },
        "tier_note": { "type": "string", "$comment": "proposed - carries the free prose that today pollutes tier" },
        "date_text": { "type": "string" },
        "related_events": { "$ref": "#/$defs/stringList" }
      }
    },
    "sourceAuthority": {
      "required": ["citation"],
      "properties": {
        "citation": { "type": "string", "minLength": 1 },
        "title": { "type": "string" },
        "kind": { "enum": ["statute", "rule", "case", "form", "benchbook", "policy", "secondary", "other"] },
        "url": { "type": "string" },
        "pin": { "type": "string" },
        "status": { "enum": ["VERIFIED", "PROVISIONAL", "CONFLICTED", "UNSUPPORTED"] },
        "context": { "type": "string" }
      }
    },
    "issue": {
      "required": ["title"],
      "properties": {
        "title": { "type": "string", "minLength": 1 },
        "summary": { "type": "string" },
        "factors": { "$ref": "#/$defs/factorList" },
        "authorities": { "$ref": "#/$defs/stringList" },
        "evidence_refs": { "$ref": "#/$defs/stringList" },
        "strength": { "enum": ["weak", "moderate", "strong", "decisive", "unknown", "unverified-ai-generated"] },
        "strength_note": { "type": "string", "$comment": "proposed - carries the free prose that today pollutes strength" },
        "status": { "enum": ["open", "active", "argued", "framed", "alleged", "documented", "resolved", "filed", "PROVISIONAL"] },
        "status_note": { "type": "string", "$comment": "proposed - carries the free prose that today pollutes status" },
        "name": { "type": "string" },
        "details": { "type": "string" },
        "risk": { "type": "string" }
      }
    },
    "risk": {
      "required": ["title"],
      "properties": {
        "title": { "type": "string", "minLength": 1 },
        "likelihood": { "enum": ["low", "medium", "high", "unknown"] },
        "impact": { "enum": ["minor", "moderate", "medium", "major", "severe", "high", "unknown"] },
        "likelihood_note": { "type": "string", "$comment": "proposed - carries the free prose that today pollutes likelihood" },
        "impact_note": { "type": "string", "$comment": "proposed - carries the free prose that today pollutes impact" },
        "mitigation": { "type": "string" },
        "source_quote": { "type": "string" },
        "authorities": { "$ref": "#/$defs/stringList" }
      }
    },
    "goal": {
      "required": ["title"],
      "properties": {
        "title": { "type": "string", "minLength": 1 },
        "priority": { "enum": ["immediate", "high", "medium", "low", "ongoing", "mid-term", "long-term", "primary"] },
        "content": { "type": "string" }
      }
    },
    "note": {
      "required": ["text"],
      "properties": {
        "text": { "type": "string", "minLength": 1 },
        "kind": { "enum": ["advice", "strategy", "finding", "question", "todo", "pattern", "definition"] },
        "about": { "type": "array" },
        "author": { "type": "string" },
        "title": { "type": "string" },
        "content": { "type": "string" },
        "tags": { "$ref": "#/$defs/stringList" },
        "factors": { "$ref": "#/$defs/factorList" },
        "authorities": { "$ref": "#/$defs/stringList" },
        "source_quote": { "type": "string" },
        "date_text": { "type": "string" },
        "label_id": { "type": "string" },
        "cluster_name": { "type": "string" },
        "primary_attack_dimension": { "type": "string" },
        "member_count": { "type": "integer" },
        "source_sha256": { "type": "string" },
        "source_path": { "type": "string" },
        "source_bytes": { "type": "integer" },
        "source_files": { "type": "array" }
      }
    },
    "entityRule": {
      "required": ["pattern"],
      "properties": {
        "pattern": { "type": "string", "minLength": 1 },
        "regex": { "type": "string" },
        "category": { "type": "string" },
        "severity": { "anyOf": [{ "type": "integer", "minimum": 0, "maximum": 10 }, { "enum": ["low", "medium", "high", "severe"] }] },
        "severity_note": { "type": "string", "$comment": "proposed - carries the free prose that today pollutes severity" },
        "factors": { "$ref": "#/$defs/factorList" },
        "sequence": { "anyOf": [{ "type": "string" }, { "type": "integer" }] },
        "aliases": { "$ref": "#/$defs/stringList" },
        "coercive_control": { "anyOf": [{ "type": "boolean" }, { "type": "string" }] },
        "source_url": { "type": "string" },
        "label_id": { "type": "string" },
        "primary_attack_dimension": { "type": "string" },
        "example_missing_in_source": { "anyOf": [{ "type": "boolean" }, { "type": "string" }] }
      }
    }
  }
}
```

### Where this file should live

`AGENTS.md` says `modules/contracts/` is the future home of cross-language contract schemas
(JSON/YAML consumed by Go + Python + n8n), and that it should be recreated **"only when H-02 lands
the first real schema files, so the directory is born with content."** This is a real schema file
consumed by at least three callers (the Case Bible extractor, `scripts/import_fct_bundle.py` or its
successor, and any n8n validation node), so it is a legitimate candidate to be that first content.

Recommended path and name:

```
modules/contracts/case-extract/v1/case-extract-v1.schema.json
```

with a sibling `modules/contracts/README.md` recording the owner ruling that created the directory.
**Not created by this review** — that is an owner decision about whether this schema is the file
that opens `modules/contracts/`.

---

## 6. Validation run

### Method

`jsonschema` 4.26.0 (Draft 2020-12), run as
`uv run --no-project --with jsonschema python <validator> <schema> <out.tsv>` from the repository
root. The schema was first checked with `Draft202012Validator.check_schema()` and passed. Every
`*.json` under the extract tree was enumerated except `_INDEX*.json`; a file whose top-level
`schema` was not `"case-extract/v1"` was counted as non-envelope and skipped. **Read-only: no
extract file was opened for writing, moved, or modified.** The sweep deliberately includes the 10
files under `C4/.review_hold/` — those are quarantined superseded extraction passes, not live
output, and are marked as such below.

Two runs were made.

### Run A — full sweep (all rows), executed ~16:05

| | |
|---|---|
| Envelope files checked | **471** |
| **PASS** | **200** |
| **FAIL** | **271** |
| Distinct failure rows (`file:record-id:field` + message) | **278,749** |

Run A is dominated by the bulk blocks and says almost nothing about the case material:
154,571 failures are `exhibit.size` carried as a **string** rather than an integer (all B4);
121,499 are `event.factors` carried as an **object** rather than an array of MCL letters (all C3
geo waypoints); 58 are `exhibit.md5` values that are not 32 hex characters. Those three classes
are the type collisions named in §2.2 / §2.7 and are the mechanical proof of §3.15.

Three Run-A entries reported as "unparseable JSON" were **not corruption**: they were
`E4/tmp_e4_238_*.json`, `tmp_e4_240_*.json` and `tmp_e4_246_*.json` — files that vanished between
enumeration and read because the extractor writes `tmp_<name>.json` and then renames. All three now
exist under their final names and parse cleanly. Reported here rather than silently dropped.

### Run B — case-narrative rows only (B1, B4, C3, D3 excluded), executed ~16:45 against the current tree

| | |
|---|---|
| Files discovered | 335 |
| Non-envelope skipped | 4 |
| Envelope files **checked** | **331** |
| **PASS** | **81** |
| **FAIL** | **250** |
| Records covered | **7,317** |
| Distinct failure rows | **3,281** |

**Failing files by row:** E4 175 · A2 27 · C4 13 · E3 12 · D1 10 · A4 3 · E1 2 · D2 2 · C1 2 ·
A3 2 · E2 1 · A1 1.
**Failure rows by row:** E4 3,014 · C4 86 · E3 38 · C1 30 · A2 27 · A4 23 · E2 22 · D1 21 · A3 9 ·
E1 6 · A1 3 · D2 2.

### Every failure, by class, with exemplars

E4 filenames are cited by their numeric prefix only (`E4/e4_161_*.json`) because several encode
personal names. Where an exemplar's value is personal data it is described, never quoted.

| # | Class | Field | Count | Exemplar `file:record-id:field` | What is wrong |
|---|---|---|---|---|---|
| 1 | format/pattern | `id` | **2,472** | `E4/e4_001_*.json:E4-1-1:id` | Row E4 uses a **three-part** id `E4-<file-ordinal>-<seq>` with inconsistent zero-padding (`E4-1-1` and `E4-073-1` both occur). The documented scheme is `<row>-<seq>` with `seq` unique across the whole row — a clarification added to the schema doc at 13:55 after row C6 collided per-file. E4 solved the same problem a different way and no longer matches the contract. **All 2,472 are one defect.** |
| 2 | format/pattern | `source/sha256` | 176 | `C4/strategy-memos.json:<envelope>:source/sha256` → `'n/a (multi-file)'`; `E4/e4_001_*.json:<envelope>:source/sha256` → `'n/a-slice-of-larger-export'` | A field typed as a digest carries sentinel prose. §3.14 |
| 3 | anyOf | `occurred_at` | 166 | `A1/<schema-export>.json:A1-8:occurred_at` → `'2023-07'` | Month-precision dates (`YYYY-MM`, and `'2022'`) — a **third** date convention beside ISO-date and `"unknown"`+`occurred_text`, documented nowhere and carrying no `occurred_text`. The fix is §3.3 (`occurred_at_precision`), not a looser pattern |
| 4 | missing required | `occurred_text` | 117 | `C4/.review_hold/duplicate-run_*.json:C4-7:<record>` | `occurred_at:"unknown"` with no accompanying raw text — the record asserts an event with no recoverable time at all. **97 of the 117 are in live files**, 20 in quarantined `.review_hold` passes |
| 5 | vocabulary | `status` | 97 | `D1/Affidavit.json:D1-1:status` → `'unsigned/unnotarized template; Case No. blank'`; `C4/ai-firm-plan.json:C4-330:status` → `'strategy-under-development'` | Prose and ad-hoc values in an enum field, across `filing`, `issue`, `court_event`, `draft`. §3.11 |
| 6 | vocabulary | `strength` | 56 | `C1/master-timeline-consolidated.json:C1-58:strength` → `'Undermines mutual parent teamwork; sets adversarial tone'` | 27 of the 56 are an explicit JSON `null` rather than an omitted field; the rest are full sentences, several of them multi-clause "anticipated defence" paragraphs. §3.11 |
| 7 | anyOf | `severity` | 32 | `A4/analysis-library-architecture.json:A4-87:severity` → `'7-9'` | Ranges (`'7-9'`, `'6-8'`, `'9-10'`), uppercase words (`'HIGH'`, `'SEVERE'`, `'HIGHEST'`) and prose in an `entity_rule` field that `reference.behavior_category.default_severity` types as `smallint 0..10` |
| 8 | format/pattern | `source/authored_by` | 27 | `A2/extraction_data__*__extract.json:<envelope>:source/authored_by` → `'ai:Gemini'` | Vendor tag case-inconsistency: `ai:Gemini` (15) vs `ai:gemini` (7), plus `ai:ChatGPT` (10) and `ai:Claude` (2). Two spellings of one vendor make provenance grouping wrong by default |
| 9 | anyOf | `tier` | 20 | `C1/relationship-timeline.json:C1-115:tier` → `'hybrid public/sealed'`; another reads `'not yet gathered — pre-hearing checklist item'` (11 records) | `exhibit.tier` mixes an admissibility scale, a confidentiality scale, and collection status in one field |
| 10 | vocabulary | `impact` | 19 | `C1/relationship-timeline.json:C1-108:impact` → a full sentence about jurisdictional loss | `risk.impact` also mixes two scales (`minor/moderate/major/severe` and `low/medium/high`). §3.11 |
| 11 | vocabulary | `likelihood` | 18 | `C1/relationship-timeline.json:C1-108:likelihood` → `'elevated (concealed prior intent + out-of-state family ties)'` | Same record as #10 — its whole risk-matrix row is prose |
| 12 | vocabulary | `role` | 17 | `E2/emergency_motion_for_protective_order.json:E2-20:role` → `'party-plaintiff'`; `D2/message_1.json:D2-63:role` → `'third-party'` | `person.role` free prose / near-miss codes. §2.1, §4.4 |
| 13 | vocabulary | `factors/*` | 21 | `E2/emergency_motion_for_protective_order.json:E2-9:factors/0` → `'MCL722.23(j)'`; `E3/perplexity-context-chat-chunk-07-of-67.json:E3-12:factors/1` → `'MCL 722.23(g)'` | Citation strings where a bare `a`–`l` letter is required. Trivially normalisable, but nothing normalises it today |
| 14 | vocabulary | `priority` | 13 | `E4/e4_268_*.json:E4-268-18:priority` → `'1'`; `E4/e4_242_*.json:E4-242-3:priority` → `'unknown'` | `goal.priority` mixes urgency, horizon and numeric rank. §2.11 |
| 15 | type | `regex` | 6 | `A3/behaviors.json:A3-030:regex` → `False` | `entity_rule.regex` carries a **boolean** ("is this a regex?") where a pattern string is expected — a field-name/meaning collision |
| 16 | anyOf | `sequence` | 6 | `A3/sequences.json:A3-167:sequence` → an object `{description, steps[]}` | `entity_rule.sequence` is a scalar in some rows and a nested step-machine object in others — **type collision** |
| 17 | anyOf | `date` | 6 | `C4/custody-case-analysis-and-strategy.json:C4-115:date` → `'2025-09'` | Month-precision `court_event.date`, same defect class as #3 |
| 18 | type | `contact` | 5 | `E4/e4_190_*.json:E4-190-1:contact` | `person.contact` carries an **object** with street address, phone and email keys where the schema documents a string. Values not reproduced here — this is live PII in an intake tree |
| 19 | missing required | `title` | 11 | (across `issue`, `goal`, `risk`) | Records with no title at all |
| 20 | missing required | `text` | 5 | (`note`) | `note` records with no `text` — these have no content |
| 21 | missing required | `filed_or_planned` | 3 | (`filing`) | 3 of 67 filings do not say whether they were filed |
| 22 | missing required | `kind` | 1 | (`court_event`) | |
| 23 | anyOf | `dob` | 2 | `E4/e4_131_*.json:E4-131-10:dob` → `'2020-01-unknown'`; `E4/e4_105_*.json:E4-105-3:dob` → `'2020'` | Partial DOB written as a malformed ISO string. **These are child DOBs** — note the importer's `CHILD_STRIP_KEYS` correctly drops them (§2.1) |
| 24 | anyOf | `known_at` | 1 | `C1/master-timeline-consolidated.json:C1-9:known_at` → explicit `null` | The realization clock, present 21 times in the whole corpus, and one of those is null |
| 25 | vocabulary | `type` | 1 | `E4/e4_065_*.json:E4-65-3:type` → `'property'` | The undocumented 14th record type. §3.16 |
| 26 | other | `about` / `legal_authority` / `risk` / `path` / `sequence` | 8 | `note.about` object-instead-of-array (2); `issue.risk` as a nested value; `draft.path` non-string | Small type collisions in fields with no declared type in the v1 doc |

**Totals check.** Classes 1–26 sum to 3,281 distinct failure rows across 250 failing envelopes.
Removing the single systematic id defect (#1, 2,472 rows, one root cause) leaves **809 failure rows**
— the substantive backlog. Of those, **the enum-vs-prose family (#5, #6, #7, #9, #10, #11, #12,
#14) is 272 rows**, which is why §3.11 is ranked first in §7.

**Reproduce:** the validator script and the schema are session-scratch artifacts; the run is
reproducible from the fenced schema in §5 plus a ~40-line `jsonschema` driver. The full 3,281-row
`file:record-id:field<TAB>message` list was written to a scratch TSV during this review and is not
committed (it embeds personal data from the extract tree).

---

## 7. Recommendation

1. **Extractor, before the next batch (highest value first):** split every enum from its prose
   (§3.11 — this is the largest machine-usability loss), add `asserted_at` / `source_available_from`
   / `provenance_depth` per §3.1 and §3.6, emit a machine `source_locator` with character offsets
   (§3.9), add the `contradiction` slot (§3.5), and stop routing bulk catalogs and bulk exports
   through this schema (§3.15 — 99.17% of the records).
2. **Snapshot (D-153: edit the snapshot, rebuild, no migrations):** add `working.candidate_authority`
   (§4.1), `working.candidate_contradiction` plus `reference.sat_action_kind` /
   `reference.sat_contradiction_kind` (§4.3), `reference.party_role` (§4.4),
   `occurred_at_precision ai.precision_class` on `working.candidate_event` (§4.2), and
   `provenance_depth` / `derived_source_ref` on the three candidate tables (§4.6).
3. **`import_fct_bundle.py` — safe on all three properties, and cannot read this format.**
   Context-lane only: six `INSERT` statements, all into `working.candidate_entity` (L334),
   `working.candidate_event` (L375), `working.candidate_fact` (L403), `timeline.event_candidate`
   (L448), `context.source` (L486) and `working.extraction_run` (L614); zero `UPDATE`/`DELETE`/DDL
   anywhere in 802 lines; nothing into `evidence.*`, `reference.*` or `registry.*`. Re-runnable:
   `ON CONFLICT … DO NOTHING` on all five content inserts (L338, L379, L407, L452, L488), and
   `--apply` rolls back unless `--commit` is also passed (L774-777).
4. **But it is not the importer for this set.** It expects `EXPECTED_MANIFEST_SCHEMA =
   "fct-platform-bundle/v1"` (L95) and a directory of `<table>.ndjson` files; `case-extract/v1` is
   one envelope-per-source with a `records[]` array, so pointing it at this tree reads zero records
   and reports every table as "(no file)".
5. **Three defects to fix before it is pointed at any real bundle:** it hashes the record `id` into
   `content_sha256` (so the C4 renumber would land duplicates — exclude `id`); it rejects every
   `occurred_at:"unknown"` event instead of using `candidate_event.validity`, discarding the 264
   highest-value undated case events while importing 121,499 GPS waypoints; and it writes no
   `working.source_provenance` row, dropping the acquisition/realization clock that ADR-0059
   requires and that the table already exists to hold.
