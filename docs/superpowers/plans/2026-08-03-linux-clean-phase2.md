# Linux `mole clean` Phase 2a Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give `mole clean` real, measurable, safe cleanup targets on
Linux/WSL (dev/package-manager caches, systemd journal, browser cache, apt
archives, Docker review notice) without touching any existing Darwin code
path.

**Architecture:** One new module `lib/clean/linux.sh`, sourced by
`bin/clean.sh` only when `uname -s == Linux`. Four new entry-point
functions (`clean_linux_dev_caches`, `clean_linux_browser_caches`,
`clean_linux_apt_cache`, plus the Docker review helper folded into
`clean_linux_dev_caches`) are called from three existing numbered sections
in `bin/clean.sh` ("Developer tools", "Browsers", "System"), guarded at each
call site by a new `IS_LINUX` flag computed once alongside the existing
`IS_M_SERIES` flag. File-level targets go through the existing `safe_clean`
helper (which internally calls `mole_delete`/`should_protect_path`);
CLI-delegated targets (journalctl, apt) go through the existing
`clean_tool_cache` helper; Docker is review-only output with no deletion,
matching the existing macOS `clean_dev_docker`.

**Tech Stack:** Bash 3.2-compatible shell, Bats for tests, existing Mole
core libs (`lib/core/file_ops.sh`, `lib/core/app_protection.sh`,
`lib/core/timeouts.sh`).

## Global Constraints

- Darwin behavior must remain byte-for-byte unaffected: no existing
  `lib/clean/*.sh` file is modified except `bin/clean.sh`'s orchestration
  additions, and every addition there is behind an `IS_LINUX` guard.
- No new CLI flag, environment variable, or config key is introduced.
- Every file-level delete goes through `safe_clean` (never a second delete
  path, never a raw `rm`/`mole_delete` call bypassing it).
- Every CLI-delegated action goes through `clean_tool_cache` (never a raw
  unguarded `apt-get clean` / `journalctl --vacuum-time` call).
- Docker is review-only: no deletion, no `docker system prune` invocation,
  matching `lib/clean/dev.sh:429`'s `clean_dev_docker`.
- apt cleanup only runs inside the existing `SYSTEM_CLEAN == true` gate
  (same sudo gate Homebrew's system cleanup already uses) — no new sudo
  gate.
- Every new path target is existence-checked before being passed to
  `safe_clean`/`clean_tool_cache` — no assumed paths.
- `~/.cache` is never swept generically; only the named sub-paths in this
  plan are touched.
- Tests use `MOLE_TEST_NO_AUTH=1` and the same sourcing pattern as
  `tests/clean_dev_caches.bats` (source `lib/core/common.sh` then the target
  module directly inside a `bash --noprofile --norc` heredoc, stubbing
  `safe_clean`, `clean_tool_cache`, `note_activity`,
  `start_section_spinner`/`stop_section_spinner` as needed).
- Shell files must pass `bash -n` and `./scripts/check.sh --format`.

---

### Task 1: Create `lib/clean/linux.sh` with npm/yarn/pnpm/pip cache cleanup

**Files:**
- Create: `lib/clean/linux.sh`
- Test: `tests/clean_linux_dev_caches.bats`

**Interfaces:**
- Produces: `clean_linux_dev_caches()` — no args, no return value contract
  beyond "always returns 0"; calls `safe_clean` and `clean_tool_cache`
  internally. Later tasks append more logic to this same function (journal
  vacuum in Task 2, Docker notice in Task 3), so its name and no-arg
  signature must not change.

- [ ] **Step 1: Write the failing test**

Create `tests/clean_linux_dev_caches.bats`:

```bash
#!/usr/bin/env bats

setup_file() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    export PROJECT_ROOT

    ORIGINAL_HOME="${HOME:-}"
    export ORIGINAL_HOME

    HOME="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp-linux-dev-caches.XXXXXX")"
    export HOME
}

teardown_file() {
    if [[ "$HOME" == "${BATS_TEST_DIRNAME}/tmp-"* ]]; then
        rm -rf "$HOME"
    fi
    if [[ -n "${ORIGINAL_HOME:-}" ]]; then
        export HOME="$ORIGINAL_HOME"
    fi
}

@test "clean_linux_dev_caches cleans npm cache when present" {
    mkdir -p "$HOME/.npm"
    touch "$HOME/.npm/some-cache-file"

    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/linux.sh"
safe_clean() { echo "safe_clean:${*: -1}"; }
clean_tool_cache() { echo "clean_tool_cache:$1"; }
note_activity() { :; }
clean_linux_dev_caches
EOF
    [[ "$status" -eq 0 ]] || return 1
    [[ "$output" == *"safe_clean:npm cache"* ]] || return 1
}

@test "clean_linux_dev_caches cleans yarn cache when present" {
    mkdir -p "$HOME/.cache/yarn"
    touch "$HOME/.cache/yarn/some-cache-file"

    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/linux.sh"
safe_clean() { echo "safe_clean:${*: -1}"; }
clean_tool_cache() { echo "clean_tool_cache:$1"; }
note_activity() { :; }
clean_linux_dev_caches
EOF
    [[ "$status" -eq 0 ]] || return 1
    [[ "$output" == *"safe_clean:Yarn cache"* ]] || return 1
}

@test "clean_linux_dev_caches cleans pnpm store when present" {
    mkdir -p "$HOME/.local/share/pnpm"
    touch "$HOME/.local/share/pnpm/some-store-file"

    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/linux.sh"
safe_clean() { echo "safe_clean:${*: -1}"; }
clean_tool_cache() { echo "clean_tool_cache:$1"; }
note_activity() { :; }
clean_linux_dev_caches
EOF
    [[ "$status" -eq 0 ]] || return 1
    [[ "$output" == *"safe_clean:pnpm store"* ]] || return 1
}

@test "clean_linux_dev_caches cleans pip cache when present" {
    mkdir -p "$HOME/.cache/pip"
    touch "$HOME/.cache/pip/some-cache-file"

    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/linux.sh"
safe_clean() { echo "safe_clean:${*: -1}"; }
clean_tool_cache() { echo "clean_tool_cache:$1"; }
note_activity() { :; }
clean_linux_dev_caches
EOF
    [[ "$status" -eq 0 ]] || return 1
    [[ "$output" == *"safe_clean:pip cache"* ]] || return 1
}

@test "clean_linux_dev_caches skips absent caches without error" {
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/linux.sh"
safe_clean() { echo "safe_clean:${*: -1}"; }
clean_tool_cache() { echo "clean_tool_cache:$1"; }
note_activity() { :; }
rm -rf "$HOME/.npm" "$HOME/.cache/yarn" "$HOME/.local/share/pnpm" "$HOME/.cache/pip"
clean_linux_dev_caches
EOF
    [[ "$status" -eq 0 ]] || return 1
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `MOLE_TEST_NO_AUTH=1 bats tests/clean_linux_dev_caches.bats`
Expected: FAIL — `lib/clean/linux.sh: No such file or directory` (file
does not exist yet).

- [ ] **Step 3: Write minimal implementation**

Create `lib/clean/linux.sh`:

```bash
#!/bin/bash
# Linux/WSL cleanup module. Sourced only when uname -s == Linux.
# Mirrors the safety plumbing every Darwin lib/clean/*.sh module uses:
# safe_clean for file-level targets, clean_tool_cache for CLI-delegated
# targets. No second delete path is introduced.

# Dev/package-manager caches, systemd journal vacuum, and a Docker
# review-only notice. Grouped into one entry point because none of these
# has a dedicated numbered section of its own on macOS either.
clean_linux_dev_caches() {
    safe_clean ~/.npm/* "npm cache"
    safe_clean ~/.cache/yarn/* "Yarn cache"
    safe_clean ~/.local/share/pnpm/* "pnpm store"
    safe_clean ~/.cache/pip/* "pip cache"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `MOLE_TEST_NO_AUTH=1 bats tests/clean_linux_dev_caches.bats`
Expected: PASS (all 5 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/clean/linux.sh tests/clean_linux_dev_caches.bats
git commit -m "[main] add linux dev/package-manager cache cleanup"
```

---

### Task 2: Add systemd journal vacuum to `clean_linux_dev_caches`

**Files:**
- Modify: `lib/clean/linux.sh`
- Modify: `tests/clean_linux_dev_caches.bats`

**Interfaces:**
- Consumes: `clean_linux_dev_caches()` from Task 1 (same function, appended
  logic).
- Produces: no new function name; `clean_tool_cache` is called with
  description `"systemd journal"` — later tasks/manual verification refer
  to this description string when checking output.

- [ ] **Step 1: Write the failing test**

Add to `tests/clean_linux_dev_caches.bats`:

```bash
@test "clean_linux_dev_caches vacuums the user journal via clean_tool_cache" {
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/linux.sh"
safe_clean() { echo "safe_clean:${*: -1}"; }
clean_tool_cache() { echo "clean_tool_cache:$1"; }
note_activity() { :; }
command -v journalctl > /dev/null 2>&1 || { echo "clean_tool_cache:systemd journal"; exit 0; }
clean_linux_dev_caches
EOF
    [[ "$status" -eq 0 ]] || return 1
    [[ "$output" == *"clean_tool_cache:systemd journal"* ]] || return 1
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `MOLE_TEST_NO_AUTH=1 bats tests/clean_linux_dev_caches.bats`
Expected: FAIL — the new test does not find `clean_tool_cache:systemd
journal` in output because `clean_linux_dev_caches` does not call it yet.

- [ ] **Step 3: Write minimal implementation**

Edit `lib/clean/linux.sh`, append inside `clean_linux_dev_caches` (after the
four `safe_clean` lines):

```bash
    if command -v journalctl > /dev/null 2>&1; then
        clean_tool_cache "systemd journal" "" run_with_timeout "$MOLE_TIMEOUT_PKG_CLEANUP_SEC" journalctl --vacuum-time=7d
    fi
```

- [ ] **Step 4: Run test to verify it passes**

Run: `MOLE_TEST_NO_AUTH=1 bats tests/clean_linux_dev_caches.bats`
Expected: PASS (all 6 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/clean/linux.sh tests/clean_linux_dev_caches.bats
git commit -m "[main] add systemd journal vacuum to linux dev cache cleanup"
```

---

### Task 3: Add Docker review-only notice to `clean_linux_dev_caches`

**Files:**
- Modify: `lib/clean/linux.sh`
- Modify: `tests/clean_linux_dev_caches.bats`

**Interfaces:**
- Consumes: `clean_linux_dev_caches()` from Tasks 1–2 (same function,
  appended logic). No deletion helper is called for this block — only
  `note_activity` and `echo`, matching `clean_dev_docker` in
  `lib/clean/dev.sh:429`.

- [ ] **Step 1: Write the failing test**

Add to `tests/clean_linux_dev_caches.bats`:

```bash
@test "clean_linux_dev_caches never deletes docker data, only reviews it" {
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/linux.sh"
safe_clean() { echo "safe_clean:${*: -1}"; }
clean_tool_cache() { echo "clean_tool_cache:$1"; }
note_activity() { :; }
docker() { echo "df line"; }
command() {
    if [[ "$1" == "-v" && "$2" == "docker" ]]; then
        return 0
    fi
    builtin command "$@"
}
clean_linux_dev_caches
EOF
    [[ "$status" -eq 0 ]] || return 1
    [[ "$output" == *"Docker"* ]] || return 1
    [[ "$output" == *"review"* ]] || return 1
    [[ "$output" != *"clean_tool_cache:Docker"* ]] || return 1
    [[ "$output" != *"safe_clean:Docker"* ]] || return 1
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `MOLE_TEST_NO_AUTH=1 bats tests/clean_linux_dev_caches.bats`
Expected: FAIL — no `Docker`/`review` text in output yet.

- [ ] **Step 3: Write minimal implementation**

Edit `lib/clean/linux.sh`, append inside `clean_linux_dev_caches` (after the
journal block from Task 2):

```bash
    if command -v docker > /dev/null 2>&1; then
        note_activity
        echo -e "  ${GRAY}${ICON_WARNING}${NC} Docker unused data · skipped (review: docker system df)"
    fi
```

- [ ] **Step 4: Run test to verify it passes**

Run: `MOLE_TEST_NO_AUTH=1 bats tests/clean_linux_dev_caches.bats`
Expected: PASS (all 7 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/clean/linux.sh tests/clean_linux_dev_caches.bats
git commit -m "[main] add docker review-only notice to linux dev cache cleanup"
```

---

### Task 4: Add `clean_linux_browser_caches` for Chrome/Chromium/Firefox

**Files:**
- Modify: `lib/clean/linux.sh`
- Test: `tests/clean_linux_browser_caches.bats`

**Interfaces:**
- Produces: `clean_linux_browser_caches()` — no args, always returns 0,
  calls `safe_clean` per existing browser cache directory. Independent of
  `clean_linux_dev_caches`; both live in the same file.

- [ ] **Step 1: Write the failing test**

Create `tests/clean_linux_browser_caches.bats`:

```bash
#!/usr/bin/env bats

setup_file() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    export PROJECT_ROOT

    ORIGINAL_HOME="${HOME:-}"
    export ORIGINAL_HOME

    HOME="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp-linux-browser-caches.XXXXXX")"
    export HOME
}

teardown_file() {
    if [[ "$HOME" == "${BATS_TEST_DIRNAME}/tmp-"* ]]; then
        rm -rf "$HOME"
    fi
    if [[ -n "${ORIGINAL_HOME:-}" ]]; then
        export HOME="$ORIGINAL_HOME"
    fi
}

@test "clean_linux_browser_caches cleans chrome cache when present" {
    mkdir -p "$HOME/.cache/google-chrome"
    touch "$HOME/.cache/google-chrome/some-cache-file"

    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/linux.sh"
safe_clean() { echo "safe_clean:${*: -1}"; }
note_activity() { :; }
clean_linux_browser_caches
EOF
    [[ "$status" -eq 0 ]] || return 1
    [[ "$output" == *"safe_clean:Chrome cache"* ]] || return 1
}

@test "clean_linux_browser_caches cleans chromium cache when present" {
    mkdir -p "$HOME/.cache/chromium"
    touch "$HOME/.cache/chromium/some-cache-file"

    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/linux.sh"
safe_clean() { echo "safe_clean:${*: -1}"; }
note_activity() { :; }
clean_linux_browser_caches
EOF
    [[ "$status" -eq 0 ]] || return 1
    [[ "$output" == *"safe_clean:Chromium cache"* ]] || return 1
}

@test "clean_linux_browser_caches cleans firefox cache2 dirs when present" {
    mkdir -p "$HOME/.cache/mozilla/firefox/abc123.default/cache2"
    touch "$HOME/.cache/mozilla/firefox/abc123.default/cache2/some-cache-file"

    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/linux.sh"
safe_clean() { echo "safe_clean:${*: -1}"; }
note_activity() { :; }
clean_linux_browser_caches
EOF
    [[ "$status" -eq 0 ]] || return 1
    [[ "$output" == *"safe_clean:Firefox cache"* ]] || return 1
}

@test "clean_linux_browser_caches skips absent browsers without error" {
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/linux.sh"
safe_clean() { echo "safe_clean:${*: -1}"; }
note_activity() { :; }
rm -rf "$HOME/.cache/google-chrome" "$HOME/.cache/chromium" "$HOME/.cache/mozilla"
clean_linux_browser_caches
EOF
    [[ "$status" -eq 0 ]] || return 1
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `MOLE_TEST_NO_AUTH=1 bats tests/clean_linux_browser_caches.bats`
Expected: FAIL — `clean_linux_browser_caches: command not found`

- [ ] **Step 3: Write minimal implementation**

Edit `lib/clean/linux.sh`, append after `clean_linux_dev_caches`:

```bash
# Generic per-browser cache cleanup for Chrome/Chromium/Firefox on Linux.
# Not the macOS "old version" cleanup — pure runtime cache, always
# rebuildable.
clean_linux_browser_caches() {
    safe_clean ~/.cache/google-chrome/* "Chrome cache"
    safe_clean ~/.cache/chromium/* "Chromium cache"
    safe_clean ~/.cache/mozilla/firefox/*/cache2/* "Firefox cache"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `MOLE_TEST_NO_AUTH=1 bats tests/clean_linux_browser_caches.bats`
Expected: PASS (all 4 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/clean/linux.sh tests/clean_linux_browser_caches.bats
git commit -m "[main] add linux browser cache cleanup"
```

---

### Task 5: Add `clean_linux_apt_cache` for apt archives

**Files:**
- Modify: `lib/clean/linux.sh`
- Test: `tests/clean_linux_apt_cache.bats`

**Interfaces:**
- Produces: `clean_linux_apt_cache()` — no args, always returns 0. Calls
  `clean_tool_cache` with description `"apt archives"`. This function is
  only ever invoked from the `SYSTEM_CLEAN == true` branch in
  `bin/clean.sh` (wired in Task 7) — it does not check `SYSTEM_CLEAN`
  itself, since that variable is a `bin/clean.sh` orchestration concern, not
  a module concern (matches how `clean_deep_system` doesn't check it
  either).

- [ ] **Step 1: Write the failing test**

Create `tests/clean_linux_apt_cache.bats`:

```bash
#!/usr/bin/env bats

setup_file() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    export PROJECT_ROOT
}

@test "clean_linux_apt_cache cleans apt archives via clean_tool_cache when apt-get present" {
    run env PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/linux.sh"
clean_tool_cache() { echo "clean_tool_cache:$1"; }
note_activity() { :; }
apt-get() { :; }
command() {
    if [[ "$1" == "-v" && "$2" == "apt-get" ]]; then
        return 0
    fi
    builtin command "$@"
}
clean_linux_apt_cache
EOF
    [[ "$status" -eq 0 ]] || return 1
    [[ "$output" == *"clean_tool_cache:apt archives"* ]] || return 1
}

@test "clean_linux_apt_cache is a no-op when apt-get is absent" {
    run env PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/linux.sh"
clean_tool_cache() { echo "clean_tool_cache:$1"; }
note_activity() { :; }
command() {
    if [[ "$1" == "-v" && "$2" == "apt-get" ]]; then
        return 1
    fi
    builtin command "$@"
}
clean_linux_apt_cache
EOF
    [[ "$status" -eq 0 ]] || return 1
    [[ "$output" != *"clean_tool_cache"* ]] || return 1
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `MOLE_TEST_NO_AUTH=1 bats tests/clean_linux_apt_cache.bats`
Expected: FAIL — `clean_linux_apt_cache: command not found`

- [ ] **Step 3: Write minimal implementation**

Edit `lib/clean/linux.sh`, append after `clean_linux_browser_caches`:

```bash
# apt archive cache cleanup. Only ever called from bin/clean.sh's
# SYSTEM_CLEAN == true branch (same sudo gate Homebrew's system cleanup
# already uses) — this function does not re-check SYSTEM_CLEAN itself,
# matching clean_deep_system's contract.
clean_linux_apt_cache() {
    if command -v apt-get > /dev/null 2>&1; then
        clean_tool_cache "apt archives" "/var/cache/apt/archives" run_with_timeout "$MOLE_TIMEOUT_PKG_CLEANUP_SEC" apt-get clean
    fi
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `MOLE_TEST_NO_AUTH=1 bats tests/clean_linux_apt_cache.bats`
Expected: PASS (both tests)

- [ ] **Step 5: Commit**

```bash
git add lib/clean/linux.sh tests/clean_linux_apt_cache.bats
git commit -m "[main] add linux apt archive cache cleanup"
```

---

### Task 6: Add `IS_LINUX` flag and conditional source in `bin/clean.sh`

**Files:**
- Modify: `bin/clean.sh:29` (next to the existing `IS_M_SERIES` line)
- Modify: `bin/clean.sh:23` (next to the existing `lib/clean/user.sh` source
  line)
- Test: `tests/clean_linux_wiring.bats`

**Interfaces:**
- Consumes: `clean_linux_dev_caches`, `clean_linux_browser_caches`,
  `clean_linux_apt_cache` from Tasks 1–5 (function names only — not called
  yet in this task, just made available).
- Produces: `IS_LINUX` (string `"true"`/`"false"`, same convention as
  `IS_M_SERIES`) — Task 7 reads this at each section call site.

- [ ] **Step 1: Write the failing test**

Create `tests/clean_linux_wiring.bats`:

```bash
#!/usr/bin/env bats

setup_file() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    export PROJECT_ROOT
}

@test "bin/clean.sh sources lib/clean/linux.sh only when uname -s is Linux" {
    run grep -n 'source.*lib/clean/linux.sh' "$PROJECT_ROOT/bin/clean.sh"
    [[ "$status" -eq 0 ]] || return 1
}

@test "bin/clean.sh defines IS_LINUX next to IS_M_SERIES" {
    run grep -n '^IS_LINUX=' "$PROJECT_ROOT/bin/clean.sh"
    [[ "$status" -eq 0 ]] || return 1
}

@test "bin/clean.sh still passes bash -n after wiring changes" {
    run bash -n "$PROJECT_ROOT/bin/clean.sh"
    [[ "$status" -eq 0 ]] || return 1
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `MOLE_TEST_NO_AUTH=1 bats tests/clean_linux_wiring.bats`
Expected: FAIL — first two greps find nothing yet.

- [ ] **Step 3: Write minimal implementation**

Edit `bin/clean.sh` line 23 (after `source
"$SCRIPT_DIR/../lib/clean/user.sh"`):

```bash
source "$SCRIPT_DIR/../lib/clean/user.sh"
if [[ "$(uname -s)" == "Linux" ]]; then
    source "$SCRIPT_DIR/../lib/clean/linux.sh"
fi
```

Edit `bin/clean.sh` line 29 (after the existing `IS_M_SERIES=` line):

```bash
IS_M_SERIES=$([[ "$(uname -m)" == "arm64" ]] && echo "true" || echo "false")
IS_LINUX=$([[ "$(uname -s)" == "Linux" ]] && echo "true" || echo "false")
```

- [ ] **Step 4: Run test to verify it passes**

Run: `MOLE_TEST_NO_AUTH=1 bats tests/clean_linux_wiring.bats`
Expected: PASS (all 3 tests)

- [ ] **Step 5: Commit**

```bash
git add bin/clean.sh tests/clean_linux_wiring.bats
git commit -m "[main] wire lib/clean/linux.sh into bin/clean.sh sourcing"
```

---

### Task 7: Call the three Linux functions from their sections

**Files:**
- Modify: `bin/clean.sh` (three call sites: "Developer tools" section,
  "Browsers" section, "System" section)
- Modify: `tests/clean_linux_wiring.bats`

**Interfaces:**
- Consumes: `IS_LINUX` from Task 6; `clean_linux_dev_caches`,
  `clean_linux_browser_caches`, `clean_linux_apt_cache` from Tasks 1–5.
- Produces: nothing new — this is the final wiring task. `mole clean`'s
  full run now exercises all three Linux entry points on Linux, none on
  Darwin.

- [ ] **Step 1: Write the failing test**

Add to `tests/clean_linux_wiring.bats`:

```bash
@test "Developer tools section calls clean_linux_dev_caches guarded by IS_LINUX" {
    run grep -A3 'start_section "Developer tools"' "$PROJECT_ROOT/bin/clean.sh"
    [[ "$status" -eq 0 ]] || return 1
    [[ "$output" == *"clean_linux_dev_caches"* ]] || return 1
    [[ "$output" == *"IS_LINUX"* ]] || return 1
}

@test "Browsers section calls clean_linux_browser_caches guarded by IS_LINUX" {
    run grep -A3 'start_section "Browsers"' "$PROJECT_ROOT/bin/clean.sh"
    [[ "$status" -eq 0 ]] || return 1
    [[ "$output" == *"clean_linux_browser_caches"* ]] || return 1
    [[ "$output" == *"IS_LINUX"* ]] || return 1
}

@test "System section calls clean_linux_apt_cache guarded by IS_LINUX inside SYSTEM_CLEAN" {
    run grep -A5 'if \[\[ "\$SYSTEM_CLEAN" == "true" \]\]; then' "$PROJECT_ROOT/bin/clean.sh"
    [[ "$status" -eq 0 ]] || return 1
    [[ "$output" == *"clean_linux_apt_cache"* ]] || return 1
    [[ "$output" == *"IS_LINUX"* ]] || return 1
}

@test "macOS-only Darwin functions are still called unconditionally" {
    run grep -A3 'start_section "Browsers"' "$PROJECT_ROOT/bin/clean.sh"
    [[ "$status" -eq 0 ]] || return 1
    [[ "$output" == *"clean_browsers"* ]] || return 1
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `MOLE_TEST_NO_AUTH=1 bats tests/clean_linux_wiring.bats`
Expected: FAIL — the three new call-site tests find no
`clean_linux_dev_caches`/`clean_linux_browser_caches`/`clean_linux_apt_cache`
references yet.

- [ ] **Step 3: Write minimal implementation**

Edit `bin/clean.sh`, "System" section (around line 1539-1544):

```bash
        # ===== 1. System =====
        if [[ "$SYSTEM_CLEAN" == "true" ]]; then
            start_section "System"
            clean_deep_system
            clean_local_snapshots
            if [[ "$IS_LINUX" == "true" ]]; then
                clean_linux_apt_cache
            fi
            end_section
        fi
```

Edit `bin/clean.sh`, "App caches" section is skipped (already handled by
existing `clean_app_caches`, no Linux target there); "Browsers" section
(around line 1565-1568):

```bash
        # ===== 4. Browsers =====
        start_section "Browsers"
        clean_browsers
        if [[ "$IS_LINUX" == "true" ]]; then
            clean_linux_browser_caches
        fi
        end_section
```

Edit `bin/clean.sh`, "Developer tools" section (around line 1589-1592):

```bash
        # ===== 6. Developer tools (merged CLI and GUI tooling) =====
        start_section "Developer tools"
        clean_developer_tools
        if [[ "$IS_LINUX" == "true" ]]; then
            clean_linux_dev_caches
        fi
        end_section
```

- [ ] **Step 4: Run test to verify it passes**

Run: `MOLE_TEST_NO_AUTH=1 bats tests/clean_linux_wiring.bats`
Expected: PASS (all 7 tests)

- [ ] **Step 5: Commit**

```bash
git add bin/clean.sh tests/clean_linux_wiring.bats
git commit -m "[main] call linux clean functions from developer tools, browsers, and system sections"
```

---

### Task 8: Verify Darwin is unaffected and Linux full-suite passes

**Files:**
- None created or modified — verification only.

**Interfaces:**
- Consumes: everything from Tasks 1–7.
- Produces: nothing — this task is a gate before Task 9's CI addition.

- [ ] **Step 1: Run `bash -n` on every shell file**

Run: `find bin lib -name '*.sh' -print0 | xargs -0 -n1 bash -n`
Expected: no output, exit 0 for every file.

- [ ] **Step 2: Run the full Bats suite in test-mode**

Run: `MOLE_TEST_NO_AUTH=1 ./scripts/test.sh`
Expected: all tests pass, including the 4 new files from Tasks 1, 4, 5, 6-7
and every existing Darwin-focused `tests/clean_*.bats` file untouched by
this plan.

- [ ] **Step 3: Run `./scripts/check.sh --format`**

Run: `./scripts/check.sh --format`
Expected: no formatting diffs reported for `lib/clean/linux.sh` or
`bin/clean.sh` beyond this plan's own edits.

- [ ] **Step 4: Confirm no Darwin section body was touched**

Run: `git diff main -- lib/clean/user.sh lib/clean/dev.sh lib/clean/apps.sh lib/clean/app_caches.sh lib/clean/system.sh lib/clean/brew.sh lib/clean/project.sh lib/clean/hints.sh lib/clean/launch_services.sh lib/clean/purge_shared.sh lib/clean/maven.sh`
Expected: empty diff — none of these files appear in this plan's tasks.

- [ ] **Step 5: Commit (only if Step 3 produced formatting fixes; otherwise skip)**

```bash
git add -A
git commit -m "[main] apply formatting fixes from scripts/check.sh --format"
```

---

### Task 9: Add Linux Bats lane to CI and verify on real WSL

**Files:**
- Modify: `.github/workflows/test.yml`

**Interfaces:**
- Consumes: `tests/clean_linux_dev_caches.bats`,
  `tests/clean_linux_browser_caches.bats`,
  `tests/clean_linux_apt_cache.bats`, `tests/clean_linux_wiring.bats` from
  Tasks 1–7.
- Produces: nothing new for later tasks — this is the last task in the
  plan.

- [ ] **Step 1: Read the existing `go-test-linux` job**

Run: `sed -n '47,61p' .github/workflows/test.yml`
Confirm it matches the job added in Phase 1 (runs on `ubuntu-latest`, sets
up Go, runs `go test ./...`).

- [ ] **Step 2: Add a Bats install + run step to a new sibling job**

Edit `.github/workflows/test.yml`, insert a new job after `go-test-linux`
(before `compatibility`):

```yaml
  bats-test-linux:
    name: Bats Tests (Linux)
    runs-on: ubuntu-latest
    timeout-minutes: 15
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1

      - name: Install bats
        run: sudo apt-get update && sudo apt-get install -y bats

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
               tests/clean_linux_wiring.bats
```

- [ ] **Step 3: Validate the YAML**

Run: `python3 -c "import yaml, sys; yaml.safe_load(open('.github/workflows/test.yml'))" && echo VALID`

(If PyYAML is unavailable and system Python is externally managed, create a
throwaway venv rather than using `pip install --break-system-packages`:
`python3 -m venv /tmp/yamlcheck && /tmp/yamlcheck/bin/pip install pyyaml -q
&& /tmp/yamlcheck/bin/python3 -c "import yaml; yaml.safe_load(open('.github/workflows/test.yml'))" && echo VALID && rm -rf /tmp/yamlcheck`)

Expected: prints `VALID`.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/test.yml
git commit -m "[main] add linux clean bats lane to CI"
```

- [ ] **Step 5: Manual end-to-end verification on the user's real WSL install**

Run each of the following on the real (non-test-mode) WSL system, in this
exact order, capturing before/after sizes for the reclaim-number
requirement in AGENTS.md:

```bash
du -sh ~/.npm ~/.cache/yarn ~/.local/share/pnpm ~/.cache/pip 2>/dev/null
du -sh ~/.cache/google-chrome ~/.cache/chromium ~/.cache/mozilla/firefox/*/cache2 2>/dev/null
journalctl --disk-usage
du -sh /var/cache/apt/archives 2>/dev/null

MOLE_TEST_NO_AUTH=1 ./mole clean --dry-run   # preview only, confirm every
                                              # Linux target line appears
                                              # with a plausible size

./mole clean                                 # real run — user-level
                                              # sections only
sudo ./mole clean --system                   # if the CLI exposes a system
                                              # flag; otherwise trigger
                                              # SYSTEM_CLEAN the same way
                                              # existing macOS system
                                              # cleanup is triggered

du -sh ~/.npm ~/.cache/yarn ~/.local/share/pnpm ~/.cache/pip 2>/dev/null
du -sh /var/cache/apt/archives 2>/dev/null
```

Report the actual measured reclaim number per target that was present on
this machine, and note which targets were absent (0 bytes reclaimed is an
expected, valid outcome for an absent cache — not a bug).
