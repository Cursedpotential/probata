# Search project profile schema

Required fields: schema, name, root, index_store, result_sink, stores,
plugin_path, source_commit, source_version, source_dirty,
source_package_sha256, installed_at_utc.

root selects the profile by longest resolved-path prefix. index_store contains
generated Tree-sitter/DuckDB files. result_sink receives exports and
reconciliation packets. stores is an optional subset of smart_explore, ccc,
docstore, codex_memory, claude_memory, cnf, remember, and memsearch.

The bootstrapper also writes <target>/.search-profile.json and a code-only
<target>/.cocoindex_code/settings.yml. Documentation roots and Markdown/text/HTML
file classes remain excluded from CCC. Docstore must use its own configuration
and index.

## HITL commands

Run scan first, then plan with all source/sink arguments and --plan-file. The
plan prints an immutable plan_id and the isolated installer/environment target.
After reviewing it, the human explicitly runs approve with --plan-file,
--approval-file, --plan-id <exact ID>, and --approve. Apply requires that exact
plan and approval pair. Verify and report accept --plan-file and do not change
the approved target contract.

Apply prefers uv and sets UV_PROJECT_ENVIRONMENT to the approved ignored
<target>/.runtime/search/env. If uv is unavailable, it creates that same isolated
environment with python -m venv and installs the exact requirements.txt pins.
Ambient site packages are never used.
