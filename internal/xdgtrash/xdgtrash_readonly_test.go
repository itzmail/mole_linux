package xdgtrash

import (
	"os"
	"path/filepath"
	"testing"
)

// TestEmptyOneRemovesReadOnlyTree reproduces a real-world failure found
// while manually verifying mole trash empty on a WSL machine: emptying a
// trashed Go module-cache directory failed with "permission denied"
// because module-cache trees are read-only (mode 444/555) by design, and
// os.RemoveAll cannot unlink or descend into read-only entries.
func TestEmptyOneRemovesReadOnlyTree(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)

	// Matches Go's module cache layout: the top-level package directory
	// itself stays writable (so it can still be renamed into the trash),
	// but a nested version directory and its files are read-only, exactly
	// like github.com/<org>/<pkg>@v<version>/ trees under GOMODCACHE.
	srcDir := filepath.Join(home, "readonly-pkg")
	nestedDir := filepath.Join(srcDir, "pkg@v1.0.0")
	if err := os.MkdirAll(nestedDir, 0o755); err != nil {
		t.Fatal(err)
	}
	roFile := filepath.Join(nestedDir, "doc.go")
	if err := os.WriteFile(roFile, []byte("readonly"), 0o444); err != nil {
		t.Fatal(err)
	}
	if err := os.Chmod(nestedDir, 0o555); err != nil {
		t.Fatal(err)
	}

	if err := Move(srcDir); err != nil {
		t.Fatalf("Move failed: %v", err)
	}

	items, err := List()
	if err != nil {
		t.Fatal(err)
	}
	if len(items) != 1 {
		t.Fatalf("expected 1 item, got %d", len(items))
	}

	if err := EmptyOne(items[0].Name); err != nil {
		t.Fatalf("EmptyOne failed on read-only tree: %v", err)
	}

	items, err = List()
	if err != nil {
		t.Fatal(err)
	}
	if len(items) != 0 {
		t.Fatalf("expected trash empty after EmptyOne, got %d items", len(items))
	}
}
