package proffer

import (
	"context"
	"encoding/json"
	"errors"
	"reflect"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/stretchr/testify/mock"
	"go.temporal.io/sdk/activity"
	"go.temporal.io/sdk/converter"
	"go.temporal.io/sdk/testsuite"
	"go.temporal.io/sdk/workflow"

	"github.com/Cursedpotential/probata/engine/stagegraph"
)

func TestPreviewDecisionDecodesCrossLanguageRepairReferences(t *testing.T) {
	var decision PreviewDecision
	if err := json.Unmarshal([]byte(`{
		"approved": true,
		"decider": "operator",
		"repaired_selection_ref": "selection-v2",
		"repaired_parser_options_ref": "options-v2"
	}`), &decision); err != nil {
		t.Fatal(err)
	}
	if !decision.Approved || decision.RepairedSelectionRef != "selection-v2" || decision.RepairedParserOptionsRef != "options-v2" {
		t.Fatalf("decoded repair decision = %#v", decision)
	}
}

// approveHold signals the preview hold approved shortly after the workflow
// starts. Temporal Signals sent to a running workflow are buffered against
// its history regardless of exactly when the workflow gets around to
// receiving them, so a near-zero delay is not a race here (unlike querying
// current state, which does need to land after a specific point is reached).
func approveHold(env *testsuite.TestWorkflowEnvironment) {
	env.RegisterDelayedCallback(func() {
		env.SignalWorkflow(RepairDecisionSignalName, RepairDecision{DecisionRef: "repair-decision-ref"})
		env.SignalWorkflow(PreviewDecisionSignalName, PreviewDecision{Approved: true, Decider: "test-operator"})
	}, time.Millisecond)
}

// rejectHold signals the preview hold rejected shortly after the workflow
// starts, with reason.
func rejectHold(env *testsuite.TestWorkflowEnvironment, reason string) {
	env.RegisterDelayedCallback(func() {
		env.SignalWorkflow(RepairDecisionSignalName, RepairDecision{DecisionRef: "repair-decision-ref"})
		env.SignalWorkflow(PreviewDecisionSignalName, PreviewDecision{Approved: false, Reason: reason, Decider: "test-operator"})
	}, time.Millisecond)
}

func testInput() WorkflowInput {
	return WorkflowInput{
		RequestID:        "req-1",
		MatterID:         "11111111-1111-1111-1111-111111111111",
		CourtCaseID:      "22222222-2222-2222-2222-222222222222",
		SourceRef:        "acquisition-ref",
		DeclaredFormat:   "whatsapp_export_json",
		ParserOptionsRef: "parser-opts-ref",
	}
}

// stageStub is the golden-path StageResult for id: success, with
// deterministic, id-derived Ref and ReceiptRef so assertions can trace which
// stage produced which registry.
func stageStub(id stagegraph.StageID) StageResult {
	return StageResult{Status: StatusSuccess, Ref: Ref(string(id) + "-ref"), ReceiptRef: Ref(string(id) + "-receipt")}
}

// placeholderActivity exists only so the TestWorkflowEnvironment has a
// function signature to register each canon stage name against. It must
// never actually run: every test mocks it via OnActivity before executing
// the workflow. It is test scaffolding for the SDK's name-based dispatch,
// not an Activity body — this package still implements none of the real
// 26 Activities.
func placeholderActivity(_ context.Context, _ StageRequest) (StageResult, error) {
	return StageResult{}, errors.New("proffer: placeholder activity ran unmocked")
}

// registerAllStages registers placeholderActivity under every canon stage
// name so OnActivity(name, ...) mocks below have somewhere to attach.
func registerAllStages(env *testsuite.TestWorkflowEnvironment) {
	for _, d := range stagegraph.Stages {
		env.RegisterActivityWithOptions(placeholderActivity, activity.RegisterOptions{Name: string(d.ID)})
	}
}

// mockStages registers exactly one OnActivity expectation per stage: the
// golden-path stub for every stage not named in results or errs, and the
// given override otherwise. Registering exactly one expectation per stage
// (rather than a general default plus a separate override) sidesteps
// testify's call-matching order entirely — there is never more than one
// candidate for a given stage name to be ambiguous between.
func mockStages(env *testsuite.TestWorkflowEnvironment, results map[stagegraph.StageID]StageResult, errs map[stagegraph.StageID]error) {
	registerAllStages(env)
	for _, d := range stagegraph.Stages {
		id := d.ID
		if err, ok := errs[id]; ok {
			env.OnActivity(string(id), mock.Anything, mock.Anything).Return(StageResult{}, err).Once()
			continue
		}
		if res, ok := results[id]; ok {
			env.OnActivity(string(id), mock.Anything, mock.Anything).Return(res, nil).Once()
			continue
		}
		env.OnActivity(string(id), mock.Anything, mock.Anything).Return(stageStub(id), nil).Once()
	}
}

// mockAllStagesSucceed registers the golden-path stub for every stage in
// stagegraph.Stages.
func mockAllStagesSucceed(env *testsuite.TestWorkflowEnvironment) {
	mockStages(env, nil, nil)
}

func queryOperation(t *testing.T, env *testsuite.TestWorkflowEnvironment) OperationState {
	t.Helper()
	encoded, err := env.QueryWorkflow(OperationQueryName)
	if err != nil {
		t.Fatalf("query operation state: %v", err)
	}
	var state OperationState
	if err := encoded.Get(&state); err != nil {
		t.Fatalf("decode operation state: %v", err)
	}
	return state
}

// recorder captures Activity invocation names in the order Temporal starts
// them, via SetOnActivityStartedListener. It is safe to append from
// concurrently scheduled activities.
type recorder struct {
	mu    sync.Mutex
	order []string
}

func newOrderRecorder(env *testsuite.TestWorkflowEnvironment) *recorder {
	r := &recorder{}
	env.SetOnActivityStartedListener(func(info *activity.Info, _ context.Context, _ converter.EncodedValues) {
		r.mu.Lock()
		defer r.mu.Unlock()
		r.order = append(r.order, info.ActivityType.Name)
	})
	return r
}

func (r *recorder) snapshot() []string {
	r.mu.Lock()
	defer r.mu.Unlock()
	out := make([]string, len(r.order))
	copy(out, r.order)
	return out
}

func (r *recorder) contains(name string) bool {
	for _, n := range r.snapshot() {
		if n == name {
			return true
		}
	}
	return false
}

func (r *recorder) indexOf(name string) int {
	for i, n := range r.snapshot() {
		if n == name {
			return i
		}
	}
	return -1
}

func TestGoldenPathRunsEveryStageExactlyOnce(t *testing.T) {
	var suite testsuite.WorkflowTestSuite
	env := suite.NewTestWorkflowEnvironment()
	env.RegisterWorkflow(ProfferWorkflow)
	mockAllStagesSucceed(env)
	order := newOrderRecorder(env)
	approveHold(env)

	env.ExecuteWorkflow(ProfferWorkflow, testInput())

	if !env.IsWorkflowCompleted() {
		t.Fatal("workflow did not complete")
	}
	if err := env.GetWorkflowError(); err != nil {
		t.Fatalf("workflow returned error on the golden path: %v", err)
	}

	var result WorkflowResult
	if err := env.GetWorkflowResult(&result); err != nil {
		t.Fatalf("GetWorkflowResult failed: %v", err)
	}
	if result.Status != StatusSuccess {
		t.Errorf("result.Status = %q, want %q", result.Status, StatusSuccess)
	}
	if result.PublicationRef != stageStub(stagegraph.PublishGeneration).Ref {
		t.Errorf("result.PublicationRef = %q, want the publish stage's stub ref", result.PublicationRef)
	}
	if result.SourceVersionRef != stageStub(stagegraph.RegisterSource).Ref {
		t.Errorf("result.SourceVersionRef = %q, want the register_source stage's stub ref", result.SourceVersionRef)
	}

	if len(result.Stages) != len(stagegraph.Stages) {
		t.Fatalf("result.Stages has %d entries, want %d (every stage exactly once)", len(result.Stages), len(stagegraph.Stages))
	}
	seen := make(map[stagegraph.StageID]int, len(result.Stages))
	for _, s := range result.Stages {
		seen[s.Stage]++
		if s.Status != StatusSuccess {
			t.Errorf("stage %q reported status %q on the golden path", s.Stage, s.Status)
		}
	}
	for _, d := range stagegraph.Stages {
		if seen[d.ID] != 1 {
			t.Errorf("stage %q ran %d times, want exactly 1", d.ID, seen[d.ID])
		}
	}

	// The recorder should have seen a Temporal activity-start event for
	// every stage too — proving the workflow actually dispatched each one
	// through Temporal, not just that our own bookkeeping recorded it.
	for _, d := range stagegraph.Stages {
		if !order.contains(string(d.ID)) {
			t.Errorf("stage %q was never started as a Temporal Activity", d.ID)
		}
	}
}

func TestOperationQueryTracksStagesHumanWaitsAndTerminalCompletion(t *testing.T) {
	var suite testsuite.WorkflowTestSuite
	env := suite.NewTestWorkflowEnvironment()
	env.RegisterWorkflow(ProfferWorkflow)
	mockAllStagesSucceed(env)

	var registering, repairWait, previewWait OperationState
	env.SetOnActivityStartedListener(func(info *activity.Info, _ context.Context, _ converter.EncodedValues) {
		if info.ActivityType.Name == string(stagegraph.RegisterSource) {
			registering = queryOperation(t, env)
		}
	})
	env.RegisterDelayedCallback(func() {
		repairWait = queryOperation(t, env)
		env.SignalWorkflow(RepairDecisionSignalName, RepairDecision{DecisionRef: "repair-decision-ref"})
	}, time.Hour)
	env.RegisterDelayedCallback(func() {
		previewWait = queryOperation(t, env)
		env.SignalWorkflow(PreviewDecisionSignalName, PreviewDecision{Approved: true, Decider: "operator"})
	}, 2*time.Hour)

	env.ExecuteWorkflow(ProfferWorkflow, testInput())
	if err := env.GetWorkflowError(); err != nil {
		t.Fatalf("workflow returned error: %v", err)
	}

	if registering.Lifecycle != OperationRunning || registering.CurrentStage != stagegraph.RegisterSource {
		t.Fatalf("registering state = %#v", registering)
	}
	if repairWait.Lifecycle != OperationAwaitingRepairDecision || repairWait.Wait != OperationWaitRepairDecision || repairWait.Terminal {
		t.Fatalf("repair wait state = %#v", repairWait)
	}
	if previewWait.Lifecycle != OperationAwaitingPreviewDecision || previewWait.Wait != OperationWaitPreviewDecision || previewWait.Terminal {
		t.Fatalf("preview wait state = %#v", previewWait)
	}
	if previewWait.CompletedStageCount <= repairWait.CompletedStageCount {
		t.Fatalf("completed stage count did not advance: repair=%d preview=%d", repairWait.CompletedStageCount, previewWait.CompletedStageCount)
	}

	terminal := queryOperation(t, env)
	if terminal.Lifecycle != OperationCompleted || !terminal.Terminal || terminal.Wait != "" || terminal.CurrentStage != "" {
		t.Fatalf("terminal state = %#v", terminal)
	}
	if terminal.SourceVersionRef != stageStub(stagegraph.RegisterSource).Ref {
		t.Fatalf("terminal source version ref = %q", terminal.SourceVersionRef)
	}
	if terminal.CompletedStageCount != len(stagegraph.Stages) || len(terminal.Stages) != len(stagegraph.Stages) {
		t.Fatalf("terminal stages = count %d query rows %d, want %d", terminal.CompletedStageCount, len(terminal.Stages), len(stagegraph.Stages))
	}
}

func TestLegacyOpenWorkflowUsesVersionedActivityAliases(t *testing.T) {
	var suite testsuite.WorkflowTestSuite
	env := suite.NewTestWorkflowEnvironment()
	env.RegisterWorkflow(ProfferWorkflow)
	registerAllStages(env)
	legacyIDs := []stagegraph.StageID{
		stagegraph.StageID(legacyHashSourceActivity),
		stagegraph.StageID(legacyHashRawRecordsActivity),
		stagegraph.StageID(legacyHashRawGenerationActivity),
	}
	for _, id := range legacyIDs {
		env.RegisterActivityWithOptions(placeholderActivity, activity.RegisterOptions{Name: string(id)})
	}
	env.OnGetVersion(fingerprintVocabularyChangeID, workflow.DefaultVersion, fingerprintVocabularyVersion).
		Return(workflow.DefaultVersion).Once()
	for _, id := range legacyIDs {
		env.OnActivity(string(id), mock.Anything, mock.Anything).Return(stageStub(id), nil).Once()
	}
	for _, descriptor := range stagegraph.Stages {
		if descriptor.ID == stagegraph.FingerprintSource || descriptor.ID == stagegraph.FingerprintRawRecords || descriptor.ID == stagegraph.FingerprintRawGeneration {
			continue
		}
		env.OnActivity(string(descriptor.ID), mock.Anything, mock.Anything).Return(stageStub(descriptor.ID), nil).Once()
	}
	order := newOrderRecorder(env)
	approveHold(env)
	env.ExecuteWorkflow(ProfferWorkflow, testInput())
	if err := env.GetWorkflowError(); err != nil {
		t.Fatalf("legacy-version workflow failed: %v", err)
	}
	for _, id := range legacyIDs {
		if !order.contains(string(id)) {
			t.Errorf("legacy workflow did not schedule replay alias %q", id)
		}
	}
	for _, id := range []stagegraph.StageID{stagegraph.FingerprintSource, stagegraph.FingerprintRawRecords, stagegraph.FingerprintRawGeneration} {
		if order.contains(string(id)) {
			t.Errorf("legacy workflow scheduled new activity name %q", id)
		}
	}
}

func TestSafeParallelFanOutAfterRetainOriginal(t *testing.T) {
	var suite testsuite.WorkflowTestSuite
	env := suite.NewTestWorkflowEnvironment()
	env.RegisterWorkflow(ProfferWorkflow)
	mockAllStagesSucceed(env)
	order := newOrderRecorder(env)
	approveHold(env)

	env.ExecuteWorkflow(ProfferWorkflow, testInput())
	if err := env.GetWorkflowError(); err != nil {
		t.Fatalf("workflow returned error on the golden path: %v", err)
	}

	retainIdx := order.indexOf(string(stagegraph.RetainOriginal))
	selectIdx := order.indexOf(string(stagegraph.SelectParser))
	if retainIdx == -1 || selectIdx == -1 || retainIdx >= selectIdx {
		t.Fatalf("retain_original (%d) must start strictly before select_parser (%d)", retainIdx, selectIdx)
	}
	fanOut := []stagegraph.StageID{
		stagegraph.CaptureFilesystemMetadata,
		stagegraph.FingerprintSource,
		stagegraph.InventoryContainer,
		stagegraph.ExtractEmbeddedMetadata,
	}
	for _, id := range fanOut {
		idx := order.indexOf(string(id))
		if idx <= retainIdx || idx >= selectIdx {
			t.Errorf("fan-out stage %q started at position %d, want strictly between retain_original (%d) and select_parser (%d)", id, idx, retainIdx, selectIdx)
		}
	}

	fingerprintRawIdx := order.indexOf(string(stagegraph.FingerprintRawRecords))
	verifyRawIdx := order.indexOf(string(stagegraph.VerifyRawCoverageAgainstSource))
	for _, id := range []stagegraph.StageID{stagegraph.ReconcileRecordAccounting, stagegraph.ReconcileByteCoverage} {
		idx := order.indexOf(string(id))
		if idx <= fingerprintRawIdx || idx >= verifyRawIdx {
			t.Errorf("reconcile stage %q started at position %d, want strictly between fingerprint_raw_records (%d) and verify_raw_coverage_against_source (%d)", id, idx, fingerprintRawIdx, verifyRawIdx)
		}
	}

	persistNormIdx := order.indexOf(string(stagegraph.PersistNormalizedGeneration))
	verifyNormIdx := order.indexOf(string(stagegraph.VerifyNormalizedGeneration))
	branchStages := []stagegraph.StageID{
		stagegraph.PersistLineage,
		stagegraph.ValidateRawLineage,
		stagegraph.HashNormalizedRecords,
		stagegraph.HashNormalizedGeneration,
	}
	for _, id := range branchStages {
		idx := order.indexOf(string(id))
		if idx <= persistNormIdx || idx >= verifyNormIdx {
			t.Errorf("branch stage %q started at position %d, want strictly between persist_normalized_generation (%d) and verify_normalized_generation (%d)", id, idx, persistNormIdx, verifyNormIdx)
		}
	}
	// Within-branch order must still be respected even though the two
	// branches run concurrently with each other.
	if order.indexOf(string(stagegraph.PersistLineage)) >= order.indexOf(string(stagegraph.ValidateRawLineage)) {
		t.Error("persist_lineage must start before validate_raw_lineage")
	}
	if order.indexOf(string(stagegraph.HashNormalizedRecords)) >= order.indexOf(string(stagegraph.HashNormalizedGeneration)) {
		t.Error("hash_normalized_records must start before hash_normalized_generation")
	}
}

// allStagesAfter returns every canon stage id that is not in before, in
// stagegraph.Stages order. Used below to assert an exhaustive "nothing past
// the hold ran" list without hand-maintaining it.
func allStagesExcept(before ...stagegraph.StageID) []stagegraph.StageID {
	excluded := make(map[stagegraph.StageID]bool, len(before))
	for _, id := range before {
		excluded[id] = true
	}
	var out []stagegraph.StageID
	for _, d := range stagegraph.Stages {
		if !excluded[d.ID] {
			out = append(out, d.ID)
		}
	}
	return out
}

// TestPreviewRejectionPausesAndLaterApprovalResumes proves rejection is a
// durable review state rather than terminal workflow failure. The normalized
// preview already exists when the gate opens; later approval resumes the same
// workflow identity without rerunning the parser.
func TestPreviewRejectionPausesAndLaterApprovalResumes(t *testing.T) {
	var suite testsuite.WorkflowTestSuite
	env := suite.NewTestWorkflowEnvironment()
	env.RegisterWorkflow(ProfferWorkflow)
	mockAllStagesSucceed(env)
	rejectHold(env, "wrong format selected")
	var executeReq StageRequest
	var executeSeen bool
	var selectSeen bool
	var activityMu sync.Mutex
	env.SetOnActivityStartedListener(func(info *activity.Info, _ context.Context, args converter.EncodedValues) {
		activityMu.Lock()
		defer activityMu.Unlock()
		if info.ActivityType.Name == string(stagegraph.SelectParser) {
			selectSeen = true
			return
		}
		if info.ActivityType.Name != string(stagegraph.ExecuteParser) {
			return
		}
		if err := args.Get(&executeReq); err != nil {
			t.Fatalf("decoding repaired execute-parser request: %v", err)
		}
		executeSeen = true
	})
	env.RegisterDelayedCallback(func() {
		env.SignalWorkflow(PreviewDecisionSignalName, PreviewDecision{Approved: true, Decider: "review-operator"})
	}, 2*time.Millisecond)

	env.ExecuteWorkflow(ProfferWorkflow, testInput())

	if !env.IsWorkflowCompleted() {
		t.Fatal("workflow did not complete")
	}
	if err := env.GetWorkflowError(); err != nil {
		t.Fatalf("workflow did not resume after repaired approval: %v", err)
	}
	activityMu.Lock()
	defer activityMu.Unlock()
	if !selectSeen {
		t.Fatal("select_parser_activity never ran; test setup is broken")
	}
	if !executeSeen {
		t.Fatal("parser did not execute after later approval resumed the workflow")
	}
	if got := executeReq.Refs["parser_selection"]; got != stageStub(stagegraph.SelectParser).Ref {
		t.Fatalf("execute parser selection ref = %q, want persisted selection", got)
	}
	if got := executeReq.Refs["parser_options"]; got != testInput().ParserOptionsRef {
		t.Fatalf("execute parser options ref = %q, want input options", got)
	}
}

func TestCleanRepairAssessmentAutoResolvesWithoutHumanRepairSignal(t *testing.T) {
	var suite testsuite.WorkflowTestSuite
	env := suite.NewTestWorkflowEnvironment()
	env.RegisterWorkflow(ProfferWorkflow)
	mockStages(env, map[stagegraph.StageID]StageResult{
		stagegraph.AssessSourceRepair: {Status: StatusNotApplicable, Ref: "assessment-clean-ref", ReceiptRef: "assessment-clean-receipt", Reason: "no repair indicated"},
	}, nil)
	var resolveReq StageRequest
	env.SetOnActivityStartedListener(func(info *activity.Info, _ context.Context, args converter.EncodedValues) {
		if info.ActivityType.Name == string(stagegraph.ResolveSourceRepair) {
			_ = args.Get(&resolveReq)
		}
	})
	env.RegisterDelayedCallback(func() {
		env.SignalWorkflow(PreviewDecisionSignalName, PreviewDecision{Approved: true, Decider: "operator"})
	}, time.Millisecond)
	env.ExecuteWorkflow(ProfferWorkflow, testInput())
	if err := env.GetWorkflowError(); err != nil {
		t.Fatalf("clean auto-resolution failed: %v", err)
	}
	if resolveReq.Refs["auto_clean_assessment"] != "assessment-clean-ref" {
		t.Fatalf("resolve refs=%v", resolveReq.Refs)
	}
	if resolveReq.Refs["repair_decision"] != "" {
		t.Fatalf("clean path unexpectedly required human decision: %v", resolveReq.Refs)
	}
}

// TestLegacyPreviewHoldReplaysOriginalTimeout proves histories that already
// recorded the pre-change branch retain their original timer command and
// terminal behavior. New executions take the durable signal-wait branch.
func TestLegacyPreviewHoldReplaysOriginalTimeout(t *testing.T) {
	var suite testsuite.WorkflowTestSuite
	env := suite.NewTestWorkflowEnvironment()
	env.RegisterWorkflow(ProfferWorkflow)
	env.OnGetVersion(durableReviewWaitChangeID, workflow.DefaultVersion, durableReviewWaitVersion).Return(workflow.DefaultVersion)
	mockAllStagesSucceed(env)
	order := newOrderRecorder(env)
	env.RegisterDelayedCallback(func() {
		env.SignalWorkflow(RepairDecisionSignalName, RepairDecision{DecisionRef: "repair-decision-ref"})
	}, time.Millisecond)

	env.ExecuteWorkflow(ProfferWorkflow, testInput())

	if !env.IsWorkflowCompleted() {
		t.Fatal("workflow did not complete")
	}
	err := env.GetWorkflowError()
	if err == nil {
		t.Fatal("workflow returned nil error after the preview hold timed out; fail-closed requires an error")
	}
	if !strings.Contains(err.Error(), "timed out") {
		t.Errorf("workflow error %q does not mention the timeout", err.Error())
	}
	if !order.contains(string(stagegraph.PublishPreview)) {
		t.Error("publish_preview_activity did not run before the timed-out preview hold")
	}
	if order.contains(string(stagegraph.SealGeneration)) || order.contains(string(stagegraph.PublishGeneration)) {
		t.Error("seal/publish ran despite an undecided, timed-out preview hold")
	}
}

// TestDurableReviewSignalsResumeAfterMultipleDays proves both human gates
// remain healthy beyond the former 24-hour deadline. The test environment
// time-skips across two multi-day waits; both late Signals resume the same
// workflow execution and it reaches publication without rerunning a stage.
func TestDurableReviewSignalsResumeAfterMultipleDays(t *testing.T) {
	var suite testsuite.WorkflowTestSuite
	env := suite.NewTestWorkflowEnvironment()
	env.RegisterWorkflow(ProfferWorkflow)
	mockAllStagesSucceed(env)
	order := newOrderRecorder(env)
	env.RegisterDelayedCallback(func() {
		env.SignalWorkflow(RepairDecisionSignalName, RepairDecision{DecisionRef: "late-repair-decision-ref"})
	}, 48*time.Hour)
	env.RegisterDelayedCallback(func() {
		env.SignalWorkflow(PreviewDecisionSignalName, PreviewDecision{Approved: true, Decider: "late-review-operator"})
	}, 96*time.Hour)

	env.ExecuteWorkflow(ProfferWorkflow, testInput())

	if err := env.GetWorkflowError(); err != nil {
		t.Fatalf("late durable review signals did not resume the workflow: %v", err)
	}
	if !order.contains(string(stagegraph.SealGeneration)) || !order.contains(string(stagegraph.PublishGeneration)) {
		t.Fatalf("workflow did not publish after late durable decisions: %v", order.snapshot())
	}
}

func TestFailedStatusHaltsDescendantsAndSealPublish(t *testing.T) {
	var suite testsuite.WorkflowTestSuite
	env := suite.NewTestWorkflowEnvironment()
	env.RegisterWorkflow(ProfferWorkflow)
	mockStages(env, map[stagegraph.StageID]StageResult{
		stagegraph.NormalizeGeneration: {Status: StatusFailed, Reason: "malformed normalized bundle", ReceiptRef: "normalize-generation-failure-receipt"},
	}, nil)
	order := newOrderRecorder(env)
	approveHold(env)

	env.ExecuteWorkflow(ProfferWorkflow, testInput())

	if !env.IsWorkflowCompleted() {
		t.Fatal("workflow did not complete")
	}
	if err := env.GetWorkflowError(); err == nil {
		t.Fatal("workflow returned nil error after an explicit failed status; fail-closed requires an error")
	}

	if !order.contains(string(stagegraph.NormalizeGeneration)) {
		t.Fatal("normalize_generation never ran; test setup is broken")
	}
	descendants := []stagegraph.StageID{
		stagegraph.PersistNormalizedGeneration,
		stagegraph.PersistLineage,
		stagegraph.ValidateRawLineage,
		stagegraph.HashNormalizedRecords,
		stagegraph.HashNormalizedGeneration,
		stagegraph.VerifyNormalizedGeneration,
		stagegraph.SealGeneration,
		stagegraph.PublishGeneration,
	}
	for _, id := range descendants {
		if order.contains(string(id)) {
			t.Errorf("descendant stage %q ran after normalize_generation reported failed status; fail-closed was violated", id)
		}
	}
}

func TestActivityErrorHaltsDescendantsAndSealPublish(t *testing.T) {
	var suite testsuite.WorkflowTestSuite
	env := suite.NewTestWorkflowEnvironment()
	env.RegisterWorkflow(ProfferWorkflow)
	mockStages(env, nil, map[stagegraph.StageID]error{
		stagegraph.FingerprintSource: errors.New("boom: object storage unreachable"),
	})
	order := newOrderRecorder(env)
	env.RegisterDelayedCallback(func() {
		env.SignalWorkflow(RepairDecisionSignalName, RepairDecision{DecisionRef: "repair-decision-ref"})
	}, time.Millisecond)

	env.ExecuteWorkflow(ProfferWorkflow, testInput())

	if !env.IsWorkflowCompleted() {
		t.Fatal("workflow did not complete")
	}
	if err := env.GetWorkflowError(); err == nil {
		t.Fatal("workflow returned nil error after an Activity execution error; fail-closed requires an error")
	}

	if !order.contains(string(stagegraph.FingerprintSource)) {
		t.Fatal("fingerprint_source never ran; test setup is broken")
	}
	// fingerprint_source's fan-out siblings are independent and were already
	// scheduled concurrently — they are expected to have run.
	for _, id := range []stagegraph.StageID{
		stagegraph.CaptureFilesystemMetadata,
		stagegraph.InventoryContainer,
		stagegraph.ExtractEmbeddedMetadata,
	} {
		if !order.contains(string(id)) {
			t.Errorf("fan-out sibling %q should still have run concurrently with the failing fingerprint_source stage", id)
		}
	}
	// Nothing that depends on the fan-out joining successfully may run.
	descendants := []stagegraph.StageID{
		stagegraph.SelectParser,
		stagegraph.ExecuteParser,
		stagegraph.PersistRawGeneration,
		stagegraph.FingerprintRawRecords,
		stagegraph.FingerprintRawGeneration,
		stagegraph.ReconcileRecordAccounting,
		stagegraph.ReconcileByteCoverage,
		stagegraph.VerifyRawCoverageAgainstSource,
		stagegraph.NormalizeGeneration,
		stagegraph.PersistNormalizedGeneration,
		stagegraph.SealGeneration,
		stagegraph.PublishGeneration,
	}
	for _, id := range descendants {
		if order.contains(string(id)) {
			t.Errorf("descendant stage %q ran after hash_source failed with an Activity error; fail-closed was violated", id)
		}
	}
}

func TestNotApplicableProducesReceiptAndContinues(t *testing.T) {
	var suite testsuite.WorkflowTestSuite
	env := suite.NewTestWorkflowEnvironment()
	env.RegisterWorkflow(ProfferWorkflow)
	mockStages(env, map[stagegraph.StageID]StageResult{
		stagegraph.ExtractEmbeddedMetadata: {Status: StatusNotApplicable, Reason: "source format carries no embedded metadata", ReceiptRef: "extract-embedded-metadata-na-receipt"},
	}, nil)
	approveHold(env)

	env.ExecuteWorkflow(ProfferWorkflow, testInput())

	if !env.IsWorkflowCompleted() {
		t.Fatal("workflow did not complete")
	}
	if err := env.GetWorkflowError(); err != nil {
		t.Fatalf("workflow returned error even though the only non-success stage was not_applicable: %v", err)
	}

	var result WorkflowResult
	if err := env.GetWorkflowResult(&result); err != nil {
		t.Fatalf("GetWorkflowResult failed: %v", err)
	}
	if result.Status != StatusSuccess {
		t.Errorf("result.Status = %q, want %q (not_applicable must not fail the run)", result.Status, StatusSuccess)
	}
	if result.PublicationRef == "" {
		t.Error("result.PublicationRef is empty; the workflow should have reached publish_generation")
	}

	found := false
	for _, s := range result.Stages {
		if s.Stage == stagegraph.ExtractEmbeddedMetadata {
			found = true
			if s.Status != StatusNotApplicable {
				t.Errorf("extract_embedded_metadata status = %q, want %q", s.Status, StatusNotApplicable)
			}
			if s.Reason == "" {
				t.Error("not_applicable receipt is missing its Reason")
			}
			if s.ReceiptRef == "" {
				t.Error("not_applicable receipt is missing its ReceiptRef")
			}
		}
	}
	if !found {
		t.Fatal("extract_embedded_metadata never produced a receipt in result.Stages")
	}
}

// TestNonContainerNotApplicableReceiptsReachParserSelectionAndPreview proves
// the ordinary non-container path does not lose its durable observation
// outcomes. Inventory and embedded-metadata Activities correctly return
// StatusNotApplicable with receipts but no separate Ref; the workflow uses
// those receipts as select_parser_activity dependency references, reaches
// the human preview hold, and retains the original N/A results in its final
// stage ledger.
func TestNonContainerNotApplicableReceiptsReachParserSelectionAndPreview(t *testing.T) {
	var suite testsuite.WorkflowTestSuite
	env := suite.NewTestWorkflowEnvironment()
	env.RegisterWorkflow(ProfferWorkflow)
	mockStages(env, map[stagegraph.StageID]StageResult{
		stagegraph.CaptureFilesystemMetadata: {
			Status: StatusSuccess, Ref: "filesystem-metadata-ref", ReceiptRef: "filesystem-metadata-receipt",
		},
		stagegraph.InventoryContainer: {
			Status: StatusNotApplicable, Reason: "source is not a container", ReceiptRef: "inventory-na-receipt",
		},
		stagegraph.ExtractEmbeddedMetadata: {
			Status: StatusNotApplicable, Reason: "source carries no embedded metadata", ReceiptRef: "metadata-na-receipt",
		},
	}, nil)

	var mu sync.Mutex
	var selectRequest *StageRequest
	var executeRequest *StageRequest
	env.SetOnActivityStartedListener(func(info *activity.Info, _ context.Context, args converter.EncodedValues) {
		if info.ActivityType.Name != string(stagegraph.SelectParser) && info.ActivityType.Name != string(stagegraph.ExecuteParser) {
			return
		}
		var req StageRequest
		if err := args.Get(&req); err != nil {
			t.Errorf("decoding StageRequest for %s: %v", info.ActivityType.Name, err)
			return
		}
		mu.Lock()
		if info.ActivityType.Name == string(stagegraph.SelectParser) {
			selectRequest = &req
		} else {
			executeRequest = &req
		}
		mu.Unlock()
	})
	approveHold(env)

	env.ExecuteWorkflow(ProfferWorkflow, testInput())
	if err := env.GetWorkflowError(); err != nil {
		t.Fatalf("non-container workflow returned error: %v", err)
	}

	mu.Lock()
	gotRequest := selectRequest
	gotExecute := executeRequest
	mu.Unlock()
	if gotRequest == nil {
		t.Fatal("select_parser_activity was never observed")
	}
	wantRefs := map[string]Ref{
		"filesystem_metadata": "filesystem-metadata-ref",
		"container_manifest":  "inventory-na-receipt",
		"metadata_manifest":   "metadata-na-receipt",
	}
	if !reflect.DeepEqual(gotRequest.Refs, wantRefs) {
		t.Errorf("select_parser_activity refs = %#v, want %#v", gotRequest.Refs, wantRefs)
	}
	for name, ref := range gotRequest.Refs {
		if ref == "" {
			t.Errorf("select_parser_activity ref %q is empty", name)
		}
	}
	if gotExecute == nil {
		t.Fatal("execute_parser_activity never ran after preview approval; workflow did not cross the human hold")
	}
	if gotExecute.Refs["parser_selection"] == "" {
		t.Errorf("execute_parser_activity received an empty parser_selection after preview: %#v", gotExecute.Refs)
	}

	var result WorkflowResult
	if err := env.GetWorkflowResult(&result); err != nil {
		t.Fatalf("GetWorkflowResult failed: %v", err)
	}
	wantNA := map[stagegraph.StageID]Ref{
		stagegraph.InventoryContainer:      "inventory-na-receipt",
		stagegraph.ExtractEmbeddedMetadata: "metadata-na-receipt",
	}
	for _, stage := range result.Stages {
		wantReceipt, ok := wantNA[stage.Stage]
		if !ok {
			continue
		}
		if stage.Status != StatusNotApplicable || stage.Ref != "" || stage.ReceiptRef != wantReceipt {
			t.Errorf("recorded N/A stage %#v was rewritten or lost; want status not_applicable, empty Ref, receipt %q", stage, wantReceipt)
		}
		delete(wantNA, stage.Stage)
	}
	if len(wantNA) != 0 {
		t.Errorf("missing N/A stage receipts in workflow result: %#v", wantNA)
	}
}

// TestNotApplicableByteCoverageRefReachesVerification proves a
// StatusNotApplicable result's Ref, when the activity chose to set one, is
// not dropped: reconcile_byte_coverage_activity's N/A ref must reach
// verify_raw_coverage_against_source_activity's "coverage" input exactly
// like a success ref would (types.go's StageResult.Ref doc comment).
func TestNotApplicableByteCoverageRefReachesVerification(t *testing.T) {
	var suite testsuite.WorkflowTestSuite
	env := suite.NewTestWorkflowEnvironment()
	env.RegisterWorkflow(ProfferWorkflow)
	mockStages(env, map[stagegraph.StageID]StageResult{
		stagegraph.ReconcileByteCoverage: {
			Status: StatusNotApplicable, Ref: "byte-coverage-na-marker",
			Reason: "source format carries no byte-addressable coverage to reconcile", ReceiptRef: "byte-coverage-na-receipt",
		},
	}, nil)
	approveHold(env)

	var mu sync.Mutex
	var gotReq *StageRequest
	env.SetOnActivityStartedListener(func(info *activity.Info, _ context.Context, args converter.EncodedValues) {
		if info.ActivityType.Name != string(stagegraph.VerifyRawCoverageAgainstSource) {
			return
		}
		var req StageRequest
		if err := args.Get(&req); err != nil {
			t.Fatalf("decoding StageRequest for verify_raw_coverage_against_source_activity: %v", err)
		}
		mu.Lock()
		gotReq = &req
		mu.Unlock()
	})

	env.ExecuteWorkflow(ProfferWorkflow, testInput())
	if err := env.GetWorkflowError(); err != nil {
		t.Fatalf("workflow returned error on the golden path: %v", err)
	}

	if gotReq == nil {
		t.Fatal("verify_raw_coverage_against_source_activity was never observed by the listener")
	}
	if got := gotReq.Refs["coverage"]; got != "byte-coverage-na-marker" {
		t.Errorf(`verify_raw_coverage_against_source_activity Refs["coverage"] = %q, want the not_applicable ref to have propagated`, got)
	}
}

// TestWireTypesCarryOnlyCompactReferences is a structural proof, not a
// behavioral one: it walks every exported field of every wire type by
// reflection and fails if any field's type is anything other than Ref,
// Status, ActivityName, a plain string tag, or a small collection of those.
// This is what "only compact refs cross stage boundaries" actually means at
// the type level — no field here can ever hold a file, a raw record, a
// normalized record, or a metadata payload, because no such type exists in
// this package.
func TestWireTypesCarryOnlyCompactReferences(t *testing.T) {
	allowedScalar := map[reflect.Type]bool{
		reflect.TypeOf(Ref("")):          true,
		reflect.TypeOf(Status("")):       true,
		reflect.TypeOf(ActivityName("")): true,
		reflect.TypeOf(""):               true,
	}

	var checkStruct func(t *testing.T, v interface{})
	checkStruct = func(t *testing.T, v interface{}) {
		rt := reflect.TypeOf(v)
		for i := 0; i < rt.NumField(); i++ {
			f := rt.Field(i)
			ft := f.Type
			switch ft.Kind() {
			case reflect.Map:
				if ft.Key().Kind() != reflect.String || !allowedScalar[ft.Elem()] {
					t.Errorf("%s.%s has disallowed map type %s; wire-type maps may only be string-keyed refs", rt.Name(), f.Name, ft)
				}
			case reflect.Slice:
				if ft.Elem() != reflect.TypeOf(StageResult{}) {
					t.Errorf("%s.%s has disallowed slice type %s; the only allowed slice is []StageResult", rt.Name(), f.Name, ft)
				}
			default:
				if !allowedScalar[ft] {
					t.Errorf("%s.%s has disallowed type %s; wire types may only carry Ref/Status/ActivityName/string fields or compact collections of them", rt.Name(), f.Name, ft)
				}
			}
		}
	}

	checkStruct(t, WorkflowInput{})
	checkStruct(t, StageRequest{})
	checkStruct(t, StageResult{})
	checkStruct(t, WorkflowResult{})
}

// TestPersistRawGenerationReceivesDeclaredFormat proves
// persist_raw_generation_activity's StageRequest carries the run's actual
// DeclaredFormat rather than an empty string — the raw generation record it
// persists needs to know what format it was parsed from.
func TestPersistRawGenerationReceivesDeclaredFormat(t *testing.T) {
	var suite testsuite.WorkflowTestSuite
	env := suite.NewTestWorkflowEnvironment()
	env.RegisterWorkflow(ProfferWorkflow)
	mockAllStagesSucceed(env)
	approveHold(env)

	var mu sync.Mutex
	var gotFormat string
	var seen bool
	env.SetOnActivityStartedListener(func(info *activity.Info, _ context.Context, args converter.EncodedValues) {
		if info.ActivityType.Name != string(stagegraph.PersistRawGeneration) {
			return
		}
		var req StageRequest
		if err := args.Get(&req); err != nil {
			t.Fatalf("decoding StageRequest for persist_raw_generation_activity: %v", err)
		}
		mu.Lock()
		gotFormat, seen = req.DeclaredFormat, true
		mu.Unlock()
	})

	in := testInput()
	env.ExecuteWorkflow(ProfferWorkflow, in)
	if err := env.GetWorkflowError(); err != nil {
		t.Fatalf("workflow returned error on the golden path: %v", err)
	}

	if !seen {
		t.Fatal("persist_raw_generation_activity was never observed by the listener")
	}
	if gotFormat != in.DeclaredFormat {
		t.Errorf("persist_raw_generation_activity StageRequest.DeclaredFormat = %q, want %q", gotFormat, in.DeclaredFormat)
	}
}

// TestRequestIDPropagatesToEveryActivity proves WorkflowInput.RequestID is
// not dead input: it decodes the real StageRequest Temporal dispatched for
// every one of the 26 stages (not just register_source_activity) and checks
// each carries the same client-supplied RequestID, so any Activity —
// register_source_activity included — can key its own idempotency/dedup
// checks off it.
func TestRequestIDPropagatesToEveryActivity(t *testing.T) {
	var suite testsuite.WorkflowTestSuite
	env := suite.NewTestWorkflowEnvironment()
	env.RegisterWorkflow(ProfferWorkflow)
	mockAllStagesSucceed(env)

	var mu sync.Mutex
	seen := make(map[string]string)
	env.SetOnActivityStartedListener(func(info *activity.Info, _ context.Context, args converter.EncodedValues) {
		if info.ActivityType.Name == string(stagegraph.PublishPreview) {
			var req PreviewPublicationRequest
			if err := args.Get(&req); err != nil {
				t.Fatalf("decoding PreviewPublicationRequest: %v", err)
			}
			mu.Lock()
			seen[info.ActivityType.Name] = req.RequestID
			mu.Unlock()
			return
		}
		var req StageRequest
		if err := args.Get(&req); err != nil {
			t.Fatalf("decoding StageRequest for %s: %v", info.ActivityType.Name, err)
		}
		mu.Lock()
		seen[info.ActivityType.Name] = req.RequestID
		mu.Unlock()
	})

	in := testInput()
	approveHold(env)
	env.ExecuteWorkflow(ProfferWorkflow, in)
	if err := env.GetWorkflowError(); err != nil {
		t.Fatalf("workflow returned error on the golden path: %v", err)
	}

	for _, d := range stagegraph.Stages {
		got, ok := seen[string(d.ID)]
		if !ok {
			t.Errorf("stage %q never observed by the listener", d.ID)
			continue
		}
		if got != in.RequestID {
			t.Errorf("stage %q StageRequest.RequestID = %q, want %q", d.ID, got, in.RequestID)
		}
	}
}

// TestSelectParserDoesNotReceiveContextSourceFingerprintRef proves context
// source fingerprint identity (from fingerprint_source_activity) never reaches
// select_parser_activity's request, even though select_parser still joins the
// fan-out that produces it (proven separately by
// TestSafeParallelFanOutAfterRetainOriginal, which asserts fingerprint_source
// starts strictly before select_parser).
func TestSelectParserDoesNotReceiveContextSourceFingerprintRef(t *testing.T) {
	var suite testsuite.WorkflowTestSuite
	env := suite.NewTestWorkflowEnvironment()
	env.RegisterWorkflow(ProfferWorkflow)
	mockAllStagesSucceed(env)

	var mu sync.Mutex
	var gotReq *StageRequest
	env.SetOnActivityStartedListener(func(info *activity.Info, _ context.Context, args converter.EncodedValues) {
		if info.ActivityType.Name != string(stagegraph.SelectParser) {
			return
		}
		var req StageRequest
		if err := args.Get(&req); err != nil {
			t.Fatalf("decoding StageRequest for select_parser_activity: %v", err)
		}
		mu.Lock()
		gotReq = &req
		mu.Unlock()
	})
	approveHold(env)

	env.ExecuteWorkflow(ProfferWorkflow, testInput())
	if err := env.GetWorkflowError(); err != nil {
		t.Fatalf("workflow returned error on the golden path: %v", err)
	}

	if gotReq == nil {
		t.Fatal("select_parser_activity was never observed by the listener")
	}
	if ref, ok := gotReq.Refs["context_source_fingerprint"]; ok {
		t.Errorf("select_parser_activity request carried a context_source_fingerprint ref (%q); hash identity must not influence parser selection", ref)
	}
}

// TestSettleRejectsInvalidStageResults proves every malformed-result shape
// settle must fail closed on: empty/unknown Status, a StatusSuccess with an
// empty result Ref or empty ReceiptRef, a StatusNotApplicable with an empty
// Reason or empty ReceiptRef, a business StatusFailed with an empty Reason
// or empty ReceiptRef, and a nonempty res.Stage that mismatches the invoked
// stage. Each case is exercised via register_source_activity, the graph's
// root, so a rejection there halts the run immediately and unambiguously.
func TestSettleRejectsInvalidStageResults(t *testing.T) {
	cases := []struct {
		name string
		res  StageResult
	}{
		{"empty status", StageResult{Ref: "x", ReceiptRef: "r"}},
		{"unknown status", StageResult{Status: "bogus", Ref: "x", ReceiptRef: "r"}},
		{"success empty result ref", StageResult{Status: StatusSuccess, ReceiptRef: "r"}},
		{"success empty receipt ref", StageResult{Status: StatusSuccess, Ref: "x"}},
		{"not_applicable empty reason", StageResult{Status: StatusNotApplicable, ReceiptRef: "r"}},
		{"not_applicable empty receipt ref", StageResult{Status: StatusNotApplicable, Reason: "n/a"}},
		{"failed empty reason", StageResult{Status: StatusFailed, ReceiptRef: "r"}},
		{"failed empty receipt ref", StageResult{Status: StatusFailed, Reason: "boom"}},
		{"mismatched stage identity", StageResult{Stage: stagegraph.FingerprintSource, Status: StatusSuccess, Ref: "x", ReceiptRef: "r"}},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			var suite testsuite.WorkflowTestSuite
			env := suite.NewTestWorkflowEnvironment()
			env.RegisterWorkflow(ProfferWorkflow)
			mockStages(env, map[stagegraph.StageID]StageResult{
				stagegraph.RegisterSource: tc.res,
			}, nil)

			env.ExecuteWorkflow(ProfferWorkflow, testInput())

			if !env.IsWorkflowCompleted() {
				t.Fatal("workflow did not complete")
			}
			if err := env.GetWorkflowError(); err == nil {
				t.Fatalf("workflow returned nil error for invalid StageResult %+v; settle must reject it", tc.res)
			}
		})
	}
}

// TestSettleAcceptsValidStatusFailedReceipt proves a well-formed
// business-reported StatusFailed (Reason and ReceiptRef both present) is
// accepted by settle's validation — it is rejected by the ordinary
// fail-closed status check, not by validation, and the error message traces
// back to the Reason the Activity actually reported rather than a generic
// "invalid result" complaint.
func TestSettleAcceptsValidStatusFailedReceipt(t *testing.T) {
	var suite testsuite.WorkflowTestSuite
	env := suite.NewTestWorkflowEnvironment()
	env.RegisterWorkflow(ProfferWorkflow)
	mockStages(env, map[stagegraph.StageID]StageResult{
		stagegraph.RegisterSource: {Status: StatusFailed, Reason: "duplicate request id", ReceiptRef: "register-source-failure-receipt"},
	}, nil)

	env.ExecuteWorkflow(ProfferWorkflow, testInput())

	if !env.IsWorkflowCompleted() {
		t.Fatal("workflow did not complete")
	}
	err := env.GetWorkflowError()
	if err == nil {
		t.Fatal("workflow returned nil error after a business-reported failed status; fail-closed requires an error")
	}
	if !strings.Contains(err.Error(), "duplicate request id") {
		t.Errorf("workflow error %q does not surface the Activity's actual Reason; validation should not have masked it as a generic invalid-result error", err.Error())
	}
	if strings.Contains(err.Error(), "invalid result") {
		t.Errorf("workflow error %q was rejected by validateStageResult, not by the ordinary failed-status check; a well-formed business failure must pass validation", err.Error())
	}
}
