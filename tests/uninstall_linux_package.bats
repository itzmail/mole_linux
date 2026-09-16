#!/usr/bin/env bats

setup_file() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    export PROJECT_ROOT
}

@test "linux_uninstall_package rejects an invalid package name before running any command" {
    run env PROJECT_ROOT="$PROJECT_ROOT" MOLE_TEST_NO_AUTH=1 /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/uninstall/linux.sh"
_linux_detect_pkg_manager() { echo "apt"; }
apt-get() { echo "APT-GET CALLED: $*"; return 0; }
sudo() { echo "SUDO CALLED: $*"; "$@"; }
linux_uninstall_package '; rm -rf /'
EOF
    [[ "$status" -ne 0 ]] || return 1
    [[ "$output" != *"APT-GET CALLED"* ]] || return 1
    [[ "$output" != *"SUDO CALLED"* ]] || return 1
}

@test "linux_uninstall_package dry-run prints without executing apt-get" {
    run env PROJECT_ROOT="$PROJECT_ROOT" MOLE_TEST_NO_AUTH=1 MOLE_DRY_RUN=1 /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/uninstall/linux.sh"
_linux_detect_pkg_manager() { echo "apt"; }
apt-get() { echo "APT-GET CALLED: $*"; return 0; }
run_with_timeout() { shift; "$@"; }
linux_uninstall_package "firefox"
EOF
    [[ "$status" -eq 0 ]] || return 1
    [[ "$output" == *"would run: apt-get remove -y firefox"* ]] || return 1
    [[ "$output" != *"APT-GET CALLED"* ]] || return 1
}

@test "linux_uninstall_package runs apt-get remove on a real run" {
    run env PROJECT_ROOT="$PROJECT_ROOT" MOLE_TEST_NO_AUTH=1 /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/uninstall/linux.sh"
_linux_detect_pkg_manager() { echo "apt"; }
apt-get() { echo "APT-GET CALLED: $*"; return 0; }
run_with_timeout() { shift; "$@"; }
linux_uninstall_package "firefox"
EOF
    [[ "$status" -eq 0 ]] || return 1
    [[ "$output" == *"APT-GET CALLED: remove -y firefox"* ]] || return 1
}

@test "linux_uninstall_package dry-run prints without executing pacman" {
    run env PROJECT_ROOT="$PROJECT_ROOT" MOLE_TEST_NO_AUTH=1 MOLE_DRY_RUN=1 /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/uninstall/linux.sh"
_linux_detect_pkg_manager() { echo "pacman"; }
pacman() { echo "PACMAN CALLED: $*"; return 0; }
run_with_timeout() { shift; "$@"; }
linux_uninstall_package "firefox"
EOF
    [[ "$status" -eq 0 ]] || return 1
    [[ "$output" == *"would run: pacman -Rns --noconfirm firefox"* ]] || return 1
    [[ "$output" != *"PACMAN CALLED"* ]] || return 1
}

@test "linux_uninstall_package returns non-zero and does not crash the batch when apt-get fails" {
    run env PROJECT_ROOT="$PROJECT_ROOT" MOLE_TEST_NO_AUTH=1 /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/uninstall/linux.sh"
_linux_detect_pkg_manager() { echo "apt"; }
apt-get() { echo "APT-GET CALLED: $*"; return 1; }
run_with_timeout() { shift; "$@"; }
linux_uninstall_package "firefox" || echo "RETURNED_NONZERO"
EOF
    [[ "$status" -eq 0 ]] || return 1
    [[ "$output" == *"RETURNED_NONZERO"* ]] || return 1
}

@test "linux_uninstall_package skips sudo -v under MOLE_TEST_NO_AUTH" {
    run env PROJECT_ROOT="$PROJECT_ROOT" MOLE_TEST_NO_AUTH=1 /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/uninstall/linux.sh"
_linux_detect_pkg_manager() { echo "apt"; }
apt-get() { return 0; }
run_with_timeout() { shift; "$@"; }
sudo() { echo "SUDO -v CALLED"; return 0; }
linux_uninstall_package "firefox"
EOF
    [[ "$status" -eq 0 ]] || return 1
    [[ "$output" != *"SUDO -v CALLED"* ]] || return 1
}

@test "linux_uninstall_package removes local webapp via mole_delete" {
    run env PROJECT_ROOT="$PROJECT_ROOT" MOLE_TEST_NO_AUTH=1 /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/uninstall/linux.sh"
TEST_DIR="$(mktemp -d)"
export HOME="$TEST_DIR"
mkdir -p "$TEST_DIR/.local/share/applications"
touch "$TEST_DIR/.local/share/applications/Discord.desktop"
mole_delete() { echo "MOLE_DELETED:$1"; rm -f "$1"; }
linux_uninstall_package "webapp:Discord.desktop"
[[ ! -f "$TEST_DIR/.local/share/applications/Discord.desktop" ]] || exit 1
rm -rf "$TEST_DIR"
EOF
    [[ "$status" -eq 0 ]] || return 1
    [[ "$output" == *"MOLE_DELETED:"*"Discord.desktop"* ]] || return 1
}

@test "linux_uninstall_package dry-run for webapp prints without deleting" {
    run env PROJECT_ROOT="$PROJECT_ROOT" MOLE_TEST_NO_AUTH=1 MOLE_DRY_RUN=1 /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/uninstall/linux.sh"
TEST_DIR="$(mktemp -d)"
export HOME="$TEST_DIR"
mkdir -p "$TEST_DIR/.local/share/applications"
touch "$TEST_DIR/.local/share/applications/Discord.desktop"
mole_delete() { echo "MOLE_DELETED:$1"; }
linux_uninstall_package "Discord"
[[ -f "$TEST_DIR/.local/share/applications/Discord.desktop" ]] || exit 1
rm -rf "$TEST_DIR"
EOF
    [[ "$status" -eq 0 ]] || return 1
    [[ "$output" == *"would remove webapp:"*"Discord.desktop"* ]] || return 1
    [[ "$output" != *"MOLE_DELETED"* ]] || return 1
}
