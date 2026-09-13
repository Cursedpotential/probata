package profferworker

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"go.temporal.io/sdk/activity"

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
	RegisterAll(recorder, Registrations{})
	if recorder.workflowCount != 1 {
		t.Fatalf("workflow registration count = %d, want 1", recorder.workflowCount)
	}
	const replayAliasCount = 3
	const genericFlowActivityCount = 1
	if len(recorder.names) != len(stagegraph.Stages)+replayAliasCount+genericFlowActivityCount || len(stagegraph.Stages) != 26 {
		t.Fatalf("activity registration count = %d, want 26 canonical + 3 replay aliases + 1 generic n8n flow", len(recorder.names))
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
	if registered["run_n8n_flow_activity"] != 1 {
		t.Errorf("generic n8n flow activity registered %d times", registered["run_n8n_flow_activity"])
	}
	for name, count := range registered {
		if count != 1 {
			t.Errorf("activity name %q registered %d times", name, count)
		}
	}
}

func TestLoadConfiguredFlowBindingsAllowsNoExtraFlows(t *testing.T) {
	registry, err := loadConfiguredFlowBindings("")
	if err != nil {
		t.Fatalf("loadConfiguredFlowBindings() error = %v", err)
	}
	if registry.Count() != 0 {
		t.Fatalf("binding count = %d, want 0", registry.Count())
	}
}

func TestLoadConfiguredFlowBindingsFailsClosedWhenConfiguredFileIsMissing(t *testing.T) {
	path := filepath.Join(t.TempDir(), "missing.json")
	_, err := loadConfiguredFlowBindings(path)
	if err == nil || !strings.Contains(err.Error(), "configured but unavailable") {
		t.Fatalf("loadConfiguredFlowBindings() error = %v, want unavailable file rejection", err)
	}
}

func TestLoadConfiguredFlowBindingsValidatesConfiguredFile(t *testing.T) {
	path := filepath.Join(t.TempDir(), "bindings.json")
	if err := os.WriteFile(path, []byte(`{"bindings":[{"name":"ocr_page","webhook_path":"proffer/ocr-page"}]}`), 0o600); err != nil {
		t.Fatal(err)
	}
	registry, err := loadConfiguredFlowBindings(path)
	if err != nil {
		t.Fatalf("loadConfiguredFlowBindings() error = %v", err)
	}
	if registry.Count() != 1 {
		t.Fatalf("binding count = %d, want 1", registry.Count())
	}

	if err := os.WriteFile(path, []byte(`{"bindings":[{"name":"bad/name","webhook_path":"proffer/ocr-page"}]}`), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := loadConfiguredFlowBindings(path); err == nil || !strings.Contains(err.Error(), "invalid N8N_FLOW_BINDINGS_FILE") {
		t.Fatalf("loadConfiguredFlowBindings() error = %v, want invalid binding rejection", err)
	}
}
