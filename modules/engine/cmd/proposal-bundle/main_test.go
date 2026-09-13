package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/Cursedpotential/probata/engine/proposal"
	"github.com/stretchr/testify/require"
)

func TestFreezeBundleVerifyAndTamperDetection(t *testing.T) {
	root := t.TempDir()
	buildingPath := filepath.Join(root, "building-manifest.json")
	frozenPath := filepath.Join(root, "logical-manifest.json")
	databasePath := filepath.Join(root, "proposal.duckdb")
	artifactPath := filepath.Join(root, "source-package.json")
	bundlePath := filepath.Join(root, "bundle-manifest.json")

	building := commandTestManifest()
	payload, err := json.Marshal(building)
	require.NoError(t, err)
	require.NoError(t, os.WriteFile(buildingPath, payload, 0o600))
	require.NoError(t, os.WriteFile(databasePath, []byte("closed-duckdb-bytes"), 0o600))
	require.NoError(t, os.WriteFile(artifactPath, []byte(`{"source":"retained"}`), 0o600))

	require.NoError(t, freeze([]string{"--input", buildingPath, "--output", frozenPath}))
	require.Error(t, freeze([]string{"--input", buildingPath, "--output", frozenPath}), "freeze output is create-only")
	require.NoError(t, bundle([]string{
		"--manifest", frozenPath,
		"--database", databasePath,
		"--artifact", "source-package=" + artifactPath,
		"--output", bundlePath,
	}))
	require.NoError(t, verify([]string{"--manifest", frozenPath, "--bundle", bundlePath}))

	require.NoError(t, os.WriteFile(databasePath, []byte("changed-duckdb-bytes"), 0o600))
	require.EqualError(
		t,
		verify([]string{"--manifest", frozenPath, "--bundle", bundlePath}),
		"proposal database bytes do not match finalized bundle",
	)
}

func commandTestManifest() proposal.Manifest {
	digest := strings.Repeat("a", 64)
	counts := proposal.Counts{SinkOperations: 1}
	rows := map[string]int64{
		"proposed_sink_operations": 1,
		"tool_receipts":            1,
	}
	tableDigests := make([]proposal.TableDigest, 0, len(proposal.LogicalContentTables))
	for _, table := range proposal.LogicalContentTables {
		tableDigests = append(tableDigests, proposal.TableDigest{
			Table: table, Algorithm: proposal.TableDigestAlgorithm, Rows: rows[table], Digest: digest,
		})
	}
	return proposal.Manifest{
		SchemaVersion: proposal.SchemaVersion,
		OperationID:   "operation-command-test",
		AttemptID:     "attempt-command-test",
		Mode:          "TEST",
		MatterID:      "deadbeef-dead-beef-dead-beefdeadbeef",
		CourtCaseID:   "cafebabe-cafe-babe-cafe-babecafebabe",
		CreatedAt:     time.Date(2026, 9, 13, 6, 0, 0, 0, time.UTC),
		State:         proposal.StateBuilding,
		SourcePackage: proposal.SourcePackage{Locator: "r2://test/source.zip", Digest: digest},
		ConfigDigest:  digest,
		TableDigests:  tableDigests,
		Counts:        counts,
		ToolReceipts: []proposal.ToolReceipt{{
			Stage: "extract", ToolID: "duckdb.read_xlsx", ToolVersion: "1.5.5",
			ConfigDigest: digest, InputDigest: digest, OutputDigest: digest,
		}},
		Destinations: []proposal.DestinationPlan{{
			Destination: proposal.DestinationPostgresControl, Selected: false, OperationCount: 1,
		}},
	}
}
