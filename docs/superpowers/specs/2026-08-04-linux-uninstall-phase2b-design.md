# Phase 2b: `mole uninstall` on Linux/WSL

Status: approved
Date: 2026-08-04

## Problem

`bin/uninstall.sh` and `lib/uninstall/batch.sh` are macOS-native: `.app` bundle
discovery, `mdls`, `osascript` login items, `launchctl`/LaunchAgents /
LaunchDaemons teardown, Homebrew cask handling, macOS epoch quirks. None of
this has a direct Linux equivalent. Linux apps are installed via apt/dpkg, not
drag-installed `.app` bundles.

## Scope

`mole uninstall` on Linux means: apt/dpkg package removal, plus cleanup of
exact-match XDG leftover dirs (`~/.config`, `~/.cache`, `~/.local/share`) that
`apt remove` (not `--purge`) leaves behind. This is the closest Linux
equivalent to the macOS "remove app + its leftovers" contract.

Non-goals (out of scope for this phase):
- snap, flatpak, AppImage, or manually-extracted `/opt` binaries
- `apt purge` / config-file wipe (system + dpkg-managed `/etc` config stays;
  only user-level XDG leftovers are cleaned)
- fuzzy, wildcard, or vendor-wide leftover matching — exact package name only
- touching any macOS code path in `bin/uninstall.sh`, `lib/uninstall/batch.sh`,
  `lib/uninstall/brew.sh`, or `lib/ui/app_selector.sh`
- login item / service teardown (no launchctl equivalent is in scope this
  phase; systemd user service teardown is a possible future phase, not this
  one)

## Architecture

New file: `lib/uninstall/linux.sh`, sourced only when `MOLE_IS_LINUX == true`
(existing flag from `lib/core/base.sh`, Phase 2a). Mirrors Phase 2a's shape:
one new file, no branching inside existing Darwin functions.

`bin/uninstall.sh` stays the router. Near the top, after sourcing
`lib/core/common.sh` (which defines `MOLE_IS_LINUX`), branch:

```bash
if [[ "$MOLE_IS_LINUX" == "true" ]]; then
    source "$SCRIPT_DIR/../lib/uninstall/linux.sh"
    linux_uninstall_main "$@"
    exit $?
fi
# ...existing macOS sourcing (app_selector.sh, batch.sh) and flow unchanged
```

This keeps the Linux path fully separate: it never loads
`lib/ui/app_selector.sh` or `lib/uninstall/batch.sh` (both `.app`-shaped), and
the macOS flow below the branch is untouched.

`lib/ui/menu_paginated.sh` is reused as-is for interactive selection — it is
already platform-agnostic (no macOS-only calls), confirmed by grep in Phase 2a
review.

## Components (`lib/uninstall/linux.sh`)

**`linux_list_uninstallable_packages`**
Lists candidate packages: `dpkg-query -W -f='${Package}|${Version}|${Status}|${Priority}\n'`
filtered to `Status` = installed and `Priority` not in
`required|important|standard` and package name not matching `^lib.*[0-9]*$`
(library packages). Output: `name|version|installed-size-kb` lines, sorted by
name. This is the source list for the interactive menu, `--list`, and
`--json`.

**`linux_uninstall_package <pkgname>`**
- Validates `pkgname` against dpkg's package name charset
  (`^[a-z0-9][a-z0-9+.-]*$`) before use in any command — no shell injection
  surface.
- `sudo -v` once at the start of the whole run (existing Mole pattern, cached
  credential; not per-package), guarded by `MOLE_TEST_NO_AUTH`/`MOLE_TEST_MODE`
  same as `clean_tool_cache` call sites.
- Preview: `MOLE_DRY_RUN=1` prints the `apt-get remove` command and target
  leftover paths, executes nothing.
- Real run: `run_with_timeout "$MOLE_TIMEOUT_PKG_CLEANUP_SEC" sudo apt-get remove -y "$pkgname"`.
- Non-zero exit from apt-get is surfaced to the user and stops that package's
  leftover cleanup (does not touch leftovers for a package that failed to
  uninstall).

**`linux_clean_package_leftovers <pkgname>`**
Exact-match only, three candidate paths:
`$HOME/.config/$pkgname`, `$HOME/.cache/$pkgname`, `$HOME/.local/share/$pkgname`.
For each: if it exists, run through the existing `should_protect_path` guard,
then `mole_delete` (same funnel every other Mole deletion uses — no second
delete path). No wildcard, no substring, no vendor-prefix matching. If a path
doesn't exist, skip silently (same no-op semantics as `safe_clean`).

**Selection / entry points (`linux_uninstall_main`)**
- `mole uninstall` (no args): interactive menu via `menu_paginated.sh` over
  `linux_list_uninstallable_packages` output, multi-select, confirm screen
  showing package + version + leftover paths that will be checked, then calls
  `linux_uninstall_package` + `linux_clean_package_leftovers` per selection.
- `mole uninstall <pkgname> [<pkgname>...]`: skips the menu, uninstalls the
  named packages directly (still goes through the same confirm-and-run path,
  respects `MOLE_DRY_RUN`).
- `mole uninstall --list`: prints the candidate table, no action.
- `mole uninstall --json`: same list, JSON array of `{name, version, size_kb}`.

## Error Handling

- Unknown/invalid package name argument: print error, exit 1, no dpkg/apt
  call made (name validated before any command construction).
- `apt-get remove` failure (package held, dependency issue, etc.): print
  apt-get's own error, skip leftover cleanup for that package, continue to
  the next selected package (batch doesn't abort on one failure), non-zero
  final exit code if any package failed.
- No `apt-get`/`dpkg` on PATH: `linux_uninstall_main` prints a clear
  "not supported on this system" message and exits 1 before touching
  anything else. (WSL/Debian/Ubuntu images always have both; this guards
  non-apt distros without pretending to support them.)

## Testing

New Bats files, mirroring Phase 2a's `tests/clean_linux_*.bats` naming:
- `tests/uninstall_linux_list.bats` — package listing/filtering logic
  (mocked `dpkg-query` output fixtures: essential pkg excluded, lib* excluded,
  normal pkg included).
- `tests/uninstall_linux_package.bats` — `linux_uninstall_package`: dry-run
  prints without executing, invalid package name rejected before any command,
  mocked `apt-get` failure path skips leftover cleanup, `MOLE_TEST_NO_AUTH`
  skips real sudo.
- `tests/uninstall_linux_leftovers.bats` — exact-match-only leftover cleanup:
  existing `~/.config/<pkg>` removed via `mole_delete`, non-matching sibling
  dirs untouched, `should_protect_path` denial respected, missing dir is a
  silent no-op.
- `tests/uninstall_linux_wiring.bats` — `bash -n` on the new file, `IS_LINUX`
  branch in `bin/uninstall.sh` present, macOS branch below it unchanged
  (`git diff main -- bin/uninstall.sh` shows only the added branch, no
  deletions in the macOS path).

CI: add these four files to the existing `bats-test-linux` job in
`.github/workflows/test.yml` (same job Phase 2a created), alongside the
`clean_linux_*.bats` files already there.

Run per repo convention:
`MOLE_TEST_NO_AUTH=1 bats tests/uninstall_linux_list.bats tests/uninstall_linux_package.bats tests/uninstall_linux_leftovers.bats tests/uninstall_linux_wiring.bats`
