---
name: decisions
description: Amend or query probata's DECISION_LOG (D-numbers) and the store's decision documents (doc_type "decision"). Use when the user says "record a decision", "amend D-<n>", "what did we decide", "close these docs with this decision", or a conversation reaches an explicit ruling that should close out one or more open documents.
allowed-tools: mcp__plugin_propria_docstore_docs__run mcp__plugin_propria_docstore_docs__list Read
---

# Decisions

`decision_log` is append-only and mostly **auto-written** by `DEFINE EVENT`
triggers on status changes. The one thing you write by hand is a
**decision banner** via `fn::decision_amend` — never a raw `CREATE
decision_log`.

## Amend / record a decision

```
run: { function: "fn::decision_amend", args: [$subject_source_path, $banner_text, $closes_doc_ids_or_none] }
```

`$subject` is the **source_path** of a document with `doc_type = "decision"`
(e.g. a `D-<n>` decision document). If one exists there, `$closes` docs get
`RELATE decision->supersedes->doc` + flipped to `superseded` in the same
call. If no decision document exists at that path and `$closes` is empty,
the call refuses with `{ok:false, error:"no_subject_record"}` — there is
nothing valid to attach the log row to.

## Query the live decision set

```
run: { function: "fn::current_decisions", args: [$project] }
run: { function: "fn::docs_search", args: [$query, NONE, "decision", NONE, "active", 10] }
```

## Definition of done

A `decision_log` row exists (verify via `fn::provenance` on the subject),
and every document the decision was meant to close is `superseded` with a
`supersedes` edge pointing at the decision.

## Refusals

Refuse to write a decision you cannot trace to a source document or an
explicit statement in the conversation. Refuse to hand-write
`decision_log` directly — say "the event trigger will write that once the
real change happens" instead.

See `references/functions.md` for the exact signature, the `decision_log`
schema, and gotchas (no `note` field — use `rationale`; `subject` is
non-optional).
