---
name: handoff
description: Write a session handoff into the probata SurrealDB docs store (doc_type "handoff") instead of a loose file. Use before /compact, before /clear, at the end of a work session, when the PreCompact hook fires, or when the user says "handoff", "write a handoff", "save state for next session".
allowed-tools: mcp__probata_docstore__docstore_handoff_write mcp__probata_docstore__docstore_get mcp__plugin_propria_docstore_control__docstore_handoff_write mcp__plugin_propria_docstore_control__docstore_get Read
---

# Handoff

The old convention of dropping a HANDOFF-*.md file under `docs/` is
retired for this store (design doc §2/§8 item 8). A handoff is a
`document` row with `doc_type = "handoff"`, written through one function.

## Write it

Call `docstore_handoff_write` with `handoff: {title, body, domains}`. The
dedicated tool invokes only `fn::handoff_write`, validates bounded typed input,
and reads the resulting record and any superseded handoff back before returning.
Never substitute a loose Markdown file or claim persistence without the returned
record ID.

Auto-supersedes the previous **active** handoff whose `domains` overlap
`$domains` — same `new->supersedes->old` + status-flip semantics as
`fn::docs_new_version`, so there is never more than one active handoff per
domain cluster. Use the `handoff` skill's own conventions (STATUS/
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

`docstore_handoff_write` returned an id with `verified_readback: true`, and if a previous active handoff in the
same domain(s) existed, its status is now `superseded` (verify with
`fn::docs_get`).

See `references/functions.md` for the exact signature and the
overlapping-domains supersede rule.
