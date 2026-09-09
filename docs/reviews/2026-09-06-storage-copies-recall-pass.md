# Storage-Copies Recall Pass (2026-09-06)

> _Byline: Claude Code · Sonnet 5 · 2026-09-06._

STATUS: RECALL — prior rulings located; feeds the thinking pass and the change map.

Scope: for each of the seven storage-copies proposals made today (11:30–11:53), locate every
prior ruling/ADR/decision/plan-line/review conclusion that already answers, contradicts, or
constrains it. Read-only recall.

---

## P1 — Cold object store + TTL block-storage cache; PG one physical text table

| Source | Location | What it says | Relation |
|---|---|---|---|
| Decision Log | D-142 (2026-09-05) | Zero live evidence exists; don't protect empty stocks; golden clone + teardown replaces purge. | CONSTRAINS |
| Memory | `test-the-job-not-the-transport.md` (owner 2026-09-06) | "Ingest-time retain = working copy + SHA-256 row. No seal ceremony... Sealing = custody at PROMOTION only." | CONSTRAINS |
| SQL | `sql/0036_context_import_foundation.sql:88-91` | `context.retained_object`, `storage_class CHECK (immutable_object_store\|filesystem\|inline)` already exists. | CONSTRAINS (infra partial) |
| Planning | `docs/planning/2026-09-06-derived-layers-change-map.md` §2 | Same proposal verbatim (one cold copy, TTL'd block cache, one physical text table). Q3/Q4 marked open, no owner ruling recorded. | ALREADY RULED SAME (same-session draft, NOT owner-ratified) |

**Verdict: OPEN.** No owner ruling found predating today fixing the TTL/cold-cache split as final; P1 restates today's own unratified change-map §2. Constrained (not contradicted) by D-142 and the ingest-retain rule.

---

## P2 — Raw records store byte offsets + H2 digest, not bytes; re-materialize via DuckDB `read_text`

| Source | Location | What it says | Relation |
|---|---|---|---|
| Planning | `docs/planning/2026-09-03-ingest-redesign-plan-and-sequential-guide.md:321-330` | **Q1 RULED 2026-09-04 23:4x = C** — owner verbatim "my lean is C… make it work the same way and everything checkable again." DuckDB `read_text` → self-split with running byte offset → decode → `RawRecordEnvelope` with byte offsets; nullable `byte_start`/`byte_end` on raw content tables. | ALREADY RULED SAME |
| Change map | `2026-09-06-derived-layers-change-map.md` §3a | As-built spelling is `byte_offset`/`byte_length` (`sql/0036:217-218`), "partly already built." | CONSTRAINS (naming) |

**Verdict: SETTLED** (Q1=C, 2026-09-04 23:4x). P2 is a direct restatement of an already-signed decision, not a new proposal.

---

## P3 — Chunks ids-only; drop `working.content_chunk.content`

| Source | Location | What it says | Relation |
|---|---|---|---|
| Planning | `2026-09-03-ingest-redesign-plan...md:45` | **Q9 RULED 2026-09-06 = A** — `content_chunk_message` bridge built as `sql/0072`, append-only, FK to both `content_chunk` and `normalized_record`. | CONSTRAINS (enables, doesn't itself rule dropping `content`) |
| SQL | `sql/0047_content_chunk_and_context_thread_foundation.sql:234,244` | `content TEXT NOT NULL` + `CHECK (digest(...) = content_sha256)` — currently the live, applied contract. | CONSTRAINS |
| Change map | §3b, Q6 | "Owner ruling? Y" — flagged as an OPEN question, not yet answered. | SILENT (no prior ruling) |

**Verdict: OPEN.** No prior ruling drops `content_chunk.content`; Q9=A built the membership bridge that would make it feasible but did not rule on removing the text column. Question is legitimately new — not a re-open.

---

## P4 — Weaviate vectors + PG coordinate + member ids, no text; PG bridge is chunk truth

| Source | Location | What it says | Relation |
|---|---|---|---|
| Planning | Q9=A (as above) | Bridge (`content_chunk_message`) already built as the provenance/membership record. | CONSTRAINS |
| Root `AGENTS.md` | Weaviate landmine section | agno silently drops `FilterExpr` on Weaviate — dict filters only, always. | CONSTRAINS (implementation detail, not scope) |
| Change map | §3c, Q8 | Cutting `EvidenceChunkV2` (no-text property set) is an OPEN question — "cut now, or hold until Go chunker writes real rows?" | SILENT (no prior ruling) |

**Verdict: OPEN.** Same family as P3; no prior ruling that Weaviate must drop text or that the bridge is "chunk truth" as a governance statement — it is a schema consequence of Q9=A, not a ruled principle on its own.

---

## P5 — HITL destination gate (test/vault/discard) + `permanent_home` + TTL sweep Activity

| Source | Location | What it says | Relation |
|---|---|---|---|
| Memory | `test-the-job-not-the-transport.md` (owner 2026-09-06) | "Test material never under the vault's `EvidenceVault/`. Dedicated test bucket + `/data/test_data`." Also: "Host-to-host data movement = separate item, decided separately. Never bundle it into a parse test." | CONSTRAINS |
| Decision Log | D-145/D-146 (2026-09-06) | Lifecycle order governs context→Surreal→evidence: "never bare 'promote'"; two distinct owner clicks. This is a DIFFERENT axis (evidentiary relevance) than file destination. | CONSTRAINS (vocabulary must not collide) |
| Change map | §5, Q12 | "Are the destination values exactly test/vault/discard, and is discard a tombstone or a no-retain?" — flagged OPEN. | SILENT (no prior ruling) |

**Verdict: OPEN.** No prior ruling establishes the specific test/vault/discard gate mechanism; constrained by the test-vs-vault path distinction and by D-145's promotion vocabulary (a destination gate must not be described as "promoting").

---

## P6 — DuckDB ELT primary for extract-only; SBV decoders fallback; smsbackuprestore XML first candidate

| Source | Location | What it says | Relation |
|---|---|---|---|
| Planning | `2026-09-03-ingest-redesign-plan...md:53-65` | Owner ruling 2026-09-03: "Extract vs parse is the split, not file class... DuckDB ELT is the primary path and REPLACES the Go/Python decoder for it [extract-only formats]. Existing Go/Python parsers remain as failure fallback." | ALREADY RULED SAME |
| Planning | same file, line 417 (owner 2026-09-06 11:52) | "DuckDB ELT primary for extract-only formats; decoders are the logged-failure fallback." Reconfirms verbatim. | ALREADY RULED SAME |
| ADR | `docs/adr/0052-pg-cdc-spine-and-stage2-extraction.md:45-54` | Owner ruling 2026-08-12 (Q3): Go SBV decoders are primary **by coverage**, no size axis, for formats that must be PARSED. | CONSTRAINS (scope boundary: applies to parse-required formats, not extract-only) |

**Verdict: SETTLED.** P6 restates the 2026-09-03 ruling (reconfirmed 11:52 today) exactly. It does not contradict ADR-0052 Q3 because the two rulings partition by category (extract-only vs. must-be-parsed), not in conflict.

---

## P7 — Attachments extracted at parse into named subfolder, converted, indexed; counted as permanent

| Source | Location | What it says | Relation |
|---|---|---|---|
| Memory | `attachments-extracted-at-parse.md` (owner 2026-09-06 11:43, HARD) | Verbatim match: parser extracts every attachment on every run into a subfolder beside the parsed object, real filename, converted/indexed, row in `context.source_version_object` role `attachment`, own SHA; byte range is provenance only. "Storage math: decoded attachment set is a permanent copy... never count it as zero." | ALREADY RULED SAME |
| Decision Log | D-136 (2026-09-02) | "EXTRACT EVERYTHING... A parser that silently drops records it could have kept is a defect" — cites the 516 dropped attachment-only MMS records. | CONSTRAINS/reinforces |
| Change map | §3d | Proposes "decode-on-view, materialize only if promoted" for attachments — the memory note calls this exact alternative a contradiction of the settled contract. | CONTRADICTS (the change-map's own §3d, not P7) |

**Verdict: SETTLED.** P7 is the owner's own 11:43 ruling restated. The change-map's §3d (decode-on-view) is the proposal that must be withdrawn/revised, not P7.

---

## Verdict per proposal

- **P1 — OPEN.** No owner ruling predates today; constrained by D-142 and the ingest-retain rule. Needs owner ruling on Q3/Q4 (cache-vs-cold distinction, 7-day TTL predicate).
- **P2 — SETTLED** (Q1=C, `docs/planning/2026-09-03-ingest-redesign-plan-and-sequential-guide.md:321`). Restatement, not new.
- **P3 — OPEN.** No prior ruling drops `content_chunk.content`; Q9=A (bridge) constrains but doesn't decide it.
- **P4 — OPEN.** Same family as P3; Q8 (`EvidenceChunkV2` cut) explicitly unruled.
- **P5 — OPEN.** No prior ruling on the test/vault/discard gate mechanism; constrained by `test-the-job-not-the-transport.md` and D-145/D-146 vocabulary.
- **P6 — SETTLED** (owner ruling 2026-09-03, reconfirmed 2026-09-06 11:52, `docs/planning/2026-09-03-ingest-redesign-plan-and-sequential-guide.md:53-65,417`). Restatement, not new.
- **P7 — SETTLED** (owner ruling 2026-09-06 11:43, `attachments-extracted-at-parse.md`). Restatement; the change-map's own §3d is the outlier requiring withdrawal.

## Newest owner statements (topic → date/time → statement)

- Attachments extraction → 2026-09-06 11:43 → "extracted at parse... subfolder... never lazy byte-range-only" (verbatim rule, see above).
- DuckDB ELT primary/fallback → 2026-09-06 11:52 → "DuckDB ELT primary for extract-only formats; decoders are the logged-failure fallback."
- Raw byte offsets (Q1) → 2026-09-04 ~23:4x → "my lean is C… make it work the same way and everything checkable again."
- Sealing/custody timing → 2026-09-06 → "Sealing into the content-addressed store (H1) = custody at PROMOTION only" (`test-the-job-not-the-transport.md`).
- Context→Surreal→evidence order → 2026-09-06 (D-145) → "It's probably gonna go into Surreal from that point... when I decide that it's important, that it's relevant, at that point we can package it and promote it to evidence."
- Zero live evidence / teardown discipline → 2026-09-05 late → "We have zero committed and live evidence... trying to preserve shit that isn't actually there is what drove two weeks worth of bullshit with the databases" (D-142).

## Not found / SILENT

- No prior ruling names a "test/vault/discard" enum or a `permanent_home` column anywhere before today.
- No prior ruling on retiring `working.content_chunk.content` or Weaviate's `content` property.
- No explicit 7-day TTL number or "run terminal + SHA matches cold" predicate found before today's change map.
