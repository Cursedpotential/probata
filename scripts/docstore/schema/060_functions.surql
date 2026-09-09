-- 060_functions.surql
-- The ONLY retrieval surface agents are permitted to use.
-- Agents call these via the MCP `run` tool; they never write raw KNN.
--
-- NOTE: K and EF must be literal integers in the KNN operator.
-- <|$k,64|> is a parse error, even inside a function body. Hence the
-- fixed variants below rather than a parameterised K.

-- ---------------------------------------------------------------------
-- fn::search_vec
-- Hybrid index/exact-scan. Tries HNSW; if the post-filter truncates the
-- result below K, falls back to an exact cosine scan over the scoped
-- slice. Sound because a post-filter only removes rows, never reorders:
-- a short result is a correct prefix of the right answer.
-- ---------------------------------------------------------------------
DEFINE FUNCTION OVERWRITE fn::search_vec(
  $q: array<float>,
  $project: option<string>,
  $doc_type: option<string>
) {
  LET $fast = (
    SELECT id, text, heading, document, doc_type, project,
           vector::distance::knn() AS dist
    FROM chunk
    WHERE embedding <|20,128|> $q
      AND status = "active"
      AND ($project = NONE OR project = $project)
      AND ($doc_type = NONE OR doc_type = $doc_type)
    ORDER BY dist
  );

  IF array::len($fast) >= 20 { RETURN $fast };

  -- Fallback: exact scan over the indexed slice. Sub-millisecond for
  -- narrow slices precisely because project/doc_type/status carry
  -- their own B-tree indexes.
  RETURN (
    SELECT id, text, heading, document, doc_type, project,
           1 - vector::similarity::cosine(embedding, $q) AS dist
    FROM chunk
    WHERE status = "active"
      AND ($project = NONE OR project = $project)
      AND ($doc_type = NONE OR doc_type = $doc_type)
    ORDER BY dist
    LIMIT 20
  );
} COMMENT "Scoped vector recall with exact-scan fallback." PERMISSIONS FULL;

-- ---------------------------------------------------------------------
-- fn::search_text  — BM25 keyword recall over the same scope.
-- ---------------------------------------------------------------------
DEFINE FUNCTION OVERWRITE fn::search_text(
  $terms: string,
  $project: option<string>,
  $doc_type: option<string>
) {
  RETURN (
    SELECT id, text, heading, document, doc_type, project,
           search::score(1) AS score,
           search::highlight("<<", ">>", 1) AS excerpt
    FROM chunk
    WHERE text @1@ $terms
      AND status = "active"
      AND ($project = NONE OR project = $project)
      AND ($doc_type = NONE OR doc_type = $doc_type)
    ORDER BY score DESC
    LIMIT 20
  );
} COMMENT "Scoped BM25 keyword recall." PERMISSIONS FULL;

-- ---------------------------------------------------------------------
-- fn::recall — the single entry point. Fuses vector + BM25 with
-- reciprocal rank fusion, then logs the retrieval for the feedback loop.
-- ---------------------------------------------------------------------
DEFINE FUNCTION OVERWRITE fn::recall(
  $query: string,
  $q: array<float>,
  $project: option<string>,
  $doc_type: option<string>,
  $agent: string
) {
  LET $vec = fn::search_vec($q, $project, $doc_type);
  LET $txt = fn::search_text($query, $project, $doc_type);

  LET $fused = search::rrf([$vec, $txt], 12, 60);

  LET $path = IF array::len($vec) >= 20 { "hybrid" } ELSE { "fallback" };

  CREATE retrieval SET
    query = $query,
    agent = $agent,
    scope = { project: $project, doc_type: $doc_type },
    hits  = $fused.map(|$h| $h.id),
    path  = $path;

  RETURN $fused;
} COMMENT "Primary agent retrieval entry point. Logged." PERMISSIONS FULL;

-- ---------------------------------------------------------------------
-- fn::open_work — deterministic, no embeddings involved.
-- ---------------------------------------------------------------------
DEFINE FUNCTION OVERWRITE fn::open_work($project: string) {
  RETURN (
    SELECT id, title, owner, priority, due, status
    FROM todo
    WHERE project = $project AND status IN ["open","in_progress","blocked"]
    ORDER BY priority ASC, due ASC
  );
} COMMENT "Current open work items for a project." PERMISSIONS FULL;

-- ---------------------------------------------------------------------
-- fn::current_decisions — accepted ADRs with nothing superseding them.
-- ---------------------------------------------------------------------
DEFINE FUNCTION OVERWRITE fn::current_decisions($project: string) {
  RETURN (
    SELECT id, number, title, decision, decided_at,
           ->supersedes->adr AS supersedes,
           <-supersedes<-adr AS superseded_by
    FROM adr
    WHERE project = $project AND status = "accepted"
      AND array::len(<-supersedes<-adr) = 0
    ORDER BY number DESC
  );
} COMMENT "Live decision set: accepted and not superseded." PERMISSIONS FULL;

-- ---------------------------------------------------------------------
-- fn::provenance — where did this come from, and what changed.
-- ---------------------------------------------------------------------
DEFINE FUNCTION OVERWRITE fn::provenance($subject: record) {
  RETURN {
    record: (SELECT * FROM ONLY $subject),
    history: (SELECT action, from, to, actor, at, rationale
              FROM decision_log WHERE subject = $subject ORDER BY at DESC),
    sources: (SELECT * FROM $subject->derived_from->document)
  };
} COMMENT "Full provenance and change history for one record." PERMISSIONS FULL;

-- ---------------------------------------------------------------------
-- fn::stale_candidates — what the reconciler should look at.
-- ---------------------------------------------------------------------
DEFINE FUNCTION OVERWRITE fn::stale_candidates($older_than: duration) {
  RETURN (
    SELECT id, title, doc_type, project, status, observed_at, age_days
    FROM document
    WHERE status = "active"
      AND (observed_at < time::now() - $older_than)
      AND array::len(<-derived_from<-adr) = 0
    ORDER BY observed_at ASC
    LIMIT 200
  );
} COMMENT "Active docs with no derived records and no recent activity." PERMISSIONS FULL;
