-- 090_docs_api.surql
-- Domain-level docs-store API. Agents call ONLY these functions (per the
-- docstore design doc §3/§4): raw SurrealQL is the KNN-post-filter trap
-- (empty results with status OK) and the freelance-write trap. Every
-- function here keeps its scope filter inside the same WHERE as any KNN
-- predicate, and K/EF are always literal integers (parameterised K is a
-- SurrealQL parse error, even inside a function body).

-- ---------------------------------------------------------------------
-- fn::docs_search — hybrid BM25 (document title/body) + vector (chunk,
-- via the same scoped-KNN pattern as fn::search_vec in 060_functions.surql)
-- when $vec is supplied. Results are fused to document granularity.
--
-- GOTCHA (post-filter KNN): the doc_type/domain/status predicates sit
-- INSIDE the same WHERE clause as the `<|K,EF|>` operator on both the
-- narrow (<=20 k) and wide (>20 k) branches below, so SurrealDB folds
-- them into the KnnScan plan node itself. Applying them as a wrapping
-- SELECT ... FROM (subquery) WHERE ... post-filter would only look
-- inside the fixed top-K candidate set the HNSW index already returned,
-- silently truncating recall for narrow scopes while reporting status OK.
--
-- GOTCHA (K literal): K/EF must be integer literals inside `<|K,EF|>`.
-- $k only controls the final LIMIT after fusion. Because the caller can
-- ask for more than the default pool, this function carries TWO literal
-- KNN variants (<|20,128|> and, when $k > 20, <|50,256|>) rather than
-- trying to parameterise K.
--
-- GOTCHA (status default): unscoped search must not silently include
-- superseded/retracted rows, so status defaults to "active" here, same
-- as fn::search_vec/fn::search_text.
-- ---------------------------------------------------------------------
DEFINE FUNCTION OVERWRITE fn::docs_search(
  $query: string,
  $vec: option<array<float>>,
  $doc_type: option<string>,
  $domain: option<string>,
  $status: option<string>,
  $k: option<int>
) {
  LET $status_f = $status ?? "active";
  LET $k_eff = $k ?? 10;

  -- BM25 over document title/body, scope predicates inline.
  LET $text_hits = (
    SELECT id, source_path, title, doc_type, domains, status,
           (search::score(1) + search::score(2)) AS score,
           (search::highlight("<<", ">>", 2)
             OR search::highlight("<<", ">>", 1)) AS excerpt
    FROM document
    WHERE (title @1@ $query OR body @2@ $query)
      AND status = $status_f
      AND ($doc_type = NONE OR doc_type = $doc_type)
      AND ($domain = NONE OR $domain INSIDE domains)
    ORDER BY score DESC
    LIMIT ($k_eff * 3)
  );

  -- Vector recall over chunks. Scope filtering uses the denormalised
  -- columns on `chunk` (020_chunks.surql) so the KNN scan never joins;
  -- the chunk_of edge is traversed only for the surviving hits.
  -- Scope predicates are inline with the KNN operator on both branches.
  LET $vec_hits = IF $vec == NONE { [] }
    ELSE IF $k_eff > 20 {
      (
        SELECT array::first(->chunk_of->document) AS doc,
               text AS excerpt, vector::distance::knn() AS dist
        FROM chunk
        WHERE embedding <|50,256|> $vec
          AND status = $status_f
          AND ($doc_type = NONE OR doc_type = $doc_type)
          AND ($domain = NONE OR $domain INSIDE domains)
        ORDER BY dist
      )
    } ELSE {
      (
        SELECT array::first(->chunk_of->document) AS doc,
               text AS excerpt, vector::distance::knn() AS dist
        FROM chunk
        WHERE embedding <|20,128|> $vec
          AND status = $status_f
          AND ($doc_type = NONE OR doc_type = $doc_type)
          AND ($domain = NONE OR $domain INSIDE domains)
        ORDER BY dist
      )
    };

  -- Collapse per-chunk vector hits to one row per document (best chunk).
  --
  -- GOTCHA: `array::first(field)` inside a GROUP BY is NOT an aggregate
  -- here — it runs per-row on the (scalar) field value, errors to NONE,
  -- and only THEN gets collected by the implicit per-group array, which
  -- silently produces an array of NULLs (verified live against 3.2.0:
  -- `array::first(name)` returned `[null, null]`). The working idiom is
  -- `array::first(array::group(field))`: `array::group()` performs the
  -- real aggregation into a per-group array, and `array::first()` then
  -- legitimately picks its first element. `math::max()` is a true
  -- aggregate already and needs no such wrapping.
  -- Dereference the edge once, then collapse to one row per document.
  -- `doc` is a record<document>; SurrealDB auto-fetches through dot notation.
  -- Chunks with no chunk_of edge (a partial run) yield doc = NONE and are
  -- dropped here rather than fusing a NULL-id row into the results.
  LET $vec_flat = (
    SELECT doc.id AS id, doc.source_path AS source_path, doc.title AS title,
           doc.doc_type AS doc_type, doc.domains AS domains,
           doc.status AS status, excerpt, dist
    FROM $vec_hits
    WHERE doc != NONE
  );

  LET $vec_docs = (
    SELECT id,
           array::first(array::group(source_path)) AS source_path,
           array::first(array::group(title)) AS title,
           array::first(array::group(doc_type)) AS doc_type,
           array::first(array::group(domains)) AS domains,
           array::first(array::group(status)) AS status,
           math::max(1 - dist) AS score,
           array::first(array::group(excerpt)) AS excerpt
    FROM $vec_flat
    GROUP BY id
  );

  -- Fuse: max score per document id, keep first non-null projection.
  -- Same array::group() gotcha applies to this second GROUP BY.
  LET $combined = array::concat($text_hits, $vec_docs);
  LET $final = (
    SELECT id,
           array::first(array::group(source_path)) AS source_path,
           array::first(array::group(title)) AS title,
           array::first(array::group(doc_type)) AS doc_type,
           array::first(array::group(domains)) AS domains,
           array::first(array::group(status)) AS status,
           math::max(score) AS score,
           array::first(array::group(excerpt)) AS excerpt
    FROM $combined
    GROUP BY id
    ORDER BY score DESC
    LIMIT $k_eff
  );

  RETURN $final;
} COMMENT "Hybrid BM25 + scoped-KNN document search. Scope predicates inline with KNN; K/EF literal; status defaults active." PERMISSIONS FULL;

-- ---------------------------------------------------------------------
-- fn::docs_get — one document plus its supersedes neighbourhood in both
-- edge directions (edge is new->supersedes->old, per fn::docs_new_version
-- below): `supersedes` = older documents this one replaces, `superseded_by`
-- = newer documents that replace this one.
-- ---------------------------------------------------------------------
DEFINE FUNCTION OVERWRITE fn::docs_get($id: record<document>) {
  RETURN {
    document: (SELECT * FROM ONLY $id),
    status: (SELECT VALUE status FROM ONLY $id),
    supersedes: (SELECT * FROM $id->supersedes->document),
    superseded_by: (SELECT * FROM $id<-supersedes<-document)
  };
} COMMENT "Document plus its supersedes neighbourhood in both directions, and its status." PERMISSIONS FULL;

-- ---------------------------------------------------------------------
-- fn::docs_register — creates a document. Refuses (returns an error
-- object; never THROWs) when an active-lineage document already exists
-- at the same source_path, i.e. status != "superseded". A superseded
-- row at that path is fine to coexist with (it is history, not a
-- collision) — that is exactly what fn::docs_new_version produces.
-- ---------------------------------------------------------------------
DEFINE FUNCTION OVERWRITE fn::docs_register(
  $source_path: string,
  $title: string,
  $doc_type: string,
  $domains: array<string>,
  $status: string,
  $body: string,
  $authored_at: option<datetime>
) {
  LET $existing = (
    SELECT id FROM document
    WHERE source_path = $source_path AND status != "superseded"
    LIMIT 1
  );

  IF array::len($existing) > 0 {
    RETURN {
      ok: false,
      error: "duplicate_active_document",
      source_path: $source_path,
      existing_id: $existing[0].id
    };
  };

  LET $new = CREATE ONLY document SET
    source_path  = $source_path,
    title        = $title,
    doc_type     = $doc_type,
    domains      = $domains,
    status       = $status,
    body         = $body,
    content_hash = crypto::sha256($body),
    authored_at  = $authored_at;

  RETURN { ok: true, id: $new.id };
} COMMENT "Registers a new document; refuses (error object, no throw) if source_path already has a non-superseded row." PERMISSIONS FULL;

-- ---------------------------------------------------------------------
-- fn::docs_new_version — new document inherits type/domains/source_path
-- from $old; new->supersedes->old; old flips to superseded. This is the
-- one legitimate way an active source_path gets a second live row: the
-- old row's status changes to "superseded" in the SAME call, so
-- fn::docs_register's uniqueness check never sees two active rows.
-- ---------------------------------------------------------------------
DEFINE FUNCTION OVERWRITE fn::docs_new_version(
  $old: record<document>,
  $body: string,
  $title: option<string>
) {
  LET $old_doc = (SELECT * FROM ONLY $old);
  LET $new_title = $title ?? $old_doc.title;

  LET $new = CREATE ONLY document SET
    source_path  = $old_doc.source_path,
    title        = $new_title,
    doc_type     = $old_doc.doc_type,
    domains      = $old_doc.domains,
    status       = "active",
    body         = $body,
    content_hash = crypto::sha256($body),
    authored_at  = time::now();

  LET $new_id = $new.id;
  RELATE $new_id->supersedes->$old SET at = time::now();
  UPDATE $old SET status = "superseded";

  RETURN { new: $new_id, old: $old };
} COMMENT "New version of $old: inherits type/domains/source_path, RELATEs new->supersedes->old, flips old to superseded." PERMISSIONS FULL;

-- ---------------------------------------------------------------------
-- fn::docs_supersede — edge + status flip only, no new document created
-- (for when the "new" document already exists, e.g. registered
-- separately and now needs to be linked as the replacement of $old).
-- ---------------------------------------------------------------------
DEFINE FUNCTION OVERWRITE fn::docs_supersede(
  $new: record<document>,
  $old: record<document>
) {
  RELATE $new->supersedes->$old SET at = time::now();
  UPDATE $old SET status = "superseded";
  RETURN { new: $new, old: $old };
} COMMENT "Edge + status flip only: new->supersedes->old, old.status = superseded." PERMISSIONS FULL;

-- ---------------------------------------------------------------------
-- fn::decision_amend — append-only decision_log row plus optional close
-- of documents. $subject is the source_path of "the decision document";
-- when a document exists at that path (doc_type = "decision"), each
-- $closes document gets a supersedes edge from it and flips to
-- superseded. When no such decision document exists, this is just the
-- log row (nothing to attribute the edge to) — kept simple and safe.
--
-- GOTCHA: decision_log (030_records.surql) has no `note` field; the
-- closest existing field is `rationale`, which is what $banner is
-- written to. `subject` on decision_log is a non-optional `record`, so
-- if neither a decision document nor any $closes item exists there is
-- nothing valid to write as subject — that case returns an error
-- object instead of violating the schema.
-- ---------------------------------------------------------------------
DEFINE FUNCTION OVERWRITE fn::decision_amend(
  $subject: string,
  $banner: string,
  $closes: option<array<record<document>>>
) {
  LET $closes_arr = $closes ?? [];

  LET $decision_doc = (
    SELECT id FROM document
    WHERE source_path = $subject AND doc_type = "decision"
    LIMIT 1
  );
  LET $decision_id = IF array::len($decision_doc) > 0 { $decision_doc[0].id } ELSE { NONE };

  LET $log_subject = IF $decision_id != NONE { $decision_id }
    ELSE IF array::len($closes_arr) > 0 { $closes_arr[0] }
    ELSE { NONE };

  IF $log_subject == NONE {
    RETURN {
      ok: false,
      error: "no_subject_record",
      detail: "no decision document at that source_path and no $closes items given"
    };
  };

  CREATE decision_log SET
    subject   = $log_subject,
    actor     = "system",
    action    = "decision_amended",
    rationale = $banner;

  IF $decision_id != NONE {
    FOR $c IN $closes_arr {
      RELATE $decision_id->supersedes->$c SET at = time::now();
      UPDATE $c SET status = "superseded";
    };
  };

  RETURN {
    ok: true,
    subject: $log_subject,
    decision_document: $decision_id,
    closed: $closes_arr
  };
} COMMENT "Append-only decision_log row (rationale = $banner); closes $closes docs via supersedes only if a decision doc exists at $subject." PERMISSIONS FULL;

-- ---------------------------------------------------------------------
-- fn::todo_open / fn::todo_close — over the existing `todo` table
-- (030_records.surql). Respects its ASSERT lists: priority 0..4,
-- status enum driven by the table's own DEFAULT/ASSERT and the
-- todo_status_change / todo_close_stamp EVENTs in 050_events.surql.
--
-- GOTCHA: `todo` has NO `domains` column (only document/chunk do).
-- Rather than altering the existing schema (out of scope here),
-- $domains is folded into `detail` as "domains:a,b" so the information
-- is not silently dropped. $source is a source_path string, resolved
-- to `source_doc` (record<document>) when a match exists.
-- ---------------------------------------------------------------------
DEFINE FUNCTION OVERWRITE fn::todo_open(
  $item: string,
  $priority: int,
  $domains: array<string>,
  $source: option<string>
) {
  LET $src_match = IF $source == NONE { [] } ELSE {
    (SELECT id FROM document WHERE source_path = $source LIMIT 1)
  };
  LET $src_id = IF array::len($src_match) > 0 { $src_match[0].id } ELSE { NONE };

  LET $detail_txt = "domains:" + array::join($domains, ",")
    + (IF $source != NONE { " | source:" + $source } ELSE { "" });

  LET $new = CREATE ONLY todo SET
    title      = $item,
    priority   = $priority,
    detail     = $detail_txt,
    source_doc = $src_id;

  RETURN { id: $new.id, title: $item, priority: $priority, domains: $domains, source_doc: $src_id };
} COMMENT "Opens a todo. No domains column on todo (gotcha): folded into detail. $source resolved to source_doc when it matches a document." PERMISSIONS FULL;

DEFINE FUNCTION OVERWRITE fn::todo_close($id: record<todo>, $evidence: string) {
  LET $before = (SELECT * FROM ONLY $id);

  -- GOTCHA: closed_at is set by the todo_close_stamp EVENT
  -- (050_events.surql) on the done/dropped transition. Do not set it
  -- here too — that would just be an immediate second write.
  UPDATE $id SET
    status = "done",
    detail = ($before.detail OR "") + " | closed_evidence:" + $evidence;

  RETURN (SELECT * FROM ONLY $id);
} COMMENT "Closes a todo as done with evidence appended to detail; closed_at comes from the todo_close_stamp EVENT." PERMISSIONS FULL;

-- ---------------------------------------------------------------------
-- fn::handoff_write — new active handoff document; supersedes the
-- previous active handoff whose domains overlap $domains (if any),
-- using the same new->supersedes->old + status-flip semantics as
-- fn::docs_new_version (reimplemented inline because the new document's
-- title/domains are caller-given here, not inherited from $old).
-- ---------------------------------------------------------------------
DEFINE FUNCTION OVERWRITE fn::handoff_write(
  $title: string,
  $body: string,
  $domains: array<string>
) {
  LET $prev = (
    SELECT id FROM document
    WHERE doc_type = "handoff" AND status = "active"
      AND array::len(array::intersect(domains, $domains)) > 0
    LIMIT 1
  );

  LET $slug = string::lowercase(string::replace($title, " ", "-"));
  LET $path = "handoff://" + $slug + "/" + <string>rand::uuid();

  LET $new = CREATE ONLY document SET
    source_path  = $path,
    title        = $title,
    doc_type     = "handoff",
    domains      = $domains,
    status       = "active",
    body         = $body,
    content_hash = crypto::sha256($body),
    authored_at  = time::now();
  LET $new_id = $new.id;

  LET $prev_id = IF array::len($prev) > 0 { $prev[0].id } ELSE { NONE };
  LET $superseded = IF $prev_id != NONE {
    RELATE $new_id->supersedes->$prev_id SET at = time::now();
    UPDATE $prev_id SET status = "superseded";
    $prev_id
  } ELSE { NONE };

  RETURN { id: $new_id, superseded: $superseded };
} COMMENT "New active handoff doc; supersedes the previous active handoff with overlapping domains, if any." PERMISSIONS FULL;
