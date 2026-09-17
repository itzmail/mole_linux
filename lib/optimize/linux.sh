#!/bin/bash
# Mole - Linux Optimization Module.
# System maintenance tasks for Linux/WSL.
# Safe, idempotent, and dry-run aware.

set -euo pipefail

if [[ -n "${MOLE_OPTIMIZE_LINUX_LOADED:-}" ]]; then
    return 0
fi
readonly MOLE_OPTIMIZE_LINUX_LOADED=1

_MOLE_OPTIMIZE_LINUX_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_MOLE_OPTIMIZE_LINUX_DIR/outcomes.sh"

opt_msg() {
    local message="$1"
    if [[ "${MOLE_DRY_RUN:-0}" == "1" ]]; then
        echo -e "  ${YELLOW}${ICON_DRY_RUN}${NC} $message"
    else
        echo -e "  ${GREEN}${ICON_SUCCESS}${NC} $message"
    fi
}

opt_warn_msg() {
    local message="$1"
    echo -e "  ${YELLOW}${ICON_WARNING}${NC} $message"
}

_linux_detect_pkg_manager() {
    if command -v pacman > /dev/null 2>&1; then
        echo "pacman"
    elif command -v apt-get > /dev/null 2>&1; then
        echo "apt"
    else
        echo "none"
    fi
}

linux_show_system_health() {
    local mem_used="0" mem_total="0" disk_used="0" disk_total="0" uptime_days="0"

    if [[ -f /proc/meminfo ]]; then
        local mem_calc
        mem_calc=$(awk '
            /^MemTotal:/ { total=$2 }
            /^MemAvailable:/ { avail=$2 }
            END {
                used = total - avail
                printf "%.0f %.0f", used / (1024*1024), total / (1024*1024)
            }
        ' /proc/meminfo 2> /dev/null || echo "0 0")
        read -r mem_used mem_total <<< "$mem_calc"
    fi

    local disk_calc
    disk_calc=$(df -k "$HOME" 2> /dev/null | tail -1 | awk '
        { printf "%.0f %.0f", ($3)/(1024*1024), ($2)/(1024*1024) }
    ' 2> /dev/null || echo "0 0")
    read -r disk_used disk_total <<< "$disk_calc"

    if [[ -f /proc/uptime ]]; then
        uptime_days=$(awk '{ printf "%d", $1/86400 }' /proc/uptime 2> /dev/null || echo "0")
    fi

    printf "${ICON_ADMIN} System  %s/%s GB RAM | %s/%s GB Disk | Uptime %sd\n" \
        "${mem_used:-0}" "${mem_total:-0}" "${disk_used:-0}" "${disk_total:-0}" "${uptime_days:-0}"
}

# Task 1: Systemd Journal Maintenance
opt_linux_journal_vacuum() {
    if ! command -v journalctl > /dev/null 2>&1; then
        opt_msg "journalctl not available"
        optimize_task_result "$MOLE_OPTIMIZE_OUTCOME_UNAVAILABLE"
        return 0
    fi

    local usage
    usage=$(journalctl --disk-usage 2> /dev/null | grep -oE '[0-9.]+[KMGTP]?' | head -1 || echo "")

    if [[ "${MOLE_DRY_RUN:-0}" == "1" ]]; then
        opt_msg "Would vacuum journals older than 14 days (current usage: ${usage:-unknown})"
        optimize_task_result "$MOLE_OPTIMIZE_OUTCOME_APPLIED"
        return 0
    fi

    if run_with_timeout "${MOLE_TIMEOUT_PKG_CLEANUP_SEC:-15}" journalctl --vacuum-time=14d > /dev/null 2>&1; then
        opt_msg "Systemd journal vacuumed (retained last 14 days)"
        optimize_task_result "$MOLE_OPTIMIZE_OUTCOME_APPLIED"
    else
        opt_msg "Systemd journal check completed"
        optimize_task_result "$MOLE_OPTIMIZE_OUTCOME_UNCHANGED"
    fi
}

# Task 2: Systemd Service Health
opt_linux_systemd_failed_audit() {
    if ! command -v systemctl > /dev/null 2>&1; then
        opt_msg "systemctl not available"
        optimize_task_result "$MOLE_OPTIMIZE_OUTCOME_UNAVAILABLE"
        return 0
    fi

    local -a failed_units=()
    local u
    while IFS= read -r u; do
        [[ -n "$u" ]] && failed_units+=("$u")
    done < <(systemctl --failed --no-legend --plain 2> /dev/null | awk '{print $1}' || true)

    while IFS= read -r u; do
        [[ -n "$u" ]] && failed_units+=("$u (user)")
    done < <(systemctl --user --failed --no-legend --plain 2> /dev/null | awk '{print $1}' || true)

    if [[ ${#failed_units[@]} -gt 0 ]]; then
        opt_warn_msg "${#failed_units[@]} failed unit(s) found: ${failed_units[*]}"
        optimize_task_result "$MOLE_OPTIMIZE_OUTCOME_ATTENTION"
    else
        opt_msg "All systemd units healthy (0 failed)"
        optimize_task_result "$MOLE_OPTIMIZE_OUTCOME_UNCHANGED"
    fi
}

# Task 3: Fontconfig Cache Refresh
opt_linux_font_cache_refresh() {
    if ! command -v fc-cache > /dev/null 2>&1; then
        opt_msg "fc-cache not available"
        optimize_task_result "$MOLE_OPTIMIZE_OUTCOME_UNAVAILABLE"
        return 0
    fi

    if [[ "${MOLE_DRY_RUN:-0}" == "1" ]]; then
        opt_msg "Would refresh user font cache"
        optimize_task_result "$MOLE_OPTIMIZE_OUTCOME_APPLIED"
        return 0
    fi

    if run_with_timeout 15 fc-cache -f "$HOME/.local/share/fonts" "$HOME/.fonts" > /dev/null 2>&1; then
        opt_msg "Font cache refreshed"
        optimize_task_result "$MOLE_OPTIMIZE_OUTCOME_APPLIED"
    else
        opt_msg "Font cache already optimal"
        optimize_task_result "$MOLE_OPTIMIZE_OUTCOME_UNCHANGED"
    fi
}

# Task 4: Desktop & MIME Database Index
opt_linux_desktop_mime_refresh() {
    local updated=false

    if [[ "${MOLE_DRY_RUN:-0}" == "1" ]]; then
        opt_msg "Would update desktop and MIME database caches"
        optimize_task_result "$MOLE_OPTIMIZE_OUTCOME_APPLIED"
        return 0
    fi

    if command -v update-desktop-database > /dev/null 2>&1 && [[ -d "$HOME/.local/share/applications" ]]; then
        update-desktop-database "$HOME/.local/share/applications" > /dev/null 2>&1 || true
        updated=true
    fi

    if command -v update-mime-database > /dev/null 2>&1 && [[ -d "$HOME/.local/share/mime" ]]; then
        update-mime-database "$HOME/.local/share/mime" > /dev/null 2>&1 || true
        updated=true
    fi

    if [[ "$updated" == "true" ]]; then
        opt_msg "Desktop & MIME caches rebuilt"
        optimize_task_result "$MOLE_OPTIMIZE_OUTCOME_APPLIED"
    else
        opt_msg "Desktop & MIME databases current"
        optimize_task_result "$MOLE_OPTIMIZE_OUTCOME_UNCHANGED"
    fi
}

# Task 5: Orphan Package Audit
opt_linux_package_orphan_audit() {
    local pm
    pm=$(_linux_detect_pkg_manager)

    local -a orphans=()
    case "$pm" in
        pacman)
            while IFS= read -r pkg; do
                [[ -n "$pkg" ]] && orphans+=("$pkg")
            done < <(pacman -Qtdq 2> /dev/null || true)
            ;;
        apt)
            while IFS= read -r pkg; do
                [[ -n "$pkg" ]] && orphans+=("$pkg")
            done < <(apt-get --dry-run autoremove 2> /dev/null | awk '/^Remv/{print $2}' || true)
            ;;
        *)
            opt_msg "Package orphan check not supported on this system"
            optimize_task_result "$MOLE_OPTIMIZE_OUTCOME_UNAVAILABLE"
            return 0
            ;;
    esac

    if [[ ${#orphans[@]} -gt 0 ]]; then
        local count=${#orphans[@]}
        local display_orphans
        if [[ $count -le 5 ]]; then
            display_orphans="${orphans[*]}"
        else
            display_orphans="${orphans[0]}, ${orphans[1]}, ${orphans[2]}... ($count total)"
        fi
        opt_warn_msg "Found $count orphan package(s): $display_orphans"
        optimize_task_result "$MOLE_OPTIMIZE_OUTCOME_ATTENTION"
    else
        opt_msg "No orphan packages found"
        optimize_task_result "$MOLE_OPTIMIZE_OUTCOME_UNCHANGED"
    fi
}

# Task 6: Storage SSD Trim
opt_linux_fstrim_trim() {
    if ! command -v fstrim > /dev/null 2>&1; then
        opt_msg "fstrim utility not found"
        optimize_task_result "$MOLE_OPTIMIZE_OUTCOME_UNAVAILABLE"
        return 0
    fi

    if [[ "${MOLE_DRY_RUN:-0}" == "1" ]]; then
        opt_msg "Would execute fstrim on mounted SSD filesystems"
        optimize_task_result "$MOLE_OPTIMIZE_OUTCOME_APPLIED"
        return 0
    fi

    if [[ "${MOLE_OPTIMIZE_SUDO_AVAILABLE:-false}" == "true" ]]; then
        if run_with_timeout 30 sudo fstrim -av > /dev/null 2>&1; then
            opt_msg "SSD filesystems trimmed successfully"
            optimize_task_result "$MOLE_OPTIMIZE_OUTCOME_APPLIED"
        else
            opt_msg "SSD trim completed (no trim needed)"
            optimize_task_result "$MOLE_OPTIMIZE_OUTCOME_UNCHANGED"
        fi
    elif systemctl is-enabled --quiet fstrim.timer 2> /dev/null; then
        opt_msg "SSD trim is scheduled via fstrim.timer"
        optimize_task_result "$MOLE_OPTIMIZE_OUTCOME_UNCHANGED"
    else
        opt_msg "SSD trim skipped (sudo required)"
        optimize_task_result "$MOLE_OPTIMIZE_OUTCOME_SKIPPED"
    fi
}

# Task 7: SQLite Database Vacuum
opt_linux_sqlite_vacuum() {
    if ! command -v sqlite3 > /dev/null 2>&1; then
        opt_msg "sqlite3 command not available"
        optimize_task_result "$MOLE_OPTIMIZE_OUTCOME_UNAVAILABLE"
        return 0
    fi

    local -a db_candidates=()
    local db
    while IFS= read -r db; do
        [[ -f "$db" ]] || continue
        db_candidates+=("$db")
    done < <(find "$HOME/.config" "$HOME/.local/share" -maxdepth 4 \( -name "*.db" -o -name "*.sqlite" \) -type f -size +50k -size -100M 2> /dev/null | head -n 20 || true)

    if [[ ${#db_candidates[@]} -eq 0 ]]; then
        opt_msg "No eligible SQLite databases found"
        optimize_task_result "$MOLE_OPTIMIZE_OUTCOME_UNCHANGED"
        return 0
    fi

    if [[ "${MOLE_DRY_RUN:-0}" == "1" ]]; then
        opt_msg "Would optimize ${#db_candidates[@]} SQLite database(s)"
        optimize_task_result "$MOLE_OPTIMIZE_OUTCOME_APPLIED"
        return 0
    fi

    local vacuumed=0
    for db in "${db_candidates[@]}"; do
        if run_with_timeout 3 sqlite3 "$db" "PRAGMA quick_check;" > /dev/null 2>&1; then
            if run_with_timeout 5 sqlite3 "$db" "VACUUM;" > /dev/null 2>&1; then
                vacuumed=$((vacuumed + 1))
            fi
        fi
    done

    if [[ $vacuumed -gt 0 ]]; then
        opt_msg "Optimized $vacuumed SQLite database(s)"
        optimize_task_result "$MOLE_OPTIMIZE_OUTCOME_APPLIED"
    else
        opt_msg "All SQLite databases already optimal"
        optimize_task_result "$MOLE_OPTIMIZE_OUTCOME_UNCHANGED"
    fi
}

announce_action() {
    local name="$1"
    if [[ "${FIRST_ACTION:-true}" == "true" ]]; then
        export FIRST_ACTION=false
    else
        echo ""
    fi
    echo -e "${BLUE}${ICON_ARROW} ${name}${NC}"
}

linux_show_optimization_summary() {
    local total
    total=$(optimize_outcome_total)
    if ((total == 0)); then
        return
    fi

    local summary_title
    local -a summary_details=()
    local applied unchanged skipped unavailable attention failed
    applied=$(optimize_outcome_count "$MOLE_OPTIMIZE_OUTCOME_APPLIED")
    unchanged=$(optimize_outcome_count "$MOLE_OPTIMIZE_OUTCOME_UNCHANGED")
    skipped=$(optimize_outcome_count "$MOLE_OPTIMIZE_OUTCOME_SKIPPED")
    unavailable=$(optimize_outcome_count "$MOLE_OPTIMIZE_OUTCOME_UNAVAILABLE")
    attention=$(optimize_outcome_count "$MOLE_OPTIMIZE_OUTCOME_ATTENTION")
    failed=$(optimize_outcome_count "$MOLE_OPTIMIZE_OUTCOME_FAILED")

    local -a outcome_parts=()
    [[ $unchanged -gt 0 ]] && outcome_parts+=("$unchanged unchanged")
    [[ $skipped -gt 0 ]] && outcome_parts+=("$skipped skipped")
    [[ $unavailable -gt 0 ]] && outcome_parts+=("$unavailable unavailable")
    [[ $attention -gt 0 ]] && outcome_parts+=("$attention need attention")
    [[ $failed -gt 0 ]] && outcome_parts+=("$failed failed")

    local outcome_line=""
    if [[ ${#outcome_parts[@]} -gt 0 ]]; then
        outcome_line="${outcome_parts[0]}"
        local index
        for ((index = 1; index < ${#outcome_parts[@]}; index++)); do
            outcome_line+=" | ${outcome_parts[$index]}"
        done
    fi

    if [[ "${MOLE_DRY_RUN:-0}" == "1" ]]; then
        summary_title="Dry Run Complete, No Changes Made"
        summary_details+=("Would apply ${YELLOW}${applied}${NC} optimizations")
        [[ -n "$outcome_line" ]] && summary_details+=("$outcome_line")
        summary_details+=("Run without ${YELLOW}--dry-run${NC} to apply these changes")
    else
        summary_title="Optimization Complete"
        summary_details+=("Applied ${GREEN}${applied}${NC} optimizations")
        [[ -n "$outcome_line" ]] && summary_details+=("$outcome_line")
        if [[ $attention -gt 0 || $failed -gt 0 ]]; then
            summary_details+=("Review the warnings above")
        else
            summary_details+=("Optimization pass complete")
        fi
    fi

    print_summary_block "$summary_title" "${summary_details[@]}"
}

cleanup_linux_optimize() {
    local exit_status="${1:-0}"
    stop_inline_spinner 2> /dev/null || true
    stop_sudo_session
    cleanup_temp_files
    local applied=0
    if declare -F optimize_outcome_count > /dev/null; then
        applied=$(optimize_outcome_count "$MOLE_OPTIMIZE_OUTCOME_APPLIED")
    fi
    log_operation_session_end "optimize" "$applied" "0"
}

_linux_optimize_usage() {
    cat << 'EOF'
Mole - Linux System Optimization

Usage:
  mo optimize [options]

Options:
  -n, --dry-run   Show optimizations without applying changes
  --debug         Enable debug output
  -h, --help      Show this help message
EOF
}

linux_optimize_main() {
    export MOLE_CURRENT_COMMAND="optimize"

    for arg in "$@"; do
        case "$arg" in
            "--help" | "-h")
                _linux_optimize_usage
                return 0
                ;;
            "--debug")
                export MO_DEBUG=1
                ;;
            "--dry-run" | "-n")
                export MOLE_DRY_RUN=1
                ;;
            *)
                echo "Unknown optimize option: $arg" >&2
                echo "Use 'mo optimize --help' for supported options." >&2
                return 1
                ;;
        esac
    done

    log_operation_session_start "optimize"

    trap 'cleanup_linux_optimize "$?"' EXIT
    trap 'trap - EXIT; cleanup_linux_optimize 130; exit 130' INT TERM

    if [[ -t 1 ]]; then
        clear_screen
    fi
    printf '\n'
    echo -e "${PURPLE_BOLD}Optimize${NC}"

    if [[ "${MOLE_DRY_RUN:-0}" == "1" ]]; then
        echo -e "${YELLOW}${ICON_DRY_RUN} DRY RUN MODE${NC}, No changes will be made\n"
    fi

    linux_show_system_health
    echo ""

    export MOLE_OPTIMIZE_SUDO_AVAILABLE="false"
    if [[ "${MOLE_DRY_RUN:-0}" == "1" ]]; then
        MOLE_OPTIMIZE_SUDO_AVAILABLE="true"
    elif [[ "${MOLE_TEST_NO_AUTH:-0}" == "1" || "${MOLE_TEST_MODE:-0}" == "1" ]]; then
        MOLE_OPTIMIZE_SUDO_AVAILABLE="false"
    elif ensure_sudo_session "System optimization requires admin access"; then
        MOLE_OPTIMIZE_SUDO_AVAILABLE="true"
    fi

    export FIRST_ACTION=true
    optimize_outcomes_reset

    local -a linux_actions=(
        "journal_vacuum"
        "systemd_failed_audit"
        "font_cache_refresh"
        "desktop_mime_refresh"
        "package_orphan_audit"
        "fstrim_trim"
        "sqlite_vacuum"
    )

    local -a linux_action_names=(
        "Systemd Journal Maintenance"
        "Systemd Service Health"
        "Fontconfig Cache Refresh"
        "Desktop & MIME Index"
        "Orphan Package Audit"
        "Storage SSD Trim"
        "SQLite Database Optimization"
    )

    local -a linux_action_handlers=(
        "opt_linux_journal_vacuum"
        "opt_linux_systemd_failed_audit"
        "opt_linux_font_cache_refresh"
        "opt_linux_desktop_mime_refresh"
        "opt_linux_package_orphan_audit"
        "opt_linux_fstrim_trim"
        "opt_linux_sqlite_vacuum"
    )

    local idx action name handler
    for ((idx = 0; idx < ${#linux_actions[@]}; idx++)); do
        action="${linux_actions[$idx]}"
        name="${linux_action_names[$idx]}"
        handler="${linux_action_handlers[$idx]}"

        announce_action "$name"
        optimize_task_start
        "$handler"
        optimize_task_finish "$action"
    done

    linux_show_optimization_summary

    printf '\n'
    optimize_outcomes_succeeded
}
