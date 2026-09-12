# CONVENTIONS — the one style

> **Authoritative for:** how we write code. Entry point: `docs/PROJECT_CANON.md` (§0).
> The *decision* behind the discipline is **ADR-0021**; this doc is the concrete *how*.
> Last updated: 2026-08-09 (added the ADR-NNNN/D-NNN citation convention, mechanically checked by
> `scripts/validate.sh`; prior: 2026-07-29, agno version ref synced to 2.8.0). One language style,
> one tool contract, one data shape — no exceptions without an ADR.
> _Byline: OWL · openrouter/owl-alpha · 2026-06-14 · updated 2026-07-29 (Claude Code · Fable 5);
> updated 2026-08-09 (Claude Code · Sonnet 5);
> drift-fix 2026-08-12 (Claude Code · Kimi K3: pin reference 2.8.0 → 2.8.7 per requirements.txt:3)_
> _Byline amendment: Claude Code · Fable 5.1 · 2026-09-05 — naming canon sweep D-137..D-141; see `docs/NAMING.md`. The `Agno-MCP-Platform-alpha/chatminer` provenance path in the example below is a literal filesystem path and is unchanged._

## Artifact byline — provenance on EVERYTHING (required)

Everyvery document and every code file we create or edit carries a **byline: `tool/platform · model · date`** —
because this is a multi-tool workflow (Claude Code, OpenCode, Codex, Gemini/Antigravity, Hermes, human) and we
must know which agent on which model produced each artifact.

- **Markdown docs:** a line directly under the title block — `> _Byline: <tool> · <model> · <YYYY-MM-DD>_`.
  On a later substantive edit by a different tool/model, append lineage: `· updated <date> (<tool> · <model>)`.
- **Code files:** a top-of-file comment — `# Byline: <tool> · <model> · <YYYY-MM-DD>` (Python) /
  `// Byline: <tool> · <model> · <date>` (TS). Vendored/ported files ALSO keep a `provenance:` note
  pointing at the donor source (see the `@register(... provenance=...)` field).
- **Vocabulary:** `tool` ∈ {Claude Code, OpenCode, Codex, Gemini, Antigravity, Hermes, human}; `model` = the
  actual model id in use (e.g. `Opus 4.8`, `gpt-5-codex`, `gemini-3-pro`, `glm-5.1`).

## Cross-tool compatibility (Claude Code / Codex / Hermes / Gemini all consume this)

The SSOT is **plain markdown + the `AGENTS.md` standard** — deliberately tool-agnostic:
- **Claude Code** reads `CLAUDE.md` (symlink → `AGENTS.md`).
- **Hermes** reads `AGENTS.md` natively.
- **OpenCode** and **Codex** read `AGENTS.md` natively.
- Any other agent (Gemini/Antigravity, a custom Agno agent) is onboarded by pointing it at `docs/PROJECT_CANON.md` → which routes to the 5 authoritative docs. No Claude-specific syntax in the canon/plan/structure/inventory.
- Agno agents inside the platform consume the same docs via the knowledge engine (`platform_design` domain) once Phase B ingests them.
- **Rule:** keep the 5 authoritative docs free of tool-specific directives. Tool-specific setup (hooks, slash-commands) lives in that tool's own config, never in the SSOT.

## Progressive Disclosure (context management)

Every directory has a `README.md` that serves as a table of contents. The entry-point
file (`AGENTS.md`) contains only universal context + a navigation index. Details
live one level deeper in each directory's `README.md`, and further in each file's
docstring. This prevents context rot in LLM-based agents.

**Pattern:**
1. `AGENTS.md` — universal context + directory index (this file is the entry point).
2. `<directory>/README.md` — table of contents for that directory (what lives there, when to read it).
3. File-level docstrings — authoritative documentation for that specific file.
4. Inline comments — explain *why*, not *what* (the code shows what).

**Rules:**
- `AGENTS.md` stays under ~100 lines. If it grows, move detail into directory READMEs.
- Every directory with 2+ `.py` files gets a `README.md`.
- Docstrings are the **authoritative** docs — when docstring and external doc conflict, fix the doc.
- Use Google or Numpy style docstrings (both Claude Code and Hermes parse them reliably).

## Working rules (apply to every change)

- **No silent stubs (ADR-0021).** Unavoidable stub → grep-able `# STUB: <tag>` in code **and** a row in `docs/DEBT.md`. `grep -rn "# STUB:"` must match the register exactly. Prefer *removing* an unfinished tool over shipping a silent `NotImplementedError`.
- **Doc-debt flagging — circle back, don't block (ADR-0022).** As you code, flag anything needing documentation with a grep-able **`# DOC: <what>`** (Python) / **`// DOC: <what>`** (TS) AND a row in **`docs/DOC_DEBT.md`**. `grep -rn "# DOC:"` ↔ `docs/DOC_DEBT.md`. Standing goal (feeds the living wiki, ADR-0022): **every function, plugin, app, tool, and 3rd-party library** documented **human-readable AND LLM-readable**. Do NOT write full docs inline mid-build — flag + register, circle back in a docs pass.
- **Harness-first tests.** `pytest` + `python -m evals` must run green; write paths (custody/HITL/normalize) aren't trusted until governance/boundary evals pass.
- **Verify Agno against the pinned wheel/image** via the agno skill + agno docs MCP — never from memory. (Current: agno **2.8.7** ~~2.8.0~~ — corrected 2026-08-12 per `requirements.txt:3`.)
- **HITL is first-class.** Every write (ingestion/normalize/evidence/config/db) pauses for recorded approval (native `@approval` + `requires_confirmation`; ADR-0002).
- **Owner-comms:** the owner does **not** code. Explain schemas/format/functions in **plain English**, no code dumps, when discussing design.
- **One canonical data shape:** everything a tool emits normalizes to **`NormalizedRecord`** (`occurred_at` / `knowledge_time` / `disclosure_tier` / `attrs`). Don't invent parallel record types.

## Core coding principles

- **DRY** — every piece of logic in exactly one place. Copy-paste → extract.
- **KISS** — simplest solution that solves the problem. No over-engineering.
- **YAGNI** — don't build features or abstractions you don't need yet.
- **SOLID** — single responsibility, open/closed, Liskov substitution, interface segregation, dependency inversion.
- **Separation of Concerns** — each module/function/class handles one distinct aspect.

## Python style

- Target **3.12**; `from __future__ import annotations`; **type hints required on every function**.
- **pydantic** for schemas/records (e.g. `NormalizedRecord`); `@dataclass` ok for simple value types.
- Formatting via `./scripts/format.sh` (ruff). `snake_case` modules and functions, `PascalCase` classes.
- **Lazy imports** for packages light consumers shouldn't pull (PEP 562 `__getattr__`, as in `server/evidence/__init__.py`) so the tools-facade container stays slim.
- Module starts with a purpose docstring (what it owns, what writes where).
- **Descriptive names** — `build_ingestion_orchestrator`, not `build_io`. Clear whitespace between logical sections.
- **Comments explain why**, not what. The code shows what.

## TypeScript style (donor tools wrapped as MCP services)

- Strict TS; **zod** for input schemas; tools expose MCP specs with `name` = `namespace.verb` (e.g. `evidence.hash_file`), a `description`, and an `inputSchema`.
- Keep the donor file header convention: `// File: <path> | Date: <d> | Agent: <who> | Model: <m>`.
- Don't port TS→Python wholesale; wrap behind Agno (REPO_STRUCTURE placement rules).

## SQL / schema

> **2026-09-07 (owner, D-153):** there are no migrations. `sql/bootstrap/schema_snapshot_<date>.sql` is the database; change it in its final form and rebuild (`scripts/rebuild_platform_from_snapshot.sh`). Reference/state tables survive every rebuild (keep set). The rule below is struck.

- ~~Numbered, append-only: `sql/NNNN_name.sql`. Never edit an applied migration — add a new one.~~ (struck 2026-09-07, D-153; see note above)
- `evidence` schema is read-only except via `custody.py`; derived data lands in `analysis`.

## Citation convention (added 2026-08-09)

Code and docs cite decisions by ID, not by re-explaining them inline:

- **`ADR-NNNN`** (4 digits, e.g. `ADR-0035`) — cite for an **architecture** decision: a design,
  dependency, data-boundary, or security/HITL guarantee locked in `docs/adr/`.
- **`D-NNN`** (3 digits, e.g. `D-008`) — cite for an **owner ruling** recorded in
  `docs/DECISION_LOG.md` (a specific decision entry, not necessarily architecturally significant
  enough for its own ADR).
- Both forms are **mechanically checked**: `scripts/validate.sh` greps `server/`, `sql/`, and
  `docs/` for every `ADR-\d{4}` / `D-\d{3}` reference and confirms it resolves to a real ADR file
  / DECISION_LOG entry. A citation that doesn't resolve fails validation — don't invent an id, and
  don't renumber an existing one out from under a citation.
- This is a **going-forward convention, not a retroactive annotation pass** — existing code is not
  swept to add citations it lacks (see `docs/DEBT.md`'s traceability register for that scope, if
  one exists; no blanket pass is authorized here).

## Commit discipline

- A locked decision updates **`PROJECT_CANON.md` §5 in the same change** (anti-drift rule).
- New decisions also get an ADR (`docs/adr/`, supersede don't edit).

## The atomic-tool contract (the heart of the architecture)

Every tool — Python in-process or polyglot — satisfies one capability under the registry contract (`server/tools/registry.py`):

```python
# server/tools/parsers/<domain>/<format>.py — ONE capability per file, self-registering.
# (domain ∈ {messaging, ai_chat, generic}; extractors live in server/tools/extractors/ — ADR-0035.)
from __future__ import annotations
from server.tools.registry import register

@register(
    id="transcripts.chatgpt-official",    # unique, dotted, stable (UI/tests depend on it)
    capability="parse.transcript",         # capability-based resolution; same capability = swappable
    description="ChatGPT official JSON export → NormalizedRecords",
    accept=lambda media_hint, size: media_hint.endswith(".json"),
    provenance="vendored: Agno-MCP-Platform-alpha/chatminer/parsers/chatgpt_official.py",
)
def run(payload: dict) -> dict:
    ...  # payload in → payload out
```

- **Capability resolution:** workflows resolve by `capability`, not function name. First registered = preferred; the rest are **substitution candidates** an agent can swap in on failure.
- **Auto-discovery:** `load_builtin_tools()` recursively imports every non-`_` module under `server/tools/` (`parsers/`, `extractors/`) via `pkgutil.walk_packages` (ADR-0035). Underscore-prefixed modules = shared helpers, never tools; the `gateway/` sub-package is excluded (it's a registry consumer, not a tool).
- **Polyglot:** TS/Go/HTTP/MCP tools register with a runner (shell-out / HTTP) under the same contract — same `id`/`capability`/`accepts`/`run`, different transport.
- **Universal exposure — API-first + MCP-wrapped (canon §5):** EVERY tool, agent, AND workflow gets (1) an **internal API** (FastAPI/HTTP) for in-platform callers and (2) an **MCP wrapper over that API** for external/any-surface callers (federated by IBM ContextForge). Everything is **atomically callable**; tools also **compose into workflows** (which may hold a variable tool slot); workflows get the same API+MCP. **Everything gets an API; every API gets an MCP.**
- **Tool exposure pattern (owner, 2026-06-13):** heavy, long-running, or non-Python tools are wrapped as **FastAPI (or similar) HTTP services** — the existing `tool-runtime` facade pattern — then registered via the registry's HTTP runner and/or federated through **IBM ContextForge**. Lightweight Python tools stay in-process via `@register` but still expose the API+MCP per the universal rule. Either way the *contract* (capability + `NormalizedRecord`/payload I/O) is identical.

## Root-layout reconciliation (2026-08-24, owner order)

- **`tests/`** = the pytest suite (code correctness). **`evals/`** = the standalone LLM-eval
  harness (`python -m evals`; model/prompt quality — NOT pytest). **`build/`** = generated
  packaging outputs ONLY (gitignored). ~~today that means `build/test-reports/` (pytest
  durable reports)~~ **Amended 2026-09-01 (owner consolidation ruling):** pytest durable
  reports now live at **`tests/_reports/`** (gitignored) so test source and test results
  share one parent; `build/` no longer holds test reports.
  Point-in-time attestation/inventory snapshots do NOT live in build/ — they were moved to
  `_stale/build-snapshots-20260824/` (never-delete).
- Root loose files quarantined to `_stale/root-tidy-20260824/` (scratch inspect script, an
  Aug-5 scripts/ backup zip). The stray root `iceberg` DuckDB database moved to
  `.duckdb/iceberg.duckdb` (local, gitignored — the .duckdb/ convention).
- **`docs/private/`** — gitignored; real-name / case-fact working files live here, never
  committed, never redacted (owner ruling 2026-09-06; Claude Code · Sonnet).
