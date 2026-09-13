# Docstore persistence receipt - 2026-09-12

Byline: Codex docstore-librarian. Scope: the three explicitly assigned repair artifacts, plus one caveat note; not the entire conversation or repository.

## Verified persisted records

| Source | Stable key | Current revision | SHA-256 / proof |
|---|---|---:|---|
| `docs/reviews/2026-09-12-duckdb-live-test-repair.md` | `document:proffer-duckdb-repair-checkpoint-20260912` | 2 | `009fa2504c3bcf4eb5a7f7d92213994e6b4f78840c68ae55f2f3e7936b0a4332` |
| `docs/pending-review/2026-09-12-handler-schema-reconcile/README.md` | `document:proffer-handler-schema-reconciliation-20260912` | 2 | `0dc1eddccae0206d221944da937b9e25f7a3b4f328feba7094ec8205041f432f` |
| `modules/engine/RECOVERY_HANDOFF_20260912.md` | `note:proffer-engine-recovery-checkpoint-20260912` | 1 | Full source text retained in note summary, metadata whitespace trimmed; source file SHA-256 `462e7cd6ede03d2733916670b9864692091c0feddc7040cb1dab7c8157bdd3b0` |
| Interpretation and completion caveats | `note:proffer-repair-checkpoint-caveats-20260912` | 1 | Exact summary equality asserted on readback; untruncated critical flags |

Native record IDs:

- `docstore_document:dba62421b0ffb49f097a53deb218be5ddabc7071b0e51b4f12b49a622585b030`
- `docstore_revision:dba62421b0ffb49f097a53deb218be5ddabc7071b0e51b4f12b49a622585b030_2`
- `docstore_document:f482078f2a1906e7380d60cf29001a9ac46cfea42c827e67398ad5670dc84f00`
- `docstore_revision:f482078f2a1906e7380d60cf29001a9ac46cfea42c827e67398ad5670dc84f00_2`
- Engine note: `docstore_flag:c82b00b588a049450dc7d90e257d9aff7126616f591a7ae09bcc69628f0a0501`; change hash `5d76be6f13ddc8615bf0e975cade981eda5dd77ce95243e6b77413c9eda27698`.
- Caveat note: `docstore_flag:ef725427dbccba69ab42fcb5430f873083b9b7abd87b9d3978b96b3b0a28e09f`; change hash `36c828628338f59762a31d1b785a86948d05404e0d26d0276dcbe3e31c66e431`.

All four writes were read back from live dedicated `probata/docs`. The two lifecycle records are `unapproved`, generation 2; projection status remains `unverified`, CDC execution `unproven`. No approval was requested or inferred. Final independent source file hashes remained unchanged.

## Method, corrections, and limits

Used the supported canonical Docstore control implementation through uv, not direct projection inserts. Read lifecycle/database contracts. Related-update searches preceded writes, and the relevant full Intake workflow visibility/repair-gate record was read. General DuckDB search was truncated; exact repair/schema/handoff searches were complete without matches. Critical proffer flags were empty before writing. Registry confirmed Probata canonical `docs/` prefix; its registered main checkout is separate from this uncommitted worktree, which is explicitly retained in source references.

Initial native calls failed because the dedicated secret file uses `SURREAL_DOCS_USER/PASS`, while the CLI environment loader only imports `DOCSTORE_` names. Mapping only those dedicated credentials to process-local `DOCSTORE_BASIC_AUTH` restored authenticated native operations. No credentials or host configuration were printed/changed.

Initial document captures used Windows PowerShell default decoding and produced wrong hashes. This was detected immediately, not represented as a match. Correct UTF-8 captures appended revision 2 on the same logical identities; erroneous revision 1 remains preserved as audit history, with correction source references. The current hashes above match exact source file hashes. Nothing was deleted or overwritten.

Engine handoff is outside `docs/`, so it was preserved as a bounded sourced note, not assigned a fictional canonical docs path. Caveat note explicitly preserves Kimi causality uncertainty, parent-reported unresolved byte-coverage verifier/SQL trigger blocker, historical test boundaries, and absence of live deployment/evidence-promotion proof.

No CocoIndex execution, vector/chunk updates, evidence promotion, source edits, or deletes occurred. This receipt is a local index of the verified remote records, not a claim that the receipt itself or every conversation message is indexed.
