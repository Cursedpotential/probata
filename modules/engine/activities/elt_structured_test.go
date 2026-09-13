// Byline: Claude Code · Sonnet 5 · 2026-09-02
package activities

import (
	"context"
	"encoding/json"
	"io"
	"testing"

	"github.com/Cursedpotential/probata/engine/parser"
	"github.com/Cursedpotential/probata/engine/proffer"
	"github.com/Cursedpotential/probata/engine/stagegraph"
)

func TestStructuredELTFormatConstants(t *testing.T) {
	if StructuredELTFormatCSV != "csv" {
		t.Fatalf("csv format constant changed value: %q", StructuredELTFormatCSV)
	}
	if StructuredELTFormatNDJSON != "ndjson" {
		t.Fatalf("ndjson format constant changed value: %q", StructuredELTFormatNDJSON)
	}
}

type fakeStructuredELTRowReader struct {
	rows  []StructuredELTRow
	index int
}

func (r *fakeStructuredELTRowReader) Next(context.Context) (StructuredELTRow, error) {
	if r.index >= len(r.rows) {
		return StructuredELTRow{}, io.EOF
	}
	row := r.rows[r.index]
	r.index++
	return row, nil
}

func (*fakeStructuredELTRowReader) Close() error { return nil }

type fakeStructuredELTRowRepository struct {
	req    proffer.StageRequest
	format StructuredELTFormat
	reader StructuredELTRowReader
	err    error
}

type fakeHandlerExecutionAuthorizationStore struct {
	authorization HandlerExecutionAuthorization
	req           proffer.StageRequest
	err           error
}

func (s *fakeHandlerExecutionAuthorizationStore) LoadHandlerExecutionAuthorization(_ context.Context, req proffer.StageRequest) (HandlerExecutionAuthorization, error) {
	s.req = req
	return s.authorization, s.err
}

func structuredELTAuthorization() *fakeHandlerExecutionAuthorizationStore {
	return &fakeHandlerExecutionAuthorizationStore{authorization: HandlerExecutionAuthorization{
		DetectedFormat: "smsbackuprestore_xml", HandlerID: StructuredELTParserID,
		HandlerVersion: StructuredELTParserVersion, ExecutionPath: proffer.HandlerPathDuckDB,
	}}
}

func (r *fakeStructuredELTRowRepository) OpenStructuredELTRows(_ context.Context, req proffer.StageRequest, format StructuredELTFormat) (StructuredELTRowReader, error) {
	r.req, r.format = req, format
	if r.err != nil {
		return nil, r.err
	}
	return r.reader, nil
}

func structuredELTStageFixture() (proffer.StageRequest, *runtimeStore, *runtimeBundleWriter) {
	req := proffer.StageRequest{
		RequestID: "workflow:elt", SourceVersionRef: "source:elt", DeclaredFormat: "sms_export_xml",
		Refs: map[string]proffer.Ref{
			"parser_selection":       "selection:elt",
			"original":               "original:elt",
			"handler_recommendation": "recommendation:elt",
			"handler_decision":       "decision:elt",
			"handler_validation":     "validation:elt",
			"detected_format":        "format:elt",
			"content_signature":      "signature:elt",
			"handler_compatibility":  "compatibility:elt",
		},
	}
	writer := &runtimeBundleWriter{}
	store := &runtimeStore{
		selection: PersistedParserSelection{
			SourceVersionRef: req.SourceVersionRef, DeclaredFormat: parser.FormatID(req.DeclaredFormat),
			ParserID: "duckdb_structured_elt", ParserVersion: "1.0.0",
		},
		input: parser.ParserInput{
			ContractVersion: parser.ContractVersion, SourceVersionRef: string(req.SourceVersionRef),
			DeclaredFormat: parser.FormatID(req.DeclaredFormat),
			FileOrMember: parser.Locator{Type: parser.LocatorWholeObject, ObjectRef: parser.ObjectRef{
				StorageClass: "immutable_object_store", URI: "s3://nexus/test/sms.xml",
			}},
		},
		writer: writer,
	}
	return req, store, writer
}

func TestSelectStructuredELTRequiresDurableContentDecision(t *testing.T) {
	req, store, _ := structuredELTStageFixture()
	delete(req.Refs, "content_signature")
	if _, err := (StructuredELTActivities{Store: store, Authorization: structuredELTAuthorization()}).SelectStructuredELT(context.Background(), req); err == nil {
		t.Fatal("expected selection without content signature to fail closed")
	}
	if store.selectionSpec.ParserID != "" {
		t.Fatalf("selection was persisted without content validation: %+v", store.selectionSpec)
	}
}

func TestExecuteStructuredELTRequiresDurableHandlerValidation(t *testing.T) {
	req, store, writer := structuredELTStageFixture()
	delete(req.Refs, "handler_validation")
	repo := &fakeStructuredELTRowRepository{reader: &fakeStructuredELTRowReader{}}
	if _, err := (StructuredELTActivities{Rows: repo, Store: store, Authorization: structuredELTAuthorization()}).ExecuteStructuredELT(context.Background(), req); err == nil {
		t.Fatal("expected execution without handler validation to fail closed")
	}
	if writer.records != 0 || store.persistExecCalls != 0 {
		t.Fatalf("unvalidated handler wrote output: records=%d receipt_calls=%d", writer.records, store.persistExecCalls)
	}
}

func TestSelectStructuredELTPinsDuckDBIdentity(t *testing.T) {
	req, store, _ := structuredELTStageFixture()
	authorization := structuredELTAuthorization()
	result, err := (StructuredELTActivities{Store: store, Authorization: authorization, Attempt: func(context.Context) int32 { return 4 }}).SelectStructuredELT(context.Background(), req)
	if err != nil {
		t.Fatalf("SelectStructuredELT() error = %v", err)
	}
	if result.Stage != stagegraph.SelectParser || result.Status != proffer.StatusSuccess || result.Ref != "selection:1" || result.ReceiptRef != "receipt:selection" {
		t.Fatalf("unexpected stage result: %+v", result)
	}
	if store.selectionSpec.ParserID != StructuredELTParserID || store.selectionSpec.ParserVersion != StructuredELTParserVersion || store.selectionSpec.Attempt != 4 {
		t.Fatalf("selection was not pinned to DuckDB: %+v", store.selectionSpec)
	}
	if store.selectionSpec.DeclaredFormat != parser.FormatID(req.DeclaredFormat) || authorization.req.DeclaredFormat != req.DeclaredFormat {
		t.Fatalf("operator declaration was not preserved through DuckDB selection: selection=%+v authorization=%+v", store.selectionSpec, authorization.req)
	}
}

func TestExecuteStructuredELTEmitsStandardBundleAndParserReceipt(t *testing.T) {
	req, store, writer := structuredELTStageFixture()
	repo := &fakeStructuredELTRowRepository{reader: &fakeStructuredELTRowReader{rows: []StructuredELTRow{
		{StoredBytes: []byte(`{"address":"+1555","body":"one"}`), NativeFields: json.RawMessage(`{"record_kind":"message","body":"one"}`), NativeMetadata: json.RawMessage(`{"duckdb_template":"sms_xml_v1"}`)},
		{StoredBytes: []byte(`{"address":"+1555","body":"two"}`), NativeFields: json.RawMessage(`{"record_kind":"message","body":"two"}`), NativeMetadata: json.RawMessage(`{"duckdb_template":"sms_xml_v1"}`)},
	}}}
	result, err := (StructuredELTActivities{Rows: repo, Store: store, Authorization: structuredELTAuthorization(), Attempt: func(context.Context) int32 { return 3 }}).ExecuteStructuredELT(context.Background(), req)
	if err != nil {
		t.Fatalf("ExecuteStructuredELT() error = %v", err)
	}
	if result.Stage != stagegraph.ExecuteParser || result.Status != proffer.StatusSuccess || result.Ref != "execution:1" || result.ReceiptRef != "receipt:execution" {
		t.Fatalf("unexpected stage result: %+v", result)
	}
	if repo.format != StructuredELTFormatSMSXML || repo.req.RequestID != req.RequestID {
		t.Fatalf("repository received format=%q request=%+v", repo.format, repo.req)
	}
	if writer.records != 2 || writer.finalizes != 1 || writer.aborts != 0 {
		t.Fatalf("bundle writer records=%d finalizes=%d aborts=%d", writer.records, writer.finalizes, writer.aborts)
	}
	if writer.header.FormatID != parser.FormatID(req.DeclaredFormat) || writer.header.ParserID != "duckdb_structured_elt" {
		t.Fatalf("unexpected bundle header: %+v", writer.header)
	}
	if store.executionSpec.BundleRef != "bundle:staged" || store.executionSpec.Attempt != 3 || store.persistExecCalls != 1 {
		t.Fatalf("unexpected parser execution receipt spec: %+v calls=%d", store.executionSpec, store.persistExecCalls)
	}
}

func TestExecuteStructuredELTEmptyQueryFailsBeforeReceiptAndAbortsBundle(t *testing.T) {
	req, store, writer := structuredELTStageFixture()
	repo := &fakeStructuredELTRowRepository{reader: &fakeStructuredELTRowReader{}}
	if _, err := (StructuredELTActivities{Rows: repo, Store: store, Authorization: structuredELTAuthorization()}).ExecuteStructuredELT(context.Background(), req); err == nil {
		t.Fatal("expected empty DuckDB extraction to fail")
	}
	if writer.aborts != 1 || writer.finalizes != 0 || store.persistExecCalls != 0 {
		t.Fatalf("writer aborts=%d finalizes=%d receipt calls=%d", writer.aborts, writer.finalizes, store.persistExecCalls)
	}
}

func TestExecuteStructuredELTRejectsTemplateMismatch(t *testing.T) {
	req, store, writer := structuredELTStageFixture()
	repo := &fakeStructuredELTRowRepository{reader: &fakeStructuredELTRowReader{rows: []StructuredELTRow{
		{StoredBytes: []byte(`{"body":"one"}`), NativeFields: json.RawMessage(`{"record_kind":"message","body":"one"}`), NativeMetadata: json.RawMessage(`{"duckdb_template":"calls_xml_v1"}`)},
	}}}
	if _, err := (StructuredELTActivities{Rows: repo, Store: store, Authorization: structuredELTAuthorization()}).ExecuteStructuredELT(context.Background(), req); err == nil {
		t.Fatal("expected mismatched DuckDB template to fail closed")
	}
	if writer.records != 0 || writer.finalizes != 0 || writer.aborts != 1 || store.persistExecCalls != 0 {
		t.Fatalf("template mismatch wrote output: records=%d finalizes=%d aborts=%d receipt_calls=%d", writer.records, writer.finalizes, writer.aborts, store.persistExecCalls)
	}
}

func TestExecuteStructuredELTRejectsDecoderSelection(t *testing.T) {
	req, store, writer := structuredELTStageFixture()
	store.selection.ParserID = "sbv_sms_xml_backup"
	repo := &fakeStructuredELTRowRepository{reader: &fakeStructuredELTRowReader{rows: []StructuredELTRow{
		{StoredBytes: []byte(`{"body":"one"}`), NativeFields: json.RawMessage(`{"record_kind":"message","body":"one"}`), NativeMetadata: json.RawMessage(`{}`)},
	}}}
	if _, err := (StructuredELTActivities{Rows: repo, Store: store, Authorization: structuredELTAuthorization()}).ExecuteStructuredELT(context.Background(), req); err == nil {
		t.Fatal("expected decoder selection to fail closed")
	}
	if writer.records != 0 || store.persistExecCalls != 0 {
		t.Fatalf("decoder selection wrote ELT output: records=%d receipt_calls=%d", writer.records, store.persistExecCalls)
	}
}

func TestExecuteStructuredELTRejectsNonDuckDBAuthorization(t *testing.T) {
	req, store, writer := structuredELTStageFixture()
	authorization := structuredELTAuthorization()
	authorization.authorization.ExecutionPath = proffer.HandlerPathDecoder
	repo := &fakeStructuredELTRowRepository{reader: &fakeStructuredELTRowReader{rows: []StructuredELTRow{
		{StoredBytes: []byte(`{"body":"one"}`), NativeFields: json.RawMessage(`{"record_kind":"message","body":"one"}`), NativeMetadata: json.RawMessage(`{"duckdb_template":"sms_xml_v1"}`)},
	}}}
	if _, err := (StructuredELTActivities{Rows: repo, Store: store, Authorization: authorization}).ExecuteStructuredELT(context.Background(), req); err == nil {
		t.Fatal("expected decoder authorization to fail before DuckDB execution")
	}
	if repo.req.RequestID != "" || writer.records != 0 || store.persistExecCalls != 0 {
		t.Fatalf("non-DuckDB authorization reached extraction: request=%+v records=%d receipt_calls=%d", repo.req, writer.records, store.persistExecCalls)
	}
}

func TestStructuredELTFormatForDeclaredFormat(t *testing.T) {
	tests := map[string]StructuredELTFormat{
		"smsbackuprestore_xml":  StructuredELTFormatSMSXML,
		"chatgpt_official_json": StructuredELTFormatChatGPTJSON,
		"messages_transcript":   StructuredELTFormatIMessageText,
	}
	for declared, want := range tests {
		got, err := StructuredELTFormatForDeclaredFormat(declared)
		if err != nil || got != want {
			t.Fatalf("StructuredELTFormatForDeclaredFormat(%q) = %q, %v; want %q", declared, got, err, want)
		}
	}
	for _, unsupported := range []string{"pdf", "sms_export_xml", "callsbackuprestore_xml", "imessage_txt"} {
		if _, err := StructuredELTFormatForDeclaredFormat(unsupported); err == nil {
			t.Fatalf("expected uncovered format %q to fail closed", unsupported)
		}
	}
}

func TestStructuredELTTemplateForFormat(t *testing.T) {
	tests := map[StructuredELTFormat]string{
		StructuredELTFormatCSV:          "csv_v1",
		StructuredELTFormatNDJSON:       "ndjson_v1",
		StructuredELTFormatSMSXML:       "sms_xml_v1",
		StructuredELTFormatChatGPTJSON:  "chatgpt_json_array_v1",
		StructuredELTFormatIMessageText: "imessage_text_v1",
	}
	for format, want := range tests {
		got, err := StructuredELTTemplateForFormat(format)
		if err != nil || got != want {
			t.Fatalf("StructuredELTTemplateForFormat(%q) = %q, %v; want %q", format, got, err, want)
		}
	}
}
