// Byline: Claude Code · Fable 5.1 · 2026-09-05 — regression for the live 422
// "source_ref must be an upload reference or a Case Bible Sorted object" on
// the synthetic rehearsal fixture. TEST mode also permits the explicitly
// selected Case Bible raw/quarantine roots; production authority stays fixed.
package runtimeapi

import "testing"

func TestValidateAuthorizedSourceRefDevFixturePrefix(t *testing.T) {
	fixture := "r2://nexus/proffer/test-fixtures/live-proof-20260827-sample_backup.xml"

	t.Setenv("PLATFORM_DEV_AUTH_BYPASS", "")
	if _, _, err := validateAuthorizedSourceRef(fixture); err == nil {
		t.Fatal("dev fixture prefix must be rejected when PLATFORM_DEV_AUTH_BYPASS is unset")
	}

	t.Setenv("PLATFORM_DEV_AUTH_BYPASS", "1")
	scheme, key, err := validateAuthorizedSourceRef(fixture)
	if err != nil {
		t.Fatalf("dev fixture prefix must be accepted under the dev flag: %v", err)
	}
	if scheme != "r2" || key != "proffer/test-fixtures/live-proof-20260827-sample_backup.xml" {
		t.Fatalf("unexpected parse: scheme=%q key=%q", scheme, key)
	}

	// The fixture bucket never widens beyond the fixture prefix.
	for _, bad := range []string{
		"r2://nexus/other/file.xml",
		"r2://nexus/proffer/test-fixtures/../escape.xml",
		"r2://photos/proffer/test-fixtures/x.xml",
	} {
		if _, _, err := validateAuthorizedSourceRef(bad); err == nil {
			t.Fatalf("%s must be rejected even under the dev flag", bad)
		}
	}

	// Canonical sources are unaffected by the flag in either state.
	for _, flag := range []string{"", "1"} {
		t.Setenv("PLATFORM_DEV_AUTH_BYPASS", flag)
		if _, _, err := validateAuthorizedSourceRef("r2://casebible-sorted/Messaging/x.html"); err != nil {
			t.Fatalf("casebible-sorted must always be accepted (flag=%q): %v", flag, err)
		}
	}
}

func TestValidateAuthorizedSourceRefDevSourceBuckets(t *testing.T) {
	t.Setenv("PLATFORM_DEV_AUTH_BYPASS", "1")
	for _, sourceRef := range []string{
		"r2://casebible-raw/Evidence/Call%20data/SMS/messages.xml",
		"r2://casebible-quarantine/onedrive/Case%20Bible/AI_Chats/conversations.json",
	} {
		scheme, key, err := validateAuthorizedSourceRef(sourceRef)
		if err != nil || scheme != "r2" || key == "" {
			t.Fatalf("dev source %q rejected: scheme=%q key=%q err=%v", sourceRef, scheme, key, err)
		}
	}

	for _, sourceRef := range []string{
		"r2://casebible-raw/Evidence/../secret.xml",
		"r2://casebible-quarantine/",
		"r2://casebible-raw/Evidence/file.xml?version=other",
	} {
		if _, _, err := validateAuthorizedSourceRef(sourceRef); err == nil {
			t.Fatalf("unsafe dev source %q was accepted", sourceRef)
		}
	}
}

func TestValidateAuthorizedSourceRefDevSourceBucketsFailClosedOutsideDevMode(t *testing.T) {
	t.Setenv("PLATFORM_DEV_AUTH_BYPASS", "0")
	for _, sourceRef := range []string{
		"r2://casebible-raw/Evidence/messages.xml",
		"r2://casebible-quarantine/AI_Chats/conversations.json",
	} {
		if _, _, err := validateAuthorizedSourceRef(sourceRef); err == nil {
			t.Fatalf("non-dev source %q was accepted", sourceRef)
		}
	}
}
