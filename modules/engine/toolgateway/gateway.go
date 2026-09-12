// Package toolgateway is the locator-addressed front end for the Python
// tool-runtime registry.
//
// WHY THIS EXISTS (D-132, ruled 2026-09-02)
//
// The Python tools take a local filesystem path and do exactly one thing with
// it. That contract is correct and stays (D-130 rule 1). The defect was that
// callers were handing those tools a path from a DIFFERENT HOST: the Proffer worker
// runs on ovh-files, tool-runtime runs on ovh-app, and
// `assess_source_repair_activity` passed a worker-local path straight through.
// tool-runtime answered 404 with the path as the body, because the file
// genuinely was not there.
//
// This gateway fixes the class, not the call site. It accepts LOCATORS
// (upload://, r2://) rather than host paths, resolves them through the same
// acquisition.NewSchemeRouter the engine uses — one resolver implementation
// platform-wide, never a second copy — materializes the bytes where the tool
// can actually read them, and only then calls the tool with a path that
// genuinely exists.
//
// A same-day expedient (a second tool-runtime co-located with the worker) was
// explicitly rejected by the owner: "it becomes temporary-permanent."
//
// ATOMICITY (D-130): one Run call is one bounded, retryable unit of work — no
// ambient state, no orchestration, deterministic given its inputs. It is
// schedulable as a Temporal Activity or wrappable as an n8n node, and it does
// not know which of those called it.
//
// Byline: Claude Code · Opus 5 · 2026-09-02.
package toolgateway

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
	"strings"

	platformpostgres "github.com/Cursedpotential/probata/engine/postgres"
	"github.com/Cursedpotential/probata/engine/proffer"
)

// ToolRunner is the minimal tool-runtime surface this package depends on, so
// tests substitute a fake instead of a live service.
type ToolRunner interface {
	Run(ctx context.Context, toolID string, payload map[string]any) (json.RawMessage, error)
}

// Gateway resolves locators and dispatches to tool-runtime.
//
// MaterializeDir MUST be visible to the tool-runtime process at the same
// absolute path. That is a deployment requirement, not a suggestion: the whole
// point of this component is that the path it hands over resolves on the other
// side. Deploy the gateway alongside tool-runtime sharing this directory.
//
// SOURCE BYTES CROSS HOSTS VIA THE OBJECT STORE, NOT A SHARED DISK (owner,
// 2026-09-02: "you can object store but use b2 / mount an object if you need
// to"). The two hosts share no filesystem — ovh-app's /r2 volume is an empty
// local ext4 mount, not an R2 mount. So anything a tool must read from another
// host is addressed as r2:// or b2:// and fetched over the network by the
// resolvers that already exist (acquisition.NewCloudflareR2AcquisitionResolver,
// acquisition.NewBackblazeB2AcquisitionResolver). Only the short-lived
// materialized copy is local, and only the gateway and its tool see it.
type Gateway struct {
	Runner         ToolRunner
	Resolve        platformpostgres.ImmutableAcquisitionResolver
	MaterializeDir string
}

// pathArgKey is the argument the Python tools expect. Every file-taking tool in
// the registry uses this one key; the gateway owns filling it so callers never
// name a host path themselves.
const pathArgKey = "path"

// maxToolIDLen bounds the tool id before it is ever placed in a URL path.
const maxToolIDLen = 128

func (g *Gateway) validate() error {
	if g == nil {
		return errors.New("tool gateway: gateway is nil")
	}
	if g.Runner == nil {
		return errors.New("tool gateway: tool-runtime runner is required")
	}
	if g.Resolve == nil {
		return errors.New("tool gateway: acquisition resolver is required")
	}
	if strings.TrimSpace(g.MaterializeDir) == "" {
		return errors.New("tool gateway: materialization directory is required")
	}
	if !filepath.IsAbs(g.MaterializeDir) {
		return errors.New("tool gateway: materialization directory must be absolute")
	}
	return nil
}

// ValidateToolID rejects anything that could escape or reshape the tool URL.
// Tool ids are registry keys like "repair.detect" or "documents.extract-text".
func ValidateToolID(id string) error {
	trimmed := strings.TrimSpace(id)
	if trimmed == "" {
		return errors.New("tool gateway: tool id is required")
	}
	if len(trimmed) > maxToolIDLen {
		return errors.New("tool gateway: tool id is too long")
	}
	if trimmed != id {
		return errors.New("tool gateway: tool id must not carry surrounding whitespace")
	}
	for _, r := range id {
		switch {
		case r >= 'a' && r <= 'z', r >= 'A' && r <= 'Z', r >= '0' && r <= '9':
		case r == '.' || r == '-' || r == '_':
		default:
			return fmt.Errorf("tool gateway: tool id contains an unsupported character %q", r)
		}
	}
	return nil
}

// Run resolves sourceRef, materializes it inside MaterializeDir, and invokes
// toolID with the resulting path merged into args.
//
// args may carry any tool-specific options (format, sample_limit, ...). It MUST
// NOT carry "path": callers never name a host path, because naming one is the
// bug this component exists to prevent.
func (g *Gateway) Run(ctx context.Context, toolID string, sourceRef proffer.Ref, args map[string]any) (json.RawMessage, error) {
	if err := g.validate(); err != nil {
		return nil, err
	}
	if err := ValidateToolID(toolID); err != nil {
		return nil, err
	}
	if _, taken := args[pathArgKey]; taken {
		return nil, errors.New("tool gateway: callers must not supply a host path; pass a locator as source_ref")
	}
	if strings.TrimSpace(string(sourceRef)) == "" {
		return nil, errors.New("tool gateway: source_ref locator is required")
	}

	acquired, err := g.Resolve(ctx, sourceRef)
	if err != nil {
		return nil, fmt.Errorf("tool gateway: resolve %q: %w", sourceRef, err)
	}

	localPath, cleanup, err := g.materialize(ctx, acquired)
	if err != nil {
		return nil, err
	}
	// The materialized copy is scratch, never evidence: it is derived from an
	// already-sealed immutable object and is safe to remove. Custody lives with
	// the sealed object, not with this copy.
	defer cleanup()

	payload := make(map[string]any, len(args)+1)
	for k, v := range args {
		payload[k] = v
	}
	payload[pathArgKey] = localPath

	result, err := g.Runner.Run(ctx, toolID, payload)
	if err != nil {
		return nil, fmt.Errorf("tool gateway: run %q: %w", toolID, err)
	}
	return result, nil
}

// materialize places the acquired object inside MaterializeDir and returns a
// path plus a cleanup func. It re-verifies the digest before handing anything
// to a tool: an object that changed between acquisition and use must fail
// closed rather than silently feed altered bytes into an evidence pipeline.
func (g *Gateway) materialize(ctx context.Context, acquired platformpostgres.ImmutableAcquisition) (string, func(), error) {
	noop := func() {}
	if err := ctx.Err(); err != nil {
		return "", noop, err
	}
	if len(acquired.ContentSHA256) != sha256.Size {
		return "", noop, errors.New("tool gateway: acquisition did not carry a sha256 digest")
	}
	digest := hex.EncodeToString(acquired.ContentSHA256)

	if err := os.MkdirAll(g.MaterializeDir, 0o750); err != nil {
		return "", noop, fmt.Errorf("tool gateway: create materialization directory: %w", err)
	}
	target := filepath.Join(g.MaterializeDir, digest+".source")

	// Content-addressed, so a concurrent or previous run of the same object is
	// a cache hit rather than a conflict. Verify before reuse.
	if info, statErr := os.Stat(target); statErr == nil && info.Mode().IsRegular() {
		if verifyErr := verifyFileDigest(target, acquired.ContentSHA256); verifyErr == nil {
			return target, noop, nil
		}
	}

	source, err := openAcquiredObject(acquired)
	if err != nil {
		return "", noop, err
	}
	defer source.Close()

	partial := target + ".partial"
	out, err := os.OpenFile(partial, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0o600)
	if err != nil {
		return "", noop, fmt.Errorf("tool gateway: create staging copy: %w", err)
	}
	hasher := sha256.New()
	written, copyErr := io.Copy(io.MultiWriter(out, hasher), source)
	closeErr := out.Close()
	if copyErr != nil {
		_ = os.Remove(partial)
		return "", noop, fmt.Errorf("tool gateway: materialize object: %w", copyErr)
	}
	if closeErr != nil {
		_ = os.Remove(partial)
		return "", noop, fmt.Errorf("tool gateway: close staging copy: %w", closeErr)
	}
	if acquired.ByteLength > 0 && written != acquired.ByteLength {
		_ = os.Remove(partial)
		return "", noop, fmt.Errorf("tool gateway: materialized %d bytes, acquisition declared %d", written, acquired.ByteLength)
	}
	if !equalDigest(hasher.Sum(nil), acquired.ContentSHA256) {
		_ = os.Remove(partial)
		return "", noop, errors.New("tool gateway: materialized object digest does not match the acquisition")
	}
	if err := os.Rename(partial, target); err != nil {
		_ = os.Remove(partial)
		return "", noop, fmt.Errorf("tool gateway: publish materialized object: %w", err)
	}
	return target, func() { _ = os.Remove(target) }, nil
}

// openAcquiredObject reads the sealed object the resolver returned. Inline
// bytes are supported because small acquisitions may be delivered that way.
func openAcquiredObject(acquired platformpostgres.ImmutableAcquisition) (io.ReadCloser, error) {
	if len(acquired.InlineBytes) > 0 {
		return io.NopCloser(strings.NewReader(string(acquired.InlineBytes))), nil
	}
	path, err := localPathFromFileURI(acquired.ObjectURI)
	if err != nil {
		return nil, err
	}
	file, err := os.Open(path)
	if err != nil {
		return nil, fmt.Errorf("tool gateway: open acquired object: %w", err)
	}
	return file, nil
}

// localPathFromFileURI converts the resolver's sealed file:// URI to a path.
func localPathFromFileURI(raw string) (string, error) {
	trimmed := strings.TrimSpace(raw)
	if trimmed == "" {
		return "", errors.New("tool gateway: acquisition returned an empty object URI")
	}
	parsed, err := url.Parse(trimmed)
	if err != nil || !strings.EqualFold(parsed.Scheme, "file") {
		return "", fmt.Errorf("tool gateway: acquisition object URI %q is not a file:// URI", raw)
	}
	path := parsed.Path
	// Windows-style file:///C:/x paths arrive with a leading slash.
	if len(path) > 2 && path[0] == '/' && path[2] == ':' {
		path = path[1:]
	}
	if path == "" {
		return "", errors.New("tool gateway: acquisition object URI has no path")
	}
	return filepath.FromSlash(path), nil
}

func verifyFileDigest(path string, want []byte) error {
	file, err := os.Open(path)
	if err != nil {
		return err
	}
	defer file.Close()
	hasher := sha256.New()
	if _, err := io.Copy(hasher, file); err != nil {
		return err
	}
	if !equalDigest(hasher.Sum(nil), want) {
		return errors.New("tool gateway: cached object digest mismatch")
	}
	return nil
}

func equalDigest(a, b []byte) bool {
	if len(a) != len(b) {
		return false
	}
	var diff byte
	for i := range a {
		diff |= a[i] ^ b[i]
	}
	return diff == 0
}
