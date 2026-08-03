//go:build darwin

package main

import "testing"

func TestSystemOverviewRootsDefaultsToRealSystemPaths(t *testing.T) {
	roots := systemOverviewRoots()
	if len(roots) != 2 {
		t.Fatalf("expected 2 default system roots, got %d", len(roots))
	}
	if roots[0].Path != "/Applications" || roots[1].Path != "/Library" {
		t.Fatalf("unexpected default system roots: %q, %q", roots[0].Path, roots[1].Path)
	}
	for _, root := range roots {
		if root.Size != -1 || !root.IsDir {
			t.Fatalf("default root %q must start pending and be a dir, got size=%d isDir=%v",
				root.Path, root.Size, root.IsDir)
		}
	}
}
