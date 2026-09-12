package activities

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strings"

	"github.com/Cursedpotential/probata/engine/proffer"
	"github.com/Cursedpotential/probata/engine/stagegraph"
)

const (
	RepairDetectTool  = "repair.detect"
	RepairPreviewTool = "repair.preview"
)

var allowedDerivedRepairTools = map[string]bool{
	"repair.write-derived": true,
	"repair.pdf-derived":   true,
}

// RepairToolClient executes an already-registered tool-runtime capability
// THROUGH THE TOOL GATEWAY (D-132). The source is named by LOCATOR, never by a
// host path: this Activity and tool-runtime run on different hosts, and a
// worker-local path is exactly the defect the gateway was built to remove.
// Results are persisted by RepairActivityStore and never returned to Temporal.
type RepairToolClient interface {
	Run(ctx context.Context, toolID string, sourceRef proffer.Ref, args map[string]any) (json.RawMessage, error)
}

type RepairDecisionRecord struct {
	DecisionRef proffer.Ref
	ActorRef    proffer.Ref
	Approved    bool
	ApplyRepair bool
	ToolID      string
	Payload     map[string]any
}

type RepairAssessmentSpec struct {
	RequestID, DeclaredFormat     string
	SourceVersionRef, OriginalRef proffer.Ref
	Attempt                       int32
	IdempotencyKey                string
	Detection, Preview            json.RawMessage
	ReviewRequired                bool
}

type RepairResolutionSpec struct {
	RequestID, DeclaredFormat                                           string
	SourceVersionRef, OriginalRef, AssessmentRef, DecisionRef, ActorRef proffer.Ref
	Attempt                                                             int32
	IdempotencyKey, ToolID                                              string
	Applied                                                             bool
	ToolResult                                                          json.RawMessage
}

type RepairPersistenceResult struct {
	ResultRef, ReceiptRef proffer.Ref
	ReviewRequired        bool
}

// RepairActivityStore owns locator resolution, immutable assessment storage,
// approval revalidation, and the exact activity receipt/idempotency boundary.
type RepairActivityStore interface {
	LoadPersistedRepairAssessment(context.Context, RepairAssessmentSpec) (RepairPersistenceResult, bool, error)
	PersistRepairAssessment(context.Context, RepairAssessmentSpec) (RepairPersistenceResult, error)
	LoadApprovedRepairDecision(context.Context, proffer.Ref, proffer.Ref, proffer.Ref) (RepairDecisionRecord, error)
	PersistRepairResolution(context.Context, RepairResolutionSpec) (RepairPersistenceResult, error)
	PersistAutomaticRepairResolution(context.Context, RepairResolutionSpec) (RepairPersistenceResult, error)
}

type RepairActivities struct {
	Client  RepairToolClient
	Store   RepairActivityStore
	Attempt Attempt
}

func (a RepairActivities) attempt(ctx context.Context) int32 {
	if a.Attempt == nil {
		return 1
	}
	attempt := a.Attempt(ctx)
	if attempt < 1 {
		return 1
	}
	return attempt
}

func (a RepairActivities) validate() error {
	if a.Client == nil {
		return errors.New("repair activities: tool-runtime client is required")
	}
	if a.Store == nil {
		return errors.New("repair activities: store is required")
	}
	return nil
}

func (a RepairActivities) AssessSourceRepair(ctx context.Context, req proffer.StageRequest) (proffer.StageResult, error) {
	if err := a.validate(); err != nil {
		return proffer.StageResult{}, err
	}
	original, err := repairRef(req, "original")
	if err != nil {
		return proffer.StageResult{}, err
	}
	idempotencyKey := fmt.Sprintf("repair-assessment:%s:%s:%s", req.RequestID, req.SourceVersionRef, original)
	prior, found, err := a.Store.LoadPersistedRepairAssessment(ctx, RepairAssessmentSpec{
		RequestID: req.RequestID, DeclaredFormat: req.DeclaredFormat,
		SourceVersionRef: req.SourceVersionRef, OriginalRef: original, IdempotencyKey: idempotencyKey,
	})
	if err != nil {
		return proffer.StageResult{}, fmt.Errorf("load persisted repair assessment: %w", err)
	}
	if found {
		return repairAssessmentResult(prior)
	}
	// The source travels to the gateway as a scheme-prefixed LOCATOR
	// (req.Refs["acquisition"]: upload:// or r2://), which the gateway
	// resolves through the shared acquisition router on ITS host and
	// materializes where the tool can read it (D-132). `original` is the
	// retained-object identity (a UUID, no scheme) and is what gets persisted.
	// Live rehearsal 2026-09-05 (rehearsal-20260905-r2c-1788610705) proved the
	// distinction: the gateway rejected the UUID with "has no URI scheme".
	locator, err := repairRef(req, "acquisition")
	if err != nil {
		return proffer.StageResult{}, err
	}
	detection, err := a.Client.Run(ctx, RepairDetectTool, locator, nil)
	if err != nil {
		return proffer.StageResult{}, fmt.Errorf("run repair detection: %w", err)
	}
	// The repair engines take the STRUCTURAL format the detector found ("xml",
	// "json", …), not the platform format tag the boundary declared
	// ("sms_xml"). Live rehearsal 2026-09-05 (rehearsal-20260905-r2d-1788611759):
	// passing DeclaredFormat made tool-runtime answer 422 "no engine for
	// format 'sms_xml'". Omitting it lets the engine auto-detect.
	previewArgs := map[string]any{"sample_limit": 25}
	if structural := repairDetectionFormat(detection); structural != "" {
		previewArgs["format"] = structural
	}
	preview, err := a.Client.Run(ctx, RepairPreviewTool, locator, previewArgs)
	if err != nil {
		return proffer.StageResult{}, fmt.Errorf("run repair preview: %w", err)
	}
	reviewRequired := RepairReviewRequired(detection, preview)
	result, err := a.Store.PersistRepairAssessment(ctx, RepairAssessmentSpec{
		RequestID: req.RequestID, DeclaredFormat: req.DeclaredFormat,
		SourceVersionRef: req.SourceVersionRef, OriginalRef: original,
		Attempt: a.attempt(ctx), IdempotencyKey: idempotencyKey,
		Detection: append(json.RawMessage(nil), detection...), Preview: append(json.RawMessage(nil), preview...), ReviewRequired: reviewRequired,
	})
	if err != nil {
		return proffer.StageResult{}, fmt.Errorf("persist repair assessment: %w", err)
	}
	return repairAssessmentResult(result)
}

func (a RepairActivities) ResolveSourceRepair(ctx context.Context, req proffer.StageRequest) (proffer.StageResult, error) {
	if err := a.validate(); err != nil {
		return proffer.StageResult{}, err
	}
	original, err := repairRef(req, "original")
	if err != nil {
		return proffer.StageResult{}, err
	}
	assessment, err := repairRef(req, "repair_assessment")
	if err != nil {
		return proffer.StageResult{}, err
	}
	if req.Refs["auto_clean_assessment"] == assessment {
		result, persistErr := a.Store.PersistAutomaticRepairResolution(ctx, RepairResolutionSpec{
			RequestID: req.RequestID, DeclaredFormat: req.DeclaredFormat, SourceVersionRef: req.SourceVersionRef,
			OriginalRef: original, AssessmentRef: assessment, ActorRef: "proffer:auto-clean",
			Attempt: a.attempt(ctx), IdempotencyKey: fmt.Sprintf("repair-resolution:auto-clean:%s:%s", req.RequestID, assessment),
		})
		if persistErr != nil {
			return proffer.StageResult{}, fmt.Errorf("persist automatic repair resolution: %w", persistErr)
		}
		return repairSuccess(stagegraph.ResolveSourceRepair, result)
	}
	decisionRef, err := repairRef(req, "repair_decision")
	if err != nil {
		return proffer.StageResult{}, err
	}
	decision, err := a.Store.LoadApprovedRepairDecision(ctx, req.SourceVersionRef, assessment, decisionRef)
	if err != nil {
		return proffer.StageResult{}, fmt.Errorf("load repair decision: %w", err)
	}
	if !decision.Approved || decision.DecisionRef != decisionRef || decision.ActorRef == "" {
		return proffer.StageResult{}, errors.New("repair decision is not an exact approved actor-bound decision")
	}
	var toolResult json.RawMessage
	if decision.ApplyRepair {
		if !allowedDerivedRepairTools[decision.ToolID] {
			return proffer.StageResult{}, fmt.Errorf("repair tool %q is not an approved derived-write capability", decision.ToolID)
		}
		payload := make(map[string]any, len(decision.Payload)+2)
		for key, value := range decision.Payload {
			payload[key] = value
		}
		// A persisted human decision chooses the operation and safe destination,
		// never a replacement source. The source is rebound to the governed
		// retained-object LOCATOR immediately before execution, so a stored
		// "path" from an older decision can never reach a tool.
		delete(payload, "path")
		payload["_execution_mode"] = "manual"
		payload["approved"] = true
		locator, locErr := repairRef(req, "acquisition")
		if locErr != nil {
			return proffer.StageResult{}, locErr
		}
		toolResult, err = a.Client.Run(ctx, decision.ToolID, locator, payload)
		if err != nil {
			return proffer.StageResult{}, fmt.Errorf("run approved derived repair: %w", err)
		}
	} else if decision.ToolID != "" || len(decision.Payload) != 0 {
		return proffer.StageResult{}, errors.New("use-original repair decision must not carry a tool or payload")
	}
	result, err := a.Store.PersistRepairResolution(ctx, RepairResolutionSpec{
		RequestID: req.RequestID, DeclaredFormat: req.DeclaredFormat, SourceVersionRef: req.SourceVersionRef,
		OriginalRef: original, AssessmentRef: assessment, DecisionRef: decisionRef, ActorRef: decision.ActorRef,
		Attempt: a.attempt(ctx), IdempotencyKey: fmt.Sprintf("repair-resolution:%s:%s:%s", req.RequestID, req.SourceVersionRef, decisionRef),
		ToolID: decision.ToolID, Applied: decision.ApplyRepair, ToolResult: append(json.RawMessage(nil), toolResult...),
	})
	if err != nil {
		return proffer.StageResult{}, fmt.Errorf("persist repair resolution: %w", err)
	}
	return repairSuccess(stagegraph.ResolveSourceRepair, result)
}

func repairRef(req proffer.StageRequest, name string) (proffer.Ref, error) {
	if strings.TrimSpace(req.RequestID) == "" || req.SourceVersionRef == "" {
		return "", errors.New("repair activity requires request and source version references")
	}
	ref := req.Refs[name]
	if ref == "" {
		return "", fmt.Errorf("repair activity requires non-empty %q reference", name)
	}
	return ref, nil
}

func repairSuccess(stage stagegraph.StageID, result RepairPersistenceResult) (proffer.StageResult, error) {
	return repairResult(stage, result, proffer.StatusSuccess)
}

func repairAssessmentResult(result RepairPersistenceResult) (proffer.StageResult, error) {
	status := proffer.StatusSuccess
	if !result.ReviewRequired {
		status = proffer.StatusNotApplicable
	}
	return repairResult(stagegraph.AssessSourceRepair, result, status)
}

func repairResult(stage stagegraph.StageID, result RepairPersistenceResult, status proffer.Status) (proffer.StageResult, error) {
	if result.ResultRef == "" || result.ReceiptRef == "" {
		return proffer.StageResult{}, errors.New("repair persistence returned incomplete compact references")
	}
	return proffer.StageResult{Stage: stage, Status: status, Ref: result.ResultRef, ReceiptRef: result.ReceiptRef}, nil
}

// repairDetectionFormat extracts the structural format the detector reported
// ({"detection":{"fmt":"xml",...}}). Empty when absent, so the caller omits
// the argument and the engine auto-detects.
func repairDetectionFormat(detection json.RawMessage) string {
	var payload struct {
		Detection struct {
			Fmt string `json:"fmt"`
		} `json:"detection"`
	}
	if err := json.Unmarshal(detection, &payload); err != nil {
		return ""
	}
	return strings.TrimSpace(payload.Detection.Fmt)
}

// RepairReviewRequired derives the human-review requirement from the repair
// preview's actual report contract. repair.detect identifies format and engine;
// it does not decide whether source bytes are damaged. repair.preview reports
// that decision under report.clean and supplies the supporting counts/events.
// Merely returning detector metadata must not strand a clean source behind an
// empty review gate.
// The PostgreSQL store deliberately reuses this function when an Activity retry
// encounters an already-persisted assessment so the durable assessment, rather
// than a fresh tool response, remains authoritative.
func RepairReviewRequired(values ...json.RawMessage) bool {
	for _, raw := range values {
		var payload struct {
			Report *struct {
				Clean bool `json:"clean"`
			} `json:"report"`
		}
		if json.Unmarshal(raw, &payload) == nil && payload.Report != nil {
			return !payload.Report.Clean
		}
	}
	return false
}
