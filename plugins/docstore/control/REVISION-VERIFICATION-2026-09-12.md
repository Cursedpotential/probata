# Revision lifecycle verification — 2026-09-12

Status: history/approval increment verified through the deployed Docstore database;
the complete source-edit → CocoIndex → current-search-projection lifecycle is unfinished.

## Verified

- Additive schema 096 applied transactionally to `probata/docs` through its dedicated
  native MCP endpoint. Independent INFO readback found all five lifecycle tables.
  Existing document/chunk and flag tables were not replaced.
- 148 local tests passed; the two explicit live-write tests skip by default.
- Both live tests were separately enabled and passed through the actual control tools.
- Lifecycle: capture, unchanged no-op, exact approval, metadata-only rename, edit,
  changed-since-approval, stale capture rejection, stale revision approval rejection,
  original approval replay, A → B → A as three distinct numbered revisions.
- Concurrent captures sharing one expected generation: exactly one succeeded;
  only one new revision/head generation was recorded.
- A separately stored synthetic human flag was byte-for-byte equivalent as returned
  by the database before and after the content race.
- Response validation rejects wrong document/revision IDs, mismatched approval
  fields and malformed results; raw UTF-8 and folded projection hashes are separate.

Retained synthetic records (no corpus file created or read):

- `note:synthetic_revision_3c4dd23c8a1d4933a4b2aeae360646bf`
- `note:synthetic_race_fba8f9905a524e7cb6d5e41a7a10d8c9`

Their approvals are explicitly labeled automated synthetic tests, not owner approvals.
Expected rejection tests log ToolError diagnostics. No HTTP-202 session-close warning
appeared in these test outputs.

## Failed attempts and limits

- Initial version-inspection SQL was rejected before schema execution. No mutation.
- A cancelled schema transaction established parse acceptance only; it did not prove
  execution success. Actual application and subsequent live tests supplied that proof.
- Initial isolated pytest collection could not import `cli`; using
  `uv run --frozen --no-sync python -m pytest` supplied the correct package directory.
- No Surreal CLI was found on PATH; validation used the deployed database instead.
- No live host plugin configuration, global cache, source corpus, CocoIndex worker,
  embedding model, or evidence store was changed or started.

## Next acceptance gates

1. Safe scoped CocoIndex update with no retirement of unselected documents.
2. Durable job/run receipts tied to the exact source/revision/projection fingerprints.
3. Real source edit → capture → index → independent current-document/chunk readback.
4. Approve-versus-edit concurrency test, path conflict/reassignment policy, bounded
   full-revision content retrieval and history pagination.
5. Verify the host-enabled plugin and ContextForge registration separately; source
   availability and database schema do not prove host deployment.

Canonical verification note is recorded through Docstore tools as
`note:docstore_revision_lifecycle_20260912`; verify readback, not this file alone.
