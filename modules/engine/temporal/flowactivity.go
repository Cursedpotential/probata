// The generic n8n-flow Activity: ONE registered Activity that can invoke ANY
// declared flow, so adding a flow is a registry entry rather than new Go.
//
// WHY (owner, 2026-09-02): "we're going to need a function to take an n8n,
// either node or flow, and create an activity in Temporal out of it and then
// run it... maybe be able to pull in different variables or locations or
// functions or something. Make it flexible for the different types of work
// that we'll be doing in that screen with the different types of data."
//
// The flexibility lives in three declared axes, and each is a different kind
// of thing on purpose:
//
//   - LOCATIONS travel as Refs — opaque locators (upload://, r2://, b2://,
//     sealed file://). Bytes never travel (D-130 rule 5).
//   - VARIABLES travel as Inputs — bounded scalars a flow needs to do its job
//     (a format, a sample limit, a mode).
//   - FUNCTIONS are reached by the flow itself through the tool gateway, which
//     already exposes the whole tool-runtime registry behind one uniform,
//     locator-addressed contract (D-132).
//
// Byline: Claude Code · Opus 5 · 2026-09-03.
package temporal

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"

	"github.com/Cursedpotential/probata/engine/proffer"
)

// RunFlowActivityName is the single Activity name under which every declared
// flow is invoked. The flow's own identity travels in the request, so the
// worker registers one Activity no matter how many flows exist.
const RunFlowActivityName = "run_n8n_flow_activity"

// maxFlowInputs bounds the declared-variable map. Inputs are knobs, never
// content; a request carrying hundreds of them is a payload in disguise.
const maxFlowInputs = 64

// FlowRequest invokes one declared flow.
type FlowRequest struct {
	// Flow is the declared binding name, not a webhook path. Callers never
	// name a URL, so a flow can be re-pathed in n8n without touching callers.
	Flow string `json:"flow"`

	// RequestID is the idempotency coordinate. Temporal retries Activities;
	// the flow must be able to recognise a repeat, so this is sent both as a
	// field and as an Idempotency-Key header.
	RequestID string `json:"request_id"`

	MatterID    string `json:"matter_id,omitempty"`
	CourtCaseID string `json:"court_case_id,omitempty"`

	SourceVersionRef proffer.Ref `json:"source_version_ref,omitempty"`
	DeclaredFormat   string      `json:"declared_format,omitempty"`

	// Refs are LOCATIONS: named locators the flow consumes.
	Refs map[string]proffer.Ref `json:"refs,omitempty"`

	// Inputs are VARIABLES: bounded scalars the flow declares it needs.
	Inputs map[string]any `json:"inputs,omitempty"`
}

// FlowResult is what a flow reports back.
type FlowResult struct {
	Flow       string         `json:"flow"`
	Status     proffer.Status `json:"status"`
	Ref        proffer.Ref    `json:"ref,omitempty"`
	ReceiptRef proffer.Ref    `json:"receipt_ref,omitempty"`
	Outputs    map[string]any `json:"outputs,omitempty"`
}

// FlowActivities is the Activity surface over the declared registry.
type FlowActivities struct {
	Client   *N8NClient
	Registry *FlowRegistry
}

// RunFlow is the generic Activity body. It resolves the declared binding,
// enforces that binding's own input contract before any HTTP leg, and calls
// the flow.
//
// It fails closed on every path — an undeclared flow, a missing required ref
// or input, a non-2xx response, or a result that does not name the flow it was
// asked for — returning an error and no result, matching engine/proffer's
// convention that an Activity error means "no receipt exists to report."
func (a FlowActivities) RunFlow(ctx context.Context, req FlowRequest) (FlowResult, error) {
	if a.Client == nil {
		return FlowResult{}, errors.New("temporal: flow activities have no n8n client")
	}
	binding, err := a.Registry.Lookup(strings.TrimSpace(req.Flow))
	if err != nil {
		return FlowResult{}, err
	}
	if err := validateFlowRequest(binding, req); err != nil {
		return FlowResult{}, err
	}
	return a.Client.CallFlow(ctx, binding, req)
}

func validateFlowRequest(binding FlowBinding, req FlowRequest) error {
	if strings.TrimSpace(req.RequestID) == "" {
		return fmt.Errorf("temporal: flow %q requires a request_id for idempotency", binding.Name)
	}
	if len(req.Inputs) > maxFlowInputs {
		return fmt.Errorf("temporal: flow %q was given %d inputs, over the %d limit — inputs are knobs, not content",
			binding.Name, len(req.Inputs), maxFlowInputs)
	}
	for _, name := range binding.RequireRefs {
		ref, ok := req.Refs[name]
		if !ok || strings.TrimSpace(string(ref)) == "" {
			return fmt.Errorf("temporal: flow %q requires ref %q", binding.Name, name)
		}
	}
	for _, name := range binding.RequireInputs {
		value, ok := req.Inputs[name]
		if !ok || value == nil {
			return fmt.Errorf("temporal: flow %q requires input %q", binding.Name, name)
		}
		if text, isText := value.(string); isText && strings.TrimSpace(text) == "" {
			return fmt.Errorf("temporal: flow %q requires a non-empty input %q", binding.Name, name)
		}
	}
	return nil
}

type flowRequestWire struct {
	Flow             string            `json:"flow"`
	RequestID        string            `json:"request_id"`
	MatterID         string            `json:"matter_id,omitempty"`
	CourtCaseID      string            `json:"court_case_id,omitempty"`
	SourceVersionRef string            `json:"source_version_ref,omitempty"`
	DeclaredFormat   string            `json:"declared_format,omitempty"`
	Refs             map[string]string `json:"refs,omitempty"`
	Inputs           map[string]any    `json:"inputs,omitempty"`
}

type flowResultWire struct {
	Flow       string         `json:"flow"`
	Status     string         `json:"status"`
	Ref        string         `json:"ref"`
	ReceiptRef string         `json:"receipt_ref"`
	Outputs    map[string]any `json:"outputs"`
}

// CallFlow performs the HTTP leg to a declared flow's webhook.
func (c *N8NClient) CallFlow(ctx context.Context, binding FlowBinding, req FlowRequest) (FlowResult, error) {
	authValue, err := c.currentAuthValue()
	if err != nil {
		return FlowResult{}, err
	}

	wire := flowRequestWire{
		Flow:             binding.Name,
		RequestID:        req.RequestID,
		MatterID:         req.MatterID,
		CourtCaseID:      req.CourtCaseID,
		SourceVersionRef: string(req.SourceVersionRef),
		DeclaredFormat:   req.DeclaredFormat,
		Inputs:           req.Inputs,
	}
	if len(req.Refs) > 0 {
		wire.Refs = make(map[string]string, len(req.Refs))
		for name, ref := range req.Refs {
			wire.Refs[name] = string(ref)
		}
	}
	body, err := json.Marshal(wire)
	if err != nil {
		return FlowResult{}, fmt.Errorf("temporal: encode FlowRequest for %q: %w", binding.Name, err)
	}

	callCtx, cancel := context.WithTimeout(ctx, binding.Timeout())
	defer cancel()
	httpReq, err := http.NewRequestWithContext(callCtx, http.MethodPost, c.baseURL+"/"+binding.WebhookPath, bytes.NewReader(body))
	if err != nil {
		return FlowResult{}, fmt.Errorf("temporal: build n8n request for flow %q: %w", binding.Name, err)
	}
	httpReq.Header.Set("Content-Type", "application/json")
	httpReq.Header.Set("X-Request-ID", req.RequestID)
	httpReq.Header.Set("Idempotency-Key", req.RequestID)
	httpReq.Header.Set(c.authHeader, authValue)

	resp, err := c.httpClient.Do(httpReq)
	if err != nil {
		return FlowResult{}, fmt.Errorf("temporal: call n8n flow %q: %w", binding.Name, err)
	}
	defer resp.Body.Close()
	limited := io.LimitReader(resp.Body, maxN8NResponseBytes)

	if resp.StatusCode != http.StatusOK {
		var errBody n8nErrorBody
		_ = json.NewDecoder(limited).Decode(&errBody)
		message := errBody.Error
		if message == "" {
			message = resp.Status
		}
		return FlowResult{}, fmt.Errorf("temporal: n8n flow %q returned %d: %s", binding.Name, resp.StatusCode, message)
	}

	decoder := json.NewDecoder(limited)
	decoder.DisallowUnknownFields()
	var wireResult flowResultWire
	if err := decoder.Decode(&wireResult); err != nil {
		return FlowResult{}, fmt.Errorf("temporal: decode n8n flow %q result: %w", binding.Name, err)
	}
	var trailing any
	if err := decoder.Decode(&trailing); !errors.Is(err, io.EOF) {
		if err == nil {
			return FlowResult{}, fmt.Errorf("temporal: n8n flow %q result contained trailing data", binding.Name)
		}
		return FlowResult{}, fmt.Errorf("temporal: n8n flow %q result malformed: %w", binding.Name, err)
	}

	result := FlowResult{
		Flow:       wireResult.Flow,
		Status:     proffer.Status(wireResult.Status),
		Ref:        proffer.Ref(wireResult.Ref),
		ReceiptRef: proffer.Ref(wireResult.ReceiptRef),
		Outputs:    wireResult.Outputs,
	}
	if err := validateFlowResult(binding, result); err != nil {
		return FlowResult{}, err
	}
	return result, nil
}

// validateFlowResult refuses a result that answers for a different flow or
// claims success without producing anything usable downstream.
func validateFlowResult(binding FlowBinding, result FlowResult) error {
	if result.Flow != binding.Name {
		return fmt.Errorf("temporal: asked n8n flow %q but the result names %q", binding.Name, result.Flow)
	}
	switch result.Status {
	case proffer.StatusSuccess:
		if strings.TrimSpace(string(result.Ref)) == "" && len(result.Outputs) == 0 {
			return fmt.Errorf("temporal: n8n flow %q reported success with neither a ref nor outputs", binding.Name)
		}
	case proffer.StatusFailed, proffer.StatusNotApplicable:
	default:
		return fmt.Errorf("temporal: n8n flow %q reported unknown status %q", binding.Name, result.Status)
	}
	return nil
}
