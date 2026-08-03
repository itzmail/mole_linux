//go:build linux

package main

import "testing"

func TestIsCriticalAnalyzeDeletePathLinux(t *testing.T) {
	cases := []struct {
		path string
		want bool
	}{
		{"/", true},
		{"/etc", true},
		{"/usr", true},
		{"/bin", true},
		{"/boot", true},
		{"/proc", true},
		{"/sys", true},
		{"/home/someuser/Documents", false},
		{"/tmp/scratch", false},
	}
	for _, c := range cases {
		if got := isCriticalAnalyzeDeletePath(c.path); got != c.want {
			t.Errorf("isCriticalAnalyzeDeletePath(%q) = %v, want %v", c.path, got, c.want)
		}
	}
}
