// Byline: Claude Code · Sonnet 5 · 2026-09-02
package postgres

import (
	"context"
	"strings"
	"testing"

	"github.com/Cursedpotential/probata/engine/activities"
)

func validStructuredELTSpec() activities.StructuredELTSpec {
	return activities.StructuredELTSpec{
		RequestID:   "req-1",
		SourceID:    "8c8c2c9e-1c1a-4a1a-9b1a-1c1a4a1a9b1a",
		IngestRunID: "3d3d2c9e-1c1a-4a1a-9b1a-1c1a4a1a9b1a",
		SourceURL:   "https://example.invalid/data.csv",
		Format:      activities.StructuredELTFormatCSV,
	}
}

func TestNewStructuredELTRepositoryRequiresDB(t *testing.T) {
	if _, err := NewStructuredELTRepository(nil); err == nil {
		t.Fatal("expected error when db is nil")
	}
}

// testDB (defined in source_lifecycle_repository_test.go) only exercises
// constructor/validation paths and deliberately cannot start a transaction —
// see that file's comment. Real execution is covered by the live proof
// script (scripts/prove_elt_duckdb.py) and the integration gate, matching
// this package's established convention of not adding a second fake pgx
// implementation that could drift from PostgreSQL.

func TestStructuredELTRepositoryRejectsBadSourceIDBeforeOpeningTransaction(t *testing.T) {
	repo, err := NewStructuredELTRepository(testDB{})
	if err != nil {
		t.Fatal(err)
	}
	spec := validStructuredELTSpec()
	spec.SourceID = "not-a-uuid"
	_, err = repo.ExecuteStructuredELT(context.Background(), spec)
	if err == nil || !strings.Contains(err.Error(), "source_id") {
		t.Fatalf("expected a source_id validation error, got %v", err)
	}
}

func TestStructuredELTRepositoryRejectsBadIngestRunIDBeforeOpeningTransaction(t *testing.T) {
	repo, err := NewStructuredELTRepository(testDB{})
	if err != nil {
		t.Fatal(err)
	}
	spec := validStructuredELTSpec()
	spec.IngestRunID = "not-a-uuid"
	_, err = repo.ExecuteStructuredELT(context.Background(), spec)
	if err == nil || !strings.Contains(err.Error(), "ingest_run_id") {
		t.Fatalf("expected an ingest_run_id validation error, got %v", err)
	}
}

func TestStructuredELTRepositoryRejectsBadOptionalUUIDsBeforeOpeningTransaction(t *testing.T) {
	repo, err := NewStructuredELTRepository(testDB{})
	if err != nil {
		t.Fatal(err)
	}
	spec := validStructuredELTSpec()
	spec.DeviceID = "not-a-uuid"
	if _, err := repo.ExecuteStructuredELT(context.Background(), spec); err == nil || !strings.Contains(err.Error(), "device_id") {
		t.Fatalf("expected a device_id validation error, got %v", err)
	}

	spec = validStructuredELTSpec()
	spec.AcquisitionID = "not-a-uuid"
	if _, err := repo.ExecuteStructuredELT(context.Background(), spec); err == nil || !strings.Contains(err.Error(), "acquisition_id") {
		t.Fatalf("expected an acquisition_id validation error, got %v", err)
	}
}

func TestStructuredELTRepositoryRejectsEmptySourceURLBeforeOpeningTransaction(t *testing.T) {
	repo, err := NewStructuredELTRepository(testDB{})
	if err != nil {
		t.Fatal(err)
	}
	spec := validStructuredELTSpec()
	spec.SourceURL = ""
	if _, err := repo.ExecuteStructuredELT(context.Background(), spec); err == nil {
		t.Fatal("expected an error for an empty source url")
	}
}

// TestStructuredELTRepositoryReachesTheDatabaseOnlyAfterValidation proves
// control flow reaches BeginTx (and only then fails, on testDB's
// "not implemented" stub) once every input is well-formed — i.e. validation
// genuinely gates the transaction rather than being dead code.
func TestStructuredELTRepositoryReachesTheDatabaseOnlyAfterValidation(t *testing.T) {
	repo, err := NewStructuredELTRepository(testDB{})
	if err != nil {
		t.Fatal(err)
	}
	_, err = repo.ExecuteStructuredELT(context.Background(), validStructuredELTSpec())
	if err == nil || !strings.Contains(err.Error(), "not implemented") {
		t.Fatalf("expected the request to reach BeginTx and hit testDB's stub, got %v", err)
	}
}

func TestDuckDBReaderExprBuildsCSVReader(t *testing.T) {
	got, err := duckDBReaderExpr(activities.StructuredELTFormatCSV, "https://example.invalid/a.csv")
	if err != nil {
		t.Fatal(err)
	}
	want := "SELECT * FROM read_csv_auto('https://example.invalid/a.csv', all_varchar=true)"
	if got != want {
		t.Fatalf("csv reader expr = %q, want %q", got, want)
	}
}

func TestDuckDBReaderExprBuildsNDJSONReader(t *testing.T) {
	got, err := duckDBReaderExpr(activities.StructuredELTFormatNDJSON, "https://example.invalid/a.ndjson")
	if err != nil {
		t.Fatal(err)
	}
	want := "SELECT * FROM read_json_auto('https://example.invalid/a.ndjson', format='newline_delimited')"
	if got != want {
		t.Fatalf("ndjson reader expr = %q, want %q", got, want)
	}
}

func TestDuckDBReaderExprEscapesSingleQuotesInURL(t *testing.T) {
	got, err := duckDBReaderExpr(activities.StructuredELTFormatCSV, "https://example.invalid/o'brien.csv")
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(got, "o''brien.csv") {
		t.Fatalf("expected doubled single quote escaping, got %q", got)
	}
}

func TestDuckDBReaderExprRejectsEmptyURL(t *testing.T) {
	if _, err := duckDBReaderExpr(activities.StructuredELTFormatCSV, "   "); err == nil {
		t.Fatal("expected an error for a blank url")
	}
}

func TestDuckDBReaderExprRejectsUnknownFormat(t *testing.T) {
	if _, err := duckDBReaderExpr(activities.StructuredELTFormat("parquet"), "https://example.invalid/a"); err == nil {
		t.Fatal("expected an error for an unsupported format")
	}
}

func TestSQLStringLiteralEscapesSingleQuotes(t *testing.T) {
	got := sqlStringLiteral("context-rawrecord-fingerprint-duckdb-json-v1")
	if got != "'context-rawrecord-fingerprint-duckdb-json-v1'" {
		t.Fatalf("literal = %q", got)
	}
	if got := sqlStringLiteral("it's"); got != "'it''s'" {
		t.Fatalf("escaped literal = %q", got)
	}
}

func TestValidateOptionalUUIDAllowsEmpty(t *testing.T) {
	if err := validateOptionalUUID("", "device_id"); err != nil {
		t.Fatalf("empty optional uuid should be allowed: %v", err)
	}
}

func TestValidateOptionalUUIDRejectsMalformed(t *testing.T) {
	if err := validateOptionalUUID("not-a-uuid", "device_id"); err == nil {
		t.Fatal("expected an error for a malformed optional uuid")
	}
}

func TestValidateOptionalUUIDAcceptsWellFormed(t *testing.T) {
	if err := validateOptionalUUID("8c8c2c9e-1c1a-4a1a-9b1a-1c1a4a1a9b1a", "device_id"); err != nil {
		t.Fatalf("unexpected error for a well-formed uuid: %v", err)
	}
}

func TestEltCanonIsAContextFingerprintNotCustodyH2(t *testing.T) {
	// Guards the ruling recorded at the top of elt_structured_repository.go
	// (D-124, D-149): this lane writes a post-decode CONTEXT FINGERPRINT and must
	// never carry a custody H-family tag - neither the byte-exact contract tag
	// nor any other h2- prefixed name (the pre-2026-09-07 mistake).
	if eltContextFingerprintCanon == "h2-rawelement-v1" || (len(eltContextFingerprintCanon) >= 3 && eltContextFingerprintCanon[:3] == "h2-") {
		t.Fatal("structured ELT content_canon is a context fingerprint and must never carry the custody h2- prefix")
	}
	if len(eltContextFingerprintCanon) < 8 || eltContextFingerprintCanon[:8] != "context-" {
		t.Fatal("structured ELT content_canon must belong to the sql/0048 context-fingerprint family")
	}
	if eltParserVersion == "" {
		t.Fatal("structured ELT parser_version tag must not be empty")
	}
}
