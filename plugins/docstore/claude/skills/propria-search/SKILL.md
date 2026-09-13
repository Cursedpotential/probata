---
name: propria-search
description: Search Propria project context. Routes documentation, decisions, plans and handoffs to the universal CocoIndex and SurrealDB Docstore; routes code symbols and implementations to the current project's separate CCC index; searches both for design-versus-code questions.
allowed-tools: mcp__plugin_propria_docstore_control__coco_docstore_search mcp__plugin_propria_docstore_control__docstore_get mcp__plugin_propria_docstore_control__docstore_flags Bash Read
---

# Propria search

Choose the evidence plane from the question, then retrieve before answering.

## Documentation

For decisions, plans, TODOs, handoffs, architecture, operating notes, current
documented state, or references, call `coco_docstore_search` with an explicit
domain. It embeds the query through NVIDIA NIM and searches CocoIndex-maintained
vectors in the dedicated SurrealDB Docstore. Use its default compact DuckDB
presentation. Fetch selected records with `docstore_get`; cite document ID, status
and source path.

## Code

For symbols, functions, implementations, configuration or call sites, use the
separate `ccc` skill/CLI from the target project root. Cite file paths and lines.
Run CCC indexing only for that project; it is not Docstore ingestion.

## Mixed questions

Search both independently. Present `Documentation evidence` and `Code evidence`,
then state whether they agree, drift, or leave a gap. Never combine scores or use
one index's freshness as proof of the other.

## Hard boundary

Docstore and CCC retain separate application identities, databases, tracking
state, locks, credentials, citations and write paths. Neither silently falls back
to the other. DuckDB only filters/presents retrieved rows; it does not store or
rank vectors. Intake is a third system for filesystem and corpus exploration and
is never queried as a substitute for either one.
