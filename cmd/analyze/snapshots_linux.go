//go:build linux

package main

import (
	"context"

	tea "github.com/charmbracelet/bubbletea"
)

type localSnapshotMsg struct {
	probeID int64
	count   int
	err     error
}

type localSnapshotCommandRunner func(context.Context, string, ...string) ([]byte, error)

func runLocalSnapshotCommand(_ context.Context, _ string, _ ...string) ([]byte, error) {
	return nil, nil
}

func (m model) detectLocalSnapshotsCmd() tea.Cmd {
	return nil
}
