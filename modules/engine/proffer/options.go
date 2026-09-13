package proffer

import (
	"time"

	"go.temporal.io/sdk/temporal"
	"go.temporal.io/sdk/workflow"

	"github.com/Cursedpotential/probata/engine/stagegraph"
)

// retryPolicy builds a bounded RetryPolicy. MaximumAttempts must always be
// set explicitly and non-zero: the Temporal SDK treats 0 as "unlimited
// attempts", which would violate the "bounded retries" requirement for
// every atomic stage.
func retryPolicy(initialInterval time.Duration, maxAttempts int32) *temporal.RetryPolicy {
	return &temporal.RetryPolicy{
		InitialInterval:    initialInterval,
		BackoffCoefficient: 2.0,
		MaximumInterval:    initialInterval * 20,
		MaximumAttempts:    maxAttempts,
	}
}

// stageOptions gives every atomic stage in stagegraph.Stages its own
// explicit ActivityOptions: a StartToCloseTimeout and RetryPolicy sized to
// what that stage actually does, per the boundary document's requirement
// that every Activity have "one retry policy" of its own. Stages that walk
// or hash large containers/records also carry a HeartbeatTimeout so
// long-running work is detectably alive rather than silently stuck (section
// 2: "long-running work reports heartbeats").
//
// TestEveryStageHasExplicitOptions in options_test.go proves this map has
// exactly one entry per registered stage — no stage silently falls back to
// a shared default.
var stageOptions = map[stagegraph.StageID]workflow.ActivityOptions{
	// Identity/bookkeeping stages: quick PostgreSQL operations, tight
	// timeout, generous retries since they are cheap to retry.
	stagegraph.RegisterSource: {
		StartToCloseTimeout: 30 * time.Second,
		RetryPolicy:         retryPolicy(time.Second, 5),
	},

	// Byte-moving/scanning stages over the original source: can be large,
	// so they get long timeouts and heartbeats.
	stagegraph.RetainOriginal: {
		StartToCloseTimeout: 30 * time.Minute,
		HeartbeatTimeout:    time.Minute,
		RetryPolicy:         retryPolicy(5*time.Second, 5),
	},
	stagegraph.AssessSourceRepair: {
		StartToCloseTimeout: 10 * time.Minute,
		RetryPolicy:         retryPolicy(5*time.Second, 3),
	},
	stagegraph.ResolveSourceRepair: {
		StartToCloseTimeout: 30 * time.Minute,
		HeartbeatTimeout:    time.Minute,
		RetryPolicy:         retryPolicy(5*time.Second, 3),
	},
	stagegraph.CaptureFilesystemMetadata: {
		StartToCloseTimeout: 2 * time.Minute,
		RetryPolicy:         retryPolicy(time.Second, 5),
	},
	stagegraph.FingerprintSource: {
		StartToCloseTimeout: 30 * time.Minute,
		HeartbeatTimeout:    time.Minute,
		RetryPolicy:         retryPolicy(5*time.Second, 5),
	},
	stagegraph.InventoryContainer: {
		StartToCloseTimeout: 15 * time.Minute,
		HeartbeatTimeout:    time.Minute,
		RetryPolicy:         retryPolicy(5*time.Second, 5),
	},
	stagegraph.ExtractEmbeddedMetadata: {
		// Shells out to specialist tools (ExifTool, ffmpeg, ...); bounded
		// but generous, and fewer retries since a tool crash is often
		// deterministic.
		StartToCloseTimeout: 10 * time.Minute,
		HeartbeatTimeout:    time.Minute,
		RetryPolicy:         retryPolicy(5*time.Second, 3),
	},

	// Parser selection/execution.
	stagegraph.SelectParser: {
		StartToCloseTimeout: 30 * time.Second,
		RetryPolicy:         retryPolicy(time.Second, 3),
	},
	stagegraph.ExecuteParser: {
		// Parsing can be slow on large sources; failures are usually
		// deterministic (a bad record), so retries stay low to avoid
		// re-running expensive, likely-futile work.
		StartToCloseTimeout: 30 * time.Minute,
		HeartbeatTimeout:    time.Minute,
		RetryPolicy:         retryPolicy(5*time.Second, 3),
	},

	// Raw persistence and verification.
	stagegraph.PersistRawGeneration: {
		StartToCloseTimeout: 5 * time.Minute,
		RetryPolicy:         retryPolicy(2*time.Second, 5),
	},
	stagegraph.FingerprintRawRecords: {
		StartToCloseTimeout: 30 * time.Minute,
		HeartbeatTimeout:    time.Minute,
		RetryPolicy:         retryPolicy(5*time.Second, 5),
	},
	stagegraph.FingerprintRawGeneration: {
		// Folds already-computed context raw-record fingerprints (cheap,
		// sequential SHA-256 over short strings) rather than walking source
		// bytes, so this mirrors hash_normalized_generation's short timeout,
		// not fingerprint_raw_records' heartbeat-bearing one.
		StartToCloseTimeout: 5 * time.Minute,
		RetryPolicy:         retryPolicy(2*time.Second, 5),
	},
	stagegraph.ReconcileRecordAccounting: {
		StartToCloseTimeout: 5 * time.Minute,
		RetryPolicy:         retryPolicy(2*time.Second, 5),
	},
	stagegraph.ReconcileByteCoverage: {
		StartToCloseTimeout: 5 * time.Minute,
		RetryPolicy:         retryPolicy(2*time.Second, 5),
	},
	stagegraph.VerifyRawCoverageAgainstSource: {
		StartToCloseTimeout: 10 * time.Minute,
		RetryPolicy:         retryPolicy(2*time.Second, 5),
	},

	// Normalization and its persistence.
	stagegraph.NormalizeGeneration: {
		StartToCloseTimeout: 15 * time.Minute,
		HeartbeatTimeout:    time.Minute,
		RetryPolicy:         retryPolicy(5*time.Second, 3),
	},
	stagegraph.PersistNormalizedGeneration: {
		StartToCloseTimeout: 5 * time.Minute,
		RetryPolicy:         retryPolicy(2*time.Second, 5),
	},

	// Lineage branch.
	stagegraph.PersistLineage: {
		StartToCloseTimeout: 10 * time.Minute,
		RetryPolicy:         retryPolicy(2*time.Second, 5),
	},
	stagegraph.ValidateRawLineage: {
		StartToCloseTimeout: 5 * time.Minute,
		RetryPolicy:         retryPolicy(2*time.Second, 5),
	},

	// Normalized-digest hash branch — not H2/H3; those names belong solely
	// to the raw-custody hashes above (vendored/sbv/CUSTODY.md).
	stagegraph.HashNormalizedRecords: {
		StartToCloseTimeout: 15 * time.Minute,
		HeartbeatTimeout:    time.Minute,
		RetryPolicy:         retryPolicy(5*time.Second, 5),
	},
	stagegraph.HashNormalizedGeneration: {
		StartToCloseTimeout: 5 * time.Minute,
		RetryPolicy:         retryPolicy(2*time.Second, 5),
	},

	// Verification join, seal, publish.
	stagegraph.VerifyNormalizedGeneration: {
		StartToCloseTimeout: 5 * time.Minute,
		RetryPolicy:         retryPolicy(2*time.Second, 5),
	},
	stagegraph.ChunkDocument: {
		// The non-messaging chunker reads one retained representation and
		// persists one sealed generation. Its writes are idempotent by package,
		// extraction attempt, source representation, and policy. Content errors
		// are generally deterministic, so retries remain deliberately low.
		StartToCloseTimeout: 30 * time.Minute,
		RetryPolicy:         retryPolicy(5*time.Second, 3),
	},
	stagegraph.PublishPreview: {
		StartToCloseTimeout: 5 * time.Minute,
		RetryPolicy:         retryPolicy(2*time.Second, 5),
	},
	stagegraph.SealGeneration: {
		// Sealing atomically freezes the generation; keep it short and
		// retry-bounded so a stuck seal fails the workflow instead of
		// hanging it.
		StartToCloseTimeout: 2 * time.Minute,
		RetryPolicy:         retryPolicy(2*time.Second, 5),
	},
	stagegraph.PublishGeneration: {
		// The outbox publish is idempotent by design, so it gets more
		// attempts than most stages — but still a bounded number, never
		// unlimited.
		StartToCloseTimeout: 2 * time.Minute,
		RetryPolicy:         retryPolicy(2*time.Second, 10),
	},
}

// optionsFor returns the explicit ActivityOptions for id. It panics on an
// unknown stage id: every base or optional stage must have an entry in
// stageOptions, and TestEveryStageHasExplicitBoundedOptions proves that statically
// so this path is unreachable in a correctly built binary.
func optionsFor(id stagegraph.StageID) workflow.ActivityOptions {
	switch string(id) {
	case legacyHashSourceActivity:
		id = stagegraph.FingerprintSource
	case legacyHashRawRecordsActivity:
		id = stagegraph.FingerprintRawRecords
	case legacyHashRawGenerationActivity:
		id = stagegraph.FingerprintRawGeneration
	}
	opts, ok := stageOptions[id]
	if !ok {
		panic("proffer: no ActivityOptions registered for stage " + string(id))
	}
	return opts
}
