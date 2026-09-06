# Rename follow-ups — agent prompt files

> _Byline: Claude Code · Fable 5.1 · 2026-09-06. One file per task; each is self-contained. Hand a file to a fresh agent as its first message._

| # | File | Who | Needs owner? |
|---|---|---|---|
| 01 | `01-finish-directory-rename.md` — **DONE 2026-09-06** (owner ran it; defects fixed by hand and the follow-up sweep — nested junctions re-pointed, stale "rename pending" text cleared in this repo, the vestigia repo, memory index and guardian rules — see register §9) | — | — |
| 02 | `02-restore-deny-list-and-gate.md` | owner or explicitly authorized agent | yes (owner's settings file) |
| 03 | `03-r2-dev-fixtures-copy.md` | any agent | yes (billable transfer sign-off) |
| 04 | `04-golden-clone-teardown.md` | the ingest session | yes before touching `platform` |
| 05 | `05-identifier-rulings-needed.md` | any agent, in conversation with the owner | yes (18 rulings) |
| 06 | `06-analysis-engine-split-indagatio.md` | planning agent | plan iterates until owner says done |
| 07 | `07-memory-tooling-repairs.md` | any agent | only for dropping collections |
| 08 | **DONE 2026-09-06** — sibling naming sweeps via `scripts/rename_siblings_2026_09_06.py`: advocatio commit `5c62b38` pushed to `Cursedpotential/Legal-Workspace` master; vestigia commit `5013583` pushed to `Cursedpotential/TraceIQ` main. Code identifiers (`legal_workspace` package, dist name) and GitHub repo names NOT renamed — those need their own rulings. | — | GitHub repo renames unruled |

**Read `BRIEFING-open-items-2026-09-06.md` first** — live state, risk, and the exact decision needed for 02, 03, 04, 05, 07 (2026-09-06 17:45).

## Standing rules every file assumes (from AGENTS.md / CLAUDE.md)

- Never hard-delete; quarantine under the repo's holding directory (`.review_hold/`). Confirm before live-infra changes. Verify before claiming done: load the real thing, read the real log. Byline every artifact.
- Canon for names: `docs/NAMING.md` (D-137..D-142). Recall stores get the new name APPENDED beside the old; canon docs replace with strike-through.
- Zero committed live evidence exists (D-142): never design around protecting empty stocks; only `reference.*`, hand labels, the Case Bible catalog, and curated docs are precious.
- Persist results in the repo. `docs/registers/RENAME-LIVE-CHANGES-2026-09-06.md` is the live-change ledger: append, do not rewrite.
