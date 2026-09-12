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
)

const maxToolRuntimeResponseBytes int64 = 2 << 20

type ToolRuntimeClient struct {
	baseURL string
	client  *http.Client
}

func NewToolRuntimeClient(baseURL string) (*ToolRuntimeClient, error) {
	baseURL = strings.TrimRight(strings.TrimSpace(baseURL), "/")
	parsed, err := url.Parse(baseURL)
	if err != nil || (parsed.Scheme != "http" && parsed.Scheme != "https") || parsed.Host == "" {
		return nil, errors.New("tool-runtime client requires an absolute HTTP(S) base URL")
	}
	return &ToolRuntimeClient{baseURL: baseURL, client: &http.Client{}}, nil
}

func (c *ToolRuntimeClient) Run(ctx context.Context, toolID string, payload map[string]any) (json.RawMessage, error) {
	if c == nil || c.client == nil {
		return nil, errors.New("tool-runtime client is not configured")
	}
	if strings.TrimSpace(toolID) == "" || strings.ContainsAny(toolID, "/?#") {
		return nil, errors.New("tool-runtime client requires a safe exact tool id")
	}
	body, err := json.Marshal(payload)
	if err != nil {
		return nil, fmt.Errorf("encode tool-runtime payload: %w", err)
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.baseURL+"/tools/"+url.PathEscape(toolID)+"/run", bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := c.client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("call tool-runtime %q: %w", toolID, err)
	}
	defer resp.Body.Close()
	limited := io.LimitReader(resp.Body, maxToolRuntimeResponseBytes+1)
	data, err := io.ReadAll(limited)
	if err != nil {
		return nil, fmt.Errorf("read tool-runtime %q response: %w", toolID, err)
	}
	if int64(len(data)) > maxToolRuntimeResponseBytes {
		return nil, fmt.Errorf("tool-runtime %q response exceeds limit", toolID)
	}
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("tool-runtime %q returned %d", toolID, resp.StatusCode)
	}
	var object map[string]any
	if err := json.Unmarshal(data, &object); err != nil || object == nil {
		return nil, fmt.Errorf("tool-runtime %q returned invalid JSON object", toolID)
	}
	return append(json.RawMessage(nil), data...), nil
}

// PlatformToolsClient and NewPlatformToolsClient are temporary source-compatibility
// shims for callers that have not yet adopted the 2026-09-12 component rename.
// New code must use ToolRuntimeClient and NewToolRuntimeClient.
type PlatformToolsClient = ToolRuntimeClient

func NewPlatformToolsClient(baseURL string) (*ToolRuntimeClient, error) {
	return NewToolRuntimeClient(baseURL)
}
