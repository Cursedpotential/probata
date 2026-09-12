package postgres

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/url"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"time"

	"github.com/Cursedpotential/probata/engine/activities"
	"github.com/Cursedpotential/probata/engine/proffer"
	"github.com/Cursedpotential/probata/engine/stagegraph"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

// RepairActivityStore is the sole durable repair Activity store. Roots are
// shared, read-only source paths visible to both this runtime and tool-runtime.
type RepairActivityStore struct {
	db           DB
	allowedRoots []string
	clock        func() time.Time
}

func NewRepairActivityStore(db DB, allowedRoots []string) (*RepairActivityStore, error) {
	if db == nil {
		return nil, errors.New("postgres repair store: database is required")
	}
	roots := make([]string, 0, len(allowedRoots))
	for _, root := range allowedRoots {
		absolute, err := filepath.Abs(strings.TrimSpace(root))
		if err != nil || strings.TrimSpace(root) == "" {
			return nil, errors.New("postgres repair store: allowed roots must be absolute paths")
		}
		roots = append(roots, filepath.Clean(absolute))
	}
	if len(roots) == 0 {
		return nil, errors.New("postgres repair store: at least one allowed shared root is required")
	}
	return &RepairActivityStore{db: db, allowedRoots: roots, clock: func() time.Time { return time.Now().UTC() }}, nil
}

// REMOVED 2026-09-05 (D-132): ResolveOriginalPath yielded a HOST PATH, which the
// repair Activity then posted to tool-runtime running on a DIFFERENT host —
// the exact defect the tool gateway exists to eliminate. The retained original
// is now addressed by LOCATOR and materialized by the gateway. Do not
// reintroduce a path-yielding method on this store.

func fileURIPath(raw string) (string, error) {
	u, err := url.Parse(raw)
	if err != nil || u.Scheme != "file" || u.Host != "" {
		return "", errors.New("repair source requires a local file URI")
	}
	path, err := url.PathUnescape(u.Path)
	if err != nil {
		return "", errors.New("repair source file URI is invalid")
	}
	if filepath.Separator == '\\' && len(path) >= 3 && path[0] == '/' && path[2] == ':' {
		path = path[1:]
	}
	if !filepath.IsAbs(path) {
		return "", errors.New("repair source path must be absolute")
	}
	return filepath.Clean(path), nil
}

func (s *RepairActivityStore) pathAllowed(path string) bool {
	clean := filepath.Clean(path)
	for _, root := range s.allowedRoots {
		rel, err := filepath.Rel(root, clean)
		if err == nil && rel != ".." && !strings.HasPrefix(rel, ".."+string(filepath.Separator)) {
			return true
		}
	}
	return false
}

func (s *RepairActivityStore) PersistRepairAssessment(ctx context.Context, spec activities.RepairAssessmentSpec) (activities.RepairPersistenceResult, error) {
	if !json.Valid(spec.Detection) || !json.Valid(spec.Preview) || spec.Attempt < 1 {
		return activities.RepairPersistenceResult{}, errors.New("repair assessment requires valid bounded JSON and attempt")
	}
	return s.persistAssessment(ctx, spec)
}

func (s *RepairActivityStore) LoadPersistedRepairAssessment(ctx context.Context, spec activities.RepairAssessmentSpec) (activities.RepairPersistenceResult, bool, error) {
	sourceID, sourceErr := uuid.Parse(string(spec.SourceVersionRef))
	_, originalErr := uuid.Parse(string(spec.OriginalRef))
	if sourceErr != nil || originalErr != nil || strings.TrimSpace(spec.IdempotencyKey) == "" || strings.TrimSpace(spec.DeclaredFormat) == "" {
		return activities.RepairPersistenceResult{}, false, errors.New("load repair assessment requires valid identity references")
	}
	row := s.db.QueryRow(ctx, `SELECT receipt.id,receipt.result_ref,assessment.id,assessment.source_version_id,
		assessment.original_object_id,assessment.declared_format,assessment.detection,assessment.preview
		FROM context.activity_execution execution
		JOIN context.activity_receipt receipt ON receipt.activity_execution_id=execution.id
		JOIN context.repair_assessment assessment ON assessment.activity_receipt_id=receipt.id
		WHERE execution.source_version_id=$1 AND execution.activity_name=$2 AND execution.idempotency_key=$3
		AND receipt.status='success' ORDER BY receipt.attempt LIMIT 1`, sourceID, string(stagegraph.AssessSourceRepair), spec.IdempotencyKey)
	return scanPriorRepairAssessment(row, spec)
}

func (s *RepairActivityStore) persistAssessment(ctx context.Context, spec activities.RepairAssessmentSpec) (activities.RepairPersistenceResult, error) {
	sourceID, err := uuid.Parse(string(spec.SourceVersionRef))
	if err != nil {
		return activities.RepairPersistenceResult{}, err
	}
	originalID, err := uuid.Parse(string(spec.OriginalRef))
	if err != nil {
		return activities.RepairPersistenceResult{}, err
	}
	tx, err := s.db.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return activities.RepairPersistenceResult{}, err
	}
	rollback := true
	defer func() {
		if rollback {
			cleanup, cancel := boundedCleanup(ctx)
			defer cancel()
			_ = tx.Rollback(cleanup)
		}
	}()
	executionID, err := parserEnsureExecution(ctx, tx, sourceID, spec.RequestID, string(stagegraph.AssessSourceRepair), spec.IdempotencyKey)
	if err != nil {
		return activities.RepairPersistenceResult{}, err
	}
	if prior, ok, err := repairAssessmentPrior(ctx, tx, executionID, spec); err != nil {
		return activities.RepairPersistenceResult{}, err
	} else if ok {
		if err = tx.Commit(ctx); err != nil {
			return activities.RepairPersistenceResult{}, err
		}
		rollback = false
		return prior, nil
	}
	assessmentID, receiptID := uuid.New(), uuid.New()
	now := s.clock()
	result, _ := json.Marshal(map[string]string{"ref_kind": "repair_assessment", "ref_id": assessmentID.String()})
	if _, err = tx.Exec(ctx, `INSERT INTO context.activity_receipt(id,activity_execution_id,attempt,status,started_at,completed_at,result_ref) VALUES($1,$2,$3,'success',$4,$4,$5)`, receiptID, executionID, spec.Attempt, now, result); err != nil {
		return activities.RepairPersistenceResult{}, err
	}
	if _, err = tx.Exec(ctx, `INSERT INTO context.repair_assessment(id,source_version_id,original_object_id,activity_receipt_id,declared_format,detection,preview) VALUES($1,$2,$3,$4,$5,$6,$7)`, assessmentID, sourceID, originalID, receiptID, spec.DeclaredFormat, []byte(spec.Detection), []byte(spec.Preview)); err != nil {
		return activities.RepairPersistenceResult{}, err
	}
	if err = tx.Commit(ctx); err != nil {
		return activities.RepairPersistenceResult{}, err
	}
	rollback = false
	return activities.RepairPersistenceResult{ResultRef: proffer.Ref(assessmentID.String()), ReceiptRef: proffer.Ref(receiptID.String()), ReviewRequired: spec.ReviewRequired}, nil
}

func repairAssessmentPrior(ctx context.Context, tx pgx.Tx, executionID uuid.UUID, spec activities.RepairAssessmentSpec) (activities.RepairPersistenceResult, bool, error) {
	row := tx.QueryRow(ctx, `SELECT receipt.id,receipt.result_ref,assessment.id,assessment.source_version_id,
		assessment.original_object_id,assessment.declared_format,assessment.detection,assessment.preview
		FROM context.activity_receipt receipt
		JOIN context.repair_assessment assessment ON assessment.activity_receipt_id=receipt.id
		WHERE receipt.activity_execution_id=$1 AND receipt.status='success'
		ORDER BY receipt.attempt LIMIT 1`, executionID)
	return scanPriorRepairAssessment(row, spec)
}

func scanPriorRepairAssessment(row pgx.Row, spec activities.RepairAssessmentSpec) (activities.RepairPersistenceResult, bool, error) {
	var receiptID, assessmentID, sourceID, originalID uuid.UUID
	var resultRef, detection, preview []byte
	var declaredFormat string
	err := row.Scan(
		&receiptID, &resultRef, &assessmentID, &sourceID, &originalID, &declaredFormat, &detection, &preview,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		return activities.RepairPersistenceResult{}, false, nil
	}
	if err != nil {
		return activities.RepairPersistenceResult{}, false, err
	}
	stored, err := validatePriorRepairAssessment(spec, assessmentID, sourceID, originalID, declaredFormat, resultRef, detection, preview)
	if err != nil {
		return activities.RepairPersistenceResult{}, false, err
	}
	stored.ReceiptRef = proffer.Ref(receiptID.String())
	return stored, true, nil
}

func validatePriorRepairAssessment(spec activities.RepairAssessmentSpec, assessmentID, sourceID, originalID uuid.UUID, declaredFormat string, resultRef, detection, preview []byte) (activities.RepairPersistenceResult, error) {
	expectedSource, sourceErr := uuid.Parse(string(spec.SourceVersionRef))
	expectedOriginal, originalErr := uuid.Parse(string(spec.OriginalRef))
	if sourceErr != nil || originalErr != nil || sourceID != expectedSource || originalID != expectedOriginal || declaredFormat != spec.DeclaredFormat {
		return activities.RepairPersistenceResult{}, errors.New("stored repair assessment identity conflicts with retry")
	}
	var receiptResult struct {
		RefKind string `json:"ref_kind"`
		RefID   string `json:"ref_id"`
	}
	if json.Unmarshal(resultRef, &receiptResult) != nil || receiptResult.RefKind != "repair_assessment" || receiptResult.RefID != assessmentID.String() {
		return activities.RepairPersistenceResult{}, errors.New("stored repair assessment receipt is invalid")
	}
	// Fresh output from a raced retry is deliberately discarded here. The
	// append-only assessment selected by the idempotency coordinate is the only
	// authoritative content and review requirement.
	return activities.RepairPersistenceResult{
		ResultRef:      proffer.Ref(assessmentID.String()),
		ReviewRequired: activities.RepairReviewRequired(json.RawMessage(detection), json.RawMessage(preview)),
	}, nil
}

func (s *RepairActivityStore) PersistAutomaticRepairResolution(ctx context.Context, spec activities.RepairResolutionSpec) (activities.RepairPersistenceResult, error) {
	decisionRef, err := s.PersistRepairDecision(ctx, proffer.RepairDecisionSpec{
		SourceVersionRef: spec.SourceVersionRef, AssessmentRef: spec.AssessmentRef,
		ActorRef: "proffer:auto-clean", Approved: true,
		IdempotencyKey: "proffer:auto-clean:" + string(spec.AssessmentRef),
	})
	if err != nil {
		return activities.RepairPersistenceResult{}, err
	}
	spec.DecisionRef, spec.ActorRef, spec.Applied = decisionRef, "proffer:auto-clean", false
	return s.PersistRepairResolution(ctx, spec)
}

func repairPrior(ctx context.Context, tx pgx.Tx, executionID uuid.UUID) (activities.RepairPersistenceResult, bool, error) {
	var receiptID uuid.UUID
	var raw []byte
	err := tx.QueryRow(ctx, `SELECT id,result_ref FROM context.activity_receipt WHERE activity_execution_id=$1 AND status='success' ORDER BY attempt LIMIT 1`, executionID).Scan(&receiptID, &raw)
	if errors.Is(err, pgx.ErrNoRows) {
		return activities.RepairPersistenceResult{}, false, nil
	}
	if err != nil {
		return activities.RepairPersistenceResult{}, false, err
	}
	var ref struct {
		RefID string `json:"ref_id"`
	}
	if json.Unmarshal(raw, &ref) != nil || ref.RefID == "" {
		return activities.RepairPersistenceResult{}, false, errors.New("stored repair receipt is invalid")
	}
	return activities.RepairPersistenceResult{ResultRef: proffer.Ref(ref.RefID), ReceiptRef: proffer.Ref(receiptID.String())}, true, nil
}

func (s *RepairActivityStore) LoadApprovedRepairDecision(ctx context.Context, sourceRef, assessmentRef, decisionRef proffer.Ref) (activities.RepairDecisionRecord, error) {
	var actor, tool string
	var approved, apply bool
	var payload []byte
	err := s.db.QueryRow(ctx, `SELECT actor_ref,approved,apply_repair,coalesce(tool_id,''),tool_payload FROM context.repair_decision WHERE id=$1::uuid AND source_version_id=$2::uuid AND assessment_id=$3::uuid`, string(decisionRef), string(sourceRef), string(assessmentRef)).Scan(&actor, &approved, &apply, &tool, &payload)
	if err != nil {
		return activities.RepairDecisionRecord{}, fmt.Errorf("load exact repair decision: %w", err)
	}
	var object map[string]any
	if json.Unmarshal(payload, &object) != nil {
		return activities.RepairDecisionRecord{}, errors.New("repair decision payload is invalid")
	}
	if !approved {
		return activities.RepairDecisionRecord{}, errors.New("repair decision is not approved")
	}
	return activities.RepairDecisionRecord{DecisionRef: decisionRef, ActorRef: proffer.Ref(actor), Approved: approved, ApplyRepair: apply, ToolID: tool, Payload: object}, nil
}

// PersistRepairDecision gives Workbench/Proffer one transactionally idempotent
// write seam. n8n and Temporal receive only its returned decision registry.
func (s *RepairActivityStore) PersistRepairDecision(ctx context.Context, spec proffer.RepairDecisionSpec) (proffer.Ref, error) {
	sourceID, err := uuid.Parse(string(spec.SourceVersionRef))
	if err != nil {
		return "", errors.New("repair decision source reference is invalid")
	}
	assessmentID, err := uuid.Parse(string(spec.AssessmentRef))
	if err != nil {
		return "", errors.New("repair decision assessment reference is invalid")
	}
	if strings.TrimSpace(string(spec.ActorRef)) == "" || strings.TrimSpace(spec.IdempotencyKey) == "" {
		return "", errors.New("repair decision requires actor and idempotency key")
	}
	payload, err := json.Marshal(spec.ToolPayload)
	if err != nil || len(payload) > 65536 {
		return "", errors.New("repair decision payload is invalid or exceeds limit")
	}
	if spec.ApplyRepair && (!spec.Approved || !allowedRepairTool(spec.ToolID)) {
		return "", errors.New("applied repair decision requires approval and an allowed derived tool")
	}
	if !spec.ApplyRepair && (spec.ToolID != "" || len(spec.ToolPayload) != 0) {
		return "", errors.New("non-applied repair decision must not carry tool state")
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
	err = tx.QueryRow(ctx, `INSERT INTO context.repair_decision(source_version_id,assessment_id,actor_ref,approved,apply_repair,tool_id,tool_payload,decision_idempotency_key)
		SELECT $1,$2,$3,$4,$5,nullif($6,''),$7,$8 FROM context.repair_assessment assessment
		WHERE assessment.id=$2 AND assessment.source_version_id=$1
		ON CONFLICT(decision_idempotency_key) DO NOTHING RETURNING id`, sourceID, assessmentID, string(spec.ActorRef), spec.Approved, spec.ApplyRepair, spec.ToolID, payload, spec.IdempotencyKey).Scan(&id)
	if errors.Is(err, pgx.ErrNoRows) {
		var actor, tool string
		var approved, apply bool
		var storedPayload []byte
		err = tx.QueryRow(ctx, `SELECT id,actor_ref,approved,apply_repair,coalesce(tool_id,''),tool_payload FROM context.repair_decision WHERE decision_idempotency_key=$1 AND source_version_id=$2 AND assessment_id=$3`, spec.IdempotencyKey, sourceID, assessmentID).Scan(&id, &actor, &approved, &apply, &tool, &storedPayload)
		var stored, requested any
		if err == nil {
			_ = json.Unmarshal(storedPayload, &stored)
			_ = json.Unmarshal(payload, &requested)
		}
		if err == nil && (actor != string(spec.ActorRef) || approved != spec.Approved || apply != spec.ApplyRepair || tool != spec.ToolID || !reflect.DeepEqual(stored, requested)) {
			err = errors.New("repair decision idempotency key is bound to different content")
		}
	}
	if err != nil {
		return "", fmt.Errorf("persist exact repair decision: %w", err)
	}
	if err = tx.Commit(ctx); err != nil {
		return "", err
	}
	rollback = false
	return proffer.Ref(id.String()), nil
}

func allowedRepairTool(tool string) bool {
	return tool == "repair.write-derived" || tool == "repair.pdf-derived"
}

func (s *RepairActivityStore) PersistRepairResolution(ctx context.Context, spec activities.RepairResolutionSpec) (activities.RepairPersistenceResult, error) {
	sourceID, _ := uuid.Parse(string(spec.SourceVersionRef))
	originalID, _ := uuid.Parse(string(spec.OriginalRef))
	assessmentID, _ := uuid.Parse(string(spec.AssessmentRef))
	decisionID, _ := uuid.Parse(string(spec.DecisionRef))
	if sourceID == uuid.Nil || originalID == uuid.Nil || assessmentID == uuid.Nil || decisionID == uuid.Nil || spec.Attempt < 1 {
		return activities.RepairPersistenceResult{}, errors.New("repair resolution requires valid references and attempt")
	}
	activeID := originalID
	toolResult := json.RawMessage(`{}`)
	var derived *derivedRepairObject
	if spec.Applied {
		var err error
		derived, err = s.validateDerived(spec.ToolResult)
		if err != nil {
			return activities.RepairPersistenceResult{}, err
		}
		toolResult = spec.ToolResult
	}
	tx, err := s.db.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return activities.RepairPersistenceResult{}, err
	}
	rollback := true
	defer func() {
		if rollback {
			cleanup, cancel := boundedCleanup(ctx)
			defer cancel()
			_ = tx.Rollback(cleanup)
		}
	}()
	executionID, err := parserEnsureExecution(ctx, tx, sourceID, spec.RequestID, string(stagegraph.ResolveSourceRepair), spec.IdempotencyKey)
	if err != nil {
		return activities.RepairPersistenceResult{}, err
	}
	if prior, ok, e := repairPrior(ctx, tx, executionID); e != nil {
		return activities.RepairPersistenceResult{}, e
	} else if ok {
		if e = tx.Commit(ctx); e != nil {
			return activities.RepairPersistenceResult{}, e
		}
		rollback = false
		return prior, nil
	}
	if derived != nil {
		if activeID, err = s.registerDerived(ctx, tx, *derived); err != nil {
			return activities.RepairPersistenceResult{}, err
		}
	}
	resolutionID, receiptID := uuid.New(), uuid.New()
	now := s.clock()
	result, _ := json.Marshal(map[string]string{"ref_kind": "retained_object", "ref_id": activeID.String(), "repair_resolution_ref": resolutionID.String()})
	if _, err = tx.Exec(ctx, `INSERT INTO context.activity_receipt(id,activity_execution_id,attempt,status,started_at,completed_at,result_ref) VALUES($1,$2,$3,'success',$4,$4,$5)`, receiptID, executionID, spec.Attempt, now, result); err != nil {
		return activities.RepairPersistenceResult{}, err
	}
	if _, err = tx.Exec(ctx, `INSERT INTO context.repair_resolution(id,source_version_id,assessment_id,decision_id,original_object_id,active_object_id,activity_receipt_id,actor_ref,applied,tool_id,tool_result) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,nullif($10,''),$11)`, resolutionID, sourceID, assessmentID, decisionID, originalID, activeID, receiptID, string(spec.ActorRef), spec.Applied, spec.ToolID, []byte(toolResult)); err != nil {
		return activities.RepairPersistenceResult{}, err
	}
	if spec.Applied {
		if _, err = tx.Exec(ctx, `INSERT INTO context.source_version_object(source_version_id,object_id,object_role,parent_object_id,member_locator) VALUES($1,$2,'derived_reference',$3,jsonb_build_object('repair_resolution_ref',$4::text)) ON CONFLICT DO NOTHING`, sourceID, activeID, originalID, resolutionID); err != nil {
			return activities.RepairPersistenceResult{}, err
		}
	}
	if err = tx.Commit(ctx); err != nil {
		return activities.RepairPersistenceResult{}, err
	}
	rollback = false
	return activities.RepairPersistenceResult{ResultRef: proffer.Ref(activeID.String()), ReceiptRef: proffer.Ref(receiptID.String())}, nil
}

type derivedRepairObject struct {
	path, uri string
	digest    []byte
	size      int64
}

func (s *RepairActivityStore) validateDerived(raw json.RawMessage) (*derivedRepairObject, error) {
	var result struct {
		Derived string `json:"derived"`
		SHA     string `json:"derived_sha256"`
	}
	if json.Unmarshal(raw, &result) != nil || result.Derived == "" || len(result.SHA) != 64 {
		return nil, errors.New("repair tool result lacks derived path or sha256")
	}
	path := filepath.Clean(result.Derived)
	if !s.pathAllowed(path) {
		return nil, errors.New("derived repair output is outside configured shared roots")
	}
	file, err := os.Open(path)
	if err != nil {
		return nil, errors.New("derived repair output is not readable")
	}
	defer file.Close()
	info, err := file.Stat()
	if err != nil || !info.Mode().IsRegular() {
		return nil, errors.New("derived repair output is not a regular file")
	}
	want, err := hex.DecodeString(result.SHA)
	if err != nil || len(want) != sha256.Size {
		return nil, errors.New("derived repair digest is invalid")
	}
	hasher := sha256.New()
	if _, err = io.Copy(hasher, file); err != nil {
		return nil, errors.New("hash derived repair output")
	}
	if !strings.EqualFold(hex.EncodeToString(hasher.Sum(nil)), result.SHA) {
		return nil, errors.New("derived repair output digest does not match bytes")
	}
	return &derivedRepairObject{path: path, uri: (&url.URL{Scheme: "file", Path: filepath.ToSlash(path)}).String(), digest: want, size: info.Size()}, nil
}

func (s *RepairActivityStore) registerDerived(ctx context.Context, tx pgx.Tx, derived derivedRepairObject) (uuid.UUID, error) {
	var id uuid.UUID
	err := tx.QueryRow(ctx, `WITH inserted AS (INSERT INTO context.retained_object(storage_class,object_uri,content_sha256,byte_length) VALUES('filesystem',$1,$2,$3) ON CONFLICT DO NOTHING RETURNING id) SELECT id FROM inserted UNION ALL SELECT id FROM context.retained_object WHERE storage_class='filesystem' AND object_uri=$1 AND content_sha256=$2 AND byte_length=$3 LIMIT 1`, derived.uri, derived.digest, derived.size).Scan(&id)
	if err != nil {
		return uuid.Nil, fmt.Errorf("register exact derived repair object: %w", err)
	}
	return id, nil
}
