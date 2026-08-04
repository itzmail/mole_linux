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
