//go:build linux

package main

import "testing"

func TestSystemOverviewRootsLinux(t *testing.T) {
	roots := systemOverviewRoots()
	if len(roots) != 2 {
		t.Fatalf("expected 2 roots, got %d", len(roots))
	}
	if roots[0].Name != "System Cache" || roots[0].Path != "/var" {
		t.Errorf("root[0] = %+v, want Name=System Cache Path=/var", roots[0])
	}
	if roots[1].Name != "Installed Software" || roots[1].Path != "/usr" {
		t.Errorf("root[1] = %+v, want Name=Installed Software Path=/usr", roots[1])
	}
}

func TestPlatformHomeInsightEntryLinux(t *testing.T) {
	_, ok := platformHomeInsightEntry("/home/testuser")
	if ok {
		t.Error("Linux should not add a home-adjacent overview entry")
	}
}
