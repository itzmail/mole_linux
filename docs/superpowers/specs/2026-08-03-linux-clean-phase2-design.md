# Linux/WSL Port — Phase 2: `mole clean` Design

## Context

Phase 1 (merged to `main` in `6be635de`) ported `analyze`, `status`, and the
new `mole trash` subcommand to Linux/WSL. `clean` and `uninstall` were
explicitly deferred. This spec covers Phase 2a: `clean` only. `uninstall`
gets its own brainstorming session later.

`bin/clean.sh` is a single orchestrator that sources every `lib/clean/*.sh`
module and runs a fixed, numbered pipeline of 16 sections (System, User
essentials, App caches, Browsers, Cloud & Office, Developer tools,
Applications, Virtualization, Application Support, App leftovers, Apple
Silicon, Device backups & firmware, Time Machine, Large files, System Data
clues, Project artifacts). Every section assumes Darwin: there is currently
**zero** `uname`/`OSTYPE`/`GOOS`-style branching anywhere in the shell layer
(`mole`, `lib/core/*.sh`, `lib/clean/*.sh`). This spec introduces the first
such branch.

## Goal

Give `mole clean` real, measurable, safe cleanup targets on Linux/WSL,
following the same safety plumbing (`mole_delete`, `should_protect_path`,
dry-run ledger, whitelist) that macOS sections already use, without touching
any existing Darwin code path.

## Non-Goals (explicit out of scope)

- **Homebrew-native flows** (`lib/clean/brew.sh`). No Linux equivalent is
  designed here; a Linux package-manager cleanup story is limited to the
  apt/docker delegation below, not a general "brew for Linux" abstraction.
- **Orphaned LaunchDaemon-style service scanning**
  (`clean_orphaned_system_services`). systemd's unit model differs enough
  (user vs system units, `systemctl --failed`, no `/Library/LaunchDaemons`
  equivalent) that this needs its own design, not a drop-in port.
- **Apple Silicon caches, Time Machine, device firmware, Finder metadata**:
  no Linux/WSL equivalent exists.
- **`uninstall` porting**: separate brainstorming session.
- Any new CLI flag, environment variable, or config key. Per AGENTS.md, a new
  knob is the same weight as a new setting — none is introduced here.

## Design

### 1. Platform dispatch

`bin/clean.sh` gains one new conditional source, guarded by `uname -s`:

```bash
if [[ "$(uname -s)" == "Linux" ]]; then
    source "$SCRIPT_DIR/../lib/clean/linux.sh"
fi
```

This is the first OS-gate in the shell layer. It is additive only — every
existing `source` line and every Darwin section is untouched.

### 2. New module: `lib/clean/linux.sh`

One new file, following the existing per-module convention (a handful of
`clean_*` entry points, each independently testable, each wrapped in
`start_section`/`end_section` by the caller). Single file for this round
(not split like `user.sh`/`dev.sh`/`apps.sh`) because the scope is small and
splitting prematurely would fight YAGNI; if it grows the way `dev.sh` did,
splitting later is cheap.

### 3. Targets and mechanism

| Target | Path(s) | Mechanism | Privilege |
|---|---|---|---|
| npm cache | `~/.npm` | `mole_delete` | none |
| yarn cache | `~/.cache/yarn` | `mole_delete` | none |
| pnpm store | `~/.local/share/pnpm` | `mole_delete` | none |
| pip cache | `~/.cache/pip` | `mole_delete` | none |
| systemd journal | persistent journal | `journalctl --vacuum-time=<N>` (not a raw path delete) | none for user journal; falls back to informational skip if only the system journal is writable-only by root |
| Browser cache (Chrome/Chromium/Firefox) | `~/.cache/google-chrome`, `~/.cache/chromium`, `~/.cache/mozilla/firefox/*/cache2` (existence-checked, not assumed) | `mole_delete` | none |
| apt archives | `/var/cache/apt/archives` | `apt-get clean` (preview via `apt-get clean -s` / equivalent simulated listing) via CLI, **not** `mole_delete` | yes — routed through the existing `SYSTEM_CLEAN` gate |
| Docker reclaimable data | dangling images, build cache, stopped containers | `docker system prune` (dry-run preview via `docker system df` / `--dry-run` where supported), **not** raw `/var/lib/docker` deletion | depends on rootless vs rootful Docker setup on the user's machine; Mole never touches the daemon's files directly |

All file-level targets go through the same `mole_delete` /
`should_protect_path` funnel every Darwin section uses — no second delete
path is introduced. `apt` and `docker` are delegated entirely to their own
CLIs, mirroring the existing `lib/clean/brew.sh` pattern (preview first,
package manager decides what's safe, Mole never touches the underlying
files).

### 4. Section wiring

New Linux targets are appended to the existing pipeline, not gated behind a
new flag:

- Dev/package-manager caches (npm/yarn/pnpm/pip), journal vacuum, and
  browser cache join the existing numbered sections that already exist for
  equivalent purposes on macOS (e.g. "Developer tools", "Browsers") when
  those sections run on Linux, rather than inventing parallel section
  numbers.
- `apt-get clean` joins the existing "System" section
  (`SYSTEM_CLEAN == true`), the same gate Homebrew's system cleanup already
  uses — no new sudo gate is introduced.
- Docker joins "Developer tools" (Virtualization is Darwin-only
  VM/container-app cleanup today; Docker's own CLI-delegated cleanup fits
  better next to other dev-tool cache cleanup than as a new numbered
  section).

Every target still runs through the same dry-run ledger, whitelist check,
and summary counters as macOS sections — no special-casing in the
section-runner loop itself.

### 5. Testing

- New Bats tests for `lib/clean/linux.sh`, following the existing
  `tests/clean_*.bats` naming and `MOLE_TEST_NO_AUTH=1` convention.
- New Linux CI lane addition: extend the `go-test-linux` job added in Phase 1
  (`.github/workflows/test.yml`) — or add a sibling `bats-test-linux` job —
  to run the new Linux-specific Bats file(s) on `ubuntu-latest`. Darwin-only
  Bats files stay on the existing `macos-latest`/`compatibility` runners
  untouched.
- Manual verification on the user's real WSL install, following the same
  practice as Phase 1 Task 10: run the real (non-dry-run, non-test-mode)
  cleanup, and report an actual measured reclaim number per target that is
  present on that machine, per AGENTS.md's "measured number and a stated
  non-target list" requirement.

### 6. Non-targets within scope areas (stated per AGENTS.md)

- `~/.cache` is **not** cleaned generically by age/heuristic — only the
  specific, named sub-paths above (npm/yarn/pnpm/pip/browser). A generic
  `~/.cache` sweep would risk deleting live application state that happens
  to live under XDG cache by convention but isn't safely rebuildable
  (example: some Electron apps store more than pure cache there).
- Docker volumes and named images still in use are never targeted — only
  what `docker system prune`'s own dangling/unused detection identifies.
- `/var/lib/docker` and `~/.local/share/docker` are never read or deleted
  directly by Mole; only the `docker` CLI touches them.

## Testing/Verification Commands

```bash
MOLE_TEST_NO_AUTH=1 bats tests/clean_linux.bats
MOLE_TEST_NO_AUTH=1 ./mole clean --dry-run
find bin lib -name '*.sh' -print0 | xargs -0 -n1 bash -n
./scripts/check.sh --format
```

Darwin must remain unaffected: `bash -n mole` and the existing macOS Bats
suite continue to pass with no changes required.
