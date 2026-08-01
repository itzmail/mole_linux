//go:build linux

package main

import "testing"

func TestCollectHardwareOmitsUnknownFieldsOnLinux(t *testing.T) {
	hw := collectHardware(0, nil)
	if hw.Model == "Unknown" {
		t.Error("collectHardware should not return the literal \"Unknown\" for Model on Linux; empty lets the view layer omit the row")
	}
	if hw.CPUModel != "" {
		t.Errorf("collectHardware should not synthesize CPUModel from GOARCH on Linux, got: %q", hw.CPUModel)
	}
	if hw.DiskSize == "Unknown" {
		t.Error("collectHardware should not return the literal \"Unknown\" for DiskSize on Linux; empty lets the view layer fall back to real disk size")
	}
	if hw.OSVersion == "linux" {
		t.Error("collectHardware should not return the bare GOOS string as OSVersion on Linux")
	}
}
