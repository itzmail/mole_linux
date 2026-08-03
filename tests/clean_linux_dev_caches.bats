#!/usr/bin/env bats

setup_file() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    export PROJECT_ROOT

    ORIGINAL_HOME="${HOME:-}"
    export ORIGINAL_HOME

    HOME="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp-linux-dev-caches.XXXXXX")"
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

@test "clean_linux_dev_caches cleans npm cache when present" {
    mkdir -p "$HOME/.npm"
    touch "$HOME/.npm/some-cache-file"

    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/linux.sh"
safe_clean() { echo "safe_clean:${*: -1}"; }
clean_tool_cache() { echo "clean_tool_cache:$1"; }
note_activity() { :; }
clean_linux_dev_caches
EOF
    [[ "$status" -eq 0 ]] || return 1
    [[ "$output" == *"safe_clean:npm cache"* ]] || return 1
}

@test "clean_linux_dev_caches cleans yarn cache when present" {
    mkdir -p "$HOME/.cache/yarn"
    touch "$HOME/.cache/yarn/some-cache-file"

    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/linux.sh"
safe_clean() { echo "safe_clean:${*: -1}"; }
clean_tool_cache() { echo "clean_tool_cache:$1"; }
note_activity() { :; }
clean_linux_dev_caches
EOF
    [[ "$status" -eq 0 ]] || return 1
    [[ "$output" == *"safe_clean:Yarn cache"* ]] || return 1
}

@test "clean_linux_dev_caches cleans pnpm store when present" {
    mkdir -p "$HOME/.local/share/pnpm"
    touch "$HOME/.local/share/pnpm/some-store-file"

    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/linux.sh"
safe_clean() { echo "safe_clean:${*: -1}"; }
clean_tool_cache() { echo "clean_tool_cache:$1"; }
note_activity() { :; }
clean_linux_dev_caches
EOF
    [[ "$status" -eq 0 ]] || return 1
    [[ "$output" == *"safe_clean:pnpm store"* ]] || return 1
}

@test "clean_linux_dev_caches cleans pip cache when present" {
    mkdir -p "$HOME/.cache/pip"
    touch "$HOME/.cache/pip/some-cache-file"

    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/linux.sh"
safe_clean() { echo "safe_clean:${*: -1}"; }
clean_tool_cache() { echo "clean_tool_cache:$1"; }
note_activity() { :; }
clean_linux_dev_caches
EOF
    [[ "$status" -eq 0 ]] || return 1
    [[ "$output" == *"safe_clean:pip cache"* ]] || return 1
}

@test "clean_linux_dev_caches skips absent caches without error" {
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/linux.sh"
safe_clean() { echo "safe_clean:${*: -1}"; }
clean_tool_cache() { echo "clean_tool_cache:$1"; }
note_activity() { :; }
rm -rf "$HOME/.npm" "$HOME/.cache/yarn" "$HOME/.local/share/pnpm" "$HOME/.cache/pip"
clean_linux_dev_caches
EOF
    [[ "$status" -eq 0 ]] || return 1
}
