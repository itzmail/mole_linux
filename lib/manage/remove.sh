#!/bin/bash
# Mole self-removal: Homebrew formula, manual binaries, config/cache/logs.
# Extracted from the `mole` dispatcher, which now only routes.

set -euo pipefail

if [[ -n "${MOLE_MANAGE_REMOVE_LOADED:-}" ]]; then
    return 0
fi
readonly MOLE_MANAGE_REMOVE_LOADED=1

# Where this install keeps its config, which `install.sh --config` can move.
#
# The launcher carries the answer: install.sh rewrites `SCRIPT_DIR=` in it to
# the chosen directory, and the `mole` dispatcher sources this file with that
# value in scope. update.sh already resolves it exactly this way; remove.sh
# used to assume ~/.config/mole instead, so a relocated install had its real
# settings left behind while the default path, if it happened to exist, was
# trashed in their place (tw93/Mole#1589).
#
# A relocated directory is adopted only when it is unmistakably ours; anything
# else falls back to the default, which is the one path that cannot belong to
# someone else. Deciding here rather than at the sink means we never name a
# directory we would then refuse to touch.
_remove_config_dir() {
    local candidate="${MOLE_CONFIG_DIR:-${SCRIPT_DIR:-}}"
    candidate="${candidate%/}"
    if [[ -n "$candidate" ]] && [[ -f "$candidate/lib/core/common.sh" ]] &&
        _remove_config_dir_is_exclusively_mole "$candidate"; then
        printf '%s\n' "$candidate"
        return 0
    fi
    printf '%s\n' "${HOME%/}/.config/mole"
}

# Whether every top-level entry in the config directory is one Mole put there.
#
# Holding Mole's own library is NOT proof the directory is Mole's to remove:
# `--config ~/Documents` makes install.sh create lib/core/common.sh inside it,
# and claiming ownership from that marker would trash everything beside it.
# The default ~/.config/mole cannot be anything else, so it is exempt; any
# other location has to earn it by containing nothing we did not install.
_remove_config_dir_is_exclusively_mole() {
    local config_dir="${1%/}"
    [[ "$config_dir" != "${HOME%/}/.config/mole" ]] || return 0

    local entry base
    for entry in "$config_dir"/* "$config_dir"/.*; do
        [[ -e "$entry" || -L "$entry" ]] || continue
        base="${entry##*/}"
        case "$base" in
            # Installed by install.sh.
            . | .. | bin | lib | README.md | LICENSE | install.sh | install_channel) ;;
            # Runtime state Mole itself writes.
            .helper_install_incomplete | whitelist | whitelist_checks) ;;
            whitelist_optimize | purge_paths) ;;
            # A staging file from an interrupted install or update.
            install_channel.* | .*-go.*) ;;
            *) return 1 ;;
        esac
    done
    return 0
}

# Remove flow (Homebrew + manual + config/cache).
remove_mole() {
    local dry_run_mode="${1:-false}"
    local remove_config_dir
    local test_mode=false
    if [[ "${MOLE_TEST_MODE:-0}" == "1" ]]; then
        test_mode=true
    fi

    if [[ -t 1 ]]; then
        start_inline_spinner "Detecting Mole installations..."
    else
        echo "Detecting installations..."
    fi

    local is_homebrew=false
    local brew_cmd=""
    local brew_has_mole="false"
    local -a manual_installs=()
    local -a alias_installs=()

    if [[ "$test_mode" != "true" ]]; then
        if command -v brew > /dev/null 2>&1; then
            brew_cmd="brew"
        elif [[ -x "/opt/homebrew/bin/brew" ]]; then
            brew_cmd="/opt/homebrew/bin/brew"
        elif [[ -x "/usr/local/bin/brew" ]]; then
            brew_cmd="/usr/local/bin/brew"
        fi

        if [[ -n "$brew_cmd" ]]; then
            if brew_mole_formula_installed "$brew_cmd"; then
                brew_has_mole="true"
            fi
        fi

        if [[ "$brew_has_mole" == "true" ]] || is_homebrew_install; then
            is_homebrew=true
        fi
    fi

    local found_mole
    found_mole=""
    if [[ "$test_mode" != "true" ]]; then
        found_mole=$(command -v mole 2> /dev/null || true)
        if [[ -n "$found_mole" && -f "$found_mole" ]]; then
            if [[ ! -L "$found_mole" ]] || ! readlink "$found_mole" | grep -q "Cellar/mole"; then
                manual_installs+=("$found_mole")
            fi
        fi
    fi

    local -a fallback_paths=()
    if [[ "$test_mode" == "true" ]]; then
        fallback_paths=("$HOME/.local/bin/mole")
    else
        fallback_paths=(
            "/usr/local/bin/mole"
            "$HOME/.local/bin/mole"
            "/opt/local/bin/mole"
        )
    fi

    for path in "${fallback_paths[@]}"; do
        if [[ -f "$path" && "$path" != "$found_mole" ]]; then
            if [[ ! -L "$path" ]] || ! readlink "$path" | grep -q "Cellar/mole"; then
                manual_installs+=("$path")
            fi
        fi
    done

    local found_mo
    found_mo=""
    if [[ "$test_mode" != "true" ]]; then
        found_mo=$(command -v mo 2> /dev/null || true)
        if [[ -n "$found_mo" && -f "$found_mo" ]]; then
            if [[ ! -L "$found_mo" ]] || ! readlink "$found_mo" | grep -q "Cellar/mole"; then
                alias_installs+=("$found_mo")
            fi
        fi
    fi

    local -a alias_fallback=()
    if [[ "$test_mode" == "true" ]]; then
        alias_fallback=("$HOME/.local/bin/mo")
    else
        alias_fallback=(
            "/usr/local/bin/mo"
            "$HOME/.local/bin/mo"
            "/opt/local/bin/mo"
        )
    fi

    for alias in "${alias_fallback[@]}"; do
        if [[ -f "$alias" && "$alias" != "$found_mo" ]]; then
            if [[ ! -L "$alias" ]] || ! readlink "$alias" | grep -q "Cellar/mole"; then
                alias_installs+=("$alias")
            fi
        fi
    done

    if [[ -t 1 ]]; then
        stop_inline_spinner
    fi

    printf '\n'

    remove_config_dir="$(_remove_config_dir)"

    local manual_count=${#manual_installs[@]}
    local alias_count=${#alias_installs[@]}
    if [[ "$is_homebrew" == "false" && ${manual_count:-0} -eq 0 && ${alias_count:-0} -eq 0 ]]; then
        printf '%s\n\n' "${YELLOW}No Mole installation detected${NC}"
        exit 0
    fi

    # Dry-run mode: show preview and exit without confirmation
    if [[ "$dry_run_mode" == "true" ]]; then
        echo -e "${YELLOW}${ICON_DRY_RUN} DRY RUN MODE${NC}, no files will be removed"
        echo ""
        echo -e "${YELLOW}Remove Mole${NC}, would delete the following:"
        if [[ "$is_homebrew" == "true" ]]; then
            echo -e "  ${GRAY}${ICON_LIST} Would run: brew uninstall --force mole${NC}"
        fi
        if [[ ${manual_count:-0} -gt 0 ]]; then
            for install in "${manual_installs[@]}"; do
                [[ -f "$install" ]] && echo -e "  ${GRAY}${ICON_LIST} Would remove: ${install}${NC}"
            done
        fi
        if [[ ${alias_count:-0} -gt 0 ]]; then
            for alias in "${alias_installs[@]}"; do
                [[ -f "$alias" ]] && echo -e "  ${GRAY}${ICON_LIST} Would remove: ${alias}${NC}"
            done
        fi
        [[ -d "$HOME/.cache/mole" ]] && echo -e "  ${GRAY}${ICON_LIST} Would remove: $HOME/.cache/mole${NC}"
        [[ -d "$remove_config_dir" ]] && echo -e "  ${GRAY}${ICON_LIST} Would move to Trash: $remove_config_dir${NC}"
        [[ -d "$HOME/Library/Logs/mole" ]] && echo -e "  ${GRAY}${ICON_LIST} Would remove: $HOME/Library/Logs/mole${NC}"

        printf '\n%s\n\n' "${GREEN}${ICON_SUCCESS}${NC} Dry run complete, no changes made"
        exit 0
    fi

    echo -e "${YELLOW}Remove Mole${NC}, will delete the following:"
    if [[ "$is_homebrew" == "true" ]]; then
        echo "  ${ICON_LIST} Mole via Homebrew"
    fi
    for install in ${manual_installs[@]+"${manual_installs[@]}"} ${alias_installs[@]+"${alias_installs[@]}"}; do
        echo "  ${ICON_LIST} $install"
    done
    local remove_config_display="$remove_config_dir"
    [[ "$remove_config_display" == "$HOME/"* ]] && remove_config_display="~${remove_config_display#"$HOME"}"
    echo "  ${ICON_LIST} $remove_config_display (to Trash)"
    echo "  ${ICON_LIST} ~/.cache/mole"
    echo "  ${ICON_LIST} ~/Library/Logs/mole"
    echo -ne "${PURPLE}${ICON_ARROW}${NC} Press ${GREEN}Enter${NC} to confirm, ${GRAY}ESC${NC} to cancel: "

    IFS= read -r -s -n1 key || key=""
    drain_pending_input # Clean up any escape sequence remnants
    case "$key" in
        $'\e')
            exit 0
            ;;
        "" | $'\n' | $'\r')
            printf "\r\033[K" # Clear the prompt line
            ;;
        *)
            exit 0
            ;;
    esac

    local has_error=false
    if [[ "$is_homebrew" == "true" ]]; then
        if [[ -z "$brew_cmd" ]]; then
            log_error "Homebrew command not found. Please ensure Homebrew is installed and in your PATH."
            log_warning "Manual step: brew uninstall --force mole"
            exit 1
        fi

        log_info "Attempting to uninstall Mole via Homebrew..."
        local brew_uninstall_output
        if ! brew_uninstall_output=$("$brew_cmd" uninstall --force mole 2>&1); then
            has_error=true
            log_error "Homebrew uninstallation failed:"
            printf "%s\n" "$brew_uninstall_output" | sed "s/^/${RED}  | ${NC}/" >&2
            log_warning "Manual step: ${YELLOW}brew uninstall --force mole${NC}"
            echo "" # Add a blank line for readability
        else
            log_success "Mole uninstalled via Homebrew."
        fi
    fi
    if [[ ${manual_count:-0} -gt 0 ]]; then
        for install in "${manual_installs[@]}"; do
            if [[ -f "$install" ]]; then
                if [[ ! -w "$(dirname "$install")" ]]; then
                    if [[ "${MOLE_TEST_MODE:-0}" == "1" || "${MOLE_TEST_NO_AUTH:-0}" == "1" ]] || ! sudo rm -f "$install" 2> /dev/null; then
                        has_error=true
                    fi
                else
                    if ! rm -f "$install" 2> /dev/null; then
                        has_error=true
                    fi
                fi
            fi
        done
    fi
    if [[ ${alias_count:-0} -gt 0 ]]; then
        for alias in "${alias_installs[@]}"; do
            if [[ -f "$alias" ]]; then
                if [[ ! -w "$(dirname "$alias")" ]]; then
                    if [[ "${MOLE_TEST_MODE:-0}" == "1" || "${MOLE_TEST_NO_AUTH:-0}" == "1" ]] || ! sudo rm -f "$alias" 2> /dev/null; then
                        has_error=true
                    fi
                else
                    if ! rm -f "$alias" 2> /dev/null; then
                        has_error=true
                    fi
                fi
            fi
        done
    fi
    if [[ -d "$HOME/.cache/mole" ]]; then
        rm -rf "$HOME/.cache/mole" 2> /dev/null || true # SAFE: hardcoded Mole-owned dir, -d guarded
    fi
    if [[ -d "$remove_config_dir" ]]; then
        # The config dir holds user-authored state (whitelist, purge config),
        # which is the one thing here a reinstall cannot rebuild. Move it to
        # Trash so it stays recoverable (#1346); cache and logs around it are
        # rebuildable and stay permanent removals. On failure leave it in
        # place rather than falling back to deletion.
        local config_trash="$HOME/.Trash/mole-config"
        local config_trash_n=1
        while [[ -e "$config_trash" || -L "$config_trash" ]]; do
            config_trash="$HOME/.Trash/mole-config-$config_trash_n"
            config_trash_n=$((config_trash_n + 1))
        done
        if ! mkdir -p "$HOME/.Trash" 2> /dev/null ||
            ! mv -f "$remove_config_dir" "$config_trash" 2> /dev/null; then
            has_error=true
            log_warning "Could not move $remove_config_dir to Trash; left in place"
        fi
    fi
    if [[ -d "$HOME/Library/Logs/mole" ]]; then
        rm -rf "$HOME/Library/Logs/mole" 2> /dev/null || true # SAFE: hardcoded Mole-owned dir, -d guarded
    fi

    local final_message
    if [[ "$has_error" == "true" ]]; then
        final_message="${YELLOW}${ICON_ERROR} Mole uninstalled with some errors, thank you for using Mole!${NC}"
    else
        final_message="${GREEN}${ICON_SUCCESS} Mole uninstalled successfully, thank you for using Mole!${NC}"
    fi
    printf '\n%s\n\n' "$final_message"

    exit 0
}
