package postgres

import (
	"bufio"
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/json"
	"encoding/xml"
	"errors"
	"fmt"
	"io"
	"regexp"
	"strings"
	"time"

	"github.com/Cursedpotential/probata/engine/activities"
	"github.com/Cursedpotential/probata/engine/proffer"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

const handlerSignatureReadLimit int64 = 8 << 20

var transcriptSignatureLine = regexp.MustCompile(`^\[\d{4}-\d{2}-\d{2} \d{1,2}:\d{2}(?::\d{2})?\s*(?:AM|PM)?\]\s*[^:]+:\s*$`)
var imessageSignatureLine = regexp.MustCompile(`(?i)^(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]* \d{1,2}, \d{4}\s+\d{1,2}:\d{2}(?::\d{2})?\s*[AP]M(?:\s*\([^\r\n]*\))?\s*$`)

// HandlerSelectionStore is the durable, content-backed implementation of the
// recommendation and validation Activities and the authenticated HTTP
// decision writer. Source bytes are inspected only through the retained
// original reference; declared format and filename are not detection inputs.
type HandlerSelectionStore struct {
	db    DB
	open  *Repository
	clock func() time.Time
}

func NewHandlerSelectionStore(db DB, open ObjectOpener) (*HandlerSelectionStore, error) {
	if db == nil {
		return nil, errors.New("postgres handler selection store: database is required")
	}
	repository, err := NewRepository(db, open)
	if err != nil {
		return nil, err
	}
	return &HandlerSelectionStore{db: db, open: repository, clock: func() time.Time { return time.Now().UTC() }}, nil
}

// RecommendHandler derives one bounded candidate set from retained content and
// persists every reference returned to Temporal in one transaction.
func (s *HandlerSelectionStore) RecommendHandler(ctx context.Context, req proffer.StageRequest, attempt int32) (proffer.HandlerRecommendationResult, error) {
	sourceID, originalID, err := handlerRequestIDs(req)
	if err != nil || attempt < 1 {
		return proffer.HandlerRecommendationResult{}, errors.New("handler recommendation requires valid source/original references and attempt")
	}
	var contentDigest []byte
	err = s.db.QueryRow(ctx, `
		SELECT object.content_sha256
		FROM context.source_version source
		JOIN context.source_version_object link ON link.source_version_id=source.id
		JOIN context.retained_object object ON object.id=link.object_id
		WHERE source.id=$1::uuid AND source.status='retained'
		  AND object.id=$2::uuid AND link.object_role IN ('original','derived_reference')`, sourceID, originalID).Scan(&contentDigest)
	if err != nil {
		return proffer.HandlerRecommendationResult{}, fmt.Errorf("load retained content identity for recommendation: %w", err)
	}
	if len(contentDigest) != sha256.Size {
		return proffer.HandlerRecommendationResult{}, errors.New("retained content identity has an invalid sha256")
	}
	reader, err := s.open.OpenOriginal(ctx, req.Refs["original"])
	if err != nil {
		return proffer.HandlerRecommendationResult{}, err
	}
	defer reader.Close()
	head, err := io.ReadAll(io.LimitReader(reader, handlerSignatureReadLimit+1))
	if err != nil {
		return proffer.HandlerRecommendationResult{}, fmt.Errorf("read retained content signature: %w", err)
	}
	if int64(len(head)) > handlerSignatureReadLimit {
		head = head[:handlerSignatureReadLimit]
	}
	detected, signatureKind, err := detectHandlerContent(head)
	if err != nil {
		return proffer.HandlerRecommendationResult{}, err
	}
	return s.persistRecommendation(ctx, req, sourceID, originalID, contentDigest, detected, signatureKind, attempt)
}

func handlerRequestIDs(req proffer.StageRequest) (uuid.UUID, uuid.UUID, error) {
	sourceID, sourceErr := uuid.Parse(string(req.SourceVersionRef))
	originalID, originalErr := uuid.Parse(string(req.Refs["original"]))
	if sourceErr != nil || originalErr != nil || strings.TrimSpace(req.RequestID) == "" {
		return uuid.Nil, uuid.Nil, errors.New("invalid handler recommendation identity")
	}
	return sourceID, originalID, nil
}

func detectHandlerContent(head []byte) (format, signatureKind string, err error) {
	trimmed := bytes.TrimSpace(bytes.TrimPrefix(head, []byte{0xef, 0xbb, 0xbf}))
	if len(trimmed) == 0 {
		return "", "", errors.New("retained source is empty")
	}
	if trimmed[0] == '<' {
		decoder := xml.NewDecoder(bytes.NewReader(trimmed))
		for {
			token, tokenErr := decoder.Token()
			if tokenErr != nil {
				return "", "", fmt.Errorf("inspect retained XML root: %w", tokenErr)
			}
			if start, ok := token.(xml.StartElement); ok {
				switch strings.ToLower(start.Name.Local) {
				case "smses":
					return "smsbackuprestore_xml", "sms_backup_restore_smses_root_v1", nil
				case "calls":
					return "", "", errors.New("calls XML is not an SMS Backup & Restore message export")
				default:
					return "", "", fmt.Errorf("unsupported retained XML root %q", start.Name.Local)
				}
			}
		}
	}
	if trimmed[0] == '[' {
		decoder := json.NewDecoder(bytes.NewReader(trimmed))
		opening, openingErr := decoder.Token()
		if openingErr == nil && opening == json.Delim('[') && decoder.More() {
			var conversation json.RawMessage
			var first map[string]json.RawMessage
			if decoder.Decode(&conversation) == nil && json.Unmarshal(conversation, &first) == nil && chatGPTConversationSignature(first) {
				return "chatgpt_official_json", "chatgpt_official_conversations_array_v1", nil
			}
		}
	}
	scanner := bufio.NewScanner(bytes.NewReader(trimmed))
	scanner.Buffer(make([]byte, 4096), 1<<20)
	lines := make([]string, 0, 64)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		lines = append(lines, line)
		if transcriptSignatureLine.MatchString(line) {
			return "messages_transcript", "bracketed_message_transcript_v1", nil
		}
	}
	if err := scanner.Err(); err != nil {
		return "", "", fmt.Errorf("inspect retained transcript signature: %w", err)
	}
	for index, line := range lines {
		if !imessageSignatureLine.MatchString(line) {
			continue
		}
		nonblank := 0
		for next := index + 1; next < len(lines) && next <= index+4; next++ {
			if lines[next] != "" {
				nonblank++
			}
		}
		if nonblank >= 2 {
			return "messages_transcript", "apple_messages_timestamp_sender_body_v1", nil
		}
	}
	return "", "", errors.New("retained content does not match a supported structured handler signature")
}

func chatGPTConversationSignature(first map[string]json.RawMessage) bool {
	if first["mapping"] == nil || (first["title"] == nil && first["conversation_id"] == nil && first["id"] == nil) {
		return false
	}
	var mapping map[string]struct {
		Message *struct {
			Author  map[string]json.RawMessage `json:"author"`
			Content map[string]json.RawMessage `json:"content"`
		} `json:"message"`
	}
	if json.Unmarshal(first["mapping"], &mapping) != nil {
		return false
	}
	for _, node := range mapping {
		if node.Message != nil && node.Message.Author != nil && node.Message.Content != nil {
			return true
		}
	}
	return false
}

func (s *HandlerSelectionStore) persistRecommendation(ctx context.Context, req proffer.StageRequest, sourceID, originalID uuid.UUID, digest []byte, detected, signatureKind string, attempt int32) (proffer.HandlerRecommendationResult, error) {
	tx, err := s.db.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return proffer.HandlerRecommendationResult{}, err
	}
	rollback := true
	defer func() {
		if rollback {
			cleanup, cancel := boundedCleanup(ctx)
			defer cancel()
			_ = tx.Rollback(cleanup)
		}
	}()
	key := "handler-recommendation:" + originalID.String() + ":" + fmt.Sprintf("%x", digest)
	executionID, err := parserEnsureExecution(ctx, tx, sourceID, req.RequestID, proffer.RecommendHandlerActivityName, key)
	if err != nil {
		return proffer.HandlerRecommendationResult{}, err
	}
	if prior, ok, err := loadRecommendationTx(ctx, tx, executionID); err != nil {
		return proffer.HandlerRecommendationResult{}, err
	} else if ok {
		if err = tx.Commit(ctx); err != nil {
			return proffer.HandlerRecommendationResult{}, err
		}
		rollback = false
		return prior, nil
	}
	signatureID, formatID, compatibilityID, recommendationID, receiptID := uuid.New(), uuid.New(), uuid.New(), uuid.New(), uuid.New()
	now := s.clock()
	candidate := proffer.HandlerCandidate{
		HandlerID: activities.StructuredELTParserID, HandlerVersion: activities.StructuredELTParserVersion,
		ExecutionPath: proffer.HandlerPathDuckDB, CompatibilityRef: proffer.Ref(compatibilityID.String()),
		Reason: "retained source content matches the pinned DuckDB structured extraction signature",
	}
	candidates, _ := json.Marshal([]proffer.HandlerCandidate{candidate})
	result := proffer.HandlerRecommendationResult{
		RecommendationRef: proffer.Ref(recommendationID.String()), ReceiptRef: proffer.Ref(receiptID.String()),
		DetectedFormat: detected, DetectedFormatRef: proffer.Ref(formatID.String()), SignatureRef: proffer.Ref(signatureID.String()), Recommended: candidate,
	}
	resultJSON, _ := json.Marshal(map[string]any{
		"ref_kind": "handler_recommendation", "ref_id": recommendationID.String(), "detected_format": detected,
		"detected_format_ref": formatID.String(), "signature_ref": signatureID.String(), "candidates": []proffer.HandlerCandidate{candidate},
	})
	if _, err = tx.Exec(ctx, `INSERT INTO context.handler_content_signature(id,source_version_id,original_object_id,signature_kind,content_sha256,created_at) VALUES($1,$2,$3,$4,$5,$6)`, signatureID, sourceID, originalID, signatureKind, digest, now); err != nil {
		return proffer.HandlerRecommendationResult{}, err
	}
	if _, err = tx.Exec(ctx, `INSERT INTO context.handler_detected_format(id,source_version_id,content_signature_id,format_id,created_at) VALUES($1,$2,$3,$4,$5)`, formatID, sourceID, signatureID, detected, now); err != nil {
		return proffer.HandlerRecommendationResult{}, err
	}
	if _, err = tx.Exec(ctx, `INSERT INTO context.handler_compatibility(id,detected_format_id,handler_id,handler_version,execution_path,reason,created_at) VALUES($1,$2,$3,$4,$5,$6,$7)`, compatibilityID, formatID, candidate.HandlerID, candidate.HandlerVersion, string(candidate.ExecutionPath), candidate.Reason, now); err != nil {
		return proffer.HandlerRecommendationResult{}, err
	}
	if _, err = tx.Exec(ctx, `INSERT INTO context.activity_receipt(id,activity_execution_id,attempt,status,started_at,completed_at,result_ref) VALUES($1,$2,$3,'success',$4,$4,$5)`, receiptID, executionID, attempt, now, resultJSON); err != nil {
		return proffer.HandlerRecommendationResult{}, err
	}
	if _, err = tx.Exec(ctx, `INSERT INTO context.handler_recommendation(id,source_version_id,original_object_id,content_signature_id,detected_format_id,activity_receipt_id,candidates,created_at) VALUES($1,$2,$3,$4,$5,$6,$7,$8)`, recommendationID, sourceID, originalID, signatureID, formatID, receiptID, candidates, now); err != nil {
		return proffer.HandlerRecommendationResult{}, err
	}
	if err = tx.Commit(ctx); err != nil {
		return proffer.HandlerRecommendationResult{}, err
	}
	rollback = false
	return result, nil
}

func loadRecommendationTx(ctx context.Context, tx pgx.Tx, executionID uuid.UUID) (proffer.HandlerRecommendationResult, bool, error) {
	var recommendationID, receiptID, formatID, signatureID uuid.UUID
	var detected string
	var candidatesJSON []byte
	err := tx.QueryRow(ctx, `
		SELECT recommendation.id,receipt.id,format.id,signature.id,format.format_id,recommendation.candidates
		FROM context.activity_receipt receipt
		JOIN context.handler_recommendation recommendation ON recommendation.activity_receipt_id=receipt.id
		JOIN context.handler_detected_format format ON format.id=recommendation.detected_format_id
		JOIN context.handler_content_signature signature ON signature.id=recommendation.content_signature_id
		WHERE receipt.activity_execution_id=$1 AND receipt.status='success' ORDER BY receipt.attempt LIMIT 1`, executionID).
		Scan(&recommendationID, &receiptID, &formatID, &signatureID, &detected, &candidatesJSON)
	if errors.Is(err, pgx.ErrNoRows) {
		return proffer.HandlerRecommendationResult{}, false, nil
	}
	if err != nil {
		return proffer.HandlerRecommendationResult{}, false, err
	}
	var candidates []proffer.HandlerCandidate
	if json.Unmarshal(candidatesJSON, &candidates) != nil || len(candidates) == 0 || len(candidates) > 4 {
		return proffer.HandlerRecommendationResult{}, false, errors.New("stored handler recommendation candidate set is invalid")
	}
	return proffer.HandlerRecommendationResult{
		RecommendationRef: proffer.Ref(recommendationID.String()), ReceiptRef: proffer.Ref(receiptID.String()),
		DetectedFormat: detected, DetectedFormatRef: proffer.Ref(formatID.String()), SignatureRef: proffer.Ref(signatureID.String()),
		Recommended: candidates[0], Alternatives: candidates[1:],
	}, true, nil
}

// PersistHandlerSelectionDecision binds an authenticated actor to one exact
// candidate from one exact recommendation before Temporal is signaled.
func (s *HandlerSelectionStore) PersistHandlerSelectionDecision(ctx context.Context, sourceRef, recommendationRef, actorRef, compatibilityRef proffer.Ref, idempotencyKey string) (proffer.Ref, error) {
	sourceID, sourceErr := uuid.Parse(string(sourceRef))
	recommendationID, recommendationErr := uuid.Parse(string(recommendationRef))
	compatibilityID, compatibilityErr := uuid.Parse(string(compatibilityRef))
	if sourceErr != nil || recommendationErr != nil || compatibilityErr != nil || strings.TrimSpace(string(actorRef)) == "" || strings.TrimSpace(idempotencyKey) == "" {
		return "", errors.New("handler selection decision requires valid durable references, actor, and idempotency key")
	}
	tx, err := s.db.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return "", err
	}
	rollback := true
	defer func() {
		if rollback {
			cleanup, cancel := boundedCleanup(ctx)
			defer cancel()
			_ = tx.Rollback(cleanup)
		}
	}()
	var id uuid.UUID
	err = tx.QueryRow(ctx, `
		INSERT INTO context.handler_selection_decision(source_version_id,recommendation_id,compatibility_id,actor_ref,decision_idempotency_key)
		SELECT $1,$2,$3,$4,$5
		FROM context.handler_recommendation recommendation
		JOIN context.handler_compatibility compatibility ON compatibility.detected_format_id=recommendation.detected_format_id
		WHERE recommendation.id=$2 AND recommendation.source_version_id=$1 AND compatibility.id=$3
		  AND recommendation.candidates @> jsonb_build_array(jsonb_build_object(
		    'handler_id',compatibility.handler_id,'handler_version',compatibility.handler_version,
		    'execution_path',compatibility.execution_path,'compatibility_ref',compatibility.id::text))
		ON CONFLICT(decision_idempotency_key) DO NOTHING RETURNING id`, sourceID, recommendationID, compatibilityID, string(actorRef), idempotencyKey).Scan(&id)
	if errors.Is(err, pgx.ErrNoRows) {
		var storedSource, storedRecommendation, storedCompatibility uuid.UUID
		var storedActor string
		err = tx.QueryRow(ctx, `SELECT id,source_version_id,recommendation_id,compatibility_id,actor_ref FROM context.handler_selection_decision WHERE decision_idempotency_key=$1`, idempotencyKey).
			Scan(&id, &storedSource, &storedRecommendation, &storedCompatibility, &storedActor)
		if err == nil && (storedSource != sourceID || storedRecommendation != recommendationID || storedCompatibility != compatibilityID || storedActor != string(actorRef)) {
			err = errors.New("handler selection idempotency key is bound to different content")
		}
	}
	if err != nil {
		return "", fmt.Errorf("persist exact handler selection decision: %w", err)
	}
	if err = tx.Commit(ctx); err != nil {
		return "", err
	}
	rollback = false
	return proffer.Ref(id.String()), nil
}

// ValidateHandlerSelection reloads every asserted reference, proves the
// actor-bound decision is a member of the durable bounded set, and persists
// the validation Activity receipt before returning the chosen route.
func (s *HandlerSelectionStore) ValidateHandlerSelection(ctx context.Context, req proffer.StageRequest, attempt int32) (proffer.HandlerSelectionValidationResult, error) {
	sourceID, sourceErr := uuid.Parse(string(req.SourceVersionRef))
	recommendationID, recommendationErr := uuid.Parse(string(req.Refs["handler_recommendation"]))
	decisionID, decisionErr := uuid.Parse(string(req.Refs["handler_decision"]))
	if sourceErr != nil || recommendationErr != nil || decisionErr != nil || strings.TrimSpace(req.RequestID) == "" || attempt < 1 {
		return proffer.HandlerSelectionValidationResult{}, errors.New("handler selection validation requires source, recommendation, decision, request, and attempt")
	}
	tx, err := s.db.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return proffer.HandlerSelectionValidationResult{}, err
	}
	rollback := true
	defer func() {
		if rollback {
			cleanup, cancel := boundedCleanup(ctx)
			defer cancel()
			_ = tx.Rollback(cleanup)
		}
	}()
	key := "handler-validation:" + recommendationID.String() + ":" + decisionID.String()
	executionID, err := parserEnsureExecution(ctx, tx, sourceID, req.RequestID, proffer.ValidateHandlerSelectionActivityName, key)
	if err != nil {
		return proffer.HandlerSelectionValidationResult{}, err
	}
	var actor, detected, handlerID, handlerVersion, path, reason string
	var formatID, signatureID, compatibilityID uuid.UUID
	err = tx.QueryRow(ctx, `
		SELECT decision.actor_ref,format.format_id,format.id,signature.id,compatibility.id,
		       compatibility.handler_id,compatibility.handler_version,compatibility.execution_path,compatibility.reason
		FROM context.handler_selection_decision decision
		JOIN context.handler_recommendation recommendation ON recommendation.id=decision.recommendation_id
		JOIN context.handler_detected_format format ON format.id=recommendation.detected_format_id
		JOIN context.handler_content_signature signature ON signature.id=recommendation.content_signature_id
		JOIN context.handler_compatibility compatibility ON compatibility.id=decision.compatibility_id
		WHERE decision.id=$1 AND decision.source_version_id=$2 AND recommendation.id=$3
		  AND recommendation.source_version_id=$2 AND format.source_version_id=$2
		  AND signature.source_version_id=$2 AND signature.original_object_id=recommendation.original_object_id
		  AND compatibility.detected_format_id=format.id
		  AND recommendation.candidates @> jsonb_build_array(jsonb_build_object(
		    'handler_id',compatibility.handler_id,'handler_version',compatibility.handler_version,
		    'execution_path',compatibility.execution_path,'compatibility_ref',compatibility.id::text))`, decisionID, sourceID, recommendationID).
		Scan(&actor, &detected, &formatID, &signatureID, &compatibilityID, &handlerID, &handlerVersion, &path, &reason)
	if err != nil {
		return proffer.HandlerSelectionValidationResult{}, fmt.Errorf("validate exact actor-bound handler selection: %w", err)
	}
	if req.DeclaredFormat != detected || req.Refs["detected_format"] != proffer.Ref(formatID.String()) || req.Refs["content_signature"] != proffer.Ref(signatureID.String()) {
		return proffer.HandlerSelectionValidationResult{}, errors.New("handler selection validation references do not match the durable recommendation")
	}
	chosen := proffer.HandlerCandidate{HandlerID: handlerID, HandlerVersion: handlerVersion, ExecutionPath: proffer.HandlerExecutionPath(path), CompatibilityRef: proffer.Ref(compatibilityID.String()), Reason: reason}
	var priorReceipt uuid.UUID
	if err = tx.QueryRow(ctx, `SELECT id FROM context.activity_receipt WHERE activity_execution_id=$1 AND status='success' ORDER BY attempt LIMIT 1`, executionID).Scan(&priorReceipt); err == nil {
		if err = tx.Commit(ctx); err != nil {
			return proffer.HandlerSelectionValidationResult{}, err
		}
		rollback = false
		return validationResult(decisionID, actor, priorReceipt, recommendationID, detected, formatID, signatureID, chosen), nil
	} else if !errors.Is(err, pgx.ErrNoRows) {
		return proffer.HandlerSelectionValidationResult{}, err
	}
	receiptID, validationID := uuid.New(), uuid.New()
	now := s.clock()
	resultJSON, _ := json.Marshal(map[string]any{"ref_kind": "handler_selection_validation", "ref_id": validationID.String(), "decision_ref": decisionID.String(), "chosen": chosen})
	if _, err = tx.Exec(ctx, `INSERT INTO context.activity_receipt(id,activity_execution_id,attempt,status,started_at,completed_at,result_ref) VALUES($1,$2,$3,'success',$4,$4,$5)`, receiptID, executionID, attempt, now, resultJSON); err != nil {
		return proffer.HandlerSelectionValidationResult{}, err
	}
	if _, err = tx.Exec(ctx, `INSERT INTO context.handler_selection_validation(id,source_version_id,recommendation_id,decision_id,compatibility_id,actor_ref,activity_receipt_id,created_at) VALUES($1,$2,$3,$4,$5,$6,$7,$8)`, validationID, sourceID, recommendationID, decisionID, compatibilityID, actor, receiptID, now); err != nil {
		return proffer.HandlerSelectionValidationResult{}, err
	}
	if err = tx.Commit(ctx); err != nil {
		return proffer.HandlerSelectionValidationResult{}, err
	}
	rollback = false
	return validationResult(decisionID, actor, receiptID, recommendationID, detected, formatID, signatureID, chosen), nil
}

func validationResult(decisionID uuid.UUID, actor string, receiptID, recommendationID uuid.UUID, detected string, formatID, signatureID uuid.UUID, chosen proffer.HandlerCandidate) proffer.HandlerSelectionValidationResult {
	return proffer.HandlerSelectionValidationResult{
		DecisionRef: proffer.Ref(decisionID.String()), ActorRef: proffer.Ref(actor), ValidationReceipt: proffer.Ref(receiptID.String()),
		RecommendationRef: proffer.Ref(recommendationID.String()), DetectedFormat: detected,
		DetectedFormatRef: proffer.Ref(formatID.String()), SignatureRef: proffer.Ref(signatureID.String()), Chosen: chosen,
	}
}
