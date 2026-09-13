# Owner-source contract reconciliation — intake, context, search, and repair

Date: 2026-09-13  
Status: accepted correction and implementation input  
Scope: Probata intake/context, Search/Smart Explore, Docstore, repair, and operator surfaces  

## Why this receipt exists

The files below are original material supplied to Claude on 2026-09-09 and
2026-09-11. They help recover requirements that later summaries omitted or
changed. They do not outrank newer owner direction merely because they preserve
an earlier conversation. This receipt distinguishes owner statements, research
proposals, open questions, and executable requirements. A proposal or
recommendation in these sources is not an accepted architecture decision unless
the owner later accepted it.

Context precedence for this fast-moving system is: current explicit owner
direction first; current accepted contracts next; newer discussions before
older discussions; executable code as proof of present behavior; and older
build kits as historical input. Code does not override newer owner intent. A
disagreement between code and the newer contract is an implementation gap.

## Source inventory

| Owner-supplied source | SHA-256 | Role |
|---|---|---|
| `I need you to refine a prompt.md` | `313F240F9A21AD0A36EB0A7C003DD1B333B8E86DF0E74E9918C3FCBACF6BF4D6` | Original research-agent conversation and corrections |
| `research-agent-prompt.md` | `0E313367B7CE52D6AB4E22B86CF37DC0C0EE5FBF9F39320AC1A101E6282E57A8` | Consolidated research-agent prompt |
| `@GitHub @Academic @Context7 So I think what I'm mi.md` | `B519713892B02EE8733DF652609AB2A3E610F243827276A9F3F020EDB7F61638` | Original lakehouse and storage discussion |
| `DocStore Plugin, Agents and Dedupe Strategy.md` | `C24BAE120F77ED844770DCC13AA331F9885D23A73D52CBB05172502CF7E5D5B3` | Docstore/plugin/reconciliation research |
| `SurrealDB as a Governed Document Store and Agent Memory Layer.md` | `2298A39472D9F036F65AB4816B991CA2E107AE91C28E89589C8E932BC406B59B` | Governed Docstore and forced-retrieval research |
| `xplorer-copilot-buildkit.zip` | `B10358E6EA3684E9D5B24D0C0BD3D33D4FB2CC108E4DF89FA09C74B1B6A34EBE` | Xplorer agent/copilot surface build kit |
| `surreal-docstore.zip` | `9B71FF53115FDD5D1ED8B721929DC14511DECC63A7EEC4F06EE3CEAE22014892` | Original Docstore plugin/agent/schema build kit |
| `repair_tool_kit_buildkit_v2.zip` | `F2A32904D98697ECA6B6A5DEB31D1B1BD388C5D84CC33F2871B759F3D7BD4D9A` | Original extraction and repair build kit |
| `Merged_Output-20260908T233006Z-1-001.zip` | `9006009A45AACB5F06CE6C3E871B18806D64A5BD3E763269643688E9287F88FC` | Three small entity/timeline/narrative spreadsheets supplied as product test material, not an architecture contract |
| `md.md` | `8EF6CD0CECB3C0837A321FEB0BDF2D8C0C13982BD86EE7F659EECC859B1917D4` | Forensic-software-editor research input |
| `drive-download-20260907T133916Z-1-001.zip` | `0C143FCBFE1CED8AFB66F98749F04219D2EFC8443E363CDAA6F3024723E8BB5B` | Large legal/corpus/export bundle; historical source and test material |
| `drive-download-20260907T133641Z-1-001.zip` | `E1DA91A49C246BF017FB370345AFA90E51CF39F272E79261B49B2775642650C2` | Legal document parsing guidance plus prompt corpus |
| `drive-download-20260907T133605Z-1-001.zip` | `43675BA7F5458540538FFA86C27588C42FE146202A085111F0FD51D7289A0BB7` | Legal parsing, prompt, vocabulary, and merged-source bundle |

The sources remain in `F:\Users\matts\Downloads`. They were read in place.
The ZIPs were inventoried through `System.IO.Compression`; they were not
extracted into the repository.

## Binding corrections recovered from the original context

### Source-type storage split

The lakehouse discussion starts with the owner's requirement that context,
unstructured knowledge, and source documents must not require a complete
PostgreSQL restructuring pass before they can be used or projected to the
vector search layer. The same discussion separately preserves a slim
PostgreSQL role for normalized messaging, participant/platform metadata, and
cross-platform temporal reconstruction. These are compatible requirements.

The resulting intake/context contract is:

1. Retain the immutable source package, original bytes, metadata, attachments,
   source fingerprint, and deterministic package manifest digest.
2. For non-messaging material, DuckDB may read and extract retained package and
   derived files directly in place. PostgreSQL stores the durable control
   plane: package/source identity, metadata, provenance, locators,
   fingerprints, parser/template/attempt references, workflow state, operator
   decisions, projection coordinates, and receipts. It is not required to
   duplicate every document body or chunk body.
3. For messaging, PostgreSQL remains the normalized relational system for raw
   and normalized message records, participants, platform origins, temporal
   reconstruction, and the bridge from search chunks to canonical text.
4. After operator approval, context chunks can be projected to Weaviate for
   search. Each result must resolve back to the retained package and the
   canonical content location for its source type.
5. SurrealDB remains the governed Docstore/agent-memory and approved analysis
   surface described by its own bounded contracts. It is not permission to mix
   evidence, potential evidence, intelligence, or documentation indiscriminately.

This supersedes the later blanket statement that all canonical searchable text
must be stored in PostgreSQL. That blanket statement was promoted from an open
proposal without an owner decision. Decision D-158 records the correction.

### Intake/context stops before evidence and custody

The current repair target is intake and context generation. Evidence
promotion and custody are later, separately governed actions. A source may be
marked as potentially relevant to evidence from intake, but intake does not
create an evidence object or start custody. The retained original and package
hash allow a later promotion workflow to reread and rehash the original,
reproduce extraction under recorded versions, and create the later custody
records only after the owner approves promotion.

`EvidenceChunkV1`, `EvidenceChunkV2`, H1/H2/H3 evidence receipts, and evidence
publication are therefore not acceptance criteria for this intake/context
repair. Using their absence to call intake incomplete would test the wrong
boundary.

### Go, DuckDB, Temporal, and n8n

The Go engine orchestrates extraction engines for one package operation.
DuckDB is the primary structured extractor and in-place query engine wherever
the signature registry says the format is supported. Go decoders remain
callable for unsupported formats and logged recovery paths.

Temporal owns durable execution: package-scoped workflow identity,
checkpoints, idempotent activity retries, durable human waits, signals,
queries, cancellation, and receipts. n8n owns visible integration and
composition flows such as arrival triggers, package submission, notification,
and later image/PDF workflows. Whether n8n drives Temporal or Temporal invokes
a bounded n8n activity was explicitly open in the original repair kit; it must
be decided per flow and cannot be silently promoted into a global rule.

The current intake/context workflow must use one Temporal child workflow per
source package when a request contains multiple packages. Payloads remain in
the package stores; workflow messages carry stable references.

### Operator control and exact preview

Automation never removes operator control. Before context projection, the
surface must expose:

- the immutable source, package manifest, source hash, metadata, attachments,
  and every derived repair/extraction artifact;
- selected parser/extractor, compatible alternatives, selection reason,
  versions, profile, template, exact options, workflow/run/activity attempt,
  and receipts;
- the ability to override a compatible parser/extractor, profile, template,
  and options;
- the ability to rerun after a template or option change, retain the previous
  attempt, and compare attempts;
- previews of extracted records, attachments, and the exact chunks that would
  be projected to Weaviate;
- visible workflow stages, active waits, failures, retries, n8n workflow and
  execution identity where used, Temporal workflow/run identity, and a usable
  cancel/stop path;
- a deliberate approve/reject decision referencing the exact attempt and
  preview digest.

The owner has repeatedly established an exact two-application boundary:

1. **Probata/Proffer** is the intake, extraction, repair, context-preview,
   override, Temporal, and n8n application.
2. **Xplorer + Case Bible + Consignatio** is one combined application/tool. It
   contains the ACP copilot, permissioned file operations, agent HITL, vault
   organization/deduplication, and the Case Bible/Consignatio review and
   legal-data workflows.

Xplorer and Case Bible/Consignatio must not be described as separate products.
The combined application is also not a Proffer module and must not be collapsed
into the Probata intake/context surface. Its interaction requirements provide
relevant design evidence for visibility and control: stream plans and tool
calls, show per-call approvals and diffs, keep terminal output visible, support
follow-along locations, expose Discuss and Draft modes according to negotiated
capabilities, provide stop/cancel, and provide a kill switch. Probata may reuse
those interaction principles without importing the combined application's ACP
file-manager architecture or confusing the two applications.

The same separation applies to indexing. The documentation index is the
Docstore/CocoIndex/SurrealDB lane. The code index is the Search/Smart Explore/
CCC/tree-sitter/DuckDB lane. The code index excludes documentation content and
the documentation index excludes source code. A reconciliation operation may
query both through their separate tools and return labeled evidence from both;
it does not combine them into one physical index.

### Extract broadly; repair only by explicit choice

The original repair kit's `RULES.md` distinguishes extraction from repair.
Extraction is non-destructive and should run whenever the source is readable.
Repair is an explicit operator choice that creates a new derived artifact next
to the byte-identical original. It never overwrites the original. Damage
detection failure is an operational failure, not proof that the source is
damaged.

The repair surface covers source detection and preview plus PDF inspection,
PDF derived repair, OCR/raster fallback, ZIP inventory/unwrap/recurse and
bounded repair, damaged-source flags, quarantine planning/copy, and audit
verification. Extracted attachments are real named package members with their
own hashes and parent links.

### Decision and conflict reconciliation

The original Docstore kit explicitly distinguishes an implemented decision
from a recent proposal. Code/config/schema that proves execution is stronger
than unimplemented prose. An explicit owner decision outranks inference. A
newer ambiguous statement does not automatically supersede an older shipped
contract. Inferred decisions without an explicit statement remain proposed or
are omitted and escalated.

Search/Smart Explore and Docstore reconciliation must preserve those states,
show conflicting candidates with dates and provenance, query all selected
memory stores when requested, and never silently batch-write inferred
decisions. Dirty/conflicting Docstore results may invoke Search/Smart Explore
for code and cross-store evidence, but the reconciler still returns evidence
and a proposed resolution rather than inventing owner approval.

## Executable gaps found on 2026-09-13

The current Go/Temporal code does not yet satisfy the operator contract:

- `chunk_document_activity` is registered and callable but explicitly not
  invoked by `ProfferWorkflow`.
- `publish_preview_activity` follows normalized-generation verification, so
  the workflow can reach its human hold without generating the document
  chunks the owner expects to inspect.
- the current preview projection is message-specific and validates that at
  least one normalized message exists; it cannot represent a generic
  non-messaging document/chunk preview.
- the new preview-decision loop ignores repaired parser-selection and
  parser-options references even though the legacy loop handled them.
- retained attempt comparison, template revision/rerun, exact-stage retry,
  checkpoint resume, authenticated cancel receipts, and one Temporal child per
  package are not complete.
- the checked-in n8n exports use placeholder endpoints and do not prove a live,
  activated workflow or a browser-visible n8n execution.

These are implementation defects and missing product flows. They must remain
visible until repaired and proven end to end; an unavailable badge is a status
signal, not final acceptance.

## Acceptance boundary

The intake/context repair is complete only when a real non-messaging package
can be retained, inspected, extracted through its selected engine, rerun with
an operator-selected compatible engine/template/options, compared with the
prior attempt, chunked, previewed in the browser with exact content and
provenance, approved against an exact preview digest, and projected to the
context Weaviate collection while PostgreSQL and the package store retain the
correct control and source records. The full operation must be observable and
controllable through its Temporal and n8n surfaces. No evidence promotion or
custody claim is part of that proof.
