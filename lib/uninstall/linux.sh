#!/bin/bash
# Linux/WSL uninstall module. Sourced only when uname -s == Linux.
# Wraps pacman/apt package removal and local webapp uninstallation
# plus exact-match XDG leftover cleanup.
# Never a second delete path: leftovers route through mole_delete /
# should_protect_path, same as every other Mole deletion.

_linux_detect_pkg_manager() {
    if command -v pacman > /dev/null 2>&1; then
        echo "pacman"
    elif command -v apt-get > /dev/null 2>&1 && command -v dpkg-query > /dev/null 2>&1; then
        echo "apt"
    else
        echo "none"
    fi
}

_linux_detect_desktop_packages() {
    if [[ -d /var/lib/pacman/local ]]; then
        grep -l 'usr/share/applications/.*\.desktop' /var/lib/pacman/local/*/files 2>/dev/null | awk -F'/' '{print $(NF-1)}' | sed -E 's/-[0-9]+[^-]*-[0-9]+[^-]*$//'
    elif [[ -d /var/lib/dpkg/info ]]; then
        grep -l 'usr/share/applications/.*\.desktop' /var/lib/dpkg/info/*.list 2>/dev/null | awk -F'/' '{n=$NF; sub(/\.list$/, "", n); sub(/:.*$/, "", n); print n}'
    fi
}

_linux_list_webapps() {
    local f base name
    for f in "$HOME/.local/share/applications"/*.desktop; do
        [[ -f "$f" ]] || continue
        base="$(basename "$f")"
        # Skip if system application with same name exists
        [[ -f "/usr/share/applications/$base" ]] && continue
        name="$(grep -m1 '^Name=' "$f" 2>/dev/null | cut -d= -f2-)"
        [[ -z "$name" ]] && name="${base%.desktop}"
        echo "2|webapp:$base|-|0|Webapp|$name"
    done
}

linux_list_uninstallable_packages() {
    local pm
    pm=$(_linux_detect_pkg_manager)

    local desktop_pkgs
    desktop_pkgs=$(_linux_detect_desktop_packages 2>/dev/null || true)

    case "$pm" in
        pacman)
            {
                _linux_list_webapps 2>/dev/null || true
                pacman -Qie 2> /dev/null | awk -F': ' '
                    /^Name/ { name=$2; sub(/^[ \t]+/, "", name); sub(/[ \t]+$/, "", name) }
                    /^Version/ { ver=$2; sub(/^[ \t]+/, "", ver); sub(/[ \t]+$/, "", ver) }
                    /^Installed Size/ {
                        size_str=$2
                        sub(/^[ \t]+/, "", size_str)
                        split(size_str, arr, " ")
                        val = arr[1]; unit = arr[2]; kb = 0
                        if (unit == "B") kb = int((val + 1023) / 1024)
                        else if (unit == "KiB") kb = int(val + 0.5)
                        else if (unit == "MiB") kb = int(val * 1024 + 0.5)
                        else if (unit == "GiB") kb = int(val * 1024 * 1024 + 0.5)
                        else kb = int(val)
                        if (name ~ /^(base|base-devel|glibc|coreutils|iproute2|iptables|pam|shadow|util-linux)$/) next
                        if (name ~ /^linux(-.*)?$/) next
                        if (name ~ /^systemd(-.*)?$/) next
                        if (name ~ /keyring/) next
                        if (name ~ /^asahi-(audio|bless|alarm-keyring|desktop-meta|fwextract|scripts)$/) next
                        if (name ~ /^alsa-ucm-conf-asahi$/) next
                        if (name != "" && ver != "") {
                            print name "|" ver "|" kb
                        }
                        name = ""; ver = ""
                    }
                ' | awk -F'|' -v dt="$desktop_pkgs" '
                    BEGIN {
                        n = split(dt, arr, "\n")
                        for (i = 1; i <= n; i++) {
                            if (arr[i] != "") dt_map[arr[i]] = 1
                        }
                    }
                    {
                        tag = ($1 in dt_map) ? "Desktop" : "CLI"
                        rank = (tag == "Desktop") ? "1" : "3"
                        print rank "|" $0 "|" tag "|" $1
                    }
                '
            } | sort -t'|' -k1,1n -k6,6 | cut -d'|' -f2-
            ;;
        apt)
            {
                _linux_list_webapps 2>/dev/null || true
                dpkg-query -W -f='${Package}|${Version}|${Status}|${Priority}|${Installed-Size}\n' 2> /dev/null |
                    awk -F'|' '
                        $3 !~ /install ok installed/ { next }
                        $4 == "required" || $4 == "essential" || $4 == "important" || $4 == "standard" { next }
                        $1 ~ /^lib[0-9a-z.+-]*$/ { next }
                        { print $1 "|" $2 "|" $5 }
                    ' | awk -F'|' -v dt="$desktop_pkgs" '
                        BEGIN {
                            n = split(dt, arr, "\n")
                            for (i = 1; i <= n; i++) {
                                if (arr[i] != "") dt_map[arr[i]] = 1
                            }
                        }
                        {
                            tag = ($1 in dt_map) ? "Desktop" : "CLI"
                            rank = (tag == "Desktop") ? "1" : "3"
                            print rank "|" $0 "|" tag "|" $1
                        }
                    '
            } | sort -t'|' -k1,1n -k6,6 | cut -d'|' -f2-
            ;;
        *)
            return 1
            ;;
    esac
}

_linux_valid_package_name() {
    [[ "$1" =~ ^[a-zA-Z0-9][a-zA-Z0-9+._-]*$ ]] || [[ "$1" == webapp:* ]]
}

linux_uninstall_package() {
    local pkgname="$1"

    # Handle webapp removal
    if [[ "$pkgname" == webapp:* ]]; then
        local base="${pkgname#webapp:}"
        local target_file="$HOME/.local/share/applications/$base"
        if [[ ! -f "$target_file" ]]; then
            echo "Error: webapp not found: $base" >&2
            return 1
        fi
        if [[ "${MOLE_DRY_RUN:-0}" == "1" ]]; then
            echo "  would remove webapp: $target_file"
            return 0
        fi
        mole_delete "$target_file"
        return 0
    fi

    # If target matches a local webapp desktop file directly
    if [[ -f "$HOME/.local/share/applications/${pkgname}.desktop" ]]; then
        local target_file="$HOME/.local/share/applications/${pkgname}.desktop"
        if [[ "${MOLE_DRY_RUN:-0}" == "1" ]]; then
            echo "  would remove webapp: $target_file"
            return 0
        fi
        mole_delete "$target_file"
        return 0
    fi

    if ! _linux_valid_package_name "$pkgname"; then
        echo "Error: invalid package name: $pkgname" >&2
        return 1
    fi

    local pm
    pm=$(_linux_detect_pkg_manager)

    local -a remove_cmd=()
    case "$pm" in
        pacman)
            remove_cmd=(pacman -Rns --noconfirm "$pkgname")
            ;;
        apt)
            remove_cmd=(apt-get remove -y "$pkgname")
            ;;
        *)
            echo "Error: no supported package manager found (pacman or apt required)" >&2
            return 1
            ;;
    esac

    if [[ "${MOLE_DRY_RUN:-0}" == "1" ]]; then
        echo "  would run: ${remove_cmd[*]}"
        return 0
    fi

    local -a sudo_prefix=()
    if [[ "${MOLE_TEST_NO_AUTH:-0}" != "1" && "${MOLE_TEST_MODE:-0}" != "1" ]]; then
        sudo -v
        sudo_prefix=(sudo)
    fi

    if run_with_timeout "$MOLE_TIMEOUT_PKG_CLEANUP_SEC" "${sudo_prefix[@]}" "${remove_cmd[@]}"; then
        return 0
    fi
    echo "Error: package removal failed for $pkgname" >&2
    return 1
}

linux_clean_package_leftovers() {
    local pkgname="$1"
    pkgname="${pkgname#webapp:}"
    pkgname="${pkgname%.desktop}"

    local lower_name
    lower_name="$(printf '%s' "$pkgname" | tr '[:upper:]' '[:lower:]')"

    local candidate
    for candidate in \
        "$HOME/.config/$pkgname" \
        "$HOME/.config/$lower_name" \
        "$HOME/.cache/$pkgname" \
        "$HOME/.cache/$lower_name" \
        "$HOME/.local/share/$pkgname" \
        "$HOME/.local/share/$lower_name"; do
        [[ -e "$candidate" ]] || continue
        should_protect_path "$candidate" && continue
        mole_delete "$candidate"
    done
    return 0
}

_linux_uninstall_require_supported_pm() {
    local pm
    pm=$(_linux_detect_pkg_manager)
    if [[ "$pm" == "none" ]]; then
        echo "Error: mole uninstall is not supported on this system (pacman or apt-get/dpkg-query not found)." >&2
        return 1
    fi
    return 0
}

_linux_uninstall_require_apt() {
    _linux_uninstall_require_supported_pm
}

_linux_print_package_table() {
    local filter_type="${1:-}"
    while IFS='|' read -r name version size_kb tag display_name; do
        [[ -z "$name" ]] && continue
        tag="${tag:-CLI}"
        display_name="${display_name:-$name}"
        if [[ -n "$filter_type" && "$tag" != "$filter_type" ]]; then
            continue
        fi
        printf '%-10s  %-28s  %-14s  %sK\n' "[$tag]" "$display_name" "$version" "$size_kb"
    done < <(linux_list_uninstallable_packages)
}

_linux_print_package_json() {
    local filter_type="${1:-}"
    local first=true
    echo -n "["
    while IFS='|' read -r name version size_kb tag display_name; do
        [[ -z "$name" ]] && continue
        tag="${tag:-CLI}"
        display_name="${display_name:-$name}"
        if [[ -n "$filter_type" && "$tag" != "$filter_type" ]]; then
            continue
        fi
        [[ "$first" == "true" ]] || echo -n ","
        first=false
        printf '{"name":"%s","version":"%s","size_kb":%s,"type":"%s","display_name":"%s"}' "$name" "$version" "$size_kb" "$tag" "$display_name"
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
    local filter_type="${1:-}"
    local -a raw_names=()
    local -a menu_items=()
    local name version size_kb tag display_name

    while IFS='|' read -r name version size_kb tag display_name; do
        [[ -z "$name" ]] && continue
        tag="${tag:-CLI}"
        display_name="${display_name:-$name}"
        if [[ -n "$filter_type" && "$tag" != "$filter_type" ]]; then
            continue
        fi
        raw_names+=("$name")

        local size_str
        if [[ "$size_kb" == "0" || "$size_kb" == "-" || -z "$size_kb" ]]; then
            size_str="N/A"
        elif [[ "$size_kb" -ge 1048576 ]]; then
            size_str="$((size_kb / 1048576))G"
        elif [[ "$size_kb" -ge 1024 ]]; then
            size_str="$((size_kb / 1024))M"
        else
            size_str="${size_kb}K"
        fi

        if [[ "$tag" == "Webapp" ]]; then
            menu_items+=("[Webapp]  $display_name (Web App)")
        elif [[ "$tag" == "Desktop" ]]; then
            menu_items+=("[Desktop] $display_name ($version, $size_str)")
        else
            menu_items+=("[CLI]     $display_name ($version, $size_str)")
        fi
    done < <(linux_list_uninstallable_packages)

    if [[ ${#raw_names[@]} -eq 0 ]]; then
        echo "No packages available to uninstall." >&2
        return 1
    fi

    export MOLE_MENU_FILTER_NAMES="$(printf '%s\n' "${raw_names[@]}")"
    export MOLE_MENU_IGNORE_INITIAL_ENTER=1

    MOLE_SELECTION_RESULT=""
    paginated_multi_select "Select items to uninstall" "${menu_items[@]}"
    local menu_rc=$?

    unset MOLE_MENU_FILTER_NAMES MOLE_MENU_IGNORE_INITIAL_ENTER

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
        _linux_uninstall_one "${raw_names[$idx]}" || overall_rc=1
    done
    return "$overall_rc"
}

_linux_uninstall_usage() {
    cat <<'EOF'
Mole - Linux Application & Package Uninstaller

Usage:
  mo uninstall [options] [app/package...]

Options:
  --list          List uninstallable applications and packages
  --json          Output candidates in JSON format
  --desktop       Filter candidates to desktop applications
  --cli           Filter candidates to command-line packages
  --webapp        Filter candidates to local webapps
  -n, --dry-run   Show removal steps without deleting anything
  -h, --help      Show this help message
EOF
}

linux_uninstall_main() {
    _linux_uninstall_require_supported_pm || return 1

    local -a targets=()
    local filter_type=""
    local show_list=false
    local show_json=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run|-n)
                export MOLE_DRY_RUN=1
                shift
                ;;
            --help|-h)
                _linux_uninstall_usage
                return 0
                ;;
            --list)
                show_list=true
                shift
                ;;
            --json)
                show_json=true
                shift
                ;;
            --desktop)
                filter_type="Desktop"
                shift
                ;;
            --cli)
                filter_type="CLI"
                shift
                ;;
            --webapp)
                filter_type="Webapp"
                shift
                ;;
            --)
                shift
                targets+=("$@")
                break
                ;;
            -*)
                echo "Error: unknown option: $1" >&2
                return 1
                ;;
            *)
                targets+=("$1")
                shift
                ;;
        esac
    done

    if [[ "$show_list" == "true" ]]; then
        _linux_print_package_table "$filter_type"
        return 0
    fi

    if [[ "$show_json" == "true" ]]; then
        _linux_print_package_json "$filter_type"
        return 0
    fi

    if [[ ${#targets[@]} -eq 0 ]]; then
        _linux_uninstall_interactive "$filter_type"
        return $?
    fi

    local overall_rc=0
    local target
    for target in "${targets[@]}"; do
        _linux_uninstall_one "$target" || overall_rc=1
    done
    return "$overall_rc"
}
