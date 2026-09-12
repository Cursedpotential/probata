// Byline: Claude Code · Sonnet 5 · 2026-09-02
package postgres

import (
	"context"
	"errors"
	"strings"
	"testing"

	"github.com/Cursedpotential/probata/engine/activities"
	"github.com/Cursedpotential/probata/engine/proffer"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
)

func TestNewStructuredELTRepositoryRequiresDB(t *testing.T) {
	if _, err := NewStructuredELTRepository(nil); err == nil {
		t.Fatal("expected error when db is nil")
	}
}

func TestOpenStructuredELTRowsRejectsInvalidReferencesBeforeDatabaseAccess(t *testing.T) {
	acquireCalls := 0
	repo := newStructuredELTRepository(func(context.Context) (structuredELTSession, error) {
		acquireCalls++
		return nil, errors.New("database should not be reached")
	})
	valid := proffer.StageRequest{
		RequestID:        "workflow-1",
		SourceVersionRef: "11111111-1111-1111-1111-111111111111",
		DeclaredFormat:   "smsbackuprestore_xml",
		Refs:             map[string]proffer.Ref{"original": "22222222-2222-2222-2222-222222222222"},
	}
	for name, req := range map[string]proffer.StageRequest{
		"missing request": func() proffer.StageRequest { copy := valid; copy.RequestID = ""; return copy }(),
		"bad source":      func() proffer.StageRequest { copy := valid; copy.SourceVersionRef = "bad"; return copy }(),
		"missing original": func() proffer.StageRequest {
			copy := valid
			copy.Refs = map[string]proffer.Ref{}
			return copy
		}(),
		"bad original": func() proffer.StageRequest {
			copy := valid
			copy.Refs = map[string]proffer.Ref{"original": "bad"}
			return copy
		}(),
	} {
		t.Run(name, func(t *testing.T) {
			if _, err := repo.OpenStructuredELTRows(context.Background(), req, activities.StructuredELTFormatSMSXML); err == nil {
				t.Fatal("expected invalid reference to fail before database access")
			}
		})
	}
	if acquireCalls != 0 {
		t.Fatalf("invalid references acquired %d PostgreSQL sessions", acquireCalls)
	}
}

type webbedStatusRow struct {
	loaded bool
	err    error
}

func (r webbedStatusRow) Scan(destinations ...any) error {
	if r.err != nil {
		return r.err
	}
	if len(destinations) != 1 {
		return errors.New("unexpected Webbed status destination count")
	}
	loaded, ok := destinations[0].(*bool)
	if !ok {
		return errors.New("Webbed status destination is not *bool")
	}
	*loaded = r.loaded
	return nil
}

type fakeStructuredELTSession struct {
	execSQL     string
	queryRowSQL string
	execErr     error
	status      webbedStatusRow
}

func (s *fakeStructuredELTSession) Exec(_ context.Context, sql string, _ ...any) (pgconn.CommandTag, error) {
	s.execSQL = sql
	return pgconn.CommandTag{}, s.execErr
}

func (*fakeStructuredELTSession) Query(context.Context, string, ...any) (pgx.Rows, error) {
	return nil, errors.New("unexpected query")
}

func (s *fakeStructuredELTSession) QueryRow(_ context.Context, sql string, _ ...any) pgx.Row {
	s.queryRowSQL = sql
	return s.status
}

func (*fakeStructuredELTSession) Release() {}

func TestEnsureWebbedLoadedUsesExplicitLoadAndDuckDBVerification(t *testing.T) {
	session := &fakeStructuredELTSession{status: webbedStatusRow{loaded: true}}
	if err := ensureWebbedLoaded(context.Background(), session); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(session.execSQL, "duckdb.load_extension('webbed')") {
		t.Fatalf("Webbed load was not explicit: %s", session.execSQL)
	}
	if !strings.Contains(session.queryRowSQL, "duckdb_extensions()") || !strings.Contains(session.queryRowSQL, "extension_name = 'webbed'") {
		t.Fatalf("Webbed readiness was not verified from DuckDB: %s", session.queryRowSQL)
	}
}

func TestEnsureWebbedLoadedFailsClosed(t *testing.T) {
	for name, session := range map[string]*fakeStructuredELTSession{
		"load failure":   {execErr: errors.New("load denied")},
		"verify failure": {status: webbedStatusRow{err: errors.New("status unavailable")}},
		"not loaded":     {status: webbedStatusRow{loaded: false}},
	} {
		t.Run(name, func(t *testing.T) {
			if err := ensureWebbedLoaded(context.Background(), session); err == nil {
				t.Fatal("expected Webbed readiness failure")
			}
		})
	}
}

func TestOnlyXMLTemplateRequiresWebbed(t *testing.T) {
	if !structuredELTRequiresWebbed(activities.StructuredELTFormatSMSXML) {
		t.Fatal("SMS XML must load Webbed")
	}
	for _, format := range []activities.StructuredELTFormat{
		activities.StructuredELTFormatCSV,
		activities.StructuredELTFormatNDJSON,
		activities.StructuredELTFormatChatGPTJSON,
		activities.StructuredELTFormatIMessageText,
	} {
		if structuredELTRequiresWebbed(format) {
			t.Fatalf("format %q unexpectedly requires Webbed", format)
		}
	}
}

func TestDuckDBSourceURLTranslatesR2ToS3(t *testing.T) {
	got, err := duckDBSourceURL("r2://nexus/proffer/test-fixtures/sample.xml")
	if err != nil {
		t.Fatal(err)
	}
	if got != "s3://nexus/proffer/test-fixtures/sample.xml" {
		t.Fatalf("duckDBSourceURL() = %q", got)
	}
}

func TestDuckDBSourceURLRejectsWorkerLocalOrUnretainedLocators(t *testing.T) {
	for _, locator := range []string{"upload://abc", "file:///sealed/source.xml", "b2://bucket/key"} {
		if _, err := duckDBSourceURL(locator); err == nil {
			t.Fatalf("expected %q to fail closed", locator)
		}
	}
}

func TestStructuredELTQueriesEmitCanonicalBundleColumns(t *testing.T) {
	formats := []activities.StructuredELTFormat{
		activities.StructuredELTFormatCSV,
		activities.StructuredELTFormatNDJSON,
		activities.StructuredELTFormatSMSXML,
		activities.StructuredELTFormatChatGPTJSON,
		activities.StructuredELTFormatIMessageText,
	}
	for _, format := range formats {
		query, err := structuredELTQuery(format, "s3://nexus/test/source")
		if err != nil {
			t.Fatalf("structuredELTQuery(%q) error = %v", format, err)
		}
		templateID, err := activities.StructuredELTTemplateForFormat(format)
		if err != nil {
			t.Fatalf("StructuredELTTemplateForFormat(%q) error = %v", format, err)
		}
		for _, column := range []string{"stored_bytes", "native_fields", "native_metadata"} {
			if !strings.Contains(query, column) {
				t.Fatalf("structuredELTQuery(%q) lacks %q output: %s", format, column, query)
			}
		}
		if !strings.Contains(query, "'duckdb_template', '"+templateID+"'") {
			t.Fatalf("structuredELTQuery(%q) does not emit pinned template %q", format, templateID)
		}
		if strings.Contains(strings.ToUpper(query), "INSERT ") {
			t.Fatalf("structuredELTQuery(%q) must not write raw tables", format)
		}
	}
}

func TestStructuredELTQueriesUseFormatSpecificDuckDBReaders(t *testing.T) {
	tests := map[activities.StructuredELTFormat][]string{
		activities.StructuredELTFormatSMSXML:       {"read_xml(", "record_element := 'sms'", "record_element := 'mms'"},
		activities.StructuredELTFormatChatGPTJSON:  {"read_text(", "json_each("},
		activities.StructuredELTFormatIMessageText: {"read_text(", "regexp_split_to_array("},
	}
	for format, expected := range tests {
		query, err := structuredELTQuery(format, "s3://nexus/test/source")
		if err != nil {
			t.Fatal(err)
		}
		for _, fragment := range expected {
			if !strings.Contains(query, fragment) {
				t.Fatalf("structuredELTQuery(%q) lacks %q", format, fragment)
			}
		}
	}
}

func TestStructuredELTQueryEscapesSourceURL(t *testing.T) {
	query, err := structuredELTQuery(activities.StructuredELTFormatChatGPTJSON, "https://example.invalid/o'brien.json")
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(query, "o''brien.json") {
		t.Fatalf("source URL was not escaped: %s", query)
	}
}
