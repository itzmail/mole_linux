#!/bin/bash
# Linux/WSL cleanup module. Sourced only when uname -s == Linux.
# Mirrors the safety plumbing every Darwin lib/clean/*.sh module uses:
# safe_clean for file-level targets, clean_tool_cache for CLI-delegated
# targets. No second delete path is introduced.

# Dev/package-manager caches, systemd journal vacuum, and a Docker
# review-only notice. Grouped into one entry point because none of these
# has a dedicated numbered section of its own on macOS either.
clean_linux_dev_caches() {
    safe_clean ~/.npm/* "npm cache"
    safe_clean ~/.cache/yarn/* "Yarn cache"
    safe_clean ~/.local/share/pnpm/* "pnpm store"
    safe_clean ~/.cache/pip/* "pip cache"

    if command -v journalctl > /dev/null 2>&1; then
        clean_tool_cache "systemd journal" "" run_with_timeout "$MOLE_TIMEOUT_PKG_CLEANUP_SEC" journalctl --vacuum-time=7d
    fi

    if command -v docker > /dev/null 2>&1; then
        note_activity
        echo -e "  ${GRAY}${ICON_WARNING}${NC} Docker unused data · skipped (review: docker system df)"
    fi
}

# Generic per-browser cache cleanup for Chrome/Chromium/Firefox on Linux.
# Not the macOS "old version" cleanup — pure runtime cache, always
# rebuildable.
clean_linux_browser_caches() {
    safe_clean ~/.cache/google-chrome/* "Chrome cache"
    safe_clean ~/.cache/chromium/* "Chromium cache"
    safe_clean ~/.cache/mozilla/firefox/*/cache2/* "Firefox cache"
}
