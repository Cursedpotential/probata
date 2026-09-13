// Byline: Codex · GPT-5.6 · 2026-08-29 (Proffer preview storage model)
package previewmodel

import (
	"context"
	"encoding/hex"
	"encoding/json"
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

// ContentProjection is a browser-safe read projection over the retained
// package, normalized records, and a sealed chunk generation. It does not
// define a second extraction format: Record.Payload is the exact persisted
// normalized_payload object and every other value is an existing durable
// identity, digest, locator, or receipt.
type Package struct {
	SourceVersionRef string  `json:"source_version_ref"`
	OriginalRef      *string `json:"original_ref,omitempty"`
	OriginalFilename *string `json:"original_filename,omitempty"`
	DeclaredFormat   string  `json:"declared_format"`
	Status           string  `json:"status"`
	OriginalSHA256   *string `json:"original_sha256,omitempty"`
	OriginalBytes    *int64  `json:"original_bytes,omitempty"`
	StorageClass     *string `json:"storage_class,omitempty"`
	MetadataCount    int64   `json:"metadata_count"`
	AttachmentCount  int64   `json:"attachment_count"`
}

type Attempt struct {
	AttemptRef              string    `json:"attempt_ref,omitempty"`
	ProjectionRef           string    `json:"projection_ref"`
	SourceVersionRef        string    `json:"source_version_ref"`
	RawGenerationRef        string    `json:"raw_generation_ref"`
	NormalizedGenerationRef string    `json:"normalized_generation_ref"`
	Parser                  *Parser   `json:"parser,omitempty"`
	SelectionRef            string    `json:"selection_ref,omitempty"`
	ParserOptionsRef        string    `json:"parser_options_ref,omitempty"`
	Receipts                []Receipt `json:"receipts"`
}

type Record struct {
	RecordID         string          `json:"record_id"`
	Ordinal          int64           `json:"ordinal"`
	RecordType       string          `json:"record_type"`
	OccurredAt       *time.Time      `json:"occurred_at,omitempty"`
	Payload          json.RawMessage `json:"payload"`
	SourceLocatorRef string          `json:"source_locator_ref"`
}

type PackageAttachment struct {
	ObjectRef       string          `json:"object_ref"`
	ParentObjectRef *string         `json:"parent_object_ref,omitempty"`
	MemberLocator   json.RawMessage `json:"member_locator"`
	SHA256          string          `json:"sha256"`
	ByteLength      int64           `json:"byte_length"`
	StorageClass    string          `json:"storage_class"`
}

type ChunkGeneration struct {
	GenerationRef     string     `json:"generation_ref"`
	GenerationOrdinal int        `json:"generation_ordinal"`
	Status            string     `json:"status"`
	PolicyID          string     `json:"policy_id"`
	PolicyVersion     string     `json:"policy_version"`
	ChunkerID         string     `json:"chunker_id"`
	ChunkerVersion    string     `json:"chunker_version"`
	SchemaVersion     string     `json:"schema_version"`
	SourceView        string     `json:"source_view"`
	SourceSHA256      string     `json:"source_sha256"`
	ManifestSHA256    *string    `json:"manifest_sha256,omitempty"`
	ChunkCount        *int64     `json:"chunk_count,omitempty"`
	ReceiptRef        string     `json:"receipt_ref"`
	ReassemblyResult  *string    `json:"reassembly_result,omitempty"`
	SealedAt          *time.Time `json:"sealed_at,omitempty"`
}

type ContentChunk struct {
	ChunkRef       string `json:"chunk_ref"`
	Index          int64  `json:"index"`
	Content        string `json:"content"`
	SHA256         string `json:"sha256"`
	DerivationMode string `json:"derivation_mode"`
	TokenCount     *int64 `json:"token_count,omitempty"`
	LocatorRef     string `json:"locator_ref"`
	ByteStart      int64  `json:"byte_start"`
	ByteEnd        int64  `json:"byte_end"`
}

type ContentPage struct {
	Package          Package             `json:"package"`
	Attempt          Attempt             `json:"attempt"`
	AttemptsComplete bool                `json:"attempts_complete"`
	AttemptsReason   string              `json:"attempts_reason,omitempty"`
	Records          []Record            `json:"records"`
	Attachments      []PackageAttachment `json:"attachments"`
	ChunkGeneration  *ChunkGeneration    `json:"chunk_generation,omitempty"`
	Chunks           []ContentChunk      `json:"chunks"`
	NextRecordOffset *int                `json:"-"`
	NextChunkOffset  *int                `json:"-"`
}

// ContentStore is optional so old preview stores and test doubles remain
// source-compatible. The HTTP endpoint fails closed when a store cannot
// supply the durable package/record/chunk projection.
type ContentStore interface {
	Content(context.Context, string, int, int, int) (ContentPage, error)
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
