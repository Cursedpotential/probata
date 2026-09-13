package proffer

import (
	"testing"

	"github.com/Cursedpotential/probata/engine/stagegraph"
)

func TestEveryStageHasExplicitBoundedOptions(t *testing.T) {
	allStages := append([]stagegraph.Descriptor(nil), stagegraph.Stages...)
	allStages = append(allStages, stagegraph.OptionalStages...)
	for _, d := range allStages {
		opts, ok := stageOptions[d.ID]
		if !ok {
			t.Fatalf("stage %q has no ActivityOptions entry", d.ID)
		}
		if opts.StartToCloseTimeout <= 0 {
			t.Errorf("stage %q has non-positive StartToCloseTimeout %v", d.ID, opts.StartToCloseTimeout)
		}
		if opts.RetryPolicy == nil {
			t.Fatalf("stage %q has no RetryPolicy", d.ID)
		}
		if opts.RetryPolicy.MaximumAttempts <= 0 {
			t.Errorf("stage %q has MaximumAttempts=%d; 0 means unlimited retries, which is not bounded", d.ID, opts.RetryPolicy.MaximumAttempts)
		}
	}

	if len(stageOptions) != len(allStages) {
		t.Errorf("stageOptions has %d entries, want exactly %d (one per base or optional stage, no strays)", len(stageOptions), len(allStages))
	}
}
