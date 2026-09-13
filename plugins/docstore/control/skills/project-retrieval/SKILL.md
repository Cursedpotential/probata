---
name: project-retrieval
description: Route Propria project questions to universal CocoIndex Docstore semantic search for documentation, project-local CCC for code, or both for mixed implementation-versus-design questions while keeping their indexes isolated.
---

# Project retrieval router

Use one agent-facing workflow while preserving two independent CocoIndex applications.

Probata hosts the universal Propria Docstore. Stored records must retain the owning
project and source path; hosting location does not transfer source ownership.

## Route by evidence type

- **Docs:** decisions, plans, TODOs, handoffs, architecture prose, current documented state, or references. Call `coco_docstore_search` with a domain and document kind. It searches NIM embeddings stored in the dedicated SurrealDB Docstore. Cite returned document IDs and statuses.
- **Code:** symbols, implementations, configuration, call sites, or observed code behavior. Use the `ccc` skill from the target repository root. Cite file paths and line locations.
- **Mixed:** retrieve both. Present separate `docs` and `code` evidence, then identify agreement, drift, or missing implementation. Never blend scores or imply that one index proves freshness in the other.

## Boundary

Docstore and CCC have different application identities, databases, tracking state, locks, credentials, freshness checks, result identifiers, and write paths. Do not repoint, merge, or silently fall back between them. DuckDB may compact/filter noisy Docstore rowsets after Surreal retrieval; it does not own embeddings or semantic ranking.
