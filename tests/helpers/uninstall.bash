#!/usr/bin/env bash
# shellcheck shell=bash

# For batch tests whose app inventory is confined to their temporary HOME.
# Keep the production sibling scan and final recheck, but never inspect the
# host's Applications, mounted volumes, or package receipts.
mole_test_isolate_uninstall_inventory() {
    _MOLE_UNINSTALL_LIVE_APP_ROOTS=("$HOME/Applications")
    _MOLE_UNINSTALL_LIVE_VOLUMES_ROOT="$HOME/no-volumes"
    # shellcheck disable=SC2329  # Invoked by the production sibling scan.
    pkg_receipt_nonstandard_app_paths() {
        printf 'RECEIPT_FIXTURE\n' >> "$HOME/inventory.trace"
        return 0
    }
}

# Model an explicit selection of every offered personal-data row, not the default.
mole_test_select_all_uninstall_data() {
    # shellcheck disable=SC2329  # Called by the production preview.
    drain_pending_input() { :; }
    # shellcheck disable=SC2329  # Called by the production data selector.
    paginated_multi_select() {
        local index
        MOLE_SELECTION_RESULT=""
        for ((index = 0; index < $# - 1; index++)); do
            [[ -z "$MOLE_SELECTION_RESULT" ]] || MOLE_SELECTION_RESULT+=,
            MOLE_SELECTION_RESULT+="$index"
        done
        return 0
    }
}
