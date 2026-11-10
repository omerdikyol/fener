#!/bin/sh
# Executable menu: a focus timer on top of the dotfiles' bar-timer, which shows the
# countdown in SketchyBar. Set BAR_TIMER if yours lives elsewhere.
T="${BAR_TIMER:-$HOME/.config/sketchybar/bin/bar-timer}"
ST=/tmp/sketchybar-timer.state

if [ ! -x "$T" ]; then
    [ $# -gt 0 ] && exit 0
    printf '{"name": "bar-timer not found", "subtitle": "%s", "icon": "nf-md-alert"}\n' "$T"
    exit 0
fi
[ $# -gt 0 ] && exec "$T" "$1"

if read -r mode start dur paused 2>/dev/null < "$ST"; then
    now=$(date +%s); [ "$paused" != 0 ] && now=$paused
    if [ "$mode" = sw ]; then s=$(( now - start )); label="Stopwatch"; else s=$(( start + dur - now )); [ $s -lt 0 ] && s=0; label="Left"; fi
    [ "$paused" != 0 ] && state=" (paused)" || state=""
    printf '{"name": "%s %02d:%02d%s", "icon": "nf-md-timer_outline"}\n' "$label" $(( s / 60 )) $(( s % 60 )) "$state"
    if [ "$paused" = 0 ]; then printf '{"name": "Pause", "value": "pause", "icon": "nf-md-pause"}\n'
    else printf '{"name": "Resume", "value": "resume", "icon": "nf-md-play"}\n'; fi
    printf '{"name": "Stop", "value": "stop", "icon": "nf-md-stop"}\n'
    printf '{"refresh": 1}\n'
fi
printf '{"name": "Focus 25 min", "value": "25m", "icon": "nf-md-timer"}\n'
printf '{"name": "Focus 50 min", "value": "50m", "icon": "nf-md-timer"}\n'
printf '{"name": "Break 5 min", "value": "5m", "icon": "nf-md-coffee"}\n'
printf '{"name": "Break 15 min", "value": "15m", "icon": "nf-md-coffee"}\n'
printf '{"name": "Stopwatch", "value": "sw", "icon": "nf-md-timer_sand"}\n'
