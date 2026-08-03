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
}
