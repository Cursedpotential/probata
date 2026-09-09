-- 010_documents.surql
-- The canonical document record. One row per logical document,
-- regardless of how many chunks it produces.

DEFINE TABLE OVERWRITE document TYPE NORMAL SCHEMAFULL
  CHANGEFEED 90d INCLUDE ORIGINAL;

-- Identity / provenance -------------------------------------------------
DEFINE FIELD OVERWRITE source_path   ON document TYPE string;
DEFINE FIELD OVERWRITE content_hash  ON document TYPE string;
DEFINE FIELD OVERWRITE title         ON document TYPE string;
DEFINE FIELD OVERWRITE body          ON document TYPE string;

-- Classification --------------------------------------------------------
DEFINE FIELD OVERWRITE doc_type      ON document TYPE string
  ASSERT $value IN ["blueprint", "infrastructure", "decision", "todo", "handoff", "review", "reference"];

DEFINE FIELD OVERWRITE project       ON document TYPE string DEFAULT "default";
DEFINE FIELD OVERWRITE tags          ON document TYPE array<string> DEFAULT [];
-- D-156: domain tags from the naming canon; one or more per document.
DEFINE FIELD OVERWRITE domains       ON document TYPE array<string> DEFAULT []
  ASSERT array::all($value, |$d| $d IN ["probata","proffer","consignatio","advocatio","vestigia","indagatio","intake","workbench","knowledge","memory","infra","docs"]);

-- Lifecycle -------------------------------------------------------------
DEFINE FIELD OVERWRITE status        ON document TYPE string
  ASSERT $value IN ["active", "proposed", "unverified", "superseded", "retracted"]
  DEFAULT "unverified";

DEFINE FIELD OVERWRITE confidence    ON document TYPE float
  ASSERT $value >= 0.0 AND $value <= 1.0 DEFAULT 0.5;

DEFINE FIELD OVERWRITE retracted_reason ON document TYPE option<string>;

-- Truth / recency signals used by the reconciler ------------------------
DEFINE FIELD OVERWRITE authored_at   ON document TYPE option<datetime>;
-- VALUE, not DEFAULT: DEFAULT fires only on CREATE, but the CocoIndex
-- connector writes `UPSERT ... CONTENT {...}`, a FULL REPLACE. A row that
-- omits this column would lose it and fail coercion on every re-ingest.
-- `$value ?? time::now()` keeps a supplied value and fills one otherwise,
-- so the pipeline need not serialise a datetime at all (the connector's
-- json.dumps(default=str) emits '2026-09-09 17:39:47+00:00', which is not
-- valid SurrealQL datetime syntax and is rejected).
DEFINE FIELD OVERWRITE observed_at   ON document TYPE datetime
  VALUE $value ?? time::now();
DEFINE FIELD OVERWRITE created       ON document TYPE datetime VALUE time::now() READONLY;
DEFINE FIELD OVERWRITE updated       ON document TYPE datetime VALUE time::now();

-- Derived on read: no staleness, no update job.
-- Null-safe on purpose: inside a transaction, `RETURN VALUE id` on a newly
-- created row evaluates COMPUTED fields before observed_at's DEFAULT is
-- visible, and `time::now() - NONE` aborts the whole transaction
-- ("Cannot perform subtraction with 'datetime' and 'none'", verified live
-- 2026-09-09 -- it blocked every genuinely new document from ingesting).
-- time::now() is also re-read per occurrence, so a fresh row can yield a
-- NEGATIVE duration; the comparison guard rules both out, returning 0s.
DEFINE FIELD OVERWRITE age_days      ON document
  COMPUTED (IF (authored_at OR observed_at) = NONE OR (authored_at OR observed_at) > time::now() { 0s } ELSE { time::now() - (authored_at OR observed_at) });

-- Indexes ---------------------------------------------------------------
DEFINE INDEX OVERWRITE document_hash    ON document FIELDS content_hash UNIQUE;
DEFINE INDEX OVERWRITE document_path    ON document FIELDS source_path;
DEFINE INDEX OVERWRITE document_type    ON document FIELDS doc_type;
DEFINE INDEX OVERWRITE document_project ON document FIELDS project;
DEFINE INDEX OVERWRITE document_status  ON document FIELDS status;
DEFINE INDEX OVERWRITE document_domains ON document FIELDS domains;
DEFINE INDEX OVERWRITE document_scope   ON document FIELDS project, doc_type, status;

DEFINE INDEX OVERWRITE document_title_ft ON document FIELDS title
  FULLTEXT ANALYZER doc_text BM25 HIGHLIGHTS;
DEFINE INDEX OVERWRITE document_body_ft  ON document FIELDS body
  FULLTEXT ANALYZER doc_text BM25 HIGHLIGHTS;
