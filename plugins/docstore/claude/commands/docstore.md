---
description: Orient an agent to the Propria Docstore and route it to the right function, tool or sub-skill for the task in hand (read, search, tag, submit, update, handoff, decision, retract, verify). Use when unsure which Docstore step applies.
argument-hint: [what you are trying to do]
---

Load and follow the `docstore` skill in this plugin (`skills/docstore/SKILL.md`). It is the process.

Task from the user: $ARGUMENTS

Steps:
1. Classify the task with the skill's table (find / find-by-tag / add repo file / add file-less note / handoff / decision / update / retire / todo / flag / verify / provenance).
2. State which lane applies and the exact function or tool you will call, then do it.
3. Apply the non-optional rules: pipeline-only for repo files, tags on every submission, every status when searching, read-then-write-then-read-back, no deletes.
4. Report the record id or the verified attribution, and the lane used. If the task needs a step the system does not have, say so instead of improvising a write.
