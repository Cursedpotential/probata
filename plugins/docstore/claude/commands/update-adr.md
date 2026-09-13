---
description: "Propose an amendment to an ADR or decision in the cloud Docstore, and record it only after owner approval."
argument-hint: '"<ADR / D-number / topic>" "<the change>"'
allowed-tools: "Bash, AskUserQuestion, Read"
---

<!-- Byline: Claude Code · Opus 5 · 2026-09-10 — owner order: "update ADR". Writes go through fn::decision_amend behind an approval gate. -->

Target and change: $ARGUMENTS

Candidate decision documents:

!`C:/Users/matts/.local/bin/python3.exe "${CLAUDE_PLUGIN_ROOT}/../../scripts/docstore/recall.py" adr $ARGUMENTS --k 5 --status all --why 2>&1`

Follow these steps in order. Never skip step 4.

1. Pick the subject decision document from the table. If more than one fits, ask the user which.
2. Show its current title, status and the passage being changed (from the table's passage column, or `recall.py adr "<topic>" --why --k 3`).
3. Draft the amendment banner: one dated paragraph, attributed to the owner, stating exactly what changes. List any documents it closes (record ids), or none.
4. Ask for approval with AskUserQuestion: Approve / Edit / Cancel. Do not write anything without Approve.
5. On Approve, run through `scripts/docstore/sq.py`: `RETURN fn::decision_amend("<source_path>", "<banner>", NONE);` (or an array of closed document ids instead of NONE). Keep double quotes out of the banner text.
6. Verify with `sq.py "RETURN fn::provenance(document:<id>);"` that a new decision_log row exists, and report it in one line.
