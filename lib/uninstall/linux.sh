#!/bin/bash
# Linux/WSL uninstall module. Sourced only when uname -s == Linux.
# Wraps apt/dpkg package removal plus exact-match XDG leftover cleanup.
# Never a second delete path: leftovers route through mole_delete /
# should_protect_path, same as every other Mole deletion.

linux_list_uninstallable_packages() {
    dpkg-query -W -f='${Package}|${Version}|${Status}|${Priority}|${Installed-Size}\n' 2> /dev/null |
        awk -F'|' '
            $3 !~ /install ok installed/ { next }
            $4 == "required" || $4 == "essential" || $4 == "important" || $4 == "standard" { next }
            $1 ~ /^lib[0-9a-z.+-]*$/ { next }
            { print $1 "|" $2 "|" $5 }
        ' | sort -t'|' -k1,1
}

_linux_valid_package_name() {
    [[ "$1" =~ ^[a-z0-9][a-z0-9+.-]*$ ]]
}

linux_uninstall_package() {
    local pkgname="$1"

    if ! _linux_valid_package_name "$pkgname"; then
        echo "Error: invalid package name: $pkgname" >&2
        return 1
    fi

    if [[ "${MOLE_DRY_RUN:-0}" == "1" ]]; then
        echo "  would run: apt-get remove -y $pkgname"
        return 0
    fi

    local -a sudo_prefix=()
    if [[ "${MOLE_TEST_NO_AUTH:-0}" != "1" && "${MOLE_TEST_MODE:-0}" != "1" ]]; then
        sudo -v
        sudo_prefix=(sudo)
    fi

    if run_with_timeout "$MOLE_TIMEOUT_PKG_CLEANUP_SEC" "${sudo_prefix[@]}" apt-get remove -y "$pkgname"; then
        return 0
    fi
    echo "Error: apt-get remove failed for $pkgname" >&2
    return 1
}

linux_clean_package_leftovers() {
    local pkgname="$1"
    local candidate

    for candidate in \
        "$HOME/.config/$pkgname" \
        "$HOME/.cache/$pkgname" \
        "$HOME/.local/share/$pkgname"; do
        [[ -e "$candidate" ]] || continue
        should_protect_path "$candidate" && continue
        mole_delete "$candidate"
    done
    return 0
}

_linux_uninstall_require_apt() {
    if ! command -v apt-get > /dev/null 2>&1 || ! command -v dpkg-query > /dev/null 2>&1; then
        echo "Error: mole uninstall is not supported on this system (apt-get/dpkg-query not found)." >&2
        return 1
    fi
    return 0
}

_linux_print_package_table() {
    linux_list_uninstallable_packages | while IFS='|' read -r name version size_kb; do
        printf '%s  %s  %sK\n' "$name" "$version" "$size_kb"
    done
}

_linux_print_package_json() {
    local first=true
    echo -n "["
    while IFS='|' read -r name version size_kb; do
        [[ -z "$name" ]] && continue
        [[ "$first" == "true" ]] || echo -n ","
        first=false
        printf '{"name":"%s","version":"%s","size_kb":%s}' "$name" "$version" "$size_kb"
    done < <(linux_list_uninstallable_packages)
    echo "]"
}

_linux_uninstall_one() {
    local pkgname="$1"
    if linux_uninstall_package "$pkgname"; then
        linux_clean_package_leftovers "$pkgname"
        return 0
    fi
    return 1
}

_linux_uninstall_interactive() {
    local -a names=()
    local -a menu_items=()
    local name version size_kb

    while IFS='|' read -r name version size_kb; do
        [[ -z "$name" ]] && continue
        names+=("$name")
        menu_items+=("$name ($version, ${size_kb}K)")
    done < <(linux_list_uninstallable_packages)

    if [[ ${#names[@]} -eq 0 ]]; then
        echo "No packages available to uninstall." >&2
        return 1
    fi

    MOLE_SELECTION_RESULT=""
    paginated_multi_select "Select packages to uninstall" "${menu_items[@]}"
    local menu_rc=$?

    if [[ $menu_rc -ne 0 || -z "$MOLE_SELECTION_RESULT" ]]; then
        echo "No packages selected" >&2
        return 1
    fi

    local -a selected_indices=()
    IFS=',' read -r -a selected_indices <<< "$MOLE_SELECTION_RESULT"

    local overall_rc=0
    local idx
    for idx in "${selected_indices[@]}"; do
        [[ -z "$idx" ]] && continue
        _linux_uninstall_one "${names[$idx]}" || overall_rc=1
    done
    return "$overall_rc"
}

linux_uninstall_main() {
    _linux_uninstall_require_apt || return 1

    if [[ $# -eq 0 ]]; then
        _linux_uninstall_interactive
        return $?
    fi

    case "$1" in
        --list)
            _linux_print_package_table
            return 0
            ;;
        --json)
            _linux_print_package_json
            return 0
            ;;
    esac

    local overall_rc=0
    local pkgname
    for pkgname in "$@"; do
        _linux_uninstall_one "$pkgname" || overall_rc=1
    done
    return "$overall_rc"
}
