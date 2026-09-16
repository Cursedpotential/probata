-- 080_memory.surql
-- D-154: one self-hosted SurrealDB shared by every agent. Our own schema,
-- not the walk-memory/Agent-Memory-product design. Sharing is done the way
-- the SurrealDB cookbooks do it (M-agent-memory-cookbooks.md secs C/D/F):
-- a hierarchical scope-path STRING on every row (`probata/<domain>/<agent>`),
-- filtered at query time with a string-prefix predicate -- not a product
-- feature, just a schema + WHERE clause. Supersession is never a DELETE or
-- overwrite: fn::supersede_memory (085) creates a new row, RELATEs it to the
-- old one, and flips the old row's status -- full chain stays inspectable.
-- Adapted from the surreal-docstore kit's schema/080_memory.surql
-- (single-project "librarian" store) to a shared, scope-keyed, multi-agent
-- store per D-154. EMBED_DIM = 2048 substituted literally throughout.

DEFINE TABLE OVERWRITE memory TYPE NORMAL SCHEMAFULL
  CHANGEFEED 180d INCLUDE ORIGINAL;

DEFINE FIELD OVERWRITE kind ON memory TYPE string
  ASSERT $value IN ["correction","preference","observation","handoff","fact","constraint","decision"];

DEFINE FIELD OVERWRITE claim ON memory TYPE string
  ASSERT string::len($value) > 10 AND string::len($value) < 600;

DEFINE FIELD OVERWRITE detail ON memory TYPE option<string>;

-- evidence is always a plain string: a doc id + source path (e.g.
-- "docstore:9f2a#/reports/q3.md"), NEVER a live SurrealDB record link --
-- links can't safely cross store/namespace boundaries and would break the
-- moment the referenced store is re-ingested or moved.
DEFINE FIELD OVERWRITE evidence ON memory TYPE option<string>
  COMMENT "doc id + source path string; never a live record link across stores";

-- scope is the sharing primitive (cookbook sec C/D): identical scope
-- strings are how independent agents/sessions see each other's writes.
-- Path form: probata/<domain>/<agent>, e.g. probata/docstore/librarian.
DEFINE FIELD OVERWRITE scope ON memory TYPE string
  ASSERT string::matches($value, '^probata(/[a-z0-9_-]+)*$')
  COMMENT "hierarchical scope path, form probata/<domain>/<agent>";

DEFINE FIELD OVERWRITE agent ON memory TYPE string DEFAULT "unknown";

DEFINE FIELD OVERWRITE status ON memory TYPE string
  ASSERT $value IN ["active","superseded","retracted"] DEFAULT "active";

DEFINE FIELD OVERWRITE confidence ON memory TYPE float
  ASSERT $value >= 0.0 AND $value <= 1.0 DEFAULT 0.6;

DEFINE FIELD OVERWRITE observed_at ON memory TYPE datetime DEFAULT time::now();
DEFINE FIELD OVERWRITE created ON memory TYPE datetime VALUE time::now() READONLY;
DEFINE FIELD OVERWRITE updated ON memory TYPE datetime VALUE time::now();
DEFINE FIELD OVERWRITE embedding ON memory TYPE option<array<float, 2048>>;

DEFINE INDEX OVERWRITE memory_kind          ON memory FIELDS kind;
DEFINE INDEX OVERWRITE memory_status        ON memory FIELDS status;
DEFINE INDEX OVERWRITE memory_scope         ON memory FIELDS scope;
DEFINE INDEX OVERWRITE memory_scope_status_kind ON memory FIELDS scope, status, kind;
DEFINE INDEX OVERWRITE memory_claim_uq      ON memory FIELDS scope, claim UNIQUE;
DEFINE INDEX OVERWRITE memory_claim_ft      ON memory FIELDS claim
  FULLTEXT ANALYZER doc_text BM25 HIGHLIGHTS;
DEFINE INDEX OVERWRITE memory_vec ON memory
  FIELDS embedding HNSW DIMENSION 2048 DIST COSINE TYPE F32
  EFC 150 M 12 CONCURRENTLY;

-- Every status change (e.g. active -> superseded, active -> retracted) is
-- logged, never silently dropped. This is the audit trail for "supersession
-- never overwrite" (D-154 / cookbook sec F "reflect(persist)" pattern note:
-- writes are additive, chains stay inspectable).
DEFINE EVENT OVERWRITE memory_status_changed ON TABLE memory
  WHEN $event = "UPDATE" AND $before.status != $after.status THEN (
    CREATE decision_log SET
      subject = $after.id,
      actor = ($auth.id OR "system"),
      action = "memory_status_changed",
      from_status = $before.status,
      to_status = $after.status
  );

-- ---------------------------------------------------------------------
-- decision_log: append-only audit trail. Never updated, never deleted.
DEFINE TABLE OVERWRITE decision_log TYPE NORMAL SCHEMAFULL;

DEFINE FIELD OVERWRITE subject     ON decision_log TYPE record<memory>;
DEFINE FIELD OVERWRITE actor       ON decision_log TYPE string;
DEFINE FIELD OVERWRITE action      ON decision_log TYPE string;
DEFINE FIELD OVERWRITE from_status ON decision_log TYPE option<string>;
DEFINE FIELD OVERWRITE to_status   ON decision_log TYPE option<string>;
DEFINE FIELD OVERWRITE reason      ON decision_log TYPE option<string>;
DEFINE FIELD OVERWRITE created     ON decision_log TYPE datetime VALUE time::now() READONLY;

DEFINE INDEX OVERWRITE decision_log_subject ON decision_log FIELDS subject;

-- ---------------------------------------------------------------------
-- episode: raw session notes, the reflection-loop input (cookbook sec F:
-- reflect() is an explicit, app-triggered synthesis pass over episodes,
-- never automatic). Condensing episodes into memory rows is the agent's
-- job; fn::reflect (085) only selects and marks episodes reflected=true.
DEFINE TABLE OVERWRITE episode TYPE NORMAL SCHEMAFULL;

DEFINE FIELD OVERWRITE scope ON episode TYPE string
  ASSERT string::matches($value, '^probata(/[a-z0-9_-]+)*$')
  COMMENT "hierarchical scope path, form probata/<domain>/<agent>";
DEFINE FIELD OVERWRITE agent      ON episode TYPE string DEFAULT "unknown";
DEFINE FIELD OVERWRITE session_id ON episode TYPE string;
DEFINE FIELD OVERWRITE text       ON episode TYPE string;
DEFINE FIELD OVERWRITE reflected  ON episode TYPE bool DEFAULT false;
DEFINE FIELD OVERWRITE created    ON episode TYPE datetime VALUE time::now() READONLY;
DEFINE FIELD OVERWRITE embedding  ON episode TYPE option<array<float, 2048>>;

DEFINE INDEX OVERWRITE episode_scope     ON episode FIELDS scope;
DEFINE INDEX OVERWRITE episode_session   ON episode FIELDS session_id;
DEFINE INDEX OVERWRITE episode_reflected ON episode FIELDS scope, reflected;
DEFINE INDEX OVERWRITE episode_text_ft   ON episode FIELDS text
  FULLTEXT ANALYZER doc_text BM25 HIGHLIGHTS;
DEFINE INDEX OVERWRITE episode_vec ON episode
  FIELDS embedding HNSW DIMENSION 2048 DIST COSINE TYPE F32
  EFC 150 M 12 CONCURRENTLY;
