# Handoff — Evidence Operations Desk production MVP

> Byline: Codex · GPT-5 · 2026-08-18

## Rule and outcome

Every build/add/finish/change request means production implementation, Coolify deployment,
and live verification. Mockups count only when the owner explicitly says “mockup.” Finish
the production drill-through: `custody jacket → original source message → normalized
message(s) → surrounding conversation → human-reviewed content/decisions →
custody/provenance`.

## Verified state

- `workbench/` is the operator product; the evidence spine is custody → parse → normalize →
  store → export (`AGENTS.md`).
- Deployed Workbench `100.72.169.40:8020` is old; it is not current-release proof.
- Current local changes include Workbench/API and evidence/message projection surfaces, but
  no live claim is made until Coolify and end-to-end verification are recorded.
- Coordination explicitly forbids claiming local builds as live without deployment proof.

## Ordered TODO and gates

1. Identify the Workbench Coolify app, branch/commit, watch paths, environment, and target
   URL; record the old endpoint and release SHA.
2. Verify real API links for custody jacket, original source, normalized messages,
   surrounding conversation, human review/decisions, and custody/provenance.
3. Finish the production UI against real contracts and loading/empty/denied/missing/error
   states; do not ship `workbench/design-mockups`.
4. Run focused tests and live-safe endpoint/UI checks; record commands, SHA, and failures.
5. Deploy via Coolify; record app, timestamp, SHA, and outcome.
6. Live-verify the complete drill-through with auth and provenance/source-clock integrity.
7. Mark complete only with evidence from steps 1–6; otherwise record blocker and resume step.

## Resume state

**NOT COMPLETE — resume at step 1.** No mockup or local preview substitutes for production
deployment and live verification.
