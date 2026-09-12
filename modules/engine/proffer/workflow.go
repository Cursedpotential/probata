package proffer

import (
	"errors"
	"fmt"
	"strings"

	"go.temporal.io/sdk/workflow"

	"github.com/Cursedpotential/probata/engine/stagegraph"
)

const (
	fingerprintVocabularyChangeID = "proffer-context-fingerprint-vocabulary-v1"
	fingerprintVocabularyVersion  = workflow.Version(1)
	previewRepairChangeID         = "proffer-preview-explicit-repair-refs-v1"
	previewRepairVersion          = workflow.Version(1)
	integratedPreviewChangeID     = "proffer-integrated-repair-preview-v1"
	integratedPreviewVersion      = workflow.Version(1)
	durableReviewWaitChangeID     = "proffer-durable-extended-review-wait-v1"
	durableReviewWaitVersion      = workflow.Version(1)
	structuredELTRouteChangeID    = "proffer-duckdb-structured-elt-route-v1"
	structuredELTRouteVersion     = workflow.Version(1)
	previewCheckpointsChangeID    = "proffer-live-preview-checkpoints-v1"
	previewCheckpointsVersion     = workflow.Version(1)
	handlerSelectionChangeID      = "proffer-content-handler-selection-v1"
	handlerSelectionVersion       = workflow.Version(1)
	// SelectStructuredELTActivityName and ExecuteStructuredELTActivityName are
	// the implementation-specific Temporal names for DuckDB execution of the
	// logical SelectParser and ExecuteParser stages. The Activity package
	// aliases these constants so registration and dispatch cannot drift.
	SelectStructuredELTActivityName  = "select_structured_elt_activity"
	ExecuteStructuredELTActivityName = "execute_structured_elt_activity"
	legacyHashSourceActivity         = "hash_source_activity"
	legacyHashRawRecordsActivity     = "hash_raw_records_activity"
	legacyHashRawGenerationActivity  = "hash_raw_generation_activity"
)

type fingerprintVocabulary struct {
	source, rawRecords, rawGeneration stagegraph.StageID
	sourceRefKey, rawManifestRefKey   string
}

func fingerprintVocabularyFor(ctx workflow.Context) fingerprintVocabulary {
	if workflow.GetVersion(ctx, fingerprintVocabularyChangeID, workflow.DefaultVersion, fingerprintVocabularyVersion) == workflow.DefaultVersion {
		return fingerprintVocabulary{
			source: stagegraph.StageID(legacyHashSourceActivity), rawRecords: stagegraph.StageID(legacyHashRawRecordsActivity),
			rawGeneration: stagegraph.StageID(legacyHashRawGenerationActivity), sourceRefKey: "h1", rawManifestRefKey: "raw_hash_manifest",
		}
	}
	return fingerprintVocabulary{
		source: stagegraph.FingerprintSource, rawRecords: stagegraph.FingerprintRawRecords,
		rawGeneration: stagegraph.FingerprintRawGeneration, sourceRefKey: "context_source_fingerprint",
		rawManifestRefKey: "raw_fingerprint_manifest",
	}
}

// ProfferWorkflow is the single Temporal workflow every source runs
// through (boundary document acceptance gate 1). It executes the exact
// engine/stagegraph.Stages graph — all 26 atomic Activities, the documented
// safe parallel fan-outs, and deterministic ordering everywhere else — and
// fails closed: any Activity error or explicit StatusFailed result halts
// every descendant and both seal_generation_activity and
// publish_generation_activity. StatusSuccess and StatusNotApplicable are
// both valid outcomes that let the workflow continue.
//
// This function contains no Activity bodies. Every stage is invoked by its
// canon name (ActivityName, identical to stagegraph.StageID) so a worker in
// a later lane can register real Activities without this file changing.
func ProfferWorkflow(ctx workflow.Context, in WorkflowInput) (WorkflowResult, error) {
	r := &run{requestID: in.RequestID, matterID: in.MatterID, courtCaseID: in.CourtCaseID}
	fingerprint := fingerprintVocabularyFor(ctx)
	integratedPreview := workflow.GetVersion(ctx, integratedPreviewChangeID, workflow.DefaultVersion, integratedPreviewVersion)
	durableReviewWait := workflow.GetVersion(ctx, durableReviewWaitChangeID, workflow.DefaultVersion, durableReviewWaitVersion)
	previewCheckpoints := workflow.GetVersion(ctx, previewCheckpointsChangeID, workflow.DefaultVersion, previewCheckpointsVersion) != workflow.DefaultVersion
	handlerSelection := workflow.GetVersion(ctx, handlerSelectionChangeID, workflow.DefaultVersion, handlerSelectionVersion)

	// Stage 1: register_source_activity — the root. It creates the
	// identity/idempotency coordinate every later stage keys off.
	registerRefs := map[string]Ref{"acquisition": in.SourceRef}
	if in.SourceContextRef != "" {
		registerRefs["source_context"] = in.SourceContextRef
	}
	sourceVersionRef, err := r.exec(ctx, stagegraph.RegisterSource, in.DeclaredFormat, registerRefs)
	if err != nil {
		return r.result(""), err
	}
	r.sourceVersionRef = sourceVersionRef

	// Stage 2: retain_original_activity — the only stage after
	// register_source that must run before anything touches source bytes.
	originalRef, err := r.exec(ctx, stagegraph.RetainOriginal, "", map[string]Ref{
		"acquisition": in.SourceRef,
	})
	if err != nil {
		return r.result(""), err
	}

	activeOriginalRef := originalRef
	preview := PreviewState{Phase: PhaseStarting, ParserOptionsRef: in.ParserOptionsRef, Checkpoints: newPreviewCheckpoints(previewCheckpoints)}
	if integratedPreview != workflow.DefaultVersion {
		// Repair assessment is produced before the repair gate, so the human is
		// deciding against durable data that already exists. The signal contains
		// only the persisted actor-bound decision registry.
		// "acquisition" is the scheme-prefixed source LOCATOR (upload:// / r2://)
		// the tool gateway resolves on its own host (D-132); "original" is the
		// retained-object identity used for persistence. Live rehearsal
		// 2026-09-05 (rehearsal-20260905-r2c-1788610705) failed with the
		// gateway rejecting the bare original UUID: "has no URI scheme".
		repairAssessmentRef, err := r.exec(ctx, stagegraph.AssessSourceRepair, in.DeclaredFormat, map[string]Ref{
			"original":    originalRef,
			"acquisition": in.SourceRef,
		})
		if err != nil {
			return r.result(""), err
		}
		assessmentResult := r.results[len(r.results)-1]
		preview = PreviewState{Phase: PhaseStarting, SourceVersionRef: r.sourceVersionRef, RepairAssessmentRef: repairAssessmentRef, ParserOptionsRef: in.ParserOptionsRef,
			Checkpoints:      newPreviewCheckpoints(previewCheckpoints),
			RepairAssessment: &RepairAssessmentView{AssessmentRef: repairAssessmentRef, SourceVersionRef: r.sourceVersionRef, ReviewRequired: assessmentResult.Status != StatusNotApplicable}}
		if err := workflow.SetQueryHandler(ctx, PreviewQueryName, func() (PreviewState, error) {
			return preview, nil
		}); err != nil {
			return r.result(""), fmt.Errorf("proffer: register preview query handler: %w", err)
		}
		refs := map[string]Ref{"original": originalRef, "repair_assessment": repairAssessmentRef, "acquisition": in.SourceRef}
		if assessmentResult.Status == StatusNotApplicable {
			refs["auto_clean_assessment"] = repairAssessmentRef
		} else {
			preview.Phase = PhaseAwaitingRepairDecision
			repairDecision, waitErr := awaitRepairDecision(ctx, &preview, durableReviewWait)
			if waitErr != nil {
				return r.result(""), waitErr
			}
			refs["repair_decision"] = repairDecision.DecisionRef
		}
		activeOriginalRef, err = r.exec(ctx, stagegraph.ResolveSourceRepair, in.DeclaredFormat, refs)
		if err != nil {
			return r.result(""), err
		}
		preview.Phase = PhaseRepairApproved
	}

	// Stages 3-6: the named safe parallel fan-out. Each depends only on
	// retain_original, not on one another (proven for the graph itself by
	// stagegraph.TestSafeParallelFanOutAfterRetainOriginal).
	fanOut, err := r.join(ctx,
		r.start(ctx, stagegraph.CaptureFilesystemMetadata, "", map[string]Ref{"original": activeOriginalRef}),
		r.start(ctx, fingerprint.source, "", map[string]Ref{"original": activeOriginalRef}),
		r.start(ctx, stagegraph.InventoryContainer, "", map[string]Ref{"original": activeOriginalRef}),
		r.start(ctx, stagegraph.ExtractEmbeddedMetadata, "", map[string]Ref{"original": activeOriginalRef}),
	)
	if err != nil {
		return r.result(""), err
	}
	filesystemMetadataRef := fanOut[stagegraph.CaptureFilesystemMetadata]
	contextSourceFingerprintRef := fanOut[fingerprint.source]
	containerManifestRef := fanOut[stagegraph.InventoryContainer]
	metadataManifestRef := fanOut[stagegraph.ExtractEmbeddedMetadata]
	structuredELTRoute := workflow.GetVersion(ctx, structuredELTRouteChangeID, workflow.DefaultVersion, structuredELTRouteVersion)
	activeFormat := in.DeclaredFormat
	useStructuredELT := structuredELTRoute != workflow.DefaultVersion && structuredELTEligible(in.DeclaredFormat)
	var selectionProgressReceipt Ref
	selectionRefs := map[string]Ref{
		"filesystem_metadata": filesystemMetadataRef,
		"container_manifest":  containerManifestRef,
		"metadata_manifest":   metadataManifestRef,
	}
	if handlerSelection != workflow.DefaultVersion {
		preview.setCheckpoint("parser_selection", CheckpointRunning, "", "")
		recommendation, recommendErr := recommendHandler(ctx, StageRequest{
			RequestID: r.requestID, MatterID: r.matterID, CourtCaseID: r.courtCaseID,
			SourceVersionRef: r.sourceVersionRef, DeclaredFormat: in.DeclaredFormat,
			Refs: map[string]Ref{
				"original":            activeOriginalRef,
				"filesystem_metadata": filesystemMetadataRef,
				"container_manifest":  containerManifestRef,
				"metadata_manifest":   metadataManifestRef,
			},
		})
		if recommendErr != nil {
			preview.setCheckpoint("parser_selection", CheckpointFailed, "", recommendErr.Error())
			return r.result(""), recommendErr
		}
		preview.Phase = PhaseAwaitingHandlerSelection
		preview.HandlerRecommendationRef = recommendation.RecommendationRef
		preview.DetectedFormat = recommendation.DetectedFormat
		preview.DetectedFormatRef = recommendation.DetectedFormatRef
		preview.SignatureRef = recommendation.SignatureRef
		preview.RecommendedHandler = &recommendation.Recommended
		preview.AlternativeHandlers = append([]HandlerCandidate(nil), recommendation.Alternatives...)
		preview.setCheckpoint("parser_selection", CheckpointRunning, recommendation.ReceiptRef, "awaiting explicit handler selection")
		selectionProgressReceipt = recommendation.ReceiptRef
		if integratedPreview == workflow.DefaultVersion {
			if err := workflow.SetQueryHandler(ctx, PreviewQueryName, func() (PreviewState, error) { return preview, nil }); err != nil {
				return r.result(""), fmt.Errorf("proffer: register handler-selection preview query: %w", err)
			}
		}
		decision, decisionErr := awaitHandlerSelectionDecision(ctx, &preview, durableReviewWait)
		if decisionErr != nil {
			preview.setCheckpoint("parser_selection", CheckpointFailed, recommendation.ReceiptRef, decisionErr.Error())
			return r.result(""), decisionErr
		}
		validation, validationErr := validateSelectedHandler(ctx, StageRequest{
			RequestID: r.requestID, MatterID: r.matterID, CourtCaseID: r.courtCaseID,
			SourceVersionRef: r.sourceVersionRef, DeclaredFormat: recommendation.DetectedFormat,
			Refs: map[string]Ref{
				"handler_recommendation": recommendation.RecommendationRef,
				"handler_decision":       decision.DecisionRef,
				"detected_format":        recommendation.DetectedFormatRef,
				"content_signature":      recommendation.SignatureRef,
			},
		})
		if validationErr != nil {
			preview.setCheckpoint("parser_selection", CheckpointFailed, recommendation.ReceiptRef, validationErr.Error())
			return r.result(""), validationErr
		}
		if err := validateHandlerSelection(recommendation, decision.DecisionRef, validation); err != nil {
			preview.setCheckpoint("parser_selection", CheckpointFailed, validation.ValidationReceipt, err.Error())
			return r.result(""), fmt.Errorf("proffer: reject handler selection: %w", err)
		}
		preview.Phase = PhaseHandlerSelected
		preview.HandlerDecisionRef = decision.DecisionRef
		activeFormat = recommendation.DetectedFormat
		useStructuredELT = validation.Chosen.ExecutionPath == HandlerPathDuckDB
		selectionRefs["handler_recommendation"] = recommendation.RecommendationRef
		selectionRefs["handler_decision"] = decision.DecisionRef
		selectionRefs["handler_validation"] = validation.ValidationReceipt
		selectionRefs["detected_format"] = recommendation.DetectedFormatRef
		selectionRefs["content_signature"] = recommendation.SignatureRef
		selectionRefs["handler_compatibility"] = validation.Chosen.CompatibilityRef
	}

	// Stage 7: select_parser_activity joins the fan-out; it needs the
	// container manifest and metadata manifest to pick an adapter. It does
	// NOT receive contextSourceFingerprintRef: hash identity must never influence parser
	// selection. The workflow still joins the fan-out (including
	// fingerprint_source) before scheduling select_parser — only the context source fingerprint
	// reference itself is withheld from this stage's request.
	selectionActivity := string(stagegraph.SelectParser)
	if useStructuredELT {
		selectionActivity = SelectStructuredELTActivityName
	}
	preview.setCheckpoint("parser_selection", CheckpointRunning, selectionProgressReceipt, "")
	parserSelectionRef, err := r.execActivity(ctx, stagegraph.SelectParser, selectionActivity, activeFormat, selectionRefs)
	if err != nil {
		preview.setCheckpoint("parser_selection", CheckpointFailed, r.receiptRef(stagegraph.SelectParser), err.Error())
		return r.result(""), err
	}
	preview.setCheckpoint("parser_selection", CheckpointCompleted, r.receiptRef(stagegraph.SelectParser), "")

	activeSelectionRef := parserSelectionRef
	activeParserOptionsRef := in.ParserOptionsRef
	if integratedPreview == workflow.DefaultVersion {
		preview = PreviewState{Phase: PhaseAwaitingDecision, SelectRef: activeSelectionRef, ParserOptionsRef: activeParserOptionsRef,
			Checkpoints: newPreviewCheckpoints(previewCheckpoints)}
		if handlerSelection == workflow.DefaultVersion {
			if err := workflow.SetQueryHandler(ctx, PreviewQueryName, func() (PreviewState, error) { return preview, nil }); err != nil {
				return r.result(""), fmt.Errorf("proffer: register legacy preview query handler: %w", err)
			}
		}
		if err := awaitLegacyPreviewDecision(ctx, &preview, &activeSelectionRef, &activeParserOptionsRef, durableReviewWait); err != nil {
			return r.result(""), err
		}
	}

	// Stage 8: execute_parser_activity's logical extraction boundary. New
	// histories route only the explicitly supported structured signatures to
	// DuckDB. Both implementations return the same immutable raw-bundle Ref
	// and identify their logical result as ExecuteParser, so every downstream
	// persistence, fingerprint, reconciliation, normalization, preview, and
	// publication stage remains unchanged. The version marker preserves the
	// original parser Activity command for histories started before this route
	// existed. Exactly one implementation is scheduled for a source.
	executionActivity := string(stagegraph.ExecuteParser)
	if useStructuredELT {
		executionActivity = ExecuteStructuredELTActivityName
	}
	preview.setCheckpoint("parser_execution", CheckpointRunning, "", "")
	executionRefs := map[string]Ref{
		"parser_selection": activeSelectionRef,
		"original":         activeOriginalRef,
		"parser_options":   activeParserOptionsRef,
	}
	for _, name := range []string{"handler_recommendation", "handler_decision", "handler_validation", "detected_format", "content_signature", "handler_compatibility"} {
		if ref := selectionRefs[name]; ref != "" {
			executionRefs[name] = ref
		}
	}
	rawBundleRef, err := r.execActivity(ctx, stagegraph.ExecuteParser, executionActivity, activeFormat, executionRefs)
	if err != nil {
		preview.setCheckpoint("parser_execution", CheckpointFailed, r.receiptRef(stagegraph.ExecuteParser), err.Error())
		return r.result(""), err
	}
	preview.setCheckpoint("parser_execution", CheckpointCompleted, r.receiptRef(stagegraph.ExecuteParser), "")

	// Stage 9: persist_raw_generation_activity, then stage 10:
	// fingerprint_raw_records_activity (context raw-record fingerprint) — strict sequence
	// (persist before hashing the persisted rows). DeclaredFormat is
	// preserved here (not dropped to "") because the raw generation's own
	// persisted record needs to know what format it was parsed from.
	preview.setCheckpoint("storage", CheckpointRunning, "", "")
	rawGenerationRef, err := r.exec(ctx, stagegraph.PersistRawGeneration, activeFormat, map[string]Ref{
		"raw_bundle": rawBundleRef,
	})
	if err != nil {
		preview.setCheckpoint("storage", CheckpointFailed, r.receiptRef(stagegraph.PersistRawGeneration), err.Error())
		return r.result(""), err
	}
	preview.setCheckpoint("storage", CheckpointCompleted, r.receiptRef(stagegraph.PersistRawGeneration), "")
	rawFingerprintManifestRef, err := r.exec(ctx, fingerprint.rawRecords, "", map[string]Ref{
		"raw_generation": rawGenerationRef,
	})
	if err != nil {
		return r.result(""), err
	}

	// Stage 10a: fingerprint_raw_generation_activity — folds the ordered
	// context raw-record fingerprints from fingerprint_raw_records into the
	// raw generation's context fingerprint chain. It reuses the SBV fold
	// formula under the platform raw-all membership tag, because
	// envelope/unparsed spans are members too. Context fingerprint chain is
	// not complete until both the per-record fingerprints and their
	// order-sensitive chain exist. This is NOT custody H3.
	rawGenerationFingerprintChainRef, err := r.exec(ctx, fingerprint.rawGeneration, "", map[string]Ref{
		fingerprint.rawManifestRefKey: rawFingerprintManifestRef,
		"raw_generation":              rawGenerationRef,
	})
	if err != nil {
		return r.result(""), err
	}

	// Stages 11-12: the second parallel pair — both depend only on
	// fingerprint_raw_generation (the completed context fingerprint chain), not on
	// each other.
	reconcilePair, err := r.join(ctx,
		r.start(ctx, stagegraph.ReconcileRecordAccounting, "", map[string]Ref{"raw_generation_chain": rawGenerationFingerprintChainRef}),
		r.start(ctx, stagegraph.ReconcileByteCoverage, "", map[string]Ref{"raw_generation_chain": rawGenerationFingerprintChainRef}),
	)
	if err != nil {
		return r.result(""), err
	}
	accountingRef := reconcilePair[stagegraph.ReconcileRecordAccounting]
	coverageRef := reconcilePair[stagegraph.ReconcileByteCoverage]

	// Stage 13: verify_raw_coverage_against_source_activity joins the
	// reconciliation pair, independently recomputes/verifies the ordered raw
	// generation fingerprint chain, and checks the accounted byte coverage
	// against the context source fingerprint. Verification remains separate
	// from every fingerprint computation.
	preview.setCheckpoint("raw_source_verification", CheckpointRunning, "", "")
	rawSourceVerificationRef, err := r.exec(ctx, stagegraph.VerifyRawCoverageAgainstSource, "", map[string]Ref{
		"accounting":             accountingRef,
		"coverage":               coverageRef,
		fingerprint.sourceRefKey: contextSourceFingerprintRef,
		"raw_generation_chain":   rawGenerationFingerprintChainRef,
	})
	if err != nil {
		preview.setCheckpoint("raw_source_verification", CheckpointFailed, r.receiptRef(stagegraph.VerifyRawCoverageAgainstSource), err.Error())
		return r.result(""), err
	}
	preview.setCheckpoint("raw_source_verification", CheckpointCompleted, r.receiptRef(stagegraph.VerifyRawCoverageAgainstSource), "")

	// Stage 14: normalize_generation_activity, then stage 15:
	// persist_normalized_generation_activity — strict sequence (normalize
	// is transform-only, persist is the only write).
	preview.setCheckpoint("normalization", CheckpointRunning, "", "")
	normalizedBundleRef, err := r.exec(ctx, stagegraph.NormalizeGeneration, "", map[string]Ref{
		"raw_source_verification": rawSourceVerificationRef,
		"raw_generation":          rawGenerationRef,
	})
	if err != nil {
		preview.setCheckpoint("normalization", CheckpointFailed, r.receiptRef(stagegraph.NormalizeGeneration), err.Error())
		return r.result(""), err
	}
	normalizedGenerationRef, err := r.exec(ctx, stagegraph.PersistNormalizedGeneration, "", map[string]Ref{
		"normalized_bundle": normalizedBundleRef,
	})
	if err != nil {
		preview.setCheckpoint("normalization", CheckpointFailed, r.receiptRef(stagegraph.PersistNormalizedGeneration), err.Error())
		return r.result(""), err
	}
	preview.setCheckpoint("normalization", CheckpointCompleted, r.receiptRef(stagegraph.PersistNormalizedGeneration), "")

	// Stages 16-19: the third parallel pair. persist_lineage ->
	// validate_raw_lineage is one branch off persist_normalized_generation;
	// hash_normalized_records (normalized record digests) ->
	// hash_normalized_generation (normalized generation manifest digest) is
	// the other, independent branch. Neither of these is H2 or H3 — those
	// names are reserved for the raw-custody hashes computed by
	// hash_raw_records/hash_raw_generation (vendored/sbv/CUSTODY.md). Both
	// branches are launched via workflow.Go before either is awaited, so
	// they run concurrently.
	lineageBranch := r.branch(ctx, func(gctx workflow.Context) (Ref, error) {
		lineageSetRef, err := r.exec(gctx, stagegraph.PersistLineage, "", map[string]Ref{
			"normalized_generation": normalizedGenerationRef,
			"raw_generation":        rawGenerationRef,
		})
		if err != nil {
			return "", err
		}
		return r.exec(gctx, stagegraph.ValidateRawLineage, "", map[string]Ref{
			"lineage_set": lineageSetRef,
		})
	})
	hashBranch := r.branch(ctx, func(gctx workflow.Context) (Ref, error) {
		normalizedRecordDigestsRef, err := r.exec(gctx, stagegraph.HashNormalizedRecords, "", map[string]Ref{
			"normalized_generation": normalizedGenerationRef,
		})
		if err != nil {
			return "", err
		}
		return r.exec(gctx, stagegraph.HashNormalizedGeneration, "", map[string]Ref{
			"normalized_record_digests": normalizedRecordDigestsRef,
			"normalized_generation":     normalizedGenerationRef,
		})
	})

	var lineageValidationRef Ref
	lineageErr := lineageBranch.Get(ctx, &lineageValidationRef)
	var normalizedGenerationManifestDigestRef Ref
	hashErr := hashBranch.Get(ctx, &normalizedGenerationManifestDigestRef)
	if lineageErr != nil {
		return r.result(""), lineageErr
	}
	if hashErr != nil {
		return r.result(""), hashErr
	}

	// Stage 20: verify_normalized_generation_activity joins the lineage
	// branch and the normalized-digest branch.
	preview.setCheckpoint("completeness", CheckpointRunning, "", "")
	normalizedVerificationRef, err := r.exec(ctx, stagegraph.VerifyNormalizedGeneration, "", map[string]Ref{
		"lineage_validation":                    lineageValidationRef,
		"normalized_generation_manifest_digest": normalizedGenerationManifestDigestRef,
	})
	if err != nil {
		preview.setCheckpoint("completeness", CheckpointFailed, r.receiptRef(stagegraph.VerifyNormalizedGeneration), err.Error())
		return r.result(""), err
	}
	preview.setCheckpoint("completeness", CheckpointCompleted, r.receiptRef(stagegraph.VerifyNormalizedGeneration), "")

	// The browser-facing preview can only be projected after normalized
	// messages and their validation receipts exist. Publishing it before the
	// human hold removes the former circular wait: the operator now reviews
	// actual persisted messages, while workflow_id/run_id remain internal to
	// the opaque binding created by the starter.
	if integratedPreview != workflow.DefaultVersion {
		previewHandle, err := r.execPreview(ctx, PreviewPublicationRequest{
			RequestID: in.RequestID, SourceVersionRef: r.sourceVersionRef,
			RawGenerationRef: rawGenerationRef, NormalizedGenerationRef: normalizedGenerationRef,
			ParserSelectionRef: activeSelectionRef, ParserOptionsRef: activeParserOptionsRef,
			ReceiptRefs: map[string]Ref{
				"raw_source_verification": r.receiptRef(stagegraph.VerifyRawCoverageAgainstSource),
				"parser_selection":        r.receiptRef(stagegraph.SelectParser),
				"parser_execution":        r.receiptRef(stagegraph.ExecuteParser),
				"normalization":           r.receiptRef(stagegraph.PersistNormalizedGeneration),
				"storage":                 r.receiptRef(stagegraph.PersistRawGeneration),
				"completeness":            r.receiptRef(stagegraph.VerifyNormalizedGeneration),
			},
		})
		if err != nil {
			return r.result(""), err
		}
		preview.Phase, preview.PreviewHandle = PhaseAwaitingDecision, previewHandle
		preview.SelectRef, preview.ParserOptionsRef = activeSelectionRef, activeParserOptionsRef
		preview.Reason = ""
		if err := awaitPreviewDecision(ctx, &preview, durableReviewWait); err != nil {
			return r.result(""), err
		}
	}

	// Stage 21: seal_generation_activity.
	sealedGenerationRef, err := r.exec(ctx, stagegraph.SealGeneration, "", map[string]Ref{
		"normalized_verification": normalizedVerificationRef,
	})
	if err != nil {
		return r.result(""), err
	}

	// Stage 22: publish_generation_activity — the sole successor of seal,
	// and therefore the sink whose transitive dependency closure is every
	// other stage.
	publicationRef, err := r.exec(ctx, stagegraph.PublishGeneration, "", map[string]Ref{
		"sealed_generation": sealedGenerationRef,
	})
	if err != nil {
		return r.result(""), err
	}

	return r.result(publicationRef), nil
}

func awaitRepairDecision(ctx workflow.Context, state *PreviewState, waitVersion workflow.Version) (RepairDecision, error) {
	var decision RepairDecision
	decided, err := awaitReviewSignal(ctx, workflow.GetSignalChannel(ctx, RepairDecisionSignalName), &decision, waitVersion)
	if err != nil {
		return RepairDecision{}, fmt.Errorf("proffer: await repair decision: %w", err)
	}
	if !decided {
		state.Phase, state.Reason = PhaseTimedOut, "repair decision timed out"
		return RepairDecision{}, errors.New("proffer: repair decision timed out")
	}
	if decision.DecisionRef == "" {
		state.Phase, state.Reason = PhaseRejected, "repair decision reference is required"
		return RepairDecision{}, errors.New("proffer: repair decision reference is required")
	}
	return decision, nil
}

func awaitHandlerSelectionDecision(ctx workflow.Context, state *PreviewState, waitVersion workflow.Version) (HandlerSelectionDecision, error) {
	var decision HandlerSelectionDecision
	decided, err := awaitReviewSignal(ctx, workflow.GetSignalChannel(ctx, HandlerSelectionDecisionSignalName), &decision, waitVersion)
	if err != nil {
		return HandlerSelectionDecision{}, fmt.Errorf("proffer: await handler selection decision: %w", err)
	}
	if !decided {
		state.Phase, state.Reason = PhaseTimedOut, "handler selection decision timed out"
		return HandlerSelectionDecision{}, errors.New("proffer: handler selection decision timed out")
	}
	if decision.DecisionRef == "" {
		state.Phase, state.Reason = PhaseRejected, "handler selection decision reference is required"
		return HandlerSelectionDecision{}, errors.New("proffer: handler selection decision reference is required")
	}
	return decision, nil
}

func awaitPreviewDecision(ctx workflow.Context, state *PreviewState, waitVersion workflow.Version) error {
	signalChannel := workflow.GetSignalChannel(ctx, PreviewDecisionSignalName)
	for {
		var decision PreviewDecision
		decided, err := awaitReviewSignal(ctx, signalChannel, &decision, waitVersion)
		if err != nil {
			return fmt.Errorf("proffer: await preview decision: %w", err)
		}
		if !decided {
			state.Phase, state.Reason = PhaseTimedOut, "preview decision timed out"
			return errors.New("proffer: preview decision timed out")
		}
		if !decision.Approved {
			state.Phase, state.Reason = PhaseRejected, decision.Reason
			continue
		}
		state.Phase, state.Reason = PhaseApproved, ""
		return nil
	}
}

// awaitLegacyPreviewDecision preserves command ordering and repaired-reference
// behavior for histories started before the normalized preview projection was
// introduced. New runs never take this branch.
func awaitLegacyPreviewDecision(ctx workflow.Context, state *PreviewState, selection, options *Ref, waitVersion workflow.Version) error {
	repairVersion := workflow.GetVersion(ctx, previewRepairChangeID, workflow.DefaultVersion, previewRepairVersion)
	signalChannel := workflow.GetSignalChannel(ctx, PreviewDecisionSignalName)
	wasRejected, repaired := false, false
	for {
		var decision PreviewDecision
		decided, err := awaitReviewSignal(ctx, signalChannel, &decision, waitVersion)
		if err != nil {
			return fmt.Errorf("proffer: await legacy preview decision: %w", err)
		}
		if !decided {
			state.Phase, state.Reason = PhaseTimedOut, "preview decision timed out"
			return errors.New("proffer: preview decision timed out")
		}
		if repairVersion != workflow.DefaultVersion {
			if decision.RepairedSelectionRef != "" {
				*selection, state.SelectRef, repaired = decision.RepairedSelectionRef, decision.RepairedSelectionRef, true
			}
			if decision.RepairedParserOptionsRef != "" {
				*options, state.ParserOptionsRef, repaired = decision.RepairedParserOptionsRef, decision.RepairedParserOptionsRef, true
			}
		}
		if !decision.Approved {
			state.Phase, state.Reason, wasRejected = PhaseRejected, decision.Reason, true
			continue
		}
		if repairVersion != workflow.DefaultVersion && wasRejected && !repaired {
			state.Phase, state.Reason = PhaseRejected, "approval after rejection requires an explicit repaired selection or parser-options reference"
			continue
		}
		state.Phase, state.Reason = PhaseApproved, ""
		return nil
	}
}

// awaitReviewSignal preserves the old 24-hour timer only while replaying a
// history that recorded the pre-change branch. New executions wait durably
// for a Signal with no application-level terminal deadline. The caller's
// Temporal WorkflowExecutionTimeout and explicit cancel/terminate controls
// remain the configurable operational bound, so a healthy human-review wait
// does not turn into a terminal failure merely because a day elapsed.
func awaitReviewSignal(ctx workflow.Context, signal workflow.ReceiveChannel, value any, waitVersion workflow.Version) (bool, error) {
	if waitVersion != workflow.DefaultVersion {
		if err := workflow.Await(ctx, func() bool { return signal.Len() > 0 }); err != nil {
			return false, err
		}
		signal.Receive(ctx, value)
		return true, nil
	}

	decided := false
	timerCtx, cancelTimer := workflow.WithCancel(ctx)
	selector := workflow.NewSelector(ctx)
	timer := workflow.NewTimer(timerCtx, previewDecisionTimeout)
	selector.AddReceive(signal, func(channel workflow.ReceiveChannel, more bool) {
		channel.Receive(ctx, value)
		decided = true
	})
	selector.AddFuture(timer, func(f workflow.Future) { _ = f.Get(timerCtx, nil) })
	selector.Select(ctx)
	if decided {
		cancelTimer()
	}
	return decided, nil
}

// run accumulates the ordered stage receipts and the running
// source/version reference across one workflow execution.
type run struct {
	requestID        string
	matterID         string
	courtCaseID      string
	sourceVersionRef Ref
	results          []StageResult
}

// pending is an in-flight Activity future paired with the stage id that
// started it, so join can attribute a failure to the right stage.
type pending struct {
	id  stagegraph.StageID
	fut workflow.Future
}

// exec runs one Activity to completion and returns its compact result Ref.
// Any Activity execution error, or an explicit StatusFailed result, is
// fail-closed: it is recorded in r.results and returned as an error, and
// the caller's control flow simply does not reach the descendant stages —
// no Temporal API call is made to schedule them.
func (r *run) exec(ctx workflow.Context, id stagegraph.StageID, declaredFormat string, refs map[string]Ref) (Ref, error) {
	return r.settle(id, r.start(ctx, id, declaredFormat, refs).fut.Get, ctx)
}

// execActivity dispatches an implementation-specific Temporal Activity while
// retaining the logical stage identity used by receipts, retry options, and
// downstream references. It exists only for mutually exclusive
// implementations of one stage; it must never schedule both implementations.
func (r *run) execActivity(ctx workflow.Context, id stagegraph.StageID, activityName, declaredFormat string, refs map[string]Ref) (Ref, error) {
	req := StageRequest{
		RequestID: r.requestID, MatterID: r.matterID, CourtCaseID: r.courtCaseID,
		SourceVersionRef: r.sourceVersionRef, DeclaredFormat: declaredFormat, Refs: refs,
	}
	actCtx := workflow.WithActivityOptions(ctx, optionsFor(id))
	future := workflow.ExecuteActivity(actCtx, activityName, req)
	return r.settle(id, future.Get, ctx)
}

func recommendHandler(ctx workflow.Context, req StageRequest) (HandlerRecommendationResult, error) {
	var result HandlerRecommendationResult
	actCtx := workflow.WithActivityOptions(ctx, optionsFor(stagegraph.SelectParser))
	if err := workflow.ExecuteActivity(actCtx, RecommendHandlerActivityName, req).Get(actCtx, &result); err != nil {
		return HandlerRecommendationResult{}, fmt.Errorf("proffer: recommend handler: %w", err)
	}
	if err := validateHandlerRecommendation(result); err != nil {
		return HandlerRecommendationResult{}, fmt.Errorf("proffer: invalid handler recommendation: %w", err)
	}
	return result, nil
}

func validateSelectedHandler(ctx workflow.Context, req StageRequest) (HandlerSelectionValidationResult, error) {
	var result HandlerSelectionValidationResult
	actCtx := workflow.WithActivityOptions(ctx, optionsFor(stagegraph.SelectParser))
	if err := workflow.ExecuteActivity(actCtx, ValidateHandlerSelectionActivityName, req).Get(actCtx, &result); err != nil {
		return HandlerSelectionValidationResult{}, fmt.Errorf("proffer: validate handler selection: %w", err)
	}
	return result, nil
}

// structuredELTEligible exists only for replay of the first versioned DuckDB
// route, before content-backed handler recommendations were introduced. Keep
// the exact canonical signatures aligned with StructuredELTFormatForDeclaredFormat;
// filename-derived aliases such as sms_export_xml must never enter this list.
// New histories route from a validated HandlerCandidate instead.
func structuredELTEligible(declaredFormat string) bool {
	switch strings.TrimSpace(declaredFormat) {
	case "csv", "ndjson", "jsonl", "smsbackuprestore_xml", "chatgpt_official_json", "messages_transcript":
		return true
	default:
		return false
	}
}

func (r *run) execPreview(ctx workflow.Context, request PreviewPublicationRequest) (Ref, error) {
	id := stagegraph.PublishPreview
	actCtx := workflow.WithActivityOptions(ctx, optionsFor(id))
	future := workflow.ExecuteActivity(actCtx, string(id), request)
	return r.settle(id, future.Get, ctx)
}

func (r *run) receiptRef(id stagegraph.StageID) Ref {
	for index := len(r.results) - 1; index >= 0; index-- {
		if r.results[index].Stage == id {
			return r.results[index].ReceiptRef
		}
	}
	return ""
}

// start schedules one Activity without blocking, for use in parallel
// fan-outs and branches.
func (r *run) start(ctx workflow.Context, id stagegraph.StageID, declaredFormat string, refs map[string]Ref) pending {
	req := StageRequest{
		RequestID:        r.requestID,
		MatterID:         r.matterID,
		CourtCaseID:      r.courtCaseID,
		SourceVersionRef: r.sourceVersionRef,
		DeclaredFormat:   declaredFormat,
		Refs:             refs,
	}
	actCtx := workflow.WithActivityOptions(ctx, optionsFor(id))
	return pending{id: id, fut: workflow.ExecuteActivity(actCtx, string(id), req)}
}

// settle awaits one future and records+validates its StageResult. get is
// fut.Get, threaded through so exec and join share exactly one recording
// path. It fails closed on three distinct malformed-result shapes, in
// addition to the ordinary business-failed and Activity-execution-error
// paths:
//   - a nonempty res.Stage that does not equal the invoked stage id (a
//     mismatched identity is never silently accepted);
//   - an empty or unknown res.Status;
//   - a result whose Status doesn't carry the receipt evidence that Status
//     requires — see validateStageResult.
func (r *run) settle(id stagegraph.StageID, get func(workflow.Context, interface{}) error, ctx workflow.Context) (Ref, error) {
	var res StageResult
	if err := get(ctx, &res); err != nil {
		// The Activity may have crashed before producing a receipt at all,
		// so this stays a Temporal execution error — there is no business
		// result here to validate.
		r.results = append(r.results, StageResult{Stage: id, Status: StatusFailed, Reason: err.Error()})
		return "", fmt.Errorf("proffer: stage %q failed: %w", id, err)
	}

	if res.Stage != "" && res.Stage != id {
		mismatchErr := fmt.Errorf("proffer: stage %q returned a result identifying itself as %q", id, res.Stage)
		r.results = append(r.results, StageResult{Stage: id, Status: StatusFailed, Reason: mismatchErr.Error()})
		return "", mismatchErr
	}
	res.Stage = id

	if err := validateStageResult(res); err != nil {
		invalidErr := fmt.Errorf("proffer: stage %q returned an invalid result: %w", id, err)
		r.results = append(r.results, StageResult{Stage: id, Status: StatusFailed, Reason: invalidErr.Error()})
		return "", invalidErr
	}

	r.results = append(r.results, res)
	if res.Status == StatusFailed {
		return "", fmt.Errorf("proffer: stage %q reported failed status: %s", id, res.Reason)
	}

	// A not-applicable stage still produced a durable, independently
	// addressable outcome. Some Activity implementations have a distinct
	// result marker and return it in Ref; source-observation stages instead
	// persist only the N/A receipt. Use that receipt as the dependency Ref
	// when no distinct result exists so descendants never receive an empty
	// reference indistinguishable from an unrecorded outcome. Keep res.Ref
	// untouched in r.results: the workflow receipt must continue to report
	// the Activity's actual StatusNotApplicable result, not rewrite it as a
	// successful materialization.
	if res.Status == StatusNotApplicable && res.Ref == "" {
		return res.ReceiptRef, nil
	}
	return res.Ref, nil
}

// validateStageResult enforces the fail-closed receipt contract: every
// terminal Status must carry the evidence its meaning requires.
// StatusSuccess and StatusNotApplicable both certify that the stage's
// outcome was durably recorded, so both require a non-empty ReceiptRef;
// StatusNotApplicable may have no separate result, so its Ref may be empty;
// settle then uses its required ReceiptRef as the downstream dependency Ref.
// Its Reason and ReceiptRef may not be empty. A business-reported StatusFailed must
// also fail closed with both Reason and ReceiptRef present — it is a real
// receipt, not a bare error string. An empty or unrecognized Status is
// always rejected: there is no default interpretation for "the Activity
// didn't say."
func validateStageResult(res StageResult) error {
	switch res.Status {
	case StatusSuccess:
		if res.Ref == "" {
			return errors.New("success result has an empty result Ref")
		}
		if res.ReceiptRef == "" {
			return errors.New("success result has an empty ReceiptRef")
		}
	case StatusNotApplicable:
		if res.Reason == "" {
			return errors.New("not_applicable result has an empty Reason")
		}
		if res.ReceiptRef == "" {
			return errors.New("not_applicable result has an empty ReceiptRef")
		}
	case StatusFailed:
		if res.Reason == "" {
			return errors.New("failed result has an empty Reason")
		}
		if res.ReceiptRef == "" {
			return errors.New("failed result has an empty ReceiptRef")
		}
	default:
		return fmt.Errorf("unknown or empty Status %q", res.Status)
	}
	return nil
}

// join awaits every pending future, draining all of them deterministically
// before returning, and fails closed if any reported failure (Activity
// error or explicit StatusFailed). It never schedules a descendant stage
// itself — that decision belongs to the caller, which only proceeds past a
// non-nil error return by returning early.
func (r *run) join(ctx workflow.Context, ps ...pending) (map[stagegraph.StageID]Ref, error) {
	out := make(map[stagegraph.StageID]Ref, len(ps))
	var firstErr error
	for _, p := range ps {
		ref, err := r.settle(p.id, p.fut.Get, ctx)
		if err != nil {
			if firstErr == nil {
				firstErr = err
			}
			continue
		}
		out[p.id] = ref
	}
	if firstErr != nil {
		return nil, firstErr
	}
	return out, nil
}

// branch launches fn on its own workflow coroutine so a multi-stage
// dependency chain (e.g. persist_lineage -> validate_raw_lineage) can run
// concurrently with a sibling chain. The returned Future resolves once fn
// returns; fn itself is responsible for fail-closed behavior within its own
// chain via r.exec.
func (r *run) branch(ctx workflow.Context, fn func(workflow.Context) (Ref, error)) workflow.Future {
	future, settable := workflow.NewFuture(ctx)
	workflow.Go(ctx, func(gctx workflow.Context) {
		ref, err := fn(gctx)
		settable.Set(ref, err)
	})
	return future
}

// result builds the terminal WorkflowResult from everything recorded so
// far. publicationRef is empty on any non-success path.
func (r *run) result(publicationRef Ref) WorkflowResult {
	status := StatusSuccess
	if publicationRef == "" {
		status = StatusFailed
	}
	return WorkflowResult{
		SourceVersionRef: r.sourceVersionRef,
		PublicationRef:   publicationRef,
		Status:           status,
		Stages:           r.results,
	}
}
