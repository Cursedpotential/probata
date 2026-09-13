# SurrealDB and visual tools

`docstore-surreal` connects to the existing native `/mcp` endpoint, scoped with `surreal-ns: probata` and `surreal-db: docs`, using `DOCSTORE_BASIC_AUTH` from the environment. It is not a second database. Never use the evidence or memory credentials as fallback.

Native MCP may expose database mutation tools. The database credential's actual permissions—not the connection label—are the security boundary. Discover available tools and schemas. Prefer server-defined operations for structured decisions, todos and handoffs. Do not invent function names or claim success from an unverified response. Inspect after authorized writes. Read tools and write tools are distinct; do not treat the whole native server as read-only.

Existing typed native function arguments may require Surreal's `{"$ql":"NONE"}` sentinel rather than JSON null. Use only where the actual discovered schema/contract requires it. Never construct raw queries by concatenating document content. If CLI inspection is needed, the repository's normalized query helper is `scripts/docstore/sq.py`; inspect its documented interface, use uv, and bind parameters where supported.

## Surrealist / Studio

`docstore_surrealist` returns a credential-free connection guide and the web viewer link; it does not open a window or log in. The current official docs call the visual interface **SurrealDB Studio**, while the project and existing installations use **Surrealist**. Graph result visualization, record/relationship Explorer, and schema Designer are different views. Verify availability in the installed viewer version.

Open the returned web URL when requested, connect to the dedicated documentation endpoint, select namespace `probata`, database `docs`, and authenticate inside the viewer. Never encode passwords/tokens into a URL. Use the MCP graph tool/resource for a bounded neighborhood directly in the agent; it does not require the graphical viewer.

Official references:
- https://surrealdb.com/docs/explore/studio
- https://github.com/surrealdb/surrealist

No native tool discovery or viewer connection is considered live-verified merely because a manifest exists.
