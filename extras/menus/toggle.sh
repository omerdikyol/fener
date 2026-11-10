#!/bin/sh
# Executable menu: on/off switches showing their current state. Run with the chosen
# entry's value as $1 to flip it.
mic() { osascript -e 'input volume of (get volume settings)'; }
awake() { pgrep -f '^caffeinate -dimsu$' >/dev/null; }
dark() { [ "$(defaults read -g AppleInterfaceStyle 2>/dev/null)" = "Dark" ]; }
bar_hidden() { sketchybar --query bar 2>/dev/null | grep -q '"hidden": *"on"'; }

if [ $# -eq 0 ]; then
    [ "$(mic)" = "0" ] && m="Muted" || m="On"
    awake && a="On" || a="Off"
    dark && d="On" || d="Off"
    printf '{"name": "Microphone: %s", "value": "mic", "icon": "nf-fa-microphone"}\n' "$m"
    printf '{"name": "Keep Awake: %s", "value": "awake", "icon": "nf-md-coffee"}\n' "$a"
    printf '{"name": "Dark Mode: %s", "value": "dark", "icon": "nf-md-theme_light_dark"}\n' "$d"
    if command -v sketchybar >/dev/null; then
        bar_hidden && b="Hidden" || b="Shown"
        printf '{"name": "Menu Bar: %s", "value": "bar", "icon": "nf-md-dock_top"}\n' "$b"
    fi
    exit 0
fi

case "$1" in
mic)  # same as the dotfiles' mic-toggle when it exists, so the bar's mic icon updates too
    if [ -x "$HOME/.config/sketchybar/bin/mic-toggle" ]; then exec "$HOME/.config/sketchybar/bin/mic-toggle"; fi
    if [ "$(mic)" = "0" ]; then osascript -e 'set volume input volume 75'; else osascript -e 'set volume input volume 0'; fi ;;
awake)
    if awake; then pkill -f '^caffeinate -dimsu$'; else nohup caffeinate -dimsu >/dev/null 2>&1 & fi ;;
dark)
    osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to not dark mode' ;;
bar)
    sketchybar --bar hidden=toggle ;;
esac
