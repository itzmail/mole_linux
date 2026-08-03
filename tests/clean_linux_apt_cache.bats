#!/usr/bin/env bats

setup_file() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    export PROJECT_ROOT
}

@test "clean_linux_apt_cache cleans apt archives via clean_tool_cache when apt-get present" {
    run env PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/linux.sh"
clean_tool_cache() { echo "clean_tool_cache:$1"; }
note_activity() { :; }
apt-get() { :; }
command() {
    if [[ "$1" == "-v" && "$2" == "apt-get" ]]; then
        return 0
    fi
    builtin command "$@"
}
clean_linux_apt_cache
EOF
    [[ "$status" -eq 0 ]] || return 1
    [[ "$output" == *"clean_tool_cache:apt archives"* ]] || return 1
}

@test "clean_linux_apt_cache is a no-op when apt-get is absent" {
    run env PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/linux.sh"
clean_tool_cache() { echo "clean_tool_cache:$1"; }
note_activity() { :; }
command() {
    if [[ "$1" == "-v" && "$2" == "apt-get" ]]; then
        return 1
    fi
    builtin command "$@"
}
clean_linux_apt_cache
EOF
    [[ "$status" -eq 0 ]] || return 1
    [[ "$output" != *"clean_tool_cache"* ]] || return 1
}
