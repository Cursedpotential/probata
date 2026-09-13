package postgres

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strings"

	"github.com/Cursedpotential/probata/engine/parser"
	"github.com/Cursedpotential/probata/engine/proffer"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

// RecoverHandler appends the failed selected-unit outcome before publishing
// actionable alternatives. It never chooses or executes a fallback itself.
func (s *HandlerSelectionStore) RecoverHandler(ctx context.Context, recovery proffer.HandlerRecoveryRequest) (proffer.HandlerRecommendationResult, error) {
	req := recovery.Request
	if strings.TrimSpace(recovery.AttemptIdentity) == "" || strings.TrimSpace(recovery.FailureReason) == "" {
		return proffer.HandlerRecommendationResult{}, errors.New("handler recovery requires a failed attempt identity and reason")
	}
	if len(recovery.AttemptIdentity) > 256 || len(recovery.FailureReason) > 8192 {
		return proffer.HandlerRecommendationResult{}, errors.New("handler recovery identity or failure reason exceeds bounded contract")
	}
	authorization, err := s.LoadHandlerExecutionAuthorization(ctx, req)
	if err != nil {
		return proffer.HandlerRecommendationResult{}, err
	}
	sourceID, originalID, err := handlerRequestIDs(req)
	if err != nil {
		return proffer.HandlerRecommendationResult{}, err
	}
	tx, err := s.db.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return proffer.HandlerRecommendationResult{}, err
	}
	defer func() { cleanup, cancel := boundedCleanup(ctx); defer cancel(); _ = tx.Rollback(cleanup) }()
	executionID, err := parserEnsureExecution(ctx, tx, sourceID, req.RequestID, proffer.RecoverHandlerActivityName, "handler-recovery:"+recovery.AttemptIdentity)
	if err != nil {
		return proffer.HandlerRecommendationResult{}, err
	}
	if prior, found, loadErr := loadRecommendationTx(ctx, tx, executionID); loadErr != nil {
		return proffer.HandlerRecommendationResult{}, loadErr
	} else if found {
		return prior, tx.Commit(ctx)
	}
	var priorExecution uuid.UUID
	if err = tx.QueryRow(ctx, `SELECT receipt.activity_execution_id FROM context.handler_recommendation recommendation
		JOIN context.activity_receipt receipt ON receipt.id=recommendation.activity_receipt_id
		WHERE recommendation.id=$1 AND recommendation.source_version_id=$2 AND recommendation.original_object_id=$3`,
		req.Refs["handler_recommendation"], sourceID, originalID).Scan(&priorExecution); err != nil {
		return proffer.HandlerRecommendationResult{}, err
	}
	prior, found, err := loadRecommendationTx(ctx, tx, priorExecution)
	if err != nil {
		return proffer.HandlerRecommendationResult{}, fmt.Errorf("load failed handler recommendation: %w", err)
	}
	if !found {
		return proffer.HandlerRecommendationResult{}, errors.New("failed handler recommendation is missing")
	}
	// A successful recommendation receipt and a separate immutable failure
	// receipt preserve both facts; neither rewrites the selected parser result.
	failureExecution, err := parserEnsureExecution(ctx, tx, sourceID, req.RequestID, "selected_handler_failure", "selected-handler-failure:"+recovery.AttemptIdentity)
	if err != nil {
		return proffer.HandlerRecommendationResult{}, err
	}
	failureID, receiptID, recommendationID := uuid.New(), uuid.New(), uuid.New()
	now := s.clock()
	failureJSON, _ := json.Marshal(map[string]any{"ref_kind": "handler_failure", "ref_id": failureID.String(), "reason": recovery.FailureReason,
		"parser_selection_ref": req.Refs["parser_selection"], "handler_validation_ref": req.Refs["handler_validation"], "attempt_identity": recovery.AttemptIdentity})
	if _, err = tx.Exec(ctx, `INSERT INTO context.activity_receipt(id,activity_execution_id,attempt,status,started_at,completed_at,error_detail)
		VALUES($1,$2,1,'failed',$3,$3,$4)`, failureID, failureExecution, now, failureJSON); err != nil {
		return proffer.HandlerRecommendationResult{}, err
	}
	chosen := prior.Recommended
	for _, candidate := range append([]proffer.HandlerCandidate{prior.Recommended}, prior.Alternatives...) {
		if candidate.HandlerID == authorization.HandlerID && candidate.HandlerVersion == authorization.HandlerVersion {
			chosen = candidate
		}
	}
	chosen.Reason = "retry selected processing unit after logged failure " + failureID.String()
	candidates := []proffer.HandlerCandidate{chosen}
	if authorization.ExecutionPath == proffer.HandlerPathDuckDB && s.parsers != nil {
		capability, selectErr := s.parsers.SelectCapability(parser.FormatID(authorization.DetectedFormat))
		if selectErr == nil {
			candidate := proffer.HandlerCandidate{HandlerID: capability.ParserID, HandlerVersion: capability.ParserVersion,
				ExecutionPath: proffer.HandlerPathDecoder, CompatibilityRef: proffer.Ref(uuid.NewString()), Reason: "registered decoder backup after logged DuckDB failure " + failureID.String()}
			if err = tx.QueryRow(ctx, `INSERT INTO context.handler_compatibility(id,detected_format_id,handler_id,handler_version,execution_path,reason,created_at)
				VALUES($1,$2,$3,$4,$5,$6,$7) ON CONFLICT (detected_format_id,handler_id,handler_version,execution_path)
				DO NOTHING RETURNING id`, candidate.CompatibilityRef, prior.DetectedFormatRef, candidate.HandlerID, candidate.HandlerVersion, candidate.ExecutionPath, candidate.Reason, now).Scan(&candidate.CompatibilityRef); errors.Is(err, pgx.ErrNoRows) {
				err = tx.QueryRow(ctx, `SELECT id FROM context.handler_compatibility WHERE detected_format_id=$1 AND handler_id=$2 AND handler_version=$3 AND execution_path=$4`, prior.DetectedFormatRef, candidate.HandlerID, candidate.HandlerVersion, candidate.ExecutionPath).Scan(&candidate.CompatibilityRef)
			}
			if err != nil {
				return proffer.HandlerRecommendationResult{}, err
			}
			candidates = append(candidates, candidate)
		}
	}
	candidatesJSON, _ := json.Marshal(candidates)
	resultJSON, _ := json.Marshal(map[string]any{"ref_kind": "handler_recommendation", "ref_id": recommendationID.String(), "failure_receipt_ref": failureID.String()})
	if _, err = tx.Exec(ctx, `INSERT INTO context.activity_receipt(id,activity_execution_id,attempt,status,started_at,completed_at,result_ref)
		VALUES($1,$2,1,'success',$3,$3,$4)`, receiptID, executionID, now, resultJSON); err != nil {
		return proffer.HandlerRecommendationResult{}, err
	}
	if _, err = tx.Exec(ctx, `INSERT INTO context.handler_recommendation(id,source_version_id,original_object_id,content_signature_id,detected_format_id,activity_receipt_id,candidates,created_at)
		VALUES($1,$2,$3,$4,$5,$6,$7,$8)`, recommendationID, sourceID, originalID, prior.SignatureRef, prior.DetectedFormatRef, receiptID, candidatesJSON, now); err != nil {
		return proffer.HandlerRecommendationResult{}, err
	}
	result := proffer.HandlerRecommendationResult{FailureReceiptRef: proffer.Ref(failureID.String()), RecommendationRef: proffer.Ref(recommendationID.String()), ReceiptRef: proffer.Ref(receiptID.String()),
		DetectedFormat: prior.DetectedFormat, DetectedFormatRef: prior.DetectedFormatRef, SignatureRef: prior.SignatureRef, Recommended: candidates[0], Alternatives: candidates[1:]}
	return result, tx.Commit(ctx)
}
