# Linux/WSL Port Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `analyze` (disk explorer TUI), `status` (health dashboard), and a new `mole trash` subcommand fully functional on Linux/WSL, with zero behavior change on macOS.

**Architecture:** Use Go's `_darwin.go` / `_linux.go` file-suffix convention to split OS-specific mechanism from shared logic, wherever a file mixes the two. Where a file already isolates its OS branch behind `runtime.GOOS` checks with sane fallbacks (e.g. `metrics_battery.go`), extend the existing branch instead of splitting the file. Add a new `cmd/trash` Go binary following the same structure as `cmd/analyze`/`cmd/status`, wired into the `mole` router the same way.

**Tech Stack:** Go 1.25, Bubble Tea (TUI), gopsutil (already cross-platform), bash (router/wrapper scripts).

## Global Constraints

- macOS behavior must not change: every darwin code path must compile and behave identically after this work (spec: "macOS is unaffected").
- No external dependencies for trash management — implement the freedesktop.org XDG Trash spec directly in Go, not `trash-cli`/`gio trash` (spec §3).
- `clean`, `uninstall`, `optimize` are out of scope — do not touch `lib/clean/`, `lib/uninstall/`, `lib/optimize/`, or their bats tests in this plan.
- Missing Linux metrics (bluetooth/GPU/hardware refinements) are omitted from output entirely, never shown as "N/A" (spec §2).
- New Linux overview roots for `analyze`: Home, `/var`, `/usr` (spec §1). New Linux insights: old Downloads (90d, unchanged logic), apt archive cache, npm/yarn/pnpm caches, Docker data, systemd journal (spec §1).
- CI: add an `ubuntu-latest` job running `go test ./...` to `.github/workflows/test.yml`; the bats suite stays macOS-only this phase (spec §4).

---

## Task 1: Relax `analyze` build tags and split the overview/insights roots

**Files:**
- Modify: every `cmd/analyze/*.go` and `cmd/analyze/*_test.go` file currently starting with `//go:build darwin` — change to `//go:build darwin || linux`
- Delete: `cmd/analyze/main_stub.go`
- Modify: `cmd/analyze/main.go:133-167` — extract `createOverviewEntriesWithInsights`'s macOS-only parts and `systemOverviewRoots()` into a new darwin file
- Create: `cmd/analyze/overview_darwin.go` — contains `systemOverviewRoots()` exactly as it exists today (Applications, System Library) plus the `~/Library` "User Library" detection block
- Create: `cmd/analyze/overview_linux.go` — Linux equivalent
- Modify: `cmd/analyze/main.go` — `createOverviewEntriesWithInsights` calls a new OS-agnostic helper that delegates to the platform file
- Test: `cmd/analyze/overview_linux_test.go`

**Interfaces:**
- Produces: `systemOverviewRoots() []dirEntry` (existing signature, now platform-specific — one impl per file)
- Produces: `platformHomeInsightEntry(home string) (dirEntry, bool)` — returns the platform-specific "extra Home-adjacent entry" (User Library on darwin, nothing on Linux) and whether to include it
- Consumes: `dirEntry` struct (already defined in `cmd/analyze/model.go`) — do not redefine it

- [ ] **Step 1: Write the failing test for Linux overview roots**

```go
// cmd/analyze/overview_linux_test.go
//go:build linux

package main

import "testing"

func TestSystemOverviewRootsLinux(t *testing.T) {
	roots := systemOverviewRoots()
	if len(roots) != 2 {
		t.Fatalf("expected 2 roots, got %d", len(roots))
	}
	if roots[0].Name != "System Cache" || roots[0].Path != "/var" {
		t.Errorf("root[0] = %+v, want Name=System Cache Path=/var", roots[0])
	}
	if roots[1].Name != "Installed Software" || roots[1].Path != "/usr" {
		t.Errorf("root[1] = %+v, want Name=Installed Software Path=/usr", roots[1])
	}
}

func TestPlatformHomeInsightEntryLinux(t *testing.T) {
	_, ok := platformHomeInsightEntry("/home/testuser")
	if ok {
		t.Error("Linux should not add a home-adjacent overview entry")
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd cmd/analyze && go test ./... -run 'TestSystemOverviewRootsLinux|TestPlatformHomeInsightEntryLinux' -v`
Expected: FAIL — `systemOverviewRoots` still returns the darwin-only Applications/Library entries because it isn't split yet, and `platformHomeInsightEntry` doesn't exist (build error: undefined).

- [ ] **Step 3: Create `overview_darwin.go` with the existing macOS logic extracted verbatim**

```go
// cmd/analyze/overview_darwin.go
//go:build darwin

package main

import (
	"os"
	"path/filepath"
)

func systemOverviewRoots() []dirEntry {
	return []dirEntry{
		{Name: "Applications", Path: "/Applications", IsDir: true, Size: -1},
		{Name: "System Library", Path: "/Library", IsDir: true, Size: -1},
	}
}

// platformHomeInsightEntry returns the macOS-only "User Library" row shown
// next to Home on the overview screen, renamed from "App Library" so it
// parallels "System Library" (/Library) and isn't confused with /Applications.
func platformHomeInsightEntry(home string) (dirEntry, bool) {
	userLibrary := filepath.Join(home, "Library")
	if _, err := os.Stat(userLibrary); err != nil {
		return dirEntry{}, false
	}
	return dirEntry{Name: "User Library", Path: userLibrary, IsDir: true, Size: -1}, true
}
```

- [ ] **Step 4: Create `overview_linux.go`**

```go
// cmd/analyze/overview_linux.go
//go:build linux

package main

func systemOverviewRoots() []dirEntry {
	return []dirEntry{
		{Name: "System Cache", Path: "/var", IsDir: true, Size: -1},
		{Name: "Installed Software", Path: "/usr", IsDir: true, Size: -1},
	}
}

// platformHomeInsightEntry has no Linux equivalent to Home; Linux has no
// per-user system library directory analogous to ~/Library.
func platformHomeInsightEntry(_ string) (dirEntry, bool) {
	return dirEntry{}, false
}
```

- [ ] **Step 5: Update `main.go` to use the new shared helper instead of the inline darwin-only block**

In `cmd/analyze/main.go`, replace lines 137-160 (`createOverviewEntriesWithInsights`):

```go
func createOverviewEntriesWithInsights(insightEntries []dirEntry) []dirEntry {
	home := os.Getenv("HOME")
	entries := []dirEntry{}

	if home != "" {
		entries = append(entries, dirEntry{Name: "Home", Path: home, IsDir: true, Size: -1})

		if extra, ok := platformHomeInsightEntry(home); ok {
			entries = append(entries, extra)
		}
	}

	entries = append(entries, systemOverviewRoots()...)
	entries = append(entries, insightEntries...)

	return entries
}
```

Also change the top of `cmd/analyze/main.go` from `//go:build darwin` to `//go:build darwin || linux`.

- [ ] **Step 6: Run test to verify it passes**

Run: `cd cmd/analyze && go test ./... -run 'TestSystemOverviewRootsLinux|TestPlatformHomeInsightEntryLinux' -v`
Expected: PASS

- [ ] **Step 7: Bulk-update remaining build tags across the package**

Run: `grep -rl '^//go:build darwin$' cmd/analyze/*.go | xargs sed -i '' 's|^//go:build darwin$|//go:build darwin || linux|'` on macOS (BSD sed) or `sed -i 's|^//go:build darwin$|//go:build darwin || linux|'` on Linux — apply to every file EXCEPT `overview_darwin.go`, `insights_darwin.go` (Task 2), `delete_darwin.go` (Task 3), which must stay darwin-only, and `scanner.go` which has no build tag change needed (Task 4).

Delete `cmd/analyze/main_stub.go` entirely (`rm cmd/analyze/main_stub.go`).

- [ ] **Step 8: Verify the package builds for both OSes**

Run: `cd cmd/analyze && GOOS=darwin go build ./... && GOOS=linux go build ./...`
Expected: both succeed with no errors. (This will fail until Tasks 2-4 are also done, since `insights.go` and `delete.go` still reference darwin-only tooling without a Linux counterpart yet — if so, note the specific compile errors and confirm they belong to Task 2/3/4 scope, not this task.)

- [ ] **Step 9: Commit**

```bash
git add cmd/analyze/overview_darwin.go cmd/analyze/overview_linux.go cmd/analyze/overview_linux_test.go cmd/analyze/main.go
git add -u cmd/analyze
git rm cmd/analyze/main_stub.go
git commit -m "[main] relax analyze build tags to darwin+linux, split overview roots"
```

---

## Task 2: Split `insights.go` into shared + platform-specific files

**Files:**
- Modify: `cmd/analyze/insights.go` — keep only the OS-agnostic parts (old-Downloads measurement, `measureInsightSize` dispatch, `getDirSizeFast`), change build tag to `//go:build darwin || linux`
- Create: `cmd/analyze/insights_darwin.go` — the macOS-only entries list (iOS Backups, Xcode*, Spotify, JetBrains, CocoaPods, OrbStack)
- Create: `cmd/analyze/insights_linux.go` — the Linux entries list (apt cache, npm/yarn/pnpm, Docker, systemd journal)
- Test: `cmd/analyze/insights_linux_test.go`

**Interfaces:**
- Consumes: `dirEntry` (from `cmd/analyze/model.go`)
- Produces: `createInsightEntries() []dirEntry` — same signature on both platforms, one impl per platform file
- Produces: `measureInsightSize(path string) (int64, error)` — stays in shared `insights.go`, unchanged signature, calls `measureOldDownloads` (shared) for the Downloads case on both platforms

- [ ] **Step 1: Write the failing test for Linux insights**

```go
// cmd/analyze/insights_linux_test.go
//go:build linux

package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestCreateInsightEntriesLinuxIncludesAptCacheWhenPresent(t *testing.T) {
	tmpHome := t.TempDir()
	t.Setenv("HOME", tmpHome)

	downloads := filepath.Join(tmpHome, "Downloads")
	if err := os.MkdirAll(downloads, 0o755); err != nil {
		t.Fatal(err)
	}

	entries := createInsightEntries()

	var foundDownloads bool
	for _, e := range entries {
		if e.Name == "Old Downloads (90d+)" {
			foundDownloads = true
		}
		if e.Path == "/var/cache/apt/archives" {
			t.Error("apt cache entry should only appear if the path exists; /var/cache/apt/archives is unlikely to exist in the test sandbox")
		}
	}
	if !foundDownloads {
		t.Error("expected Old Downloads entry when ~/Downloads exists")
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd cmd/analyze && GOOS=linux go vet ./... 2>&1 | head -20`
Expected: build error — `createInsightEntries` is still darwin-only (tagged `//go:build darwin`), so it doesn't exist for a linux build yet.

- [ ] **Step 3: Rewrite `insights.go` to keep only shared logic**

Replace the full contents of `cmd/analyze/insights.go`:

```go
// cmd/analyze/insights.go
//go:build darwin || linux

package main

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

// measureInsightSize measures the size of a path.
// Old Downloads is treated specially: only files older than 90 days are counted.
func measureInsightSize(path string) (int64, error) {
	home := os.Getenv("HOME")

	if home != "" && path == filepath.Join(home, "Downloads") {
		return measureOldDownloads(path, 90)
	}

	return measureOverviewSize(path)
}

// measureOldDownloads calculates total size of files in a directory
// that haven't been modified in the given number of days.
func measureOldDownloads(dir string, daysOld int) (int64, error) {
	cutoff := time.Now().AddDate(0, 0, -daysOld)
	var total int64

	entries, err := os.ReadDir(dir)
	if err != nil {
		return 0, err
	}

	for _, entry := range entries {
		if strings.HasPrefix(entry.Name(), ".") {
			continue
		}

		info, err := entry.Info()
		if err != nil {
			continue
		}

		if info.ModTime().Before(cutoff) {
			if entry.IsDir() {
				if size, err := getDirSizeFast(filepath.Join(dir, entry.Name())); err == nil {
					total += size
				}
			} else {
				total += info.Size()
			}
		}
	}

	return total, nil
}

// getDirSizeFast measures directory size using du.
func getDirSizeFast(path string) (int64, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	cmd := exec.CommandContext(ctx, "du", "-sk", path)
	output, err := cmd.Output()
	if err != nil {
		return 0, err
	}

	fields := strings.Fields(string(output))
	if len(fields) == 0 {
		return 0, nil
	}

	kb, err := strconv.ParseInt(fields[0], 10, 64)
	if err != nil {
		return 0, err
	}

	return kb * 1024, nil
}

// oldDownloadsInsightEntry returns the shared "Old Downloads (90d+)" entry
// if ~/Downloads exists, or false if there is nothing to show.
func oldDownloadsInsightEntry(home string) (dirEntry, bool) {
	downloadsPath := filepath.Join(home, "Downloads")
	if info, err := os.Stat(downloadsPath); err == nil && info.IsDir() {
		return dirEntry{
			Name:  "Old Downloads (90d+)",
			Path:  downloadsPath,
			IsDir: true,
			Size:  -1,
		}, true
	}
	return dirEntry{}, false
}

// appendExistingPathEntries appends one dirEntry per (name, path) pair whose
// path exists as a directory, in order.
func appendExistingPathEntries(entries []dirEntry, candidates []struct {
	name string
	path string
}) []dirEntry {
	for _, c := range candidates {
		if info, err := os.Stat(c.path); err == nil && info.IsDir() {
			entries = append(entries, dirEntry{Name: c.name, Path: c.path, IsDir: true, Size: -1})
		}
	}
	return entries
}
```

- [ ] **Step 4: Create `insights_darwin.go` with the macOS-only entries list**

```go
// cmd/analyze/insights_darwin.go
//go:build darwin

package main

import (
	"os"
	"path/filepath"
)

// createInsightEntries returns the list of hidden-space insight entries
// to show in the overview screen alongside the standard directory entries.
func createInsightEntries() []dirEntry {
	home := os.Getenv("HOME")
	if home == "" {
		return nil
	}

	var entries []dirEntry

	backupPath := filepath.Join(home, "Library", "Application Support", "MobileSync", "Backup")
	if info, err := os.Stat(backupPath); err == nil && info.IsDir() {
		entries = append(entries, dirEntry{Name: "iOS Backups", Path: backupPath, IsDir: true, Size: -1})
	}

	if entry, ok := oldDownloadsInsightEntry(home); ok {
		entries = append(entries, entry)
	}

	cleanablePaths := []struct {
		name string
		path string
	}{
		{"System Logs", filepath.Join(home, "Library", "Logs")},
		{"Homebrew Cache", filepath.Join(home, "Library", "Caches", "Homebrew")},
		{"Xcode DerivedData", filepath.Join(home, "Library", "Developer", "Xcode", "DerivedData")},
		{"Xcode Simulators", filepath.Join(home, "Library", "Developer", "CoreSimulator", "Devices")},
		{"Xcode Archives", filepath.Join(home, "Library", "Developer", "Xcode", "Archives")},
		{"Spotify Cache", filepath.Join(home, "Library", "Application Support", "Spotify", "PersistentCache")},
		{"JetBrains Cache", filepath.Join(home, "Library", "Caches", "JetBrains")},
		{"Docker Data", filepath.Join(home, "Library", "Containers", "com.docker.docker", "Data")},
		{"pip Cache", filepath.Join(home, "Library", "Caches", "pip")},
		{"Gradle Cache", filepath.Join(home, ".gradle", "caches")},
		{"CocoaPods Cache", filepath.Join(home, "Library", "Caches", "CocoaPods")},
	}
	if matches, err := filepath.Glob(filepath.Join(home, "Library", "Group Containers", "*dev.orbstack", "data")); err == nil {
		for _, match := range matches {
			if info, statErr := os.Stat(match); statErr == nil && info.IsDir() {
				cleanablePaths = append(cleanablePaths, struct {
					name string
					path string
				}{"OrbStack Data", match})
				break
			}
		}
	}
	entries = appendExistingPathEntries(entries, cleanablePaths)

	return entries
}
```

- [ ] **Step 5: Create `insights_linux.go` with the Linux entries list**

```go
// cmd/analyze/insights_linux.go
//go:build linux

package main

import (
	"os"
	"path/filepath"
)

// createInsightEntries returns the list of hidden-space insight entries
// to show in the overview screen alongside the standard directory entries.
func createInsightEntries() []dirEntry {
	home := os.Getenv("HOME")
	if home == "" {
		return nil
	}

	var entries []dirEntry

	if entry, ok := oldDownloadsInsightEntry(home); ok {
		entries = append(entries, entry)
	}

	cleanablePaths := []struct {
		name string
		path string
	}{
		{"APT Package Cache", "/var/cache/apt/archives"},
		{"npm Cache", filepath.Join(home, ".npm")},
		{"Yarn Cache", filepath.Join(home, ".cache", "yarn")},
		{"pnpm Store", filepath.Join(home, ".local", "share", "pnpm")},
		{"pip Cache", filepath.Join(home, ".cache", "pip")},
		{"Gradle Cache", filepath.Join(home, ".gradle", "caches")},
		{"Docker Data (rootless)", filepath.Join(home, ".local", "share", "docker")},
		{"Docker Data", "/var/lib/docker"},
	}
	entries = appendExistingPathEntries(entries, cleanablePaths)

	if size, err := journalDiskUsageBytes(); err == nil && size > 0 {
		entries = append(entries, dirEntry{Name: "systemd Journal Logs", Path: "journalctl", IsDir: false, Size: -1})
	}

	return entries
}
```

- [ ] **Step 6: Add the journal-size helper (Linux only, since `journalctl` output isn't a filesystem path `measureInsightSize` can `du` directly)**

Append to `cmd/analyze/insights_linux.go`:

```go
import (
	"context"
	"strconv"
	"strings"
	"time"
)

// journalDiskUsageBytes returns the disk space systemd's journal reports
// using, via `journalctl --disk-usage`. Journal storage is not a single
// du-able path the way other insight entries are, so this is measured
// directly instead of routed through measureInsightSize.
func journalDiskUsageBytes() (int64, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	cmd := exec.CommandContext(ctx, "journalctl", "--disk-usage")
	out, err := cmd.Output()
	if err != nil {
		return 0, err
	}

	// Output looks like: "Archived and active journals take up 128.0M in the file system."
	fields := strings.Fields(string(out))
	for i, f := range fields {
		if f == "up" && i+1 < len(fields) {
			return parseHumanSize(fields[i+1])
		}
	}
	return 0, nil
}

func parseHumanSize(s string) (int64, error) {
	units := map[byte]int64{'K': 1 << 10, 'M': 1 << 20, 'G': 1 << 30, 'T': 1 << 40}
	if len(s) == 0 {
		return 0, nil
	}
	last := s[len(s)-1]
	if mult, ok := units[last]; ok {
		val, err := strconv.ParseFloat(s[:len(s)-1], 64)
		if err != nil {
			return 0, err
		}
		return int64(val * float64(mult)), nil
	}
	val, err := strconv.ParseFloat(s, 64)
	if err != nil {
		return 0, err
	}
	return int64(val), nil
}
```

Add `"os/exec"` to the import block alongside the others.

- [ ] **Step 7: Run test to verify it passes**

Run: `cd cmd/analyze && GOOS=linux go build ./... && go test ./... -run TestCreateInsightEntriesLinuxIncludesAptCacheWhenPresent -v`

Note: cross-compiled tests can't execute on a darwin dev machine — if developing on macOS, run this step inside a Linux environment (e.g. the CI job from Task 6, or a local Linux VM/WSL). `go build` with `GOOS=linux` at minimum must succeed on any machine.

Expected: build succeeds; test PASS when actually run on Linux.

- [ ] **Step 8: Commit**

```bash
git add cmd/analyze/insights.go cmd/analyze/insights_darwin.go cmd/analyze/insights_linux.go cmd/analyze/insights_linux_test.go
git commit -m "[main] split analyze insights into darwin/linux entry lists"
```

---

## Task 3: Split `delete.go` into shared validation/policy + platform trash mechanism

**Context:** `delete.go` today mixes three concerns: (1) the trash-move mechanism (`moveToTrashViaBinary`/`moveToTrashViaFilesystem`/`moveToTrashViaFinder`, all macOS-specific), (2) path-safety validation (`validatePath`, `validateTrashTarget` — OS-agnostic), (3) protected-path policy (`isCriticalAnalyzeDeletePath`, EDR cache protection, home-root protection — the protected root *list* is macOS-specific, but the policy *logic* is shared). Only (1) needs a real Linux implementation *here*; the Linux trash mechanism itself is implemented once, in Task 5, as the shared `cmd/trash` package's writer, called from both `mole trash` and `analyze`'s delete path.

**Files:**
- Modify: `cmd/analyze/delete.go` — keep only shared logic: `deletePathCmd`, `deleteMultiplePathsCmd`, `multiDeleteError`, `trashPathWithProgress`, `moveToTrash` (dispatcher), `validateTrashTarget`, `isEndpointSecurityCachePath`, `endpointSecurityBundlePrefixes`, `protectedAnalyzeHomeRoots`, `isPathWithinExistingRoot`, `isSameExistingPath`, `isDirectChildOfExistingRoot`, `validatePath`. Change build tag to `//go:build darwin || linux`.
- Create: `cmd/analyze/delete_darwin.go` — `moveToTrashViaBinary`, `moveToTrashViaFilesystem`, `moveToTrashViaFinder`, `trashDirectoryForPath`, `ensureOwnedTrashDirectory`, `isCriticalAnalyzeDeletePath` (with the macOS critical-roots list), `trashBinary`/`trashTimeout` constants
- Create: `cmd/analyze/delete_linux.go` — Linux `moveToTrash` mechanism (delegates to the shared XDG trash writer from Task 5) and `isCriticalAnalyzeDeletePath` with a Linux critical-roots list
- Modify: `cmd/analyze/delete.go`'s `moveToTrash` — becomes a thin dispatcher calling a platform function `moveToTrashPlatform(absPath string) error`
- Test: `cmd/analyze/delete_linux_test.go`

**Interfaces:**
- Consumes (from Task 5, `cmd/trash` package — see that task for exact signatures): `trash.MoveToTrash(absPath string) error`
- Produces: `moveToTrashPlatform(absPath string) error` — one impl per platform file, called only from the shared `moveToTrash` in `delete.go`
- Produces: `isCriticalAnalyzeDeletePath(path string) bool` — same signature, per-platform root list

- [ ] **Step 1: Write the failing test for Linux critical-path protection**

```go
// cmd/analyze/delete_linux_test.go
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
```

- [ ] **Step 2: Run test to verify it fails**

Run (on a Linux machine or WSL): `cd cmd/analyze && go test ./... -run TestIsCriticalAnalyzeDeletePathLinux -v`
Expected: FAIL — `isCriticalAnalyzeDeletePath` is still darwin-only, doesn't exist in a linux build.

- [ ] **Step 3: Rewrite `delete.go` to keep only shared logic**

In `cmd/analyze/delete.go`:
- Change the build tag at the top to `//go:build darwin || linux`.
- Delete these functions/consts (they move to `delete_darwin.go`): `trashTimeout`, `trashBinary`, `moveToTrashViaBinary`, `moveToTrashViaFilesystem`, `moveToTrashViaFinder`, `trashDirectoryForPath`, `ensureOwnedTrashDirectory`, `isCriticalAnalyzeDeletePath`.
- Replace the body of `moveToTrash` (currently lines 130-154) with:

```go
func moveToTrash(path string) error {
	if err := validateTrashTarget(path); err != nil {
		return err
	}

	absPath, err := filepath.Abs(path)
	if err != nil {
		return fmt.Errorf("failed to resolve path: %w", err)
	}

	if err := validateTrashTarget(absPath); err != nil {
		return err
	}

	return moveToTrashPlatform(absPath)
}
```
- Remove now-unused imports (`os/exec`, `sort` stays since it's used by `deleteMultiplePathsCmd`, `syscall`, `golang.org/x/sys/unix` move to `delete_darwin.go`). Keep `context`, `fmt`, `os`, `os/user`, `path/filepath`, `slices`, `sort`, `strings`, `sync/atomic`, `time`.

- [ ] **Step 4: Create `delete_darwin.go` with the extracted macOS mechanism**

```go
// cmd/analyze/delete_darwin.go
//go:build darwin

package main

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"time"

	"golang.org/x/sys/unix"
)

const trashTimeout = 30 * time.Second

// trashBinary is Apple's own trash(8). It moves paths to the user Trash without
// involving Finder, which is what makes deletion work over SSH: the Finder
// AppleScript path raises a dialog on the physical machine that a remote user
// cannot answer, so the delete only ever times out (discussion #474).
const trashBinary = "/usr/bin/trash"

// moveToTrashPlatform moves a file/directory to the user Trash. macOS 15+
// ships trash(8); older supported systems use an atomic, no-overwrite move
// into the correct per-volume Trash. Finder is only the final compatibility
// fallback.
func moveToTrashPlatform(absPath string) error {
	if trashErr := moveToTrashViaBinary(absPath); trashErr == nil {
		return nil
	}
	if filesystemErr := moveToTrashViaFilesystem(absPath); filesystemErr == nil {
		return nil
	}
	return moveToTrashViaFinder(absPath)
}

func moveToTrashViaBinary(absPath string) error {
	if _, err := os.Stat(trashBinary); err != nil {
		return err
	}

	ctx, cancel := context.WithTimeout(context.Background(), trashTimeout)
	defer cancel()

	cmd := exec.CommandContext(ctx, trashBinary, absPath)
	output, err := cmd.CombinedOutput()
	if err != nil {
		if ctx.Err() == context.DeadlineExceeded {
			return fmt.Errorf("timeout moving to Trash")
		}
		return fmt.Errorf("failed to move to Trash: %s", strings.TrimSpace(string(output)))
	}

	return nil
}

func moveToTrashViaFilesystem(absPath string) error {
	trashDir, err := trashDirectoryForPath(absPath)
	if err != nil {
		return err
	}

	base := filepath.Base(absPath)
	if base == "." || base == string(filepath.Separator) || base == "" {
		return fmt.Errorf("invalid Trash item name")
	}

	stamp := time.Now().UnixNano()
	for attempt := range 100 {
		name := base
		if attempt > 0 {
			name = fmt.Sprintf("%s.%d.%d.%d", base, stamp, os.Getpid(), attempt)
		}
		dest := filepath.Join(trashDir, name)
		err = unix.RenameatxNp(unix.AT_FDCWD, absPath, unix.AT_FDCWD, dest, unix.RENAME_EXCL)
		if err == nil {
			return nil
		}
		if err != syscall.EEXIST {
			return fmt.Errorf("failed to move to Trash: %w", err)
		}
	}

	return fmt.Errorf("failed to choose unique Trash destination for %s", absPath)
}

func trashDirectoryForPath(absPath string) (string, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return "", fmt.Errorf("failed to resolve home directory: %w", err)
	}

	var pathFS, homeFS unix.Statfs_t
	if err := unix.Statfs(absPath, &pathFS); err != nil {
		return "", fmt.Errorf("failed to inspect target volume: %w", err)
	}
	if err := unix.Statfs(home, &homeFS); err != nil {
		return "", fmt.Errorf("failed to inspect home volume: %w", err)
	}

	if pathFS.Fsid == homeFS.Fsid {
		trashDir := filepath.Join(home, ".Trash")
		if err := ensureOwnedTrashDirectory(trashDir, true); err != nil {
			return "", err
		}
		return trashDir, nil
	}

	mountPoint := strings.TrimRight(string(pathFS.Mntonname[:]), "\x00")
	if mountPoint == "" {
		return "", fmt.Errorf("target volume has no mount point")
	}
	trashRoot := filepath.Join(mountPoint, ".Trashes")
	rootInfo, err := os.Lstat(trashRoot)
	if err != nil {
		return "", fmt.Errorf("volume Trash is unavailable: %w", err)
	}
	if rootInfo.Mode()&os.ModeSymlink != 0 || !rootInfo.IsDir() {
		return "", fmt.Errorf("volume Trash is not a normal directory")
	}

	trashDir := filepath.Join(trashRoot, fmt.Sprintf("%d", os.Getuid()))
	if err := ensureOwnedTrashDirectory(trashDir, true); err != nil {
		return "", err
	}
	return trashDir, nil
}

func ensureOwnedTrashDirectory(path string, create bool) error {
	info, err := os.Lstat(path)
	if os.IsNotExist(err) && create {
		if err := os.Mkdir(path, 0o700); err != nil {
			return fmt.Errorf("failed to create Trash directory: %w", err)
		}
		info, err = os.Lstat(path)
	}
	if err != nil {
		return fmt.Errorf("failed to inspect Trash directory: %w", err)
	}
	if info.Mode()&os.ModeSymlink != 0 || !info.IsDir() {
		return fmt.Errorf("trash path is not a normal directory")
	}

	stat, ok := info.Sys().(*syscall.Stat_t)
	if !ok || stat.Uid != uint32(os.Getuid()) {
		return fmt.Errorf("trash directory is not owned by the current user")
	}
	if info.Mode().Perm()&0o022 != 0 {
		return fmt.Errorf("trash directory is writable by another user")
	}
	return nil
}

// moveToTrashViaFinder remains as a last fallback for unusual volume layouts.
func moveToTrashViaFinder(absPath string) error {
	escapedPath := strings.ReplaceAll(absPath, "\\", "\\\\")
	escapedPath = strings.ReplaceAll(escapedPath, "\"", "\\\"")

	script := fmt.Sprintf(`tell application "Finder" to delete POSIX file "%s"`, escapedPath)

	ctx, cancel := context.WithTimeout(context.Background(), trashTimeout)
	defer cancel()

	cmd := exec.CommandContext(ctx, "osascript", "-e", script)
	output, err := cmd.CombinedOutput()
	if err != nil {
		if ctx.Err() == context.DeadlineExceeded {
			return fmt.Errorf("timeout moving to Trash")
		}
		return fmt.Errorf("failed to move to Trash: %s", strings.TrimSpace(string(output)))
	}

	return nil
}

func isCriticalAnalyzeDeletePath(path string) bool {
	criticalRoots := []string{
		"/", "/Applications", "/Applications/Finder.app", "/Applications/Safari.app",
		"/Library", "/Library/Apple", "/Library/Application Support", "/Library/Extensions",
		"/Library/Keychains", "/System", "/Users", "/Volumes", "/Network", "/cores",
		"/dev", "/etc", "/home", "/net", "/tmp", "/var", "/private", "/private/etc",
		"/private/tmp", "/private/var", "/private/var/audit", "/private/var/db",
		"/private/var/root", "/private/var/tmp", "/private/var/folders",
		"/bin", "/sbin", "/usr", "/opt", "/opt/homebrew",
	}
	for _, root := range criticalRoots {
		if path == root || isSameExistingPath(path, root) {
			return true
		}
	}

	if isDirectChildOfExistingRoot(path, "/Users") {
		return true
	}

	protectedTrees := []string{
		"/System", "/bin", "/sbin", "/usr", "/private/etc", "/private/var/audit",
		"/private/var/db", "/private/var/root", "/Library/Apple", "/Library/Extensions",
		"/Library/Keychains", "/Applications/Finder.app", "/Applications/Safari.app", "/dev",
	}
	for _, root := range protectedTrees {
		if strings.HasPrefix(path, root+string(filepath.Separator)) ||
			isPathWithinExistingRoot(path, root) {
			return true
		}
	}
	return false
}
```

- [ ] **Step 5: Create `delete_linux.go`**

```go
// cmd/analyze/delete_linux.go
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
```

Note: this references `github.com/tw93/mole/internal/xdgtrash`, built in Task 5. This task's build will not fully succeed until Task 5 exists — that is expected; note it and proceed, or reorder to do Task 5 first if working sequentially rather than via parallel subagents.

- [ ] **Step 6: Run test to verify it passes (after Task 5 exists)**

Run: `cd cmd/analyze && go test ./... -run TestIsCriticalAnalyzeDeletePathLinux -v`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add cmd/analyze/delete.go cmd/analyze/delete_darwin.go cmd/analyze/delete_linux.go cmd/analyze/delete_linux_test.go
git commit -m "[main] split analyze delete/trash mechanism into darwin/linux files"
```

---

## Task 4: Make Spotlight scan-acceleration conditional on darwin

**Files:**
- Modify: `cmd/analyze/scanner.go:26` (`mdfindSearch` or equivalent Spotlight-calling function) — no structural split needed, `useSpotlight` is already a threaded parameter
- Modify: `cmd/analyze/scanner.go` — wherever `useSpotlight` is set to `true` unconditionally by a caller (search for callers of `scanPathConcurrentWithOptions`/`findLargeFilesWithSpotlight` outside this file, in `model.go`/`update.go`)
- Test: `cmd/analyze/scanner_test.go` (add one case)

**Interfaces:**
- Consumes: nothing new
- Produces: no signature changes — `findLargeFilesWithSpotlight` and `useSpotlight`-parameterized functions keep their exact existing signatures; only the boolean value passed in changes based on `runtime.GOOS`

- [ ] **Step 1: Find where `useSpotlight` is decided for a real scan (not passed as a test parameter)**

Run: `grep -rn "useSpotlight" cmd/analyze/*.go | grep -v _test.go`

Read the calling context around each hit outside `scanner.go` to find where the top-level scan decides `true` vs `false`. This is likely in `model.go` or `update.go` where a scan command is constructed.

- [ ] **Step 2: Write the failing test**

```go
// Add to cmd/analyze/scanner_test.go
func TestFindLargeFilesWithSpotlightNoopOnLinux(t *testing.T) {
	if runtime.GOOS != "linux" {
		t.Skip("linux-only assertion")
	}
	// On Linux, mdfind does not exist; findLargeFilesWithSpotlight must return
	// an empty result rather than erroring or hanging.
	tmpDir := t.TempDir()
	files := findLargeFilesWithSpotlight(tmpDir, 0)
	if len(files) != 0 {
		t.Errorf("expected no files from findLargeFilesWithSpotlight on Linux, got %d", len(files))
	}
}
```

Add `"runtime"` to the test file's imports if not already present.

- [ ] **Step 3: Run test to verify current behavior**

Run (on Linux/WSL): `cd cmd/analyze && go test ./... -run TestFindLargeFilesWithSpotlightNoopOnLinux -v`
Expected: likely already PASS if `exec.Command("mdfind", ...)` simply errors out cleanly on Linux (command not found → `Output()` returns an error → function should already return nil/empty). Confirm this is true by reading `findLargeFilesWithSpotlight`'s error handling at `scanner.go:599-673`. If it already handles the missing-binary case gracefully, this step just documents/locks the behavior; if not, proceed to Step 4.

- [ ] **Step 4: If needed, guard the call explicitly**

Only if Step 3 shows a problem (e.g. a long hang instead of a fast error), wrap the call site found in Step 1:

```go
useSpotlight := runtime.GOOS == "darwin"
```

Add `"runtime"` import where this line is inserted if not already present in that file.

- [ ] **Step 5: Run test to verify it passes**

Run: `cd cmd/analyze && go test ./... -run TestFindLargeFilesWithSpotlightNoopOnLinux -v`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add cmd/analyze/scanner.go cmd/analyze/scanner_test.go
git commit -m "[main] gate Spotlight scan acceleration to darwin"
```

---

## Task 5: Implement the XDG Trash spec as a shared internal package

**Files:**
- Create: `internal/xdgtrash/xdgtrash.go`
- Create: `internal/xdgtrash/xdgtrash_test.go`

**Interfaces:**
- Produces: `Move(absPath string) error` — moves a file/dir into `~/.local/share/Trash/{files,info}`, writing a `.trashinfo` sidecar; used by `cmd/analyze/delete_linux.go` (Task 3) and `cmd/trash` (Task 6)
- Produces: `type Item struct { Name string; OriginalPath string; DeletedAt time.Time; Size int64; IsDir bool }`
- Produces: `List() ([]Item, error)` — parses every `.trashinfo` file and pairs it with its `files/` entry
- Produces: `TotalSize() (int64, error)` — sum of all trashed item sizes
- Produces: `EmptyAll() error` — permanently deletes every item
- Produces: `EmptyOne(name string) error` — permanently deletes one item by its trash-file name (as returned in `Item.Name`)

- [ ] **Step 1: Write the failing test for `Move` + `.trashinfo` format**

```go
// internal/xdgtrash/xdgtrash_test.go
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd internal/xdgtrash && go test ./... -v`
Expected: FAIL — package doesn't exist yet (no `xdgtrash.go`).

- [ ] **Step 3: Implement `xdgtrash.go`**

```go
// Package xdgtrash implements the freedesktop.org Trash specification
// (files/ + info/*.trashinfo under $XDG_DATA_HOME/Trash) directly, with no
// external dependency on trash-cli or gio.
package xdgtrash

import (
	"fmt"
	"os"
	"path/filepath"
	"strconv"
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

	if err := os.RemoveAll(filePath); err != nil {
		return fmt.Errorf("failed to remove trashed item: %w", err)
	}
	if err := os.Remove(infoPath); err != nil && !os.IsNotExist(err) {
		return fmt.Errorf("failed to remove trashinfo: %w", err)
	}
	return nil
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

var _ = strconv.Itoa // placeholder removed if strconv ends up unused
```

Remove the trailing `var _ = strconv.Itoa` line and the `"strconv"` import — it was a placeholder to catch unused-import risk during drafting; the real file has no use for `strconv`, so both must be deleted before this compiles cleanly.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd internal/xdgtrash && go test ./... -v`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add internal/xdgtrash/
git commit -m "[main] implement XDG Trash spec as shared internal package"
```

---

## Task 6: Build the `mole trash` subcommand

**Files:**
- Create: `cmd/trash/main.go`
- Create: `cmd/trash/main_test.go`
- Create: `bin/trash.sh`
- Modify: `mole` — add `"trash")` case to the dispatch, following the exact pattern of `"status")` at line 252-254
- Modify: `Makefile` — add `TRASH := trash`, `TRASH_SRC := ./cmd/trash`, build/clean/release rules mirroring `ANALYZE`/`STATUS`

**Interfaces:**
- Consumes: `xdgtrash.List() ([]xdgtrash.Item, error)`, `xdgtrash.TotalSize() (int64, error)`, `xdgtrash.EmptyAll() error`, `xdgtrash.EmptyOne(name string) error` (from Task 5)
- Produces: CLI surface — `mole trash` (list), `mole trash empty` (empty all), `mole trash empty <name>` (empty one)

- [ ] **Step 1: Write the failing test for the list/empty command dispatch**

```go
// cmd/trash/main_test.go
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd cmd/trash && go test ./... -v`
Expected: FAIL — package/functions don't exist yet.

- [ ] **Step 3: Implement `cmd/trash/main.go`**

```go
// Package main provides the mo trash command for managing the XDG Trash
// on Linux, where there is no Finder to own this responsibility.
package main

import (
	"flag"
	"fmt"
	"io"
	"os"

	"github.com/tw93/mole/internal/xdgtrash"
)

func humanBytes(n int64) string {
	const unit = 1024
	if n < unit {
		return fmt.Sprintf("%d B", n)
	}
	div, exp := int64(unit), 0
	for v := n / unit; v >= unit; v /= unit {
		div *= unit
		exp++
	}
	units := "KMGTPE"
	return fmt.Sprintf("%.1f %ciB", float64(n)/float64(div), units[exp])
}

func runList(w io.Writer) error {
	items, err := xdgtrash.List()
	if err != nil {
		return err
	}
	if len(items) == 0 {
		fmt.Fprintln(w, "Trash is empty.")
		return nil
	}

	total, err := xdgtrash.TotalSize()
	if err != nil {
		return err
	}
	fmt.Fprintf(w, "Trash: %s in %d item(s)\n\n", humanBytes(total), len(items))
	for _, item := range items {
		kind := "file"
		if item.IsDir {
			kind = "dir"
		}
		fmt.Fprintf(w, "  %-30s %8s  %s  (%s, deleted %s)\n",
			item.Name, humanBytes(item.Size), item.OriginalPath, kind,
			item.DeletedAt.Format("2006-01-02 15:04"))
	}
	return nil
}

func runEmptyAll() error {
	return xdgtrash.EmptyAll()
}

func runEmptyOne(name string) error {
	return xdgtrash.EmptyOne(name)
}

func main() {
	flag.Parse()
	args := flag.Args()

	var err error
	switch {
	case len(args) == 0:
		err = runList(os.Stdout)
	case args[0] == "empty" && len(args) == 1:
		err = runEmptyAll()
		if err == nil {
			fmt.Println("Trash emptied.")
		}
	case args[0] == "empty" && len(args) == 2:
		err = runEmptyOne(args[1])
		if err == nil {
			fmt.Printf("Removed %s from trash.\n", args[1])
		}
	default:
		fmt.Fprintln(os.Stderr, "usage: mole trash [empty [<item-name>]]")
		os.Exit(1)
	}

	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd cmd/trash && go test ./... -v`
Expected: PASS.

- [ ] **Step 5: Add `bin/trash.sh` wrapper, following the exact pattern of `bin/status.sh`**

```bash
#!/bin/bash
# Mole - Trash command.
# Manages the XDG Trash on Linux (no Finder to own this on Linux/WSL).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GO_BIN="$SCRIPT_DIR/trash-go"
if [[ -x "$GO_BIN" ]]; then
    exec "$GO_BIN" "$@"
fi

echo "Bundled trash binary not found. Please reinstall Mole or run mo update to restore it." >&2
exit 1
```

Run: `chmod +x bin/trash.sh`

- [ ] **Step 6: Wire `trash` into the `mole` router dispatch**

In `mole`, find the case block containing `"status")` (around line 252-254):

```bash
        "status")
            exec "$SCRIPT_DIR/bin/status.sh" "${args[@]:1}"
            ;;
```

Add immediately after it:

```bash
        "trash")
            exec "$SCRIPT_DIR/bin/trash.sh" "${args[@]:1}"
            ;;
```

- [ ] **Step 7: Add `trash` to the Makefile build/clean targets**

In `Makefile`, add alongside the existing `ANALYZE`/`STATUS` definitions:

```makefile
TRASH := trash
TRASH_SRC := ./cmd/trash
```

In the `build:` target, add:

```makefile
	$(GO) build -ldflags="$(LDFLAGS)" -o $(BIN_DIR)/$(TRASH)-go $(TRASH_SRC)
```

In `clean:`, extend the `rm -f` line to include `$(BIN_DIR)/$(TRASH)-* $(BIN_DIR)/$(TRASH)-go`.

(Release targets `release-amd64`/`release-arm64` build darwin binaries only — `trash` is Linux-only in this phase, so it is intentionally NOT added there; it only needs the local `build:` target so `./mole trash` works from a source checkout, per this repo's convention of testing via `./mole` before installation.)

- [ ] **Step 8: Build and manually verify end-to-end**

Run: `make build && MOLE_TEST_NO_AUTH=1 ./mole trash`
Expected: prints "Trash is empty." (or lists items if the local `~/.local/share/Trash` already has some — this is your real trash, so nothing here modifies it unless you explicitly run `./mole trash empty`).

- [ ] **Step 9: Commit**

```bash
git add cmd/trash/ bin/trash.sh mole Makefile
git commit -m "[main] add mole trash subcommand for Linux trash management"
```

---

## Task 7: Add Linux process listing to `status`

**Context:** `metrics_process.go:16-19` returns `nil, nil` unconditionally on non-darwin — this is the one real gap in `status` (most other metrics already have working fallbacks via gopsutil or `/sys`). gopsutil's `process` package (already imported transitively via `github.com/shirou/gopsutil/v4`) supports Linux natively.

**Files:**
- Modify: `cmd/status/metrics_process.go`
- Test: `cmd/status/metrics_process_test.go` (new file, or add to existing if one exists — check first)

**Interfaces:**
- Consumes: `github.com/shirou/gopsutil/v4/process` (already a transitive dependency via go.mod's `gopsutil/v4` — verify it's usable directly by checking `go.sum` includes the `process` subpackage, or run `go get github.com/shirou/gopsutil/v4/process` if needed)
- Produces: `collectProcesses() ([]ProcessInfo, error)` — same signature, must now return real data on both darwin and linux

**`ProcessInfo` struct fields** (verify against `cmd/status/metrics.go` before writing — do not guess field names):

- [ ] **Step 1: Confirm the exact `ProcessInfo` struct fields**

Run: `grep -n "type ProcessInfo struct" -A 15 cmd/status/metrics.go`

Read the output and use those exact field names in Step 3 below — do not assume PID/CPU/Mem/RSS/Command are the real names without checking.

- [ ] **Step 2: Write the failing test**

```go
// cmd/status/metrics_process_test.go
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
```

- [ ] **Step 3: Run test to verify it fails**

Run (on Linux/WSL): `cd cmd/status && go test ./... -run TestCollectProcessesReturnsDataOnLinux -v`
Expected: FAIL — `collectProcesses` returns `nil, nil` on non-darwin today.

- [ ] **Step 4: Implement the Linux path using gopsutil**

In `cmd/status/metrics_process.go`, replace lines 16-19:

```go
func collectProcesses() ([]ProcessInfo, error) {
	if runtime.GOOS == "darwin" {
		ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
		defer cancel()

		out, err := runCmd(ctx, "ps", "-Aceo", "pid=,ppid=,pcpu=,pmem=,rss=,comm=", "-r")
		if err != nil {
			out, err = runCmd(ctx, "ps", "aux")
			if err != nil {
				return nil, err
			}
			return parsePsAuxOutput(out), nil
		}
		return parseProcessOutput(out), nil
	}

	return collectProcessesGopsutil()
}
```

Then add a new function in the same file (fields below are placeholders for whatever Step 1 revealed — replace `PID`/`PPID`/`CPUPercent`/`MemPercent`/`RSS`/`Command` with the real field names before writing this):

```go
func collectProcessesGopsutil() ([]ProcessInfo, error) {
	pids, err := process.Pids()
	if err != nil {
		return nil, err
	}

	procs := make([]ProcessInfo, 0, len(pids))
	for _, pid := range pids {
		p, err := process.NewProcess(pid)
		if err != nil {
			continue
		}
		name, err := p.Name()
		if err != nil {
			continue
		}
		cpuPercent, _ := p.CPUPercent()
		memPercent, _ := p.MemoryPercent()
		var rss uint64
		if memInfo, err := p.MemoryInfo(); err == nil && memInfo != nil {
			rss = memInfo.RSS
		}
		ppid, _ := p.Ppid()

		procs = append(procs, ProcessInfo{
			PID:        int(pid),
			PPID:       int(ppid),
			CPUPercent: cpuPercent,
			MemPercent: float64(memPercent),
			RSS:        rss,
			Command:    name,
		})
	}
	return procs, nil
}
```

Add `"github.com/shirou/gopsutil/v4/process"` to the import block.

- [ ] **Step 5: Run test to verify it passes**

Run: `cd cmd/status && go test ./... -run TestCollectProcessesReturnsDataOnLinux -v`
Expected: PASS.

- [ ] **Step 6: Run the full status test suite to check for regressions**

Run: `cd cmd/status && go test ./...`
Expected: all PASS, including existing darwin-path tests (unaffected — the darwin branch is untouched).

- [ ] **Step 7: Commit**

```bash
git add cmd/status/metrics_process.go cmd/status/metrics_process_test.go
git commit -m "[main] add Linux process listing to status via gopsutil"
```

---

## Task 8: Omit unavailable metric rows on Linux in `status` view

**Context:** Per the design spec, bluetooth/GPU/hardware-refinement rows with no Linux data source must be omitted from the rendered dashboard entirely, not shown as "N/A". Battery is already handled correctly (real Linux data via `/sys/class/power_supply`, and `collectBatteries` already returns an empty slice + error when no `BAT*` glob matches — confirm the view layer already skips rendering on empty/error before assuming this needs a change). This task covers all three flagged-empty metrics — bluetooth, GPU, and the hardware refinements (model/CPU name/refresh rate) — not just bluetooth.

**Files:**
- Modify: `cmd/status/view.go` — wherever bluetooth/GPU/hardware rows are unconditionally rendered
- Test: `cmd/status/view_test.go` (add cases)

**Interfaces:**
- Consumes: existing `MetricsSnapshot` fields for bluetooth/GPU/hardware (check `cmd/status/metrics.go` for exact field names before editing)

- [ ] **Step 1: Find the current rendering logic for bluetooth/GPU/hardware rows**

Run: `grep -n "Bluetooth\|GPU\|Hardware\|RefreshRate\|CPUModel" cmd/status/view.go`

Read the surrounding context for each hit to see whether the row is already conditionally skipped when the data is empty (e.g. `if snapshot.Bluetooth != nil { ... }`) or always rendered (e.g. hardcoded row with a fallback string like "N/A"/"Unknown"). Recall `metrics_hardware.go:11-21` already returns `"Unknown"`/`runtime.GOARCH` on non-darwin rather than empty — check whether the view should suppress that row too on Linux, or whether showing "Unknown" there is acceptable (this is a narrower case than bluetooth/GPU, which return fully empty/zero-value data on Linux). Note your finding for each of the three metrics before writing tests.

- [ ] **Step 2: Write the failing tests (only for rows Step 1 shows are unconditionally rendered)**

For each of bluetooth, GPU, and hardware, write one regression test confirming the correct Linux behavior found in Step 1. Example for bluetooth (repeat the pattern for GPU; for hardware, assert on whatever Step 1 determined — omission or "Unknown" — rather than assuming omission is correct there too):

```go
// Add to cmd/status/view_test.go — exact snapshot construction depends on
// MetricsSnapshot's real field names/types; inspect cmd/status/metrics.go
// first and adjust field names below accordingly.
func TestRenderOmitsBluetoothRowWhenEmpty(t *testing.T) {
	snapshot := MetricsSnapshot{} // zero-value: no bluetooth data
	output := renderSnapshot(snapshot) // replace with the real render function name from view.go
	if strings.Contains(output, "Bluetooth") {
		t.Error("expected no Bluetooth row when bluetooth data is empty")
	}
}

func TestRenderOmitsGPURowWhenEmpty(t *testing.T) {
	snapshot := MetricsSnapshot{} // zero-value: no GPU data
	output := renderSnapshot(snapshot)
	if strings.Contains(output, "GPU") {
		t.Error("expected no GPU row when GPU data is empty")
	}
}
```

- [ ] **Step 3: Run tests to verify current behavior**

Run: `cd cmd/status && go test ./... -run 'TestRenderOmitsBluetoothRowWhenEmpty|TestRenderOmitsGPURowWhenEmpty' -v`
Expected PASS if already correctly gated (this locks in existing correct behavior with a regression test); FAIL if a row shows a hardcoded fallback string that needs removing.

- [ ] **Step 4: If needed, fix the render to skip a row entirely on empty data**

Only for rows where Step 3 failed: find the unconditional render block from Step 1 and wrap it in the same existence check other optional rows already use elsewhere in `view.go` (follow the existing pattern in the file for a comparable optional row — do not invent a new pattern).

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd cmd/status && go test ./... -run 'TestRenderOmitsBluetoothRowWhenEmpty|TestRenderOmitsGPURowWhenEmpty' -v`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add cmd/status/view.go cmd/status/view_test.go
git commit -m "[main] confirm status omits bluetooth/GPU rows when unavailable on Linux"
```

---

## Task 9: Add Linux CI lane

**Files:**
- Modify: `.github/workflows/test.yml`

**Interfaces:** none (CI config only)

- [ ] **Step 1: Read the current `test.yml` job structure in full**

Run: `cat .github/workflows/test.yml`

Confirm the exact step sequence (checkout, tool install, Go setup, test invocation) used by the existing `tests` job so the new job mirrors it minus the macOS-only tool installs (`bats-core`, `shellcheck`, `coreutils`, `parallel` via `brew` — not needed since this new job only runs `go test`).

- [ ] **Step 2: Add a new `go-test-linux` job**

Add a new job to `.github/workflows/test.yml`, alongside the existing `tests` job:

```yaml
  go-test-linux:
    name: Go Tests (Linux)
    runs-on: ubuntu-latest
    timeout-minutes: 15
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1

      - name: Set up Go
        uses: actions/setup-go@b7ad1dad31e06c5925ef5d2fc7ad053ef454303e # v7.0.0
        with:
          go-version-file: go.mod

      - name: Run Go tests
        run: go test ./...
```

(Pin the same action SHAs already used in the `tests` job — copy them exactly rather than retyping, to avoid an accidental version drift between the two jobs.)

- [ ] **Step 3: Verify YAML validity**

Run: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/test.yml'))"`
Expected: no error (confirms valid YAML syntax before pushing).

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/test.yml
git commit -m "[main] add Linux CI lane for go test"
```

---

## Task 10: Manual end-to-end verification on Linux/WSL

This task has no code changes — it is the final acceptance check, run by hand on the user's actual WSL environment before considering Phase 1 done.

- [ ] **Step 1: Build all three binaries**

Run: `make build`
Expected: `bin/analyze-go`, `bin/status-go`, `bin/trash-go` all produced with no errors.

- [ ] **Step 2: Run analyze and manually verify the overview screen**

Run: `MOLE_TEST_NO_AUTH=1 ./mole analyze`
Expected: overview shows Home, System Cache (`/var`), Installed Software (`/usr`), plus any present insight entries (APT cache, npm/yarn/pnpm, Docker, journal) — no crash, no reference to `/Applications` or `/Library`.

- [ ] **Step 3: Manually test a delete-to-trash from analyze**

Navigate into a scratch directory with a throwaway test file, delete it via analyze's delete key, then confirm:

Run: `./mole trash`
Expected: the deleted file appears in the list with its correct original path and size.

- [ ] **Step 4: Run status and manually verify the dashboard**

Run: `MOLE_TEST_NO_AUTH=1 ./mole status`
Expected: CPU/memory/disk/network/process rows show real data; no Bluetooth/GPU row appears; battery row is absent (expected on WSL, no `/sys/class/power_supply/BAT*`).

- [ ] **Step 5: Test `mole trash empty` round-trip**

Run: `./mole trash empty` (only after confirming via Step 3 that only intended test files are in trash — this permanently deletes everything currently there)
Expected: prints "Trash emptied.", and a follow-up `./mole trash` shows "Trash is empty."

- [ ] **Step 6: Run the full Go test suite one more time**

Run: `go test ./...`
Expected: all PASS.

- [ ] **Step 7: Report results back for final spec sign-off**

No commit for this task — report the manual verification outcomes to the user so they can confirm Phase 1 is genuinely usable on their WSL setup before moving to Phase 2 (`clean`/`uninstall`) design.
