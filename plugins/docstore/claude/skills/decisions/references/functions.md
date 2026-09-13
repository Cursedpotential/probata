# decisions — function reference

Source: `090_docs_api.surql` (`fn::decision_amend`) and `060_functions.surql`
(`fn::current_decisions`). Confirmed, live schema as of 2026-09-09.

## fn::decision_amend

```
fn::decision_amend(
  $subject: string,                          -- source_path of a doc_type="decision" document
  $banner: string,                           -- written to decision_log.rationale
  $closes: option<array<record<document>>>
) -> object
  -- ok:      {ok: true, subject: record, decision_document: record|NONE, closed: array<record>}
  -- refused: {ok: false, error: "no_subject_record", detail: string}
```

Resolution order for the log row's `subject`: the decision document at
`$subject` if one exists → else the first item of `$closes` → else refuse.

## fn::current_decisions

```
fn::current_decisions($project: string) -> array<object>
  -- {id, number, title, decision, decided_at, supersedes, superseded_by}
```

This queries the `adr` table (`number`, `status IN ["proposed","accepted",
"superseded","deprecated","rejected"]`), which is a **separate** structure
from `document(doc_type="decision")`. Probata's D-number decisions may live
as `document` rows, `adr` rows, or both depending on how they were
registered — check `fn::docs_search(..., doc_type="decision", ...)` too
before concluding a decision set is empty.

## decision_log schema (read-only from this skill)

- `subject: record` (non-optional — this is why `fn::decision_amend`
  refuses rather than writing a row with no subject)
- `actor: string` default `"system"`
- `action: string`
- `from` / `to: option<string>`
- `rationale: option<string>` — there is **no `note` field**; `$banner`
  writes here
- `at: datetime` (READONLY, `time::now()`)

Auto-populated by `DEFINE EVENT` triggers: `adr_status_change`,
`adr_created`, `todo_status_change`, `todo_close_stamp` (sets `closed_at`,
does not itself write `decision_log`), `document_status_change`. Never
hand-write a row matching one of these `action` values — the event already
wrote it inside the same transaction as the status change.

## Worked example

```
run: { function: "fn::decision_amend",
       args: ["docs/decisions/D-160-docstore-plugin-scope.md",
              "D-160: plugin ships without forced main-thread agent; deny-by-settings replaced by agent-level tool allowlists.",
              [document:old_scope_note, document:draft_settings_plan]] }
```

## Gotchas

1. `decision_log` has no `note` field — use `rationale`.
2. `subject` is non-optional on `decision_log`; a call with no decision
   document at `$subject` and an empty `$closes` array is refused rather
   than writing a schema-violating row.
3. `fn::current_decisions` reads `adr`, not `document`. If probata's real
   D-numbers are stored as `document(doc_type="decision")` rows instead,
   this function returns nothing even though decisions exist — cross-check
   both before reporting "no current decisions".
