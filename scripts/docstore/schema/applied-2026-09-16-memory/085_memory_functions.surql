-- 085_memory_functions.surql
-- D-154 shared-memory function surface. Guarded writes, explicit
-- supersession (never overwrite), explicit retraction (never DELETE),
-- reflection as a manual/app-triggered synthesis pass (cookbook sec F:
-- reflect() is never automatic), and RRF recall over BM25 + KNN.
--
-- KNN literal-K note (verified empirically against the local 3.2.0 engine,
-- 2026-09-09): the `<|K, EF|>` operator requires K and EF as query-literal
-- integers -- passing a bound variable for K is not how the operator is
-- used anywhere in the SurrealDB docs/skill examples. fn::recall therefore
-- uses a fixed literal candidate pool (<|20,40|>) for the KNN leg and
-- applies the caller's $k only as the final LIMIT after RRF fusion.
--
-- RRF fusion note: SurrealQL has no built-in RRF/hybrid-search function
-- (confirmed against surrealdb-vector skill: "Application-level fusion is
-- recommended for proper score normalization"). Fusion is implemented here
-- with array::find_index() rank lookups against the two ordered candidate
-- id-arrays, since SurrealQL has no map/reduce; not-found returns NONE by
-- experiment (`array::find_index([1,2,3], 5)` -> NONE), which the IF-guard
-- reads directly.

-- ---------------------------------------------------------------------
DEFINE FUNCTION OVERWRITE fn::remember($payload: object) {
  LET $scope = $payload.scope;
  LET $claim = $payload.claim;

  LET $bm25_conflicts = (
    SELECT id, claim, confidence, status FROM memory
    WHERE scope = $scope AND status = "active" AND claim @@ $claim
    LIMIT 5
  );

  LET $vec_conflicts = IF $payload.embedding != NONE {
    (SELECT id, claim, confidence, status, vector::distance::knn() AS dist
     FROM memory
     WHERE scope = $scope AND status = "active"
       AND embedding <|5,40|> $payload.embedding)
  } ELSE {
    []
  };

  LET $conflicts = array::concat($bm25_conflicts, $vec_conflicts);

  IF array::len($conflicts) > 0 AND $payload.force != true AND $payload.supersede = NONE {
    RETURN {
      written: NONE,
      conflicts: $conflicts,
      note: "Similar active memory exists in this scope. Pass force:true or supersede:<id> to proceed."
    };
  };

  IF $payload.supersede != NONE {
    RETURN fn::supersede_memory(
      $payload.supersede,
      $payload,
      ($payload.reason OR "fn::remember: explicit supersede")
    );
  };

  LET $new = (CREATE ONLY memory SET
    kind        = $payload.kind,
    claim       = $payload.claim,
    detail      = $payload.detail,
    evidence    = $payload.evidence,
    scope       = $payload.scope,
    agent       = $payload.agent,
    confidence  = ($payload.confidence OR 0.6),
    observed_at = ($payload.observed_at OR time::now()),
    embedding   = $payload.embedding
  );
  RETURN { written: $new.id, conflicts: [] };
} COMMENT "Guarded memory write: refuses silent duplication (BM25 + vector conflict check), unless force:true or supersede:<id>." PERMISSIONS FULL;

-- ---------------------------------------------------------------------
DEFINE FUNCTION OVERWRITE fn::supersede_memory($old: record<memory>, $new_payload: object) {
  LET $new = (CREATE ONLY memory SET
    kind        = $new_payload.kind,
    claim       = $new_payload.claim,
    detail      = $new_payload.detail,
    evidence    = $new_payload.evidence,
    scope       = $new_payload.scope,
    agent       = $new_payload.agent,
    confidence  = ($new_payload.confidence OR 0.6),
    observed_at = ($new_payload.observed_at OR time::now()),
    embedding   = $new_payload.embedding
  );
  RELATE ($new.id)->supersedes->$old SET at = time::now();
  UPDATE $old SET status = "superseded";
  RETURN { new: $new, old: (SELECT * FROM ONLY $old) };
} COMMENT "Correct a memory without ever destroying it: new row, RELATE edge, old row flipped to superseded. Chain stays inspectable via ->supersedes->." PERMISSIONS FULL;

-- ---------------------------------------------------------------------
DEFINE FUNCTION OVERWRITE fn::forget($id: record<memory>, $reason: string) {
  LET $updated = (UPDATE ONLY $id SET status = "retracted");
  -- Supplemental, reason-bearing audit row. memory_status_changed (080)
  -- also fires on this UPDATE and writes its own reason-less row -- two
  -- decision_log rows for one retraction is intentional (full audit trail,
  -- append-only, never overwritten).
  CREATE decision_log SET
    subject     = $id,
    actor       = ($auth.id OR "system"),
    action      = "memory_forgotten",
    from_status = NONE,
    to_status   = "retracted",
    reason      = $reason;
  RETURN $updated;
} COMMENT "Retract a memory (status = retracted) with a reason. Never DELETEs -- the row and its history stay queryable." PERMISSIONS FULL;

-- ---------------------------------------------------------------------
DEFINE FUNCTION OVERWRITE fn::recall(
  $query: string, $vec: option<array<float>>, $scope: string, $k: int
) {
  LET $bm25 = (
    SELECT id, claim, kind, confidence, observed_at, evidence,
           search::score(1) AS score
    FROM memory
    WHERE status = "active"
      AND (scope = $scope OR string::starts_with(scope, $scope + "/"))
      AND claim @1@ $query
    ORDER BY score DESC
    LIMIT 20
  );

  LET $vecres = IF $vec != NONE {
    (SELECT id, claim, kind, confidence, observed_at, evidence,
            vector::distance::knn() AS dist
     FROM memory
     WHERE status = "active"
       AND (scope = $scope OR string::starts_with(scope, $scope + "/"))
       AND embedding <|20,40|> $vec
     ORDER BY dist ASC)
  } ELSE {
    []
  };

  LET $bm25_ids = $bm25.id;
  LET $vec_ids  = $vecres.id;
  LET $all_ids  = array::distinct(array::concat($bm25_ids, $vec_ids));
  LET $rrf_k    = 60;

  LET $fused = (
    SELECT id, claim, kind, confidence, observed_at, evidence, status,
      ((IF array::find_index($bm25_ids, id) != NONE {
          1.0 / ($rrf_k + array::find_index($bm25_ids, id) + 1)
        } ELSE { 0.0 })
       +
       (IF array::find_index($vec_ids, id) != NONE {
          1.0 / ($rrf_k + array::find_index($vec_ids, id) + 1)
        } ELSE { 0.0 })) AS rrf_score
    FROM $all_ids
    WHERE status = "active"
    ORDER BY rrf_score DESC
    LIMIT $k
  );

  RETURN $fused;
} COMMENT "RRF fusion of BM25 (claim @1@) and KNN (literal K=20, EF=40) over active claims whose scope equals or is a prefix-descendant of $scope. Final result truncated to caller's $k." PERMISSIONS FULL;

-- ---------------------------------------------------------------------
DEFINE FUNCTION OVERWRITE fn::reflect($scope: string, $since: datetime) {
  LET $eps = (
    SELECT * FROM episode
    WHERE (scope = $scope OR string::starts_with(scope, $scope + "/"))
      AND created >= $since
      AND reflected = false
    ORDER BY session_id, created ASC
  );
  UPDATE episode SET reflected = true WHERE id IN $eps.id;
  RETURN $eps;
} COMMENT "Selects unreflected episodes since $since for the given scope (and its descendants) and marks them reflected. Condensing into memory rows is the calling agent's job, not this function's." PERMISSIONS FULL;

-- ---------------------------------------------------------------------
DEFINE FUNCTION OVERWRITE fn::memory_stats($scope: string) {
  RETURN {
    scope: $scope,
    total: (SELECT count() FROM memory
            WHERE scope = $scope OR string::starts_with(scope, $scope + "/")
            GROUP ALL)[0].count,
    active: (SELECT count() FROM memory
             WHERE (scope = $scope OR string::starts_with(scope, $scope + "/"))
               AND status = "active"
             GROUP ALL)[0].count,
    superseded: (SELECT count() FROM memory
                 WHERE (scope = $scope OR string::starts_with(scope, $scope + "/"))
                   AND status = "superseded"
                 GROUP ALL)[0].count,
    retracted: (SELECT count() FROM memory
                WHERE (scope = $scope OR string::starts_with(scope, $scope + "/"))
                  AND status = "retracted"
                GROUP ALL)[0].count,
    by_kind: (SELECT kind, count() AS n FROM memory
              WHERE (scope = $scope OR string::starts_with(scope, $scope + "/"))
                AND status = "active"
              GROUP BY kind),
    episodes_pending_reflection: (SELECT count() FROM episode
                                   WHERE (scope = $scope OR string::starts_with(scope, $scope + "/"))
                                     AND reflected = false
                                   GROUP ALL)[0].count
  };
} COMMENT "Point-in-time counts for a scope and its descendants: total/active/superseded/retracted memory rows, by-kind breakdown, and episodes still awaiting reflection." PERMISSIONS FULL;
