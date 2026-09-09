# Storage Copies and Derived Layers — Thinking Pass

> _Byline: Claude Code · Opus 5 · 2026-09-06._

STATUS: ANALYSIS — feeds the derived-layers change map; owner has not ruled.

Scope: the seven proposals P1–P7 made 2026-09-06 11:30–11:53 without a thinking pass. Each is treated as a hypothesis. Fixed constraints respected: D-124 (hash at promotion only), D-145/146 (context → Surreal → evidence), ADR-0052/D-054 (PG canonical, projections carry PG coordinate), D-130 (one job per Activity), 2026-09-03 (Go orchestrates DuckDB), ADR-0053 (chunk→classify→domain-tag settled), D-142 (test data disposable), D-073/D-080 (horizon filter lives in Surreal).


> **Owner corrections 12:07–12:12, applied:** (1) P5 is closed, not open: the destination gate fires ONLY for one-off sources (upload/drop/test); anything already sorted into the Case Bible vault has its home and gets no gate. (2) The ToC "operator time is the bottleneck" finding is WITHDRAWN: the gate is one click on a file the owner is already pushing through; not a constraint. (3) No test bucket; tests live on block at `/data/test_data/<source_type>/<export-folder>/`. Tiers: vault (cold, home) · block (working + test) · `nexus` (workbench upload staging only).

## 1. Router output

| Domain | Problem type | Routed model | Why |
|---|---|---|---|
| Architecture | Optimize | **Theory of Constraints** | The proposals are all resource optimizations. ToC forbids optimizing a non-bottleneck. |
| Architecture | Understand | **First Principles** | "What must be physical" is a fundamentals question; conventional RAG answers come out wrong here. |
| Risk | Predict | **Pre-mortem** | Six of seven proposals delete or relocate a store; failure would be silent. |
| Architecture | Predict | **Second-Order** | Every deletion forces migrations, readers, retrieval-contract changes. |
| Abstract | Evaluate | **Steel-manning** (adversarial pair) | P4's "Weaviate as chunk truth" needs its strongest form argued before rejection. |

Combination pattern: **sequential with one adversarial parallel branch** — ToC → First Principles → Pre-mortem → Second-Order, with Steel-manning run in parallel on P4. The graph map supplies the shared node set all four consume.

## 2. Theory of Constraints — where is the actual bottleneck?

| Candidate constraint | Magnitude (P7's 1.3 GB SMS export) | Verdict |
|---|---|---|
| Bytes at rest | Text side ~1.3 GB → ~2 MB saved. Attachments ~0.9 GB **permanent**. Vectors ~90 MB unchanged. | **Not the constraint.** All text optimizations together move ~0.2% of the footprint. |
| Vectors | ~90 MB, unchanged by every proposal | Not the constraint, but the only irreducible derived cost. |
| Re-scan latency | P2 re-materializes from a 1.3 GB original per preview | **Constraint candidate — created by P2 itself.** |
| **Operator time** | One human, HITL gate on every source, zero live evidence (D-142) | **THE constraint.** |

System throughput is limited by how fast one owner can look at a source and rule on it. Storage is effectively free at this scale. Therefore: **any proposal that trades operator latency for bytes is optimizing a non-constraint and is net-negative.** That single test decides P2 and P5.

## 3. First principles — what MUST be physical, per layer

| Layer | Must be physical? | Irreducible reason |
|---|---|---|
| Original bytes | **Yes, once** | Nothing else can regenerate them. Custody attaches here (D-124). |
| Attachments decoded at parse | **Yes, permanent** | Decoding is not bit-reproducible in practice (codec drift, converter versions), so a decoded attachment is an *original*, not a derivation. Owner ruling 11:43 is first-principles-correct. |
| Message text (`working.normalized_record.content`, verified `text NOT NULL`) | **Yes** | Re-derivation costs a full re-scan of the original, and the constraint is operator latency. This is the one authored spine. |
| Raw record bytes | **No** | Fully re-derivable from original + range. |
| Chunk text (`working.content_chunk.content`) | **No** | Fully determined by member ids + ordering + the physical message text. Pure duplication. |
| Vectors | **Yes** | Not derivable without paying the embedder again. |
| Chunk *definition* (generation + index + member ids) | **Yes, in PG** | Authored by the chunker; not derived from anything. |
| Horizon filter | **Surreal only** (D-073/D-080) | Not a storage question at all. |

Conclusion: exactly **two** authored text stores are justified — original bytes (cold) and `normalized_record.content` (PG). Everything else is derived or a vector.

## 4. Pre-mortem, per proposal

| # | It is 2026-12. This failed. Why? |
|---|---|
| P1 | The 7-day TTL sweep deleted the block cache for a run marked terminal that the owner had not yet triaged (D-145 puts the owner's read *after* ingest). SHA matched cold, so no alarm fired; the owner simply waited on a cold re-pull at every review. **TTL keyed to the wrong event.** |
| P2 | Every HITL preview re-scanned 1.3 GB through DuckDB. Preview went from milliseconds to tens of seconds; the owner stopped previewing and started rubber-stamping. **Attacks the real constraint to save 1.3 GB.** Separately, it reinvented machinery that already exists: `context.source_range_locator` (`coordinate_system`, `range_start`, `range_end`, `exact_slice_sha256` — sql/0047:179) plus `context.normalized_record_range_locator`. Adding `byte_start`/`byte_end` columns would have created a *second*, competing locator model. |
| P3 | Dropping `working.content_chunk.content` broke `CHECK (digest(convert_to(content,'UTF8'),'sha256') = content_sha256)` (sql/0047:244) and seven live readers: `modules/engine/activities/chunking.go`, `modules/engine/postgres/chunk_repository.go`, `server/contracts/records.py`, `server/evidence/store.py`, `server/evidence/native_activation.py`, `server/evidence/vector_projection.py`, `server/proffer/query.py`. `content_sha256` survived with nothing verifying it — an integrity field asserting nothing. |
| P4 | Weaviate hit → PG round-trip added a hop per result set; a 50-hit query became 50 point-reads. Separately, a horizon-shaped filter was written as a `FilterExpr` and agno's adapter silently dropped it (`weaviate.py:414-416`, `:441-443`, `:883-884`). |
| P5 | The gate sat **before parse**, so the owner triaged filenames rather than content. Everything went to "test" because nothing was legible. Contradicts D-145: the owner reads context first, then decides. |
| P6 | DuckDB ELT was declared primary while `RegisterStructuredELTActivities` (`modules/engine/activities/register.go:222`) was still **never called by any worker** — verified; the only caller is its own test. "Primary" named a path no worker could execute. |
| P7 | The estimate optimized the 0.2% and ignored the 99.8%. Attachments (~0.9 GB permanent, per source) set the storage curve, and no proposal states a dedup or conversion-target policy for them. |

## 5. Second-order — what each change forces next

| # | Forces |
|---|---|
| P1 | Sweep Activity plus a `permanent_home` state machine; every reader of block paths must handle cache-miss → cold re-pull; an R2 Class-A cost model for re-pulls. |
| P2 | Locator population becomes mandatory inside the parse Activity; `verification_activity_receipt_id` is NOT NULL, so a receipt must exist per locator — a new Activity dependency, and D-130 says that is its own unit. |
| P3 | One migration dropping `content` **and** the CHECK together; a `working.content_chunk_text` view; seven reader migrations; the embedding path must materialize text before the embedder; the vector-projection job contract changes. |
| P4 | The retrieval contract gains a mandatory PG-coordinate hydration step; batched (not per-hit) fetch becomes a requirement; Weaviate rebuild-on-embedder-change becomes a routine runbook rather than an incident. |
| P5 | New source-row column, gate Activity, later an n8n node; interacts with D-145's Surreal step ordering. |
| P6 | Worker registration first; the router gains a coverage-table entry (ADR-0052 Q3: coverage-based, never size-based). |
| P7 | Attachment naming/conversion/indexing becomes a first-class Activity family rather than a parse side-effect (D-130). |

## 6. Graph map — every holder of message content today

Nodes (centrality H/M/L):

| Node | Kind | Centrality |
|---|---|---|
| N1 original bytes (R2 cold) | authored | **H** — root of every path |
| N2 VPS block copy | cache | M |
| N3 `context.retained_object` / `source_version_object` (roles `original`, `container_member`, **`attachment`**, `derived_reference` — verified sql/0036:147) | authored ref | M |
| N4 `context.raw_record` bytes | derived | L |
| N5 **`working.normalized_record.content`** | authored | **H** — the spine |
| N6 `working.content_chunk.content` | derived | M |
| N7 `working.content_chunk_message` (sql/0072) | authored definition | **H** |
| N8 `context.source_range_locator` + `normalized_record_range_locator` | derived coordinate | M (currently unpopulated) |
| N9 Weaviate object (vector + payload) | projection | M |
| N10 Surreal analytical graph | projection | M |
| N11 attachments decoded | authored | **H** by bytes |

Edges: N1→N2 (copy-of); N1→N3 (registered-as); N1→N4 (derives-from); N4→N5 (derives-from); N5→N6 (derives-from, **via** N7); N7→N6 (defines); N1→N8 and N5→N8 (points-to); N6→N9 (embeds-into); N9→N5 (points-to — the PG coordinate); N5→N10 (projects-into); N3→N11 (contains).

Clusters: **authored** {N1, N5, N7, N11} · **derived** {N4, N6, N8} · **projection** {N9, N10} · **cache** {N2}.

Nodes the proposals delete: P2 → N4; P3 → N6 (text only — N7 survives and *becomes* the definition); P4 → the text payload inside N9; P1 → N2 on a timer. Every deletion lands in the derived or cache cluster, and **no proposal touches the authored cluster.** That is the structurally correct shape.

## 7. Adversarial — "Weaviate as chunk truth" vs "PG bridge as truth"

**Steel-man for Weaviate as truth:** a chunk exists in order to be retrieved. The embedding is its operative identity, and the vector cannot be reconstructed from ids without paying the embedder — Weaviate is the only store holding something irreplaceable about a chunk. Splitting definition (PG) from vector (Weaviate) creates two writes that can diverge: a chunk with no vector, or a vector whose member ids no longer resolve. One store, one truth, no skew.

**Rebuttal:** (a) the vector is irreplaceable only until the embedder changes — and it does change (NIM EOLs, 2026-08-26), so the definition must outlive it and cannot live in the perishable store; (b) ADR-0052/D-054 make PG canonical and require every projection to carry the PG coordinate, so a Weaviate-truth model is out of canon by construction; (c) the horizon must be a *pre*-filter, and agno's Weaviate adapter silently drops FilterExpr lists — a store that cannot be reliably filtered cannot be an authority; (d) divergence is repaired by rebuild-from-PG, which only exists if PG is truth.

**Resolution: the PG bridge (N7) is truth; Weaviate is the sole holder of vectors and is disposable.** P4 as written is correct.

## 8. Convergence / divergence

| Question | ToC | First Principles | Pre-mortem | Second-Order | Result |
|---|---|---|---|---|---|
| Drop raw bytes (P2) | neutral | yes | **no — latency** | new receipt dependency | **Diverges** → keep, but scope to raw only |
| Drop chunk text (P3) | neutral | **yes** | breakage, fixable | 7 readers + CHECK | **Converges** |
| Weaviate holds no text (P4) | neutral | yes | round-trip risk | batched hydration | **Converges** |
| Attachments permanent (P7) | **dominant cost** | yes (not reproducible) | policy unaddressed | new Activity family | **Converges on keep; diverges on its silence about policy** |
| Gate before parse (P5) | **no** | no | no | — | **Converges against** |

## 9. Verdicts

| # | Verdict | Change / question |
|---|---|---|
| P1 | **ADOPT-WITH-CHANGE** | TTL trigger must be run-terminal **AND** `permanent_home` written **AND** SHA matches cold — not terminal alone. |
| P2 | **ADOPT-WITH-CHANGE** | Do **not** add `byte_start`/`byte_end`; populate the existing `context.source_range_locator` / `normalized_record_range_locator` (sql/0047:179+). Scope the byte-drop to the **raw** layer only — `working.normalized_record.content` stays physical. |
| P3 | **ADOPT-WITH-CHANGE** | Drop `content` **and** its digest CHECK in one migration; expose a `working.content_chunk_text` view; migrate the seven named readers in the same change. |
| P4 | **ADOPT** | Add two conditions: dict filters only on Weaviate; hydrate PG with one batched read per result set, never per hit. |
| P5 | **NEEDS-OWNER-RULING** | Should the destination gate sit *after* an extract-only text preview rather than before parse, given D-145 puts your read before the decision? |
| P6 | **ADOPT-WITH-CHANGE** | Wire `RegisterStructuredELTActivities` into a worker first — it is currently called only from its own test. |
| P7 | **NEEDS-OWNER-RULING** | Attachments are ~99.8% of the footprint: do decoded attachments get content-hash dedup across sources and a fixed conversion-target policy before this estimate is used for capacity? |

## 10. Owner questions

1. P5 gate placement: before parse, or after an extract-only preview?
2. P3: does `content_sha256` survive on `content_chunk` once nothing verifies it, or is it dropped alongside `content`?
3. P7: attachment dedup and conversion-target policy — decided before capacity numbers are trusted?
4. P1: is a cold re-pull acceptable during review, or must the block cache survive until the source is promoted or discarded?
5. P2: confirm the raw-layer-only scope — i.e. `normalized_record.content` is never re-materialized on demand.
