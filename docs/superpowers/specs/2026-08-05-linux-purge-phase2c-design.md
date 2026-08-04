# Phase 2c: `mole purge` on Linux/WSL — Design

## Context

Phase 2a (`mole clean`) and Phase 2b (`mole uninstall`) are merged to `main`. Both required a dedicated Linux-specific module behind an `IS_LINUX` branch, because their targets (macOS system caches, `.app` bundles, `apt`/`dpkg`) are inherently platform-specific.

`mole purge` (`bin/purge.sh`, `lib/clean/project.sh`, `lib/clean/purge_shared.sh`) is different: its purge targets are language/build-tool artifacts (`node_modules`, `target`, `venv`, `__pycache__`, etc.) detected by project-indicator files (`package.json`, `Cargo.toml`, `go.mod`, ...). None of this is macOS-specific. A direct test run on this Linux/WSL box confirms it: **37 of 44 existing purge tests pass unmodified**, with zero code changes.

The 7 failures are all pre-existing bugs, not missing Linux logic:

1. **`format_purge_target_path` tilde bug** (4 tests: `format_purge_target_path rewrites home with tilde`, `save_discovered_paths writes config with tilde`, `clean_project_artifacts: non-interactive dry-run shows cloud marker and preserves artifact`, plus display formatting reused elsewhere). The function is:
   ```bash
   format_purge_target_path() {
       local path="$1"
       echo "${path/#$HOME/~}"
   }
   ```
   On bash 5.2 (this box), a **bare** `~` as the replacement operand of a `${var/pattern/replacement}` substitution is itself tilde-expanded to `$HOME` before the substitution runs. Net effect: replacing `$HOME` with (effectively) `$HOME` again — a silent no-op, so the path is never shortened. Reproduced in plain bash outside any Mole code:
   ```bash
   $ bash -c 'x="/foo/bar"; echo "${x/#\/foo/~}"'
   /home/itsmail/bar    # expected: ~/bar
   ```
   This is a bash-version-triggered bug, not a macOS/Linux logic difference — it just happens to surface now because this is the first time these tests ran on a bash build that exhibits it.

2. **`scan_purge_targets: trusts empty fd result without falling back to find`** (1 test). Diagnosed by adding call logging to the mock `fd`/`find` scripts: `scan_purge_targets` itself never calls `find` — it correctly uses the mocked `fd` for both the target scan and the CACHEDIR.TAG scan. The `find` calls the test's mock is catching come from `common.sh`'s own startup maintenance (`prune_stale_mole_temp_files` in `lib/core/base.sh`), which runs because `project.sh`'s guarded `source common.sh` (`if ! command -v ensure_user_dir ...`) always sources fully in a fresh subshell. The mock's marker file (`$HOME/find-called`) is written by *any* invocation of the mocked `find`, so it can't distinguish "called by `scan_purge_targets`" from "called by unrelated `common.sh` bootstrap." Test isolation gap, not a product bug.

3. **Two PTY-based sort-order regression tests** (`sort: PURGE_CATEGORY_FULL_PATHS_ARRAY[0] is the largest artifact after size-descending sort`, `sort: PURGE_CATEGORY_FULL_PATHS_ARRAY and PURGE_CATEGORY_SIZES indices are consistent`; a third, `sort: cloud marker stays aligned...`, shares the same root cause). The shared `_run_in_pty` test helper invokes:
   ```bash
   script -q /dev/null /bin/bash --noprofile --norc "$script_file" < /dev/null
   ```
   This is BSD `script(1)` syntax (macOS). util-linux's `script` (installed on this Linux box) parses `--noprofile` as an option to `script` itself and fails immediately: `script: unrecognized option '--noprofile'`. util-linux requires `-c "command"` or `-- command args...` to separate its own flags from the wrapped command. This is a genuine, previously-undiscovered Linux portability gap in a **test helper**, not in `project.sh`.

## Scope

Phase 2c has two parts:

### Part 1 — Fix the 7 pre-existing failures (portability bugs surfaced by running on Linux)

- Fix `format_purge_target_path` to not rely on bash's bare-`~`-replacement quirk. Use a form that inserts a literal tilde deterministically regardless of bash version (e.g. quote-protect the replacement so it can't be tilde-expanded, or build the result with string concatenation instead of pattern substitution).
- Fix the `scan_purge_targets: trusts empty fd result...` test itself (not the product code) to isolate the marker file per-test-scope so unrelated `common.sh` bootstrap `find` calls can't trip it — e.g. truncate/remove any pre-existing marker immediately before calling `scan_purge_targets`, after sourcing, so only calls made *during* the function under test count.
- Fix `_run_in_pty` to detect which `script(1)` variant is present and invoke it with the right syntax on each: BSD form on macOS, `-c`/`-- ` form on util-linux/Linux. Same shape as the existing macOS-only comment in that helper — extend it to a real two-branch dispatch instead of a single hardcoded invocation.

No changes to `lib/clean/project.sh`'s actual scanning/filtering/protection logic — those are already platform-neutral and already pass.

### Part 2 — Confirm and lock in Linux support

- No new `lib/purge/linux.sh` module is needed — unlike clean/uninstall, purge has no macOS-only branch to route around. `bin/purge.sh` and `lib/clean/project.sh` run as-is on Linux.
- Add the existing purge test files (`tests/purge.bats`, `tests/purge_config_paths.bats`) to the Linux CI lane (`bats-test-linux` job in `.github/workflows/test.yml`), the same way Phase 2a/2b's test files were added, so this stays regression-tested on Linux going forward.
- Manual WSL verification checkpoint (matching Phase 2a/2b pattern): run `./mole purge --dry-run` in a real project directory and confirm output/paths look correct, and that `~`-shortened paths now display correctly after the tilde fix.

## Non-goals

- No behavior changes to purge target detection, protection rules, or search-path discovery — those are already correct on Linux.
- No new purge targets specific to Linux tooling (e.g. no new indicators or artifact names added in this phase). If Linux-specific artifact types are wanted later (e.g. `Cargo.lock`-adjacent caches unique to Linux toolchains), that's a separate future request.
- `$HOME/Library/CloudStorage` stays in `MOLE_PURGE_DEFAULT_SEARCH_PATHS` unchanged — it simply won't exist on Linux and the existing `-d "$path"` check already skips missing paths. Not worth special-casing out.
- No fix attempted for any *other* latent bash-version-triggered bugs beyond the ones enumerated above — this phase fixes exactly the 7 failures found, not a general bash-compat audit.

## Testing plan

- Fix `format_purge_target_path`; re-run `tests/purge.bats` — the 3-4 tests keyed on tilde display should go green.
- Fix the `scan_purge_targets` test's marker-file isolation; re-run — should go green without touching `scan_purge_targets` itself.
- Fix `_run_in_pty`'s `script(1)` dispatch; re-run the 3 sort-order tests — should go green on this Linux box, and must not regress on macOS (verify by reading the BSD branch stays byte-identical to today's invocation).
- Full suite: `MOLE_TEST_NO_AUTH=1 bats tests/purge.bats tests/purge_config_paths.bats` → 44/44 (or however many exist after the fix) on Linux.
- `GOOS=darwin go build ./...` stays clean (no Go changes expected, but confirm as a sanity check since none of this phase touches Go).
- CI: extend `bats-test-linux` job's existing bats invocation with the two purge test files.
- Manual: `MOLE_DRY_RUN=1 ./mole purge --dry-run` (or equivalent) against a real project tree in this WSL environment; confirm tilde-shortened paths display correctly and no artifacts are actually removed.
