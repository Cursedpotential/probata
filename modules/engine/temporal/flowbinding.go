// Declarative n8n flow bindings: turn an n8n flow into a Temporal Activity by
// DECLARING it, not by writing Go.
//
// WHY (owner, 2026-09-02): "we're going to need a function to take an n8n,
// either node or flow, and create an activity in Temporal out of it and then
// run it... make it flexible for the different types of work that we'll be
// doing in that screen with the different types of data."
//
// Before this, stageRoutes() was a hardcoded map of exactly two routes
// (select-parser, execute-parser). Every new flow meant editing Go, rebuilding,
// and redeploying the worker. A binding registry makes the route table DATA:
// add a row, the flow is callable as an Activity.
//
// ON "NODE OR FLOW": an n8n NODE has no URL — only a flow with a webhook
// trigger is addressable over HTTP. Wrapping a single node therefore means
// generating a one-node flow with a webhook trigger around it, then declaring
// THAT here. This registry is the same either way; node-wrapping is a
// generator that sits on top of it.
//
// ATOMICITY (D-130): one flow invocation is one bounded, retryable unit —
// references travel, payloads do not, and the flow does not know whether a
// Temporal Activity or a direct call invoked it.
//
// Byline: Claude Code · Opus 5 · 2026-09-03.
package temporal

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

const (
	// maxFlowBindingFileBytes bounds the binding document. Bindings are route
	// declarations, never content.
	maxFlowBindingFileBytes = 1 << 20

	// defaultFlowTimeout applies when a binding declares none.
	defaultFlowTimeout = 5 * time.Minute

	// maxFlowTimeout is the ceiling for any single HTTP leg to n8n. Anything
	// longer belongs in a flow that reports progress, not one HTTP call held
	// open past an Activity's own start-to-close budget.
	maxFlowTimeout = 2 * time.Hour
)

// FlowBinding declares one n8n flow as an invocable Activity.
//
// The zero value is not usable; construct through LoadFlowBindings or
// NewFlowRegistry so validation always runs.
type FlowBinding struct {
	// Name is the stable Activity-facing identity, e.g. "chunk_preview".
	// Callers and the operator screen reference this, never the webhook path,
	// so a flow can be re-pathed in n8n without changing any caller.
	Name string `json:"name"`

	// WebhookPath is the n8n webhook path relative to N8NBaseURL, without a
	// leading slash, e.g. "proffer/select-parser-activity".
	WebhookPath string `json:"webhook_path"`

	// RequireRefs names the locator keys this flow's own validator demands.
	// A call missing any of them fails before the HTTP leg, so a
	// misconfiguration surfaces here rather than as an opaque n8n rejection.
	RequireRefs []string `json:"require_refs,omitempty"`

	// RequireInputs names scalar variables the flow demands. This is what
	// makes one registry serve "different types of work with different types
	// of data" — each flow declares its own input contract.
	RequireInputs []string `json:"require_inputs,omitempty"`

	// Description is operator-facing text for the flow-picker screen.
	Description string `json:"description,omitempty"`

	// TimeoutSeconds bounds the HTTP leg. Zero means defaultFlowTimeout.
	TimeoutSeconds int `json:"timeout_seconds,omitempty"`
}

// Timeout resolves the declared timeout, applying the default and the ceiling.
func (b FlowBinding) Timeout() time.Duration {
	if b.TimeoutSeconds <= 0 {
		return defaultFlowTimeout
	}
	d := time.Duration(b.TimeoutSeconds) * time.Second
	if d > maxFlowTimeout {
		return maxFlowTimeout
	}
	return d
}

// validate fails closed on anything that could produce an unroutable or unsafe
// call. Binding names and webhook paths both end up in URLs or Activity
// registrations, so neither may carry traversal or wildcard characters.
func (b FlowBinding) validate() error {
	if err := validateFlowName(b.Name); err != nil {
		return err
	}
	path := strings.TrimSpace(b.WebhookPath)
	if path == "" {
		return fmt.Errorf("flow binding %q: webhook_path is required", b.Name)
	}
	if path != b.WebhookPath {
		return fmt.Errorf("flow binding %q: webhook_path must not carry surrounding whitespace", b.Name)
	}
	if strings.HasPrefix(path, "/") || strings.HasPrefix(strings.ToLower(path), "http") {
		return fmt.Errorf("flow binding %q: webhook_path must be relative to the n8n base URL", b.Name)
	}
	if strings.ContainsAny(path, "?#\\") {
		return fmt.Errorf("flow binding %q: webhook_path must not carry a query, fragment, or backslash", b.Name)
	}
	for _, segment := range strings.Split(path, "/") {
		if segment == "" || segment == "." || segment == ".." {
			return fmt.Errorf("flow binding %q: webhook_path has an empty or traversing segment", b.Name)
		}
	}
	if err := validateKeyList(b.Name, "require_refs", b.RequireRefs); err != nil {
		return err
	}
	if err := validateKeyList(b.Name, "require_inputs", b.RequireInputs); err != nil {
		return err
	}
	if b.TimeoutSeconds < 0 {
		return fmt.Errorf("flow binding %q: timeout_seconds must not be negative", b.Name)
	}
	return nil
}

func validateFlowName(name string) error {
	if strings.TrimSpace(name) == "" {
		return errors.New("flow binding: name is required")
	}
	if name != strings.TrimSpace(name) {
		return fmt.Errorf("flow binding %q: name must not carry surrounding whitespace", name)
	}
	if len(name) > 128 {
		return fmt.Errorf("flow binding %q: name is too long", name)
	}
	for _, r := range name {
		switch {
		case r >= 'a' && r <= 'z', r >= 'A' && r <= 'Z', r >= '0' && r <= '9':
		case r == '_' || r == '-' || r == '.':
		default:
			return fmt.Errorf("flow binding %q: name contains an unsupported character %q", name, r)
		}
	}
	return nil
}

func validateKeyList(binding, field string, keys []string) error {
	seen := make(map[string]struct{}, len(keys))
	for _, key := range keys {
		if strings.TrimSpace(key) == "" || key != strings.TrimSpace(key) {
			return fmt.Errorf("flow binding %q: %s contains an empty or padded key", binding, field)
		}
		if _, dup := seen[key]; dup {
			return fmt.Errorf("flow binding %q: %s repeats key %q", binding, field, key)
		}
		seen[key] = struct{}{}
	}
	return nil
}

// FlowRegistry is the resolved, validated set of declared flows.
type FlowRegistry struct {
	byName map[string]FlowBinding
}

// NewFlowRegistry validates and indexes bindings. Duplicate names are refused:
// two flows answering to one Activity name is an ambiguity that must fail at
// startup, never at call time.
func NewFlowRegistry(bindings []FlowBinding) (*FlowRegistry, error) {
	byName := make(map[string]FlowBinding, len(bindings))
	for _, binding := range bindings {
		if err := binding.validate(); err != nil {
			return nil, err
		}
		if _, dup := byName[binding.Name]; dup {
			return nil, fmt.Errorf("flow binding %q is declared more than once", binding.Name)
		}
		byName[binding.Name] = binding
	}
	return &FlowRegistry{byName: byName}, nil
}

// LoadFlowBindings reads a JSON document of bindings from an absolute path.
// A missing path yields an empty registry rather than an error: declaring no
// extra flows is a legitimate configuration, and the two built-in parser
// stages keep working without any binding file at all.
func LoadFlowBindings(path string) (*FlowRegistry, error) {
	trimmed := strings.TrimSpace(path)
	if trimmed == "" {
		return NewFlowRegistry(nil)
	}
	if trimmed != path || !filepath.IsAbs(path) {
		return nil, errors.New("flow bindings: path must be absolute and unpadded")
	}
	info, err := os.Stat(path)
	if errors.Is(err, os.ErrNotExist) {
		return NewFlowRegistry(nil)
	}
	if err != nil {
		return nil, fmt.Errorf("flow bindings: stat %s: %w", path, err)
	}
	if !info.Mode().IsRegular() {
		return nil, errors.New("flow bindings: path must be a regular file")
	}
	if info.Size() > maxFlowBindingFileBytes {
		return nil, errors.New("flow bindings: file is implausibly large")
	}
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("flow bindings: read %s: %w", path, err)
	}
	var doc struct {
		Bindings *[]FlowBinding `json:"bindings"`
	}
	decoder := json.NewDecoder(strings.NewReader(string(raw)))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&doc); err != nil {
		return nil, fmt.Errorf("flow bindings: %s must be {\"bindings\":[...]}: %w", path, err)
	}
	if doc.Bindings == nil {
		return nil, fmt.Errorf("flow bindings: %s must contain a bindings array", path)
	}
	var trailing any
	if err := decoder.Decode(&trailing); !errors.Is(err, io.EOF) {
		if err == nil {
			return nil, fmt.Errorf("flow bindings: %s contains trailing JSON values", path)
		}
		return nil, fmt.Errorf("flow bindings: %s contains trailing data: %w", path, err)
	}
	return NewFlowRegistry(*doc.Bindings)
}

// Lookup resolves a declared flow by name.
func (r *FlowRegistry) Lookup(name string) (FlowBinding, error) {
	if r == nil {
		return FlowBinding{}, errors.New("flow bindings: registry is not configured")
	}
	binding, ok := r.byName[name]
	if !ok {
		return FlowBinding{}, fmt.Errorf("flow bindings: no flow named %q is declared", name)
	}
	return binding, nil
}

// Names lists declared flows in stable order, for the operator screen's picker
// and for startup logging.
func (r *FlowRegistry) Names() []string {
	if r == nil {
		return nil
	}
	names := make([]string, 0, len(r.byName))
	for name := range r.byName {
		names = append(names, name)
	}
	sort.Strings(names)
	return names
}

// Count reports how many extra n8n flows are declared for RunFlow. It is
// intended for bounded startup/health telemetry; it does not assert that the
// corresponding n8n webhooks are active. Callers that need operator metadata
// should use List instead.
func (r *FlowRegistry) Count() int {
	if r == nil {
		return 0
	}
	return len(r.byName)
}

// List returns every declared binding in stable order, so the screen can show
// each flow's description and its input contract without a second lookup.
func (r *FlowRegistry) List() []FlowBinding {
	if r == nil {
		return nil
	}
	out := make([]FlowBinding, 0, len(r.byName))
	for _, name := range r.Names() {
		out = append(out, r.byName[name])
	}
	return out
}
