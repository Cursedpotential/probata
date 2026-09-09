> _Byline: Claude Code · Fable 5 · 2026-09-06_

Owner-authorized ATOMIC PARSE TEST driver (2026-09-06). Standalone Go program that
calls `github.com/lowcarbdev/sbv/pkg/parseonly` directly (no DB, no Temporal, no
custody writes) against one source file and prints parse/reject/date-range/
participant/attachment stats. Used to test the SBV decoder on
`imessage_txt`, `imessage_html`, and `smsbackuprestore_xml` (SMS + calls) against
the four fixture files hardlinked into `/data/test_data/first-real-runs/` on
ovh-files. Cross-compiled `GOOS=linux GOARCH=amd64 CGO_ENABLED=0`, copied into the
running `parser-activity-runtime` container's `/tmp`, and executed there against
the container's existing read-only `/data/proffer/source-objects` mount — no
redeploy, no compose change. Not wired into any build; kept here for provenance
per the owner result-persistence rule. Not committed unless the owner asks.
