# Docstore plugin scope

<!-- Updated by: Codex | Date: 2026-09-12 | Rev: 3 | Platform: Codex / win32 | Changes: establish canonical plugin package and federation gate | Context: universal Docstore cutover implementation -->

Inherit repository instructions. **Docstore = CocoIndex + SurrealDB for documentation**, with tools/resources/skills and Surrealist/Studio graph access. It is distinct from **CCC = project-local CocoIndex Code**, and **Intake = multifaceted CocoIndex + Weaviate + SurrealDB filesystem organization with multimodal libraries and processing**.

Probata hosts Docstore, but the service and governed corpus are Propria-wide. All
Propria project documentation is progressively registered through the root
`docs/docstore-source-registry.json`. Search, bounded recall, resources, notes,
decisions, revisions, flags, graph inspection and CDC/freshness verification are
universal agent capabilities. Preserve each source file's owning project, path,
provenance and authority. Query related Docstore records before documentation
writes, persist notes through governed tools, and read writes back.

Plugin packaging does not merge runtimes, credentials, locks or target ownership. The documentation helper's current Markdown limits are not Intake eligibility rules. Historical memory bundling is an integration, not ownership of the independent memory service.

Apply this scope in both claude/ and control/. Do not modify installed host caches as an incidental source documentation update.

The canonical Claude marketplace identity is `probata-docstore@probata`; the
canonical Codex MCP identity is `probata-docstore`. The old `docstore@probata`
package remains disabled until the owner chooses to quarantine it. ContextForge
uses the control server's explicit stateless Streamable HTTP mode and must set
transport `STREAMABLEHTTP`.

See [shared boundaries](../../../../SYSTEM-BOUNDARIES.md). Runtime availability is reported separately in verification receipts.
