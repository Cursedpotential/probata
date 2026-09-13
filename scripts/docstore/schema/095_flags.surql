-- Owner-authorized note/decision flags, 2026-09-12. Independent of CocoIndex-owned rows.
-- Additive only; do not run unrelated schema files to install this extension.
DEFINE TABLE IF NOT EXISTS docstore_flag SCHEMAFULL PERMISSIONS NONE;
DEFINE FIELD IF NOT EXISTS subject ON docstore_flag TYPE string;
DEFINE FIELD IF NOT EXISTS title ON docstore_flag TYPE string;
DEFINE FIELD IF NOT EXISTS summary ON docstore_flag TYPE string;
DEFINE FIELD IF NOT EXISTS priority ON docstore_flag TYPE string ASSERT $value IN ['critical','high','normal'];
DEFINE FIELD IF NOT EXISTS authority ON docstore_flag TYPE string ASSERT $value IN ['owner_decision','verified_finding','proposal'];
DEFINE FIELD IF NOT EXISTS status ON docstore_flag TYPE string ASSERT $value IN ['active','superseded','retracted'];
DEFINE FIELD IF NOT EXISTS domains ON docstore_flag TYPE array<string>;
DEFINE FIELD IF NOT EXISTS source_ref ON docstore_flag TYPE string;
DEFINE FIELD IF NOT EXISTS rationale ON docstore_flag TYPE string;
DEFINE FIELD IF NOT EXISTS actor ON docstore_flag TYPE string;
DEFINE FIELD IF NOT EXISTS revision ON docstore_flag TYPE int ASSERT $value > 0;
DEFINE FIELD IF NOT EXISTS change_hash ON docstore_flag TYPE string;
DEFINE FIELD IF NOT EXISTS updated_at ON docstore_flag TYPE datetime VALUE time::now();
DEFINE INDEX IF NOT EXISTS docstore_flag_subject ON docstore_flag FIELDS subject UNIQUE;
DEFINE INDEX IF NOT EXISTS docstore_flag_scope ON docstore_flag FIELDS priority, status, domains;
DEFINE TABLE IF NOT EXISTS docstore_flag_audit SCHEMAFULL PERMISSIONS NONE;
DEFINE FIELD IF NOT EXISTS subject ON docstore_flag_audit TYPE string;
DEFINE FIELD IF NOT EXISTS revision ON docstore_flag_audit TYPE int;
DEFINE FIELD IF NOT EXISTS snapshot ON docstore_flag_audit TYPE string;
DEFINE FIELD IF NOT EXISTS at ON docstore_flag_audit TYPE datetime VALUE time::now();
DEFINE INDEX IF NOT EXISTS docstore_flag_audit_revision ON docstore_flag_audit FIELDS subject, revision UNIQUE;
