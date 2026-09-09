-- 040_graph.surql
-- Relations. CocoIndex can own these via mount_relation_target,
-- or the librarian agent writes them with RELATE.

DEFINE TABLE OVERWRITE supersedes TYPE RELATION IN adr|document OUT adr|document SCHEMAFULL;
DEFINE FIELD OVERWRITE at        ON supersedes TYPE datetime VALUE time::now() READONLY;
DEFINE FIELD OVERWRITE reason    ON supersedes TYPE option<string>;

DEFINE TABLE OVERWRITE derived_from TYPE RELATION IN adr|todo|document OUT document SCHEMAFULL;
DEFINE FIELD OVERWRITE method    ON derived_from TYPE string DEFAULT "extraction";
DEFINE FIELD OVERWRITE at        ON derived_from TYPE datetime VALUE time::now() READONLY;

-- chunk_of: retrieval unit -> its source document. Written by the ingest via
-- the connector's RelationTarget (cocoindex.connectors.surrealdb), so CDC
-- creates AND reconciles it in the same run as the chunk row itself.
-- Field-free on purpose: the connector emits `RELATE ... CONTENT {}`, and a
-- SCHEMAFULL edge with no extra fields accepts that exactly.
DEFINE TABLE OVERWRITE chunk_of TYPE RELATION IN chunk OUT document SCHEMAFULL;

DEFINE TABLE OVERWRITE mentions TYPE RELATION IN document|chunk OUT entity SCHEMAFULL;
DEFINE FIELD OVERWRITE count     ON mentions TYPE int DEFAULT 1;

DEFINE TABLE OVERWRITE blocks TYPE RELATION IN todo OUT todo SCHEMAFULL;

DEFINE TABLE OVERWRITE entity TYPE NORMAL SCHEMAFULL;
DEFINE FIELD OVERWRITE name ON entity TYPE string;
DEFINE FIELD OVERWRITE kind ON entity TYPE string
  ASSERT $value IN ["component","service","library","person","concept","file"];
DEFINE INDEX OVERWRITE entity_key ON entity FIELDS kind, name UNIQUE;
DEFINE INDEX OVERWRITE entity_name_ft ON entity FIELDS name
  FULLTEXT ANALYZER doc_code BM25;

-- Retrieval telemetry: what was retrieved, and did the action succeed.
-- This is the feedback loop that lets the store improve itself.
DEFINE TABLE OVERWRITE retrieval TYPE NORMAL SCHEMAFULL;
DEFINE FIELD OVERWRITE query    ON retrieval TYPE string;
DEFINE FIELD OVERWRITE agent    ON retrieval TYPE string;
DEFINE FIELD OVERWRITE scope    ON retrieval TYPE object DEFAULT {};
DEFINE FIELD OVERWRITE hits     ON retrieval TYPE array<record<chunk>> DEFAULT [];
DEFINE FIELD OVERWRITE path     ON retrieval TYPE string
  ASSERT $value IN ["index","fallback","fulltext","hybrid","graph"];
DEFINE FIELD OVERWRITE outcome  ON retrieval TYPE string
  ASSERT $value IN ["unknown","used","ignored","insufficient","wrong"]
  DEFAULT "unknown";
DEFINE FIELD OVERWRITE at       ON retrieval TYPE datetime VALUE time::now() READONLY;
DEFINE INDEX OVERWRITE retrieval_at    ON retrieval FIELDS at;
DEFINE INDEX OVERWRITE retrieval_agent ON retrieval FIELDS agent;
