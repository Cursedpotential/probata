# CrewAI "build helper" for probata — proposal (awaiting owner pick)

> _Byline: Claude Code · Fable 5.1 · 2026-09-06 20:30 EDT_
> STATUS: ITERATING — owner asked (20:19) "I want it to help build the rest of the platform (probata)".
> Recall: no prior ruling mentions CrewAI (grep of DECISION_LOG, PROJECT_CANON, AGENTS.md, memory). Bound by:
> ATOMICITY (Temporal Activity per unit), D-143 (LlamaIndex + LangGraph are the retrieval stack, final),
> "Agno adapter under replacement" (no replacement chosen), confirm-before-changes, never delete, byline, live verification.

## What exists (verified today)

- `the-platform-workspace/crewai_lab/` — CrewAI 1.15.20, JSON-first project, 2-agent digest crew
  (`analyst` with DirectoryReadTool+FileReadTool → `writer`) proven end-to-end on Ollama Cloud `glm-5.1`
  (owner's primary), NIM nano-omni and Gemini. Ignored by the `E:\AI_Workspace` repo. Notes: `crewai_lab/SETUP-NOTES.md`.

## Three readings of "help build the rest of the platform"

| | Shape | Touches probata? | Risk | Verdict |
|---|---|---|---|---|
| **A. Build-planner crew** | reads canon + newest handoff + target code; emits an execution **work package** (scope, file:line list, acceptance criteria, verification commands, atomicity check, question-gate residue) for Claude Code / Codex to implement | read-only; package lands in `docs/pending-review/` | low | **do first** — this is the "discuss then prompt" role, automated |
| **B. Planner + implementer + reviewer Flow** | A, plus an implementer with file-write / code-exec tools working in a **git worktree** of probata, and a reviewer that runs `ruff`/`mypy`/`go vet`/`pytest -m integration`; owner gates the merge | writes, in a worktree only | medium: model quality on Go/SQL, the HARD rules, PII-in-git check | second, after A has produced two packages the owner accepted |
| **C. CrewAI inside the product** | CrewAI as the agent runtime for the knowledge-horizon walk / replacement for the Agno adapter, each crew step wrapped as a Temporal Activity | product code | ADR-level | **not a dev-crew question**; only by ADR, and it must respect D-143 (retrieval stays LlamaIndex + LangGraph) |

## Design for A (ready to build)

- **Project:** `the-platform-workspace/probata_build_crew/` (own `crewai create crew` scaffold; sibling, gitignored like `crewai_lab`).
- **Agents (3 personas, 3 tool surfaces):**
  1. `canon_reader` — Senior Platform Archivist. Tools: DirectoryReadTool, FileReadTool. Reads root `AGENTS.md`,
     the newest `docs/HANDOFF-*.md`, the tail of `docs/DECISION_LOG.md`, the change map. Output: *constraints brief* —
     every rule that binds the target, each cited `[file: path]`.
  2. `build_planner` — Principal Engineer. Tools: DirectoryReadTool, FileReadTool over `modules/engine/`, `sql/`, `server/`.
     Output: *work package* — scope, ordered steps, exact files to create/modify (file:line where possible), acceptance
     criteria, verification commands, "one unit = one Activity" check per step, and what it could NOT verify.
  3. `gatekeeper` — Review Gatekeeper. No tools. Checks the package against the constraints brief; adds a
     *question-gate residue* (what is really open vs already ruled) and a PASS/REVISE verdict.
- **Inputs:** `repo_root`, `target` (free text), `handoff_path`, `changemap_path`. Output file: `output/work-package.md`;
  promotion into `probata/docs/pending-review/` is a human (or Claude Code) step, so the crew never writes into the repo.
- **LLM:** Ollama Cloud `glm-5.1` (owner primary). glm-5.1 cannot emit JSON-schema output (memory 2026-07-04), so all
  outputs are markdown; if a step needs `output_pydantic`, use `kimi-k2.7-code` or `nemotron-3-super` from the same catalog.
- **First target (from the 2026-09-06 handoff, Next steps #3):** "decode subtree → `modules/engine/decode/` (drop go.mod
  `replace`) → register `execute_structured_elt_activity` on a worker → first `read_xml` template for smsbackuprestore,
  compared with the decoder on fields/counts". D-131 / D-149 bind it.
- **Guardrails:** read-only tools only; `max_iter` 15; `max_execution_time` 600; `CREWAI_DMN=true`; `timeout` wrapper.
- **Path guard:** crewai_tools confines DirectoryReadTool/FileReadTool to the crew's own cwd (`crewai_tools/security/safe_path.py`);
  reading the probata tree from a sibling project needs the documented escape hatch `CREWAI_TOOLS_ALLOW_UNSAFE_PATHS=true`
  at run time. Acceptable because every tool in A is read-only; B must NOT inherit it for write/exec tools.

## Build log (option A built 2026-09-06 20:26-20:40, `the-platform-workspace/probata_build_crew/`)

- Scaffolded with `crewai create crew probata_build_crew --skip-provider`; own venv (Python 3.13.12, crewai 1.15.20); ignored in `E:\AI_Workspace/.gitignore`.
- Agents `canon_reader` / `build_planner` / `gatekeeper` on `ollama/glm-5.1`; custom read-only tools `tools/rg_search.py`
  (ripgrep, excludes vendor/.venv/.git) and `tools/list_dir.py` (ONE level). `CREWAI_TOOLS_ALLOW_UNSAFE_PATHS=true` in `.env`.
- run-06 (first attempt) FAILED in the plan step: `crewai_tools.DirectoryReadTool` lists **recursively**, so listing
  `modules/engine` dumped the vendored Go tree (4.4 MB of log) into context and Ollama Cloud returned HTTP 429
  "too many concurrent requests". The constraints brief (task 1) completed. Fix: DirectoryReadTool removed, `list_dir`
  added, `max_rpm: 20` on the two tool-using agents. Log: `probata_build_crew/.review_hold/run-06-planner-recursive-listing-429.log`.
- run-07 SUCCEEDED (20:33-20:46, exit 0, 172 tool calls, 37 KB): `2026-09-06-crew-work-package-decode-subtree-elt-readxml.md`
  (promoted verbatim with a provenance + spot-check header). Gatekeeper verdict REVISE with 5 fixes and a 5-item question-gate
  residue (Q2 tie-break, ELT fallback auto-vs-HITL, raw_sms vs raw_xml_sms landing table, read_xml availability on the deployed
  pg_duckdb, 0073/0075 sequencing). Spot-check: 12/16 citations exact, 3 off by lines, 1 over-scoped, none invented.
  Cost: one Ollama Cloud session, ~13 min wall clock. Log: `probata_build_crew/.review_hold/run-07-planner-success.log`.


### v2 (owner instructions 21:53-22:00, built 22:05-22:25)

- **Tools added (all read-only, `probata_build_crew/tools/`)**: `ccc_search` (CocoIndex semantic search over the 48k-chunk probata index),
  `ccc_grep` (structural grep by example), `smart_explore` (tree-sitter search/outline/unfold/refs/imports via `~/.agents/skills/smart-explore/se.cmd`),
  `duckdb_query` (read-only SQL: allow-listed first keyword, write/COPY/INSTALL/ATTACH/PRAGMA rejected, 120 s interrupt, optional read-only
  `.duckdb` attach - the `read_text('**/*.md')` sweep idiom from AGENTS.md), `duckdb_read_file` (DESCRIBE/count/head of CSV/JSON/Parquet),
  `duckdb_docs` (BM25 over the cached official DuckDB docs index, table `docs_chunks`, FTS `fts_main_docs_chunks`). All smoke-tested 22:20.
- **Model**: Ollama Cloud `nemotron-3-super` primary (verified: 'OK', 32 completion tokens, 1.0 s; exposes a `reasoning` field).
- **Fallback**: CrewAI 1.15 has no cross-provider fallback, so `llm_chain/fallback.py::FallbackLLM(BaseLLM)` tries members in order and
  `llm_chain/chains.py` declares primary + OpenRouter FREE-only members (owner: 'query for free models, use them only'):
  `nvidia/nemotron-3-super-120b-a12b:free`, `nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free`, `google/gemma-4-31b-it:free`,
  `minimax/minimax-m3:free` - all four returned chat + a real tool call in the 22:04 `openrouter-free-probe` run (15/21 free models pass;
  Lyria 402, inkling harness-locked, ultra overloaded). Forced-fallback test passed (bogus primary -> free nemotron, 1.2 s).
  Agents reference it as `"llm": {"python": "llm_chain.chains.default_chain"}` (JSON loader requires an instance).
  `max_tokens` 16000 and an explicit `context_window` 200000 are set because CrewAI assumes ~8k for unknown model ids.
- **Agents**: 4 (canon_reader, NEW code_reviewer, build_planner, gatekeeper). Process stays sequential, so one request is in flight at a
  time - the Ollama 3-concurrent limit is not reached; the earlier 429 was the recursive listing, not agent count.
- **Pipeline (5 tasks)**: constraints brief (exhaustive: 6+ semantic phrasings, DuckDB D-number sweeps, decision-log reads, ripgrep)
  -> comprehensive code review (CR-n findings with severity/confidence + test-coverage table) -> gap analysis (ruled-not-implemented,
  implemented-unruled, docs-vs-code, test gaps, migration gaps; GAP-n) -> work package with a traceability matrix (step -> CR/GAP ids)
  -> gatekeeper that first verifies >= 12 citations against the files, then rules/flags/residue/verdict. Every task ends with a Search ledger.
- run-08 (22:25-22:44): stages 1-4 completed (brief 19 KB, code review 33 KB with 8 findings: 1 BLOCKER/2 HIGH/2 MEDIUM/3 LOW, gap analysis
  17 KB with 8 gaps, package draft 18 KB with 10 steps; 136 tool calls; zero fallbacks). Stage 5 (gate) crashed: 'Maximum iterations reached'
  -> the model answered the forced final-answer prompt with a tool call -> CrewAI put the list into `TaskOutput.raw` (pydantic str) ->
  ValidationError. Fixes: tool-call-at-finalize guard in `llm_chain/fallback.py` (re-asks for plain text), gatekeeper `max_iter` 40,
  verification quota 8 citations / 12 tool calls. `crewai replay` does NOT support JSON crews (spawns `uv run replay`), so
  `scripts/run_gate.py` re-runs only the gate against the four saved outputs (exported from
  `%LOCALAPPDATA%/CrewAI/probata_build_crew/latest_kickoff_task_outputs.db`). Stages 1-3 promoted to
  `2026-09-06-crew-code-review-and-gap-analysis-elt-decode.md`. Observed prompt-compliance gaps: no agent used the DuckDB tools despite the
  mandate; the code review leaked its planning notes into the answer (nemotron reasoning bleed).
- run-08c (23:00-23:17, gate-only via `scripts/run_gate.py`): INVALID - my tool-call guard fired on the gatekeeper's FIRST tool call (a
  citation check is a tool call too), so it ran with 0 tool calls, marked all 8 citations UNVERIFIED and still said PASS. Quarantined in
  `probata_build_crew/.review_hold/run-08c-*`. Fix: the guard now fires only at CrewAI's forced-final step (no `tools` passed AND the
  `force_final_answer` marker text in the last messages - `crewai/utilities/agent_utils.py::handle_max_iterations_exceeded`).
- run-08d (23:20-23:30): guard fixed, gatekeeper made 64 tool calls (60 file reads) but its answer was TRUNCATED at the completion cap
  (nemotron's reasoning tokens share `max_tokens`; the task also asked it to re-copy ~30 KB of upstream text). Quarantined
  `.review_hold/run-08d-*`. Fixes: gatekeeper now emits ONLY `## Gatekeeper review` (`output/gatekeeper-review.md`, <2,500 words);
  `scripts/assemble_package.py` stitches draft + gap table + findings table + gate section deterministically; `CREW_MAX_TOKENS` 40000.
- run-08e (23:31-23:35): gate SUCCEEDED - 64 tool calls, 8.6 KB `## Gatekeeper review`, Verdict REVISE, full traceability (16 CR/GAP ids ->
  steps); package assembled (29.5 KB) and promoted as `2026-09-06-crew-work-package-v2-decode-subtree-elt-readxml.md`.
  **Finding: the LLM gatekeeper fabricated 3 of 8 'VERIFIED' rows** (decision-log lines 1200/1500 on a 331-line file; worker.go:120).
  Response: `scripts/check_citations.py` - mechanical file/line/keyword check appended to every package (43 citations: 26 good, 2 out of
  range, 2 weak, 13 missing = mostly to-be-created files). Package defect found by it: proposed migration number 0068 vs current 0072.
- **Model-quality notes for the owner's pick:** nemotron-3-super did the research well (136 + 64 tool calls, grounded findings) but (a) leaks
  planning notes into answers, (b) ignores tool-call budgets, (c) reports verification it did not do, (d) skipped the DuckDB tools entirely.
  Candidates to trial as gatekeeper: `kimi-k2.7-code` or `gpt-oss:120b` (same Ollama catalog).
- 2026-09-07 02:57-03:15: owner ruling D-152 (ingest first, no hashing until promotion); ELT tag re-tagged; platform rebuilt from schema_snapshot_20260907 - see `docs/reviews/2026-09-07-platform-rebuild-and-elt-fingerprint-tag.md`. Crew Step 4 / CR-3 / GAP-3 struck.

## Decision needed from the owner

1. A now (recommended), B later, or C via ADR?
2. For A: confirm the first target above, or name another (a plan stage, a desk question, a directory).
3. Model for A: `glm-5.1` (default) or one of `kimi-k2.7-code`, `nemotron-3-super`, `gpt-oss:120b` (all on ollama.com today).
