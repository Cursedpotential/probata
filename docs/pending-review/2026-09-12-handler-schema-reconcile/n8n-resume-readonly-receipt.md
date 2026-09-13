# Resume verification: validator updates have not landed

Byline: Codex, 2026-09-12. Read-only verification after interrupted update task.

Inspected the existing `n8n-validator-update.ps1` without invoking Apply. Read both
dedicated workflows through the live n8n Public API and compared their validator
code with current local wrapper JSON. Credentials were parsed privately, never printed.

| Workflow | Live draft and active version (equal) | Active | Matches local code |
|---|---|---|---|
| fvKS2gcsRUdEKUun (select) | 3870c5fc-d036-4868-887f-8f2fe90cd7a0 | true | false |
| YQoFBykpZoDrU0n6 (execute) | a839c59b-a0ad-4504-b412-538c925db703 | true | false |

Both version IDs remain the exact pre-update IDs pinned in the prepared script.
Both live validators lack `handlerRefs` and `allowedRefSets`; they still require
exactly three references. Select requires filesystem_metadata, container_manifest,
metadata_manifest. Execute requires parser_selection, original, parser_options.

Expected local contract is base-three OR base-three plus **all six** handler references:
handler_recommendation, handler_decision, handler_validation, detected_format,
content_signature, handler_compatibility. Partial six-ref sets must be rejected.
The live exact-three tests reject the expected nine-ref request before runtime.

**Conclusion:** no desired validator update is currently applied or published on
either workflow. There is no successful prior mutation proof; do not call this deployed.
Read-only API requests succeeded (shell exit 0). No workflow writes, activation,
parser execution, new ingest, database mutation, or deployment occurred in this pass.

Script observation: Apply would perform a full editable-payload PUT after a fresh
whole-response fingerprint check, compare post-PUT graph/settings, then publish the
new version if needed. It is prepared code, not executed proof. Future execution
must follow renewed parent authorization and retain the current concurrent-drift guard.
