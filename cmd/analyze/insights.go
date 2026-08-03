//go:build darwin || linux

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

// measureInsightSize measures the size of a path.
// Old Downloads is treated specially: only files older than 90 days are counted.
func measureInsightSize(path string) (int64, error) {
	home := os.Getenv("HOME")

	if home != "" && path == filepath.Join(home, "Downloads") {
		return measureOldDownloads(path, 90)
	}

	return measureOverviewSize(path)
}

// measureOldDownloads calculates total size of files in a directory
// that haven't been modified in the given number of days.
func measureOldDownloads(dir string, daysOld int) (int64, error) {
	cutoff := time.Now().AddDate(0, 0, -daysOld)
	var total int64

	entries, err := os.ReadDir(dir)
	if err != nil {
		return 0, err
	}

	for _, entry := range entries {
		// Skip hidden files.
		if strings.HasPrefix(entry.Name(), ".") {
			continue
		}

		info, err := entry.Info()
		if err != nil {
			continue
		}

		if info.ModTime().Before(cutoff) {
			if entry.IsDir() {
				// Use du for directories.
				if size, err := getDirSizeFast(filepath.Join(dir, entry.Name())); err == nil {
					total += size
				}
			} else {
				total += info.Size()
			}
		}
	}

	return total, nil
}

// getDirSizeFast measures directory size using du.
func getDirSizeFast(path string) (int64, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	cmd := exec.CommandContext(ctx, "du", "-sk", path)
	output, err := cmd.Output()
	if err != nil {
		return 0, err
	}

	fields := strings.Fields(string(output))
	if len(fields) == 0 {
		return 0, nil
	}

	kb, err := strconv.ParseInt(fields[0], 10, 64)
	if err != nil {
		return 0, err
	}

	return kb * 1024, nil
}

// oldDownloadsInsightEntry returns the shared "Old Downloads (90d+)" entry
// if ~/Downloads exists, or false if there is nothing to show.
func oldDownloadsInsightEntry(home string) (dirEntry, bool) {
	downloadsPath := filepath.Join(home, "Downloads")
	if info, err := os.Stat(downloadsPath); err == nil && info.IsDir() {
		return dirEntry{
			Name:  "Old Downloads (90d+)",
			Path:  downloadsPath,
			IsDir: true,
			Size:  -1,
		}, true
	}
	return dirEntry{}, false
}

// appendExistingPathEntries appends one dirEntry per (name, path) pair whose
// path exists as a directory, in order.
func appendExistingPathEntries(entries []dirEntry, candidates []struct {
	name string
	path string
}) []dirEntry {
	for _, c := range candidates {
		if info, err := os.Stat(c.path); err == nil && info.IsDir() {
			entries = append(entries, dirEntry{Name: c.name, Path: c.path, IsDir: true, Size: -1})
		}
	}
	return entries
}
