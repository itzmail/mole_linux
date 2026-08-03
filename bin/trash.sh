#!/bin/bash
# Mole - Trash command.
# Manages the XDG Trash on Linux (no Finder to own this on Linux/WSL).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GO_BIN="$SCRIPT_DIR/trash-go"
if [[ -x "$GO_BIN" ]]; then
    exec "$GO_BIN" "$@"
fi

echo "Bundled trash binary not found. Please reinstall Mole or run mo update to restore it." >&2
exit 1
