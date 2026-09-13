package normalize

import (
	"context"
	"testing"
	"time"
)

// Actual DuckDB SQL output fields must normalize as messages even when intake
// only declares generic XML. The format-specific extractor converts the source
// epoch-millisecond value to an exact RFC 3339 timestamp before normalization.
func TestDuckDBSMSNativeBundleWithGenericXMLDeclaration(t *testing.T) {
	input := baseInput([]RawRecordView{{RecordOrdinal: 0, RecordStatus: "parsed",
		NativeFields:   []byte(`{"record_kind":"message","body":"actual SMS body","sender":"+15551234567","recipients":["self"],"participants":["self","+15551234567"],"occurred_at":"2022-11-03T18:26:40.000000Z"}`),
		NativeMetadata: []byte(`{"duckdb_template":"sms_xml_v1","source_kind":"sms","date_ms":"1667500000000"}`),
	}})
	input.DeclaredFormat = "xml"
	writer := &recordingWriter{bundleRef: "normalized:test-sms"}
	if _, err := Execute(context.Background(), input, GenericMessageNormalizer{}, writer); err != nil {
		t.Fatal(err)
	}
	if len(writer.emitted) != 1 || writer.emitted[0].RecordType != RecordTypeMessage || string(writer.emitted[0].Content) != `{"body":"actual SMS body"}` {
		t.Fatalf("wrong SMS normalization: %#v", writer.emitted)
	}
	if !hasParticipant(writer.emitted[0].Participants, RoleSender, "+15551234567") {
		t.Fatal("lost sender")
	}
	wantOccurredAt := time.Date(2022, 11, 3, 18, 26, 40, 0, time.UTC)
	if writer.emitted[0].OccurredAt == nil || !writer.emitted[0].OccurredAt.Equal(wantOccurredAt) {
		t.Fatalf("occurred_at = %v, want %s", writer.emitted[0].OccurredAt, wantOccurredAt.Format(time.RFC3339Nano))
	}
}
