-- 045_doc_graph.surql
-- Byline: Claude Code · Opus 5 · 2026-09-10
-- Derived document graph (owner 2026-09-10: "set up a graph so we can see how things are
-- interconnected ... use Surreal's viewer to view the graph"). Written ONLY by
-- scripts/docstore/graph_build.py, which deletes and rebuilds these edges from document bodies and
-- the mapping CSV on every run, so they always equal what the current documents say.
-- supersedes (040_graph.surql) is reused for mapping-CSV successor edges with reason = "mapping".

-- links_to: a markdown link [..](path.md) from one document to another.
DEFINE TABLE OVERWRITE links_to TYPE RELATION IN document OUT document SCHEMAFULL;
DEFINE FIELD OVERWRITE kind ON links_to TYPE string DEFAULT "md_link";
DEFINE FIELD OVERWRITE at   ON links_to TYPE datetime VALUE time::now();
DEFINE INDEX OVERWRITE links_to_in  ON links_to FIELDS in;
DEFINE INDEX OVERWRITE links_to_out ON links_to FIELDS out;

-- cites: a document citing an ADR ("ADR-NNNN" -> docs/adr/NNNN-*.md) or decision numbers
-- ("D-NNN" -> docs/DECISION_LOG.md; the cited numbers are kept in ids).
DEFINE TABLE OVERWRITE cites TYPE RELATION IN document OUT document SCHEMAFULL;
DEFINE FIELD OVERWRITE kind ON cites TYPE string ASSERT $value IN ["adr", "decision"];
DEFINE FIELD OVERWRITE ids  ON cites TYPE array<string> DEFAULT [];
DEFINE FIELD OVERWRITE at   ON cites TYPE datetime VALUE time::now();
DEFINE INDEX OVERWRITE cites_in   ON cites FIELDS in;
DEFINE INDEX OVERWRITE cites_out  ON cites FIELDS out;
DEFINE INDEX OVERWRITE cites_kind ON cites FIELDS kind;
