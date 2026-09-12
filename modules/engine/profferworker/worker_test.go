package profferworker

import (
	"context"
	"testing"

	"go.temporal.io/sdk/activity"

	"github.com/Cursedpotential/probata/engine/activities"
	"github.com/Cursedpotential/probata/engine/proffer"
	"github.com/Cursedpotential/probata/engine/stagegraph"
)

type registrationRecorder struct {
	workflowCount int
	names         []string
}

func (r *registrationRecorder) RegisterWorkflow(interface{}) { r.workflowCount++ }

func (r *registrationRecorder) RegisterActivityWithOptions(_ interface{}, options activity.RegisterOptions) {
	r.names = append(r.names, options.Name)
}

func TestRegisterAllRegistersCanonicalStagesAndReplayAliasesExactlyOnce(t *testing.T) {
	recorder := &registrationRecorder{}
	RegisterAll(recorder, Registrations{HandlerSelection: HandlerSelectionActivities{
		Recommend: func(context.Context, proffer.StageRequest) (proffer.HandlerRecommendationResult, error) {
			return proffer.HandlerRecommendationResult{}, nil
		},
		Validate: func(context.Context, proffer.StageRequest) (proffer.HandlerSelectionValidationResult, error) {
			return proffer.HandlerSelectionValidationResult{}, nil
		},
	}})
	if recorder.workflowCount != 1 {
		t.Fatalf("workflow registration count = %d, want 1", recorder.workflowCount)
	}
	const replayAliasCount = 3
	const standaloneActivityCount = 4
	if len(recorder.names) != len(stagegraph.Stages)+replayAliasCount+standaloneActivityCount || len(stagegraph.Stages) != 26 {
		t.Fatalf("activity registration count = %d, want 26 canonical + 3 replay aliases + 4 standalone activities", len(recorder.names))
	}
	registered := make(map[string]int, len(recorder.names))
	for _, name := range recorder.names {
		registered[name]++
	}
	for _, descriptor := range stagegraph.Stages {
		if registered[string(descriptor.ID)] != 1 {
			t.Errorf("canonical stage %q registered %d times", descriptor.ID, registered[string(descriptor.ID)])
		}
	}
	for _, alias := range []string{"hash_source_activity", "hash_raw_records_activity", "hash_raw_generation_activity"} {
		if registered[alias] != 1 {
			t.Errorf("replay alias %q registered %d times", alias, registered[alias])
		}
	}
	if registered[activities.ExecuteStructuredELTActivityName] != 1 {
		t.Errorf("standalone structured ELT activity %q registered %d times", activities.ExecuteStructuredELTActivityName, registered[activities.ExecuteStructuredELTActivityName])
	}
	if registered[activities.SelectStructuredELTActivityName] != 1 {
		t.Errorf("standalone structured ELT activity %q registered %d times", activities.SelectStructuredELTActivityName, registered[activities.SelectStructuredELTActivityName])
	}
	if registered[proffer.RecommendHandlerActivityName] != 1 || registered[proffer.ValidateHandlerSelectionActivityName] != 1 {
		t.Errorf("handler recommendation/validation activities were not registered exactly once: %#v", registered)
	}
	for name, count := range registered {
		if count != 1 {
			t.Errorf("activity name %q registered %d times", name, count)
		}
	}
}
