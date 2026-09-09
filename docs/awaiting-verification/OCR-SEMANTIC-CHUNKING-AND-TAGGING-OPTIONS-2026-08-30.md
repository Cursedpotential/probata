# OCR, semantic chunking, and compact tagging options

> **Status:** pending owner review; research and design only  
> **Snapshot:** 2026-08-30  
> **Byline:** Codex · GPT-5.6-Sol  
> **Boundary:** repository inspection and official-source research. No provider account was
> created, no evidence was uploaded, no production service was changed, and no OCR quality claim
> below replaces a representative corpus benchmark.

## Answer first

The lowest-cost credible pipeline is not one OCR engine. It is a ladder:

1. Extract native text and layout first. Do not OCR born-digital pages.
2. Use Tesseract/OCRmyPDF for ordinary scans on the controlled Platform Tools worker.
3. Escalate difficult pages—not whole files—to a structured parser.
4. Test Granite Docling cheaply on Colab Pro, using synthetic or expressly cloud-approved pages.
5. For durable remote execution, prefer a scale-to-zero Granite Docling worker or a dedicated
   page API. NVIDIA Nemotron Parse is the best free prototype route already represented in the
   Platform model catalog; Mistral OCR Batch is the clearest predictable paid fallback.
6. Give the semantic model stable block IDs plus text, and require it to return only block ranges,
   type/tag codes, confidence, and review state. The model never repeats the document text.

The immediate product problem is not lack of candidates. It is that the current Platform advertises
more than it can execute and has no atomic semantic chunk tool:

- Tesseract/Poppler/pytesseract are baked into `platform-tools`, but tests prove package/binary
  declarations rather than real OCR output.
- `documents.extract-docling` is registered, but Docling is deliberately omitted from that image.
  Office formats consequently have no working fallback there.
- Chonkie 1.7.0 is installed and the canonical ingest path uses a deterministic character-recursive
  chunker, but no `chunk.*` capability is registered through Platform Tools.
- The richer Chonkie factories and Semantica structural chunker exist, but are not atomic Platform
  Tools capabilities or the canonical document path.
- Local discovery currently returns 39 tool declarations, including two `extract.text` tools and
  zero `chunk.*` tools. A local declaration does not prove the deployed image can execute it.

## Recommended Platform pipeline

| Stage | Default | Escalate when | Durable output |
|---|---|---|---|
| 0. Inspect | native PDF/Office/text extraction | native layer missing, sparse, or corrupt | page/block inventory with stable IDs and source locators |
| 1. Classical OCR | Tesseract through OCRmyPDF or existing `documents.extract-text` | low text yield, handwriting, bad reading order, tables, forms, formulas | searchable rendition plus word/line boxes and engine receipt |
| 2. Structured parsing | Docling standard pipeline or Xberg in native/Tesseract-only mode | complex layout or office structure needs recovery | DoclingDocument/structured JSON plus Markdown projection |
| 3. Document VLM | Granite Docling remote worker | Stage 2 is incomplete or layout-heavy | DocTags/blocks, tables, formulas, boxes, confidence, model/container hashes |
| 4. Dedicated hosted OCR | Nemotron Parse, then Mistral OCR Batch, then Google/AWS/Mathpix | remote worker unavailable or benchmark shows a provider wins a document class | immutable provider response and cost/retention receipt |
| 5. Semantic boundaries | low-output model over stable block IDs | overlap disagreement or low confidence | block ranges and controlled codes only |
| 6. Local reconstruction | deterministic Platform code | never delegated | exact chunk text reassembled from retained blocks and source ranges |
| 7. Embedding/classification | reconstructed chunks | only difficult/valuable chunks receive richer summaries | versioned derived projections; PostgreSQL remains canonical |

OCR, structural parsing, semantic grouping, tagging, and summarization are separate passes. A
provider that performs several internally still has to return pass-specific receipts and source
coordinates so the output remains reproducible and reviewable.

## Compact semantic-boundary contract

The structural pass creates stable, ordered blocks. A block should retain page, kind, bounding box,
text hash, and an exact source range. The model sees the block IDs and text but returns no text:

```json
{
  "schema": "semantic-range-v1",
  "document_type": "court-filing",
  "chunks": [
    {
      "start_block": "b000012",
      "end_block_exclusive": "b000019",
      "kind": "procedural-history",
      "tags": ["custody", "prior-order"],
      "confidence": 0.93,
      "needs_review": false
    }
  ]
}
```

Contract rules:

- Ranges are half-open: `start_block` is included and `end_block_exclusive` is not.
- Blocks are immutable within one extraction generation. A re-extraction creates a new generation.
- `document_type`, `kind`, and `tags` are controlled codes, not free-form prose.
- The first pass emits no summary. Summary generation is a later selective pass.
- Tables, attachments, message units, signatures, and page furniture carry explicit structural
  kinds so the boundary model can preserve or exclude them deliberately.
- Long documents use overlapping block windows. Reconciliation accepts matching boundaries,
  routes disagreements to a narrow adjudication call, and never asks a model to repeat source text.
- The Platform reconstructs chunk text from the retained blocks and proves the exact source ranges.

Expected output is approximately 15–40 tokens per chunk without a summary. At ten chunks per file,
150,000 files would use roughly 22.5–60 million boundary-output tokens. The number is driven by
semantic chunks per file, not input length.

## Fit with the current Platform schema

The format-neutral foundation in migration `0047` already has the right lineage primitives:

- immutable chunk generations;
- `context.source_range_locator` with half-open byte/codepoint ranges and slice hashes;
- `working.content_chunk` with content hashes and derivation mode;
- ordered source-span membership and reassembly receipts;
- append-only chunk lane-classification decisions.

The earlier chat schema also has `reference.knowledge_tag` and provenance/confidence/review fields
for `working.chat_chunk_tag`. That table is specific to legacy chat chunks. The generalized
`working.content_chunk` foundation does **not** yet have a generalized tag-assignment relation.

Therefore the model should emit canonical tag slugs now, but implementation should not force them
into the legacy chat table. After owner review, add one generalized, append-only content-chunk tag
assignment contract that references `reference.knowledge_tag`, carries classifier/prompt/model
versions, confidence and review state, and never changes evidence status. Lane classification,
document type, semantic kind, reusable tags, and evidence promotion remain distinct concepts.

## Python projects — five

| Project | Best use | Cost/license | Platform judgment |
|---|---|---|---|
| [Docling](https://github.com/docling-project/docling) | mixed documents, reading order, tables, formulas, structured JSON/Markdown | open source, MIT | primary structured-parser candidate; separate standard and Granite-VLM modes |
| [OCRmyPDF](https://github.com/ocrmypdf/OCRmyPDF) | searchable PDF/A, deskew, cleanup, lossless scan preservation | $0 software, MPL-2.0 | best mature Tesseract batch wrapper |
| [PaddleOCR](https://github.com/PaddlePaddle/PaddleOCR) | multilingual OCR, layout, tables, seals, formulas | $0 software, Apache-2.0 | strong benchmark candidate but local neural inference conflicts with current remote-only policy |
| [MinerU](https://github.com/opendatalab/MinerU) | difficult technical layouts, formulas, figures, cross-page tables | $0 software; custom project license needs review | useful free API/local benchmark; do not assume production license or custody fit |
| [RapidOCR](https://github.com/RapidAI/RapidOCR) | lightweight OCR component and Docling backend | $0 software, Apache-2.0 code; model rights separate | exclude while ONNX/local-model inference remains prohibited |

## JavaScript and TypeScript projects — five

| Project | What it does | Platform judgment |
|---|---|---|
| [Xberg Node](https://github.com/xberg-io/xberg) | typed bindings over a Rust document core; native extraction, OCR chains, tables, boxes, REST/MCP | most complete candidate, but the v1 line is new; benchmark as an isolated service |
| [Scribe.js](https://github.com/scribeocr/scribe.js/) | browser/Node OCR workflow over Tesseract.js; native-PDF detection, OCR caches, searchable PDFs | strongest JS-only workflow; AGPL requires a deliberate service/license boundary |
| [Tesseract.js](https://github.com/naptha/tesseract.js/) | Tesseract compiled to WebAssembly for browser/Node | useful for bounded image OCR; no direct PDF, handwriting, or semantic table parsing |
| [unpdf](https://github.com/unjs/unpdf) | serverless PDF.js native text, links, images, metadata, and rendering | excellent stage-zero native-text detector for Workbench/edge paths; not OCR |
| [PDF.js](https://github.com/mozilla/pdf.js/) | mature browser PDF renderer and text layer | best viewer/coordinate overlay substrate; not an OCR engine |

## Go projects — two

| Project | What it does | Platform judgment |
|---|---|---|
| [gosseract](https://github.com/otiai10/gosseract) | CGO binding to Tesseract/Leptonica | use only if OCR must live inside Go; a separate process/service is safer than adding CGO to custody-critical binaries |
| [pdfcpu](https://github.com/pdfcpu/pdfcpu) | pure-Go PDF validation, split/merge, images, forms, encryption, preprocessing | excellent deterministic preparation adapter; it is not OCR or semantic layout extraction |

## Rust projects — two plus one held candidate

| Project | What it does | Platform judgment |
|---|---|---|
| [Xberg](https://github.com/xberg-io/xberg) | native extraction for many formats, OCR backends, tables, boxes, batch/streaming, REST/MCP | most promising next-tier self-hosted candidate; use native/Tesseract-only mode initially and treat newness as risk |
| [ocrs](https://github.com/robertknight/ocrs) | early-preview Latin OCR with coordinates through RTen models | exclude: early preview, narrow language support, and local neural-model conflict |
| [docling.rs](https://github.com/docling-project/docling.rs) | Rust Docling implementation with layout/table pipeline | held, not shortlisted: current PDF/image path requires local model artifacts including ONNX-style components |

## Tesseract and Tesseract-enabled applications

[Tesseract](https://github.com/tesseract-ocr/tesseract) itself is mature, Apache-2.0, multilingual,
and can emit hOCR, TSV, ALTO, PAGE XML, text, and searchable PDF. It is a recognition engine, not a
complete reading-order/table/document-understanding system.

| Application | Best use | Platform judgment |
|---|---|---|
| [OCRmyPDF](https://github.com/ocrmypdf/OCRmyPDF) | production batch searchable-PDF creation, deskew/cleanup, validation | recommended controlled worker |
| [NAPS2](https://www.naps2.com/doc/ocr) | Windows/macOS/Linux scanning, preprocessing, imported-PDF OCR | excellent owner-side intake/batch fallback; retain output as a derived rendition |
| [Stirling PDF](https://github.com/Stirling-Tools/Stirling-PDF) | broad self-hosted PDF operations and Tesseract OCR | isolated operator utility only; audit edition/subtree licenses |
| [Paperless-ngx](https://github.com/paperless-ngx/paperless-ngx) | full document-management ingest/OCR/tag/search UI | do not create a parallel canonical store; reference deployment only |
| [gImageReader](https://github.com/manisandro/gImageReader) | manual Tesseract review with hOCR confidence and box editing | useful proofreading donor, but stale release cadence makes it a poor new production dependency |

## Next-tier self-hosted document intelligence

1. **Docling standard pipeline:** first benchmark for structure and ordinary scans. It can use
   Tesseract and avoids a proprietary page charge.
2. **Granite Docling 258M:** first remote document-VLM benchmark. It is purpose-built for DocTags,
   layout, tables, formulas, and document conversion, and is Apache-2.0.
3. **Xberg:** benchmark as a uniform native/Tesseract extraction facade with structured output.
   It is feature-rich but new, so observed corpus behavior matters more than its catalog.
4. **PaddleOCR/PP-Structure:** strong quality comparator where the current no-local-model rule can
   be satisfied by an approved remote worker. Do not introduce an ONNX/local fallback silently.
5. **MinerU:** useful free/trial comparator for technical documents; legal/license and custody
   review must precede production use.

## Hosted parsers and OCR APIs

Prices are per page. **150,000 files cannot be budgeted without total pages.** The last column uses
150,000 pages only as an illustration.

| Service | Current public free/price signal | 150k-page illustration | Best use / caution |
|---|---:|---:|---|
| [NVIDIA Nemotron Parse](https://build.nvidia.com/nvidia/nemotron-parse) | hosted NIM preview free for prototyping; production price not published | unknown | best first free exception probe; English document parsing, tables, layout classes and boxes |
| [Google Document AI OCR](https://cloud.google.com/products/document-ai/pricing) | first 1,000 pages/month free, then $1.50/1k through 5M | about $223.50 | low-cost printed/handwritten OCR; Layout Parser is $10/1k |
| [Google Cloud Vision OCR](https://cloud.google.com/vision/pricing) | first 1,000 units/month free, then $1.50/1k | about $223.50 | simple OCR where document structure is not required |
| [AWS Textract](https://aws.amazon.com/textract/pricing/) | $1.50/1k basic text; new-account allowance 1,000 pages/month for three months | about $225 | handwriting/basic text; tables/forms are much more expensive |
| [Mathpix](https://mathpix.com/pricing) | $1.50/1k batch pages plus account/setup terms and testing credit | about $225 usage | math, handwriting, tables, diagrams |
| [Mistral OCR 4](https://mistral.ai/news/ocr-4/) | $4/1k standard; official Batch discount makes it $2/1k | $600 standard / $300 batch | strongest predictable dedicated paid fallback; boxes, blocks, confidence, 170 languages |
| [Azure Document Intelligence](https://azure.microsoft.com/en-us/pricing/details/ai-document-intelligence/) | 500 free pages/month; public numeric paid rate is region/calculator-dependent | unverified | strong layout/table/handwriting benchmark, but not publicly budgetable here |
| [LlamaParse](https://www.llamaindex.ai/llamaparse) | 10,000 free credits/month, advertised as about 1,000 pages; current paid rate not public | unverified | complex layout, multi-page tables, handwriting; benchmark before budgeting |
| [Unstructured](https://unstructured.io/pricing) | current public pricing says 10,000 starting pages then $0.015/page; its separately published platform terms have shown different allowances/rates | $2,100 after the public starting allowance, if the pricing page governs | broad formats/connectors/chunking; confirm the account's controlling rate before volume use |
| [LandingAI ADE](https://landing.ai/pricing-agentic-apis) | 1,000 free credits; variable credit consumption lacks a stable public page rate | unverified | complex visual documents and grounded extraction |
| [Reducto](https://reducto.ai/pricing) | credit-based; stable public page rate unavailable at snapshot | unverified | benchmark candidate only until budgetable |

For sensitive material, free tier does not mean acceptable. Provider retention, training use, data
residency, zero-data-retention eligibility, and batch/file retention must be approved per provider
before any upload.

## Services that bundle parsing with chunking, tagging, or summarization

This is the more useful comparison when the goal is to reduce both integration work and extra model
calls. Prices below are ordered by the cheapest publicly budgetable entry point. “Bundled” means the
capability is available from the same vendor; it does not always mean one API call or one page charge.

| Service | Public entry price | Parse/convert | Chunk | Tag/classify | Summarize | HTML/Office breadth | What one bill actually buys |
|---|---:|---:|---:|---:|---:|---|---|
| [Unstructured](https://unstructured.io/pricing) | first 10,000 pages free; then $15/1,000 pages | yes | yes: character, title, page, similarity, contextual | NER plus custom element classification | image/table descriptions, not a general whole-document summary | excellent: HTML, XML, email, Office, PDF, images and many legacy formats | strongest low-price transform pipeline: partition, chunk, enrich, embed; VLM/enrichment passes can affect effective billing |
| [Google Document AI](https://cloud.google.com/products/document-ai/pricing) | Layout Parser $10/1,000 pages | yes | included; re-chunking is $0.02/1,000 chunks | custom classifier or splitter adds $5/1,000 pages | summarizer adds $25/1,000 pages | excellent: HTML, PDF, DOCX, PPTX, XLSX/XLSM | most transparent full suite: parse + chunk + classify + summarize is approximately $40/1,000 pages if every page receives every pass |
| [Reducto](https://reducto.ai/pricing) | first 15,000 credits free; then $0.015/credit | yes | layout-aware chunking in Parse | Classify and Split APIs | table/figure summarization and VLM enrichment | excellent: HTML, Office, spreadsheets, PDF, images | broadest agentic document workflow, but operations/configuration consume different credits; benchmark a sample to learn effective per-page cost |
| [LandingAI ADE](https://docs.landing.ai/ade/ade-pricing) | 1,000 free credits; $0.01/credit; Parse is 3 credits/page ($30/1,000) | yes | Parse returns grounded chunks; Section adds hierarchy | Classify is 0.5 credit/page ($5/1,000); Split also classifies sub-documents | figure summaries included; no clearly priced general whole-document summary | strong: PDFs, images, text documents, presentations, spreadsheets | best tightly integrated schema workflow: parse/chunks + figure descriptions + classify + section/split + field extraction; parse + classify starts near $35/1,000 pages |
| [LlamaCloud](https://www.llamaindex.ai/llamacloud) | free trial/credits; current public paid unit rate not exposed | yes | Index adds intelligent chunking and embeddings | schema extraction can produce chosen labels, but no clear standalone classifier on the public product page | not a clearly priced core primitive | broad complex-document support | Parse + Extract + Index is a coherent managed RAG path, but these are distinct products and cannot be honestly cost-ranked from current public pricing |
| [Azure Content Understanding](https://learn.microsoft.com/en-us/azure/ai-services/content-understanding/pricing-explainer) | region and model dependent | yes | segmentation/chunk-ready output | categorization supported | generative fields/insights through the customer's Foundry model | excellent for digital Office/HTML plus scanned documents | can cover extraction, segmentation and classification, but adds content-extraction, contextualization and model-token charges; budget only after a measured sample |

### Important near-misses

- **Mistral OCR, Nemotron Parse, Mathpix and basic Google/AWS OCR** are good parsers/OCR engines,
  but they do not themselves replace the semantic chunking, tagging and summary passes.
- **MinerU's free Agent API** and a remote **Granite Docling** worker can parse/convert and emit
  heading-aware or structural chunks cheaply. Tagging and summaries remain our own low-output model
  calls, which is often desirable because the Platform controls the codes and provenance.
- **Unstructured** provides the widest cheap file-conversion surface, but its “summary” features are
  primarily image/table descriptions. Do not assume it generates the compact document/chunk summary
  required by the Platform without a separate prompt/enrichment definition.
- **LandingAI** and **Reducto** use “chunk” for detected document regions as well as retrieval-ready
  grouping. Confirm the returned granularity against the Platform's semantic-range contract.

### Practical order for this Platform

1. Use **Unstructured's 10,000-page allowance** to test the widest mix of HTML, email, Office and
   legacy files, including partition + title/contextual chunking + NER/table descriptions.
2. Use **LandingAI's 1,000 credits** on the hardest visual documents where grounded chunks, figure
   summaries, classification and schema extraction can be evaluated together.
3. Use **Reducto's 15,000 credits** on complex tables/forms and measure the exact credit receipt for
   Parse, chunking, summarization and Classify separately.
4. Use **Google Layout Parser** when transparent production pricing and HTML/DOCX/PPTX/XLSX support
   matter. Add its classifier only if it beats the Platform's compact low-output classifier; add the
   $25/1,000-page summarizer only where a summary is actually valuable.
5. Use **LlamaCloud** only after the free trial proves its parse/index quality and the account shows
   current paid rates. It is attractive for managed retrieval, but PostgreSQL and Platform custody
   must remain authoritative.

## Free and inexpensive OCR-specialized models

| Model/route | Type and price | Judgment |
|---|---|---|
| [NVIDIA Nemotron Parse](https://build.nvidia.com/nvidia/nemotron-parse) | dedicated parser; hosted prototyping currently free | first Platform exception probe because the exact model ID and NVIDIA route already exist |
| [Granite Docling 258M](https://huggingface.co/ibm-granite/granite-docling-258M) | dedicated open model; compute only | best owner-controlled document-VLM candidate; run remotely, not as a hidden local fallback |
| [Mistral OCR 4](https://docs.mistral.ai/models/ocr-4-0) | dedicated API; $4/1k or $2/1k Batch | best predictable paid exception service |
| [GLM-OCR](https://ollama.com/library/glm-ocr) | dedicated 0.9B model; local Ollama listing | promising, but no `:cloud` route was verified; do not run locally under current policy |
| [Nemotron Nano 12B VL free](https://openrouter.ai/nvidia/nemotron-nano-12b-v2-vl%3Afree/pricing) | OCR-capable generic VLM; $0 while offered | synthetic benchmark only: current route indicates prompt training and unclear retention; never custody evidence |
| [Gemini 2.5 Flash-Lite](https://ai.google.dev/gemini-api/docs/pricing) | generic multimodal model; free tier or $0.10/M input + $0.40/M output | extremely cheap adjudicator/tagger; not the source-text authority |
| [GPT-5 nano](https://developers.openai.com/api/docs/models/gpt-5-nano) | generic multimodal model; $0.05/M input + $0.40/M output | tiny hard-page adjudication lane only; measure image tokenization before budgeting |

Generic VLMs may adjudicate ambiguity or assign semantic codes after dedicated OCR. They must not
silently replace or “correct” extracted source text.

## Granite Docling on Colab Pro

Yes, Colab Pro can run Granite Docling effectively for a bounded benchmark.

- The model is 258M parameters and Apache-2.0.
- IBM's model card specifically documents the older Colab T4 issue: T4 lacks BF16 support for this
  path, so use `float32`. It works but is slower.
- Colab does not guarantee GPU type or availability. Managed runtimes remain ephemeral and
  generally have a 12-hour maximum; Pro+ can reach 24 hours with sufficient compute units.
- The notebook must process page batches, write a manifest/receipt after every completed batch,
  resume from the manifest, and never depend on one uninterrupted session.
- Use a synthetic or expressly cloud-approved 100–500 page benchmark first. Do not place real
  evidence in Drive/Colab merely because the compute is cheap.
- A current experimental Kaggle benefit adds 15 extra GPU-hours/week for linked Colab Pro accounts.

For repeatable production compute, current scale-to-zero reference prices are approximately:

- [Modal](https://modal.com/pricing): T4 $0.5904/hour, L4 $0.7992/hour, with $30/month Starter
  compute credit.
- [RunPod](https://docs.runpod.io/serverless/pricing): inexpensive A4000/T4-class serverless
  workers around the same order of magnitude; verify the selected GPU at deployment time.
- RunPod's current secure 4090 reference is about $0.69/hour.

Docling's official benchmark reports Granite Docling inference-server throughput around 2–2.4
pages/second on substantially stronger GPUs. A conservative **inference**, not a measured promise,
is 0.5–1 page/second on a cheap T4/A4000. At current compute rates that suggests roughly
$0.16–$0.44 per 1,000 pages before cold start, rendering, storage and egress. The Colab benchmark
must replace this estimate with observed pages/second and quality scores.

The durable worker pattern is: prebuilt digest-pinned image and cached weights; short-lived access
to immutable page blobs; page-reference batches; DocTags plus exact output/model/config/container
hashes; per-page receipts; immediate ephemeral-storage cleanup. It is a derived processing worker,
never a document store.

## Benchmark gate

Use 100–300 representative, non-canonical evaluation pages covering:

- born-digital PDF;
- clean scan;
- skewed/noisy scan;
- handwriting;
- multi-column pages;
- tables with merged cells;
- forms and checkboxes;
- signatures/stamps;
- formulas and diagrams;
- screenshots and photographed pages;
- office documents;
- intentionally damaged or incomplete inputs.

Score character/word accuracy, reading order, table cell fidelity, block/box fidelity, handwriting,
source-coordinate traceability, failure/timeout rate, latency, and effective cost. The winning
engine is selected per document class, not globally.

## Proposed next slice, requiring owner approval before implementation

1. Build a resumable Granite Docling Colab notebook for synthetic/approved benchmark pages.
2. Create a small gold set and record quality, throughput, output size, and actual Pro compute use.
3. Exercise real Tesseract OCR inside the exact `platform-tools` image and add observed-output tests.
4. Make `GET /tools` honest: unavailable optional tools must not advertise as executable.
5. Register structural extraction and the winning Chonkie path under explicit `extract.*` and
   `chunk.*` capabilities; expose them through the existing Platform Tools REST contract.
6. Add the compact semantic-range response schema and overlap reconciliation.
7. Add the generalized content-chunk tag assignment only after owner review of document types and
   tag vocabulary.
8. Prove the API, ContextForge MCP publication, Temporal/n8n execution, receipts, and live Coolify
   worker before calling the capability production-ready.

## Verification receipt

- Read-only repository inspection at commit `43675cb`.
- Local registry discovery: 39 declarations, two `extract.text`, zero `chunk.*`.
- Focused registry/facade/chunking/gateway/MCP contract suite reported 103 passing tests.
- `tests/test_ingest_port.py` currently reports 14 failures and 4 passes because its helper still
  constructs the now-forbidden `platform` ingest lane; this blocks its mocked extraction tests
  before extraction executes.
- No live OCR result, Docling result, rebuilt container, ContextForge execution, Colab run, or
  production deployment was proven in this investigation.
