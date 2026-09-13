// Byline: Codex · GPT-5 · 2026-08-28 (Proffer upload ingress contract tests)
package main

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/Cursedpotential/probata/engine/acquisition"
	"github.com/Cursedpotential/probata/engine/proffer"
	platformtemporal "github.com/Cursedpotential/probata/engine/temporal"
	"github.com/stretchr/testify/require"
)

type uploadTestStarter struct{}

func (uploadTestStarter) Start(context.Context, proffer.WorkflowInput) (string, string, error) {
	return "workflow", "run", nil
}
func (uploadTestStarter) Decide(context.Context, string, proffer.PreviewDecision) error { return nil }
func (uploadTestStarter) DecideRepair(context.Context, string, proffer.RepairDecision) error {
	return nil
}
func (uploadTestStarter) Preview(context.Context, string) (proffer.PreviewState, error) {
	return proffer.PreviewState{Phase: proffer.PhaseAwaitingDecision}, nil
}
func (uploadTestStarter) Operation(context.Context, string) (proffer.OperationState, error) {
	return proffer.OperationState{Lifecycle: proffer.OperationAwaitingPreviewDecision, Wait: proffer.OperationWaitPreviewDecision, ActiveStages: []proffer.ActivityName{}}, nil
}

func TestStarterRoutesMountsTailnetAuthorizedUploadOnSharedRoot(t *testing.T) {
	root := t.TempDir()
	t.Setenv("SOURCE_OBJECT_DIR", root)
	t.Setenv(uploadMaxBytesEnv, "1024")
	ingress, err := newUploadIngress()
	require.NoError(t, err)
	starter, err := platformtemporal.NewStarterHTTPHandler(uploadTestStarter{})
	require.NoError(t, err)
	routes, err := starterRoutes(starter.Routes(), ingress)
	require.NoError(t, err)

	req := httptest.NewRequest(http.MethodPost, uploadIngressPath, bytes.NewBufferString("uploaded bytes"))
	req.RemoteAddr = "100.64.1.2:1234"
	recorder := httptest.NewRecorder()
	routes.ServeHTTP(recorder, req)
	require.Equal(t, http.StatusCreated, recorder.Code)
	var response struct {
		AcquisitionRef string `json:"acquisition_ref"`
	}
	require.NoError(t, json.NewDecoder(recorder.Body).Decode(&response))
	require.Contains(t, response.AcquisitionRef, "upload://")

	resolver, err := acquisition.NewUploadIngressResolver(root)
	require.NoError(t, err)
	_, err = resolver(context.Background(), proffer.Ref(response.AcquisitionRef))
	require.NoError(t, err)
}

func TestStarterRoutesPreservesHealthAndProtectsUpload(t *testing.T) {
	root := t.TempDir()
	ingress, err := acquisition.NewUploadIngress(acquisition.UploadIngressConfig{
		Root: root, MaxBytes: 1024,
	})
	require.NoError(t, err)
	starter, err := platformtemporal.NewStarterHTTPHandler(uploadTestStarter{})
	require.NoError(t, err)
	routes, err := starterRoutes(starter.Routes(), ingress)
	require.NoError(t, err)

	health := httptest.NewRecorder()
	routes.ServeHTTP(health, httptest.NewRequest(http.MethodGet, "/healthz", nil))
	require.Equal(t, http.StatusOK, health.Code)

	unauthorized := httptest.NewRecorder()
	unauthorizedReq := httptest.NewRequest(http.MethodPost, uploadIngressPath, bytes.NewBufferString("secret"))
	unauthorizedReq.RemoteAddr = "192.0.2.1:1234"
	routes.ServeHTTP(unauthorized, unauthorizedReq)
	require.Equal(t, http.StatusUnauthorized, unauthorized.Code)

	suffix := httptest.NewRecorder()
	routes.ServeHTTP(suffix, httptest.NewRequest(http.MethodPost, uploadIngressPath+"/unexpected", bytes.NewBufferString("secret")))
	require.Equal(t, http.StatusNotFound, suffix.Code)
}

func TestPositiveEnvInt64RejectsMissingInvalidAndNonPositive(t *testing.T) {
	for _, raw := range []string{"", "nope", "0", "-1"} {
		t.Setenv("TEST_UPLOAD_LIMIT", raw)
		_, err := positiveEnvInt64("TEST_UPLOAD_LIMIT")
		require.Error(t, err)
	}
	t.Setenv("TEST_UPLOAD_LIMIT", "4096")
	value, err := positiveEnvInt64("TEST_UPLOAD_LIMIT")
	require.NoError(t, err)
	require.Equal(t, int64(4096), value)
}
