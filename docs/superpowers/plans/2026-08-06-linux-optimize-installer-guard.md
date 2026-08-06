# Linux Guard for `optimize` and `installer` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `mole optimize` and `mole installer` exit with a clear error on Linux instead of falling through into macOS-only tool calls (`mdutil`, `tmutil`, `launchctl`, `PlistBuddy`, `diskutil`, `.dmg`/`.pkg` scanning).

**Architecture:** A 4-line early-exit guard at the top of each entrypoint (`bin/optimize.sh`, `bin/installer.sh`), gated on the existing `MOLE_IS_LINUX` variable, placed before any heavier module sourcing. No new files, no Linux functional port — this is a reject-only guard, matching the pattern `bin/uninstall.sh:20-24` already uses for OS branching.

**Tech Stack:** Bash, Bats tests. No Go changes.

## Global Constraints

- No macOS behavior change whatsoever — the guard only fires when `MOLE_IS_LINUX == "true"` (spec: Non-goals).
- No change to `mole` router dispatch — guard lives inside each entrypoint script itself (spec: Non-goals).
- No change to `mole help` output or command listing (spec: Non-goals).
- No JSON-specific rejection shape — plain stderr message + exit 1 (spec: Non-goals).
- `MOLE_IS_LINUX` is `readonly`, computed from `uname -s` at `lib/core/base.sh:182`, and already available transitively via `common.sh` — do not redefine it.
- Guard must be placed before any macOS-only module is sourced, so the exit is immediate and no macOS-only module load is attempted on Linux (spec: Design).

---

## File Structure

- Modify: `bin/optimize.sh` — add guard after `source "$SCRIPT_DIR/lib/core/common.sh"` (line 13), before `source "$SCRIPT_DIR/lib/core/sudo.sh"` (line 17).
- Modify: `bin/installer.sh` — add guard after `source "$SCRIPT_DIR/../lib/core/common.sh"` (line 17), before `source "$SCRIPT_DIR/../lib/ui/menu_paginated.sh"` (line 18).
- Create: `tests/linux_unsupported_commands.bats` — covers both entrypoints.
- Modify: `.github/workflows/test.yml` — add the new test file to the `bats-test-linux` job's bats invocation (currently lines 79-86, per Phase 2c precedent).

No new `lib/*/linux.sh` module — there is no Linux logic to house, only a reject.

---

### Task 1: Guard `bin/optimize.sh` on Linux

**Files:**
- Modify: `bin/optimize.sh:13-14`
- Test: `tests/linux_unsupported_commands.bats` (new)

**Interfaces:**
- Consumes: `$MOLE_IS_LINUX` (readonly, from `lib/core/base.sh:182`, available after `source common.sh`).
- Produces: nothing new — script now exits 1 with a stderr message on Linux instead of proceeding.

- [ ] **Step 1: Write the failing test file with the optimize guard test**

Create `tests/linux_unsupported_commands.bats`:

```bash
#!/usr/bin/env bats

setup_file() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    export PROJECT_ROOT
}

@test "bin/optimize.sh has valid bash syntax" {
    run bash -n "$PROJECT_ROOT/bin/optimize.sh"
    [[ "$status" -eq 0 ]] || return 1
}

@test "bin/optimize.sh guards on MOLE_IS_LINUX before sourcing optimize modules" {
    run grep -n 'MOLE_IS_LINUX' "$PROJECT_ROOT/bin/optimize.sh"
    [[ "$status" -eq 0 ]] || return 1

    local guard_line source_line
    guard_line=$(grep -n 'MOLE_IS_LINUX' "$PROJECT_ROOT/bin/optimize.sh" | head -1 | cut -d: -f1)
    source_line=$(grep -n 'lib/optimize/catalog.sh' "$PROJECT_ROOT/bin/optimize.sh" | head -1 | cut -d: -f1)
    [[ "$guard_line" -lt "$source_line" ]] || return 1
}

@test "mole optimize exits 1 with a clear message on Linux" {
    if [[ "$(uname -s)" != "Linux" ]]; then
        skip "guard behavior only observable on a real Linux host"
    fi
    run "$PROJECT_ROOT/bin/optimize.sh"
    [[ "$status" -eq 1 ]] || return 1
    [[ "$output" == *"not supported on Linux"* ]] || return 1
}
```

- [ ] **Step 2: Run the tests to verify the wiring/behavior tests fail**

Run: `MOLE_TEST_NO_AUTH=1 bats tests/linux_unsupported_commands.bats`
Expected: syntax test PASSES (file is unmodified valid bash), wiring test FAILS (no `MOLE_IS_LINUX` in `bin/optimize.sh` yet), Linux-behavior test either FAILS (if running on Linux) or SKIPS (if running on macOS).

- [ ] **Step 3: Add the guard to `bin/optimize.sh`**

In `bin/optimize.sh`, replace:

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/core/common.sh"

# Clean temp files on exit.
trap cleanup_temp_files EXIT INT TERM
source "$SCRIPT_DIR/lib/core/sudo.sh"
```

with:

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/core/common.sh"

if [[ "$MOLE_IS_LINUX" == "true" ]]; then
    echo "Error: mole optimize is not supported on Linux (macOS-specific maintenance: Spotlight, launchctl, TimeMachine)." >&2
    exit 1
fi

# Clean temp files on exit.
trap cleanup_temp_files EXIT INT TERM
source "$SCRIPT_DIR/lib/core/sudo.sh"
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `MOLE_TEST_NO_AUTH=1 bats tests/linux_unsupported_commands.bats`
Expected: syntax and wiring tests PASS. Linux-behavior test PASSES if run on a Linux host, SKIPS on macOS.

- [ ] **Step 5: Verify macOS behavior is unaffected**

Run: `bash -n bin/optimize.sh && echo SYNTAX_OK`
Expected: `SYNTAX_OK` (confirms no syntax breakage on the shared code path).

Run: `git diff --unified=0 bin/optimize.sh | grep -c '^-[^-]'`
Expected: `0` (confirms the change is purely additive — no line removed from the macOS path).

- [ ] **Step 6: Commit**

```bash
git add bin/optimize.sh tests/linux_unsupported_commands.bats
git commit -m "[main] guard mole optimize against running on Linux

optimize's 21 registered tasks (Spotlight reindex, launchctl repair,
TimeMachine thinning, PlistBuddy preference fixes, diskutil verify)
have no Linux equivalent. Without a guard, running it on Linux fell
through into scattered macOS-only command-not-found failures instead
of one clear message. Confirms Phase 1's prior decision that optimize
remains macOS-only."
```

---

### Task 2: Guard `bin/installer.sh` on Linux

**Files:**
- Modify: `bin/installer.sh:17-18`
- Test: `tests/linux_unsupported_commands.bats` (extend)

**Interfaces:**
- Consumes: `$MOLE_IS_LINUX` (readonly, from `lib/core/base.sh:182`, available after `source common.sh`).
- Produces: nothing new — script now exits 1 with a stderr message on Linux instead of proceeding.

- [ ] **Step 1: Add the failing tests for the installer guard**

Append to `tests/linux_unsupported_commands.bats`:

```bash
@test "bin/installer.sh has valid bash syntax" {
    run bash -n "$PROJECT_ROOT/bin/installer.sh"
    [[ "$status" -eq 0 ]] || return 1
}

@test "bin/installer.sh guards on MOLE_IS_LINUX before sourcing menu_paginated" {
    run grep -n 'MOLE_IS_LINUX' "$PROJECT_ROOT/bin/installer.sh"
    [[ "$status" -eq 0 ]] || return 1

    local guard_line source_line
    guard_line=$(grep -n 'MOLE_IS_LINUX' "$PROJECT_ROOT/bin/installer.sh" | head -1 | cut -d: -f1)
    source_line=$(grep -n 'lib/ui/menu_paginated.sh' "$PROJECT_ROOT/bin/installer.sh" | head -1 | cut -d: -f1)
    [[ "$guard_line" -lt "$source_line" ]] || return 1
}

@test "mole installer exits 1 with a clear message on Linux" {
    if [[ "$(uname -s)" != "Linux" ]]; then
        skip "guard behavior only observable on a real Linux host"
    fi
    run "$PROJECT_ROOT/bin/installer.sh"
    [[ "$status" -eq 1 ]] || return 1
    [[ "$output" == *"not supported on Linux"* ]] || return 1
}
```

- [ ] **Step 2: Run the tests to verify the new ones fail**

Run: `MOLE_TEST_NO_AUTH=1 bats tests/linux_unsupported_commands.bats`
Expected: the two new syntax/wiring tests behave the same as Task 1 Step 2 (wiring test FAILS, syntax test PASSES, Linux-behavior test FAILS or SKIPS).

- [ ] **Step 3: Add the guard to `bin/installer.sh`**

In `bin/installer.sh`, replace:

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/core/common.sh"
source "$SCRIPT_DIR/../lib/ui/menu_paginated.sh"
```

with:

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/core/common.sh"

if [[ "$MOLE_IS_LINUX" == "true" ]]; then
    echo "Error: mole installer is not supported on Linux (scans macOS-only installer formats: .dmg/.pkg/.mpkg/.xip)." >&2
    exit 1
fi

source "$SCRIPT_DIR/../lib/ui/menu_paginated.sh"
```

- [ ] **Step 4: Run the full test file to verify everything passes**

Run: `MOLE_TEST_NO_AUTH=1 bats tests/linux_unsupported_commands.bats`
Expected: all 6 tests PASS (or 4 PASS + 2 SKIP if run on macOS).

- [ ] **Step 5: Verify macOS behavior is unaffected**

Run: `bash -n bin/installer.sh && echo SYNTAX_OK`
Expected: `SYNTAX_OK`

Run: `git diff --unified=0 bin/installer.sh | grep -c '^-[^-]'`
Expected: `0`

- [ ] **Step 6: Commit**

```bash
git add bin/installer.sh tests/linux_unsupported_commands.bats
git commit -m "[main] guard mole installer against running on Linux

installer scans for macOS-only installer package formats
(.dmg/.pkg/.mpkg/.xip) with no Linux equivalent. Without a guard,
running it on Linux would scan real user directories for files that
can never match, silently doing nothing useful. Reject with a clear
message instead."
```

---

### Task 3: Wire the new test file into Linux CI

**Files:**
- Modify: `.github/workflows/test.yml` (the `bats-test-linux` job's `Run linux clean bats subset` step, currently lines 79-86 plus the Phase 2c purge additions)

**Interfaces:**
- Consumes: `tests/linux_unsupported_commands.bats` (fully green as of Task 2).
- Produces: no new interface — CI wiring only.

- [ ] **Step 1: Confirm the full local test suite is green before touching CI**

Run: `MOLE_TEST_NO_AUTH=1 bats tests/linux_unsupported_commands.bats`
Expected: all tests PASS (or PASS+SKIP on macOS), 0 failures.

- [ ] **Step 2: Read the current CI step to get the exact block**

Run: `grep -n -A 15 "Run linux clean bats subset" .github/workflows/test.yml`

Confirm the current bats invocation list (it should already include the Phase 2c purge additions: `tests/purge.bats`, `tests/purge_config_paths.bats`, plus the clean/uninstall linux files from earlier phases).

- [ ] **Step 3: Add `tests/linux_unsupported_commands.bats` to the list**

Using the exact list confirmed in Step 2, append `tests/linux_unsupported_commands.bats \` as the last line of the `bats` invocation in the `Run linux clean bats subset` step of the `bats-test-linux` job.

- [ ] **Step 4: Validate the workflow YAML syntax**

Run:
```bash
python3 -m venv /tmp/yamlcheck && /tmp/yamlcheck/bin/pip install -q pyyaml && /tmp/yamlcheck/bin/python3 -c "import yaml; yaml.safe_load(open('.github/workflows/test.yml'))" && echo VALID
```
Expected: `VALID` printed, no exception.

- [ ] **Step 5: Run the full local verification sweep**

Run:
```bash
./scripts/check.sh --format
MOLE_TEST_NO_AUTH=1 bats tests/linux_unsupported_commands.bats
GOOS=darwin go build ./...
```
Expected: formatter reports no changes needed, all Bats tests PASS (or PASS+SKIP), Go build stays clean for the macOS target (no Go files touched in this plan — sanity check only).

- [ ] **Step 6: Commit**

```bash
git add .github/workflows/test.yml
git commit -m "[main] add linux unsupported-command guard tests to Linux CI job

tests/linux_unsupported_commands.bats now passes cleanly on Linux
after the optimize/installer guard tasks. Add it to the existing
bats-test-linux job's bats invocation, same pattern used for the
clean, uninstall, and purge Linux test files in prior phases."
```

---

## Self-Review Notes

- **Spec coverage:** Design's two guard blocks map 1:1 to Task 1 (`optimize`) and Task 2 (`installer`) with byte-identical code from the spec. Non-goals (no router change, no help-output change, no JSON shape, no macOS behavior change) are respected — no task touches `mole`, `mole help`, or adds a JSON branch. Testing section maps to all three tasks' test steps plus Task 3's CI wiring.
- **Type/interface consistency:** Both guards consume the same `$MOLE_IS_LINUX` readonly variable, no new functions or signatures introduced, so no naming drift risk.
- **No placeholders:** every step has literal before/after code or literal commands. The Linux-behavior tests `skip` explicitly on macOS rather than asserting unobservable behavior, consistent with how this repo's other Linux-only behavior tests only run meaningfully on the `ubuntu-latest` CI runner (confirmed: `bats-test-linux` job runs on `ubuntu-latest` in `.github/workflows/test.yml:64`).
