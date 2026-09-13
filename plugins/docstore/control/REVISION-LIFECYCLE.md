# Docstore revision lifecycle

Owner-approved scope: update the current search projection, append revision history,
preserve human flags separately, and track exactly which revision was approved.
This increment implements the history/approval tools; CocoIndex execution and durable
CDC run receipts remain a separate unfinished integration.

## Tool contract

- Query `docstore_related_updates` before adding/updating; inspect current state.
- Choose one stable `document:`, `adr:` or `note:` logical key, not a path-derived key.
- `docstore_capture_revision` takes that key, canonical repository-relative `docs/`
  path, title, original body text (maximum 1 MiB UTF-8), expected generation, actor
  and source reference. It does not read/write the source file.
- Changed content appends the next numbered revision, including A → B → A.
  Identical content/path/title is a no-op, even with a stale expected generation;
  this is retry safety, not proof the caller held the latest generation.
- Rename/title-only changes append an event linked to the applicable content
  revision; content approval survives. Historical paths remain reserved to that
  logical document. Path reuse/reassignment is not implemented.
- `docstore_approve_revision` requires explicit authority, current revision number,
  raw SHA-256, expected generation, actor, rationale, source reference and a stable
  request key. Never infer owner approval from active status or an agent summary.
- Replaying an identical approval request returns its original receipt, even after
  a later edit. It does not reapprove current content. Reusing the request key with
  different approval data conflicts. Generation is excluded from the request hash.
- `docstore_revision_state` distinguishes document_missing, unapproved,
  approved_current and changed_since_approval. Each history list returns at most
  20 rows with explicit truncation. Approval covers content, not title/path metadata.

Raw SHA-256 preserves supplied UTF-8 text, including CRLF and non-BMP characters.
The separate projection hash follows the existing Docstore non-BMP folding profile;
it is not evidence that CocoIndex has ingested that revision. Full historical-body
retrieval and pagination beyond the bounded recent history are not implemented yet.

## Isolation and verification

`docstore_document`, `docstore_revision`, `docstore_revision_event`,
`docstore_source_alias` and `docstore_approval` are outside the CocoIndex projection.
The existing `docstore_flag` and audit rows are not replaced. Snapshot fields use
SurrealDB READONLY; privileged administrators can still alter schema/delete rows,
so this is not an administrator-proof immutable archive.

The tools use bound named functions inside transactions and verify exact returned
identities/fields. An uncertain response must be read back before retrying. The
transport's session-close status is separate from transaction success.

Do not call legacy `fn::docs_new_version` as a substitute for this lifecycle on
filesystem-indexed documents: it creates a separate projection document identity
without creating the corresponding chunk projection. The legacy workflow requires
separate reconciliation; it is not a CocoIndex incremental-update operation.

Local tests: `uv run --frozen --no-sync python -m pytest -q -o addopts='' -p no:cacheprovider`.
The opt-in `tests/test_revisions_live.py` requires `DOCSTORE_REVISION_LIVE=1` and
dedicated Docstore credentials. It retains clearly synthetic records, never deletes
them, and neither accesses corpus files nor invokes a model/indexing worker.

Official schema reference: [SurrealDB DEFINE FIELD](https://surrealdb.com/docs/reference/query-language/statements/define/field).
