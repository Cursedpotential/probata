-- 070_access.surql
-- Two roles. The librarian writes; everyone else reads through functions.
--
-- IMPORTANT: a table-level PERMISSIONS clause is applied OUTSIDE the query
-- plan, so it acts as a post-filter on KNN results and shows up in neither
-- EXPLAIN's KnnScan predicate nor a Filter node. Scope filters therefore
-- live in fn::search_vec's WHERE clause, not here.

DEFINE ACCESS OVERWRITE librarian ON DATABASE TYPE RECORD
  SIGNIN { RETURN NONE } DURATION FOR TOKEN 15m, FOR SESSION 12h;

-- Reader-facing tables are permissioned NONE for direct select:
-- retrieval must go through the DEFINE FUNCTION surface.
-- Comment these out during development.
-- DEFINE TABLE OVERWRITE chunk PERMISSIONS FOR select NONE;
