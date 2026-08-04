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

    run grep -n 'lib/uninstall/linux.sh\|linux_uninstall_main' "$PROJECT_ROOT/bin/uninstall.sh"
    [[ "$status" -eq 0 ]] || return 1
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

@test "linux_uninstall_main with no args opens the interactive menu and uninstalls the selection" {
    run env PROJECT_ROOT="$PROJECT_ROOT" MOLE_TEST_NO_AUTH=1 MOLE_DRY_RUN=1 /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/uninstall/linux.sh"
command() {
    if [[ "$1" == "-v" ]]; then return 0; fi
    builtin command "$@"
}
linux_list_uninstallable_packages() {
    printf 'ansible|8.5|20000\nfirefox|120.0|350000\n'
}
paginated_multi_select() {
    echo "MENU_CALLED:$1"
    shift
    echo "MENU_ITEMS:$*"
    MOLE_SELECTION_RESULT="1"
    return 0
}
linux_clean_package_leftovers() { echo "LEFTOVERS_CHECKED:$1"; }
linux_uninstall_main
EOF
    [[ "$status" -eq 0 ]] || return 1
    [[ "$output" == *"MENU_CALLED:"* ]] || return 1
    [[ "$output" == *"MENU_ITEMS:"*"firefox"* ]] || return 1
    [[ "$output" == *"would run: apt-get remove -y firefox"* ]] || return 1
    [[ "$output" == *"LEFTOVERS_CHECKED:firefox"* ]] || return 1
}

@test "linux_uninstall_main with no args and no menu selection exits cleanly without uninstalling anything" {
    run env PROJECT_ROOT="$PROJECT_ROOT" MOLE_TEST_NO_AUTH=1 MOLE_DRY_RUN=1 /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/uninstall/linux.sh"
command() {
    if [[ "$1" == "-v" ]]; then return 0; fi
    builtin command "$@"
}
linux_list_uninstallable_packages() { echo "firefox|120.0|350000"; }
paginated_multi_select() {
    MOLE_SELECTION_RESULT=""
    return 1
}
linux_clean_package_leftovers() { echo "LEFTOVERS_CHECKED:$1"; }
linux_uninstall_main
EOF
    [[ "$status" -eq 1 ]] || return 1
    [[ "$output" != *"would run: apt-get remove"* ]] || return 1
    [[ "$output" != *"LEFTOVERS_CHECKED"* ]] || return 1
}

@test "linux_uninstall_main with no args and an empty package list exits with a clear message" {
    run env PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/uninstall/linux.sh"
command() {
    if [[ "$1" == "-v" ]]; then return 0; fi
    builtin command "$@"
}
linux_list_uninstallable_packages() { :; }
linux_uninstall_main
EOF
    [[ "$status" -eq 1 ]] || return 1
    [[ "$output" == *"No packages"* ]] || return 1
}

@test "git diff shows only additions to the macOS branch of bin/uninstall.sh, no deletions" {
    cd "$PROJECT_ROOT"
    run git diff --unified=0 main -- bin/uninstall.sh
    [[ "$status" -eq 0 ]] || return 1
    local removed_non_context_lines
    removed_non_context_lines=$(echo "$output" | grep -c '^-[^-]' || true)
    [[ "$removed_non_context_lines" -eq 0 ]] || return 1
}
