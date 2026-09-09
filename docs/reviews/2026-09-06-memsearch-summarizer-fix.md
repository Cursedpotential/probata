# memsearch: summarizer fix (Nemotron 3.5 Lightning, thinking off) and stub repair

> _Byline: Claude Code · Fable 5.1 · 2026-09-06_

**Scope:** summarization / memory capture only. The search-side rebuild (stale 4096-dim `ms_*` collections renamed to `stale_*`, `ms_matts_f436780d` recreated at 2048-dim) was done by a parallel session on the same day and is NOT covered here.

## Symptom

- Stop-hook journal entries in `~/.memsearch/memory/2026-09-06.md` (8) and `2026-09-02.md` (1) were stubs: `- Memory summary unavailable: summarizer timed out; transcript content was omitted.`
- `~/.memsearch/.maintenance-state.json`: `claude-code.project_review` failing with `InternalServerError: Error code: 504` since 2026-09-03.

## Root cause (verified live)

| Probe | Result |
|---|---|
| `mistralai/mistral-nemotron` chat on NIM, 60 s timeout | HTTP 000 (no response) |
| Retired model on the same endpoint | HTTP 410 in 0.2 s (endpoint + network fine) |

The configured summarizer model (`[llm.providers.nemotron] model`, `~/.memsearch/config.toml`) hangs; the Stop hook kills it at 110 s and writes the stub.

## Model selection (owner: "use nemo 3.5 lightning or 3 nano")

| Model | Result |
|---|---|
| `nvidia/nemotron-nano-3-30b-a3b` | HTTP 404 on this account |
| `nvidia/llama-3.1-nemotron-70b-instruct` | HTTP 404 on this account |
| `nvidia/nemotron-3.5-lightning-30b-a3b`, default | thinks by default: 69 s / 2208 reasoning chars for a toy prompt; 300-token budget filled with reasoning, reasoning leaked into `content` |
| same, `chat_template_kwargs.enable_thinking=false` | 5.5 s, 38 tokens, clean bullets |
| same, prompt-level `/no_think`, `detailed thinking off`, `Reasoning: off` | all ignored (still thinks) |
| same, tools + thinking off | tool call returned in 1.4 s (maintenance path OK) |

## Constraint

memsearch 0.4.19 (`compact.py::_compact_openai`, `maintenance.py::_run_openai_with_tools`) calls `chat.completions.create(model, messages)` with no `extra_body`; `LLMProviderConfig` has only `type/model/base_url/api_key`. The LiteLLM gateway (`100.72.169.40:4000`) is unreachable and marked "being retired, do not fix" in `PLATFORM_REFERENCE.md`; Portkey needs headers memsearch cannot send.

## Fix

1. **Config:** `~/.memsearch/config.toml` line 28 → `model = "nvidia/nemotron-3.5-lightning-30b-a3b"`; re-pinned `~/.memsearch/_pinned/config.toml.pinned`. Same provider block serves `summarize`, `project_review`, `user_profile`.
2. **Shim (minimal custom code, ~60 lines):** `~/.claude/hooks/memsearch_nim_nothink/{memsearch_nim_nothink.py,.pth,install.sh}` installed into the memsearch uv-tool venv site-packages. Lazy meta-path hook; wraps `Completions.create`/`AsyncCompletions.create` to inject `extra_body.chat_template_kwargs.enable_thinking=False` for models starting `nvidia/nemotron-3`. Opt out `MEMSEARCH_NIM_THINKING=1`; debug `MEMSEARCH_NIM_NOTHINK_DEBUG=1`. No `openai` import at interpreter start (checked: `openai` absent from `sys.modules`).
3. **Self-heal:** `~/.claude/hooks/memsearch_provider_guard.py` (SessionStart) now re-copies the shim if a `uv tool install --force/--reinstall` dropped it.
4. **Stub repair:** scratch script re-derived each stub's turn from its transcript anchor (`memsearch transcript PATH -j`, user message through next user message), re-summarized, and replaced only the stub line under the anchor, with a `<!-- re-summarized ... -->` marker. Backups: `~/.memsearch/_backup/*.pre-resummarize-20260906-163124.md`.

## Failed approach worth recording

First shim install silently did nothing: the "already patched" guard used `hasattr(create, "__wrapped__")`, but the openai SDK decorates `create` with `functools.wraps`, so the original already carries `__wrapped__`. End-to-end run timed out at 110 s with no debug output. Fixed with a private marker attribute `_memsearch_nim_nothink`.

## Verification (end-to-end, the exact Stop-hook command)

```
MEMSEARCH_NO_WATCH=1 timeout 110 memsearch summarize --plugin claude-code --agent-name "Claude Code" < transcript
exit=0  elapsed=22.2s  8 bullets, 0 non-bullet lines, no reasoning leak; stderr shows "injected chat_template_kwargs.enable_thinking=False"
```

Stub repair: 9/9 repaired (one needed a second attempt after a non-bullet line); `grep -c "Memory summary unavailable"` → 0 in both files.

## Still open

- The first in-the-wild proof is the next Stop hook appending a real summary to `2026-09-06.md` instead of a stub; check at the start of the next turn.
- `project_review` will re-run on its 24 h interval; its 504 was the same dead model.
- Two-collection split (CLI config collection vs hook-derived `ms_matts_f436780d`) is a separate decision, not touched here.
