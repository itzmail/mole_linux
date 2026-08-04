#!/usr/bin/env bats

setup_file() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    export PROJECT_ROOT
}

@test "linux_list_uninstallable_packages includes a normal manually-installed package" {
    run env PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/uninstall/linux.sh"
dpkg-query() {
    cat <<'FIXTURE'
firefox|120.0|install ok installed|optional|350000
FIXTURE
}
linux_list_uninstallable_packages
EOF
    [[ "$status" -eq 0 ]] || return 1
    [[ "$output" == "firefox|120.0|350000" ]] || return 1
}

@test "linux_list_uninstallable_packages excludes essential/required/important/standard priority packages" {
    run env PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/uninstall/linux.sh"
dpkg-query() {
    cat <<'FIXTURE'
bash|5.2|install ok installed|required|8000
coreutils|9.4|install ok installed|essential|17000
apt|2.7|install ok installed|important|4000
util-linux|2.39|install ok installed|standard|5000
firefox|120.0|install ok installed|optional|350000
FIXTURE
}
linux_list_uninstallable_packages
EOF
    [[ "$status" -eq 0 ]] || return 1
    [[ "$output" == "firefox|120.0|350000" ]] || return 1
}

@test "linux_list_uninstallable_packages excludes library packages" {
    run env PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/uninstall/linux.sh"
dpkg-query() {
    cat <<'FIXTURE'
libc6|2.37|install ok installed|optional|12000
libssl3|3.0.11|install ok installed|optional|6000
firefox|120.0|install ok installed|optional|350000
FIXTURE
}
linux_list_uninstallable_packages
EOF
    [[ "$status" -eq 0 ]] || return 1
    [[ "$output" == "firefox|120.0|350000" ]] || return 1
}

@test "linux_list_uninstallable_packages excludes non-installed packages" {
    run env PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/uninstall/linux.sh"
dpkg-query() {
    cat <<'FIXTURE'
oldpkg|1.0|deinstall ok config-files|optional|0
firefox|120.0|install ok installed|optional|350000
FIXTURE
}
linux_list_uninstallable_packages
EOF
    [[ "$status" -eq 0 ]] || return 1
    [[ "$output" == "firefox|120.0|350000" ]] || return 1
}

@test "linux_list_uninstallable_packages sorts by name" {
    run env PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/uninstall/linux.sh"
dpkg-query() {
    cat <<'FIXTURE'
zsh|5.9|install ok installed|optional|3000
ansible|8.5|install ok installed|optional|20000
FIXTURE
}
linux_list_uninstallable_packages
EOF
    [[ "$status" -eq 0 ]] || return 1
    local expected
    expected=$'ansible|8.5|20000\nzsh|5.9|3000'
    [[ "$output" == "$expected" ]] || return 1
}
