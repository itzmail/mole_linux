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
    safe_clean ~/.cache/yay/* "yay AUR cache"
    safe_clean ~/.cache/paru/* "paru AUR cache"

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

# Linux package cache cleanup (apt, pacman, etc.).
# Only ever called from bin/clean.sh's SYSTEM_CLEAN == true branch.
clean_linux_package_cache() {
    if command -v paccache > /dev/null 2>&1; then
        clean_tool_cache "pacman cache (uninstalled)" "/var/cache/pacman/pkg" run_with_timeout "$MOLE_TIMEOUT_PKG_CLEANUP_SEC" paccache -ruk0
        clean_tool_cache "pacman cache (keep latest 2)" "/var/cache/pacman/pkg" run_with_timeout "$MOLE_TIMEOUT_PKG_CLEANUP_SEC" paccache -rk2
    elif command -v pacman > /dev/null 2>&1; then
        clean_tool_cache "pacman cache" "/var/cache/pacman/pkg" run_with_timeout "$MOLE_TIMEOUT_PKG_CLEANUP_SEC" pacman -Sc --noconfirm
    elif command -v apt-get > /dev/null 2>&1; then
        clean_tool_cache "apt archives" "/var/cache/apt/archives" run_with_timeout "$MOLE_TIMEOUT_PKG_CLEANUP_SEC" apt-get clean
    elif command -v dnf > /dev/null 2>&1; then
        clean_tool_cache "dnf cache" "/var/cache/dnf" run_with_timeout "$MOLE_TIMEOUT_PKG_CLEANUP_SEC" dnf clean all
    fi
}

# Alias for backward compatibility with existing tests
clean_linux_apt_cache() {
    clean_linux_package_cache
}
