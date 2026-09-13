---
description: Recall ADRs and decision documents from the cloud docstore - hybrid search, reranked, compact table
argument-hint: "<question>" [--k 8] [--status all] [--why]
allowed-tools: Bash, Read
---

<!-- Byline: Claude Code · Opus 5 · 2026-09-10 — owner order: "/recall adr" pulls it up. -->

ADR / decision recall for: $ARGUMENTS

!`C:/Users/matts/.local/bin/python3.exe "${CLAUDE_PLUGIN_ROOT}/../../scripts/docstore/recall.py" adr $ARGUMENTS 2>&1`

Show the table exactly as printed. Then at most three bullets naming the governing decision and its path. Superseded ADRs are hidden by default; if the answer may be an older ruling, rerun with `--status all` and say which one supersedes it. If the top score is under 0.3, say there is no strong match.
