package runtimeapi

import (
	"strings"
	"testing"
)

func TestSourceRefAdmitsOnlyContentAddressedNexusStaging(t *testing.T) {
	t.Setenv("PLATFORM_DEV_AUTH_BYPASS", "false")
	root := "r2://nexus/workbench/staging/" + strings.Repeat("a", 64) + "/"
	if _, _, err := validateAuthorizedSourceRef(root + "sms.xml"); err != nil {
		t.Fatal(err)
	}
	for _, ref := range []string{root + "../secret", root + "%2e%2e", root + "x/y", root, "r2://nexus/workbench/staging/not-a-hash/sms.xml", "r2://nexus/other/sms.xml"} {
		if _, _, err := validateAuthorizedSourceRef(ref); err == nil {
			t.Errorf("admitted %s", ref)
		}
	}
}
