package proposal

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

type fakeInspector struct {
	tables []string
	counts map[string]int64
	err    error
}

type fakeSchemaExecutor struct {
	sql string
	err error
}

func (f *fakeSchemaExecutor) Exec(_ context.Context, sql string) error {
	f.sql = sql
	return f.err
}

func (f fakeInspector) TableNames(context.Context) ([]string, error) {
	return f.tables, f.err
}

func (f fakeInspector) RowCount(_ context.Context, table string) (int64, error) {
	return f.counts[table], f.err
}

type fakeWriter struct {
	created bool
	payload []byte
	digest  string
	err     error
}

func (f *fakeWriter) CreateFrozen(_ context.Context, payload []byte, digest string, _ time.Time) error {
	if f.created {
		return ErrFrozenArtifactExists
	}
	if f.err != nil {
		return f.err
	}
	f.created = true
	f.payload = payload
	f.digest = digest
	return nil
}

func frozenManifest(t *testing.T) Manifest {
	t.Helper()
	frozen, err := Freeze(testManifest())
	require.NoError(t, err)
	return frozen
}

func completeInspector(t *testing.T, manifest Manifest) fakeInspector {
	t.Helper()
	counts, err := ExpectedRowCounts(manifest)
	require.NoError(t, err)
	return fakeInspector{tables: append([]string(nil), RequiredTables...), counts: counts}
}

func TestDuckDBSchemaDeclaresEveryRequiredRelation(t *testing.T) {
	require.ElementsMatch(t, []string{
		"proposal_control",
		"proposed_source_records",
		"proposed_records",
		"proposed_metadata",
		"proposed_attachments",
		"proposed_entity_mentions",
		"proposed_entities",
		"proposed_relationships",
		"proposed_temporal_expressions",
		"proposed_chunks",
		"proposed_lineage",
		"proposed_warnings",
		"proposed_sink_operations",
		"tool_receipts",
	}, RequiredTables)
	for _, table := range RequiredTables {
		require.Contains(t, DuckDBSchema, "CREATE TABLE "+table+" (")
	}
	require.Contains(t, DuckDBSchema, "CREATE TABLE proposal_control")
	require.Contains(t, DuckDBSchema, "matter_id VARCHAR NOT NULL")
	require.Contains(t, DuckDBSchema, "court_case_id VARCHAR NOT NULL")
	require.Contains(t, DuckDBSchema, "proposal_digest VARCHAR")
	require.NotContains(t, DuckDBSchema, "database_byte_digest")
	require.NotContains(t, DuckDBSchema, "bundle_digest")
	require.NotContains(t, DuckDBSchema, "postgres_payload")
	require.NotContains(t, DuckDBSchema, "CREATE TABLE surreal")
}

func TestInitializeArtifactAppliesVersionedSchemaThroughNarrowExecutor(t *testing.T) {
	executor := &fakeSchemaExecutor{}
	require.NoError(t, InitializeArtifact(context.Background(), executor))
	require.Equal(t, DuckDBSchema, executor.sql)

	executor.err = errors.New("duckdb unavailable")
	require.EqualError(
		t,
		InitializeArtifact(context.Background(), executor),
		"initialize proposal artifact schema: duckdb unavailable",
	)
}

func TestValidateArtifactChecksEveryRequiredTableAndCount(t *testing.T) {
	frozen := frozenManifest(t)
	inspector := completeInspector(t, frozen)

	report, err := ValidateArtifact(context.Background(), inspector, frozen)
	require.NoError(t, err)
	require.Len(t, report.Tables, len(RequiredTables))
}

func TestValidateArtifactRejectsMissingTable(t *testing.T) {
	frozen := frozenManifest(t)
	inspector := completeInspector(t, frozen)
	inspector.tables = inspector.tables[:len(inspector.tables)-1]

	_, err := ValidateArtifact(context.Background(), inspector, frozen)
	require.EqualError(t, err, `required proposal table "tool_receipts" is missing`)
}

func TestValidateArtifactRejectsRowCountDrift(t *testing.T) {
	frozen := frozenManifest(t)
	inspector := completeInspector(t, frozen)
	inspector.counts["proposed_chunks"]++

	_, err := ValidateArtifact(context.Background(), inspector, frozen)
	require.EqualError(t, err, `proposal table "proposed_chunks" row count is 18, expected 17`)
}

func TestExpectedDestinationRowsCoverSelectedAndUnselectedPreviewOperations(t *testing.T) {
	manifest := testManifest()
	manifest.Destinations = append(manifest.Destinations, DestinationPlan{
		Destination:    DestinationPostgresControl,
		Selected:       false,
		OperationCount: 99,
	})
	manifest.Counts.SinkOperations = 135
	for index := range manifest.TableDigests {
		if manifest.TableDigests[index].Table == "proposed_sink_operations" {
			manifest.TableDigests[index].Rows = 135
		}
	}
	frozen, err := Freeze(manifest)
	require.NoError(t, err)

	counts, err := ExpectedRowCounts(frozen)
	require.NoError(t, err)
	require.EqualValues(t, 135, counts["proposed_sink_operations"])
	require.EqualValues(t, 1, counts["proposal_control"])
}

func TestLegalStateTransitions(t *testing.T) {
	legal := [][2]State{
		{StateBuilding, StateFrozen},
		{StateFrozen, StateApproved},
		{StateApproved, StateCommitting},
		{StateCommitting, StateCommitted},
		{StateCommitted, StateSuperseded},
	}
	for _, transition := range legal {
		require.NoError(t, ValidateTransition(transition[0], transition[1]))
	}
	for _, transition := range [][2]State{
		{StateBuilding, StateApproved},
		{StateApproved, StateFrozen},
		{StateFailed, StateBuilding},
		{StateCommitted, StateCommitting},
	} {
		require.Error(t, ValidateTransition(transition[0], transition[1]))
	}
}

func TestFreezeOnceRefusesExistingArtifact(t *testing.T) {
	existing := frozenManifest(t)
	_, err := FreezeOnce(&existing, testManifest())
	require.ErrorIs(t, err, ErrFrozenArtifactExists)
}

func TestPersistFrozenUsesAtomicCreateAndRefusesOverwrite(t *testing.T) {
	frozen := frozenManifest(t)
	writer := &fakeWriter{}

	require.NoError(t, PersistFrozen(context.Background(), writer, frozen, time.Now()))
	require.Equal(t, frozen.ProposalDigest, writer.digest)
	require.True(t, strings.Contains(string(writer.payload), frozen.ProposalDigest))
	require.ErrorIs(t, PersistFrozen(context.Background(), writer, frozen, time.Now()), ErrFrozenArtifactExists)
}

func TestPersistFrozenRejectsNonFrozenOrWriterFailure(t *testing.T) {
	writer := &fakeWriter{}
	require.EqualError(
		t,
		PersistFrozen(context.Background(), writer, testManifest(), time.Now()),
		`only state "frozen" may be persisted as a frozen artifact`,
	)

	frozen := frozenManifest(t)
	writer.err = errors.New("disk unavailable")
	require.EqualError(
		t,
		PersistFrozen(context.Background(), writer, frozen, time.Now()),
		"persist frozen proposal: disk unavailable",
	)
}
