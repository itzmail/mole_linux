# Phase 2c: `mole purge` on Linux/WSL Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `mole purge`'s existing test suite fully green on Linux by fixing three pre-existing bugs the Linux run surfaced, then lock in Linux CI coverage. No new Linux-specific purge module is needed — `lib/clean/project.sh`, `lib/clean/purge_shared.sh`, and `bin/purge.sh` are already platform-neutral.

**Architecture:** Three independent, small fixes: (1) a deterministic tilde-shortening helper in `lib/clean/project.sh` used by both `format_purge_target_path` and `save_discovered_paths`, replacing a bash-version-dependent pattern substitution that silently no-ops; (2) an isolation fix inside one existing test in `tests/purge.bats` so its mock-`find` marker file can't be tripped by unrelated `common.sh` bootstrap `find` calls; (3) a two-branch dispatch in the shared `_run_in_pty` test helper (`tests/purge.bats`) so it invokes BSD `script(1)` (macOS) or util-linux `script(1)` (Linux) with the syntax each expects. Then wire `tests/purge.bats` and `tests/purge_config_paths.bats` into the existing Linux CI job.

**Tech Stack:** Bash, Bats tests, existing Mole core libs (`lib/core/common.sh`). No Go changes.

## Global Constraints

- No changes to purge target detection, protection rules (`is_protected_purge_artifact`, `is_protected_vendor_dir`), or search-path discovery logic — those already pass on Linux unmodified (spec: Scope Part 2, Non-goals).
- The tilde-shortening fix must not depend on bash-version-specific behavior — it must produce `~/...` deterministically on any bash 4+ (spec: Part 1, item 1).
- The `scan_purge_targets` test fix must isolate the test, not touch `scan_purge_targets` or any other function in `lib/clean/project.sh` (spec: Part 1, item 2 — "not the product code").
- The `_run_in_pty` fix's macOS/BSD branch must stay byte-identical in behavior to the current invocation — no regression risk on macOS CI (spec: Testing plan).
- No new purge targets, no new search paths, no `$HOME/Library/CloudStorage` special-casing (spec: Non-goals).
- Extend the existing `bats-test-linux` CI job in `.github/workflows/test.yml` — do not create a new job (spec: Part 2, following Phase 2a/2b pattern).

---

## File Structure

- Modify: `lib/clean/project.sh` — fix `format_purge_target_path` (lines 205-208), fix `save_discovered_paths` (lines 161-167) to tilde-shorten paths before writing.
- Modify: `tests/purge.bats` — fix the `scan_purge_targets: trusts empty fd result...` test's isolation (around line 826); fix `_run_in_pty` (around line 1523) to dispatch on `script(1)` variant.
- Modify: `.github/workflows/test.yml` — add `tests/purge.bats` and `tests/purge_config_paths.bats` to the existing `bats-test-linux` job's bats invocation (currently lines 79-86).

No new files are created in this phase.

---

### Task 1: Fix `format_purge_target_path` tilde substitution

**Files:**
- Modify: `lib/clean/project.sh:205-208`
- Test: `tests/purge.bats` (existing test, currently failing)

**Interfaces:**
- Produces: `format_purge_target_path(path) -> string` — unchanged signature and contract (takes an absolute path, returns it with a leading `$HOME` replaced by `~`). Only the internal implementation changes.

- [ ] **Step 1: Confirm the existing failing test**

Run: `MOLE_TEST_NO_AUTH=1 bats --filter "format_purge_target_path rewrites home with tilde" tests/purge.bats`

Expected: FAIL — `[[ "$output" == \~/www/app/node_modules ]]' failed` (the function currently returns the path unchanged because bash tilde-expands the bare `~` replacement operand before the substitution runs).

- [ ] **Step 2: Write the minimal implementation fix**

In `lib/clean/project.sh`, replace:

```bash
format_purge_target_path() {
    local path="$1"
    echo "${path/#$HOME/~}"
}
```

with a version that builds the tilde via string concatenation instead of putting a bare `~` in the substitution's replacement operand (which is what triggers bash's tilde-expansion-before-substitution behavior):

```bash
format_purge_target_path() {
    local path="$1"
    if [[ "$path" == "$HOME" || "$path" == "$HOME"/* ]]; then
        printf '~%s\n' "${path#"$HOME"}"
        return
    fi
    printf '%s\n' "$path"
}
```

- [ ] **Step 3: Run test to verify it passes**

Run: `MOLE_TEST_NO_AUTH=1 bats --filter "format_purge_target_path rewrites home with tilde" tests/purge.bats`
Expected: PASS

- [ ] **Step 4: Run the cloud-marker test that depends on this function**

Run: `MOLE_TEST_NO_AUTH=1 bats --filter "clean_project_artifacts: non-interactive dry-run shows cloud marker and preserves artifact" tests/purge.bats`
Expected: PASS (this test asserts `[cloud] ~/Library/CloudStorage/...` appears in output, which flows through `format_purge_target_path` at `lib/clean/project.sh:1580`)

- [ ] **Step 5: Commit**

```bash
git add lib/clean/project.sh
git commit -m "[main] fix format_purge_target_path tilde substitution on bash 5.2+

A bare ~ as the replacement operand of \${path/#\$HOME/~} is itself
tilde-expanded by bash before the substitution runs, making the
replacement a no-op (HOME replaced with HOME). Build the tilde via
string concatenation instead so the fix does not depend on bash
version behavior."
```

---

### Task 2: Fix `save_discovered_paths` to tilde-shorten before writing

**Files:**
- Modify: `lib/clean/project.sh:161-167`
- Test: `tests/purge.bats` (existing test, currently failing)

**Interfaces:**
- Consumes: `format_purge_target_path(path) -> string` from Task 1.
- Produces: `save_discovered_paths(paths...)` — unchanged signature. Writes each path tilde-shortened via `format_purge_target_path` instead of raw absolute paths.

- [ ] **Step 1: Confirm the existing failing test**

Run: `MOLE_TEST_NO_AUTH=1 bats --filter "save_discovered_paths writes config with tilde" tests/purge.bats`
Expected: FAIL — the config file contains the raw absolute path (e.g. `/tmp/.../Projects`), not `~/Projects`, so `grep -q "^~/"` fails.

- [ ] **Step 2: Write the minimal implementation fix**

In `lib/clean/project.sh`, replace:

```bash
save_discovered_paths() {
    local -a paths=("$@")
    write_purge_config "# Mole Purge Paths - Auto-discovered project directories
# Edit this file to customize, or run: mo purge --paths
# Add one path per line (supports ~ for home directory)
" "${paths[@]}"
}
```

with:

```bash
save_discovered_paths() {
    local -a paths=("$@")
    local -a display_paths=()
    local path
    for path in "${paths[@]}"; do
        display_paths+=("$(format_purge_target_path "$path")")
    done
    write_purge_config "# Mole Purge Paths - Auto-discovered project directories
# Edit this file to customize, or run: mo purge --paths
# Add one path per line (supports ~ for home directory)
" "${display_paths[@]}"
}
```

- [ ] **Step 3: Run test to verify it passes**

Run: `MOLE_TEST_NO_AUTH=1 bats --filter "save_discovered_paths writes config with tilde" tests/purge.bats`
Expected: PASS

- [ ] **Step 4: Run the full purge_config_paths suite to check for regressions**

Run: `MOLE_TEST_NO_AUTH=1 bats tests/purge_config_paths.bats`
Expected: all PASS — `format_purge_target_path` and `mole_purge_read_paths_config` already expand `~` back to `$HOME` on read (`purge_shared.sh:184-197`, `line="${line/#\~/$HOME}"`), so round-tripping through tilde-shortened storage must still resolve to the same absolute paths.

- [ ] **Step 5: Commit**

```bash
git add lib/clean/project.sh
git commit -m "[main] tilde-shorten paths in save_discovered_paths before writing

save_discovered_paths wrote raw absolute paths to the purge config
file even though the file's own header comment says it supports ~
for home directory. Route each path through format_purge_target_path
before writing so auto-discovered paths display the same way
user-edited config entries do."
```

---

### Task 3: Fix `scan_purge_targets` fd-trust test isolation

**Files:**
- Modify: `tests/purge.bats` (test only, around line 826-858)

**Interfaces:**
- Consumes: nothing new — this is a test-only fix, `scan_purge_targets` itself is unmodified.
- Produces: nothing new — no interface change.

- [ ] **Step 1: Confirm the existing failing test and its false-positive cause**

Run: `MOLE_TEST_NO_AUTH=1 bats --filter "scan_purge_targets: trusts empty fd result without falling back to find" tests/purge.bats`
Expected: FAIL — `[ "$status" -eq 0 ]' failed`.

Root cause (already diagnosed): the test's mock `find` script appends to `$HOME/find-called` on *any* invocation. `project.sh` sources `common.sh` on load (its own guard `if ! command -v ensure_user_dir ...` is always true in a fresh subshell), and `common.sh`'s bootstrap runs `prune_stale_mole_temp_files` (`lib/core/base.sh:695-729`), which calls `find` unconditionally as part of temp-directory maintenance — unrelated to `scan_purge_targets`. That bootstrap `find` call trips the same marker file the test checks, even though `scan_purge_targets` itself correctly used the mocked `fd` and never called `find`.

- [ ] **Step 2: Write the minimal test fix**

In `tests/purge.bats`, find the test:

```bash
@test "scan_purge_targets: trusts empty fd result without falling back to find" {
	mkdir -p "$HOME/.config/mole" "$HOME/www/empty-project"
	printf '%s\n' "$HOME/www" > "$HOME/.config/mole/purge_paths"

	local mock_bin="$HOME/mock-bin"
	mkdir -p "$mock_bin"
	cat > "$mock_bin/fd" <<'EOF'
#!/bin/bash
exit 0
EOF
	chmod +x "$mock_bin/fd"
	cat > "$mock_bin/find" <<'EOF'
#!/bin/bash
echo find-called >> "$HOME/find-called"
exit 0
EOF
	chmod +x "$mock_bin/find"

	local scan_output
	scan_output="$(mktemp)"

	run env HOME="$HOME" PATH="$mock_bin:$PATH" /bin/bash --noprofile --norc <<EOF
set -euo pipefail
source "$PROJECT_ROOT/lib/clean/project.sh"
scan_purge_targets "$HOME/www" "$scan_output"
[[ ! -e "$HOME/find-called" ]] || exit 1
[[ -f "$scan_output" ]] || exit 1
[[ ! -s "$scan_output" ]] || exit 1
EOF

	rm -f "$scan_output"
	[ "$status" -eq 0 ]
}
```

Replace the inner script so the marker file is removed immediately after sourcing `project.sh` (which is what triggers the unrelated bootstrap `find` calls), so only `find` calls made during `scan_purge_targets` itself count:

```bash
@test "scan_purge_targets: trusts empty fd result without falling back to find" {
	mkdir -p "$HOME/.config/mole" "$HOME/www/empty-project"
	printf '%s\n' "$HOME/www" > "$HOME/.config/mole/purge_paths"

	local mock_bin="$HOME/mock-bin"
	mkdir -p "$mock_bin"
	cat > "$mock_bin/fd" <<'EOF'
#!/bin/bash
exit 0
EOF
	chmod +x "$mock_bin/fd"
	cat > "$mock_bin/find" <<'EOF'
#!/bin/bash
echo find-called >> "$HOME/find-called"
exit 0
EOF
	chmod +x "$mock_bin/find"

	local scan_output
	scan_output="$(mktemp)"

	run env HOME="$HOME" PATH="$mock_bin:$PATH" /bin/bash --noprofile --norc <<EOF
set -euo pipefail
source "$PROJECT_ROOT/lib/clean/project.sh"
# Sourcing project.sh runs common.sh bootstrap maintenance (stale temp-file
# pruning), which calls the real find and can trip the mock's marker file
# before scan_purge_targets is even invoked. Clear it here so only find
# calls made by scan_purge_targets itself are observed below.
rm -f "$HOME/find-called"
scan_purge_targets "$HOME/www" "$scan_output"
[[ ! -e "$HOME/find-called" ]] || exit 1
[[ -f "$scan_output" ]] || exit 1
[[ ! -s "$scan_output" ]] || exit 1
EOF

	rm -f "$scan_output"
	[ "$status" -eq 0 ]
}
```

- [ ] **Step 3: Run test to verify it passes**

Run: `MOLE_TEST_NO_AUTH=1 bats --filter "scan_purge_targets: trusts empty fd result without falling back to find" tests/purge.bats`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add tests/purge.bats
git commit -m "[main] isolate scan_purge_targets fd-trust test from common.sh bootstrap find calls

The test's mock find marker file was tripped by common.sh's own
startup temp-file pruning (prune_stale_mole_temp_files), which runs
as a side effect of sourcing project.sh, before scan_purge_targets
was even called. Clear the marker immediately after sourcing so the
test only observes find calls made by scan_purge_targets itself."
```

---

### Task 4: Fix `_run_in_pty` for util-linux `script(1)`

**Files:**
- Modify: `tests/purge.bats` (test helper only, around line 1519-1527)

**Interfaces:**
- Produces: `_run_in_pty(script_file)` — unchanged signature and contract (runs a bash script file under a pseudo-terminal so `[[ -t 0 ]]` is true inside it). Internal invocation now dispatches on which `script(1)` variant is installed.

- [ ] **Step 1: Confirm the existing failures and their cause**

Run: `MOLE_TEST_NO_AUTH=1 bats tests/purge.bats 2>&1 | grep -A2 "sort:"`
Expected: 3 tests fail with `_run_in_pty` returning non-zero.

Root cause (already diagnosed): the current helper is
```bash
_run_in_pty() {
	local script_file="$1"
	script -q /dev/null /bin/bash --noprofile --norc "$script_file" < /dev/null 2>/dev/null
}
```
This is BSD `script(1)` syntax. util-linux's `script` (the Linux/WSL default) parses `--noprofile` as its own unrecognized option and exits immediately with `script: unrecognized option '--noprofile'`, so `/bin/bash` never runs at all — reproduced directly: `script -q /dev/null /bin/bash --noprofile --norc /tmp/x.sh < /dev/null` fails with that exact message on this box.

- [ ] **Step 2: Write the minimal implementation fix**

In `tests/purge.bats`, replace:

```bash
_run_in_pty() {
	local script_file="$1"
	# A socket-backed runner stdin makes macOS script(1) fail before the child starts.
	script -q /dev/null /bin/bash --noprofile --norc "$script_file" < /dev/null 2>/dev/null
}
```

with a variant that detects util-linux vs BSD `script(1)` and uses each one's own syntax for passing a command through:

```bash
_run_in_pty() {
	local script_file="$1"
	# BSD script(1) (macOS) takes the command as trailing positional args.
	# util-linux script(1) (Linux) parses leading dashes as its own options,
	# so --noprofile/--norc there must go after `-c` inside a single string.
	# A socket-backed runner stdin makes macOS script(1) fail before the
	# child starts, so both branches keep stdin redirected from /dev/null.
	if script --version 2>&1 | grep -qi "util-linux"; then
		script -qc "/bin/bash --noprofile --norc '$script_file'" /dev/null < /dev/null 2>/dev/null
	else
		script -q /dev/null /bin/bash --noprofile --norc "$script_file" < /dev/null 2>/dev/null
	fi
}
```

- [ ] **Step 3: Run test to verify it passes**

Run: `MOLE_TEST_NO_AUTH=1 bats --filter "sort:" tests/purge.bats`
Expected: all 3 sort-order tests PASS.

- [ ] **Step 4: Run the full purge.bats suite**

Run: `MOLE_TEST_NO_AUTH=1 bats tests/purge.bats`
Expected: all tests PASS (0 failures).

- [ ] **Step 5: Commit**

```bash
git add tests/purge.bats
git commit -m "[main] dispatch _run_in_pty on script(1) variant for Linux support

util-linux script(1) (default on Linux/WSL) parses leading-dash
arguments as its own options rather than passing them through to the
wrapped command, so the existing BSD-style invocation
(script -q /dev/null bash --noprofile --norc file) fails immediately
with 'unrecognized option --noprofile' and the 3 PTY-based sort-order
regression tests never actually ran their script. Detect the
installed variant and use script -qc '...' for util-linux, keeping
the existing BSD invocation unchanged for macOS."
```

---

### Task 5: Wire purge tests into Linux CI and manual verification

**Files:**
- Modify: `.github/workflows/test.yml` (lines 79-86, the `bats-test-linux` job's `Run linux clean bats subset` step)

**Interfaces:**
- Consumes: `tests/purge.bats`, `tests/purge_config_paths.bats` (both fully green as of Task 4).
- Produces: no new interface — CI wiring only.

- [ ] **Step 1: Confirm full local test suite is green before touching CI**

Run: `MOLE_TEST_NO_AUTH=1 bats tests/purge.bats tests/purge_config_paths.bats`
Expected: all PASS, 0 failures.

- [ ] **Step 2: Add the two purge test files to the Linux CI job**

In `.github/workflows/test.yml`, find:

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

Replace with:

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
               tests/uninstall_linux_wiring.bats \
               tests/purge.bats \
               tests/purge_config_paths.bats
```

- [ ] **Step 3: Validate the workflow YAML syntax**

Run:
```bash
python3 -m venv /tmp/yamlcheck && /tmp/yamlcheck/bin/pip install -q pyyaml && /tmp/yamlcheck/bin/python3 -c "import yaml; yaml.safe_load(open('.github/workflows/test.yml'))" && echo VALID
```
Expected: `VALID` printed, no exception.

- [ ] **Step 4: Manual WSL verification checkpoint**

Run in a scratch project directory (do not run against real project trees without `--dry-run`):

```bash
mkdir -p /tmp/mole-purge-check/demo-project/node_modules
echo '{}' > /tmp/mole-purge-check/demo-project/package.json
dd if=/dev/zero of=/tmp/mole-purge-check/demo-project/node_modules/data bs=1024 count=100 2>/dev/null

mkdir -p ~/.config/mole
echo "/tmp/mole-purge-check" > ~/.config/mole/purge_paths
MOLE_DRY_RUN=1 MOLE_TEST_NO_AUTH=1 ./mole purge --dry-run </dev/null
```

Expected: output lists `demo-project/node_modules` as a candidate with its size, tilde-shortened paths (if any fall under `$HOME`) display as `~/...` rather than the full absolute path, and no files are actually removed (dry-run). Confirm the artifact still exists afterward:
```bash
[[ -d /tmp/mole-purge-check/demo-project/node_modules ]] && echo "confirmed: not deleted"
```

Clean up the scratch check afterward:
```bash
rm -rf /tmp/mole-purge-check
rm -f ~/.config/mole/purge_paths
```

- [ ] **Step 5: Run the full local verification sweep**

Run:
```bash
./scripts/check.sh --format
MOLE_TEST_NO_AUTH=1 bats tests/purge.bats tests/purge_config_paths.bats
GOOS=darwin go build ./...
```
Expected: formatter reports no changes needed (or auto-fixes are re-verified), all Bats tests PASS, Go build stays clean for the macOS target (no Go files touched in this phase, so this is a sanity check).

- [ ] **Step 6: Commit**

```bash
git add .github/workflows/test.yml
git commit -m "[main] add purge bats tests to Linux CI job

tests/purge.bats and tests/purge_config_paths.bats now pass cleanly
on Linux after the Task 1-4 fixes. Add them to the existing
bats-test-linux job's bats invocation, same pattern used for the
clean and uninstall Linux test files in Phase 2a/2b."
```

---

## Self-Review Notes

- **Spec coverage:** Part 1 items 1-3 map to Tasks 1-4 (tilde bug split into two call sites — `format_purge_target_path` and `save_discovered_paths` — since the diagnosis phase found `save_discovered_paths` was missing a call to the shared helper entirely, not just inheriting its bug); Part 2 (CI wiring + manual verification) maps to Task 5. Non-goals are respected — no task touches target detection, protection rules, or search-path defaults.
- **Type/interface consistency:** `format_purge_target_path(path) -> string` signature is unchanged across Tasks 1 and 2; Task 2 explicitly consumes it. `_run_in_pty(script_file)` signature unchanged in Task 4. No new functions introduced, so no naming drift risk.
- **No placeholders:** every step has literal before/after code or literal commands.
