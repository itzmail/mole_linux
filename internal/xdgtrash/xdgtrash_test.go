package xdgtrash

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestMoveCreatesFileAndTrashinfo(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)

	srcDir := filepath.Join(home, "work")
	if err := os.MkdirAll(srcDir, 0o755); err != nil {
		t.Fatal(err)
	}
	src := filepath.Join(srcDir, "doomed.txt")
	if err := os.WriteFile(src, []byte("bye"), 0o644); err != nil {
		t.Fatal(err)
	}

	if err := Move(src); err != nil {
		t.Fatalf("Move failed: %v", err)
	}

	if _, err := os.Stat(src); !os.IsNotExist(err) {
		t.Fatal("original file should no longer exist")
	}

	trashedFile := filepath.Join(home, ".local", "share", "Trash", "files", "doomed.txt")
	if _, err := os.Stat(trashedFile); err != nil {
		t.Fatalf("expected trashed file at %s: %v", trashedFile, err)
	}

	infoFile := filepath.Join(home, ".local", "share", "Trash", "info", "doomed.txt.trashinfo")
	data, err := os.ReadFile(infoFile)
	if err != nil {
		t.Fatalf("expected trashinfo file: %v", err)
	}
	content := string(data)
	if !strings.HasPrefix(content, "[Trash Info]\n") {
		t.Errorf("trashinfo must start with [Trash Info] header, got: %s", content)
	}
	if !strings.Contains(content, "Path="+src) {
		t.Errorf("trashinfo must record original absolute path, got: %s", content)
	}
	if !strings.Contains(content, "DeletionDate=") {
		t.Errorf("trashinfo must record a deletion date, got: %s", content)
	}
}

func TestMoveHandlesNameCollision(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)

	makeAndTrash := func(n int) {
		src := filepath.Join(home, "dup.txt")
		if err := os.WriteFile(src, []byte("v"), 0o644); err != nil {
			t.Fatal(err)
		}
		if err := Move(src); err != nil {
			t.Fatalf("Move #%d failed: %v", n, err)
		}
	}
	makeAndTrash(1)
	makeAndTrash(2)

	entries, err := os.ReadDir(filepath.Join(home, ".local", "share", "Trash", "files"))
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) != 2 {
		t.Fatalf("expected 2 distinct trashed files after collision, got %d", len(entries))
	}
}

func TestListAndTotalSize(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)

	src := filepath.Join(home, "sized.txt")
	if err := os.WriteFile(src, []byte("12345"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := Move(src); err != nil {
		t.Fatal(err)
	}

	items, err := List()
	if err != nil {
		t.Fatal(err)
	}
	if len(items) != 1 {
		t.Fatalf("expected 1 item, got %d", len(items))
	}
	if items[0].OriginalPath != src {
		t.Errorf("OriginalPath = %q, want %q", items[0].OriginalPath, src)
	}
	if items[0].Size != 5 {
		t.Errorf("Size = %d, want 5", items[0].Size)
	}

	total, err := TotalSize()
	if err != nil {
		t.Fatal(err)
	}
	if total != 5 {
		t.Errorf("TotalSize = %d, want 5", total)
	}
}

func TestEmptyOneAndEmptyAll(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)

	for _, name := range []string{"a.txt", "b.txt"} {
		src := filepath.Join(home, name)
		if err := os.WriteFile(src, []byte("x"), 0o644); err != nil {
			t.Fatal(err)
		}
		if err := Move(src); err != nil {
			t.Fatal(err)
		}
	}

	items, err := List()
	if err != nil {
		t.Fatal(err)
	}
	if len(items) != 2 {
		t.Fatalf("expected 2 items, got %d", len(items))
	}

	if err := EmptyOne(items[0].Name); err != nil {
		t.Fatal(err)
	}
	items, err = List()
	if err != nil {
		t.Fatal(err)
	}
	if len(items) != 1 {
		t.Fatalf("expected 1 item after EmptyOne, got %d", len(items))
	}

	if err := EmptyAll(); err != nil {
		t.Fatal(err)
	}
	items, err = List()
	if err != nil {
		t.Fatal(err)
	}
	if len(items) != 0 {
		t.Fatalf("expected 0 items after EmptyAll, got %d", len(items))
	}
}
