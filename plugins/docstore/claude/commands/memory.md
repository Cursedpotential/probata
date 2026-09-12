---
description: Recall agent session memory (memsearch) - compact table of what past sessions established
argument-hint: "<question>" [--k 6]
allowed-tools: Bash, Read
---

<!-- Byline: Claude Code · Opus 5 · 2026-09-10 — owner order: "/memory" pulls it up. -->

Memory recall for: $ARGUMENTS

!`C:/Users/matts/.local/bin/python3.exe "${CLAUDE_PLUGIN_ROOT}/../../scripts/docstore/memory.py" $ARGUMENTS 2>&1`

Show the table exactly as printed. Then at most three bullets: what past sessions established, with the date. Memory is recollection, not ruling: if it conflicts with the docstore (`/recall-doc`, `/recall-adr`), the docstore wins and the conflict is reported.
