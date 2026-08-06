# Linux Guard for `optimize` and `installer` — Design

Date: 2026-08-06
Status: Approved for planning

## Context

Phase 1 (2026-08-01) already decided `optimize` is "not currently planned
for any phase; likely remains macOS-only permanently" — its 21 registered
tasks (`lib/optimize/catalog.sh`) are Spotlight reindex, `launchctl` repair,
TimeMachine thinning, `PlistBuddy` preference fixes, `diskutil` verify —
none have a meaningful Linux equivalent.

`installer` was never addressed by any phase. Its scan targets
(`bin/installer.sh:31-44`) are `.dmg`/`.pkg`/`.mpkg`/`.xip` — macOS
installer package formats only. Linux has no equivalent "leftover
installer artifact" pattern to scan for.

Today, neither command has any Linux guard (confirmed: zero `MOLE_IS_LINUX`,
`uname`, or `darwin` references in `bin/optimize.sh`, `lib/optimize/*.sh`,
or `bin/installer.sh`). Running either on Linux/WSL currently falls through
into macOS-only tool calls (`mdutil`, `tmutil`, `launchctl`, `PlistBuddy`,
`diskutil`) with no coherent error — scattered "command not found" failures
instead of one clear message.

## Decision

Guard only. No Linux port of either command's functionality. This confirms
and formalizes the Phase 1 optimize decision, and extends the same decision
to installer for the same reason (no viable Linux equivalent for the task
set).

## Design

Add an early-exit guard to each entrypoint, following the exact pattern
`bin/uninstall.sh:20-24` already uses for its own Linux dispatch (though
here the Linux branch is "reject", not "dispatch to a Linux module"):

**`bin/optimize.sh`** — immediately after `source common.sh` (before
sourcing `sudo.sh`, `diagnostics.sh`, `maintenance.sh`, `catalog.sh`,
`tasks.sh`, `health_json.sh`, `whitelist.sh`):

```bash
if [[ "$MOLE_IS_LINUX" == "true" ]]; then
    echo "Error: mole optimize is not supported on Linux (macOS-specific maintenance: Spotlight, launchctl, TimeMachine)." >&2
    exit 1
fi
```

**`bin/installer.sh`** — immediately after `source common.sh` (before
sourcing `menu_paginated.sh` and before the scan-path/zip-tool setup):

```bash
if [[ "$MOLE_IS_LINUX" == "true" ]]; then
    echo "Error: mole installer is not supported on Linux (scans macOS-only installer formats: .dmg/.pkg/.mpkg/.xip)." >&2
    exit 1
fi
```

No new files, no new `lib/*/linux.sh` module — there is no Linux logic to
house. This is a 4-line reject block per entrypoint, placed before any
heavier sourcing so the exit is immediate and no macOS-only module load is
attempted on Linux.

`$MOLE_IS_LINUX` is already defined by `lib/core/base.sh:182` and available
transitively via `common.sh`, matching the exact variable `bin/uninstall.sh`
and `bin/clean.sh` already key off.

### Non-goals

- No change to `mole` router dispatch — both commands stay wired exactly as
  today; the guard lives inside the entrypoint script itself, matching the
  existing `uninstall`/`clean` convention.
- No change to `mole help` output or command listing — out of scope for
  this guard-only pass.
- No JSON-specific rejection shape. Neither command currently has a
  scripted/JSON consumer that would need a machine-readable reject payload.
- No macOS behavior change whatsoever — the guard is purely additive and
  only triggers when `MOLE_IS_LINUX == "true"`.

## Testing

New Bats file `tests/linux_unsupported_commands.bats` covering both
entrypoints:

- `mole optimize` under `MOLE_IS_LINUX=true` (mocked): exits 1, stderr
  contains "not supported on Linux".
- `mole installer` under `MOLE_IS_LINUX=true` (mocked): exits 1, stderr
  contains "not supported on Linux".
- Sanity check that neither guard fires when `MOLE_IS_LINUX=false` (i.e.
  macOS behavior is unaffected — the script proceeds past the guard).

Wire this file into the existing `bats-test-linux` CI job in
`.github/workflows/test.yml`, same pattern as Phase 2/2b/2c.

## Self-review

- No placeholders — exact code blocks, exact file paths, exact insertion
  points given.
- Consistent with confirmed repo fact: `MOLE_IS_LINUX` already exists and
  is the variable `uninstall`/`clean` already branch on.
- Scope is deliberately minimal per user decision (guard-only, no port) —
  matches Phase 1's own prior call on `optimize` and extends the same
  reasoning to `installer`.
