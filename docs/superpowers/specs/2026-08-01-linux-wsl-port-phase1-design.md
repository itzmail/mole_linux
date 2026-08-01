# Linux/WSL Port — Phase 1 Design (`analyze`, `status`, `trash`)

Date: 2026-08-01
Status: Approved for planning

## Context

Mole is currently a macOS-only CLI (shell + Go). The user runs Linux via WSL and
wants Mole to be genuinely functional there, not just buildable. A full
portability audit (see summary below) found the codebase splits roughly into:

- ~35% of the shell layer is portable as-is or with trivial path changes
  (UI layer, core plumbing: log, history, help, menu system).
- ~45% needs a Linux-equivalent reimplementation (app existence checks via
  package managers instead of Spotlight/`mdfind`, XDG path remapping, Trash
  via XDG spec instead of Finder AppleScript, uninstall teardown via
  systemd/apt/snap/flatpak instead of `launchctl`/`.plist`).
- ~20% is macOS-only and should be dropped or no-op'd on Linux (bundle-ID
  protection data, Spotlight/TimeMachine/launch-services optimize tasks,
  GUI-auth AppleScript dialogs).

`clean` and `uninstall` are the heaviest lift because macOS's app-bundle +
`.plist` + Spotlight model for "what is installed and where does its data
live" has no 1:1 Linux equivalent — that needs its own product decision
(target apt/dpkg? snap? flatpak? some combination?) and is explicitly
out of scope for this phase.

`optimize` is mostly macOS-specific maintenance tasks (Spotlight reindex,
`launchctl`, `defaults` writes) with little to no Linux equivalent; it is
not part of any planned phase and will likely remain macOS-only.

## Scope

This phase ports exactly three things, chosen because they are the cheapest
to port and require the fewest unresolved product decisions:

1. `analyze` — disk explorer TUI (Go, Bubble Tea)
2. `status` — read-only health dashboard (Go)
3. `mole trash` — new subcommand, needed because this phase introduces a
   Linux delete-to-trash mechanism with no macOS Finder equivalent to manage it

`clean`, `uninstall`, and `optimize` are explicitly deferred. This spec does
not design them.

**macOS is unaffected.** Every change below uses Go's `_darwin.go` / `_linux.go`
file-suffix convention or additive `runtime.GOOS` branches. No existing
macOS code path is modified or removed; the darwin build continues to compile
and behave exactly as it does today.

## 1. `analyze`

### Current state

Every file in `cmd/analyze/` carries `//go:build darwin`; `main_stub.go`
(`//go:build !darwin`) just prints "analyze is only supported on macOS" and
exits 1. This is a hard compile-time wall, not a runtime assumption problem.

Auditing the actual macOS-only logic inside shows it's narrower than the
blanket build tag implies:

- Spotlight (`mdfind`) used as an optional scan-acceleration path
  (`scanner.go`) — not required for correctness, only speed.
- Trash-move via `osascript` + Finder (`delete.go`).
- Hardcoded macOS root shortcuts on the overview screen: Home, `~/Library`
  (renamed "User Library"), `/Applications`, `/Library` ("System Library")
  (`main.go`, `cleanable.go`).
- A macOS-specific "hidden space insights" list: iOS Backups, old Downloads,
  Xcode DerivedData/Simulators/Archives, Spotify/JetBrains/CocoaPods caches,
  OrbStack data (`insights.go`).
- `syscall.Stat_t` / `syscall.Statfs_t` usage — these exist on Linux too with
  compatible field access; not a real blocker, just needs compile verification.

The core scanning/TUI/sort/filter logic (the majority of the package) is
OS-agnostic: walk a directory, compute sizes, render a list.

### Design

Relax the build tag to `//go:build darwin || linux` across `cmd/analyze/*.go`
and delete `main_stub.go`. Split the genuinely OS-specific pieces into
paired files using Go's standard `_darwin.go` / `_linux.go` suffix
convention (compiled automatically per-OS, no manual tag juggling):

- **`overview_darwin.go` / `overview_linux.go`** — top-level overview roots.
  - macOS (unchanged): Home, User Library, Applications, System Library.
  - Linux: Home, `/var`, `/usr`.
- **`insights_darwin.go` / `insights_linux.go`** — hidden-space insights list.
  - macOS (unchanged): iOS Backups, old Downloads, Xcode*, Spotify,
    JetBrains, CocoaPods, OrbStack.
  - Linux: old Downloads (same 90-day logic, OS-agnostic), apt archive cache
    (`/var/cache/apt/archives`), npm/yarn/pnpm caches (`~/.npm`,
    `~/.cache/yarn`, `~/.local/share/pnpm`), Docker data (`/var/lib/docker`
    or rootless `~/.local/share/docker`), persistent systemd journal
    (`journalctl`-managed logs).
- **`trash_darwin.go` / `trash_linux.go`** — delete-to-trash mechanism.
  - macOS (unchanged): `osascript` + Finder.
  - Linux: implement the freedesktop.org XDG Trash spec directly in Go (see
    §3) — no external dependency (not `trash-cli`, not `gio trash`).
- **`scanner.go`**: Spotlight acceleration (`mdfind`) becomes conditional on
  `runtime.GOOS == "darwin"`. Linux always uses the plain filesystem walk;
  this is not a gap needing a replacement, since Linux directory walks
  don't need an indexed-search shortcut for this use case.

Everything else in the package (TUI state machine, sorting, filtering, size
computation) is unchanged and compiles on Linux as-is.

## 2. `status`

### Current state

`cmd/status` is **not** build-tag-gated — it already compiles on every OS.
Every metrics file isolates macOS-only logic behind explicit
`runtime.GOOS == "darwin"` checks (CPU, memory, network, process, disk,
battery, bluetooth, GPU, hardware). gopsutil (already an existing dependency)
returns real cross-platform data for CPU, memory, disk, network, and
process metrics. Right now, non-darwin branches largely fall through to
gopsutil's raw values with no refinement, or are simply absent.

### Design

Add a Linux branch alongside each existing darwin branch (never replacing
or modifying the darwin branch):

- **CPU / memory / network / process**: use gopsutil's cross-platform
  values directly. The existing darwin branches are macOS-only
  *refinements* on top of the same base data; Linux ships without those
  refinements initially.
- **disk**: use gopsutil's raw usage; skip the APFS-specific correction
  logic (not applicable to ext4 or other common Linux filesystems). WSL's
  `/mnt/*` drvfs mounts are not specially handled in this phase.
- **battery**: read `/sys/class/power_supply/BAT*/capacity` and
  `.../status`. If no `BAT*` entry exists (the normal case for WSL, since
  it's a VM with no direct hardware access), omit the row entirely.
- **bluetooth / GPU / hardware**: no Linux implementation in this phase.
  Omit these rows entirely rather than showing "N/A" — consistent with
  this project's existing "don't clutter the dashboard" principle, and
  these are not meaningful on WSL regardless.

## 3. `mole trash` (new subcommand)

### Motivation

Phase 1 introduces a Linux delete-to-trash mechanism (§1) with no Finder to
manage it. Without a way to view or reclaim that space, deleted files would
accumulate invisibly in `~/.local/share/Trash` forever — defeating the
purpose of a disk-cleanup tool. This is a real gap the design creates, not
speculative scope creep.

### Design

Implement the freedesktop.org XDG Trash specification directly in Go, no
external dependency (not `trash-cli`, not `gio trash`):

- Deleting a path moves it to `~/.local/share/Trash/files/<name>` and
  writes matching metadata to
  `~/.local/share/Trash/info/<name>.trashinfo` (original path + deletion
  timestamp), per spec. Name collisions are resolved by appending a
  numeric suffix.
- Because this follows the real XDG spec, files trashed by Mole remain
  restorable via any spec-compliant tool a user might already have
  (Nautilus, Dolphin, `trash-cli`, etc.), and vice versa.

New subcommand surface (mirrors Mole's existing subcommand pattern —
`clean`, `uninstall`, `analyze`, `status`):

- `mole trash` — show total trash size and an itemized list (name,
  original path, deletion date, size).
- `mole trash empty` — permanently delete everything in trash.
- `mole trash empty <item>` — permanently delete one selected item.

Implementation lives as a new small Go package (`cmd/trash/`), consistent
with `analyze` and `status` already being separate Go binaries invoked by
the `mole` shell router, since itemizing/parsing `.trashinfo` files and
computing sizes is more natural in Go than bash.

On macOS, `mole trash` is out of scope for this phase: Finder already owns
trash management there, and the existing macOS delete-to-trash path via
Finder AppleScript is unchanged. (Whether `mole trash` should later no-op,
defer to Finder, or stay Linux-only is a decision for when/if that need
arises — not fixed by this spec.)

## 4. Testing

- Go: existing `cmd/analyze` tests currently tagged `//go:build darwin`
  follow the same split — `_darwin_test.go` / `_linux_test.go` pairs where
  behavior differs (e.g. overview root lists), shared tests otherwise.
- New `cmd/trash` package gets its own unit tests covering XDG spec
  compliance: correct `.trashinfo` format, collision handling, and a
  restore round-trip (move to trash, confirm metadata, confirm restorable).
- CI: add an `ubuntu-latest` job to `.github/workflows/test.yml` running at
  minimum `go test ./...`. The bats shell-test suite stays macOS-only for
  this phase since `clean`/`uninstall` (the shell-heavy commands) are not
  in scope.

## Out of scope (explicitly deferred)

- `clean` — needs its own design pass: XDG path remapping
  (`~/Library/*` → `~/.cache` / `~/.config` / `~/.local/share`), and a
  decision on what replaces Spotlight-based app-existence checks.
- `uninstall` — needs its own design pass: macOS's single `.app` bundle
  concept has no 1:1 Linux equivalent; target package manager(s)
  (apt/dpkg, snap, flatpak, or some combination) must be decided first.
- `optimize` — mostly macOS-specific maintenance tasks (Spotlight reindex,
  `launchctl`, `defaults` writes) with little to no Linux equivalent.
  Not currently planned for any phase; likely remains macOS-only
  permanently.
