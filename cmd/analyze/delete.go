//go:build darwin || linux

package main

import (
	"fmt"
	"os"
	"os/user"
	"path/filepath"
	"slices"
	"sort"
	"strings"
	"sync/atomic"

	tea "github.com/charmbracelet/bubbletea"
)

func deletePathCmd(path string, counter *int64) tea.Cmd {
	return func() tea.Msg {
		count, err := trashPathWithProgress(path, counter)
		return deleteProgressMsg{
			done:  true,
			err:   err,
			count: count,
			path:  path,
		}
	}
}

// deleteMultiplePathsCmd moves paths to Trash and aggregates results.
func deleteMultiplePathsCmd(paths []string, counter *int64) tea.Cmd {
	return func() tea.Msg {
		var totalCount int64
		var errors []string
		var removedPaths []string

		// Process deeper paths first to avoid parent/child conflicts.
		pathsToDelete := append([]string(nil), paths...)
		sort.Slice(pathsToDelete, func(i, j int) bool {
			return strings.Count(pathsToDelete[i], string(filepath.Separator)) > strings.Count(pathsToDelete[j], string(filepath.Separator))
		})

		for _, path := range pathsToDelete {
			count, err := trashPathWithProgress(path, counter)
			totalCount += count
			if err != nil {
				if os.IsNotExist(err) {
					removedPaths = append(removedPaths, path)
					continue
				}
				errors = append(errors, err.Error())
				continue
			}
			removedPaths = append(removedPaths, path)
		}

		var resultErr error
		if len(errors) > 0 {
			resultErr = &multiDeleteError{errors: errors}
		}

		return deleteProgressMsg{
			done:         true,
			err:          resultErr,
			count:        totalCount,
			path:         "",
			removedPaths: removedPaths,
		}
	}
}

// multiDeleteError holds multiple deletion errors.
type multiDeleteError struct {
	errors []string
}

func (e *multiDeleteError) Error() string {
	if len(e.errors) == 1 {
		return e.errors[0]
	}
	return strings.Join(e.errors[:min(3, len(e.errors))], "; ")
}

// trashPathWithProgress moves one selected path to Trash and reports completion.
func trashPathWithProgress(root string, counter *int64) (int64, error) {
	// Verify path exists (use Lstat to handle broken symlinks).
	_, err := os.Lstat(root)
	if err != nil {
		return 0, err
	}

	// Trash moves one selected path as a unit. Recursively counting every file
	// first made large directory deletes appear hung before the move began.
	const count int64 = 1

	if err := moveToTrash(root); err != nil {
		return 0, err
	}
	if counter != nil {
		atomic.AddInt64(counter, count)
	}

	return count, nil
}

// moveToTrash moves a file/directory to the user Trash via the
// platform-specific mechanism (see delete_darwin.go / delete_linux.go).
func moveToTrash(path string) error {
	if err := validateTrashTarget(path); err != nil {
		return err
	}

	absPath, err := filepath.Abs(path)
	if err != nil {
		return fmt.Errorf("failed to resolve path: %w", err)
	}

	if err := validateTrashTarget(absPath); err != nil {
		return err
	}

	return moveToTrashPlatform(absPath)
}

func validateTrashTarget(path string) error {
	if err := validatePath(path); err != nil {
		return err
	}
	if isProtectedAnalyzeDeletePath(path) {
		return fmt.Errorf("protected path cannot be deleted: %s", path)
	}
	if resolvedPath, err := filepath.EvalSymlinks(path); err == nil && isProtectedAnalyzeDeletePath(resolvedPath) {
		return fmt.Errorf("protected path cannot be deleted: %s", path)
	}
	return nil
}

func isProtectedAnalyzeDeletePath(path string) bool {
	if path == "" {
		return false
	}

	cleanPath := filepath.Clean(path)

	// EDR / Darwin-cache protection is based on the absolute path and does not
	// depend on HOME, so check it first: an unset HOME must not let a Falcon
	// cache slip through (e.g. `env -u HOME mo analyze`).
	if isEndpointSecurityCachePath(cleanPath) {
		return true
	}
	if isCriticalAnalyzeDeletePath(cleanPath) {
		return true
	}

	homeRoots := protectedAnalyzeHomeRoots()
	if len(homeRoots) == 0 {
		return false
	}

	for _, homeRoot := range homeRoots {
		if cleanPath == homeRoot || isSameExistingPath(cleanPath, homeRoot) {
			return true
		}

		dockerDesktopState := filepath.Join(homeRoot, "Library", "Containers", "com.docker.docker")
		if cleanPath == dockerDesktopState || strings.HasPrefix(cleanPath, dockerDesktopState+string(filepath.Separator)) {
			return true
		}
		if isPathWithinExistingRoot(cleanPath, dockerDesktopState) {
			return true
		}

		orbstackState := filepath.Join(homeRoot, ".orbstack")
		if cleanPath == orbstackState || strings.HasPrefix(cleanPath, orbstackState+string(filepath.Separator)) {
			return true
		}
		if isPathWithinExistingRoot(cleanPath, orbstackState) {
			return true
		}

		groupContainers := filepath.Join(homeRoot, "Library", "Group Containers")
		if entries, err := os.ReadDir(groupContainers); err == nil {
			for _, entry := range entries {
				if !strings.HasSuffix(strings.ToLower(entry.Name()), "dev.orbstack") {
					continue
				}
				if isPathWithinExistingRoot(cleanPath, filepath.Join(groupContainers, entry.Name())) {
					return true
				}
			}
		}

		rel, err := filepath.Rel(strings.ToLower(groupContainers), strings.ToLower(cleanPath))
		if err != nil || rel == "." || rel == ".." || strings.HasPrefix(rel, ".."+string(filepath.Separator)) {
			continue
		}

		containerName := rel
		if idx := strings.Index(containerName, string(filepath.Separator)); idx >= 0 {
			containerName = containerName[:idx]
		}
		if strings.HasSuffix(strings.ToLower(containerName), "dev.orbstack") {
			return true
		}
	}
	return false
}

func protectedAnalyzeHomeRoots() []string {
	var homeRoots []string
	seenHomeRoots := make(map[string]bool)
	addHomeRoot := func(home string) {
		if home == "" {
			return
		}
		cleanHome := filepath.Clean(home)
		if !seenHomeRoots[cleanHome] {
			homeRoots = append(homeRoots, cleanHome)
			seenHomeRoots[cleanHome] = true
		}
		if resolvedHome, err := filepath.EvalSymlinks(cleanHome); err == nil && !seenHomeRoots[resolvedHome] {
			homeRoots = append(homeRoots, resolvedHome)
			seenHomeRoots[resolvedHome] = true
		}
	}

	addHomeRoot(os.Getenv("HOME"))
	if currentUser, err := user.Current(); err == nil {
		addHomeRoot(currentUser.HomeDir)
	}
	return homeRoots
}

func isPathWithinExistingRoot(path, protectedRoot string) bool {
	protectedInfo, err := os.Stat(protectedRoot)
	if err != nil {
		return false
	}

	for current := filepath.Clean(path); ; current = filepath.Dir(current) {
		if currentInfo, err := os.Stat(current); err == nil && os.SameFile(currentInfo, protectedInfo) {
			return true
		}
		parent := filepath.Dir(current)
		if parent == current {
			return false
		}
	}
}

func isSameExistingPath(path, protectedPath string) bool {
	pathInfo, pathErr := os.Stat(path)
	protectedInfo, protectedErr := os.Stat(protectedPath)
	return pathErr == nil && protectedErr == nil && os.SameFile(pathInfo, protectedInfo)
}

func isDirectChildOfExistingRoot(path, protectedRoot string) bool {
	cleanPath := filepath.Clean(path)
	return cleanPath != filepath.Clean(protectedRoot) &&
		filepath.Dir(cleanPath) != cleanPath &&
		isSameExistingPath(filepath.Dir(cleanPath), protectedRoot)
}

// endpointSecurityBundlePrefixes mirrors ENDPOINT_SECURITY_BUNDLE_PREFIXES in
// lib/core/app_protection_data.sh. Deleting anything inside one of these EDR/MDM
// agents' per-user Darwin caches trips sensor tamper detection (e.g. CrowdStrike
// MacFalconSensorTamper, MITRE T1562.001), so analyze must never Trash them.
var endpointSecurityBundlePrefixes = []string{
	"com.crowdstrike.",
	"com.sentinelone.",
	"com.sentinel-labs.",
	"com.eset.",
	"com.jamf.",
	"com.jamfsoftware.",
	"com.paloaltonetworks.",
	"com.cisco.anyconnect",
	"com.cisco.secureclient",
}

// isEndpointSecurityCachePath reports whether path is an endpoint-security / EDR
// agent file under the per-user Darwin folder (/private/var/folders or its
// /var/folders symlink form). Mirror of is_endpoint_security_cache_path() in
// lib/core/app_protection.sh.
func isEndpointSecurityCachePath(path string) bool {
	lowerPath := strings.ToLower(path)
	if !strings.HasPrefix(lowerPath, "/private/var/folders/") && !strings.HasPrefix(lowerPath, "/var/folders/") {
		return false
	}
	for _, prefix := range endpointSecurityBundlePrefixes {
		if strings.Contains(lowerPath, prefix) {
			return true
		}
	}
	return false
}

// validatePath checks path safety for external commands.
// Returns error if path is empty, relative, contains null bytes, or has traversal.
func validatePath(path string) error {
	if path == "" {
		return fmt.Errorf("path is empty")
	}
	if !filepath.IsAbs(path) {
		return fmt.Errorf("path must be absolute: %s", path)
	}
	if strings.Contains(path, "\x00") {
		return fmt.Errorf("path contains null bytes")
	}
	// Check for path traversal attempts (.. components).
	if slices.Contains(strings.Split(path, string(filepath.Separator)), "..") {
		return fmt.Errorf("path contains traversal components: %s", path)
	}
	return nil
}
