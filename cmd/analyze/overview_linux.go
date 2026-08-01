//go:build linux

package main

func systemOverviewRoots() []dirEntry {
	return []dirEntry{
		{Name: "System Cache", Path: "/var", IsDir: true, Size: -1},
		{Name: "Installed Software", Path: "/usr", IsDir: true, Size: -1},
	}
}

// platformHomeInsightEntry has no Linux equivalent to Home; Linux has no
// per-user system library directory analogous to ~/Library.
func platformHomeInsightEntry(_ string) (dirEntry, bool) {
	return dirEntry{}, false
}
