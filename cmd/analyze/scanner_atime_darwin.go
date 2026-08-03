//go:build darwin

package main

import (
	"syscall"
	"time"
)

// lastAccessTimeFromStat reads the last-access time from a raw stat
// structure. The field name for the atime timespec differs by platform
// (Atimespec on Darwin/BSD, Atim on Linux) even though the underlying
// syscall.Timespec type is the same.
func lastAccessTimeFromStat(stat *syscall.Stat_t) time.Time {
	return time.Unix(stat.Atimespec.Sec, stat.Atimespec.Nsec)
}
