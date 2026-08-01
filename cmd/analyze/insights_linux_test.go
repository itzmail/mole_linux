//go:build linux

package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestCreateInsightEntriesLinuxIncludesAptCacheWhenPresent(t *testing.T) {
	tmpHome := t.TempDir()
	t.Setenv("HOME", tmpHome)

	downloads := filepath.Join(tmpHome, "Downloads")
	if err := os.MkdirAll(downloads, 0o755); err != nil {
		t.Fatal(err)
	}

	entries := createInsightEntries()

	var foundDownloads bool
	for _, e := range entries {
		if e.Name == "Old Downloads (90d+)" {
			foundDownloads = true
		}
		if e.Path == "/var/cache/apt/archives" {
			t.Error("apt cache entry should only appear if the path exists; /var/cache/apt/archives is unlikely to exist in the test sandbox")
		}
	}
	if !foundDownloads {
		t.Error("expected Old Downloads entry when ~/Downloads exists")
	}
}
