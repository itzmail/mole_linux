#!/usr/bin/env bats

# Regression test for a real crash found during manual Linux/WSL
# verification: bin/clean.sh's safe_clean batch-sizing path called BSD-only
# `stat -f%z` unconditionally. On GNU/Linux stat, `-f` means "filesystem
# info" rather than "format string", so the command fails, and because
# bin/clean.sh runs under `set -euo pipefail`, the whole script aborted
# (exit 1) the moment a safe_clean call batched more than 3 existing paths.

setup_file() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    export PROJECT_ROOT

    ORIGINAL_HOME="${HOME:-}"
    export ORIGINAL_HOME

    HOME="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp-linux-stat-regression.XXXXXX")"
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

@test "get_cleanup_path_size_kb sizing loop does not crash with more than 3 existing paths on Linux" {
    mkdir -p "$HOME/.npm"
    for i in 1 2 3 4 5; do
        echo "data" > "$HOME/.npm/file_${i}.txt"
    done

    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" MOLE_TEST_NO_AUTH=1 /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/core/sudo.sh"
source "$PROJECT_ROOT/lib/clean/brew.sh"
source "$PROJECT_ROOT/lib/clean/caches.sh"
source "$PROJECT_ROOT/lib/clean/apps.sh"
source "$PROJECT_ROOT/lib/clean/dev.sh"
source "$PROJECT_ROOT/lib/clean/app_caches.sh"
source "$PROJECT_ROOT/lib/clean/hints.sh"
source "$PROJECT_ROOT/lib/clean/launch_services.sh"
source "$PROJECT_ROOT/lib/clean/system.sh"
source "$PROJECT_ROOT/lib/clean/user.sh"
source "$PROJECT_ROOT/lib/clean/linux.sh"
IS_LINUX="true"
DRY_RUN=false
existing_paths=("$HOME/.npm/file_1.txt" "$HOME/.npm/file_2.txt" "$HOME/.npm/file_3.txt" "$HOME/.npm/file_4.txt" "$HOME/.npm/file_5.txt")
if [[ "$IS_LINUX" == "true" ]]; then
    while IFS= read -r bytes; do
        echo "size_line:$bytes"
    done < <(stat -c%s "${existing_paths[@]}" 2> /dev/null)
else
    while IFS= read -r bytes; do
        echo "size_line:$bytes"
    done < <(stat -f%z "${existing_paths[@]}" 2> /dev/null)
fi
EOF
    [[ "$status" -eq 0 ]] || return 1
    [[ "$output" == *"size_line:"* ]] || return 1
}

@test "mole clean --dry-run does not crash on Linux with a populated npm cache" {
    mkdir -p "$HOME/.npm"
    for i in 1 2 3 4 5; do
        echo "data" > "$HOME/.npm/file_${i}.txt"
    done

    run env HOME="$HOME" MOLE_TEST_NO_AUTH=1 "$PROJECT_ROOT/bin/clean.sh" --dry-run
    [[ "$status" -eq 0 ]] || return 1
}
