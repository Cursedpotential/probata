-- 030_records.surql
-- ADRs, decision logs and todos as first-class rows.

DEFINE TABLE OVERWRITE adr TYPE NORMAL SCHEMAFULL
  CHANGEFEED 180d INCLUDE ORIGINAL;

DEFINE FIELD OVERWRITE number    ON adr TYPE int;
DEFINE FIELD OVERWRITE title     ON adr TYPE string;
DEFINE FIELD OVERWRITE context   ON adr TYPE string;
DEFINE FIELD OVERWRITE decision  ON adr TYPE string;
DEFINE FIELD OVERWRITE consequences ON adr TYPE option<string>;
DEFINE FIELD OVERWRITE project   ON adr TYPE string DEFAULT "default";
DEFINE FIELD OVERWRITE status    ON adr TYPE string
  ASSERT $value IN ["proposed","accepted","superseded","deprecated","rejected"]
  DEFAULT "proposed";
DEFINE FIELD OVERWRITE decided_at ON adr TYPE option<datetime>;
DEFINE FIELD OVERWRITE source_doc ON adr TYPE option<record<document>>;
DEFINE FIELD OVERWRITE created   ON adr TYPE datetime VALUE time::now() READONLY;
DEFINE FIELD OVERWRITE updated   ON adr TYPE datetime VALUE time::now();

DEFINE INDEX OVERWRITE adr_number ON adr FIELDS project, number UNIQUE;
DEFINE INDEX OVERWRITE adr_status ON adr FIELDS status;
DEFINE INDEX OVERWRITE adr_title_ft ON adr FIELDS title
  FULLTEXT ANALYZER doc_text BM25 HIGHLIGHTS;
DEFINE INDEX OVERWRITE adr_decision_ft ON adr FIELDS decision
  FULLTEXT ANALYZER doc_text BM25 HIGHLIGHTS;

-- ---------------------------------------------------------------------
DEFINE TABLE OVERWRITE todo TYPE NORMAL SCHEMAFULL
  CHANGEFEED 90d INCLUDE ORIGINAL;

DEFINE FIELD OVERWRITE title    ON todo TYPE string;
DEFINE FIELD OVERWRITE detail   ON todo TYPE option<string>;
DEFINE FIELD OVERWRITE project  ON todo TYPE string DEFAULT "default";
DEFINE FIELD OVERWRITE owner    ON todo TYPE string DEFAULT "unassigned";
DEFINE FIELD OVERWRITE status   ON todo TYPE string
  ASSERT $value IN ["open","in_progress","blocked","done","dropped"]
  DEFAULT "open";
DEFINE FIELD OVERWRITE priority ON todo TYPE int
  ASSERT $value >= 0 AND $value <= 4 DEFAULT 2;
DEFINE FIELD OVERWRITE due      ON todo TYPE option<datetime>;
DEFINE FIELD OVERWRITE source_doc ON todo TYPE option<record<document>>;
DEFINE FIELD OVERWRITE created  ON todo TYPE datetime VALUE time::now() READONLY;
DEFINE FIELD OVERWRITE updated  ON todo TYPE datetime VALUE time::now();
DEFINE FIELD OVERWRITE closed_at ON todo TYPE option<datetime>;

DEFINE INDEX OVERWRITE todo_status   ON todo FIELDS status;
DEFINE INDEX OVERWRITE todo_scope    ON todo FIELDS project, status, priority;
DEFINE INDEX OVERWRITE todo_open_cnt ON todo COUNT WHERE status = "open";
DEFINE INDEX OVERWRITE todo_title_ft ON todo FIELDS title
  FULLTEXT ANALYZER doc_text BM25 HIGHLIGHTS;

-- ---------------------------------------------------------------------
-- Append-only audit log. Never updated, never deleted.
DEFINE TABLE OVERWRITE decision_log TYPE NORMAL SCHEMAFULL;

DEFINE FIELD OVERWRITE subject ON decision_log TYPE record;
DEFINE FIELD OVERWRITE actor   ON decision_log TYPE string DEFAULT "system";
DEFINE FIELD OVERWRITE action  ON decision_log TYPE string;
DEFINE FIELD OVERWRITE from    ON decision_log TYPE option<string>;
DEFINE FIELD OVERWRITE to      ON decision_log TYPE option<string>;
DEFINE FIELD OVERWRITE rationale ON decision_log TYPE option<string>;
DEFINE FIELD OVERWRITE at      ON decision_log TYPE datetime VALUE time::now() READONLY;

DEFINE INDEX OVERWRITE dlog_subject ON decision_log FIELDS subject;
DEFINE INDEX OVERWRITE dlog_at      ON decision_log FIELDS at;
