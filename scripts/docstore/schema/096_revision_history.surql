-- Docstore control history, owner-approved 2026-09-12. Additive; no projection writes.
DEFINE TABLE IF NOT EXISTS docstore_document SCHEMAFULL PERMISSIONS NONE;
DEFINE FIELD IF NOT EXISTS document_key ON docstore_document TYPE string;
DEFINE FIELD IF NOT EXISTS source_path ON docstore_document TYPE string;
DEFINE FIELD IF NOT EXISTS title ON docstore_document TYPE string;
DEFINE FIELD IF NOT EXISTS generation ON docstore_document TYPE int;
DEFINE FIELD IF NOT EXISTS latest_number ON docstore_document TYPE int;
DEFINE FIELD IF NOT EXISTS current_revision ON docstore_document TYPE record<docstore_revision>;
DEFINE FIELD IF NOT EXISTS approved_revision ON docstore_document TYPE option<record<docstore_revision>>;
DEFINE FIELD IF NOT EXISTS current_hash ON docstore_document TYPE string;
DEFINE FIELD IF NOT EXISTS updated_at ON docstore_document TYPE datetime
  VALUE time::now();
DEFINE INDEX IF NOT EXISTS docstore_document_key ON docstore_document FIELDS document_key
  UNIQUE;

DEFINE TABLE IF NOT EXISTS docstore_source_alias SCHEMAFULL PERMISSIONS NONE;
DEFINE FIELD IF NOT EXISTS source_path ON docstore_source_alias TYPE string;
DEFINE FIELD IF NOT EXISTS document ON docstore_source_alias TYPE record<docstore_document>;
DEFINE FIELD IF NOT EXISTS actor ON docstore_source_alias TYPE string;
DEFINE FIELD IF NOT EXISTS at ON docstore_source_alias TYPE datetime
  DEFAULT time::now();
DEFINE INDEX IF NOT EXISTS docstore_alias_path ON docstore_source_alias FIELDS source_path
  UNIQUE;
DEFINE INDEX IF NOT EXISTS docstore_alias_document ON docstore_source_alias FIELDS document;

DEFINE TABLE IF NOT EXISTS docstore_revision SCHEMAFULL PERMISSIONS NONE;
DEFINE FIELD IF NOT EXISTS document ON docstore_revision TYPE record<docstore_document>
  READONLY;
DEFINE FIELD IF NOT EXISTS number ON docstore_revision TYPE int READONLY;
DEFINE FIELD IF NOT EXISTS body ON docstore_revision TYPE string READONLY;
DEFINE FIELD IF NOT EXISTS raw_sha256 ON docstore_revision TYPE string READONLY;
DEFINE FIELD IF NOT EXISTS projection_sha256 ON docstore_revision TYPE string
  READONLY;
DEFINE FIELD IF NOT EXISTS projection_profile ON docstore_revision TYPE string
  READONLY;
DEFINE FIELD IF NOT EXISTS source_path ON docstore_revision TYPE string READONLY;
DEFINE FIELD IF NOT EXISTS actor ON docstore_revision TYPE string READONLY;
DEFINE FIELD IF NOT EXISTS source_ref ON docstore_revision TYPE string READONLY;
DEFINE FIELD IF NOT EXISTS at ON docstore_revision TYPE datetime
  DEFAULT time::now()
  READONLY;
DEFINE INDEX IF NOT EXISTS docstore_revision_number ON docstore_revision FIELDS document, number
  UNIQUE;

DEFINE TABLE IF NOT EXISTS docstore_revision_event SCHEMAFULL PERMISSIONS NONE;
DEFINE FIELD IF NOT EXISTS document ON docstore_revision_event TYPE record<docstore_document>
  READONLY;
DEFINE FIELD IF NOT EXISTS generation ON docstore_revision_event TYPE int
  READONLY;
DEFINE FIELD IF NOT EXISTS revision ON docstore_revision_event TYPE record<docstore_revision>
  READONLY;
DEFINE FIELD IF NOT EXISTS source_path ON docstore_revision_event TYPE string
  READONLY;
DEFINE FIELD IF NOT EXISTS title ON docstore_revision_event TYPE string READONLY;
DEFINE FIELD IF NOT EXISTS actor ON docstore_revision_event TYPE string READONLY;
DEFINE FIELD IF NOT EXISTS source_ref ON docstore_revision_event TYPE string
  READONLY;
DEFINE FIELD IF NOT EXISTS at ON docstore_revision_event TYPE datetime
  DEFAULT time::now()
  READONLY;
DEFINE INDEX IF NOT EXISTS docstore_revision_event_generation ON docstore_revision_event FIELDS document, generation
  UNIQUE;

DEFINE TABLE IF NOT EXISTS docstore_approval SCHEMAFULL PERMISSIONS NONE;
DEFINE FIELD IF NOT EXISTS document ON docstore_approval TYPE record<docstore_document>
  READONLY;
DEFINE FIELD IF NOT EXISTS revision ON docstore_approval TYPE record<docstore_revision>
  READONLY;
DEFINE FIELD IF NOT EXISTS raw_sha256 ON docstore_approval TYPE string READONLY;
DEFINE FIELD IF NOT EXISTS actor ON docstore_approval TYPE string READONLY;
DEFINE FIELD IF NOT EXISTS rationale ON docstore_approval TYPE string READONLY;
DEFINE FIELD IF NOT EXISTS source_ref ON docstore_approval TYPE string READONLY;
DEFINE FIELD IF NOT EXISTS request_hash ON docstore_approval TYPE string
  READONLY;
DEFINE FIELD IF NOT EXISTS at ON docstore_approval TYPE datetime
  DEFAULT time::now()
  READONLY;
DEFINE INDEX IF NOT EXISTS docstore_approval_document_at ON docstore_approval FIELDS document, at;

DEFINE FUNCTION IF NOT EXISTS fn::docstore_capture_revision PERMISSIONS FULL(
  $key: string,
  $path: string,
  $title: string,
  $body: string,
  $projection_hash: string,
  $expected: int,
  $actor: string,
  $source_ref: string,
) {
  LET $rid = type::record('docstore_document', crypto::sha256($key));
  LET $head = (
    SELECT *
    FROM ONLY $rid
  );
  LET $hash = crypto::sha256($body);
  IF $head != NONE
  AND $head.current_hash = $hash
  AND $head.source_path = $path
  AND $head.title = $title {
    RETURN {
      head: $head,
      unchanged: true,
      content_appended: false,
    };
  };
  IF (
    $head.generation ?? 0
  ) != $expected {
    THROW 'revision_conflict';
  };
  LET $alias_id = type::record('docstore_source_alias', crypto::sha256($path));
  LET $alias = (
    SELECT *
    FROM ONLY $alias_id
  );
  IF $alias != NONE
  AND $alias.document != $rid {
    THROW 'source_path_conflict';
  };
  IF $alias = NONE {
    CREATE $alias_id SET
      source_path = $path,
      document = $rid,
      actor = $actor;
  };
  LET $changed = $head = NONE OR $head.current_hash != $hash;
  LET $number = (
    $head.latest_number ?? 0
  ) + (
    IF $changed {
      1;
    } ELSE {
      0;
    }
  );
  LET $revision_id = type::record(
    'docstore_revision',
    crypto::sha256($key) + '_' + <string> $number
  );
  IF $changed {
    CREATE $revision_id SET
      document = $rid,
      number = $number,
      body = $body,
      raw_sha256 = $hash,
      projection_sha256 = $projection_hash,
      projection_profile = 'docstore-fold-non-bmp-v1',
      source_path = $path,
      actor = $actor,
      source_ref = $source_ref;
  };
  LET $generation = $expected + 1;
  CREATE type::record(
    'docstore_revision_event',
    crypto::sha256($key) + '_' + <string> $generation
  ) SET
    document = $rid,
    generation = $generation,
    revision = $revision_id,
    source_path = $path,
    title = $title,
    actor = $actor,
    source_ref = $source_ref;
  LET $saved = (
    UPSERT ONLY $rid MERGE {
      document_key: $key,
      source_path: $path,
      title: $title,
      generation: $generation,
      latest_number: $number,
      current_revision: $revision_id,
      current_hash: $hash,
    }
  );
  RETURN {
    head: $saved,
    unchanged: false,
    content_appended: $changed,
  };
};

DEFINE FUNCTION IF NOT EXISTS fn::docstore_approve_revision PERMISSIONS FULL(
  $key: string,
  $number: int,
  $hash: string,
  $expected: int,
  $actor: string,
  $rationale: string,
  $source_ref: string,
  $request_key: string,
  $request_hash: string,
) {
  LET $rid = type::record('docstore_document', crypto::sha256($key));
  LET $approval_id = type::record(
    'docstore_approval',
    crypto::sha256($key + ':' + $request_key)
  );
  LET $existing = (
    SELECT *
    FROM ONLY $approval_id
  );
  IF $existing != NONE {
    IF $existing.request_hash != $request_hash {
      THROW 'idempotency_conflict';
    };
    RETURN { approval: $existing, unchanged: true };
  };
  LET $head = (
    SELECT *
    FROM ONLY $rid
  );
  IF $head = NONE {
    THROW 'document_missing';
  };
  IF $head.generation != $expected {
    THROW 'revision_conflict';
  };
  IF $head.latest_number != $number
  OR $head.current_hash != $hash {
    THROW 'approval_revision_mismatch';
  };
  LET $approval = (
    CREATE ONLY $approval_id SET
      document = $rid,
      revision = $head.current_revision,
      raw_sha256 = $hash,
      actor = $actor,
      rationale = $rationale,
      source_ref = $source_ref,
      request_hash = $request_hash
  );
  UPDATE $rid SET
    approved_revision = $head.current_revision,
    generation = $expected + 1;
  RETURN { approval: $approval, unchanged: false };
};
