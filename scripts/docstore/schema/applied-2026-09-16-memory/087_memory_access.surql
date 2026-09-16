-- 087_memory_access.surql
-- Key/principal hierarchy (cookbook sec C/D/E.3): every agent authenticates
-- with its own key, minted against a principal record that carries a
-- scope-prefix grant and a role. Scope-prefix enforcement itself lives in
-- fn::remember/fn::recall/etc (085) and in the memory/episode scope ASSERT
-- (080) -- DEFINE ACCESS only proves *who* the caller is; it does not by
-- itself filter *what* they can see. That mirrors the cookbook finding:
-- "A key bound to a principal granted memory:read/memory:write on a scope
-- can read/write at that scope" -- the principal/grant row is the real
-- enforcement point, scope-path equality alone is just a retrieval filter.

DEFINE TABLE OVERWRITE principal TYPE NORMAL SCHEMAFULL;

DEFINE FIELD OVERWRITE name         ON principal TYPE string;
DEFINE FIELD OVERWRITE key_hash     ON principal TYPE string
  COMMENT "crypto::argon2::generate() PHC string of the agent's key. Never store the raw key.";
DEFINE FIELD OVERWRITE scope_prefix ON principal TYPE string
  ASSERT string::matches($value, '^probata(/[a-z0-9_-]+)*$')
  COMMENT "hierarchical scope-path prefix this principal is granted; agents may only remember/recall at or below this prefix.";
DEFINE FIELD OVERWRITE role         ON principal TYPE string
  ASSERT $value IN ["reader","writer","curator"];
DEFINE FIELD OVERWRITE created      ON principal TYPE datetime VALUE time::now() READONLY;

DEFINE INDEX OVERWRITE principal_name_uq ON principal FIELDS name UNIQUE;
DEFINE INDEX OVERWRITE principal_scope   ON principal FIELDS scope_prefix;

-- Every agent gets its own key, scoped to a path prefix. SIGNUP is
-- intentionally omitted -- principals are provisioned out-of-band (by a
-- curator inserting a `principal` row with a pre-hashed key), never
-- self-registered. SIGNIN checks name + key against key_hash.
DEFINE ACCESS OVERWRITE agent ON DATABASE TYPE RECORD
  SIGNIN (
    SELECT * FROM principal
    WHERE name = $name AND crypto::argon2::compare(key_hash, $key)
  )
  DURATION FOR TOKEN 15m, FOR SESSION 12h;

-- Readers may only execute functions (fn::recall, fn::memory_stats, ...),
-- never SELECT the memory/episode tables directly -- this keeps every read
-- path funneled through the scope-prefix + status-filter logic in 085,
-- the same reasoning the kit's own 070_access.surql documents for `chunk`:
--
--   "a table-level PERMISSIONS clause is applied OUTSIDE the query plan,
--    so it acts as a post-filter on KNN results and shows up in neither
--    EXPLAIN's KnnScan predicate nor a Filter node. Scope filters therefore
--    live in the function's WHERE clause, not here."
--
-- Left commented during development/verification (this file's own
-- verification pass reads `memory`/`episode` directly via root auth to
-- confirm state) -- uncomment before pointing any non-root/non-function
-- client at this schema.
-- DEFINE TABLE OVERWRITE memory  PERMISSIONS FOR select NONE;
-- DEFINE TABLE OVERWRITE episode PERMISSIONS FOR select NONE;
