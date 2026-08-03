package main

import (
	"runtime"
	"testing"
)

func TestCollectProcessesReturnsDataOnLinux(t *testing.T) {
	if runtime.GOOS != "linux" {
		t.Skip("linux-only assertion")
	}
	procs, err := collectProcesses()
	if err != nil {
		t.Fatalf("collectProcesses failed: %v", err)
	}
	if len(procs) == 0 {
		t.Error("expected at least one process on a running Linux system (this test process itself), got 0")
	}
}
