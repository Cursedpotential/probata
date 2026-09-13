---
description: Recall any document from the cloud docstore - hybrid keyword + vector search, reranked, compact table
argument-hint: "<question>" [--k 8] [--status all] [--why]
allowed-tools: Bash, Read
---

<!-- Byline: Claude Code · Opus 5 · 2026-09-10 — owner order: "/recall doc" pulls it up; all processing inside the tool. -->

Docstore recall (any document type) for: $ARGUMENTS

!`C:/Users/matts/.local/bin/python3.exe "${CLAUDE_PLUGIN_ROOT}/../../scripts/docstore/recall.py" doc $ARGUMENTS 2>&1`

Show the table exactly as printed. Then at most three bullets: which result answers the question, with its path. If the top score is under 0.3, say the store has no strong match rather than stretching a weak one. Add `--why` to see the matching passage, `--status all` to include superseded documents.
