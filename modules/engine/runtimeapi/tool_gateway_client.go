// ToolGatewayClient is the ONLY sanctioned way an Activity reaches a platform
// tool (D-132).
//
// It speaks the gateway contract, not the raw tool-runtime contract: a
// LOCATOR plus tool-specific args. It never sends a host path, because handing
// a path across a host boundary is the defect the gateway exists to remove —
// the Proffer worker runs on ovh-files, tool-runtime on ovh-app, and a
// worker-local path simply does not exist over there.
//
// The gateway authenticates callers with a bearer service token in addition to
// its always-on tailnet peer check, so this client FAILS CLOSED when no token
// is configured rather than emitting requests that would all return 401.
//
// Byline: Claude Code · Opus 5 · 2026-09-05.
package runtimeapi

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"

	"github.com/Cursedpotential/probata/engine/proffer"
)

const maxToolGatewayResponseBytes int64 = 2 << 20

// ToolGatewayClient calls tool-gateway's POST /tools/{tool_id}/run.
type ToolGatewayClient struct {
	baseURL      string
	serviceToken string
	client       *http.Client
}

// NewToolGatewayClient requires an absolute HTTP(S) base URL and a non-empty
// service token. An empty token is a configuration defect, never a permitted
// "anonymous" mode: every authenticated gateway route would answer 401 and the
// failure would surface far from its cause.
func NewToolGatewayClient(baseURL, serviceToken string) (*ToolGatewayClient, error) {
	baseURL = strings.TrimRight(strings.TrimSpace(baseURL), "/")
	parsed, err := url.Parse(baseURL)
	if err != nil || (parsed.Scheme != "http" && parsed.Scheme != "https") || parsed.Host == "" {
		return nil, errors.New("tool gateway client requires an absolute HTTP(S) base URL")
	}
	if strings.TrimSpace(serviceToken) == "" {
		return nil, errors.New("tool gateway client requires a service token: the gateway is the only sanctioned path to platform tools (D-132) and rejects unauthenticated callers")
	}
	return &ToolGatewayClient{baseURL: baseURL, serviceToken: serviceToken, client: &http.Client{}}, nil
}

// Run posts {"source_ref": ..., "args": {...}} for toolID.
//
// args carries tool options only. "path" is rejected here as well as by the
// gateway: a caller that names a host path has already lost the property this
// whole component chain protects.
func (c *ToolGatewayClient) Run(ctx context.Context, toolID string, sourceRef proffer.Ref, args map[string]any) (json.RawMessage, error) {
	if c == nil || c.client == nil {
		return nil, errors.New("tool gateway client is not configured")
	}
	if strings.TrimSpace(toolID) == "" || strings.ContainsAny(toolID, "/?#") {
		return nil, errors.New("tool gateway client requires a safe exact tool id")
	}
	if strings.TrimSpace(string(sourceRef)) == "" {
		return nil, errors.New("tool gateway client requires a non-empty source locator")
	}
	if _, taken := args["path"]; taken {
		return nil, errors.New("tool gateway client must not send a host path; the gateway materializes the locator itself")
	}
	if args == nil {
		args = map[string]any{}
	}
	body, err := json.Marshal(struct {
		SourceRef string         `json:"source_ref"`
		Args      map[string]any `json:"args"`
	}{SourceRef: string(sourceRef), Args: args})
	if err != nil {
		return nil, fmt.Errorf("encode tool gateway payload: %w", err)
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.baseURL+"/tools/"+url.PathEscape(toolID)+"/run", bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+c.serviceToken)
	resp, err := c.client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("call tool gateway %q: %w", toolID, err)
	}
	defer resp.Body.Close()
	limited := io.LimitReader(resp.Body, maxToolGatewayResponseBytes+1)
	data, err := io.ReadAll(limited)
	if err != nil {
		return nil, fmt.Errorf("read tool gateway %q response: %w", toolID, err)
	}
	if int64(len(data)) > maxToolGatewayResponseBytes {
		return nil, fmt.Errorf("tool gateway %q response exceeds limit", toolID)
	}
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("tool gateway %q returned %d", toolID, resp.StatusCode)
	}
	var object map[string]any
	if err := json.Unmarshal(data, &object); err != nil || object == nil {
		return nil, fmt.Errorf("tool gateway %q returned invalid JSON object", toolID)
	}
	return append(json.RawMessage(nil), data...), nil
}
