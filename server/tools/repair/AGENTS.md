# server/tools/repair/ — streaming repair + structural chunking

> _Byline: Claude Code · Opus 5 (1M) · 2026-08-02_
> _Byline: Codex · GPT-5 · 2026-08-13 (Ruff Markdown formatting)_
>
> Nested map. Parent: `../AGENTS.md`. Root: `../../../AGENTS.md`.

## What's here

Damaged-input handling for every text format this corpus arrives in, plus
structural PDF repair. One router, several engines, one reporting contract.

```
types.py      Chunk / RepairEvent / RepairReport / Detection  (stdlib ONLY)
encoding.py   charset detection + STREAMING decode (never read_text)
detect.py     format routing from a bounded head read (content > extension)
chunkers.py   the structural iterators: xml / html / json / ndjson / csv / pdf
engines.py    format -> engine registry, availability probe, iter_chunks()
pdf.py        STRUCTURAL PDF repair via QPDF/pikepdf (rebuild the file itself)
quarantine.py damaged-file lifecycle: rewrite clean / flag / quarantine
```

## The four rules

1. **Never read a whole file.** Every path streams. `encoding.open_text()` is
   the only sanctioned text reader; it wraps a binary handle in an incremental
   decoder so memory stays flat regardless of file size. Measured: a 400 MiB
   XML peaks at **821 MiB** via `read_text()` and **28 MiB** via `iter_chunks()`.
2. **Never write over the original.** Repaired output always goes to a NEW
   path; `write_repaired()` and `repair_pdf()` both raise rather than overwrite
   their input, because the original bytes are the custody anchor (H1).
3. **Never repair silently.** Every fix is a `RepairEvent` carrying a severity.
   `lossy` means evidence could have been lost; gate on it.
4. **Never import a repair library at module scope.** See below.

## Damaged-file lifecycle (`quarantine.py`)

Owner directive 2026-08-02: *"Write a new repaired file and quarantine the
damaged file. Or at the very least flag it as damaged so that it doesn't
continue being parsed out."* Three escalating actions, safest default first:

| Action | Touches disk | Use |
|---|---|---|
| `flag_damaged()` | ledger only | **default.** Ingest calls `DamageLedger.should_skip()` and stops re-parsing a known-bad file every run |
| `write_repaired()` | writes a NEW file | streaming rewrite to a clean, re-parsable file |
| `quarantine_file()` | verified copy + ledger | opt-in, `dry_run=True` by default, manifest via `plan_quarantine()` first; original remains owner-controlled |

Quarantine is not the default because two standing rules constrain it: never
delete, and a full manifest precedes any copy job with approval explicit rather
than inferred. The verified copy is additive; the original remains in place
and the SHA-keyed ledger prevents re-ingestion until the owner decides its
final disposition.

The ledger is **keyed by sha256**, not path: paths move, content does not, so a
flagged artifact stays flagged across a reorganisation. It is append-only —
later entries supersede earlier ones on read, and history is never rewritten.
Default location `docs/reports/damaged-artifacts.jsonl` (gitignored; filenames
can carry PII).

## Severity taxonomy (the point of `types.py`)

| Severity | Meaning | Example |
|---|---|---|
| `cosmetic` | nothing informational changed | BOM stripped |
| `structural` | shape fixed, content preserved | tag auto-closed, ragged row padded |
| `lossy` | bytes discarded or reconstructed | control char removed, OCR output, repaired PDF |

Only `lossy` can cost evidence. A silent repair is indistinguishable from the
parser bug that dropped 516 body-less MMS: nothing raises, the counts just come
out smaller.

## Format → engine

| Format | Engine | Chunk | Notes |
|---|---|---|---|
| `xml` | lxml `recover=True` + `iterparse` | element subtree | recovers **while streaming** |
| `html` | lxml HTML parser | element subtree | recovering by design |
| `json` | ijson → json-repair fallback | array item | fallback capped at `JSON_REPAIR_MAX_BYTES` |
| `ndjson` | per-line | object | one bad line costs one line |
| `csv` | CleverCSV dialect + ragged repair | row | **never truncates**; extras go to `__overflow__` |
| `pdf` | `extract.text` tiered | page | see the PDF split below |
| `image` | Tesseract OCR | page | always lossy |

## ⚠ Function-local imports are mandatory

`registry.load_builtin_tools()` walks `server/tools/` **recursively** and
imports every module whose final path segment does not start with `_`. That
walk also runs inside the dep-light `deploy/docker/tool-runtime` facade, which includes the
whole `server/` tree but installs almost none of its dependencies.

A module-level `import lxml` anywhere here would FATAL-loop the facade — the
same failure mode `../AGENTS.md` warns about for `server.contracts`, and which
the ADR-0033-era outage already paid for once.

So `available()` probes with `find_spec` (no execution) and `engine_for()`
returns `None` when a library is missing, turning "dependency absent" into a
routed, reportable state instead of a crash.

## ⚠ XML/HTML element lifetime

The yielded Element is valid **until the next iteration** — it is cleared and
unlinked as soon as the consumer asks for the next one. That is what keeps
memory flat. `list(iter_xml(...))` returns a list of *emptied* elements.

Copy what you need inside the loop (`dict(elem.attrib)`), or pass
`materialize=True` and accept the memory cost.

## PDF: repair and extraction are different problems

- **`pdf.py` — repair.** The file does not open: damaged cross-reference table,
  missing trailer, truncated tail. QPDF rebuilds the xref by scanning for
  object markers. Nothing can extract until this succeeds.
- **`../extractors/extract_text.py` — extraction.** The file already opens;
  pull text out of it (native pypdf/pdfplumber → Tesseract OCR).

`inspect_pdf()` is read-only triage returning `healthy` / `reconstructed` /
`encrypted` / `unrecoverable`. **`reconstructed` is the dangerous status**: the
file opens fine in any reader, so it looks healthy while actually being damaged
— only `Pdf.get_warnings()` reveals it.

Two traps already paid for here:
- qpdf recovery is **not** on the `pikepdf` logger and **not** in Python's
  `warnings`. Both were tried and captured nothing. `Pdf.get_warnings()`, read
  *inside* the `with` block, is the only reliable source.
- Status must key on **any** warning, not a keyword allowlist. Gating on
  reconstruction keywords reported a file that made qpdf say "can't find PDF
  header" as `healthy`.

## Usage

```python
from server.tools.repair import detect, iter_chunks, RepairReport

report = RepairReport()
for chunk in iter_chunks(path, report=report):
    if chunk.ok:
        handle(chunk.node)
report.summary()  # funnel counters for the ingest ledger
```

```python
from server.tools.repair import inspect_pdf, repair_pdf

health = inspect_pdf(path)  # read-only
if health.needs_repair:
    result = repair_pdf(path, dest)  # NEW file, never in place
    result.provenance()  # -> custody ledger row
```

## Scripts

- `scripts/repair_smoke.py` — routing on real files, damage recovery, and a
  streaming proof that measures peak working set in child processes.
- `scripts/pdf_triage.py` — sweep a tree, classify every PDF, optionally repair
  the damaged ones into a separate output tree.

## How to add an engine

1. Write the iterator in `chunkers.py`, yielding `Chunk` objects. Third-party
   imports go **inside** the function.
2. Add an `EngineSpec` to `ENGINES` in `engines.py`. Use `requires` for
   all-of dependencies, `any_of` when one of several will do.
3. Add the signature to `detect.py` (`_BINARY_SIGS` or `_classify`).
4. That is all — `iter_chunks()` routes by format automatically.

## ATOMICITY — every unit must be assignable to a Temporal Activity

> _Owner directive · 2026-09-02. Binding on every directory below this file.
> Reinforces the 2026-08-25 boundary ruling, ADR-0061, and D-077._

**Write every unit of work so it can be handed to one Temporal Activity, and never
conflate multiple processes into one unit.**

Owner, 2026-09-02: *"Everything needs to be modular so that it can be assigned to
Temporal activities. We can't be conflating or mixing a bunch of processes into one.
Yes, the engine can call individual ones, but it's going to be calling the Activity
more likely than 99.9% of the time."* And: *"Or to be added into an n8n node which
gets run as an activity, however that shape looks."*

Rules, in force everywhere:

1. **One unit does one thing.** A parser parses and does nothing else (owner,
   2026-08-29: *"they parse, they do nothing more"*). A chunker chunks. A hasher
   hashes. If a function does two of those, it is wrong and must be split before it
   is wired to anything.
2. **Hashing is its own Activity family and is never folded into parsing, chunking,
   or normalization.** Custody hashing is separate machinery with its own boundary
   (D-077, four hash moments; see `docs/reference/HASH-TAXONOMY-2026-08-29.md`).
3. **The Activity is the normal caller.** Direct in-process calls stay legitimate —
   but the overwhelmingly common path is invocation *as*, or from *within*, a
   Temporal Activity. Design signatures for that: bounded inputs, bounded outputs,
   no ambient state, no hidden I/O, deterministic given its inputs, safely
   retryable. An Activity may be retried; anything that breaks on a second identical
   call is a defect.
4. **Three call shapes, one unit.** The same unit must serve all of them without
   knowing which is in play: (a) called directly in-process; (b) invoked as a
   Temporal Activity; (c) **wrapped as an n8n node that is itself executed as, or
   from within, an Activity.** n8n owns the visual flow, Temporal owns durability,
   the unit owns one job. A unit that needs to know its caller has a boundary
   violation in it.
5. **Pass references, never payloads.** Source bytes and bundles move by locator
   (`upload://`, `r2://`, sealed `file://`), never through Temporal history, an n8n
   payload, or a PostgreSQL activity request.
6. **No orchestration inside a unit.** Sequencing, fan-out, retries, and human gates
   belong to the workflow (`modules/engine/proffer` (formerly `uiw`, renamed D-140)) and to n8n's visual flow — never
   buried inside a parser, decoder, chunker, or repository method.
7. **New capability = new Activity, registered in the stage graph.** Do not widen an
   existing Activity to cover a second concern because it is convenient.

The test before adding or editing anything here: *could this be scheduled on its own,
retried, wrapped as an n8n node, and reasoned about in isolation?* If not, it is not
finished.
