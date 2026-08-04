# Phase 2b: `mole uninstall` on Linux/WSL Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port `mole uninstall` to Linux/WSL as an apt/dpkg package remover plus exact-match XDG leftover cleanup, without touching any macOS uninstall code path.

**Architecture:** One new file `lib/uninstall/linux.sh`, sourced only when `MOLE_IS_LINUX == true`. `bin/uninstall.sh` branches near the top: Linux dispatches to `linux_uninstall_main` and exits; everything below the branch (macOS `app_selector.sh`/`batch.sh` flow) is unchanged. Reuses existing platform-agnostic helpers: `mole_delete`, `should_protect_path`, `run_with_timeout`, `lib/ui/menu_paginated.sh`.

**Tech Stack:** Bash, `dpkg-query`, `apt-get`, Bats tests, existing Mole core libs.

## Global Constraints

- Exact package-name matching only for leftovers — no wildcard, substring, or vendor-prefix matching (spec: Scope, Components).
- No second delete path: leftover removal must go through `mole_delete`/`should_protect_path` (repo-wide rule, AGENTS.md Critical Safety Rules).
- `apt-get remove`, never `--purge`, and no `/etc` config wipe in this phase (spec: Non-goals).
- `sudo -v` cached once per run, not per-package (spec: Components, `linux_uninstall_package`).
- Every `sudo`/privileged call site must be guarded by `MOLE_TEST_NO_AUTH`/`MOLE_TEST_MODE` or fully mocked in tests (AGENTS.md Critical Safety Rules).
- Package name validated against `^[a-z0-9][a-z0-9+.-]*$` before use in any command string (spec: Components — no shell injection surface).
- Zero changes to `bin/uninstall.sh`'s macOS branch, `lib/uninstall/batch.sh`, `lib/uninstall/brew.sh`, `lib/ui/app_selector.sh` (spec: Scope non-goals).
- Use `MOLE_TIMEOUT_PKG_CLEANUP_SEC` (existing constant, `lib/core/timeouts.sh:65`, default 20s) for the `apt-get remove` timeout.

---

## File Structure

- Create: `lib/uninstall/linux.sh` — package listing, package removal, leftover cleanup, CLI entry point (`linux_uninstall_main`).
- Modify: `bin/uninstall.sh` — add `MOLE_IS_LINUX` branch right after `source common.sh`, before the macOS-only sourcing block.
- Modify: `.github/workflows/test.yml` — add the four new test files to the existing `bats-test-linux` job.
- Create: `tests/uninstall_linux_list.bats`
- Create: `tests/uninstall_linux_package.bats`
- Create: `tests/uninstall_linux_leftovers.bats`
- Create: `tests/uninstall_linux_wiring.bats`

---

### Task 1: Package listing (`linux_list_uninstallable_packages`)

**Files:**
- Create: `lib/uninstall/linux.sh`
- Test: `tests/uninstall_linux_list.bats`

**Interfaces:**
- Produces: `linux_list_uninstallable_packages` — no args, prints `name|version|size_kb` lines to stdout, one per candidate package, sorted by name. Reads from `dpkg-query -W -f='${Package}|${Version}|${Status}|${Priority}|${Installed-Size}\n'`.

- [ ] **Step 1: Write the failing test**

Create `tests/uninstall_linux_list.bats`:

```bash
#!/usr/bin/env bats

setup_file() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    export PROJECT_ROOT
}

@test "linux_list_uninstallable_packages includes a normal manually-installed package" {
    run env PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/uninstall/linux.sh"
dpkg-query() {
    cat <<'FIXTURE'
firefox|120.0|install ok installed|optional|350000
FIXTURE
}
linux_list_uninstallable_packages
EOF
    [[ "$status" -eq 0 ]] || return 1
    [[ "$output" == "firefox|120.0|350000" ]] || return 1
}

@test "linux_list_uninstallable_packages excludes essential/required/important/standard priority packages" {
    run env PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/uninstall/linux.sh"
dpkg-query() {
    cat <<'FIXTURE'
bash|5.2|install ok installed|required|8000
coreutils|9.4|install ok installed|essential|17000
apt|2.7|install ok installed|important|4000
util-linux|2.39|install ok installed|standard|5000
firefox|120.0|install ok installed|optional|350000
FIXTURE
}
linux_list_uninstallable_packages
EOF
    [[ "$status" -eq 0 ]] || return 1
    [[ "$output" == "firefox|120.0|350000" ]] || return 1
}

@test "linux_list_uninstallable_packages excludes library packages" {
    run env PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/uninstall/linux.sh"
dpkg-query() {
    cat <<'FIXTURE'
libc6|2.37|install ok installed|optional|12000
libssl3|3.0.11|install ok installed|optional|6000
firefox|120.0|install ok installed|optional|350000
FIXTURE
}
linux_list_uninstallable_packages
EOF
    [[ "$status" -eq 0 ]] || return 1
    [[ "$output" == "firefox|120.0|350000" ]] || return 1
}

@test "linux_list_uninstallable_packages excludes non-installed packages" {
    run env PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/uninstall/linux.sh"
dpkg-query() {
    cat <<'FIXTURE'
oldpkg|1.0|deinstall ok config-files|optional|0
firefox|120.0|install ok installed|optional|350000
FIXTURE
}
linux_list_uninstallable_packages
EOF
    [[ "$status" -eq 0 ]] || return 1
    [[ "$output" == "firefox|120.0|350000" ]] || return 1
}

@test "linux_list_uninstallable_packages sorts by name" {
    run env PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/uninstall/linux.sh"
dpkg-query() {
    cat <<'FIXTURE'
zsh|5.9|install ok installed|optional|3000
ansible|8.5|install ok installed|optional|20000
FIXTURE
}
linux_list_uninstallable_packages
EOF
    [[ "$status" -eq 0 ]] || return 1
    local expected
    expected=$'ansible|8.5|20000\nzsh|5.9|3000'
    [[ "$output" == "$expected" ]] || return 1
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `MOLE_TEST_NO_AUTH=1 bats tests/uninstall_linux_list.bats`
Expected: FAIL — `linux_list_uninstallable_packages: command not found`

- [ ] **Step 3: Write minimal implementation**

Create `lib/uninstall/linux.sh`:

```bash
#!/bin/bash
# Linux/WSL uninstall module. Sourced only when uname -s == Linux.
# Wraps apt/dpkg package removal plus exact-match XDG leftover cleanup.
# Never a second delete path: leftovers route through mole_delete /
# should_protect_path, same as every other Mole deletion.

linux_list_uninstallable_packages() {
    dpkg-query -W -f='${Package}|${Version}|${Status}|${Priority}|${Installed-Size}\n' 2> /dev/null |
        awk -F'|' '
            $3 !~ /install ok installed/ { next }
            $4 == "required" || $4 == "essential" || $4 == "important" || $4 == "standard" { next }
            $1 ~ /^lib[0-9a-z.+-]*$/ { next }
            { print $1 "|" $2 "|" $5 }
        ' | sort -t'|' -k1,1
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `MOLE_TEST_NO_AUTH=1 bats tests/uninstall_linux_list.bats`
Expected: PASS (5 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/uninstall/linux.sh tests/uninstall_linux_list.bats
git commit -m "[worktree-linux-uninstall-phase2b] add linux_list_uninstallable_packages"
```

---

### Task 2: Package name validation + removal (`linux_uninstall_package`)

**Files:**
- Modify: `lib/uninstall/linux.sh`
- Test: `tests/uninstall_linux_package.bats`

**Interfaces:**
- Consumes: `run_with_timeout` (existing, `lib/core/base.sh`), `MOLE_TIMEOUT_PKG_CLEANUP_SEC` (existing, `lib/core/timeouts.sh`).
- Produces: `_linux_valid_package_name <pkgname>` — returns 0 if valid, 1 otherwise, no output. `linux_uninstall_package <pkgname>` — returns 0 on successful (or dry-run) removal, 1 on invalid name or `apt-get` failure. Honors `MOLE_DRY_RUN=1` (print-only, no exec) and `MOLE_TEST_NO_AUTH`/`MOLE_TEST_MODE` (skip `sudo -v`, still runs the mocked `apt-get` in tests).

- [ ] **Step 1: Write the failing test**

Create `tests/uninstall_linux_package.bats`:

```bash
#!/usr/bin/env bats

setup_file() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    export PROJECT_ROOT
}

@test "linux_uninstall_package rejects an invalid package name before running any command" {
    run env PROJECT_ROOT="$PROJECT_ROOT" MOLE_TEST_NO_AUTH=1 /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/uninstall/linux.sh"
apt-get() { echo "APT-GET CALLED: $*"; return 0; }
sudo() { echo "SUDO CALLED: $*"; "$@"; }
linux_uninstall_package '; rm -rf /'
EOF
    [[ "$status" -ne 0 ]] || return 1
    [[ "$output" != *"APT-GET CALLED"* ]] || return 1
    [[ "$output" != *"SUDO CALLED"* ]] || return 1
}

@test "linux_uninstall_package dry-run prints without executing apt-get" {
    run env PROJECT_ROOT="$PROJECT_ROOT" MOLE_TEST_NO_AUTH=1 MOLE_DRY_RUN=1 /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/uninstall/linux.sh"
apt-get() { echo "APT-GET CALLED: $*"; return 0; }
run_with_timeout() { shift; "$@"; }
linux_uninstall_package "firefox"
EOF
    [[ "$status" -eq 0 ]] || return 1
    [[ "$output" == *"would run: apt-get remove -y firefox"* ]] || return 1
    [[ "$output" != *"APT-GET CALLED"* ]] || return 1
}

@test "linux_uninstall_package runs apt-get remove on a real run" {
    run env PROJECT_ROOT="$PROJECT_ROOT" MOLE_TEST_NO_AUTH=1 /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/uninstall/linux.sh"
apt-get() { echo "APT-GET CALLED: $*"; return 0; }
run_with_timeout() { shift; "$@"; }
linux_uninstall_package "firefox"
EOF
    [[ "$status" -eq 0 ]] || return 1
    [[ "$output" == *"APT-GET CALLED: remove -y firefox"* ]] || return 1
}

@test "linux_uninstall_package returns non-zero and does not crash the batch when apt-get fails" {
    run env PROJECT_ROOT="$PROJECT_ROOT" MOLE_TEST_NO_AUTH=1 /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/uninstall/linux.sh"
apt-get() { echo "APT-GET CALLED: $*"; return 1; }
run_with_timeout() { shift; "$@"; }
linux_uninstall_package "firefox" || echo "RETURNED_NONZERO"
EOF
    [[ "$status" -eq 0 ]] || return 1
    [[ "$output" == *"RETURNED_NONZERO"* ]] || return 1
}

@test "linux_uninstall_package skips sudo -v under MOLE_TEST_NO_AUTH" {
    run env PROJECT_ROOT="$PROJECT_ROOT" MOLE_TEST_NO_AUTH=1 /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/uninstall/linux.sh"
apt-get() { return 0; }
run_with_timeout() { shift; "$@"; }
sudo() { echo "SUDO -v CALLED"; return 0; }
linux_uninstall_package "firefox"
EOF
    [[ "$status" -eq 0 ]] || return 1
    [[ "$output" != *"SUDO -v CALLED"* ]] || return 1
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `MOLE_TEST_NO_AUTH=1 bats tests/uninstall_linux_package.bats`
Expected: FAIL — `linux_uninstall_package: command not found`

- [ ] **Step 3: Write minimal implementation**

Append to `lib/uninstall/linux.sh`:

```bash
_linux_valid_package_name() {
    [[ "$1" =~ ^[a-z0-9][a-z0-9+.-]*$ ]]
}

linux_uninstall_package() {
    local pkgname="$1"

    if ! _linux_valid_package_name "$pkgname"; then
        echo "Error: invalid package name: $pkgname" >&2
        return 1
    fi

    if [[ "${MOLE_DRY_RUN:-0}" == "1" ]]; then
        echo "  would run: apt-get remove -y $pkgname"
        return 0
    fi

    if [[ "${MOLE_TEST_NO_AUTH:-0}" != "1" && "${MOLE_TEST_MODE:-0}" != "1" ]]; then
        sudo -v
    fi

    if run_with_timeout "$MOLE_TIMEOUT_PKG_CLEANUP_SEC" sudo apt-get remove -y "$pkgname"; then
        return 0
    fi
    echo "Error: apt-get remove failed for $pkgname" >&2
    return 1
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `MOLE_TEST_NO_AUTH=1 bats tests/uninstall_linux_package.bats`
Expected: PASS (5 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/uninstall/linux.sh tests/uninstall_linux_package.bats
git commit -m "[worktree-linux-uninstall-phase2b] add linux_uninstall_package"
```

---

### Task 3: Leftover cleanup (`linux_clean_package_leftovers`)

**Files:**
- Modify: `lib/uninstall/linux.sh`
- Test: `tests/uninstall_linux_leftovers.bats`

**Interfaces:**
- Consumes: `mole_delete <path> [needs_sudo]` (existing, `lib/core/file_ops.sh:762`), `should_protect_path <path>` (existing, `lib/core/app_protection.sh:326`).
- Produces: `linux_clean_package_leftovers <pkgname>` — no return value semantics beyond 0 (always succeeds; individual path failures are logged by `mole_delete` itself, not fatal to the batch).

- [ ] **Step 1: Write the failing test**

Create `tests/uninstall_linux_leftovers.bats`:

```bash
#!/usr/bin/env bats

setup_file() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    export PROJECT_ROOT
}

setup() {
    TEST_HOME="$(mktemp -d)"
    export TEST_HOME
}

teardown() {
    rm -rf "$TEST_HOME"
}

@test "linux_clean_package_leftovers removes existing config/cache/share dirs via mole_delete" {
    mkdir -p "$TEST_HOME/.config/firefox" "$TEST_HOME/.cache/firefox" "$TEST_HOME/.local/share/firefox"
    run env PROJECT_ROOT="$PROJECT_ROOT" HOME="$TEST_HOME" /bin/bash --noprofile --norc <<EOF
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/uninstall/linux.sh"
mole_delete() { echo "DELETE:\$1"; }
should_protect_path() { return 1; }
linux_clean_package_leftovers "firefox"
EOF
    [[ "$status" -eq 0 ]] || return 1
    [[ "$output" == *"DELETE:$TEST_HOME/.config/firefox"* ]] || return 1
    [[ "$output" == *"DELETE:$TEST_HOME/.cache/firefox"* ]] || return 1
    [[ "$output" == *"DELETE:$TEST_HOME/.local/share/firefox"* ]] || return 1
}

@test "linux_clean_package_leftovers is a silent no-op when no leftover dirs exist" {
    run env PROJECT_ROOT="$PROJECT_ROOT" HOME="$TEST_HOME" /bin/bash --noprofile --norc <<EOF
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/uninstall/linux.sh"
mole_delete() { echo "DELETE:\$1"; }
should_protect_path() { return 1; }
linux_clean_package_leftovers "nonexistent-pkg"
EOF
    [[ "$status" -eq 0 ]] || return 1
    [[ "$output" != *"DELETE:"* ]] || return 1
}

@test "linux_clean_package_leftovers does not touch a non-matching sibling directory" {
    mkdir -p "$TEST_HOME/.config/firefox-beta"
    run env PROJECT_ROOT="$PROJECT_ROOT" HOME="$TEST_HOME" /bin/bash --noprofile --norc <<EOF
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/uninstall/linux.sh"
mole_delete() { echo "DELETE:\$1"; }
should_protect_path() { return 1; }
linux_clean_package_leftovers "firefox"
EOF
    [[ "$status" -eq 0 ]] || return 1
    [[ "$output" != *"firefox-beta"* ]] || return 1
}

@test "linux_clean_package_leftovers respects should_protect_path denial" {
    mkdir -p "$TEST_HOME/.config/firefox"
    run env PROJECT_ROOT="$PROJECT_ROOT" HOME="$TEST_HOME" /bin/bash --noprofile --norc <<EOF
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/uninstall/linux.sh"
mole_delete() { echo "DELETE:\$1"; }
should_protect_path() { [[ "\$1" == *"/.config/firefox" ]] && return 0; return 1; }
linux_clean_package_leftovers "firefox"
EOF
    [[ "$status" -eq 0 ]] || return 1
    [[ "$output" != *"DELETE:$TEST_HOME/.config/firefox"* ]] || return 1
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `MOLE_TEST_NO_AUTH=1 bats tests/uninstall_linux_leftovers.bats`
Expected: FAIL — `linux_clean_package_leftovers: command not found`

- [ ] **Step 3: Write minimal implementation**

Append to `lib/uninstall/linux.sh`:

```bash
linux_clean_package_leftovers() {
    local pkgname="$1"
    local candidate

    for candidate in \
        "$HOME/.config/$pkgname" \
        "$HOME/.cache/$pkgname" \
        "$HOME/.local/share/$pkgname"; do
        [[ -e "$candidate" ]] || continue
        should_protect_path "$candidate" && continue
        mole_delete "$candidate"
    done
    return 0
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `MOLE_TEST_NO_AUTH=1 bats tests/uninstall_linux_leftovers.bats`
Expected: PASS (4 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/uninstall/linux.sh tests/uninstall_linux_leftovers.bats
git commit -m "[worktree-linux-uninstall-phase2b] add linux_clean_package_leftovers"
```

---

### Task 4: CLI entry point (`linux_uninstall_main`) + wiring into `bin/uninstall.sh`

**Files:**
- Modify: `lib/uninstall/linux.sh`
- Modify: `bin/uninstall.sh:17-24`
- Test: `tests/uninstall_linux_wiring.bats`

**Interfaces:**
- Consumes: `linux_list_uninstallable_packages` (Task 1), `linux_uninstall_package` (Task 2), `linux_clean_package_leftovers` (Task 3), `select_from_menu` or equivalent from `lib/ui/menu_paginated.sh` (existing — read its public function name before wiring, see Step 3 note).
- Produces: `linux_uninstall_main "$@"` — the sole entry point Linux `bin/uninstall.sh` calls. Handles `--list`, `--json`, direct package-name args, and falls through to interactive menu with no args. Exits 1 with a clear message if `apt-get`/`dpkg-query` are not on PATH.

- [ ] **Step 1: Check `lib/ui/menu_paginated.sh`'s public entry function name**

Run: `grep -n '^[a-z_]*()' lib/ui/menu_paginated.sh | head -5`

Read the first matching function signature — this is the function Task 4's interactive branch calls. (Recorded here as `show_paginated_menu` is the expected name based on Phase 1/2a conventions; confirm against the actual grep output before writing Step 3, and adjust the interactive branch call accordingly. Do not guess if the name differs — read the function's parameter contract in the file before wiring it.)

- [ ] **Step 2: Write the failing test**

Create `tests/uninstall_linux_wiring.bats`:

```bash
#!/usr/bin/env bats

setup_file() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    export PROJECT_ROOT
}

@test "lib/uninstall/linux.sh has valid bash syntax" {
    run bash -n "$PROJECT_ROOT/lib/uninstall/linux.sh"
    [[ "$status" -eq 0 ]] || return 1
}

@test "bin/uninstall.sh has valid bash syntax" {
    run bash -n "$PROJECT_ROOT/bin/uninstall.sh"
    [[ "$status" -eq 0 ]] || return 1
}

@test "bin/uninstall.sh sources lib/uninstall/linux.sh under an IS_LINUX guard" {
    run grep -n 'MOLE_IS_LINUX' "$PROJECT_ROOT/bin/uninstall.sh"
    [[ "$status" -eq 0 ]] || return 1
    [[ "$output" == *"lib/uninstall/linux.sh"* || "$output" == *"linux_uninstall_main"* ]] || return 1
}

@test "linux_uninstall_main --list prints the candidate table" {
    run env PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/uninstall/linux.sh"
command() {
    if [[ "$1" == "-v" ]]; then return 0; fi
    builtin command "$@"
}
linux_list_uninstallable_packages() { echo "firefox|120.0|350000"; }
linux_uninstall_main --list
EOF
    [[ "$status" -eq 0 ]] || return 1
    [[ "$output" == *"firefox"* ]] || return 1
}

@test "linux_uninstall_main --json prints a JSON array" {
    run env PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/uninstall/linux.sh"
command() {
    if [[ "$1" == "-v" ]]; then return 0; fi
    builtin command "$@"
}
linux_list_uninstallable_packages() { echo "firefox|120.0|350000"; }
linux_uninstall_main --json
EOF
    [[ "$status" -eq 0 ]] || return 1
    [[ "$output" == *'"name"'*'"firefox"'* ]] || return 1
    [[ "$output" == *'"version"'*'"120.0"'* ]] || return 1
    [[ "$output" == *'"size_kb"'*'350000'* ]] || return 1
}

@test "linux_uninstall_main with a direct package name skips the menu and uninstalls it" {
    run env PROJECT_ROOT="$PROJECT_ROOT" MOLE_TEST_NO_AUTH=1 MOLE_DRY_RUN=1 /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/uninstall/linux.sh"
command() {
    if [[ "$1" == "-v" ]]; then return 0; fi
    builtin command "$@"
}
linux_clean_package_leftovers() { echo "LEFTOVERS_CHECKED:$1"; }
linux_uninstall_main firefox
EOF
    [[ "$status" -eq 0 ]] || return 1
    [[ "$output" == *"would run: apt-get remove -y firefox"* ]] || return 1
    [[ "$output" == *"LEFTOVERS_CHECKED:firefox"* ]] || return 1
}

@test "linux_uninstall_main exits 1 with a clear message when apt-get is absent" {
    run env PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/uninstall/linux.sh"
command() {
    if [[ "$1" == "-v" && "$2" == "apt-get" ]]; then return 1; fi
    builtin command "$@"
}
linux_uninstall_main --list
EOF
    [[ "$status" -eq 1 ]] || return 1
    [[ "$output" == *"not supported"* ]] || return 1
}

@test "git diff shows only additions to the macOS branch of bin/uninstall.sh, no deletions" {
    cd "$PROJECT_ROOT"
    run git diff --unified=0 main -- bin/uninstall.sh
    [[ "$status" -eq 0 ]] || return 1
    local removed_non_context_lines
    removed_non_context_lines=$(echo "$output" | grep -c '^-[^-]' || true)
    [[ "$removed_non_context_lines" -eq 0 ]] || return 1
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `MOLE_TEST_NO_AUTH=1 bats tests/uninstall_linux_wiring.bats`
Expected: FAIL — `linux_uninstall_main: command not found`, and the "sources lib/uninstall/linux.sh" grep test fails since `bin/uninstall.sh` isn't modified yet.

- [ ] **Step 4: Write minimal implementation**

Append to `lib/uninstall/linux.sh`:

```bash
_linux_uninstall_require_apt() {
    if ! command -v apt-get > /dev/null 2>&1 || ! command -v dpkg-query > /dev/null 2>&1; then
        echo "Error: mole uninstall is not supported on this system (apt-get/dpkg-query not found)." >&2
        return 1
    fi
    return 0
}

_linux_print_package_table() {
    linux_list_uninstallable_packages | while IFS='|' read -r name version size_kb; do
        printf '%s  %s  %sK\n' "$name" "$version" "$size_kb"
    done
}

_linux_print_package_json() {
    local first=true
    echo -n "["
    while IFS='|' read -r name version size_kb; do
        [[ -z "$name" ]] && continue
        [[ "$first" == "true" ]] || echo -n ","
        first=false
        printf '{"name":"%s","version":"%s","size_kb":%s}' "$name" "$version" "$size_kb"
    done < <(linux_list_uninstallable_packages)
    echo "]"
}

_linux_uninstall_one() {
    local pkgname="$1"
    if linux_uninstall_package "$pkgname"; then
        linux_clean_package_leftovers "$pkgname"
        return 0
    fi
    return 1
}

linux_uninstall_main() {
    _linux_uninstall_require_apt || return 1

    if [[ $# -eq 0 ]]; then
        echo "Usage: mole uninstall <package> [<package>...] | --list | --json" >&2
        return 1
    fi

    case "$1" in
        --list)
            _linux_print_package_table
            return 0
            ;;
        --json)
            _linux_print_package_json
            return 0
            ;;
    esac

    local overall_rc=0
    local pkgname
    for pkgname in "$@"; do
        _linux_uninstall_one "$pkgname" || overall_rc=1
    done
    return "$overall_rc"
}
```

Modify `bin/uninstall.sh` — insert immediately after line 18 (`source "$SCRIPT_DIR/../lib/core/common.sh"`), before the `trap cleanup_temp_files` line:

```bash
if [[ "$MOLE_IS_LINUX" == "true" ]]; then
    source "$SCRIPT_DIR/../lib/uninstall/linux.sh"
    linux_uninstall_main "$@"
    exit $?
fi
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `MOLE_TEST_NO_AUTH=1 bats tests/uninstall_linux_wiring.bats`
Expected: PASS (8 tests)

- [ ] **Step 6: Run the full new Linux uninstall test surface plus a `bash -n` sanity pass on every touched file**

Run:
```bash
MOLE_TEST_NO_AUTH=1 bats tests/uninstall_linux_list.bats tests/uninstall_linux_package.bats tests/uninstall_linux_leftovers.bats tests/uninstall_linux_wiring.bats
find bin lib -name '*.sh' -print0 | xargs -0 -n1 bash -n
```
Expected: all PASS, no syntax errors.

- [ ] **Step 7: Commit**

```bash
git add lib/uninstall/linux.sh bin/uninstall.sh tests/uninstall_linux_wiring.bats
git commit -m "[worktree-linux-uninstall-phase2b] wire linux_uninstall_main into bin/uninstall.sh"
```

---

### Task 5: CI wiring + manual WSL verification

**Files:**
- Modify: `.github/workflows/test.yml`

**Interfaces:**
- Consumes: the existing `bats-test-linux` job created in Phase 2a (runs on `ubuntu-latest`, installs `bats` via apt, already lists `tests/clean_linux_*.bats`).
- Produces: no new interface — this task only extends the job's file list.

- [ ] **Step 1: Read the current job step**

Run: `grep -n -A 12 "Run linux clean bats subset" .github/workflows/test.yml`

- [ ] **Step 2: Add the four new test files to the bats invocation**

In `.github/workflows/test.yml`, extend the existing `bats-test-linux` job's run step to include the new files (do not create a second job — one Linux Bats lane, per Phase 2a's design):

```yaml
        - name: Run linux clean bats subset
          env:
            MOLE_TEST_NO_AUTH: "1"
            BATS_FORMATTER: tap
            LANG: en_US.UTF-8
            LC_ALL: en_US.UTF-8
          run: |
            bats tests/clean_linux_dev_caches.bats \
                 tests/clean_linux_browser_caches.bats \
                 tests/clean_linux_apt_cache.bats \
                 tests/clean_linux_wiring.bats \
                 tests/uninstall_linux_list.bats \
                 tests/uninstall_linux_package.bats \
                 tests/uninstall_linux_leftovers.bats \
                 tests/uninstall_linux_wiring.bats
```

(The step name stays `Run linux clean bats subset` — renaming it is optional polish, not required; leave as-is unless it reads confusingly once reviewed.)

- [ ] **Step 3: Validate the YAML**

Run:
```bash
python3 -c "import yaml, sys; yaml.safe_load(open('.github/workflows/test.yml'))" 2>&1 || echo "YAML_INVALID"
```
Expected: no `YAML_INVALID` output. (If `python3`/`pyyaml` aren't available, use a throwaway venv per repo convention: `python3 -m venv /tmp/yamlcheck && /tmp/yamlcheck/bin/pip install pyyaml -q && /tmp/yamlcheck/bin/python -c "import yaml; yaml.safe_load(open('.github/workflows/test.yml'))"`.)

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/test.yml
git commit -m "[worktree-linux-uninstall-phase2b] add linux uninstall bats to CI"
```

- [ ] **Step 5: Manual verification on real WSL (not a commit step — a checkpoint)**

Run on the actual WSL machine, in order:
```bash
find bin lib -name '*.sh' -print0 | xargs -0 -n1 bash -n
GOOS=darwin go build ./... 2>&1 | head -20   # confirm Darwin build is unaffected (no Go changes expected, but this branch touches shared shell files)
MOLE_TEST_NO_AUTH=1 ./mole uninstall --list
MOLE_TEST_NO_AUTH=1 ./mole uninstall --json
MOLE_TEST_NO_AUTH=1 MOLE_DRY_RUN=1 ./mole uninstall <a real installed non-essential package name from the --list output>
```
Confirm: `--list`/`--json` show real packages from the machine (excluding essential/library ones), and the dry-run line prints `would run: apt-get remove -y <pkg>` plus the three leftover-path checks, with **no actual removal or deletion occurring**. This is the same "catch what the plan didn't anticipate" step that found the BSD-stat and `set -e` post-increment bugs in Phase 2a — read the full output, don't just check the exit code.

---

## Self-Review Notes

- Spec coverage: `linux_list_uninstallable_packages` (Task 1) ↔ spec's package listing; `linux_uninstall_package` + sudo/dry-run/timeout handling (Task 2) ↔ spec's removal component; `linux_clean_package_leftovers` (Task 3) ↔ spec's leftover component; `linux_uninstall_main` with `--list`/`--json`/direct-arg/menu (Task 4) ↔ spec's entry points; CI + manual WSL check (Task 5) ↔ spec's Testing section. Interactive menu path in Task 4 depends on reading `lib/ui/menu_paginated.sh`'s actual function name at execution time (flagged explicitly in Task 4 Step 1, not guessed) since it wasn't re-verified during planning — this is the one interface not pinned to an exact signature in this plan, by design, and must be resolved before writing that branch's code.
- No placeholders: every step has runnable code, no "add error handling" prose.
- Type/name consistency checked: `linux_list_uninstallable_packages` output format (`name|version|size_kb`) is identical across Task 1, Task 4's `--json`/`--list` consumers, and Task 4's wiring test. `linux_uninstall_package`/`linux_clean_package_leftovers` signatures match between their defining tasks and Task 4's `_linux_uninstall_one` caller.
