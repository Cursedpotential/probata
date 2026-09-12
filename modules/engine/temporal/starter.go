package temporal

import (
	"context"
	"errors"
	"fmt"
	"strings"

	"go.temporal.io/api/serviceerror"
	"go.temporal.io/sdk/client"

	"github.com/Cursedpotential/probata/engine/proffer"
)

// WorkflowStarter is the narrow surface the HTTP starter service (httpapi.go)
// needs: start one real engine/proffer.ProfferWorkflow run, signal a
// held run's human decision, and query its preview state. Defining this
// instead of depending on the full client.Client interface keeps httpapi.go's
// tests free of a real Temporal connection.
type WorkflowStarter interface {
	// Start begins one ProfferWorkflow run with in.RequestID as the
	// Temporal workflow ID.
	Start(ctx context.Context, in proffer.WorkflowInput) (workflowID, runID string, err error)
	// Decide sends proffer.PreviewDecisionSignalName to a held run. This is a
	// real Temporal Signal: it is delivered and buffered by the Temporal
	// server against the workflow's own history, so it works regardless of
	// which worker process (if any) happens to be polling right now, and
	// survives a worker restart between the hold starting and the decision
	// arriving.
	Decide(ctx context.Context, workflowID string, decision proffer.PreviewDecision) error
	DecideRepair(ctx context.Context, workflowID string, decision proffer.RepairDecision) error
	DecideHandler(ctx context.Context, workflowID string, decision proffer.HandlerSelectionDecision) error
	// Preview queries proffer.PreviewQueryName on a run. Like Decide, this goes
	// through the Temporal server against durable workflow state, not any
	// process-local cache.
	Preview(ctx context.Context, workflowID string) (proffer.PreviewState, error)
}

// temporalStarter is the production WorkflowStarter, backed by a real
// Temporal client.Client.
type temporalStarter struct {
	client    client.Client
	taskQueue string
}

// NewWorkflowStarter wraps an already-dialed Temporal client. It does not own
// the client's lifecycle — the caller (cmd/starter/main.go) dials and closes
// it.
func NewWorkflowStarter(c client.Client, taskQueue string) (WorkflowStarter, error) {
	if c == nil {
		return nil, errors.New("temporal: workflow starter requires a Temporal client")
	}
	if strings.TrimSpace(taskQueue) == "" {
		return nil, errors.New("temporal: workflow starter requires a task queue")
	}
	return &temporalStarter{client: c, taskQueue: taskQueue}, nil
}

// Start begins one ProfferWorkflow run with in.RequestID as the
// Temporal workflow ID, so a duplicate submission with the same RequestID
// joins the existing run instead of starting a second one.
func (s *temporalStarter) Start(ctx context.Context, in proffer.WorkflowInput) (string, string, error) {
	if strings.TrimSpace(in.RequestID) == "" {
		return "", "", errors.New("temporal: request_id is required to start the workflow")
	}
	run, err := s.client.ExecuteWorkflow(ctx, client.StartWorkflowOptions{
		ID:        in.RequestID,
		TaskQueue: s.taskQueue,
	}, proffer.ProfferWorkflow, in)
	if err != nil {
		if runID, ok := alreadyStartedRunID(err); ok {
			return in.RequestID, runID, nil
		}
		return "", "", fmt.Errorf("temporal: start proffer workflow (formerly universal import workflow): %w", err)
	}
	return run.GetID(), run.GetRunID(), nil
}

func alreadyStartedRunID(err error) (string, bool) {
	var alreadyStarted *serviceerror.WorkflowExecutionAlreadyStarted
	if !errors.As(err, &alreadyStarted) || strings.TrimSpace(alreadyStarted.RunId) == "" {
		return "", false
	}
	return alreadyStarted.RunId, true
}

// Decide sends the human preview_decision Signal to a held workflow.
func (s *temporalStarter) Decide(ctx context.Context, workflowID string, decision proffer.PreviewDecision) error {
	if strings.TrimSpace(workflowID) == "" {
		return errors.New("temporal: workflow_id is required to send a preview decision")
	}
	if err := s.client.SignalWorkflow(ctx, workflowID, "", proffer.PreviewDecisionSignalName, decision); err != nil {
		return fmt.Errorf("temporal: signal preview decision: %w", err)
	}
	return nil
}

func (s *temporalStarter) DecideRepair(ctx context.Context, workflowID string, decision proffer.RepairDecision) error {
	if strings.TrimSpace(workflowID) == "" || decision.DecisionRef == "" {
		return errors.New("temporal: workflow_id and repair decision reference are required")
	}
	if err := s.client.SignalWorkflow(ctx, workflowID, "", proffer.RepairDecisionSignalName, decision); err != nil {
		return fmt.Errorf("temporal: signal repair decision: %w", err)
	}
	return nil
}

// DecideHandler transports only the durable actor-bound decision reference.
// Handler identity, format, compatibility, and actor are deliberately reloaded
// by the validation Activity rather than copied into Temporal history.
func (s *temporalStarter) DecideHandler(ctx context.Context, workflowID string, decision proffer.HandlerSelectionDecision) error {
	if strings.TrimSpace(workflowID) == "" || decision.DecisionRef == "" {
		return errors.New("temporal: workflow_id and handler decision reference are required")
	}
	if err := s.client.SignalWorkflow(ctx, workflowID, "", proffer.HandlerSelectionDecisionSignalName, decision); err != nil {
		return fmt.Errorf("temporal: signal handler selection decision: %w", err)
	}
	return nil
}

// Preview queries a run's current proffer.PreviewState.
func (s *temporalStarter) Preview(ctx context.Context, workflowID string) (proffer.PreviewState, error) {
	if strings.TrimSpace(workflowID) == "" {
		return proffer.PreviewState{}, errors.New("temporal: workflow_id is required to query preview state")
	}
	value, err := s.client.QueryWorkflow(ctx, workflowID, "", proffer.PreviewQueryName)
	if err != nil {
		return proffer.PreviewState{}, fmt.Errorf("temporal: query preview state: %w", err)
	}
	var state proffer.PreviewState
	if err := value.Get(&state); err != nil {
		return proffer.PreviewState{}, fmt.Errorf("temporal: decode preview state: %w", err)
	}
	return state, nil
}
