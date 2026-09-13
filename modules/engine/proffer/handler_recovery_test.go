package proffer

import (
	"context"
	"strings"
	"testing"
	"time"

	"github.com/Cursedpotential/probata/engine/stagegraph"
	"github.com/stretchr/testify/mock"
	"go.temporal.io/sdk/activity"
	"go.temporal.io/sdk/temporal"
	"go.temporal.io/sdk/testsuite"
)

func TestLoggedDuckDBFailureOffersActorSelectedDecoderRecovery(t *testing.T) {
	var suite testsuite.WorkflowTestSuite
	env := suite.NewTestWorkflowEnvironment()
	env.RegisterWorkflow(ProfferWorkflow)
	registerAllStages(env)
	env.RegisterActivityWithOptions(placeholderActivity, activity.RegisterOptions{Name: SelectStructuredELTActivityName})
	env.RegisterActivityWithOptions(placeholderActivity, activity.RegisterOptions{Name: ExecuteStructuredELTActivityName})
	env.RegisterActivityWithOptions(func(context.Context, HandlerRecoveryRequest) (HandlerRecommendationResult, error) {
		return HandlerRecommendationResult{}, nil
	}, activity.RegisterOptions{Name: RecoverHandlerActivityName})
	for _, descriptor := range stagegraph.Stages {
		env.OnActivity(string(descriptor.ID), mock.Anything, mock.Anything).Return(stageStub(descriptor.ID), nil).Once()
	}
	initial := handlerRecommendation("smsbackuprestore_xml", HandlerPathDuckDB)
	initial.EngineDecisionRef = "handler-decision-ref"
	recovery := initial
	recovery.EngineDecisionRef = ""
	recovery.RecommendationRef = "recovery-recommendation"
	recovery.FailureReceiptRef = "logged-failure-receipt"
	recovery.Alternatives = []HandlerCandidate{handlerCandidate(HandlerPathDecoder)}
	validation := handlerValidation(recovery)
	validation.Chosen = recovery.Alternatives[0]
	env.OnActivity(RecommendHandlerActivityName, mock.Anything, mock.Anything).Return(initial, nil).Once()
	env.OnActivity(ValidateHandlerSelectionActivityName, mock.Anything, mock.MatchedBy(func(req StageRequest) bool { return req.Refs["handler_recommendation"] == initial.RecommendationRef })).Return(handlerValidation(initial), nil).Once()
	env.OnActivity(ValidateHandlerSelectionActivityName, mock.Anything, mock.MatchedBy(func(req StageRequest) bool { return req.Refs["handler_recommendation"] == recovery.RecommendationRef })).Return(validation, nil).Once()
	env.OnActivity(SelectStructuredELTActivityName, mock.Anything, mock.Anything).Return(stageStub(stagegraph.SelectParser), nil).Once()
	env.OnActivity(ExecuteStructuredELTActivityName, mock.Anything, mock.Anything).Return(StageResult{}, temporal.NewNonRetryableApplicationError("DuckDB Webbed unavailable", "test_failure", nil)).Once()
	env.OnActivity(RecoverHandlerActivityName, mock.Anything, mock.MatchedBy(func(req HandlerRecoveryRequest) bool {
		return strings.Contains(req.FailureReason, "Webbed unavailable") && req.AttemptIdentity != "" && req.Request.Refs["handler_validation"] != ""
	})).Return(recovery, nil).Once()
	order := newOrderRecorder(env)
	env.RegisterDelayedCallback(func() {
		env.SignalWorkflow(RepairDecisionSignalName, RepairDecision{DecisionRef: "repair-decision-ref"})
		env.SignalWorkflow(PreviewDecisionSignalName, PreviewDecision{Approved: true, Decider: "operator"})
	}, time.Millisecond)
	env.RegisterDelayedCallback(func() {
		env.SignalWorkflow(HandlerSelectionDecisionSignalName, HandlerSelectionDecision{DecisionRef: "handler-decision-ref"})
	}, time.Second)
	in := testInput()
	in.DeclaredFormat = "smsbackuprestore_xml"
	env.ExecuteWorkflow(ProfferWorkflow, in)
	if err := env.GetWorkflowError(); err != nil {
		t.Fatal(err)
	}
	if order.indexOf(ExecuteStructuredELTActivityName) >= order.indexOf(RecoverHandlerActivityName) || order.indexOf(RecoverHandlerActivityName) >= order.indexOf(string(stagegraph.ExecuteParser)) {
		t.Fatalf("invalid recovery order: %v", order.snapshot())
	}
	var result WorkflowResult
	if err := env.GetWorkflowResult(&result); err != nil {
		t.Fatal(err)
	}
	failed, success := 0, 0
	for _, stage := range result.Stages {
		if stage.Stage == stagegraph.ExecuteParser {
			if stage.Status == StatusFailed {
				failed++
			}
			if stage.Status == StatusSuccess {
				success++
			}
		}
	}
	if failed != 1 || success != 1 {
		t.Fatalf("failure was overwritten: failed=%d success=%d", failed, success)
	}
	env.AssertExpectations(t)
}
