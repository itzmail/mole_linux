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
