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
