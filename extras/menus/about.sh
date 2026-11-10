#!/bin/sh
# Executable menu: a short system summary. Choosing a line does nothing, except the last.
[ "$1" = "info" ] && exec open -a "System Information"
[ $# -gt 0 ] && exit 0
gb=$(( $(sysctl -n hw.memsize) / 1073741824 ))
up=$(uptime | sed 's/.*up *//; s/, *[0-9]* user.*//')
printf '{"name": "macOS %s", "subtitle": "build %s", "icon": "apple.logo"}\n' "$(sw_vers -productVersion)" "$(sw_vers -buildVersion)"
printf '{"name": "%s", "subtitle": "%s GB memory", "icon": "cpu"}\n' "$(sysctl -n machdep.cpu.brand_string)" "$gb"
printf '{"name": "Up %s", "icon": "clock"}\n' "$up"
printf '{"name": "System Information", "value": "info", "icon": "info.circle"}\n'
