//go:build linux

package main

import (
	"path/filepath"
	"strings"

	"github.com/tw93/mole/internal/xdgtrash"
)

// moveToTrashPlatform moves a file/directory to the user's XDG Trash
// directory (~/.local/share/Trash), per the freedesktop.org Trash spec.
func moveToTrashPlatform(absPath string) error {
	return xdgtrash.Move(absPath)
}

func isCriticalAnalyzeDeletePath(path string) bool {
	criticalRoots := []string{
		"/", "/bin", "/boot", "/dev", "/etc", "/home", "/lib", "/lib64",
		"/proc", "/root", "/run", "/sbin", "/srv", "/sys", "/tmp", "/usr", "/var",
		"/mnt", "/media", "/opt",
	}
	for _, root := range criticalRoots {
		if path == root || isSameExistingPath(path, root) {
			return true
		}
	}

	if isDirectChildOfExistingRoot(path, "/home") {
		return true
	}

	protectedTrees := []string{
		"/bin", "/boot", "/dev", "/etc", "/lib", "/lib64", "/proc",
		"/run", "/sbin", "/sys", "/usr", "/var",
	}
	for _, root := range protectedTrees {
		if strings.HasPrefix(path, root+string(filepath.Separator)) ||
			isPathWithinExistingRoot(path, root) {
			return true
		}
	}
	return false
}
