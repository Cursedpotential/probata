// Byline: Codex · GPT-5.6 · 2026-08-29 (durable Proffer preview projection store)
package postgres

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"sort"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	"github.com/Cursedpotential/probata/engine/proffer"
	"github.com/Cursedpotential/probata/engine/runtimeapi/previewmodel"
)

// ProfferPreviewStore is the durable implementation of previewmodel.Store.
// It stores reference-only projections in PostgreSQL; source and normalized
// bytes remain in their governed context tables/object store.
type ProfferPreviewStore struct {
	db      DB
	entropy io.Reader
	clock   func() time.Time
}

type normalizedPreviewPayload struct {
	NormalizedRecordID string `json:"normalized_record_id"`
	Participants       []struct {
		Role        string `json:"role"`
		Identifier  string `json:"identifier"`
		DisplayName string `json:"display_name"`
	} `json:"participants"`
	Content struct {
		Body string `json:"body"`
	} `json:"content"`
}

type previewAttachmentMetadata struct {
	AttachmentOrdinal int64          `json:"attachment_ordinal"`
	NativeMetadata    map[string]any `json:"native_metadata"`
}

// PublishWorkflowPreview resolves reference-only workflow coordinates into a
// complete normalized projection, then delegates the atomic append to
// PublishProjection. Raw/normalized bytes never enter the Activity payload.
func (s *ProfferPreviewStore) PublishWorkflowPreview(ctx context.Context, request proffer.PreviewPublicationRequest) (previewmodel.Binding, error) {
	binding, err := s.bindingByRequest(ctx, request.RequestID)
	if err != nil {
		return previewmodel.Binding{}, err
	}
	var sourceID, rawID, normalizedID uuid.UUID
	if sourceID, err = uuid.Parse(string(request.SourceVersionRef)); err != nil {
		return binding, err
	}
	if rawID, err = uuid.Parse(string(request.RawGenerationRef)); err != nil {
		return binding, err
	}
	if normalizedID, err = uuid.Parse(string(request.NormalizedGenerationRef)); err != nil {
		return binding, err
	}
	var actualSource, actualRaw uuid.UUID
	if err := s.db.QueryRow(ctx, `SELECT source_version_id, raw_generation_id FROM context.normalized_generation WHERE id=$1::uuid`, normalizedID).Scan(&actualSource, &actualRaw); err != nil {
		return binding, err
	}
	if actualSource != sourceID || actualRaw != rawID {
		return binding, errors.New("preview generations do not share the requested source lineage")
	}
	selectionID, err := uuid.Parse(string(request.ParserSelectionRef))
	if err != nil {
		return binding, err
	}
	var parserID, parserVersion string
	if err := s.db.QueryRow(ctx, `SELECT result_ref->>'parser_id', result_ref->>'parser_version' FROM context.activity_receipt WHERE id=$1::uuid AND status='success'`, selectionID).Scan(&parserID, &parserVersion); err != nil {
		return binding, err
	}
	configDigest := sha256.Sum256([]byte(request.ParserOptionsRef))
	snapshot := previewmodel.Snapshot{PreviewHandle: binding.Handle, Phase: string(proffer.PhaseAwaitingDecision), PreviewDigest: strings.Repeat("0", 64)}
	snapshot.Correlation.RequestID, snapshot.Correlation.SourceVersionID = request.RequestID, sourceID
	snapshot.Correlation.RawGenerationID, snapshot.Correlation.NormalizedGenerationID = rawID, normalizedID
	snapshot.Parser = &previewmodel.Parser{ParserID: parserID, ParserVersion: parserVersion, ConfigDigest: hex.EncodeToString(configDigest[:])}
	for _, kind := range previewmodel.ReceiptTypes {
		ref := request.ReceiptRefs[kind]
		id, parseErr := uuid.Parse(string(ref))
		if parseErr != nil {
			return binding, parseErr
		}
		var recorded time.Time
		if err := s.db.QueryRow(ctx, `SELECT completed_at FROM context.activity_receipt WHERE id=$1::uuid AND status='success'`, id).Scan(&recorded); err != nil {
			return binding, fmt.Errorf("resolve %s receipt: %w", kind, err)
		}
		snapshot.Receipts = append(snapshot.Receipts, previewmodel.Receipt{ReceiptType: kind, ReceiptRef: string(ref), Status: "completed", RecordedAt: recorded})
	}
	rows, err := s.db.Query(ctx, `SELECT id, record_ordinal, occurred_at, normalized_payload FROM context.normalized_record_identity WHERE normalized_generation_id=$1::uuid AND record_type='message' ORDER BY record_ordinal`, normalizedID)
	if err != nil {
		return binding, err
	}
	defer rows.Close()
	participantsByID := map[string]previewmodel.Participant{}
	var messages []previewmodel.Message
	for rows.Next() {
		var recordID uuid.UUID
		var ordinal int64
		var sentAt *time.Time
		var rawJSON []byte
		if err := rows.Scan(&recordID, &ordinal, &sentAt, &rawJSON); err != nil {
			return binding, err
		}
		var payload normalizedPreviewPayload
		if err := json.Unmarshal(rawJSON, &payload); err != nil {
			return binding, err
		}
		message := previewmodel.Message{MessageID: recordID.String(), Ordinal: ordinal, SentAt: sentAt, Body: payload.Content.Body, SourceLocatorRef: "context.normalized_record_identity/" + recordID.String()}
		for _, p := range payload.Participants {
			digest := sha256.Sum256([]byte(p.Identifier))
			participantID := hex.EncodeToString(digest[:16])
			display := p.DisplayName
			if strings.TrimSpace(display) == "" {
				display = p.Identifier
			}
			address := p.Identifier
			participantsByID[participantID] = previewmodel.Participant{ParticipantID: participantID, DisplayName: display, CanonicalAddress: &address}
			message.ParticipantIDs = append(message.ParticipantIDs, participantID)
			if p.Role == "sender" {
				id := participantID
				message.SenderParticipantID = &id
			}
		}
		attachmentRows, queryErr := s.db.Query(ctx, `SELECT raw.id, COALESCE(raw.native_metadata->'attachments','[]'::jsonb) FROM context.normalization_lineage lineage JOIN context.raw_record_identity raw ON raw.id=lineage.raw_record_id WHERE lineage.normalized_record_id=$1::uuid ORDER BY raw.record_ordinal`, recordID)
		if queryErr != nil {
			return binding, queryErr
		}
		for attachmentRows.Next() {
			var rawRecordID uuid.UUID
			var attachmentJSON []byte
			if err := attachmentRows.Scan(&rawRecordID, &attachmentJSON); err != nil {
				attachmentRows.Close()
				return binding, err
			}
			var metadata []previewAttachmentMetadata
			if err := json.Unmarshal(attachmentJSON, &metadata); err != nil {
				attachmentRows.Close()
				return binding, err
			}
			for _, attachment := range metadata {
				id := fmt.Sprintf("%s:%d", rawRecordID, attachment.AttachmentOrdinal)
				projected := previewmodel.Attachment{AttachmentID: id, SourceLocatorRef: "context.raw_record_identity/" + rawRecordID.String() + "/attachment/" + fmt.Sprint(attachment.AttachmentOrdinal)}
				if value, ok := attachment.NativeMetadata["original_name"].(string); ok && value != "" {
					projected.Filename = &value
				}
				if value, ok := attachment.NativeMetadata["mime"].(string); ok && value != "" {
					projected.MediaType = &value
				}
				if value, ok := attachment.NativeMetadata["sha256"].(string); ok && previewmodel.ValidDigest(value) {
					projected.SHA256 = &value
				}
				if value, ok := attachment.NativeMetadata["byte_count"].(float64); ok && value >= 0 {
					size := int64(value)
					projected.ByteLength = &size
				}
				message.Attachments = append(message.Attachments, projected)
			}
		}
		if err := attachmentRows.Err(); err != nil {
			attachmentRows.Close()
			return binding, err
		}
		attachmentRows.Close()
		messages = append(messages, message)
	}
	if err := rows.Err(); err != nil {
		return binding, err
	}
	participants := make([]previewmodel.Participant, 0, len(participantsByID))
	for _, p := range participantsByID {
		participants = append(participants, p)
	}
	sort.Slice(participants, func(i, j int) bool { return participants[i].ParticipantID < participants[j].ParticipantID })
	digestInput, _ := json.Marshal(struct {
		Parser       *previewmodel.Parser
		Receipts     []previewmodel.Receipt
		Participants []previewmodel.Participant
		Messages     []previewmodel.Message
	}{snapshot.Parser, snapshot.Receipts, participants, messages})
	previewDigest := sha256.Sum256(digestInput)
	snapshot.PreviewDigest = hex.EncodeToString(previewDigest[:])
	count := len(messages)
	// Event IDs are allocated while the binding row is locked inside
	// PublishProjection. This keeps retries and concurrent publishers contiguous.
	events := []previewmodel.Event{{EventType: "messages_available", OccurredAt: s.clock(), PreviewHandle: binding.Handle, Phase: string(proffer.PhaseAwaitingDecision), MessageCount: &count}, {EventType: "phase_changed", OccurredAt: s.clock(), PreviewHandle: binding.Handle, Phase: string(proffer.PhaseAwaitingDecision)}}
	if err := s.PublishProjection(ctx, binding.Handle, snapshot, participants, messages, events); err != nil {
		return binding, err
	}
	return s.Binding(ctx, binding.Handle)
}

func (s *ProfferPreviewStore) bindingByRequest(ctx context.Context, requestID string) (previewmodel.Binding, error) {
	var handle string
	if err := s.db.QueryRow(ctx, `SELECT preview_handle FROM context.proffer_preview_binding WHERE request_id=$1`, requestID).Scan(&handle); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return previewmodel.Binding{}, previewmodel.ErrNotFound
		}
		return previewmodel.Binding{}, err
	}
	return s.Binding(ctx, handle)
}

func NewProfferPreviewStore(db DB, entropy io.Reader) (*ProfferPreviewStore, error) {
	if db == nil {
		return nil, errors.New("postgres Proffer preview store: database is required")
	}
	if entropy == nil {
		entropy = rand.Reader
	}
	return &ProfferPreviewStore{db: db, entropy: entropy, clock: func() time.Time { return time.Now().UTC() }}, nil
}

func (s *ProfferPreviewStore) Create(ctx context.Context, binding previewmodel.Binding) (previewmodel.Binding, error) {
	if strings.TrimSpace(binding.RequestID) == "" || strings.TrimSpace(string(binding.SourceRef)) == "" || strings.TrimSpace(binding.WorkflowID) == "" || strings.TrimSpace(binding.RunID) == "" || strings.TrimSpace(string(binding.ParserOptionsRef)) == "" {
		return previewmodel.Binding{}, errors.New("postgres Proffer preview binding is incomplete")
	}
	for attempt := 0; attempt < 4; attempt++ {
		raw := make([]byte, 24)
		if _, err := io.ReadFull(s.entropy, raw); err != nil {
			return previewmodel.Binding{}, fmt.Errorf("generate preview handle: %w", err)
		}
		binding.Handle = base64.RawURLEncoding.EncodeToString(raw)
		tx, err := s.db.BeginTx(ctx, pgx.TxOptions{})
		if err != nil {
			return previewmodel.Binding{}, fmt.Errorf("begin preview binding: %w", err)
		}
		rollback := func() { cleanup, cancel := boundedCleanup(ctx); defer cancel(); _ = tx.Rollback(cleanup) }
		result, err := tx.Exec(ctx, `
			INSERT INTO context.proffer_preview_binding
			    (preview_handle, request_id, source_ref, workflow_id, run_id, parser_options_ref)
			VALUES ($1, $2, $3, $4, $5, $6)
			ON CONFLICT DO NOTHING`, binding.Handle, binding.RequestID, binding.SourceRef,
			binding.WorkflowID, binding.RunID, binding.ParserOptionsRef)
		if err != nil {
			rollback()
			return previewmodel.Binding{}, fmt.Errorf("insert preview binding: %w", err)
		}
		if result.RowsAffected() == 1 {
			_, err = tx.Exec(ctx, `
				INSERT INTO context.proffer_preview_event
				    (preview_handle, event_id, event_type, occurred_at, phase)
				VALUES ($1, 0, 'phase_changed', $2, 'starting')`, binding.Handle, s.clock())
			if err != nil {
				rollback()
				return previewmodel.Binding{}, fmt.Errorf("insert initial preview event: %w", err)
			}
			if err := tx.Commit(ctx); err != nil {
				rollback()
				return previewmodel.Binding{}, fmt.Errorf("commit preview binding: %w", err)
			}
			return binding, nil
		}

		var existing previewmodel.Binding
		err = tx.QueryRow(ctx, `
			SELECT preview_handle, request_id, source_ref, workflow_id, run_id, parser_options_ref
			FROM context.proffer_preview_binding WHERE request_id = $1`, binding.RequestID).Scan(
			&existing.Handle, &existing.RequestID, &existing.SourceRef, &existing.WorkflowID,
			&existing.RunID, &existing.ParserOptionsRef)
		rollback()
		if err == nil {
			if existing.SourceRef != binding.SourceRef || existing.WorkflowID != binding.WorkflowID || existing.RunID != binding.RunID || existing.ParserOptionsRef != binding.ParserOptionsRef {
				return previewmodel.Binding{}, errors.New("request_id is already bound to different Proffer coordinates")
			}
			return existing, nil
		}
		if !errors.Is(err, pgx.ErrNoRows) {
			return previewmodel.Binding{}, fmt.Errorf("resolve preview binding conflict: %w", err)
		}
	}
	return previewmodel.Binding{}, errors.New("generate unique durable preview handle")
}

func (s *ProfferPreviewStore) Binding(ctx context.Context, handle string) (previewmodel.Binding, error) {
	var binding previewmodel.Binding
	var sourceVersion, rawGeneration, normalizedGeneration *uuid.UUID
	err := s.db.QueryRow(ctx, `
		SELECT binding.preview_handle, binding.request_id, binding.source_ref,
		       binding.workflow_id, binding.run_id,
		       COALESCE(decision.selection_ref, ''),
		       COALESCE(decision.parser_options_ref, binding.parser_options_ref),
		       snapshot.source_version_id, snapshot.raw_generation_id,
		       snapshot.normalized_generation_id
		FROM context.proffer_preview_binding binding
		LEFT JOIN LATERAL (
		    SELECT selection_ref, parser_options_ref
		    FROM context.proffer_preview_decision
		    WHERE preview_handle = binding.preview_handle
		    ORDER BY recorded_at DESC, id DESC LIMIT 1
		) decision ON true
		LEFT JOIN LATERAL (
		    SELECT source_version_id, raw_generation_id, normalized_generation_id
		    FROM context.proffer_preview_snapshot
		    WHERE preview_handle = binding.preview_handle
		    ORDER BY snapshot_seq DESC LIMIT 1
		) snapshot ON true
		WHERE binding.preview_handle = $1`, handle).Scan(
		&binding.Handle, &binding.RequestID, &binding.SourceRef, &binding.WorkflowID, &binding.RunID,
		&binding.SelectionRef, &binding.ParserOptionsRef, &sourceVersion, &rawGeneration, &normalizedGeneration)
	if errors.Is(err, pgx.ErrNoRows) {
		return previewmodel.Binding{}, previewmodel.ErrNotFound
	}
	if err != nil {
		return previewmodel.Binding{}, fmt.Errorf("read preview binding: %w", err)
	}
	if sourceVersion != nil {
		binding.SourceVersionID = *sourceVersion
	}
	if rawGeneration != nil {
		binding.RawGenerationID = *rawGeneration
	}
	if normalizedGeneration != nil {
		binding.NormalizedGenerationID = *normalizedGeneration
	}
	return binding, nil
}

func (s *ProfferPreviewStore) Snapshot(ctx context.Context, handle string) (previewmodel.Snapshot, error) {
	var snapshot previewmodel.Snapshot
	var seq int64
	var parserID, parserVersion, parserDigest string
	err := s.db.QueryRow(ctx, `
		SELECT snapshot.snapshot_seq, snapshot.phase, binding.request_id,
		       snapshot.source_version_id, snapshot.raw_generation_id,
		       snapshot.normalized_generation_id,
		       COALESCE(snapshot.parser_id, ''), COALESCE(snapshot.parser_version, ''),
		       COALESCE(encode(snapshot.parser_config_digest, 'hex'), ''),
		       encode(snapshot.preview_digest, 'hex'), snapshot.reason
		FROM context.proffer_preview_snapshot snapshot
		JOIN context.proffer_preview_binding binding USING (preview_handle)
		WHERE snapshot.preview_handle = $1
		ORDER BY snapshot.snapshot_seq DESC LIMIT 1`, handle).Scan(
		&seq, &snapshot.Phase, &snapshot.Correlation.RequestID,
		&snapshot.Correlation.SourceVersionID, &snapshot.Correlation.RawGenerationID,
		&snapshot.Correlation.NormalizedGenerationID, &parserID, &parserVersion,
		&parserDigest, &snapshot.PreviewDigest, &snapshot.Reason)
	if errors.Is(err, pgx.ErrNoRows) {
		if _, bindingErr := s.Binding(ctx, handle); errors.Is(bindingErr, previewmodel.ErrNotFound) {
			return previewmodel.Snapshot{}, bindingErr
		}
		return previewmodel.Snapshot{}, previewmodel.ErrNotReady
	}
	if err != nil {
		return previewmodel.Snapshot{}, fmt.Errorf("read preview snapshot: %w", err)
	}
	snapshot.PreviewHandle = handle
	if parserID != "" {
		snapshot.Parser = &previewmodel.Parser{ParserID: parserID, ParserVersion: parserVersion, ConfigDigest: parserDigest}
	}
	rows, err := s.db.Query(ctx, `
		SELECT receipt_type, receipt_ref, status, COALESCE(encode(digest, 'hex'), ''), recorded_at
		FROM context.proffer_preview_receipt
		WHERE preview_handle = $1 AND snapshot_seq = $2
		ORDER BY receipt_type`, handle, seq)
	if err != nil {
		return previewmodel.Snapshot{}, fmt.Errorf("read preview receipts: %w", err)
	}
	defer rows.Close()
	for rows.Next() {
		var receipt previewmodel.Receipt
		if err := rows.Scan(&receipt.ReceiptType, &receipt.ReceiptRef, &receipt.Status, &receipt.Digest, &receipt.RecordedAt); err != nil {
			return previewmodel.Snapshot{}, fmt.Errorf("scan preview receipt: %w", err)
		}
		snapshot.Receipts = append(snapshot.Receipts, receipt)
	}
	if err := rows.Err(); err != nil {
		return previewmodel.Snapshot{}, fmt.Errorf("iterate preview receipts: %w", err)
	}
	return snapshot, nil
}

func (s *ProfferPreviewStore) Page(ctx context.Context, handle string, offset, limit int) (previewmodel.Page, error) {
	if offset < 0 || limit < 1 || limit > 250 {
		return previewmodel.Page{}, errors.New("preview page bounds are invalid")
	}
	var seq int64
	if err := s.db.QueryRow(ctx, `SELECT snapshot_seq FROM context.proffer_preview_snapshot WHERE preview_handle = $1 ORDER BY snapshot_seq DESC LIMIT 1`, handle).Scan(&seq); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			if _, bindingErr := s.Binding(ctx, handle); errors.Is(bindingErr, previewmodel.ErrNotFound) {
				return previewmodel.Page{}, bindingErr
			}
			return previewmodel.Page{}, previewmodel.ErrNotReady
		}
		return previewmodel.Page{}, err
	}
	page := previewmodel.Page{}
	participantRows, err := s.db.Query(ctx, `SELECT participant_id, display_name, canonical_address FROM context.proffer_preview_participant WHERE preview_handle = $1 AND snapshot_seq = $2 ORDER BY participant_id`, handle, seq)
	if err != nil {
		return page, err
	}
	for participantRows.Next() {
		var participant previewmodel.Participant
		if err := participantRows.Scan(&participant.ParticipantID, &participant.DisplayName, &participant.CanonicalAddress); err != nil {
			participantRows.Close()
			return page, err
		}
		page.Participants = append(page.Participants, participant)
	}
	if err := participantRows.Err(); err != nil {
		participantRows.Close()
		return page, err
	}
	participantRows.Close()

	messageRows, err := s.db.Query(ctx, `
		SELECT message_id, ordinal, sent_at, sender_participant_id, body,
		       participant_ids, source_locator_ref
		FROM context.proffer_preview_message
		WHERE preview_handle = $1 AND snapshot_seq = $2
		ORDER BY ordinal, message_id OFFSET $3 LIMIT $4`, handle, seq, offset, limit+1)
	if err != nil {
		return page, err
	}
	for messageRows.Next() {
		var message previewmodel.Message
		if err := messageRows.Scan(&message.MessageID, &message.Ordinal, &message.SentAt,
			&message.SenderParticipantID, &message.Body, &message.ParticipantIDs,
			&message.SourceLocatorRef); err != nil {
			messageRows.Close()
			return page, err
		}
		page.Messages = append(page.Messages, message)
	}
	if err := messageRows.Err(); err != nil {
		messageRows.Close()
		return page, err
	}
	messageRows.Close()
	if len(page.Messages) > limit {
		next := offset + limit
		page.NextOffset = &next
		page.Messages = page.Messages[:limit]
	}
	if len(page.Messages) == 0 {
		return page, nil
	}
	messageIDs := make([]string, len(page.Messages))
	byID := make(map[string]*previewmodel.Message, len(page.Messages))
	for index := range page.Messages {
		messageIDs[index] = page.Messages[index].MessageID
		byID[messageIDs[index]] = &page.Messages[index]
	}
	attachmentRows, err := s.db.Query(ctx, `
		SELECT message_id, attachment_id, filename, media_type, byte_length,
		       CASE WHEN sha256 IS NULL THEN NULL ELSE encode(sha256, 'hex') END,
		       source_locator_ref
		FROM context.proffer_preview_attachment
		WHERE preview_handle = $1 AND snapshot_seq = $2 AND message_id = ANY($3::text[])
		ORDER BY message_id, attachment_id`, handle, seq, messageIDs)
	if err != nil {
		return page, err
	}
	defer attachmentRows.Close()
	for attachmentRows.Next() {
		var messageID string
		var attachment previewmodel.Attachment
		if err := attachmentRows.Scan(&messageID, &attachment.AttachmentID, &attachment.Filename,
			&attachment.MediaType, &attachment.ByteLength, &attachment.SHA256,
			&attachment.SourceLocatorRef); err != nil {
			return page, err
		}
		if message := byID[messageID]; message != nil {
			message.Attachments = append(message.Attachments, attachment)
		}
	}
	return page, attachmentRows.Err()
}

func (s *ProfferPreviewStore) EventsAfter(ctx context.Context, handle string, after int64) ([]previewmodel.Event, error) {
	var first, latest *int64
	if err := s.db.QueryRow(ctx, `SELECT min(event_id), max(event_id) FROM context.proffer_preview_event WHERE preview_handle = $1`, handle).Scan(&first, &latest); err != nil {
		return nil, err
	}
	if latest == nil {
		if _, err := s.Binding(ctx, handle); err != nil {
			return nil, err
		}
		return nil, previewmodel.ErrEventGap
	}
	if after > *latest || (after >= 0 && after+1 < *first) {
		return nil, previewmodel.ErrEventGap
	}
	rows, err := s.db.Query(ctx, `
		SELECT event_id, event_type, occurred_at, preview_handle, phase,
		       receipt_ref, message_count, detail
		FROM context.proffer_preview_event
		WHERE preview_handle = $1 AND event_id > $2 ORDER BY event_id`, handle, after)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var events []previewmodel.Event
	for rows.Next() {
		var event previewmodel.Event
		if err := rows.Scan(&event.EventID, &event.EventType, &event.OccurredAt,
			&event.PreviewHandle, &event.Phase, &event.ReceiptRef,
			&event.MessageCount, &event.Detail); err != nil {
			return nil, err
		}
		events = append(events, event)
	}
	return events, rows.Err()
}

func (s *ProfferPreviewStore) RecordDecision(ctx context.Context, handle string, approved bool, reason, actor string, selection, options proffer.Ref) error {
	if strings.TrimSpace(actor) == "" || strings.TrimSpace(string(selection)) == "" || strings.TrimSpace(string(options)) == "" {
		return errors.New("durable preview decision requires actor, selection, and options refs")
	}
	key := decisionKey(handle, approved, reason, actor, selection, options)
	tx, err := s.db.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return err
	}
	rollback := func() { cleanup, cancel := boundedCleanup(ctx); defer cancel(); _ = tx.Rollback(cleanup) }
	if err := tx.QueryRow(ctx, `SELECT 1 FROM context.proffer_preview_binding WHERE preview_handle = $1 FOR UPDATE`, handle).Scan(new(int)); err != nil {
		rollback()
		if errors.Is(err, pgx.ErrNoRows) {
			return previewmodel.ErrNotFound
		}
		return err
	}
	decisionID, err := uuid.NewV7()
	if err != nil {
		rollback()
		return err
	}
	recordedAt := s.clock()
	result, err := tx.Exec(ctx, `
		INSERT INTO context.proffer_preview_decision
		    (id, preview_handle, decision_key, approved, reason, actor_subject_uid,
		     selection_ref, parser_options_ref, recorded_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
		ON CONFLICT (preview_handle, decision_key) DO NOTHING`, decisionID, handle, key[:],
		approved, reason, actor, selection, options, recordedAt)
	if err != nil {
		rollback()
		return fmt.Errorf("record preview decision: %w", err)
	}
	if result.RowsAffected() == 1 {
		var eventID, successorSeq int64
		if err := tx.QueryRow(ctx, `SELECT COALESCE(max(event_id) + 1, 0) FROM context.proffer_preview_event WHERE preview_handle = $1`, handle).Scan(&eventID); err != nil {
			rollback()
			return err
		}
		phase := "rejected"
		if approved {
			phase = "approved"
		}
		if err := tx.QueryRow(ctx, `
			INSERT INTO context.proffer_preview_snapshot
			    (preview_handle, snapshot_seq, phase, source_version_id, raw_generation_id,
			     normalized_generation_id, parser_id, parser_version, parser_config_digest,
			     preview_digest, reason, recorded_at)
			SELECT preview_handle, snapshot_seq + 1, $2, source_version_id, raw_generation_id,
			       normalized_generation_id, parser_id, parser_version, parser_config_digest,
			       preview_digest, $3, $4
			FROM context.proffer_preview_snapshot
			WHERE preview_handle = $1
			ORDER BY snapshot_seq DESC LIMIT 1
			RETURNING snapshot_seq`, handle, phase, strings.TrimSpace(reason), recordedAt).Scan(&successorSeq); err != nil {
			rollback()
			if errors.Is(err, pgx.ErrNoRows) {
				return previewmodel.ErrNotReady
			}
			return fmt.Errorf("append preview decision snapshot: %w", err)
		}
		if _, err := tx.Exec(ctx, `
			INSERT INTO context.proffer_preview_receipt
			    (preview_handle, snapshot_seq, receipt_type, receipt_ref, status, digest, recorded_at)
			SELECT preview_handle, $2, receipt_type, receipt_ref, status, digest, recorded_at
			FROM context.proffer_preview_receipt
			WHERE preview_handle = $1 AND snapshot_seq = $2 - 1`, handle, successorSeq); err != nil {
			rollback()
			return fmt.Errorf("copy preview decision receipts: %w", err)
		}
		if _, err := tx.Exec(ctx, `
			INSERT INTO context.proffer_preview_participant
			    (preview_handle, snapshot_seq, participant_id, display_name, canonical_address)
			SELECT preview_handle, $2, participant_id, display_name, canonical_address
			FROM context.proffer_preview_participant
			WHERE preview_handle = $1 AND snapshot_seq = $2 - 1`, handle, successorSeq); err != nil {
			rollback()
			return fmt.Errorf("copy preview decision participants: %w", err)
		}
		if _, err := tx.Exec(ctx, `
			INSERT INTO context.proffer_preview_message
			    (preview_handle, snapshot_seq, message_id, ordinal, sent_at,
			     sender_participant_id, body, participant_ids, source_locator_ref)
			SELECT preview_handle, $2, message_id, ordinal, sent_at,
			       sender_participant_id, body, participant_ids, source_locator_ref
			FROM context.proffer_preview_message
			WHERE preview_handle = $1 AND snapshot_seq = $2 - 1`, handle, successorSeq); err != nil {
			rollback()
			return fmt.Errorf("copy preview decision messages: %w", err)
		}
		if _, err := tx.Exec(ctx, `
			INSERT INTO context.proffer_preview_attachment
			    (preview_handle, snapshot_seq, message_id, attachment_id, filename,
			     media_type, byte_length, sha256, source_locator_ref)
			SELECT preview_handle, $2, message_id, attachment_id, filename,
			       media_type, byte_length, sha256, source_locator_ref
			FROM context.proffer_preview_attachment
			WHERE preview_handle = $1 AND snapshot_seq = $2 - 1`, handle, successorSeq); err != nil {
			rollback()
			return fmt.Errorf("copy preview decision attachments: %w", err)
		}
		if _, err := tx.Exec(ctx, `
			INSERT INTO context.proffer_preview_event
			    (preview_handle, event_id, event_type, occurred_at, phase, detail)
			VALUES ($1, $2, 'decision_recorded', $3, $4, $5)`,
			handle, eventID, recordedAt, phase, strings.TrimSpace(actor+": "+reason)); err != nil {
			rollback()
			return err
		}
	}
	if err := tx.Commit(ctx); err != nil {
		rollback()
		return err
	}
	return nil
}

// PublishProjection atomically appends a new validated projection generation.
// It is the intended projection-activity entrypoint and is never browser-facing;
// wiring that activity is a separately owned orchestration change.
func (s *ProfferPreviewStore) PublishProjection(ctx context.Context, handle string, snapshot previewmodel.Snapshot, participants []previewmodel.Participant, messages []previewmodel.Message, events []previewmodel.Event) error {
	if err := previewmodel.Validate(handle, snapshot, participants, messages); err != nil {
		return err
	}
	tx, err := s.db.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return err
	}
	rollback := func() { cleanup, cancel := boundedCleanup(ctx); defer cancel(); _ = tx.Rollback(cleanup) }
	var requestID string
	var seq int64
	if err := tx.QueryRow(ctx, `SELECT request_id FROM context.proffer_preview_binding WHERE preview_handle = $1 FOR UPDATE`, handle).Scan(&requestID); err != nil {
		rollback()
		if errors.Is(err, pgx.ErrNoRows) {
			return previewmodel.ErrNotFound
		}
		return err
	}
	if requestID != snapshot.Correlation.RequestID {
		rollback()
		return errors.New("preview projection request correlation mismatch")
	}
	var existingNormalizedID uuid.UUID
	var existingDigest []byte
	existingErr := tx.QueryRow(ctx, `SELECT normalized_generation_id, preview_digest
		FROM context.proffer_preview_snapshot WHERE preview_handle=$1
		ORDER BY snapshot_seq DESC LIMIT 1`, handle).Scan(&existingNormalizedID, &existingDigest)
	if existingErr == nil && existingNormalizedID == snapshot.Correlation.NormalizedGenerationID {
		wanted, _ := hex.DecodeString(snapshot.PreviewDigest)
		rollback()
		if string(existingDigest) == string(wanted) {
			return nil
		}
		return errors.New("preview projection retry changed digest for the same normalized generation")
	}
	if existingErr != nil && !errors.Is(existingErr, pgx.ErrNoRows) {
		rollback()
		return existingErr
	}
	if err := tx.QueryRow(ctx, `SELECT COALESCE(max(snapshot_seq) + 1, 0) FROM context.proffer_preview_snapshot WHERE preview_handle = $1`, handle).Scan(&seq); err != nil {
		rollback()
		return err
	}
	previewDigest, _ := hex.DecodeString(snapshot.PreviewDigest)
	var parserID, parserVersion any
	var parserDigest []byte
	if snapshot.Parser != nil {
		parserID, parserVersion = snapshot.Parser.ParserID, snapshot.Parser.ParserVersion
		parserDigest, _ = hex.DecodeString(snapshot.Parser.ConfigDigest)
	}
	if _, err := tx.Exec(ctx, `INSERT INTO context.proffer_preview_snapshot
		(preview_handle, snapshot_seq, phase, source_version_id, raw_generation_id,
		 normalized_generation_id, parser_id, parser_version, parser_config_digest,
		 preview_digest, reason) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)`,
		handle, seq, snapshot.Phase, snapshot.Correlation.SourceVersionID,
		snapshot.Correlation.RawGenerationID, snapshot.Correlation.NormalizedGenerationID,
		parserID, parserVersion, parserDigest, previewDigest, snapshot.Reason); err != nil {
		rollback()
		return err
	}
	for _, receipt := range snapshot.Receipts {
		var digest []byte
		if receipt.Digest != "" {
			digest, _ = hex.DecodeString(receipt.Digest)
		}
		if _, err := tx.Exec(ctx, `INSERT INTO context.proffer_preview_receipt
			(preview_handle,snapshot_seq,receipt_type,receipt_ref,status,digest,recorded_at)
			VALUES ($1,$2,$3,$4,$5,$6,$7)`, handle, seq, receipt.ReceiptType,
			receipt.ReceiptRef, receipt.Status, digest, receipt.RecordedAt); err != nil {
			rollback()
			return err
		}
	}
	for _, participant := range participants {
		if _, err := tx.Exec(ctx, `INSERT INTO context.proffer_preview_participant
			(preview_handle,snapshot_seq,participant_id,display_name,canonical_address)
			VALUES ($1,$2,$3,$4,$5)`, handle, seq, participant.ParticipantID,
			participant.DisplayName, participant.CanonicalAddress); err != nil {
			rollback()
			return err
		}
	}
	sort.SliceStable(messages, func(i, j int) bool { return messages[i].Ordinal < messages[j].Ordinal })
	for _, message := range messages {
		if _, err := tx.Exec(ctx, `INSERT INTO context.proffer_preview_message
			(preview_handle,snapshot_seq,message_id,ordinal,sent_at,sender_participant_id,
			 body,participant_ids,source_locator_ref) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)`,
			handle, seq, message.MessageID, message.Ordinal, message.SentAt,
			message.SenderParticipantID, message.Body, message.ParticipantIDs,
			message.SourceLocatorRef); err != nil {
			rollback()
			return err
		}
		for _, attachment := range message.Attachments {
			var digest []byte
			if attachment.SHA256 != nil {
				digest, _ = hex.DecodeString(*attachment.SHA256)
			}
			if _, err := tx.Exec(ctx, `INSERT INTO context.proffer_preview_attachment
				(preview_handle,snapshot_seq,message_id,attachment_id,filename,media_type,
				 byte_length,sha256,source_locator_ref) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)`,
				handle, seq, message.MessageID, attachment.AttachmentID, attachment.Filename,
				attachment.MediaType, attachment.ByteLength, digest,
				attachment.SourceLocatorRef); err != nil {
				rollback()
				return err
			}
		}
	}
	var nextEventID int64
	if err := tx.QueryRow(ctx, `SELECT COALESCE(max(event_id) + 1, 0) FROM context.proffer_preview_event WHERE preview_handle=$1`, handle).Scan(&nextEventID); err != nil {
		rollback()
		return err
	}
	for index, event := range events {
		eventID := nextEventID + int64(index)
		if _, err := tx.Exec(ctx, `INSERT INTO context.proffer_preview_event
			(preview_handle,event_id,event_type,occurred_at,phase,receipt_ref,message_count,detail)
			VALUES ($1,$2,$3,$4,$5,$6,$7,$8)`, handle, eventID, event.EventType,
			event.OccurredAt, event.Phase, event.ReceiptRef, event.MessageCount,
			event.Detail); err != nil {
			rollback()
			return err
		}
	}
	if err := tx.Commit(ctx); err != nil {
		rollback()
		return err
	}
	return nil
}

func decisionKey(handle string, approved bool, reason, actor string, selection, options proffer.Ref) [sha256.Size]byte {
	return sha256.Sum256([]byte(fmt.Sprintf("%s\x00%t\x00%s\x00%s\x00%s\x00%s", handle, approved, reason, actor, selection, options)))
}

var _ previewmodel.Store = (*ProfferPreviewStore)(nil)
