package postgres

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

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
		{name: "calls backup is not sms", content: `<?xml version="1.0"?><calls count="1"><call number="+1"/></calls>`, wantError: "calls XML is not"},
		{name: "chatgpt official", content: `[{"title":"Chat","conversation_id":"c-1","mapping":{"node":{"message":{"author":{"role":"user"},"content":{"content_type":"text","parts":["hello"]}}}}}]`, wantFormat: "chatgpt_official_json"},
		{name: "message transcript", content: "[2026-09-12 8:04 PM] Matthew Salem:\nhello\n", wantFormat: "messages_transcript"},
		{name: "filename-like text is not a signature", content: "sms-backup.xml\nnot actually an export", wantError: "does not match"},
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
