// Package xdgtrash implements the freedesktop.org Trash specification
// (files/ + info/*.trashinfo under $XDG_DATA_HOME/Trash) directly, with no
// external dependency on trash-cli or gio.
package xdgtrash

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"
)

func trashHome() (string, error) {
	if dataHome := os.Getenv("XDG_DATA_HOME"); dataHome != "" {
		return filepath.Join(dataHome, "Trash"), nil
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return "", fmt.Errorf("failed to resolve home directory: %w", err)
	}
	return filepath.Join(home, ".local", "share", "Trash"), nil
}

func filesDir() (string, error) {
	th, err := trashHome()
	if err != nil {
		return "", err
	}
	return filepath.Join(th, "files"), nil
}

func infoDir() (string, error) {
	th, err := trashHome()
	if err != nil {
		return "", err
	}
	return filepath.Join(th, "info"), nil
}

func ensureTrashDirs() (files string, info string, err error) {
	files, err = filesDir()
	if err != nil {
		return "", "", err
	}
	info, err = infoDir()
	if err != nil {
		return "", "", err
	}
	if err := os.MkdirAll(files, 0o700); err != nil {
		return "", "", fmt.Errorf("failed to create trash files dir: %w", err)
	}
	if err := os.MkdirAll(info, 0o700); err != nil {
		return "", "", fmt.Errorf("failed to create trash info dir: %w", err)
	}
	return files, info, nil
}

// Move moves absPath into the XDG Trash, writing a .trashinfo sidecar
// recording its original location and deletion time. Name collisions are
// resolved by appending a numeric suffix before the extension.
func Move(absPath string) error {
	if !filepath.IsAbs(absPath) {
		return fmt.Errorf("path must be absolute: %s", absPath)
	}
	if _, err := os.Lstat(absPath); err != nil {
		return err
	}

	filesD, infoD, err := ensureTrashDirs()
	if err != nil {
		return err
	}

	base := filepath.Base(absPath)
	name := base
	var destFile, destInfo string
	for attempt := 0; ; attempt++ {
		if attempt > 0 {
			ext := filepath.Ext(base)
			stem := strings.TrimSuffix(base, ext)
			name = fmt.Sprintf("%s.%d%s", stem, attempt, ext)
		}
		destFile = filepath.Join(filesD, name)
		destInfo = filepath.Join(infoD, name+".trashinfo")
		if _, err := os.Lstat(destFile); os.IsNotExist(err) {
			if _, err := os.Lstat(destInfo); os.IsNotExist(err) {
				break
			}
		}
		if attempt > 10000 {
			return fmt.Errorf("failed to choose unique trash destination for %s", absPath)
		}
	}

	deletionDate := time.Now().Format("2006-01-02T15:04:05")
	trashInfo := fmt.Sprintf("[Trash Info]\nPath=%s\nDeletionDate=%s\n", absPath, deletionDate)
	if err := os.WriteFile(destInfo, []byte(trashInfo), 0o600); err != nil {
		return fmt.Errorf("failed to write trashinfo: %w", err)
	}

	if err := os.Rename(absPath, destFile); err != nil {
		_ = os.Remove(destInfo)
		return fmt.Errorf("failed to move to trash: %w", err)
	}

	return nil
}

// Item describes one trashed file or directory.
type Item struct {
	Name         string
	OriginalPath string
	DeletedAt    time.Time
	Size         int64
	IsDir        bool
}

// List returns every item currently in the trash, derived by pairing each
// info/*.trashinfo file with its files/ entry.
func List() ([]Item, error) {
	filesD, infoD, err := ensureTrashDirs()
	if err != nil {
		return nil, err
	}

	entries, err := os.ReadDir(infoD)
	if err != nil {
		return nil, fmt.Errorf("failed to read trash info dir: %w", err)
	}

	var items []Item
	for _, e := range entries {
		if e.IsDir() || !strings.HasSuffix(e.Name(), ".trashinfo") {
			continue
		}
		name := strings.TrimSuffix(e.Name(), ".trashinfo")
		data, err := os.ReadFile(filepath.Join(infoD, e.Name()))
		if err != nil {
			continue
		}
		origPath, deletedAt := parseTrashInfo(string(data))

		filePath := filepath.Join(filesD, name)
		info, statErr := os.Lstat(filePath)
		var size int64
		var isDir bool
		if statErr == nil {
			isDir = info.IsDir()
			if isDir {
				size, _ = dirSize(filePath)
			} else {
				size = info.Size()
			}
		}

		items = append(items, Item{
			Name:         name,
			OriginalPath: origPath,
			DeletedAt:    deletedAt,
			Size:         size,
			IsDir:        isDir,
		})
	}
	return items, nil
}

func parseTrashInfo(content string) (origPath string, deletedAt time.Time) {
	for _, line := range strings.Split(content, "\n") {
		if p, ok := strings.CutPrefix(line, "Path="); ok {
			origPath = p
		}
		if d, ok := strings.CutPrefix(line, "DeletionDate="); ok {
			if t, err := time.Parse("2006-01-02T15:04:05", d); err == nil {
				deletedAt = t
			}
		}
	}
	return origPath, deletedAt
}

func dirSize(path string) (int64, error) {
	var total int64
	err := filepath.Walk(path, func(_ string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if !info.IsDir() {
			total += info.Size()
		}
		return nil
	})
	return total, err
}

// TotalSize returns the combined size in bytes of every item in the trash.
func TotalSize() (int64, error) {
	items, err := List()
	if err != nil {
		return 0, err
	}
	var total int64
	for _, item := range items {
		total += item.Size
	}
	return total, nil
}

// EmptyOne permanently deletes one trashed item by its trash-file name
// (Item.Name), removing both the file/directory and its .trashinfo sidecar.
func EmptyOne(name string) error {
	filesD, infoD, err := ensureTrashDirs()
	if err != nil {
		return err
	}
	filePath := filepath.Join(filesD, name)
	infoPath := filepath.Join(infoD, name+".trashinfo")

	if err := makeWritableRecursive(filePath); err != nil {
		return fmt.Errorf("failed to prepare trashed item for removal: %w", err)
	}
	if err := os.RemoveAll(filePath); err != nil {
		return fmt.Errorf("failed to remove trashed item: %w", err)
	}
	if err := os.Remove(infoPath); err != nil && !os.IsNotExist(err) {
		return fmt.Errorf("failed to remove trashinfo: %w", err)
	}
	return nil
}

// makeWritableRecursive ensures every directory under root (root included)
// carries the owner write bit, so os.RemoveAll can unlink entries and
// descend into subdirectories that were trashed read-only. This is a real
// case in practice: Go's module cache (GOMODCACHE) ships package version
// directories as read-only (mode 555) to prevent accidental modification,
// and a plain os.RemoveAll fails partway through such a tree with
// "permission denied" instead of completing the delete.
func makeWritableRecursive(root string) error {
	return filepath.WalkDir(root, func(path string, d os.DirEntry, err error) error {
		if err != nil {
			if os.IsNotExist(err) {
				return nil
			}
			return err
		}
		if !d.IsDir() {
			return nil
		}
		info, err := d.Info()
		if err != nil {
			return err
		}
		if info.Mode().Perm()&0o200 == 0 {
			if chmodErr := os.Chmod(path, info.Mode().Perm()|0o200); chmodErr != nil {
				return chmodErr
			}
		}
		return nil
	})
}

// EmptyAll permanently deletes every item currently in the trash.
func EmptyAll() error {
	items, err := List()
	if err != nil {
		return err
	}
	var firstErr error
	for _, item := range items {
		if err := EmptyOne(item.Name); err != nil && firstErr == nil {
			firstErr = err
		}
	}
	return firstErr
}
