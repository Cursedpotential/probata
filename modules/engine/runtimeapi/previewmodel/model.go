// Byline: Codex · GPT-5.6 · 2026-08-29 (Proffer preview storage model)
package previewmodel

import (
	"context"
	"encoding/hex"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/google/uuid"

	"github.com/Cursedpotential/probata/engine/proffer"
)

var (
	ErrNotFound = errors.New("proffer preview handle not found")
	ErrNotReady = errors.New("proffer preview projection not ready")
	ErrEventGap = errors.New("proffer preview event replay gap")
)

type Binding struct {
	Handle                 string
	RequestID              string
	SourceRef              proffer.Ref
	WorkflowID             string
	RunID                  string
	SelectionRef           proffer.Ref
	ParserOptionsRef       proffer.Ref
	SourceVersionID        uuid.UUID
	RawGenerationID        uuid.UUID
	NormalizedGenerationID uuid.UUID
	CreatedAt              time.Time
}

// BindingCursor is a stable keyset coordinate over the append-only preview
// binding registry. Newer rows do not shift an in-progress listing.
type BindingCursor struct {
	CreatedAt time.Time
	Handle    string
}

type BindingPage struct {
	Bindings []Binding
	HasMore  bool
}

// OperationStage is the durable receipt projection for one settled Activity.
// It intentionally carries references and accounting timestamps, never source
// or normalized payloads.
type OperationStage struct {
	Stage       string     `json:"stage"`
	Status      string     `json:"status"`
	Ref         string     `json:"ref,omitempty"`
	ReceiptRef  string     `json:"receipt_ref,omitempty"`
	Reason      string     `json:"reason,omitempty"`
	Attempt     int        `json:"attempt,omitempty"`
	StartedAt   *time.Time `json:"started_at,omitempty"`
	CompletedAt *time.Time `json:"completed_at,omitempty"`
}
type Receipt struct {
	ReceiptType string    `json:"receipt_type"`
	ReceiptRef  string    `json:"receipt_ref"`
	Status      string    `json:"status"`
	Digest      string    `json:"digest,omitempty"`
	RecordedAt  time.Time `json:"recorded_at"`
}
type Parser struct {
	ParserID      string `json:"parser_id"`
	ParserVersion string `json:"parser_version"`
	ConfigDigest  string `json:"config_digest"`
}
type Snapshot struct {
	PreviewHandle string `json:"preview_handle"`
	Phase         string `json:"phase"`
	Correlation   struct {
		RequestID              string    `json:"request_id"`
		SourceVersionID        uuid.UUID `json:"source_version_id"`
		RawGenerationID        uuid.UUID `json:"raw_generation_id"`
		NormalizedGenerationID uuid.UUID `json:"normalized_generation_id"`
	} `json:"correlation"`
	Parser              *Parser                    `json:"parser,omitempty"`
	PreviewDigest       string                     `json:"preview_digest"`
	Receipts            []Receipt                  `json:"receipts"`
	Reason              string                     `json:"reason,omitempty"`
	Lifecycle           proffer.OperationLifecycle `json:"lifecycle"`
	CurrentStage        proffer.ActivityName       `json:"current_stage,omitempty"`
	ActiveStages        []proffer.ActivityName     `json:"active_stages"`
	Wait                proffer.OperationWait      `json:"wait,omitempty"`
	Terminal            bool                       `json:"terminal"`
	CompletedStageCount int                        `json:"completed_stage_count"`
}
type Participant struct {
	ParticipantID    string  `json:"participant_id"`
	DisplayName      string  `json:"display_name"`
	CanonicalAddress *string `json:"canonical_address,omitempty"`
}
type Attachment struct {
	AttachmentID     string  `json:"attachment_id"`
	Filename         *string `json:"filename,omitempty"`
	MediaType        *string `json:"media_type,omitempty"`
	ByteLength       *int64  `json:"byte_length,omitempty"`
	SHA256           *string `json:"sha256,omitempty"`
	SourceLocatorRef string  `json:"source_locator_ref"`
}
type Message struct {
	MessageID           string       `json:"message_id"`
	Ordinal             int64        `json:"ordinal"`
	SentAt              *time.Time   `json:"sent_at,omitempty"`
	SenderParticipantID *string      `json:"sender_participant_id,omitempty"`
	Body                string       `json:"body"`
	ParticipantIDs      []string     `json:"participant_ids"`
	Attachments         []Attachment `json:"attachments"`
	SourceLocatorRef    string       `json:"source_locator_ref"`
}
type Event struct {
	EventID       int64     `json:"event_id"`
	EventType     string    `json:"event_type"`
	OccurredAt    time.Time `json:"occurred_at"`
	PreviewHandle string    `json:"preview_handle"`
	Phase         string    `json:"phase"`
	ReceiptRef    *string   `json:"receipt_ref,omitempty"`
	MessageCount  *int      `json:"message_count,omitempty"`
	Detail        string    `json:"detail,omitempty"`
}
type Page struct {
	Participants []Participant
	Messages     []Message
	NextOffset   *int
}

type Store interface {
	Create(context.Context, Binding) (Binding, error)
	Binding(context.Context, string) (Binding, error)
	Snapshot(context.Context, string) (Snapshot, error)
	Page(context.Context, string, int, int) (Page, error)
	EventsAfter(context.Context, string, int64) ([]Event, error)
	RecordDecision(context.Context, string, bool, string, string, proffer.Ref, proffer.Ref) error
	ListBindings(context.Context, *BindingCursor, int) (BindingPage, error)
	OperationStages(context.Context, string) ([]OperationStage, error)
}

// ReceiptTypes are context-import completeness checkpoints. The first receipt
// verifies raw records against their source; it is not evidence custody,
// admission, sealing, or promotion.
var ReceiptTypes = []string{"raw_source_verification", "parser_selection", "parser_execution", "normalization", "storage", "completeness"}

func Validate(handle string, snapshot Snapshot, participants []Participant, messages []Message) error {
	if snapshot.PreviewHandle != handle || !ValidDigest(snapshot.PreviewDigest) {
		return errors.New("preview snapshot correlation or digest is invalid")
	}
	seen := make(map[string]bool)
	for _, receipt := range snapshot.Receipts {
		if strings.TrimSpace(receipt.ReceiptRef) == "" || receipt.Status != "completed" || (receipt.Digest != "" && !ValidDigest(receipt.Digest)) {
			return errors.New("preview receipt is incomplete or invalid")
		}
		seen[receipt.ReceiptType] = true
	}
	for _, kind := range ReceiptTypes {
		if !seen[kind] {
			return fmt.Errorf("preview is missing completed %s receipt", kind)
		}
	}
	ids := make(map[string]bool)
	for _, participant := range participants {
		if strings.TrimSpace(participant.ParticipantID) == "" || strings.TrimSpace(participant.DisplayName) == "" {
			return errors.New("preview participant is invalid")
		}
		ids[participant.ParticipantID] = true
	}
	if len(messages) == 0 {
		return errors.New("preview requires at least one normalized message")
	}
	for _, message := range messages {
		if strings.TrimSpace(message.MessageID) == "" || message.Ordinal < 0 || strings.TrimSpace(message.SourceLocatorRef) == "" || len(message.Body) > 1_000_000 {
			return errors.New("preview message is invalid")
		}
		for _, id := range message.ParticipantIDs {
			if !ids[id] {
				return errors.New("preview message references an unknown participant")
			}
		}
		if message.SenderParticipantID != nil && !ids[*message.SenderParticipantID] {
			return errors.New("preview message sender is unknown")
		}
		for _, attachment := range message.Attachments {
			if strings.TrimSpace(attachment.AttachmentID) == "" || strings.TrimSpace(attachment.SourceLocatorRef) == "" || (attachment.SHA256 != nil && !ValidDigest(*attachment.SHA256)) {
				return errors.New("preview attachment is invalid")
			}
		}
	}
	return nil
}

func ValidDigest(value string) bool {
	if len(value) != 64 {
		return false
	}
	_, err := hex.DecodeString(value)
	return err == nil && value == strings.ToLower(value)
}
