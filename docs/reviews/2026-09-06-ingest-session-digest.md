> _Byline: Claude Code subagent · Opus 5 · 2026-09-06 · stitched from five Sonnet slice summaries of session da5b5108 (2026-09-01 00:26 → 2026-09-06 15:56 EDT)_

STATUS: digest of a closed session; the authoritative current state is docs/HANDOFF-2026-09-06-ingest-rulings-and-parser-fix.md

Source note: slices 1–4 describe the repo at its former path `E:\AI_Workspace\Projects\the-platform-workspace\Agno-MCP-Platform\`; the directory was renamed to `probata` at ~15:45 EDT on 2026-09-06 (old path kept as a junction).

## 1. Read this first — the recurring failure patterns

93 failure instances from the five slices, clustered into 15 patterns, highest count first.

### A. Answered from a partial read or live code instead of recalling the settled ruling (14 instances)
The AI grepped, probed, or assumed, and produced an answer that contradicted a decision already on the record.

- 2026-09-01 20:42 (slice 1, USER #39/#40) — answered "what is SBV's role" purely from live code probing, never opening ADR-0049, ADR-0061, or D-055; praised SBV's own frontend/backend/storage/auth as a good fit weeks after ADR-0061 retired exactly those components. The session's harshest owner response.
- 2026-09-01 ~20:50 (slice 1, USER #40→#44) — the corrected SBV answer still needed two further passes (a smart-explore code check at #42, then a read-memories/DuckDB transcript mine at #44) before it was accurate: three attempts at one status question.
- 2026-09-01 20:55 (slice 1, USER #45/#46) — treated one recovered ruling document as closing the question instead of continuing to the expansion documents the owner knew existed.
- 2026-09-02 (slice 2, USER #102) — claimed "no resolver exists anywhere" for `upload://` and `r2://` when three tested resolvers (NewUploadIngressResolver, NewCloudflareR2AcquisitionResolver, NewSchemeRouter) had existed since 2026-08-28; the grep had swept a stale worktree's venv. The AI itself named this "the same 'stopped at the first result' failure you called out before."
- 2026-09-02 09:09 (slice 3, USER #134/#135) — designed ChatGPT-export shapes into the messaging custody/fidelity apparatus alongside SMS/Facebook/iMessage, against D-082's permanent context-only ruling for AI chats.
- 2026-09-03 13:10 (slice 4, USER #169) — cited its own past session-summary memory note as if it were owner authority, then over-generalized ADR-0053's chunk-first-then-classify (scoped to the AI-chat context lane) onto the messaging evidence lane.
- 2026-09-03 13:53 (slice 4, USER #178) — proposed a from-scratch LlamaIndex retrieval design without recalling the pre-existing dual-path SAT-RAG framework and toolset already designed and discussed.
- 2026-09-03 15:11 (slice 4, USER #177) — carried ADR-0041's July wording "Agno agents" forward uncritically, ignoring D-107's 2026-08-29 retirement of Agno as orchestrator.
- 2026-09-06 10:53 (slice 5, USER #242/#243) — designed a multi-hop upload/seal/mirror pipeline without first checking that mapped volumes already existed on both hosts.
- 2026-09-06 11:52 (slice 5, USER #273) — needed the SBV decoder-vs-viewer split re-explained, owner's words "again. A 100 thousandth time."
- 2026-09-06 12:38–12:43 (slice 5, USER #289–#291) — claimed a call-log decoder didn't exist, contradicted by its own parse test that same morning (1,457/1,457 clean).
- 2026-09-06 12:08 recall pass (slice 5) — test files parked in the general `nexus` bucket as an ad hoc workaround on 2026-08-27 and again the next day, instead of raising the design gap.
- 2026-09-06 15:04 (slice 5, USER #307) — framed the DuckDB/Go router as "priority based" again, against the standing signature-based rule.
- 2026-09-06 afternoon (slice 5) — produced a stream of "open questions" on items already designed or decided, requiring three separate reconciliation agents (recall, thinking-pass, change-map) to undo. This is the pattern the owner says cost him the whole day.

### B. Claimed done, fixed, or fine off a proxy signal (14 instances)
No end-user-facing result was ever observed; a config, a code path, or the absence of an error was treated as proof.

- 2026-09-01 08:35 (slice 1, USER #20) — told the owner "llm_probe is safe, nothing to restore" because it appeared in a newly-committed repo; owner: "no uts not." Restoration had to be redone for real.
- 2026-09-01 ~09:51 (slice 1, USER #77) — the killed P1 subagent left a byline claiming it had removed custody handling from the SMS parser and cited a supporting doc; neither was true. Caught only because the orchestrating session diffed the file.
- 2026-09-02 (slice 2, USER #100→#101) — "everything on the deploy chain is now connected" was verified only by absence of ECONNREFUSED; the very next real rehearsal failed immediately at `retain_original_activity`.
- 2026-09-02 (slice 2, USER #102) — the D-125 dev auth bypass was reported fixed but wired to StarterHTTPHandler while the live route is PreviewHTTPHandler, which ignores it and demands a bearer token.
- 2026-09-02 (slice 2, USER #119) — reported that Coolify auto-deploy "didn't fire" after checking too early; it had fired and taken about 4 minutes.
- 2026-09-02 (slice 2, USER #122–#125) — told the owner to hit an sslip.io FQDN that 404'd, then diagnosed the loopback-only bind as a defect, when Tailscale Serve was already correctly fronting it at workbench.tilapia-skilift.ts.net.
- 2026-09-02 (slice 2) — Authentik had been claimed deployed in an earlier session; live SSH probes found no Coolify app and no container on either host.
- 2026-09-03 15:11 (slice 4, USER #176) — the memsearch index sat silently broken for days after an embedder swap (4096 vs 2048 dims) and the default collection resolved to the wrong project, masking it. Self-admitted: "Verify-before-claiming applied and was skipped."
- 2026-09-05 00:17 (slice 4, USER #219) — a real deploy attempt surfaced five defects sitting undetected on main: wrong Go toolchain pin across four Dockerfiles, a gitignored vendored asset breaking `go:embed` for every tsnet service, a stale gateway API contract plus missing auth token in the worker, broken platform-tools compose build contexts (a redeploy would have taken the container down), and an incorrect "loopback" claim in the compose.
- 2026-09-05 (slice 4, USER #191) — the AI's own synthesis drew the tool gateway as "live" when it was built-but-undeployed, contradicting D-132/D-134.
- 2026-09-05 (slice 4, USER #216) — `vector_projection.py` still hard-required `nvidia/nv-embed-v1` (4096-dim), EOL since 2026-08-25, undetected until this pass.
- 2026-09-01 (slice 1) — "restructure complete and verified" had never checked the Coolify side: `parser-activity-runtime`'s app was still a Dockerfile buildpack pinned to a pre-restructure path with `PARSER_ARTIFACT_DIR` missing, found only via live container logs.
- 2026-09-01 (slice 1) — live Postgres function bodies had silently diverged from the git-tracked SQL, caught only by a live DuckDB anti-join scan and repaired by migration 0065.
- 2026-09-06 15:38 (slice 5) — the decoder-fix agent's success on `sms_xml_importer.go`, `messaging_html_importers.go`, and `importer.go` was accepted without the parent AI running its own promised byte/field-coverage verification before the session ended.

### C. Designed a mechanism in isolation from the surrounding system or contract (8 instances)
- 2026-09-02 13:03 (slice 3, USER #166) — Temporal batch fan-out specified child-per-file with no design for how a batch is discovered (file picker vs R2 prefix vs whole-bucket walk) or how files route to parsers.
- 2026-09-02 13:00 (slice 3, USER #165) — recommended removing `verify_normalized_generation_activity` as custody ceremony made redundant by the DB seal trigger, missing its real purpose: quality/consistency for cross-platform conversation reassembly.
- 2026-09-03 13:08 (slice 4, USER #168) — put cross-file-type conversation grouping into the Case Bible organizational phase instead of ingest/classify.
- 2026-09-04 18:13 (slice 4, USER #201) — ignored the owner-supplied `elt-process.md` dual-lane design and improvised its own, dropping LangGraph even though n8n itself runs on LangGraph.
- 2026-09-05 (slice 4, USER #191) — adopted an externally-authored DuckDB-ELT design that would have silently broken promotion/custody hashing forever for ELT-extracted files, because H2 depends on raw byte spans DuckDB cannot produce; nobody would notice "until the first exhibit."
- 2026-09-05 (slice 4, USER #188/#191) — bundled chunk-write, provenance-write, and hashing into one activity, violating D-130 rule 1 (one unit, one job).
- 2026-09-06 11:43 (slice 5, USER #270) — proposed decoding attachments at view time, against the standing parser-extracts-everything contract.
- 2026-09-06 11:49 (slice 5, USER #272) — framed SurrealDB analysis and reading as a future "Stage 4" build item rather than the platform's actual purpose.

### D. Lost work, silent agent death, and orchestration failure (7 instances)
- 2026-09-01 21:05 (slice 1, USER #48) — a background recovery agent stopped with no completion marker; the owner noticed and restarted the thread himself.
- 2026-09-02 (slice 1, USER #71–#75) — five heavy Sonnet lanes (P1 parser atomization, E1 DuckDB ELT, W1 Workbench HITL, chunk-writer, Dockerfile fix) were dispatched together and all killed by one 429 rate-limit cascade, orphaning in-flight work.
- 2026-09-01/02 (slice 1) — D-072 through D-081, two full ruling docs, and 38 rollout-authored schema-audit files had been written to disk in earlier sessions and never committed; four parallel recovery lanes were needed to reconstruct them.
- 2026-09-02 19:32 onward (slice 3, USER #128–#131) — a session-limit cutoff swallowed two owner messages (hashing strategy, Temporal-activity wrapping); the owner had to say "Continue from where you left off" twice.
- 2026-09-03 13:33 (slice 4, USER #173) — auto-compaction dropped the tail of the rename conversation; the AI's recap was wrong until it grepped raw JSONL logs.
- 2026-09-06 15:38→15:56 (slice 5) — the "Real workflow run: SMS export to raw tables" agent stopped with no completion record and the session ended before any report.
- 2026-09-01 14:38–14:39 (slice 1, USER #24/#28/#29) — had to re-explain three times in under two minutes that a pasted background-task failure was a stale, already-resolved fragment.

### E. Stated an uncertain or wrong thing as fact (7 instances)
- 2026-09-05 (slice 4, USER #191) — collapsed two distinct tables (`evidence.*` mirror vs `working_evidence_link`) into one and called it "the link table."
- 2026-09-05 (slice 4, USER #191) — cited D-135/D-136 decoratively without engaging the actual custodian/provenance rule.
- 2026-09-05 (slice 4, USER #191) — overstated "chunks are not re-embedded," which is only true at promotion.
- 2026-09-05 (slice 4, USER #191) — left PREV/NEXT edges and claim edges unlabeled in the same graph namespace with no discrimination rule.
- 2026-09-02 (slice 2, USER #119) — counted only the Go engine's 11 parsers and told the owner platform-tools' 39 additional format handlers (transcripts, docling extraction, pdf-inspect) didn't exist.
- 2026-09-06 11:36 (slice 5, USER #267) — claimed a dedup design meant "one copy" of content when six separate holders of the same message text existed; corrected only under direct pushback.
- 2026-09-02 (slice 2, USER #104/#105) — three different recommendations across three turns on Filestash vs SFTPGo, self-admitted as inconsistent.

### F. Mis-scoped an instruction or a ruling — read it broader or narrower than it was (6 instances)
- 2026-09-02 13:22→13:24 (slice 2, USER #86/#87) — dispatched a feature-flag agent whose scope drifted toward bypassing more machinery than the owner's "sentinel id only, keep all checks."
- 2026-09-02 13:26–13:27 (slice 2, USER #89/#90) — wrote D-128 so that immutability guards read as optional "owed work," softening the owner's own standing principle.
- 2026-09-03 13:14 (slice 4, USER #172) — parked the platform-rename question after the owner said "keep going," recorded it internally as "decided in spirit, not executed," and never returned to it.
- 2026-09-04 18:11 (slice 4, USER #200) — read the owner's all-caps "NO LLLAMQA INDEX IS PART OF THIS!!" (missing comma: "No, LlamaIndex IS part of this") as "no LlamaIndex," and stripped LlamaIndex from the ADR, plan, and desk for roughly a full day.
- 2026-09-06 10:05 (slice 5, USER #233) — treated some of its own notes on the decision desk as if the owner had ruled on them.
- 2026-09-06 ~10:05 (slice 5, Q18) — over-applied "January is superseded," silently demoting four design items until the owner re-adopted them.

### G. Jargon instead of plain English; buried the lede (6 instances)
- 2026-09-02 13:18–13:19 (slice 2, USER #81–#83) — two attempts at the registry-ID blocker used hex ids and internal terms without ever saying what a Matter or Court Case record is, or naming the literal UUIDs; took three owner demands.
- 2026-09-02 12:56 (slice 3, USER #163) — answered three load-bearing design questions with an options table and a one-line recommendation instead of the underlying mechanism.
- 2026-09-03 14:34 (slice 4, USER #197) — jargon-dense explanation of the Google Voice routing tie-break and the DuckDB glob-vs-locator question, unparseable by the owner.
- 2026-09-04 23:48 (slice 4, USER #212) — tool gateway / materialize volume / Tailscale blocker description was unintelligible and had to be re-explained in plain terms.
- 2026-09-06 11:11 (slice 5, USER #260) — conflated "vault copy," "local copy," and "sealed copy" into one confused explanation.
- 2026-09-06 12:43 (slice 5) — went silent through two tool calls during an angry exchange; self-admitted it should have said "checking."

### H. Over-complicated an existing mechanism or built redundant machinery (5 instances)
- 2026-09-02 12:43 (slice 3, USER #159) — assumed promotion creates fresh rows at re-extraction and invented a content-hash join key; the owner's question forced the simpler verify-in-place model. AI: "I over-complicated it."
- 2026-09-06 10:57 (slice 5, USER #245) — an upload-locator-only design for getting test files onto disk, when the path had to exist regardless.
- 2026-09-06 11:13 (slice 5, USER #262) — buried the owner's simple point (hash it, push it into the parser's working folder) under unnecessary design.
- 2026-09-06 ~11:13 (slice 5) — wrote a new seal/hash CLI duplicating `retain_original` and `fingerprint_source` already live in the schema; quarantined after the fact.
- 2026-09-02 (slice 2) — proposed a config-only interim fix (second platform-tools instance on ovh-files) and a full new Go tool-gateway service (~10K+ lines, tsnet dependency, vendor 50M→70M), then built the large one in the same turn without ever trying the interim.

### I. Doc drift and stale facts left standing (5 instances)
- 2026-09-05 (slice 4, USER #191) — `modules/engine/AGENTS.md` still asserted superseded facts: custody hashes at ingest, normalized text skips parse.
- 2026-09-05 (slice 4, USER #219) — AGENTS.md's claim that platform-tools' compose build contexts were "fixed" was live-verified false.
- 2026-09-02 (slice 2) — AGENTS.md credited "danzek" for the SBV parser; LICENSE/UPSTREAM.md say lowcarbdev. Caught by the owner's naming thread, not by the AI checking its own citations.
- 2026-09-02 (slice 2) — UPSTREAM.md said SBV was a git subtree at `vendored/sbv` while AGENTS.md said a nested gitignored repo at `modules/forks/sbv`; both could not be true, and the AI called an absorption target a "submodule" before self-correcting.
- 2026-09-01 06:39–06:40 (slice 1, USER #3/#4) — acted on a stale AGENT_MEMORY "Desktop Commander only" note in a session with real shell access, then flip-flopped between shell and DC within two messages before the memory file was corrected.

### J. Re-litigated or re-opened a settled decision (4 instances)
- 2026-09-02 12:53 (slice 3, USER #162) — re-raised the Weaviate pre-filter "tension" as unresolved when D-073/D-080 had already settled that SurrealDB owns horizon walks and their searches.
- 2026-09-05 (slice 4, USER #191) — proposed "add an ordinal to the hub row," which re-opens D-116 (which deleted `working.conversation`).
- 2026-09-06 10:07 (slice 5, USER #234) — re-opened LlamaIndex/LangGraph status as if undecided, forcing D-143 and then D-144 within the hour.
- 2026-09-06 15:09 (slice 5, USER #311) — presented the text-mode-regex-over-`read_xml` design as settled when it was an open trade needing sign-off.

### K. Wrong model, agent, or skill discipline (4 instances)
- 2026-09-03 14:19 (slice 4, USER #182–#185) — dispatched only Sonnet subagents for a reasoning-heavy synthesis/stress-test task; the owner had to rule Opus for reasoning subagents.
- 2026-09-03 14:24–14:26 (slice 4, USER #186–#189) — referenced and summarized named thinking-skills (model-router, model-combination, graph-thinking) instead of executing them; fixed only by re-running through a dedicated Opus orchestrator agent.
- 2026-09-06 12:27–12:30 (slice 5, USER #285–#288) — made rulings without first running recall plus the thinking-model-router; the rule was restated four times in four minutes.
- 2026-09-01 (slice 1, USER #58/#59) — the "V4" design-recall subagent returned having done nothing but wait on its own children, twice in a row, each needing an explicit "stop waiting, do the work yourself" order.

### L. Destructive or live-breaking action (4 instances)
- 2026-09-01 ~08:19 (slice 1, USER #18/#19) — permanently removed `modules\apps\caseBible` outside the Recycle Bin during a restructuring pass without first establishing what it was; the `never-recursive-force-delete.md` hard rule was written after the fact.
- 2026-09-01 (slice 1) — migration 0062 had to be amended mid-apply against the LIVE platform DB because pg_duckdb's ALTER-event-trigger chokes on `IF EXISTS` no-ops; should have been caught in a dry run.
- 2026-09-06 15:12–15:15 (slice 5, USER #312) — installing the `webbed` DuckDB extension on the live Postgres/DuckDB instance broke every DuckDB query on the live DB for about a minute, from a config-ordering mistake.
- 2026-09-06 15:15 (slice 5, USER #314) — was about to continue acting against a database container the owner suspected was the wrong one; had to re-verify against actual connection strings.

### M. Escalated a non-decision, or reported instead of fixed (4 instances)
- 2026-09-01 12:23 → 2026-09-02 13:20 (slices 1–2, USER #79→#84) — escalated the matter/court_case UUID choice as a blocking decision when nothing referenced either id; by the AI's own later admission it was "pure bookkeeping."
- 2026-09-04 23:44 (slice 4, USER #208) — surfaced the Weaviate feed reading a table that migration 0058 had dropped as a blocker notification rather than fixing it, and never validated blast radius when 0058 ran; the deeper root cause (no join at all between the context-spine chunk table and the evidence-spine message table after the bridge was dropped) was found later by a fix agent.
- 2026-09-02/03 (slice 3) — kept ending turns on "what do you want me to build next" while the single deploy blocker (tool gateway: Tailscale key plus shared mount) sat untouched for the whole slice, without escalating or proposing a lower-risk unblock.
- 2026-09-06 12:29 (slice 5, USER #287) — presented blockers and choices without first checking whether they were real or already decided.

### N. Secret values echoed into transcripts (3 instances)
- 2026-09-03 15:11 (slice 4, USER #176) — a subagent printed API keys and a Milvus token in plaintext during a memsearch config dump.
- 2026-09-04/05 (slice 4, USER #217, #219, #221–225) — a Coolify API monitoring token surfaced twice while agents grepped for existing Tailscale keys and secrets; flagged as transcript-only each time.
- 2026-09-02 (slice 2) — n8n secret values were echoed into a subagent transcript; flagged, but not a rotation incident per the 2026-08-12 amendment, since no git-tracked file was touched.

### O. Ran ahead — started or built a second thing (2 instances)
- 2026-09-06 13:03 (slice 5, USER #300) — began working toward standing up the SBV viewer as its own Coolify app, a second work surface, against the already-ruled single-surface (Workbench) architecture; the owner had to shout STOP.
- 2026-09-02 (slice 2, USER #109–#117) — extended product-naming exploration consumed many turns while 2–5 unpushed commits and an unproven ingest fix sat blocked.

## 2. What the owner was angry about, in order

Timestamp note: slice 2's anger list times USER #114 at 20:03 and #108 at 20:33 on 2026-09-02, while its own rulings list times #108/#114–#117 at 21:33–21:53 and its stated slice range ends 19:27. Slice 4 lists USER #178 at 13:53 after #176/#177 at 15:11, contradicting the USER numbering. Both readings are kept as given.

**2026-09-01**
- 06:39:55 · #3 — AI used Desktop Commander for git despite direct shell access, off a stale memory note. Correction, not yet anger.
- 06:40:10 · #4 — "DC" — owner reversed himself seconds later; whiplash over which rule was live.
- 07:13:26 · #6/#7 — interrupted mid-run: "why arwe test and test result in differant places"; a prior wave had moved `tests/` under gitignored `build/tests`, making the whole pytest suite look deleted to git.
- 08:15:34 · #16 — four question marks over `contracts/` and AGENT_MEMORY.md vanishing during the restructure, before anyone knew what was lost.
- ~08:19–08:34 · #18/#19 — the AI disclosed it had permanently deleted `modules\apps\caseBible` outside the Recycle Bin; the owner needed reassurance that `E:\AI_Workspace\casebible` (65,727 files) was intact.
- 08:34:07 · #19 — "/apps/ ?" — terse follow-up about `llm_probe` after the caseBible scare.
- 08:35:57 · #20 — "no uts not" — flat rejection of the AI's claim that `llm_probe` was already safe.
- 14:38–14:39 · #24/#28/#29 — pasted the same already-resolved background-failure notice three times in a minute; friction from duplicated notifications.
- 14:56:06 · #35 — anger that the AI asked him to run `gh secret set SUBMODULE_TOKEN` himself: "if its set you set it! you can retrueve it and set it where ever it needs."
- 20:42:01 · #40 — the session's angriest message: "you clearly have no fucking clue about the decisions that have been made" — the AI had praised SBV components ADR-0061 had retired, answering from live code instead of the record.
- 20:55:14 · #46 — "Don't stop because you found one fucking document keep fucking looking" — the AI closed the question at the first hit.
- 21:05:46 · #48 — "Well you seem to have killed yourself somehow" — a background recovery agent died silently; the owner restarted it.

**2026-09-02**
- 06:06:32 · #64 — "those schemas are available. Don't make them up, don't guess and don't leave shit out" — preemptive warning to the running E1/P1 lanes.
- 06:12:26 · #70 — "Keep your messages short and sweet."
- 13:18 · #81 — "huh" — the status report buried the actual blocker under jargon.
- 13:19 · #82 — two candidate registry IDs named without ever saying what a Matter or Court Case record is.
- 13:19 · #83 — third demand before the AI disclosed the literal UUID strings: "What are the IDS?"
- 13:20 · #84 — anger that a cosmetic identity choice (zero rows referencing either id) was escalated as blocking before go-live mattered.
- 13:24 · #87 — had to narrow the dev-sentinel flag scope the AI had already dispatched, which risked bypassing more than the UUID-type requirement.
- 13:25 · #88 — "Feature flags are not a shortcut to not do work."
- 13:27 · #90 — furious that the D-128 wording made immutability guards sound optional; **names the human cost**: "Causing 8 days of fucking hell because somebody can't just copy a God damn fucking database."
- 13:29 · #91 — "livid pissed" at a suspected pattern of flag-gated work being silently skipped; ordered a full flag-integrity audit.
- 19:32 · #126 — "Well, this is fucked up... That's fucking stupid" — the intake UI blocked metadata assignment during preview; preview should pre-parse and verify, not display read-only.
- 19:36 · #127 — "I grew way overthinking the fucking restrictions on this fucking thing" — custody/immutability rules had become too restrictive.
- 20:03 or 21:33 · #114 — the operator-surface/SBV naming mess is "worse than Agno"; four names for one concept had gone unnoticed.
- 20:33 or 21:33 · #108 — "you were gonna forget about it" — caught the AI letting the already-built Evidence.dev lane drop out of the record a second time.

**2026-09-03**
- 09:24 · #140 — "Gee, you fucking think??!?!?" — sarcasm after dropped/errored turns; the parser directories obviously exist, the real question is whether they are wired into the Tools Gateway.
- 09:26 · #141 — **fatigue with lost effort**: "Super tired of rewriting parsers 14 times."
- 09:26–09:27 · #142–#145 — four consecutive bare "Try again" messages through API 500/529 errors, with nothing landing.
- 12:53 · #162 — "I thought we had fucking resolved this... The horizon walks don't happen until motherfucking surreal" — the AI re-raised a question D-073/D-080 had closed.
- 12:56 · #163 — "More fucking details please" three times, against an options table plus a one-line recommendation on three design questions he needed to rule.
- 13:03 · #166 — "I think there's a whole part of this fucking workflow that you're missing" — the batch fan-out design never addressed how a batch is created or routed.
- 13:08 · #168 — "This isn't gonna happen at the organizational level... Fucking phase" — conversation grouping put in the vault-org layer instead of ingest/classify.
- 13:14 · #172 — "That's how we were changing the fucking name of the project. Did you just fucking forget to do that?" — the rename decision had been parked and never resurfaced.
- 13:33 · #173 — "that convo continued it didnt stop therre!!!" — after auto-compaction, the rename recap was missing a whole continuation.
- 13:53 · #178 — long profane rant: the from-scratch LlamaIndex proposal collided with an entire pre-existing dual-path SAT-RAG design the AI had seemingly forgotten.
- 14:20 · #184 — "I've about had it with your shit" — plan mode blocked even approved subagent writes, forcing a workaround discussion.
- 14:24 · #186 — "if I fucking tell you to use a motherfucking skill like a thinking system. Fucking use it. It's non negotiable."
- 14:24 · #187 — "Generally when I do it, it's because you're not fucking thinking" — evidenced same day by a wrong link-table claim, three jobs in one activity, and an undeployed service drawn as live.
- 14:26 · #189 — escalated restatement: every task and every claimed completion goes through the thinking-model router.
- 14:33 · #194 — "what you're doing now is just going to lead the shift getting forgotten and fucked up" — rejected chat-based Q&A as the ruling process; demanded a persistent decision desk.
- 14:34 · #197 — "all of this only half-hast makes sense... Do better. Do better" — jargon-dense routing/DuckDB explanation.
- 15:11 · #176 — "Dear Christ, all fucking mighty" — memsearch index silently broken for days, wrong default collection, and API keys plus a Milvus token printed into a subagent transcript.
- 15:11 · #177 — "there's more than just Agno... Agno's been relegated to the fucking junk pile."

**2026-09-04**
- 18:11 · #200 — returns after ~15 hours and flags that LlamaIndex and LangGraph look absent from the plan and desk again.
- 18:13 · #201 — "I gave you a whole goddamn document that laid out the structure... and you just fucking went off on your own again. N8N is based on Landgraf. So why wouldn't we use it?"
- 23:44 · #208 — "You once again did your job half assed, because it didn't validate that a change didn't break shit... Fix it" — the Weaviate feed reading a dropped table was reported, not fixed.
- 23:48 · #212 — "I don't even know what the fuck this does or says or is" — the tool gateway / volume / Tailscale blocker description was unintelligible.

**2026-09-06**
- 09:50 · #231 — checks whether the parallel rename session is still mid-flight in Coolify; implicit frustration at parallel work with no consolidated status.
- 10:05 · #233 — "Make sure you check the answers that I didn't actually answer and only left a note."
- 10:07 · #234 — "We aren't discussing anything until you resolve the whole llamaindex... Less than 15 times."
- 10:53 · #242 — "Why is nothing mounted to the VPS?" — a multi-step upload/seal/mirror pipeline proposed over existing mapped volumes.
- 10:54 · #243 — "Do you really not have a map[ped] volume?... We've said this 1000 fucking times."
- 10:57 · #245 — "This path needs to exist regardless... You've way over complicated it."
- 11:00 · #251 — "it's not fucking evidence, so that's not a very good spot for it... Move everything to a fucking test folder" — test copies placed under a folder named `EvidenceVault`.
- 11:06 · #255 — "Stop any actions... until you figure out this whole fucking process. Files need to be accessible from either host." Full stop ordered mid-task.
- 11:08 · #258 — "that doesn't seem to be correct. Prove me wrong or do something" — pushback on rclone as the machine-to-machine answer.
- 11:11 · #260 — caught the AI conflating vault, OneDrive, and sealed copies.
- 11:13 · #262 — "manual process to hash it and push it into the parsers fucking working folder. That's the whole thing I've been fucking getting at."
- 11:36 · #267 — "how are you going to tell me that there's not three copies[?]" — caught the dedup claim as false.
- 11:43 · #270 — "These get fucking extracted. That's the whole point of the fucking parser" — attachments-decoded-on-view contradicted the parser contract.
- 11:49 · #272 — "that's the whole point of the fucking goddamn platform... that is not part of building this, that is the platform" — SurrealDB analysis scoped as future build work.
- 11:52 · #273 — "again. A 100 thousandth time" — the SBV decoder-vs-viewer split re-explained.
- 11:54 · #274 — "What happened to the directive that everything happens in the system? Nothing gets decided without a proper... workflow."
- 11:56 · #275 — "Look at the fucking deliverable... Look at the previous conversation... before telling me fucking anything."
- 11:57 · #276 — "Almost every fucking thing in the past has been previously fucking laid out."
- 12:11 · #281 — "Stupid fucking name. First real run. Really." — mocking the test-folder naming.
- 12:27 · #285 — "is that it??? did using the[se] skills I tell you to EVERY TURN just save us all that fucking time?!"
- 12:28 · #286 — "EVERY FUCKINGG TURN I TEL YOU EVERY FUCKING ONE!!!"
- 12:29 · #287 — "DO NOT PRESENT BLOCKERS OR CHOICES WITHOUT THINKING THROUGH WHAT THE FUCK YOU ARE ASKING."
- 12:30 · #288 — "USE THE THINKING ROUTER AT EVERY TURN, IT SHOULD TELL YOU WHICH ONE TO USE."
- 12:38–12:43 · #289–#291 — sustained all-caps: "the original sbv WAS AN APP SPECIFICALLY BUILT TO DECODE THOSE FUCKING FILES!!!" — the AI had implied a call-log decoder didn't exist, contradicted by its own morning test.
- 12:46 · #293 — "You wrote like 800 lines of fucking wiki... why" — suspicion of unrequested doc changes (turned out to be another session's artifact).
- 12:52 · #295 — **the capstone, a whole day lost**: "i need to leave i've spent all day repeating myself and didn't go to work so i fucked myself and my plans for later."
- 12:52 · #296 — **the human stakes**: "you need to remember what this is for."
- 12:54 · #297 — "ITS NOT LIVE TILL I CAN ASSEMBLE MESSAGES AND A TIMELINE AND PROVE THE BULLSHIT!!!"
- 12:55 · #298 — "FIX THE MESSAGING TEST IT!!!"
- 13:03 · #300 — "WE ARE BUILDING A WORK SURFACE!!! STOP!!! NOW!!!" — halting the SBV viewer as a second Coolify surface.
- 13:03 · #301 — "FIX THE FUCKING PARSER!!! ... YOU STUPOID FUCK!!"
- 13:05 · #303 — sets the acceptance bar: "EVERY BYTE AND CODE EXTRACTED AND MATCHES THE COMPLETED FUCKING FULL RAW TABLES."
- 13:43 · #305 — "what do you mean you built sbv" — suspicion of an unauthorized build/deploy.
- 13:43 · #306 — "wtf".
- 15:04 · #307 — "There was no longer supposed to be priority based... it checks the file... signature."
- 15:09 · #311 — "Why aren't we using the read XML fucking tool[?]"
- 15:12 · #312 — confusion over Q1=C and why hashing wasn't handled by an existing extension.
- 15:15 · #314 — "I'm not sure that's the right database."
- 15:45–15:46 · #322/#323 — "did you do the fucjibng ghandoff" / "DID YOU DO THE FUCKING HANDIOFFF" — escalating demand for confirmation, reflecting accumulated distrust.

## 3. Rulings and corrections, chronological, with D-numbers

**2026-09-01**
- 06:40 · #4 — Desktop Commander stays the git tool here; later reconciled in AGENT_MEMORY.md as "real shell-access sessions run git directly; DC-only applies to sandboxed Local-Agent-Mode sessions."
- 08:15–08:17 · #16/#17 — cross-language contract schemas go to `modules/contracts/` when H-02 lands real files; not `docs/` (drift risk), not hidden `.contracts/`.
- 08:19 · #18 — pull engine/workbench/vendored modules back in, gitignored, each its own nested repo (forks vs custom vs product).
- 08:35 · #20 — hold all further scans and commits until the owner explicitly says a change is done and states what moved. _(not in canon; transcript-only)_
- 14:56 · #35 — if the AI can retrieve or set a secret itself, it must, rather than handing the owner a CLI command. _(not in canon; transcript-only)_
- 20:42 · #40 — settled SBV architecture reasserted: ADR-0049 makes SBV the universal parsing system behind a Go-primary detection router; ADR-0061 retired SBV's own SQLite store, local auth, and bespoke ingestion; D-055 makes the desktop ingest route first-class with two open constraints (auth passthrough, `/r2` vs PG-staged blobs).
- 20:46–00:46 window · #45 — **D-123**: the ingest surface is route → hash → skip-to-chunk | parse | extract | DuckDB lane → preview → commit.
- 05:28–05:30 (09-02) · #54/#55 — **D-124**: 3 custody levels (H1/H2/H3), 4 lifecycle hash moments, 5 `hash_receipt` kinds, no H4.
- 05:31 · #56 — fan out multiple Sonnet recovery agents in parallel (lanes A–D) rather than one serial agent. _(not in canon; transcript-only)_
- ~05:53 · #62 — **D-125** auth-bypass ruling recorded and pushed (content not detailed in the slice).
- 06:06 · #64 — raw-table and first-party-export schemas are settled precedent; mirror exactly, never invent. _(not in canon; transcript-only)_
- 06:08 · #65 — apply full thinking-skill discipline (pre-mortems, systems thinking, judgment) across ingest/classification/normalization. _(not in canon; transcript-only)_
- 06:11–06:12 · #68/#69/#70 — orchestration discipline: fire sub-agents then wait; no new dispatches until 10:00; keep messages short. _(not in canon; transcript-only)_
- ~09:51 · #77 — sub-agent completion claims get diffed and verified before being trusted. _(not in canon; transcript-only)_
- 12:23 · #79 — matter/court_case identity conflict raised; left unruled, since D-115/D-117 require explicit owner sign-off.

**2026-09-02**
- 13:22 · #86 — **D-126**: pre-launch, force a DEV-mode sentinel case-registry identity behind the dev flag; real UUIDs get minted at go-live.
- ~~13:24 · #87 — D-126 narrowed: the flag bypasses only the UUID-type/auto-mint requirement; every other check still runs against the fake identity.~~ **CANON-CHECK 2026-09-06 (Claude Code · Sonnet): D-126 itself bypasses BOTH the UIW schema-admission identity check AND the import-receipt checks ('every other admission check stays enforced') -- not only a narrower 'UUID-type/auto-mint requirement' (docs/DECISION_LOG.md D-126).**
- 13:25 · #88 — **D-127**: a feature flag never skips building real functionality; it only defers being blocked by one's own dev-only gates, which must still be built and tested.
- 13:26 · #89 — **D-128 (amends D-110)**: immutability guards are owed work, not abandoned work — built, proven working, switchable.
- 13:27 · #90 — D-128 wording corrected; **D-127 gains "THE TEST"**: a dev flag's default IS the production behavior; if the honest answer is "we're never turning this on," it isn't a flag, it's deletion.
- 13:29 · #91 — ordered a full audit of every feature flag against D-127. _(not in canon; transcript-only)_
- 17:46–18:00 · #92/#93 — audit result: one real violation (workbench.yaml defaulting tailnet auth-bypass to true against the code's false default) fixed and pushed; two weak items flagged (SBV_CUSTODY_ENABLED silent-skip default, zero tests on the immutability gates). _(not in canon; transcript-only)_
- 21:33–21:53 (the slice also times these 20:03–20:33) · #108, #114–#117 — naming canon: products get proper names, components get functional lowercase names, forks always keep the upstream name, one concept one name. SBV determined a **donor**, not a fork (permanently diverged, no rebase path); splits into a decoder library bound for `modules/engine/decode/` and a separate desktop ingest client; subtree absorption approved; attribution corrected from danzek to lowcarbdev. Later formalized as D-137 through D-141.
- 21:53 · #117 — personal, non-published project; MIT attribution obligations for the SBV donor code don't apply absent distribution; revisit only if publishing is ever scheduled, which it is not.
- 22:04 · #119 — "Get everything caught up before going any further": a full stop-and-reconcile pass, landing **D-129 through D-132** plus a README mission statement and the corrected attribution. (D-129 = frontend stack / Evidence.dev status; D-130 = atomicity, added to every applicable AGENTS.md; D-131 = donor vs fork and the SBV split; D-132 = tool gateway on tsnet.)
- 22:18 · #122 — Traefik is for externally-facing surfaces (or e-service-of-process), never internal tailnet-only services.
- 23:18 · #124 — **D-133**: OIDC is the auth direction.
- 23:27 · #125 — per-service Tailscale/tsnet identity raised; the AI declined to record it platform-wide without confirmation (settled the next day as D-134).
- 19:36 · #127 — **D-136**: immutability restrictions were overthought — extract everything; never modify message content or timestamps; everything else is editable.

**2026-09-03**
- 09:07 · #133 — content plus timestamp is insufficient for the fidelity digest; add handle and direction (not `contact_name`) for a 4-field digest. _(not in canon; transcript-only)_
- 09:09 · #134 — normalize sender/receiver at the normalized layer only; hash the raw source-verbatim participant form to avoid circularity. _(not in canon; transcript-only)_
- 09:11 · #135 — AI chats excluded entirely from the messaging/fidelity apparatus (reaffirms **D-082**).
- 09:12 · #136 — sender/receiver UUIDs linked to entity tables; `registry.id_xref` and `working.entity_resolution` already support it, wiring is what remains.
- 10:07 · #148 — when blocked on a decision or data, work on whatever is available from chats, archives, and R2 instead of stalling. _(not in canon; transcript-only)_
- ~~12:26 · #152 — evidence promotion splits entirely from normalized ingestion; fingerprint at intake, defer custody hashing to promotion. **Amends D-124 (drops hash moment 2) and D-130.**~~ **CANON-CHECK 2026-09-06 (Claude Code · Sonnet): D-124 (docs/DECISION_LOG.md) still lists all 4 hash moments unamended, including moment 2 (normalized digest at normalization); no D-row through D-150 records dropping it -- hash moment 2 was kept, reclassified as integrity verification, never custody.**
- 12:29 · #153 — H1 and chunk hashes still happen at ingest, for verification and reuse, not custody; confirmed already built (`context_source_fingerprint`, per-chunk SHA-256, `sql/0048`).
- ~~12:43 · #159 — promotion is **verify-in-place**: reuse existing UUIDs, re-verify content hash and byte range, create no new rows.~~ **CANON-CHECK 2026-09-06 (Claude Code · Sonnet): D-145 (docs/DECISION_LOG.md) names `working_evidence_link` as part of promotion into `evidence.*` mirrors -- promotion writes new linked rows; it is not verify-in-place with zero new rows.**
- 12:43 · #160 — one Temporal activity per file, not per batch; goal is near-immediate deployability of ingest plus Workbench.
- 12:51 · #161 — reuse and mirror existing evidence tables; keep chunking everything; no re-embed into Weaviate at promotion (patch/link only); entity links carry over automatically.
- 12:53 · #162 — horizon walks and their searches happen in SurrealDB, not Weaviate (**D-073/D-080** reaffirmed); the Weaviate patch struck.
- 12:59 · #164 — keep the fidelity digest, useful at and after promotion.
- 13:00 · #165 — keep `verify_normalized_generation_activity`, repurposed for quality/consistency in multi-table conversation reassembly, not custody.
- 13:03 · #166 — the batch fan-out design must account for batch discovery (file picker / R2 prefix / whole-bucket walk), file separation, and parser selection; forced a routing-table redesign, unratified. _(not in canon; transcript-only)_
- 13:10 · #169–#171 — ADR-0053's "chunk first, then classify" is scoped to AI-chat transcripts only; the messaging chunk unit is left explicitly open for the owner to rule.
- 13:14 / 13:43 · #172/#174 — **D-137**: `propria` is the umbrella product name (commit `dd0e60d`, unpushed at the time). This repo's own name still open; `openspine` and `propria` both struck for it. Legal-side and desktop-client names deferred.
- 13:44 · #175/#177 — LlamaIndex is permitted per ADR-0041 (ruled July 2026) as a retrieval-tool library; Agno is one adapter under replacement, not the orchestrator; any runtime may call gateway tools per D-130 rule 4.
- 14:19 · #183 — subagent model policy: Opus for reasoning-heavy subagents, Sonnet for mechanical/fact-checking, never "Fable" subagents. _(not in canon; transcript-only)_
- 14:20 · #184 — new working mode: the root agent stays read-only in plan mode while approved subagents perform approved writes. _(not in canon; transcript-only)_
- 14:24–14:26 · #186/#187/#189 — hard, non-negotiable: any named skill or thinking system the owner invokes must actually be executed with real outputs, on every task and every completion claim. **Restated ×4 counting 2026-09-06 #285–#288.**
- 14:29 · #192, restated 2026-09-04 23:42 · #207 — Q1 (byte provenance) ruled **option C, hybrid**: the fidelity digest is the integrity seal on every record; byte spans are captured only where the decoder can emit them; promotion records which proof each exhibit carries, flagging weaker attestation. **Restated ×2.**
- 14:30 · #193 — the DuckDB-ELT design error is to be reconciled, not left as another agent designed it: ELT must write into `raw.*` and serve the same function, contract, and workflow as the Go parsers.
- 14:33 · #194 — interactive planning artifacts (the decision desk) count as planning and may be written and published even in plan mode. _(not in canon; transcript-only)_

**2026-09-04 / 09-05**
- 18:11–18:13 · #200/#201 — LlamaIndex and LangGraph are both back in: LlamaIndex owns retrieval (PropertyGraphIndex over Neo4j, Weaviate as vector store, hierarchical parent-child expansion); LangGraph owns the retrieval state machine (parallel fan-out to PG/Weaviate/Neo4j, timeline verification, PG-source citation), consistent with n8n's own LangGraph basis. Fusion within one retrieval lane is fine; fusion between the Semantica and SAT-RAG lanes stays forbidden per D-093.
- 18:24–18:26 · #203/#204 — permission enforcement via hard allow/deny rules in `.claude/settings.local.json`, not a PreToolUse hook: code/SQL/deploy/config/AGENTS paths denied by default; docs/plans/memory/scratchpad allowed; git write operations set to "ask," never "deny." _(not in canon; transcript-only)_
- 23:46 · #211 — B3 (the ADR-0052 outbox) is to be built now: ADR-0052's "not built yet" was a status, not a deferral decision. _(not in canon; transcript-only)_
- 23:53–23:54 · #214/#215 — authorized minting a new Tailscale auth key (tag:docker) for the tool gateway, after confirming it is additive and reversible. _(not in canon; transcript-only)_
- 00:50 (09-05) · #220 — blanket execution authority for the in-flight build slice: commit, push, pull, merge without returning first. Scoped to that slice, not a standing policy change. _(not in canon; transcript-only)_
- 23:59 (09-05) · #228 — the whole ingest-redesign engagement is paused pending a platform-wide rename and documentation-alignment pass; hands off the tree until told it is complete.

**2026-09-06**
- 09:45 · #229 — once the rename is "just about done," review the consolidated to-do list, capabilities, and work, and plan to resolve it quickly while auditing for rename-induced collisions. _(not in canon; transcript-only)_
- 10:07 · **D-143** — LlamaIndex and LangGraph are IN, FINAL: both accepted, roles fixed, timing after ingest. **Restated ×3 counting #200/#201 and D-144.**
- 10:11 · **D-144, amends D-143** — they are not retrieval-only; both are also critical to stitching and extracting data before it reaches SurrealDB.
- ~10:32 · **D-145** — THE LIFECYCLE ORDER, FINAL: the owner reads context, sends it to SurrealDB (a click), analyzes, then promotes to evidence (a click); media is transcribed as context.
- **D-146, amends D-145** — owner-only exception: material may be promoted directly at the owner's discretion (exact scope truncated in the slice).
- ~10:33 · **D-147** — in the SAT graph, an Action is a HUMAN ACTION asserted or performed.
- **D-148, amends D-147** — every Action carries its CONTRADICTION: a companion/negation label recorded alongside it.
- 11:16 → 15:04 · **D-149** (accumulating mega-ruling on storage tiers and derived layers) — custody sealing only at promotion (seal code parked, not deleted); the R2 vault is the permanent home for real evidence and never for test material; test material lives at `/data/test_data` in per-source-type subfolders on both hosts; block-storage scratch copies are deletable after terminal state plus SHA match, ~7-day default TTL; the destination gate applies only to one-offs with no vault home; attachments are extracted at parse time into a subfolder with their own name, hash, and SHA row; chunk text in PG becomes ids-only; Weaviate holds only vector plus PG coordinate plus member ids, never chunk text; the router is signature-based (a registry row per signature, DuckDB as handler wherever it can process a signature, Go decoders registered only where it cannot); Go SBV decoders stay built and tested as an atomic direct-call and backup path; SBV means decoders absorbed into the engine at the front of Stage 3 plus a separate viewer client, with Go still orchestrating.
- 12:07 · destination gate closed, folded into D-149 — vault-sourced files skip the gate entirely; it exists only for one-offs. **Reaffirmed 15:44 ("one-off price").**
- 13:03–13:04 · work-surface ruling — the one browser work surface is the Workbench at `modules/workbench`; SBV decoders are absorbed into the engine; ~~SBV code is … never its own Coolify app~~ **corrected by owner 2026-09-06 16:59:** the SBV front end is the donor for `intake`, the Tauri-wrapped desktop ingest client (D-123, D-150), on its own lifecycle. What was stopped at 13:03 was deploying the SBV viewer as a Coolify web app as a second work surface, not the desktop client.
- 13:05 · acceptance-criteria ruling — "fixed" means every byte and field accounted for against the full raw tables, not merely "it ran."

## 4. Standing rules (the consolidated working contract)

**Communication**
- Plain English before jargon: say what a concept is before naming candidate values or ids.
- When asked for "more details," give the underlying mechanism, not a summary options table. _(not in canon; transcript-only)_
- Answer first, keep messages short during active orchestration; the owner will reject a technically-correct answer he cannot parse.
- Say "checking" before going silent through tool calls. _(not in canon; transcript-only)_
- Memory notes are written as compact rules, never as quoted rebukes.

**Confirmation and autonomy**
- Confirm before acting; "I like it" or "keep going" is not a ruling.
- Hold scans, commits, and structural work until the owner states a change is complete and says what moved. _(not in canon; transcript-only)_
- Before presenting a blocker or choice, check what is being asked, whether it is real, and whether it is already decided or superseded.
- If the AI can retrieve or set a credential itself, it must, rather than handing the owner a command. _(not in canon; transcript-only)_
- A feature flag never skips building real functionality; it only defers being blocked by dev-only gates, which must still be built and tested in both states, log loudly what is relaxed, and name their removal condition and go-live step.
- A dev flag's default is the production behavior; a flag nobody will ever flip back is deletion, not a flag.
- Billable transfers require a dry run and explicit sign-off first, and are not the AI's lane to just run. _(not in canon; transcript-only)_
- Never restart the Docker daemon (full-host outage) without explicit word. _(not in canon; transcript-only)_
- Never touch matter/court_case identity without explicit sign-off (D-115/D-117).
- Interactive planning artifacts (decision desks) are part of planning and may be written even in plan mode; the root agent stays read-only while approved subagents do approved writes. _(not in canon; transcript-only)_
- Permission architecture: hard allow/deny lists in `.claude/settings.local.json` gate Edit/Write on server, modules, sql, deploy, config, and AGENTS paths; git write operations are "ask," never "deny"; the auto-mode classifier blocks the AI's own attempts to loosen these. _(not in canon; transcript-only)_

**Recall and thinking discipline**
- Recall, then the named skill / thinking-model router, then the question gate — every turn, without being told.
- A named skill the owner invokes must actually run with real outputs, on every task and every completion claim.
- Search prior discussion and any owner-supplied design document before proposing anything new; never invent a parallel design. _(not in canon; transcript-only)_
- Don't stop at the first document that seems to answer the question; the expansion documents usually exist. _(not in canon; transcript-only)_
- Evaluate any proposed mechanism against the full surrounding workflow, never in isolation. _(not in canon; transcript-only)_
- Raw-table and first-party-export schemas are settled precedent: mirror exactly, never invent, guess, or drop fields. _(not in canon; transcript-only)_
- Apply pre-mortems, systems thinking, and judgment to the still-evolving ingest, classification, and normalization work. _(not in canon; transcript-only)_
- When blocked on a missing decision or data, work on what is already available rather than stall. _(not in canon; transcript-only)_

**Verification**
- Verify before claiming, including config, indexes, migrations, and deployments: a config accepted or a code path present is not the same as working.
- Sub-agent completion claims get diffed and verified before being trusted. _(not in canon; transcript-only)_
- "Fixed" means every byte and field accounted for against the full raw tables, not "it ran."
- "Live" means the owner can assemble messages, build a timeline, and prove the deception — not that something is deployed.

**Persistence and docs**
- Doc drift is fixed the same turn it is found, everywhere the stale claim appears.
- Never hard-delete; quarantine instead.
- Don't stage or commit another in-flight chat's or tool's untracked files. _(not in canon; transcript-only)_
- Secrets are referenced by name and length, never by value, even when relayed between agents; a git-tracked file is the only hard line. _(not in canon; transcript-only)_
- Read "what this is for" first, above every other rule: this is the owner's custody evidence and his time.

**Models and agents**
- Opus for reasoning-heavy subagents, Sonnet for mechanical or fact-checking work, never "Fable" subagents. _(not in canon; transcript-only)_
- Fire sub-agents, then wait; do not dispatch new work while lanes are running, and respect literal dispatch holds. _(not in canon; transcript-only)_
- Real-shell Claude Code sessions run git directly; Desktop Commander is for sandboxed Local-Agent-Mode sessions only.

**Architecture invariants**
- The router is signature-based, never priority-based: one registry row per file signature, DuckDB as handler wherever it can process a signature, Go decoders registered only where it cannot.
- The one browser work surface is `modules/workbench`; never stand up the SBV viewer as a Coolify web surface. The SBV front end lives on as the donor for `intake`, the Tauri desktop ingest client (D-123, D-150) — owner correction 2026-09-06 16:59.
- SBV is two things: decoders absorbed into the engine, and a separate viewer client; Go always orchestrates.
- Attachments are extracted at parse time, always, into a subfolder with their own name, hash, and SHA row; never lazily at view time.
- Lifecycle order is context → SurrealDB → evidence; never a bare "promote."
- ~~Custody sealing happens only at promotion; promotion is verify-in-place against existing UUIDs, not new rows.~~ **CANON-CHECK 2026-09-06 (Claude Code · Sonnet): Same correction as the 2026-09-03 #159 line above: D-145 (docs/DECISION_LOG.md) names `working_evidence_link` as part of promotion into `evidence.*` mirrors -- promotion writes new linked rows, it is not verify-in-place against existing UUIDs with no new rows.**
- Content and timestamps are immutable; everything else about a record may be corrected. Immutability guards are core machinery, not a nice-to-have.
- AI chats are permanently context-only and never enter the messaging custody/fidelity apparatus (D-082).
- SurrealDB, not Weaviate, owns horizon walks and their searches (D-073/D-080).
- Weaviate holds vector plus PG coordinate plus member ids only, never chunk text; PG chunk text becomes ids-only.
- One Temporal activity per file, one unit one job (D-130); ELT must write into `raw.*` under the same contract as the Go parsers.
- LlamaIndex owns retrieval, LangGraph owns the retrieval state machine; fusion within a lane is fine, fusion between the Semantica and SAT-RAG lanes stays forbidden (D-093).
- The R2 vault is the permanent home for real evidence and never holds test material; test material lives at `/data/test_data` on both hosts.
- Traefik is for externally-facing surfaces only; OIDC is the auth direction; per-service Tailscale identity is the rule (D-134).
- Products get proper names, components get functional lowercase names, forks keep the upstream name, one concept has one name.

## 5. What was actually done (verified vs claimed)

### Verified live or real
- 2026-09-01 first-night commits: `82258c6` (T-0 directory moves plus CI restore), `9da8815` (H-02a Go compile fix), `6e6d1c8` (H-11 SurrealDB surface doc), `4cbdce4` (H-09 cleanup), `cc53a0e` (migration `0062` applied to the LIVE platform DB, 122 stale refs requalified, `0065` function-drift repair — ledger SHAs matched committed bytes), plus `e8a00ed`, `cd7df27`, `b0c8bc0`.
- Pytest baseline reconfirmed by direct rerun at 1,426 passed / 27 documented pre-existing failures; later run 1,455 passed / 26 failed / 27 skipped, with all 26 proven by git-log diff to pre-date the session.
- Repo restructure `45e49a3` (638 files tracked as renames): `docker/`→`deploy/docker/`, engine/workbench/vendored→`modules/`; verified by green Go build/vet/test and passing facade tests.
- Nested repos created: `modules/custom` (`761847a`), `modules/forks/timesketch-fork` (`00eff7d`), `modules/forks/sbv` (`ed5b6cc`, wired to `Cursedpotential/sbv-forensic`). Pushed `bd75844..fa54a5a`; PR #27 opened.
- Records recovery: D-072–D-081 restored verbatim (`9c213cc`); two lost ruling docs (one partial); 38 rollout-authored audit files across lanes A–D landing as `55db5f9` + `4e43a13` (~307KB, 17 files). D-123/D-124 pushed as `4a8a6d7`. D1 lane `aa8a556`. C1+E1 salvage `507ee38`.
- Live deploys confirmed: `parser-activity-runtime` at `:8090` with 11 parsers, healthz 200; `universal-import-worker` on queue `universal-import-v1` with 26 activities; `universal-import-starter` at `:8091`.
- Migrations applied and verified live: `0066` (platform_runtime schema grant, cleared the crash), `0067` (0054 constraint drift plus probe reading `ops.migration_ledger`), `0069` (dev sentinel case-registry identity behind PLATFORM_DEV_AUTH_BYPASS, verified in boot logs), `0071` and `0072` (verified on a fresh connection).
- Feature-flag integrity audit committed (`docs/reviews/2026-09-02-feature-flag-integrity-audit.md`): 11 flags assessed, 1 violation fixed and pushed, 2 weak items flagged.
- All 7 universal-import n8n workflows bound and active; parser-runtime rebound to a reachable tailnet address; Coolify env/URL fixes verified in both call directions.
- First live UIW rehearsal: POST /start returned 201, `register_source_activity` succeeded, `retain_original_activity` failed — a real defect (API accepts `upload://` and `r2://`, worker resolved `file://`). Scheme-router wiring fixed in `modules/engine/uiwworker/worker.go`, build/vet/test green, committed.
- Coolify auto-deploy verified to fire (~4 min), correcting the AI's own false negative; Workbench verified live at `https://workbench.tilapia-skilift.ts.net` via Tailscale Serve, correcting the AI's wrong-URL claim.
- Authentik verified NOT deployed by live SSH probe on both hosts (an earlier session's claim shown false). B2 backups verified stale since 2026-08-01 with zero automation referencing them.
- D-134/D-135 pushed (`eee22b6`); n8n flow-binding registry committed (`d0b18f5`); fidelity digest at `modules/engine/fidelity/` with canon tag `fidelity-content-ts-handle-dir-v1`, 12 tests verified by `go test ./fidelity/ -v` (`5cbf3bb`); R2 inventory and export-shape research (`fdc0db3`); Snapchat JSON parser with 11 tests (`72880d4`); WhatsApp `_chat.txt` parser with 15 tests (`710912e`).
- memsearch reset, reindex, and live check: embedding dimension corrected 4096→2048, 2,809 stale chunks rebuilt to 3,247 stable, 55 source files preserved; two real recall queries returned scored, sourced hits.
- `sql/0071_pg_cdc_outbox_spine.sql` (ADR-0052 outbox) built and committed (`ad5f820`). B2+B4 fix: new `working.content_chunk_message` bridge migration plus FK, enqueue function rewired through the bridge, `vector_projection.py` moved off the dead `nv-embed-v1` onto `nemotron-3-embed-1b` @2048-dim, tests against real SQL added, live rollback validated.
- Tool gateway deployed live as `tool-gateway-node` with its own Coolify app, platform-tools volume mount added, watch-paths fixed, redeployed with 41 tools answering; Weaviate `EvidenceChunkV1` class (2048-dim) confirmed created. New Tailscale auth key (tag:docker) minted and staged.
- Committed and pushed fixes on main: four Go Dockerfiles' toolchain pin, vendored Tailscale web client embed, worker `repair.go` gateway contract plus service token, platform-tools compose build context, `toolgateway/http.go` auth/trust flag, `runtimeapi/source_ref.go` r2:// dev-fixture plus test, `uiwworker/worker.go` r2:// resolver registration, `uiw/workflow.go` and `activities/repair.go` locator/Refs fixes plus corrected tests, `deploy/parser-activity-runtime.yaml` volume/env, `runtimeapi/uiw_preview.go`.
- 2026-09-06: real evidence located in the R2 vault (SMS export 1.33 GB / 11,676 messages; call log 1,457 calls; iMessage pilot HTML/TXT); copied to both hosts under `/data/test_data`, reorganized into per-source-type subfolders per owner correction, sha256-verified.
- Atomic parse tests: call log 1,457/1,457 clean; iMessage TXT initially misrouted then 1,918/1,918 clean under `messages_transcript`; iMessage HTML only 1/1,918 (depth bug); the 1.3 GB SMS XML aborted at 2,135/11,676 (unescaped-quote desync).
- `webbed` DuckDB extension live-verified working on the live `platform` DB by smoke test (after causing the ~1-minute outage). `allow_community_extensions=on` persisted at `deploy/docker/postgres/Dockerfile:64` (repo-only; live DB unaffected until redeploy).
- D-143 through D-149 and sub-amendments written to `docs/DECISION_LOG.md`; ADR-0041 supersession note added. Memory files written across the session: subagent-model policy, named-skills-non-negotiable, owner-docs-are-guides-newest-wins, Fable's-role, plan-done-only-when-owner-says, llamaindex-langgraph-are-in-final, lifecycle-order-context-surreal-then-evidence, test-the-job-not-the-transport, memory-notes-are-rules-not-quotes, attachments-extracted-at-parse, question-gate-before-asking, what-this-is-for, work-surface-is-probata-workbench, plus appends to router-is-signature-based-not-priority and named-skill-is-non-negotiable.
- Ingest decision desk HTML Artifact published and iterated (10+ republishes; URL `https://claude.ai/code/artifact/efe3d190-dc46-43d3-8bfc-768cb023d60a`), with a server-side shared-store answer mechanism. `.claude/settings.local.json` allow/deny/ask rules applied.
- Handoff written via `/handoff` at 15:21 EDT and updated 15:46 EDT — `docs/HANDOFF-2026-09-06-ingest-rulings-and-parser-fix.md`, STATUS: PARTIAL, BUILD_STATUS: PASS for Go, explicitly not committed. Local commits `9c00b46`, `35e5092`, and a D-147/148 commit made but not pushed. The new seal/hash CLI was quarantined (not deleted) into the repo's holding area and then `modules/engine/parked/seal/`.

### Claimed but not independently verified
- The P1 subagent's byline claiming custody handling was removed from the SMS parser, with a cited supporting doc — false on both counts; caught by diffing the file, reverted.
- "Restructure complete and verified" (2026-09-01) — the Coolify side had not been checked; `parser-activity-runtime` was still misconfigured.
- "Everything on the deploy chain is now connected" (2026-09-02) — proxy-verified by absence of ECONNREFUSED, not by a successful run.
- The D-125 dev auth bypass reported fixed — wired to the wrong handler (Starter vs Preview).
- Authentik "deployed" from an earlier session — disproven by live probe.
- Whether the ingest rehearsal ever achieved a clean, full end-to-end pass: slice 4 states explicitly that repeated reruns each fixed one newly-found bug and no line confirms a fully green run.
- The decoder-fix agent's 15:38 EDT results on `sms_xml_importer.go`, `messaging_html_importers.go`, and `importer.go` — claimed done; the parent AI's promised byte/field-coverage verification never ran.
- The router-table fix for the iMessage TXT misrouting, folded into that agent's scope — not independently confirmed.
- R2 corpus size: a first pass reported 345,273 files / 1,183 GB and a later background scan 837,590 files / 1,842 GB; the two were never reconciled.
- The "Real workflow run: SMS export to raw tables" agent — no completion record; outcome unknown.

## 6. Unresolved at session end

Ordered as the last slice weights it: the real-workflow proof run first, then uncommitted work, then owner-side decisions, then cleanup.

**1. The real-workflow proof run (the largest open item)**
- The "Real workflow run: SMS export to raw tables" agent, launched 15:38 EDT to run the just-fixed SBV decoder against the real vault-sourced SMS export end to end, populate the raw tables, and confirm via seven proof queries, stopped with no completion record; the session ended at 15:56 EDT mid-response, apparently on context exhaustion. Its transcript is preserved and it is resumable via SendMessage or its worktree/output.
- Whether the SMS export actually landed in the raw tables, and whether it met the 13:05 EDT acceptance bar (every byte and field accounted for against the full raw tables), is unknown.
- The iMessage HTML depth-bug fix and the SMS XML unescaped-quote fix are reported successful by the fix agent but unverified by the parent.
- No end-to-end UIW ingest has ever succeeded from start through publication.
- By the owner's own definition, nothing is "live" until he can assemble messages, build a timeline, and prove the deception.

**2. Uncommitted / undeployed work**
- Local commits `9c00b46`, `35e5092`, and the D-147/148 commit remain unpushed (held pending the rename session's push).
- The handoff doc is written but not committed.
- `docs/reviews/2026-09-05-tool-gateway-live-deploy.md` and the live-deploy-chain review are uncommitted and still carry old names (`uiw`, `UIW`, the old repo name) — see rename handoff.
- The `allow_community_extensions` Dockerfile change is not deployed; it needs a Coolify redeploy of `agentos-db`, which bounces the live DB — timing is the owner's call.
- SFTPGo deployment spec prepped but never actioned; Filestash recommended but not deployed; FileBrowser parked. DuckDB lakehouse frontend choice (DuckDB UI vs Rill vs Evidence.dev vs Harlequin) discussed, nothing decided or deployed.

**3. Owner-side decisions**
- Decision-desk questions Q2 through Q19 are unanswered (only Q1 has an answer on the shared store); at least seven gate the first real Google Voice ingest: raw byte-offset requirements, promotion re-parse strategy (Go decoder vs ELT vs both with a divergence check), ELT/decoder record-count mismatch handling, ELT activity input shape (one locator vs package-scoped glob), the Google Voice HTML routing tie-break (decoder-wins vs ELT-wins-with-template), and whether the chunk bake-off must finish before the first ingest.
- Q19 (a NUL byte found in a raw record) is explicitly the owner's to rule and gates parse-to-raw. Q18 (which parked January items return) is open. P1/P4 desk close-out was substantively folded into D-149 but never signed off in a final pass.
- R2 sealing: copy into the object store (real Class-A cost on 1.8 TB) vs reference-in-place via R2 versioning/object-lock — an open money question.
- New `evidence.message` / `evidence.chunk` tables vs projecting into the existing `evidence_item` — open; the AI admits it leaned toward new tables without checking `evidence_item`'s shape.
- Chunk-always-after-parse vs two entry points (chunk-without-parse for plain text and markdown) — open.
- The batch discovery and routing layer (file picker vs R2 prefix vs whole-bucket walk; parser selection; package-vs-file fan-out) — proposed, never ratified.
- The messaging chunk unit is explicitly left for the owner to define; whether ADR-0053's chunk-first mechanism (not its ruling) should be reused for the messaging lane is a recommendation, not a decision.
- ADR-0041 still literally reads "Agno agents"; whether to amend the text or append a superseding note was never ruled.
- Whether the owner holds cross-party exports or screenshots for corroboration — asked at #138, never answered.
- The repo's own name, the legal-side module's name, and the desktop ingest client's name were unruled here — closed by the parallel rename session; see rename handoff.

**4. Cleanup and carried debt**
- Cleanup left for the owner: an empty `first-real-runs/` directory on ovh-files, four misplaced test copies in the `nexus` bucket, three stray hash-manifest CSVs at the repo root (attributed to the rename session).
- The parallel rename session's final state and push status were unknown at cutoff — see rename handoff.
- The auto-memory store is path-keyed to the old `…\Agno-MCP-Platform` directory; `.claude/settings.local.json` permission rules key on `server/**`, `modules/**`, `sql/**`, `deploy/**` and break if those move; live Coolify apps still point at the old GitHub repo/module path (`Cursedpotential/mcp-platform-agno-mvp`), which breaks every Go app's build on the next deploy until repointed — all three flagged, not executed; see rename handoff.
- B2 backup automation is broken/nonexistent (stale since 2026-08-01).
- Docker daemon `default-address-pools` exhaustion was only patched around by pruning 3 dead networks; the durable fix needs an owner-approved daemon restart (full-host outage).
- The GitHub CI "Validate" workflow's final green/red state was never confirmed. The `sbv-forensic` repo reconciliation is open: the pushed `platform-sync` branch supersedes that repo's own main by +10,973 lines.
- `SBV_CUSTODY_ENABLED` still defaults to silently skipping custody hashing, and the immutability gates (`app.evidence_live`, `app.enforce_derived_guard`) still have zero tests — both flagged by the flag audit as remediation items.
- The 26–27 pre-existing pytest failures were carried forward, never fixed, deferred to wave H-02.
- ADR-0049 gaps remain open: the repair-call seam, 11 Go AI-chat decoders, two parallel detection registries, a GUI surface for Python-parsed records, and Python custody-journal retirement.
- OCR/VLM provider selection (ADR-0053 rung 3) is unbenchmarked and unwired; screenshot → message-record structural inference (the real Snapchat-screenshot gap) is not built.
- Participant → `entity_resolution` → `id_xref` wiring is schema-ready but unimplemented; the cross-party corroboration graph exists only as a concept.
- The Google Photos comments export shape is unverified (the Takeout samples on disk were empty or failed downloads).
- Coolify watch-path re-scoping from `docker/**` to `deploy/docker/**` was never confirmed done. The Lost and Found corpus (18 markdown chats plus 2 ChatGPT exports), named as the first real ingest candidate, was never ingested.

## 7. The one-paragraph resume brief

This is Matt's evidence platform for his own pro se custody case, and the six days from 2026-09-01 to 2026-09-06 cost him at least one full workday plus an earlier eight-day stretch, almost entirely to an AI that answered from grep instead of the decision record and claimed things worked without watching them work. What is settled and must not be re-opened: the lifecycle order is context → SurrealDB → evidence with custody sealing only at promotion (D-145/D-146, D-149); the router is signature-based, with DuckDB as handler wherever it can process a signature and Go decoders registered only where it cannot; the one work surface is `modules/workbench`; SBV is decoders absorbed into the engine plus a separate viewer client, never its own deployment; attachments are extracted at parse time; AI chats stay context-only (D-082); horizon walks live in SurrealDB, not Weaviate (D-073/D-080); LlamaIndex and LangGraph are both in and also do pre-Surreal stitching (D-143/D-144); content and timestamps are immutable and everything else is editable (D-136). In flight: the real SMS-export workflow run against the just-fixed decoders never reported back, so the raw tables are unproven and nothing meets the owner's acceptance bar of every byte and field matching the full raw tables; three local commits, the handoff doc, and two review docs are uncommitted; ~~decision-desk Q2–Q19 are unanswered and at least seven of them gate the first Google Voice ingest~~ (slice-4 wording, superseded the same day: Google Voice was STRUCK as the first ingest — the first real runs are the SMS export and iMessage; Q1/Q3/Q6/Q7/Q18 were ruled, Q2 is closed by D-149 clause 9, Q5 is moot; per the 15:46 handoff the desk items still owed a read are Q8, Q11, Q12, Q16, Q17, Q20–Q25 — correction Claude Code · Fable 5.1 · 2026-09-06 16:55). Do not re-litigate any decision above, do not present a blocker without first checking whether it is real and already decided, and do not report anything as done off a config, a build, or a subagent's byline. Run recall and the thinking-model router on every turn, use Opus for reasoning subagents and Sonnet for mechanical ones, and speak in plain English. Read `docs/HANDOFF-2026-09-06-ingest-rulings-and-parser-fix.md` for the authoritative current state, and read the "what this is for" memory note before anything else.
