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
    # shellcheck disable=SC2016
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
