# Docstore pipeline scope

<!-- Updated by: Codex | Date: 2026-09-12 | Rev: 2 | Platform: Codex / win32 | Changes: establish registry-driven universal source scope | Context: explicit owner decision -->

Inherit repository instructions. This directory owns **CocoIndex + SurrealDB for project documentation**. It is not codebase CCC and not Intake.

Probata is the implementation host, not the corpus boundary. The target state will
progressively include every active source in the Propria root
`docs/docstore-source-registry.json`. Multi-root ingestion must remain one complete
CocoIndex App target state with stable project IDs and canonical prefixes; never
run one partial root through the full-source app because omitted components can be
retired. A registry entry is discoverability and intent until a verified worker
receipt proves its ingestion status.

CCC is CocoIndex Code for individual codebases. Intake is the multifaceted CocoIndex/Weaviate/SurrealDB file workstation, with OCR, STT, video processing, advanced SLM and multiple libraries/example patterns. Do not import that entire stack into Docstore or apply Docstore helper limits to Intake.

Preserve existing Docstore App/environment/tracking ownership unless a separately verified migration changes it. Never use ccc commands or codebase tracking state to run this documentation pipeline. Memory/evidence stores remain separate destinations.

See [shared boundaries](../../../../SYSTEM-BOUNDARIES.md). This records intended scope, not implementation readiness.
