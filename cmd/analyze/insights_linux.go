//go:build linux

package main

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

// createInsightEntries returns the list of hidden-space insight entries
// to show in the overview screen alongside the standard directory entries.
func createInsightEntries() []dirEntry {
	home := os.Getenv("HOME")
	if home == "" {
		return nil
	}

	var entries []dirEntry

	if entry, ok := oldDownloadsInsightEntry(home); ok {
		entries = append(entries, entry)
	}

	cleanablePaths := []struct {
		name string
		path string
	}{
		{"APT Package Cache", "/var/cache/apt/archives"},
		{"npm Cache", filepath.Join(home, ".npm")},
		{"Yarn Cache", filepath.Join(home, ".cache", "yarn")},
		{"pnpm Store", filepath.Join(home, ".local", "share", "pnpm")},
		{"pip Cache", filepath.Join(home, ".cache", "pip")},
		{"Gradle Cache", filepath.Join(home, ".gradle", "caches")},
		{"Docker Data (rootless)", filepath.Join(home, ".local", "share", "docker")},
		{"Docker Data", "/var/lib/docker"},
	}
	entries = appendExistingPathEntries(entries, cleanablePaths)

	if size, err := journalDiskUsageBytes(); err == nil && size > 0 {
		entries = append(entries, dirEntry{Name: "systemd Journal Logs", Path: "journalctl", IsDir: false, Size: -1})
	}

	return entries
}

// journalDiskUsageBytes returns the disk space systemd's journal reports
// using, via `journalctl --disk-usage`. Journal storage is not a single
// du-able path the way other insight entries are, so this is measured
// directly instead of routed through measureInsightSize.
func journalDiskUsageBytes() (int64, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	cmd := exec.CommandContext(ctx, "journalctl", "--disk-usage")
	out, err := cmd.Output()
	if err != nil {
		return 0, err
	}

	// Output looks like: "Archived and active journals take up 128.0M in the file system."
	fields := strings.Fields(string(out))
	for i, f := range fields {
		if f == "up" && i+1 < len(fields) {
			return parseHumanSize(fields[i+1])
		}
	}
	return 0, nil
}

func parseHumanSize(s string) (int64, error) {
	units := map[byte]int64{'K': 1 << 10, 'M': 1 << 20, 'G': 1 << 30, 'T': 1 << 40}
	if len(s) == 0 {
		return 0, nil
	}
	last := s[len(s)-1]
	if mult, ok := units[last]; ok {
		val, err := strconv.ParseFloat(s[:len(s)-1], 64)
		if err != nil {
			return 0, err
		}
		return int64(val * float64(mult)), nil
	}
	val, err := strconv.ParseFloat(s, 64)
	if err != nil {
		return 0, err
	}
	return int64(val), nil
}
