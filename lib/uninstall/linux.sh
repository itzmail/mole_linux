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
