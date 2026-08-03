#!/usr/bin/env bats

setup_file() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    export PROJECT_ROOT

    ORIGINAL_HOME="${HOME:-}"
    export ORIGINAL_HOME

    HOME="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp-linux-browser-caches.XXXXXX")"
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

@test "clean_linux_browser_caches cleans chrome cache when present" {
    mkdir -p "$HOME/.cache/google-chrome"
    touch "$HOME/.cache/google-chrome/some-cache-file"

    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/linux.sh"
safe_clean() { echo "safe_clean:${*: -1}"; }
note_activity() { :; }
clean_linux_browser_caches
EOF
    [[ "$status" -eq 0 ]] || return 1
    [[ "$output" == *"safe_clean:Chrome cache"* ]] || return 1
}

@test "clean_linux_browser_caches cleans chromium cache when present" {
    mkdir -p "$HOME/.cache/chromium"
    touch "$HOME/.cache/chromium/some-cache-file"

    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/linux.sh"
safe_clean() { echo "safe_clean:${*: -1}"; }
note_activity() { :; }
clean_linux_browser_caches
EOF
    [[ "$status" -eq 0 ]] || return 1
    [[ "$output" == *"safe_clean:Chromium cache"* ]] || return 1
}

@test "clean_linux_browser_caches cleans firefox cache2 dirs when present" {
    mkdir -p "$HOME/.cache/mozilla/firefox/abc123.default/cache2"
    touch "$HOME/.cache/mozilla/firefox/abc123.default/cache2/some-cache-file"

    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/linux.sh"
safe_clean() { echo "safe_clean:${*: -1}"; }
note_activity() { :; }
clean_linux_browser_caches
EOF
    [[ "$status" -eq 0 ]] || return 1
    [[ "$output" == *"safe_clean:Firefox cache"* ]] || return 1
}

@test "clean_linux_browser_caches skips absent browsers without error" {
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/linux.sh"
safe_clean() { echo "safe_clean:${*: -1}"; }
note_activity() { :; }
rm -rf "$HOME/.cache/google-chrome" "$HOME/.cache/chromium" "$HOME/.cache/mozilla"
clean_linux_browser_caches
EOF
    [[ "$status" -eq 0 ]] || return 1
}
