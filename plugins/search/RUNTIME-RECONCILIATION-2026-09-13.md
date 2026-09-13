# Search Runtime Reconciliation — 2026-09-13

## Governing location

The only Smart Explore engine implementation is plugins/search. Generated
Tree-sitter/DuckDB state follows two deterministic ownership scopes: Propria
paths use E:\AI_Workspace\Projects\Propria\.runtime\search\smart-explore\indexes;
all other paths use C:\Users\matts\.smart-explore\indexes. The Propria root
ignores /.runtime/; database and WAL files are never source artifacts. Shared
runtime-root overrides and legacy repository-local indexes are rejected. --db
remains available only for isolated diagnostics.

C:\Users\matts\.smart-explore is the platform-agnostic profile/package home.
It contains config, the Propria routing profile, two generalized skill
entrypoints, and thin launchers. It contains no engine source. The generalized
customizer installs one pinned Search plugin engine instance per approved target
through scan, immutable plan, exact human approval, target-bound apply, and
verify/report stages.

The locked runtime pins DuckDB 1.5.5 and Tree-sitter Language Pack 1.9.1 in
pyproject.toml, requirements.txt, and uv.lock. The target environment lives in
the target's ignored .runtime/search/env. uv is preferred; the documented
fallback uses python -m venv plus exact requirements pins and never ambient site
packages.

The isolated HITL proof under Propria/to_be_deleted used plan ID
03BE3B022765C066ADD0661457A4A890963367A0C15610833C0AFE8956915DB6.
It rejected implicit mutation by construction, then used a labeled test approval
fixture bound to the exact target and package hash. Apply and verify proved
DuckDB 1.5.5 imports, Tree-sitter structural search, CLI help, MCP initialize,
and CCC documentation exclusions. The entire proof remains quarantined for the
owner; it was not installed into a live product.

## Why E:\data\codex-smart-explore existed

The directory was selected on 2026-09-12 by a transient historical
SMART_EXPLORE_HOME=E:\data\codex-smart-explore override. The source default
at that time was the user profile. Process, User, and Machine environment scopes
contained no such value during this reconciliation, and targeted searches found
no committed or active config reference to the E:\data path. Its Probata
filename hash is identical to the canonical path hash, confirming that it was
alternate runtime state for the same resolved project root.

The flagged directory contained only:

| File | Bytes | SHA-256 |
| --- | ---: | --- |
| probata-5dd437c903f9.duckdb | 12,288 | E507EE3E10AE6F57180779E68B3A94DB0575566B063BB6D997FA83815507A5E6 |
| probata-5dd437c903f9.duckdb.wal | 4,574,173 | 802A30A82F7329D22DFB616ECE4A58113FE54F3DA14FA18591B0F1A2D159B989 |

No Smart Explore process held either file. The unrelated DuckDB processes seen
during inspection were building the Consignatio best-copy database at a
different path.

## Preserved migration

The newer user-profile Probata index was checkpointed before copying. It records
root E:\AI_Workspace\Projects\Propria\Probata\probata, 8,534 files, and
112,480 symbols. The source and canonical copy matched:

| Location | Bytes | SHA-256 |
| --- | ---: | --- |
| C:\Users\matts\.agents\smart-explore\indexes\probata-5dd437c903f9.duckdb | 22,294,528 | 89FF949713E0F916DEEAB6785C5CD012EB9D8AADE97263B8D1109D603ED5C243 |
| E:\AI_Workspace\Projects\Propria\.runtime\search\smart-explore\indexes\probata-5dd437c903f9.duckdb | 22,294,528 | 89FF949713E0F916DEEAB6785C5CD012EB9D8AADE97263B8D1109D603ED5C243 |

After hash and read-only metadata/count verification, the obsolete roots were
moved without deletion to:

- E:\AI_Workspace\Projects\Propria\to_be_deleted\smart-explore-runtime-reconciliation-20260913\legacy-user-runtime
- E:\AI_Workspace\Projects\Propria\to_be_deleted\smart-explore-runtime-reconciliation-20260913\legacy-e-data-runtime

The user-profile quarantine contains 144 files totaling 923,276,630 bytes after
the Probata WAL checkpoint. The E:\data quarantine contains two files totaling
4,586,461 bytes. A local PROVENANCE.txt beside them records the source paths,
counts, hashes, and canonical destination.

Only the owner may delete those quarantined copies.

## CCC code-index boundary

CCC remains a separate generated code index at
E:\AI_Workspace\.cocoindex_code\target_sqlite.db; it is not a Smart Explore
runtime database. After the bounded refresh attempt, the 2,847,653,888-byte
database contains 288,820 chunks across 13,354 files. Its SHA-256 is
17843B85DD602F1539B9F3154C5261361DF81971D0DD78429FD708D0B4A8BA64.
SQLite integrity_check returned ok and no WAL or journal sidecar remains. Direct
SQLite inspection found zero documentation-root files/chunks
and zero .md, .mdx, .rst, .txt, .html, or .htm files/chunks.

The refresh could not close successfully. Its vector-index phase grew to more
than 41 GB private memory on a 38.9 GiB host and left about 0.2 GiB physical
memory free. It was interrupted cleanly, then the daemon was stopped. A bounded
semantic query repeated the same defect, consuming about 29 GB and leaving about
0.7 GiB free before clean interruption. CCC status therefore remains in progress
and semantic usability is failed, not fresh or operational. The code-only
content fence and database integrity are proven; CCC resource behavior requires
repair before another full refresh. Search product usability remains pending
owner review regardless of index plumbing results.
