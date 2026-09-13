package stagegraph

// Stages is the ordered, exhaustive registry of every Activity in the
// ProfferWorkflow. Order follows the canon document's numbering
// (section 2) purely for readability; the actual execution order is
// determined by DependsOn, not slice position.
//
// D-149/D-152: ingest is context processing, never evidence custody.
// Source, raw-record, and raw-generation fingerprints use context-specific
// receipt families. Normalized digests are also context integrity checks.
// Promotion owns custody sealing and its separately governed hash machinery.
//
// Dependency rationale, mirroring the canon document:
//
//   - register_source is the root: it creates the identity/idempotency
//     coordinate every other stage keys off.
//   - retain_original precedes repair assessment/resolution; the resolved
//     retained object is the only byte source used by the remaining stages.
//   - capture_filesystem_metadata, fingerprint_source, inventory_container, and
//     extract_embedded_metadata are the named "safe parallel fan-out": each
//     depends only on resolve_source_repair and not on one another.
//   - select_parser joins that fan-out (it needs the container manifest and
//     metadata manifest to pick an adapter) before execute_parser runs.
//   - persist_raw_generation, fingerprint_raw_records, then
//     fingerprint_raw_generation follow parsing in strict
//     sequence (persist before hashing the persisted rows, hash the members
//     before folding their chain).
//   - reconcile_record_accounting and reconcile_byte_coverage both depend
//     only on fingerprint_raw_generation and not on each other (second parallel
//     pair) — reconciliation follows the context generation fingerprint.
//   - verify_raw_coverage_against_source joins that pair and additionally
//     depends on fingerprint_source for context source verification.
//   - normalize_generation, persist_normalized_generation follow verification
//     in strict sequence (normalize is transform-only, persist is the only
//     write).
//   - persist_lineage -> validate_raw_lineage is one branch off
//     persist_normalized_generation; hash_normalized_records (normalized
//     record digests) is the other, independent branch (third parallel
//     pair).
//   - hash_normalized_generation (normalized generation manifest digest)
//     depends on hash_normalized_records, since it folds the ordered
//     normalized-record membership.
//   - verify_normalized_generation joins the lineage branch and the
//     normalized-digest branch before seal_generation may run.
//   - publish_generation is the sole successor of seal_generation, and is
//     therefore the sink whose transitive dependency closure is every other
//     stage.
var Stages = []Descriptor{
	{
		ID:             RegisterSource,
		Responsibility: RespRegisterIdentity,
		Result:         "source/version reference",
	},
	{
		ID:             RetainOriginal,
		Responsibility: RespRetain,
		Result:         "original-object reference",
		DependsOn:      []StageID{RegisterSource},
	},
	{
		ID:             AssessSourceRepair,
		Responsibility: RespAssessRepair,
		Result:         "repair assessment reference",
		DependsOn:      []StageID{RetainOriginal},
	},
	{
		ID:             ResolveSourceRepair,
		Responsibility: RespResolveRepair,
		Result:         "active retained-object reference",
		DependsOn:      []StageID{AssessSourceRepair},
	},
	{
		ID:             CaptureFilesystemMetadata,
		Responsibility: RespCaptureMetadata,
		Result:         "filesystem metadata reference",
		DependsOn:      []StageID{ResolveSourceRepair},
	},
	{
		ID:             FingerprintSource,
		Responsibility: RespComputeHash,
		Result:         "context source fingerprint receipt reference",
		DependsOn:      []StageID{ResolveSourceRepair},
	},
	{
		ID:             InventoryContainer,
		Responsibility: RespInventory,
		Result:         "container manifest reference",
		DependsOn:      []StageID{ResolveSourceRepair},
	},
	{
		ID:             ExtractEmbeddedMetadata,
		Responsibility: RespExtractMetadata,
		Result:         "metadata manifest reference",
		DependsOn:      []StageID{ResolveSourceRepair},
	},
	{
		ID:             SelectParser,
		Responsibility: RespSelect,
		Result:         "parser selection receipt",
		DependsOn: []StageID{
			CaptureFilesystemMetadata,
			FingerprintSource,
			InventoryContainer,
			ExtractEmbeddedMetadata,
		},
	},
	{
		ID:             ExecuteParser,
		Responsibility: RespParse,
		Result:         "immutable bundle reference",
		DependsOn:      []StageID{SelectParser},
	},
	{
		ID:             PersistRawGeneration,
		Responsibility: RespPersist,
		Result:         "raw generation receipt",
		DependsOn:      []StageID{ExecuteParser},
	},
	{
		ID:             FingerprintRawRecords,
		Responsibility: RespComputeHash,
		Result:         "context raw-record fingerprint manifest reference",
		DependsOn:      []StageID{PersistRawGeneration},
	},
	{
		ID:             FingerprintRawGeneration,
		Responsibility: RespComputeHash,
		Result:         "context raw-generation fingerprint chain reference",
		DependsOn:      []StageID{FingerprintRawRecords},
	},
	{
		ID:             ReconcileRecordAccounting,
		Responsibility: RespReconcile,
		Result:         "accounting receipt",
		DependsOn:      []StageID{FingerprintRawGeneration},
	},
	{
		ID:             ReconcileByteCoverage,
		Responsibility: RespReconcile,
		Result:         "coverage receipt",
		DependsOn:      []StageID{FingerprintRawGeneration},
	},
	{
		ID:             VerifyRawCoverageAgainstSource,
		Responsibility: RespVerify,
		Result:         "raw/source verification receipt",
		DependsOn: []StageID{
			ReconcileRecordAccounting,
			ReconcileByteCoverage,
			FingerprintSource,
		},
	},
	{
		ID:             NormalizeGeneration,
		Responsibility: RespNormalize,
		Result:         "normalized bundle reference",
		DependsOn:      []StageID{VerifyRawCoverageAgainstSource},
	},
	{
		ID:             PersistNormalizedGeneration,
		Responsibility: RespPersist,
		Result:         "normalized generation reference",
		DependsOn:      []StageID{NormalizeGeneration},
	},
	{
		ID:             PersistLineage,
		Responsibility: RespPersist,
		Result:         "lineage-set reference",
		DependsOn:      []StageID{PersistNormalizedGeneration},
	},
	{
		ID:             ValidateRawLineage,
		Responsibility: RespValidate,
		Result:         "lineage validation receipt",
		DependsOn:      []StageID{PersistLineage},
	},
	{
		ID:             HashNormalizedRecords,
		Responsibility: RespComputeHash,
		Result:         "normalized record digest manifest reference",
		DependsOn:      []StageID{PersistNormalizedGeneration},
	},
	{
		ID:             HashNormalizedGeneration,
		Responsibility: RespComputeHash,
		Result:         "normalized generation manifest digest reference",
		DependsOn:      []StageID{HashNormalizedRecords},
	},
	{
		ID:             VerifyNormalizedGeneration,
		Responsibility: RespVerify,
		Result:         "normalized verification receipt",
		DependsOn: []StageID{
			ValidateRawLineage,
			HashNormalizedGeneration,
		},
	},
	{
		ID:             PublishPreview,
		Responsibility: RespProjectPreview,
		Result:         "opaque preview handle",
		DependsOn:      []StageID{VerifyNormalizedGeneration},
	},
	{
		ID:             SealGeneration,
		Responsibility: RespSeal,
		Result:         "sealed generation receipt",
		DependsOn:      []StageID{PublishPreview},
	},
	{
		ID:             PublishGeneration,
		Responsibility: RespPublish,
		Result:         "publication receipt",
		DependsOn:      []StageID{SealGeneration},
	},
}
