---
name: handoff
description: Write a session handoff into the probata SurrealDB docs store (doc_type "handoff") instead of a loose file. Use before /compact, before /clear, at the end of a work session, when the PreCompact hook fires, or when the user says "handoff", "write a handoff", "save state for next session".
allowed-tools: mcp__plugin_propria_docstore_control__docstore_handoff_write mcp__plugin_propria_docstore_control__docstore_get mcp__plugin_propria_docstore_docs__run Read
---

# Handoff

The old convention of dropping a HANDOFF-*.md file under `docs/` is
retired for this store (design doc §2/§8 item 8). A handoff is a
`document` row with `doc_type = "handoff"`, written through one function.

## Write it

Call `docstore_handoff_write` with `handoff: {title, body, domains, supersedes}`
(`supersedes` is a list of `document:<id>` strings; omit it or pass `[]` to
create a handoff that replaces nothing). **Fixed 2026-09-16:** the control
tool now always forwards `supersedes` as a real array, even when empty, so it
never triggers the dangerous same-domain-set fallback described below — that
fallback only exists in the raw `fn::handoff_write` SurrealQL function
(reachable directly via the `docs` MCP server's `run` tool), not through this
tool. Prefer this tool for exactly that reason. The dedicated tool invokes
`fn::handoff_write`, validates bounded typed input, and reads the resulting
record and every superseded handoff back before returning. Never substitute a
loose Markdown file or claim persistence without the returned record ID.

**Fixed 2026-09-15/16.** Pass an explicit `$supersedes` (the real record
id(s) this handoff replaces, found first via a `fn::docs_search(...,
doc_type="handoff", status="active", $domain, ...)` lookup) whenever you
know what you're replacing. Without an explicit `$supersedes`, the function
falls back to superseding **every** currently-active handoff whose
`domains` array is the exact same *set* as `$domains` — same
`new->supersedes->old` + status-flip semantics as `fn::docs_new_version`,
but this can be more than one row: a common domain tag like `["docs"]` is
shared by many unrelated real handoffs, and the fallback closes all of
them in one call (reproduced live 2026-09-16 — a test call with domain
`["docs"]` and no `$supersedes` superseded six real, unrelated handoffs;
fully reverted). Treat the same-domain-set fallback as a last resort, not
the normal path. Use the `handoff` skill's own conventions (STATUS/
BUILD_STATUS enums, mandatory UNRESOLVED section, WHAT/WHY/APPROACH/
SHORTCOMINGS on pending decisions) for `$body` — this skill only handles
where it's stored, not the narrative structure.

## PreCompact behaviour

`hooks/hooks.json` runs `bin/precompact-marker.sh` on `PreCompact`. It
cannot inject context into the resulting session (`additionalContext` is
invalid there and would drop the hook's entire output) — it only writes a
marker file and emits a best-effort `systemMessage` for the *current*
transcript. The next `SessionStart` reads that marker and reminds the
resumed session to run this skill. If compaction happens without this
skill having run first, that unresolved-work loss is real — treat the
SessionStart "resumed after compaction" line as high priority.

## Definition of done

`docstore_handoff_write` returned an id with `verified_readback: true`, and
the specific prior handoff(s) you meant to replace are now `superseded`
(verify each id with `fn::docs_get`) — and nothing else flipped to
`superseded` that you didn't intend.

See `references/functions.md` for the exact signature and the
same-domain-set supersede rule (and why to pass `$supersedes` explicitly).
