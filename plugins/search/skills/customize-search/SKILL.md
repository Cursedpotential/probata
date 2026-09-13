---
name: customize-search
description: Install or update a pinned Search plugin instance for a target codebase and register its code-index, result, and optional recall-store profile.
---

# Customize Search

Use this skill when a codebase needs its own pinned Search plugin instance. Read
references/profile-schema.md before changing an existing profile.

Run scripts/bootstrap.py through scan, plan, approve, apply, and verify/report.
Scan and plan do not mutate the target. Plan records the installer, ignored
runtime environment, sources, sinks, versions, target, and immutable package
hash. Approval binds the exact plan ID, target, and hash. Apply refuses any
mismatch; it copies through a staging directory and preserves replaced content.
Verify checks isolated imports, parser, DuckDB, CLI, MCP, and docs exclusions.

By default, an existing target plugin or profile causes a fail-closed error.
--update preserves the old instance or profile under the nearest to_be_deleted
quarantine before replacement. The script never deletes files.

A project instance owns one engine copy at <target>/plugins/search. User home
C:\Users\matts\.smart-explore contains profiles, skills, templates, and thin
launchers only. Keep CCC code ingestion separate from Docstore documentation
ingestion and preserve unavailable-store reasons.

Read the reference for exact commands. Do not run approve or apply until the
human explicitly approves the emitted plan ID.

~~~powershell
python scripts\bootstrap.py --target E:\code\example --source E:\AI_Workspace\Projects\Propria\Probata\probata\plugins\search --index-store E:\code\example\.runtime\search\smart-explore\indexes --result-sink E:\code\example\.runtime\search\results --stores smart_explore,ccc,docstore
~~~
