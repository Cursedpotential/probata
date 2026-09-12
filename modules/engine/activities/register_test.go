package activities

import (
	"testing"

	"go.temporal.io/sdk/activity"

	"github.com/Cursedpotential/probata/engine/stagegraph"
)

type recordingRegistrar struct{ names []string }

func (r *recordingRegistrar) RegisterActivityWithOptions(_ interface{}, options activity.RegisterOptions) {
	r.names = append(r.names, options.Name)
}

func TestRegisterHashActivitiesUsesExactCanonicalStageNames(t *testing.T) {
	registrar := &recordingRegistrar{}
	RegisterHashActivities(registrar, HashActivities{})
	want := []string{
		string(stagegraph.FingerprintSource),
		string(stagegraph.FingerprintRawRecords),
		string(stagegraph.FingerprintRawGeneration),
		legacyHashSourceActivity,
		legacyHashRawRecordsActivity,
		legacyHashRawGenerationActivity,
		string(stagegraph.HashNormalizedRecords),
		string(stagegraph.HashNormalizedGeneration),
	}
	if len(registrar.names) != len(want) {
		t.Fatalf("registered %d hash activities, want %d: %v", len(registrar.names), len(want), registrar.names)
	}
	for i := range want {
		if registrar.names[i] != want[i] {
			t.Errorf("registration %d = %q, want %q", i, registrar.names[i], want[i])
		}
	}
}

func TestRegisterParserActivitiesUsesExactCanonicalStageNames(t *testing.T) {
	registrar := &recordingRegistrar{}
	RegisterParserActivities(registrar, ParserActivities{})
	want := []string{string(stagegraph.SelectParser), string(stagegraph.ExecuteParser)}
	if len(registrar.names) != len(want) {
		t.Fatalf("registered %d parser activities, want %d: %v", len(registrar.names), len(want), registrar.names)
	}
	for i := range want {
		if registrar.names[i] != want[i] {
			t.Errorf("registration %d = %q, want %q", i, registrar.names[i], want[i])
		}
	}
}

func TestRegisterSourceLifecycleActivitiesUsesExactCanonicalStageNames(t *testing.T) {
	registrar := &recordingRegistrar{}
	RegisterSourceLifecycleActivities(registrar, SourceLifecycleActivities{})
	want := []string{string(stagegraph.RegisterSource), string(stagegraph.RetainOriginal)}
	if len(registrar.names) != len(want) {
		t.Fatalf("registered %d source lifecycle activities, want %d: %v", len(registrar.names), len(want), registrar.names)
	}
	for i := range want {
		if registrar.names[i] != want[i] {
			t.Errorf("registration %d = %q, want %q", i, registrar.names[i], want[i])
		}
	}
}

func TestRegisterSourceObservationActivitiesUsesExactCanonicalStageNames(t *testing.T) {
	registrar := &recordingRegistrar{}
	RegisterSourceObservationActivities(registrar, SourceObservationActivities{})
	want := []string{
		string(stagegraph.CaptureFilesystemMetadata),
		string(stagegraph.InventoryContainer),
		string(stagegraph.ExtractEmbeddedMetadata),
	}
	if len(registrar.names) != len(want) {
		t.Fatalf("registered %d source observation activities, want %d: %v", len(registrar.names), len(want), registrar.names)
	}
	for i := range want {
		if registrar.names[i] != want[i] {
			t.Errorf("registration %d = %q, want %q", i, registrar.names[i], want[i])
		}
	}
}

func TestSplitSourceObservationRegistrationsUseExactCanonicalStageNames(t *testing.T) {
	tests := []struct {
		name     string
		register func(ActivityRegistrar, SourceObservationActivities)
		want     stagegraph.StageID
	}{
		{name: "filesystem", register: RegisterFilesystemMetadataActivity, want: stagegraph.CaptureFilesystemMetadata},
		{name: "inventory", register: RegisterInventoryContainerActivity, want: stagegraph.InventoryContainer},
		{name: "embedded", register: RegisterEmbeddedMetadataActivity, want: stagegraph.ExtractEmbeddedMetadata},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			registrar := &recordingRegistrar{}
			test.register(registrar, SourceObservationActivities{})
			if len(registrar.names) != 1 || registrar.names[0] != string(test.want) {
				t.Fatalf("registered names = %v, want [%q]", registrar.names, test.want)
			}
		})
	}
}

func TestRegisterRawPipelineActivitiesUsesExactCanonicalStageNames(t *testing.T) {
	registrar := &recordingRegistrar{}
	RegisterRawPipelineActivities(registrar, RawPipelineActivities{})
	want := []string{
		string(stagegraph.PersistRawGeneration),
		string(stagegraph.ReconcileRecordAccounting),
		string(stagegraph.ReconcileByteCoverage),
		string(stagegraph.VerifyRawCoverageAgainstSource),
	}
	if len(registrar.names) != len(want) {
		t.Fatalf("registered %d raw pipeline activities, want %d: %v", len(registrar.names), len(want), registrar.names)
	}
	for i := range want {
		if registrar.names[i] != want[i] {
			t.Errorf("registration %d = %q, want %q", i, registrar.names[i], want[i])
		}
	}
}

func TestRegisterStructuredELTActivitiesUsesExactCanonicalName(t *testing.T) {
	registrar := &recordingRegistrar{}
	RegisterStructuredELTActivities(registrar, StructuredELTActivities{})
	want := []string{SelectStructuredELTActivityName, ExecuteStructuredELTActivityName}
	if len(registrar.names) != len(want) {
		t.Fatalf("registered %d structured elt activities, want %d: %v", len(registrar.names), len(want), registrar.names)
	}
	for i := range want {
		if registrar.names[i] != want[i] {
			t.Errorf("registration %d = %q, want %q", i, registrar.names[i], want[i])
		}
	}
}

func TestRegisterNormalizedPipelineActivitiesUsesExactCanonicalStageNames(t *testing.T) {
	registrar := &recordingRegistrar{}
	RegisterNormalizedPipelineActivities(registrar, NormalizedPipelineActivities{})
	want := []string{
		string(stagegraph.NormalizeGeneration),
		string(stagegraph.PersistNormalizedGeneration),
		string(stagegraph.PersistLineage),
		string(stagegraph.ValidateRawLineage),
		string(stagegraph.VerifyNormalizedGeneration),
		string(stagegraph.SealGeneration),
		string(stagegraph.PublishGeneration),
	}
	if len(registrar.names) != len(want) {
		t.Fatalf("registered %d normalized pipeline activities, want %d: %v", len(registrar.names), len(want), registrar.names)
	}
	for i := range want {
		if registrar.names[i] != want[i] {
			t.Errorf("registration %d = %q, want %q", i, registrar.names[i], want[i])
		}
	}
}
