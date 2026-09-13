package proposal

import (
	"encoding/json"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

func testManifest() Manifest {
	digest := strings.Repeat("a", 64)
	manifest := Manifest{
		SchemaVersion: SchemaVersion,
		OperationID:   "operation-1",
		AttemptID:     "attempt-2",
		Mode:          "TEST",
		MatterID:      "matter-3",
		CourtCaseID:   "court-case-4",
		CreatedAt:     time.Date(2026, 9, 13, 12, 30, 0, 0, time.FixedZone("EDT", -4*60*60)),
		State:         StateBuilding,
		SourcePackage: SourcePackage{Locator: "r2://sources/package.zip", Digest: digest},
		ConfigDigest:  digest,
		Counts: Counts{
			SourceRecords:       69,
			Records:             69,
			Metadata:            12,
			Attachments:         3,
			EntityMentions:      14,
			Entities:            11,
			Relationships:       8,
			TemporalExpressions: 6,
			Chunks:              17,
			Lineage:             44,
			Warnings:            1,
			SinkOperations:      36,
		},
		ToolReceipts: []ToolReceipt{
			{Stage: "chunk", ToolID: "duckdb.chunk", ToolVersion: "1", ConfigDigest: digest, InputDigest: digest, OutputDigest: strings.Repeat("d", 64)},
			{Stage: "extract", ToolID: "duckdb.xlsx", ToolVersion: "1", ConfigDigest: digest, InputDigest: digest, OutputDigest: strings.Repeat("e", 64)},
		},
		Destinations: []DestinationPlan{
			{Destination: DestinationNeo4jGraph, Selected: true, OperationCount: 19, SnapshotDigest: strings.Repeat("f", 64)},
			{Destination: DestinationWeaviateContext, Selected: true, OperationCount: 17, SnapshotDigest: digest},
		},
	}
	for _, table := range LogicalContentTables {
		manifest.TableDigests = append(manifest.TableDigests, TableDigest{
			Table: table, Algorithm: TableDigestAlgorithm, Rows: manifest.logicalRowCounts()[table], Digest: digest,
		})
	}
	return manifest
}

func TestFreezeIsDeterministicAcrossInputOrdering(t *testing.T) {
	firstInput := testManifest()
	secondInput := testManifest()
	secondInput.TableDigests[0], secondInput.TableDigests[1] = secondInput.TableDigests[1], secondInput.TableDigests[0]
	secondInput.ToolReceipts[0], secondInput.ToolReceipts[1] = secondInput.ToolReceipts[1], secondInput.ToolReceipts[0]
	secondInput.Destinations[0], secondInput.Destinations[1] = secondInput.Destinations[1], secondInput.Destinations[0]

	first, err := Freeze(firstInput)
	require.NoError(t, err)
	second, err := Freeze(secondInput)
	require.NoError(t, err)

	require.Equal(t, first.ProposalDigest, second.ProposalDigest)
	require.Equal(t, StateFrozen, first.State)
	require.NoError(t, first.VerifyFrozen())
}

func TestFrozenDigestDetectsMutation(t *testing.T) {
	frozen, err := Freeze(testManifest())
	require.NoError(t, err)

	frozen.TableDigests[0].Digest = strings.Repeat("9", 64)
	require.EqualError(t, frozen.VerifyFrozen(), "proposal digest does not match the frozen manifest")
}

func TestLogicalDigestBindsSourceConfigTablesAndDestinationPlan(t *testing.T) {
	baseline, err := Freeze(testManifest())
	require.NoError(t, err)

	mutations := map[string]func(*Manifest){
		"source": func(m *Manifest) { m.SourcePackage.Digest = strings.Repeat("1", 64) },
		"config": func(m *Manifest) { m.ConfigDigest = strings.Repeat("2", 64) },
		"table":  func(m *Manifest) { m.TableDigests[0].Digest = strings.Repeat("3", 64) },
		"destination": func(m *Manifest) {
			m.Destinations[0].Selected = !m.Destinations[0].Selected
		},
	}
	for name, mutate := range mutations {
		t.Run(name, func(t *testing.T) {
			changed := testManifest()
			mutate(&changed)
			frozen, freezeErr := Freeze(changed)
			require.NoError(t, freezeErr)
			require.NotEqual(t, baseline.ProposalDigest, frozen.ProposalDigest)
		})
	}
}

func TestFreezeRequiresEveryLogicalTableDigest(t *testing.T) {
	manifest := testManifest()
	manifest.TableDigests = manifest.TableDigests[:len(manifest.TableDigests)-1]

	_, err := Freeze(manifest)
	require.EqualError(t, err, `logical table digest "tool_receipts" is required`)
}

func TestFreezeRequiresVersionedTableDigestAlgorithm(t *testing.T) {
	manifest := testManifest()
	manifest.TableDigests[0].Algorithm = "unversioned-json"

	_, err := Freeze(manifest)
	require.EqualError(
		t,
		err,
		`logical table digest "proposed_source_records" must use algorithm "proffer-table-json-v1"`,
	)
}

func TestFreezeRejectsNegativeRelationCount(t *testing.T) {
	manifest := testManifest()
	manifest.Counts.EntityMentions = -1

	_, err := Freeze(manifest)
	require.EqualError(t, err, `proposal count "entity_mentions" must not be negative`)
}

func TestSurrealCannotBeAutomaticDestination(t *testing.T) {
	manifest := testManifest()
	manifest.Destinations = append(manifest.Destinations, DestinationPlan{
		Destination: DestinationSurrealDBManual,
		Selected:    true,
	})

	_, err := Freeze(manifest)
	require.EqualError(t, err, "destination \"surrealdb_manual_projection\" is not an automatic Context destination")
}

func TestApprovalBindsExactAttemptAndDigest(t *testing.T) {
	frozen, err := Freeze(testManifest())
	require.NoError(t, err)

	approval := ApprovalBinding{
		OperationID:    frozen.OperationID,
		AttemptID:      frozen.AttemptID,
		ProposalDigest: frozen.ProposalDigest,
		ActorSubject:   "owner-subject",
		ApprovedAt:     time.Now(),
	}
	require.NoError(t, approval.ValidateFor(frozen))

	approval.ProposalDigest = strings.Repeat("0", 64)
	require.EqualError(t, approval.ValidateFor(frozen), "approval digest does not match proposal")
}

func TestApprovalRequiresExactlyFrozenState(t *testing.T) {
	frozen, err := Freeze(testManifest())
	require.NoError(t, err)
	approval := ApprovalBinding{
		OperationID:    frozen.OperationID,
		AttemptID:      frozen.AttemptID,
		ProposalDigest: frozen.ProposalDigest,
		ActorSubject:   "owner-subject",
		ApprovedAt:     time.Now(),
	}

	frozen.State = StateApproved
	require.EqualError(t, approval.ValidateFor(frozen), `approval requires proposal state "frozen", got "approved"`)
}

func TestManualSurrealProjectionRequiresSeparateScopeDigest(t *testing.T) {
	request := ManualSurrealProjection{
		OperationID:             "operation-1",
		AttemptID:               "attempt-2",
		CommittedProposalDigest: strings.Repeat("a", 64),
		ScopeDigest:             strings.Repeat("b", 64),
		ActorSubject:            "owner-subject",
		RequestedAt:             time.Now(),
	}
	require.NoError(t, request.Validate())

	request.ScopeDigest = ""
	require.EqualError(t, request.Validate(), "committed proposal and projection scope require SHA-256 digests")
}

func TestBundleEnvelopeSeparatesFinalDatabaseByteDigest(t *testing.T) {
	frozen, err := Freeze(testManifest())
	require.NoError(t, err)
	buildingEnvelope := BundleEnvelope{
		SchemaVersion:      SchemaVersion,
		OperationID:        frozen.OperationID,
		AttemptID:          frozen.AttemptID,
		ProposalDigest:     frozen.ProposalDigest,
		DatabaseLocator:    "file:///proposal/attempt-2.duckdb",
		DatabaseByteDigest: strings.Repeat("f", 64),
		DatabaseBytes:      8192,
		FinalizedAt:        time.Now(),
	}
	envelope, err := FinalizeBundle(frozen, buildingEnvelope)
	require.NoError(t, err)
	require.NoError(t, envelope.ValidateFor(frozen))

	originalLogicalDigest := frozen.ProposalDigest
	secondBuilding := buildingEnvelope
	secondBuilding.DatabaseByteDigest = strings.Repeat("e", 64)
	secondEnvelope, err := FinalizeBundle(frozen, secondBuilding)
	require.NoError(t, err)
	require.NotEqual(t, envelope.BundleDigest, secondEnvelope.BundleDigest)
	require.Equal(t, originalLogicalDigest, frozen.ProposalDigest)
}

func TestApprovalBindsBundleWhenFinalizedEnvelopeExists(t *testing.T) {
	frozen, err := Freeze(testManifest())
	require.NoError(t, err)
	envelope, err := FinalizeBundle(frozen, BundleEnvelope{
		SchemaVersion:      SchemaVersion,
		OperationID:        frozen.OperationID,
		AttemptID:          frozen.AttemptID,
		ProposalDigest:     frozen.ProposalDigest,
		DatabaseLocator:    "file:///proposal/attempt-2.duckdb",
		DatabaseByteDigest: strings.Repeat("f", 64),
		DatabaseBytes:      8192,
		FinalizedAt:        time.Now(),
	})
	require.NoError(t, err)
	approval := ApprovalBinding{
		OperationID:    frozen.OperationID,
		AttemptID:      frozen.AttemptID,
		ProposalDigest: frozen.ProposalDigest,
		BundleDigest:   envelope.BundleDigest,
		ActorSubject:   "owner-subject",
		ApprovedAt:     time.Now(),
	}

	require.NoError(t, approval.ValidateForBundle(frozen, &envelope))
	require.EqualError(t, approval.ValidateFor(frozen), "bundle-bound approval requires ValidateForBundle")
	approval.BundleDigest = strings.Repeat("0", 64)
	require.EqualError(t, approval.ValidateForBundle(frozen, &envelope), "approval bundle digest does not match finalized bundle")
}

func TestLogicalManifestCannotContainPhysicalDatabaseDigest(t *testing.T) {
	manifest := testManifest()
	payload, err := json.Marshal(manifest)
	require.NoError(t, err)
	require.NotContains(t, string(payload), "database_byte_digest")
	require.NotContains(t, string(payload), "database_bytes")
}
