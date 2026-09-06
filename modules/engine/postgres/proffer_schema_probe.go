// Byline: Codex · GPT-5.6-Sol · 2026-08-30 (shared Proffer schema admission)
// Retarget · Claude Code · Sonnet 5 · 2026-09-02 (BUILD LANE S2): ledger check
// moved from public.schema_version to ops.migration_ledger per D-109 (see
// comment at the ledgerCount subquery below).
// Dev-flag identity/receipt sentinel · Claude Code · Sonnet 5 · 2026-09-02
// (BUILD LANE S3, D-126): PLATFORM_DEV_AUTH_BYPASS (D-125) points the
// identity + receipt checks at a fixed, obviously-synthetic pre-launch
// sentinel instead of the real go-live identity. Both checks stay fully
// enforced in both modes -- see the doc comment on devMatterID below for the
// owner's exact scoping ruling and why this is not a skip.
package postgres

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"os"
	"strings"

	"github.com/jackc/pgx/v5"
)

// SchemaProbeDB is the read-only database surface needed for startup admission.
type SchemaProbeDB interface {
	QueryRow(context.Context, string, ...any) pgx.Row
}

var requiredProfferMigrations = []string{
	"0036", "0037", "0038", "0039", "0042", "0050", "0051", "0053", "0054",
}

var requiredProfferTables = []string{
	"registry.matter", "registry.court_case", "analysis.matter_knowledge_partition", "analysis.case_registry_import_receipt",
	"context.activity_execution", "context.activity_receipt", "context.hash_batch",
	"context.hash_batch_member", "context.hash_manifest", "context.hash_manifest_member",
	"context.hash_receipt", "context.normalization_lineage", "context.normalized_generation",
	"context.normalized_generation_publication", "context.normalized_record_identity",
	"context.raw_format_registry", "context.raw_generation", "context.raw_record_identity",
	"context.reconciliation_receipt", "context.retained_object", "context.source",
	"context.source_metadata", "context.source_version", "context.source_version_object",
	"context.proffer_preview_binding", "context.proffer_preview_snapshot", "context.proffer_preview_receipt",
	"context.proffer_preview_participant", "context.proffer_preview_message", "context.proffer_preview_attachment",
	"context.proffer_preview_event", "context.proffer_preview_decision", "context.repair_assessment",
	"context.repair_decision", "context.repair_resolution", "context.proffer_source_context_revision",
}

var requiredProfferColumns = []string{
	"context.source_version.matter_id", "context.source_version.court_case_id",
	"context.source_version.source_context_ref",
	"context.proffer_source_context_revision.matter_id",
	"context.proffer_source_context_revision.court_case_id",
	"context.proffer_source_context_revision.source_context_ref",
	"analysis.case_registry_import_receipt.source_migration_uri",
	"analysis.case_registry_import_receipt.source_migration_sha256",
	"analysis.case_registry_import_receipt.source_git_commit",
	"analysis.case_registry_import_receipt.payload_schema_version",
	"analysis.case_registry_import_receipt.payload_byte_length",
	"analysis.case_registry_import_receipt.canonical_payload_sha256",
	"analysis.case_registry_import_receipt.api_payload_sha256",
	"analysis.case_registry_import_receipt.source_observed_at",
	"analysis.case_registry_import_receipt.approved_by",
	"analysis.case_registry_import_receipt.approved_on",
}

const authoritativeMatterID = "01a03136-c5cc-71c7-ac77-5c00a29a2ea8"
const authoritativeCourtCaseID = "01a03136-c5cc-76f9-98df-702058d423d9"
const registrySourceMigrationURI = "sql/0030_matter_case_foundation.sql"
const registrySourceMigrationSHA256 = "b19959119c0f040adcdc442aa7772503fd2d1439a90b1565eaa6c17e0883eb70"
const registrySourceGitCommit = "97f48b172b1d31aa5a0005b45170d72af1299773"
const registryPayloadSchemaVersion = "0030-platform-registry-handoff-v1"
const registryCanonicalPayloadSHA256 = "8e0a8e2d86027add31f9470976d1378e039d6efb5312ecae4cfec0ebd10690e6"
const registryAPIPayloadSHA256 = "cd370f6c9c00e620f39f283e2d0d7d1a83a463b14097b99537b886d438618a6d"

// The two receipt predicates that used to be hardcoded literals in the SQL
// text below (D-126 needed a second, DEV-mode expectation for both) are now
// bind parameters too. These three constants are STRICT mode's values --
// unchanged from the literals Codex originally wrote inline.
const registryReceiptPayloadByteLength = 1075
const registryReceiptApprovedBy = "owner"
const registryReceiptApprovedOn = "2026-08-23"

// platformDevAuthBypassEnv is the one flag D-125 defines for every ingest
// surface (Proffer starter, Workbench BFF, and -- as of D-126 -- this admission
// probe). Default OFF, fail-closed: unset or anything but a truthy value
// means STRICT (the real go-live identity is required, unmet until go-live).
const platformDevAuthBypassEnv = "PLATFORM_DEV_AUTH_BYPASS"

// D-126 (2026-09-02, owner refinement): "The only thing the feature flag
// should really do is bypass the UUID type requirement. And allow for the
// UUID to persist. And add a fake one instead of an auto created one, but
// everything else is still going to look for it, still going to reference
// it. But it's going to be referencing a fake one that's not an actual
// UUID." I.e. identity and receipt checking stay fully ON under the flag --
// only WHICH constants they must match changes. This is not "skip the
// check"; it is "check against the known-fake pre-launch value."
//
// registry.matter.id / registry.court_case.id are Postgres `uuid`-typed
// columns with live FK referrers across sql/0043, 0047, 0053 and 0054
// (context.source_version, context.proffer_source_context_revision,
// working.first_party_context_thread/third_party_context_thread,
// analysis.matter_knowledge_partition, analysis.case_registry_import_receipt
// all carry `matter_id UUID`/`court_case_id UUID` FKs) -- a non-UUID-shaped
// literal ("dev1" etc.) cannot be stored without a destabilizing type change
// across every one of them. So the sentinel is UUID-SHAPED but built
// entirely from classic "this is obviously fake" hex magic numbers (every
// digit is valid hex, 0-9/a-f): DEADBEEF for the matter, CAFEBABE for the
// court case. Neither uuidv7() nor any real UUID generator emits either
// pattern, and both read as fake at a glance next to a real time-ordered
// uuidv7 id, which always starts with a timestamp prefix (e.g. 01a0...).
// sql/0069_dev_case_registry_identity.sql seeds exactly these two values.
const devMatterID = "deadbeef-dead-beef-dead-beefdeadbeef"
const devCourtCaseID = "cafebabe-cafe-babe-cafe-babecafebabe"

// The dev receipt is written HONESTLY: D-126 forbids ever recording
// approved_by='owner' for an approval the owner did not give -- that would
// be exactly the fabricated-record class of defect
// docs/CLAIMED_COMPLETE_LIKELY_LIES/ exists to catch. approved_by here names
// the mechanism, not a person. Every hash/commit field is a fixed hex
// "magic number" placeholder (never derived from a real payload) so it is
// obviously not asserting real content-integrity -- sql/0069 seeds the
// identical literals; the two files must be changed together.
const devReceiptSourceMigrationURI = "sql/0069_dev_case_registry_identity.sql"
const devReceiptSourceMigrationSHA256 = "deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
const devReceiptSourceGitCommit = "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
const devReceiptPayloadSchemaVersion = "dev-placeholder-v1"
const devReceiptPayloadByteLength = 1
const devReceiptCanonicalPayloadSHA256 = "cafebabecafebabecafebabecafebabecafebabecafebabecafebabecafebabe"
const devReceiptAPIPayloadSHA256 = "deadfacedeadfacedeadfacedeadfacedeadfacedeadfacedeadfacedeadface"
const devReceiptApprovedBy = "dev-mode-placeholder"
const devReceiptApprovedOn = "2026-09-02"

// devAuthBypassEnabled reads PLATFORM_DEV_AUTH_BYPASS directly rather than
// taking a parameter: ProbeProfferSchema is called from modules/engine/temporal/
// cmd/starter/main.go and modules/engine/profferworker/worker.go with a fixed
// two-argument signature, and D-125's contract is one process-wide flag, not
// a value threaded through every caller. Truthy values match D-125's own
// documented example (PLATFORM_DEV_AUTH_BYPASS=1) plus the usual spellings;
// anything else, including unset, is OFF (fail-closed default).
func devAuthBypassEnabled() bool {
	switch strings.ToLower(strings.TrimSpace(os.Getenv(platformDevAuthBypassEnv))) {
	case "1", "true", "yes", "on":
		return true
	default:
		return false
	}
}

// ProbeProfferSchema rejects an incomplete, legacy, over-privileged, or wrongly
// scoped database before any Proffer Temporal queue is polled.
func ProbeProfferSchema(ctx context.Context, db SchemaProbeDB) error {
	if db == nil {
		return errors.New("Proffer schema admission: database is required")
	}
	devBypass := devAuthBypassEnabled()
	matterID, courtCaseID := authoritativeMatterID, authoritativeCourtCaseID
	receiptURI, receiptSHA256Hex := registrySourceMigrationURI, registrySourceMigrationSHA256
	gitCommit, schemaVersion := registrySourceGitCommit, registryPayloadSchemaVersion
	canonicalSHA256Hex, apiSHA256Hex := registryCanonicalPayloadSHA256, registryAPIPayloadSHA256
	payloadByteLength, approvedBy, approvedOn := registryReceiptPayloadByteLength, registryReceiptApprovedBy, registryReceiptApprovedOn
	if devBypass {
		matterID, courtCaseID = devMatterID, devCourtCaseID
		receiptURI, receiptSHA256Hex = devReceiptSourceMigrationURI, devReceiptSourceMigrationSHA256
		gitCommit, schemaVersion = devReceiptSourceGitCommit, devReceiptPayloadSchemaVersion
		canonicalSHA256Hex, apiSHA256Hex = devReceiptCanonicalPayloadSHA256, devReceiptAPIPayloadSHA256
		payloadByteLength, approvedBy, approvedOn = devReceiptPayloadByteLength, devReceiptApprovedBy, devReceiptApprovedOn
		slog.Warn("Proffer schema admission: PLATFORM_DEV_AUTH_BYPASS is set -- admitting the pre-launch DEV sentinel case-registry identity, not the real go-live identity (D-125, D-126); remove this flag before go-live",
			"flag", platformDevAuthBypassEnv, "dev_matter_id", devMatterID, "dev_court_case_id", devCourtCaseID)
	}
	var database, currentUser, databaseOwner string
	var ledgerCount, tableCount, columnCount int
	var constraintsExact, substrateExact, roleSafe, grantsExact, receiptExact bool
	err := db.QueryRow(ctx, `
		SELECT current_database(), current_user,
		       pg_get_userbyid((SELECT datdba FROM pg_database WHERE datname=current_database())),
		       -- D-109 (docs/DECISION_LOG.md, 2026-08-30): public.schema_version is
		       -- NOT a migration ledger -- its status vocabulary (active/superseded/
		       -- deprecated) and columns (applies_to/ddl_uri/supersedes) describe
		       -- data-contract versions, not applied migrations; that resemblance
		       -- destroyed migration state once already (2026-08-29 CREATE DATABASE
		       -- ... TEMPLATE ai inherited its rows). ops.migration_ledger (sql/0055
		       -- PART 5) is THE ledger: one row per applied migration_id, no status
		       -- column, so presence alone means "applied" -- no status predicate.
		       (SELECT count(*) FROM ops.migration_ledger
		         WHERE migration_id=ANY($1::text[])),
		       (SELECT count(*) FROM information_schema.tables
		         WHERE format('%s.%s',table_schema,table_name)=ANY($2::text[])),
		       (SELECT count(*) FROM information_schema.columns
		         WHERE format('%s.%s.%s',table_schema,table_name,column_name)=ANY($3::text[])),
		       (NOT EXISTS (
		         SELECT 1 FROM (VALUES
		           ('context.source_version','source_version_matter_fk','registry.matter',ARRAY['matter_id'],ARRAY['id']),
		           ('context.source_version','source_version_court_case_scope_fk','registry.court_case',ARRAY['court_case_id','matter_id'],ARRAY['id','matter_id']),
		           ('context.source_version','source_version_source_context_scope_fk','context.proffer_source_context_revision',ARRAY['source_context_ref','matter_id','court_case_id'],ARRAY['source_context_ref','matter_id','court_case_id']),
		           ('context.proffer_source_context_revision','proffer_source_context_matter_fk','registry.matter',ARRAY['matter_id'],ARRAY['id']),
		           ('context.proffer_source_context_revision','proffer_source_context_court_case_scope_fk','registry.court_case',ARRAY['court_case_id','matter_id'],ARRAY['id','matter_id'])
		         ) AS required(relation_name,constraint_name,referenced_name,columns,referenced_columns)
		         WHERE NOT EXISTS (
		           SELECT 1 FROM pg_constraint c
		           WHERE c.conrelid=required.relation_name::regclass
		             AND c.confrelid=required.referenced_name::regclass AND c.contype='f'
		             AND c.conname=required.constraint_name AND c.convalidated AND c.confdeltype='r'
		             AND ARRAY(SELECT a.attname::text FROM unnest(c.conkey) WITH ORDINALITY k(attnum,ord)
		                       JOIN pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=k.attnum ORDER BY k.ord)=required.columns
		             AND ARRAY(SELECT a.attname::text FROM unnest(c.confkey) WITH ORDINALITY k(attnum,ord)
		                       JOIN pg_attribute a ON a.attrelid=c.confrelid AND a.attnum=k.attnum ORDER BY k.ord)=required.referenced_columns))
		         AND EXISTS (SELECT 1 FROM pg_constraint c
		           WHERE c.conrelid='context.source_version'::regclass
		             AND c.conname='source_version_matter_case_pair_check' AND c.contype='c' AND c.convalidated)
		         AND EXISTS (SELECT 1 FROM pg_constraint c
		           WHERE c.conrelid='context.source_version'::regclass
		             AND c.conname='source_version_source_context_scope_check' AND c.contype='c' AND c.convalidated)
		         AND EXISTS (SELECT 1 FROM pg_constraint c
		           WHERE c.conrelid='context.proffer_source_context_revision'::regclass
		             AND c.conname='proffer_source_context_scope_key' AND c.contype='u' AND c.convalidated
		             AND ARRAY(SELECT a.attname::text FROM unnest(c.conkey) WITH ORDINALITY k(attnum,ord)
		                       JOIN pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=k.attnum ORDER BY k.ord)
		                 =ARRAY['source_context_ref','matter_id','court_case_id'])),
		       (SELECT count(*)=4 FROM pg_constraint WHERE convalidated AND conname=ANY(ARRAY[
		         'raw_record_context_fingerprint_canon_check','hash_batch_context_kind_check',
		         'hash_manifest_context_kind_check','hash_receipt_context_kind_check'])),
		       COALESCE((SELECT rolcanlogin AND NOT (rolsuper OR rolcreatedb OR rolcreaterole OR rolreplication OR rolbypassrls)
		         AND pg_has_role('platform_runtime','context_import_writer','MEMBER')
		         FROM pg_roles WHERE rolname='platform_runtime'),false),
		       has_schema_privilege('platform_runtime','analysis','USAGE')
		         AND NOT has_schema_privilege('platform_runtime','analysis','CREATE')
		         AND has_table_privilege('platform_runtime','registry.matter','SELECT')
		         AND has_table_privilege('platform_runtime','registry.court_case','SELECT')
		         AND has_table_privilege('platform_runtime','analysis.matter_knowledge_partition','SELECT')
		         AND has_table_privilege('platform_runtime','analysis.case_registry_import_receipt','SELECT')
		         AND NOT has_table_privilege('platform_runtime','registry.matter','INSERT')
		         AND NOT has_table_privilege('platform_runtime','registry.matter','UPDATE')
		         AND NOT has_table_privilege('platform_runtime','registry.matter','DELETE')
		         -- The guard's intent is "platform_runtime must never be able to
		         -- forge ledger history" -- it must track whichever table is
		         -- ACTUALLY the ledger. Retargeted alongside the ledgerCount
		         -- subquery above (D-109): checking INSERT-denial on the old
		         -- data-contract-version table no longer protects anything, since
		         -- platform_runtime writing rows there can no longer masquerade
		         -- as applied-migration state.
		         AND NOT has_table_privilege('platform_runtime','ops.migration_ledger','INSERT')
		         AND (NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='agno_app') OR NOT (
		           has_table_privilege('agno_app','registry.matter','INSERT')
		           OR has_table_privilege('agno_app','registry.matter','UPDATE')
		           OR has_table_privilege('agno_app','registry.matter','DELETE')
		           OR has_table_privilege('agno_app','registry.court_case','INSERT')
		           OR has_table_privilege('agno_app','registry.court_case','UPDATE')
		           OR has_table_privilege('agno_app','registry.court_case','DELETE')
		           OR has_table_privilege('agno_app','analysis.matter_knowledge_partition','INSERT')
		           OR has_table_privilege('agno_app','analysis.matter_knowledge_partition','UPDATE')
		           OR has_table_privilege('agno_app','analysis.matter_knowledge_partition','DELETE'))),
		       -- payload_byte_length ($12), approved_by ($13) and approved_on
		       -- ($14) used to be hardcoded literals (1075 / 'owner' /
		       -- DATE '2026-08-23'). D-126 needs a second, DEV-mode
		       -- expectation for the same predicates, so all three are now
		       -- bind parameters -- the query text itself never changes
		       -- between STRICT and DEV mode, only which Go constants are
		       -- bound to $4/$5/$6..$14.
		       (SELECT count(*)=1 AND count(*) FILTER (WHERE matter_id=$4::uuid AND court_case_id=$5::uuid
		          AND source_migration_uri=$6 AND encode(source_migration_sha256,'hex')=$7
		          AND source_git_commit=$8 AND payload_schema_version=$9 AND payload_byte_length=$12
		          AND encode(canonical_payload_sha256,'hex')=$10 AND encode(api_payload_sha256,'hex')=$11
		          AND approved_by=$13 AND approved_on=$14::date)=1
		          FROM analysis.case_registry_import_receipt)`,
		requiredProfferMigrations, requiredProfferTables, requiredProfferColumns, matterID, courtCaseID,
		receiptURI, receiptSHA256Hex, gitCommit,
		schemaVersion, canonicalSHA256Hex, apiSHA256Hex,
		payloadByteLength, approvedBy, approvedOn,
	).Scan(&database, &currentUser, &databaseOwner, &ledgerCount, &tableCount, &columnCount,
		&constraintsExact, &substrateExact, &roleSafe, &grantsExact, &receiptExact)
	if err != nil {
		return errors.New("Proffer schema admission: catalog verification unavailable")
	}
	if database != "platform" || currentUser != "platform_runtime" || databaseOwner != "platform_admin" {
		return fmt.Errorf("Proffer schema admission: identity rejected: database=%q role=%q owner=%q", database, currentUser, databaseOwner)
	}
	if ledgerCount != len(requiredProfferMigrations) || tableCount != len(requiredProfferTables) || columnCount != len(requiredProfferColumns) || !constraintsExact || !substrateExact || !roleSafe || !grantsExact || !receiptExact {
		return fmt.Errorf("Proffer schema admission failed (dev_bypass=%t): ledger=%d/%d tables=%d/%d columns=%d/%d constraints=%t substrate=%t role=%t grants=%t receipt=%t",
			devBypass, ledgerCount, len(requiredProfferMigrations), tableCount, len(requiredProfferTables), columnCount,
			len(requiredProfferColumns), constraintsExact, substrateExact, roleSafe, grantsExact, receiptExact)
	}
	return nil
}
