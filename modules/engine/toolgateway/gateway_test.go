// Byline: Claude Code · Opus 5 · 2026-09-02.
package toolgateway

import (
	"context"
	"crypto/sha256"
	"encoding/json"
	"errors"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"

	platformpostgres "github.com/Cursedpotential/probata/engine/postgres"
	"github.com/Cursedpotential/probata/engine/proffer"
)

type fakeRunner struct {
	calls    int
	lastID   string
	lastArgs map[string]any
	err      error
}

func (f *fakeRunner) Run(_ context.Context, toolID string, payload map[string]any) (json.RawMessage, error) {
	f.calls++
	f.lastID = toolID
	f.lastArgs = payload
	if f.err != nil {
		return nil, f.err
	}
	return json.RawMessage(`{"ok":true}`), nil
}

// sealObject writes content to a sealed-object file and returns a resolver that
// hands it back the way the real acquisition resolvers do.
func sealObject(t *testing.T, content []byte) (platformpostgres.ImmutableAcquisitionResolver, string) {
	t.Helper()
	dir := t.TempDir()
	path := filepath.Join(dir, "sealed.source")
	if err := os.WriteFile(path, content, 0o600); err != nil {
		t.Fatalf("write sealed object: %v", err)
	}
	sum := sha256.Sum256(content)
	uri := "file://" + filepath.ToSlash(path)
	if !strings.HasPrefix(filepath.ToSlash(path), "/") {
		uri = "file:///" + filepath.ToSlash(path)
	}
	return func(_ context.Context, _ proffer.Ref) (platformpostgres.ImmutableAcquisition, error) {
		return platformpostgres.ImmutableAcquisition{
			StorageClass:  "sealed",
			ObjectURI:     uri,
			ContentSHA256: sum[:],
			ByteLength:    int64(len(content)),
		}, nil
	}, path
}

func newGateway(t *testing.T, resolve platformpostgres.ImmutableAcquisitionResolver, runner ToolRunner) *Gateway {
	t.Helper()
	return &Gateway{Runner: runner, Resolve: resolve, MaterializeDir: t.TempDir()}
}

// The whole point of the component: the tool receives a path that exists.
func TestRunHandsToolAnExistingLocalPath(t *testing.T) {
	content := []byte("<smses count=\"1\"><sms body=\"hi\"/></smses>")
	resolve, _ := sealObject(t, content)
	runner := &fakeRunner{}
	g := newGateway(t, resolve, runner)

	var observedPath string
	var existedDuringCall bool
	probe := &fakeRunner{}
	g.Runner = runnerFunc(func(_ context.Context, toolID string, payload map[string]any) (json.RawMessage, error) {
		probe.calls++
		observedPath, _ = payload["path"].(string)
		_, statErr := os.Stat(observedPath)
		existedDuringCall = statErr == nil
		return json.RawMessage(`{"ok":true}`), nil
	})

	out, err := g.Run(context.Background(), "repair.detect", proffer.Ref("upload://abc"), map[string]any{"sample_limit": 25})
	if err != nil {
		t.Fatalf("Run: %v", err)
	}
	if string(out) != `{"ok":true}` {
		t.Fatalf("unexpected tool output: %s", out)
	}
	if !existedDuringCall {
		t.Fatal("tool was given a path that did not exist at call time — this is the bug the gateway exists to prevent")
	}
	if !strings.HasPrefix(observedPath, g.MaterializeDir) {
		t.Fatalf("materialized outside the configured directory: %s", observedPath)
	}
	// Scratch copy is removed after the call; custody lives with the sealed object.
	if _, err := os.Stat(observedPath); !os.IsNotExist(err) {
		t.Fatalf("materialized copy was not cleaned up: %v", err)
	}
}

type runnerFunc func(context.Context, string, map[string]any) (json.RawMessage, error)

func (f runnerFunc) Run(ctx context.Context, id string, p map[string]any) (json.RawMessage, error) {
	return f(ctx, id, p)
}

// Options pass through; the gateway only owns "path".
func TestRunPassesArgsThroughAndOwnsPath(t *testing.T) {
	resolve, _ := sealObject(t, []byte("data"))
	runner := &fakeRunner{}
	g := newGateway(t, resolve, runner)
	if _, err := g.Run(context.Background(), "repair.preview", proffer.Ref("upload://abc"),
		map[string]any{"format": "smsbackuprestore_xml", "sample_limit": 25}); err != nil {
		t.Fatalf("Run: %v", err)
	}
	if runner.lastID != "repair.preview" {
		t.Fatalf("tool id not forwarded: %q", runner.lastID)
	}
	if runner.lastArgs["format"] != "smsbackuprestore_xml" || runner.lastArgs["sample_limit"] != 25 {
		t.Fatalf("args not forwarded: %#v", runner.lastArgs)
	}
	if _, ok := runner.lastArgs["path"].(string); !ok {
		t.Fatal("gateway did not supply a path")
	}
}

// Callers must never name a host path — that is the defect being eliminated.
func TestRunRejectsCallerSuppliedPath(t *testing.T) {
	resolve, _ := sealObject(t, []byte("data"))
	g := newGateway(t, resolve, &fakeRunner{})
	_, err := g.Run(context.Background(), "repair.detect", proffer.Ref("upload://abc"),
		map[string]any{"path": "/data/proffer/source-objects/objects/sha256/aa/aa.source"})
	if err == nil || !strings.Contains(err.Error(), "must not supply a host path") {
		t.Fatalf("expected caller-supplied path to be refused, got %v", err)
	}
}

// An object that changed between acquisition and use must fail closed rather
// than feed altered bytes into an evidence pipeline.
func TestMaterializeFailsClosedOnDigestMismatch(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "sealed.source")
	if err := os.WriteFile(path, []byte("tampered"), 0o600); err != nil {
		t.Fatal(err)
	}
	wrong := sha256.Sum256([]byte("original"))
	uri := "file:///" + strings.TrimPrefix(filepath.ToSlash(path), "/")
	resolve := func(_ context.Context, _ proffer.Ref) (platformpostgres.ImmutableAcquisition, error) {
		return platformpostgres.ImmutableAcquisition{
			ObjectURI: uri, ContentSHA256: wrong[:], ByteLength: int64(len("tampered")),
		}, nil
	}
	runner := &fakeRunner{}
	g := newGateway(t, resolve, runner)
	_, err := g.Run(context.Background(), "repair.detect", proffer.Ref("upload://abc"), nil)
	if err == nil || !strings.Contains(err.Error(), "digest does not match") {
		t.Fatalf("expected digest mismatch to fail closed, got %v", err)
	}
	if runner.calls != 0 {
		t.Fatal("tool was invoked despite a digest mismatch")
	}
}

// Activities get retried. Two identical calls must both succeed (D-130 rule 3).
func TestRunIsSafelyRetryable(t *testing.T) {
	resolve, _ := sealObject(t, []byte("retry me"))
	runner := &fakeRunner{}
	g := newGateway(t, resolve, runner)
	for i := 0; i < 3; i++ {
		if _, err := g.Run(context.Background(), "repair.detect", proffer.Ref("upload://abc"), nil); err != nil {
			t.Fatalf("attempt %d failed: %v", i+1, err)
		}
	}
	if runner.calls != 3 {
		t.Fatalf("expected 3 tool calls, got %d", runner.calls)
	}
}

func TestValidateToolIDRejectsUnsafeIDs(t *testing.T) {
	for _, bad := range []string{"", " ", "repair.detect ", "../../etc/passwd", "repair/detect", "repair?x=1", "repair#frag", strings.Repeat("a", 200)} {
		if err := ValidateToolID(bad); err == nil {
			t.Fatalf("expected %q to be rejected", bad)
		}
	}
	for _, good := range []string{"repair.detect", "documents.extract-text", "transcripts.claude-ai-export", "messages.sms-xml-sbv"} {
		if err := ValidateToolID(good); err != nil {
			t.Fatalf("expected %q to be accepted: %v", good, err)
		}
	}
}

func TestRunSurfacesToolFailure(t *testing.T) {
	resolve, _ := sealObject(t, []byte("data"))
	g := newGateway(t, resolve, &fakeRunner{err: errors.New("tool-runtime \"repair.detect\" returned 404")})
	_, err := g.Run(context.Background(), "repair.detect", proffer.Ref("upload://abc"), nil)
	if err == nil || !strings.Contains(err.Error(), "returned 404") {
		t.Fatalf("expected the tool error to surface, got %v", err)
	}
}

// The service is never internet-facing.
func TestHTTPRejectsNonTailnetPeer(t *testing.T) {
	resolve, _ := sealObject(t, []byte("data"))
	h := &HTTPHandler{Gateway: newGateway(t, resolve, &fakeRunner{})}
	req := httptest.NewRequest(http.MethodPost, "/tools/repair.detect/run",
		strings.NewReader(`{"source_ref":"upload://abc"}`))
	req.RemoteAddr = "203.0.113.9:5555"
	rec := httptest.NewRecorder()
	h.Routes().ServeHTTP(rec, req)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401 for a non-tailnet peer, got %d", rec.Code)
	}
}

func TestHTTPRunAcceptsLocatorFromTailnetPeer(t *testing.T) {
	resolve, _ := sealObject(t, []byte("data"))
	runner := &fakeRunner{}
	h := &HTTPHandler{Gateway: newGateway(t, resolve, runner)}
	req := httptest.NewRequest(http.MethodPost, "/tools/repair.detect/run",
		strings.NewReader(`{"source_ref":"upload://abc","args":{"sample_limit":25}}`))
	req.RemoteAddr = "100.91.190.107:5555"
	rec := httptest.NewRecorder()
	h.Routes().ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}
	if runner.calls != 1 {
		t.Fatalf("expected the tool to be invoked once, got %d", runner.calls)
	}
}

func TestHTTPRequiresSourceRef(t *testing.T) {
	resolve, _ := sealObject(t, []byte("data"))
	h := &HTTPHandler{Gateway: newGateway(t, resolve, &fakeRunner{})}
	req := httptest.NewRequest(http.MethodPost, "/tools/repair.detect/run", strings.NewReader(`{}`))
	req.RemoteAddr = "100.91.190.107:5555"
	rec := httptest.NewRecorder()
	h.Routes().ServeHTTP(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 without a locator, got %d", rec.Code)
	}
}

// A path smuggled through args must be refused at the HTTP boundary too.
func TestHTTPRejectsPathInArgs(t *testing.T) {
	resolve, _ := sealObject(t, []byte("data"))
	runner := &fakeRunner{}
	h := &HTTPHandler{Gateway: newGateway(t, resolve, runner)}
	req := httptest.NewRequest(http.MethodPost, "/tools/repair.detect/run",
		strings.NewReader(`{"source_ref":"upload://abc","args":{"path":"/etc/passwd"}}`))
	req.RemoteAddr = "100.91.190.107:5555"
	rec := httptest.NewRecorder()
	h.Routes().ServeHTTP(rec, req)
	if rec.Code == http.StatusOK {
		t.Fatal("a caller-supplied path was accepted")
	}
	if runner.calls != 0 {
		t.Fatal("tool was invoked with a caller-supplied path")
	}
}

func TestHealthzNeedsNoAuth(t *testing.T) {
	h := &HTTPHandler{}
	req := httptest.NewRequest(http.MethodGet, "/healthz", nil)
	req.RemoteAddr = "203.0.113.9:5555"
	rec := httptest.NewRecorder()
	h.Routes().ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected healthz 200, got %d", rec.Code)
	}
}

// Byline: Claude Code · Fable 5.1 · 2026-09-05 — regression for the live 401:
// VIP-service peers arrive with IPv6 tailnet addresses.
func TestTailnetAddressAcceptsBothTailscaleFamilies(t *testing.T) {
	cases := map[string]bool{
		"100.91.190.107":            true,
		"100.64.0.1":                true,
		"100.127.255.254":           true,
		"100.128.0.1":               false,
		"fd7a:115c:a1e0::1b29:fb86": true,
		"fd7a:115c:a1e0:ab12::1":    true,
		"fd7a:115c:a1e1::1":         false,
		"10.0.0.1":                  false,
		"::1":                       false,
	}
	for raw, want := range cases {
		if got := tailnetAddress(net.ParseIP(raw)); got != want {
			t.Fatalf("tailnetAddress(%s) = %v, want %v", raw, got, want)
		}
	}
}

func TestAuthorizedTailnetPeerTrustsForwardedOnlyFromLoopbackOnTsnet(t *testing.T) {
	mk := func(remote, xff string) *http.Request {
		r := httptest.NewRequest(http.MethodGet, "/tools", nil)
		r.RemoteAddr = remote
		if xff != "" {
			r.Header.Set("X-Forwarded-For", xff)
		}
		return r
	}
	tsnet := &HTTPHandler{TrustForwardedFromLoopback: true}
	plain := &HTTPHandler{}
	if !tsnet.authorizedTailnetPeer(mk("127.0.0.1:59786", "100.91.190.107")) {
		t.Fatal("tsnet mode must accept a loopback hop carrying a tailnet X-Forwarded-For")
	}
	if !tsnet.authorizedTailnetPeer(mk("127.0.0.1:1", "fd7a:115c:a1e0::1b29:fb86, 10.0.0.9")) {
		t.Fatal("first X-Forwarded-For hop is the peer")
	}
	if tsnet.authorizedTailnetPeer(mk("127.0.0.1:1", "203.0.113.5")) {
		t.Fatal("non-tailnet forwarded peer must be rejected")
	}
	if tsnet.authorizedTailnetPeer(mk("127.0.0.1:1", "")) {
		t.Fatal("loopback without a forwarded peer must be rejected")
	}
	if plain.authorizedTailnetPeer(mk("127.0.0.1:1", "100.91.190.107")) {
		t.Fatal("plain BIND_IP listener must never trust X-Forwarded-For")
	}
	if !plain.authorizedTailnetPeer(mk("100.91.190.107:4444", "")) {
		t.Fatal("direct tailnet peer is always accepted")
	}
}
