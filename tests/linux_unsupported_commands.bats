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
