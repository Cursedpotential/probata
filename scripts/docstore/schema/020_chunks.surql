-- 020_chunks.surql
-- Retrieval unit. CocoIndex owns the contents of this table.
-- DIM is substituted by SurrealKit template variables.

DEFINE TABLE OVERWRITE chunk TYPE NORMAL SCHEMAFULL;

-- RULED 2026-09-09 (owner, superseding the 11:12 ruling): the chunk->document
-- link is a RELATION (`chunk_of`, 040_graph.surql), not a field.
--
-- WHY: the connector's TableTarget inlines rows as `UPSERT ... CONTENT {json}`,
-- and a JSON string is never coerced into a record link, so a
-- `record<document>` FIELD is unwritable by the ingest. Its RelationTarget
-- builds `from`/`to` as raw SurrealQL record ids and emits a real
-- `RELATE chunk:x->chunk_of->document:y`, so the edge is written by the same
-- CDC-managed run — no second pass, no hand-written backfill.
--
-- `source_path` stays denormalised (cookbook Pattern 2 keeps `filename` on the
-- chunk row) so scope filtering never needs the join.
DEFINE FIELD OVERWRITE source_path ON chunk TYPE string;
DEFINE FIELD OVERWRITE ordinal    ON chunk TYPE int;
DEFINE FIELD OVERWRITE heading    ON chunk TYPE option<string>;
DEFINE FIELD OVERWRITE text       ON chunk TYPE string;
DEFINE FIELD OVERWRITE token_est  ON chunk TYPE int DEFAULT 0;

-- Denormalised scope columns. These exist ONLY so retrieval can filter
-- without a join, and so the filter column can carry its own B-tree index.
DEFINE FIELD OVERWRITE doc_type   ON chunk TYPE string;
DEFINE FIELD OVERWRITE project    ON chunk TYPE string;
DEFINE FIELD OVERWRITE status     ON chunk TYPE string DEFAULT "active";
DEFINE FIELD OVERWRITE domains    ON chunk TYPE array<string> DEFAULT [];

DEFINE FIELD OVERWRITE embedding  ON chunk TYPE array<float, 2048>;

-- Scope indexes: mandatory. Without these the exact-scan fallback
-- degrades from 0.17ms to 45ms.
DEFINE INDEX OVERWRITE chunk_path    ON chunk FIELDS source_path;
DEFINE INDEX OVERWRITE chunk_type    ON chunk FIELDS doc_type;
DEFINE INDEX OVERWRITE chunk_project ON chunk FIELDS project;
DEFINE INDEX OVERWRITE chunk_status  ON chunk FIELDS status;
DEFINE INDEX OVERWRITE chunk_domains ON chunk FIELDS domains;
DEFINE INDEX OVERWRITE chunk_scope   ON chunk FIELDS project, doc_type, status;

DEFINE INDEX OVERWRITE chunk_text_ft ON chunk FIELDS text
  FULLTEXT ANALYZER doc_text BM25 HIGHLIGHTS;

DEFINE INDEX OVERWRITE chunk_embedding ON chunk
  FIELDS embedding HNSW DIMENSION 2048 DIST COSINE TYPE F32
  EFC 200 M 16 CONCURRENTLY;
