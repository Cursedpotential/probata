package activities

import (
	"context"
	"encoding/json"
	"testing"

	"github.com/Cursedpotential/probata/engine/proffer"
)

type repairClientStub struct {
	calls    []string
	sources  []proffer.Ref
	payloads []map[string]any
	result   json.RawMessage
}

func (c *repairClientStub) Run(_ context.Context, id string, sourceRef proffer.Ref, args map[string]any) (json.RawMessage, error) {
	c.calls = append(c.calls, id)
	c.sources = append(c.sources, sourceRef)
	c.payloads = append(c.payloads, args)
	if c.result != nil {
		return c.result, nil
	}
	return json.RawMessage(`{"needs_repair":false}`), nil
}

type repairStoreStub struct {
	decision               RepairDecisionRecord
	assessment, resolution RepairPersistenceResult
	persisted              RepairPersistenceResult
	persistedFound         bool
}

func (s *repairStoreStub) LoadPersistedRepairAssessment(context.Context, RepairAssessmentSpec) (RepairPersistenceResult, bool, error) {
	return s.persisted, s.persistedFound, nil
}
func (s *repairStoreStub) PersistRepairAssessment(context.Context, RepairAssessmentSpec) (RepairPersistenceResult, error) {
	return s.assessment, nil
}
func (s *repairStoreStub) LoadApprovedRepairDecision(context.Context, proffer.Ref, proffer.Ref, proffer.Ref) (RepairDecisionRecord, error) {
	return s.decision, nil
}
func (s *repairStoreStub) PersistRepairResolution(context.Context, RepairResolutionSpec) (RepairPersistenceResult, error) {
	return s.resolution, nil
}
func (s *repairStoreStub) PersistAutomaticRepairResolution(context.Context, RepairResolutionSpec) (RepairPersistenceResult, error) {
	return s.resolution, nil
}

func repairRequest(refs map[string]proffer.Ref) proffer.StageRequest {
	return proffer.StageRequest{RequestID: "req", SourceVersionRef: "source", DeclaredFormat: "pdf", Refs: refs}
}

func TestAssessSourceRepairCallsExistingCapabilitiesAndReturnsOnlyRefs(t *testing.T) {
	client := &repairClientStub{}
	store := &repairStoreStub{assessment: RepairPersistenceResult{ResultRef: "assessment", ReceiptRef: "receipt", ReviewRequired: false}}
	result, err := (RepairActivities{Client: client, Store: store}).AssessSourceRepair(t.Context(), repairRequest(map[string]proffer.Ref{"original": "original", "acquisition": "r2://bucket/object"}))
	if err != nil {
		t.Fatal(err)
	}
	if len(client.calls) != 2 || client.calls[0] != RepairDetectTool || client.calls[1] != RepairPreviewTool {
		t.Fatalf("calls=%v", client.calls)
	}
	if result.Ref != "assessment" || result.ReceiptRef != "receipt" {
		t.Fatalf("result=%+v", result)
	}
	if result.Status != proffer.StatusNotApplicable {
		t.Fatalf("clean assessment status=%q", result.Status)
	}
}

func TestAssessSourceRepairRequiresReviewWhenDetectorFlagsRepair(t *testing.T) {
	client := &repairClientStub{result: json.RawMessage(`{"needs_repair":true}`)}
	store := &repairStoreStub{assessment: RepairPersistenceResult{ResultRef: "assessment", ReceiptRef: "receipt", ReviewRequired: true}}
	result, err := (RepairActivities{Client: client, Store: store}).AssessSourceRepair(t.Context(), repairRequest(map[string]proffer.Ref{"original": "original", "acquisition": "r2://bucket/object"}))
	if err != nil {
		t.Fatal(err)
	}
	if result.Status != proffer.StatusSuccess {
		t.Fatalf("review assessment status=%q", result.Status)
	}
}

func TestAssessSourceRepairRetryKeepsPersistedReviewRequirement(t *testing.T) {
	// A tool would now say clean, but the store already has an assessment that
	// requires review. The retry must return that durable result without calling
	// either nondeterministic external capability again.
	client := &repairClientStub{result: json.RawMessage(`{"needs_repair":false}`)}
	store := &repairStoreStub{persistedFound: true, persisted: RepairPersistenceResult{
		ResultRef: "persisted-assessment", ReceiptRef: "persisted-receipt", ReviewRequired: true,
	}}
	result, err := (RepairActivities{Client: client, Store: store}).AssessSourceRepair(t.Context(), repairRequest(map[string]proffer.Ref{"original": "original", "acquisition": "r2://bucket/object"}))
	if err != nil {
		t.Fatal(err)
	}
	if result.Status != proffer.StatusSuccess || result.Ref != "persisted-assessment" || result.ReceiptRef != "persisted-receipt" {
		t.Fatalf("retry replaced the durable review assessment: %+v", result)
	}
	if len(client.calls) != 0 {
		t.Fatalf("retry reran external repair tools after durable persistence: %v", client.calls)
	}
}

func TestResolveSourceRepairAutomaticallyPersistsCleanResolution(t *testing.T) {
	store := &repairStoreStub{resolution: RepairPersistenceResult{ResultRef: "original-resolution", ReceiptRef: "receipt"}}
	result, err := (RepairActivities{Client: &repairClientStub{}, Store: store}).ResolveSourceRepair(t.Context(), repairRequest(map[string]proffer.Ref{
		"original": "original", "acquisition": "r2://bucket/object", "repair_assessment": "assessment", "auto_clean_assessment": "assessment",
	}))
	if err != nil {
		t.Fatal(err)
	}
	if result.Ref != "original-resolution" || result.ReceiptRef != "receipt" {
		t.Fatalf("result=%+v", result)
	}
}

func TestResolveSourceRepairFailsClosedWithoutExactApproval(t *testing.T) {
	store := &repairStoreStub{decision: RepairDecisionRecord{DecisionRef: "decision", ActorRef: "actor", Approved: false}, resolution: RepairPersistenceResult{ResultRef: "derived", ReceiptRef: "receipt"}}
	_, err := (RepairActivities{Client: &repairClientStub{}, Store: store}).ResolveSourceRepair(t.Context(), repairRequest(map[string]proffer.Ref{"original": "original", "acquisition": "r2://bucket/object", "repair_assessment": "assessment", "repair_decision": "decision"}))
	if err == nil {
		t.Fatal("unapproved repair decision was accepted")
	}
}

func TestResolveSourceRepairInjectsManualApprovalOnlyAfterStoredDecision(t *testing.T) {
	client := &repairClientStub{}
	store := &repairStoreStub{decision: RepairDecisionRecord{DecisionRef: "decision", ActorRef: "actor", Approved: true, ApplyRepair: true, ToolID: "repair.pdf-derived", Payload: map[string]any{"path": "/r2/source.pdf", "dest": "/r2/derived.pdf", "artifact_root": "/r2"}}, resolution: RepairPersistenceResult{ResultRef: "derived-original", ReceiptRef: "receipt"}}
	result, err := (RepairActivities{Client: client, Store: store}).ResolveSourceRepair(t.Context(), repairRequest(map[string]proffer.Ref{"original": "original", "acquisition": "r2://bucket/object", "repair_assessment": "assessment", "repair_decision": "decision"}))
	if err != nil {
		t.Fatal(err)
	}
	if result.Ref != "derived-original" || len(client.calls) != 1 {
		t.Fatalf("result=%+v calls=%v", result, client.calls)
	}
	if client.payloads[0]["_execution_mode"] != "manual" || client.payloads[0]["approved"] != true {
		t.Fatalf("payload=%v", client.payloads[0])
	}
	// D-132: a stored decision payload may carry a stale host path from an
	// older schema. It must be stripped, and the source rebound to the
	// governed locator.
	if _, leaked := client.payloads[0]["path"]; leaked {
		t.Fatalf("approved repair leaked a host path to the gateway: %v", client.payloads[0])
	}
	if client.sources[0] != "r2://bucket/object" {
		t.Fatalf("approved repair did not address the source by its acquisition locator: %q", client.sources[0])
	}
}

// TestAssessSourceRepairAddressesSourceByLocatorNotHostPath pins the D-132
// contract: the Activity names a locator and never a filesystem path, because
// the worker and tool-runtime are on different hosts.
func TestAssessSourceRepairAddressesSourceByLocatorNotHostPath(t *testing.T) {
	client := &repairClientStub{}
	store := &repairStoreStub{assessment: RepairPersistenceResult{ResultRef: "assessment", ReceiptRef: "receipt"}}
	if _, err := (RepairActivities{Client: client, Store: store}).AssessSourceRepair(
		t.Context(), repairRequest(map[string]proffer.Ref{"original": "01a06423-d4ce-799e-acbb-bbc4b867ab94", "acquisition": "r2://bucket/object"})); err != nil {
		t.Fatal(err)
	}
	if len(client.sources) != 2 {
		t.Fatalf("expected detect + preview calls, got sources=%v calls=%v", client.sources, client.calls)
	}
	for index, source := range client.sources {
		// The gateway is addressed by the scheme-prefixed acquisition locator,
		// never by the retained-original UUID (live 2026-09-05: "has no URI scheme").
		if source != "r2://bucket/object" {
			t.Fatalf("call %d addressed %q instead of the acquisition locator", index, source)
		}
		if _, leaked := client.payloads[index]["path"]; leaked {
			t.Fatalf("call %d sent a host path: %v", index, client.payloads[index])
		}
	}
	// The declared platform format ("pdf" in repairRequest) must NOT reach the
	// repair engine; only a structural format from the detection result does.
	// The stub's detection carries no fmt, so no format is sent and the engine
	// auto-detects (live 2026-09-05: "no engine for format 'sms_xml'").
	if _, sent := client.payloads[1]["format"]; sent || client.payloads[1]["sample_limit"] != 25 {
		t.Fatalf("preview args wrong: %v", client.payloads[1])
	}
}

func TestAssessSourceRepairForwardsStructuralFormatFromDetection(t *testing.T) {
	client := &repairClientStub{result: json.RawMessage(`{"detection":{"fmt":"xml","encoding":"utf-8"},"cloud_only":false}`)}
	store := &repairStoreStub{assessment: RepairPersistenceResult{ResultRef: "assessment", ReceiptRef: "receipt"}}
	if _, err := (RepairActivities{Client: client, Store: store}).AssessSourceRepair(
		t.Context(), repairRequest(map[string]proffer.Ref{"original": "orig", "acquisition": "r2://bucket/object"})); err != nil {
		t.Fatal(err)
	}
	if client.payloads[1]["format"] != "xml" {
		t.Fatalf("preview must carry the detector's structural format: %v", client.payloads[1])
	}
}

func TestRepairReviewUsesActualPreviewReport(t *testing.T) {
	detection := json.RawMessage(`{"detection":{"fmt":"image","encoding":"binary","confidence":1},"cloud_only":false}`)
	if RepairReviewRequired(detection, json.RawMessage(`{"report":{"clean":true,"chunks_failed":0,"repairs":0,"lossy":0,"truncated":false},"events":[]}`)) {
		t.Fatal("clean preview report created a repair gate")
	}
	if !RepairReviewRequired(detection, json.RawMessage(`{"report":{"clean":false,"chunks_failed":1,"repairs":0,"lossy":0,"truncated":false},"events":[]}`)) {
		t.Fatal("validated damaged preview report did not require review")
	}
	if RepairReviewRequired(detection, json.RawMessage(`{"samples":[]}`)) {
		t.Fatal("preview without a damage report was falsely labeled as needing repair")
	}
}
