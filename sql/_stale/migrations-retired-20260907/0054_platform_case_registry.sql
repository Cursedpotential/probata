-- Migration 0054: platform-native Matter/CourtCase registry and UIW scope binding.
-- Forward-only. No legacy ai/evidence/working/ops substrate and no fabricated case rows.
-- Byline: Codex · GPT-5.6-Sol · 2026-08-30.

BEGIN;

DO $prerequisites$
DECLARE v_name TEXT;
BEGIN
    IF current_database() <> 'platform' THEN
        RAISE EXCEPTION 'migration 0054 may run only in database platform, not %', current_database();
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'platform_admin' AND NOT rolcanlogin)
       OR NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'platform_runtime' AND rolcanlogin) THEN
        RAISE EXCEPTION 'migration 0054 requires the platform role topology';
    END IF;
    IF EXISTS (
        SELECT 1 FROM pg_roles
        WHERE rolname IN ('platform_admin', 'platform_runtime')
          AND (rolsuper OR rolcreatedb OR rolcreaterole OR rolreplication OR rolbypassrls)
    ) THEN
        RAISE EXCEPTION 'migration 0054 refuses elevated platform roles';
    END IF;
    IF to_regclass('context.source_version') IS NULL
       OR to_regclass('context.uiw_source_context_revision') IS NULL THEN
        RAISE EXCEPTION 'migration 0054 requires migrations 0036 and 0053';
    END IF;
    IF EXISTS (SELECT 1 FROM public.schema_version WHERE migration_id='0043' AND status='active') THEN
        RAISE EXCEPTION 'migration 0054 refuses legacy migration 0043 state';
    END IF;
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema='context' AND table_name='source_version'
          AND column_name IN ('matter_id','court_case_id')
    ) THEN
        RAISE EXCEPTION 'migration 0054 refuses pre-existing source_version matter/case columns';
    END IF;
    FOREACH v_name IN ARRAY ARRAY[
        'source_version_matter_case_pair_check', 'source_version_source_context_scope_check',
        'source_version_matter_fk', 'source_version_court_case_scope_fk',
        'source_version_source_context_scope_fk', 'uiw_source_context_matter_fk',
        'uiw_source_context_court_case_scope_fk', 'uiw_source_context_scope_key'
    ] LOOP
        IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname=v_name) THEN
            RAISE EXCEPTION 'migration 0054 refuses duplicate/pre-existing constraint %', v_name;
        END IF;
    END LOOP;
    IF num_nonnulls(to_regclass('analysis.matter'),to_regclass('analysis.court_case'),
                    to_regclass('analysis.matter_knowledge_partition')) NOT IN (0,3) THEN
        RAISE EXCEPTION 'migration 0054 refuses a partial case registry';
    END IF;
    IF to_regclass('analysis.matter') IS NOT NULL AND (
        (SELECT count(*) FROM analysis.matter) <> 1
        OR (SELECT count(*) FROM analysis.court_case) <> 1
        OR (SELECT count(*) FROM analysis.matter_knowledge_partition) <> 1
        OR NOT EXISTS (SELECT 1 FROM analysis.matter WHERE id='01a03136-c5cc-71c7-ac77-5c00a29a2ea8')
        OR NOT EXISTS (SELECT 1 FROM analysis.court_case WHERE id='01a03136-c5cc-76f9-98df-702058d423d9'
                       AND matter_id='01a03136-c5cc-71c7-ac77-5c00a29a2ea8')
        OR NOT EXISTS (SELECT 1 FROM analysis.matter_knowledge_partition WHERE partition_key='primary'
                       AND matter_id='01a03136-c5cc-71c7-ac77-5c00a29a2ea8'
                       AND default_court_case_id='01a03136-c5cc-76f9-98df-702058d423d9')
    ) THEN
        RAISE EXCEPTION 'migration 0054 refuses mismatched or additional canonical registry rows';
    END IF;
END
$prerequisites$;

SET LOCAL ROLE platform_admin;

CREATE SCHEMA IF NOT EXISTS analysis AUTHORIZATION platform_admin;

DO $schema_owner$
BEGIN
    IF (SELECT pg_get_userbyid(nspowner) FROM pg_namespace WHERE nspname = 'analysis')
       IS DISTINCT FROM 'platform_admin' THEN
        RAISE EXCEPTION 'analysis schema has an unexpected owner';
    END IF;
END
$schema_owner$;

REVOKE ALL ON SCHEMA analysis FROM PUBLIC;

CREATE TABLE IF NOT EXISTS analysis.matter (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    title TEXT NOT NULL CHECK (length(btrim(title)) > 0),
    description TEXT,
    status TEXT NOT NULL DEFAULT 'active'
        CHECK (status IN ('active', 'closed', 'archived')),
    created_by TEXT NOT NULL CHECK (length(btrim(created_by)) > 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS analysis.court_case (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    matter_id UUID NOT NULL,
    caption TEXT NOT NULL CHECK (length(btrim(caption)) > 0),
    docket_number TEXT,
    court_name TEXT,
    jurisdiction TEXT,
    case_type TEXT,
    status TEXT NOT NULL DEFAULT 'pre_filing'
        CHECK (status IN ('pre_filing', 'active', 'stayed', 'closed', 'appealed', 'archived')),
    filed_on DATE,
    closed_on DATE,
    is_primary BOOLEAN NOT NULL DEFAULT false,
    created_by TEXT NOT NULL CHECK (length(btrim(created_by)) > 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT court_case_matter_fkey
        FOREIGN KEY (matter_id) REFERENCES analysis.matter(id) ON DELETE RESTRICT,
    CONSTRAINT court_case_dates_ck
        CHECK (closed_on IS NULL OR filed_on IS NULL OR closed_on >= filed_on),
    CONSTRAINT court_case_id_matter_key UNIQUE (id, matter_id)
);

CREATE INDEX IF NOT EXISTS court_case_matter_status_idx ON analysis.court_case (matter_id, status);
CREATE UNIQUE INDEX IF NOT EXISTS court_case_one_primary_per_matter_idx
    ON analysis.court_case (matter_id) WHERE is_primary;
CREATE UNIQUE INDEX IF NOT EXISTS court_case_docket_per_matter_idx
    ON analysis.court_case (matter_id, lower(docket_number)) WHERE docket_number IS NOT NULL;

CREATE TABLE IF NOT EXISTS analysis.matter_knowledge_partition (
    partition_key TEXT PRIMARY KEY CHECK (length(btrim(partition_key)) > 0),
    matter_id UUID NOT NULL,
    default_court_case_id UUID NOT NULL,
    created_by TEXT NOT NULL CHECK (length(btrim(created_by)) > 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT matter_knowledge_partition_matter_fkey
        FOREIGN KEY (matter_id) REFERENCES analysis.matter(id) ON DELETE RESTRICT,
    CONSTRAINT matter_knowledge_partition_default_case_fkey
        FOREIGN KEY (default_court_case_id, matter_id)
        REFERENCES analysis.court_case(id, matter_id) ON DELETE RESTRICT,
    CONSTRAINT matter_knowledge_partition_scope_key UNIQUE (partition_key, matter_id)
);

CREATE INDEX IF NOT EXISTS matter_knowledge_partition_matter_idx
    ON analysis.matter_knowledge_partition (matter_id);
CREATE INDEX IF NOT EXISTS matter_knowledge_partition_default_case_idx
    ON analysis.matter_knowledge_partition (default_court_case_id);

CREATE TABLE analysis.case_registry_import_receipt (
    id UUID PRIMARY KEY DEFAULT uuidv7(),
    manifest_sha256 BYTEA NOT NULL UNIQUE CHECK (octet_length(manifest_sha256)=32),
    source_migration_uri TEXT NOT NULL CHECK (length(btrim(source_migration_uri)) > 0),
    source_migration_sha256 BYTEA NOT NULL CHECK (octet_length(source_migration_sha256)=32),
    source_git_commit TEXT NOT NULL CHECK (source_git_commit ~ '^[0-9a-f]{40}$'),
    payload_schema_version TEXT NOT NULL CHECK (length(btrim(payload_schema_version)) > 0),
    payload_byte_length BIGINT NOT NULL CHECK (payload_byte_length > 0),
    canonical_payload_sha256 BYTEA NOT NULL CHECK (octet_length(canonical_payload_sha256)=32),
    api_payload_sha256 BYTEA NOT NULL CHECK (octet_length(api_payload_sha256)=32),
    source_observed_at TIMESTAMPTZ NOT NULL,
    matter_id UUID NOT NULL REFERENCES analysis.matter(id) ON DELETE RESTRICT,
    court_case_id UUID NOT NULL,
    partition_key TEXT NOT NULL,
    approved_by TEXT NOT NULL CHECK (length(btrim(approved_by)) > 0),
    approved_on DATE NOT NULL,
    imported_by TEXT NOT NULL CHECK (length(btrim(imported_by)) > 0),
    imported_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT case_registry_import_case_scope_fk
        FOREIGN KEY (court_case_id,matter_id)
        REFERENCES analysis.court_case(id,matter_id) ON DELETE RESTRICT,
    CONSTRAINT case_registry_import_partition_scope_fk
        FOREIGN KEY (partition_key,matter_id)
        REFERENCES analysis.matter_knowledge_partition(partition_key,matter_id) ON DELETE RESTRICT
);

CREATE OR REPLACE FUNCTION analysis.set_case_management_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path = pg_catalog AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$;
ALTER FUNCTION analysis.set_case_management_updated_at() OWNER TO platform_admin;

DO $updated_at_triggers$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='analysis.matter'::regclass
                   AND tgname='matter_set_updated_at' AND NOT tgisinternal) THEN
        CREATE TRIGGER matter_set_updated_at BEFORE UPDATE ON analysis.matter
        FOR EACH ROW EXECUTE FUNCTION analysis.set_case_management_updated_at();
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='analysis.court_case'::regclass
                   AND tgname='court_case_set_updated_at' AND NOT tgisinternal) THEN
        CREATE TRIGGER court_case_set_updated_at BEFORE UPDATE ON analysis.court_case
        FOR EACH ROW EXECUTE FUNCTION analysis.set_case_management_updated_at();
    END IF;
END
$updated_at_triggers$;

ALTER TABLE analysis.matter OWNER TO platform_admin;
ALTER TABLE analysis.court_case OWNER TO platform_admin;
ALTER TABLE analysis.matter_knowledge_partition OWNER TO platform_admin;

CREATE FUNCTION analysis.forbid_case_registry_import_receipt_mutation()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path = pg_catalog AS $$
BEGIN
    RAISE EXCEPTION 'case_registry_import_receipt is immutable';
END;
$$;
CREATE TRIGGER case_registry_import_receipt_immutable
    BEFORE UPDATE OR DELETE ON analysis.case_registry_import_receipt
    FOR EACH ROW EXECUTE FUNCTION analysis.forbid_case_registry_import_receipt_mutation();
CREATE TRIGGER case_registry_import_receipt_no_truncate
    BEFORE TRUNCATE ON analysis.case_registry_import_receipt
    FOR EACH STATEMENT EXECUTE FUNCTION analysis.forbid_case_registry_import_receipt_mutation();

ALTER TABLE context.source_version
    ADD COLUMN matter_id UUID,
    ADD COLUMN court_case_id UUID,
    ADD CONSTRAINT source_version_matter_case_pair_check
        CHECK ((matter_id IS NULL) = (court_case_id IS NULL)),
    ADD CONSTRAINT source_version_source_context_scope_check
        CHECK (source_context_ref IS NULL OR (matter_id IS NOT NULL AND court_case_id IS NOT NULL)) NOT VALID,
    ADD CONSTRAINT source_version_matter_fk
        FOREIGN KEY (matter_id) REFERENCES analysis.matter(id) ON DELETE RESTRICT NOT VALID,
    ADD CONSTRAINT source_version_court_case_scope_fk
        FOREIGN KEY (court_case_id, matter_id)
        REFERENCES analysis.court_case(id, matter_id) ON DELETE RESTRICT NOT VALID;

ALTER TABLE context.uiw_source_context_revision
    ADD CONSTRAINT uiw_source_context_scope_key
        UNIQUE (source_context_ref,matter_id,court_case_id);

ALTER TABLE context.source_version
    ADD CONSTRAINT source_version_source_context_scope_fk
        FOREIGN KEY (source_context_ref,matter_id,court_case_id)
        REFERENCES context.uiw_source_context_revision(source_context_ref,matter_id,court_case_id)
        ON DELETE RESTRICT NOT VALID;

ALTER TABLE context.uiw_source_context_revision
    ADD CONSTRAINT uiw_source_context_matter_fk
        FOREIGN KEY (matter_id) REFERENCES analysis.matter(id) ON DELETE RESTRICT NOT VALID,
    ADD CONSTRAINT uiw_source_context_court_case_scope_fk
        FOREIGN KEY (court_case_id, matter_id)
        REFERENCES analysis.court_case(id, matter_id) ON DELETE RESTRICT NOT VALID;

COMMENT ON TABLE analysis.matter IS
    'Platform-native operator-authored matter registry. Migration 0054 creates no placeholder rows.';
COMMENT ON TABLE analysis.court_case IS
    'Platform-native proceeding registry; composite identity prevents cross-matter case binding.';
COMMENT ON TABLE analysis.matter_knowledge_partition IS
    'Explicit partition-to-matter/default-case mapping created by an authorized application caller.';
COMMENT ON COLUMN context.source_version.matter_id IS
    'Optional intake matter scope; it must be paired with court_case_id.';
COMMENT ON COLUMN context.source_version.court_case_id IS
    'Optional intake case scope; its composite FK must resolve inside matter_id.';

REVOKE ALL ON ALL TABLES IN SCHEMA analysis FROM PUBLIC;
REVOKE ALL ON
    analysis.matter, analysis.court_case, analysis.matter_knowledge_partition,
    analysis.case_registry_import_receipt
    FROM platform_runtime;
REVOKE ALL ON FUNCTION analysis.set_case_management_updated_at() FROM PUBLIC;
REVOKE ALL ON FUNCTION analysis.forbid_case_registry_import_receipt_mutation() FROM PUBLIC;
DO $retired_agno_grants$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='agno_app') THEN
        REVOKE ALL ON analysis.matter, analysis.court_case,
            analysis.matter_knowledge_partition, analysis.case_registry_import_receipt FROM agno_app;
    END IF;
END
$retired_agno_grants$;
GRANT USAGE ON SCHEMA analysis TO platform_runtime;
GRANT SELECT ON
    analysis.matter, analysis.court_case, analysis.matter_knowledge_partition,
    analysis.case_registry_import_receipt
    TO platform_runtime;

DO $verify$
DECLARE v_relation REGCLASS;
BEGIN
    FOREACH v_relation IN ARRAY ARRAY[
        'analysis.matter'::REGCLASS,
        'analysis.court_case'::REGCLASS,
        'analysis.matter_knowledge_partition'::REGCLASS,
        'analysis.case_registry_import_receipt'::REGCLASS
    ] LOOP
        IF (SELECT pg_get_userbyid(relowner) FROM pg_class WHERE oid = v_relation)
           IS DISTINCT FROM 'platform_admin' THEN
            RAISE EXCEPTION '% must be owned by platform_admin', v_relation;
        END IF;
    END LOOP;
    IF NOT has_schema_privilege('platform_runtime', 'analysis', 'USAGE')
       OR NOT has_table_privilege('platform_runtime', 'analysis.matter', 'SELECT')
       OR has_table_privilege('platform_runtime', 'analysis.matter', 'INSERT')
       OR has_table_privilege('platform_runtime', 'analysis.matter', 'UPDATE')
       OR has_table_privilege('platform_runtime', 'analysis.matter', 'DELETE')
       OR (EXISTS (SELECT 1 FROM pg_roles WHERE rolname='agno_app') AND
           (has_table_privilege('agno_app','analysis.matter','INSERT')
            OR has_table_privilege('agno_app','analysis.matter','UPDATE')
            OR has_table_privilege('agno_app','analysis.matter','DELETE')
            OR has_table_privilege('agno_app','analysis.court_case','INSERT')
            OR has_table_privilege('agno_app','analysis.court_case','UPDATE')
            OR has_table_privilege('agno_app','analysis.court_case','DELETE')
            OR has_table_privilege('agno_app','analysis.matter_knowledge_partition','INSERT')
            OR has_table_privilege('agno_app','analysis.matter_knowledge_partition','UPDATE')
            OR has_table_privilege('agno_app','analysis.matter_knowledge_partition','DELETE')))
       OR EXISTS (
           SELECT 1
           FROM pg_proc p,
                LATERAL aclexplode(COALESCE(p.proacl,acldefault('f',p.proowner))) acl
           WHERE p.oid='analysis.set_case_management_updated_at()'::regprocedure
             AND acl.grantee=0 AND acl.privilege_type='EXECUTE')
       OR has_schema_privilege('platform_runtime', 'analysis', 'CREATE') THEN
        RAISE EXCEPTION 'migration 0054 runtime grants are invalid';
    END IF;
    IF EXISTS (SELECT 1 FROM analysis.case_registry_import_receipt) THEN
        RAISE EXCEPTION 'migration 0054 DDL must not fabricate an import receipt';
    END IF;
END
$verify$;

COMMIT;
