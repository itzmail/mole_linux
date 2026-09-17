#!/usr/bin/env bats

setup_file() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    export PROJECT_ROOT
}

@test "lib/optimize/linux.sh has valid bash syntax" {
    run bash -n "$PROJECT_ROOT/lib/optimize/linux.sh"
    [[ "$status" -eq 0 ]] || return 1
}

@test "bin/optimize.sh has valid bash syntax" {
    run bash -n "$PROJECT_ROOT/bin/optimize.sh"
    [[ "$status" -eq 0 ]] || return 1
}

@test "bin/optimize.sh sources lib/optimize/linux.sh under an IS_LINUX guard" {
    run grep -n 'MOLE_IS_LINUX' "$PROJECT_ROOT/bin/optimize.sh"
    [[ "$status" -eq 0 ]] || return 1

    run grep -n 'lib/optimize/linux.sh\|linux_optimize_main' "$PROJECT_ROOT/bin/optimize.sh"
    [[ "$status" -eq 0 ]] || return 1
}

@test "linux_optimize_main --help prints usage" {
    run env PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/optimize/linux.sh"
linux_optimize_main --help
EOF
    [[ "$status" -eq 0 ]] || return 1
    [[ "$output" == *"Usage:"* ]] || return 1
    [[ "$output" == *"mo optimize"* ]] || return 1
}

@test "linux_optimize_main --dry-run runs all linux maintenance tasks without failure" {
    run env PROJECT_ROOT="$PROJECT_ROOT" MOLE_TEST_NO_AUTH=1 /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/optimize/linux.sh"
linux_optimize_main --dry-run
EOF
    [[ "$status" -eq 0 ]] || return 1
    [[ "$output" == *"Optimize"* ]] || return 1
    [[ "$output" == *"Systemd Journal Maintenance"* ]] || return 1
    [[ "$output" == *"Systemd Service Health"* ]] || return 1
    [[ "$output" == *"Fontconfig Cache Refresh"* ]] || return 1
    [[ "$output" == *"Desktop & MIME Index"* ]] || return 1
    [[ "$output" == *"Orphan Package Audit"* ]] || return 1
    [[ "$output" == *"Storage SSD Trim"* ]] || return 1
    [[ "$output" == *"SQLite Database Optimization"* ]] || return 1
    [[ "$output" == *"Dry Run Complete"* ]] || return 1
}
