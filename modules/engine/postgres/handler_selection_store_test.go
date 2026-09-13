package postgres

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/Cursedpotential/probata/engine/parser"
	"github.com/stretchr/testify/require"
)

func TestDetectHandlerContentUsesRetainedBytesAndSeparatesCallsXML(t *testing.T) {
	tests := []struct {
		name       string
		content    string
		wantFormat string
		wantError  string
	}{
		{name: "sms backup and restore", content: `<?xml version="1.0"?><smses count="1"><sms address="+1"/></smses>`, wantFormat: "smsbackuprestore_xml"},
		{name: "calls backup is not sms", content: `<?xml version="1.0"?><calls count="1"><call number="+1"/></calls>`, wantFormat: "callsbackuprestore_xml"},
		{name: "chatgpt official", content: `[{"title":"Chat","conversation_id":"c-1","mapping":{"node":{"message":{"author":{"role":"user"},"content":{"content_type":"text","parts":["hello"]}}}}}]`, wantFormat: "chatgpt_official_json"},
		{name: "message transcript", content: "[2026-09-12 8:04 PM] Matthew Salem:\nhello\n", wantFormat: "messages_transcript"},
		{name: "filename-like text is not an sms signature", content: "sms-backup.xml\nnot actually an export", wantFormat: "text"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			format, signature, err := detectHandlerContent([]byte(tt.content))
			if tt.wantError != "" {
				require.ErrorContains(t, err, tt.wantError)
				require.Empty(t, format)
				require.Empty(t, signature)
				return
			}
			require.NoError(t, err)
			require.Equal(t, tt.wantFormat, format)
			require.NotEmpty(t, signature)
		})
	}
}

func TestDetectHandlerContentKeepsEstablishedFormatsOnDecoderPath(t *testing.T) {
	tests := []struct {
		name       string
		content    []byte
		wantFormat string
	}{
		{name: "pdf", content: []byte("%PDF-1.7\n1 0 obj\n"), wantFormat: "pdf"},
		{name: "docx", content: append([]byte{'P', 'K', 0x03, 0x04}, []byte("[Content_Types].xml\x00word/document.xml")...), wantFormat: "docx"},
		{name: "zip archive", content: append([]byte{'P', 'K', 0x03, 0x04}, []byte("ordinary/member.txt")...), wantFormat: "archive"},
		{name: "ordinary json", content: []byte(`{"kind":"ordinary","items":[1,2]}`), wantFormat: "json"},
		{name: "csv", content: []byte("sender,body\nMatthew,hello\nOther,goodbye\n"), wantFormat: "csv"},
		{name: "ndjson", content: []byte("{\"body\":\"one\"}\n{\"body\":\"two\"}\n"), wantFormat: "ndjson"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			format, signature, err := detectHandlerContent(tt.content)
			require.NoError(t, err)
			require.Equal(t, tt.wantFormat, format)
			require.NotEmpty(t, signature)
		})
	}
}

func TestHandlerCandidatesSelectOneSignatureHandlerWithoutDecoderAlternative(t *testing.T) {
	decoder := parser.Capability{ParserID: "sbv_csv", ParserVersion: "1.4.0"}
	structured := handlerCandidatesForDetectedFormat("csv", decoder)
	require.Len(t, structured, 1)
	require.Equal(t, "duckdb", string(structured[0].ExecutionPath))

	for _, detected := range []string{"pdf", "docx", "archive", "json", "text", "binary"} {
		candidates := handlerCandidatesForDetectedFormat(detected, decoder)
		require.Len(t, candidates, 1, detected)
		require.Equal(t, decoder.ParserID, candidates[0].HandlerID, detected)
		require.Equal(t, decoder.ParserVersion, candidates[0].HandlerVersion, detected)
		require.Equal(t, "decoder", string(candidates[0].ExecutionPath), detected)
		require.NotEmpty(t, candidates[0].CompatibilityRef, detected)
	}
}

func TestHandlerDetectedFormatConstraintCoversEveryDetectorOutput(t *testing.T) {
	snapshot, err := os.ReadFile(filepath.Join("..", "..", "..", "sql", "bootstrap", "schema_snapshot_20260907.sql"))
	require.NoError(t, err)
	const constraintName = "CONSTRAINT handler_detected_format_format_id_check"
	start := strings.Index(string(snapshot), constraintName)
	require.NotEqual(t, -1, start)
	constraint := string(snapshot[start:])
	if end := strings.IndexByte(constraint, '\n'); end >= 0 {
		constraint = constraint[:end]
	}
	expected := []string{
		"smsbackuprestore_xml", "chatgpt_official_json", "messages_transcript",
		"pdf", "docx", "archive", "callsbackuprestore_xml", "xml", "ndjson", "json", "csv", "text", "binary",
	}
	for _, format := range expected {
		require.Contains(t, constraint, "'"+format+"'::text", format)
	}
	require.Equal(t, len(expected)*2, strings.Count(constraint, "'"), "detected-format CHECK contains an unexpected or missing value")
}

func TestDetectHandlerContentRecognizesRealAppleMessagesStructure(t *testing.T) {
	content, err := os.ReadFile(filepath.Join("..", "..", "..", "tests", "fixtures", "probata_mixed_demo", "imessage-thread.txt"))
	require.NoError(t, err)
	format, signature, err := detectHandlerContent(content)
	require.NoError(t, err)
	require.Equal(t, "messages_transcript", format)
	require.Equal(t, "apple_messages_timestamp_sender_body_v1", signature)
}

func TestDetectHandlerContentStreamsFirstChatGPTConversationWithoutClosingArray(t *testing.T) {
	first := `{"title":"Chat","conversation_id":"c-1","mapping":{"node":{"message":{"author":{"role":"user"},"content":{"content_type":"text","parts":["hello"]}}}}}`
	truncatedLargeArray := "[" + first + `,{"title":"unfinished","mapping":{"node":{"message":{"content":"` + strings.Repeat("x", 1<<20)
	format, signature, err := detectHandlerContent([]byte(truncatedLargeArray))
	require.NoError(t, err)
	require.Equal(t, "chatgpt_official_json", format)
	require.Equal(t, "chatgpt_official_conversations_array_v1", signature)
}
