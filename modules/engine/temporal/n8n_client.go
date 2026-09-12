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
	"time"

	"github.com/Cursedpotential/probata/engine/proffer"
	"github.com/Cursedpotential/probata/engine/stagegraph"
)

const (
	maxN8NResponseBytes  int64 = 64 << 10
	maxN8NAuthValueBytes       = 4096
)

// stageRoute is everything the N8N client needs to reach and safely wait on
// one n8n-backed Activity: its webhook path, the compact set of Refs keys
// the n8n workflow's own validator requires plus the bounded durable handler
// decision references accepted after content-backed validation, and how long the
// HTTP leg to n8n is allowed to run.
type stageRoute struct {
	path        string
	requireRefs []string
	allowRefs   []string
	timeout     time.Duration
}

func stageRoutes(cfg Config) map[stagegraph.StageID]stageRoute {
	return map[stagegraph.StageID]stageRoute{
		stagegraph.SelectParser: {
			path:        "proffer/select-parser-activity",
			requireRefs: []string{"filesystem_metadata", "container_manifest", "metadata_manifest"},
			allowRefs:   handlerDecisionRefNames(),
			timeout:     cfg.SelectHTTPTimeout,
		},
		stagegraph.ExecuteParser: {
			path:        "proffer/execute-parser-activity",
			requireRefs: []string{"parser_selection", "original", "parser_options"},
			allowRefs:   handlerDecisionRefNames(),
			timeout:     cfg.ExecuteHTTPTimeout,
		},
	}
}

func handlerDecisionRefNames() []string {
	return []string{"handler_recommendation", "handler_decision", "handler_validation", "detected_format", "content_signature", "handler_compatibility"}
}

// N8NClient calls the two n8n-backed parser Activity webhooks over HTTP. It
// carries no parsing, persistence, or hashing logic of its own: it is a
// contract-shaped envelope around the exact wire format the existing n8n
// workflows already validate (request_id/source_version_ref/declared_format/
// refs in, stage/status/ref/receipt_ref out).
type N8NClient struct {
	baseURL       string
	authHeader    string
	authValueFile string
	routes        map[stagegraph.StageID]stageRoute
	httpClient    *http.Client
}

// NewN8NClient builds a client from Config. It fails closed if the base URL
// or auth header/file are empty — an unauthenticated call to the n8n
// webhook is not a degraded mode this package supports.
func NewN8NClient(cfg Config) (*N8NClient, error) {
	if strings.TrimSpace(cfg.N8NBaseURL) == "" {
		return nil, errors.New("temporal: n8n client requires a base URL")
	}
	if strings.TrimSpace(cfg.N8NAuthHeader) == "" {
		return nil, errors.New("temporal: n8n client requires an auth header name")
	}
	if strings.TrimSpace(cfg.N8NAuthValueFile) == "" {
		return nil, errors.New("temporal: n8n client requires an auth value file")
	}
	if !isAbsoluteRuntimePath(cfg.N8NAuthValueFile) {
		return nil, errors.New("temporal: n8n auth value file is unavailable or invalid")
	}
	return &N8NClient{
		baseURL:       strings.TrimRight(cfg.N8NBaseURL, "/"),
		authHeader:    cfg.N8NAuthHeader,
		authValueFile: cfg.N8NAuthValueFile,
		routes:        stageRoutes(cfg),
		httpClient:    &http.Client{},
	}, nil
}

func (c *N8NClient) currentAuthValue() (string, error) {
	value, err := ReadRuntimeSecretFile(c.authValueFile, maxN8NAuthValueBytes)
	if err != nil {
		return "", errors.New("temporal: n8n auth value file is unavailable or invalid")
	}
	return value, nil
}

// stageRequestWire is the exact JSON shape the n8n workflows' "Validate +
// Shape StageRequest" code node accepts: exactly these four fields, refs
// values as plain strings.
type stageRequestWire struct {
	RequestID        string            `json:"request_id"`
	SourceVersionRef string            `json:"source_version_ref"`
	DeclaredFormat   string            `json:"declared_format"`
	Refs             map[string]string `json:"refs"`
}

// stageResultWire is the exact JSON shape the n8n workflows' "Respond to
// Webhook" node returns on success: exactly these four fields, all non-empty
// strings. The n8n contract never sends a fifth "reason" field on the
// success path this client is built to reach — see
// docker/n8n/workflows/proffer/README.md.
type stageResultWire struct {
	Stage      string `json:"stage"`
	Status     string `json:"status"`
	Ref        string `json:"ref"`
	ReceiptRef string `json:"receipt_ref"`
}

type n8nErrorBody struct {
	Error string `json:"error"`
}

// CallStage sends one StageRequest to the n8n webhook for id and returns the
// StageResult it validated and forwarded. It fails closed on every path: an
// unroutable stage, a request missing required refs, a non-2xx HTTP
// response, or a StageResult that doesn't match the invoked stage or carry a
// success status all return a plain error and no StageResult — matching
// engine/proffer's convention that an Activity execution error (not a business
// StatusFailed) means "no receipt exists to report."
func (c *N8NClient) CallStage(ctx context.Context, id stagegraph.StageID, req proffer.StageRequest) (proffer.StageResult, error) {
	route, ok := c.routes[id]
	if !ok {
		return proffer.StageResult{}, fmt.Errorf("temporal: n8n client has no route for stage %q", id)
	}
	if err := validateOutboundRequest(route, req); err != nil {
		return proffer.StageResult{}, err
	}
	authValue, err := c.currentAuthValue()
	if err != nil {
		return proffer.StageResult{}, err
	}

	wire := stageRequestWire{
		RequestID:        req.RequestID,
		SourceVersionRef: string(req.SourceVersionRef),
		DeclaredFormat:   req.DeclaredFormat,
		Refs:             make(map[string]string, len(req.Refs)),
	}
	for name, ref := range req.Refs {
		wire.Refs[name] = string(ref)
	}
	body, err := json.Marshal(wire)
	if err != nil {
		return proffer.StageResult{}, fmt.Errorf("temporal: encode StageRequest for %q: %w", id, err)
	}

	callCtx, cancel := context.WithTimeout(ctx, route.timeout)
	defer cancel()
	httpReq, err := http.NewRequestWithContext(callCtx, http.MethodPost, c.baseURL+"/"+route.path, bytes.NewReader(body))
	if err != nil {
		return proffer.StageResult{}, fmt.Errorf("temporal: build n8n request for %q: %w", id, err)
	}
	httpReq.Header.Set("Content-Type", "application/json")
	httpReq.Header.Set("X-Request-ID", req.RequestID)
	httpReq.Header.Set("Idempotency-Key", req.RequestID)
	httpReq.Header.Set(c.authHeader, authValue)

	resp, err := c.httpClient.Do(httpReq)
	if err != nil {
		return proffer.StageResult{}, fmt.Errorf("temporal: call n8n %q: %w", id, err)
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
		return proffer.StageResult{}, fmt.Errorf("temporal: n8n %q returned %d: %s", id, resp.StatusCode, message)
	}

	decoder := json.NewDecoder(limited)
	decoder.DisallowUnknownFields()
	var wireResult stageResultWire
	if err := decoder.Decode(&wireResult); err != nil {
		return proffer.StageResult{}, fmt.Errorf("temporal: decode n8n %q StageResult: %w", id, err)
	}
	var trailing any
	if err := decoder.Decode(&trailing); !errors.Is(err, io.EOF) {
		if err == nil {
			return proffer.StageResult{}, fmt.Errorf("temporal: n8n %q StageResult contained trailing data", id)
		}
		return proffer.StageResult{}, fmt.Errorf("temporal: n8n %q StageResult malformed: %w", id, err)
	}

	result := proffer.StageResult{
		Stage:      stagegraph.StageID(wireResult.Stage),
		Status:     proffer.Status(wireResult.Status),
		Ref:        proffer.Ref(wireResult.Ref),
		ReceiptRef: proffer.Ref(wireResult.ReceiptRef),
	}
	if err := validateInboundResult(id, result); err != nil {
		return proffer.StageResult{}, err
	}
	return result, nil
}

func validateOutboundRequest(route stageRoute, req proffer.StageRequest) error {
	if strings.TrimSpace(req.RequestID) == "" {
		return errors.New("temporal: StageRequest.RequestID is required")
	}
	if strings.TrimSpace(string(req.SourceVersionRef)) == "" {
		return errors.New("temporal: StageRequest.SourceVersionRef is required")
	}
	if strings.TrimSpace(req.DeclaredFormat) == "" {
		return errors.New("temporal: StageRequest.DeclaredFormat is required")
	}
	for _, name := range route.requireRefs {
		ref, ok := req.Refs[name]
		if !ok || strings.TrimSpace(string(ref)) == "" {
			return fmt.Errorf("temporal: StageRequest.Refs missing required non-empty %q", name)
		}
	}
	allowed := make(map[string]struct{}, len(route.requireRefs)+len(route.allowRefs))
	for _, name := range append(append([]string(nil), route.requireRefs...), route.allowRefs...) {
		allowed[name] = struct{}{}
	}
	for name, ref := range req.Refs {
		if _, ok := allowed[name]; !ok {
			return fmt.Errorf("temporal: StageRequest.Refs contains unsupported %q", name)
		}
		if strings.TrimSpace(string(ref)) == "" {
			return fmt.Errorf("temporal: StageRequest.Refs contains empty %q", name)
		}
	}
	return nil
}

func validateInboundResult(id stagegraph.StageID, result proffer.StageResult) error {
	if result.Stage != id {
		return fmt.Errorf("temporal: n8n returned stage %q for invoked stage %q", result.Stage, id)
	}
	if result.Status != proffer.StatusSuccess {
		return fmt.Errorf("temporal: n8n %q returned non-success status %q", id, result.Status)
	}
	if strings.TrimSpace(string(result.Ref)) == "" {
		return fmt.Errorf("temporal: n8n %q returned an empty result ref", id)
	}
	if strings.TrimSpace(string(result.ReceiptRef)) == "" {
		return fmt.Errorf("temporal: n8n %q returned an empty receipt ref", id)
	}
	return nil
}
