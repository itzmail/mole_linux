package main

import (
	"bytes"
	"os"
	"path/filepath"
	"testing"

	"github.com/tw93/mole/internal/xdgtrash"
)

func TestRunListShowsTrashedItem(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)

	src := filepath.Join(home, "keepme.txt")
	if err := os.WriteFile(src, []byte("hello"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := xdgtrash.Move(src); err != nil {
		t.Fatal(err)
	}

	var buf bytes.Buffer
	if err := runList(&buf); err != nil {
		t.Fatalf("runList failed: %v", err)
	}
	out := buf.String()
	if !bytes.Contains([]byte(out), []byte("keepme.txt")) {
		t.Errorf("expected output to mention keepme.txt, got: %s", out)
	}
	if !bytes.Contains([]byte(out), []byte(src)) {
		t.Errorf("expected output to mention original path %s, got: %s", src, out)
	}
}

func TestRunEmptyAllClearsTrash(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)

	src := filepath.Join(home, "gone.txt")
	if err := os.WriteFile(src, []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := xdgtrash.Move(src); err != nil {
		t.Fatal(err)
	}

	if err := runEmptyAll(); err != nil {
		t.Fatalf("runEmptyAll failed: %v", err)
	}

	items, err := xdgtrash.List()
	if err != nil {
		t.Fatal(err)
	}
	if len(items) != 0 {
		t.Fatalf("expected empty trash, got %d items", len(items))
	}
}
