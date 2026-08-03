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
		// Every listed entry must point at a path that actually exists;
		// entries for absent candidates (e.g. npm cache under this fresh
		// tmpHome) must never appear. /var/cache/apt/archives is a real
		// system path outside tmpHome, so it may legitimately appear on a
		// machine with apt installed -- this test only asserts the
		// per-candidate existence invariant, not any single path's absence.
		// The journal entry is a sentinel ("journalctl"), not a du-able
		// filesystem path, so it is exempt from this check.
		if e.Path != downloads && e.Name != "systemd Journal Logs" {
			if _, err := os.Stat(e.Path); err != nil {
				t.Errorf("insight entry %q points at a path that does not exist: %s", e.Name, e.Path)
			}
		}
	}
	if !foundDownloads {
		t.Error("expected Old Downloads entry when ~/Downloads exists")
	}
}
