//go:build darwin

package main

import (
	"os"
	"path/filepath"
)

func systemOverviewRoots() []dirEntry {
	return []dirEntry{
		{Name: "Applications", Path: "/Applications", IsDir: true, Size: -1},
		{Name: "System Library", Path: "/Library", IsDir: true, Size: -1},
	}
}

// platformHomeInsightEntry returns the macOS-only "User Library" row shown
// next to Home on the overview screen, renamed from "App Library" so it
// parallels "System Library" (/Library) and isn't confused with /Applications.
func platformHomeInsightEntry(home string) (dirEntry, bool) {
	userLibrary := filepath.Join(home, "Library")
	if _, err := os.Stat(userLibrary); err != nil {
		return dirEntry{}, false
	}
	return dirEntry{Name: "User Library", Path: userLibrary, IsDir: true, Size: -1}, true
}
