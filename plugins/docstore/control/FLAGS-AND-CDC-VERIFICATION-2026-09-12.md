# Decision flags and index verification receipt

Recorded by Codex, 2026-09-12. Scope: Docstore control plugin only; no Intake or CCC runtime changes.

## Delivered

- Separate validated priority, authority and status fields, plus domain scope, source reference, rationale, actor, revision and change fingerprint.
- Additive `095_flags.surql` applied to live `probata/docs`, creating `docstore_flag` and `docstore_flag_audit`. No other legacy schemas replayed.
- Authorized owner boundary saved as `note:ccc_intake_docstore_boundaries`: critical / owner_decision / active, revision 1. Domains: docs, intake, consignatio, probata, infra.
- `docstore_set_flags` uses bound parameters, expected revision, transactional audit creation and identical-write replay detection. Audit append behavior is an application contract, not an absolute immutability guarantee against administrative credentials.
- `docstore_flags` and `docstore://critical/{domain}` retrieve flags independently of similarity ranking. Search includes critical context when native credentials are present; absent/failed flag retrieval is explicit. Shared skill instructs agents to consult scoped flags at decision points.
- Escaped, script-free HTML snapshot with separate badges. Not an interactive editor or live frontend.
- `docstore_verify_index` inspects 1–20 explicit Markdown paths, at most 1 MiB each, without indexing, importing the flow, or hydrating placeholders.

The control catalog now has 11 tools, four static resources, three resource templates and one prompt. Source host configurations forward native credentials by environment reference, never embedded values. Global host activation and ContextForge federation remain pending; this receipt does not claim agents automatically have the new tools installed.

## Validation

- Final local suite: **99 tests passed in 4.65 seconds**, isolated E-drive test directory, no live network in tests.
- Live native authentication, schema inspection, authorized flag write and flag read succeeded.
- Identical write replay retained revision 1 and original timestamp, without a second audit revision.
- A changed payload with stale expected revision was rejected; audit query showed only revision 1. The native server emits inline transaction errors, handled by regression-tested parsing.
- Live HTML snapshot: `.docstore-control/flags-20260912T134612003420.html`, one flag. Open request queued in Codex; visual display not independently confirmed.

Live testing exposed native protocol differences not caught by the first mocks: successful statements contain JSON beneath numbered headers, while failures can be inline `(error, Thrown)` / `(error, Query)` headers. Parser now checks statement sequence and errors, including rollback failures, rather than equating transport success with query success.

The initial array-index query returned one copy of the same flag per matching record domain. Explicit documented `WITH NOINDEX` returned the correct single row. Queries now table-scan the small flag overlay instead of silently deduplicating client-side; revisit with a proven index plan if this table grows substantially.

The native MCP client still reports `Session termination failed: 202` on teardown after successful operations. This is recorded separately from query success and is not claimed fixed.

## Index freshness result and limitations

Live check of local `docs/NAMING.md` found:

- Local worker-compatible folded UTF-8 hash: `23a206679ce2b66322c184a6b0c630d6c052bfda85959a5d9deddfa91c9078cc`.
- Stored hash: `875a39811f4fa2e38a012ece0cc0719d1b3cd60c5ae0760340366fd58a3585ed`.
- Document `document:docs_naming_md`, active; 15 observed chunks, expected 2048-dimensional vectors and valid document links.
- Result: **hash mismatch**, projection present but unverified; CDC execution and exact projection freshness **unproven**.

This mismatch does not establish why the content differs: stale ingestion, deployed-source differences and line-ending differences remain possibilities. The verifier preserves CRLF/BOM and mirrors the existing non-BMP folding profile. Document hash alone does not prove chunk freshness or complete chunk cardinality. The current CLI returns its structured findings with exit 0 when the verification request succeeds; automation must inspect findings, not treat exit 0 as an index freshness assertion.

The hosted REST recall API was unavailable during these checks. Standalone native flags and verification worked; live integrated semantic-search flag rendering remains unverified.

## Remaining work

- [ ] Add durable worker-owned run receipts correlating source identity/hash, CocoIndex execution, target projection and errors; then prove create/update/no-change cases end to end.
- [ ] Validate integrated retrieval when the recall API is available.
- [ ] Deliberately activate the plugin in the selected host and verify resource/tool access and credential isolation.
- [ ] Integrate badges/filtering into the eventual interactive note/decision UI; current viewer is a snapshot.

No indexing worker, per-turn hook, scheduler, model inference, corpus reconciliation, service deployment, git commit or push was started. The flag overlay does not replace CocoIndex change tracking. CCC, Intake and Docstore isolation is unchanged.

An earlier duplicate-card preview was moved, not deleted, to `to_be_deleted/docstore-control-20260912/flags-20260912T134513456953-array-index-duplicate-preview.html`. Only the owner may permanently remove it.
